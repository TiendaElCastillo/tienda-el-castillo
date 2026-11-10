-- New tables created by postgres must not inherit DDL/maintenance privileges
-- for browser-facing roles. Keep normal RLS-protected CRUD grants unchanged.
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
REVOKE TRUNCATE, REFERENCES, TRIGGER, MAINTAIN
ON TABLES FROM anon, authenticated;
