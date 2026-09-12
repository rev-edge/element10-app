\set ON_ERROR_STOP 0
begin;
\i fixture.sql
\i common_post.sql
create temp table vars(k text primary key, v text); grant all on vars to authenticated, public;
create function pg_temp.v(k text) returns text language sql stable as $$ select v from vars where k=$1 $$; grant execute on function pg_temp.v(text) to authenticated, public;
insert into ids values('u4',gen_random_uuid()),('c4',gen_random_uuid()),('c5',gen_random_uuid());
insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at) values(pg_temp.i('u4'),'00000000-0000-0000-0000-000000000000','authenticated','authenticated','u4-'||pg_temp.i('u4')||'@x.invalid',now(),now());
insert into public.e10_organization_memberships(organization_id,user_id,role_id,status) values(pg_temp.i('org'),pg_temp.i('u4'),pg_temp.i('r1'),'active');
insert into public.e10_customers(id,organization_id,display_name) values(pg_temp.i('c4'),pg_temp.i('org'),null),(pg_temp.i('c5'),pg_temp.i('org'),null);
set role authenticated;
select pg_temp.as_user('u1');
select pg_temp.post_tx('t1','c1',100,'2026-01-05',null,'web');
select pg_temp.post_tx('t2','c2',100,'2026-01-06',null,'web');
select pg_temp.post_tx('t3','c3',50,'2026-01-07',null,'store');
select pg_temp.post_tx('t4','c4',100,'2026-01-08',null,'web');
select pg_temp.post_tx('t5','c5',100,'2026-01-09',null,'web');
\echo === E7a display_name_asc with two NULL-named customers, limit 4 then cursor
select j->'next_cursor' cur, j->>'dataset_revision' rev, j->>'query_fingerprint' fp, (select string_agg(coalesce(x->>'display_name','<null>'),',') from jsonb_array_elements(j->'items') x) page1 from public.e10_org_customer_spend_grid_v2(pg_temp.i('org'),'bounded','2026-01-01','2026-03-01','2026-09-01','USD','UTC',1,null,null,null,null,null,null,null,null,null,null,null,'display_name_asc',4,null,null,null) j \gset g_
insert into vars values('cur',:'g_cur'),('rev',:'g_rev'),('fp',:'g_fp');
select :'g_page1' page1, (select string_agg(coalesce(x->>'display_name','<null>')||':'||(x->>'effective_customer_id'),',') from jsonb_array_elements(j->'items') x) page2, j->>'has_more' from public.e10_org_customer_spend_grid_v2(pg_temp.i('org'),'bounded','2026-01-01','2026-03-01','2026-09-01','USD','UTC',1,null,null,null,null,null,null,null,null,null,null,null,'display_name_asc',4,pg_temp.v('cur')::jsonb,pg_temp.v('rev')::bigint,pg_temp.v('fp')) j;
select pg_temp.v('cur') cursor_page1;
\echo === E7b grid cursor (customer_id_asc) from u1 replayed by u4 (same org-wide scope) ; and v1 summary cursor from u1 replayed by u4
select j->'next_cursor' cur, j->>'dataset_revision' rev, j->>'query_fingerprint' fp from public.e10_org_customer_spend_grid_v2(pg_temp.i('org'),'bounded','2026-01-01','2026-03-01','2026-09-01','USD','UTC',1,null,null,null,null,null,null,null,null,null,null,null,'customer_id_asc',1,null,null,null) j \gset g2_
insert into vars values('cur2',:'g2_cur'),('rev2',:'g2_rev'),('fp2',:'g2_fp');
select j->'items'->0->>'effective_customer_id' c, j->>'dataset_revision' rev, j->>'query_fingerprint' fp from public.e10_org_customer_spend_summary(pg_temp.i('org'),'2026-01-01','2026-03-01','2026-09-01','USD','UTC',1,null,null,null,null,null,null,null,null,null,1,null,null,null) j \gset s_
insert into vars values('s_c',:'s_c'),('s_rev',:'s_rev'),('s_fp',:'s_fp');
select pg_temp.as_user('u4');
select pg_temp.try($$public.e10_org_customer_spend_grid_v2(pg_temp.i('org'),'bounded','2026-01-01','2026-03-01','2026-09-01','USD','UTC',1,null,null,null,null,null,null,null,null,null,null,null,'customer_id_asc',1,pg_temp.v('cur2')::jsonb,pg_temp.v('rev2')::bigint,pg_temp.v('fp2'))$$) grid_cursor_other_user_same_scope;
select pg_temp.try($$jsonb_array_length(public.e10_org_customer_spend_summary(pg_temp.i('org'),'2026-01-01','2026-03-01','2026-09-01','USD','UTC',1,null,null,null,null,null,null,null,null,null,1,pg_temp.v('s_c')::uuid,pg_temp.v('s_rev')::bigint,pg_temp.v('s_fp'))->'items')$$) v1_summary_cursor_other_user_same_scope;
\echo === E7c org2 replays org0 grid cursor using org2's own revision (isolate fingerprint check from revision check)
select pg_temp.as_user('ufor');
select j->>'dataset_revision' rev2 from public.e10_org_customer_spend_grid_v2(pg_temp.i('org2'),'bounded','2026-01-01','2026-03-01','2026-09-01','USD','UTC',1,null,null,null,null,null,null,null,null,null,null,null,'customer_id_asc',1,null,null,null) j \gset o2_
insert into vars values('o2rev',:'o2_rev2');
select pg_temp.try($$public.e10_org_customer_spend_grid_v2(pg_temp.i('org2'),'bounded','2026-01-01','2026-03-01','2026-09-01','USD','UTC',1,null,null,null,null,null,null,null,null,null,null,null,'customer_id_asc',1,pg_temp.v('cur2')::jsonb,pg_temp.v('o2rev')::bigint,pg_temp.v('fp2'))$$) grid_cursor_other_org_own_revision;
select pg_temp.try($$public.e10_org_customer_spend_summary(pg_temp.i('org2'),'2026-01-01','2026-03-01','2026-09-01','USD','UTC',1,null,null,null,null,null,null,null,null,null,1,pg_temp.v('s_c')::uuid,pg_temp.v('o2rev')::bigint,pg_temp.v('s_fp'))$$) v1_cursor_other_org_own_revision;
\echo === E7d find_customers wildcard query
select pg_temp.as_user('u1');
select count(*) all_customers_via_wildcard from public.e10_org_find_customers(pg_temp.i('org'),'%%',100);
select count(*) via_underscore from public.e10_org_find_customers(pg_temp.i('org'),'__',100);
\echo === E7e X8 typed query v2 path strips display_name?
select pg_temp.try($$(select r->>'context_id' from public.e10_org_create_query_context(pg_temp.i('org'),'workspace',600,'e7-ctx') r)$$) ctx;
rollback;
