\set ON_ERROR_STOP on
begin;

do $$
declare
 actor uuid:='c6000000-0000-4000-8000-000000000001';
 outsider uuid:='c6000000-0000-4000-8000-000000000002';
 org uuid:='c6000000-0000-4000-8000-000000000003';
 role_id uuid:='c6000000-0000-4000-8000-000000000004';
 expected timestamptz;suspended_revision timestamptz;result jsonb;
begin
 insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at)values
 (actor,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','c6-admin@example.invalid',now(),now()),
 (outsider,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','c6-member@example.invalid',now(),now());
 insert into public.e10_platform_admins(user_id)values(actor);
 insert into public.e10_organizations(id,slug,name,created_by)values(org,'c6-org','C6 Org',actor);
 insert into public.e10_organization_roles(id,organization_id,key,name,is_system)values(role_id,org,'member','Member',false);
 insert into public.e10_organization_memberships(organization_id,user_id,role_id,status)values(org,outsider,role_id,'active');
 if(select count(*) from public.e10_organization_status_transitions where organization_id=org)<>1 then raise exception 'new organization baseline missing';end if;
 select updated_at into expected from public.e10_organizations where id=org;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',outsider,'role','authenticated')::text,true);
 begin
  perform public.e10_platform_set_organization_status(org,expected,'suspended','test','{}','c6-suspend');
  raise exception 'ordinary member changed organization status';
 exception when insufficient_privilege then if sqlerrm<>'organization_status_change_denied'then raise;end if;end;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',actor,'role','authenticated')::text,true);
 result:=public.e10_platform_set_organization_status(org,expected,'suspended','policy hold','{"ticket":"C6"}','c6-suspend');
 if result->>'replay'<>'false'or(select status from public.e10_organizations where id=org)<>'suspended'
  or not(select suspension_time_known and suspended_at is not null from public.e10_organizations where id=org)
  or(select count(*) from public.e10_organization_status_transitions where organization_id=org)<>2 then raise exception 'suspension state/history mismatch';end if;
 select updated_at into suspended_revision from public.e10_organizations where id=org;
 result:=public.e10_platform_set_organization_status(org,expected,'suspended','policy hold','{"ticket":"C6"}','c6-suspend');
 if result->>'replay'<>'true'then raise exception 'suspension replay mismatch';end if;
 begin
  perform public.e10_platform_set_organization_status(org,expected,'active','stale','{}','c6-stale');
  raise exception 'stale resume accepted';
 exception when serialization_failure then if sqlerrm<>'organization_status_revision_conflict'then raise;end if;end;
 result:=public.e10_platform_set_organization_status(org,suspended_revision,'active','hold cleared','{}','c6-resume');
 if result->>'replay'<>'false'or(select status from public.e10_organizations where id=org)<>'active'
  or exists(select 1 from public.e10_organizations where id=org and(suspended_at is not null or suspension_time_known))
  or(select count(*) from public.e10_organization_status_transitions where organization_id=org)<>3 then raise exception 'resume state/history mismatch';end if;
 if exists(select 1 from public.e10_organization_status_transitions where organization_id=org and revision=2 and(transition_type<>'suspend'or from_status<>'active'or to_status<>'suspended'or not effective_time_known or effective_at is null))
  or exists(select 1 from public.e10_organization_status_transitions where organization_id=org and revision=3 and(transition_type<>'resume'or from_status<>'suspended'or to_status<>'active'))then raise exception 'transition semantics mismatch';end if;
end$$;

do $$begin
 if has_function_privilege('anon','public.e10_platform_set_organization_status(uuid,timestamptz,text,text,jsonb,text)','execute')then raise exception 'anonymous organization-status execute leak';end if;
end$$;

rollback;
select 'schema review C6 organization status PASS' result;
