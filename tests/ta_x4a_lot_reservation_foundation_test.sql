-- TA-X4a lot and reservation foundation gate. Self-failing and rolled back.
begin;
do $$
declare
  o uuid:='e1000000-0000-4000-8000-0000000000a6'; ob uuid:='e1000000-0000-4000-8000-00000000e4a0';
  supplier uuid:=gen_random_uuid(); location uuid:=gen_random_uuid(); product uuid:=gen_random_uuid(); config uuid:=gen_random_uuid();
  po uuid:=gen_random_uuid(); pol uuid:=gen_random_uuid(); lot uuid:=gen_random_uuid(); c bigint;
begin
  insert into public.e10_organizations(id,name,slug) values(ob,'X4 Org B','x4-org-b');
  insert into public.e10_suppliers(id,organization_id,name) values(supplier,o,'X4 Supplier');
  insert into public.e10_locations(id,organization_id,name) values(location,o,'X4 Location');
  insert into public.e10_product_masters(id,organization_id,name) values(product,o,'X4 Product');
  insert into public.e10_product_configurations(id,organization_id,product_master_id,name) values(config,o,product,'Each');
  insert into public.e10_product_configuration_versions(id,organization_id,configuration_id,version_no,state,packaging_kind,base_unit,base_units_per_package) values(config,o,config,1,'active','each','each',1);
  insert into public.e10_purchase_orders(id,organization_id,supplier_id,destination_location_id,currency) values(po,o,supplier,location,'CAD');
  insert into public.e10_purchase_order_lines(id,organization_id,purchase_order_id,configuration_version_id,line_no,ordered_quantity) values(pol,o,po,config,1,10);
  insert into public.e10_inventory_lots(id,organization_id,configuration_version_id,location_id,supplier_id,lot_code,status,accepted_quantity) values(lot,o,config,location,supplier,'X4-LOT','available',10);
  insert into public.e10_lot_cost_evidence(organization_id,lot_id,evidence_kind,amount,currency,source_note,occurred_at) values(o,lot,'freight',20,'CAD','carrier invoice pending match',now());
  insert into public.e10_expected_inventory_allocations(organization_id,purchase_order_line_id,destination_location_id,expected_quantity) values(o,pol,location,10);
  insert into public.e10_lot_reservations(organization_id,lot_id,quantity,source_type,source_id,idempotency_key) values(o,lot,2,'manual','fixture','x4-reserve-1');
  select count(*) into c from public.e10_inventory_lots where id=lot; if c<>1 then raise exception 'lot missing'; end if;
  begin insert into public.e10_inventory_lots(organization_id,configuration_version_id,location_id,status,accepted_quantity) values(ob,config,location,'available',1); raise exception 'cross-org lot allowed'; exception when foreign_key_violation then null; end;
  begin insert into public.e10_lot_reservations(organization_id,lot_id,quantity,source_type,source_id,idempotency_key) values(ob,lot,1,'manual','foreign','x4-reserve-foreign'); raise exception 'cross-org reservation allowed'; exception when foreign_key_violation then null; end;
  begin update public.e10_lot_cost_evidence set amount=0 where lot_id=lot; raise exception 'cost evidence update allowed'; exception when sqlstate '55000' then null; end;
  begin insert into public.e10_lot_reservations(organization_id,lot_id,quantity,source_type,source_id,idempotency_key) values(o,lot,1,'manual','fixture','x4-reserve-2'); raise exception 'duplicate active reservation allowed'; exception when unique_violation then null; end;
  raise notice 'TA-X4a lot/reservation foundation: PASS';
end $$;

set local role authenticated;
do $$ declare t text; begin
  foreach t in array array['e10_inventory_lots','e10_lot_cost_evidence','e10_expected_inventory_allocations','e10_lot_reservations'] loop
    begin execute format('select 1 from public.%I',t); raise exception 'authenticated can read %',t; exception when insufficient_privilege then null; end;
    if has_table_privilege('authenticated','public.'||t,'insert') then raise exception 'authenticated can insert %',t; end if;
  end loop;
  raise notice 'TA-X4a fail-closed ACL: PASS';
end $$;
reset role;
rollback;
