
alter table public.orders
  add column if not exists central_one_idempotency_key text,
  add column if not exists central_one_order_id uuid,
  add column if not exists central_one_reference_code text,
  add column if not exists central_one_status text not null default 'not_submitted',
  add column if not exists central_one_request_id text,
  add column if not exists central_one_error_code text,
  add column if not exists central_one_error_message text,
  add column if not exists central_one_submitted_at timestamptz,
  add column if not exists central_one_checked_at timestamptz,
  add column if not exists central_one_response jsonb;

alter table public.orders drop constraint if exists orders_status_check;
alter table public.orders
  add constraint orders_status_check
  check (status = any (array[
    'pending','payment_review','processing','completed','failed','rejected','cancelled'
  ]::text[]));

alter table public.orders drop constraint if exists orders_central_one_status_check;
alter table public.orders
  add constraint orders_central_one_status_check
  check (central_one_status = any (array[
    'not_submitted','submitting','unknown','retryable','rejected',
    'created','confirmed','processing','partially_completed','completed','failed','cancelled'
  ]::text[]));

create unique index if not exists orders_central_one_order_id_key
  on public.orders (central_one_order_id)
  where central_one_order_id is not null;

create unique index if not exists orders_central_one_idempotency_key_key
  on public.orders (central_one_idempotency_key)
  where central_one_idempotency_key is not null;

create or replace function public.claim_central_one_order(
  p_order_id uuid,
  p_admin_id uuid
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_order public.orders%rowtype;
  v_product public.products%rowtype;
  v_key text;
begin
  if p_admin_id is null or not exists (
    select 1 from public.profiles
    where id = p_admin_id and role = 'admin'
  ) then
    raise exception 'No tienes permiso para autorizar recargas.';
  end if;

  select * into v_order
  from public.orders
  where id = p_order_id
  for update;

  if not found then raise exception 'No encontramos ese pedido.'; end if;

  if v_order.central_one_order_id is not null then
    return jsonb_build_object(
      'claim_status','already_submitted',
      'provider_order_id',v_order.central_one_order_id,
      'reference_code',v_order.central_one_reference_code,
      'provider_status',v_order.central_one_status
    );
  end if;

  if v_order.status <> 'processing' then
    raise exception 'Primero debes confirmar el pago del cliente.';
  end if;

  if v_order.payment_source = 'direct' then
    if v_order.proof_path is null or v_order.payment_confirmed_at is null
       or v_order.payment_confirmed_by is distinct from p_admin_id then
      raise exception 'El pago externo no está confirmado con comprobante.';
    end if;
  elsif v_order.payment_source = 'wallet' then
    if v_order.paid_at is null then
      raise exception 'El pago desde la billetera no está confirmado.';
    end if;
  else
    raise exception 'Origen de pago no válido.';
  end if;

  if v_order.player_id_validated is distinct from true
     or v_order.player_id_validated_at is null
     or v_order.provider_product_id is null
     or v_order.provider_region is null then
    raise exception 'Este pedido no tiene una validación de jugador válida. No se enviará a Central One.';
  end if;

  select * into v_product
  from public.products
  where id = v_order.product_id;

  if not found or v_product.active is distinct from true
     or v_product.provider_product_id is distinct from v_order.provider_product_id
     or upper(coalesce(v_product.provider_region,'')) <> upper(coalesce(v_order.provider_region,''))
     or coalesce(v_product.provider_validation_supported,false) is distinct from true
     or lower(coalesce(v_product.provider_status,'')) <> 'active'
     or v_product.provider_in_stock is distinct from true then
    raise exception 'El paquete ya no está habilitado o disponible en Central One.';
  end if;

  if coalesce(v_product.provider_requires_target,false) is distinct from true
     or v_product.provider_target_fields is distinct from '["player_id"]'::jsonb
     or jsonb_typeof(v_product.provider_target_schema) <> 'array'
     or jsonb_array_length(v_product.provider_target_schema) <> 1
     or v_product.provider_target_schema->0->>'key' <> 'player_id'
     or v_product.provider_target_schema->0->>'type' <> 'text' then
    raise exception 'El formato de datos de jugador de este paquete cambió. La recarga quedó bloqueada para evitar un envío incorrecto.';
  end if;

  if v_order.central_one_status = 'submitting'
     and v_order.central_one_submitted_at > now() - interval '90 seconds' then
    return jsonb_build_object('claim_status','in_progress');
  end if;

  v_key := coalesce(
    v_order.central_one_idempotency_key,
    'EC_ORDER_' || replace(v_order.id::text, '-', '')
  );

  update public.orders
  set central_one_idempotency_key = v_key,
      central_one_status = 'submitting',
      central_one_submitted_at = now(),
      central_one_checked_at = now(),
      central_one_error_code = null,
      central_one_error_message = null
  where id = p_order_id;

  return jsonb_build_object(
    'claim_status','claimed',
    'order_id',v_order.id,
    'order_code',v_order.order_code,
    'provider_product_id',v_product.provider_product_id,
    'provider_region',v_product.provider_region,
    'provider_target_fields',v_product.provider_target_fields,
    'provider_target_schema',v_product.provider_target_schema,
    'player_id',v_order.player_id,
    'idempotency_key',v_key
  );
end;
$function$;

create or replace function public.finish_central_one_order(
  p_order_id uuid,
  p_provider_status text,
  p_provider_order_id uuid default null,
  p_reference_code text default null,
  p_request_id text default null,
  p_response jsonb default null,
  p_error_code text default null,
  p_error_message text default null
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_order public.orders%rowtype;
  v_local_status text;
begin
  if not exists (
    select 1 from pg_catalog.pg_roles
    where rolname = current_user and rolname in ('service_role','postgres')
  ) then
    raise exception 'Operación interna no autorizada.';
  end if;

  if p_provider_status not in (
    'unknown','retryable','rejected','created','confirmed',
    'processing','partially_completed','completed','failed','cancelled'
  ) then
    raise exception 'Estado de Central One no válido.';
  end if;

  select * into v_order
  from public.orders
  where id = p_order_id
  for update;

  if not found then raise exception 'Pedido local no encontrado.'; end if;

  if v_order.central_one_order_id is not null
     and p_provider_order_id is not null
     and v_order.central_one_order_id <> p_provider_order_id then
    raise exception 'El pedido local ya está asociado a otra orden del proveedor.';
  end if;

  v_local_status := v_order.status;
  if p_provider_status = 'completed' then
    v_local_status := 'completed';
  elsif p_provider_status = 'failed' then
    v_local_status := 'failed';
  elsif p_provider_status = 'cancelled' then
    v_local_status := 'cancelled';
  end if;

  update public.orders
  set central_one_order_id = coalesce(p_provider_order_id,central_one_order_id),
      central_one_reference_code = coalesce(p_reference_code,central_one_reference_code),
      central_one_status = p_provider_status,
      central_one_request_id = coalesce(p_request_id,central_one_request_id),
      central_one_response = coalesce(p_response,central_one_response),
      central_one_error_code = p_error_code,
      central_one_error_message = p_error_message,
      central_one_checked_at = now(),
      status = v_local_status
  where id = p_order_id;

  return jsonb_build_object(
    'order_id',p_order_id,
    'status',v_local_status,
    'central_one_status',p_provider_status,
    'central_one_order_id',coalesce(p_provider_order_id,v_order.central_one_order_id),
    'central_one_reference_code',coalesce(p_reference_code,v_order.central_one_reference_code)
  );
end;
$function$;

revoke all on function public.claim_central_one_order(uuid,uuid) from public, anon, authenticated;
grant execute on function public.claim_central_one_order(uuid,uuid) to service_role;

revoke all on function public.finish_central_one_order(uuid,text,uuid,text,text,jsonb,text,text) from public, anon, authenticated;
grant execute on function public.finish_central_one_order(uuid,text,uuid,text,text,jsonb,text,text) to service_role;
