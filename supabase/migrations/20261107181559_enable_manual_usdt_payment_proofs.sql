drop policy if exists "Pedidos: insertar propio o admin" on public.orders;
create policy "Pedidos: insertar propio o admin"
on public.orders
for insert
to authenticated
with check (
  (select private.is_admin())
  OR (
    user_id = (select auth.uid())
    AND status = 'pending'
    AND payment_source = 'direct'
    AND payment_method = ANY (ARRAY['Transferencia CUP'::text, 'Saldo móvil'::text, 'USDT'::text])
  )
);

create unique index if not exists orders_usdt_payment_reference_active_unique
on public.orders (payment_reference)
where payment_method = 'USDT'
  and payment_reference is not null
  and status in ('payment_review','processing','completed','rejected');

create or replace function public.submit_payment_proof(
 p_order_id uuid,
 p_proof_path text,
 p_reference text,
 p_sender_phone text,
 p_reported_amount numeric
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
 v_uid uuid := auth.uid();
 v_order public.orders%rowtype;
 v_reference text := upper(nullif(trim(coalesce(p_reference,'')), ''));
 v_phone text := regexp_replace(trim(coalesce(p_sender_phone,'')), '[^0-9+]', '', 'g');
 v_phone_digits text := regexp_replace(coalesce(p_sender_phone,''), '[^0-9]', '', 'g');
begin
 if v_uid is null then raise exception 'Debes iniciar sesión para enviar el comprobante.'; end if;
 if p_order_id is null or p_proof_path is null then raise exception 'Faltan datos del comprobante.'; end if;

 select * into v_order
 from public.orders
 where id=p_order_id and user_id=v_uid
 for update;

 if not found then raise exception 'No encontramos ese pedido en tu cuenta.'; end if;
 if v_order.payment_source <> 'direct' then raise exception 'Este pedido no admite comprobantes externos.'; end if;
 if v_order.status <> 'pending' or v_order.proof_path is not null then
  raise exception 'El pedido ya fue enviado a verificación y no admite más cambios. Contacta con la tienda si necesitas ayuda.';
 end if;
 if not exists(
  select 1 from public.payment_methods pm
  where pm.name=v_order.payment_method and pm.active=true
    and nullif(trim(coalesce(pm.instructions,'')),'') is not null
 ) then
  raise exception 'El método de pago no está activo o no tiene instrucciones configuradas. Contacta con la tienda.';
 end if;

 if v_order.payment_method in ('Transferencia CUP','Saldo móvil') then
  if v_phone_digits !~ '^[0-9]{8,15}$' or v_phone !~ '^[+]?[0-9]{8,15}$' then
   raise exception 'Escribe un número móvil válido desde el que realizaste el pago.';
  end if;
 end if;

 if v_order.payment_method='Transferencia CUP' then
  if v_reference is null or length(v_reference)<3 or length(v_reference)>100 then
   raise exception 'Escribe el número de transferencia.';
  end if;
  if exists(
   select 1 from public.orders o
   where o.id<>p_order_id
     and o.payment_method='Transferencia CUP'
     and o.payment_reference=v_reference
     and o.status in ('payment_review','processing','completed')
  ) then
   raise exception 'Ese número de transferencia ya fue utilizado en otro pedido.';
  end if;
  if p_reported_amount is not null then
   raise exception 'No envíes un importe manual para la transferencia bancaria.';
  end if;

 elsif v_order.payment_method='Saldo móvil' then
  if p_reported_amount is null or p_reported_amount<=0 then
   raise exception 'Escribe el importe de saldo que enviaste.';
  end if;
  if abs(p_reported_amount-v_order.price)>0.01 then
   raise exception 'El importe enviado debe coincidir exactamente con el precio del paquete: %.',v_order.price;
  end if;
  if v_reference is not null then
   raise exception 'El saldo móvil no utiliza número de transferencia bancaria.';
  end if;

 elsif v_order.payment_method='USDT' then
  if v_reference is null or v_reference !~ '^[A-Fa-f0-9]{64}$' then
   raise exception 'Escribe el hash/TxID válido de 64 caracteres hexadecimales.';
  end if;
  if p_reported_amount is null or p_reported_amount<=0 then
   raise exception 'Escribe la cantidad exacta de USDT que enviaste.';
  end if;
  if abs(p_reported_amount-v_order.price)>0.000001 then
   raise exception 'La cantidad de USDT debe coincidir exactamente con el precio del paquete: %.',v_order.price;
  end if;
  if exists(
   select 1 from public.orders o
   where o.id<>p_order_id
     and o.payment_method='USDT'
     and o.payment_reference=v_reference
     and o.status in ('payment_review','processing','completed','rejected')
  ) then
   raise exception 'Ese hash/TxID USDT ya fue utilizado en otro pedido.';
  end if;

 else
  raise exception 'Este método de pago todavía no admite comprobantes.';
 end if;

 if p_proof_path !~ ('^'||v_uid::text||'/'||p_order_id::text||'/[a-f0-9-]{36}[.](jpg|jpeg|png|webp)$') then
  raise exception 'La ruta del comprobante no es válida.';
 end if;
 if not exists(
  select 1 from storage.objects so
  where so.bucket_id='payment-proofs' and so.name=p_proof_path
 ) then
  raise exception 'No encontramos la imagen subida. Inténtalo de nuevo.';
 end if;

 update public.orders
 set proof_path=p_proof_path,
  payment_reference=case when v_order.payment_method in ('Transferencia CUP','USDT') then v_reference else null end,
  payment_sender_phone=case when v_order.payment_method='USDT' then null else nullif(v_phone,'') end,
  payment_reported_amount=case when v_order.payment_method in ('Saldo móvil','USDT') then p_reported_amount else null end,
  status='payment_review'
 where id=p_order_id and user_id=v_uid and status='pending' and proof_path is null;

 if not found then raise exception 'El pedido cambió de estado y ya no admite cambios.'; end if;
 return jsonb_build_object('order_id',v_order.id,'order_code',v_order.order_code,'status','payment_review');
end;
$function$;

insert into public.payment_methods(name,instructions,active)
select 'USDT', null, false
where not exists (select 1 from public.payment_methods where name='USDT');