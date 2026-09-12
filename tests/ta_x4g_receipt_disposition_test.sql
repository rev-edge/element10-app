\set ON_ERROR_STOP on
begin;
do $$
#variable_conflict use_variable
declare
 o uuid:='e1000000-0000-4000-8000-0000000000a6';foreign_org uuid:=gen_random_uuid();actor uuid:=gen_random_uuid();role_id uuid:=gen_random_uuid();
 supplier uuid:=gen_random_uuid();location_id uuid:=gen_random_uuid();product_id uuid:=gen_random_uuid();config_id uuid:=gen_random_uuid();
 po_id uuid:=gen_random_uuid();po_line uuid:=gen_random_uuid();item_id text:='x4g-'||gen_random_uuid();
 receipt jsonb;accept1 jsonb;damage1 jsonb;correct1 jsonb;correct2 jsonb;replay jsonb;reversal jsonb;
 receipt_id uuid;line_id uuid;lot_id uuid;q record;summary jsonb;cost jsonb;n bigint;
begin
 insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at)
 values(actor,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','x4g-'||actor||'@example.invalid',now(),now());
 insert into public.e10_organization_roles(id,organization_id,key,name,is_system)
 values(role_id,o,'x4g-'||substr(role_id::text,1,8),'X4g reviewer',false);
 insert into public.e10_organization_role_permissions(organization_id,role_id,capability,allowed)
 values(o,role_id,'act.create_receiving',true),(o,role_id,'act.resolve_recovery',true),
  (o,role_id,'financial.actual_cost.read',true);
 insert into public.e10_organization_memberships(organization_id,user_id,role_id,status)values(o,actor,role_id,'active');
 insert into public.e10_suppliers(id,organization_id,code,name,status)values(supplier,o,'X4G','X4g supplier','active');
 insert into public.e10_locations(id,organization_id,code,name,status)values(location_id,o,'X4G','X4g location','active');
 insert into public.e10_location_role_permissions(organization_id,location_id,role_id,can_receive)values(o,location_id,role_id,true);
 insert into public.e10_product_masters(id,organization_id,name,status)values(product_id,o,'X4g carton','active');
 insert into public.e10_product_configurations(id,organization_id,product_master_id,name,status)values(config_id,o,product_id,'Carton','active');
 insert into public.e10_product_configuration_versions(id,organization_id,configuration_id,version_no,state,packaging_kind,base_unit,base_units_per_package)
 values(config_id,o,config_id,1,'active','carton','unit',12);
 insert into public.e10_inventory_items(id,name,qty,organization_id)values(item_id,'X4g item',0,o);
 insert into public.e10_purchase_orders(id,organization_id,supplier_id,destination_location_id,status,currency,created_by)
 values(po_id,o,supplier,location_id,'approved','CAD',actor);
 insert into public.e10_purchase_order_lines(id,organization_id,purchase_order_id,configuration_version_id,line_no,ordered_quantity)
 values(po_line,o,po_id,config_id,1,5);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',actor,'role','authenticated')::text,true);
 set local role authenticated;
 receipt:=public.e10_org_receive_batch(o,supplier,location_id,'2026-09-12T06:00:00Z',jsonb_build_array(
  jsonb_build_object('line_no',1,'configuration_version_id',config_id,'inventory_item_id',item_id,
   'accepted_quantity',0,'damaged_quantity',0,'quarantined_quantity',5,'actual_unit_cost',10,'currency','CAD',
   'purchase_order_line_id',po_line,'expected_allocations',jsonb_build_array())),'x4g-receive');
 reset role;
 receipt_id:=(receipt->>'receipt_id')::uuid;line_id:=(receipt#>>'{lines,0,receipt_line_id}')::uuid;lot_id:=(receipt#>>'{lines,0,lot_id}')::uuid;
 cost:=public.e10_org_supplier_actual_cost_history(o,supplier,config_id,'CAD','2026-09-13',50,null);
 if jsonb_array_length(cost->'items')<>0 then raise exception 'all-quarantined cost became eligible';end if;

 set local role authenticated;
 accept1:=public.e10_org_review_receipt_disposition(o,line_id,'accept',2,null,0,'accept two','x4g-accept-1');
 reset role;
 select * into q from e10.receipt_line_effective_quantities(o,line_id);
 summary:=e10.purchase_order_open_commitment_summary(o,po_id);
 cost:=public.e10_org_supplier_actual_cost_history(o,supplier,config_id,'CAD','2026-09-13',50,null);
 if q.effective_accepted<>2 or q.effective_damaged<>0 or q.unresolved_quarantined<>3
  or (select qty from public.e10_inventory_items where organization_id=o and id=item_id)<>2
  or (select accepted_quantity from public.e10_inventory_lots where organization_id=o and id=lot_id)<>2
  or (select quarantined_quantity from public.e10_inventory_lots where organization_id=o and id=lot_id)<>3
  or (summary->>'unknown_outstanding_quantity')::numeric<>3 or jsonb_array_length(cost->'items')<>1 then
  raise exception 'accept interpretation diverged q=% summary=% cost=%',to_jsonb(q),summary,cost;end if;

 set local role authenticated;
 damage1:=public.e10_org_review_receipt_disposition(o,line_id,'damage',1,null,0,'damage one','x4g-damage-1');
 correct1:=public.e10_org_review_receipt_disposition(o,line_id,'damage',1,(accept1->>'decision_id')::uuid,1,
  'correct acceptance to damage','x4g-correct-1');
 reset role;
 select * into q from e10.receipt_line_effective_quantities(o,line_id);
 summary:=e10.purchase_order_open_commitment_summary(o,po_id);
 cost:=public.e10_org_supplier_actual_cost_history(o,supplier,config_id,'CAD','2026-09-13',50,null);
 if q.effective_accepted<>0 or q.effective_damaged<>2 or q.unresolved_quarantined<>3
  or (select qty from public.e10_inventory_items where organization_id=o and id=item_id)<>0
  or (summary->>'unknown_outstanding_quantity')::numeric<>5 or jsonb_array_length(cost->'items')<>0 then
  raise exception 'accept-to-damage correction diverged q=% summary=% cost=%',to_jsonb(q),summary,cost;end if;
 set local role authenticated;
 begin
  perform public.e10_org_review_receipt_disposition(o,line_id,'accept',1,(accept1->>'decision_id')::uuid,1,
   'stale correction','x4g-stale');raise exception 'stale predecessor accepted';
 exception when sqlstate '40001' then null;end;
 correct2:=public.e10_org_review_receipt_disposition(o,line_id,'accept',2,(damage1->>'decision_id')::uuid,1,
  'correct damage to accept','x4g-correct-2');
 replay:=public.e10_org_review_receipt_disposition(o,line_id,'accept',2,(damage1->>'decision_id')::uuid,1,
  'correct damage to accept','x4g-correct-2');
 begin
  perform public.e10_org_review_receipt_disposition(o,line_id,'accept',3,(damage1->>'decision_id')::uuid,1,
   'changed replay','x4g-correct-2');raise exception 'changed disposition replay accepted';
 exception when sqlstate '22023' then null;end;
 reset role;
 select * into q from e10.receipt_line_effective_quantities(o,line_id);
 if q.effective_accepted<>2 or q.effective_damaged<>1 or q.unresolved_quarantined<>2
  or not (replay->>'replay')::boolean or replay->>'decision_id'<>correct2->>'decision_id'
  or (select count(*) from public.e10_receipt_disposition_decisions where organization_id=o and stock_receipt_line_id=line_id)<>4
  or (select count(*) from public.e10_commercial_events where organization_id=o and event_type='correction'
   and source_connection_id='receipt-ledger' and payload->>'receipt_line_id'=line_id::text)<>4 then
  raise exception 'revision/replay history invalid q=% replay=%',to_jsonb(q),replay;end if;
 if exists(select 1 from public.e10_receipt_disposition_decisions d
   left join public.e10_commercial_events e on e.organization_id=d.organization_id and e.source_event_id=d.id::text
    and e.source_connection_id='receipt-ledger'
   where d.organization_id=o and d.stock_receipt_line_id=line_id
    and (e.id is null or e.payload->>'decision_id'<>d.id::text or e.payload->>'lot_id'<>lot_id::text
      or e.inventory_movement_id is distinct from d.inventory_movement_id)) then
  raise exception 'decision event correlation invalid';end if;
 if (select allocated_quantity from public.e10_receipt_po_allocations where organization_id=o and receipt_line_id=line_id)<>5 then
  raise exception 'physical source allocation changed during disposition';end if;

 set local role authenticated;
 reversal:=public.e10_org_reverse_receipt_batch(o,receipt_id,'reverse after disposition','x4g-reverse');
 begin
  perform public.e10_org_review_receipt_disposition(o,line_id,'accept',1,null,0,'too late','x4g-after-reverse');
  raise exception 'post-reversal disposition accepted';
 exception when sqlstate '55000' then null;end;
 reset role;
 select * into q from e10.receipt_line_effective_quantities(o,line_id);
 summary:=e10.purchase_order_open_commitment_summary(o,po_id);
 cost:=public.e10_org_supplier_actual_cost_history(o,supplier,config_id,'CAD','2026-09-13',50,null);
 if q.effective_accepted<>0 or q.effective_damaged<>0 or q.unresolved_quarantined<>0 or q.reversed_quantity<>5
  or (select qty from public.e10_inventory_items where organization_id=o and id=item_id)<>0
  or (summary->>'unknown_outstanding_quantity')::numeric<>5 or jsonb_array_length(cost->'items')<>0
  or (select allocated_quantity from public.e10_receipt_po_allocations where organization_id=o and receipt_line_id=line_id)<>5
  or (select count(*) from public.e10_stock_receipt_reversals where organization_id=o and stock_receipt_id=receipt_id)<>1 then
  raise exception 'reversal after disposition diverged q=% summary=% cost=%',to_jsonb(q),summary,cost;end if;

 insert into public.e10_organizations(id,slug,name)values(foreign_org,'x4g-'||substr(foreign_org::text,1,8),'Foreign X4g');
 set local role authenticated;
 begin
  perform public.e10_org_review_receipt_disposition(foreign_org,line_id,'accept',1,null,0,'foreign','x4g-foreign');
  raise exception 'foreign p_org disposition accepted';
 exception when insufficient_privilege then null;end;
 reset role;
 if exists(select 1 from public.e10_receipt_disposition_commands where organization_id=foreign_org)then
  raise exception 'foreign disposition left residue';end if;
 raise notice 'TA-X4g reviewed receipt disposition: PASS';
end $$;
rollback;

set role anon;
do $$ begin
 if has_function_privilege('anon','public.e10_org_review_receipt_disposition(uuid,uuid,text,numeric,uuid,integer,text,text)','execute')
  or has_function_privilege('public','public.e10_org_review_receipt_disposition(uuid,uuid,text,numeric,uuid,integer,text,text)','execute')
  or has_table_privilege('authenticated','public.e10_receipt_disposition_decisions','select')
  or has_table_privilege('authenticated','public.e10_receipt_disposition_commands','select') then
  raise exception 'X4g API or tables exposed';end if;
 raise notice 'TA-X4g fail-closed ACL: PASS';
end $$;
reset role;
