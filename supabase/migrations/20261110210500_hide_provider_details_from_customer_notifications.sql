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
        v_title := 'Tu recarga está en preparación';
        v_label := 'Recibimos tu pago y estamos preparando la recarga; todavía no está entregada';
      when 'confirmed' then
        v_title := 'Tu recarga fue aceptada';
        v_label := 'La tienda aceptó tu pedido y está preparando la entrega';
      when 'processing' then
        v_title := 'Tu recarga está en proceso';
        v_label := 'Tu recarga está en proceso; te avisaremos cuando esté lista';
      when 'partially_completed' then
        v_title := 'Tu recarga requiere revisión';
        v_label := 'La entrega no se completó por completo; la tienda está revisando tu pedido';
      when 'completed' then
        v_title := '¡Tu recarga está entregada!';
        v_label := 'La tienda confirmó la entrega de la recarga';
      when 'failed' then
        v_title := 'Necesitamos revisar tu recarga';
        v_label := 'No pudimos completar la recarga; la tienda revisará el pedido y te informará la solución';
      when 'cancelled' then
        v_title := 'Tu recarga fue cancelada';
        v_label := 'El pedido fue cancelado; la tienda revisará el caso y te informará';
    end case;
  elsif new.status is distinct from old.status then
    v_label := case new.status
      when 'pending' then 'Pendiente'
      when 'payment_review' then 'Pago en revisión'
      when 'processing' then 'Pago confirmado · preparando tu recarga'
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

  insert into public.user_notifications(user_id,order_id,kind,title,message)
  values(new.user_id,new.id,'order_status',v_title,left(v_message,1000));
  return new;
end;
$function$;

update public.user_notifications
set title = case
      when title = 'Pedido creado en Central One' then 'Tu recarga está en preparación'
      else replace(title, 'Central One', 'la tienda')
    end,
    message = regexp_replace(
      replace(message, 'Central One', 'la tienda'),
      ' Detalle:.*$',
      '',
      'i'
    )
where kind = 'order_status'
  and (title ilike '%Central One%' or message ilike '%Central One%');
