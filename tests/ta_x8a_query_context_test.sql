\set ON_ERROR_STOP on
begin;
do $$
declare o uuid:=gen_random_uuid();o2 uuid:=gen_random_uuid();u uuid:=gen_random_uuid();v uuid:=gen_random_uuid();r uuid:=gen_random_uuid();r2 uuid:=gen_random_uuid();j jsonb;j2 jsonb;cid uuid;old_cid uuid:=gen_random_uuid();old_fp text:=repeat('a',64);
begin
 insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at)values(u,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','x8a-'||u||'@x.invalid',now(),now()),(v,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','x8a-'||v||'@x.invalid',now(),now());
 insert into public.e10_organizations(id,slug,name)values(o,'x8a-'||substr(o::text,1,8),'X8a'),(o2,'x8a-'||substr(o2::text,1,8),'X8a foreign');
 insert into public.e10_organization_roles(id,organization_id,key,name,is_system)values(r,o,'x8a','X8a',false),(r2,o2,'x8a','X8a',false);
 insert into public.e10_organization_memberships(organization_id,user_id,role_id,status)values(o,u,r,'active'),(o2,u,r2,'active');
 perform set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated')::text,true);set local role authenticated;
 j:=public.e10_org_create_query_context(o,'assistant',600,'x8a-create');cid:=(j->>'context_id')::uuid;
 j2:=public.e10_org_create_query_context(o,'assistant',600,'x8a-create');if(j2->>'context_id')::uuid<>cid or(j2->>'replay')::boolean is not true then raise exception'context exact replay failed %',j2;end if;
 begin perform public.e10_org_create_query_context(o,'workspace',600,'x8a-create');raise exception'changed replay accepted';exception when invalid_parameter_value then null;end;
 begin perform public.e10_org_create_query_context(o,'assistant',59,'x8a-short');raise exception'short lifetime accepted';exception when invalid_parameter_value then null;end;
 begin perform public.e10_org_create_query_context(o,'other',600,'x8a-purpose');raise exception'unknown purpose accepted';exception when invalid_parameter_value then null;end;
 reset role;
 begin perform e10.x8_query_context_actor(o2,cid,false);raise exception'foreign org context accepted';exception when insufficient_privilege then null;end;
 if e10.x8_query_context_actor(o,cid,true)<>u then raise exception'context actor guard failed';end if;
 set local role authenticated;
 j:=public.e10_org_revoke_query_context(o,cid,'x8a-revoke');j2:=public.e10_org_revoke_query_context(o,cid,'x8a-revoke');if(j2->>'replay')::boolean is not true then raise exception'revoke exact replay failed';end if;
 reset role;begin perform e10.x8_query_context_actor(o,cid,false);raise exception'revoked context accepted';exception when insufficient_privilege then null;end;set local role authenticated;
 reset role;begin update public.e10_query_context_commands set result='{}'where organization_id=o;raise exception'command update accepted';exception when object_not_in_prerequisite_state then null;end;
 insert into public.e10_query_contexts(id,organization_id,actor_id,purpose,created_at,expires_at)values(old_cid,o,u,'workspace',clock_timestamp()-interval'31 days 1 hour',clock_timestamp()-interval'31 days');
 insert into public.e10_query_context_commands(organization_id,actor_id,idempotency_key,command_type,context_id,request_fingerprint,result,created_at)values(o,u,'x8a-old','create',old_cid,old_fp,jsonb_build_object('context_id',old_cid),clock_timestamp()-interval'31 days');
 perform e10.purge_query_contexts(1000);if exists(select 1 from public.e10_query_contexts where id=old_cid)or exists(select 1 from public.e10_query_context_commands where context_id=old_cid)then raise exception'retention purge failed';end if;
 if(select count(*)from public.e10_query_context_commands where organization_id=o)<>2 then raise exception'command evidence count wrong';end if;
 if not(select relrowsecurity from pg_class where oid='public.e10_query_contexts'::regclass)or not(select relrowsecurity from pg_class where oid='public.e10_query_context_commands'::regclass)then raise exception'context RLS disabled';end if;
 if has_table_privilege('authenticated','public.e10_query_contexts','select')or has_table_privilege('authenticated','public.e10_query_context_commands','select')or has_table_privilege('anon','public.e10_query_contexts','select')then raise exception'context table ACL leak';end if;
 if has_function_privilege('anon','public.e10_org_create_query_context(uuid,text,integer,text)','execute')or has_function_privilege('anon','public.e10_org_revoke_query_context(uuid,uuid,text)','execute')or has_function_privilege('authenticated','e10.x8_query_context_actor(uuid,uuid,boolean)','execute')or has_function_privilege('authenticated','e10.purge_query_contexts(integer)','execute')then raise exception'context function ACL leak';end if;
end $$;
rollback;
select'TA-X8a query context PASS'as result;
