\set ON_ERROR_STOP 0
\set ON_ERROR_ROLLBACK on
begin;
\i prelude.sql
select set_config('request.jwt.claims','{"sub":"a4000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
set local role authenticated;
-- B1: X4d quarantine-only receipt then batch reversal
select public.e10_org_receive_po_line('e1000000-0000-4000-8000-0000000000a6','a4000000-0000-4000-8000-000000000008','rv-item-1',0,0,4,'rvB-lot','2026-09-12T06:00:00Z','[]','rvB-receive') as r \gset
reset role;
select (:'r'::jsonb->>'receipt_id') as receipt_id \gset
select (:'r'::jsonb->>'receipt_line_id') as line_id \gset
select 'events after X4d quarantine receipt' tag, count(*) from public.e10_commercial_events where subject_id='rv-item-1';
set local role authenticated;
select public.e10_org_reverse_receipt_batch('e1000000-0000-4000-8000-0000000000a6',:'receipt_id','wrong','rvB-x4f');
-- B2: after damage-only disposition, batch reversal
select public.e10_org_review_receipt_disposition('e1000000-0000-4000-8000-0000000000a6',:'line_id','damage',1,null,0,'dmg','rvB-dmg')->>'ok';
select public.e10_org_reverse_receipt_batch('e1000000-0000-4000-8000-0000000000a6',:'receipt_id','wrong','rvB-x4f-2');
-- B3: X4d single reversal works on it
select public.e10_org_reverse_receipt('e1000000-0000-4000-8000-0000000000a6',:'receipt_id','wrong','rvB-x4d')->>'status';
reset role;
select 'events after X4d reverse' tag, event_type, corrects_event_id is not null lineage from public.e10_commercial_events where subject_id='rv-item-1' order by created_at;
rollback;
