-- TA-R4 completion: every membership-authorized path denies suspended orgs.
create or replace function e10.is_org_member(org uuid) returns boolean
language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.e10_organizations o where o.id=org and o.status='active')
    and (e10.is_platform_admin() or exists(
      select 1 from public.e10_organization_memberships m
      where m.organization_id=org and m.user_id=auth.uid() and m.status='active'));
$$;
