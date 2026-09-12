\set ON_ERROR_STOP on
begin;
do $$
declare o uuid:=gen_random_uuid();other_o uuid:=gen_random_uuid();u uuid:=gen_random_uuid();v_role uuid:=gen_random_uuid();
  p jsonb;c jsonb;v jsonb;i jsonb;product_id uuid;config_id uuid;
begin
  insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at)values(u,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',u||'@r5.invalid',now(),now());
  insert into public.e10_organizations(id,slug,name)values(o,'r5-'||left(o::text,8),'R5'),(other_o,'r5-'||left(other_o::text,8),'R5 other');
  insert into public.e10_organization_roles(id,organization_id,key,name)values(v_role,o,'r5','R5');
  insert into public.e10_organization_memberships(organization_id,user_id,role_id,status)values(o,u,v_role,'active');
  insert into public.e10_organization_role_permissions values(o,v_role,'catalog.propose',true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated')::text,true);set local role authenticated;
  p:=public.e10_org_create_product_master(o,'R5 Product',' R5-P ','{"kind":"sealed"}','r5-product');product_id:=(p->>'product_master_id')::uuid;
  if not (public.e10_org_create_product_master(o,'R5 Product',' R5-P ','{"kind":"sealed"}',' r5-product ')->>'replay')::boolean then raise exception'product replay failed';end if;
  c:=public.e10_org_create_product_configuration(o,product_id,'Hobby Box','R5-C','{}','r5-config');config_id:=(c->>'configuration_id')::uuid;
  v:=public.e10_org_create_configuration_version(o,config_id,0,'draft','box','each',24,'R5-BC','{}','r5-version');
  begin perform public.e10_org_create_configuration_version(o,config_id,0,'draft','box','each',24,null,'{}','r5-version-stale');raise exception'stale configuration version accepted';exception when sqlstate'40001'then null;end;
  i:=public.e10_org_create_unique_item(o,null,null,'collectible','new',null,null,null,null,'{}','{}','r5-item');
  begin perform public.e10_org_create_configuration_version(o,config_id,1,null,'box','each',1,null,'{}','r5-null-state');raise exception'null configuration state accepted';exception when sqlstate'22023'then null;end;
  begin perform public.e10_org_create_configuration_version(o,config_id,1,'draft','box','each','Infinity'::numeric,null,'{}','r5-infinite');raise exception'infinite package quantity accepted';exception when sqlstate'22023'then null;end;
  begin perform public.e10_org_create_unique_item(o,null,null,'collectible',null,null,null,null,null,'{}',jsonb_build_object('oversized',repeat('x',66000)),'r5-oversized');raise exception'oversized attributes accepted';exception when sqlstate'22023'then null;end;
  if product_id is null or config_id is null or (v->>'version_no')::integer<>1 or i->>'unique_item_id'is null then raise exception'X1 writer result invalid';end if;
  begin perform public.e10_org_create_product_master(o,'changed',null,'{}','r5-product');raise exception'idempotency mismatch accepted';exception when sqlstate'22023'then null;end;
  begin perform public.e10_org_create_product_master(other_o,'foreign',null,'{}','r5-foreign');raise exception'cross-org create accepted';exception when sqlstate'42501'then null;end;
  begin insert into public.e10_product_masters(organization_id,name)values(o,'direct');raise exception'direct authenticated write accepted';exception when insufficient_privilege then null;end;
  reset role;delete from public.e10_organization_role_permissions where organization_id=o and role_id=v_role and capability='catalog.propose';set local role authenticated;
  begin perform public.e10_org_create_product_master(o,'R5 Product',' R5-P ','{"kind":"sealed"}','r5-product');raise exception'revoked replay accepted';exception when sqlstate'42501'then null;end;
  reset role;
  if has_table_privilege('authenticated','public.e10_x1_creation_commands','select')or has_function_privilege('anon','public.e10_org_create_product_master(uuid,text,text,jsonb,text)','execute')then raise exception'X1 writer ACL closure failed';end if;
  if (select count(*)from public.e10_x1_creation_commands where authority_scope=o)<>4 then raise exception'X1 command cardinality invalid';end if;
end $$;
rollback;
select 'TA-R5 supported tenant X1 writers: PASS' result;
