\set ON_ERROR_STOP 0
\pset format unaligned
\pset tuples_only on
begin;
\i fixture.sql
select pg_temp.as_a();
create temp table st(k text primary key, v uuid); grant all on st to public;
do $$ declare o uuid; p uuid; res jsonb; b uuid; r uuid; begin
 select org_a,prod_a into o,p from fx;
 res:=public.e10_org_stage_intake(o,'csv','vendor','t1.csv','storage://t1','sha-t1',jsonb_build_array(jsonb_build_object('raw_payload','{"source_event_id":"s1"}'::jsonb,'observation_kind','completed_sale','occurred_at','2025-01-01T00:00:00Z','currency','CAD','amount',100)),'T-stage-1');
 b:=(res->>'batch_id')::uuid; select id into r from public.e10_intake_rows where batch_id=b; insert into st values('b',b),('r',r);
 res:=public.e10_org_stage_intake(o,'csv','vendor','t2.csv','storage://t2','sha-t2',jsonb_build_array(jsonb_build_object('raw_payload','{"source_event_id":"s2"}'::jsonb,'observation_kind','completed_sale','occurred_at','2025-01-01T00:00:00Z','currency','CAD','amount',100)),'T-stage-2');
 b:=(res->>'batch_id')::uuid; select id into r from public.e10_intake_rows where batch_id=b; insert into st values('b2',b),('r2',r);
 perform public.e10_org_resolve_intake_row(o,r,'match_product',p,'rev',null,'T-res-2');
 perform public.e10_org_commit_intake(o,b,(public.e10_org_intake_review_state(o,b)->>'review_revision')::bigint,'T-commit-2');
 insert into st select 'obs',id from public.e10_market_observations where intake_row_id=r;
 res:=public.e10_org_record_commercial_event_v2(o,'listing_created',1,'inventory_item','c-item-a','2025-01-01T00:00:00Z','exact','manual',null,'ref','src-1','corr',null,'operator_asserted','{"listing_id":"l","channel":"c"}',null,'{}','T-ev-1');
 insert into st values('ev',(res->>'event_id')::uuid);
end $$;
\echo '--- org B user (member of B with all caps) attacking org A ids'
select pg_temp.as_b();
set local role authenticated;
select pg_temp.try('P1 resolve orgA row with p_org=B', $q$select public.e10_org_resolve_intake_row(org_b,(select v from st where k='r'),'match_product',prod_b,'x',null,'T-b-1')::text from fx$q$);
select pg_temp.try('P2 resolve orgA row with p_org=A', $q$select public.e10_org_resolve_intake_row(org_a,(select v from st where k='r'),'match_product',prod_a,'x',null,'T-b-2')::text from fx$q$);
select pg_temp.try('P3 review_state orgA batch p_org=B', $q$select public.e10_org_intake_review_state(org_b,(select v from st where k='b'))::text from fx$q$);
select pg_temp.try('P4 commit orgA batch p_org=B', $q$select public.e10_org_commit_intake(org_b,(select v from st where k='b'),0,'T-b-4')::text from fx$q$);
select pg_temp.try('P5 commit_corrected orgA batch p_org=B', $q$select public.e10_org_commit_corrected_intake(org_b,(select v from st where k='b'),0,'[]','T-b-5')::text from fx$q$);
select pg_temp.try('P6 stage_corrected with orgA predecessor', $q$select public.e10_org_stage_corrected_intake(org_b,(select v from st where k='b2'),'manual',null,null,null,'fp',jsonb_build_array(jsonb_build_object('raw_payload','{}'::jsonb,'observation_kind','asking_price','occurred_at','2025-01-01T00:00:00Z','currency','CAD','amount',1)),'T-b-6')::text from fx$q$);
select pg_temp.try('P7 orgB resolve own-org nonexistent row with orgA product target', $q$select public.e10_org_resolve_intake_row(org_b,gen_random_uuid(),'match_product',prod_a,'x',null,'T-b-7')::text from fx$q$);
select pg_temp.try('P8 orgB v2 event causation=orgA event', $q$select public.e10_org_record_commercial_event_v2(org_b,'listing_created',1,'inventory_item','c-item-b','2025-01-01T00:00:00Z','exact','manual',null,'ref','src-b','corr',(select v from st where k='ev'),'operator_asserted','{"listing_id":"l","channel":"c"}',null,'{}','T-b-8')::text from fx$q$);
select pg_temp.try('P9 orgB v2 correction corrects=orgA event', $q$select public.e10_org_record_commercial_event_v2(org_b,'correction',1,'inventory_item','c-item-b','2025-01-01T00:00:00Z','exact','manual',null,'ref','src-b2','corr',null,'operator_asserted','{"reason":"x"}',(select v from st where k='ev'),'{}','T-b-9')::text from fx$q$);
select pg_temp.try('P10 orgB v1 event on orgA subject', $q$select public.e10_org_record_commercial_event(org_b,'listing_created','inventory_item','c-item-a','2025-01-01T00:00:00Z','manual','ref','{"listing_id":"l","channel":"c"}',null,'{}','T-b-10')::text from fx$q$);
select pg_temp.try('P11 orgB stage_intake with p_org=A', $q$select public.e10_org_stage_intake(org_a,'manual',null,null,null,'fp',jsonb_build_array(jsonb_build_object('raw_payload','{}'::jsonb,'observation_kind','asking_price','occurred_at','2025-01-01T00:00:00Z','currency','CAD','amount',1)),'T-b-11')::text from fx$q$);
\echo '--- direct table/view access as authenticated'
select pg_temp.try('Q1 select market_observations', $q$select count(*)::text from public.e10_market_observations$q$);
select pg_temp.try('Q2 select current view', $q$select count(*)::text from public.e10_current_market_observations$q$);
select pg_temp.try('Q3 select intake_batches', $q$select count(*)::text from public.e10_intake_batches$q$);
select pg_temp.try('Q4 select commercial_events', $q$select count(*)::text from public.e10_commercial_events$q$);
select pg_temp.try('Q5 select event schemas', $q$select count(*)::text from public.e10_commercial_event_schemas$q$);
select pg_temp.try('Q6 select reconciliation cases', $q$select count(*)::text from public.e10_customer_transaction_reconciliation_cases$q$);
select pg_temp.try('Q7 select source claims', $q$select count(*)::text from public.e10_customer_transaction_source_claims$q$);
select pg_temp.try('Q8 select supersessions', $q$select count(*)::text from public.e10_market_observation_supersessions$q$);
select pg_temp.try('Q9 select stage_replays', $q$select count(*)::text from public.e10_intake_stage_replays$q$);
select pg_temp.try('Q10 select corrected commits', $q$select count(*)::text from public.e10_corrected_intake_commits$q$);
select pg_temp.try('Q11 select activity source components', $q$select count(*)::text from public.e10_customer_activity_source_components$q$);
select pg_temp.try('Q12 call service-only _x5b resolve directly', $q$select public._e10_org_resolve_intake_row_x5b(org_a,(select v from st where k='r'),'reject',null,'x',null,'T-b-12')::text from fx$q$);
select pg_temp.try('Q13 call service-only _x5d commit directly', $q$select public._e10_org_commit_intake_x5d(org_a,(select v from st where k='b'),0,'T-b-13')::text from fx$q$);
select pg_temp.try('Q14 call x6d3 impl directly', $q$select public.e10_org_decide_customer_transaction_reconciliation_x6d3_impl(org_b,gen_random_uuid(),0,'reject',null,null,null,'x','{}','T-b-14')::text from fx$q$);
\echo '--- anon'
set local role anon;
select pg_temp.try('Q15 anon stage_intake', $q$select public.e10_org_stage_intake(org_a,'manual',null,null,null,'fp','[]','T-anon')::text from fx$q$);
select pg_temp.try('Q16 anon record event v2', $q$select public.e10_org_record_commercial_event_v2(org_a,'listing_created',1,'inventory_item','c-item-a',now(),'exact','manual',null,null,null,null,null,'operator_asserted','{}',null,'{}','T-anon2')::text from fx$q$);
select pg_temp.try('Q17 anon open reconciliation', $q$select public.e10_org_open_customer_transaction_reconciliation(org_a,'manual',null,'e','c','CAD',1,null,null,'{}','T-anon3')::text from fx$q$);
reset role;
\echo '--- X6d3: org B on org A reconciliation case / native source_kind as authenticated'
select pg_temp.as_a(); set local role authenticated;
select pg_temp.try('R1 open reconciliation as authenticated with native source_kind', $q$select public.e10_org_open_customer_transaction_reconciliation(org_a,'native',null,'e1','c1','CAD',1,null,null,'{}','T-r-1')::text from fx$q$);
select pg_temp.try('R2 open reconciliation import', $q$select public.e10_org_open_customer_transaction_reconciliation(org_a,'import','shop','e1','c1','CAD',1,null,null,'{}','T-r-2')::text from fx$q$);
select pg_temp.try('R3 open again same source diff key', $q$select public.e10_org_open_customer_transaction_reconciliation(org_a,'import','shop','e1','c1','CAD',2,null,null,'{}','T-r-3')::text from fx$q$);
select pg_temp.try('R3b open same component, different event id', $q$select public.e10_org_open_customer_transaction_reconciliation(org_a,'import','shop','e2','c1','CAD',2,null,null,'{}','T-r-3b')::text from fx$q$);
select pg_temp.try('R3c open same source with whitespace in event id', $q$select public.e10_org_open_customer_transaction_reconciliation(org_a,'import','shop',' e1','c1 ','CAD',2,null,null,'{}','T-r-3c')::text from fx$q$);
select pg_temp.try('R3d open same source with connection whitespace', $q$select public.e10_org_open_customer_transaction_reconciliation(org_a,'import','shop ','e1','c1','CAD',2,null,null,'{}','T-r-3d')::text from fx$q$);
select pg_temp.try('R4 open all-null amounts', $q$select public.e10_org_open_customer_transaction_reconciliation(org_a,'import','shop','e9','c9','CAD',null,null,null,'{}','T-r-4')::text from fx$q$);
insert into st select 'case',id from public.e10_customer_transaction_reconciliation_cases where organization_id=(select org_a from fx) and source_event_id='e1' and source_component_id='c1';
select pg_temp.as_b(); 
select pg_temp.try('R5 orgB decides orgA case p_org=B', $q$select public.e10_org_decide_customer_transaction_reconciliation(org_b,(select v from st where k='case'),0,'reject',null,null,null,'x','{}','T-r-5')::text from fx$q$);
select pg_temp.try('R6 orgB decides orgA case p_org=A', $q$select public.e10_org_decide_customer_transaction_reconciliation(org_a,(select v from st where k='case'),0,'reject',null,null,null,'x','{}','T-r-6')::text from fx$q$);
select pg_temp.try('R7 orgB bind activity random', $q$select public.e10_org_bind_customer_activity_source_component(org_b,gen_random_uuid(),'c','r','T-r-7')::text from fx$q$);
reset role;
rollback;
