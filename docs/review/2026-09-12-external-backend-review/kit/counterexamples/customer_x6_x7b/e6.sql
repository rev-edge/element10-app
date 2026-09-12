\set ON_ERROR_STOP 0
begin;
\i fixture.sql
\i common_post.sql
set role authenticated;
select pg_temp.as_user('u1');
select pg_temp.post_tx('t1','c1',100,'2026-01-05','L1','web');
select pg_temp.post_tx('t2','c1',200,'2026-01-06','L2','web');
select pg_temp.post_tx('t3','c1',300,'2026-01-07',null,'web');
select pg_temp.post_tx('t4','c2',50,'2026-01-08','L1','web');
\echo === E6a admin grants u3 role location financial access on L1
select pg_temp.as_user('uadmin');
select pg_temp.try($$public.e10_org_set_location_financial_access(pg_temp.i('org'),pg_temp.i('L1'),pg_temp.i('r3'),null::timestamptz,true,'grant','{}'::jsonb,'e6-grant')$$) grant_l1;
select pg_temp.as_user('u3');
\echo --- u3 contributions/summary/grid (expect only L1 lines: 100 and 50)
select j->'totals'->>'line_count' lines, j->'totals'->>'known_official_merchandise_subtotal' known, j->>'authorization_scope' scope from public.e10_org_customer_spend_contributions(pg_temp.i('org'),'2026-01-01','2026-03-01','2026-09-01','USD',null,null,null,null,null,null,null,null,null,100,null,null,null,null,null) j;
select x->>'effective_customer_id' c, x->>'known_official_subtotal' known, j->'full_cohort_totals' totals, j->'authorized_data_diagnostics' diag from public.e10_org_customer_spend_summary(pg_temp.i('org'),'2026-01-01','2026-03-01','2026-09-01','USD','UTC',1,null,null,null,null,null,null,null,null,null,100,null,null,null) j, jsonb_array_elements(j->'items') x;
select x->>'display_name' name, x->>'known_official_subtotal' known, j->'full_cohort_totals' totals from public.e10_org_customer_spend_grid_v2(pg_temp.i('org'),'bounded','2026-01-01','2026-03-01','2026-09-01','USD','UTC',1,null,null,null,null,null,null,null,null,null,null,null,'customer_id_asc',100,null,null,null) j, jsonb_array_elements(j->'items') x;
select pg_temp.try($$public.e10_org_customer_spend_contributions(pg_temp.i('org'),'2026-01-01','2026-03-01','2026-09-01','USD',null,null,pg_temp.i('L2'),null,null,null,null,null,null,100,null,null,null,null,null)$$) u3_filter_L2;
select pg_temp.try($$public.e10_org_customer_provisional_activity(pg_temp.i('org'),'2026-01-01','2026-03-01','2026-09-01','USD',null,100,null,null,null,null)$$) u3_provisional;
reset role;
select pg_temp.remember('l2line',(select id from public.e10_customer_transaction_lines where transaction_id=pg_temp.i('t2')));
select pg_temp.remember('l3line',(select id from public.e10_customer_transaction_lines where transaction_id=pg_temp.i('t3')));
select pg_temp.remember('l1line',(select id from public.e10_customer_transaction_lines where transaction_id=pg_temp.i('t1')));
set role authenticated;
select pg_temp.try($$public.e10_org_customer_spend_lineage(pg_temp.i('org'),pg_temp.i('l2line'),'2026-09-01',100,null,null,null,null,null)$$) u3_lineage_L2;
select pg_temp.try($$public.e10_org_customer_spend_lineage(pg_temp.i('org'),pg_temp.i('l3line'),'2026-09-01',100,null,null,null,null,null)$$) u3_lineage_null_loc;
select pg_temp.try($$jsonb_array_length(public.e10_org_customer_spend_lineage(pg_temp.i('org'),pg_temp.i('l1line'),'2026-09-01',100,null,null,null,null,null)->'items')$$) u3_lineage_L1;
\echo --- archive L1: location-only access closes
reset role; update public.e10_locations set status='archived' where id=pg_temp.i('L1'); set role authenticated;
select pg_temp.try($$public.e10_org_customer_spend_contributions(pg_temp.i('org'),'2026-01-01','2026-03-01','2026-09-01','USD',null,null,null,null,null,null,null,null,null,100,null,null,null,null,null)$$) u3_after_archive;
reset role; update public.e10_locations set status='active' where id=pg_temp.i('L1'); set role authenticated;
\echo === E6b cross-org probes by foreign user ufor (knows all UUIDs)
select pg_temp.as_user('ufor');
select pg_temp.try($$public.e10_org_customer_spend_lineage(pg_temp.i('org2'),pg_temp.i('l1line'),'2026-09-01',100,null,null,null,null,null)$$) for_lineage;
select pg_temp.try($$public.e10_org_adjust_customer_transaction(pg_temp.i('org2'),pg_temp.i('t1'),pg_temp.i('l1line'),'refund','decrease','USD',1::numeric,null::numeric,null::numeric,'2026-01-09'::timestamptz,'exact','x','manual',null::text,'e','c',null::uuid,'{}'::jsonb,'for-adj')$$) for_adjust;
select pg_temp.try($$public.e10_org_finalize_customer_transaction_component(pg_temp.i('org2'),pg_temp.i('t1'),pg_temp.i('l1line'),'shipping',1,'USD','x','manual',null::text,'e','c','{}'::jsonb,'for-fin')$$) for_finalize;
select pg_temp.try($$public.e10_org_decide_customer_transaction_attribution(pg_temp.i('org2'),pg_temp.i('t1'),0,pg_temp.i('c_for'),'steal','{}'::jsonb,'for-attr')$$) for_attr;
select pg_temp.try($$public.e10_org_decide_customer_resolution(pg_temp.i('org2'),pg_temp.i('c1'),pg_temp.i('c_for'),0,0,0,'merge','operator_review','{}'::uuid[],'x','{}'::jsonb,'for-merge')$$) for_merge;
select pg_temp.try($$(select count(*) from public.e10_org_resolve_customers(pg_temp.i('org2'),array[pg_temp.i('c1'),pg_temp.i('c_for')]))$$) for_resolve_customers_count;
select pg_temp.try($$public.e10_org_resolve_customer_transactions(pg_temp.i('org2'),array[pg_temp.i('t1')])$$) for_resolve_tx;
select pg_temp.try($$public.e10_org_decide_customer_identity(pg_temp.i('org2'),pg_temp.i('c1'),'channel_account','whatnot','alicehandle',null,'attach',null,'x','{}'::jsonb,'for-id')$$) for_identity_on_foreign_customer;
select pg_temp.try($$public.e10_org_create_customer_transaction_draft(pg_temp.i('org2'),pg_temp.i('c_for'),'USD','2026-01-08','exact','x',jsonb_build_array(jsonb_build_object('purchase_kind','retail','capture_source','manual','source_line_id','for-1','quantity',1,'merchandise_gross',1,'location_id',pg_temp.i('L1'))),'for-d')$$) for_draft_with_foreign_location;
select pg_temp.try($$public.e10_org_update_customer(pg_temp.i('org2'),pg_temp.i('c1'),0,'Hacked','active','for-upd')$$) for_update_customer;
select pg_temp.try($$public.e10_org_attribute_customer_activity(pg_temp.i('org2'),gen_random_uuid(),pg_temp.i('c1'),'x','{}'::jsonb,'for-attr2')$$) for_attribute_activity;
select pg_temp.try($$public.e10_org_set_location_financial_access(pg_temp.i('org2'),pg_temp.i('L1'),pg_temp.i('rfor'),null::timestamptz,true,'x','{}'::jsonb,'for-grant')$$) for_grant_on_foreign_location;
select pg_temp.try($$public.e10_org_set_location_financial_access(pg_temp.i('org2'),pg_temp.i('L_for'),pg_temp.i('r3'),null::timestamptz,true,'x','{}'::jsonb,'for-grant2')$$) for_grant_foreign_role;
\echo --- identity: foreign org attaching the same whatnot handle to its own customer (allowed by design), and find_customers scoping
select pg_temp.as_user('u1');
select pg_temp.try($$public.e10_org_decide_customer_identity(pg_temp.i('org'),pg_temp.i('c1'),'channel_account','whatnot','alicehandle',null,'attach',null,'x','{}'::jsonb,'u1-id')$$) u1_attach;
select pg_temp.as_user('ufor');
select pg_temp.try($$public.e10_org_decide_customer_identity(pg_temp.i('org2'),pg_temp.i('c_for'),'channel_account','whatnot','alicehandle',null,'attach',null,'x','{}'::jsonb,'for-id2')$$) for_attach_same_handle_own_customer;
select * from public.e10_org_find_customers(pg_temp.i('org2'),'alice',10);
select pg_temp.try($$(select count(*) from public.e10_org_find_customers(pg_temp.i('org'),'alice',10))$$) for_find_in_org0;
\echo --- location-only reader u3 (no org cap) calling find_customers (has manage_customers): sees names only
select pg_temp.as_user('u3');
select * from public.e10_org_find_customers(pg_temp.i('org'),'alice',10);
rollback;
