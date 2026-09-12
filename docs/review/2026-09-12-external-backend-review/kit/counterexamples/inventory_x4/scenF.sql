\set ON_ERROR_STOP 0
\set ON_ERROR_ROLLBACK on
\set ON_ERROR_ROLLBACK on
begin;
\i prelude.sql
select set_config('request.jwt.claims','{"sub":"a4000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
set local role authenticated;
select public.e10_org_receive_po_line('e1000000-0000-4000-8000-0000000000a6','a4000000-0000-4000-8000-000000000008','rv-item-1',10,0,0,'rvF-lot','2026-09-12T06:00:00Z','[]','rvF-receive') as r \gset
reset role;
select (:'r'::jsonb->>'lot_id') as lot_id \gset
select (:'r'::jsonb->>'receipt_id') as receipt_id \gset
set local role authenticated;
select (public.e10_org_lot_reserve('e1000000-0000-4000-8000-0000000000a6',:'lot_id',4,'a4000000-0000-4000-8000-00000000000b','rvF-res'))->>'reservation_id' as res \gset
-- F1: legacy consume on the same item/show_ref (session source_show_ref = rv-show)
select public.e10_org_inv_consume('e1000000-0000-4000-8000-0000000000a6','rv-item-1','a4000000-0000-4000-8000-00000000000b','rv-show',1,'rvF-legacy-consume');
-- F2: legacy release of the show
select public.e10_org_inv_release('e1000000-0000-4000-8000-0000000000a6','rv-item-1','rv-show','rvF-legacy-release');
-- F3: legacy consume with NO show ref (draws nothing from reservations) -> reduces on-hand beneath lot accounting?
select public.e10_org_inv_consume('e1000000-0000-4000-8000-0000000000a6','rv-item-1',null,null,6,'rvF-legacy-consume2')->>'msg';
reset role;
select 'after legacy consume 6' tag, qty from public.e10_inventory_items where id='rv-item-1';
select 'lot' tag, status, accepted_quantity from public.e10_inventory_lots where id=:'lot_id';
select 'legacy res' tag, qty, status from public.e10_inventory_reservations where item_id='rv-item-1';
set local role authenticated;
-- F4: lot consume now: reserved 4 but on hand 4 -> should be fine; then another lot reserve of remaining accepted (10-4=6) but on hand 0
select public.e10_org_lot_consume('e1000000-0000-4000-8000-0000000000a6',:'res',4,'rvF-c')->>'status';
select public.e10_org_lot_reserve('e1000000-0000-4000-8000-0000000000a6',:'lot_id',1,'a4000000-0000-4000-8000-00000000000b','rvF-res2');
-- F5: legacy qty patch upward then lot reserve
select public.e10_org_inv_edit_item('e1000000-0000-4000-8000-0000000000a6','rv-item-1','{"qty":50}','rvF-edit')->>'msg';
select public.e10_org_lot_reserve('e1000000-0000-4000-8000-0000000000a6',:'lot_id',6,'a4000000-0000-4000-8000-00000000000b','rvF-res3')->>'status';
select public.e10_org_lot_reserve('e1000000-0000-4000-8000-0000000000a6',:'lot_id',1,'a4000000-0000-4000-8000-00000000000b','rvF-res4');
-- F6: legacy qty patch downward below active lot reservations -> clamp tries to trim lot-linked reservation
select public.e10_org_inv_edit_item('e1000000-0000-4000-8000-0000000000a6','rv-item-1','{"qty":2}','rvF-edit2');
-- F7: mark sold while lot reservation active (non-admin)
select public.e10_org_inv_mark_sold('e1000000-0000-4000-8000-0000000000a6','rv-item-1',45,10,'rvF-sold')->>'msg';
-- F8: delete item with lots
select public.e10_org_inv_delete_item('e1000000-0000-4000-8000-0000000000a6','rv-item-1','rvF-del');
reset role;
select 'final item' tag, qty from public.e10_inventory_items where id='rv-item-1';
select 'final lot' tag, accepted_quantity, (select sum(case when status='active' then quantity else 0 end) from public.e10_lot_reservations where lot_id=:'lot_id') active, (select sum(consumed_quantity) from public.e10_lot_reservations where lot_id=:'lot_id') consumed from public.e10_inventory_lots where id=:'lot_id';
rollback;
