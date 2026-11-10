-- The Central One order Edge Function reads pricing rules through PostgREST
-- using the server-only service_role key. Keep this table unavailable to anon;
-- grant the backend only the read access it needs, while preserving RLS.
GRANT SELECT ON TABLE public.pricing_settings TO service_role;
