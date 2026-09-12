\set ON_ERROR_STOP on
begin;

do $$
declare n bigint;org uuid;role_id uuid;
begin
  select count(*) into n from public.e10_organization_role_permissions p
  left join public.e10_capabilities c on c.capability_key=p.capability
  where c.capability_key is null;
  if n<>0 then raise exception 'uncataloged persisted grants: %',n;end if;
  if exists(select 1 from pg_constraint where conname='e10_organization_role_permissions_capability_fkey'and not convalidated)then
    raise exception 'permission capability FK not validated';end if;
  if exists(select 1 from pg_constraint where conname in('e10_custom_field_definitions_read_capability_fkey','e10_custom_field_definitions_write_capability_fkey')and not convalidated)then
    raise exception 'custom-field capability FK not validated';end if;
  if (select count(*) from public.e10_capabilities where capability_key in('catalog.propose','catalog.review','catalog.publish'))<>3 then
    raise exception 'catalog operation vocabulary missing';end if;
  if exists(select 1 from public.e10_capabilities where capability_key in('catalog.review','catalog.publish')and authority_scope<>'platform')
    or exists(select 1 from public.e10_capabilities where capability_key='catalog.propose'and authority_scope<>'organization')then
    raise exception 'catalog authority scopes incorrect';end if;
  if exists(select 1 from public.e10_organization_role_permissions where capability in('catalog.propose','catalog.review','catalog.publish','receiving.over_accept'))then
    raise exception 'reserved capability received an unapproved default grant';end if;

  select organization_id,id into org,role_id from public.e10_organization_roles order by organization_id,id limit 1;
  insert into public.e10_organization_role_permissions(organization_id,role_id,capability,allowed)
  values(org,role_id,'catalog.propose',false);
  if e10.has_org_cap(org,'catalog.propose') then raise exception 'false row granted authority';end if;
  begin
    insert into public.e10_organization_role_permissions(organization_id,role_id,capability,allowed)
    values(org,role_id,'catalog.publish',true);
    raise exception 'platform capability accepted in tenant role';
  exception when check_violation then
    if sqlerrm<>'organization_capability_not_grantable' then raise;end if;
  end;
  begin
    insert into public.e10_organization_role_permissions(organization_id,role_id,capability,allowed)
    values(org,role_id,'invented.capability',true);
    raise exception 'unknown capability accepted';
  exception when check_violation then
    if sqlerrm<>'organization_capability_not_grantable' then raise;end if;
  end;
end $$;

select set_config('request.jwt.claims','{"sub":"c3000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
set local role authenticated;
do $$
begin
  if not exists(select 1 from public.e10_capabilities where capability_key='catalog.propose')then
    raise exception 'organization capability not visible';end if;
  if exists(select 1 from public.e10_capabilities where capability_key in('catalog.review','catalog.publish'))then
    raise exception 'platform capability exposed to ordinary authenticated user';end if;
  begin
    insert into public.e10_capabilities(capability_key,owning_module,operation_group,sensitivity,authority_scope)
    values('invented.write','core','test','ordinary','organization');
    raise exception 'authenticated capability mutation accepted';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;

rollback;
select 'schema review C3 capability catalog PASS' result;
