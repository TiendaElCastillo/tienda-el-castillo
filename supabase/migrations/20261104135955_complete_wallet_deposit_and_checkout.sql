create table if not exists public.wallet_deposits (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete restrict,
  amount numeric(14,2) not null check (amount > 0),
  currency text not null default 'CUP' check (currency = 'CUP'),
  payment_method text not null check (payment_method in ('Transferencia CUP','Saldo móvil')),
  payment_reference text,
  status text not null default 'pending' check (status in ('pending','payment_review','approved','rejected')),
  proof_path text,
  admin_notes text,
  created_at timestamptz not null default now(),
  reviewed_at timestamptz
);
alter table public.wallet_deposits enable row level security;
drop policy if exists "wallet deposits read own or admin" on public.wallet_deposits;
create policy "wallet deposits read own or admin"
on public.wallet_deposits for select to authenticated
using (user_id = (select auth.uid()) or (select private.is_admin()));
drop policy if exists "wallet deposits insert own pending" on public.wallet_deposits;
create policy "wallet deposits insert own pending"
on public.wallet_deposits for insert to authenticated
with check (user_id = (select auth.uid()) and status = 'pending' and currency = 'CUP' and proof_path is null);
grant select, insert on public.wallet_deposits to authenticated;
revoke update, delete on public.wallet_deposits from anon, authenticated;

create or replace function public.validate_wallet_deposit_request()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
 if auth.uid() is null or new.user_id is distinct from auth.uid() then
  raise exception 'No autorizado para crear este depósito.';
 end if;
 if new.amount is null or new.amount <= 0 then
  raise exception 'El importe del depósito debe ser mayor que cero.';
 end if;
 if new.currency <> 'CUP' then
  raise exception 'Por ahora la billetera solo admite CUP.';
 end if;
 if new.payment_method not in ('Transferencia CUP','Saldo móvil') then
  raise exception 'Método de pago no válido.';
 end if;
 if not exists (select 1 from public.payment_methods pm where pm.name=new.payment_method and pm.active=true) then
  raise exception 'El método de pago no está disponible.';
 end if;
 new.status := 'pending';
 new.proof_path := null;
 new.payment_reference := null;
 new.admin_notes := null;
 new.reviewed_at := null;
 new.created_at := now();
 return new;
end;
$$;
drop trigger if exists validate_wallet_deposit_before_insert on public.wallet_deposits;
create trigger validate_wallet_deposit_before_insert
before insert on public.wallet_deposits
for each row execute function public.validate_wallet_deposit_request();

drop policy if exists "Customers upload proof for own pending orders" on storage.objects;
create policy "Customers upload proof for own pending orders"
on storage.objects for insert to authenticated
with check (
 bucket_id='payment-proofs'
 and (storage.foldername(name))[1]=(select auth.uid())::text
 and (
  exists (
   select 1 from public.orders o
   where o.id::text=(storage.foldername(name))[2]
     and o.user_id=(select auth.uid())
     and o.status in ('pending','payment_review')
     and o.payment_source='direct'
  )
  or exists (
   select 1 from public.wallet_deposits d
   where d.id::text=(storage.foldername(name))[2]
     and d.user_id=(select auth.uid())
     and d.status in ('pending','payment_review')
  )
 )
);

create or replace function public.submit_wallet_deposit_proof(
 p_deposit_id uuid,
 p_proof_path text,
 p_reference text default null
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
 v_uid uuid:=auth.uid();
 v_deposit public.wallet_deposits%rowtype;
 v_reference text:=nullif(trim(coalesce(p_reference,'')),'');
begin
 if v_uid is null then raise exception 'Debes iniciar sesión.'; end if;
 select * into v_deposit from public.wallet_deposits
 where id=p_deposit_id and user_id=v_uid for update;
 if not found then raise exception 'No encontramos el depósito en tu cuenta.'; end if;
 if v_deposit.status not in ('pending','payment_review') then raise exception 'Este depósito ya no admite cambios.'; end if;
 if not exists(select 1 from public.payment_methods pm where pm.name=v_deposit.payment_method and pm.active=true) then
  raise exception 'El método de pago ya no está disponible.';
 end if;
 if v_deposit.payment_method='Transferencia CUP' and v_reference is null then
  raise exception 'Escribe el número de transferencia.';
 end if;
 if p_proof_path !~ ('^'||v_uid::text||'/'||p_deposit_id::text||'/[a-f0-9-]{36}[.](jpg|jpeg|png|webp)$') then
  raise exception 'La ruta del comprobante no es válida.';
 end if;
 if not exists(select 1 from storage.objects so where so.bucket_id='payment-proofs' and so.name=p_proof_path) then
  raise exception 'No encontramos la imagen subida.';
 end if;
 update public.wallet_deposits
 set proof_path=p_proof_path,payment_reference=v_reference,status='payment_review'
 where id=p_deposit_id and user_id=v_uid;
 return jsonb_build_object('deposit_id',p_deposit_id,'status','payment_review');
end;
$$;
revoke all on function public.submit_wallet_deposit_proof(uuid,text,text) from public,anon;
grant execute on function public.submit_wallet_deposit_proof(uuid,text,text) to authenticated;

create or replace function public.admin_review_wallet_deposit(
 p_deposit_id uuid,
 p_approve boolean,
 p_note text default null
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
 v_deposit public.wallet_deposits%rowtype;
begin
 if not private.is_admin() then raise exception 'No autorizado.'; end if;
 select * into v_deposit from public.wallet_deposits where id=p_deposit_id for update;
 if not found then raise exception 'Depósito no encontrado.'; end if;
 if v_deposit.status<>'payment_review' or v_deposit.proof_path is null then
  raise exception 'El depósito todavía no tiene comprobante para revisar.';
 end if;
 if p_approve then
  insert into public.wallet_transactions(user_id,kind,amount,currency,description)
  values(v_deposit.user_id,'deposit',v_deposit.amount,'CUP','Depósito aprobado por '+ 'Tienda El Castillo');
  update public.wallet_deposits set status='approved',admin_notes=nullif(trim(coalesce(p_note,'')),''),reviewed_at=now() where id=p_deposit_id;
 else
  update public.wallet_deposits set status='rejected',admin_notes=nullif(trim(coalesce(p_note,'')),''),reviewed_at=now() where id=p_deposit_id;
 end if;
 return jsonb_build_object('deposit_id',p_deposit_id,'status',case when p_approve then 'approved' else 'rejected' end);
end;
$$;
revoke all on function public.admin_review_wallet_deposit(uuid,boolean,text) from public,anon;
grant execute on function public.admin_review_wallet_deposit(uuid,boolean,text) to authenticated;

create or replace function public.validate_order_request()
returns trigger
language plpgsql
set search_path = ''
as $$
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
  if new.payment_method<>'Billetera CUP' then raise exception 'Método de billetera no válido.'; end if;
  final_price:=selected_product.price_transfer;
 elsif coalesce(new.payment_source,'direct')='direct' then
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
 new.payment_reference:=nullif(btrim(coalesce(new.payment_reference,'')),'');
 new.admin_notes:=null;
 new.created_at:=now();
 new.payment_source:=coalesce(new.payment_source,'direct');
 return new;
end;
$$;
drop trigger if exists validate_order_before_insert on public.orders;
create trigger validate_order_before_insert
before insert on public.orders
for each row execute function public.validate_order_request();

drop policy if exists "Pedidos: insertar propio o admin" on public.orders;
create policy "Pedidos: insertar propio o admin"
on public.orders for insert to authenticated
with check (
 (select private.is_admin())
 or (
  user_id=(select auth.uid())
  and status='pending'
  and payment_source='direct'
  and payment_method in ('Transferencia CUP','Saldo móvil','USDT')
 )
);

create or replace function public.create_wallet_order(
 p_product_id uuid,
 p_player_id text,
 p_player_name text default ''
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
 v_uid uuid:=auth.uid();
 v_product public.products%rowtype;
 v_balance numeric;
 v_order public.orders%rowtype;
begin
 if v_uid is null then raise exception 'Debes iniciar sesión.'; end if;
 if length(trim(coalesce(p_player_id,'')))<3 or length(trim(p_player_id))>64 then
  raise exception 'ID de jugador no válido.';
 end if;
 select * into v_product from public.products where id=p_product_id and active=true;
 if not found or coalesce(v_product.price_transfer,0)<=0 then raise exception 'Paquete no disponible para billetera CUP.'; end if;
 perform pg_advisory_xact_lock(hashtextextended(v_uid::text,0));
 v_balance:=private.wallet_balance(v_uid,'CUP');
 if v_balance<v_product.price_transfer then
  raise exception 'Saldo insuficiente. Disponible: % CUP. Necesitas: % CUP.',v_balance,v_product.price_transfer;
 end if;
 insert into public.orders(user_id,product_id,player_id,player_name,payment_method,payment_reference,status,payment_source)
 values(v_uid,v_product.id,trim(p_player_id),trim(coalesce(p_player_name,'')),'Billetera CUP','', 'pending','wallet')
 returning * into v_order;
 insert into public.wallet_transactions(user_id,order_id,kind,amount,currency,description)
 values(v_uid,v_order.id,'purchase',v_order.price,'CUP','Pago del pedido '||v_order.order_code);
 update public.orders set status='processing' where id=v_order.id and user_id=v_uid;
 return jsonb_build_object(
  'order_id',v_order.id,'order_code',v_order.order_code,'price',v_order.price,
  'balance',private.wallet_balance(v_uid,'CUP'),'status','processing'
 );
end;
$$;
revoke all on function public.create_wallet_order(uuid,text,text) from public,anon;
grant execute on function public.create_wallet_order(uuid,text,text) to authenticated;

revoke all on function private.wallet_balance(uuid,text) from public,anon,authenticated;