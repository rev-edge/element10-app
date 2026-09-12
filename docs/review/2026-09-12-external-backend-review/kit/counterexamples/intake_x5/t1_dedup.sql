\set ON_ERROR_STOP 0
\pset format unaligned
\pset tuples_only on
begin;
\i fixture.sql
select pg_temp.as_a();
select pg_temp.try('A1 durable first', $q$select public.e10_org_stage_intake(org_a,'csv','vendor','daily.csv','storage://v1','sha-v1',jsonb_build_array(jsonb_build_object('raw_payload','{"source_event_id":"sale-1"}'::jsonb,'observation_kind','asking_price','occurred_at','2025-01-01T00:00:00Z','currency','CAD','amount',10)),'k-A1')::text from fx$q$);
select pg_temp.try('A2 durable exact replay new key', $q$select public.e10_org_stage_intake(org_a,'csv','vendor','daily.csv','storage://v1','sha-v1',jsonb_build_array(jsonb_build_object('raw_payload','{"source_event_id":"sale-1"}'::jsonb,'observation_kind','asking_price','occurred_at','2025-01-01T00:00:00Z','currency','CAD','amount',10)),'k-A2')::text from fx$q$);
select pg_temp.try('B1 connection trailing space', $q$select public.e10_org_stage_intake(org_a,'csv','vendor ','daily.csv','storage://v1','sha-v1',jsonb_build_array(jsonb_build_object('raw_payload','{"source_event_id":"sale-1"}'::jsonb,'observation_kind','asking_price','occurred_at','2025-01-01T00:00:00Z','currency','CAD','amount',10)),'k-B1')::text from fx$q$);
select pg_temp.try('B2 reference case', $q$select public.e10_org_stage_intake(org_a,'csv','vendor','Daily.csv','storage://v1','sha-v1',jsonb_build_array(jsonb_build_object('raw_payload','{"source_event_id":"sale-1"}'::jsonb,'observation_kind','asking_price','occurred_at','2025-01-01T00:00:00Z','currency','CAD','amount',10)),'k-B2')::text from fx$q$);
select pg_temp.try('B3 fingerprint case', $q$select public.e10_org_stage_intake(org_a,'csv','vendor','daily.csv','storage://v1','SHA-V1',jsonb_build_array(jsonb_build_object('raw_payload','{"source_event_id":"sale-1"}'::jsonb,'observation_kind','asking_price','occurred_at','2025-01-01T00:00:00Z','currency','CAD','amount',10)),'k-B3')::text from fx$q$);
select pg_temp.try('B4 empty-string connection', $q$select public.e10_org_stage_intake(org_a,'csv','','daily.csv','storage://v1','sha-v1',jsonb_build_array(jsonb_build_object('raw_payload','{"source_event_id":"sale-1"}'::jsonb,'observation_kind','asking_price','occurred_at','2025-01-01T00:00:00Z','currency','CAD','amount',10)),'k-B4')::text from fx$q$);
select pg_temp.try('D1 manual same fp', $q$select public.e10_org_stage_intake(org_a,'manual',null,null,null,'sha-manual',jsonb_build_array(jsonb_build_object('raw_payload','{"source_event_id":"m-1"}'::jsonb,'observation_kind','asking_price','occurred_at','2025-01-01T00:00:00Z','currency','CAD','amount',10)),'k-D1')::text from fx$q$);
select pg_temp.try('D2 manual same fp again', $q$select public.e10_org_stage_intake(org_a,'manual',null,null,null,'sha-manual',jsonb_build_array(jsonb_build_object('raw_payload','{"source_event_id":"m-1"}'::jsonb,'observation_kind','asking_price','occurred_at','2025-01-01T00:00:00Z','currency','CAD','amount',10)),'k-D2')::text from fx$q$);
select pg_temp.try('F1 csv null connection', $q$select public.e10_org_stage_intake(org_a,'csv',null,'daily.csv','storage://v1','sha-v1',jsonb_build_array(jsonb_build_object('raw_payload','{"source_event_id":"sale-1"}'::jsonb,'observation_kind','asking_price','occurred_at','2025-01-01T00:00:00Z','currency','CAD','amount',10)),'k-F1')::text from fx$q$);
select pg_temp.try('F2 csv null connection again', $q$select public.e10_org_stage_intake(org_a,'csv',null,'daily.csv','storage://v1','sha-v1',jsonb_build_array(jsonb_build_object('raw_payload','{"source_event_id":"sale-1"}'::jsonb,'observation_kind','asking_price','occurred_at','2025-01-01T00:00:00Z','currency','CAD','amount',10)),'k-F2')::text from fx$q$);
select pg_temp.try('G1 authenticated stages source_kind=native', $q$select public.e10_org_stage_intake(org_a,'native','inventory-ledger','forged-ref',null,'sha-native',jsonb_build_array(jsonb_build_object('raw_payload','{"source_event_id":"forged"}'::jsonb,'observation_kind','completed_sale','occurred_at','2025-01-01T00:00:00Z','currency','CAD','amount',999)),'k-G1')::text from fx$q$);
select pg_temp.try('G2 bogus source_kind', $q$select public.e10_org_stage_intake(org_a,'bogus','x','y',null,'sha-bogus',jsonb_build_array(jsonb_build_object('raw_payload','{}'::jsonb,'observation_kind','completed_sale','occurred_at','2025-01-01T00:00:00Z','currency','CAD','amount',1)),'k-G2')::text from fx$q$);
select pg_temp.try('C1 same connection different reference same source_event_id', $q$select public.e10_org_stage_intake(org_a,'csv','vendor','daily-2.csv','storage://v2','sha-v2',jsonb_build_array(jsonb_build_object('raw_payload','{"source_event_id":"sale-1"}'::jsonb,'observation_kind','asking_price','occurred_at','2025-01-01T00:00:00Z','currency','CAD','amount',10)),'k-C1')::text from fx$q$);
\echo '--- batches'
select idempotency_key,source_kind,'['||coalesce(source_connection_id,'NULL')||']' conn,source_reference,payload_fingerprint,status,supersedes_intake_batch_id from public.e10_intake_batches b where organization_id=(select org_a from fx) and idempotency_key like 'k-%' order by created_at;
\echo '--- commit all of them via ordinary commit'
do $$ declare o uuid; p uuid; r record; res jsonb; begin
 select org_a,prod_a into o,p from fx;
 for r in select b.id bid,b.idempotency_key k from public.e10_intake_batches b where b.organization_id=o and b.idempotency_key like 'k-%' order by created_at loop
   perform public.e10_org_resolve_intake_row(o,x.id,'match_product',p,'rev',null,'res-'||x.id) from public.e10_intake_rows x where x.batch_id=r.bid;
   begin
     res:=public.e10_org_commit_intake(o,r.bid,(public.e10_org_intake_review_state(o,r.bid)->>'review_revision')::bigint,'commit-'||r.bid);
     raise notice 'commit % -> obs=% replay=%',r.k,res->>'observation_count',res->>'replay';
   exception when others then raise notice 'commit % -> ERR % %',r.k,sqlstate,sqlerrm; end;
 end loop;
end $$;
\echo '--- resulting CURRENT observations: duplicates by (source_kind, connection, source_event_id)'
select source_kind,'['||coalesce(source_connection_id,'NULL')||']' conn,source_reference,raw_payload_snapshot->>'source_event_id' sev,amount,
 count(*) over (partition by source_kind,source_connection_id,raw_payload_snapshot->>'source_event_id') dup_count
 from public.e10_current_market_observations where organization_id=(select org_a from fx) order by 1,2,3;
rollback;
