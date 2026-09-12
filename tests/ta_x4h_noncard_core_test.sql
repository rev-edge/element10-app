\set ON_ERROR_STOP on
begin;
do $$
#variable_conflict use_variable
declare
  o uuid:=gen_random_uuid(); foreign_org uuid:=gen_random_uuid(); actor uuid:=gen_random_uuid(); role_id uuid:=gen_random_uuid();
  supplier uuid:=gen_random_uuid(); location_id uuid:=gen_random_uuid(); product_id uuid:=gen_random_uuid();
  config_id uuid:=gen_random_uuid(); camera_product_id uuid:=gen_random_uuid(); camera_config_id uuid:=gen_random_uuid();
  invoice_id uuid:=gen_random_uuid(); invoice_line_id uuid:=gen_random_uuid(); camera_invoice_line_id uuid:=gen_random_uuid();
  result jsonb; replay jsonb; history jsonb; camera_history jsonb; transition jsonb;
  lot_id uuid; camera_lot_id uuid; reservation_id uuid; camera_reservation_id uuid; n bigint;
begin
  insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at)
  values(actor,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',
    'x4h-'||actor||'@example.invalid',now(),now());
  insert into public.e10_organizations(id,slug,name)
  values(o,'x4h-'||substr(o::text,1,8),'X4h non-card shop'),
    (foreign_org,'x4h-'||substr(foreign_org::text,1,8),'X4h foreign shop');
  insert into public.e10_organization_modules(organization_id,module_key,enabled)
  values(o,'core',true);
  insert into public.e10_organization_roles(id,organization_id,key,name,is_system)
  values(role_id,o,'x4h','X4h operator',false);
  insert into public.e10_organization_role_permissions(organization_id,role_id,capability,allowed)
  values(o,role_id,'act.create_receiving',true),(o,role_id,'act.purchasing_prepare',true),
    (o,role_id,'act.reserve_inventory',true),(o,role_id,'act.inventory_edit',true),
    (o,role_id,'financial.actual_cost.read',true);
  insert into public.e10_organization_memberships(organization_id,user_id,role_id,status)
  values(o,actor,role_id,'active');
  insert into public.e10_suppliers(id,organization_id,code,name,status)
  values(supplier,o,'X4H','X4h apparel supplier','active');
  insert into public.e10_locations(id,organization_id,code,name,status)
  values(location_id,o,'X4H','X4h stockroom','active');
  insert into public.e10_location_role_permissions(organization_id,location_id,role_id,can_receive)
  values(o,location_id,role_id,true);
  insert into public.e10_product_masters(id,organization_id,name,status)
  values(product_id,o,'X4h apparel','active'),(camera_product_id,o,'X4h used camera','active');
  insert into public.e10_product_configurations(id,organization_id,product_master_id,name,status)
  values(config_id,o,product_id,'Carton','active'),(camera_config_id,o,camera_product_id,'Individual','active');
  insert into public.e10_product_configuration_versions(id,organization_id,configuration_id,version_no,state,
    packaging_kind,base_unit,base_units_per_package)
  values(config_id,o,config_id,1,'active','carton','each',12),
    (camera_config_id,o,camera_config_id,1,'active','each','each',1);
  insert into public.e10_inventory_items(id,name,qty,organization_id)
  values('x4h-apparel','X4h apparel cartons',0,o),('x4h-camera','X4h used camera',0,o);
  insert into public.e10_unique_items(organization_id,inventory_item_id,catalog_variant_id,item_kind,serial_numerator,condition)
  values(o,'x4h-camera',null,'camera',314159,'used');
  insert into public.e10_supplier_invoices(id,organization_id,supplier_id,supplier_document_number,status,currency,created_by)
  values(invoice_id,o,supplier,'X4H-INVOICE','draft','CAD',actor);
  insert into public.e10_supplier_invoice_lines(id,organization_id,supplier_invoice_id,configuration_version_id,
    line_no,invoiced_quantity,line_amount,state)
  values(invoice_line_id,o,invoice_id,config_id,1,10,110,'active'),
    (camera_invoice_line_id,o,invoice_id,camera_config_id,2,1,200,'active');

  perform set_config('request.jwt.claims',jsonb_build_object('sub',actor,'role','authenticated')::text,true);
  set local role authenticated;
  result:=public.e10_org_receive_batch(o,supplier,location_id,'2026-09-12T04:00:00Z',jsonb_build_array(
    jsonb_build_object('line_no',1,'configuration_version_id',config_id,'inventory_item_id','x4h-apparel',
      'accepted_quantity',10,'damaged_quantity',0,'quarantined_quantity',0,'actual_unit_cost',11,
      'currency','CAD','invoice_line_id',invoice_line_id,'expected_allocations',jsonb_build_array()),
    jsonb_build_object('line_no',2,'configuration_version_id',camera_config_id,'inventory_item_id','x4h-camera',
      'accepted_quantity',1,'damaged_quantity',0,'quarantined_quantity',0,'actual_unit_cost',200,
      'currency','CAD','invoice_line_id',camera_invoice_line_id,'expected_allocations',jsonb_build_array())
  ),'x4h-receive');
  lot_id:=(result#>>'{lines,0,lot_id}')::uuid;
  camera_lot_id:=(result#>>'{lines,1,lot_id}')::uuid;
  result:=public.e10_org_lot_reserve_for_demand(o,lot_id,2,'manual','web-order-314','Non-card web order','x4h-reserve');
  reservation_id:=(result->>'reservation_id')::uuid;
  -- Preserve the pre-R6 persisted fingerprint shape while replaying through
  -- the current semantic reservation contract.
  set local role postgres;
  set local session_replication_role=replica;
  update public.e10_lot_reservations set request_fingerprint='pre-r6-reservation-fingerprint-v1'
   where organization_id=o and id=reservation_id;
  set local session_replication_role=origin;
  if not exists(select 1 from public.e10_lot_reservations where organization_id=o and id=reservation_id and request_fingerprint='pre-r6-reservation-fingerprint-v1')then raise exception 'pre-R6 reservation fixture not stored';end if;
  set local role authenticated;
  replay:=public.e10_org_lot_reserve_for_demand(o,lot_id,2,'manual','web-order-314','Non-card web order','x4h-reserve');
  result:=public.e10_org_lot_reserve_for_demand(o,camera_lot_id,1,'sale_order','camera-order-1','Used camera order','x4h-camera-reserve');
  camera_reservation_id:=(result->>'reservation_id')::uuid;
  transition:=public.e10_org_lot_consume(o,camera_reservation_id,1,'x4h-camera-consume');
  history:=public.e10_org_supplier_actual_cost_history(o,supplier,config_id,'CAD','2026-09-13T00:00:00Z',10,null);
  camera_history:=public.e10_org_supplier_actual_cost_history(o,supplier,camera_config_id,'CAD','2026-09-13T00:00:00Z',10,null);
  if (result->>'replay')::boolean is distinct from false or (replay->>'replay')::boolean is distinct from true
    or replay->>'reservation_id' is distinct from reservation_id::text then raise exception 'generic reservation replay invalid';end if;
  if history#>>'{items,0,actual_unit_cost}' is distinct from '11' or history#>>'{items,0,accepted_quantity}' is distinct from '10'
    or history#>>'{items,0,inventory_lot_id}' is distinct from lot_id::text then raise exception 'non-card cost history invalid: %',history;end if;
  if camera_history#>>'{items,0,actual_unit_cost}' is distinct from '200' or camera_history#>>'{items,0,accepted_quantity}' is distinct from '1'
    or camera_history#>>'{items,0,inventory_lot_id}' is distinct from camera_lot_id::text
    or transition->>'status' is distinct from 'consumed' or transition->>'consumed_quantity' is distinct from '1' then
    raise exception 'unique camera receipt/cost/reserve/consume invalid history=% transition=%',camera_history,transition;end if;
  begin
    perform public.e10_org_lot_reserve_for_demand(o,lot_id,1,null,'null-kind','Null kind','x4h-null-kind');
    raise exception 'NULL demand type accepted';
  exception when sqlstate '22023' then null;end;
  begin
    perform public.e10_org_lot_reserve_for_demand(o,lot_id,3,'manual','web-order-314','Non-card web order','x4h-reserve');
    raise exception 'changed reservation replay accepted';
  exception when sqlstate '22023' then null;end;
  begin
    perform public.e10_org_lot_reserve_for_demand(o,lot_id,9,'manual','web-order-over','Overcommit','x4h-over');
    raise exception 'generic reservation overcommit accepted';
  exception when check_violation then null;end;
  begin
    perform public.e10_org_lot_reserve_for_demand(foreign_org,lot_id,1,'manual','foreign','Foreign','x4h-foreign');
    raise exception 'foreign generic reservation accepted';
  exception when insufficient_privilege then null;end;
  reset role;

  select count(*) into n from public.e10_break_sessions where organization_id=o;
  if n<>0 then raise exception 'non-card flow fabricated break session';end if;
  if exists(select 1 from public.e10_organization_modules where organization_id=o and module_key='cards') then
    raise exception 'Cards module unexpectedly enabled';end if;
  if not exists(select 1 from public.e10_unique_items where organization_id=o and inventory_item_id='x4h-camera'
    and catalog_variant_id is null and item_kind='camera' and serial_numerator=314159) then
    raise exception 'unique used camera identity missing';end if;
  if (select count(*) from public.e10_unique_items where organization_id=o and inventory_item_id='x4h-camera')<>1
    or (select qty from public.e10_inventory_items where organization_id=o and id='x4h-camera')<>0
    or (select status from public.e10_lot_reservations where organization_id=o and id=camera_reservation_id)<>'consumed'
    or exists(select 1 from public.e10_lot_reservations where organization_id=o and idempotency_key='x4h-null-kind') then
    raise exception 'unique camera one-copy or NULL-kind residue invariant failed';end if;
  if not exists(select 1 from public.e10_lot_reservations where organization_id=o and id=reservation_id
      and source_type='manual' and source_id='web-order-314' and quantity=2 and status='active')
    or not exists(select 1 from public.e10_inventory_movements where organization_id=o and item_id='x4h-apparel'
      and source_entity_type='manual' and source_entity_id='web-order-314' and reserved_delta=2)
    or not exists(select 1 from public.e10_inventory_reservations where organization_id=o and item_id='x4h-apparel'
      and show_ref='web-order-314' and streamer_uid is null and qty=2 and status='active') then
    raise exception 'generic reservation projections incomplete';end if;
  raise notice 'TA-X4h non-card core: PASS (Cards disabled; apparel receipt/cost/reservation; unique used camera; no break session)';
end $$;
rollback;

select 'TA-X4h non-card core PASS' as result;
