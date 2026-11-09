
create schema if not exists private;
revoke all on schema private from public, anon;
grant usage on schema private to authenticated;

create or replace function private.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.profiles p
    where p.id = (select auth.uid())
      and p.role = 'admin'
  );
$$;

revoke all on function private.is_admin() from public, anon, authenticated;
grant execute on function private.is_admin() to authenticated;

drop policy if exists "Pedidos: borrar solo admin" on public.orders;
drop policy if exists "Pedidos: insertar propio o admin" on public.orders;
drop policy if exists "Pedidos: lectura propia o admin" on public.orders;
drop policy if exists "Pedidos: actualizar solo admin" on public.orders;
create policy "Pedidos: borrar solo admin" on public.orders for delete to authenticated using ((select private.is_admin()));
create policy "Pedidos: insertar propio o admin" on public.orders for insert to authenticated with check ((select private.is_admin()) or (user_id=(select auth.uid()) and status='pending'));
create policy "Pedidos: lectura propia o admin" on public.orders for select to authenticated using (user_id=(select auth.uid()) or (select private.is_admin()));
create policy "Pedidos: actualizar solo admin" on public.orders for update to authenticated using ((select private.is_admin())) with check ((select private.is_admin()));

drop policy if exists "Productos: lectura autenticados" on public.products;
drop policy if exists "Productos: insertar admin" on public.products;
drop policy if exists "Productos: actualizar admin" on public.products;
drop policy if exists "Productos: borrar admin" on public.products;
create policy "Productos: lectura autenticados" on public.products for select to authenticated using (active=true or (select private.is_admin()));
create policy "Productos: insertar admin" on public.products for insert to authenticated with check ((select private.is_admin()));
create policy "Productos: actualizar admin" on public.products for update to authenticated using ((select private.is_admin())) with check ((select private.is_admin()));
create policy "Productos: borrar admin" on public.products for delete to authenticated using ((select private.is_admin()));

drop policy if exists "Métodos: lectura autenticados" on public.payment_methods;
drop policy if exists "Métodos: insertar admin" on public.payment_methods;
drop policy if exists "Métodos: actualizar admin" on public.payment_methods;
drop policy if exists "Métodos: borrar admin" on public.payment_methods;
create policy "Métodos: lectura autenticados" on public.payment_methods for select to authenticated using (active=true or (select private.is_admin()));
create policy "Métodos: insertar admin" on public.payment_methods for insert to authenticated with check ((select private.is_admin()));
create policy "Métodos: actualizar admin" on public.payment_methods for update to authenticated using ((select private.is_admin())) with check ((select private.is_admin()));
create policy "Métodos: borrar admin" on public.payment_methods for delete to authenticated using ((select private.is_admin()));

drop policy if exists "Leer perfil propio o admin" on public.profiles;
create policy "Leer perfil propio o admin" on public.profiles for select to authenticated using (id=(select auth.uid()) or (select private.is_admin()));

drop function if exists public.is_admin();
