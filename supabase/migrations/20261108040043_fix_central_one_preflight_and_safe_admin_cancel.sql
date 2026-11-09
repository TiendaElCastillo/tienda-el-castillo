
-- Carry the already-locked order's payment values in the authorization claim.
-- This removes a redundant PostgREST read that was failing before provider submission.
create or replace function public.claim_central_one_order(p_order_id uuid, p_admin_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to ''
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
     or coalesce(jsonb_typeof(v_product.provider_target_schema),'') <> 'array'
     or coalesce(jsonb_array_length(v_product.provider_target_schema),-1) not in (0,1)
     or (
       jsonb_array_length(v_product.provider_target_schema) = 1
       and (
         v_product.provider_target_schema->0->>'key' <> 'player_id'
         or v_product.provider_target_schema->0->>'type' <> 'text'
       )
     ) then
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
    'order_price',v_order.price,
    'payment_method',v_order.payment_method,
    'idempotency_key',v_key
  );
end;
$function$;

-- An admin may only cancel an order proven to have stopped during the local
-- preflight, before the POST to Central One. Never cancel ambiguous submissions.
create or replace function public.admin_cancel_preflight_blocked_order(p_order_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_order public.orders%rowtype;
begin
  if auth.uid() is null or not exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'admin'
  ) then
    raise exception 'Solo un administrador puede anular este pedido.';
  end if;

  select * into v_order
  from public.orders
  where id = p_order_id
  for update;

  if not found then raise exception 'No encontramos ese pedido.'; end if;

  if v_order.status <> 'processing'
     or v_order.central_one_order_id is not null
     or v_order.central_one_status <> 'retryable'
     or v_order.central_one_error_code <> 'local_order_read_failed'
     or coalesce(v_order.central_one_response->>'preflight','') <> 'blocked' then
    raise exception 'Este pedido no cumple las condiciones de anulación segura. Comprueba su estado antes de actuar.';
  end if;

  update public.orders
  set status = 'cancelled',
      central_one_status = 'cancelled',
      central_one_error_message = 'Pedido anulado por el administrador antes de crear una orden en Central One. No se realizó una devolución automática.',
      admin_notes = concat_ws(E'\n', nullif(admin_notes,''), 'Anulado por administrador: fallo local de prevalidación; no se envió a Central One.')
  where id = p_order_id;

  return jsonb_build_object(
    'ok',true,
    'order_id',v_order.id,
    'order_code',v_order.order_code,
    'status','cancelled',
    'provider_order_created',false,
    'automatic_refund',false
  );
end;
$function$;

revoke all on function public.admin_cancel_preflight_blocked_order(uuid) from public;
grant execute on function public.admin_cancel_preflight_blocked_order(uuid) to authenticated;
