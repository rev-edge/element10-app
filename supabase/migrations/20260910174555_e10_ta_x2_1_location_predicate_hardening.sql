-- TA-X2.1 forward corrective: an admin bypasses role grants, not location identity.
create or replace function e10.can_receive_at(p_org uuid, p_location uuid)
returns boolean
language sql stable security definer set search_path=public as $$
  select exists (
    select 1 from public.e10_locations l
    where l.organization_id=p_org and l.id=p_location and l.status='active'
      and (
        e10.is_org_admin(p_org)
        or exists (
          select 1
          from public.e10_organization_memberships m
          join public.e10_location_role_permissions p
            on p.organization_id=m.organization_id and p.role_id=m.role_id
          where m.organization_id=p_org and m.user_id=auth.uid() and m.status='active'
            and p.location_id=l.id and p.can_receive
        )
      )
  );
$$;
revoke all on function e10.can_receive_at(uuid,uuid) from public,anon;
grant execute on function e10.can_receive_at(uuid,uuid) to authenticated,service_role;
