create or replace function public.guard_order_status_update()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
 if new.status is distinct from old.status then
  if old.payment_source='direct'
     and new.status in ('payment_review','processing','completed')
     and new.proof_path is null then
   raise exception 'Este pedido no puede avanzar sin un comprobante de pago válido.';
  end if;
  if old.payment_source='direct'
     and old.status='payment_review'
     and new.status='processing'
     and new.paid_at is null then
   new.paid_at:=now();
  end if;
  if old.payment_source='wallet'
     and new.status='processing'
     and new.paid_at is null then
   new.paid_at:=now();
  end if;
 end if;
 return new;
end;
$$;
drop trigger if exists guard_order_status_before_update on public.orders;
create trigger guard_order_status_before_update
before update of status on public.orders
for each row execute function public.guard_order_status_update();