\set ON_ERROR_STOP 0
begin;
\i fixture.sql
set role authenticated;
select pg_temp.as_user('u1');
select public.e10_org_decide_customer_identity(pg_temp.i('org'),pg_temp.i('c1'),'channel_account','whatnot','@AliceHandle',null,'attach',null,'reviewed','{}','e2-id1') as attach_identity;
\echo === E2a native sale commit -> release -> recommit ; provisional activity report
select pg_temp.remember('sale1',(public.e10_org_commit_native_break_sale(pg_temp.i('org'),pg_temp.i('S'),pg_temp.i('slot1'),0,null,'alicehandle',1,30,'USD','auction','2026-01-10','[]','{}','e2-sale1')->>'sale_id')::uuid);
reset role;
select id as activity1, customer_id, buyer_identity_status from public.e10_native_break_sales where id=pg_temp.i('sale1') \gset s1_
select pg_temp.remember('act_sale1',(select activity_observation_id from public.e10_native_break_sales where id=pg_temp.i('sale1')));
set role authenticated;
select pg_temp.try($$public.e10_org_release_native_break_sale(pg_temp.i('org'),pg_temp.i('S'),pg_temp.i('slot1'),pg_temp.i('sale1'),1,'buyer backed out','{}','e2-release1')$$) release1;
select pg_temp.remember('sale2',(public.e10_org_commit_native_break_sale(pg_temp.i('org'),pg_temp.i('S'),pg_temp.i('slot1'),2,null,'alicehandle',1,35,'USD','auction','2026-01-10T01:00:00Z','[]','{}','e2-sale2')->>'sale_id')::uuid);
select j->'totals' as provisional_totals_after_release_and_resale, jsonb_array_length(j->'items') items
from public.e10_org_customer_provisional_activity(pg_temp.i('org'),'2026-01-01','2026-03-01','2026-09-01','USD',pg_temp.i('c1'),100,null,null,null,null) j;
\echo === E2b post the RELEASED sale's activity through draft/approve/post
select pg_temp.remember('d_rel',(public.e10_org_create_customer_transaction_draft(pg_temp.i('org'),pg_temp.i('c1'),'USD','2026-01-10','exact','post released sale',
 jsonb_build_array(jsonb_build_object('purchase_kind','break','capture_source','native','source_line_id','e2-rel-line','activity_observation_id',pg_temp.i('act_sale1'),'break_session_id',pg_temp.i('S'),'break_slot_id',pg_temp.i('slot1'),'quantity',1,'merchandise_gross',30,'merchandise_discount',0)),'e2-d-rel')->>'draft_id')::uuid);
select pg_temp.try($$public.e10_org_approve_customer_transaction_draft(pg_temp.i('org'),pg_temp.i('d_rel'),1,'e2-ap-rel')$$) approve_released;
select pg_temp.try($$public.e10_org_post_customer_transaction_draft(pg_temp.i('org'),pg_temp.i('d_rel'),1,'e2-post-rel')$$) post_released_sale;
\echo === E2c native sale2 posted, then an IMPORT activity for the same sale posted as separate line (double count?)
reset role;
select pg_temp.remember('act_sale2',(select activity_observation_id from public.e10_native_break_sales where id=pg_temp.i('sale2')));
set role authenticated;
select pg_temp.remember('d_nat',(public.e10_org_create_customer_transaction_draft(pg_temp.i('org'),pg_temp.i('c1'),'USD','2026-01-10T01:00:00Z','exact','post native sale2',
 jsonb_build_array(jsonb_build_object('purchase_kind','break','capture_source','native','source_line_id','e2-nat-line','activity_observation_id',pg_temp.i('act_sale2'),'break_session_id',pg_temp.i('S'),'break_slot_id',pg_temp.i('slot1'),'quantity',1,'merchandise_gross',35,'merchandise_discount',0)),'e2-d-nat')->>'draft_id')::uuid);
select pg_temp.try($$public.e10_org_approve_customer_transaction_draft(pg_temp.i('org'),pg_temp.i('d_nat'),1,'e2-ap-nat')$$) approve_native;
select pg_temp.try($$public.e10_org_post_customer_transaction_draft(pg_temp.i('org'),pg_temp.i('d_nat'),1,'e2-post-nat')$$) post_native;
-- import of the same sale (whatnot export row) recorded as provisional activity then posted
select pg_temp.remember('act_imp',(public.e10_org_record_customer_activity(pg_temp.i('org'),'break',pg_temp.i('c1'),null,'alicehandle',pg_temp.i('S'),pg_temp.i('slot1'),1,35,0,null,null,'USD','auction','2026-01-10T01:00:00Z','exact','import','whatnot-export','order-777','order-777-line-1','{}','reviewed_import','e2-act-imp')->>'activity_id')::uuid);
select pg_temp.remember('d_imp',(public.e10_org_create_customer_transaction_draft(pg_temp.i('org'),pg_temp.i('c1'),'USD','2026-01-10T01:00:00Z','exact','post import of same sale',
 jsonb_build_array(jsonb_build_object('purchase_kind','break','capture_source','import','source_connection_id','whatnot-export','source_line_id','order-777-line-1','activity_observation_id',pg_temp.i('act_imp'),'break_session_id',pg_temp.i('S'),'break_slot_id',pg_temp.i('slot1'),'quantity',1,'merchandise_gross',35,'merchandise_discount',0)),'e2-d-imp')->>'draft_id')::uuid);
select pg_temp.try($$public.e10_org_approve_customer_transaction_draft(pg_temp.i('org'),pg_temp.i('d_imp'),1,'e2-ap-imp')$$) approve_import;
select pg_temp.try($$public.e10_org_post_customer_transaction_draft(pg_temp.i('org'),pg_temp.i('d_imp'),1,'e2-post-imp')$$) post_import_same_sale;
\echo === official spend summary for c1 (expect 35 if deduped; 70 if double; +30 if released sale posted)
select j->'items'->0->'known_official_subtotal' known, j->'items'->0->'line_count' lines, j->'items'->0->'order_count' orders, j->'items'->0->'purchasing_breaks' pb, j->'full_cohort_totals' totals
from public.e10_org_customer_spend_summary(pg_temp.i('org'),'2026-01-01','2026-03-01','2026-09-01','USD','UTC',1,pg_temp.i('c1'),null,null,null,null,null,null,null,null,100,null,null,null) j;
select j->'totals' provisional_after_posting from public.e10_org_customer_provisional_activity(pg_temp.i('org'),'2026-01-01','2026-03-01','2026-09-01','USD',pg_temp.i('c1'),100,null,null,null,null) j;
\echo === E2d activity currency CAD posted under USD draft header
select pg_temp.remember('act_cad',(public.e10_org_record_customer_activity(pg_temp.i('org'),'retail',pg_temp.i('c1'),null,null,null,null,1,50,0,null,null,'CAD',null,'2026-01-12','exact','manual',null,null,'e2-cad-src','{}','operator_asserted','e2-act-cad')->>'activity_id')::uuid);
select pg_temp.remember('d_cad',(public.e10_org_create_customer_transaction_draft(pg_temp.i('org'),pg_temp.i('c1'),'USD','2026-01-12','exact','currency mismatch',
 jsonb_build_array(jsonb_build_object('purchase_kind','retail','capture_source','manual','source_line_id','e2-cad-line','activity_observation_id',pg_temp.i('act_cad'),'quantity',1,'merchandise_gross',50,'merchandise_discount',0)),'e2-d-cad')->>'draft_id')::uuid);
select pg_temp.try($$public.e10_org_approve_customer_transaction_draft(pg_temp.i('org'),pg_temp.i('d_cad'),1,'e2-ap-cad')$$) approve_cad;
select pg_temp.try($$public.e10_org_post_customer_transaction_draft(pg_temp.i('org'),pg_temp.i('d_cad'),1,'e2-post-cad')$$) post_cad_activity_as_usd;
\echo === E2e duplicate activity in one draft: posting
select pg_temp.remember('d_dup',(public.e10_org_create_customer_transaction_draft(pg_temp.i('org'),pg_temp.i('c1'),'USD','2026-01-13','exact','dup',
 jsonb_build_array(jsonb_build_object('purchase_kind','retail','capture_source','manual','source_line_id','e2-dupA','activity_observation_id',pg_temp.i('act_cad'),'quantity',1,'merchandise_gross',5,'merchandise_discount',0),
                  jsonb_build_object('purchase_kind','retail','capture_source','manual','source_line_id','e2-dupB','activity_observation_id',pg_temp.i('act_cad'),'quantity',1,'merchandise_gross',5,'merchandise_discount',0)),'e2-d-dup')->>'draft_id')::uuid);
select pg_temp.try($$public.e10_org_approve_customer_transaction_draft(pg_temp.i('org'),pg_temp.i('d_dup'),1,'e2-ap-dup')$$) approve_dup;
select pg_temp.try($$public.e10_org_post_customer_transaction_draft(pg_temp.i('org'),pg_temp.i('d_dup'),1,'e2-post-dup')$$) post_dup;
rollback;
