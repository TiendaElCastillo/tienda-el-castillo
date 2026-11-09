
alter table public.orders
  add column if not exists payment_confirmed_by uuid references auth.users(id),
  add column if not exists payment_confirmed_at timestamptz;

create or replace function public.admin_update_order_status(p_order_id uuid, p_status text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_order public.orders%rowtype;
begin
  if auth.uid() is null or not private.is_admin() then
    raise exception 'No tienes permiso para administrar pedidos.';
  end if;
  if p_order_id is null or p_status not in ('processing','rejected') then
    raise exception 'Acción de pedido no válida.';
  end if;

  select * into v_order
  from public.orders
  where id = p_order_id
  for update;

  if not found then
    raise exception 'No encontramos ese pedido.';
  end if;

  if p_status = 'processing' then
    if v_order.status <> 'payment_review' then
      raise exception 'Solo puedes autorizar pedidos cuyo pago está en revisión.';
    end if;
    if v_order.payment_source <> 'direct' or v_order.proof_path is null then
      raise exception 'El pedido no tiene un comprobante externo válido.';
    end if;
    if not exists (
      select 1 from public.payment_methods pm
      where pm.name = v_order.payment_method and pm.active = true
    ) then
      raise exception 'El método de pago ya no está activo.';
    end if;

    update public.orders
    set status = 'processing',
        paid_at = now(),
        payment_confirmed_by = auth.uid(),
        payment_confirmed_at = now()
    where id = p_order_id;
  else
    if v_order.status not in ('pending','payment_review') then
      raise exception 'Este pedido ya no se puede rechazar desde este estado.';
    end if;
    update public.orders
    set status = 'rejected',
        admin_notes = coalesce(admin_notes,'') || case when admin_notes is null or admin_notes='' then '' else E'\n' end || 'Rechazado por administrador el ' || now()::text
    where id = p_order_id;
  end if;

  return jsonb_build_object(
    'id', p_order_id,
    'status', p_status,
    'payment_confirmed_by', case when p_status='processing' then auth.uid() else null end
  );
end;
$$;

revoke all on function public.admin_update_order_status(uuid,text) from public, anon;
grant execute on function public.admin_update_order_status(uuid,text) to authenticated;

revoke update on table public.orders from authenticated, anon;
