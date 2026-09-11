-- TA-X3d.1d allocation/release functional gate. Self-failing and rolled back.
begin;

do $$
declare
  o constant uuid:='d31f0000-0000-4000-8000-000000000001';
  actor constant uuid:='d31f0000-0000-4000-8000-000000000002';
  role_id constant uuid:='d31f0000-0000-4000-8000-000000000003';
  supplier constant uuid:='d31f0000-0000-4000-8000-000000000004';
  location_id constant uuid:='d31f0000-0000-4000-8000-000000000005';
  product_id constant uuid:='d31f0000-0000-4000-8000-000000000006';
  config_id constant uuid:='d31f0000-0000-4000-8000-000000000007';
  version_id constant uuid:='d31f0000-0000-4000-8000-000000000008';
  po1 constant uuid:='d31f0000-0000-4000-8000-000000000009';
  po2 constant uuid:='d31f0000-0000-4000-8000-000000000010';
  pol1 constant uuid:='d31f0000-0000-4000-8000-000000000011';
  pol2 constant uuid:='d31f0000-0000-4000-8000-000000000012';
  inv1 constant uuid:='d31f0000-0000-4000-8000-000000000013';
  inv2 constant uuid:='d31f0000-0000-4000-8000-000000000014';
  il1 constant uuid:='d31f0000-0000-4000-8000-000000000015';
  il2 constant uuid:='d31f0000-0000-4000-8000-000000000016';
  credit constant uuid:='d31f0000-0000-4000-8000-000000000017';
  cl constant uuid:='d31f0000-0000-4000-8000-000000000018';
  r jsonb; replay jsonb; baseline jsonb;
begin
  insert into public.e10_organizations(id,name,slug) values(o,'X3d1d org','x3d1d-org');
  insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at)
    values(actor,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','x3d1d@example.invalid',now(),now());
  insert into public.e10_organization_roles(id,organization_id,key,name)
    values(role_id,o,'x3d1d','X3d1d');
  insert into public.e10_organization_memberships(organization_id,user_id,role_id,status)
    values(o,actor,role_id,'active');
  insert into public.e10_organization_role_permissions(organization_id,role_id,capability,allowed)
    values(o,role_id,'act.purchasing_prepare',true);
  insert into public.e10_suppliers(id,organization_id,name,status) values(supplier,o,'X3d1d supplier','active');
  insert into public.e10_locations(id,organization_id,name,status) values(location_id,o,'X3d1d location','active');
  insert into public.e10_location_role_permissions(organization_id,location_id,role_id,can_receive)
    values(o,location_id,role_id,true);
  insert into public.e10_product_masters(id,organization_id,name) values(product_id,o,'X3d1d product');
  insert into public.e10_product_configurations(id,organization_id,product_master_id,name)
    values(config_id,o,product_id,'X3d1d config');
  insert into public.e10_product_configuration_versions
    (id,organization_id,configuration_id,version_no,state,packaging_kind,base_unit,base_units_per_package)
    values(version_id,o,config_id,1,'active','unit','unit',1);
  insert into public.e10_purchase_orders
    (id,organization_id,supplier_id,destination_location_id,order_number,status,currency,created_by)
    values(po1,o,supplier,location_id,'X3D1D-PO1','approved','CAD',actor),
      (po2,o,supplier,location_id,'X3D1D-PO2','submitted','CAD',actor);
  insert into public.e10_purchase_order_lines
    (id,organization_id,purchase_order_id,configuration_version_id,line_no,ordered_quantity)
    values(pol1,o,po1,version_id,1,8),(pol2,o,po2,version_id,1,8);
  insert into public.e10_supplier_invoices
    (id,organization_id,supplier_id,supplier_document_number,status,currency,total_amount,created_by)
    values(inv1,o,supplier,'X3D1D-INV1','approved','CAD',100,actor),
      (inv2,o,supplier,'X3D1D-INV2','draft','CAD',40,actor);
  update public.e10_supplier_invoices set approved_revision=1,approved_by=actor,approved_at=now() where id=inv1;
  insert into public.e10_supplier_invoice_lines
    (id,organization_id,supplier_invoice_id,configuration_version_id,line_no,invoiced_quantity,unit_cost,line_amount)
    values(il1,o,inv1,version_id,1,10,10,100),(il2,o,inv2,version_id,1,4,10,40);
  insert into public.e10_supplier_credits
    (id,organization_id,supplier_id,supplier_document_number,status,currency,total_amount,created_by)
    values(credit,o,supplier,'X3D1D-CR','approved','CAD',30,actor);
  update public.e10_supplier_credits set approved_revision=1,approved_by=actor,approved_at=now() where id=credit;
  insert into public.e10_supplier_credit_lines
    (id,organization_id,supplier_credit_id,configuration_version_id,line_no,line_amount)
    values(cl,o,credit,version_id,1,30);
  baseline:=jsonb_build_object('receipts',(select count(*) from public.e10_stock_receipts),
    'lots',(select count(*) from public.e10_inventory_lots),'movements',(select count(*) from public.e10_inventory_movements));

  perform set_config('request.jwt.claims',jsonb_build_object('sub',actor,'role','authenticated')::text,true);
  set local role authenticated;
  r:=public.e10_org_allocate_invoice_to_po(o,il1,pol1,1,1,6,'first partial','x3d1d-ip-1');
  if r->>'allocated_quantity'<>'6' or r->>'supplier_invoice_revision'<>'2'
    or r->>'supplier_invoice_status'<>'reviewed' then raise exception 'invoice allocation failed: %',r; end if;
  replay:=public.e10_org_allocate_invoice_to_po(o,il1,pol1,1,1,6,'first partial','x3d1d-ip-1');
  if replay->>'replay'<>'true' or replay->>'supplier_invoice_revision'<>'2' then raise exception 'replay failed'; end if;
  r:=public.e10_org_allocate_invoice_to_po(o,il1,pol2,2,1,4,'split target','x3d1d-ip-2');
  if r->>'allocated_quantity'<>'4' or r->>'supplier_invoice_revision'<>'3' then raise exception 'split failed'; end if;
  begin
    perform public.e10_org_allocate_invoice_to_po(o,il2,pol1,1,1,3,'target overrun','x3d1d-ip-over');
    raise exception 'target conservation failed'; exception when check_violation then null; end;
  r:=public.e10_org_release_invoice_from_po(o,il1,pol1,3,1,2,'partial release','x3d1d-ip-release');
  if r->>'allocated_quantity'<>'4' or r->>'supplier_invoice_revision'<>'4' then raise exception 'release failed'; end if;
  begin
    perform public.e10_org_release_invoice_from_po(o,il1,pol1,4,1,5,'excess release','x3d1d-ip-excess');
    raise exception 'excess release accepted'; exception when check_violation then null; end;

  r:=public.e10_org_allocate_credit_to_invoice(o,cl,il1,1,4,20,'credit match','x3d1d-ci-1');
  if r->>'allocated_amount'<>'20' or r->>'supplier_credit_revision'<>'2'
    or r->>'supplier_invoice_revision'<>'5' or r->>'supplier_credit_status'<>'reviewed' then
    raise exception 'credit allocation failed: %',r; end if;
  r:=public.e10_org_allocate_credit_to_invoice(o,cl,il2,2,1,10,'credit split','x3d1d-ci-2');
  if r->>'supplier_credit_revision'<>'3' or r->>'supplier_invoice_revision'<>'2' then raise exception 'credit split failed'; end if;
  begin
    perform public.e10_org_allocate_credit_to_invoice(o,cl,il1,3,5,1,'credit overrun','x3d1d-ci-over');
    raise exception 'credit conservation failed'; exception when check_violation then null; end;
  r:=public.e10_org_release_credit_from_invoice(o,cl,il1,3,5,5,'credit release','x3d1d-ci-release');
  if r->>'allocated_amount'<>'15' or r->>'supplier_credit_revision'<>'4'
    or r->>'supplier_invoice_revision'<>'6' then raise exception 'credit release failed'; end if;
  begin
    perform public.e10_org_allocate_invoice_to_po(o,il1,pol1,6,1,'NaN'::numeric,'bad','x3d1d-nan');
    raise exception 'NaN accepted'; exception when invalid_parameter_value then null; end;
  begin
    perform public.e10_org_allocate_invoice_to_po(o,il1,pol1,1,1,1,'stale','x3d1d-stale');
    raise exception 'stale CAS accepted'; exception when sqlstate '40001' then null; end;
  begin
    perform public.e10_org_allocate_invoice_to_po(o,il1,pol1,1,1,7,'changed','x3d1d-ip-1');
    raise exception 'idempotency mismatch accepted'; exception when invalid_parameter_value then null; end;
  reset role;

  set constraints all immediate;
  if (select sum(allocated_quantity) from public.e10_invoice_po_allocations where organization_id=o and invoice_line_id=il1)<>8
    or (select sum(allocated_amount) from public.e10_credit_invoice_allocations where organization_id=o and credit_line_id=cl)<>25
    or (select count(*) from public.e10_invoice_po_allocation_events where organization_id=o)<>3
    or (select count(*) from public.e10_credit_invoice_allocation_events where organization_id=o)<>3
    or (select count(*) from public.e10_financial_allocation_commands where organization_id=o)<>6
    or exists(select 1 from public.e10_financial_allocation_commands where organization_id=o
      and idempotency_key in ('x3d1d-ip-over','x3d1d-ip-excess','x3d1d-ci-over','x3d1d-nan','x3d1d-stale'))
    or not exists(select 1 from public.e10_supplier_invoice_revisions where organization_id=o
      and supplier_invoice_id=inv1 and revision=2 and status='reviewed'
      and jsonb_array_length(snapshot->'purchase_order_allocations')=1)
    or not exists(select 1 from public.e10_supplier_credit_revisions where organization_id=o
      and supplier_credit_id=credit and revision=2
      and jsonb_array_length(snapshot->'invoice_allocations')=1)
    or (select approved_revision from public.e10_supplier_invoices where id=inv1) is not null
    or (select approved_revision from public.e10_supplier_credits where id=credit) is not null then
    raise exception 'allocation evidence invalid';
  end if;
  if (select count(*) from public.e10_stock_receipts)<>(baseline->>'receipts')::bigint
    or (select count(*) from public.e10_inventory_lots)<>(baseline->>'lots')::bigint
    or (select count(*) from public.e10_inventory_movements)<>(baseline->>'movements')::bigint then
    raise exception 'allocation created operational side effect';
  end if;
  if has_function_privilege('anon','public.e10_org_allocate_invoice_to_po(uuid,uuid,uuid,integer,integer,numeric,text,text)','execute')
    or not has_function_privilege('authenticated','public.e10_org_allocate_credit_to_invoice(uuid,uuid,uuid,integer,integer,numeric,text,text)','execute')
    or has_function_privilege('authenticated','public._e10_org_financial_allocation_x3d1d(uuid,text,text,uuid,uuid,integer,integer,numeric,text,text)','execute') then
    raise exception 'allocation ACL closure failed';
  end if;
  raise notice 'TA-X3d.1d allocation/release conservation, replay, CAS, history, ACL, no-side-effects: PASS';
end $$;

rollback;
