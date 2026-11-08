create table if not exists public.user_notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  order_id uuid null references public.orders(id) on delete set null,
  kind text not null default 'admin_message'
    check (kind in ('admin_message','order_status')),
  title text not null check (length(btrim(title)) between 1 and 100),
  message text not null check (length(btrim(message)) between 1 and 1000),
  created_by uuid null references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  read_at timestamptz null
);

create index if not exists user_notifications_user_created_idx
  on public.user_notifications(user_id, created_at desc);
create index if not exists user_notifications_user_unread_idx
  on public.user_notifications(user_id, read_at)
  where read_at is null;
create index if not exists user_notifications_created_by_idx
  on public.user_notifications(created_by)
  where created_by is not null;
create index if not exists user_notifications_order_id_idx
  on public.user_notifications(order_id)
  where order_id is not null;

alter table public.user_notifications enable row level security;
revoke all on table public.user_notifications from public, anon, authenticated;
grant select, insert on table public.user_notifications to authenticated;
grant update(read_at) on table public.user_notifications to authenticated;

drop policy if exists "notifications_select_own" on public.user_notifications;
create policy "notifications_select_own"
  on public.user_notifications for select to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists "notifications_mark_own_read" on public.user_notifications;
create policy "notifications_mark_own_read"
  on public.user_notifications for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

drop policy if exists "notifications_admin_insert" on public.user_notifications;
create policy "notifications_admin_insert"
  on public.user_notifications for insert to authenticated
  with check (
    (select private.is_admin())
    and created_by = (select auth.uid())
  );

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
    select o.user_id into v_order_user
    from public.orders o where o.id=p_order_id for share;
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

create or replace function private.notify_order_status_change()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_title text;
  v_message text;
  v_label text;
  v_provider_changed boolean := new.central_one_status is distinct from old.central_one_status;
begin
  if new.status is not distinct from old.status
     and not v_provider_changed then
    return new;
  end if;

  if v_provider_changed and new.central_one_status in
    ('created','confirmed','processing','partially_completed','completed','failed','cancelled') then
    case new.central_one_status
      when 'created' then
        v_title := 'Pedido creado en Central One';
        v_label := 'Central One creó tu recarga; todavía no significa que esté entregada';
      when 'confirmed' then
        v_title := 'Tu recarga fue confirmada';
        v_label := 'Central One confirmó la orden y reservó el saldo';
      when 'processing' then
        v_title := 'Tu recarga está en proceso';
        v_label := 'Central One está procesando tu recarga';
      when 'partially_completed' then
        v_title := 'Tu recarga tiene una entrega parcial';
        v_label := 'Central One informa una entrega parcial; la tienda revisará el resultado';
      when 'completed' then
        v_title := '¡Tu recarga está entregada!';
        v_label := 'Central One confirmó la entrega de la recarga';
      when 'failed' then
        v_title := 'Necesitamos revisar tu recarga';
        v_label := 'Central One informó un fallo; la tienda revisará tu pedido y la solución';
      when 'cancelled' then
        v_title := 'Tu recarga fue cancelada';
        v_label := 'Central One informó que la orden fue cancelada; la tienda revisará el caso';
    end case;
  elsif new.status is distinct from old.status then
    v_label := case new.status
      when 'pending' then 'Pendiente'
      when 'payment_review' then 'Pago en revisión'
      when 'processing' then 'Pago confirmado · pendiente de recarga'
      when 'completed' then 'Recarga completada'
      when 'failed' then 'Recarga fallida · requiere revisión'
      when 'rejected' then 'Pedido rechazado'
      when 'cancelled' then 'Pedido cancelado'
      else 'Estado actualizado'
    end;
    v_title := case new.status
      when 'payment_review' then 'Comprobante recibido'
      when 'processing' then 'Pago confirmado'
      when 'completed' then '¡Tu recarga está lista!'
      when 'failed' then 'Necesitamos revisar tu pedido'
      when 'rejected' then 'Actualización de tu pedido'
      when 'cancelled' then 'Pedido cancelado'
      else 'Tu pedido se actualizó'
    end;
  else
    return new;
  end if;

  v_message := 'Tu pedido ' || coalesce(new.order_code, left(new.id::text,8)) ||
    ' cambió de estado: ' || v_label || '. Consulta «Mis pedidos» para ver el progreso.';

  if new.central_one_error_message is not null
     and v_provider_changed
     and new.central_one_status in ('failed','partially_completed') then
    v_message := v_message || ' Detalle: ' || left(new.central_one_error_message,300);
  end if;

  insert into public.user_notifications(user_id,order_id,kind,title,message)
  values(new.user_id,new.id,'order_status',v_title,left(v_message,1000));
  return new;
end;
$function$;
revoke all on function private.notify_order_status_change() from public, anon, authenticated;
drop trigger if exists notify_customer_order_status on public.orders;
create trigger notify_customer_order_status
  after update of status, central_one_status on public.orders
  for each row
  when (old.status is distinct from new.status
     or old.central_one_status is distinct from new.central_one_status)
  execute function private.notify_order_status_change();

create or replace function private.enforce_wallet_deposit_proof_limit()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_count integer;
begin
  perform 1 from public.wallet_deposits d
  where d.id = new.deposit_id
  for update;
  if not found then
    raise exception 'No encontramos la solicitud de depósito.';
  end if;
  select count(*) into v_count
  from public.wallet_deposit_proofs p
  where p.deposit_id = new.deposit_id;
  if v_count >= 2 then
    raise exception 'Cada depósito admite un máximo de 2 imágenes de comprobante.';
  end if;
  return new;
end;
$function$;
revoke all on function private.enforce_wallet_deposit_proof_limit() from public, anon, authenticated;
drop trigger if exists wallet_deposit_proofs_max_two_before_insert on public.wallet_deposit_proofs;
create trigger wallet_deposit_proofs_max_two_before_insert
  before insert on public.wallet_deposit_proofs
  for each row execute function private.enforce_wallet_deposit_proof_limit();
