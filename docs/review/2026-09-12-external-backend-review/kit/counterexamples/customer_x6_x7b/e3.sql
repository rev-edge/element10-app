\set ON_ERROR_STOP 0
begin;
\i fixture.sql
set role authenticated;
select pg_temp.as_user('u1');
-- tx1: c1, two lines: L1 known 100 (disc 0, ship 20, tax 10), L2 unknown discount (gross 40, discount null), L3 shipping null tax null gross 10 disc 0
select pg_temp.remember('d1',(public.e10_org_create_customer_transaction_draft(pg_temp.i('org'),pg_temp.i('c1'),'USD','2026-01-05','exact','mixed knowns',
 jsonb_build_array(
  jsonb_build_object('purchase_kind','retail','capture_source','manual','source_line_id','e3-l1','quantity',1,'merchandise_gross',100,'merchandise_discount',0,'shipping_amount',20,'tax_amount',10,'location_id',pg_temp.i('L1')),
  jsonb_build_object('purchase_kind','break','capture_source','manual','source_line_id','e3-l2','quantity',1,'merchandise_gross',40,'merchandise_discount',null,'break_session_id',pg_temp.i('S')),
  jsonb_build_object('purchase_kind','retail','capture_source','manual','source_line_id','e3-l3','quantity',2,'merchandise_gross',10,'merchandise_discount',0)
 ),'e3-d1')->>'draft_id')::uuid);
select pg_temp.try($$public.e10_org_approve_customer_transaction_draft(pg_temp.i('org'),pg_temp.i('d1'),1,'e3-ap1')$$);
select pg_temp.remember('tx1',(public.e10_org_post_customer_transaction_draft(pg_temp.i('org'),pg_temp.i('d1'),1,'e3-post1')->>'transaction_id')::uuid);
reset role;
select pg_temp.remember('l1',(select id from public.e10_customer_transaction_lines where transaction_id=pg_temp.i('tx1') and line_no=1));
select pg_temp.remember('l2',(select id from public.e10_customer_transaction_lines where transaction_id=pg_temp.i('tx1') and line_no=2));
select pg_temp.remember('l3',(select id from public.e10_customer_transaction_lines where transaction_id=pg_temp.i('tx1') and line_no=3));
set role authenticated;
\echo === E3a refund larger than remaining; refund in other currency; negative; adjust unknown component
select pg_temp.try($$public.e10_org_adjust_customer_transaction(pg_temp.i('org'),pg_temp.i('tx1'),pg_temp.i('l1'),'refund','decrease','USD',150::numeric,null::numeric,null::numeric,'2026-01-08'::timestamptz,'exact','too big','manual',null::text,'ref-1','m','{}'::jsonb,'e3-ref-big')$$) refund_exceeds;
select pg_temp.try($$public.e10_org_adjust_customer_transaction(pg_temp.i('org'),pg_temp.i('tx1'),pg_temp.i('l1'),'refund','decrease','CAD',10::numeric,null::numeric,null::numeric,'2026-01-08'::timestamptz,'exact','wrong currency','manual',null::text,'ref-2','m',null::uuid,'{}'::jsonb,'e3-ref-cad')$$) refund_other_currency;
select pg_temp.try($$public.e10_org_adjust_customer_transaction(pg_temp.i('org'),pg_temp.i('tx1'),pg_temp.i('l1'),'refund','decrease','USD',-10::numeric,null::numeric,null::numeric,'2026-01-08'::timestamptz,'exact','negative','manual',null::text,'ref-3','m',null::uuid,'{}'::jsonb,'e3-ref-neg')$$) refund_negative;
select pg_temp.try($$public.e10_org_adjust_customer_transaction(pg_temp.i('org'),pg_temp.i('tx1'),pg_temp.i('l2'),'refund','decrease','USD',5::numeric,null::numeric,null::numeric,'2026-01-08'::timestamptz,'exact','unknown merch','manual',null::text,'ref-4','m',null::uuid,'{}'::jsonb,'e3-ref-unk')$$) refund_unknown_component;
select pg_temp.try($$public.e10_org_adjust_customer_transaction(pg_temp.i('org'),pg_temp.i('tx1'),pg_temp.i('l1'),'refund','decrease','USD',60::numeric,5::numeric,null::numeric,'2026-01-08'::timestamptz,'exact','partial refund','manual',null::text,'ref-5','m',null::uuid,'{}'::jsonb,'e3-ref-ok')$$) refund_ok;
select pg_temp.try($$public.e10_org_adjust_customer_transaction(pg_temp.i('org'),pg_temp.i('tx1'),pg_temp.i('l1'),'refund','decrease','USD',41::numeric,null::numeric,null::numeric,'2026-01-09'::timestamptz,'exact','second refund exceeds remaining 40','manual',null::text,'ref-6','m',null::uuid,'{}'::jsonb,'e3-ref-2')$$) second_refund_exceeds;
select pg_temp.try($$public.e10_org_adjust_customer_transaction(pg_temp.i('org'),pg_temp.i('tx1'),pg_temp.i('l1'),'correction','increase','USD',1000::numeric,null::numeric,null::numeric,'2026-01-09'::timestamptz,'exact','unbounded increase','manual',null::text,'cor-1','m',null::uuid,'{}'::jsonb,'e3-cor-1')$$) increase_unbounded;
\echo === E3b finalize unknown discount on l2 -> merchandise known; finalize known component rejected; finalize shipping l3 to zero
select pg_temp.try($$public.e10_org_finalize_customer_transaction_component(pg_temp.i('org'),pg_temp.i('tx1'),pg_temp.i('l1'),'merchandise',5,'USD','already known','manual',null,'fin-0','m','{}'::jsonb,'e3-fin-0')$$) finalize_known;
select pg_temp.try($$public.e10_org_finalize_customer_transaction_component(pg_temp.i('org'),pg_temp.i('tx1'),pg_temp.i('l2'),'merchandise',33,'USD','reviewed','manual',null,'fin-1','m','{}'::jsonb,'e3-fin-1')$$) finalize_l2_merch;
select pg_temp.try($$public.e10_org_finalize_customer_transaction_component(pg_temp.i('org'),pg_temp.i('tx1'),pg_temp.i('l3'),'shipping',0,'USD','reviewed zero','manual',null,'fin-2','m','{}'::jsonb,'e3-fin-2')$$) finalize_l3_ship_zero;
\echo === contributions per line (official values, known flags)
select x->>'line_no' ln, x->>'merchandise_gross' gross, x->>'merchandise_discount' disc, x->>'base_merchandise_net' base, x->>'merchandise_adjustment_delta' delta, x->>'official_net_merchandise' official, x->>'official_shipping' ship, x->>'official_tax' tax, x->>'merchandise_known' mk, x->>'shipping_known' sk, x->>'tax_known' tk
from public.e10_org_customer_spend_contributions(pg_temp.i('org'),'2026-01-01','2026-03-01','2026-09-01','USD',pg_temp.i('c1'),null,null,null,null,null,null,null,null,100,null,null,null,null,null) j, jsonb_array_elements(j->'items') x;
select j->'totals' contribution_totals from public.e10_org_customer_spend_contributions(pg_temp.i('org'),'2026-01-01','2026-03-01','2026-09-01','USD',pg_temp.i('c1'),null,null,null,null,null,null,null,null,100,null,null,null,null,null) j;
select j->'items'->0 summary_row from public.e10_org_customer_spend_summary(pg_temp.i('org'),'2026-01-01','2026-03-01','2026-09-01','USD','UTC',1,pg_temp.i('c1'),null,null,null,null,null,null,null,null,100,null,null,null) j;
select j->'items'->0 grid_row, j->'full_cohort_totals' grid_totals, j->'coverage' coverage from public.e10_org_customer_spend_grid_v2(pg_temp.i('org'),'bounded','2026-01-01','2026-03-01','2026-09-01','USD','UTC',1,pg_temp.i('c1'),null,null,null,null,null,null,null,null,null,null,'customer_id_asc',100,null,null,null) j;
\echo === E3c cancellation must zero known comps; then refund after cancel; reinstatement
select pg_temp.try($$public.e10_org_adjust_customer_transaction(pg_temp.i('org'),pg_temp.i('tx1'),pg_temp.i('l3'),'cancellation','decrease','USD',20::numeric,null::numeric,null::numeric,'2026-01-09'::timestamptz,'exact','cancel l3 (shipping finalized 0, tax unknown)','manual',null::text,'can-1','m',null::uuid,'{}'::jsonb,'e3-can-1')$$) cancel_l3;
select pg_temp.try($$public.e10_org_adjust_customer_transaction(pg_temp.i('org'),pg_temp.i('tx1'),pg_temp.i('l3'),'refund','decrease','USD',1::numeric,null::numeric,null::numeric,'2026-01-09'::timestamptz,'exact','refund after cancel','manual',null::text,'ref-7','m',null::uuid,'{}'::jsonb,'e3-ref-7')$$) refund_after_cancel;
select pg_temp.try($$public.e10_org_finalize_customer_transaction_component(pg_temp.i('org'),pg_temp.i('tx1'),pg_temp.i('l3'),'tax',3,'USD','tax after cancel','manual',null,'fin-3','m','{}'::jsonb,'e3-fin-3')$$) finalize_tax_after_cancel;
select x->>'line_no' ln, x->>'official_net_merchandise' official, x->>'official_shipping' ship, x->>'official_tax' tax, x->>'merchandise_known' mk
from public.e10_org_customer_spend_contributions(pg_temp.i('org'),'2026-01-01','2026-03-01','2026-09-01','USD',pg_temp.i('c1'),null,null,null,null,null,null,null,null,100,null,null,null,null,null) j, jsonb_array_elements(j->'items') x where x->>'line_no'='3';
\echo === E3d adjustment on a transaction with unknown occurrence: transaction excluded but adjustment accepted
select pg_temp.remember('d2',(public.e10_org_create_customer_transaction_draft(pg_temp.i('org'),pg_temp.i('c1'),'USD',null,'unknown','unknown occurrence',
 jsonb_build_array(jsonb_build_object('purchase_kind','retail','capture_source','manual','source_line_id','e3-unk','quantity',1,'merchandise_gross',77,'merchandise_discount',0)),'e3-d2')->>'draft_id')::uuid);
select pg_temp.try($$public.e10_org_approve_customer_transaction_draft(pg_temp.i('org'),pg_temp.i('d2'),1,'e3-ap2')$$);
select pg_temp.try($$public.e10_org_post_customer_transaction_draft(pg_temp.i('org'),pg_temp.i('d2'),1,'e3-post2')$$) post_unknown_occurrence;
select j->'authorized_data_diagnostics' diag, j->'full_cohort_totals' totals from public.e10_org_customer_spend_summary(pg_temp.i('org'),'2026-01-01','2026-03-01','2026-09-01','USD','UTC',1,null,null,null,null,null,null,null,null,null,100,null,null,null) j;
\echo === E3e mixed-currency: CAD transaction for same customer is invisible in USD summary; no combined total
select pg_temp.remember('d3',(public.e10_org_create_customer_transaction_draft(pg_temp.i('org'),pg_temp.i('c1'),'CAD','2026-01-06','exact','cad',
 jsonb_build_array(jsonb_build_object('purchase_kind','retail','capture_source','manual','source_line_id','e3-cad','quantity',1,'merchandise_gross',500,'merchandise_discount',0)),'e3-d3')->>'draft_id')::uuid);
select pg_temp.try($$public.e10_org_approve_customer_transaction_draft(pg_temp.i('org'),pg_temp.i('d3'),1,'e3-ap3')$$);
select pg_temp.try($$public.e10_org_post_customer_transaction_draft(pg_temp.i('org'),pg_temp.i('d3'),1,'e3-post3')$$);
select 'USD' cur, j->'full_cohort_totals' from public.e10_org_customer_spend_summary(pg_temp.i('org'),'2026-01-01','2026-03-01','2026-09-01','USD','UTC',1,null,null,null,null,null,null,null,null,null,100,null,null,null) j
union all select 'CAD', j->'full_cohort_totals' from public.e10_org_customer_spend_summary(pg_temp.i('org'),'2026-01-01','2026-03-01','2026-09-01','CAD','UTC',1,null,null,null,null,null,null,null,null,null,100,null,null,null) j;
rollback;
