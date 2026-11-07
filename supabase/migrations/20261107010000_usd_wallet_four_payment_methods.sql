-- USD-denominated internal wallet, CUP/USDT wallet deposits, four checkout methods,
-- safe provider-failure refunds, and exact USDT payment evidence.
-- This migration is staged on a feature branch; it has NOT been applied to production.

begin;

-- Keep the wallet conversion rate distinct from the store's USDT acquisition-cost rate.
alter table public.pricing_settings
  add column if not exists usd_cup_rate numeric(14,4);
update public.pricing_settings
set usd_cup_rate = usdt_cup_rate
where usd_cup_rate is null;
alter table public.pricing_settings
  alter column usd_cup_rate set default 1200,
  alter column usd_cup_rate set not null;
alter table public.pricing_settings
  drop constraint if exists pricing_settings_usd_cup_rate_check;
alter table public.pricing_settings
  add constraint pricing_settings_usd_cup_rate_check check (usd_cup_rate > 0);

alter table public.pricing_rate_history
  add column if not exists usd_cup_rate numeric(14,4);
update public.pricing_rate_history
set usd_cup_rate = usdt_cup_rate
where usd_cup_rate is null;
alter table public.pricing_rate_history
  alter column usd_cup_rate set default 1200,
  alter column usd_cup_rate set not null;

create or replace function public.log_pricing_settings_history()
returns trigger
language plpgsql
set search_path to ''
as $function$
begin
  insert into public.pricing_rate_history (
    usdt_cup_rate,
    usd_cup_rate,
    mobile_credit_units,
    mobile_cost_cup,
    markup_percent,
    rounding_cup,
    changed_at,
    changed_by,
    note
  ) values (
    new.usdt_cup_rate,
    new.usd_cup_rate,
    new.mobile_credit_units,
    new.mobile_cost_cup,
    new.markup_percent,
    new.rounding_cup,
    now(),
    auth.uid(),
    case when tg_op = 'INSERT' then 'Configuración inicial' else 'Cambio de configuración' end
  );
  return new;
end;
$function$;

-- A fourth independently editable retail price for the USD wallet.
alter table public.products
  add column if not exists price_wallet_usd numeric(12,2) not null default 0;
alter table public.products
  drop constraint if exists products_price_wallet_usd_check;
alter table public.products
  add constraint products_price_wallet_usd_check check (price_wallet_usd >= 0);
update public.products p
set price_wallet_usd = case
  when coalesce(p.price_transfer,0) > 0
    then round(p.price_transfer / s.usd_cup_rate, 2)
  else 0
end
from public.pricing_settings s
where s.id = 1;

-- The wallet ledger is denominated in USD. Existing currencies remain accepted for
-- backwards-compatible history, but all new wallet operations use USD.
alter table public.wallet_transactions
  drop constraint if exists wallet_transactions_currency_check;
alter table public.wallet_transactions
  add constraint wallet_transactions_currency_check
  check (currency in ('USD','CUP','USDT'));

alter table public.wallet_transactions
  add column if not exists deposit_id uuid
  references public.wallet_deposits(id) on delete restrict;

create unique index if not exists wallet_transactions_one_deposit_credit_idx
  on public.wallet_transactions(deposit_id)
  where deposit_id is not null;

create unique index if not exists wallet_transactions_one_refund_per_order_idx
  on public.wallet_transactions(order_id)
  where order_id is not null and kind = 'refund';

-- Snapshot the refund value at order creation, so later price changes never change a refund.
alter table public.orders
  add column if not exists wallet_refund_usd numeric(18,2) not null default 0,
  add column if not exists wallet_refunded_at timestamptz;
alter table public.orders
  drop constraint if exists orders_wallet_refund_usd_check;
alter table public.orders
  add constraint orders_wallet_refund_usd_check check (wallet_refund_usd >= 0);

-- Record the amount paid in its native currency and the exact USD credit calculated
-- at request time. The exchange rate is not recalculated on the approval day.
alter table public.wallet_deposits
  add column if not exists exchange_rate_snapshot numeric(14,4),
  add column if not exists credit_usd numeric(18,2);

alter table public.wallet_deposits
  drop constraint if exists wallet_deposits_currency_check;
alter table public.wallet_deposits
  add constraint wallet_deposits_currency_check check (currency in ('CUP','USDT'));

alter table public.wallet_deposits
  drop constraint if exists wallet_deposits_payment_method_check;
alter table public.wallet_deposits
  add constraint wallet_deposits_payment_method_check
  check (payment_method in ('Transferencia CUP','USDT'));

drop policy if exists "wallet deposits insert own pending" on public.wallet_deposits;
create policy "wallet deposits insert own pending"
on public.wallet_deposits
for insert
to authenticated
with check (
  user_id = (select auth.uid())
  and status = 'pending'
  and currency in ('CUP','USDT')
  and proof_path is null
);

create or replace function public.validate_wallet_deposit_request()
returns trigger
language plpgsql
set search_path to ''
as $function$
declare
  v_rate numeric(14,4);
begin
  if auth.uid() is null or new.user_id is distinct from auth.uid() then
    raise exception 'No autorizado para crear este depósito.';
  end if;
  if new.amount is null or new.amount <= 0 then
    raise exception 'El importe del depósito debe ser mayor que cero.';
  end if;

  if new.currency = 'CUP' and new.payment_method <> 'Transferencia CUP' then
    raise exception 'Para ingresar CUP debes seleccionar Transferencia CUP.';
  elsif new.currency = 'USDT' and new.payment_method <> 'USDT' then
    raise exception 'Para ingresar USDT debes seleccionar USDT.';
  elsif new.currency not in ('CUP','USDT') then
    raise exception 'Moneda de depósito no admitida.';
  end if;

  if new.currency = 'USDT' and abs(new.amount - round(new.amount,2)) > 0.000001 then
    raise exception 'Los depósitos USDT deben indicarse con un máximo de dos decimales.';
  end if;

  if not exists (
    select 1
    from public.payment_methods pm
    where pm.name = new.payment_method
      and pm.active = true
      and nullif(trim(coalesce(pm.instructions,'')),'') is not null
  ) then
    raise exception 'El método de pago no está disponible o no tiene instrucciones configuradas.';
  end if;

  select usd_cup_rate into v_rate
  from public.pricing_settings
  where id = 1;
  if new.currency = 'CUP' and (v_rate is null or v_rate <= 0) then
    raise exception 'La tasa CUP/USD no está configurada.';
  end if;

  new.exchange_rate_snapshot := case when new.currency = 'CUP' then v_rate else 1 end;
  new.credit_usd := case
    when new.currency = 'CUP' then round(new.amount / v_rate, 2)
    else round(new.amount, 2)
  end;
  if new.credit_usd <= 0 then
    raise exception 'El importe es demasiado pequeño para generar crédito.';
  end if;

  new.status := 'pending';
  new.proof_path := null;
  new.payment_reference := null;
  new.admin_notes := null;
  new.reviewed_at := null;
  new.created_at := now();
  return new;
end;
$function$;

create or replace function public.submit_wallet_deposit_proof(
  p_deposit_id uuid,
  p_proof_path text,
  p_reference text default null
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_uid uuid := auth.uid();
  v_deposit public.wallet_deposits%rowtype;
  v_reference text := upper(nullif(trim(coalesce(p_reference,'')), ''));
begin
  if v_uid is null then
    raise exception 'Debes iniciar sesión.';
  end if;

  select * into v_deposit
  from public.wallet_deposits
  where id = p_deposit_id and user_id = v_uid
  for update;
  if not found then
    raise exception 'No encontramos el depósito en tu cuenta.';
  end if;
  if v_deposit.status not in ('pending','payment_review') then
    raise exception 'Este depósito ya no admite cambios.';
  end if;
  if not exists (
    select 1 from public.payment_methods pm
    where pm.name = v_deposit.payment_method and pm.active = true
      and nullif(trim(coalesce(pm.instructions,'')),'') is not null
  ) then
    raise exception 'El método de pago ya no está disponible.';
  end if;

  if v_deposit.currency = 'CUP' then
    if v_deposit.payment_method <> 'Transferencia CUP'
       or v_reference is null or length(v_reference) < 3 or length(v_reference) > 100 then
      raise exception 'Escribe el número válido de la transferencia.';
    end if;
  elsif v_deposit.currency = 'USDT' then
    if v_deposit.payment_method <> 'USDT'
       or v_reference !~ '^[A-F0-9]{64}$' then
      raise exception 'Escribe el hash/TxID USDT de 64 caracteres hexadecimales.';
    end if;
    if exists (
      select 1 from public.wallet_deposits d
      where d.id <> p_deposit_id and upper(coalesce(d.payment_reference,'')) = v_reference
        and d.status in ('payment_review','approved')
    ) or exists (
      select 1 from public.orders o
      where o.payment_method = 'USDT' and upper(coalesce(o.payment_reference,'')) = v_reference
        and o.status in ('payment_review','processing','completed')
    ) then
      raise exception 'Ese TxID ya fue utilizado en otra operación.';
    end if;
  else
    raise exception 'Moneda de depósito no válida.';
  end if;

  if p_proof_path !~ (
    '^' || v_uid::text || '/' || p_deposit_id::text ||
    '/[a-f0-9-]{36}[.](jpg|jpeg|png|webp)$'
  ) then
    raise exception 'La ruta del comprobante no es válida.';
  end if;
  if not exists (
    select 1 from storage.objects so
    where so.bucket_id = 'payment-proofs' and so.name = p_proof_path
  ) then
    raise exception 'No encontramos la imagen subida.';
  end if;

  update public.wallet_deposits
  set proof_path = p_proof_path,
      payment_reference = v_reference,
      status = 'payment_review'
  where id = p_deposit_id and user_id = v_uid;

  return jsonb_build_object(
    'deposit_id',p_deposit_id,
    'status','payment_review',
    'credit_usd',v_deposit.credit_usd,
    'exchange_rate_snapshot',v_deposit.exchange_rate_snapshot
  );
end;
$function$;

revoke all on function public.submit_wallet_deposit_proof(uuid,text,text) from public;
grant execute on function public.submit_wallet_deposit_proof(uuid,text,text) to authenticated;

create or replace function public.admin_review_wallet_deposit(
  p_deposit_id uuid,
  p_approve boolean,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_deposit public.wallet_deposits%rowtype;
  v_credit numeric(18,2);
  v_tx_id uuid;
begin
  if auth.uid() is null or not private.is_admin() then
    raise exception 'No autorizado.';
  end if;

  select * into v_deposit
  from public.wallet_deposits
  where id = p_deposit_id
  for update;
  if not found then
    raise exception 'Depósito no encontrado.';
  end if;
  if v_deposit.status <> 'payment_review' or v_deposit.proof_path is null then
    raise exception 'El depósito todavía no tiene comprobante para revisar.';
  end if;

  if p_approve then
    v_credit := v_deposit.credit_usd;
    if v_credit is null or v_credit <= 0 then
      raise exception 'El crédito USD del depósito no es válido.';
    end if;

    insert into public.wallet_transactions(
      user_id, deposit_id, kind, amount, currency, description
    ) values (
      v_deposit.user_id,
      v_deposit.id,
      'deposit',
      v_credit,
      'USD',
      'Depósito aprobado (' || v_deposit.amount::text || ' ' || v_deposit.currency ||
        ', tasa ' || coalesce(v_deposit.exchange_rate_snapshot::text,'1') || ' CUP/USD)'
    )
    on conflict (deposit_id) where deposit_id is not null do nothing
    returning id into v_tx_id;

    if v_tx_id is null then
      raise exception 'Este depósito ya fue acreditado anteriormente.';
    end if;

    update public.wallet_deposits
    set status = 'approved',
        admin_notes = nullif(trim(coalesce(p_note,'')),''),
        reviewed_at = now()
    where id = p_deposit_id;
  else
    update public.wallet_deposits
    set status = 'rejected',
        admin_notes = nullif(trim(coalesce(p_note,'')),''),
        reviewed_at = now()
    where id = p_deposit_id;
  end if;

  return jsonb_build_object(
    'deposit_id',p_deposit_id,
    'status',case when p_approve then 'approved' else 'rejected' end,
    'credited_usd',case when p_approve then v_credit else 0 end
  );
end;
$function$;

create or replace function public.validate_order_request()
returns trigger
language plpgsql
set search_path to ''
as $function$
declare
  selected_product public.products%rowtype;
  final_price numeric;
begin
  if auth.uid() is null or new.user_id is distinct from auth.uid() then
    raise exception 'No autorizado para crear este pedido.';
  end if;
  if new.product_id is null then
    raise exception 'Selecciona un producto válido.';
  end if;
  if new.player_id is null or length(btrim(new.player_id)) < 3 or length(btrim(new.player_id)) > 64 then
    raise exception 'El ID del jugador debe tener entre 3 y 64 caracteres.';
  end if;

  select * into selected_product
  from public.products
  where id = new.product_id and active = true;
  if not found then
    raise exception 'El producto ya no está disponible.';
  end if;

  if coalesce(new.payment_source,'direct') = 'wallet' then
    if new.payment_method <> 'Billetera USD' then
      raise exception 'Método de billetera no válido.';
    end if;
    final_price := selected_product.price_wallet_usd;
  elsif coalesce(new.payment_source,'direct') = 'direct' then
    if not exists (
      select 1 from public.payment_methods pm
      where pm.name = new.payment_method and pm.active = true
        and nullif(trim(coalesce(pm.instructions,'')),'') is not null
    ) then
      raise exception 'El método de pago no está activo o no tiene instrucciones.';
    end if;
    case new.payment_method
      when 'Transferencia CUP' then final_price := selected_product.price_transfer;
      when 'Saldo móvil' then final_price := selected_product.price_mobile;
      when 'USDT' then final_price := selected_product.price_usdt;
      else raise exception 'Método de pago no válido.';
    end case;
  else
    raise exception 'Origen de pago no válido.';
  end if;

  if final_price is null or final_price <= 0 then
    raise exception 'Este producto no tiene precio para ese método de pago.';
  end if;

  new.game := selected_product.game;
  new.package_name := selected_product.name;
  new.price := final_price;
  new.wallet_refund_usd := selected_product.price_wallet_usd;
  new.status := 'pending';
  new.order_code := 'EC-' || upper(substr(replace(gen_random_uuid()::text,'-',''),1,10));
  new.player_id := btrim(new.player_id);
  new.player_name := nullif(btrim(coalesce(new.player_name,'')),'');
  new.payment_reference := null;
  new.payment_sender_phone := null;
  new.payment_reported_amount := null;
  new.admin_notes := null;
  new.created_at := now();
  new.payment_source := coalesce(new.payment_source,'direct');
  new.proof_path := null;
  new.paid_at := null;
  return new;
end;
$function$;

create or replace function public.create_wallet_order(
  p_product_id uuid,
  p_player_id text,
  p_player_name text default '',
  p_player_validation_token uuid default null,
  p_privacy_policy_version text default '2026-11-07-v1'
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_uid uuid := auth.uid();
  v_product public.products%rowtype;
  v_balance numeric;
  v_order public.orders%rowtype;
begin
  if v_uid is null then
    raise exception 'Debes iniciar sesión.';
  end if;
  if length(trim(coalesce(p_player_id,''))) < 3 or length(trim(p_player_id)) > 64 then
    raise exception 'ID de jugador no válido.';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(v_uid::text,0));

  select * into v_product
  from public.products
  where id = p_product_id and active = true;
  if not found or coalesce(v_product.price_wallet_usd,0) <= 0 then
    raise exception 'Paquete no disponible para la billetera USD.';
  end if;

  v_balance := private.wallet_balance(v_uid,'USD');
  if v_balance < v_product.price_wallet_usd then
    raise exception 'Saldo insuficiente. Disponible: % USD. Necesitas: % USD.',
      round(v_balance,2), v_product.price_wallet_usd;
  end if;

  insert into public.orders (
    user_id, product_id, player_id, player_name, payment_method,
    payment_reference, status, payment_source, provider_product_id,
    provider_region, player_id_validation_token, privacy_consent_at,
    privacy_policy_version
  ) values (
    v_uid, v_product.id, trim(p_player_id), trim(coalesce(p_player_name,'')),
    'Billetera USD', '', 'pending', 'wallet', v_product.provider_product_id,
    v_product.provider_region, p_player_validation_token, now(),
    p_privacy_policy_version
  )
  returning * into v_order;

  insert into public.wallet_transactions(
    user_id, order_id, kind, amount, currency, description
  ) values (
    v_uid, v_order.id, 'purchase', v_order.price, 'USD',
    'Compra del pedido ' || v_order.order_code
  );

  update public.orders
  set status = 'processing'
  where id = v_order.id and user_id = v_uid;

  return jsonb_build_object(
    'order_id',v_order.id,
    'order_code',v_order.order_code,
    'price',v_order.price,
    'currency','USD',
    'balance',round(private.wallet_balance(v_uid,'USD'),2),
    'status','processing'
  );
end;
$function$;

revoke all on function public.create_wallet_order(uuid,text,text,uuid,text) from public;
grant execute on function public.create_wallet_order(uuid,text,text,uuid,text) to authenticated;

-- A verified terminal failure/cancellation returns the saved wallet-equivalent value
-- exactly once. Unknown, retryable, processing, and partial completion are not refunded.
create or replace function public.finish_central_one_order(
  p_order_id uuid,
  p_provider_status text,
  p_provider_order_id uuid default null,
  p_reference_code text default null,
  p_request_id text default null,
  p_response jsonb default null,
  p_error_code text default null,
  p_error_message text default null
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_order public.orders%rowtype;
  v_local_status text;
  v_refund_id uuid;
  v_refunded_at timestamptz;
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
  if not found then
    raise exception 'Pedido local no encontrado.';
  end if;

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

  if p_provider_status in ('failed','cancelled')
     and coalesce(v_order.wallet_refund_usd,0) > 0
     and v_order.wallet_refunded_at is null then
    insert into public.wallet_transactions(
      user_id, order_id, kind, amount, currency, description
    ) values (
      v_order.user_id,
      v_order.id,
      'refund',
      v_order.wallet_refund_usd,
      'USD',
      'Crédito devuelto por fallo confirmado del pedido ' || coalesce(v_order.order_code,v_order.id::text)
    )
    on conflict (order_id) where order_id is not null and kind = 'refund'
    do nothing
    returning id into v_refund_id;

    if v_refund_id is not null then
      v_refunded_at := now();
    else
      select created_at into v_refunded_at
      from public.wallet_transactions
      where order_id = v_order.id and kind = 'refund'
      limit 1;
    end if;
  else
    v_refunded_at := v_order.wallet_refunded_at;
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
      status = v_local_status,
      wallet_refunded_at = coalesce(v_refunded_at,wallet_refunded_at)
  where id = p_order_id;

  return jsonb_build_object(
    'order_id',p_order_id,
    'status',v_local_status,
    'central_one_status',p_provider_status,
    'central_one_order_id',coalesce(p_provider_order_id,v_order.central_one_order_id),
    'central_one_reference_code',coalesce(p_reference_code,v_order.central_one_reference_code),
    'wallet_refund_usd',case when v_refunded_at is not null then v_order.wallet_refund_usd else 0 end,
    'wallet_refunded_at',v_refunded_at
  );
end;
$function$;

-- USDT evidence: no mobile number is required; the exact amount and unique TxID are.
alter table public.orders
  alter column payment_reported_amount type numeric(18,6)
  using payment_reported_amount::numeric(18,6);

create or replace function public.submit_payment_proof(
  p_order_id uuid,
  p_proof_path text,
  p_reference text,
  p_sender_phone text,
  p_reported_amount numeric
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_uid uuid := auth.uid();
  v_order public.orders%rowtype;
  v_reference text := upper(nullif(trim(coalesce(p_reference,'')), ''));
  v_phone text := regexp_replace(trim(coalesce(p_sender_phone,'')), '[^0-9+]', '', 'g');
  v_phone_digits text := regexp_replace(coalesce(p_sender_phone,''), '[^0-9]', '', 'g');
begin
  if v_uid is null then
    raise exception 'Debes iniciar sesión para enviar el comprobante.';
  end if;
  if p_order_id is null or p_proof_path is null then
    raise exception 'Faltan datos del comprobante.';
  end if;

  select * into v_order
  from public.orders
  where id = p_order_id and user_id = v_uid
  for update;
  if not found then
    raise exception 'No encontramos ese pedido en tu cuenta.';
  end if;
  if v_order.payment_source <> 'direct' then
    raise exception 'Este pedido no admite comprobantes externos.';
  end if;
  if v_order.status not in ('pending','payment_review') then
    raise exception 'Este pedido ya no admite cambios de comprobante.';
  end if;
  if not exists (
    select 1 from public.payment_methods pm
    where pm.name = v_order.payment_method and pm.active = true
      and nullif(trim(coalesce(pm.instructions,'')),'') is not null
  ) then
    raise exception 'El método de pago ya no está disponible. Contacta con la tienda.';
  end if;

  if v_order.payment_method in ('Transferencia CUP','Saldo móvil') then
    if v_phone_digits !~ '^[0-9]{8,15}$' or v_phone !~ '^[+]?[0-9]{8,15}$' then
      raise exception 'Escribe un número móvil válido desde el que realizaste el pago.';
    end if;
  elsif v_order.payment_method <> 'USDT' then
    raise exception 'Este método de pago no admite comprobantes.';
  end if;

  if v_order.payment_method = 'Transferencia CUP' then
    if v_reference is null or length(v_reference) < 3 or length(v_reference) > 100 then
      raise exception 'Escribe el número de transferencia.';
    end if;
    if p_reported_amount is not null then
      raise exception 'No envíes un importe manual para la transferencia bancaria.';
    end if;
  elsif v_order.payment_method = 'Saldo móvil' then
    if p_reported_amount is null or p_reported_amount <= 0 then
      raise exception 'Escribe el importe de saldo que enviaste.';
    end if;
    if abs(p_reported_amount - v_order.price) > 0.01 then
      raise exception 'El importe enviado debe coincidir exactamente con el precio del paquete: %.',v_order.price;
    end if;
    if v_reference is not null then
      raise exception 'El saldo móvil no utiliza número de transferencia bancaria.';
    end if;
  elsif v_order.payment_method = 'USDT' then
    if v_reference !~ '^[A-F0-9]{64}$' then
      raise exception 'Escribe el hash/TxID USDT de 64 caracteres hexadecimales.';
    end if;
    if p_reported_amount is null or p_reported_amount <= 0
       or abs(p_reported_amount - v_order.price) > 0.000001 then
      raise exception 'El importe debe coincidir exactamente con el precio del paquete: % USDT.',v_order.price;
    end if;
    if exists (
      select 1 from public.orders o
      where o.id <> p_order_id and o.payment_method='USDT'
        and upper(coalesce(o.payment_reference,''))=v_reference
        and o.status in ('payment_review','processing','completed')
    ) or exists (
      select 1 from public.wallet_deposits d
      where d.payment_method='USDT'
        and upper(coalesce(d.payment_reference,''))=v_reference
        and d.status in ('payment_review','approved')
    ) then
      raise exception 'Ese TxID ya fue utilizado en otra operación.';
    end if;
  end if;

  if p_proof_path !~ (
    '^' || v_uid::text || '/' || p_order_id::text ||
    '/[a-f0-9-]{36}[.](jpg|jpeg|png|webp)$'
  ) then
    raise exception 'La ruta del comprobante no es válida.';
  end if;
  if not exists (
    select 1 from storage.objects so
    where so.bucket_id = 'payment-proofs' and so.name = p_proof_path
  ) then
    raise exception 'No encontramos la imagen subida. Inténtalo de nuevo.';
  end if;

  update public.orders
  set proof_path = p_proof_path,
      payment_reference = case when v_order.payment_method in ('Transferencia CUP','USDT') then v_reference else null end,
      payment_sender_phone = case when v_order.payment_method in ('Transferencia CUP','Saldo móvil') then v_phone else null end,
      payment_reported_amount = case when v_order.payment_method in ('Saldo móvil','USDT') then p_reported_amount else null end,
      status = 'payment_review'
  where id = p_order_id and user_id = v_uid;

  return jsonb_build_object(
    'order_id',v_order.id,
    'order_code',v_order.order_code,
    'status','payment_review'
  );
end;
$function$;

revoke all on function public.submit_payment_proof(uuid,text,text,text,numeric) from public;
grant execute on function public.submit_payment_proof(uuid,text,text,text,numeric) to authenticated;

commit;
