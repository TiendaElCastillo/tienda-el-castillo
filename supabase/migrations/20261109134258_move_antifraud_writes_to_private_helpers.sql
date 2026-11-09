create or replace function private.admin_warn_customer_impl(
  p_user_id uuid,
  p_order_id uuid,
  p_message text
)
returns uuid
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_message text := btrim(coalesce(p_message,''));
  v_notification_id uuid;
begin
  if auth.uid() is null or not private.is_admin() then
    raise exception 'No tienes permiso para advertir a esta cuenta.';
  end if;
  if p_user_id is null or length(v_message) not between 3 and 1000 then
    raise exception 'Escribe una advertencia de entre 3 y 1000 caracteres.';
  end if;
  if not exists (
    select 1 from public.profiles p
    where p.id = p_user_id and p.role = 'customer'
  ) then
    raise exception 'No se encontró una cuenta de cliente válida.';
  end if;
  if p_order_id is not null and not exists (
    select 1 from public.orders o
    where o.id = p_order_id and o.user_id = p_user_id
  ) then
    raise exception 'El pedido no pertenece a esa cuenta.';
  end if;

  insert into private.customer_account_controls(
    user_id,warning_count,last_warning_at,updated_at
  )
  values(p_user_id,1,now(),now())
  on conflict(user_id) do update
    set warning_count=private.customer_account_controls.warning_count+1,
        last_warning_at=now(),
        updated_at=now();

  insert into public.user_notifications(user_id,order_id,kind,title,message,created_by)
  values(p_user_id,p_order_id,'admin_message','Advertencia de Tienda El Castillo',v_message,auth.uid())
  returning id into v_notification_id;

  insert into private.customer_security_events(user_id,actor_id,order_id,event_type,message)
  values(p_user_id,auth.uid(),p_order_id,'warning',v_message);

  return v_notification_id;
end;
$function$;

create or replace function private.admin_set_customer_blocked_impl(
  p_user_id uuid,
  p_blocked boolean,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_reason text := btrim(coalesce(p_reason,''));
  v_notice text;
begin
  if auth.uid() is null or not private.is_admin() then
    raise exception 'No tienes permiso para restringir esta cuenta.';
  end if;
  if p_user_id is null or p_blocked is null then
    raise exception 'Faltan los datos de la cuenta o de la acción.';
  end if;
  if not exists (
    select 1 from public.profiles p
    where p.id = p_user_id and p.role = 'customer'
  ) then
    raise exception 'No se encontró una cuenta de cliente válida. Las cuentas administrativas no se pueden bloquear desde aquí.';
  end if;

  if p_blocked then
    if length(v_reason) < 5 then
      raise exception 'Escribe un motivo de bloqueo de al menos 5 caracteres.';
    end if;
    insert into private.customer_account_controls(
      user_id,is_blocked,block_reason,blocked_at,blocked_by,updated_at
    )
    values(p_user_id,true,v_reason,now(),auth.uid(),now())
    on conflict(user_id) do update
      set is_blocked=true,
          block_reason=excluded.block_reason,
          blocked_at=now(),
          blocked_by=auth.uid(),
          updated_at=now();

    v_notice := 'La administración ha restringido la creación de nuevos pedidos en tu cuenta. Motivo: ' ||
      left(v_reason,700) ||
      ' Si consideras que se trata de un error, comunícate con Tienda El Castillo para solicitar una revisión.';

    insert into public.user_notifications(user_id,kind,title,message,created_by)
    values(p_user_id,'admin_message','Restricción de compras en tu cuenta',left(v_notice,1000),auth.uid());

    insert into private.customer_security_events(user_id,actor_id,event_type,message)
    values(p_user_id,auth.uid(),'blocked',v_reason);
  else
    insert into private.customer_account_controls(user_id,is_blocked,updated_at)
    values(p_user_id,false,now())
    on conflict(user_id) do update
      set is_blocked=false,
          block_reason=null,
          blocked_at=null,
          blocked_by=null,
          updated_at=now();

    v_notice := 'La restricción de tu cuenta ha sido retirada. Ya puedes volver a realizar pedidos en Tienda El Castillo.';

    insert into public.user_notifications(user_id,kind,title,message,created_by)
    values(p_user_id,'admin_message','Tu cuenta ha sido reactivada',v_notice,auth.uid());

    insert into private.customer_security_events(user_id,actor_id,event_type,message)
    values(p_user_id,auth.uid(),'unblocked','Cuenta desbloqueada por la administración.');
  end if;

  return jsonb_build_object('ok',true,'user_id',p_user_id,'blocked',p_blocked);
end;
$function$;

revoke all on function private.admin_warn_customer_impl(uuid,uuid,text) from public,anon,authenticated;
revoke all on function private.admin_set_customer_blocked_impl(uuid,boolean,text) from public,anon,authenticated;
grant execute on function private.admin_warn_customer_impl(uuid,uuid,text) to authenticated;
grant execute on function private.admin_set_customer_blocked_impl(uuid,boolean,text) to authenticated;

create or replace function public.admin_warn_customer(
  p_user_id uuid,p_order_id uuid,p_message text
)
returns uuid
language sql
security invoker
set search_path to ''
as $function$
  select private.admin_warn_customer_impl(p_user_id,p_order_id,p_message);
$function$;

create or replace function public.admin_set_customer_blocked(
  p_user_id uuid,p_blocked boolean,p_reason text default null
)
returns jsonb
language sql
security invoker
set search_path to ''
as $function$
  select private.admin_set_customer_blocked_impl(p_user_id,p_blocked,p_reason);
$function$;

revoke all on function public.admin_warn_customer(uuid,uuid,text) from public,anon,authenticated;
revoke all on function public.admin_set_customer_blocked(uuid,boolean,text) from public,anon,authenticated;
grant execute on function public.admin_warn_customer(uuid,uuid,text) to authenticated;
grant execute on function public.admin_set_customer_blocked(uuid,boolean,text) to authenticated;
