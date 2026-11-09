create table if not exists public.wallet_transactions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete restrict,
  order_id uuid references public.orders(id) on delete restrict,
  kind text not null check (kind in ('deposit','purchase','refund','adjustment')),
  amount numeric(14,2) not null check (amount > 0),
  currency text not null default 'CUP' check (currency in ('CUP','USDT')),
  description text not null default '',
  created_at timestamptz not null default now()
);
alter table public.wallet_transactions enable row level security;
drop policy if exists "wallet transactions own or admin read" on public.wallet_transactions;
create policy "wallet transactions own or admin read" on public.wallet_transactions for select to authenticated using (user_id=(select auth.uid()) or private.is_admin());
revoke insert, update, delete on public.wallet_transactions from anon, authenticated;
grant select on public.wallet_transactions to authenticated;

alter table public.orders add column if not exists payment_source text not null default 'direct' check (payment_source in ('direct','wallet'));
alter table public.orders add column if not exists proof_path text;
alter table public.orders add column if not exists paid_at timestamptz;

create or replace function private.wallet_balance(p_user_id uuid, p_currency text default 'CUP')
returns numeric language sql stable security definer set search_path=''
as $$
 select coalesce(sum(case when kind in ('deposit','refund','adjustment') then amount else -amount end),0)
 from public.wallet_transactions where user_id=p_user_id and currency=p_currency
$$;
revoke all on function private.wallet_balance(uuid,text) from public;
grant execute on function private.wallet_balance(uuid,text) to authenticated;

create or replace function public.create_wallet_order(
 p_product_id uuid, p_player_id text, p_player_name text default ''
) returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_uid uuid:=auth.uid(); v_product public.products%rowtype; v_balance numeric; v_order public.orders%rowtype;
begin
 if v_uid is null then raise exception 'Debes iniciar sesión.'; end if;
 if length(trim(coalesce(p_player_id,'')))<3 or length(trim(p_player_id))>64 then raise exception 'ID de jugador no válido.'; end if;
 select * into v_product from public.products where id=p_product_id and active=true;
 if not found or coalesce(v_product.price_transfer,0)<=0 then raise exception 'Paquete no disponible.'; end if;
 perform pg_advisory_xact_lock(hashtextextended(v_uid::text,0));
 v_balance:=private.wallet_balance(v_uid,'CUP');
 if v_balance < v_product.price_transfer then raise exception 'Saldo insuficiente. Disponible: % CUP',v_balance; end if;
 insert into public.orders(user_id,product_id,player_id,player_name,payment_method,payment_reference,status,payment_source)
 values(v_uid,v_product.id,trim(p_player_id),trim(coalesce(p_player_name,'')),'Billetera CUP','', 'processing','wallet')
 returning * into v_order;
 insert into public.wallet_transactions(user_id,order_id,kind,amount,currency,description)
 values(v_uid,v_order.id,'purchase',v_order.price,'CUP','Pago del pedido '||v_order.order_code);
 return jsonb_build_object('order_id',v_order.id,'order_code',v_order.order_code,'price',v_order.price,'balance',private.wallet_balance(v_uid,'CUP'));
end $$;
revoke all on function public.create_wallet_order(uuid,text,text) from public, anon;
grant execute on function public.create_wallet_order(uuid,text,text) to authenticated;