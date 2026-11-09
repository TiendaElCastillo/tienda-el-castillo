-- Evidence required for direct payments before an administrator can authorize a top-up.
-- Applied to production on 2026-11-06 and kept here for project history.

alter table public.orders
  add column if not exists payment_sender_phone text,
  add column if not exists payment_reported_amount numeric(12,2);

comment on column public.orders.payment_sender_phone is
  'Número móvil desde el que el cliente envió la transferencia o el saldo móvil.';
comment on column public.orders.payment_reported_amount is
  'Importe de saldo móvil que el cliente declara haber enviado; debe coincidir con el precio del pedido.';

create or replace function public.validate_order_request()
returns trigger
language plpgsql
set search_path to ''
as $function$
declare
 selected_product public.products%rowtype;
 final_price numeric;
begin
 if auth.uid() is null or new.user_id is distinct from auth.uid() then
  raise exception 'No autorizado para crear este pedido.';
 end if;
 if new.product_id is null then raise exception 'Selecciona un producto válido.'; end if;
 if new.player_id is null or length(btrim(new.player_id))<3 or length(btrim(new.player_id))>64 then
  raise exception 'El ID del jugador debe tener entre 3 y 64 caracteres.';
 end if;
 select * into selected_product from public.products where id=new.product_id and active=true;
 if not found then raise exception 'El producto ya no está disponible.'; end if;
 if coalesce(new.payment_source,'direct')='wallet' then
  if new.payment_method<>'Billetera CUP' then raise exception 'Método de billetera no válido.'; end if;
  final_price:=selected_product.price_transfer;
 elsif coalesce(new.payment_source,'direct')='direct' then
  if not exists(select 1 from public.payment_methods pm where pm.name=new.payment_method and pm.active=true) then
   raise exception 'El método de pago no está activo.';
  end if;
  case new.payment_method
   when 'Transferencia CUP' then final_price:=selected_product.price_transfer;
   when 'Saldo móvil' then final_price:=selected_product.price_mobile;
   when 'USDT' then final_price:=selected_product.price_usdt;
   else raise exception 'Método de pago no válido.';
  end case;
 else
  raise exception 'Origen de pago no válido.';
 end if;
 if final_price is null or final_price<=0 then raise exception 'Este producto no tiene precio para ese método de pago.'; end if;
 new.game:=selected_product.game;
 new.package_name:=selected_product.name;
 new.price:=final_price;
 new.status:='pending';
 new.order_code:='EC-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,10));
 new.player_id:=btrim(new.player_id);
 new.player_name:=nullif(btrim(coalesce(new.player_name,'')),'');
 new.payment_reference:=null;
 new.payment_sender_phone:=null;
 new.payment_reported_amount:=null;
 new.admin_notes:=null;
 new.created_at:=now();
 new.payment_source:=coalesce(new.payment_source,'direct');
 new.proof_path:=null;
 new.paid_at:=null;
 return new;
end;
$function$;

drop function if exists public.submit_payment_proof(uuid,text,text);
drop function if exists public.submit_payment_proof(uuid,text,text,text,numeric);

create function public.submit_payment_proof(
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
 v_reference text := nullif(trim(coalesce(p_reference,'')), '');
 v_phone text := regexp_replace(trim(coalesce(p_sender_phone,'')), '[^0-9+]', '', 'g');
 v_phone_digits text := regexp_replace(coalesce(p_sender_phone,''), '[^0-9]', '', 'g');
begin
 if v_uid is null then
  raise exception 'Debes iniciar sesión para enviar el comprobante.';
 end if;
 if p_order_id is null or p_proof_path is null then
  raise exception 'Faltan datos del comprobante.';
 end if;
 select * into v_order from public.orders
 where id = p_order_id and user_id = v_uid for update;
 if not found then
  raise exception 'No encontramos ese pedido en tu cuenta.';
 end if;
 if v_order.payment_source <> 'direct' then
  raise exception 'Este pedido no admite comprobantes externos.';
 end if;
 if v_order.status not in ('pending','payment_review') then
  raise exception 'Este pedido ya no admite cambios de comprobante.';
 end if;
 if not exists (select 1 from public.payment_methods pm
  where pm.name = v_order.payment_method and pm.active = true) then
  raise exception 'El método de pago ya no está disponible. Contacta con la tienda.';
 end if;
 if v_phone_digits !~ '^[0-9]{8,15}$' or v_phone !~ '^[+]?[0-9]{8,15}$' then
  raise exception 'Escribe un número móvil válido desde el que realizaste el pago.';
 end if;
 if v_order.payment_method = 'Transferencia CUP' then
  if v_reference is null or length(v_reference)<3 or length(v_reference)>100 then
   raise exception 'Escribe el número de transferencia.';
  end if;
  if exists (
   select 1 from public.orders o
   where o.id <> p_order_id
     and o.payment_method = 'Transferencia CUP'
     and o.payment_reference = v_reference
     and o.status in ('payment_review','processing','completed')
  ) then
   raise exception 'Ese número de transferencia ya fue utilizado en otro pedido.';
  end if;
  if p_reported_amount is not null then
   raise exception 'No envíes un importe manual para la transferencia bancaria.';
  end if;
 elsif v_order.payment_method = 'Saldo móvil' then
  if p_reported_amount is null or p_reported_amount <= 0 then
   raise exception 'Escribe el importe de saldo que enviaste.';
  end if;
  if abs(p_reported_amount - v_order.price) > 0.01 then
   raise exception 'El importe enviado debe coincidir exactamente con el precio del paquete: %.', v_order.price;
  end if;
  if v_reference is not null then
   raise exception 'El saldo móvil no utiliza número de transferencia bancaria.';
  end if;
 else
  raise exception 'Este método de pago todavía no admite comprobantes.';
 end if;
 if p_proof_path !~ (
  '^' || v_uid::text || '/' || p_order_id::text ||
  '/[a-f0-9-]{36}[.](jpg|jpeg|png|webp)$'
 ) then
  raise exception 'La ruta del comprobante no es válida.';
 end if;
 if not exists (select 1 from storage.objects so
  where so.bucket_id = 'payment-proofs' and so.name = p_proof_path) then
  raise exception 'No encontramos la imagen subida. Inténtalo de nuevo.';
 end if;
 update public.orders
 set proof_path = p_proof_path,
     payment_reference = case when v_order.payment_method='Transferencia CUP' then v_reference else null end,
     payment_sender_phone = v_phone,
     payment_reported_amount = case when v_order.payment_method='Saldo móvil' then p_reported_amount else null end,
     status = 'payment_review'
 where id = p_order_id and user_id = v_uid;
 return jsonb_build_object(
  'order_id',v_order.id,
  'order_code',v_order.order_code,
  'status','payment_review'
 );
end;
$function$;

revoke all on function public.submit_payment_proof(uuid,text,text,text,numeric) from public;
grant execute on function public.submit_payment_proof(uuid,text,text,text,numeric) to authenticated;

do $block$
begin
 if not exists (
  select 1 from pg_publication_tables
  where pubname='supabase_realtime' and schemaname='public' and tablename='orders'
 ) then
  alter publication supabase_realtime add table public.orders;
 end if;
end;
$block$;
