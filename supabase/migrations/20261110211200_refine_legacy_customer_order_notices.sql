update public.user_notifications
set title = case
      when title = 'Pedido creado en la tienda' then 'Tu recarga está en preparación'
      when title = 'Tu recarga fue confirmada' then 'Tu recarga fue aceptada'
      else title
    end,
    message = replace(
      replace(
        replace(message,
          'cambió de estado: Pago confirmado · pendiente de recarga',
          'cambió de estado: Pago confirmado · preparando tu recarga'
        ),
        'cambió de estado: la tienda confirmó la orden y reservó el saldo',
        'cambió de estado: Tienda El Castillo aceptó tu pedido y está preparando la entrega'
      ),
      'cambió de estado: la tienda confirmó la entrega de la recarga',
      'cambió de estado: Tienda El Castillo confirmó la entrega de tu recarga'
    )
where kind = 'order_status'
  and (
    title in ('Pedido creado en la tienda','Tu recarga fue confirmada')
    or message ilike '%Pago confirmado · pendiente de recarga%'
    or message ilike '%la tienda confirmó la orden y reservó el saldo%'
    or message ilike '%la tienda confirmó la entrega de la recarga%'
  );
