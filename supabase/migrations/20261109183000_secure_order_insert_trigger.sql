-- Keep product cost columns private while allowing the order trigger
-- to validate product availability and calculate the authoritative sale price.
-- The trigger function checks auth.uid() against NEW.user_id before reading
-- the product, and only writes server-derived fields into NEW.
ALTER FUNCTION public.validate_order_request() SET SCHEMA private;

ALTER FUNCTION private.validate_order_request() SECURITY DEFINER;
ALTER FUNCTION private.validate_order_request() SET search_path TO '';

-- This is a trigger-only function, not a client RPC endpoint.
REVOKE ALL PRIVILEGES ON FUNCTION private.validate_order_request()
FROM PUBLIC, anon, authenticated, service_role;
