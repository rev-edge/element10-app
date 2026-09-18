-- TA-X3d.1d interoperability: match -> receive -> close -> release -> void.
begin;
do $$
declare
  o constant uuid:='d3210000-0000-4000-8000-000000000001';
  actor constant uuid:='d3210000-0000-4000-8000-000000000002';
  role_id constant uuid:='d3210000-0000-4000-8000-000000000003';
  supplier constant uuid:='d3210000-0000-4000-8000-000000000004';
  location_id constant uuid:='d3210000-0000-4000-8000-000000000005';
  product_id constant uuid:='d3210000-0000-4000-8000-000000000006';
  config_id constant uuid:='d3210000-0000-4000-8000-000000000007';
  version_id constant uuid:='d3210000-0000-4000-8000-000000000008';
  po constant uuid:='d3210000-0000-4000-8000-000000000009';
  pol constant uuid:='d3210000-0000-4000-8000-000000000010';
  invoice constant uuid:='d3210000-0000-4000-8000-000000000011';
  invoice_line constant uuid:='d3210000-0000-4000-8000-000000000012';
  item constant text:='x3d1d-lifecycle-item';
  r jsonb; receipt_id uuid;
begin
  insert into public.e10_organizations(id,name,slug) values(o,'X3d1d lifecycle','x3d1d-lifecycle');
  insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at)
    values(actor,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','x3d1d-lifecycle@example.invalid',now(),now());
  insert into public.e10_organization_roles(id,organization_id,key,name) values(role_id,o,'x3d1d-life','X3d1d lifecycle');
  insert into public.e10_organization_memberships(organization_id,user_id,role_id,status) values(o,actor,role_id,'active');
  insert into public.e10_organization_role_permissions(organization_id,role_id,capability,allowed) values
    (o,role_id,'act.purchasing_prepare',true),(o,role_id,'act.purchasing_cancel',true),
    (o,role_id,'act.create_receiving',true);
  insert into public.e10_suppliers(id,organization_id,name,status) values(supplier,o,'Lifecycle supplier','active');
  insert into public.e10_locations(id,organization_id,name,status) values(location_id,o,'Lifecycle location','active');
  insert into public.e10_location_role_permissions(organization_id,location_id,role_id,can_receive)
    values(o,location_id,role_id,true);
  insert into public.e10_product_masters(id,organization_id,name) values(product_id,o,'Lifecycle product');
  insert into public.e10_product_configurations(id,organization_id,product_master_id,name)
    values(config_id,o,product_id,'Lifecycle config');
  insert into public.e10_product_configuration_versions
    (id,organization_id,configuration_id,version_no,state,packaging_kind,base_unit,base_units_per_package)
    values(version_id,o,config_id,1,'active','unit','unit',1);
  insert into public.e10_inventory_items(id,name,qty,organization_id) values(item,'Lifecycle item',0,o);
  insert into public.e10_purchase_orders
    (id,organization_id,supplier_id,destination_location_id,order_number,status,currency,created_by)
    values(po,o,supplier,location_id,'X3D1D-LIFE-PO','approved','CAD',actor);
  insert into public.e10_purchase_order_lines
    (id,organization_id,purchase_order_id,configuration_version_id,line_no,ordered_quantity)
    values(pol,o,po,version_id,1,2);
  insert into public.e10_supplier_invoices
    (id,organization_id,supplier_id,supplier_document_number,status,currency,total_amount,created_by)
    values(invoice,o,supplier,'X3D1D-LIFE-INV','approved','CAD',20,actor);
  update public.e10_supplier_invoices set approved_revision=1,approved_by=actor,approved_at=now() where id=invoice;
  insert into public.e10_supplier_invoice_lines
    (id,organization_id,supplier_invoice_id,configuration_version_id,line_no,invoiced_quantity,unit_cost,line_amount)
    values(invoice_line,o,invoice,version_id,1,2,10,20);

  perform set_config('request.jwt.claims',jsonb_build_object('sub',actor,'role','authenticated')::text,true);
  set local role authenticated;
  r:=public.e10_org_allocate_invoice_to_po(o,invoice_line,pol,1,1,2,'full match','x3d1d-life-match');
  if r->>'supplier_invoice_revision'<>'2' then raise exception 'initial match failed: %',r; end if;
  r:=public.e10_org_receive_po_line(o,pol,item,2,0,0,'x3d1d-life-lot','2026-09-11T22:00:00Z','[]','x3d1d-life-receive');
  receipt_id:=(r->>'receipt_id')::uuid;
  r:=public.e10_org_transition_purchase_order(o,po,1,'close','fully received','x3d1d-life-close');
  if r->>'status'<>'closed' or r->>'revision'<>'2' then raise exception 'PO close failed: %',r; end if;
  r:=public.e10_org_release_invoice_from_po(o,invoice_line,pol,2,2,2,'release closed match','x3d1d-life-release');
  if r->>'allocated_quantity'<>'0' or r->>'supplier_invoice_revision'<>'3' then raise exception 'closed release failed: %',r; end if;
  r:=public.e10_org_void_supplier_invoice(o,invoice,3,'released invoice void','x3d1d-life-void');
  if r->>'status'<>'void' or r->>'revision'<>'4' then raise exception 'post-release void failed: %',r; end if;
  reset role;

  set constraints all immediate;
  if exists(select 1 from public.e10_invoice_po_allocations where organization_id=o)
    or (select coalesce(sum(quantity_delta),0) from public.e10_invoice_po_allocation_events
      where organization_id=o and invoice_line_id=invoice_line and purchase_order_line_id=pol)<>0
    or (select count(*) from public.e10_invoice_po_allocation_events where organization_id=o)<>2
    or not exists(select 1 from public.e10_stock_receipts where organization_id=o and id=receipt_id and status='posted')
    or (select qty from public.e10_inventory_items where organization_id=o and id=item)<>2
    or (select coalesce(sum(on_hand_delta),0) from public.e10_inventory_movements where organization_id=o and item_id=item)<>2
    or (select status from public.e10_purchase_orders where organization_id=o and id=po)<>'closed'
    or (select status from public.e10_supplier_invoices where organization_id=o and id=invoice)<>'void' then
    raise exception 'lifecycle reconciliation failed';
  end if;
  raise notice 'TA-X3d.1d match -> receive -> close -> release -> void interoperability: PASS';
end $$;
rollback;
