\set ON_ERROR_STOP 0
begin;
\i prelude.sql
select set_config('request.jwt.claims','{"sub":"a4000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
set local role authenticated;
-- G1: history before any receipt (PO line has estimated_unit_cost 99)
select public.e10_org_supplier_actual_cost_history('e1000000-0000-4000-8000-0000000000a6','a4000000-0000-4000-8000-000000000003','a4000000-0000-4000-8000-000000000006','CAD','2026-12-31',50,null)->'items' as items_before;
-- G2: PO-only receipt with caller-supplied actual_unit_cost (no invoice at all)
select public.e10_org_receive_batch('e1000000-0000-4000-8000-0000000000a6','a4000000-0000-4000-8000-000000000003','a4000000-0000-4000-8000-000000000004','2026-09-12T06:00:00Z',
 jsonb_build_array(jsonb_build_object('line_no',1,'configuration_version_id','a4000000-0000-4000-8000-000000000006','inventory_item_id','rv-item-1',
  'accepted_quantity',2,'damaged_quantity',0,'quarantined_quantity',0,'actual_unit_cost',7.77,'currency','CAD','purchase_order_line_id','a4000000-0000-4000-8000-000000000008')),'rvG-po-only') as r1 \gset
-- G3: no-source receipt (neither PO nor invoice) with actual cost
select public.e10_org_receive_batch('e1000000-0000-4000-8000-0000000000a6','a4000000-0000-4000-8000-000000000003','a4000000-0000-4000-8000-000000000004','2026-09-12T07:00:00Z',
 jsonb_build_array(jsonb_build_object('line_no',1,'configuration_version_id','a4000000-0000-4000-8000-000000000006','inventory_item_id','rv-item-1',
  'accepted_quantity',1,'damaged_quantity',0,'quarantined_quantity',0,'actual_unit_cost',1.11,'currency','CAD')),'rvG-no-source') as r2 \gset
-- G4: damaged-only with cost
select public.e10_org_receive_batch('e1000000-0000-4000-8000-0000000000a6','a4000000-0000-4000-8000-000000000003','a4000000-0000-4000-8000-000000000004','2026-09-12T08:00:00Z',
 jsonb_build_array(jsonb_build_object('line_no',1,'configuration_version_id','a4000000-0000-4000-8000-000000000006','inventory_item_id','rv-item-1',
  'accepted_quantity',0,'damaged_quantity',1,'quarantined_quantity',0,'actual_unit_cost',5.55,'currency','CAD','invoice_line_id','a4000000-0000-4000-8000-00000000000a')),'rvG-dmg') as r3 \gset
select jsonb_pretty(public.e10_org_supplier_actual_cost_history('e1000000-0000-4000-8000-0000000000a6','a4000000-0000-4000-8000-000000000003','a4000000-0000-4000-8000-000000000006','CAD','2026-12-31',50,null)->'items');
-- G5: reverse the no-source receipt and check it disappears
select public.e10_org_reverse_receipt_batch('e1000000-0000-4000-8000-0000000000a6',(:'r2'::jsonb->>'receipt_id')::uuid,'x','rvG-rev')->>'status';
select jsonb_array_length(public.e10_org_supplier_actual_cost_history('e1000000-0000-4000-8000-0000000000a6','a4000000-0000-4000-8000-000000000003','a4000000-0000-4000-8000-000000000006','CAD','2026-12-31',50,null)->'items') as n_after_reverse;
reset role;
-- G6: check no PO/allocation rows were fabricated for no-source and invoice-only lines
select 'po allocs for no-source line' tag, count(*) from public.e10_receipt_po_allocations where receipt_line_id=(:'r2'::jsonb#>>'{lines,0,receipt_line_id}')::uuid;
select 'po allocs for invoice-only line' tag, count(*) from public.e10_receipt_po_allocations where receipt_line_id=(:'r3'::jsonb#>>'{lines,0,receipt_line_id}')::uuid;
select 'expected allocations count' tag, count(*) from public.e10_expected_inventory_allocations where organization_id='e1000000-0000-4000-8000-0000000000a6' and purchase_order_line_id='a4000000-0000-4000-8000-000000000008';
select 'X3a.1 authenticated select on receipt lines' tag, has_table_privilege('authenticated','public.e10_stock_receipt_lines','select') sel,
 (select count(*) from pg_policies where tablename='e10_stock_receipt_lines') policies;
select tablename, has_table_privilege('authenticated','public.'||tablename,'select') from pg_tables where tablename in ('e10_inventory_lots','e10_lot_reservations','e10_lot_reservation_transitions','e10_stock_receipt_reversals','e10_receipt_disposition_decisions','e10_receipt_commands','e10_receipt_reversal_commands','e10_expected_inventory_allocations','e10_lot_cost_evidence') order by 1;
rollback;
