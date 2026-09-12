\set ON_ERROR_STOP on
begin;
do $$
declare o uuid:=gen_random_uuid();o2 uuid:=gen_random_uuid();o3 uuid:=gen_random_uuid();u uuid:=gen_random_uuid();r uuid:=gen_random_uuid();r2 uuid:=gen_random_uuid();v_release uuid:=gen_random_uuid();v_variant uuid:=gen_random_uuid();player_id uuid:=gen_random_uuid();product3 uuid:=gen_random_uuid();n integer;
begin
 insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at)values(u,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',u||'@r4.invalid',now(),now());
 insert into public.e10_organizations(id,slug,name)values(o,'r4-'||substr(o::text,1,8),'R4'),(o2,'r4-'||substr(o2::text,1,8),'R4 second'),(o3,'r4-'||substr(o3::text,1,8),'R4 foreign');
 insert into public.e10_organization_roles(id,organization_id,key,name,is_system)values(r,o,'r4','R4',false),(r2,o2,'r4','R4 second',false);
 insert into public.e10_organization_memberships(organization_id,user_id,role_id,status)values(o,u,r,'active'),(o2,u,r2,'active');
 insert into public.e10_organization_role_permissions(organization_id,role_id,capability,allowed)values
  (o,r,'act.purchasing_prepare',true),(o,r,'act.create_receiving',true);
 insert into public.e10_catalog_releases(id,release_name)values(v_release,'R4 shared release');
 insert into public.e10_catalog_variants(id,release_id)values(v_variant,v_release);
 insert into public.e10_players(id,name)values(player_id,'R4 shared subject');
 insert into public.e10_catalog_variant_subjects(variant_id,player_id)values(v_variant,player_id);
 insert into public.e10_catalog_identity_mappings(provider,entity_kind,external_id,release_id,match_status)values('r4','release',v_release::text,v_release,'candidate');
 insert into public.e10_product_masters(id,organization_id,name)values(product3,o3,'R4 foreign tenant product');
 perform set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated')::text,true);set local role authenticated;
 if e10.current_org() is not null then raise exception'two memberships unexpectedly selected a current org';end if;
 select (select count(*)from public.e10_catalog_releases cr where cr.id=v_release)+(select count(*)from public.e10_catalog_variants cv where cv.id=v_variant)+(select count(*)from public.e10_catalog_variant_subjects cvs where cvs.variant_id=v_variant)+(select count(*)from public.e10_catalog_identity_mappings cim where cim.provider='r4'and cim.external_id=v_release::text)into n;
 if n<>4 then raise exception'shared catalog policies hidden from two-org member: %',n;end if;
 select count(*)into n from public.e10_product_masters where id=product3;if n<>0 then raise exception'shared catalog eligibility widened tenant-owned products';end if;
 reset role;update public.e10_organizations set status='suspended'where id=o;set local role authenticated;
 select (select count(*)from public.e10_catalog_releases cr where cr.id=v_release)+(select count(*)from public.e10_catalog_variants cv where cv.id=v_variant)+(select count(*)from public.e10_catalog_variant_subjects cvs where cvs.variant_id=v_variant)+(select count(*)from public.e10_catalog_identity_mappings cim where cim.provider='r4'and cim.external_id=v_release::text)into n;
 if n<>4 then raise exception'shared catalog hidden while another membership remained active: %',n;end if;
 reset role;update public.e10_organizations set status='suspended'where id=o2;set local role authenticated;
 select (select count(*)from public.e10_catalog_releases cr where cr.id=v_release)+(select count(*)from public.e10_catalog_variants cv where cv.id=v_variant)+(select count(*)from public.e10_catalog_variant_subjects cvs where cvs.variant_id=v_variant)+(select count(*)from public.e10_catalog_identity_mappings cim where cim.provider='r4'and cim.external_id=v_release::text)into n;
 if n<>0 then raise exception'shared catalog visible with no active organization membership: %',n;end if;
 reset role;update public.e10_organizations set status='active'where id=o;
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
