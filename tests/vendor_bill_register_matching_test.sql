-- BILL-03/04/05/09/10 invoice-after-receipt matching and bill register.
-- Self-failing and rolled back.
begin;
do $$
declare
  o uuid:=gen_random_uuid(); actor uuid:=gen_random_uuid(); role_id uuid:=gen_random_uuid();
  supplier uuid:=gen_random_uuid(); location_id uuid:=gen_random_uuid(); product_id uuid:=gen_random_uuid();
  config_id uuid:=gen_random_uuid(); version_id uuid:=gen_random_uuid(); receipt_id uuid:=gen_random_uuid();
  receipt_line uuid:=gen_random_uuid(); invoice_a uuid:=gen_random_uuid(); invoice_b uuid:=gen_random_uuid();
  line_a uuid:=gen_random_uuid(); line_b uuid:=gen_random_uuid(); case_id uuid:=gen_random_uuid();
  before_movements bigint; before_lots bigint; r jsonb; page_1 jsonb; page_2 jsonb; detail jsonb; decision jsonb;
begin
  insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at)
    values(actor,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','bill-register-'||actor||'@example.invalid',now(),now());
  insert into public.e10_organizations(id,name,slug) values(o,'Bill register org','bill-register-'||substr(o::text,1,8));
  insert into public.e10_organization_roles(id,organization_id,key,name) values(role_id,o,'bill-register','Bill register');
  insert into public.e10_organization_memberships(organization_id,user_id,role_id,status) values(o,actor,role_id,'active');
  insert into public.e10_organization_role_permissions(organization_id,role_id,capability,allowed) values
    (o,role_id,'act.purchasing_prepare',true),(o,role_id,'act.purchasing_approve',true),
    (o,role_id,'financial.actual_cost.read',true);
  insert into public.e10_suppliers(id,organization_id,name) values(supplier,o,'Bill register supplier');
  insert into public.e10_locations(id,organization_id,name) values(location_id,o,'Bill register location');
  insert into public.e10_product_masters(id,organization_id,name) values(product_id,o,'Bill register product');
  insert into public.e10_product_configurations(id,organization_id,product_master_id,name) values(config_id,o,product_id,'Bill register config');
  insert into public.e10_product_configuration_versions
    (id,organization_id,configuration_id,version_no,state,packaging_kind,base_unit,base_units_per_package,quantity_increment)
    values(version_id,o,config_id,1,'active','unit','unit',1,1);
  insert into public.e10_stock_receipts(id,organization_id,supplier_id,destination_location_id,status,received_at,created_by)
    values(receipt_id,o,supplier,location_id,'posted',now(),actor);
  insert into public.e10_stock_receipt_lines(id,organization_id,stock_receipt_id,configuration_version_id,line_no,
    received_quantity,accepted_quantity,damaged_quantity,quarantined_quantity,currency)
    values(receipt_line,o,receipt_id,version_id,1,10,10,0,0,'CAD');
  insert into public.e10_supplier_invoices(id,organization_id,supplier_id,supplier_document_number,status,currency,document_date,total_amount,created_by)
    values(invoice_a,o,supplier,'REG-A','draft','CAD','2026-09-14',120,actor),
          (invoice_b,o,supplier,'REG-B','approved','CAD',null,50,actor);
  insert into public.e10_supplier_invoice_lines(id,organization_id,supplier_invoice_id,configuration_version_id,line_no,invoiced_quantity,unit_cost,line_amount)
    values(line_a,o,invoice_a,version_id,1,12,10,120),(line_b,o,invoice_b,version_id,1,5,10,50);
  select count(*) into before_movements from public.e10_inventory_movements where organization_id=o;
  select count(*) into before_lots from public.e10_inventory_lots where organization_id=o;

  perform set_config('request.jwt.claims',jsonb_build_object('sub',actor,'role','authenticated')::text,true);
  set local role authenticated;
  r:=public.e10_org_link_receipt_to_invoice(o,receipt_line,line_a,10,'link','invoice arrived after receipt','bill-link-1');
  if r->>'stock_changed'<>'false' or r->>'allocated_quantity'<>'10' then raise exception 'link result invalid: %',r;end if;
  if (public.e10_org_link_receipt_to_invoice(o,receipt_line,line_a,10,'link','invoice arrived after receipt','bill-link-1')->>'replay')<>'true' then raise exception 'link replay failed';end if;
  begin
    perform public.e10_org_link_receipt_to_invoice(o,receipt_line,line_a,3,'link','over allocation','bill-link-over');
    raise exception 'receipt/invoice conservation not enforced';
  exception when check_violation then null;end;

  page_1:=public.e10_org_bill_register(o,null,null,null,null,null,1,null);
  if jsonb_array_length(page_1->'items')<>1 or page_1->>'has_more'<>'true'
    or page_1#>>'{full_dataset_totals_by_currency,CAD,document_count}'<>'2'
    or page_1#>>'{full_dataset_totals_by_currency,CAD,known_total_amount}'<>'170'
    or page_1->>'payment_status'<>'unavailable_not_modeled' then raise exception 'bill page 1 invalid: %',page_1;end if;
  page_2:=public.e10_org_bill_register(o,null,null,null,null,null,1,page_1->>'next_cursor');
  if jsonb_array_length(page_2->'items')<>1 or page_2->>'has_more'<>'false' then raise exception 'bill page 2 invalid: %',page_2;end if;
  detail:=public.e10_org_bill_detail(o,invoice_a,1,null);
  if detail#>>'{header,invoice_id}'<>invoice_a::text or detail#>>'{header,payment_status}'<>'unavailable_not_modeled'
    or jsonb_array_length(detail->'lines')<>1 or detail#>>'{lines,0,receipt_allocations,0,stock_receipt_id}'<>receipt_id::text then raise exception 'bill detail invalid: %',detail;end if;

  reset role;
  insert into public.e10_financial_document_reconciliation_cases
    (id,organization_id,document_kind,identity_kind,supplier_id,normalized_document_number,existing_document_id,existing_fingerprint,received_fingerprint,created_by)
    values(case_id,o,'supplier_invoice','manual',supplier,'reg-a',invoice_a,'old-fingerprint','new-fingerprint',actor);
  set local role authenticated;
  decision:=public.e10_org_decide_financial_document_reconciliation(o,case_id,'same_document','reviewed source evidence','{}','bill-decision-1');
  if decision->>'outcome'<>'same_document' or decision->>'replay'<>'false' then raise exception 'decision result invalid: %',decision;end if;
  if (public.e10_org_decide_financial_document_reconciliation(o,case_id,'same_document','reviewed source evidence','{}','bill-decision-1')->>'replay')<>'true' then raise exception 'decision replay failed';end if;
  begin
    perform public.e10_org_decide_financial_document_reconciliation(o,case_id,'different_document','changed decision','{}','bill-decision-2');
    raise exception 'immutable decision was replaced';
  exception when sqlstate '22023' then null;end;
  reset role;

  if (select count(*) from public.e10_inventory_movements where organization_id=o)<>before_movements
    or (select count(*) from public.e10_inventory_lots where organization_id=o)<>before_lots then raise exception 'invoice linking changed stock';end if;
  if has_function_privilege('anon','public.e10_org_bill_register(uuid,text[],uuid,text,date,date,integer,text)','execute')
    or has_function_privilege('anon','public.e10_org_link_receipt_to_invoice(uuid,uuid,uuid,numeric,text,text,text)','execute') then raise exception 'anon vendor bill API execute';end if;
  raise notice 'Vendor bill register and matching: PASS (pagination totals, null dates, no duplicate stock, immutable decision, replay)';
end $$;
rollback;
