\set ON_ERROR_STOP 0
begin;
\i prelude.sql
select set_config('request.jwt.claims','{"sub":"a4000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
set local role authenticated;
-- A1: X4e receipt, quarantine-only 5 against PO line (ordered 10)
select public.e10_org_receive_batch('e1000000-0000-4000-8000-0000000000a6','a4000000-0000-4000-8000-000000000003','a4000000-0000-4000-8000-000000000004','2026-09-12T06:00:00Z',
 jsonb_build_array(jsonb_build_object('line_no',1,'configuration_version_id','a4000000-0000-4000-8000-000000000006','inventory_item_id','rv-item-1',
  'accepted_quantity',0,'damaged_quantity',0,'quarantined_quantity',5,'actual_unit_cost',10,'currency','CAD','purchase_order_line_id','a4000000-0000-4000-8000-000000000008')),'rvA-receive') as r \gset
reset role;
select (:'r'::jsonb#>>'{lines,0,receipt_line_id}') as line_id \gset
select (:'r'::jsonb->>'receipt_id') as receipt_id \gset
select (:'r'::jsonb#>>'{lines,0,lot_id}') as lot_id \gset
set local role authenticated;
select public.e10_org_review_receipt_disposition('e1000000-0000-4000-8000-0000000000a6',:'line_id','accept',3,null,0,'accept three','rvA-accept') as d \gset
reset role;
select 'before X4d reverse' tag, qty from public.e10_inventory_items where id='rv-item-1';
select 'lot before' tag, status,accepted_quantity,quarantined_quantity from public.e10_inventory_lots where id=:'lot_id';
select * from e10.receipt_line_effective_quantities('e1000000-0000-4000-8000-0000000000a6',:'line_id');
set local role authenticated;
select public.e10_org_reverse_receipt('e1000000-0000-4000-8000-0000000000a6',:'receipt_id','wrong shipment','rvA-x4d-reverse');
reset role;
select 'after X4d reverse' tag, qty from public.e10_inventory_items where id='rv-item-1';
select 'lot after' tag, status,accepted_quantity,quarantined_quantity from public.e10_inventory_lots where id=:'lot_id';
select 'receipt after' tag, status from public.e10_stock_receipts where id=:'receipt_id';
select * from e10.receipt_line_effective_quantities('e1000000-0000-4000-8000-0000000000a6',:'line_id');
select 'movements' tag, movement_type,on_hand_delta,source_action from public.e10_inventory_movements where item_id='rv-item-1' order by created_at;
select 'ledger sum' tag, sum(on_hand_delta) from public.e10_inventory_movements where item_id='rv-item-1';
select 'reversal rows' tag, quantity, inventory_movement_id from public.e10_stock_receipt_reversals where stock_receipt_id=:'receipt_id';
select 'events' tag, event_type, corrects_event_id is not null as has_lineage, payload->>'receipt_line_id' from public.e10_commercial_events where subject_id='rv-item-1' order by created_at;
-- can the orphan quantity now be reserved through legacy path?
set local role authenticated;
select public.e10_org_inv_reserve('e1000000-0000-4000-8000-0000000000a6','rv-item-1','rv-show','RV',3,'rvA-legacy-reserve')->>'msg';
reset role;
rollback;
