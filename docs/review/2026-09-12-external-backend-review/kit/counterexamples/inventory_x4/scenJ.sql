\set ON_ERROR_STOP 0
\set ON_ERROR_ROLLBACK on
begin;
\i prelude.sql
select set_config('request.jwt.claims','{"sub":"a4000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
set local role authenticated;
-- J1: X4e receipt accepted 2 + quarantined 3 (PO), disposition accept 3, then X4d reverse: expect orphan 3
select public.e10_org_receive_batch('e1000000-0000-4000-8000-0000000000a6','a4000000-0000-4000-8000-000000000003','a4000000-0000-4000-8000-000000000004','2026-09-12T06:00:00Z',
 jsonb_build_array(jsonb_build_object('line_no',1,'configuration_version_id','a4000000-0000-4000-8000-000000000006','inventory_item_id','rv-item-1',
  'accepted_quantity',2,'damaged_quantity',0,'quarantined_quantity',3,'actual_unit_cost',10,'currency','CAD','purchase_order_line_id','a4000000-0000-4000-8000-000000000008','invoice_line_id','a4000000-0000-4000-8000-00000000000a')),'rvJ-receive') as r \gset
select (:'r'::jsonb#>>'{lines,0,receipt_line_id}') as line_id \gset
select (:'r'::jsonb->>'receipt_id') as receipt_id \gset
select (:'r'::jsonb#>>'{lines,0,lot_id}') as lot_id \gset
select public.e10_org_review_receipt_disposition('e1000000-0000-4000-8000-0000000000a6',:'line_id','accept',3,null,0,'accept','rvJ-accept')->>'effective_accepted' as eff_after_accept;
-- reserve 4 of the 5 accepted, then release, so lot has no committed quantity
select public.e10_org_lot_reserve('e1000000-0000-4000-8000-0000000000a6',:'lot_id',4,'a4000000-0000-4000-8000-00000000000b','rvJ-res')->>'reservation_id' as res \gset
select public.e10_org_lot_release('e1000000-0000-4000-8000-0000000000a6',:'res','rvJ-rel')->>'status';
select public.e10_org_reverse_receipt('e1000000-0000-4000-8000-0000000000a6',:'receipt_id','x','rvJ-x4d')->>'status' as x4d_reverse;
reset role;
select 'item qty after X4d reverse (expected 0)' tag, qty from public.e10_inventory_items where id='rv-item-1';
select 'PO open commitment after reverse' tag, e10.purchase_order_open_commitment_summary('e1000000-0000-4000-8000-0000000000a6','a4000000-0000-4000-8000-000000000007')->>'unknown_outstanding_quantity' unknown_q, e10.purchase_order_open_commitment_summary('e1000000-0000-4000-8000-0000000000a6','a4000000-0000-4000-8000-000000000007')->>'known_subtotal' known;
select 'X4e prior for PO line (allows re-receipt of 10?)' tag, coalesce(sum(a.allocated_quantity),0) prior from public.e10_receipt_po_allocations a join public.e10_stock_receipt_lines rl on rl.id=a.receipt_line_id join public.e10_stock_receipts sr on sr.id=rl.stock_receipt_id where a.purchase_order_line_id='a4000000-0000-4000-8000-000000000008' and sr.status<>'reversed';
set local role authenticated;
-- disposition after X4d reversal is closed?
select public.e10_org_review_receipt_disposition('e1000000-0000-4000-8000-0000000000a6',:'line_id','accept',1,null,0,'late','rvJ-late');
-- batch reverse after X4d reverse?
select public.e10_org_reverse_receipt_batch('e1000000-0000-4000-8000-0000000000a6',:'receipt_id','x','rvJ-x4f');
-- legacy sell of orphaned units
select public.e10_org_inv_mark_sold('e1000000-0000-4000-8000-0000000000a6','rv-item-1',3,30,'rvJ-sell')->>'msg';
reset role;
select 'ledger' tag, movement_type,on_hand_delta,source_action from public.e10_inventory_movements where item_id='rv-item-1' order by created_at;
rollback;
