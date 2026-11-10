-- The Central One order Edge Function reads the local order via PostgREST
-- before asking the provider for its latest status. Keep public roles unchanged;
-- grant only the server-side role the SELECT privilege it needs.
GRANT SELECT ON TABLE public.orders TO service_role;
