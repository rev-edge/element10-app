\set ON_ERROR_STOP 0
begin;
\i fixture.sql
\i common_post.sql
set role authenticated;
select pg_temp.as_user('u1');
select pg_temp.post_tx('t1','c1',100,'2026-01-05',null,'web');
select pg_temp.post_tx('t2','c2',40,'2026-01-06',null,'web');
select pg_temp.post_tx('t3','c1',10,'2026-01-07',null,'store');
\echo === E4a merge c1 -> c2 : summary rows
select pg_temp.try($$public.e10_org_decide_customer_resolution(pg_temp.i('org'),pg_temp.i('c1'),pg_temp.i('c2'),0,0,0,'merge','operator_review','{}'::uuid[],'dupe','{}'::jsonb,'e4-merge')$$) merge;
select x->>'effective_customer_id' cust, x->>'known_official_subtotal' known, x->>'line_count' lines from public.e10_org_customer_spend_summary(pg_temp.i('org'),'2026-01-01','2026-03-01','2026-09-01','USD','UTC',1,null,null,null,null,null,null,null,null,null,100,null,null,null) j, jsonb_array_elements(j->'items') x;
\echo --- summary filtered by merged source c1 should be denied
select pg_temp.try($$public.e10_org_customer_spend_summary(pg_temp.i('org'),'2026-01-01','2026-03-01','2026-09-01','USD','UTC',1,pg_temp.i('c1'),null,null,null,null,null,null,null,null,100,null,null,null)$$) summary_for_merged_source;
\echo --- find_customers hides merged source
select * from public.e10_org_find_customers(pg_temp.i('org'),'ali',10);
\echo === E4b selective attribution of t3 to c3 while c1 merged into c2; then split c1
select pg_temp.try($$public.e10_org_decide_customer_transaction_attribution(pg_temp.i('org'),pg_temp.i('t3'),0,pg_temp.i('c3'),'belongs to c3','{}'::jsonb,'e4-attr-t3')$$) attr_t3;
select pg_temp.try($$public.e10_org_decide_customer_transaction_attribution(pg_temp.i('org'),pg_temp.i('t1'),0,pg_temp.i('c1'),'to merged source','{}'::jsonb,'e4-attr-t1-src')$$) attr_to_merged_source;
select pg_temp.try($$public.e10_org_decide_customer_resolution(pg_temp.i('org'),pg_temp.i('c1'),null,0,null,1,'split','operator_review','{}'::uuid[],'undo','{}'::jsonb,'e4-split')$$) split;
select x->>'effective_customer_id' cust, x->>'known_official_subtotal' known, x->>'line_count' lines from public.e10_org_customer_spend_summary(pg_temp.i('org'),'2026-01-01','2026-03-01','2026-09-01','USD','UTC',1,null,null,null,null,null,null,null,null,null,100,null,null,null) j, jsonb_array_elements(j->'items') x order by 2;
select sum((x->>'known_official_subtotal')::numeric) sum_rows, j->'full_cohort_totals' totals from public.e10_org_customer_spend_summary(pg_temp.i('org'),'2026-01-01','2026-03-01','2026-09-01','USD','UTC',1,null,null,null,null,null,null,null,null,null,100,null,null,null) j, jsonb_array_elements(j->'items') x group by 2;
\echo === E4c unattribute t1 -> disappears from official, counted in diagnostics
select pg_temp.try($$public.e10_org_decide_customer_transaction_attribution(pg_temp.i('org'),pg_temp.i('t1'),0,null,'unknown buyer','{}'::jsonb,'e4-unattr-t1')$$) unattr;
select j->'full_cohort_totals' totals, j->'authorized_data_diagnostics' diag from public.e10_org_customer_spend_summary(pg_temp.i('org'),'2026-01-01','2026-03-01','2026-09-01','USD','UTC',1,null,null,null,null,null,null,null,null,null,100,null,null,null) j;
\echo === E4d merge c1->c2 then a draft for c1 (merged source) rejected? and record activity for c1?
select pg_temp.try($$public.e10_org_decide_customer_resolution(pg_temp.i('org'),pg_temp.i('c1'),pg_temp.i('c2'),0,0,2,'merge','operator_review','{}'::uuid[],'dupe again','{}'::jsonb,'e4-merge2')$$) merge2;
select pg_temp.try($$public.e10_org_create_customer_transaction_draft(pg_temp.i('org'),pg_temp.i('c1'),'USD','2026-01-08','exact','draft for merged',jsonb_build_array(jsonb_build_object('purchase_kind','retail','capture_source','manual','source_line_id','e4-m','quantity',1,'merchandise_gross',1)),'e4-d-merged')$$) draft_for_merged_source;
select pg_temp.try($$public.e10_org_record_customer_activity(pg_temp.i('org'),'retail',pg_temp.i('c1'),null,null,null,null,1,5,0,null,null,'USD',null,'2026-01-08'::timestamptz,'exact','manual',null,null,'e4-act-src','{}'::jsonb,'operator_asserted','e4-act')$$) activity_for_merged_source;
\echo --- archive merged participant
select pg_temp.try($$public.e10_org_update_customer(pg_temp.i('org'),pg_temp.i('c2'),0,'Bob','archived','e4-arch')$$) archive_merge_target;
rollback;
