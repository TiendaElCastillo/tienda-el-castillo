ALTER TABLE public.products
  ADD COLUMN IF NOT EXISTS storefront_visible boolean NOT NULL DEFAULT false;

-- Publish only the 10 current Free Fire offers.
UPDATE public.products
SET storefront_visible = true
WHERE game = 'Free Fire'
  AND active = true
  AND provider_region = 'LATAM'
  AND provider_status = 'active'
  AND provider_in_stock IS TRUE
  AND provider_validation_supported IS TRUE
  AND provider_requires_target IS TRUE
  AND provider_product_id IS NOT NULL
  AND price_transfer > 0
  AND price_mobile > 0
  AND price_usdt > 0;

-- Publish only the 7 MLBB diamond denominations and 4 passes currently
-- approved in the storefront's curated catalog.
UPDATE public.products
SET storefront_visible = true
WHERE game = 'Mobile Legends: Bang Bang'
  AND active = true
  AND provider_region = 'GLOBAL'
  AND provider_status = 'active'
  AND provider_in_stock IS TRUE
  AND provider_validation_supported IS TRUE
  AND provider_requires_target IS TRUE
  AND provider_product_id IS NOT NULL
  AND provider_target_fields @> '["game_user_id","game_zone_id"]'::jsonb
  AND price_transfer > 0
  AND price_mobile > 0
  AND price_usdt > 0
  AND (
    (name ~* '^Mobile Legends · [0-9]+ Diamantes$' AND amount IN (55,172,275,565,706,2195,3688))
    OR translate(lower(name),'éáíóúü','eaiouu') IN (
      'mobile legends · paquete elite semanal',
      'mobile legends · pase semanal',
      'mobile legends · paquete elite mensual',
      'mobile legends · twilight pass'
    )
  );

GRANT SELECT (storefront_visible) ON public.products TO anon, authenticated;
GRANT UPDATE (storefront_visible) ON public.products TO authenticated;

ALTER TABLE private.product_costs ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE private.product_costs FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE private.product_costs TO service_role;

CREATE OR REPLACE FUNCTION private.validate_order_request()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
declare
  selected_product public.products%rowtype;
  final_price numeric;
begin
  if auth.uid() is null or new.user_id is distinct from auth.uid() then
    raise exception 'No autorizado para crear este pedido.';
  end if;
  if new.product_id is null then raise exception 'Selecciona un producto válido.'; end if;
  if new.player_id is null or length(btrim(new.player_id))<3 or length(btrim(new.player_id))>64 then
    raise exception 'El ID del jugador debe tener entre 3 y 64 caracteres.';
  end if;

  select * into selected_product from public.products where id=new.product_id and active=true;
  if not found then raise exception 'El producto ya no está disponible.'; end if;
  if selected_product.storefront_visible is distinct from true then
    raise exception 'Este paquete todavía no está publicado en Tienda El Castillo.';
  end if;

  if coalesce(new.payment_source,'direct')='wallet' then
    if new.payment_method<>'Saldo de Tienda El Castillo' then raise exception 'Método de billetera no válido.'; end if;
    final_price:=selected_product.price_usdt;
  elsif coalesce(new.payment_source,'direct')='direct' then
    if not exists(select 1 from public.payment_methods pm where pm.name=new.payment_method and pm.active=true) then
      raise exception 'El método de pago no está activo.';
    end if;
    case new.payment_method
      when 'Transferencia CUP' then final_price:=selected_product.price_transfer;
      when 'Saldo móvil' then final_price:=selected_product.price_mobile;
      when 'USDT' then final_price:=selected_product.price_usdt;
      else raise exception 'Método de pago no válido.';
    end case;
  else
    raise exception 'Origen de pago no válido.';
  end if;

  if final_price is null or final_price<=0 then raise exception 'Este producto no tiene precio para ese método de pago.'; end if;
  new.game:=selected_product.game;
  new.package_name:=selected_product.name;
  new.price:=final_price;
  new.status:='pending';
  new.order_code:='EC-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,10));
  new.player_id:=btrim(new.player_id);
  new.player_name:=nullif(btrim(coalesce(new.player_name,'')),'');
  new.payment_reference:=null;
  new.payment_sender_phone:=null;
  new.payment_reported_amount:=null;
  new.admin_notes:=null;
  new.created_at:=now();
  new.payment_source:=coalesce(new.payment_source,'direct');
  new.proof_path:=null;
  new.paid_at:=null;
  return new;
end;
$function$;
