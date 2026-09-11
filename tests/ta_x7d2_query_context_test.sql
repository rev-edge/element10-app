\set ON_ERROR_STOP on
begin;
do $$
declare
 o uuid:=gen_random_uuid();a uuid:=gen_random_uuid();b uuid:=gen_random_uuid();
 fp text;fp2 text;ctx uuid;ctx2 uuid;expired_ctx uuid;reused uuid;cur uuid;i integer;
begin
 insert into auth.users(id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
 values(a,'authenticated','authenticated','x7d-context-a@example.invalid','',now(),'{}','{}',now(),now()),(b,'authenticated','authenticated','x7d-context-b@example.invalid','',now(),'{}','{}',now(),now());
 insert into public.e10_organizations(id,slug,name)values(o,'x7d-context-'||substr(o::text,1,8),'X7d Context');
 fp:=e10.market_query_fingerprint('market-read-v1',o,a,'screener','{"scope":"catalog","limit":50}'::jsonb,'["shop"]'::jsonb,1,1);
 fp2:=e10.market_query_fingerprint('market-read-v1',o,a,'screener','{"limit":50,"scope":"catalog"}'::jsonb,'["shop"]'::jsonb,1,1);
 if fp<>fp2 or fp!~'^[0-9a-f]{64}$'then raise exception'fingerprint is not stable canonical sha256';end if;
 if fp=e10.market_query_fingerprint('market-read-v1',o,b,'screener','{"scope":"catalog","limit":50}'::jsonb,'["shop"]'::jsonb,1,1)then raise exception'fingerprint not actor-bound';end if;
 ctx:=e10.save_market_query_context('market-read-v1',o,a,'screener',fp,'{"scope":"catalog","limit":50}'::jsonb,'["shop"]'::jsonb,1,1,array['cohort-a','cohort-b']);
 select e10.save_market_query_cursor(ctx,o,a,'screener',fp,'{"cohort_key":"cohort-a","amount":"1.2300"}'::jsonb,null,1,1)into cur;
 if not exists(select 1 from public.e10_market_query_contexts where id=ctx and total_row_count=2 and expires_at<=created_at+interval'15 minutes')or not exists(select 1 from public.e10_market_query_cursors where id=cur and sort_position->>'amount'='1.2300')then raise exception'context/cursor persistence failed';end if;
 begin perform e10.save_market_query_cursor(ctx,o,b,'screener',fp,'{}',null,1,1);raise exception'foreign actor cursor accepted';exception when invalid_parameter_value then null;end;
 begin perform e10.save_market_query_cursor(ctx,o,a,'screener',repeat('0',64),'{}',null,1,1);raise exception'rebound cursor accepted';exception when invalid_parameter_value then null;end;
 begin perform e10.save_market_query_context('market-read-v1',o,a,'screener',fp,'{}','[]',1,1,array_fill('x'::text,array[100001]));raise exception'oversized cohort context accepted';exception when invalid_parameter_value then null;end;
 begin perform e10.save_market_query_context('market-read-v1',o,a,'screener',fp,'{"different":true}','["shop"]',1,1,array[]::text[]);raise exception'fingerprint/request mismatch accepted';exception when invalid_parameter_value then null;end;
 begin perform e10.market_query_fingerprint('v1',o,a,null,'{}','[]',1,1);raise exception'NULL endpoint accepted';exception when invalid_parameter_value then null;end;
 begin perform e10.save_market_query_context('v1',o,a,null,fp,'{}','[]',1,1,array[]::text[]);raise exception'NULL context endpoint accepted';exception when invalid_parameter_value then null;end;
 begin perform e10.save_market_query_cursor(ctx,o,a,null,fp,'{}',null,1,1);raise exception'NULL cursor endpoint accepted';exception when invalid_parameter_value then null;end;
 for i in 1..99 loop fp2:=e10.market_query_fingerprint('market-read-v1',o,a,'screener',jsonb_build_object('n',i),'[]',1,1);perform e10.save_market_query_context('market-read-v1',o,a,'screener',fp2,jsonb_build_object('n',i),'[]',1,1,array[]::text[]);end loop;
 fp2:=e10.market_query_fingerprint('market-read-v1',o,a,'screener','{"overflow":true}','[]',1,1);begin perform e10.save_market_query_context('market-read-v1',o,a,'screener',fp2,'{"overflow":true}','[]',1,1,array[]::text[]);raise exception'live context cap not enforced';exception when program_limit_exceeded then null;end;
 fp2:=e10.market_query_fingerprint('market-read-v1',o,b,'drilldown','{"parent":"x"}','[]',1,1);ctx2:=e10.save_market_query_context('market-read-v1',o,b,'drilldown',fp2,'{"parent":"x"}','[]',1,1,array['allowed-cohort']);
 begin perform e10.save_market_query_cursor(ctx2,o,b,'drilldown',fp2,'{}','wrong-cohort',1,1);raise exception'foreign parent cohort accepted';exception when invalid_parameter_value then null;end;
 perform e10.save_market_query_cursor(ctx2,o,b,'drilldown',fp2,'{}','allowed-cohort',1,1);
 insert into public.e10_market_query_contexts(organization_id,actor_id,endpoint,api_version,query_fingerprint,normalized_request,resolved_source_universe,organization_revision,catalog_revision,cohort_keys,total_row_count,created_at,expires_at)values(o,b,'screener','v1',repeat('1',64),'{}','[]',1,1,array[]::text[],0,statement_timestamp()-interval'20 minutes',statement_timestamp()-interval'5 minutes')returning id into expired_ctx;
 begin perform e10.save_market_query_cursor(expired_ctx,o,b,'screener',repeat('1',64),'{}',null,1,1);raise exception'expired context accepted';exception when invalid_parameter_value then null;end;
 reused:=e10.save_market_query_context('market-read-v1',o,b,'drilldown',fp2,'{"parent":"x"}','[]',1,1,array['allowed-cohort']);
 if reused<>ctx2 then raise exception'context reuse failed: expected %, got %',ctx2,reused;end if;
 begin perform e10.save_market_query_context('market-read-v1',o,b,'drilldown',fp2,'{"parent":"x"}','[]',1,1,array['different-cohort']);raise exception'context cohort mismatch accepted';exception when invalid_parameter_value then null;end;
 if exists(select 1 from public.e10_market_query_contexts where id=expired_ctx)then raise exception'expired context cleanup failed';end if;
 if not exists(select 1 from public.e10_market_query_contexts where id=ctx)then raise exception'cleanup crossed actor boundary';end if;
 for i in 2..1000 loop perform e10.save_market_query_cursor(ctx2,o,b,'drilldown',fp2,jsonb_build_object('n',i),'allowed-cohort',1,1);end loop;
 begin perform e10.save_market_query_cursor(ctx2,o,b,'drilldown',fp2,'{"overflow":true}','allowed-cohort',1,1);raise exception'live cursor cap not enforced';exception when program_limit_exceeded then null;end;
 begin update public.e10_market_query_contexts set total_row_count=1 where id=ctx;raise exception'context update accepted';exception when object_not_in_prerequisite_state then null;end;
 delete from public.e10_market_query_contexts where id=ctx2;if exists(select 1 from public.e10_market_query_cursors where context_id=ctx2)then raise exception'cursor cleanup cascade failed';end if;
 if has_table_privilege('anon','public.e10_market_query_contexts','select')or has_table_privilege('authenticated','public.e10_market_query_contexts','select')or has_table_privilege('anon','public.e10_market_query_cursors','select')or has_table_privilege('authenticated','public.e10_market_query_cursors','select')then raise exception'query state table ACL leak';end if;
 if has_function_privilege('anon','e10.market_query_fingerprint(text,uuid,uuid,text,jsonb,jsonb,bigint,bigint)','execute')or has_function_privilege('authenticated','e10.market_query_fingerprint(text,uuid,uuid,text,jsonb,jsonb,bigint,bigint)','execute')or has_function_privilege('anon','e10.save_market_query_context(text,uuid,uuid,text,text,jsonb,jsonb,bigint,bigint,text[])','execute')or has_function_privilege('authenticated','e10.save_market_query_context(text,uuid,uuid,text,text,jsonb,jsonb,bigint,bigint,text[])','execute')or has_function_privilege('anon','e10.save_market_query_cursor(uuid,uuid,uuid,text,text,jsonb,text,bigint,bigint)','execute')or has_function_privilege('authenticated','e10.save_market_query_cursor(uuid,uuid,uuid,text,text,jsonb,text,bigint,bigint)','execute')then raise exception'query state helper ACL leak';end if;
 if not(select relrowsecurity from pg_class where oid='public.e10_market_query_contexts'::regclass)or not(select relrowsecurity from pg_class where oid='public.e10_market_query_cursors'::regclass)then raise exception'query state RLS disabled';end if;
end $$;
rollback;
select'TA-X7d.2 query context PASS'as result;
