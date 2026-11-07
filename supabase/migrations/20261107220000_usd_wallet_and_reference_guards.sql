-- Tienda El Castillo: wallet en USD, depósitos CUP/USDT y compras con saldo interno.
-- Esta migración no cambia precios directos; la wallet usa products.price_usdt como precio USD.

begin;

create table if not exists public.wallet_settings (
  id smallint primary key default 1 check (id=1),
  cup_per_usd numeric(18,4) not null default 1160 check (cup_per_usd>0),
  usdt_network text not null default 'BNB Smart Chain (BEP20)',
  usdt_address text not null default '0x30d000d6B30f241986186BfFeCa8A449E5790C1D',
  updated_at timestamptz not null default now(),
  updated_by uuid references public.profiles(id) on delete set null
);
insert into public.wallet_settings(id,cup_per_usd,usdt_network,usdt_address)
values(1,1160,'BNB Smart Chain (BEP20)','0x30d000d6B30f241986186BfFeCa8A449E5790C1D')
on conflict(id) do nothing;

alter table public.wallet_deposits
  add column if not exists credited_amount numeric(20,6),
  add column if not exists exchange_rate numeric(18,6),
  add column if not exists sender_phone text,
  add column if not exists txid text,
  add column if not exists network text,
  add column if not exists recipient_address text,
  add column if not exists reviewed_by uuid references public.profiles(id) on delete set null;

alter table public.wallet_transactions
  add column if not exists deposit_id uuid references public.wallet_deposits(id) on delete restrict;

-- The wallet balance is denominated in USD. The old table check only allowed CUP/USDT,
-- which silently blocked every USD credit and every wallet purchase.
alter table public.wallet_transactions drop constraint if exists wallet_transactions_currency_check;
alter table public.wallet_transactions add constraint wallet_transactions_currency_check
  check(currency in ('CUP','USDT','USD'));

alter table public.orders
  add column if not exists wallet_request_id uuid;

create table if not exists public.wallet_deposit_proofs (
  id uuid primary key default gen_random_uuid(),
  deposit_id uuid not null references public.wallet_deposits(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  proof_path text not null unique,
  uploaded_at timestamptz not null default now(),
  unique(deposit_id,proof_path)
);

alter table public.wallet_deposits drop constraint if exists wallet_deposits_currency_check;
alter table public.wallet_deposits add constraint wallet_deposits_currency_check check(currency in ('CUP','USDT'));
alter table public.wallet_deposits drop constraint if exists wallet_deposits_payment_method_check;
alter table public.wallet_deposits add constraint wallet_deposits_payment_method_check check(payment_method in ('Transferencia CUP','USDT'));

create index if not exists wallet_deposits_currency_status_created_idx
  on public.wallet_deposits(currency,status,created_at desc);
create index if not exists wallet_deposit_proofs_deposit_id_idx
  on public.wallet_deposit_proofs(deposit_id);
create index if not exists wallet_deposit_proofs_user_id_idx
  on public.wallet_deposit_proofs(user_id);
create index if not exists wallet_deposits_reviewed_by_idx
  on public.wallet_deposits(reviewed_by) where reviewed_by is not null;
create index if not exists wallet_settings_updated_by_idx
  on public.wallet_settings(updated_by) where updated_by is not null;

drop index if exists public.wallet_deposits_transfer_reference_unique;
create unique index wallet_deposits_transfer_reference_unique
  on public.wallet_deposits(upper(regexp_replace(trim(payment_reference),'[[:space:]]+','','g')))
  where payment_method='Transferencia CUP' and payment_reference is not null and trim(payment_reference)<>'';
create unique index if not exists wallet_deposits_txid_unique
  on public.wallet_deposits(lower(txid))
  where txid is not null and trim(txid)<>'';
create unique index if not exists wallet_transactions_deposit_id_unique
  on public.wallet_transactions(deposit_id) where deposit_id is not null;
create unique index if not exists wallet_transactions_wallet_purchase_order_unique
  on public.wallet_transactions(order_id) where kind='purchase' and order_id is not null;
create unique index if not exists orders_wallet_request_id_unique
  on public.orders(user_id,wallet_request_id)
  where payment_source='wallet' and wallet_request_id is not null;

alter table public.wallet_settings enable row level security;
alter table public.wallet_deposit_proofs enable row level security;

drop policy if exists "wallet settings readable by authenticated" on public.wallet_settings;
create policy "wallet settings readable by authenticated"
  on public.wallet_settings for select to authenticated using(true);
drop policy if exists "wallet settings manageable by admins" on public.wallet_settings;
create policy "wallet settings manageable by admins"
  on public.wallet_settings for update to authenticated
  using((select private.is_admin()))
  with check((select private.is_admin()));

drop policy if exists "wallet deposit proofs read own or admin" on public.wallet_deposit_proofs;
create policy "wallet deposit proofs read own or admin"
  on public.wallet_deposit_proofs for select to authenticated
  using(user_id=(select auth.uid()) or (select private.is_admin()));

drop policy if exists "wallet deposits insert own pending" on public.wallet_deposits;
create policy "wallet deposits insert own pending"
  on public.wallet_deposits for insert to authenticated
  with check(
    user_id=(select auth.uid())
    and status='pending'
    and currency in ('CUP','USDT')
    and proof_path is null
  );

grant select,update on public.wallet_settings to authenticated;
grant select on public.wallet_deposit_proofs to authenticated;
grant usage on schema public to authenticated;

-- Direct USDT checkout remains independent from internal USD wallet deposits.
update public.payment_methods
set active=true,
    instructions='Envía el importe exacto del paquete en USDT por la red BNB Smart Chain (BEP20) a esta dirección: 0x30d000d6B30f241986186BfFeCa8A449E5790C1D. Comprueba cuidadosamente la red y la dirección antes de confirmar. Después adjunta el comprobante, indica la cantidad exacta enviada y pega el hash/TxID de 64 caracteres de la transacción. La tienda verificará la llegada real antes de autorizar la recarga.'
where name='USDT';

create or replace function public.validate_wallet_deposit_request()
returns trigger
language plpgsql
set search_path=''
as $function$
declare
  v_settings public.wallet_settings%rowtype;
begin
  if auth.uid() is null or new.user_id is distinct from auth.uid() then
    raise exception 'No autorizado para crear este depósito.';
  end if;
  if new.amount is null or new.amount<=0 then
    raise exception 'El importe del depósito debe ser mayor que cero.';
  end if;
  select * into v_settings from public.wallet_settings where id=1;
  if not found then raise exception 'La configuración de la billetera no está disponible.'; end if;

  if new.payment_method='Transferencia CUP' and new.currency='CUP' then
    if new.amount<v_settings.cup_per_usd then
      raise exception 'El depósito mínimo es el equivalente a 1 USD: % CUP al cambio actual.',ceil(v_settings.cup_per_usd);
    end if;
    new.exchange_rate:=v_settings.cup_per_usd;
    new.credited_amount:=floor((new.amount/v_settings.cup_per_usd)*100)/100;
    if new.credited_amount<1 then raise exception 'El depósito debe acreditar al menos 1.00 USD.'; end if;
    new.network:=null;
    new.txid:=null;
    new.recipient_address:=null;
  elsif new.payment_method='USDT' and new.currency='USDT' then
    if new.amount<1 then raise exception 'El depósito mínimo es 1 USDT.'; end if;
    new.exchange_rate:=1;
    new.credited_amount:=new.amount;
    new.network:=v_settings.usdt_network;
    new.recipient_address:=v_settings.usdt_address;
    new.txid:=null;
  else
    raise exception 'Método o moneda de depósito no válido. Utiliza Transferencia CUP o USDT.';
  end if;

  if not exists(
    select 1 from public.payment_methods pm
    where pm.name=new.payment_method and pm.active=true and nullif(trim(pm.instructions),'') is not null
  ) then raise exception 'Este método de depósito todavía no está configurado.'; end if;

  new.status:='pending';
  new.proof_path:=null;
  new.payment_reference:=null;
  new.sender_phone:=null;
  new.admin_notes:=null;
  new.reviewed_at:=null;
  new.reviewed_by:=null;
  new.created_at:=now();
  return new;
end;
$function$;

create or replace function public.submit_wallet_deposit_proofs(
  p_deposit_id uuid,
  p_proof_paths text[],
  p_reference text default null,
  p_sender_phone text default null,
  p_txid text default null,
  p_network text default null
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_uid uuid:=auth.uid();
  v_deposit public.wallet_deposits%rowtype;
  v_path text;
  v_reference text:=nullif(upper(regexp_replace(trim(coalesce(p_reference,'')),'[[:space:]]+','','g')),'');
  v_txid text:=nullif(lower(trim(coalesce(p_txid,''))),'');
  v_phone text:=nullif(trim(coalesce(p_sender_phone,'')),'');
  v_count integer:=0;
begin
  if v_uid is null then raise exception 'Debes iniciar sesión.'; end if;
  if p_proof_paths is null or cardinality(p_proof_paths)<1 or cardinality(p_proof_paths)>5 then
    raise exception 'Adjunta entre 1 y 5 comprobantes.';
  end if;
  select * into v_deposit from public.wallet_deposits
  where id=p_deposit_id and user_id=v_uid for update;
  if not found then raise exception 'No encontramos el depósito en tu cuenta.'; end if;
  if v_deposit.status not in ('pending','payment_review') then
    raise exception 'Este depósito ya no admite comprobantes.';
  end if;

  if v_deposit.payment_method='Transferencia CUP' then
    if v_reference is null or length(v_reference)<3 or length(v_reference)>100 then
      raise exception 'Escribe el número de transferencia del banco.';
    end if;
    if v_phone is null or v_phone !~ '^[+]?[0-9 ().-]{8,20}$'
       or length(regexp_replace(v_phone,'[^0-9]','','g')) not between 8 and 15 then
      raise exception 'Escribe el teléfono desde el que hiciste la transferencia.';
    end if;
    perform pg_advisory_xact_lock(hashtextextended('castle-payment-reference:CUP:'||v_reference,0));
    if v_deposit.payment_reference is not null
       and upper(regexp_replace(v_deposit.payment_reference,'[[:space:]]+','','g'))<>v_reference then
      raise exception 'El número de transferencia ya quedó registrado en esta solicitud.';
    end if;
    if exists(
      select 1 from public.wallet_deposits d
      where d.id<>p_deposit_id and d.payment_method='Transferencia CUP'
        and upper(regexp_replace(coalesce(d.payment_reference,''),'[[:space:]]+','','g'))=v_reference
    ) then
      raise exception 'Ese número de transferencia ya fue utilizado en otra solicitud de depósito.';
    end if;
    if exists(
      select 1 from public.orders o
      where o.payment_method='Transferencia CUP'
        and upper(regexp_replace(coalesce(o.payment_reference,''),'[[:space:]]+','','g'))=v_reference
        and o.status in ('payment_review','processing','completed','rejected')
    ) then
      raise exception 'Ese número de transferencia ya fue utilizado en un pedido directo.';
    end if;
  elsif v_deposit.payment_method='USDT' then
    if v_txid is null or v_txid !~ '^[a-f0-9]{64}$' then
      raise exception 'El TxID debe tener 64 caracteres hexadecimales.';
    end if;
    if upper(coalesce(p_network,'')) not in ('BNB SMART CHAIN (BEP20)','BEP20') then
      raise exception 'La red debe ser BNB Smart Chain (BEP20).';
    end if;
    perform pg_advisory_xact_lock(hashtextextended('castle-payment-reference:USDT:'||v_txid,0));
    if v_deposit.txid is not null and lower(v_deposit.txid)<>v_txid then
      raise exception 'El TxID ya quedó registrado en esta solicitud.';
    end if;
    if exists(select 1 from public.wallet_deposits d where d.id<>p_deposit_id and lower(coalesce(d.txid,''))=v_txid) then
      raise exception 'Ese TxID ya fue utilizado en otra solicitud de depósito.';
    end if;
    if exists(
      select 1 from public.orders o
      where o.payment_method='USDT'
        and lower(coalesce(o.payment_reference,''))=v_txid
        and o.status in ('payment_review','processing','completed','rejected')
    ) then
      raise exception 'Ese TxID ya fue utilizado en un pedido directo.';
    end if;
  else
    raise exception 'Método de depósito no válido.';
  end if;

  foreach v_path in array p_proof_paths loop
    if v_path !~ ('^'||v_uid::text||'/'||p_deposit_id::text||'/[a-f0-9-]{36}[.](jpg|jpeg|png|webp)$') then
      raise exception 'La ruta de uno de los comprobantes no es válida.';
    end if;
    if not exists(select 1 from storage.objects so where so.bucket_id='payment-proofs' and so.name=v_path) then
      raise exception 'No encontramos uno de los archivos subidos.';
    end if;
    insert into public.wallet_deposit_proofs(deposit_id,user_id,proof_path)
    values(p_deposit_id,v_uid,v_path)
    on conflict(deposit_id,proof_path) do nothing;
    v_count:=v_count+1;
  end loop;

  update public.wallet_deposits
  set proof_path=coalesce(proof_path,p_proof_paths[1]),
      payment_reference=case when v_deposit.payment_method='Transferencia CUP' then v_reference else v_txid end,
      sender_phone=case when v_deposit.payment_method='Transferencia CUP' then v_phone else null end,
      txid=case when v_deposit.payment_method='USDT' then v_txid else null end,
      network=case when v_deposit.payment_method='USDT' then 'BNB Smart Chain (BEP20)' else null end,
      status='payment_review'
  where id=p_deposit_id and user_id=v_uid;

  return jsonb_build_object('deposit_id',p_deposit_id,'status','payment_review','proofs_received',v_count);
end;
$function$;

create or replace function public.admin_review_wallet_deposit(
  p_deposit_id uuid,p_approve boolean,p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_deposit public.wallet_deposits%rowtype;
  v_note text:=nullif(trim(coalesce(p_note,'')),'');
begin
  if not private.is_admin() then raise exception 'No autorizado.'; end if;
  if p_approve is null then raise exception 'Selecciona aprobar o rechazar.'; end if;
  select * into v_deposit from public.wallet_deposits where id=p_deposit_id for update;
  if not found then raise exception 'Depósito no encontrado.'; end if;
  if v_deposit.status<>'payment_review' then
    raise exception 'El depósito debe estar en revisión y no puede acreditarse dos veces.';
  end if;
  if not exists(select 1 from public.wallet_deposit_proofs p where p.deposit_id=p_deposit_id) then
    raise exception 'No hay comprobantes asociados a este depósito.';
  end if;

  if p_approve then
    if coalesce(v_deposit.credited_amount,0)<1 then raise exception 'El importe a acreditar no cumple el mínimo de 1 USD.'; end if;
    if v_deposit.payment_method='Transferencia CUP'
       and (v_deposit.payment_reference is null or v_deposit.sender_phone is null) then
      raise exception 'Faltan los datos de verificación de la transferencia CUP.';
    end if;
    if v_deposit.payment_method='USDT'
       and (v_deposit.txid is null or v_deposit.network<>'BNB Smart Chain (BEP20)' or v_deposit.recipient_address is null) then
      raise exception 'La información de red, dirección o TxID no es válida.';
    end if;
    insert into public.wallet_transactions(user_id,deposit_id,kind,amount,currency,description)
    values(
      v_deposit.user_id,p_deposit_id,'deposit',v_deposit.credited_amount,'USD',
      case when v_deposit.currency='CUP' then 'Depósito por transferencia CUP aprobado' else 'Depósito USDT BEP20 aprobado' end
    );
    update public.wallet_deposits
    set status='approved',admin_notes=nullif(v_note,''),reviewed_at=now(),reviewed_by=auth.uid()
    where id=p_deposit_id;
  else
    if v_note is null or length(v_note)<5 then
      raise exception 'Es obligatorio explicar el motivo del rechazo (mínimo 5 caracteres).';
    end if;
    update public.wallet_deposits
    set status='rejected',admin_notes=v_note,reviewed_at=now(),reviewed_by=auth.uid()
    where id=p_deposit_id;
  end if;
  return jsonb_build_object(
    'deposit_id',p_deposit_id,
    'status',case when p_approve then 'approved' else 'rejected' end,
    'credited_amount',case when p_approve then v_deposit.credited_amount else 0 end
  );
end;
$function$;

drop function if exists public.submit_wallet_deposit_proof(uuid,text,text);
revoke all on function public.submit_wallet_deposit_proofs(uuid,text[],text,text,text,text) from public,anon;
grant execute on function public.submit_wallet_deposit_proofs(uuid,text[],text,text,text,text) to authenticated;
revoke all on function public.admin_review_wallet_deposit(uuid,boolean,text) from public,anon;
grant execute on function public.admin_review_wallet_deposit(uuid,boolean,text) to authenticated;

create or replace function public.validate_order_request()
returns trigger
language plpgsql
set search_path=''
as $function$
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

drop function if exists public.create_wallet_order(uuid,text,text);
drop function if exists public.create_wallet_order(uuid,text,text,uuid);
create function public.create_wallet_order(
  p_product_id uuid,
  p_player_id text,
  p_player_name text default '',
  p_player_id_validation_token uuid default null,
  p_request_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_uid uuid:=auth.uid();
  v_product public.products%rowtype;
  v_balance numeric;
  v_order public.orders%rowtype;
  v_price numeric;
begin
  if v_uid is null then raise exception 'Debes iniciar sesión.'; end if;
  if p_request_id is null then raise exception 'No se pudo identificar esta compra. Vuelve a intentarlo.'; end if;
  if length(trim(coalesce(p_player_id,'')))<3 or length(trim(p_player_id))>64 then
    raise exception 'ID de jugador no válido.';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(v_uid::text,0));
  select * into v_order
  from public.orders
  where user_id=v_uid and wallet_request_id=p_request_id
  for update;
  if found then
    if v_order.product_id is distinct from p_product_id or v_order.player_id is distinct from trim(p_player_id) then
      raise exception 'La clave de compra ya está asociada a otro pedido. Actualiza la página antes de repetir.';
    end if;
    return jsonb_build_object(
      'order_id',v_order.id,'order_code',v_order.order_code,'price',v_order.price,
      'currency','USD','balance',private.wallet_balance(v_uid,'USD'),
      'status',v_order.status,'already_processed',true
    );
  end if;

  select * into v_product from public.products where id=p_product_id and active=true;
  if not found or coalesce(v_product.price_usdt,0)<=0 then
    raise exception 'Paquete no disponible para el saldo de Tienda El Castillo.';
  end if;
  v_price:=v_product.price_usdt;
  v_balance:=private.wallet_balance(v_uid,'USD');
  if v_balance<v_price then
    raise exception 'Saldo insuficiente. Disponible: % USD. Necesitas: % USD.',round(v_balance,6),v_price;
  end if;

  insert into public.orders(
    user_id,product_id,player_id,player_name,payment_method,payment_reference,status,payment_source,
    provider_product_id,provider_region,player_id_validation_token,wallet_request_id
  ) values (
    v_uid,v_product.id,trim(p_player_id),trim(coalesce(p_player_name,'')),
    'Saldo de Tienda El Castillo','', 'pending','wallet',
    v_product.provider_product_id,v_product.provider_region,p_player_id_validation_token,p_request_id
  ) returning * into v_order;

  insert into public.wallet_transactions(user_id,order_id,kind,amount,currency,description)
  values(v_uid,v_order.id,'purchase',v_price,'USD','Compra del pedido '||v_order.order_code);

  update public.orders
  set status='processing',paid_at=now(),payment_confirmed_by=v_uid,payment_confirmed_at=now()
  where id=v_order.id and user_id=v_uid;

  return jsonb_build_object(
    'order_id',v_order.id,'order_code',v_order.order_code,'price',v_price,
    'currency','USD','balance',private.wallet_balance(v_uid,'USD'),
    'status','processing','already_processed',false
  );
end;
$function$;

revoke all on function public.create_wallet_order(uuid,text,text,uuid,uuid) from public,anon;
grant execute on function public.create_wallet_order(uuid,text,text,uuid,uuid) to authenticated;

create or replace function public.submit_payment_proof(
 p_order_id uuid,p_proof_path text,p_reference text,p_sender_phone text,p_reported_amount numeric
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
 v_uid uuid:=auth.uid();
 v_order public.orders%rowtype;
 v_reference text:=upper(nullif(regexp_replace(trim(coalesce(p_reference,'')),'[[:space:]]+','','g'),''));
 v_phone text:=regexp_replace(trim(coalesce(p_sender_phone,'')),'[^0-9+]','','g');
 v_phone_digits text:=regexp_replace(coalesce(p_sender_phone,''),'[^0-9]','','g');
begin
 if v_uid is null then raise exception 'Debes iniciar sesión para enviar el comprobante.'; end if;
 if p_order_id is null or p_proof_path is null then raise exception 'Faltan datos del comprobante.'; end if;
 select * into v_order from public.orders where id=p_order_id and user_id=v_uid for update;
 if not found then raise exception 'No encontramos ese pedido en tu cuenta.'; end if;
 if v_order.payment_source<>'direct' then raise exception 'Este pedido no admite comprobantes externos.'; end if;
 if v_order.status<>'pending' or v_order.proof_path is not null then
  raise exception 'El pedido ya fue enviado a verificación y no admite más cambios. Contacta con la tienda si necesitas ayuda.';
 end if;
 if not exists(
  select 1 from public.payment_methods pm
  where pm.name=v_order.payment_method and pm.active=true
    and nullif(trim(coalesce(pm.instructions,'')),'') is not null
 ) then
  raise exception 'El método de pago no está activo o no tiene instrucciones configuradas. Contacta con la tienda.';
 end if;
 if v_order.payment_method in ('Transferencia CUP','Saldo móvil') then
  if v_phone_digits !~ '^[0-9]{8,15}$' or v_phone !~ '^[+]?[0-9]{8,15}$' then
   raise exception 'Escribe un número móvil válido desde el que realizaste el pago.';
  end if;
 end if;

 if v_order.payment_method='Transferencia CUP' then
  if v_reference is null or length(v_reference)<3 or length(v_reference)>100 then
   raise exception 'Escribe el número de transferencia.';
  end if;
  if p_reported_amount is not null then raise exception 'No envíes un importe manual para la transferencia bancaria.'; end if;
  perform pg_advisory_xact_lock(hashtextextended('castle-payment-reference:CUP:'||v_reference,0));
  if exists(
   select 1 from public.orders o
   where o.id<>p_order_id and o.payment_method='Transferencia CUP'
     and upper(regexp_replace(coalesce(o.payment_reference,''),'[[:space:]]+','','g'))=v_reference
     and o.status in ('payment_review','processing','completed','rejected')
  ) then raise exception 'Ese número de transferencia ya fue utilizado en otro pedido.'; end if;
  if exists(
   select 1 from public.wallet_deposits d
   where d.payment_method='Transferencia CUP'
     and upper(regexp_replace(coalesce(d.payment_reference,''),'[[:space:]]+','','g'))=v_reference
  ) then raise exception 'Ese número de transferencia ya fue utilizado en un depósito de wallet.'; end if;

 elsif v_order.payment_method='Saldo móvil' then
  if p_reported_amount is null or p_reported_amount<=0 then raise exception 'Escribe el importe de saldo que enviaste.'; end if;
  if abs(p_reported_amount-v_order.price)>0.01 then
   raise exception 'El importe enviado debe coincidir exactamente con el precio del paquete: %.',v_order.price;
  end if;
  if v_reference is not null then raise exception 'El saldo móvil no utiliza número de transferencia bancaria.'; end if;

 elsif v_order.payment_method='USDT' then
  if v_reference is null or v_reference !~ '^[A-Fa-f0-9]{64}$' then
   raise exception 'Escribe el hash/TxID válido de 64 caracteres hexadecimales.';
  end if;
  if p_reported_amount is null or p_reported_amount<=0 then raise exception 'Escribe la cantidad exacta de USDT que enviaste.'; end if;
  if abs(p_reported_amount-v_order.price)>0.000001 then
   raise exception 'La cantidad de USDT debe coincidir exactamente con el precio del paquete: %.',v_order.price;
  end if;
  perform pg_advisory_xact_lock(hashtextextended('castle-payment-reference:USDT:'||lower(v_reference),0));
  if exists(
   select 1 from public.orders o
   where o.id<>p_order_id and o.payment_method='USDT'
     and lower(coalesce(o.payment_reference,''))=lower(v_reference)
     and o.status in ('payment_review','processing','completed','rejected')
  ) then raise exception 'Ese hash/TxID USDT ya fue utilizado en otro pedido.'; end if;
  if exists(
   select 1 from public.wallet_deposits d
   where d.payment_method='USDT' and lower(coalesce(d.txid,''))=lower(v_reference)
  ) then raise exception 'Ese hash/TxID ya fue utilizado en un depósito de wallet.'; end if;
 else
  raise exception 'Este método de pago todavía no admite comprobantes.';
 end if;

 if p_proof_path !~ ('^'||v_uid::text||'/'||p_order_id::text||'/[a-f0-9-]{36}[.](jpg|jpeg|png|webp)$') then
  raise exception 'La ruta del comprobante no es válida.';
 end if;
 if not exists(select 1 from storage.objects so where so.bucket_id='payment-proofs' and so.name=p_proof_path) then
  raise exception 'No encontramos la imagen subida. Inténtalo de nuevo.';
 end if;
 update public.orders
 set proof_path=p_proof_path,
  payment_reference=case when v_order.payment_method in ('Transferencia CUP','USDT') then v_reference else null end,
  payment_sender_phone=case when v_order.payment_method='USDT' then null else nullif(v_phone,'') end,
  payment_reported_amount=case when v_order.payment_method in ('Saldo móvil','USDT') then p_reported_amount else null end,
  status='payment_review'
 where id=p_order_id and user_id=v_uid and status='pending' and proof_path is null;
 if not found then raise exception 'El pedido cambió de estado y ya no admite cambios.'; end if;
 return jsonb_build_object('order_id',v_order.id,'order_code',v_order.order_code,'status','payment_review');
end;
$function$;

revoke all on function public.submit_payment_proof(uuid,text,text,text,numeric) from public,anon;
grant execute on function public.submit_payment_proof(uuid,text,text,text,numeric) to authenticated;
