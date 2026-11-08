-- Consolidate the admin and customer-cancellation UPDATE policies on orders.
-- Preserves the same authorization predicates while avoiding two permissive UPDATE policies.
drop policy if exists "Customers cancel own pending orders without proof" on public.orders;
drop policy if exists "Pedidos: actualizar solo admin" on public.orders;

create policy "Orders update admin or own unsubmitted cancel"
on public.orders
for update
to authenticated
using (
  (select private.is_admin())
  or (
    user_id = (select auth.uid())
    and payment_source = 'direct'
    and status = 'pending'
    and proof_path is null
    and paid_at is null
    and payment_confirmed_at is null
    and central_one_order_id is null
    and central_one_submitted_at is null
    and central_one_idempotency_key is null
    and (central_one_status is null or central_one_status = 'not_submitted')
  )
)
with check (
  (select private.is_admin())
  or (
    user_id = (select auth.uid())
    and payment_source = 'direct'
    and status = 'cancelled'
    and proof_path is null
    and paid_at is null
    and payment_confirmed_at is null
    and central_one_order_id is null
    and central_one_submitted_at is null
    and central_one_idempotency_key is null
    and (central_one_status is null or central_one_status = 'not_submitted')
  )
);
