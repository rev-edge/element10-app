\set ON_ERROR_STOP on
begin;
do $$
#variable_conflict use_variable
declare
  o uuid:='e1000000-0000-4000-8000-0000000000a6';foreign_org uuid:=gen_random_uuid();
  actor uuid:=gen_random_uuid();role_id uuid:=gen_random_uuid();supplier uuid:=gen_random_uuid();location_id uuid:=gen_random_uuid();
  product_id uuid:=gen_random_uuid();config_id uuid:=gen_random_uuid();po_id uuid:=gen_random_uuid();
  po_line_1 uuid:=gen_random_uuid();po_line_2 uuid:=gen_random_uuid();expected_id uuid:=gen_random_uuid();
  item_a text:='x4f-a-'||gen_random_uuid();item_b text:='x4f-b-'||gen_random_uuid();
  result jsonb;replay jsonb;receipt_id uuid;line_ids uuid[];lot_ids uuid[];movement_ids uuid[];
  n bigint;quantity numeric;effective record;
begin
  insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at)
  values(actor,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',
    'x4f-'||actor||'@example.invalid',now(),now());
  insert into public.e10_organization_roles(id,organization_id,key,name,is_system)
  values(role_id,o,'x4f-'||substr(role_id::text,1,8),'X4f recovery',false);
  insert into public.e10_organization_role_permissions(organization_id,role_id,capability,allowed)
  values(o,role_id,'act.create_receiving',true),(o,role_id,'act.resolve_recovery',true);
  insert into public.e10_organization_memberships(organization_id,user_id,role_id,status)
  values(o,actor,role_id,'active');
  insert into public.e10_suppliers(id,organization_id,code,name,status)
  values(supplier,o,'X4F-'||substr(supplier::text,1,6),'X4f supplier','active');
  insert into public.e10_locations(id,organization_id,code,name,status)
  values(location_id,o,'X4F-'||substr(location_id::text,1,6),'X4f receiving','active');
  insert into public.e10_location_role_permissions(organization_id,location_id,role_id,can_receive)
  values(o,location_id,role_id,true);
  insert into public.e10_product_masters(id,organization_id,name,status)
  values(product_id,o,'X4f non-card carton','active');
  insert into public.e10_product_configurations(id,organization_id,product_master_id,name,status)
  values(config_id,o,product_id,'Carton','active');
  insert into public.e10_product_configuration_versions(id,organization_id,configuration_id,version_no,state,
    packaging_kind,base_unit,base_units_per_package)
  values(config_id,o,config_id,1,'active','carton','unit',12);
  insert into public.e10_inventory_items(id,name,qty,organization_id)
  values(item_a,'X4f A',0,o),(item_b,'X4f B',0,o);
  insert into public.e10_purchase_orders(id,organization_id,supplier_id,destination_location_id,status,currency,created_by)
  values(po_id,o,supplier,location_id,'approved','CAD',actor);
  insert into public.e10_purchase_order_lines(id,organization_id,purchase_order_id,configuration_version_id,line_no,ordered_quantity)
  values(po_line_1,o,po_id,config_id,1,10),(po_line_2,o,po_id,config_id,2,10);
  insert into public.e10_expected_inventory_allocations(id,organization_id,purchase_order_line_id,destination_location_id,
    expected_quantity,status,planning_reference)
  values(expected_id,o,po_line_1,location_id,3,'open','x4f-plan');

  perform set_config('request.jwt.claims',jsonb_build_object('sub',actor,'role','authenticated')::text,true);
  set local role authenticated;
  result:=public.e10_org_receive_batch(o,supplier,location_id,'2026-09-12T03:00:00Z',jsonb_build_array(
    jsonb_build_object('line_no',1,'configuration_version_id',config_id,'inventory_item_id',item_a,
      'accepted_quantity',3,'damaged_quantity',1,'quarantined_quantity',1,'purchase_order_line_id',po_line_1,
      'expected_allocations',jsonb_build_array(jsonb_build_object('id',expected_id,'quantity',2))),
    jsonb_build_object('line_no',2,'configuration_version_id',config_id,'inventory_item_id',item_b,
      'accepted_quantity',0,'damaged_quantity',1,'quarantined_quantity',2,'purchase_order_line_id',po_line_2,
      'expected_allocations',jsonb_build_array())
  ),'x4f-receive');
  receipt_id:=(result->>'receipt_id')::uuid;
  select array_agg((x->>'receipt_line_id')::uuid order by (x->>'line_no')::integer),
    array_agg((x->>'lot_id')::uuid order by (x->>'line_no')::integer)
  into line_ids,lot_ids from jsonb_array_elements(result->'lines') x;
  result:=public.e10_org_reverse_receipt_batch(o,receipt_id,'full receipt correction','x4f-reverse');
  reset role;

  if not (result->>'ok')::boolean or (result->>'replay')::boolean or result->>'status'<>'reversed'
    or jsonb_array_length(result->'lines')<>2 then raise exception 'batch reversal result invalid: %',result;end if;
  select array_agg((x->>'movement_id')::uuid order by (x->>'line_no')::integer)
    into movement_ids from jsonb_array_elements(result->'lines') x where x->>'movement_id' is not null;
  if coalesce(array_length(movement_ids,1),0)<>1 then raise exception 'expected one correction movement: %',movement_ids;end if;
  select count(*) into n from public.e10_stock_receipt_reversals
    where organization_id=o and stock_receipt_id=receipt_id;
  if n<>2 then raise exception 'expected one reversal per line: %',n;end if;
  if (select status from public.e10_stock_receipts where organization_id=o and id=receipt_id)<>'reversed'
    or exists(select 1 from public.e10_inventory_lots where organization_id=o and id=any(lot_ids) and status<>'reversed')
    or (select qty from public.e10_inventory_items where organization_id=o and id=item_a)<>0
    or (select qty from public.e10_inventory_items where organization_id=o and id=item_b)<>0 then
    raise exception 'receipt, lot, or item reversal state invalid';end if;
  select fulfilled_quantity into quantity from public.e10_expected_inventory_allocations
    where organization_id=o and id=expected_id;
  if quantity<>0 or (select status from public.e10_expected_inventory_allocations where organization_id=o and id=expected_id)<>'open'
    or (select count(*) from public.e10_expected_allocation_events where organization_id=o
      and expected_allocation_id=expected_id and action='reverse')<>1 then
    raise exception 'expected allocation was not reversed exactly once';end if;
  if (select count(*) from public.e10_receipt_po_allocations a where a.organization_id=o
      and a.receipt_line_id=any(line_ids))<>2 then raise exception 'source allocation evidence changed';end if;
  foreach receipt_id in array line_ids loop
    select * into effective from e10.receipt_line_effective_quantities(o,receipt_id);
    if effective.effective_accepted<>0 or effective.effective_damaged<>0 or effective.unresolved_quarantined<>0
      or effective.reversed_quantity<>effective.physical_received then
      raise exception 'effective reversal interpretation invalid line=% quantities=%',receipt_id,to_jsonb(effective);end if;
  end loop;
  if (select count(*) from public.e10_commercial_events e where e.organization_id=o and e.event_type='correction'
      and (e.payload->>'receipt_line_id')::uuid=any(line_ids))<>2
    or exists(select 1 from public.e10_commercial_events e where e.organization_id=o and e.event_type='correction'
      and (e.payload->>'receipt_line_id')::uuid=any(line_ids)
      and ((e.payload->>'receipt_id')::uuid<> (result->>'receipt_id')::uuid
        or (e.payload->>'lot_id')::uuid<>all(lot_ids) and (e.payload->>'lot_id')::uuid is null)) then
    raise exception 'line-level correction evidence incomplete';end if;
  if not exists(select 1 from public.e10_commercial_events e where e.organization_id=o and e.event_type='correction'
      and (e.payload->>'receipt_line_id')::uuid=line_ids[2] and e.inventory_movement_id is null
      and e.source_kind='native' and e.evidence_quality='native_system') then
    raise exception 'zero-accepted line correction evidence missing';end if;

  set local role authenticated;
  replay:=public.e10_org_reverse_receipt_batch(o,(result->>'receipt_id')::uuid,'full receipt correction','x4f-reverse');
  begin
    perform public.e10_org_reverse_receipt_batch(o,(result->>'receipt_id')::uuid,'changed reason','x4f-reverse');
    raise exception 'changed reversal replay accepted';
  exception when sqlstate '22023' then null;end;
  reset role;
  if not (replay->>'replay')::boolean or replay->'lines'<>result->'lines'
    or (select count(*) from public.e10_stock_receipt_reversals where organization_id=o
      and stock_receipt_id=(result->>'receipt_id')::uuid)<>2
    or (select count(*) from public.e10_commercial_events where organization_id=o and event_type='correction'
      and (payload->>'receipt_line_id')::uuid=any(line_ids))<>2 then
    raise exception 'replay changed reversal cardinality: %',replay;end if;

  insert into public.e10_organizations(id,slug,name) values(foreign_org,'x4f-'||substr(foreign_org::text,1,8),'Foreign X4f');
  set local role authenticated;
  begin
    perform public.e10_org_reverse_receipt_batch(foreign_org,(result->>'receipt_id')::uuid,'foreign','x4f-foreign');
    raise exception 'foreign reversal accepted';
  exception when insufficient_privilege then null;end;
  reset role;
  if exists(select 1 from public.e10_receipt_reversal_commands where organization_id=foreign_org) then
    raise exception 'foreign reversal left command residue';end if;
  raise notice 'TA-X4f atomic receipt reversal: PASS';
end $$;
rollback;

set role anon;
do $$ begin
  if has_function_privilege('anon','public.e10_org_reverse_receipt_batch(uuid,uuid,text,text)','execute')
    or has_function_privilege('public','public.e10_org_reverse_receipt_batch(uuid,uuid,text,text)','execute')
    or has_table_privilege('authenticated','public.e10_receipt_reversal_commands','select') then
    raise exception 'X4f API or command table exposed';
  end if;
  raise notice 'TA-X4f fail-closed ACL: PASS';
end $$;
reset role;
