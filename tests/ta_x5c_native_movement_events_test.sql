\set ON_ERROR_STOP on
begin;
do $$
declare o uuid:='e1000000-0000-4000-8000-0000000000a6'; u uuid:=gen_random_uuid(); rid uuid:=gen_random_uuid();
  r jsonb; c bigint; linked bigint;
begin
  insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at)
    values(u,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','x5c@x.invalid',now(),now());
  insert into public.e10_organization_roles(id,organization_id,key,name,is_system) values(rid,o,'x5c','X5c',false);
  insert into public.e10_organization_role_permissions(organization_id,role_id,capability,allowed)
    values(o,rid,'act.inventory_edit',true);
  insert into public.e10_organization_memberships(organization_id,user_id,role_id,status) values(o,u,rid,'active');
  insert into public.e10_inventory_items(id,name,qty,organization_id) values('x5c-item','X5c Item',5,o);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated')::text,true);
  r:=public.e10_org_inv_reserve(o,'x5c-item','show-1','Show 1',2,'x5c-reserve-1');
  if not (r->>'ok')::boolean then raise exception 'native reserve failed: %',r; end if;
  begin
    perform public.e10_org_inv_reserve(o,'x5c-item','show-rollback','Rollback',1,'x5c-reserve-rollback');
    raise exception 'force action rollback';
  exception when raise_exception then null; end;
  select count(*) into c from public.e10_inventory_movements where organization_id=o and idempotency_key='x5c-reserve-rollback';
  if c<>0 then raise exception 'rolled-back action retained movement'; end if;
  select count(*) into c from public.e10_commercial_events where organization_id=o and subject_id='x5c-item';
  if c<>1 then raise exception 'rolled-back action retained event; count=%',c; end if;
  r:=public.e10_org_inv_release(o,'x5c-item','show-1','x5c-release-1');
  if not (r->>'ok')::boolean then raise exception 'native release failed: %',r; end if;
  perform public.e10_org_emit_inventory_movement(o,'x5c-item','correction',1,0,'x5c-unclassified','test','unclassified',
    'test','x','other',null,'{}');
  select count(*),count(inventory_movement_id) into c,linked from public.e10_commercial_events
    where organization_id=o and subject_type='inventory_item' and subject_id='x5c-item';
  if c<>2 or linked<>2 then raise exception 'native event linkage wrong events=% linked=%',c,linked; end if;
  if (select count(*) from public.e10_commercial_events where organization_id=o and subject_id='x5c-item' and event_type='hold')<>1
     or (select count(*) from public.e10_commercial_events where organization_id=o and subject_id='x5c-item' and event_type='release')<>1 then
    raise exception 'native event types wrong';
  end if;
  if exists(select 1 from public.e10_commercial_events where organization_id=o and subject_id='x5c-item'
    and (evidence_quality<>'native_system' or source_connection_id<>'inventory-ledger' or source_event_id is null or correlation_id is null)) then
    raise exception 'native event envelope incomplete';
  end if;
  raise notice 'TA-X5c native action linkage: PASS (reserve/release atomic events, rollback atomicity, unknown correction not guessed)';
end $$;
rollback;

begin;
alter table public.e10_commercial_events disable trigger e10_commercial_events_append_only_trg;
do $$
declare
  o uuid:='e1000000-0000-4000-8000-0000000000a6'; u uuid:=gen_random_uuid(); role_id uuid:=gen_random_uuid();
  supplier uuid:=gen_random_uuid(); location uuid:=gen_random_uuid(); product uuid:=gen_random_uuid(); config uuid:=gen_random_uuid();
  po uuid:=gen_random_uuid(); pol uuid:=gen_random_uuid(); receipt uuid; original_movement uuid; reversal jsonb;
  backdated constant timestamptz:='2024-02-03T04:05:06Z'; event_time timestamptz; ingested_at timestamptz;
  original_event uuid; correction_event uuid; linked_original_event uuid; retroactive boolean; c bigint;
begin
  insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at)
    values(u,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','x5c1@x.invalid',now(),now());
  insert into public.e10_organization_roles(id,organization_id,key,name,is_system) values(role_id,o,'x5c1','X5c1',false);
  insert into public.e10_organization_role_permissions(organization_id,role_id,capability,allowed)
    values(o,role_id,'act.create_receiving',true),(o,role_id,'act.resolve_recovery',true);
  insert into public.e10_organization_memberships(organization_id,user_id,role_id,status) values(o,u,role_id,'active');
  insert into public.e10_suppliers(id,organization_id,name) values(supplier,o,'X5c1 Supplier');
  insert into public.e10_locations(id,organization_id,name) values(location,o,'X5c1 Location');
  insert into public.e10_location_role_permissions(organization_id,location_id,role_id,can_receive) values(o,location,role_id,true);
  insert into public.e10_product_masters(id,organization_id,name) values(product,o,'X5c1 Product');
  insert into public.e10_product_configurations(id,organization_id,product_master_id,name) values(config,o,product,'Each');
  insert into public.e10_product_configuration_versions(id,organization_id,configuration_id,version_no,state,packaging_kind,base_unit,base_units_per_package)
    values(config,o,config,1,'active','each','each',1);
  insert into public.e10_inventory_items(id,name,qty,organization_id) values('x5c1-item','X5c1 Item',0,o);
  insert into public.e10_purchase_orders(id,organization_id,supplier_id,destination_location_id,status,currency,created_by)
    values(po,o,supplier,location,'approved','CAD',u);
  insert into public.e10_purchase_order_lines(id,organization_id,purchase_order_id,configuration_version_id,line_no,ordered_quantity)
    values(pol,o,po,config,1,2);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated')::text,true);

  -- A post-X5c backdated receipt preserves received_at as occurrence and created_at as ingestion.
  reversal:=public.e10_org_receive_po_line(o,pol,'x5c1-item',1,0,0,'post-x5c',backdated,'[]','x5c1-backdated');
  select ce.occurred_at,ce.created_at into event_time,ingested_at
    from public.e10_commercial_events ce where ce.organization_id=o
      and ce.inventory_movement_id=(reversal->>'movement_id')::uuid;
  if event_time<>backdated or ingested_at<=event_time then
    raise exception 'source/ingestion time separation failed occurred=% created=%',event_time,ingested_at;
  end if;

  -- Build a genuinely pre-R1 originless receipt by removing its origin under
  -- replica mode, then prove compatibility reversal repairs it append-only.
  alter table public.e10_inventory_movements disable trigger e10_capture_native_inventory_event_trg;
  reversal:=public.e10_org_receive_po_line(o,pol,'x5c1-item',1,0,0,'pre-x5c',backdated-'1 day'::interval,'[]','x5c1-legacy');
  alter table public.e10_inventory_movements enable trigger e10_capture_native_inventory_event_trg;
  receipt:=(reversal->>'receipt_id')::uuid;
  original_movement:=(reversal->>'movement_id')::uuid;
  delete from public.e10_commercial_events where organization_id=o and inventory_movement_id=original_movement;
  if exists(select 1 from public.e10_commercial_events where organization_id=o and inventory_movement_id=original_movement) then
    raise exception 'historical originless fixture construction failed';end if;
  reversal:=public.e10_org_reverse_receipt(o,receipt,'legacy receipt correction','x5c1-legacy-reverse');
  select id,occurred_at,(payload->>'captured_retroactively')::boolean into original_event,event_time,retroactive
    from public.e10_commercial_events where organization_id=o and inventory_movement_id=original_movement;
  select id,corrects_event_id into correction_event,linked_original_event
    from public.e10_commercial_events where organization_id=o and inventory_movement_id=(reversal->>'movement_id')::uuid;
  if original_event is null or correction_event is null or linked_original_event<>original_event
     or not coalesce(retroactive,false) or event_time<>backdated-'1 day'::interval then
    raise exception 'receipt reversal lineage incomplete original=% linked_original=% correction=% retro=% occurred=%',
      original_event,linked_original_event,correction_event,retroactive,event_time;
  end if;
  select count(*) into c from public.e10_commercial_events where organization_id=o
    and inventory_movement_id in (original_movement,(reversal->>'movement_id')::uuid);
  if c<>2 then raise exception 'legacy receipt reversal must produce exactly two linked events, got %',c; end if;
  if exists(select 1 from public.e10_commercial_events where organization_id=o
    and inventory_movement_id in (original_movement,(reversal->>'movement_id')::uuid)
    and (evidence_quality<>'native_system' or source_connection_id not in('receipt-ledger','inventory-ledger') or source_event_id is null)) then
    raise exception 'receipt/native envelope incomplete';
  end if;
  raise notice 'TA-X5c.1 source time + receipt-origin/reversal linkage: PASS';
end $$;
rollback;
