\set ON_ERROR_STOP on
begin;
do $$
declare
  a uuid:='e1000000-0000-4000-8000-0000000000a6'; b uuid:=gen_random_uuid(); ua uuid:=gen_random_uuid(); ub uuid:=gen_random_uuid(); ra uuid:=gen_random_uuid(); rb uuid:=gen_random_uuid();
  ca uuid:=gen_random_uuid(); cb uuid:=gen_random_uuid(); session_a uuid:=gen_random_uuid(); slot_a uuid:=gen_random_uuid(); result jsonb; activity uuid; event_id uuid;
begin
  insert into public.e10_organizations(id,name,slug) values(b,'X6a B','x6a-'||replace(b::text,'-',''));
  insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at) values
    (ua,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',ua||'@x.invalid',now(),now()),
    (ub,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',ub||'@x.invalid',now(),now());
  insert into public.e10_organization_roles(id,organization_id,key,name,is_system) values(ra,a,'x6a-'||ua,'X6a A',false),(rb,b,'x6a-'||ub,'X6a B',false);
  insert into public.e10_organization_role_permissions values(a,ra,'act.record_commercial_events',true),(b,rb,'act.record_commercial_events',true);
  insert into public.e10_organization_memberships(organization_id,user_id,role_id,status) values(a,ua,ra,'active'),(b,ub,rb,'active');
  insert into public.e10_customers(id,organization_id,auth_user_id,display_name,status) values(ca,a,ua,'Customer A','active'),(cb,b,ub,'Customer B','active');
  insert into public.e10_break_sessions(id,organization_id,name,streamer_uid,share_code) values(session_a,a,'X6a Session',ua,'x6a-'||substr(session_a::text,1,8));
  insert into public.e10_break_slots(id,organization_id,session_id,label,price,state,buyer_uid,buyer_handle,position) values(slot_a,a,session_a,'Slot',30,'held',ua,'buyer-a',1);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',ua,'role','authenticated')::text,true);
  result:=public.e10_org_record_customer_activity(a,'break',ca,ua,'buyer-a',session_a,slot_a,1,30,0,0,0,'CAD','auction','2026-01-01T00:00:00Z','exact','manual',null,'operator','sale-a','{"slot":"a"}','operator_asserted','x6a-a');
  activity:=(result->>'activity_id')::uuid; event_id:=(result->>'event_id')::uuid;
  if (result->>'posted')::boolean then raise exception 'provisional activity marked posted'; end if;
  if not exists(select 1 from public.e10_customer_activity_observations where id=activity and merchandise_net=30 and activity_kind='break' and buyer_identity_status='verified_auth') then raise exception 'activity or verified identity missing'; end if;
  if not exists(select 1 from public.e10_commercial_events where id=event_id and customer_activity_observation_id=activity and event_type='sale_committed' and payload->>'provisional_only'='true') then raise exception 'atomic activity event missing'; end if;
  result:=public.e10_org_record_customer_activity(a,'break',ca,ua,'buyer-a',session_a,slot_a,1,30,0,0,0,'CAD','auction','2025-12-31T19:00:00-05','exact','manual',null,'operator','sale-a','{"slot":"a"}','operator_asserted','x6a-a');
  if not (result->>'replay')::boolean or (result->>'activity_id')::uuid<>activity then raise exception 'activity replay failed'; end if;
  begin perform public.e10_org_record_customer_activity(a,'break',ca,ua,'buyer-a',session_a,slot_a,1,31,0,0,0,'CAD','auction',now(),'exact','manual',null,'operator','sale-a2','{}','operator_asserted','x6a-a'); raise exception 'idempotency mismatch accepted'; exception when sqlstate '22023' then null; end;
  begin perform public.e10_org_record_customer_activity(a,'break',ca,ub,'buyer-b',session_a,slot_a,1,30,0,0,0,'CAD','auction',now(),'exact','manual',null,'operator','sale-identity-mismatch','{}','operator_asserted','x6a-identity-mismatch'); raise exception 'foreign buyer user attributed to customer'; exception when sqlstate '22023' then null; end;
  result:=public.e10_org_record_customer_activity(a,'retail',null,ub,'external-buyer',null,null,1,40,null,null,null,'CAD','import','2026-01-02T00:00:00Z','exact','import','marketplace','order.csv','retail-unknown-components','{}','imported_unreviewed','x6a-unknown-components');
  if not exists(select 1 from public.e10_customer_activity_observations where id=(result->>'activity_id')::uuid and buyer_identity_status='unresolved' and merchandise_discount is null and shipping_amount is null and tax_amount is null and merchandise_net is null) then raise exception 'unknown source components or identity were fabricated'; end if;
  begin perform public.e10_org_record_customer_activity(a,'break',cb,ua,'buyer-a',session_a,slot_a,1,30,0,0,0,'CAD','auction',now(),'exact','manual',null,'operator','sale-cross-customer','{}','operator_asserted','x6a-cross-customer'); raise exception 'foreign customer accepted'; exception when insufficient_privilege then null; end;
  begin perform public.e10_org_record_customer_activity(b,'break',cb,ub,'buyer-b',session_a,slot_a,1,30,0,0,0,'CAD','auction',now(),'exact','manual',null,'operator','sale-cross-session','{}','operator_asserted','x6a-cross-session'); raise exception 'foreign session accepted'; exception when insufficient_privilege then null; end;
  if exists(select 1 from public.e10_customer_activity_observations where organization_id=a and break_slot_id=slot_a and id<>activity) then raise exception 'held slot or retry fabricated activity'; end if;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',ub,'role','authenticated')::text,true); perform set_config('role','authenticated',true);
  begin perform public.e10_org_record_customer_activity(a,'break',ca,ua,'buyer-a',session_a,slot_a,1,30,0,0,0,'CAD','auction',now(),'exact','manual',null,'operator','hostile','{}','operator_asserted','x6a-hostile'); raise exception 'cross-org writer accepted'; exception when insufficient_privilege then null; end;
  begin perform 1 from public.e10_customer_activity_observations where id=activity; raise exception 'direct activity select allowed'; exception when insufficient_privilege then null; end;
  perform set_config('role','postgres',true);
  raise notice 'TA-X6a customer activity: PASS (provisional, atomic event, replay, no hold spend, hostile tenant denial)';
end $$;
rollback;
