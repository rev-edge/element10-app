\set ON_ERROR_STOP 0
begin;
\i fixture.sql
set role authenticated;
select pg_temp.as_user('u1');
\echo === E1a same user prepares/approves/posts
select pg_temp.remember('d1',(public.e10_org_create_customer_transaction_draft(pg_temp.i('org'),pg_temp.i('c1'),'USD','2026-01-05','exact','same user',
 jsonb_build_array(jsonb_build_object('purchase_kind','retail','capture_source','manual','source_line_id','e1-l1','quantity',1,'merchandise_gross',100,'merchandise_discount',0)),'e1-draft')->>'draft_id')::uuid);
select pg_temp.try($$public.e10_org_approve_customer_transaction_draft(pg_temp.i('org'),pg_temp.i('d1'),1,'e1-approve')$$) approve_same_user;
select pg_temp.try($$public.e10_org_post_customer_transaction_draft(pg_temp.i('org'),pg_temp.i('d1'),1,'e1-post')$$) post_same_user;
\echo === E1b post replay same key different revision
select pg_temp.try($$public.e10_org_post_customer_transaction_draft(pg_temp.i('org'),pg_temp.i('d1'),2,'e1-post')$$) post_replay_other_rev;
\echo === E1c approve, reopen, amend, post old rev
select pg_temp.remember('d2',(public.e10_org_create_customer_transaction_draft(pg_temp.i('org'),pg_temp.i('c1'),'USD','2026-01-06','exact','amend flow',
 jsonb_build_array(jsonb_build_object('purchase_kind','retail','capture_source','manual','source_line_id','e1-l2','quantity',1,'merchandise_gross',10)),'e1-draft2')->>'draft_id')::uuid);
select pg_temp.try($$public.e10_org_approve_customer_transaction_draft(pg_temp.i('org'),pg_temp.i('d2'),1,'e1-approve2')$$) approve2;
select pg_temp.try($$public.e10_org_amend_customer_transaction_draft(pg_temp.i('org'),pg_temp.i('d2'),1,pg_temp.i('c1'),'USD','2026-01-06','exact','amend while approved',
 jsonb_build_array(jsonb_build_object('purchase_kind','retail','capture_source','manual','source_line_id','e1-l2','quantity',1,'merchandise_gross',9999)),'e1-amend-approved')$$) amend_while_approved;
select pg_temp.try($$public.e10_org_reopen_customer_transaction_draft(pg_temp.i('org'),pg_temp.i('d2'),1,'reopen','e1-reopen2')$$) reopen2;
select pg_temp.try($$public.e10_org_amend_customer_transaction_draft(pg_temp.i('org'),pg_temp.i('d2'),1,pg_temp.i('c1'),'USD','2026-01-06','exact','amended',
 jsonb_build_array(jsonb_build_object('purchase_kind','retail','capture_source','manual','source_line_id','e1-l2','quantity',1,'merchandise_gross',9999)),'e1-amend2')$$) amend_after_reopen;
select pg_temp.try($$public.e10_org_post_customer_transaction_draft(pg_temp.i('org'),pg_temp.i('d2'),1,'e1-post2-old')$$) post_old_rev;
select pg_temp.try($$public.e10_org_post_customer_transaction_draft(pg_temp.i('org'),pg_temp.i('d2'),2,'e1-post2-new')$$) post_new_rev_unapproved;
\echo === E1d approver-only user
select pg_temp.as_user('u2');
select pg_temp.try($$public.e10_org_create_customer_transaction_draft(pg_temp.i('org'),pg_temp.i('c1'),'USD','2026-01-06','exact','u2',
 jsonb_build_array(jsonb_build_object('purchase_kind','retail','capture_source','manual','source_line_id','e1-l3','quantity',1,'merchandise_gross',10)),'e1-u2-draft')$$) u2_prepare;
select pg_temp.try($$public.e10_org_approve_customer_transaction_draft(pg_temp.i('org'),pg_temp.i('d2'),2,'e1-u2-approve')$$) u2_approve;
select pg_temp.try($$public.e10_org_post_customer_transaction_draft(pg_temp.i('org'),pg_temp.i('d2'),2,'e1-u2-post')$$) u2_post;
\echo === E1e reopen after posted, amend posted
select pg_temp.as_user('u1');
select pg_temp.try($$public.e10_org_reopen_customer_transaction_draft(pg_temp.i('org'),pg_temp.i('d1'),1,'reopen posted','e1-reopen-posted')$$) reopen_posted;
\echo === E1f NULL / NaN / negative amounts in draft lines
select pg_temp.try($$public.e10_org_create_customer_transaction_draft(pg_temp.i('org'),pg_temp.i('c1'),'USD','2026-01-06','exact','null gross',
 jsonb_build_array(jsonb_build_object('purchase_kind','retail','capture_source','manual','source_line_id','e1-null','quantity',1)),'e1-null')$$) null_gross;
select pg_temp.try($$public.e10_org_create_customer_transaction_draft(pg_temp.i('org'),pg_temp.i('c1'),'USD','2026-01-06','exact','nan gross',
 jsonb_build_array(jsonb_build_object('purchase_kind','retail','capture_source','manual','source_line_id','e1-nan','quantity',1,'merchandise_gross','NaN')),'e1-nan')$$) nan_gross;
select pg_temp.try($$public.e10_org_create_customer_transaction_draft(pg_temp.i('org'),pg_temp.i('c1'),'USD','2026-01-06','exact','neg qty',
 jsonb_build_array(jsonb_build_object('purchase_kind','retail','capture_source','manual','source_line_id','e1-neg','quantity',-1,'merchandise_gross',5)),'e1-neg')$$) neg_qty;
select pg_temp.try($$public.e10_org_create_customer_transaction_draft(pg_temp.i('org'),pg_temp.i('c1'),'USD','2026-01-06','exact','null qty',
 jsonb_build_array(jsonb_build_object('purchase_kind','retail','capture_source','manual','source_line_id','e1-nq','merchandise_gross',5)),'e1-nq')$$) null_qty;
select pg_temp.try($$public.e10_org_create_customer_transaction_draft(pg_temp.i('org'),pg_temp.i('c1'),'USD','2026-01-06','exact','inf gross',
 jsonb_build_array(jsonb_build_object('purchase_kind','retail','capture_source','manual','source_line_id','e1-inf','quantity',1,'merchandise_gross','Infinity')),'e1-inf')$$) inf_gross;
select pg_temp.try($$public.e10_org_create_customer_transaction_draft(pg_temp.i('org'),pg_temp.i('c1'),'usd','2026-01-06','exact','lower currency',
 jsonb_build_array(jsonb_build_object('purchase_kind','retail','capture_source','manual','source_line_id','e1-cur','quantity',1,'merchandise_gross',1)),'e1-cur')$$) lowercase_currency;
\echo === E1g duplicate activity / duplicate source_line in one draft accepted at draft time?
select pg_temp.remember('act1',(public.e10_org_record_customer_activity(pg_temp.i('org'),'retail',pg_temp.i('c1'),null,null,null,null,1,50,0,null,null,'CAD',null,'2026-01-07','exact','manual',null,null,'e1-act-src','{}','operator_asserted','e1-act')->>'activity_id')::uuid);
select pg_temp.try($$public.e10_org_create_customer_transaction_draft(pg_temp.i('org'),pg_temp.i('c1'),'USD','2026-01-07','exact','dup activity + currency mismatch',
 jsonb_build_array(jsonb_build_object('purchase_kind','retail','capture_source','manual','source_line_id','e1-dupA','activity_observation_id',pg_temp.i('act1'),'quantity',1,'merchandise_gross',50,'merchandise_discount',0),
                  jsonb_build_object('purchase_kind','retail','capture_source','manual','source_line_id','e1-dupB','activity_observation_id',pg_temp.i('act1'),'quantity',1,'merchandise_gross',50,'merchandise_discount',0)),'e1-dup')$$) dup_activity_draft;
rollback;
