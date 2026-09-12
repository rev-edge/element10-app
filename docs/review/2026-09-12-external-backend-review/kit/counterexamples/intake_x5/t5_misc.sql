\set ON_ERROR_STOP 0
\pset format unaligned
\pset tuples_only on
begin;
\i fixture.sql
create temp table st(k text primary key, v uuid); grant all on st to public;
select pg_temp.as_b();
do $$ declare o uuid; p uuid; res jsonb; b uuid; r uuid; begin
 select org_b,prod_b into o,p from fx;
 res:=public.e10_org_stage_intake(o,'manual',null,null,null,'fpB',jsonb_build_array(jsonb_build_object('raw_payload','{}'::jsonb,'observation_kind','asking_price','occurred_at','2025-01-01T00:00:00Z','currency','CAD','amount',1)),'B-stage');
 b:=(res->>'batch_id')::uuid; select id into r from public.e10_intake_rows where batch_id=b;
 res:=public.e10_org_resolve_intake_row(o,r,'match_product',p,'rev',null,'B-res'); insert into st values('decB',(res->>'decision_id')::uuid);
end $$;
select pg_temp.as_a();
do $$ declare o uuid; p uuid; res jsonb; b uuid; r uuid; begin
 select org_a,prod_a into o,p from fx;
 res:=public.e10_org_stage_intake(o,'manual',null,null,null,'fpA',jsonb_build_array(jsonb_build_object('raw_payload','{}'::jsonb,'observation_kind','asking_price','occurred_at','2025-01-01T00:00:00Z','currency','CAD','amount',1),jsonb_build_object('raw_payload','{}'::jsonb,'observation_kind','asking_price','occurred_at','2025-01-01T00:00:00Z','currency','CAD','amount',2)),'A-stage');
 b:=(res->>'batch_id')::uuid; insert into st values('bA',b);
 select id into r from public.e10_intake_rows where batch_id=b and source_row_number=1; insert into st values('rA1',r);
 select id into r from public.e10_intake_rows where batch_id=b and source_row_number=2; insert into st values('rA2',r);
 res:=public.e10_org_resolve_intake_row(o,(select v from st where k='rA1'),'match_product',p,'rev',null,'A-res-1'); insert into st values('decA1',(res->>'decision_id')::uuid);
end $$;
set local role authenticated;
select pg_temp.try('X1 corrects_decision from org B', $q$select public.e10_org_resolve_intake_row(org_a,(select v from st where k='rA1'),'reject',null,'x',(select v from st where k='decB'),'A-res-x1')::text from fx$q$);
select pg_temp.try('X2 corrects_decision of another row same org', $q$select public.e10_org_resolve_intake_row(org_a,(select v from st where k='rA2'),'reject',null,'x',(select v from st where k='decA1'),'A-res-x2')::text from fx$q$);
select pg_temp.try('X3 corrects_decision random', $q$select public.e10_org_resolve_intake_row(org_a,(select v from st where k='rA1'),'reject',null,'x',gen_random_uuid(),'A-res-x3')::text from fx$q$);
select pg_temp.try('X4 valid correction of own decision', $q$select public.e10_org_resolve_intake_row(org_a,(select v from st where k='rA1'),'reject',null,'x',(select v from st where k='decA1'),'A-res-x4')::text from fx$q$);
select pg_temp.try('X5 resolve key reuse across rows (same org key namespace)', $q$select public.e10_org_resolve_intake_row(org_a,(select v from st where k='rA2'),'reject',null,'x',null,'A-res-x4')::text from fx$q$);
select pg_temp.try('X6 match_catalog_variant with random id', $q$select public.e10_org_resolve_intake_row(org_a,(select v from st where k='rA2'),'match_catalog_variant',gen_random_uuid(),'x',null,'A-res-x6')::text from fx$q$);
select pg_temp.try('X7 match_catalog_variant with real shared variant', $q$select public.e10_org_resolve_intake_row(org_a,(select v from st where k='rA2'),'match_catalog_variant',(select id from public.e10_catalog_variants limit 1),'x',null,'A-res-x7')::text from fx$q$);
reset role;
select 'review state: '||public.e10_org_intake_review_state(org_a,(select v from st where k='bA'))::text from fx;
\echo '--- commit key namespace collision: ordinary commit using key corrected:X then corrected commit with key X'
select pg_temp.try('X8 ordinary commit with key "corrected:foo"', $q$select public.e10_org_commit_intake(org_a,(select v from st where k='bA'),(public.e10_org_intake_review_state(org_a,(select v from st where k='bA'))->>'review_revision')::bigint,'corrected:foo')::text from fx$q$);
rollback;
