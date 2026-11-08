CREATE OR REPLACE FUNCTION private.enforce_provider_player_validation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_product public.products%rowtype;
  v_validation public.player_id_validations%rowtype;
  v_hash text;
BEGIN
  SELECT * INTO v_product
  FROM public.products
  WHERE id = NEW.product_id
  LIMIT 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'El producto no existe.';
  END IF;

  -- Free Fire must never use the legacy no-provider path: every FF order
  -- requires a supported Central One product and a single-use validation token.
  IF lower(btrim(coalesce(v_product.game, ''))) = 'free fire'
     AND v_product.provider_product_id IS NULL THEN
    RAISE EXCEPTION 'El paquete de Free Fire no está vinculado con Central One. No se puede crear el pedido.';
  END IF;

  IF v_product.provider_product_id IS NULL THEN
    IF NEW.provider_product_id IS NOT NULL
       OR NEW.player_id_validation_token IS NOT NULL
       OR coalesce(NEW.player_id_validated, false) THEN
      RAISE EXCEPTION 'No se puede asociar una validación de proveedor a este producto.';
    END IF;
    NEW.provider_product_id := NULL;
    NEW.provider_region := NULL;
    NEW.player_id_validated := false;
    NEW.player_id_validated_at := NULL;
    NEW.player_id_validation_token := NULL;
    RETURN NEW;
  END IF;

  IF NOT v_product.active
     OR NOT coalesce(v_product.provider_validation_supported, false)
     OR lower(coalesce(v_product.provider_status, '')) <> 'active'
     OR v_product.provider_in_stock IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'El paquete no está habilitado para validación y venta.';
  END IF;

  IF NEW.provider_product_id IS DISTINCT FROM v_product.provider_product_id
     OR upper(coalesce(NEW.provider_region, '')) IS DISTINCT FROM upper(coalesce(v_product.provider_region, '')) THEN
    RAISE EXCEPTION 'La región o el producto del pedido no coincide con el catálogo.';
  END IF;

  IF NEW.player_id_validation_token IS NULL THEN
    RAISE EXCEPTION 'Debes verificar el ID del jugador con Central One antes de crear el pedido.';
  END IF;

  v_hash := encode(extensions.digest(convert_to(btrim(NEW.player_id), 'UTF8'), 'sha256'), 'hex');

  SELECT * INTO v_validation
  FROM public.player_id_validations
  WHERE token = NEW.player_id_validation_token
    AND user_id = NEW.user_id
    AND product_id = NEW.product_id
    AND provider_product_id = v_product.provider_product_id
    AND upper(region) = upper(v_product.provider_region)
    AND player_id_hash = v_hash
    AND expires_at > now()
    AND consumed_at IS NULL
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'La validación del ID caducó, ya fue utilizada o no coincide con el paquete.';
  END IF;

  UPDATE public.player_id_validations
  SET consumed_at = now()
  WHERE token = v_validation.token
    AND consumed_at IS NULL;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'La validación ya fue utilizada. Verifica el ID otra vez.';
  END IF;

  NEW.player_id_validated := true;
  NEW.player_id_validated_at := v_validation.validated_at;
  NEW.player_name := coalesce(nullif(v_validation.player_name, ''), NEW.player_name);
  NEW.provider_product_id := v_product.provider_product_id;
  NEW.provider_region := v_product.provider_region;
  RETURN NEW;
END;
$function$;