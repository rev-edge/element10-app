\set ON_ERROR_STOP 0
begin;
do $$
declare o uuid:=gen_random_uuid();u uuid:=gen_random_uuid();rid uuid:=gen_random_uuid();cust uuid:=gen_random_uuid();s uuid:=gen_random_uuid();j jsonb;n int;c1 uuid;deep jsonb;big jsonb;r record;
begin
 insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at)values(u,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','e8-'||u||'@x.invalid',now(),now());
 insert into public.e10_organizations(id,slug,name)values(o,'e8-'||substr(o::text,1,8),'E8');
 insert into public.e10_organization_roles(id,organization_id,key,name,is_system)values(rid,o,'e8','E8',false);
 insert into public.e10_organization_role_permissions values(o,rid,'act.view_customer_engagement',true),(o,rid,'act.view_customer_financials',true),(o,rid,'act.manage_attendance_coverage',true);
 insert into public.e10_organization_memberships(organization_id,user_id,role_id,status)values(o,u,rid,'active');
 insert into public.e10_customers(id,organization_id,display_name)values(cust,o,'C1');
 insert into public.e10_break_sessions(id,organization_id,streamer_uid,name,status,ended_at,visibility)values(s,o,u,'E8','ended','2026-01-06T12:00:00Z','private');
 raise notice '0 grants: v1 dispatcher exec by authenticated=%',has_function_privilege('authenticated','public.e10_org_typed_query_v1(uuid,uuid,text,jsonb)','execute');
 perform set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated')::text,true);set local role authenticated;
 j:=public.e10_org_create_query_context(o,'workspace',600,'e8-c1');c1:=(j->>'context_id')::uuid;
 -- 1. suspended org: X7c reads and X8 context
 reset role;update public.e10_organizations set status='suspended' where id=o;set local role authenticated;
 begin select count(*) into n from public.e10_org_provider_attendance_quarantine(o,'prov','2026-01-01','2026-01-08','2026-01-09',null,10,null,null,null);raise notice '1a suspended org provider quarantine rows=% (X7c read allowed)',n;exception when others then raise notice '1a -> % %',sqlstate,sqlerrm;end;
 begin select count(*) into n from public.e10_org_provider_attendance_intervals(o,'prov',s,null,'2026-01-01','2026-01-08','2026-01-09',10,null,null,null,null);raise notice '1b suspended org provider intervals rows=% (X7c read allowed)',n;exception when others then raise notice '1b -> % %',sqlstate,sqlerrm;end;
 begin select count(*) into n from public.e10_org_source_attendance_summary(o,'prov',s,cust,'2026-01-01','2026-01-08','2026-01-09');raise notice '1c suspended org source summary rows=% (X7c read allowed)',n;exception when others then raise notice '1c -> % %',sqlstate,sqlerrm;end;
 begin select count(*) into n from public.e10_org_attendance_contributions(o,'2026-01-01','2026-01-08','2026-01-09',null,'companion','companion',10,null,null,null,null);raise notice '1d suspended org contributions rows=% (X7a read allowed)',n;exception when others then raise notice '1d -> % %',sqlstate,sqlerrm;end;
 begin perform public.e10_org_typed_query(o,c1,'attendance.weekly',jsonb_build_object('from','2026-01-01T00:00:00Z','to','2026-01-08T00:00:00Z','observation_cutoff','2026-01-09T00:00:00Z','timezone','UTC','week_start',1,'limit',5));raise notice 'FINDING 1e: X8 dispatcher allowed suspended org';exception when others then raise notice '1e suspended org via dispatcher -> % %',sqlstate,sqlerrm;end;
 reset role;update public.e10_organizations set status='active' where id=o;set local role authenticated;
 -- 2. v2 route cursor bypasses x8_validate_json? deep/huge cursor object
 deep:='1'::jsonb;for n in 1..40 loop deep:=jsonb_build_object('k',deep);end loop;
 select jsonb_object_agg('k'||i,repeat('x',5000)) into big from generate_series(1,300)i;
 begin perform public.e10_org_typed_query(o,c1,'customer.spend_summary',jsonb_build_object('window_mode','custom','from','2026-01-01T00:00:00Z','to','2026-01-08T00:00:00Z','observation_cutoff','2026-01-09T00:00:00Z','currency','USD','timezone','UTC','week_start',1,'limit',5,'cursor',deep));raise notice '2a deep cursor accepted';exception when others then raise notice '2a deep v2 cursor -> % %',sqlstate,left(sqlerrm,80);end;
 begin perform public.e10_org_typed_query(o,c1,'customer.spend_summary',jsonb_build_object('window_mode','custom','from','2026-01-01T00:00:00Z','to','2026-01-08T00:00:00Z','observation_cutoff','2026-01-09T00:00:00Z','currency','USD','timezone','UTC','week_start',1,'limit',5,'cursor',big));raise notice '2b 1.5MB cursor accepted';exception when others then raise notice '2b huge v2 cursor -> % %',sqlstate,left(sqlerrm,80);end;
 begin perform public.e10_org_typed_query(o,c1,'customer.spend_summary',jsonb_build_object('window_mode','custom','from','2026-01-01T00:00:00Z','to','2026-01-08T00:00:00Z','observation_cutoff','2026-01-09T00:00:00Z','currency','USD','timezone','UTC','week_start',1,'limit',5,'cursor','str'));raise notice '2c string cursor accepted';exception when others then raise notice '2c string v2 cursor -> % %',sqlstate,left(sqlerrm,80);end;
 begin j:=public.e10_org_typed_query(o,c1,'customer.spend_summary',jsonb_build_object('window_mode','custom','from','2026-01-01T00:00:00Z','to','2026-01-08T00:00:00Z','observation_cutoff','2026-01-09T00:00:00Z','currency','USD','timezone','UTC','week_start',1,'limit',5));raise notice '2d v2 ok items=%',jsonb_array_length(j#>'{result,items}');exception when others then raise notice '2d v2 baseline -> % %',sqlstate,left(sqlerrm,120);end;
 -- 3. screener via dispatcher: does the dispatcher ever expose data the direct RPC redacts? compare direct vs dispatcher output keys for the screener
 reset role;insert into public.e10_organization_role_permissions values(o,rid,'act.view_market_analytics',true);set local role authenticated;
 j:=public.e10_org_typed_query(o,c1,'market.screener',jsonb_build_object('scope','catalog','grouping','entity','metric','count','observation_kind','completed_sale','observed_from','2026-01-01T00:00:00Z','observed_to','2026-02-01T00:00:00Z','as_of','2026-02-01T00:00:00Z','source_mode','none','limit',5));
 raise notice '3 dispatcher screener result keys=%',(select string_agg(k,',' order by k) from jsonb_object_keys(j->'result')k);
 j:=public.e10_org_market_screener(o,'catalog','entity','count','completed_sale','2026-01-01','2026-02-01','2026-02-01',null,'none',null,null,'{}','cohort_asc',5,null);
 raise notice '3 direct screener result keys=%',(select string_agg(k,',' order by k) from jsonb_object_keys(j)k);
end $$;
rollback;
