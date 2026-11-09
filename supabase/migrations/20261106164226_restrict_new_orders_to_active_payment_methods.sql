
drop policy if exists "Pedidos: insertar propio o admin" on public.orders;

create policy "Pedidos: insertar propio o admin"
on public.orders
for insert
to authenticated
with check (
  (select private.is_admin())
  or (
    user_id = (select auth.uid())
    and status = 'pending'
    and payment_source = 'direct'
    and payment_method in ('Transferencia CUP', 'Saldo móvil')
  )
);
