\set ON_ERROR_STOP 0
\pset format unaligned
\pset tuples_only on
begin;
\i fixture.sql
select pg_temp.as_a();
create temp table st(k text primary key, v uuid); grant all on st to public;
do $$ declare o uuid; p uuid; res jsonb; b uuid; r uuid; begin
 select org_a,prod_a into o,p from fx;
 res:=public.e10_org_stage_intake(o,'csv','vendor','f1.csv','storage://f1','sha-f1',jsonb_build_array(jsonb_build_object('raw_payload','{"source_event_id":"s1"}'::jsonb,'observation_kind','completed_sale','occurred_at','2025-01-01T00:00:00Z','currency','CAD','amount',100)),'L-stage-1');
 b:=(res->>'batch_id')::uuid; select id into r from public.e10_intake_rows where batch_id=b;
 perform public.e10_org_resolve_intake_row(o,r,'match_product',p,'rev',null,'L-res-1');
 perform public.e10_org_commit_intake(o,b,(public.e10_org_intake_review_state(o,b)->>'review_revision')::bigint,'L-commit-1');
 insert into st select 'A',id from public.e10_market_observations where intake_row_id=r;
 insert into st values('b1',b);
 -- a second committed import to serve as reimport replacement
 res:=public.e10_org_stage_intake(o,'api','vendor','f2','api://f2','sha-f2',jsonb_build_array(jsonb_build_object('raw_payload','{"source_event_id":"s2"}'::jsonb,'observation_kind','completed_sale','occurred_at','2025-01-02T00:00:00Z','currency','CAD','amount',110)),'L-stage-2');
 b:=(res->>'batch_id')::uuid; select id into r from public.e10_intake_rows where batch_id=b;
 perform public.e10_org_resolve_intake_row(o,r,'match_product',p,'rev',null,'L-res-2');
 perform public.e10_org_commit_intake(o,b,(public.e10_org_intake_review_state(o,b)->>'review_revision')::bigint,'L-commit-2');
 insert into st select 'R',id from public.e10_market_observations where intake_row_id=r;
end $$;
\echo '--- I. fork: correct A twice with different keys'
select pg_temp.try('I1 correct A', $q$select (public.e10_org_correct_market_observation(org_a,(select v from st where k='A'),'completed_sale','product',prod_a,'2025-01-01T00:00:00Z','CAD',101,null,'ref','{}','fix','L-corr-1')->>'observation_id') from fx$q$);
insert into st select 'B',(select replacement_observation_id from public.e10_market_observation_supersessions where superseded_observation_id=(select v from st where k='A'));
select pg_temp.try('I2 correct A again (fork)', $q$select public.e10_org_correct_market_observation(org_a,(select v from st where k='A'),'completed_sale','product',prod_a,'2025-01-01T00:00:00Z','CAD',102,null,'ref','{}','fix2','L-corr-2')::text from fx$q$);
select pg_temp.try('I3 reimport A->R (fork via reimport)', $q$select public.e10_org_reconcile_market_observation_reimport(org_a,(select v from st where k='A'),(select v from st where k='R'),'why','L-reimp-1')::text from fx$q$);
\echo '--- J. cycles: B->R ok; then R->A must be a cycle; R->B cycle; self'
select pg_temp.try('J1 reimport B->R', $q$select public.e10_org_reconcile_market_observation_reimport(org_a,(select v from st where k='B'),(select v from st where k='R'),'why','L-reimp-2')::text from fx$q$);
select pg_temp.try('J2 reimport R->A (cycle, A is original intake obs)', $q$select public.e10_org_reconcile_market_observation_reimport(org_a,(select v from st where k='R'),(select v from st where k='A'),'why','L-reimp-3')::text from fx$q$);
select pg_temp.try('J3 reimport R->R self', $q$select public.e10_org_reconcile_market_observation_reimport(org_a,(select v from st where k='R'),(select v from st where k='R'),'why','L-reimp-4')::text from fx$q$);
select pg_temp.try('J4 reimport R->B (B is manual, not reimport)', $q$select public.e10_org_reconcile_market_observation_reimport(org_a,(select v from st where k='R'),(select v from st where k='B'),'why','L-reimp-5')::text from fx$q$);
\echo '--- K. original row unchanged; append-only even as postgres/service_role'
select 'A amount='||amount||' kind='||observation_kind from public.e10_market_observations where id=(select v from st where k='A');
select pg_temp.try('K1 update observation as postgres', $q$update public.e10_market_observations set amount=1 where id=(select v from st where k='A') returning 'updated'$q$);
select pg_temp.try('K2 delete supersession as postgres', $q$delete from public.e10_market_observation_supersessions where superseded_observation_id=(select v from st where k='A') returning 'deleted'$q$);
set local role service_role;
select pg_temp.try('K3 update observation as service_role', $q$update public.e10_market_observations set amount=1 where id=(select v from st where k='A') returning 'updated'$q$);
select pg_temp.try('K4 delete observation as service_role', $q$delete from public.e10_market_observations where id=(select v from st where k='A') returning 'deleted'$q$);
select pg_temp.try('K5 update intake_rows raw_payload as service_role', $q$update public.e10_intake_rows set raw_payload='{}' where batch_id=(select v from st where k='b1') returning 'updated'$q$);
select pg_temp.try('K6 update intake_batches status as service_role (no append-only trg on batches)', $q$update public.e10_intake_batches set status='rejected' where id=(select v from st where k='b1') returning 'updated:'||status$q$);
select pg_temp.try('K7 delete intake_commits as service_role', $q$delete from public.e10_intake_commits where intake_batch_id=(select v from st where k='b1') returning 'deleted'$q$);
reset role;
\echo '--- L. cross-org: org B user on org A observations'
select pg_temp.as_b();
select pg_temp.try('L1 orgB corrects orgA obs (p_org=B)', $q$select public.e10_org_correct_market_observation(org_b,(select v from st where k='R'),'completed_sale','product',prod_b,'2025-01-01T00:00:00Z','CAD',1,null,'ref','{}','x','L-x-1')::text from fx$q$);
select pg_temp.try('L2 orgB corrects orgA obs (p_org=A)', $q$select public.e10_org_correct_market_observation(org_a,(select v from st where k='R'),'completed_sale','product',prod_a,'2025-01-01T00:00:00Z','CAD',1,null,'ref','{}','x','L-x-2')::text from fx$q$);
select pg_temp.try('L3 orgB reimport with orgA ids', $q$select public.e10_org_reconcile_market_observation_reimport(org_b,(select v from st where k='R'),(select v from st where k='A'),'why','L-x-3')::text from fx$q$);
select pg_temp.try('L4 orgB correct with product from org A as target', $q$select public.e10_org_correct_market_observation(org_b,gen_random_uuid(),'completed_sale','product',prod_a,'2025-01-01T00:00:00Z','CAD',1,null,'ref','{}','x','L-x-4')::text from fx$q$);
select pg_temp.as_a();
\echo '--- M. corrected commit atomicity: bad classifications leave no partial state'
do $$ declare o uuid; p uuid; res jsonb; b uuid; r1 uuid; r2 uuid; rev bigint; a uuid; classes jsonb; begin
 select org_a,prod_a into o,p from fx; select v into a from st where k='R';
 -- stage a changed-source version of f2 (api vendor f2) with two rows
 res:=public.e10_org_stage_intake(o,'api','vendor','f2','api://f2-v2','sha-f2-v2',jsonb_build_array(
   jsonb_build_object('raw_payload','{"source_event_id":"s2"}'::jsonb,'observation_kind','completed_sale','occurred_at','2025-01-02T00:00:00Z','currency','CAD','amount',111),
   jsonb_build_object('raw_payload','{"source_event_id":"s3"}'::jsonb,'observation_kind','completed_sale','occurred_at','2025-01-03T00:00:00Z','currency','CAD','amount',5)),'L-stage-3');
 b:=(res->>'batch_id')::uuid; raise notice 'stage3 supersedes=%',res->>'supersedes_batch_id';
 select id into r1 from public.e10_intake_rows where batch_id=b and source_row_number=1; select id into r2 from public.e10_intake_rows where batch_id=b and source_row_number=2;
 perform public.e10_org_resolve_intake_row(o,r1,'match_product',p,'rev',null,'L-res-3a'); perform public.e10_org_resolve_intake_row(o,r2,'match_product',p,'rev',null,'L-res-3b');
 rev:=(public.e10_org_intake_review_state(o,b)->>'review_revision')::bigint; insert into st values('b3',b);
 -- M1: both rows claim to replace the same observation R -> unique(org,superseded) violation on second link
 classes:=jsonb_build_array(jsonb_build_object('source_row_number',1,'classification','replacement','superseded_observation_id',a,'reason','r'),jsonb_build_object('source_row_number',2,'classification','replacement','superseded_observation_id',a,'reason','r'));
 begin res:=public.e10_org_commit_corrected_intake(o,b,rev,classes,'L-cc-1'); raise notice 'M1 accepted?! %',res; exception when others then raise notice 'M1 -> % %',sqlstate,sqlerrm; end;
 raise notice 'M1 state: batch status=%, commits=%, corrected_commits=%, observations for batch=%',(select status from public.e10_intake_batches where id=b),(select count(*) from public.e10_intake_commits where intake_batch_id=b),(select count(*) from public.e10_corrected_intake_commits where intake_batch_id=b),(select count(*) from public.e10_market_observations where intake_row_id in (r1,r2));
 -- M2: row1 'new' with source_event_id s2 already observed -> stable_source_event_requires_replacement
 classes:=jsonb_build_array(jsonb_build_object('source_row_number',1,'classification','new','reason','r','duplicate_reviewed',true),jsonb_build_object('source_row_number',2,'classification','new','reason','r','duplicate_reviewed',true));
 begin res:=public.e10_org_commit_corrected_intake(o,b,rev,classes,'L-cc-2'); raise notice 'M2 accepted?! %',res; exception when others then raise notice 'M2 -> % %',sqlstate,sqlerrm; end;
 -- M3: replacement superseded_observation_id belongs to other org / random -> not current
 classes:=jsonb_build_array(jsonb_build_object('source_row_number',1,'classification','replacement','superseded_observation_id',gen_random_uuid(),'reason','r'),jsonb_build_object('source_row_number',2,'classification','new','reason','r','duplicate_reviewed',true));
 begin res:=public.e10_org_commit_corrected_intake(o,b,rev,classes,'L-cc-3'); raise notice 'M3 accepted?! %',res; exception when others then raise notice 'M3 -> % %',sqlstate,sqlerrm; end;
 -- M3b: replacement targets B (manual correction obs, already superseded by R via J1) 
 classes:=jsonb_build_array(jsonb_build_object('source_row_number',1,'classification','replacement','superseded_observation_id',(select v from st where k='B'),'reason','r'),jsonb_build_object('source_row_number',2,'classification','new','reason','r','duplicate_reviewed',true));
 begin res:=public.e10_org_commit_corrected_intake(o,b,rev,classes,'L-cc-3b'); raise notice 'M3b accepted?! %',res; exception when others then raise notice 'M3b -> % %',sqlstate,sqlerrm; end;
 -- M4: replacement of R where row1 source_event_id s2 matches -> OK; row2 new; but first pre-stage a manual supersession key collision: correct_market_observation with key 'corrected-commit:L-cc-4:2'? not applicable (row2 is new). Do valid commit after failures with same key L-cc-1 (retry after failure)
 classes:=jsonb_build_array(jsonb_build_object('source_row_number',1,'classification','replacement','superseded_observation_id',a,'reason','r'),jsonb_build_object('source_row_number',2,'classification','new','reason','r','duplicate_reviewed',true));
 begin res:=public.e10_org_commit_corrected_intake(o,b,rev,classes,'L-cc-1'); raise notice 'M4 retry same key after failure -> replay=% obs=%',res->>'replay',res->>'observation_count'; exception when others then raise notice 'M4 -> % %',sqlstate,sqlerrm; end;
 raise notice 'M4 state: batch status=%, commits=%, corrected_commits=%, supersessions from R=%',(select status from public.e10_intake_batches where id=b),(select count(*) from public.e10_intake_commits where intake_batch_id=b),(select count(*) from public.e10_corrected_intake_commits where intake_batch_id=b),(select count(*) from public.e10_market_observation_supersessions where superseded_observation_id=a);
 -- M5: replay with same key & classes; and replay with different classes
 begin res:=public.e10_org_commit_corrected_intake(o,b,rev,classes,'L-cc-1'); raise notice 'M5 replay -> replay=%',res->>'replay'; exception when others then raise notice 'M5 -> % %',sqlstate,sqlerrm; end;
 begin res:=public.e10_org_commit_corrected_intake(o,b,rev+1,classes,'L-cc-1'); raise notice 'M5b accepted?! %',res; exception when others then raise notice 'M5b diff revision same key -> % %',sqlstate,sqlerrm; end;
end $$;
\echo '--- N. lineage chain now: A->B->R->(new). Verify current set and that old rows untouched'
select k, (select amount from public.e10_market_observations where id=v) amt, exists(select 1 from public.e10_current_market_observations c where c.id=v) is_current from st where k in ('A','B','R');
\echo '--- O. stage_corrected_intake edge cases'
select pg_temp.try('O1 predecessor from org B', $q$select public.e10_org_stage_corrected_intake(org_a,(select id from public.e10_intake_batches where organization_id=org_b limit 1),'manual',null,null,null,'fp-o1',jsonb_build_array(jsonb_build_object('raw_payload','{}'::jsonb,'observation_kind','asking_price','occurred_at','2025-01-01T00:00:00Z','currency','CAD','amount',1)),'L-sc-1')::text from fx$q$);
select pg_temp.try('O2 predecessor random uuid', $q$select public.e10_org_stage_corrected_intake(org_a,gen_random_uuid(),'manual',null,null,null,'fp-o2',jsonb_build_array(jsonb_build_object('raw_payload','{}'::jsonb,'observation_kind','asking_price','occurred_at','2025-01-01T00:00:00Z','currency','CAD','amount',1)),'L-sc-2')::text from fx$q$);
select pg_temp.try('O3 predecessor = committed b1, replaying key of an existing committed ordinary batch (L-stage-1 key) -> retrofit?', $q$select public.e10_org_stage_corrected_intake(org_a,(select v from st where k='b1'),'csv','vendor','f1.csv','storage://f1','sha-f1',jsonb_build_array(jsonb_build_object('raw_payload','{"source_event_id":"s1"}'::jsonb,'observation_kind','completed_sale','occurred_at','2025-01-01T00:00:00Z','currency','CAD','amount',100)),'L-stage-1')::text from fx$q$);
select pg_temp.try('O4 corrected batch superseding b1 using durable identity (exact replay of b1 payload under new key)', $q$select public.e10_org_stage_corrected_intake(org_a,(select v from st where k='b1'),'csv','vendor','f1.csv','storage://f1','sha-f1',jsonb_build_array(jsonb_build_object('raw_payload','{"source_event_id":"s1"}'::jsonb,'observation_kind','completed_sale','occurred_at','2025-01-01T00:00:00Z','currency','CAD','amount',100)),'L-sc-4')::text from fx$q$);
rollback;
