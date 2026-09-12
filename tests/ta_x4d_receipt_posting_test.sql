\set ON_ERROR_STOP on
begin;
do $$
declare
  o uuid:='e1000000-0000-4000-8000-0000000000a6'; u uuid:=gen_random_uuid(); v_role uuid:=gen_random_uuid();
  supplier uuid:=gen_random_uuid(); location uuid:=gen_random_uuid(); product uuid:=gen_random_uuid(); config uuid:=gen_random_uuid(); config2 uuid:=gen_random_uuid();
  po uuid:=gen_random_uuid(); pol uuid:=gen_random_uuid(); pol2 uuid:=gen_random_uuid(); pol3 uuid:=gen_random_uuid(); pol4 uuid:=gen_random_uuid(); pol5 uuid:=gen_random_uuid(); expected uuid:=gen_random_uuid(); expected2 uuid:=gen_random_uuid(); r1 jsonb; r2 jsonb; rr jsonb; zero_r jsonb; zero_line uuid;
  receipt2 uuid; lot2 uuid; session uuid:=gen_random_uuid(); lr uuid; c bigint; q numeric; st text;
begin
  insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at)
    values(u,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','x4d@x.invalid',now(),now());
  insert into public.e10_organization_roles(id,organization_id,key,name,is_system) values(v_role,o,'x4d','X4d',false);
  insert into public.e10_organization_role_permissions(organization_id,role_id,capability,allowed)
    values(o,v_role,'act.create_receiving',true),(o,v_role,'act.resolve_recovery',true),
      (o,v_role,'act.reserve_inventory',true),(o,v_role,'act.inventory_edit',true);
  insert into public.e10_organization_memberships(organization_id,user_id,role_id,status) values(o,u,v_role,'active');
  insert into public.e10_suppliers(id,organization_id,name) values(supplier,o,'X4d Supplier');
  insert into public.e10_locations(id,organization_id,name) values(location,o,'X4d Location');
  insert into public.e10_location_role_permissions(organization_id,location_id,role_id,can_receive)
    values(o,location,v_role,true);
  insert into public.e10_product_masters(id,organization_id,name) values(product,o,'X4d Product');
  insert into public.e10_product_configurations(id,organization_id,product_master_id,name) values(config,o,product,'Each');
  insert into public.e10_product_configuration_versions(id,organization_id,configuration_id,version_no,state,packaging_kind,base_unit,base_units_per_package)
    values(config,o,config,1,'active','each','each',1);
  insert into public.e10_product_configurations(id,organization_id,product_master_id,name) values(config2,o,product,'Case');
  insert into public.e10_product_configuration_versions(id,organization_id,configuration_id,version_no,state,packaging_kind,base_unit,base_units_per_package)
    values(config2,o,config2,1,'active','case','each',10);
  insert into public.e10_inventory_items(id,name,qty,organization_id) values
    ('x4d-item','X4d Item',0,o),('x4d-null-alloc','X4d Null Allocation',0,o),('x4d-zero-damage','X4d Zero Damage',0,o),('x4d-zero-accept','X4d Zero Accept',0,o);
  insert into public.e10_purchase_orders(id,organization_id,supplier_id,destination_location_id,status,currency,created_by)
    values(po,o,supplier,location,'approved','CAD',u);
  insert into public.e10_purchase_order_lines(id,organization_id,purchase_order_id,configuration_version_id,line_no,ordered_quantity)
    values(pol,o,po,config,1,10);
  insert into public.e10_purchase_order_lines(id,organization_id,purchase_order_id,configuration_version_id,line_no,ordered_quantity)
    values(pol2,o,po,config2,2,10);
  insert into public.e10_purchase_order_lines(id,organization_id,purchase_order_id,configuration_version_id,line_no,ordered_quantity)
    values(pol3,o,po,config,3,2),(pol4,o,po,config,4,2),(pol5,o,po,config,5,1);
  insert into public.e10_expected_inventory_allocations(id,organization_id,purchase_order_line_id,destination_location_id,expected_quantity,planning_reference)
    values(expected,o,pol,location,5,'x4d-demand-1'),(expected2,o,pol,location,5,'x4d-demand-2');
  insert into public.e10_break_sessions(id,name,streamer_uid,organization_id,source_show_ref)
    values(session,'X4d Session',u,o,'x4d-show');
  perform set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated')::text,true);
  delete from public.e10_location_role_permissions lp where lp.organization_id=o and lp.location_id=location and lp.role_id=v_role;
  begin perform public.e10_org_receive_po_line(o,pol,'x4d-item',1,0,0,null,now(),'[]','x4d-location-denied'); raise exception 'restricted location accepted';
  exception when insufficient_privilege then null; end;
  insert into public.e10_location_role_permissions(organization_id,location_id,role_id,can_receive) values(o,location,v_role,true);
  perform set_config('role','authenticated',true);
  r1:=public.e10_org_receive_po_line(o,pol,'x4d-item',4,1,1,'x4d-lot-1','2026-09-10T20:00:00Z',
    jsonb_build_array(jsonb_build_object('id',expected,'quantity',4)),'x4d-receive-1');
  perform set_config('role','postgres',true);
  if not (r1->>'ok')::boolean or (r1->>'replay')::boolean then raise exception 'first receipt failed: %',r1; end if;
  r1:=public.e10_org_receive_po_line(o,pol,'x4d-item',4,1,1,'x4d-lot-1','2026-09-10T20:00:00Z',
    jsonb_build_array(jsonb_build_object('id',expected,'quantity',4)),'x4d-receive-1');
  if not (r1->>'replay')::boolean then raise exception 'receipt replay missing'; end if;
  begin perform public.e10_org_receive_po_line(o,pol,'x4d-item',5,0,1,'x4d-lot-1','2026-09-10T20:00:00Z','[]','x4d-receive-1'); raise exception 'receipt mismatch accepted';
  exception when sqlstate '22023' then null; end;
  r2:=public.e10_org_receive_po_line(o,pol5,'x4d-null-alloc',1,0,0,'x4d-null-alloc','2026-09-10T20:30:00Z',null,'x4d-null-alloc');
  r2:=public.e10_org_receive_po_line(o,pol5,'x4d-null-alloc',1.00,0.00,0.00,'x4d-null-alloc',null,'[]','x4d-null-alloc');
  if not(r2->>'replay')::boolean then raise exception 'legacy NULL allocation / numeric scale / omitted effective-time replay failed';end if;
  r2:=public.e10_org_receive_po_line(o,pol,'x4d-item',4,0,0,'x4d-lot-2','2026-09-10T21:00:00Z',
    jsonb_build_array(jsonb_build_object('id',expected,'quantity',1),jsonb_build_object('id',expected2,'quantity',3)),'x4d-receive-2');
  receipt2:=(r2->>'receipt_id')::uuid;
  lot2:=(r2->>'lot_id')::uuid;
  select count(*),sum(fulfilled_quantity) into c,q from public.e10_expected_inventory_allocations where id in(expected,expected2) and status='fulfilled';
  if c<>1 or q<>5 then raise exception 'expected allocation conservation wrong fulfilled_rows=% fulfilled_sum=%',c,q; end if;
  select sum(fulfilled_quantity) into q from public.e10_expected_inventory_allocations where id in(expected,expected2);
  if q<>8 then raise exception 'accepted allocation total wrong: %',q; end if;
  select qty into q from public.e10_inventory_items where organization_id=o and id='x4d-item';
  if q<>8 then raise exception 'accepted on-hand wrong: %',q; end if;
  begin perform public.e10_org_receive_po_line(o,pol2,'x4d-item',1,0,0,null,now(),'[]','x4d-config-mismatch'); raise exception 'incompatible item configuration accepted';
  exception when insufficient_privilege then null; end;
  begin perform public.e10_org_receive_po_line(o,pol,'x4d-item',1,0,0,'x4d-over','2026-09-10T22:00:00Z','[]','x4d-over'); raise exception 'over-receipt accepted';
  exception when check_violation then null; end;
  lr:=(public.e10_org_lot_reserve(o,lot2,1,session,'x4d-lot-reserve')->>'reservation_id')::uuid;
  begin perform public.e10_org_reverse_receipt(o,receipt2,'duplicate physical receipt','x4d-reverse-blocked'); raise exception 'reserved receipt reversed';
  exception when sqlstate '55000' then null; end;
  perform public.e10_org_lot_release(o,lr,'x4d-lot-release');
  update public.e10_expected_inventory_allocations set status='cancelled' where id=expected;
  rr:=public.e10_org_reverse_receipt(o,receipt2,'duplicate physical receipt','x4d-reverse-2');
  if not (rr->>'ok')::boolean or (rr->>'replay')::boolean then raise exception 'reversal failed: %',rr; end if;
  rr:=public.e10_org_reverse_receipt(o,receipt2,'duplicate physical receipt','x4d-reverse-2');
  if not (rr->>'replay')::boolean then raise exception 'reversal replay missing'; end if;
  select qty into q from public.e10_inventory_items where organization_id=o and id='x4d-item';
  select sum(fulfilled_quantity) into c from public.e10_expected_inventory_allocations where id in(expected,expected2);
  if q<>4 or c<>4 then raise exception 'reversal reconciliation wrong onhand=% allocated=%',q,c; end if;
  select status into st from public.e10_expected_inventory_allocations where id=expected;
  if st<>'cancelled' then raise exception 'reversal resurrected cancelled allocation: %',st; end if;
  select coalesce(sum(on_hand_delta),0) into q from public.e10_inventory_movements where organization_id=o and item_id='x4d-item';
  if q<>4 then raise exception 'receipt movement ledger wrong: %',q; end if;
  select count(*) into c from public.e10_commercial_events correction
    join public.e10_commercial_events original on original.organization_id=correction.organization_id and original.id=correction.corrects_event_id
    where correction.organization_id=o and correction.event_type='correction' and original.event_type='receipt'
      and correction.subject_id='x4d-item' and original.subject_id='x4d-item';
  if c<>1 then raise exception 'receipt reversal event lineage wrong: %',c; end if;
  select count(*) into c from public.e10_lot_cost_evidence where organization_id=o and lot_id in
    (select inventory_lot_id from public.e10_stock_receipt_lines where organization_id=o and stock_receipt_id in ((r1->>'receipt_id')::uuid,receipt2));
  if c<>0 then raise exception 'receipt invented landed-cost allocation'; end if;
  insert into public.e10_stock_receipt_lines(organization_id,stock_receipt_id,configuration_version_id,line_no,received_quantity,accepted_quantity,damaged_quantity,quarantined_quantity)
    values(o,(r1->>'receipt_id')::uuid,config,2,1,0,1,0);
  begin perform public.e10_org_reverse_receipt(o,(r1->>'receipt_id')::uuid,'multi line','x4d-multi'); raise exception 'multi-line partial reversal accepted';
  exception when sqlstate '55000' then null; end;
  begin perform public.e10_org_receive_po_line('e4000000-0000-4000-8000-00000000e4ff',pol,'x4d-item',1,0,0,null,now(),'[]','x4d-cross'); raise exception 'cross-org receipt accepted';
  exception when insufficient_privilege then null; end;

  -- IMPL-13: an actual X4d PO-line receipt with zero accepted quantity still
  -- gets one origin fact. Damage disposition and batch reversal preserve it.
  zero_r:=public.e10_org_receive_po_line(o,pol3,'x4d-zero-damage',0,0,2,'zero-damage',now(),'[]','x4d-zero-damage');
  zero_line:=(zero_r->>'receipt_line_id')::uuid;
  perform public.e10_org_review_receipt_disposition(o,zero_line,'damage',1,null,0,'damage observed','x4d-zero-damage-disposition');
  rr:=public.e10_org_reverse_receipt_batch(o,(zero_r->>'receipt_id')::uuid,'reverse damaged quarantine','x4d-zero-damage-reverse');
  if not (rr->>'ok')::boolean or (rr->>'replay')::boolean then raise exception 'zero-damage reversal failed: %',rr;end if;
  rr:=public.e10_org_reverse_receipt_batch(o,(zero_r->>'receipt_id')::uuid,'reverse damaged quarantine','x4d-zero-damage-reverse');
  if not (rr->>'replay')::boolean then raise exception 'zero-damage reversal replay missing';end if;
  select count(*) into c from public.e10_commercial_events where organization_id=o and event_type='receipt'
    and payload->>'receipt_line_id'=zero_line::text and coalesce((payload->>'captured_retroactively')::boolean,false)=false;
  if c<>1 then raise exception 'new zero-accepted receipt origin count/provenance wrong: %',c;end if;

  -- Accepting quarantined quantity then using the legacy single name removes
  -- exactly effective accepted stock through the batch implementation.
  zero_r:=public.e10_org_receive_po_line(o,pol4,'x4d-zero-accept',0,0,2,'zero-accept',now(),'[]','x4d-zero-accept');
  zero_line:=(zero_r->>'receipt_line_id')::uuid;
  perform public.e10_org_review_receipt_disposition(o,zero_line,'accept',2,null,0,'accept observed','x4d-zero-accept-disposition');
  rr:=public.e10_org_reverse_receipt(o,(zero_r->>'receipt_id')::uuid,'legacy compatibility reversal','x4d-zero-accept-reverse');
  if not (rr->>'ok')::boolean or (rr->>'replay')::boolean then raise exception 'zero-accept single reversal failed: %',rr;end if;
  rr:=public.e10_org_reverse_receipt(o,(zero_r->>'receipt_id')::uuid,'legacy compatibility reversal','x4d-zero-accept-reverse');
  if not (rr->>'replay')::boolean then raise exception 'zero-accept single reversal replay missing';end if;
  select qty into q from public.e10_inventory_items where organization_id=o and id='x4d-zero-accept';
  if q<>0 then raise exception 'zero-accept reversal left phantom stock: %',q;end if;
  select count(*) into c from public.e10_receipt_po_allocations where organization_id=o
    and purchase_order_line_id in(pol3,pol4) and allocated_quantity=2;
  if c<>2 then raise exception 'zero-accepted PO allocation conservation wrong: %',c;end if;
  raise notice 'TA-X4d receipt posting: PASS (partial, accepted/quarantine split, strict over-receipt, reversal, expected-supply reconciliation)';
end $$;
rollback;

set role anon;
do $$ begin
  if has_function_privilege('anon','public.e10_org_receive_po_line(uuid,uuid,text,numeric,numeric,numeric,text,timestamptz,jsonb,text)','execute')
     or has_function_privilege('anon','public.e10_org_reverse_receipt(uuid,uuid,text,text)','execute') then raise exception 'X4d function exposed to anon'; end if;
  raise notice 'TA-X4d fail-closed ACL: PASS';
end $$;
reset role;
