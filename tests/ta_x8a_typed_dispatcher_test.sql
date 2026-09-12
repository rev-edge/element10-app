\set ON_ERROR_STOP on
begin;
do $$
declare o uuid:=gen_random_uuid();o2 uuid:=gen_random_uuid();u uuid:=gen_random_uuid();role_id uuid:=gen_random_uuid();role2 uuid:=gen_random_uuid();cid uuid;j jsonb;before_state jsonb;after_state jsonb;
begin
 insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at)values(u,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','x8ad-'||u||'@x.invalid',now(),now());
 insert into public.e10_organizations(id,slug,name)values(o,'x8ad-'||substr(o::text,1,8),'X8a dispatcher'),(o2,'x8ad-'||substr(o2::text,1,8),'X8a foreign');
 insert into public.e10_organization_roles(id,organization_id,key,name,is_system)values(role_id,o,'x8ad','X8a dispatcher',false),(role2,o2,'x8ad','X8a foreign',false);
 insert into public.e10_organization_memberships(organization_id,user_id,role_id,status)values(o,u,role_id,'active'),(o2,u,role2,'active');
 insert into public.e10_inventory_items(id,name,qty,cost,value,extra,organization_id)values('x8ad-item','Visible item',3,7,11,'{"secret":"must-not-leak","email":"private@example.invalid"}',o);
 insert into public.e10_inventory_movements(workspace_id,item_id,movement_type,on_hand_delta,idempotency_key,note,meta,organization_id)values('shared','x8ad-item','manual_increase',3,'x8ad-move','private note','{"secret":"must-not-leak"}',o);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated')::text,true);set local role authenticated;
 cid:=(public.e10_org_create_query_context(o,'workspace',600,'x8ad-context')->>'context_id')::uuid;reset role;
 select jsonb_build_object('items',(select count(*)from public.e10_inventory_items where organization_id=o),'moves',(select count(*)from public.e10_inventory_movements where organization_id=o),'commands',(select count(*)from public.e10_mutation_receipts where organization_id=o),'events',(select count(*)from public.e10_commercial_events where organization_id=o),'contexts',(select count(*)from public.e10_query_contexts where organization_id=o),'context_commands',(select count(*)from public.e10_query_context_commands where organization_id=o))into before_state;
 set local role authenticated;
 j:=public.e10_org_typed_query(o,cid,'inventory.page','{"limit":10,"filters":{}}');
 if j->>'version'<>'x8-query-v1'or j->>'operation'<>'inventory.page'or j->>'organization_id'<>o::text or j->>'context_id'<>cid::text or j->>'grain'<>'inventory_item'or j#>>'{result,items,0,id}'<>'x8ad-item'then raise exception'inventory page envelope invalid %',j;end if;
 if j#>'{result,items,0}'?'cost'or j#>'{result,items,0}'?'value'or j#>'{result,items,0}'?'secret'or j#>'{result,items,0}'?'email'then raise exception'inventory private field leaked %',j;end if;
 j:=public.e10_org_typed_query(o,cid,'inventory.history','{"limit":10}');
 if j->>'grain'<>'inventory_movement'or j#>>'{result,movements,0,item_id}'is distinct from'x8ad-item'then raise exception'inventory history envelope invalid %',j;end if;
 if j#>'{result,movements,0}'?'note'or j#>'{result,movements,0}'?'meta'then raise exception'movement private field leaked %',j;end if;
 begin perform public.e10_org_typed_query(o,cid,'inventory.page','{"limit":10,"sql":"select 1"}');raise exception'unknown argument accepted';exception when invalid_parameter_value then null;end;
 begin perform public.e10_org_typed_query(o,cid,'arbitrary.sql','{}');raise exception'unknown operation accepted';exception when invalid_parameter_value then null;end;
 begin perform public.e10_org_typed_query(o,cid,'inventory.page',jsonb_build_object('limit',10,'filters',jsonb_build_object('q',repeat('x',2001))));raise exception'oversized nested string accepted';exception when invalid_parameter_value then null;end;
 begin perform public.e10_org_typed_query(o2,cid,'inventory.page','{"limit":10,"filters":{}}');raise exception'foreign org context accepted';exception when insufficient_privilege then null;end;
 reset role;select jsonb_build_object('items',(select count(*)from public.e10_inventory_items where organization_id=o),'moves',(select count(*)from public.e10_inventory_movements where organization_id=o),'commands',(select count(*)from public.e10_mutation_receipts where organization_id=o),'events',(select count(*)from public.e10_commercial_events where organization_id=o),'contexts',(select count(*)from public.e10_query_contexts where organization_id=o),'context_commands',(select count(*)from public.e10_query_context_commands where organization_id=o))into after_state;set local role authenticated;
 if after_state is distinct from before_state then raise exception'non-market query changed state before=% after=%',before_state,after_state;end if;
 perform public.e10_org_revoke_query_context(o,cid,'x8ad-revoke');
 begin perform public.e10_org_typed_query(o,cid,'inventory.page','{"limit":10,"filters":{}}');raise exception'revoked context accepted';exception when insufficient_privilege then null;end;
 reset role;
 if has_function_privilege('anon','public.e10_org_typed_query(uuid,uuid,text,jsonb)','execute')or has_function_privilege('authenticated','e10.x8_assert_args(jsonb,text[])','execute')then raise exception'dispatcher ACL leak';end if;
end $$;
rollback;
select'TA-X8a typed dispatcher PASS'as result;
