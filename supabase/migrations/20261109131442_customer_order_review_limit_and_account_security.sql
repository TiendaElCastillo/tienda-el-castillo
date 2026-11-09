create table if not exists private.customer_account_controls (
  user_id uuid primary key references auth.users(id) on delete cascade,
  is_blocked boolean not null default false,
  block_reason text,
  blocked_at timestamptz,
  blocked_by uuid references auth.users(id) on delete set null,
  warning_count integer not null default 0 check (warning_count >= 0),
  last_warning_at timestamptz,
  updated_at timestamptz not null default now()
);

create table if not exists private.customer_security_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  actor_id uuid not null references auth.users(id),
  order_id uuid references public.orders(id) on delete set null,
  event_type text not null check (event_type in ('warning','blocked','unblocked')),
  message text not null default '',
  created_at timestamptz not null default now()
);

alter table private.customer_account_controls enable row level security;
alter table private.customer_security_events enable row level security;
revoke all on table private.customer_account_controls from anon, authenticated;
revoke all on table private.customer_security_events from anon, authenticated;

create index if not exists orders_user_direct_open_review_idx
  on public.orders(user_id, created_at desc)
  where payment_source = 'direct' and status in ('pending','payment_review');

create or replace function private.enforce_customer_order_limit()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_role text;
  v_blocked boolean := false;
  v_open_count integer := 0;
begin
  if new.user_id is null then
    raise exception 'No se pudo identificar la cuenta del pedido.';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(new.user_id::text, 0)
  );

  select p.role into v_role
  from public.profiles p
  where p.id = new.user_id;

  if v_role = 'admin' then
    return new;
  end if;

  select coalesce(c.is_blocked, false) into v_blocked
  from private.customer_account_controls c
  where c.user_id = new.user_id;

  if coalesce(v_blocked, false) then
    raise exception 'Tu cuenta tiene restringida la creación de nuevos pedidos. Contacta con la administración de Tienda El Castillo.';
  end if;

  if coalesce(new.payment_source, 'direct') = 'direct' then
    select count(*)::integer into v_open_count
    from public.orders o
    where o.user_id = new.user_id
      and o.payment_source = 'direct'
      and o.status in ('pending','payment_review');

    if v_open_count >= 4 then
      raise exception 'Has alcanzado el límite de 4 operaciones en revisión por cuenta. Espera a que la tienda resuelva alguna antes de crear otro pedido.';
    end if;
  end if;

  return new;
end;
$function$;

revoke all on function private.enforce_customer_order_limit() from public, anon, authenticated;

drop trigger if exists zzz_enforce_customer_order_limit on public.orders;
create trigger zzz_enforce_customer_order_limit
before insert on public.orders
for each row execute function private.enforce_customer_order_limit();

create or replace function public.admin_warn_customer(
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
    user_id, warning_count, last_warning_at, updated_at
  )
  values (p_user_id, 1, now(), now())
  on conflict (user_id) do update
    set warning_count = private.customer_account_controls.warning_count + 1,
        last_warning_at = now(),
        updated_at = now();

  insert into public.user_notifications(user_id,order_id,kind,title,message,created_by)
  values (
    p_user_id,p_order_id,'admin_message',
    'Advertencia de Tienda El Castillo',
    v_message,auth.uid()
  )
  returning id into v_notification_id;

  insert into private.customer_security_events(
    user_id,actor_id,order_id,event_type,message
  )
  values (p_user_id,auth.uid(),p_order_id,'warning',v_message);

  return v_notification_id;
end;
$function$;

create or replace function public.admin_set_customer_blocked(
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
    values (p_user_id,true,v_reason,now(),auth.uid(),now())
    on conflict (user_id) do update
      set is_blocked = true,
          block_reason = excluded.block_reason,
          blocked_at = now(),
          blocked_by = auth.uid(),
          updated_at = now();

    v_notice := 'La administración ha restringido la creación de nuevos pedidos en tu cuenta. Motivo: ' ||
      left(v_reason,700) ||
      ' Si consideras que se trata de un error, comunícate con Tienda El Castillo para solicitar una revisión.';

    insert into public.user_notifications(user_id,kind,title,message,created_by)
    values (p_user_id,'admin_message','Restricción de compras en tu cuenta',left(v_notice,1000),auth.uid());

    insert into private.customer_security_events(user_id,actor_id,event_type,message)
    values (p_user_id,auth.uid(),'blocked',v_reason);
  else
    insert into private.customer_account_controls(user_id,is_blocked,updated_at)
    values (p_user_id,false,now())
    on conflict (user_id) do update
      set is_blocked = false,
          block_reason = null,
          blocked_at = null,
          blocked_by = null,
          updated_at = now();

    v_notice := 'La restricción de tu cuenta ha sido retirada. Ya puedes volver a realizar pedidos en Tienda El Castillo.';

    insert into public.user_notifications(user_id,kind,title,message,created_by)
    values (p_user_id,'admin_message','Tu cuenta ha sido reactivada',v_notice,auth.uid());

    insert into private.customer_security_events(user_id,actor_id,event_type,message)
    values (p_user_id,auth.uid(),'unblocked','Cuenta desbloqueada por la administración.');
  end if;

  return jsonb_build_object('ok',true,'user_id',p_user_id,'blocked',p_blocked);
end;
$function$;

create or replace function public.admin_get_user_security_summary(p_user_ids uuid[])
returns table (
  user_id uuid,
  is_blocked boolean,
  block_reason text,
  warning_count integer,
  open_review_count integer
)
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if auth.uid() is null or not private.is_admin() then
    raise exception 'No tienes permiso para consultar la seguridad de las cuentas.';
  end if;
  if coalesce(pg_catalog.cardinality(p_user_ids),0) > 500 then
    raise exception 'Consulta demasiadas cuentas a la vez.';
  end if;

  return query
  with requested as (
    select distinct x.user_id
    from pg_catalog.unnest(coalesce(p_user_ids, array[]::uuid[])) as x(user_id)
  )
  select
    requested.user_id,
    coalesce(c.is_blocked,false),
    c.block_reason,
    coalesce(c.warning_count,0)::integer,
    count(o.id)::integer
  from requested
  left join private.customer_account_controls c
    on c.user_id = requested.user_id
  left join public.orders o
    on o.user_id = requested.user_id
   and o.payment_source = 'direct'
   and o.status in ('pending','payment_review')
  group by requested.user_id,c.is_blocked,c.block_reason,c.warning_count;
end;
$function$;

revoke all on function public.admin_warn_customer(uuid,uuid,text) from public, anon, authenticated;
revoke all on function public.admin_set_customer_blocked(uuid,boolean,text) from public, anon, authenticated;
revoke all on function public.admin_get_user_security_summary(uuid[]) from public, anon, authenticated;
grant execute on function public.admin_warn_customer(uuid,uuid,text) to authenticated;
grant execute on function public.admin_set_customer_blocked(uuid,boolean,text) to authenticated;
grant execute on function public.admin_get_user_security_summary(uuid[]) to authenticated;
