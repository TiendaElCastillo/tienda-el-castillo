
CREATE OR REPLACE FUNCTION private.mobile_legends_target_schema_supported(
  p_fields jsonb,
  p_schema jsonb
)
RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
SET search_path TO ''
AS $function$
DECLARE
  v_field text;
  v_descriptor jsonb;
  v_semantic text;
  v_player_count integer := 0;
  v_zone_count integer := 0;
BEGIN
  IF jsonb_typeof(p_fields) <> 'array'
     OR jsonb_array_length(p_fields) <> 2
     OR jsonb_typeof(p_schema) <> 'array'
     OR jsonb_array_length(p_schema) <> 2 THEN
    RETURN false;
  END IF;

  FOR v_field IN
    SELECT jsonb_array_elements_text(p_fields)
  LOOP
    IF v_field !~ '^[A-Za-z][A-Za-z0-9_]{0,39}$' THEN
      RETURN false;
    END IF;

    SELECT s.value INTO v_descriptor
    FROM jsonb_array_elements(p_schema) AS s(value)
    WHERE s.value->>'key' = v_field
    LIMIT 1;

    IF v_descriptor IS NULL
       OR coalesce(lower(v_descriptor->>'type'), 'text') <> 'text' THEN
      RETURN false;
    END IF;

    v_semantic := lower(v_field || ' ' || coalesce(v_descriptor->>'label',''));

    IF v_semantic ~ '(zone|server)' THEN
      v_zone_count := v_zone_count + 1;
    ELSIF v_semantic ~ '(player|user|account|game.?id|uid)' THEN
      v_player_count := v_player_count + 1;
    ELSE
      RETURN false;
    END IF;
  END LOOP;

  RETURN v_player_count = 1 AND v_zone_count = 1;
END;
$function$;

CREATE OR REPLACE FUNCTION private.sync_mobile_legends_provider_products(
  p_token text,
  p_items jsonb,
  p_coverage_products jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_settings record;
  v_item jsonb;
  v_id text;
  v_sku text;
  v_name text;
  v_region text;
  v_market text;
  v_currency text;
  v_cost numeric;
  v_rate numeric;
  v_markup numeric;
  v_rounding numeric;
  v_mobile_units numeric;
  v_mobile_cost numeric;
  v_price_cup numeric;
  v_price_mobile numeric;
  v_price_usdt numeric;
  v_amount integer;
  v_status text;
  v_stock boolean;
  v_requires_target boolean;
  v_target_fields jsonb;
  v_target_schema jsonb;
  v_supported boolean;
  v_schema_supported boolean;
  v_image_url text;
  v_price_updated_at timestamptz;
  v_active boolean;
  v_synced integer := 0;
  v_enabled integer := 0;
  v_coverage_count integer := 0;
  v_schema_blocked integer := 0;
BEGIN
  IF NOT private.is_central_one_sync_token_valid(p_token) THEN
    RAISE EXCEPTION 'unauthorized' USING errcode = '42501';
  END IF;

  IF jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) > 500 THEN
    RAISE EXCEPTION 'invalid_mobile_legends_items' USING errcode = '22023';
  END IF;
  IF jsonb_typeof(p_coverage_products) <> 'array' THEN
    RAISE EXCEPTION 'invalid_coverage_products' USING errcode = '22023';
  END IF;

  SELECT usdt_cup_rate, markup_percent, rounding_cup,
         mobile_credit_units, mobile_cost_cup
    INTO v_settings
  FROM public.pricing_settings
  WHERE id = 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'pricing_settings_missing';
  END IF;

  v_rate := v_settings.usdt_cup_rate;
  v_markup := v_settings.markup_percent;
  v_rounding := v_settings.rounding_cup;
  v_mobile_units := v_settings.mobile_credit_units;
  v_mobile_cost := v_settings.mobile_cost_cup;

  IF v_rate <= 0 OR v_rounding <= 0 OR v_mobile_units <= 0 OR v_mobile_cost <= 0 THEN
    RAISE EXCEPTION 'invalid_pricing_settings';
  END IF;

  UPDATE public.products
  SET active = false,
      provider_validation_supported = false,
      provider_synced_at = now()
  WHERE provider_product_id IS NOT NULL
    AND lower(game) IN ('mobile legends', 'mobile legends: bang bang');

  FOR v_item IN SELECT value FROM jsonb_array_elements(p_items)
  LOOP
    v_id := nullif(v_item->>'product_id','');
    v_sku := nullif(v_item->>'sku','');
    v_name := coalesce(nullif(v_item->>'name',''), v_sku, 'Mobile Legends: Bang Bang');
    v_region := upper(coalesce(nullif(v_item->>'region',''),''));
    v_market := nullif(v_item->>'market','');
    v_currency := upper(coalesce(nullif(v_item->>'currency',''),'USD'));
    v_status := lower(coalesce(nullif(v_item->>'status',''),'inactive'));
    v_stock := coalesce((v_item->>'in_stock')::boolean, false);
    v_requires_target := coalesce((v_item->>'requires_target')::boolean, false);
    v_target_fields := coalesce(v_item->'target_fields','[]'::jsonb);
    v_target_schema := coalesce(v_item->'target_schema','[]'::jsonb);
    v_image_url := coalesce(
      nullif(v_item->>'image_url',''),
      nullif(v_item->>'image',''),
      nullif(v_item->>'icon_url',''),
      nullif(v_item->>'thumbnail_url','')
    );
    v_cost := nullif(v_item->>'reseller_price','')::numeric;
    v_price_updated_at := nullif(v_item->>'price_updated_at','')::timestamptz;
    v_amount := coalesce(
      (regexp_match(v_name, '([0-9]+)[[:space:]]*(Diamonds?|Diamantes?)', 'i'))[1]::integer,
      (regexp_match(coalesce(v_sku,''), '([0-9]+)[[:space:]_-]*(?:DIAMONDS?|DIAMANTES?)', 'i'))[1]::integer,
      0
    );

    IF v_id IS NULL OR v_cost IS NULL OR v_cost <= 0 THEN
      CONTINUE;
    END IF;
    IF v_region <> 'GLOBAL' THEN
      CONTINUE;
    END IF;

    v_coverage_count := v_coverage_count + 1;
    SELECT EXISTS (
      SELECT 1
      FROM jsonb_array_elements(p_coverage_products) cp
      WHERE cp->>'product_id' = v_id
        AND lower(coalesce(cp->>'game','')) ~ '(mobile[[:space:]_-]*legends|mlbb)'
        AND upper(coalesce(cp->>'region','')) = v_region
    ) INTO v_supported;

    v_schema_supported := private.mobile_legends_target_schema_supported(
      v_target_fields, v_target_schema
    );

    IF NOT v_schema_supported THEN
      v_schema_blocked := v_schema_blocked + 1;
    END IF;

    v_price_cup := ceil((v_cost * v_rate * (1 + v_markup / 100)) / v_rounding) * v_rounding;
    v_price_mobile := ceil(v_price_cup * v_mobile_units / v_mobile_cost);
    v_price_usdt := ceil((v_price_cup / v_rate) * 100) / 100;
    v_active := v_status = 'active'
      AND v_stock
      AND v_supported
      AND v_requires_target
      AND v_schema_supported;

    IF v_active THEN
      v_enabled := v_enabled + 1;
    END IF;

    INSERT INTO public.products (
      game, name, description, amount,
      price_transfer, price_mobile, price_usdt, active,
      provider_product_id, provider_sku, provider_region, provider_market,
      provider_currency, provider_cost, provider_status, provider_in_stock,
      provider_requires_target, provider_target_fields, provider_target_schema,
      provider_validation_supported, provider_image_url,
      provider_price_updated_at, provider_synced_at
    )
    VALUES (
      'Mobile Legends: Bang Bang',
      v_name,
      'Región GLOBAL. Para acreditar diamantes se verifican el ID del jugador y el Zone ID del servidor con Central One.',
      v_amount,
      v_price_cup, v_price_mobile, v_price_usdt, v_active,
      v_id, v_sku, v_region, v_market,
      v_currency, v_cost, v_status, v_stock,
      v_requires_target, v_target_fields, v_target_schema,
      v_supported, v_image_url,
      v_price_updated_at, now()
    )
    ON CONFLICT (provider_product_id) WHERE provider_product_id IS NOT NULL
    DO UPDATE SET
      game = excluded.game,
      name = excluded.name,
      description = excluded.description,
      amount = excluded.amount,
      price_transfer = excluded.price_transfer,
      price_mobile = excluded.price_mobile,
      price_usdt = excluded.price_usdt,
      active = excluded.active,
      provider_sku = excluded.provider_sku,
      provider_region = excluded.provider_region,
      provider_market = excluded.provider_market,
      provider_currency = excluded.provider_currency,
      provider_cost = excluded.provider_cost,
      provider_status = excluded.provider_status,
      provider_in_stock = excluded.provider_in_stock,
      provider_requires_target = excluded.provider_requires_target,
      provider_target_fields = excluded.provider_target_fields,
      provider_target_schema = excluded.provider_target_schema,
      provider_validation_supported = excluded.provider_validation_supported,
      provider_image_url = excluded.provider_image_url,
      provider_price_updated_at = excluded.provider_price_updated_at,
      provider_synced_at = now();

    v_synced := v_synced + 1;
  END LOOP;

  RETURN jsonb_build_object(
    'ok', true,
    'synced', v_synced,
    'coverage_matches', v_coverage_count,
    'validation_schema_blocked', v_schema_blocked,
    'published_active', v_enabled,
    'message', 'Solo se publican recargas GLOBAL con cobertura de validación y campos de jugador/servidor compatibles.'
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.sync_mobile_legends_provider_products(
  p_token text,
  p_items jsonb,
  p_coverage_products jsonb
)
RETURNS jsonb
LANGUAGE sql
SET search_path TO ''
AS $function$
  SELECT private.sync_mobile_legends_provider_products(p_token, p_items, p_coverage_products);
$function$;

REVOKE ALL ON FUNCTION public.sync_mobile_legends_provider_products(text, jsonb, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.sync_mobile_legends_provider_products(text, jsonb, jsonb) TO anon;

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
$function$;

UPDATE public.pricing_settings
SET mobile_cost_cup = 1200
WHERE id = 1
  AND mobile_credit_units = 360
  AND mobile_cost_cup = 1800;
