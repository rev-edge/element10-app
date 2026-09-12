-- TA-X2 location/supplier foundation gate. Self-failing and transactionally rolled back.
begin;

do $$
declare
  org_a uuid := 'e1000000-0000-4000-8000-0000000000a6';
  role_b uuid;
  user_member uuid := 'a7000000-0000-4000-8000-00000000e2a1';
  user_admin uuid := 'a7000000-0000-4000-8000-00000000e2a2';
  user_nogrant uuid := 'a7000000-0000-4000-8000-00000000e2a3';
  user_b uuid := 'a7000000-0000-4000-8000-00000000e2b1';
  org_b uuid := 'e1000000-0000-4000-8000-00000000e2b0';
  loc_a uuid := 'a7000000-0000-4000-8000-00000000e211';
  loc_b uuid := 'a7000000-0000-4000-8000-00000000e212';
  loc_inactive uuid := 'a7000000-0000-4000-8000-00000000e213';
  loc_foreign uuid := 'a7000000-0000-4000-8000-00000000e214';
  product_a uuid := 'a7000000-0000-4000-8000-00000000e221';
  config_a uuid := 'a7000000-0000-4000-8000-00000000e222';
  version_a uuid := 'a7000000-0000-4000-8000-00000000e223';
  supplier_a uuid := 'a7000000-0000-4000-8000-00000000e231';
  supplier_b uuid := 'a7000000-0000-4000-8000-00000000e232';
begin
  insert into public.e10_organizations(id,name,slug)
    values (org_b,'TA-X2 Org B','ta-x2-org-b') on conflict do nothing;
  insert into public.e10_organization_roles(organization_id,key,name)
    values (org_b,'member','Member') returning id into role_b;
  insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at)
    select u,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',
      replace(u::text,'-','')||'@ta-x2.invalid',now(),now()
    from unnest(array[user_member,user_admin,user_nogrant,user_b]) u on conflict (id) do nothing;
  insert into public.e10_organization_memberships(organization_id,user_id,role_id,status) values
    (org_a,user_member,'e1000000-0000-4000-8000-000000000003','active'),
    (org_a,user_admin,'e1000000-0000-4000-8000-000000000001','active'),
    (org_a,user_nogrant,'e1000000-0000-4000-8000-000000000004','active'),
    (org_b,user_b,role_b,'active')
    on conflict (organization_id,user_id) do update set role_id=excluded.role_id,status='active';

  insert into public.e10_locations(id,organization_id,code,name,status) values
    (loc_a,org_a,'A','Alpha Receiving','active'),
    (loc_b,org_a,'B','Beta Receiving','active'),
    (loc_inactive,org_a,'C','Closed Receiving','inactive'),
    (loc_foreign,org_b,'D','Foreign Receiving','active');
  insert into public.e10_location_role_permissions(organization_id,location_id,role_id,can_receive) values
    (org_a,loc_a,'e1000000-0000-4000-8000-000000000003',true),
    (org_a,loc_inactive,'e1000000-0000-4000-8000-000000000003',true);

  insert into public.e10_product_masters(id,organization_id,name) values (product_a,org_a,'TA-X2 Product');
  insert into public.e10_product_configurations(id,organization_id,product_master_id,name)
    values (config_a,org_a,product_a,'TA-X2 Box');
  insert into public.e10_product_configuration_versions(
    id,organization_id,configuration_id,version_no,state,packaging_kind,base_unit,base_units_per_package
  ) values (version_a,org_a,config_a,1,'active','box','unit',1);
  insert into public.e10_suppliers(id,organization_id,code,name) values
    (supplier_a,org_a,'SUP-A','Supplier A'),(supplier_b,org_b,'SUP-B','Supplier B');
  insert into public.e10_supplier_offerings(
    organization_id,supplier_id,configuration_version_id,vendor_item_code,currency
  ) values (org_a,supplier_a,version_a,'VENDOR-A','CAD');
end $$;

set local role authenticated;
do $$
declare
  org_a uuid := 'e1000000-0000-4000-8000-0000000000a6';
  user_member uuid := 'a7000000-0000-4000-8000-00000000e2a1';
  user_admin uuid := 'a7000000-0000-4000-8000-00000000e2a2';
  user_nogrant uuid := 'a7000000-0000-4000-8000-00000000e2a3';
  user_b uuid := 'a7000000-0000-4000-8000-00000000e2b1';
  c integer;
  only_flag boolean;
  ok integer := 0;
  bad text := '';
begin
  perform set_config('request.jwt.claims',json_build_object('sub',user_member::text,'role','authenticated')::text,true);
  select count(*),bool_and(sole_eligible and eligible_count=1) into c,only_flag
    from public.e10_org_purchase_destinations(org_a);
  if c=1 and only_flag then ok:=ok+1; else bad:=bad||' member_dest='||c; end if;
  select count(*) into c from public.e10_suppliers where organization_id=org_a;
  if c=1 then ok:=ok+1; else bad:=bad||' member_supplier='||c; end if;
  select count(*) into c from public.e10_suppliers where organization_id<>org_a;
  if c=0 then ok:=ok+1; else bad:=bad||' cross_supplier='||c; end if;

  perform set_config('request.jwt.claims',json_build_object('sub',user_admin::text,'role','authenticated')::text,true);
  if e10.can_receive_at(org_a,'a7000000-0000-4000-8000-00000000e211') then ok:=ok+1; else bad:=bad||' admin_valid_false'; end if;
  if not e10.can_receive_at(org_a,'a7000000-0000-4000-8000-00000000e213') then ok:=ok+1; else bad:=bad||' admin_inactive_true'; end if;
  if not e10.can_receive_at(org_a,'a7000000-0000-4000-8000-00000000efff') then ok:=ok+1; else bad:=bad||' admin_missing_true'; end if;
  if not e10.can_receive_at(org_a,'a7000000-0000-4000-8000-00000000e214') then ok:=ok+1; else bad:=bad||' admin_foreign_true'; end if;
  select count(*),bool_and(not sole_eligible and eligible_count=2) into c,only_flag
    from public.e10_org_purchase_destinations(org_a);
  if c=2 and only_flag then ok:=ok+1; else bad:=bad||' admin_dest='||c; end if;
  select count(*) into c from public.e10_org_purchase_destinations(org_a,'Alpha Receiving','a7000000-0000-4000-8000-00000000e211',1);
  if c=1 then ok:=ok+1; else bad:=bad||' cursor='||c; end if;
  begin perform 1 from public.e10_org_purchase_destinations(org_a,'Alpha Receiving',null,50); bad:=bad||' bad_cursor_allowed';
  exception when invalid_parameter_value then ok:=ok+1;
  when others then bad:=bad||' bad_cursor_wrong='||sqlstate; end;

  perform set_config('request.jwt.claims',json_build_object('sub',user_nogrant::text,'role','authenticated')::text,true);
  select count(*) into c from public.e10_org_purchase_destinations(org_a);
  if c=0 then ok:=ok+1; else bad:=bad||' nogrant_dest='||c; end if;

  perform set_config('request.jwt.claims',json_build_object('sub',user_b::text,'role','authenticated')::text,true);
  begin perform 1 from public.e10_org_purchase_destinations(org_a); bad:=bad||' cross_org_rpc_allowed';
  exception when insufficient_privilege then ok:=ok+1;
  when others then bad:=bad||' cross_org_rpc_wrong='||sqlstate; end;

  if ok=12 then raise notice 'TA-X2 location/supplier gate: PASS (12/12)';
  else raise exception 'TA-X2 location/supplier gate: FAIL passed=%/12 failures=[%]',ok,bad; end if;
end $$;
reset role;

do $$
declare ok integer:=0;
begin
  begin
    insert into public.e10_supplier_offerings(
      organization_id,supplier_id,configuration_version_id,currency
    ) values (
      'e1000000-0000-4000-8000-00000000e2b0',
      'a7000000-0000-4000-8000-00000000e232',
      'a7000000-0000-4000-8000-00000000e223','CAD'
    );
  exception when foreign_key_violation then ok:=ok+1; end;
  if has_function_privilege('anon','e10.can_receive_at(uuid,uuid)','execute') then
    raise exception 'TA-X2 anon can execute internal location predicate';
  else ok:=ok+1; end if;
  if has_function_privilege('anon','public.e10_org_purchase_destinations(uuid,text,uuid,integer)','execute') then
    raise exception 'TA-X2 anon can execute destination RPC';
  else ok:=ok+1; end if;
  if ok=3 then raise notice 'TA-X2 FK and ACL gate: PASS (3/3)';
  else raise exception 'TA-X2 FK and ACL gate: FAIL passed=%/3',ok; end if;
end $$;

rollback;
