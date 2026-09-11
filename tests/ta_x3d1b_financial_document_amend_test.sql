-- TA-X3d.1b financial-document amendment gate. Self-failing and rolled back.
begin;

do $$
declare
  o uuid:='d31b0000-0000-4000-8000-000000000001';
  other_org uuid:='d31b0000-0000-4000-8000-000000000002';
  actor uuid:='d31b0000-0000-4000-8000-000000000003';
  low_actor uuid:='d31b0000-0000-4000-8000-000000000004';
  role_id uuid:='d31b0000-0000-4000-8000-000000000005';
  low_role uuid:='d31b0000-0000-4000-8000-000000000006';
  supplier uuid:='d31b0000-0000-4000-8000-000000000007';
  location_id uuid:='d31b0000-0000-4000-8000-000000000008';
  product_id uuid:='d31b0000-0000-4000-8000-000000000009';
  config_id uuid:='d31b0000-0000-4000-8000-000000000010';
  version_id uuid:='d31b0000-0000-4000-8000-000000000011';
  alt_version uuid:='d31b0000-0000-4000-8000-000000000012';
  alt_config uuid:='d31b0000-0000-4000-8000-000000000021';
  po_id uuid:='d31b0000-0000-4000-8000-000000000013';
  po_line uuid:='d31b0000-0000-4000-8000-000000000014';
  invoice_id uuid:='d31b0000-0000-4000-8000-000000000015';
  invoice_line uuid:='d31b0000-0000-4000-8000-000000000016';
  cancelled_line uuid:='d31b0000-0000-4000-8000-000000000017';
  credit_id uuid:='d31b0000-0000-4000-8000-000000000018';
  credit_line uuid:='d31b0000-0000-4000-8000-000000000019';
  receipt_id uuid:='d31b0000-0000-4000-8000-000000000022';
  receipt_line uuid:='d31b0000-0000-4000-8000-000000000023';
  result jsonb;
  invoice_lines jsonb;
  credit_lines jsonb;
begin
  insert into public.e10_organizations(id,name,slug) values
    (o,'X3d1b org','x3d1b-org'),(other_org,'X3d1b other','x3d1b-other');
  insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at) values
    (actor,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','x3d1b@example.invalid',now(),now()),
    (low_actor,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','x3d1b-low@example.invalid',now(),now());
  insert into public.e10_organization_roles(id,organization_id,key,name) values
    (role_id,o,'x3d1b-preparer','X3d1b preparer'),(low_role,o,'x3d1b-low','X3d1b low');
  insert into public.e10_organization_memberships(organization_id,user_id,role_id,status) values
    (o,actor,role_id,'active'),(o,low_actor,low_role,'active');
  insert into public.e10_organization_role_permissions(organization_id,role_id,capability,allowed)
    values(o,role_id,'act.purchasing_prepare',true);
  insert into public.e10_suppliers(id,organization_id,name,status) values(supplier,o,'X3d1b supplier','active');
  insert into public.e10_locations(id,organization_id,name,status) values(location_id,o,'X3d1b location','active');
  insert into public.e10_product_masters(id,organization_id,name) values(product_id,o,'X3d1b product');
  insert into public.e10_product_configurations(id,organization_id,product_master_id,name)
    values(config_id,o,product_id,'X3d1b configuration'),
      (alt_config,o,product_id,'X3d1b alternate configuration');
  insert into public.e10_product_configuration_versions
    (id,organization_id,configuration_id,version_no,state,packaging_kind,base_unit,base_units_per_package)
    values(version_id,o,config_id,1,'active','unit','unit',1),
      (alt_version,o,alt_config,1,'active','unit','unit',1);
  insert into public.e10_purchase_orders
    (id,organization_id,supplier_id,destination_location_id,order_number,status,currency,created_by)
    values(po_id,o,supplier,location_id,'X3D1B-PO','approved','CAD',actor);
  insert into public.e10_purchase_order_lines
    (id,organization_id,purchase_order_id,configuration_version_id,line_no,ordered_quantity,estimated_unit_cost)
    values(po_line,o,po_id,version_id,1,10,20);
  insert into public.e10_supplier_invoices
    (id,organization_id,supplier_id,supplier_document_number,revision,status,currency,total_amount,
      reviewed_by,reviewed_at,approved_revision,approved_by,approved_at,created_by)
    values(invoice_id,o,supplier,'X3D1B-INV',1,'approved','CAD',120,
      actor,now(),1,actor,now(),actor);
  insert into public.e10_supplier_invoice_lines
    (id,organization_id,supplier_invoice_id,configuration_version_id,line_no,description,
      invoiced_quantity,unit_cost,line_amount,state)
    values(invoice_line,o,invoice_id,version_id,1,'original',5,20,100,'active'),
      (cancelled_line,o,invoice_id,version_id,2,'omit me',1,20,20,'active');
  insert into public.e10_supplier_credits
    (id,organization_id,supplier_id,supplier_document_number,revision,status,currency,total_amount,
      reviewed_by,reviewed_at,approved_revision,approved_by,approved_at,created_by)
    values(credit_id,o,supplier,'X3D1B-CR',1,'approved','CAD',10,
      actor,now(),1,actor,now(),actor);
  insert into public.e10_supplier_credit_lines
    (id,organization_id,supplier_credit_id,configuration_version_id,line_no,description,line_amount,state)
    values(credit_line,o,credit_id,version_id,1,'credit',10,'active');
  insert into public.e10_invoice_po_allocations
    (organization_id,invoice_line_id,purchase_order_line_id,allocated_quantity)
    values(o,invoice_line,po_line,4);
  insert into public.e10_credit_invoice_allocations
    (organization_id,credit_line_id,invoice_line_id,allocated_amount)
    values(o,credit_line,invoice_line,10);
  insert into public.e10_stock_receipts
    (id,organization_id,supplier_id,destination_location_id,receipt_number,status,received_at,created_by)
    values(receipt_id,o,supplier,location_id,'X3D1B-REC','posted',now(),actor);
  insert into public.e10_stock_receipt_lines
    (id,organization_id,stock_receipt_id,configuration_version_id,line_no,received_quantity,
      accepted_quantity,actual_unit_cost,currency)
    values(receipt_line,o,receipt_id,version_id,1,3,3,20,'CAD');
  insert into public.e10_receipt_invoice_allocations
    (organization_id,receipt_line_id,invoice_line_id,allocated_quantity)
    values(o,receipt_line,invoice_line,3);

  perform set_config('request.jwt.claims',jsonb_build_object('sub',actor,'role','authenticated')::text,true);
  invoice_lines:=jsonb_build_array(jsonb_build_object('id',invoice_line,'line_no',1,
    'configuration_version_id',version_id,'description','compatible increase',
    'invoiced_quantity',6,'unit_cost',20,'line_amount',130));
  set local role authenticated;
  result:=public.e10_org_amend_supplier_invoice(o,invoice_id,1,'CAD','2026-09-11',130,
    invoice_lines,'compatible allocated amendment','x3d1b-invoice-amend');
  if result->>'status'<>'reviewed' or result->>'revision'<>'2' or result->>'replay'<>'false' then
    raise exception 'invoice amendment result invalid: %',result;
  end if;
  result:=public.e10_org_amend_supplier_invoice(o,invoice_id,1,'CAD','2026-09-11',130,
    invoice_lines,'compatible allocated amendment','x3d1b-invoice-amend');
  if result->>'replay'<>'true' or result->>'revision'<>'2' then raise exception 'amend replay failed: %',result; end if;

  begin
    perform public.e10_org_amend_supplier_invoice(o,invoice_id,1,'CAD',null,130,
      invoice_lines,'stale revision','x3d1b-stale');
    raise exception 'stale amendment accepted'; exception when sqlstate '40001' then null; end;
  begin
    perform public.e10_org_amend_supplier_invoice(o,invoice_id,2,'CAD',null,70,
      jsonb_build_array(jsonb_build_object('id',invoice_line,'line_no',1,
        'configuration_version_id',version_id,'invoiced_quantity',3,'unit_cost',20,'line_amount',70)),
      'reduce below allocation','x3d1b-reduce');
    raise exception 'allocation-stranding reduction accepted'; exception when sqlstate '55000' then null; end;
  begin
    perform public.e10_org_amend_supplier_invoice(o,invoice_id,2,'CAD',null,130,
      jsonb_build_array(jsonb_build_object('id',invoice_line,'line_no',1,
        'configuration_version_id',alt_version,'invoiced_quantity',6,'unit_cost',20,'line_amount',130)),
      'change allocated configuration','x3d1b-config');
    raise exception 'allocated configuration change accepted'; exception when sqlstate '55000' then null; end;
  begin
    perform public.e10_org_amend_supplier_invoice(o,invoice_id,2,'USD',null,130,
      invoice_lines,'change allocated currency','x3d1b-currency');
    raise exception 'allocated currency change accepted'; exception when sqlstate '55000' then null; end;
  begin
    perform public.e10_org_amend_supplier_invoice(o,invoice_id,2,'CAD',null,1,
      jsonb_build_array(jsonb_build_object('id','d31b0000-0000-4000-8000-000000000020',
        'line_no',2,'line_amount',1)),'reuse cancelled number','x3d1b-reuse');
    raise exception 'cancelled line number reused'; exception when unique_violation then null; end;

  credit_lines:=jsonb_build_array(jsonb_build_object('id',credit_line,'line_no',1,
    'configuration_version_id',version_id,'description','credit increase','line_amount',12));
  result:=public.e10_org_amend_supplier_credit(o,credit_id,1,'CAD','2026-09-11',12,
    credit_lines,'compatible allocated credit amendment','x3d1b-credit-amend');
  if result->>'status'<>'reviewed' or result->>'revision'<>'2' then raise exception 'credit amend failed: %',result; end if;
  begin
    perform public.e10_org_amend_supplier_credit(o,credit_id,2,'CAD',null,9,
      jsonb_build_array(jsonb_build_object('id',credit_line,'line_no',1,
        'configuration_version_id',version_id,'line_amount',9)),
      'reduce credit below allocation','x3d1b-credit-reduce');
    raise exception 'credit allocation-stranding reduction accepted'; exception when sqlstate '55000' then null; end;

  perform set_config('request.jwt.claims',jsonb_build_object('sub',low_actor,'role','authenticated')::text,true);
  begin
    perform public.e10_org_amend_supplier_invoice(o,invoice_id,2,'CAD',null,130,
      invoice_lines,'unauthorized','x3d1b-low');
    raise exception 'member without prepare capability amended'; exception when insufficient_privilege then null; end;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',actor,'role','authenticated')::text,true);
  begin
    perform public.e10_org_amend_supplier_invoice(other_org,invoice_id,2,'CAD',null,130,
      invoice_lines,'cross org','x3d1b-cross-org');
    raise exception 'cross-org amendment accepted'; exception when insufficient_privilege then null; end;
  reset role;

  if (select status from public.e10_supplier_invoices where id=invoice_id)<>'reviewed'
    or (select revision from public.e10_supplier_invoices where id=invoice_id)<>2
    or (select approved_revision from public.e10_supplier_invoices where id=invoice_id) is not null
    or (select state from public.e10_supplier_invoice_lines where id=cancelled_line)<>'cancelled'
    or (select count(*) from public.e10_supplier_invoice_revisions where supplier_invoice_id=invoice_id and revision=2)<>1
    or (select count(*) from public.e10_supplier_credit_revisions where supplier_credit_id=credit_id and revision=2)<>1
    or (select count(*) from public.e10_financial_document_events where organization_id=o and operation='amend')<>2
    or exists(select 1 from public.e10_financial_document_commands where organization_id=o
      and idempotency_key in ('x3d1b-stale','x3d1b-reduce','x3d1b-config','x3d1b-currency',
        'x3d1b-reuse','x3d1b-credit-reduce','x3d1b-low','x3d1b-cross-org')) then
    raise exception 'amend durable evidence or rollback residue invalid';
  end if;
  if has_function_privilege('anon','public.e10_org_amend_supplier_invoice(uuid,uuid,integer,text,date,numeric,jsonb,text,text)','execute')
    or has_function_privilege('authenticated','public._e10_org_amend_financial_document_x3d1b(uuid,text,uuid,integer,text,date,numeric,jsonb,text,text)','execute') then
    raise exception 'X3d.1b ACL closure failed';
  end if;
  raise notice 'TA-X3d.1b amendment, conservation, CAS, authority, immutable evidence: PASS';
end $$;

rollback;
