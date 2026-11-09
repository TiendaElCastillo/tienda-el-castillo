revoke select on table public.products from public, anon, authenticated;
revoke select (
  cost,
  provider_cost,
  provider_sku,
  provider_market,
  provider_currency,
  provider_price_updated_at,
  provider_synced_at
) on table public.products from public, anon, authenticated;

grant select (
  id,
  game,
  name,
  description,
  amount,
  price_transfer,
  price_mobile,
  price_usdt,
  active,
  provider_product_id,
  provider_region,
  provider_validation_supported,
  provider_image_url,
  provider_target_fields,
  provider_target_schema,
  provider_requires_target,
  provider_status,
  provider_in_stock
) on table public.products to anon, authenticated;

grant select (created_at) on table public.products to authenticated;
