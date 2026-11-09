CREATE OR REPLACE FUNCTION private.sync_free_fire_provider_products(p_token text, p_items jsonb, p_coverage_products jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
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
  v_image_url text;
  v_price_updated_at timestamptz;
  v_active boolean;
  v_synced integer := 0;
  v_enabled integer := 0;
  v_latam integer := 0;
  v_indonesia integer := 0;
begin
  if not private.is_central_one_sync_token_valid(p_token) then
    raise exception 'unauthorized' using errcode = '42501';
  end if;

  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) > 500 then
    raise exception 'invalid_free_fire_items' using errcode = '22023';
  end if;
  if jsonb_typeof(p_coverage_products) <> 'array' then
    raise exception 'invalid_coverage_products' using errcode = '22023';
  end if;

  select usdt_cup_rate, markup_percent, rounding_cup,
         mobile_credit_units, mobile_cost_cup
    into v_settings
  from public.pricing_settings
  where id = 1;

  if not found then
    raise exception 'pricing_settings_missing';
  end if;

  v_rate := v_settings.usdt_cup_rate;
  v_markup := v_settings.markup_percent;
  v_rounding := v_settings.rounding_cup;
  v_mobile_units := v_settings.mobile_credit_units;
  v_mobile_cost := v_settings.mobile_cost_cup;

  if v_rate <= 0 or v_rounding <= 0 or v_mobile_units <= 0 or v_mobile_cost <= 0 then
    raise exception 'invalid_pricing_settings';
  end if;

  -- Imported provider products are disabled first. Each current product is re-enabled
  -- only when Central One explicitly lists it as validation-supported and in stock.
  update public.products
  set active = false,
      provider_validation_supported = false,
      provider_synced_at = now()
  where provider_product_id is not null
    and provider_region in ('LATAM','ID');

  for v_item in select value from jsonb_array_elements(p_items)
  loop
    v_id := nullif(v_item->>'product_id','');
    v_sku := nullif(v_item->>'sku','');
    v_name := coalesce(nullif(v_item->>'name',''), v_sku, 'Free Fire');
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
    v_amount := coalesce((regexp_match(v_name, '([0-9]+)[[:space:]]+Diamantes'))[1]::integer, 0);

    if v_id is null or v_cost is null or v_cost <= 0 then
      continue;
    end if;

    if v_region not in ('LATAM','ID') then
      continue;
    end if;

    select exists (
      select 1
      from jsonb_array_elements(p_coverage_products) cp
      where cp->>'product_id' = v_id
        and lower(coalesce(cp->>'game','free fire')) = 'free fire'
        and upper(coalesce(cp->>'region','')) = v_region
    ) into v_supported;

    v_price_cup := ceil((v_cost * v_rate * (1 + v_markup / 100)) / v_rounding) * v_rounding;
    v_price_mobile := ceil(v_price_cup * v_mobile_units / v_mobile_cost);
    v_price_usdt := round(v_price_cup / v_rate, 2);
    v_active := (v_status = 'active') and v_stock and v_supported
      and coalesce(v_sku,'') not ilike 'NIVEL-%'
      and v_name not ilike '%subida de nivel%'
      and v_name not ilike '%mejora de nivel%';

    if v_region = 'LATAM' then v_latam := v_latam + 1; end if;
    if v_region = 'ID' then v_indonesia := v_indonesia + 1; end if;
    if v_active then v_enabled := v_enabled + 1; end if;

    -- Reuse the existing manually created 110-diamond row to prevent duplicate listings
    -- while preserving its UUID and order history.
    if not exists (select 1 from public.products where provider_product_id = v_id)
       and v_region = 'LATAM'
       and v_sku = 'FF-110-DIAMONDS' then
      update public.products
      set provider_product_id = v_id
      where id = (
        select p.id
        from public.products p
        where p.provider_product_id is null
          and p.game = 'Free Fire'
          and p.amount = 110
          and p.name ilike '%110%'
        order by p.created_at desc
        limit 1
      );
    end if;

    insert into public.products (
      game, name, description, amount,
      price_transfer, price_mobile, price_usdt, active,
      provider_product_id, provider_sku, provider_region, provider_market,
      provider_currency, provider_cost, provider_status, provider_in_stock,
      provider_requires_target, provider_target_fields, provider_target_schema,
      provider_validation_supported, provider_image_url,
      provider_price_updated_at, provider_synced_at
    )
    values (
      'Free Fire', v_name,
      'Región ' || v_region || '. El ID del jugador se verificará con el proveedor antes de crear el pedido.',
      v_amount,
      v_price_cup, v_price_mobile, v_price_usdt, v_active,
      v_id, v_sku, v_region, v_market,
      v_currency, v_cost, v_status, v_stock,
      v_requires_target, v_target_fields, v_target_schema,
      v_supported, v_image_url, v_price_updated_at, now()
    )
    on conflict (provider_product_id) where provider_product_id is not null
    do update set
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
  end loop;

  return jsonb_build_object(
    'ok', true,
    'synced', v_synced,
    'latam_catalog_items', v_latam,
    'indonesia_catalog_items', v_indonesia,
    'validation_supported_and_active', v_enabled,
    'message', 'Solo quedan activos los productos presentes en la cobertura oficial de validación del proveedor.'
  );
end;
$function$
