\set ON_ERROR_STOP 0
\set ON_ERROR_ROLLBACK on
\set ON_ERROR_ROLLBACK on
begin;
\i prelude.sql
select set_config('request.jwt.claims','{"sub":"a4000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
set local role authenticated;
select public.e10_org_receive_po_line('e1000000-0000-4000-8000-0000000000a6','a4000000-0000-4000-8000-000000000008','rv-item-1',10,0,0,'rvC-lot','2026-09-12T06:00:00Z','[]','rvC-receive') as r \gset
reset role;
select (:'r'::jsonb->>'lot_id') as lot_id \gset
set local role authenticated;
-- C1: fingerprint sensitivity to numeric text form
select public.e10_org_lot_reserve('e1000000-0000-4000-8000-0000000000a6',:'lot_id',5,'a4000000-0000-4000-8000-00000000000b','rvC-k1')->>'replay' as first;
select public.e10_org_lot_reserve('e1000000-0000-4000-8000-0000000000a6',:'lot_id',5.0,'a4000000-0000-4000-8000-00000000000b','rvC-k1')->>'replay' as replay_5_0;
select public.e10_org_lot_reserve('e1000000-0000-4000-8000-0000000000a6',:'lot_id',5,'a4000000-0000-4000-8000-00000000000b','rvC-k1')->>'replay' as replay_5;
-- C2: retry after failed attempt (insufficient) then success with smaller qty using SAME key -> mismatch? and NEW key works
select public.e10_org_lot_reserve('e1000000-0000-4000-8000-0000000000a6',:'lot_id',50,'a4000000-0000-4000-8000-00000000000b','rvC-k2');
select public.e10_org_lot_reserve('e1000000-0000-4000-8000-0000000000a6',:'lot_id',2,'a4000000-0000-4000-8000-00000000000b','rvC-k2')->>'replay' as retry_after_failure_same_key;
-- C3: reserve idempotency key reused by X4h generic reserve in same org -> same table unique(org,key): what happens?
select public.e10_org_lot_reserve_for_demand('e1000000-0000-4000-8000-0000000000a6',:'lot_id',1,'manual','ref-1','label','rvC-k2');
-- C4: consume fingerprint 1 vs 1.0
select (public.e10_org_lot_reserve('e1000000-0000-4000-8000-0000000000a6',:'lot_id',2,'a4000000-0000-4000-8000-00000000000b','rvC-k1'))->>'reservation_id' as res_id \gset
select public.e10_org_lot_consume('e1000000-0000-4000-8000-0000000000a6',:'res_id',1,'rvC-c1')->>'replay';
select public.e10_org_lot_consume('e1000000-0000-4000-8000-0000000000a6',:'res_id',1.0,'rvC-c1')->>'replay';
-- C5: release key reused for consume (same transitions table, same org)
select public.e10_org_lot_release('e1000000-0000-4000-8000-0000000000a6',:'res_id','rvC-c1');
reset role;
-- C6: cross-org: foreign actor uses org A's idempotency keys under its own org id
select set_config('request.jwt.claims','{"sub":"a4000000-0000-4000-8000-00000000000d","role":"authenticated"}',true);
set local role authenticated;
select public.e10_org_lot_reserve('a4000000-0000-4000-8000-00000000000c',:'lot_id',1,'a4000000-0000-4000-8000-00000000000b','rvC-k1');
select public.e10_org_lot_consume('a4000000-0000-4000-8000-00000000000c',:'res_id',1,'rvC-c1');
-- foreign actor with org A id
select public.e10_org_lot_reserve('e1000000-0000-4000-8000-0000000000a6',:'lot_id',1,'a4000000-0000-4000-8000-00000000000b','rvC-k1');
select public.e10_org_reverse_receipt_batch('e1000000-0000-4000-8000-0000000000a6',(:'r'::jsonb->>'receipt_id')::uuid,'x','rvC-rev');
select public.e10_org_reverse_receipt('e1000000-0000-4000-8000-0000000000a6',(:'r'::jsonb->>'receipt_id')::uuid,'x','rvC-rev');
-- foreign actor with own org id but org A receipt
select public.e10_org_reverse_receipt_batch('a4000000-0000-4000-8000-00000000000c',(:'r'::jsonb->>'receipt_id')::uuid,'x','rvC-rev');
select public.e10_org_reverse_receipt('a4000000-0000-4000-8000-00000000000c',(:'r'::jsonb->>'receipt_id')::uuid,'x','rvC-rev');
select public.e10_org_review_receipt_disposition('a4000000-0000-4000-8000-00000000000c',(:'r'::jsonb->>'receipt_line_id')::uuid,'accept',1,null,0,'x','rvC-disp');
select public.e10_org_lot_reserve_for_demand('a4000000-0000-4000-8000-00000000000c',:'lot_id',1,'manual','ref','lbl','rvC-gen');
reset role;
rollback;
