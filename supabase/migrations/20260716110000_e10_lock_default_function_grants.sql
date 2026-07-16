-- Foundation Gate A5.1a — close the default-function-privileges factory.
-- DB-verified: new public functions are born EXECUTE-able by anon+authenticated via TWO sources —
--   (1) PostgreSQL's built-in default: EXECUTE to PUBLIC (anon ∈ PUBLIC). This is a DATABASE-LEVEL default;
--       a schema-scoped `ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ... FROM PUBLIC` does NOT override it
--       (verified on PG 17.6 — the built-in PUBLIC persisted until revoked at the database level).
--   (2) Supabase's explicit schema-level default grants of EXECUTE to anon + authenticated.
-- A4 fixed EXISTING functions; without this, every FUTURE function (all of A6's RPC surface) is born
-- anonymously executable unless its migration remembers to revoke. Fix BOTH sources so functions are born
-- non-executable; intended-public APIs must then GRANT EXECUTE TO authenticated explicitly (documented in SECURITY.md).
--
-- Scope note (flag, not fake): this targets the `postgres` grantor (the migration role; every migration-created
-- function is created BY postgres). A SECOND grantor exists on this project (supabase_admin) whose default also
-- grants anon/authenticated, but `postgres` is NOT a member of supabase_admin so the migration role cannot alter
-- it — and it only governs supabase_admin-created objects (extensions/internals) we never author. Left as-is by design.
--
-- Touches no data. Reversible — see supabase/recovery/a5_1a_default_grants_down.sql (rolling back REOPENS the factory).

begin;

-- (1) remove the database-level built-in PUBLIC EXECUTE default (the source a schema-scoped revoke can't reach)
alter default privileges revoke execute on functions from public;

-- (2) remove Supabase's explicit schema-level anon/authenticated default grants
alter default privileges in schema public revoke execute on functions from anon, authenticated;

-- cleanup: two pre-existing SECURITY INVOKER helpers still carried PUBLIC EXECUTE (an A4 miss) — lock to
-- authenticated so the post-state is genuinely zero anon/PUBLIC-executable functions.
revoke execute on function public.e10_slot_cards(uuid, jsonb, integer) from anon, public;
revoke execute on function public.e10_slot_partition(uuid, jsonb)       from anon, public;

commit;

-- ============================================================================
-- DOWN (restores the prior, LESS-SECURE state — REOPENS the anon-executable factory):
-- begin;
-- alter default privileges grant execute on functions to public;                                  -- restore built-in PUBLIC
-- alter default privileges in schema public grant execute on functions to anon, authenticated;    -- restore Supabase grants
-- grant execute on function public.e10_slot_cards(uuid, jsonb, integer) to anon;
-- grant execute on function public.e10_slot_partition(uuid, jsonb)       to anon;
-- commit;
