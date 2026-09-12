\set ON_ERROR_STOP on
begin;
do $$
#variable_conflict use_variable
declare
  o uuid:='e1000000-0000-4000-8000-0000000000a6';
  foreign_org uuid:=gen_random_uuid(); actor uuid:=gen_random_uuid(); role_id uuid:=gen_random_uuid();
  supplier uuid:=gen_random_uuid(); location_id uuid:=gen_random_uuid(); product_id uuid:=gen_random_uuid();
  config_id uuid:=gen_random_uuid(); po_id uuid:=gen_random_uuid(); po_line_id uuid:=gen_random_uuid();
  invoice_id uuid:=gen_random_uuid(); invoice_line_id uuid:=gen_random_uuid(); result jsonb; replay jsonb;
  receipt_id uuid; direct_receipt uuid; line_ids uuid[]; n bigint; quantity numeric; invoice_status text; effective record;
begin
  insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at)
  values(actor,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',
    'x4e-'||actor||'@example.invalid',now(),now());
  insert into public.e10_organization_roles(id,organization_id,key,name,is_system)
  values(role_id,o,'x4e-'||substr(role_id::text,1,8),'X4e receiver',false);
  insert into public.e10_organization_role_permissions(organization_id,role_id,capability,allowed)
  values(o,role_id,'act.create_receiving',true);
  insert into public.e10_organization_memberships(organization_id,user_id,role_id,status)
  values(o,actor,role_id,'active');
  insert into public.e10_suppliers(id,organization_id,code,name,status)
  values(supplier,o,'X4E-'||substr(supplier::text,1,6),'X4e supplier','active');
  insert into public.e10_locations(id,organization_id,code,name,status)
  values(location_id,o,'X4E','X4e receiving','active');
  insert into public.e10_location_role_permissions(organization_id,location_id,role_id,can_receive)
  values(o,location_id,role_id,true);
  insert into public.e10_product_masters(id,organization_id,name,status)
  values(product_id,o,'X4e non-card carton','active');
  insert into public.e10_product_configurations(id,organization_id,product_master_id,name,status)
  values(config_id,o,product_id,'Carton','active');
  insert into public.e10_product_configuration_versions(id,organization_id,configuration_id,version_no,state,
    packaging_kind,base_unit,base_units_per_package)
  values(config_id,o,config_id,1,'active','carton','unit',12);
  insert into public.e10_inventory_items(id,name,qty,organization_id)
  values('x4e-item-a','X4e A',0,o),('x4e-item-b','X4e B',0,o),('x4e-item-c','X4e C',0,o);
  insert into public.e10_purchase_orders(id,organization_id,supplier_id,destination_location_id,status,currency,created_by)
  values(po_id,o,supplier,location_id,'approved','CAD',actor);
  insert into public.e10_purchase_order_lines(id,organization_id,purchase_order_id,configuration_version_id,line_no,ordered_quantity)
  values(po_line_id,o,po_id,config_id,1,20);
  insert into public.e10_supplier_invoices(id,organization_id,supplier_id,supplier_document_number,status,currency,created_by)
  values(invoice_id,o,supplier,'X4E-INVOICE','draft','CAD',actor);
  insert into public.e10_supplier_invoice_lines(id,organization_id,supplier_invoice_id,configuration_version_id,
    line_no,invoiced_quantity,line_amount,state)
  values(invoice_line_id,o,invoice_id,config_id,1,12,120,'active');

  perform set_config('request.jwt.claims',jsonb_build_object('sub',actor,'role','authenticated')::text,true);
  set local role authenticated;
  result:=public.e10_org_receive_batch(o,supplier,location_id,'2026-09-12T00:00:00Z',jsonb_build_array(
    jsonb_build_object('line_no',1,'configuration_version_id',config_id,'inventory_item_id','x4e-item-a',
      'accepted_quantity',4,'damaged_quantity',1,'quarantined_quantity',1,'lot_code','X4E-A',
      'actual_unit_cost',10,'currency','CAD','purchase_order_line_id',po_line_id,
      'invoice_line_id',invoice_line_id,'expected_allocations',jsonb_build_array()),
    jsonb_build_object('line_no',2,'configuration_version_id',config_id,'inventory_item_id','x4e-item-b',
      'accepted_quantity',0,'damaged_quantity',1,'quarantined_quantity',2,'lot_code','X4E-B',
      'expected_allocations',jsonb_build_array())
  ),'x4e-batch-1');
  reset role;
  if not (result->>'ok')::boolean or (result->>'replay')::boolean
    or jsonb_array_length(result->'lines')<>2 then raise exception 'batch result invalid: %',result; end if;
  receipt_id:=(result->>'receipt_id')::uuid;
  select array_agg((x->>'receipt_line_id')::uuid order by (x->>'line_no')::integer)
    into line_ids from jsonb_array_elements(result->'lines') x;
  select count(*),sum(received_quantity) into n,quantity from public.e10_stock_receipt_lines
    where organization_id=o and stock_receipt_id=receipt_id;
  if n<>2 or quantity<>9 then raise exception 'physical batch conservation failed rows=% qty=%',n,quantity; end if;
  select allocated_quantity into quantity from public.e10_receipt_po_allocations
    where organization_id=o and receipt_line_id=line_ids[1] and purchase_order_line_id=po_line_id;
  if quantity<>6 then raise exception 'PO physical allocation wrong: %',quantity; end if;
  select allocated_quantity into quantity from public.e10_receipt_invoice_allocations
    where organization_id=o and receipt_line_id=line_ids[1] and invoice_line_id=invoice_line_id;
  if quantity<>6 then raise exception 'invoice physical allocation wrong: %',quantity; end if;
  select * into effective from e10.receipt_line_effective_quantities(o,line_ids[1]);
  if effective.physical_received<>6 or effective.effective_accepted<>4 or effective.effective_damaged<>1
    or effective.unresolved_quarantined<>1 or effective.reversed_quantity<>0 then
    raise exception 'effective quantities wrong: %',to_jsonb(effective); end if;
  select count(*) into n from public.e10_commercial_events
    where organization_id=o and event_type='receipt'
      and (payload->>'receipt_line_id')::uuid=any(line_ids);
  if n<>2 then raise exception 'one receipt event per line not preserved: %',n; end if;
  if exists(select 1 from public.e10_commercial_events where organization_id=o and event_type='receipt'
      and (payload->>'receipt_line_id')::uuid=any(line_ids)
      and (payload->>'receipt_id')::uuid<>receipt_id) then raise exception 'receipt event correlation wrong'; end if;

  set local role authenticated;
  replay:=public.e10_org_receive_batch(o,supplier,location_id,'2026-09-12T00:00:00Z',jsonb_build_array(
    jsonb_build_object('line_no',1,'configuration_version_id',config_id,'inventory_item_id','x4e-item-a',
      'accepted_quantity',4,'damaged_quantity',1,'quarantined_quantity',1,'lot_code','X4E-A',
      'actual_unit_cost',10,'currency','CAD','purchase_order_line_id',po_line_id,
      'invoice_line_id',invoice_line_id,'expected_allocations',jsonb_build_array()),
    jsonb_build_object('line_no',2,'configuration_version_id',config_id,'inventory_item_id','x4e-item-b',
      'accepted_quantity',0,'damaged_quantity',1,'quarantined_quantity',2,'lot_code','X4E-B',
      'expected_allocations',jsonb_build_array())
  ),'x4e-batch-1');
  reset role;
  if not (replay->>'replay')::boolean or replay->>'receipt_id'<>receipt_id::text
    or replay->'lines'<>result->'lines' then raise exception 'stable replay failed: %',replay; end if;
  select count(*) into n from public.e10_stock_receipt_lines where organization_id=o and stock_receipt_id=receipt_id;
  if n<>2 then raise exception 'replay duplicated receipt lines'; end if;

  set local role authenticated;
  begin
    perform public.e10_org_receive_batch(o,supplier,location_id,'2026-09-12T00:00:00Z','[]','x4e-batch-1');
    raise exception 'changed replay accepted';
  exception when sqlstate '22023' then null; end;
  begin
    perform public.e10_org_receive_batch(o,supplier,location_id,now(),jsonb_build_array(
      jsonb_build_object('line_no',1,'configuration_version_id',config_id,'inventory_item_id','x4e-item-c',
        'accepted_quantity',1,'damaged_quantity',0,'quarantined_quantity',0,'expected_allocations',jsonb_build_array()),
      jsonb_build_object('line_no',2,'configuration_version_id',config_id,'inventory_item_id','missing-item',
        'accepted_quantity',1,'damaged_quantity',0,'quarantined_quantity',0,'expected_allocations',jsonb_build_array())
    ),'x4e-atomic-fail');
    raise exception 'invalid batch line accepted';
  exception when insufficient_privilege then null; end;
  reset role;
  if exists(select 1 from public.e10_receipt_commands where organization_id=o and idempotency_key='x4e-atomic-fail')
    or exists(select 1 from public.e10_stock_receipts where organization_id=o and idempotency_key='x4e-atomic-fail')
    then raise exception 'invalid batch left residue'; end if;

  set local role authenticated;
  result:=public.e10_org_receive_batch(o,supplier,location_id,'2026-09-12T01:00:00Z',jsonb_build_array(
    jsonb_build_object('line_no',1,'configuration_version_id',config_id,'inventory_item_id','x4e-item-c',
      'accepted_quantity',2,'damaged_quantity',0,'quarantined_quantity',0,'actual_unit_cost',11,'currency','CAD',
      'invoice_line_id',invoice_line_id,'expected_allocations',jsonb_build_array())
  ),'x4e-invoice-only');
  reset role;
  direct_receipt:=(result->>'receipt_id')::uuid;
  if exists(select 1 from public.e10_receipt_po_allocations a join public.e10_stock_receipt_lines l
      on l.organization_id=a.organization_id and l.id=a.receipt_line_id
      where l.organization_id=o and l.stock_receipt_id=direct_receipt) then
    raise exception 'invoice-only receipt fabricated PO allocation';
  end if;
  select status into invoice_status from public.e10_supplier_invoices where organization_id=o and id=invoice_id;
  if invoice_status<>'draft' then raise exception 'physical receipt changed invoice status: %',invoice_status; end if;

  insert into public.e10_organizations(id,slug,name) values(foreign_org,'x4e-'||substr(foreign_org::text,1,8),'Foreign X4e');
  set local role authenticated;
  begin
    perform public.e10_org_receive_batch(foreign_org,supplier,location_id,now(),jsonb_build_array(
      jsonb_build_object('line_no',1,'configuration_version_id',config_id,'inventory_item_id','x4e-item-a',
        'accepted_quantity',1,'damaged_quantity',0,'quarantined_quantity',0,'expected_allocations',jsonb_build_array())
    ),'x4e-foreign');
    raise exception 'foreign organization accepted';
  exception when insufficient_privilege then null; end;
  reset role;
  if exists(select 1 from public.e10_lot_cost_evidence where organization_id=o and lot_id in(
      select inventory_lot_id from public.e10_stock_receipt_lines where organization_id=o and stock_receipt_id in(receipt_id,direct_receipt)))
    then raise exception 'receipt invented landed-cost evidence'; end if;
  raise notice 'TA-X4e source-neutral receipt batch: PASS';
end $$;
rollback;

set role anon;
do $$ begin
  if has_function_privilege('anon','public.e10_org_receive_batch(uuid,uuid,uuid,timestamptz,jsonb,text)','execute')
    or has_function_privilege('public','public.e10_org_receive_batch(uuid,uuid,uuid,timestamptz,jsonb,text)','execute') then
    raise exception 'X4e API exposed';
  end if;
  raise notice 'TA-X4e fail-closed ACL: PASS';
end $$;
reset role;
