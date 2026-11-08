-- Keep published USDT prices at or above the configured margin after cent rounding.
do $migration$
declare
  v_definition text;
  v_old text := 'v_price_usdt := round(v_price_cup / v_rate, 2);';
  v_new text := 'v_price_usdt := ceil((v_price_cup / v_rate) * 100) / 100;';
begin
  select pg_get_functiondef('private.sync_free_fire_provider_products(text,jsonb,jsonb)'::regprocedure)
    into v_definition;
  if position(v_old in v_definition) = 0 then
    raise exception 'Expected USDT rounding statement was not found; refusing to modify the sync function.';
  end if;
  execute replace(v_definition, v_old, v_new);
end;
$migration$;

-- Use one USDT/CUP rate for product pricing and customer wallet deposits.
create or replace function private.sync_wallet_rate_from_pricing_settings()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if TG_OP = 'INSERT' or NEW.usdt_cup_rate is distinct from OLD.usdt_cup_rate then
    update public.wallet_settings
       set cup_per_usd = NEW.usdt_cup_rate,
           updated_by = NEW.updated_by,
           updated_at = now()
     where id = 1;
  end if;
  return NEW;
end;
$function$;

revoke all on function private.sync_wallet_rate_from_pricing_settings() from public, anon, authenticated;

drop trigger if exists pricing_settings_sync_wallet_rate on public.pricing_settings;
create trigger pricing_settings_sync_wallet_rate
after insert or update on public.pricing_settings
for each row execute function private.sync_wallet_rate_from_pricing_settings();

update public.wallet_settings w
   set cup_per_usd = p.usdt_cup_rate,
       updated_by = p.updated_by,
       updated_at = now()
  from public.pricing_settings p
 where w.id = 1 and p.id = 1
   and w.cup_per_usd is distinct from p.usdt_cup_rate;

-- An admin can cancel a locally blocked preflight only if no provider order/request exists.
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
     or v_order.central_one_reference_code is not null
     or v_order.central_one_request_id is not null
     or v_order.central_one_status <> 'retryable'
     or coalesce(v_order.central_one_response->>'preflight','') <> 'blocked' then
    raise exception 'Este pedido no cumple las condiciones de anulación segura. Puede que ya se haya enviado al proveedor.';
  end if;

  update public.orders
     set status = 'cancelled',
         central_one_status = 'cancelled',
         central_one_error_code = 'admin_cancelled_before_provider',
         central_one_error_message = 'Pedido anulado por el administrador antes de crear una orden en Central One. No se realizó una devolución automática.',
         central_one_checked_at = now(),
         central_one_response = coalesce(central_one_response, '{}'::jsonb)
           || jsonb_build_object('cancelled_before_provider', true, 'cancelled_at', now()),
         admin_notes = concat_ws(E'\n', nullif(admin_notes,''), 'Anulado por administrador antes del envío a Central One; no se creó una orden del proveedor.')
   where id = p_order_id;

  return jsonb_build_object(
    'ok', true,
    'order_id', v_order.id,
    'order_code', v_order.order_code,
    'status', 'cancelled',
    'provider_order_created', false,
    'automatic_refund', false
  );
end;
$function$;

revoke all on function public.admin_cancel_preflight_blocked_order(uuid) from public, anon;
grant execute on function public.admin_cancel_preflight_blocked_order(uuid) to authenticated;
