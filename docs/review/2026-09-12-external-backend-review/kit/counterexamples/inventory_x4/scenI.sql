\set ON_ERROR_STOP 0
\set ON_ERROR_ROLLBACK on
begin;
\i prelude.sql
insert into public.e10_purchase_order_lines(id,organization_id,purchase_order_id,configuration_version_id,line_no,ordered_quantity)
 values('a4000000-0000-4000-8000-0000000000e2','e1000000-0000-4000-8000-0000000000a6','a4000000-0000-4000-8000-000000000007','a4000000-0000-4000-8000-000000000006',2,10);
insert into public.e10_expected_inventory_allocations(id,organization_id,purchase_order_line_id,destination_location_id,expected_quantity,planning_reference)
 values('a4000000-0000-4000-8000-0000000000e1','e1000000-0000-4000-8000-0000000000a6','a4000000-0000-4000-8000-0000000000e2','a4000000-0000-4000-8000-000000000004',5,'rvI-plan');
-- second same-org user with same caps
insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at) values('a4000000-0000-4000-8000-000000000021','00000000-0000-0000-0000-000000000000','authenticated','authenticated','rv-u2@example.invalid',now(),now());
insert into public.e10_organization_memberships(organization_id,user_id,role_id,status) values('e1000000-0000-4000-8000-0000000000a6','a4000000-0000-4000-8000-000000000021','a4000000-0000-4000-8000-000000000002','active');
select set_config('request.jwt.claims','{"sub":"a4000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
set local role authenticated;
-- I1: fractional receipt quantities on card PO line (X4d and X4e)
select public.e10_org_receive_po_line('e1000000-0000-4000-8000-0000000000a6','a4000000-0000-4000-8000-0000000000e2','rv-item-2',0.5,0.25,0,null,now(),'[]','rvI-frac')->>'ok' as x4d_fractional_ok;
select public.e10_org_receive_batch('e1000000-0000-4000-8000-0000000000a6','a4000000-0000-4000-8000-000000000003','a4000000-0000-4000-8000-000000000004',null,
 jsonb_build_array(jsonb_build_object('line_no',1,'configuration_version_id','a4000000-0000-4000-8000-000000000006','inventory_item_id','rv-item-2','accepted_quantity',0.5,'damaged_quantity',0,'quarantined_quantity',0,'purchase_order_line_id','a4000000-0000-4000-8000-0000000000e2')),'rvI-frac-batch')->>'ok' as x4e_fractional_ok;
-- I2: duplicate expected allocation id in X4d payload
select public.e10_org_receive_po_line('e1000000-0000-4000-8000-0000000000a6','a4000000-0000-4000-8000-0000000000e2','rv-item-2',4,0,0,null,now(),
  '[{"id":"a4000000-0000-4000-8000-0000000000e1","quantity":2},{"id":"a4000000-0000-4000-8000-0000000000e1","quantity":2}]','rvI-dup-alloc');
-- I3: expected allocation quantity exceeding accepted / negative / on wrong line
select public.e10_org_receive_po_line('e1000000-0000-4000-8000-0000000000a6','a4000000-0000-4000-8000-0000000000e2','rv-item-2',1,0,0,null,now(),'[{"id":"a4000000-0000-4000-8000-0000000000e1","quantity":2}]','rvI-alloc-exceeds');
select public.e10_org_receive_po_line('e1000000-0000-4000-8000-0000000000a6','a4000000-0000-4000-8000-0000000000e2','rv-item-2',1,0,0,null,now(),'[{"id":"a4000000-0000-4000-8000-0000000000e1","quantity":-1}]','rvI-alloc-neg');
select public.e10_org_receive_po_line('e1000000-0000-4000-8000-0000000000a6','a4000000-0000-4000-8000-000000000008','rv-item-1',1,0,0,null,now(),'[{"id":"a4000000-0000-4000-8000-0000000000e1","quantity":1}]','rvI-alloc-wrongline');
-- I4: consume fingerprint 1 vs 1.0 and release key reuse across transition kinds
select public.e10_org_receive_po_line('e1000000-0000-4000-8000-0000000000a6','a4000000-0000-4000-8000-000000000008','rv-item-1',10,0,0,'rvI-lot',now(),'[]','rvI-receive') as r \gset
select (:'r'::jsonb->>'lot_id') as lot_id \gset
select (:'r'::jsonb->>'receipt_id') as receipt_id \gset
select public.e10_org_lot_reserve('e1000000-0000-4000-8000-0000000000a6',:'lot_id',4,'a4000000-0000-4000-8000-00000000000b','rvI-k1')->>'reservation_id' as res_id \gset
select public.e10_org_lot_consume('e1000000-0000-4000-8000-0000000000a6',:'res_id',1,'rvI-c1')->>'replay' as consume_first;
select public.e10_org_lot_consume('e1000000-0000-4000-8000-0000000000a6',:'res_id',1.0,'rvI-c1')->>'replay' as consume_replay_1_0;
select public.e10_org_lot_release('e1000000-0000-4000-8000-0000000000a6',:'res_id','rvI-c1');
-- I5: replay of a receipt command by a different same-org user (created_by not checked)
reset role;
select set_config('request.jwt.claims','{"sub":"a4000000-0000-4000-8000-000000000021","role":"authenticated"}',true);
set local role authenticated;
select public.e10_org_receive_po_line('e1000000-0000-4000-8000-0000000000a6','a4000000-0000-4000-8000-000000000008','rv-item-1',10,0,0,'rvI-lot',(:'r'::jsonb->>'received_at')::timestamptz,'[]','rvI-receive')->>'replay' as x4d_replay_by_other_user;
select public.e10_org_reverse_receipt_batch('e1000000-0000-4000-8000-0000000000a6',:'receipt_id','x','rvI-rev-u2');
reset role;
select set_config('request.jwt.claims','{"sub":"a4000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
set local role authenticated;
select public.e10_org_lot_release('e1000000-0000-4000-8000-0000000000a6',:'res_id','rvI-rel')->>'status';
select public.e10_org_reverse_receipt_batch('e1000000-0000-4000-8000-0000000000a6',:'receipt_id','x','rvI-rev')->>'status' as rev_by_u1;
reset role;
select set_config('request.jwt.claims','{"sub":"a4000000-0000-4000-8000-000000000021","role":"authenticated"}',true);
set local role authenticated;
select public.e10_org_reverse_receipt_batch('e1000000-0000-4000-8000-0000000000a6',:'receipt_id','x','rvI-rev')->>'replay' as rev_replay_by_u2;
reset role;
-- I6: history/lineage immutability: try updating historical rows as postgres (append-only triggers)
update public.e10_stock_receipt_reversals set quantity=1 where stock_receipt_id=:'receipt_id';
update public.e10_lot_reservation_transitions set quantity=1 where idempotency_key='rvI-c1';
delete from public.e10_receipt_reversal_commands where idempotency_key='rvI-rev';
update public.e10_expected_allocation_events set quantity=9 where organization_id='e1000000-0000-4000-8000-0000000000a6';
-- disposition decisions: are they insert-only? (covered by trigger) ; receipt lines mutable by design?
update public.e10_stock_receipt_lines set accepted_quantity=accepted_quantity where stock_receipt_id=:'receipt_id';
rollback;
