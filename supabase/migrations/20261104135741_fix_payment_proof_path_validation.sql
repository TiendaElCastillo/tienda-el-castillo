create or replace function public.submit_payment_proof(
  p_order_id uuid,
  p_proof_path text,
  p_reference text default null
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_order public.orders%rowtype;
  v_reference text := nullif(trim(coalesce(p_reference,'')), '');
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
  if v_order.payment_method = 'Transferencia CUP' and v_reference is null then
    raise exception 'Escribe el número de transferencia.';
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
      payment_reference = v_reference,
      status = 'payment_review'
  where id = p_order_id and user_id = v_uid;
  return jsonb_build_object('order_id',v_order.id,'order_code',v_order.order_code,'status','payment_review');
end;
$$;
revoke all on function public.submit_payment_proof(uuid,text,text) from public, anon;
grant execute on function public.submit_payment_proof(uuid,text,text) to authenticated;