-- A customer order already created with an active payment method must remain approvable
-- after the administrator later disables that method. New orders remain protected by
-- validate_order_request(), which checks payment_methods.active at insert time.
do $migration$
declare
  v_definition text;
  v_check text := $remove$
    if not exists (
      select 1 from public.payment_methods pm
      where pm.name = v_order.payment_method and pm.active = true
    ) then
      raise exception 'El método de pago ya no está activo.';
    end if;

$remove$;
begin
  select pg_get_functiondef(
    'public.admin_update_order_status(uuid,text)'::regprocedure
  ) into v_definition;

  if position(v_check in v_definition) = 0 then
    raise exception 'No se encontró la comprobación esperada del método activo. Se cancela la migración sin modificar la función.';
  end if;

  execute replace(v_definition, v_check, '');
end;
$migration$;

-- The function itself checks private.is_admin() before any status change.
revoke all on function public.admin_update_order_status(uuid,text) from public, anon;
grant execute on function public.admin_update_order_status(uuid,text) to authenticated;
