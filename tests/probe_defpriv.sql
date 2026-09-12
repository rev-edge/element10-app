-- Element 10 — default-function-privileges REGRESSION probe (CI, runs against the ephemeral local stack).
-- Guards the A5.1a invariant that never re-opens: new public functions are born executable ONLY by service_role
-- (+ owner) — not anon, not authenticated. Must be run AS THE MIGRATION ROLE (postgres). Self-failing: any
-- violation RAISEs, so `psql -v ON_ERROR_STOP=1` exits non-zero and the CI job fails. Also a belt-and-suspenders
-- scan (the safeguard against the unalterable supabase_admin grantor path): zero public functions may be
-- anon/PUBLIC-executable. Run: psql "<local db url>" -v ON_ERROR_STOP=1 -f tests/probe_defpriv.sql
do $$
begin
  -- create a throwaway function as the migration role and assert it is born locked
  create function public._e10_probe_defpriv() returns int language sql as 'select 42';

  if has_function_privilege('anon', 'public._e10_probe_defpriv()', 'execute') then
    raise exception 'REGRESSION: a newly created function is anon-executable — the default-privileges factory has re-opened';
  end if;
  if has_function_privilege('authenticated', 'public._e10_probe_defpriv()', 'execute') then
    raise exception 'REGRESSION: a newly created function is authenticated-executable by default (should require an explicit grant)';
  end if;
  if not has_function_privilege('service_role', 'public._e10_probe_defpriv()', 'execute') then
    raise exception 'REGRESSION: service_role lost EXECUTE on a newly created function';
  end if;

  -- an explicit grant to authenticated must still work (intended-public APIs opt in)
  grant execute on function public._e10_probe_defpriv() to authenticated;
  if not has_function_privilege('authenticated', 'public._e10_probe_defpriv()', 'execute') then
    raise exception 'REGRESSION: an explicit GRANT EXECUTE TO authenticated did not take effect';
  end if;

  drop function public._e10_probe_defpriv();

  -- whole-surface scan: NO public function may be anon/PUBLIC-executable (catches anything that slipped in,
  -- including via the supabase_admin-grantor default we cannot alter)
  if exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('public', p.oid, 'execute'))
  ) then
    raise exception 'REGRESSION: public function(s) are anon/PUBLIC-executable: %',
      (select string_agg(p.proname, ', ') from pg_proc p join pg_namespace n on n.oid = p.pronamespace
       where n.nspname = 'public'
         and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('public', p.oid, 'execute')));
  end if;

  raise notice 'default-privileges probe: PASS (born-locked 4/4 + zero anon/PUBLIC-executable functions)';
end $$;
