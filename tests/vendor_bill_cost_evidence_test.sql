-- BILL-12 approved-source versus provisional receipt cost. Self-failing and rolled back.
begin;
do $$
declare
  o uuid:=gen_random_uuid();reviewer uuid:=gen_random_uuid();approver uuid:=gen_random_uuid();role_id uuid:=gen_random_uuid();
  supplier uuid:=gen_random_uuid();location_id uuid:=gen_random_uuid();product_id uuid:=gen_random_uuid();config_id uuid:=gen_random_uuid();version_id uuid:=gen_random_uuid();
  invoice_id uuid:=gen_random_uuid();invoice_line_id uuid:=gen_random_uuid();receipt_id uuid:=gen_random_uuid();v_receipt_line_id uuid:=gen_random_uuid();r jsonb;
begin
  insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at) values
    (reviewer,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','bill-reviewer-'||reviewer||'@example.invalid',now(),now()),
    (approver,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','bill-approver-'||approver||'@example.invalid',now(),now());
  insert into public.e10_organizations(id,name,slug) values(o,'Bill cost org','bill-cost-'||substr(o::text,1,8));
  insert into public.e10_organization_roles(id,organization_id,key,name) values(role_id,o,'bill-cost','Bill cost');
  insert into public.e10_organization_memberships(organization_id,user_id,role_id,status) values(o,reviewer,role_id,'active'),(o,approver,role_id,'active');
  insert into public.e10_organization_role_permissions(organization_id,role_id,capability,allowed) values
    (o,role_id,'act.purchasing_approve',true),(o,role_id,'financial.actual_cost.read',true);
  insert into public.e10_suppliers(id,organization_id,name) values(supplier,o,'Bill cost supplier');
  insert into public.e10_locations(id,organization_id,name) values(location_id,o,'Bill cost location');
  insert into public.e10_product_masters(id,organization_id,name) values(product_id,o,'Bill cost product');
  insert into public.e10_product_configurations(id,organization_id,product_master_id,name) values(config_id,o,product_id,'Bill cost config');
  insert into public.e10_product_configuration_versions(id,organization_id,configuration_id,version_no,state,packaging_kind,base_unit,base_units_per_package)
    values(version_id,o,config_id,1,'active','box','box',1);
  insert into public.e10_supplier_invoices(id,organization_id,supplier_id,supplier_document_number,status,currency,total_amount,
    reviewed_by,reviewed_at,approved_revision,approved_by,approved_at,revision)
    values(invoice_id,o,supplier,'BILL-COST','approved','CAD',120,reviewer,now(),1,approver,now(),1);
  insert into public.e10_supplier_invoice_lines(id,organization_id,supplier_invoice_id,configuration_version_id,line_no,invoiced_quantity,unit_cost,line_amount)
    values(invoice_line_id,o,invoice_id,version_id,1,12,10,120);
  insert into public.e10_stock_receipts(id,organization_id,supplier_id,destination_location_id,status,received_at,created_by)
    values(receipt_id,o,supplier,location_id,'posted',now(),reviewer);
  insert into public.e10_stock_receipt_lines(id,organization_id,stock_receipt_id,configuration_version_id,line_no,
    received_quantity,accepted_quantity,damaged_quantity,quarantined_quantity,actual_unit_cost,currency)
    values(v_receipt_line_id,o,receipt_id,version_id,1,10,10,0,0,9,'CAD');
  insert into public.e10_receipt_invoice_allocations(organization_id,receipt_line_id,invoice_line_id,allocated_quantity)
    values(o,v_receipt_line_id,invoice_line_id,10);
  if (select count(*) from public.e10_receipt_cost_evidence where receipt_line_id=v_receipt_line_id and evidence_basis='operator_entered')<>1 then
    raise exception 'operator receipt cost was not preserved as provisional evidence';
  end if;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',approver,'role','authenticated')::text,true);
  set local role authenticated;
  r:=public.e10_org_record_approved_invoice_receipt_cost(o,v_receipt_line_id,invoice_line_id,10,10,'approved invoice supports receipt','bill-cost-approved');
  if r->>'evidence_basis'<>'approved_invoice_supported' or r->>'payment_status'<>'unavailable_not_modeled' then raise exception 'approved evidence result invalid: %',r;end if;
  if (public.e10_org_record_approved_invoice_receipt_cost(o,v_receipt_line_id,invoice_line_id,10,10,'approved invoice supports receipt','bill-cost-approved')->>'replay')<>'true' then raise exception 'cost evidence replay failed';end if;
  reset role;
  if (select count(*) from public.e10_receipt_cost_evidence where organization_id=o)<>2 then raise exception 'cost evidence count invalid';end if;
  if has_function_privilege('anon','public.e10_org_record_approved_invoice_receipt_cost(uuid,uuid,uuid,numeric,numeric,text,text)','execute') then raise exception 'anon cost evidence execute';end if;
  raise notice 'Vendor bill cost evidence: PASS (provisional receipt entry, approved revision support, payment unavailable, replay)';
end $$;
rollback;
