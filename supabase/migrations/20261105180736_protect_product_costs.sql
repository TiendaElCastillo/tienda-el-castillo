create schema if not exists private;
create table if not exists private.product_costs (
  product_id uuid primary key references public.products(id) on delete cascade,
  cost numeric not null default 0 check (cost >= 0),
  updated_at timestamptz not null default now()
);
insert into private.product_costs(product_id,cost)
select id,coalesce(cost,0) from public.products
on conflict (product_id) do update set cost=excluded.cost, updated_at=now();
revoke all on schema private from public, anon, authenticated;
revoke all on table private.product_costs from public, anon, authenticated;
grant usage on schema private to service_role;
grant select,insert,update,delete on table private.product_costs to service_role;
revoke select (cost) on public.products from anon, authenticated;
revoke insert (cost) on public.products from anon, authenticated;
revoke update (cost) on public.products from anon, authenticated;