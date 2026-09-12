\set ON_ERROR_STOP 0
\set ON_ERROR_ROLLBACK on
\set ON_ERROR_ROLLBACK on
begin;
\i prelude.sql
select set_config('request.jwt.claims','{"sub":"a4000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
set local role authenticated;
select public.e10_org_receive_po_line('e1000000-0000-4000-8000-0000000000a6','a4000000-0000-4000-8000-000000000008','rv-item-1',10,0,0,'rvD-lot','2026-09-12T06:00:00Z','[]','rvD-receive') as r \gset
reset role;
select (:'r'::jsonb->>'lot_id') as lot_id \gset
select (:'r'::jsonb->>'receipt_id') as receipt_id \gset
set local role authenticated;
-- D1: fractional reservation and consumption on a card lot
select public.e10_org_lot_reserve('e1000000-0000-4000-8000-0000000000a6',:'lot_id',2.5,'a4000000-0000-4000-8000-00000000000b','rvD-frac')->>'reservation_id' as fres \gset
select public.e10_org_lot_consume('e1000000-0000-4000-8000-0000000000a6',:'fres',0.25,'rvD-frac-c')->>'consumed_quantity' as consumed_frac;
reset role;
select 'after fractional' tag, qty from public.e10_inventory_items where id='rv-item-1';
select 'legacy res' tag, qty, status from public.e10_inventory_reservations where item_id='rv-item-1';
set local role authenticated;
-- D2: consume more than reserved
select public.e10_org_lot_consume('e1000000-0000-4000-8000-0000000000a6',:'fres',5,'rvD-over-c');
-- D3: release twice with different keys; consume after release
select public.e10_org_lot_release('e1000000-0000-4000-8000-0000000000a6',:'fres','rvD-rel1')->>'released_quantity';
select public.e10_org_lot_release('e1000000-0000-4000-8000-0000000000a6',:'fres','rvD-rel2');
select public.e10_org_lot_consume('e1000000-0000-4000-8000-0000000000a6',:'fres',1,'rvD-c-after-rel');
-- D4: zero / negative / null
select public.e10_org_lot_reserve('e1000000-0000-4000-8000-0000000000a6',:'lot_id',0,'a4000000-0000-4000-8000-00000000000b','rvD-zero');
select public.e10_org_lot_reserve('e1000000-0000-4000-8000-0000000000a6',:'lot_id',-1,'a4000000-0000-4000-8000-00000000000b','rvD-neg');
select public.e10_org_lot_reserve('e1000000-0000-4000-8000-0000000000a6',:'lot_id',null,'a4000000-0000-4000-8000-00000000000b','rvD-null');
select public.e10_org_lot_reserve('e1000000-0000-4000-8000-0000000000a6',:'lot_id','NaN','a4000000-0000-4000-8000-00000000000b','rvD-nan');
select public.e10_org_lot_reserve('e1000000-0000-4000-8000-0000000000a6',:'lot_id',5,null,'rvD-nullsess');
-- D5: X4d receive NaN / null quantities / all-null
select public.e10_org_receive_po_line('e1000000-0000-4000-8000-0000000000a6','a4000000-0000-4000-8000-000000000008','rv-item-2','NaN',0,0,null,now(),'[]','rvD-nan-recv');
select public.e10_org_receive_po_line('e1000000-0000-4000-8000-0000000000a6','a4000000-0000-4000-8000-000000000008','rv-item-2',null,null,null,null,now(),'[]','rvD-null-recv');
select public.e10_org_receive_po_line('e1000000-0000-4000-8000-0000000000a6','a4000000-0000-4000-8000-000000000008','rv-item-2',0.5,0,0,null,now(),'[]','rvD-frac-recv')->>'ok' as frac_receipt_ok;
-- D6: reverse a reversal; reverse after consumption
select (public.e10_org_lot_reserve('e1000000-0000-4000-8000-0000000000a6',:'lot_id',2,'a4000000-0000-4000-8000-00000000000b','rvD-r2'))->>'reservation_id' as r2 \gset
select public.e10_org_lot_consume('e1000000-0000-4000-8000-0000000000a6',:'r2',2,'rvD-r2-c')->>'status';
select public.e10_org_reverse_receipt_batch('e1000000-0000-4000-8000-0000000000a6',:'receipt_id','x','rvD-rev-after-consume');
select public.e10_org_reverse_receipt('e1000000-0000-4000-8000-0000000000a6',:'receipt_id','x','rvD-rev-after-consume-x4d');
reset role;
-- D7: expected allocation duplicates in X4d payload
insert into public.e10_expected_inventory_allocations(id,organization_id,purchase_order_line_id,destination_location_id,expected_quantity,planning_reference)
 values('a4000000-0000-4000-8000-0000000000e1','e1000000-0000-4000-8000-0000000000a6','a4000000-0000-4000-8000-000000000008','a4000000-0000-4000-8000-000000000004',5,'rvD-plan');
set local role authenticated;
select public.e10_org_receive_po_line('e1000000-0000-4000-8000-0000000000a6','a4000000-0000-4000-8000-000000000008','rv-item-1',4,0,0,null,now(),
  '[{"id":"a4000000-0000-4000-8000-0000000000e1","quantity":2},{"id":"a4000000-0000-4000-8000-0000000000e1","quantity":2}]','rvD-dup-alloc');
reset role;
-- D8: lot/item invariants after all of the above
select 'lot' tag, accepted_quantity, (select coalesce(sum(case when status='active' then quantity else 0 end),0) from public.e10_lot_reservations where lot_id=:'lot_id') active,
 (select coalesce(sum(consumed_quantity),0) from public.e10_lot_reservations where lot_id=:'lot_id') consumed from public.e10_inventory_lots where id=:'lot_id';
select 'item' tag, qty, (select coalesce(sum(qty),0) from public.e10_inventory_reservations where item_id='rv-item-1' and status='active') legacy_active from public.e10_inventory_items where id='rv-item-1';
select 'ledger' tag, sum(on_hand_delta) on_hand, sum(reserved_delta) reserved from public.e10_inventory_movements where item_id='rv-item-1';
rollback;
