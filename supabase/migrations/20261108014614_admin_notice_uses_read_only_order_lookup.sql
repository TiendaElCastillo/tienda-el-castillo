create or replace function public.admin_send_user_notification(
  p_user_id uuid,
  p_order_id uuid,
  p_title text,
  p_message text
) returns uuid
language plpgsql
security invoker
set search_path to ''
as $function$
declare
  v_order_user uuid;
  v_id uuid;
  v_title text := btrim(coalesce(p_title,''));
  v_message text := btrim(coalesce(p_message,''));
begin
  if auth.uid() is null or not private.is_admin() then
    raise exception 'No tienes permiso para enviar avisos.';
  end if;
  if p_user_id is null or length(v_title) not between 1 and 100
     or length(v_message) not between 3 and 1000 then
    raise exception 'El aviso debe tener un título y un mensaje de 3 a 1000 caracteres.';
  end if;
  if p_order_id is not null then
    -- Read only: authenticated admins have SELECT permission, not direct UPDATE.
    select o.user_id into v_order_user
    from public.orders o where o.id=p_order_id;
    if not found or v_order_user <> p_user_id then
      raise exception 'El pedido no pertenece a ese cliente.';
    end if;
  end if;
  insert into public.user_notifications(user_id,order_id,kind,title,message,created_by)
  values(p_user_id,p_order_id,'admin_message',v_title,v_message,auth.uid())
  returning id into v_id;
  return v_id;
end;
$function$;
revoke all on function public.admin_send_user_notification(uuid,uuid,text,text) from public, anon;
grant execute on function public.admin_send_user_notification(uuid,uuid,text,text) to authenticated;
