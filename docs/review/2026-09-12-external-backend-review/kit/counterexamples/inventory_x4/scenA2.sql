\set ON_ERROR_STOP 0
begin;
\i prelude.sql
select set_config('request.jwt.claims','{"sub":"a4000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
set local role authenticated;
-- A2: X4d receipt accepted 3 + quarantined 2, then X4g accept 2, then X4d reverse
select public.e10_org_receive_po_line('e1000000-0000-4000-8000-0000000000a6','a4000000-0000-4000-8000-000000000008','rv-item-1',3,0,2,'rvA2-lot','2026-09-12T06:00:00Z','[]','rvA2-receive') as r \gset
reset role;
select (:'r'::jsonb->>'receipt_line_id') as line_id \gset
select (:'r'::jsonb->>'receipt_id') as receipt_id \gset
select (:'r'::jsonb->>'lot_id') as lot_id \gset
set local role authenticated;
select public.e10_org_review_receipt_disposition('e1000000-0000-4000-8000-0000000000a6',:'line_id','accept',2,null,0,'accept two','rvA2-accept') as d \gset
reset role;
select 'before' tag, qty from public.e10_inventory_items where id='rv-item-1';
select 'lot before' tag, status,accepted_quantity,quarantined_quantity from public.e10_inventory_lots where id=:'lot_id';
set local role authenticated;
select public.e10_org_reverse_receipt('e1000000-0000-4000-8000-0000000000a6',:'receipt_id','wrong shipment','rvA2-x4d-reverse');
reset role;
select 'after' tag, qty from public.e10_inventory_items where id='rv-item-1';
select 'lot after' tag, status,accepted_quantity,quarantined_quantity from public.e10_inventory_lots where id=:'lot_id';
select 'ledger sum' tag, sum(on_hand_delta) from public.e10_inventory_movements where item_id='rv-item-1';
select 'reversal quantity' tag, quantity from public.e10_stock_receipt_reversals where stock_receipt_id=:'receipt_id';
-- A3: the batch reverser on the same state (fresh receipt) for comparison
set local role authenticated;
select public.e10_org_receive_po_line('e1000000-0000-4000-8000-0000000000a6','a4000000-0000-4000-8000-000000000008','rv-item-2',3,0,2,'rvA3-lot','2026-09-12T06:00:00Z','[]','rvA3-receive') as r3 \gset
reset role;
select (:'r3'::jsonb->>'receipt_line_id') as line3 \gset
select (:'r3'::jsonb->>'receipt_id') as receipt3 \gset
set local role authenticated;
select public.e10_org_review_receipt_disposition('e1000000-0000-4000-8000-0000000000a6',:'line3','accept',2,null,0,'accept two','rvA3-accept')->>'effective_accepted' as eff;
select public.e10_org_reverse_receipt_batch('e1000000-0000-4000-8000-0000000000a6',:'receipt3','wrong shipment','rvA3-x4f-reverse')->'lines'->0->>'effective_accepted_removed' as removed;
reset role;
select 'item2 after batch reverse' tag, qty from public.e10_inventory_items where id='rv-item-2';
rollback;
