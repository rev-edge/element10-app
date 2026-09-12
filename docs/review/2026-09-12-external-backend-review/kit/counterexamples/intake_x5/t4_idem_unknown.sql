\set ON_ERROR_STOP 0
\pset format unaligned
\pset tuples_only on
begin;
\i fixture.sql
select pg_temp.as_a(); set local role authenticated;
\echo '--- idempotency: stage key reuse / failed attempt'
select pg_temp.try('I1 stage invalid rows (missing raw_payload) key K1', $q$select public.e10_org_stage_intake(org_a,'manual',null,null,null,'fp1','[{"observation_kind":"asking_price"}]','K1')::text from fx$q$);
select pg_temp.try('I2 retry K1 with valid rows after failure', $q$select public.e10_org_stage_intake(org_a,'manual',null,null,null,'fp1',jsonb_build_array(jsonb_build_object('raw_payload','{}'::jsonb,'observation_kind','asking_price','occurred_at','2025-01-01T00:00:00Z','currency','CAD','amount',1)),'K1')::text from fx$q$);
select pg_temp.try('I3 K1 with different rows', $q$select public.e10_org_stage_intake(org_a,'manual',null,null,null,'fp1',jsonb_build_array(jsonb_build_object('raw_payload','{}'::jsonb,'observation_kind','asking_price','occurred_at','2025-01-01T00:00:00Z','currency','CAD','amount',2)),'K1')::text from fx$q$);
select pg_temp.try('I4 K1 same rows different key order', $q$select public.e10_org_stage_intake(org_a,'manual',null,null,null,'fp1','[{"amount":1,"currency":"CAD","occurred_at":"2025-01-01T00:00:00Z","observation_kind":"asking_price","raw_payload":{}}]','K1')::text from fx$q$);
select pg_temp.try('I5 K1 amount 1.0 vs 1', $q$select public.e10_org_stage_intake(org_a,'manual',null,null,null,'fp1','[{"amount":1.0,"currency":"CAD","occurred_at":"2025-01-01T00:00:00Z","observation_kind":"asking_price","raw_payload":{}}]','K1')::text from fx$q$);
select pg_temp.try('I6 whitespace-padded key " K1"', $q$select public.e10_org_stage_intake(org_a,'manual',null,null,null,'fp1',jsonb_build_array(jsonb_build_object('raw_payload','{}'::jsonb,'observation_kind','asking_price','occurred_at','2025-01-01T00:00:00Z','currency','CAD','amount',1)),' K1')::text from fx$q$);
\echo '--- unknown values in intake parsing'
select pg_temp.try('U1 stage mixed invalid values', $q$select public.e10_org_stage_intake(org_a,'manual',null,null,null,'fp-u1',jsonb_build_array(
 jsonb_build_object('raw_payload','{}'::jsonb,'observation_kind','asking_price','occurred_at','2025-01-01T00:00:00Z','currency','usd','amount','abc'),
 jsonb_build_object('raw_payload','{}'::jsonb,'observation_kind','asking_price','occurred_at','2025-01-01','currency','USD','amount',0),
 jsonb_build_object('raw_payload','{}'::jsonb,'observation_kind','asking_price','occurred_at','2025-01-01T00:00:00Z','currency','USD','amount','-5'),
 jsonb_build_object('raw_payload','{}'::jsonb,'observation_kind','asking_price','occurred_at','2025-01-01T00:00:00Z','currency','USD','amount','1e400','quantity',0),
 jsonb_build_object('raw_payload','{}'::jsonb,'observation_kind','asking_price','occurred_at','2025-01-01T00:00:00Z','currency','USD'),
 jsonb_build_object('raw_payload','{}'::jsonb,'observation_kind','inventory_receipt','occurred_at','2025-01-01T00:00:00Z','quantity','2'),
 jsonb_build_object('raw_payload','{}'::jsonb,'observation_kind','asking_price','occurred_at','2025-01-01T00:00:00Z','currency','USD','amount',true)
),'U1')::text from fx$q$);
reset role;
select source_row_number,currency,amount,quantity,occurred_at,validation_errors from public.e10_intake_rows r join public.e10_intake_batches b on b.id=r.batch_id where b.idempotency_key='U1' order by 1;
select pg_temp.as_a(); set local role authenticated;
\echo '--- event envelope type confusion (v2)'
select pg_temp.try('E1 amount as string "5"', $q$select public.e10_org_record_commercial_event_v2(org_a,'fee',1,'inventory_item','c-item-a','2025-01-01T00:00:00Z','exact','manual',null,null,'e1',null,null,'operator_asserted','{"fee_id":"f","currency":"CAD","amount":"5"}',null,'{}','E1')::text from fx$q$);
select pg_temp.try('E2 amount 1e400', $q$select public.e10_org_record_commercial_event_v2(org_a,'fee',1,'inventory_item','c-item-a','2025-01-01T00:00:00Z','exact','manual',null,null,'e2',null,null,'operator_asserted','{"fee_id":"f","currency":"CAD","amount":1e400}',null,'{}','E2')::text from fx$q$);
select pg_temp.try('E3 amount -0', $q$select public.e10_org_record_commercial_event_v2(org_a,'fee',1,'inventory_item','c-item-a','2025-01-01T00:00:00Z','exact','manual',null,null,'e3',null,null,'operator_asserted','{"fee_id":"f","currency":"CAD","amount":-0}',null,'{}','E3')::text from fx$q$);
select pg_temp.try('E4 extra keys + nested', $q$select public.e10_org_record_commercial_event_v2(org_a,'fee',1,'inventory_item','c-item-a','2025-01-01T00:00:00Z','exact','manual',null,null,'e4',null,null,'operator_asserted','{"fee_id":"f","currency":"CAD","amount":1,"amount_paid":"lots","x":{"y":[1,2]}}',null,'{}','E4')::text from fx$q$);
select pg_temp.try('E5 currency missing on fee', $q$select public.e10_org_record_commercial_event_v2(org_a,'fee',1,'inventory_item','c-item-a','2025-01-01T00:00:00Z','exact','manual',null,null,'e5',null,null,'operator_asserted','{"fee_id":"f","amount":1}',null,'{}','E5')::text from fx$q$);
select pg_temp.try('E6 precision=date with time component', $q$select public.e10_org_record_commercial_event_v2(org_a,'return',1,'inventory_item','c-item-a','2025-01-01T13:45:00Z','date','manual',null,null,'e6',null,null,'operator_asserted','{"return_id":"r"}',null,'{}','E6')::text from fx$q$);
select pg_temp.try('E7 precision=unknown with occurred_at', $q$select public.e10_org_record_commercial_event_v2(org_a,'return',1,'inventory_item','c-item-a','2025-01-01T13:45:00Z','unknown','manual',null,null,'e7',null,null,'operator_asserted','{"return_id":"r"}',null,'{}','E7')::text from fx$q$);
select pg_temp.try('E8 fee_id numeric not string', $q$select public.e10_org_record_commercial_event_v2(org_a,'fee',1,'inventory_item','c-item-a','2025-01-01T00:00:00Z','exact','manual',null,null,'e8',null,null,'operator_asserted','{"fee_id":5,"currency":"CAD","amount":1}',null,'{}','E8')::text from fx$q$);
select pg_temp.try('E9 fee_id whitespace only', $q$select public.e10_org_record_commercial_event_v2(org_a,'fee',1,'inventory_item','c-item-a','2025-01-01T00:00:00Z','exact','manual',null,null,'e9',null,null,'operator_asserted','{"fee_id":"  ","currency":"CAD","amount":1}',null,'{}','E9')::text from fx$q$);
select pg_temp.try('E10 import kind with native_system quality', $q$select public.e10_org_record_commercial_event_v2(org_a,'return',1,'inventory_item','c-item-a','2025-01-01T00:00:00Z','exact','import','shop',null,'e10',null,null,'native_system','{"return_id":"r"}',null,'{}','E10')::text from fx$q$);
select pg_temp.try('E11 import claims connection inventory-ledger + movement-like id', $q$select public.e10_org_record_commercial_event_v2(org_a,'receipt',1,'inventory_item','c-item-a','2025-01-01T00:00:00Z','exact','import','inventory-ledger',null,gen_random_uuid()::text,null,null,'reviewed_import','{"receipt_id":"r"}',null,'{}','E11')::text from fx$q$);
\echo '--- v2 source_event_id normalization'
select pg_temp.try('E12 source_event_id "src-1"', $q$select public.e10_org_record_commercial_event_v2(org_a,'return',1,'inventory_item','c-item-a','2025-01-01T00:00:00Z','exact','manual','conn',null,'src-1',null,null,'operator_asserted','{"return_id":"r"}',null,'{}','E12')::text from fx$q$);
select pg_temp.try('E13 source_event_id " src-1 " (trimmed dup?)', $q$select public.e10_org_record_commercial_event_v2(org_a,'return',1,'inventory_item','c-item-a','2025-01-01T00:00:00Z','exact','manual','conn',null,' src-1 ',null,null,'operator_asserted','{"return_id":"r"}',null,'{}','E13')::text from fx$q$);
select pg_temp.try('E14 source_event_id "SRC-1" (case dup?)', $q$select public.e10_org_record_commercial_event_v2(org_a,'return',1,'inventory_item','c-item-a','2025-01-01T00:00:00Z','exact','manual','conn',null,'SRC-1',null,null,'operator_asserted','{"return_id":"r"}',null,'{}','E14')::text from fx$q$);
select pg_temp.try('E15 connection "conn " (untrimmed conn dup?)', $q$select public.e10_org_record_commercial_event_v2(org_a,'return',1,'inventory_item','c-item-a','2025-01-01T00:00:00Z','exact','manual','conn ',null,'src-1',null,null,'operator_asserted','{"return_id":"r"}',null,'{}','E15')::text from fx$q$);
select pg_temp.try('E16 same source id different subject/type (silently rejected as dup?)', $q$select public.e10_org_record_commercial_event_v2(org_a,'hold',1,'inventory_item','c-item-a','2025-02-01T00:00:00Z','exact','manual','conn',null,'src-1',null,null,'operator_asserted','{"hold_id":"h"}',null,'{}','E16')::text from fx$q$);
select pg_temp.try('E17 v2 source_event_id NULL twice (no dedup expected)', $q$select public.e10_org_record_commercial_event_v2(org_a,'return',1,'inventory_item','c-item-a','2025-01-01T00:00:00Z','exact','manual','conn',null,null,null,null,'operator_asserted','{"return_id":"r"}',null,'{}','E17')::text from fx$q$);
select pg_temp.try('E18 v2 source_event_id NULL again', $q$select public.e10_org_record_commercial_event_v2(org_a,'return',1,'inventory_item','c-item-a','2025-01-01T00:00:00Z','exact','manual','conn',null,null,null,null,'operator_asserted','{"return_id":"r"}',null,'{}','E18')::text from fx$q$);
\echo '--- native forging of commercial events'
select pg_temp.try('N1 v1 native', $q$select public.e10_org_record_commercial_event(org_a,'receipt','inventory_item','c-item-a','2025-01-01T00:00:00Z','native','x','{"receipt_id":"r"}',null,'{}','N1')::text from fx$q$);
select set_config('e10.receipt_evidence','on',true);
select pg_temp.try('N2 v1 native after user set_config e10.receipt_evidence=on', $q$select public.e10_org_record_commercial_event(org_a,'receipt','inventory_item','c-item-a','2025-01-01T00:00:00Z','native','x','{"receipt_id":"r"}',null,'{}','N2')::text from fx$q$);
select pg_temp.try('N3 v2 native', $q$select public.e10_org_record_commercial_event_v2(org_a,'receipt',1,'inventory_item','c-item-a','2025-01-01T00:00:00Z','exact','native','receipt-ledger',null,'x',null,null,'native_system','{"receipt_id":"r"}',null,'{}','N3')::text from fx$q$);
select pg_temp.try('N4 v1 system', $q$select public.e10_org_record_commercial_event(org_a,'receipt','inventory_item','c-item-a','2025-01-01T00:00:00Z','system','x','{"receipt_id":"r"}',null,'{}','N4')::text from fx$q$);
select pg_temp.try('N5 v1 bogus source kind', $q$select public.e10_org_record_commercial_event(org_a,'receipt','inventory_item','c-item-a','2025-01-01T00:00:00Z','bogus','x','{"receipt_id":"r"}',null,'{}','N5')::text from fx$q$);
select pg_temp.try('N6 v1 null occurred_at', $q$select public.e10_org_record_commercial_event(org_a,'receipt','inventory_item','c-item-a',null,'manual','x','{"receipt_id":"r"}',null,'{}','N6')::text from fx$q$);
\echo '--- v1 timezone-dependent fingerprint'
set local timezone to 'UTC';
select pg_temp.try('Z1 v1 record under UTC', $q$select public.e10_org_record_commercial_event(org_a,'return','inventory_item','c-item-a','2025-01-01T00:00:00Z','manual','x','{"return_id":"r"}',null,'{}','Z1')::text from fx$q$);
set local timezone to 'America/Toronto';
select pg_temp.try('Z2 v1 replay same key under America/Toronto', $q$select public.e10_org_record_commercial_event(org_a,'return','inventory_item','c-item-a','2025-01-01T00:00:00Z','manual','x','{"return_id":"r"}',null,'{}','Z1')::text from fx$q$);
set local timezone to 'UTC';
reset role;
rollback;
