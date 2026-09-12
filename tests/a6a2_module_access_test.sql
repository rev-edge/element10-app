-- Element 10 — A6a.2 effective module-access truth table. Self-failing and transactionally rolled back.
-- Requires the CI-provisioned local members. Run as postgres after provision_rls_users.js.

begin;
do $$
declare
  v_org uuid := 'e1000000-0000-4000-8000-0000000000a6'::uuid;
  v_user uuid;
  v_role uuid;
begin
  select id into v_user
    from auth.users u
   where not exists (select 1 from public.e10_platform_admins p where p.user_id = u.id)
   order by u.created_at
   limit 1;
  select id into v_role
    from public.e10_organization_roles
   where organization_id = v_org and key = 'manager';

  if v_user is null or v_role is null then
    raise exception 'A6a.2 requires a provisioned auth user and the org0 manager role';
  end if;

  insert into public.e10_organization_memberships (organization_id, user_id, role_id, status)
    values (v_org, v_user, v_role, 'active')
    on conflict (organization_id, user_id) do update set role_id = excluded.role_id, status = 'active';

  select m.user_id, m.role_id into v_user, v_role
    from public.e10_organization_memberships m
   where m.organization_id = v_org
     and m.status = 'active'
     and not exists (select 1 from public.e10_platform_admins p where p.user_id = m.user_id)
   order by m.created_at
   limit 1;

  perform set_config('request.jwt.claims', json_build_object('sub', v_user::text, 'role', 'authenticated')::text, true);

  -- Both present: enabled core entitlement + exact mod.toolkit grant.
  insert into public.e10_organization_modules (organization_id, module_key, enabled)
    values (v_org, 'core', true)
    on conflict (organization_id, module_key) do update set enabled = true;
  insert into public.e10_organization_role_permissions (organization_id, role_id, capability, allowed)
    values (v_org, v_role, 'mod.toolkit', true)
    on conflict (organization_id, role_id, capability) do update set allowed = true;
  if not e10.has_module_access(v_org, 'toolkit') then
    raise exception 'A6a.2 FAIL: enabled entitlement + granted capability must allow';
  end if;

  -- Disabled entitlement + granted capability: deny.
  update public.e10_organization_modules
     set enabled = false
   where organization_id = v_org and module_key = 'core';
  if e10.has_module_access(v_org, 'toolkit') then
    raise exception 'A6a.2 FAIL: disabled entitlement must deny despite granted capability';
  end if;

  -- Enabled entitlement + missing capability: deny.
  update public.e10_organization_modules
     set enabled = true
   where organization_id = v_org and module_key = 'core';
  delete from public.e10_organization_role_permissions
   where organization_id = v_org and role_id = v_role and capability = 'mod.toolkit';
  if e10.has_module_access(v_org, 'toolkit') then
    raise exception 'A6a.2 FAIL: missing capability must deny despite enabled entitlement';
  end if;

  raise notice 'A6a.2 module access: PASS (both=true, disabled=false, missing=false)';
end $$;
rollback;

do $$ begin
  if has_function_privilege('anon', 'e10.has_module_access(uuid,text)', 'execute')
     or has_function_privilege('public', 'e10.has_module_access(uuid,text)', 'execute') then
    raise exception 'A6a.2 FAIL: has_module_access is anon/PUBLIC executable';
  end if;
end $$;
