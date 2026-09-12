\set ON_ERROR_STOP 0
begin;
do $$
declare o uuid:=gen_random_uuid();o2 uuid:=gen_random_uuid();u uuid:=gen_random_uuid();u2 uuid:=gen_random_uuid();u3 uuid:=gen_random_uuid();role1 uuid:=gen_random_uuid();role2 uuid:=gen_random_uuid();rel uuid:=gen_random_uuid();v1 uuid:=gen_random_uuid();
 j jsonb;c1 uuid;c2 uuid;res jsonb;i int;n int;
 args jsonb:=jsonb_build_object('scope','catalog','grouping','entity','metric','count','observation_kind','completed_sale','observed_from','2026-01-01T00:00:00Z','observed_to','2026-02-01T00:00:00Z','as_of','2026-02-01T00:00:00Z','source_mode','none','limit',5);
begin
 insert into auth.users(id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)values(u,'authenticated','authenticated','e2-u@x.invalid','',now(),'{}','{}',now(),now()),(u2,'authenticated','authenticated','e2-u2@x.invalid','',now(),'{}','{}',now(),now()),(u3,'authenticated','authenticated','e2-u3@x.invalid','',now(),'{}','{}',now(),now());
 insert into public.e10_organizations(id,slug,name)values(o,'e2-'||substr(o::text,1,8),'E2'),(o2,'e2f-'||substr(o2::text,1,8),'E2 foreign');
 insert into public.e10_organization_roles(id,organization_id,key,name)values(role1,o,'reader','Reader'),(role2,o2,'reader','Reader');
 insert into public.e10_organization_memberships(organization_id,user_id,role_id,status)values(o,u,role1,'active'),(o,u2,role1,'active'),(o2,u2,role2,'active'),(o2,u3,role2,'active');
 insert into public.e10_catalog_releases(id,release_name,release_year,sport)values(rel,'E2 release',2026,'baseball');insert into public.e10_catalog_variants(id,release_id,card_number)values(v1,rel,'1');
 perform set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated')::text,true);set local role authenticated;
 j:=public.e10_org_create_query_context(o,'workspace',600,'e2-c1');c1:=(j->>'context_id')::uuid;
 -- 1. no cap: dispatcher must not escalate
 begin perform public.e10_org_typed_query(o,c1,'market.screener',args);raise notice 'FINDING 1: dispatcher bypassed act.view_market_analytics';exception when others then raise notice '1 no-cap via dispatcher -> % %',sqlstate,sqlerrm;end;
 reset role;insert into public.e10_organization_role_permissions(organization_id,role_id,capability,allowed)values(o,role1,'act.view_market_analytics',true),(o,role1,'act.view_customer_engagement',true);set local role authenticated;
 res:=public.e10_org_typed_query(o,c1,'market.screener',args);raise notice '2 dispatch ok: fp=% rows=%',left(res->>'query_fingerprint',12),jsonb_array_length(res#>'{result,rows}');
 -- 3. other member same org uses c1
 perform set_config('request.jwt.claims',jsonb_build_object('sub',u2,'role','authenticated')::text,true);
 begin perform public.e10_org_typed_query(o,c1,'market.screener',args);raise notice 'FINDING 3: other member used foreign context';exception when others then raise notice '3 other member ctx -> % %',sqlstate,sqlerrm;end;
 -- 4. u2 revokes u's context (non-admin)
 begin perform public.e10_org_revoke_query_context(o,c1,'e2-rv-u2');raise notice 'FINDING 4: non-owner non-admin revoked';exception when others then raise notice '4 non-owner revoke -> % %',sqlstate,sqlerrm;end;
 -- 5. u3 (member only of o2) uses c1 with org o2
 perform set_config('request.jwt.claims',jsonb_build_object('sub',u3,'role','authenticated')::text,true);
 begin perform public.e10_org_typed_query(o2,c1,'market.screener',args);raise notice 'FINDING 5: cross-org context use';exception when others then raise notice '5 cross-org ctx -> % %',sqlstate,sqlerrm;end;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated')::text,true);
 -- 6. revoke and reuse; revoke idempotency
 j:=public.e10_org_revoke_query_context(o,c1,'e2-rv');raise notice '6 revoke ok=% replay=%',j->>'ok',j->>'replay';
 begin perform public.e10_org_typed_query(o,c1,'market.screener',args);raise notice 'FINDING 6: use after revoke';exception when others then raise notice '6 use after revoke -> % %',sqlstate,sqlerrm;end;
 j:=public.e10_org_revoke_query_context(o,c1,'e2-rv');raise notice '6 revoke replay=%',j->>'replay';
 begin perform public.e10_org_revoke_query_context(o,c1,'e2-rv-again');raise notice 'FINDING 6b: double revoke accepted with new key';exception when others then raise notice '6b second revoke new key -> % %',sqlstate,sqlerrm;end;
 begin perform public.e10_org_revoke_query_context(o,gen_random_uuid(),'e2-rv');raise notice 'FINDING 6c: idempotency key reused for different ctx';exception when others then raise notice '6c key reuse other ctx -> % %',sqlstate,sqlerrm;end;
 -- 7. lifetime bounds
 begin perform public.e10_org_create_query_context(o,'workspace',86401,'e2-long');raise notice 'FINDING 7: lifetime > 24h';exception when others then raise notice '7 lifetime 86401 -> % %',sqlstate,sqlerrm;end;
 begin perform public.e10_org_create_query_context(o,'admin',600,'e2-purpose');raise notice 'FINDING 7b: bad purpose';exception when others then raise notice '7b bad purpose -> % %',sqlstate,sqlerrm;end;
 -- 8. expired context
 j:=public.e10_org_create_query_context(o,'workspace',60,'e2-c2');c2:=(j->>'context_id')::uuid;
 reset role;update public.e10_query_contexts set created_at=created_at-interval'2 minutes',expires_at=expires_at-interval'2 minutes' where id=c2;set local role authenticated;
 begin perform public.e10_org_typed_query(o,c2,'market.screener',args);raise notice 'FINDING 8: expired context used';exception when others then raise notice '8 expired ctx -> % %',sqlstate,sqlerrm;end;
 -- 9. membership removal
 j:=public.e10_org_create_query_context(o,'workspace',600,'e2-c3');c2:=(j->>'context_id')::uuid;
 reset role;delete from public.e10_organization_memberships where organization_id=o and user_id=u;set local role authenticated;
 begin perform public.e10_org_typed_query(o,c2,'market.screener',args);raise notice 'FINDING 9: removed member used ctx';exception when others then raise notice '9 removed member -> % %',sqlstate,sqlerrm;end;
 reset role;insert into public.e10_organization_memberships(organization_id,user_id,role_id,status)values(o,u,role1,'active');set local role authenticated;
 -- 10. argument validation
 begin perform public.e10_org_typed_query(o,c2,'market.drop_table',args);raise notice 'FINDING 10a';exception when others then raise notice '10a unknown op -> % %',sqlstate,sqlerrm;end;
 begin perform public.e10_org_typed_query(o,c2,'market.screener',args||'{"evil":1}');raise notice 'FINDING 10b';exception when others then raise notice '10b unknown key -> % %',sqlstate,sqlerrm;end;
 begin perform public.e10_org_typed_query(o,c2,'market.screener',args||'{"limit":"5"}');raise notice 'FINDING 10c';exception when others then raise notice '10c string limit -> % %',sqlstate,sqlerrm;end;
 begin perform public.e10_org_typed_query(o,c2,'market.screener',args||'{"limit":5.5}');raise notice 'FINDING 10d';exception when others then raise notice '10d float limit -> % %',sqlstate,sqlerrm;end;
 begin perform public.e10_org_typed_query(o,c2,'market.screener',args||'{"limit":100000}');raise notice 'FINDING 10e';exception when others then raise notice '10e huge limit -> % %',sqlstate,sqlerrm;end;
 begin perform public.e10_org_typed_query(o,c2,'market.screener',args||'{"limit":99999999999999999999}');raise notice 'FINDING 10f';exception when others then raise notice '10f overflow limit -> % %',sqlstate,sqlerrm;end;
 begin perform public.e10_org_typed_query(o,c2,'market.screener',args||'{"filters":{"release_year":{"$gt":1}}}');raise notice 'FINDING 10g';exception when others then raise notice '10g nested filter -> % %',sqlstate,sqlerrm;end;
 begin perform public.e10_org_typed_query(o,c2,'market.screener',args||'{"filters":{"sport":"x'' or 1=1 --"}}');raise notice '10h sql string in filter accepted (rows=%)',0;exception when others then raise notice '10h sql string -> % %',sqlstate,sqlerrm;end;
 begin perform public.e10_org_typed_query(o,c2,'market.screener',args||'{"cursor":"not-a-uuid"}');raise notice 'FINDING 10i';exception when others then raise notice '10i malformed cursor -> % %',sqlstate,sqlerrm;end;
 begin perform public.e10_org_typed_query(o,c2,'inventory.history',jsonb_build_object('limit',5,'item_id','x'));raise notice '10j ok';exception when others then raise notice '10j inventory.history item_id text -> % %',sqlstate,sqlerrm;end;
 begin perform public.e10_org_typed_query(o,c2,'supplier.workspace',jsonb_build_object('limit',5,'supplier_id','not-a-uuid'));raise notice 'FINDING 10k';exception when others then raise notice '10k malformed supplier_id -> % %',sqlstate,sqlerrm;end;
 begin perform public.e10_org_typed_query(o,c2,'inventory.page',jsonb_build_object('limit',5,'filters',jsonb_build_object('cat',jsonb_build_object('a',1))));raise notice 'FINDING 10l';exception when others then raise notice '10l nested inventory filter -> % %',sqlstate,sqlerrm;end;
 begin perform public.e10_org_typed_query(o,c2,'inventory.page',jsonb_build_object('limit',5,'after',repeat('x',3000)));raise notice 'FINDING 10m';exception when others then raise notice '10m 3000-char string -> % %',sqlstate,sqlerrm;end;
 begin perform public.e10_org_typed_query(o,c2,'attendance.weekly',jsonb_build_object('from','2026-01-01T00:00:00Z','to','2026-01-08T00:00:00Z','observation_cutoff','2026-01-09T00:00:00Z','timezone','UTC','week_start',99999999999,'limit',5));raise notice 'FINDING 10n';exception when others then raise notice '10n week_start overflow -> % %',sqlstate,sqlerrm;end;
 begin perform public.e10_org_typed_query(o,c2,'attendance.weekly',jsonb_build_object('from','2026-01-01T00:00:00Z','to','2026-01-08T00:00:00Z','observation_cutoff','2026-01-09T00:00:00Z','timezone','UTC','week_start',1,'limit',5,'customer','zzz'));raise notice 'FINDING 10o';exception when others then raise notice '10o malformed customer uuid -> % %',sqlstate,sqlerrm;end;
 begin perform public.e10_org_typed_query(o,c2,'attendance.weekly',jsonb_build_object('from','2026-01-01T00:00:00Z','to','2026-01-08T00:00:00Z','observation_cutoff','2026-01-09T00:00:00Z','timezone','UTC','week_start',1,'limit',5,'expected_dataset_revision',99999999999999999999));raise notice 'FINDING 10p';exception when others then raise notice '10p expected_dataset_revision overflow -> % %',sqlstate,sqlerrm;end;
 -- 11. capacity 100
 begin for i in 1..101 loop perform public.e10_org_create_query_context(o,'workspace',600,'e2-cap-'||i);end loop;raise notice 'FINDING 11: >100 live contexts';exception when others then raise notice '11 cap -> % %',sqlstate,sqlerrm;end;
 reset role;select count(*) into n from public.e10_query_contexts where organization_id=o and actor_id=u and revoked_at is null and expires_at>clock_timestamp();raise notice '11 live contexts=%',n;
 raise notice '12 grants: authenticated select query_contexts=% commands=% ; anon exec typed_query=%',has_table_privilege('authenticated','public.e10_query_contexts','select'),has_table_privilege('authenticated','public.e10_query_context_commands','select'),has_function_privilege('anon','public.e10_org_typed_query(uuid,uuid,text,jsonb)','execute');
end $$;
rollback;
