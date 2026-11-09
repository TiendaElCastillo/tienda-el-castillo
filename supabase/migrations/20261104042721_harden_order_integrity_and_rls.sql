
-- Keep customer/admin access separated and remove overlapping permissive policies.
drop policy if exists "Administrar pedidos" on public.orders;
drop policy if exists "Ver pedidos propios o admin" on public.orders;
drop policy if exists "Crear pedidos propios" on public.orders;

create policy "Pedidos: lectura propia o admin"
on public.orders for select to authenticated
using (user_id = (select auth.uid()) or (select public.is_admin()));

create policy "Pedidos: insertar propio o admin"
on public.orders for insert to authenticated
with check (
  (select public.is_admin())
  or (user_id = (select auth.uid()) and status = 'pending')
);

create policy "Pedidos: actualizar solo admin"
on public.orders for update to authenticated
using ((select public.is_admin()))
with check ((select public.is_admin()));

create policy "Pedidos: borrar solo admin"
on public.orders for delete to authenticated
using ((select public.is_admin()));

drop policy if exists "Administrar productos" on public.products;
drop policy if exists "Ver productos activos" on public.products;

create policy "Productos: lectura pública activos"
on public.products for select to anon
using (active = true);

create policy "Productos: lectura autenticados"
on public.products for select to authenticated
using (active = true or (select public.is_admin()));

create policy "Productos: insertar admin"
on public.products for insert to authenticated
with check ((select public.is_admin()));

create policy "Productos: actualizar admin"
on public.products for update to authenticated
using ((select public.is_admin()))
with check ((select public.is_admin()));

create policy "Productos: borrar admin"
on public.products for delete to authenticated
using ((select public.is_admin()));

drop policy if exists "Administrar métodos de pago" on public.payment_methods;
drop policy if exists "Ver métodos activos" on public.payment_methods;

create policy "Métodos: lectura pública activos"
on public.payment_methods for select to anon
using (active = true);

create policy "Métodos: lectura autenticados"
on public.payment_methods for select to authenticated
using (active = true or (select public.is_admin()));

create policy "Métodos: insertar admin"
on public.payment_methods for insert to authenticated
with check ((select public.is_admin()));

create policy "Métodos: actualizar admin"
on public.payment_methods for update to authenticated
using ((select public.is_admin()))
with check ((select public.is_admin()));

create policy "Métodos: borrar admin"
on public.payment_methods for delete to authenticated
using ((select public.is_admin()));

create index if not exists orders_user_created_at_idx
on public.orders (user_id, created_at desc);
create index if not exists orders_product_id_idx
on public.orders (product_id);

create or replace function public.validate_order_request()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
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

  case new.payment_method
    when 'Transferencia CUP' then final_price := selected_product.price_transfer;
    when 'Saldo móvil' then final_price := selected_product.price_mobile;
    when 'USDT' then final_price := selected_product.price_usdt;
    else raise exception 'Método de pago no válido.';
  end case;

  if final_price is null or final_price <= 0 then
    raise exception 'Este producto no tiene precio para ese método de pago.';
  end if;

  -- Treat the database catalog as the source of truth; never trust client-submitted totals/status.
  new.game := selected_product.game;
  new.package_name := selected_product.name;
  new.price := final_price;
  new.status := 'pending';
  new.order_code := 'EC-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 10));
  new.player_id := btrim(new.player_id);
  new.player_name := nullif(btrim(coalesce(new.player_name, '')), '');
  new.payment_reference := nullif(btrim(coalesce(new.payment_reference, '')), '');
  new.admin_notes := null;
  new.created_at := now();

  return new;
end;
$$;

revoke all on function public.validate_order_request() from public, anon, authenticated;

drop trigger if exists validate_order_before_insert on public.orders;
create trigger validate_order_before_insert
before insert on public.orders
for each row execute function public.validate_order_request();
