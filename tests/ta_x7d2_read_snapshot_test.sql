\set ON_ERROR_STOP on
begin;
do $$declare o uuid:=gen_random_uuid();u uuid:=gen_random_uuid();r uuid:=gen_random_uuid();s record;begin
 insert into auth.users(id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)values(u,'authenticated','authenticated','x7d-snapshot@example.invalid','',now(),'{}','{}',now(),now());
 insert into public.e10_organizations(id,slug,name)values(o,'x7d-snap-'||substr(o::text,1,8),'X7d Snapshot');insert into public.e10_organization_roles(id,organization_id,key,name)values(r,o,'reader','Reader');insert into public.e10_organization_memberships(organization_id,user_id,role_id,status)values(o,u,r,'active');
 perform set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated')::text,true);
 begin perform e10.lock_market_read_snapshot(o);raise exception'missing cap read allowed';exception when insufficient_privilege then null;end;
 insert into public.e10_organization_role_permissions(organization_id,role_id,capability,allowed)values(o,r,'act.view_market_analytics',true);
 select*into s from e10.lock_market_read_snapshot(o);if s.actor_id<>u or s.organization_revision is null or s.catalog_revision is null then raise exception'snapshot capture failed';end if;
 update public.e10_organization_memberships set status='suspended'where organization_id=o and user_id=u;begin perform e10.lock_market_read_snapshot(o);raise exception'suspended member read allowed';exception when insufficient_privilege then null;end;
 if has_function_privilege('anon','e10.lock_market_read_snapshot(uuid)','execute')or has_function_privilege('authenticated','e10.lock_market_read_snapshot(uuid)','execute')then raise exception'snapshot helper ACL leak';end if;
end $$;
rollback;
select'TA-X7d.2 read snapshot PASS'as result;
