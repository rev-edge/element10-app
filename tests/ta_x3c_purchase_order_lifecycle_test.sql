-- TA-X3c purchase-order lifecycle gate. Self-failing and rolled back.
begin;

do $$
declare
  o uuid:='e1000000-0000-4000-8000-0000000000a6';
  ob uuid:='e1000000-0000-4000-8000-00000000e3d0';
  prep_role uuid:=gen_random_uuid(); approve_role uuid:=gen_random_uuid(); foreign_role uuid:=gen_random_uuid();
  location uuid:='a7000000-0000-4000-8000-00000000e301';
  supplier uuid:='a7000000-0000-4000-8000-00000000e302';
  product uuid:='a7000000-0000-4000-8000-00000000e303';
  config uuid:='a7000000-0000-4000-8000-00000000e304';
  version uuid:='a7000000-0000-4000-8000-00000000e305';
begin
  insert into public.e10_organizations(id,name,slug) values(ob,'X3c foreign org','x3c-foreign');
  insert into public.e10_organization_roles(id,organization_id,key,name) values
    (prep_role,o,'x3c-preparer','X3c preparer'),
    (approve_role,o,'x3c-approver','X3c approver'),
    (foreign_role,ob,'x3c-foreign','X3c foreign');
  insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at) values
    ('a7000000-0000-4000-8000-00000000e311','00000000-0000-0000-0000-000000000000','authenticated','authenticated','x3c-prep@example.invalid',now(),now()),
    ('a7000000-0000-4000-8000-00000000e312','00000000-0000-0000-0000-000000000000','authenticated','authenticated','x3c-approve@example.invalid',now(),now()),
    ('a7000000-0000-4000-8000-00000000e313','00000000-0000-0000-0000-000000000000','authenticated','authenticated','x3c-low@example.invalid',now(),now()),
    ('a7000000-0000-4000-8000-00000000e314','00000000-0000-0000-0000-000000000000','authenticated','authenticated','x3c-foreign@example.invalid',now(),now());
  insert into public.e10_organization_memberships(organization_id,user_id,role_id,status) values
    (o,'a7000000-0000-4000-8000-00000000e311',prep_role,'active'),
    (o,'a7000000-0000-4000-8000-00000000e312',approve_role,'active'),
    (o,'a7000000-0000-4000-8000-00000000e313',prep_role,'active'),
    (ob,'a7000000-0000-4000-8000-00000000e314',foreign_role,'active');
  insert into public.e10_organization_role_permissions(organization_id,role_id,capability,allowed) values
    (o,prep_role,'act.purchasing_prepare',true),
    (o,approve_role,'act.purchasing_approve',true),
    (o,approve_role,'act.purchasing_cancel',true);
  -- Remove the low user's effective prepare grant while retaining membership.
  update public.e10_organization_memberships set role_id=approve_role
    where organization_id=o and user_id='a7000000-0000-4000-8000-00000000e313';
  insert into public.e10_locations(id,organization_id,code,name,status) values(location,o,'X3C','X3c receiving','active');
  insert into public.e10_location_role_permissions(organization_id,location_id,role_id,can_receive)
    values(o,location,prep_role,true);
  insert into public.e10_suppliers(id,organization_id,code,name,status) values(supplier,o,'X3C','X3c supplier','active');
  insert into public.e10_product_masters(id,organization_id,name) values(product,o,'X3c non-card product');
  insert into public.e10_product_configurations(id,organization_id,product_master_id,name) values(config,o,product,'X3c case');
  insert into public.e10_product_configuration_versions(id,organization_id,configuration_id,version_no,state,packaging_kind,base_unit,base_units_per_package)
    values(version,o,config,1,'active','case','unit',12);
end $$;

set local role authenticated;

do $$
declare
  o uuid:='e1000000-0000-4000-8000-0000000000a6';
  location uuid:='a7000000-0000-4000-8000-00000000e301';
  supplier uuid:='a7000000-0000-4000-8000-00000000e302';
  version uuid:='a7000000-0000-4000-8000-00000000e305';
  line_id uuid:='a7000000-0000-4000-8000-00000000e306';
  r jsonb; po uuid;
begin
  perform set_config('request.jwt.claims',jsonb_build_object('sub','a7000000-0000-4000-8000-00000000e311','role','authenticated')::text,true);
  r:=public.e10_org_create_purchase_order(o,supplier,location,'X3C-PO-1','CAD',now()+interval '8 days',
    jsonb_build_array(jsonb_build_object('id',line_id,'line_no',1,'configuration_version_id',version,
      'ordered_quantity',10,'estimated_unit_cost',12.50)),'x3c-create-1');
  if r->>'replay'<>'false' or r->>'status'<>'draft' or (r->>'revision')::integer<>1 then raise exception 'create result invalid: %',r; end if;
  po:=(r->>'purchase_order_id')::uuid;
  perform set_config('e10.test.x3c_po',po::text,true);
  r:=public.e10_org_create_purchase_order(o,supplier,location,'X3C-PO-1','CAD',now()+interval '7 days',
    jsonb_build_array(jsonb_build_object('id',line_id,'line_no',1,'configuration_version_id',version,
      'ordered_quantity',10,'estimated_unit_cost',12.50)),'x3c-create-1');
  -- Timestamp is intentionally different, therefore the server fingerprint must reject changed payload.
  raise exception 'changed create payload replayed';
exception when sqlstate '22023' then null;
end $$;

-- Create a stable replay fixture with a NULL expected_at.
do $$
declare o uuid:='e1000000-0000-4000-8000-0000000000a6'; r jsonb; po uuid;
begin
  perform set_config('request.jwt.claims',jsonb_build_object('sub','a7000000-0000-4000-8000-00000000e311','role','authenticated')::text,true);
  r:=public.e10_org_create_purchase_order(o,'a7000000-0000-4000-8000-00000000e302','a7000000-0000-4000-8000-00000000e301',
    'X3C-PO-2','CAD',null,jsonb_build_array(jsonb_build_object('id','a7000000-0000-4000-8000-00000000e307',
      'line_no',1,'configuration_version_id','a7000000-0000-4000-8000-00000000e305','ordered_quantity',10,
      'estimated_unit_cost',12.50)),'x3c-create-2');
  po:=(r->>'purchase_order_id')::uuid; perform set_config('e10.test.x3c_po',po::text,true);
  r:=public.e10_org_create_purchase_order(o,'a7000000-0000-4000-8000-00000000e302','a7000000-0000-4000-8000-00000000e301',
    'X3C-PO-2','CAD',null,jsonb_build_array(jsonb_build_object('id','a7000000-0000-4000-8000-00000000e307',
      'line_no',1,'configuration_version_id','a7000000-0000-4000-8000-00000000e305','ordered_quantity',10,
      'estimated_unit_cost',12.50)),'x3c-create-2');
  if r->>'replay'<>'true' or r ? 'lines' or r ? 'snapshot' then raise exception 'safe replay invalid: %',r; end if;
end $$;

do $$
declare o uuid:='e1000000-0000-4000-8000-0000000000a6'; po uuid:=current_setting('e10.test.x3c_po')::uuid; r jsonb;
begin
  perform set_config('request.jwt.claims',jsonb_build_object('sub','a7000000-0000-4000-8000-00000000e313','role','authenticated')::text,true);
  begin perform public.e10_org_transition_purchase_order(o,po,1,'submit','ready','x3c-low-submit');
    raise exception 'member without prepare submitted'; exception when insufficient_privilege then null; end;
  perform set_config('request.jwt.claims',jsonb_build_object('sub','a7000000-0000-4000-8000-00000000e314','role','authenticated')::text,true);
  begin perform public.e10_org_transition_purchase_order(o,po,1,'submit','foreign','x3c-foreign-submit');
    raise exception 'foreign member submitted'; exception when insufficient_privilege then null; end;
  perform set_config('request.jwt.claims',jsonb_build_object('sub','a7000000-0000-4000-8000-00000000e311','role','authenticated')::text,true);
  r:=public.e10_org_transition_purchase_order(o,po,1,'submit','ready','x3c-submit');
  if r->>'status'<>'submitted' or (r->>'revision')::integer<>2 then raise exception 'submit invalid'; end if;
  begin perform public.e10_org_transition_purchase_order(o,po,2,'approve','not allowed','x3c-prep-approve');
    raise exception 'preparer approved'; exception when insufficient_privilege then null; end;
  perform set_config('request.jwt.claims',jsonb_build_object('sub','a7000000-0000-4000-8000-00000000e312','role','authenticated')::text,true);
  r:=public.e10_org_transition_purchase_order(o,po,2,'approve','approved','x3c-approve');
  if r->>'status'<>'approved' or (r->>'revision')::integer<>3 then raise exception 'approve invalid'; end if;
  begin perform public.e10_org_transition_purchase_order(o,po,2,'cancel','stale','x3c-stale');
    raise exception 'stale CAS accepted'; exception when serialization_failure then null; end;
end $$;

do $$
declare o uuid:='e1000000-0000-4000-8000-0000000000a6'; po uuid:=current_setting('e10.test.x3c_po')::uuid; r jsonb;
begin
  perform set_config('request.jwt.claims',jsonb_build_object('sub','a7000000-0000-4000-8000-00000000e311','role','authenticated')::text,true);
  r:=public.e10_org_amend_purchase_order(o,po,3,'a7000000-0000-4000-8000-00000000e302',
    'a7000000-0000-4000-8000-00000000e301','X3C-PO-2','CAD',null,
    jsonb_build_array(jsonb_build_object('id','a7000000-0000-4000-8000-00000000e307','line_no',1,
      'configuration_version_id','a7000000-0000-4000-8000-00000000e305','ordered_quantity',8,
      'estimated_unit_cost',13)), 'supplier revision','x3c-amend');
  if r->>'status'<>'submitted' or (r->>'revision')::integer<>4 then raise exception 'approved amendment invalid'; end if;
end $$;

reset role;

do $$
declare o uuid:='e1000000-0000-4000-8000-0000000000a6'; po uuid:=current_setting('e10.test.x3c_po')::uuid;
begin
  if (select count(*) from public.e10_purchase_order_revisions where organization_id=o and purchase_order_id=po)<>4 then
    raise exception 'revision history incomplete'; end if;
  if (select count(*) from public.e10_commercial_events where organization_id=o and subject_id=po::text and event_type='purchase_order_changed')<>4 then
    raise exception 'commercial event history incomplete'; end if;
  if exists(select 1 from public.e10_purchase_orders where organization_id=o and id=po
    and (status<>'submitted' or revision<>4 or approved_revision is not null or approved_by is not null or approved_at is not null)) then
    raise exception 'approval was not invalidated by amendment'; end if;
  if (select count(*) from public.e10_organization_role_permissions
      where capability in ('act.purchasing_prepare','act.purchasing_approve','act.purchasing_cancel') and organization_id<>o)<>0 then
    raise exception 'unexpected purchasing grant outside fixture'; end if;
  raise notice 'TA-X3c PO lifecycle: PASS (authority split, destination/config, idempotency, CAS, revisions/events, approval invalidation, tenant denial)';
end $$;

set local role authenticated;
do $$ begin
  perform set_config('request.jwt.claims',jsonb_build_object('sub','a7000000-0000-4000-8000-00000000e311','role','authenticated')::text,true);
  begin perform 1 from public.e10_purchase_order_commands; raise exception 'command receipts exposed'; exception when insufficient_privilege then null; end;
  begin insert into public.e10_purchase_orders(organization_id,supplier_id,destination_location_id,currency)
    values('e1000000-0000-4000-8000-0000000000a6',gen_random_uuid(),gen_random_uuid(),'CAD');
    raise exception 'direct PO insert allowed'; exception when insufficient_privilege then null; end;
end $$;
reset role;

rollback;
