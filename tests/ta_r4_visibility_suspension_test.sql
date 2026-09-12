\set ON_ERROR_STOP on
begin;
do $$
declare o uuid:=gen_random_uuid();u uuid:=gen_random_uuid();r uuid:=gen_random_uuid();release_id uuid:=gen_random_uuid();n integer;
begin
 insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at)values(u,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',u||'@r4.invalid',now(),now());
 insert into public.e10_organizations(id,slug,name)values(o,'r4-'||substr(o::text,1,8),'R4');
 insert into public.e10_organization_roles(id,organization_id,key,name,is_system)values(r,o,'r4','R4',false);
 insert into public.e10_organization_memberships(organization_id,user_id,role_id,status)values(o,u,r,'active');
 insert into public.e10_organization_role_permissions(organization_id,role_id,capability,allowed)values
  (o,r,'act.purchasing_prepare',true),(o,r,'act.create_receiving',true);
 insert into public.e10_catalog_releases(id,release_name)values(release_id,'R4 shared release');
 perform set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated')::text,true);set local role authenticated;
 select count(*)into n from public.e10_catalog_releases where id=release_id;if n<>1 then raise exception'shared catalog hidden from active member';end if;
 reset role;
 if e10.can_access_commercial_comments(o,'supplier_invoice')then raise exception'invoice comments exposed without actual-cost authority';end if;
 if not e10.can_access_commercial_comments(o,'purchase_order')or not e10.can_access_commercial_comments(o,'stock_receipt')then raise exception'document authority mapping denied';end if;
 insert into public.e10_organization_role_permissions values(o,r,'financial.actual_cost.read',true);
 if not e10.can_access_commercial_comments(o,'supplier_invoice')then raise exception'invoice authority not recognized';end if;
 update public.e10_organizations set status='suspended'where id=o;
 if e10.has_org_cap(o,'act.purchasing_prepare')then raise exception'suspended organization retained capability';end if;
 set local role authenticated;
 begin perform public.e10_org_purchase_destinations(o);raise exception'suspended X2 API allowed';exception when insufficient_privilege then null;end;
 begin perform public.e10_org_list_commercial_comments(o,'purchase_order',gen_random_uuid(),10,null,null);raise exception'suspended X3 API allowed';exception when insufficient_privilege then null;end;
 reset role;
 if not exists(select 1 from pg_policies where schemaname='public'and tablename='e10_catalog_releases'and qual='e10.has_any_active_org_membership()')then raise exception'catalog policy still depends on current_org';end if;
end $$;
rollback;
select 'TA-R4 visibility/suspension: PASS' result;
