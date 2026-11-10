-- Public browser roles should not need table-level DDL/maintenance privileges.
-- RLS does not apply to TRUNCATE, so remove these capabilities explicitly.
REVOKE TRUNCATE, REFERENCES, TRIGGER, MAINTAIN
ON ALL TABLES IN SCHEMA public
FROM anon, authenticated;
