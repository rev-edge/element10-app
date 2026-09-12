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
    (o,prep_role,'act.create_receiving',true),
    (o,prep_role,'act.record_commercial_events',true),
    (o,approve_role,'act.purchasing_approve',true),
    (o,approve_role,'act.purchasing_cancel',true);
  -- Remove the low user's effective prepare grant while retaining membership.
  update public.e10_organization_memberships set role_id=approve_role
    where organization_id=o and user_id='a7000000-0000-4000-8000-00000000e313';
  insert into public.e10_locations(id,organization_id,code,name,status) values(location,o,'X3C','X3c receiving','active');
  insert into public.e10_location_role_permissions(organization_id,location_id,role_id,can_receive)
    values(o,location,prep_role,true),(o,location,approve_role,true);
  insert into public.e10_suppliers(id,organization_id,code,name,status) values(supplier,o,'X3C','X3c supplier','active');
  insert into public.e10_product_masters(id,organization_id,name) values(product,o,'X3c non-card product');
  insert into public.e10_product_configurations(id,organization_id,product_master_id,name) values
    (config,o,product,'X3c case'),
    ('a7000000-0000-4000-8000-00000000e30b',o,product,'X3c alternate case');
  insert into public.e10_product_configuration_versions(id,organization_id,configuration_id,version_no,state,packaging_kind,base_unit,base_units_per_package)
    values
      (version,o,config,1,'active','case','unit',12),
      ('a7000000-0000-4000-8000-00000000e30a',o,'a7000000-0000-4000-8000-00000000e30b',1,'active','case','unit',24);
  insert into public.e10_inventory_items(id,name,qty,organization_id) values('x3c-item','X3c item',0,o);
  insert into public.e10_purchase_orders(id,organization_id,supplier_id,destination_location_id,order_number,revision,status,currency,created_by)
    values('a7000000-0000-4000-8000-00000000e321',o,supplier,location,'X3C-COMMITTED',1,'draft','CAD','a7000000-0000-4000-8000-00000000e311');
  insert into public.e10_purchase_order_lines(id,organization_id,purchase_order_id,configuration_version_id,line_no,ordered_quantity,state)
    values('a7000000-0000-4000-8000-00000000e322',o,'a7000000-0000-4000-8000-00000000e321',version,1,8,'active');
  insert into public.e10_purchase_order_revisions(organization_id,purchase_order_id,revision,status,snapshot,payload_fingerprint,change_reason,created_by)
    values(o,'a7000000-0000-4000-8000-00000000e321',1,'draft',e10.purchase_order_snapshot(o,'a7000000-0000-4000-8000-00000000e321'),'fixture','fixture','a7000000-0000-4000-8000-00000000e311');
  insert into public.e10_stock_receipts(id,organization_id,supplier_id,destination_location_id,status,received_at,created_by)
    values('a7000000-0000-4000-8000-00000000e323',o,supplier,location,'posted',now(),'a7000000-0000-4000-8000-00000000e311');
  insert into public.e10_stock_receipt_lines(id,organization_id,stock_receipt_id,configuration_version_id,line_no,received_quantity,accepted_quantity,damaged_quantity,quarantined_quantity)
    values('a7000000-0000-4000-8000-00000000e324',o,'a7000000-0000-4000-8000-00000000e323',version,1,3,3,0,0);
  insert into public.e10_receipt_po_allocations(organization_id,receipt_line_id,purchase_order_line_id,allocated_quantity)
    values(o,'a7000000-0000-4000-8000-00000000e324','a7000000-0000-4000-8000-00000000e322',3);
  insert into public.e10_expected_inventory_allocations(id,organization_id,purchase_order_line_id,destination_location_id,expected_quantity,status,planning_reference)
    values('a7000000-0000-4000-8000-00000000e325',o,'a7000000-0000-4000-8000-00000000e322',location,4,'open','x3c-commitment');
  insert into public.e10_purchase_orders(id,organization_id,supplier_id,destination_location_id,order_number,revision,status,currency,created_by)
    values('a7000000-0000-4000-8000-00000000e326',o,supplier,location,'X3C-INVOICED',1,'draft','CAD','a7000000-0000-4000-8000-00000000e311');
  insert into public.e10_purchase_order_lines(id,organization_id,purchase_order_id,configuration_version_id,line_no,ordered_quantity,state)
    values('a7000000-0000-4000-8000-00000000e327',o,'a7000000-0000-4000-8000-00000000e326',version,1,2,'active');
  insert into public.e10_purchase_order_revisions(organization_id,purchase_order_id,revision,status,snapshot,payload_fingerprint,change_reason,created_by)
    values(o,'a7000000-0000-4000-8000-00000000e326',1,'draft',e10.purchase_order_snapshot(o,'a7000000-0000-4000-8000-00000000e326'),'fixture-invoiced','fixture','a7000000-0000-4000-8000-00000000e311');
  insert into public.e10_supplier_invoices(id,organization_id,supplier_id,supplier_document_number,status,currency,total_amount,created_by)
    values('a7000000-0000-4000-8000-00000000e328',o,supplier,'X3C-INV','approved','CAD',20,'a7000000-0000-4000-8000-00000000e311');
  insert into public.e10_supplier_invoice_lines(id,organization_id,supplier_invoice_id,configuration_version_id,line_no,invoiced_quantity,unit_cost,line_amount)
    values('a7000000-0000-4000-8000-00000000e329',o,'a7000000-0000-4000-8000-00000000e328',version,1,2,10,20);
  insert into public.e10_invoice_po_allocations(organization_id,invoice_line_id,purchase_order_line_id,allocated_quantity)
    values(o,'a7000000-0000-4000-8000-00000000e329','a7000000-0000-4000-8000-00000000e327',2);
end $$;

set local role authenticated;

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
  begin
    perform public.e10_org_create_purchase_order(o,'a7000000-0000-4000-8000-00000000e302','a7000000-0000-4000-8000-00000000e301',
      'X3C-PO-CHANGED','CAD',null,jsonb_build_array(jsonb_build_object('id','a7000000-0000-4000-8000-00000000e307',
        'line_no',1,'configuration_version_id','a7000000-0000-4000-8000-00000000e305','ordered_quantity',10,
        'estimated_unit_cost',12.50)),'x3c-create-2');
    raise exception 'changed create payload replayed';
  exception when sqlstate '22023' then null; end;
  begin
    perform public.e10_org_create_purchase_order(o,'a7000000-0000-4000-8000-00000000e302','a7000000-0000-4000-8000-00000000e301',
      'X3C-NAN','CAD',null,jsonb_build_array(jsonb_build_object('id',gen_random_uuid(),'line_no',1,
        'configuration_version_id','a7000000-0000-4000-8000-00000000e305','ordered_quantity','NaN')),'x3c-nan');
    raise exception 'nonfinite quantity accepted'; exception when sqlstate '22023' then null; end;
  begin
    perform public.e10_org_create_purchase_order(o,'a7000000-0000-4000-8000-00000000e302','a7000000-0000-4000-8000-00000000e301',
      'X3C-TOO-MANY','CAD',null,(select jsonb_agg(jsonb_build_object('id',gen_random_uuid(),'line_no',g,
        'configuration_version_id','a7000000-0000-4000-8000-00000000e305','ordered_quantity',1)) from generate_series(1,201) g),
      'x3c-too-many');
    raise exception 'line bound exceeded'; exception when sqlstate '22023' then null; end;
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
declare o uuid:='e1000000-0000-4000-8000-0000000000a6';
begin
  perform set_config('request.jwt.claims',jsonb_build_object('sub','a7000000-0000-4000-8000-00000000e311','role','authenticated')::text,true);
  begin
    perform public.e10_org_amend_purchase_order(o,'a7000000-0000-4000-8000-00000000e321',1,
      'a7000000-0000-4000-8000-00000000e302','a7000000-0000-4000-8000-00000000e301',
      'X3C-COMMITTED','CAD',null,jsonb_build_array(jsonb_build_object(
        'id','a7000000-0000-4000-8000-00000000e322','line_no',1,
        'configuration_version_id','a7000000-0000-4000-8000-00000000e305',
        'ordered_quantity',4)),'invalid reduction','x3c-reduce-below-total-commitment');
    raise exception 'reduction below received plus remaining expected commitment accepted';
  exception when check_violation then null; end;
  perform set_config('request.jwt.claims',jsonb_build_object('sub','a7000000-0000-4000-8000-00000000e312','role','authenticated')::text,true);
  begin
    perform public.e10_org_transition_purchase_order(o,'a7000000-0000-4000-8000-00000000e321',1,
      'cancel','would strand committed supply','x3c-cancel-committed');
    raise exception 'cancel with receipt/expected commitment accepted';
  exception when sqlstate '55000' then null; end;
  begin
    perform public.e10_org_transition_purchase_order(o,'a7000000-0000-4000-8000-00000000e326',1,
      'cancel','would strand invoice match','x3c-cancel-invoiced');
    raise exception 'cancel with invoice allocation accepted';
  exception when sqlstate '55000' then null; end;
end $$;

reset role;
update public.e10_stock_receipts set status='reversed'
  where organization_id='e1000000-0000-4000-8000-0000000000a6' and id='a7000000-0000-4000-8000-00000000e323';
update public.e10_expected_inventory_allocations set status='fulfilled',fulfilled_quantity=expected_quantity
  where organization_id='e1000000-0000-4000-8000-0000000000a6' and id='a7000000-0000-4000-8000-00000000e325';
set local role authenticated;
do $$
declare o uuid:='e1000000-0000-4000-8000-0000000000a6'; r jsonb;
begin
  perform set_config('request.jwt.claims',jsonb_build_object('sub','a7000000-0000-4000-8000-00000000e311','role','authenticated')::text,true);
  begin
    perform public.e10_org_amend_purchase_order(o,'a7000000-0000-4000-8000-00000000e321',1,
      'a7000000-0000-4000-8000-00000000e302','a7000000-0000-4000-8000-00000000e301',
      'X3C-COMMITTED','CAD',null,jsonb_build_array(jsonb_build_object(
        'id','a7000000-0000-4000-8000-00000000e322','line_no',1,
        'configuration_version_id','a7000000-0000-4000-8000-00000000e30a','ordered_quantity',8)),
      'illegal historical rebind','x3c-rebind-after-reversal');
    raise exception 'configuration rebound after reversed receipt history';
  exception when sqlstate '55000' then null; end;
  r:=public.e10_org_amend_purchase_order(o,'a7000000-0000-4000-8000-00000000e321',1,
    'a7000000-0000-4000-8000-00000000e302','a7000000-0000-4000-8000-00000000e301',
    'X3C-COMMITTED','CAD',null,jsonb_build_array(jsonb_build_object(
      'id','a7000000-0000-4000-8000-00000000e322','line_no',1,
      'configuration_version_id','a7000000-0000-4000-8000-00000000e305','ordered_quantity',1)),
    'fulfilled supply no longer remains','x3c-fulfilled-floor');
  if (r->>'revision')::integer<>2 then raise exception 'fulfilled expected allocation still counted as remaining commitment: %',r; end if;
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
  r:=public.e10_org_amend_purchase_order(o,po,4,'a7000000-0000-4000-8000-00000000e302',
    'a7000000-0000-4000-8000-00000000e301','X3C-PO-2','CAD',null,
    jsonb_build_array(
      jsonb_build_object('id','a7000000-0000-4000-8000-00000000e307','line_no',2,
        'configuration_version_id','a7000000-0000-4000-8000-00000000e305','ordered_quantity',8,'estimated_unit_cost',13),
      jsonb_build_object('id','a7000000-0000-4000-8000-00000000e308','line_no',1,
        'configuration_version_id','a7000000-0000-4000-8000-00000000e305','ordered_quantity',2,'estimated_unit_cost',14)),
    'add and renumber','x3c-amend-add');
  if r->>'status'<>'draft' or (r->>'revision')::integer<>5 then raise exception 'add/renumber amendment invalid'; end if;
  r:=public.e10_org_amend_purchase_order(o,po,5,'a7000000-0000-4000-8000-00000000e302',
    'a7000000-0000-4000-8000-00000000e301','X3C-PO-2','CAD',null,
    jsonb_build_array(jsonb_build_object('id','a7000000-0000-4000-8000-00000000e308','line_no',1,
      'configuration_version_id','a7000000-0000-4000-8000-00000000e305','ordered_quantity',2,'estimated_unit_cost',14)),
    'remove old line','x3c-amend-remove');
  r:=public.e10_org_transition_purchase_order(o,po,6,'submit','ready after amendment','x3c-resubmit');
  begin perform public.e10_org_receive_po_line(o,'a7000000-0000-4000-8000-00000000e307','x3c-item',1,0,0,null,now(),'[]','x3c-cancelled-line');
    raise exception 'cancelled PO line remained receivable'; exception when sqlstate '55000' then null; end;
  perform set_config('request.jwt.claims',jsonb_build_object('sub','a7000000-0000-4000-8000-00000000e312','role','authenticated')::text,true);
  r:=public.e10_org_transition_purchase_order(o,po,7,'approve','approved after amendment','x3c-reapprove');
  perform set_config('request.jwt.claims',jsonb_build_object('sub','a7000000-0000-4000-8000-00000000e311','role','authenticated')::text,true);
  r:=public.e10_org_receive_po_line(o,'a7000000-0000-4000-8000-00000000e308','x3c-item',2,0,0,null,
    '2026-09-11T19:00:00Z','[]','x3c-receive-active');
  if r->>'replay'<>'false' then raise exception 'active-line receipt failed'; end if;
  perform set_config('request.jwt.claims',jsonb_build_object('sub','a7000000-0000-4000-8000-00000000e312','role','authenticated')::text,true);
  r:=public.e10_org_transition_purchase_order(o,po,8,'close','fully received','x3c-close');
  if r->>'status'<>'closed' or (r->>'revision')::integer<>9 then raise exception 'close failed'; end if;
  r:=public.e10_org_transition_purchase_order(o,po,8,'close','fully received','x3c-close');
  if r->>'replay'<>'true' or r->>'status'<>'closed' or (r->>'revision')::integer<>9 then
    raise exception 'terminal transition replay failed: %',r; end if;
  perform set_config('request.jwt.claims',jsonb_build_object('sub','a7000000-0000-4000-8000-00000000e311','role','authenticated')::text,true);
  r:=public.e10_org_receive_po_line(o,'a7000000-0000-4000-8000-00000000e308','x3c-item',2,0,0,null,
    '2026-09-11T19:00:00Z','[]','x3c-receive-active');
  if r->>'replay'<>'true' then raise exception 'historical receipt replay failed after PO close'; end if;
end $$;

reset role;

-- A stale destination grant blocks forward progress but not recovery cancellation.
set local role authenticated;
do $$ declare r jsonb; begin
  perform set_config('request.jwt.claims',jsonb_build_object('sub','a7000000-0000-4000-8000-00000000e311','role','authenticated')::text,true);
  r:=public.e10_org_create_purchase_order('e1000000-0000-4000-8000-0000000000a6',
    'a7000000-0000-4000-8000-00000000e302','a7000000-0000-4000-8000-00000000e301',
    'X3C-CANCEL','CAD',null,jsonb_build_array(jsonb_build_object(
      'id','a7000000-0000-4000-8000-00000000e309','line_no',1,
      'configuration_version_id','a7000000-0000-4000-8000-00000000e305','ordered_quantity',1)),
    'x3c-create-cancel');
  perform set_config('e10.test.x3c_cancel_po',r->>'purchase_order_id',true);
end $$;
reset role;
set local role authenticated;
do $$ begin
  perform set_config('request.jwt.claims',jsonb_build_object('sub','a7000000-0000-4000-8000-00000000e312','role','authenticated')::text,true);
  begin
    perform public.e10_org_transition_purchase_order('e1000000-0000-4000-8000-0000000000a6',
      current_setting('e10.test.x3c_cancel_po')::uuid,1,'approve','cannot approve draft','x3c-invalid-approve');
    raise exception 'authorized illegal draft-to-approved transition accepted';
  exception when sqlstate '55000' then null; end;
end $$;
reset role;
delete from public.e10_location_role_permissions where organization_id='e1000000-0000-4000-8000-0000000000a6'
  and location_id='a7000000-0000-4000-8000-00000000e301'
  and role_id=(select role_id from public.e10_organization_memberships
    where organization_id='e1000000-0000-4000-8000-0000000000a6' and user_id='a7000000-0000-4000-8000-00000000e311');
set local role authenticated;
do $$ begin
  perform set_config('request.jwt.claims',jsonb_build_object('sub','a7000000-0000-4000-8000-00000000e311','role','authenticated')::text,true);
  begin perform public.e10_org_transition_purchase_order('e1000000-0000-4000-8000-0000000000a6',
      current_setting('e10.test.x3c_cancel_po')::uuid,1,'submit','stale location','x3c-stale-location-submit');
    raise exception 'stale destination grant allowed submit'; exception when insufficient_privilege then null; end;
end $$;
reset role;
insert into public.e10_location_role_permissions(organization_id,location_id,role_id,can_receive)
select 'e1000000-0000-4000-8000-0000000000a6','a7000000-0000-4000-8000-00000000e301',role_id,true
from public.e10_organization_memberships where organization_id='e1000000-0000-4000-8000-0000000000a6'
  and user_id='a7000000-0000-4000-8000-00000000e311';
update public.e10_suppliers set status='inactive' where id='a7000000-0000-4000-8000-00000000e302';
set local role authenticated;
do $$ begin
  perform set_config('request.jwt.claims',jsonb_build_object('sub','a7000000-0000-4000-8000-00000000e311','role','authenticated')::text,true);
  begin perform public.e10_org_transition_purchase_order('e1000000-0000-4000-8000-0000000000a6',
      current_setting('e10.test.x3c_cancel_po')::uuid,1,'submit','inactive supplier','x3c-inactive-supplier-submit');
    raise exception 'inactive supplier allowed submit'; exception when sqlstate '55000' then null; end;
end $$;
reset role;
update public.e10_suppliers set status='active' where id='a7000000-0000-4000-8000-00000000e302';
update public.e10_product_configuration_versions set state='retired' where id='a7000000-0000-4000-8000-00000000e305';
set local role authenticated;
do $$ begin
  perform set_config('request.jwt.claims',jsonb_build_object('sub','a7000000-0000-4000-8000-00000000e311','role','authenticated')::text,true);
  begin perform public.e10_org_transition_purchase_order('e1000000-0000-4000-8000-0000000000a6',
      current_setting('e10.test.x3c_cancel_po')::uuid,1,'submit','inactive configuration','x3c-inactive-config-submit');
    raise exception 'inactive configuration allowed submit'; exception when sqlstate '55000' then null; end;
end $$;
reset role;
-- Configuration versions are immutable-history rows after R5. Keep the
-- fixture retired; recovery cancellation must not require reactivation.
set local role authenticated;
do $$ declare r jsonb; begin
  perform set_config('request.jwt.claims',jsonb_build_object('sub','a7000000-0000-4000-8000-00000000e312','role','authenticated')::text,true);
  r:=public.e10_org_transition_purchase_order('e1000000-0000-4000-8000-0000000000a6',
    current_setting('e10.test.x3c_cancel_po')::uuid,1,'cancel','cancel despite stale destination','x3c-cancel');
  if r->>'status'<>'cancelled' or (r->>'revision')::integer<>2 then raise exception 'recovery cancellation failed'; end if;
end $$;
reset role;

do $$
declare o uuid:='e1000000-0000-4000-8000-0000000000a6'; po uuid:=current_setting('e10.test.x3c_po')::uuid;
begin
  if not exists(select 1 from public.e10_purchase_order_lines where organization_id=o and purchase_order_id=po
      and id='a7000000-0000-4000-8000-00000000e308' and line_no=1 and state='active')
    or not exists(select 1 from public.e10_purchase_order_lines where organization_id=o and purchase_order_id=po
      and id='a7000000-0000-4000-8000-00000000e307' and line_no=2 and state='cancelled') then
    raise exception 'add/renumber/remove line state invalid'; end if;
  if (select count(*) from public.e10_purchase_order_revisions where organization_id=o and purchase_order_id=po)<>9 then
    raise exception 'revision history incomplete'; end if;
  if (select count(*) from public.e10_commercial_events where organization_id=o and subject_id=po::text and event_type='purchase_order_changed')<>9 then
    raise exception 'commercial event history incomplete'; end if;
  if exists(select 1 from public.e10_purchase_orders where organization_id=o and id=po
    and (status<>'closed' or revision<>9 or approved_revision<>8 or approved_by is null or approved_at is null or closed_by is null)) then
    raise exception 'closed PO state invalid'; end if;
  if not exists(select 1 from public.e10_purchase_order_revisions where organization_id=o and purchase_order_id=po
      and revision=7 and status='submitted' and snapshot->>'approved_revision' is null) then
    raise exception 'approval invalidation was not captured before reapproval'; end if;
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
  begin
    perform public.e10_org_record_commercial_event_v2(
      'e1000000-0000-4000-8000-0000000000a6','purchase_order_changed',1,'inventory_item','x3c-item',
      now(),'exact','manual',null,'forged',null,null,null,'operator_asserted',
      jsonb_build_object('purchase_order_id','does-not-exist','operation','approve','status','approved','revision','999'),
      null,'{}'::text[],'x3c-forged-po-event');
    raise exception 'generic event route forged purchase-order lifecycle';
  exception when insufficient_privilege then null; end;
end $$;
reset role;

rollback;
