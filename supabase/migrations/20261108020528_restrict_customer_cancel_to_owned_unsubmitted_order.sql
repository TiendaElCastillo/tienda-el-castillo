-- Restrict customer cancellation to an owned, unpaid direct order with no provider submission.
-- Only grant UPDATE on status; RLS permits only the transition from pending to cancelled.
grant update(status) on table public.orders to authenticated;

drop policy if exists "Customers cancel own pending orders without proof" on public.orders;
create policy "Customers cancel own pending orders without proof"
on public.orders
for update
to authenticated
using (
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
with check (
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
);

create or replace function public.cancel_own_unsubmitted_order(p_order_id uuid)
returns jsonb
language plpgsql
security invoker
set search_path to ''
as $function$
declare
  v_order public.orders%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Debes iniciar sesión para cancelar este pedido.';
  end if;
  if p_order_id is null then
    raise exception 'No se indicó el pedido que deseas cancelar.';
  end if;

  select * into v_order
  from public.orders
  where id = p_order_id
    and user_id = auth.uid()
  for update;

  if not found then
    raise exception 'No encontramos ese pedido en tu cuenta.';
  end if;

  if v_order.payment_source <> 'direct'
     or v_order.status <> 'pending'
     or v_order.proof_path is not null
     or v_order.paid_at is not null
     or v_order.payment_confirmed_at is not null
     or v_order.central_one_order_id is not null
     or v_order.central_one_submitted_at is not null
     or v_order.central_one_idempotency_key is not null
     or (v_order.central_one_status is not null
         and v_order.central_one_status <> 'not_submitted') then
    raise exception 'Este pedido ya tiene comprobante, pago o actividad de recarga y no puede cancelarse desde tu cuenta.';
  end if;

  update public.orders
  set status = 'cancelled'
  where id = p_order_id
    and user_id = auth.uid()
    and status = 'pending'
    and proof_path is null;

  if not found then
    raise exception 'El pedido cambió de estado y ya no puede cancelarse.';
  end if;

  return jsonb_build_object(
    'order_id', v_order.id,
    'order_code', v_order.order_code,
    'status', 'cancelled'
  );
end;
$function$;

revoke all on function public.cancel_own_unsubmitted_order(uuid) from public, anon;
grant execute on function public.cancel_own_unsubmitted_order(uuid) to authenticated;
