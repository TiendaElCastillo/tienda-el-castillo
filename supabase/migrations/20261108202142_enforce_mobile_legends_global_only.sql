-- Keep only the GLOBAL region of Mobile Legends active and enforce the same rule at order authorization.
UPDATE public.products
SET active = false,
    provider_validation_supported = false
WHERE lower(coalesce(game,'')) IN ('mobile legends','mobile legends: bang bang')
  AND upper(coalesce(provider_region,'')) <> 'GLOBAL';

CREATE OR REPLACE FUNCTION public.claim_central_one_order(p_order_id uuid, p_admin_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_order public.orders%rowtype;
  v_product public.products%rowtype;
  v_key text;
  v_target_schema_supported boolean := false;
BEGIN
  IF p_admin_id IS NULL OR NOT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = p_admin_id AND role = 'admin'
  ) THEN
    RAISE EXCEPTION 'No tienes permiso para autorizar recargas.';
  END IF;

  SELECT * INTO v_order
  FROM public.orders
  WHERE id = p_order_id
  FOR UPDATE;

  IF NOT FOUND THEN RAISE EXCEPTION 'No encontramos ese pedido.'; END IF;

  IF v_order.central_one_order_id IS NOT NULL THEN
    RETURN jsonb_build_object(
      'claim_status','already_submitted',
      'provider_order_id',v_order.central_one_order_id,
      'reference_code',v_order.central_one_reference_code,
      'provider_status',v_order.central_one_status
    );
  END IF;

  IF v_order.status <> 'processing' THEN
    RAISE EXCEPTION 'Primero debes confirmar el pago del cliente.';
  END IF;

  IF v_order.payment_source = 'direct' THEN
    IF v_order.proof_path IS NULL OR v_order.payment_confirmed_at IS NULL
       OR v_order.payment_confirmed_by IS DISTINCT FROM p_admin_id THEN
      RAISE EXCEPTION 'El pago externo no está confirmado con comprobante.';
    END IF;
  ELSIF v_order.payment_source = 'wallet' THEN
    IF v_order.paid_at IS NULL THEN
      RAISE EXCEPTION 'El pago desde la billetera no está confirmado.';
    END IF;
  ELSE
    RAISE EXCEPTION 'Origen de pago no válido.';
  END IF;

  IF v_order.player_id_validated IS DISTINCT FROM true
     OR v_order.player_id_validated_at IS NULL
     OR v_order.provider_product_id IS NULL
     OR v_order.provider_region IS NULL THEN
    RAISE EXCEPTION 'Este pedido no tiene una validación de jugador válida. No se enviará a Central One.';
  END IF;

  SELECT * INTO v_product
  FROM public.products
  WHERE id = v_order.product_id;

  IF NOT FOUND OR v_product.active IS DISTINCT FROM true
     OR v_product.provider_product_id IS DISTINCT FROM v_order.provider_product_id
     OR upper(coalesce(v_product.provider_region,'')) <> upper(coalesce(v_order.provider_region,''))
     OR coalesce(v_product.provider_validation_supported,false) IS DISTINCT FROM true
     OR lower(coalesce(v_product.provider_status,'')) <> 'active'
     OR v_product.provider_in_stock IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'El paquete ya no está habilitado o disponible en Central One.';
  END IF;

  IF lower(coalesce(v_product.game,'')) = 'mobile legends: bang bang'
     AND upper(coalesce(v_product.provider_region,'')) <> 'GLOBAL' THEN
    RAISE EXCEPTION 'Mobile Legends solo se vende en la región GLOBAL. Este pedido no se enviará.';
  END IF;

  IF lower(coalesce(v_product.game,'')) = 'mobile legends: bang bang' THEN
    v_target_schema_supported := private.mobile_legends_target_schema_supported(
      v_product.provider_target_fields, v_product.provider_target_schema
    );
  ELSE
    v_target_schema_supported := coalesce(
      v_product.provider_target_fields = '["player_id"]'::jsonb
      AND jsonb_typeof(v_product.provider_target_schema) = 'array'
      AND jsonb_array_length(v_product.provider_target_schema) IN (0,1)
      AND (
        jsonb_array_length(v_product.provider_target_schema) = 0
        OR (
          v_product.provider_target_schema->0->>'key' = 'player_id'
          AND v_product.provider_target_schema->0->>'type' = 'text'
        )
      ),
      false
    );
  END IF;

  IF coalesce(v_product.provider_requires_target,false) IS DISTINCT FROM true
     OR NOT v_target_schema_supported THEN
    RAISE EXCEPTION 'El formato de datos de jugador de este paquete cambió. La recarga quedó bloqueada para evitar un envío incorrecto.';
  END IF;

  IF v_order.central_one_status = 'submitting'
     AND v_order.central_one_submitted_at > now() - interval '90 seconds' THEN
    RETURN jsonb_build_object('claim_status','in_progress');
  END IF;

  v_key := coalesce(
    v_order.central_one_idempotency_key,
    'EC_ORDER_' || replace(v_order.id::text, '-', '')
  );

  UPDATE public.orders
  SET central_one_idempotency_key = v_key,
      central_one_status = 'submitting',
      central_one_submitted_at = now(),
      central_one_checked_at = now(),
      central_one_error_code = null,
      central_one_error_message = null
  WHERE id = p_order_id;

  RETURN jsonb_build_object(
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
END;
$function$

