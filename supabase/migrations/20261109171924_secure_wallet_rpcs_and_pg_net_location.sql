-- Security hardening for wallet RPCs and pg_net placement.
-- Applied to Tienda El Castillo on 2026-11-09.
-- The public RPC names/signatures remain stable for index.html.
ALTER FUNCTION public.create_wallet_order(uuid,text,text,uuid,uuid) SET SCHEMA private;
ALTER FUNCTION public.submit_payment_proof(uuid,text,text,text,numeric) SET SCHEMA private;
ALTER FUNCTION public.submit_wallet_deposit_proofs(uuid,text[],text,text,text,text) SET SCHEMA private;

CREATE OR REPLACE FUNCTION private.create_wallet_order(p_product_id uuid, p_player_id text, p_player_name text DEFAULT ''::text, p_player_id_validation_token uuid DEFAULT NULL::uuid, p_request_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid := auth.uid();
  v_product public.products%rowtype;
  v_balance numeric;
  v_order public.orders%rowtype;
  v_price numeric;
begin
  if v_uid is null then raise exception 'Debes iniciar sesión.'; end if;
  if p_request_id is null then raise exception 'No se pudo identificar esta compra. Vuelve a intentarlo.'; end if;
  if length(trim(coalesce(p_player_id,'')))<3 or length(trim(p_player_id))>64 then
    raise exception 'ID de jugador no válido.';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(v_uid::text,0));

  select * into v_order
  from public.orders
  where user_id=v_uid and wallet_request_id=p_request_id
  for update;
  if found then
    if v_order.product_id is distinct from p_product_id or v_order.player_id is distinct from trim(p_player_id) then
      raise exception 'La clave de compra ya está asociada a otro pedido. Actualiza la página antes de repetir.';
    end if;
    return jsonb_build_object(
      'order_id',v_order.id,'order_code',v_order.order_code,'price',v_order.price,
      'currency','USD','balance',private.wallet_balance(v_uid,'USD'),
      'status',v_order.status,'already_processed',true
    );
  end if;

  select * into v_product from public.products where id=p_product_id and active=true;
  if not found or coalesce(v_product.price_usdt,0)<=0 then
    raise exception 'Paquete no disponible para el saldo de Tienda El Castillo.';
  end if;
  v_price:=v_product.price_usdt;
  v_balance:=private.wallet_balance(v_uid,'USD');
  if v_balance<v_price then
    raise exception 'Saldo insuficiente. Disponible: % USD. Necesitas: % USD.',round(v_balance,6),v_price;
  end if;

  insert into public.orders(
    user_id,product_id,player_id,player_name,payment_method,payment_reference,status,payment_source,
    provider_product_id,provider_region,player_id_validation_token,wallet_request_id
  ) values (
    v_uid,v_product.id,trim(p_player_id),trim(coalesce(p_player_name,'')),
    'Saldo de Tienda El Castillo','', 'pending','wallet',
    v_product.provider_product_id,v_product.provider_region,p_player_id_validation_token,p_request_id
  ) returning * into v_order;

  insert into public.wallet_transactions(user_id,order_id,kind,amount,currency,description)
  values(v_uid,v_order.id,'purchase',v_price,'USD','Compra del pedido '||v_order.order_code);

  update public.orders
  set status='processing',paid_at=now(),payment_confirmed_by=v_uid,payment_confirmed_at=now()
  where id=v_order.id and user_id=v_uid;

  return jsonb_build_object(
    'order_id',v_order.id,'order_code',v_order.order_code,'price',v_price,
    'currency','USD','balance',private.wallet_balance(v_uid,'USD'),
    'status','processing','already_processed',false
  );
end;
$function$

CREATE OR REPLACE FUNCTION private.submit_payment_proof(p_order_id uuid, p_proof_path text, p_reference text, p_sender_phone text, p_reported_amount numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 v_uid uuid:=auth.uid();
 v_order public.orders%rowtype;
 v_reference text:=upper(nullif(regexp_replace(trim(coalesce(p_reference,'')),'[[:space:]]+','','g'),''));
 v_phone text:=regexp_replace(trim(coalesce(p_sender_phone,'')),'[^0-9+]','','g');
 v_phone_digits text:=regexp_replace(coalesce(p_sender_phone,''),'[^0-9]','','g');
begin
 if v_uid is null then raise exception 'Debes iniciar sesión para enviar el comprobante.'; end if;
 if p_order_id is null or p_proof_path is null then raise exception 'Faltan datos del comprobante.'; end if;

 select * into v_order
 from public.orders
 where id=p_order_id and user_id=v_uid
 for update;

 if not found then raise exception 'No encontramos ese pedido en tu cuenta.'; end if;
 if v_order.payment_source<>'direct' then raise exception 'Este pedido no admite comprobantes externos.'; end if;
 if v_order.status<>'pending' or v_order.proof_path is not null then
  raise exception 'El pedido ya fue enviado a verificación y no admite más cambios. Contacta con la tienda si necesitas ayuda.';
 end if;
 -- El método se validó al crear el pedido. Una desactivación posterior solo afecta a pedidos nuevos.
 -- Los pedidos pendientes conservan el derecho a adjuntar el comprobante de su pago.

 if v_order.payment_method in ('Transferencia CUP','Saldo móvil') then
  if v_phone_digits !~ '^[0-9]{8,15}$' or v_phone !~ '^[+]?[0-9]{8,15}$' then
   raise exception 'Escribe un número móvil válido desde el que realizaste el pago.';
  end if;
 end if;

 if v_order.payment_method='Transferencia CUP' then
  if v_reference is null or length(v_reference)<3 or length(v_reference)>100 then
   raise exception 'Escribe el número de transferencia.';
  end if;
  if p_reported_amount is not null then
   raise exception 'No envíes un importe manual para la transferencia bancaria.';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('castle-payment-reference:CUP:'||v_reference,0));
  if exists(
   select 1 from public.orders o
   where o.id<>p_order_id
     and o.payment_method='Transferencia CUP'
     and upper(regexp_replace(coalesce(o.payment_reference,''),'[[:space:]]+','','g'))=v_reference
     and o.status in ('payment_review','processing','completed','rejected')
  ) then
   raise exception 'Ese número de transferencia ya fue utilizado en otro pedido.';
  end if;
  if exists(
   select 1 from public.wallet_deposits d
   where d.payment_method='Transferencia CUP'
     and upper(regexp_replace(coalesce(d.payment_reference,''),'[[:space:]]+','','g'))=v_reference
  ) then
   raise exception 'Ese número de transferencia ya fue utilizado en un depósito de wallet.';
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

  perform pg_advisory_xact_lock(hashtextextended('castle-payment-reference:USDT:'||lower(v_reference),0));
  if exists(
   select 1 from public.orders o
   where o.id<>p_order_id
     and o.payment_method='USDT'
     and lower(coalesce(o.payment_reference,''))=lower(v_reference)
     and o.status in ('payment_review','processing','completed','rejected')
  ) then
   raise exception 'Ese hash/TxID USDT ya fue utilizado en otro pedido.';
  end if;
  if exists(
   select 1 from public.wallet_deposits d
   where d.payment_method='USDT' and lower(coalesce(d.txid,''))=lower(v_reference)
  ) then
   raise exception 'Ese hash/TxID ya fue utilizado en un depósito de wallet.';
  end if;
 else
  raise exception 'Este método de pago todavía no admite comprobantes.';
 end if;

 if p_proof_path !~ ('^'||v_uid::text||'/'||p_order_id::text||'/[a-f0-9-]{36}[.](jpg|jpeg|png|webp)$') then
  raise exception 'La ruta del comprobante no es válida.';
 end if;
 if not exists(select 1 from storage.objects so where so.bucket_id='payment-proofs' and so.name=p_proof_path) then
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
$function$

CREATE OR REPLACE FUNCTION private.submit_wallet_deposit_proofs(p_deposit_id uuid, p_proof_paths text[], p_reference text DEFAULT NULL::text, p_sender_phone text DEFAULT NULL::text, p_txid text DEFAULT NULL::text, p_network text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_deposit public.wallet_deposits%rowtype;
  v_path text;
  v_reference text := nullif(upper(regexp_replace(trim(coalesce(p_reference,'')),'[[:space:]]+','','g')),'');
  v_txid text := nullif(lower(trim(coalesce(p_txid,''))),'');
  v_phone text := nullif(trim(coalesce(p_sender_phone,'')),'');
  v_count integer := 0;
  v_inserted integer := 0;
  v_existing_proofs integer := 0;
  v_requested_proofs integer := 0;
  v_new_proofs integer := 0;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Debes iniciar sesión.';
  END IF;

  IF p_proof_paths IS NULL OR cardinality(p_proof_paths) < 1 OR cardinality(p_proof_paths) > 2 THEN
    RAISE EXCEPTION 'Adjunta entre 1 y 2 comprobantes.';
  END IF;

  SELECT count(DISTINCT requested_path)
  INTO v_requested_proofs
  FROM unnest(p_proof_paths) AS paths(requested_path);

  IF v_requested_proofs <> cardinality(p_proof_paths) THEN
    RAISE EXCEPTION 'No adjuntes la misma imagen más de una vez.';
  END IF;

  SELECT *
  INTO v_deposit
  FROM public.wallet_deposits
  WHERE id = p_deposit_id
    AND user_id = v_uid
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'No encontramos el depósito en tu cuenta.';
  END IF;

  IF v_deposit.status NOT IN ('pending','payment_review') THEN
    RAISE EXCEPTION 'Este depósito ya no admite comprobantes.';
  END IF;

  -- Include both the normalized child table and the legacy first-proof column.
  SELECT count(DISTINCT existing_path)
  INTO v_existing_proofs
  FROM (
    SELECT wdp.proof_path AS existing_path
    FROM public.wallet_deposit_proofs wdp
    WHERE wdp.deposit_id = p_deposit_id
      AND wdp.user_id = v_uid
    UNION ALL
    SELECT wd.proof_path AS existing_path
    FROM public.wallet_deposits wd
    WHERE wd.id = p_deposit_id
      AND wd.user_id = v_uid
      AND wd.proof_path IS NOT NULL
  ) existing
  WHERE existing_path IS NOT NULL;

  SELECT count(*)
  INTO v_new_proofs
  FROM (
    SELECT requested_path
    FROM unnest(p_proof_paths) AS paths(requested_path)
    EXCEPT
    SELECT existing_path
    FROM (
      SELECT wdp.proof_path AS existing_path
      FROM public.wallet_deposit_proofs wdp
      WHERE wdp.deposit_id = p_deposit_id
        AND wdp.user_id = v_uid
      UNION
      SELECT wd.proof_path AS existing_path
      FROM public.wallet_deposits wd
      WHERE wd.id = p_deposit_id
        AND wd.user_id = v_uid
        AND wd.proof_path IS NOT NULL
    ) existing
    WHERE existing_path IS NOT NULL
  ) new_paths;

  IF v_existing_proofs + v_new_proofs > 2 THEN
    RAISE EXCEPTION 'Cada depósito admite un máximo de dos comprobantes en total.';
  END IF;

  IF v_deposit.payment_method = 'Transferencia CUP' THEN
    IF v_reference IS NULL OR length(v_reference) < 3 OR length(v_reference) > 100 THEN
      RAISE EXCEPTION 'Escribe el número de transferencia del banco.';
    END IF;

    IF v_phone IS NULL OR v_phone !~ '^[+]?[0-9 ().-]{8,20}$'
       OR length(regexp_replace(v_phone,'[^0-9]','','g')) NOT BETWEEN 8 AND 15 THEN
      RAISE EXCEPTION 'Escribe el teléfono desde el que hiciste la transferencia.';
    END IF;

    -- Serialize claims of the same bank reference across deposits and orders.
    PERFORM pg_advisory_xact_lock(hashtextextended('castle-payment-reference:CUP:'||v_reference,0));

    IF v_deposit.payment_reference IS NOT NULL
       AND upper(regexp_replace(v_deposit.payment_reference,'[[:space:]]+','','g')) <> v_reference THEN
      RAISE EXCEPTION 'El número de transferencia ya quedó registrado en esta solicitud.';
    END IF;

    IF EXISTS (
      SELECT 1
      FROM public.wallet_deposits d
      WHERE d.id <> p_deposit_id
        AND d.payment_method = 'Transferencia CUP'
        AND upper(regexp_replace(coalesce(d.payment_reference,''),'[[:space:]]+','','g')) = v_reference
    ) THEN
      RAISE EXCEPTION 'Ese número de transferencia ya fue utilizado en otra solicitud de depósito.';
    END IF;

    IF EXISTS (
      SELECT 1
      FROM public.orders o
      WHERE o.payment_method = 'Transferencia CUP'
        AND upper(regexp_replace(coalesce(o.payment_reference,''),'[[:space:]]+','','g')) = v_reference
        AND o.status IN ('payment_review','processing','completed','rejected')
    ) THEN
      RAISE EXCEPTION 'Ese número de transferencia ya fue utilizado en un pedido directo.';
    END IF;

  ELSIF v_deposit.payment_method = 'USDT' THEN
    IF v_txid IS NULL OR v_txid !~ '^[a-f0-9]{64}$' THEN
      RAISE EXCEPTION 'El TxID debe tener 64 caracteres hexadecimales.';
    END IF;

    IF upper(coalesce(p_network,'')) NOT IN ('BNB SMART CHAIN (BEP20)','BEP20') THEN
      RAISE EXCEPTION 'La red debe ser BNB Smart Chain (BEP20).';
    END IF;

    PERFORM pg_advisory_xact_lock(hashtextextended('castle-payment-reference:USDT:'||v_txid,0));

    IF v_deposit.txid IS NOT NULL AND lower(v_deposit.txid) <> v_txid THEN
      RAISE EXCEPTION 'El TxID ya quedó registrado en esta solicitud.';
    END IF;

    IF EXISTS (
      SELECT 1
      FROM public.wallet_deposits d
      WHERE d.id <> p_deposit_id
        AND lower(coalesce(d.txid,'')) = v_txid
    ) THEN
      RAISE EXCEPTION 'Ese TxID ya fue utilizado en otra solicitud de depósito.';
    END IF;

    IF EXISTS (
      SELECT 1
      FROM public.orders o
      WHERE o.payment_method = 'USDT'
        AND lower(coalesce(o.payment_reference,'')) = v_txid
        AND o.status IN ('payment_review','processing','completed','rejected')
    ) THEN
      RAISE EXCEPTION 'Ese TxID ya fue utilizado en un pedido directo.';
    END IF;
  ELSE
    RAISE EXCEPTION 'Método de depósito no válido.';
  END IF;

  FOREACH v_path IN ARRAY p_proof_paths LOOP
    IF v_path !~ ('^'||v_uid::text||'/'||p_deposit_id::text||'/[a-f0-9-]{36}[.](jpg|jpeg|png|webp)$') THEN
      RAISE EXCEPTION 'La ruta de uno de los comprobantes no es válida.';
    END IF;

    IF NOT EXISTS (
      SELECT 1
      FROM storage.objects so
      WHERE so.bucket_id = 'payment-proofs'
        AND so.name = v_path
    ) THEN
      RAISE EXCEPTION 'No encontramos uno de los archivos subidos.';
    END IF;

    INSERT INTO public.wallet_deposit_proofs(deposit_id,user_id,proof_path)
    VALUES(p_deposit_id,v_uid,v_path)
    ON CONFLICT(deposit_id,proof_path) DO NOTHING;

    GET DIAGNOSTICS v_inserted = ROW_COUNT;
    v_count := v_count + v_inserted;
  END LOOP;

  UPDATE public.wallet_deposits
  SET proof_path = coalesce(proof_path,p_proof_paths[1]),
      payment_reference = CASE WHEN v_deposit.payment_method = 'Transferencia CUP' THEN v_reference ELSE v_txid END,
      sender_phone = CASE WHEN v_deposit.payment_method = 'Transferencia CUP' THEN v_phone ELSE NULL END,
      txid = CASE WHEN v_deposit.payment_method = 'USDT' THEN v_txid ELSE NULL END,
      network = CASE WHEN v_deposit.payment_method = 'USDT' THEN 'BNB Smart Chain (BEP20)' ELSE NULL END,
      status = 'payment_review'
  WHERE id = p_deposit_id
    AND user_id = v_uid;

  RETURN jsonb_build_object(
    'deposit_id',p_deposit_id,
    'status','payment_review',
    'proofs_received',v_count
  );
END;
$function$


GRANT USAGE ON SCHEMA private TO authenticated;
REVOKE ALL PRIVILEGES ON FUNCTION private.create_wallet_order(uuid,text,text,uuid,uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION private.create_wallet_order(uuid,text,text,uuid,uuid) TO authenticated;
REVOKE ALL PRIVILEGES ON FUNCTION private.submit_payment_proof(uuid,text,text,text,numeric) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION private.submit_payment_proof(uuid,text,text,text,numeric) TO authenticated;
REVOKE ALL PRIVILEGES ON FUNCTION private.submit_wallet_deposit_proofs(uuid,text[],text,text,text,text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION private.submit_wallet_deposit_proofs(uuid,text[],text,text,text,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.create_wallet_order(p_product_id uuid, p_player_id text, p_player_name text DEFAULT ''::text, p_player_id_validation_token uuid DEFAULT NULL::uuid, p_request_id uuid DEFAULT NULL::uuid)
RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path TO ''
AS $function$ SELECT private.create_wallet_order($1,$2,$3,$4,$5); $function$;

CREATE OR REPLACE FUNCTION public.submit_payment_proof(p_order_id uuid, p_proof_path text, p_reference text, p_sender_phone text, p_reported_amount numeric)
RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path TO ''
AS $function$ SELECT private.submit_payment_proof($1,$2,$3,$4,$5); $function$;

CREATE OR REPLACE FUNCTION public.submit_wallet_deposit_proofs(p_deposit_id uuid, p_proof_paths text[], p_reference text DEFAULT NULL::text, p_sender_phone text DEFAULT NULL::text, p_txid text DEFAULT NULL::text, p_network text DEFAULT NULL::text)
RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path TO ''
AS $function$ SELECT private.submit_wallet_deposit_proofs($1,$2,$3,$4,$5,$6); $function$;

REVOKE ALL PRIVILEGES ON FUNCTION public.create_wallet_order(uuid,text,text,uuid,uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.create_wallet_order(uuid,text,text,uuid,uuid) TO authenticated;
REVOKE ALL PRIVILEGES ON FUNCTION public.submit_payment_proof(uuid,text,text,text,numeric) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.submit_payment_proof(uuid,text,text,text,numeric) TO authenticated;
REVOKE ALL PRIVILEGES ON FUNCTION public.submit_wallet_deposit_proofs(uuid,text[],text,text,text,text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.submit_wallet_deposit_proofs(uuid,text[],text,text,text,text) TO authenticated;

-- Pause the one catalog refresh before recreating pg_net. The request queue
-- was empty before the move; stored HTTP response cache rows are disposable.
DO $migration$
DECLARE v_job_count integer;
BEGIN
  SELECT count(*) INTO v_job_count FROM cron.job WHERE jobname='central-one-catalog-refresh';
  IF v_job_count <> 1 THEN
    RAISE EXCEPTION 'Expected exactly one central-one-catalog-refresh job; aborting pg_net move.';
  END IF;
  IF NOT cron.unschedule('central-one-catalog-refresh') THEN
    RAISE EXCEPTION 'Could not pause central-one-catalog-refresh.';
  END IF;
END;
$migration$;

DROP EXTENSION pg_net;
CREATE EXTENSION pg_net WITH SCHEMA extensions;

-- pg_net's net schema is not exposed through Supabase Data API. Its managed
-- schema/object ACLs are owned by supabase_admin on hosted projects.

SELECT cron.schedule(
  'central-one-catalog-refresh',
  '*/15 * * * *',
  $cron$
    select net.http_post(
      url := 'https://kfllglkfncebpknnugnx.supabase.co/functions/v1/central-one-sync',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-sync-token', (select decrypted_secret from vault.decrypted_secrets where name = 'central_one_sync_token')
      ),
      body := '{"action":"catalog"}'::jsonb,
      timeout_milliseconds := 45000
    );
  $cron$
);
