-- Foundation Gate A2: fail-closed schema-version handshake. The client reads e10_schema_version() on boot
-- and refuses mutations (read-only banner) if its built-in SCHEMA_VERSION does not match. Bump the returned
-- value in the SAME migration that changes the client-visible schema contract, and update the client's
-- SCHEMA_VERSION constant + redeploy. This makes an app-vs-schema mismatch fail closed instead of silently
-- corrupting data (the M4-incident class).
create or replace function public.e10_schema_version()
  returns text language sql stable security definer set search_path to 'public' as $$
  select '2026-07-15.fg1'::text;
$$;
revoke all on function public.e10_schema_version() from public, anon;
grant execute on function public.e10_schema_version() to authenticated;
