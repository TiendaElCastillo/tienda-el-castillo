-- Security and permission hardening for Tienda El Castillo.
-- PREPARED ON A FEATURE BRANCH ONLY. Review and test before applying to production.
--
-- 1) Server-managed payment/provider fields must never be accepted from a client
--    inserting a new order. In particular, a forged central_one_order_id could
--    make claim_central_one_order() report "already_submitted" without a real order.
-- 2) Restore only the narrowly required wallet-request permissions. Existing RLS
--    policies and SECURITY DEFINER ownership/admin checks continue to enforce access.
-- 3) Do not grant wallet purchase/checkout access; that flow remains disabled in the UI.

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
 if new.product_id is null then
  raise exception 'Selecciona un producto válido.';
 end if;
 if new.player_id is null or length(btrim(new.player_id)) < 3 or length(btrim(new.player_id)) > 64 then
  raise exception 'El ID del jugador debe tener entre 3 y 64 caracteres.';
 end if;

 select * into selected_product
 from public.products
 where id = new.product_id and active = true;

 if not found then
  raise exception 'El producto ya no está disponible.';
 end if;

 if coalesce(new.payment_source, 'direct') = 'wallet' then
  if new.payment_method <> 'Billetera CUP' then
   raise exception 'Método de billetera no válido.';
  end if;
  final_price := selected_product.price_transfer;
 elsif coalesce(new.payment_source, 'direct') = 'direct' then
  if not exists (
   select 1 from public.payment_methods pm
   where pm.name = new.payment_method and pm.active = true
  ) then
   raise exception 'El método de pago no está activo.';
  end if;
  case new.payment_method
   when 'Transferencia CUP' then final_price := selected_product.price_transfer;
   when 'Saldo móvil' then final_price := selected_product.price_mobile;
   when 'USDT' then final_price := selected_product.price_usdt;
   else raise exception 'Método de pago no válido.';
  end case;
 else
  raise exception 'Origen de pago no válido.';
 end if;

 if final_price is null or final_price <= 0 then
  raise exception 'Este producto no tiene precio para ese método de pago.';
 end if;

 -- Values derived from the active product and server state.
 new.game := selected_product.game;
 new.package_name := selected_product.name;
 new.price := final_price;
 new.status := 'pending';
 new.order_code := 'EC-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 10));
 new.player_id := btrim(new.player_id);
 new.player_name := nullif(btrim(coalesce(new.player_name, '')), '');
 new.payment_reference := null;
 new.payment_sender_phone := null;
 new.payment_reported_amount := null;
 new.admin_notes := null;
 new.created_at := now();
 new.payment_source := coalesce(new.payment_source, 'direct');
 new.proof_path := null;
 new.paid_at := null;

 -- These fields are written only by trusted server-side flows.
 -- Keep player_id_validation_token intact: the following provider-validation
 -- trigger validates and consumes it before setting validated/provider fields.
 new.payment_confirmed_by := null;
 new.payment_confirmed_at := null;
 new.player_id_validated := false;
 new.player_id_validated_at := null;
 new.central_one_idempotency_key := null;
 new.central_one_order_id := null;
 new.central_one_reference_code := null;
 new.central_one_status := 'not_submitted';
 new.central_one_request_id := null;
 new.central_one_error_code := null;
 new.central_one_error_message := null;
 new.central_one_submitted_at := null;
 new.central_one_checked_at := null;
 new.central_one_response := null;

 return new;
end;
$function$;

-- These grants do not weaken RLS. The existing INSERT policy limits deposits
-- to the caller's own pending CUP request, and the INSERT trigger validates it.
grant insert on table public.wallet_deposits to authenticated;

-- Wallet history is read through an existing own-or-admin SELECT RLS policy.
grant select on table public.wallet_transactions to authenticated;


-- Replace the wallet-proof function with the same owner/path checks plus a
-- one-proof lock and duplicate-transfer-reference protection before exposing it.
create or replace function public.submit_wallet_deposit_proof(
 p_deposit_id uuid,
 p_proof_path text,
 p_reference text default null
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
 v_uid uuid := auth.uid();
 v_deposit public.wallet_deposits%rowtype;
 v_reference text := nullif(trim(coalesce(p_reference, '')), '');
begin
 if v_uid is null then
  raise exception 'Debes iniciar sesión.';
 end if;

 select * into v_deposit
 from public.wallet_deposits
 where id = p_deposit_id and user_id = v_uid
 for update;

 if not found then
  raise exception 'No encontramos el depósito en tu cuenta.';
 end if;

 if v_deposit.status not in ('pending', 'payment_review')
    or v_deposit.proof_path is not null then
  raise exception 'Este depósito ya fue enviado a verificación y no admite más cambios.';
 end if;

 if not exists (
  select 1 from public.payment_methods pm
  where pm.name = v_deposit.payment_method and pm.active = true
 ) then
  raise exception 'El método de pago ya no está disponible.';
 end if;

 if v_deposit.payment_method = 'Transferencia CUP' then
  if v_reference is null or length(v_reference) < 3 or length(v_reference) > 100 then
   raise exception 'Escribe un número de transferencia válido.';
  end if;
  if exists (
   select 1 from public.wallet_deposits d
   where d.id <> p_deposit_id
     and d.payment_method = 'Transferencia CUP'
     and d.payment_reference = v_reference
     and d.status in ('payment_review', 'approved')
  ) or exists (
   select 1 from public.orders o
   where o.payment_method = 'Transferencia CUP'
     and o.payment_reference = v_reference
     and o.status in ('payment_review', 'processing', 'completed')
  ) then
   raise exception 'Ese número de transferencia ya fue utilizado en otra solicitud.';
  end if;
 elsif v_deposit.payment_method = 'Saldo móvil' then
  if v_reference is not null then
   raise exception 'El saldo móvil no utiliza número de transferencia bancaria.';
  end if;
 else
  raise exception 'Este método de pago todavía no admite comprobantes.';
 end if;

 if p_proof_path !~ (
  '^' || v_uid::text || '/' || p_deposit_id::text ||
  '/[a-f0-9-]{36}[.](jpg|jpeg|png|webp)grant execute on function public.submit_wallet_deposit_proof(uuid, text, text)
to authenticated;

-- The review function calls private.is_admin() before approving/rejecting and
-- creates wallet transactions internally. Non-admin authenticated users are denied.
grant execute on function public.admin_review_wallet_deposit(uuid, boolean, text)
to authenticated;

 ) then
  raise exception 'La ruta del comprobante no es válida.';
 end if;

 if not exists (
  select 1 from storage.objects so
  where so.bucket_id = 'payment-proofs' and so.name = p_proof_path
 ) then
  raise exception 'No encontramos la imagen subida.';
 end if;

 update public.wallet_deposits
 set proof_path = p_proof_path,
     payment_reference = v_reference,
     status = 'payment_review'
 where id = p_deposit_id and user_id = v_uid
   and proof_path is null
   and status in ('pending', 'payment_review');

 if not found then
  raise exception 'El depósito cambió de estado y ya no admite cambios.';
 end if;

 return jsonb_build_object('deposit_id', p_deposit_id, 'status', 'payment_review');
end;
$function$;

-- The proof function checks auth.uid(), ownership, pending state, active method,
-- path shape and uploaded object existence before updating a deposit.
grant execute on function public.submit_wallet_deposit_proof(uuid, text, text)
to authenticated;

-- The review function calls private.is_admin() before approving/rejecting and
-- creates wallet transactions internally. Non-admin authenticated users are denied.
grant execute on function public.admin_review_wallet_deposit(uuid, boolean, text)
to authenticated;
