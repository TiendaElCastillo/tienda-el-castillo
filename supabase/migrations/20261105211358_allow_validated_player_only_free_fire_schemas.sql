
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

  -- Some legacy Free Fire level SKUs declare only player_id in target_fields
  -- and return an empty target_schema. Their player ID was already validated
  -- by Central One using this exact one-field payload, so allow that case only.
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
    'idempotency_key',v_key
  );
end;
$function$;
