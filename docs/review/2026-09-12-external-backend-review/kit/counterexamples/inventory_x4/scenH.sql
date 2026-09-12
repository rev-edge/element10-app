\set ON_ERROR_STOP 0
\set ON_ERROR_ROLLBACK on
\set ON_ERROR_ROLLBACK on
begin;
\i prelude.sql
select set_config('request.jwt.claims','{"sub":"a4000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
set local role authenticated;
-- H1: same lot_code twice in one batch
select public.e10_org_receive_batch('e1000000-0000-4000-8000-0000000000a6','a4000000-0000-4000-8000-000000000003','a4000000-0000-4000-8000-000000000004',null,
 jsonb_build_array(
  jsonb_build_object('line_no',1,'configuration_version_id','a4000000-0000-4000-8000-000000000006','inventory_item_id','rv-item-1','accepted_quantity',1,'damaged_quantity',0,'quarantined_quantity',0,'lot_code','DUP'),
  jsonb_build_object('line_no',2,'configuration_version_id','a4000000-0000-4000-8000-000000000006','inventory_item_id','rv-item-1','accepted_quantity',1,'damaged_quantity',0,'quarantined_quantity',0,'lot_code','dup ')),'rvH-dup');
-- H2: X4e over-receipt across two lines of the same batch (6+6 > 10)
select public.e10_org_receive_batch('e1000000-0000-4000-8000-0000000000a6','a4000000-0000-4000-8000-000000000003','a4000000-0000-4000-8000-000000000004',null,
 jsonb_build_array(
  jsonb_build_object('line_no',1,'configuration_version_id','a4000000-0000-4000-8000-000000000006','inventory_item_id','rv-item-1','accepted_quantity',6,'damaged_quantity',0,'quarantined_quantity',0,'purchase_order_line_id','a4000000-0000-4000-8000-000000000008'),
  jsonb_build_object('line_no',2,'configuration_version_id','a4000000-0000-4000-8000-000000000006','inventory_item_id','rv-item-1','accepted_quantity',6,'damaged_quantity',0,'quarantined_quantity',0,'purchase_order_line_id','a4000000-0000-4000-8000-000000000008')),'rvH-over');
-- H3: receipt with 10 via X4d then X4e batch 1 more -> over
select public.e10_org_receive_po_line('e1000000-0000-4000-8000-0000000000a6','a4000000-0000-4000-8000-000000000008','rv-item-1',10,0,0,'rvH-lot','2026-09-12T06:00:00Z','[]','rvH-receive') as r \gset
select public.e10_org_receive_batch('e1000000-0000-4000-8000-0000000000a6','a4000000-0000-4000-8000-000000000003','a4000000-0000-4000-8000-000000000004',null,
 jsonb_build_array(jsonb_build_object('line_no',1,'configuration_version_id','a4000000-0000-4000-8000-000000000006','inventory_item_id','rv-item-1','accepted_quantity',1,'damaged_quantity',0,'quarantined_quantity',0,'purchase_order_line_id','a4000000-0000-4400-8000-000000000008')),'rvH-over2');
select public.e10_org_receive_batch('e1000000-0000-4000-8000-0000000000a6','a4000000-0000-4000-8000-000000000003','a4000000-0000-4000-8000-000000000004',null,
 jsonb_build_array(jsonb_build_object('line_no',1,'configuration_version_id','a4000000-0000-4000-8000-000000000006','inventory_item_id','rv-item-1','accepted_quantity',1,'damaged_quantity',0,'quarantined_quantity',0,'purchase_order_line_id','a4000000-0000-4000-8000-000000000008')),'rvH-over3');
-- H4: X4e batch reusing X4d's stock_receipts idempotency key
select public.e10_org_receive_batch('e1000000-0000-4000-8000-0000000000a6','a4000000-0000-4000-8000-000000000003','a4000000-0000-4000-8000-000000000004',null,
 jsonb_build_array(jsonb_build_object('line_no',1,'configuration_version_id','a4000000-0000-4000-8000-000000000006','inventory_item_id','rv-item-2','accepted_quantity',1,'damaged_quantity',0,'quarantined_quantity',0)),'rvH-receive');
-- H5: X4h duplicate demand reference on the same lot with different keys
select (:'r'::jsonb->>'lot_id') as lot_id \gset
select public.e10_org_lot_reserve_for_demand('e1000000-0000-4000-8000-0000000000a6',:'lot_id',1,'sale_order','SO-1','Sale order 1','rvH-g1')->>'status';
select public.e10_org_lot_reserve_for_demand('e1000000-0000-4000-8000-0000000000a6',:'lot_id',1,'sale_order','SO-1','Sale order 1','rvH-g2');
-- H6: X4b same session twice on same lot with different keys
select public.e10_org_lot_reserve('e1000000-0000-4000-8000-0000000000a6',:'lot_id',1,'a4000000-0000-4000-8000-00000000000b','rvH-s1')->>'status';
select public.e10_org_lot_reserve('e1000000-0000-4000-8000-0000000000a6',:'lot_id',1,'a4000000-0000-4000-8000-00000000000b','rvH-s2');
-- H7: disposition on the accepted-only line (no quarantine): accept 1 -> exceeds
select public.e10_org_review_receipt_disposition('e1000000-0000-4000-8000-0000000000a6',(:'r'::jsonb->>'receipt_line_id')::uuid,'accept',1,null,0,'x','rvH-disp');
-- H8: X4e receipt with received_at in far future; then history as_of now
select public.e10_org_receive_batch('e1000000-0000-4000-8000-0000000000a6','a4000000-0000-4000-8000-000000000003','a4000000-0000-4000-8000-000000000004','2999-01-01',
 jsonb_build_array(jsonb_build_object('line_no',1,'configuration_version_id','a4000000-0000-4000-8000-000000000006','inventory_item_id','rv-item-2','accepted_quantity',1,'damaged_quantity',0,'quarantined_quantity',0,'actual_unit_cost',3,'currency','CAD')),'rvH-future')->>'ok';
reset role;
rollback;
