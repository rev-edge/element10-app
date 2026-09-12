\set ON_ERROR_STOP 0
begin;
\i fixture.sql
\i common_post.sql
create temp table vars(k text primary key, v text); grant all on vars to authenticated, public;
create function pg_temp.v(k text) returns text language sql stable as $$ select v from vars where k=$1 $$; grant execute on function pg_temp.v(text) to authenticated, public;
set role authenticated;
select pg_temp.as_user('u1');
reset role;
insert into ids values('c4',gen_random_uuid()); insert into public.e10_customers(id,organization_id,display_name) values(pg_temp.i('c4'),pg_temp.i('org'),null);
set role authenticated;
select pg_temp.post_tx('t1','c1',100,'2026-01-05',null,'web');
select pg_temp.post_tx('t2','c2',100,'2026-01-06',null,'web');
select pg_temp.post_tx('t3','c3',50,'2026-01-07',null,'store');
select pg_temp.post_tx('t4','c4',100,'2026-01-08',null,'web');
select pg_temp.post_tx('t5','c1',0,'2026-01-09',null,'web');
create temp table ref as select s.sort, x.ord, x.item->>'effective_customer_id' cid, x.item->>'display_name' name, (x.item->>'known_official_subtotal')::numeric known
 from unnest(array['customer_id_asc','display_name_asc','known_official_subtotal_asc','known_official_subtotal_desc']) s(sort),
 lateral public.e10_org_customer_spend_grid_v2(pg_temp.i('org'),'bounded','2026-01-01','2026-03-01','2026-09-01','USD','UTC',1,null,null,null,null,null,null,null,null,null,null,null,s.sort,100,null,null,null) j,
 lateral jsonb_array_elements(j->'items') with ordinality x(item,ord);
\echo === E5b traverse each sort with limit 1; compare to reference ordering; totals on each page
create function pg_temp.walk(p_sort text) returns table(page int, cid text, totals jsonb, has_more boolean) language plpgsql as $$
declare j jsonb; cur jsonb:=null; rev bigint; fp text; n int:=0;
begin
  loop
    n:=n+1;
    j:=public.e10_org_customer_spend_grid_v2(pg_temp.i('org'),'bounded','2026-01-01','2026-03-01','2026-09-01','USD','UTC',1,null,null,null,null,null,null,null,null,null,null,null,p_sort,1,cur,rev,fp);
    rev:=(j->>'dataset_revision')::bigint; fp:=j->>'query_fingerprint';
    page:=n; cid:=j->'items'->0->>'effective_customer_id'; totals:=j->'full_cohort_totals'; has_more:=(j->>'has_more')::boolean; return next;
    if not (j->>'has_more')::boolean then exit; end if;
    cur:=j->'next_cursor';
    if n>20 then exit; end if;
  end loop;
end $$;
grant execute on function pg_temp.walk(text) to authenticated, public;
create temp table walked as select s.sort, w.* from unnest(array['customer_id_asc','display_name_asc','known_official_subtotal_asc','known_official_subtotal_desc']) s(sort) cross join lateral pg_temp.walk(s.sort) w;
select w.sort, w.page, w.cid, r.ord ref_ord, (w.page=r.ord) same_position, w.totals, w.has_more from walked w left join ref r on r.sort=w.sort and r.cid=w.cid order by w.sort, w.page;
\echo === E5c aggregate filter min=100 with channel web (c1 has 100 web; c2 100 web; c4 100 web; c3 store) : totals before pagination, limit 1
select j->'full_cohort_totals' totals, jsonb_array_length(j->'items') n, j->>'has_more' from public.e10_org_customer_spend_grid_v2(pg_temp.i('org'),'bounded','2026-01-01','2026-03-01','2026-09-01','USD','UTC',1,null,null,null,'web',null,null,null,null,null,100,null,'known_official_subtotal_desc',1,null,null,null) j;
\echo === E5d cursor rebinding
select j->'next_cursor' cur, j->>'dataset_revision' rev, j->>'query_fingerprint' fp from public.e10_org_customer_spend_grid_v2(pg_temp.i('org'),'bounded','2026-01-01','2026-03-01','2026-09-01','USD','UTC',1,null,null,null,null,null,null,null,null,null,null,null,'customer_id_asc',1,null,null,null) j \gset g_
insert into vars values('cur',:'g_cur'),('rev',:'g_rev'),('fp',:'g_fp');
select pg_temp.try($$public.e10_org_customer_spend_grid_v2(pg_temp.i('org'),'bounded','2026-01-01','2026-03-01','2026-09-01','USD','UTC',1,null,null,null,'web',null,null,null,null,null,null,null,'customer_id_asc',1,pg_temp.v('cur')::jsonb,pg_temp.v('rev')::bigint,pg_temp.v('fp'))$$) cursor_with_added_filter;
select pg_temp.try($$public.e10_org_customer_spend_grid_v2(pg_temp.i('org'),'bounded','2026-01-01','2026-03-01','2026-09-01','USD','UTC',1,null,null,null,null,null,null,null,null,null,null,null,'display_name_asc',1,pg_temp.v('cur')::jsonb,pg_temp.v('rev')::bigint,pg_temp.v('fp'))$$) cursor_with_other_sort;
select pg_temp.try($$jsonb_array_length(public.e10_org_customer_spend_grid_v2(pg_temp.i('org'),'bounded','2026-01-01','2026-03-01','2026-09-01','USD','UTC',1,null,null,null,null,null,null,null,null,null,null,null,'customer_id_asc',1,pg_temp.v('cur')::jsonb,pg_temp.v('rev')::bigint,pg_temp.v('fp'))->'items')$$) cursor_same_query_ok;
select pg_temp.try($$public.e10_org_customer_spend_grid_v2(pg_temp.i('org'),'bounded','2026-01-01','2026-03-01','2026-09-01','USD','UTC',1,null,null,null,null,null,null,null,null,null,null,null,'customer_id_asc',1,(pg_temp.v('cur')::jsonb)||jsonb_build_object('effective_customer_id',pg_temp.i('c_for')),pg_temp.v('rev')::bigint,pg_temp.v('fp'))$$) cursor_tampered_customer;
select pg_temp.try($$public.e10_org_customer_spend_grid_v2(pg_temp.i('org'),'bounded','2026-01-01','2026-03-01','2026-09-01','USD','UTC',1,null,null,null,null,null,null,null,null,null,null,null,'customer_id_asc',1,(pg_temp.v('cur')::jsonb)||jsonb_build_object('known_official_subtotal',0),pg_temp.v('rev')::bigint,pg_temp.v('fp'))$$) cursor_tampered_subtotal_customer_sort;
select pg_temp.as_user('uadmin');
select pg_temp.try($$public.e10_org_customer_spend_grid_v2(pg_temp.i('org'),'bounded','2026-01-01','2026-03-01','2026-09-01','USD','UTC',1,null,null,null,null,null,null,null,null,null,null,null,'customer_id_asc',1,pg_temp.v('cur')::jsonb,pg_temp.v('rev')::bigint,pg_temp.v('fp'))$$) cursor_replayed_by_other_user;
select pg_temp.as_user('ufor');
select pg_temp.try($$public.e10_org_customer_spend_grid_v2(pg_temp.i('org2'),'bounded','2026-01-01','2026-03-01','2026-09-01','USD','UTC',1,null,null,null,null,null,null,null,null,null,null,null,'customer_id_asc',1,pg_temp.v('cur')::jsonb,pg_temp.v('rev')::bigint,pg_temp.v('fp'))$$) cursor_replayed_in_other_org;
select pg_temp.as_user('u1');
\echo === E5e v1 summary: page after the last customer -> full_cohort_totals on an empty page
select j->'full_cohort_totals' p1_totals, j->'items'->0->>'effective_customer_id' c, j->>'dataset_revision' rev, j->>'query_fingerprint' fp from public.e10_org_customer_spend_summary(pg_temp.i('org'),'2026-01-01','2026-03-01','2026-09-01','USD','UTC',1,null,null,null,null,null,null,null,null,null,1,null,null,null) j \gset s_
insert into vars values('s_c',:'s_c'),('s_rev',:'s_rev'),('s_fp',:'s_fp'),('last_cid',(select max(cid) from ref where sort='customer_id_asc'));
select jsonb_array_length(j->'items') items, j->'full_cohort_totals' totals_on_empty_last_page from public.e10_org_customer_spend_summary(pg_temp.i('org'),'2026-01-01','2026-03-01','2026-09-01','USD','UTC',1,null,null,null,null,null,null,null,null,null,1,pg_temp.v('last_cid')::uuid,pg_temp.v('s_rev')::bigint,pg_temp.v('s_fp')) j;
\echo === E5f v1 summary cursor from user u1 replayed by uadmin (same scope) and v1 contributions cursor by other org
select pg_temp.as_user('uadmin');
select pg_temp.try($$jsonb_array_length(public.e10_org_customer_spend_summary(pg_temp.i('org'),'2026-01-01','2026-03-01','2026-09-01','USD','UTC',1,null,null,null,null,null,null,null,null,null,1,pg_temp.v('s_c')::uuid,pg_temp.v('s_rev')::bigint,pg_temp.v('s_fp'))->'items')$$) v1_cursor_other_user_same_scope;
select pg_temp.as_user('ufor');
select pg_temp.try($$public.e10_org_customer_spend_summary(pg_temp.i('org2'),'2026-01-01','2026-03-01','2026-09-01','USD','UTC',1,null,null,null,null,null,null,null,null,null,1,pg_temp.v('s_c')::uuid,pg_temp.v('s_rev')::bigint,pg_temp.v('s_fp'))$$) v1_cursor_other_org;
select pg_temp.as_user('u1');
\echo === E5g known_history mode
select j->'full_cohort_totals' kh_totals, j->'coverage' from public.e10_org_customer_spend_grid_v2(pg_temp.i('org'),'known_history',null,'2026-03-01','2026-09-01','USD','UTC',1,null,null,null,null,null,null,null,null,null,null,null,'customer_id_asc',100,null,null,null) j;
\echo === E5h grid_v2 vs summary v1 consistency, and contributions page totals
select (select sum((x->>'known_official_subtotal')::numeric) from public.e10_org_customer_spend_summary(pg_temp.i('org'),'2026-01-01','2026-03-01','2026-09-01','USD','UTC',1,null,null,null,null,null,null,null,null,null,100,null,null,null) j, jsonb_array_elements(j->'items') x) v1_sum,
       (select j->'full_cohort_totals'->>'known_official_subtotal' from public.e10_org_customer_spend_grid_v2(pg_temp.i('org'),'bounded','2026-01-01','2026-03-01','2026-09-01','USD','UTC',1,null,null,null,null,null,null,null,null,null,null,null,'customer_id_asc',100,null,null,null) j) v2_total,
       (select j->'totals'->>'known_official_merchandise_subtotal' from public.e10_org_customer_spend_contributions(pg_temp.i('org'),'2026-01-01','2026-03-01','2026-09-01','USD',null,null,null,null,null,null,null,null,null,2,null,null,null,null,null) j) contrib_total_limit2;
rollback;
