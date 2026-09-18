-- BILL-06 and BILL-11 backend contract gate. Self-failing and rolled back.
begin;
do $$
declare
  o uuid:=gen_random_uuid();p uuid:=gen_random_uuid();c uuid:=gen_random_uuid();v uuid:=gen_random_uuid();
  s uuid:=gen_random_uuid();l uuid:=gen_random_uuid();po uuid:=gen_random_uuid();pol uuid:=gen_random_uuid();
  inv uuid:=gen_random_uuid();il uuid:=gen_random_uuid();receipt uuid:=gen_random_uuid();rl uuid:=gen_random_uuid();lot uuid:=gen_random_uuid();
begin
  insert into public.e10_organizations(id,name,slug) values(o,'Bill contract guard','bill-contract-'||substr(o::text,1,8));
  insert into public.e10_product_masters(id,organization_id,name) values(p,o,'Divisible product');
  insert into public.e10_product_configurations(id,organization_id,product_master_id,name) values(c,o,p,'Quarter unit');
  insert into public.e10_product_configuration_versions(id,organization_id,configuration_id,version_no,state,packaging_kind,base_unit,base_units_per_package,quantity_increment)
    values(v,o,c,1,'active','bulk','unit',1,0.25);
  insert into public.e10_suppliers(id,organization_id,name) values(s,o,'Guard supplier');
  insert into public.e10_locations(id,organization_id,name) values(l,o,'Guard location');
  insert into public.e10_purchase_orders(id,organization_id,supplier_id,destination_location_id,currency,status) values(po,o,s,l,'CAD','approved');
  insert into public.e10_purchase_order_lines(id,organization_id,purchase_order_id,configuration_version_id,line_no,ordered_quantity)
    values(pol,o,po,v,1,1.25);
  begin
    update public.e10_purchase_order_lines set ordered_quantity=1.10 where id=pol;
    raise exception 'nonincrement PO quantity accepted';
  exception when check_violation then
    if sqlerrm<>'configuration_quantity_increment_violation' then raise;end if;
  end;
  insert into public.e10_supplier_invoices(id,organization_id,supplier_id,supplier_document_number,currency,total_amount)
    values(inv,o,s,'BILL-GUARD','CAD',10);
  insert into public.e10_supplier_invoice_lines(id,organization_id,supplier_invoice_id,configuration_version_id,line_no,invoiced_quantity,line_amount)
    values(il,o,inv,v,1,1.25,10);
  begin
    update public.e10_supplier_invoice_lines set invoiced_quantity=1.1 where id=il;
    raise exception 'nonincrement invoice quantity accepted';
  exception when check_violation then
    if sqlerrm<>'configuration_quantity_increment_violation' then raise;end if;
  end;
  insert into public.e10_stock_receipts(id,organization_id,supplier_id,destination_location_id,status) values(receipt,o,s,l,'posted');
  insert into public.e10_stock_receipt_lines(id,organization_id,stock_receipt_id,configuration_version_id,line_no,received_quantity,accepted_quantity,damaged_quantity,quarantined_quantity)
    values(rl,o,receipt,v,1,1.25,0.75,0.25,0.25);
  insert into public.e10_inventory_lots(id,organization_id,configuration_version_id,location_id,supplier_id,stock_receipt_line_id,status,accepted_quantity,quarantined_quantity)
    values(lot,o,v,l,s,rl,'available',0.75,0.25);
  begin
    insert into public.e10_lot_reservations(organization_id,lot_id,quantity,source_type,source_id,idempotency_key)
      values(o,lot,0.1,'manual','bad','bad');
    raise exception 'nonincrement reservation accepted';
  exception when check_violation then
    if sqlerrm<>'configuration_quantity_increment_violation' then raise;end if;
  end;
  begin
    update public.e10_product_configuration_versions set quantity_increment=0.5 where id=v;
    raise exception 'quantity increment mutation accepted';
  exception when object_not_in_prerequisite_state then
    if sqlerrm<>'configuration_quantity_increment_immutable' then raise;end if;
  end;
  if has_function_privilege('anon','e10.assert_configuration_quantity(uuid,uuid,numeric,text)','execute')
    or not has_function_privilege('authenticated','public.e10_org_create_configuration_version(uuid,uuid,integer,text,text,text,numeric,numeric,text,jsonb,text)','execute') then
    raise exception 'quantity contract ACL invalid';
  end if;
  raise notice 'Vendor bill contract guards: PASS (immutable 0.25 grain across PO, invoice, receipt, lot and reservation)';
end $$;
rollback;
