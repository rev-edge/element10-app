\set ON_ERROR_STOP 0
\pset format unaligned
\pset tuples_only on
begin;
\i fixture.sql
select pg_temp.as_a();
create temp table st(k text primary key, v uuid); grant all on st to public;
do $$ declare o uuid; p uuid; res jsonb; b uuid; r uuid; r1 uuid; r2 uuid; rev bigint; a uuid; classes jsonb; begin
 select org_a,prod_a into o,p from fx;
 res:=public.e10_org_stage_intake(o,'api','vendor','f2','api://f2','sha-f2',jsonb_build_array(jsonb_build_object('raw_payload','{"source_event_id":"s2"}'::jsonb,'observation_kind','completed_sale','occurred_at','2025-01-02T00:00:00Z','currency','CAD','amount',110)),'L-stage-2');
 b:=(res->>'batch_id')::uuid; select id into r from public.e10_intake_rows where batch_id=b; insert into st values('b1',b);
 perform public.e10_org_resolve_intake_row(o,r,'match_product',p,'rev',null,'L-res-2');
 perform public.e10_org_commit_intake(o,b,(public.e10_org_intake_review_state(o,b)->>'review_revision')::bigint,'L-commit-2');
 select id into a from public.e10_market_observations where intake_row_id=r; insert into st values('R',a);
 -- changed source: two rows, both s2 (vendor duplicated the line)
 res:=public.e10_org_stage_intake(o,'api','vendor','f2','api://f2-v2','sha-f2-v2',jsonb_build_array(
   jsonb_build_object('raw_payload','{"source_event_id":"s2"}'::jsonb,'observation_kind','completed_sale','occurred_at','2025-01-02T00:00:00Z','currency','CAD','amount',111),
   jsonb_build_object('raw_payload','{"source_event_id":"s2"}'::jsonb,'observation_kind','completed_sale','occurred_at','2025-01-02T00:00:00Z','currency','CAD','amount',112)),'L-stage-3');
 b:=(res->>'batch_id')::uuid; insert into st values('b3',b);
 select id into r1 from public.e10_intake_rows where batch_id=b and source_row_number=1; select id into r2 from public.e10_intake_rows where batch_id=b and source_row_number=2;
 perform public.e10_org_resolve_intake_row(o,r1,'match_product',p,'rev',null,'L-res-3a'); perform public.e10_org_resolve_intake_row(o,r2,'match_product',p,'rev',null,'L-res-3b');
 rev:=(public.e10_org_intake_review_state(o,b)->>'review_revision')::bigint;
 classes:=jsonb_build_array(jsonb_build_object('source_row_number',1,'classification','replacement','superseded_observation_id',a,'reason','r'),jsonb_build_object('source_row_number',2,'classification','replacement','superseded_observation_id',a,'reason','r'));
 begin res:=public.e10_org_commit_corrected_intake(o,b,rev,classes,'L-cc-1'); raise notice 'M1 accepted?! %',res; exception when others then raise notice 'M1 double-supersede -> % %',sqlstate,sqlerrm; end;
 raise notice 'M1 state: batch status=%, commits=%, corrected_commits=%, observations for batch=%, supersessions=%',(select status from public.e10_intake_batches where id=b),(select count(*) from public.e10_intake_commits where intake_batch_id=b),(select count(*) from public.e10_corrected_intake_commits where intake_batch_id=b),(select count(*) from public.e10_market_observations where intake_row_id in (r1,r2)),(select count(*) from public.e10_market_observation_supersessions where superseded_observation_id=a);
 -- M1b: pre-existing manual supersession with colliding derived key
 begin perform public.e10_org_correct_market_observation(o,a,'completed_sale','product',p,'2025-01-02T00:00:00Z','CAD',1,null,null,'{}','collide','corrected-commit:L-cc-9:1'); exception when others then raise notice 'prep -> % %',sqlstate,sqlerrm; end;
 raise notice 'after manual correction of R, supersessions from R=%',(select count(*) from public.e10_market_observation_supersessions where superseded_observation_id=a);
 -- now row 2 'new' (duplicate_reviewed) and row1 replacement of R (already superseded) -> should be 55000 not current
 classes:=jsonb_build_array(jsonb_build_object('source_row_number',1,'classification','replacement','superseded_observation_id',a,'reason','r'),jsonb_build_object('source_row_number',2,'classification','new','reason','r','duplicate_reviewed',true));
 begin res:=public.e10_org_commit_corrected_intake(o,b,rev,classes,'L-cc-9'); raise notice 'M1b accepted?! %',res; exception when others then raise notice 'M1b -> % %',sqlstate,sqlerrm; end;
end $$;
\echo '--- O. stage_corrected_intake retrofit of an existing key'
select pg_temp.try('O3 replay ordinary committed batch key as corrected (retrofit committed)', $q$select public.e10_org_stage_corrected_intake(org_a,(select v from st where k='b1'),'api','vendor','f2','api://f2','sha-f2',jsonb_build_array(jsonb_build_object('raw_payload','{"source_event_id":"s2"}'::jsonb,'observation_kind','completed_sale','occurred_at','2025-01-02T00:00:00Z','currency','CAD','amount',110)),'L-stage-2')::text from fx$q$);
select pg_temp.try('O4 durable exact replay of b1 payload with new key, as corrected of b1 (self-supersede?)', $q$select public.e10_org_stage_corrected_intake(org_a,(select v from st where k='b1'),'api','vendor','f2','api://f2','sha-f2',jsonb_build_array(jsonb_build_object('raw_payload','{"source_event_id":"s2"}'::jsonb,'observation_kind','completed_sale','occurred_at','2025-01-02T00:00:00Z','currency','CAD','amount',110)),'L-sc-4')::text from fx$q$);
select pg_temp.try('O5 corrected manual batch, predecessor b1', $q$select public.e10_org_stage_corrected_intake(org_a,(select v from st where k='b1'),'manual',null,null,null,'fp-o5',jsonb_build_array(jsonb_build_object('raw_payload','{}'::jsonb,'observation_kind','asking_price','occurred_at','2025-01-01T00:00:00Z','currency','CAD','amount',1)),'L-sc-5')::text from fx$q$);
select pg_temp.try('O6 same key L-sc-5 with different predecessor b3 (validated, not committed)', $q$select public.e10_org_stage_corrected_intake(org_a,(select v from st where k='b3'),'manual',null,null,null,'fp-o5',jsonb_build_array(jsonb_build_object('raw_payload','{}'::jsonb,'observation_kind','asking_price','occurred_at','2025-01-01T00:00:00Z','currency','CAD','amount',1)),'L-sc-5')::text from fx$q$);
select pg_temp.try('O7 ordinary stage with key L-sc-5 replays corrected batch', $q$select public.e10_org_stage_intake(org_a,'manual',null,null,null,'fp-o5',jsonb_build_array(jsonb_build_object('raw_payload','{}'::jsonb,'observation_kind','asking_price','occurred_at','2025-01-01T00:00:00Z','currency','CAD','amount',1)),'L-sc-5')::text from fx$q$);
\echo '--- batch status mutability as service_role: committed -> validated and re-commit?'
set local role service_role;
select pg_temp.try('S1 flip committed b1 to validated', $q$update public.e10_intake_batches set status='validated' where id=(select v from st where k='b1') returning status$q$);
reset role;
select pg_temp.as_a();
select pg_temp.try('S2 commit b1 again with new key', $q$select public.e10_org_commit_intake(org_a,(select v from st where k='b1'),(public.e10_org_intake_review_state(org_a,(select v from st where k='b1'))->>'review_revision')::bigint,'L-commit-2b')::text from fx$q$);
rollback;
