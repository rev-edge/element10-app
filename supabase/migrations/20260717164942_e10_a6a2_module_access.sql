-- Foundation Gate A6a.2 — effective module access predicate (STAGING/LOCAL only; production untouched).
-- Additive and idempotent. Preserves A6a.1's confirmed mapping: all six legacy module keys map to `core`.
-- Effective access requires BOTH an enabled organization entitlement and the exact role capability.

create or replace function e10.has_module_access(org uuid, p_key text) returns boolean
  language sql stable security definer set search_path = public as $$
  select exists (
    select 1
      from public.e10_organization_modules m
     where m.organization_id = org
       and m.module_key = e10.module_bundle(p_key)
       and m.enabled = true
  ) and e10.has_org_cap(org, 'mod.' || p_key);
$$;

revoke all on function e10.has_module_access(uuid, text) from anon, public;
grant execute on function e10.has_module_access(uuid, text) to authenticated;
