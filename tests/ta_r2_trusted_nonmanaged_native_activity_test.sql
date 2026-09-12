\set ON_ERROR_STOP on

begin;
set constraints all deferred;

insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at)
values('a2000000-0000-4000-8000-000000000010','00000000-0000-0000-0000-000000000000',
       'authenticated','authenticated','r2-trusted-native@example.invalid',now(),now());

insert into public.e10_organization_roles(id,organization_id,key,name,is_system)
values('a2000000-0000-4000-8000-000000000011','e1000000-0000-4000-8000-0000000000a6',
       'r2_trusted_native','R2 trusted native',false);

insert into public.e10_organization_role_permissions(organization_id,role_id,capability)
values
 ('e1000000-0000-4000-8000-0000000000a6','a2000000-0000-4000-8000-000000000011','act.prepare_customer_transactions'),
 ('e1000000-0000-4000-8000-0000000000a6','a2000000-0000-4000-8000-000000000011','act.approve_customer_transactions'),
 ('e1000000-0000-4000-8000-0000000000a6','a2000000-0000-4000-8000-000000000011','act.post_customer_transactions');

insert into public.e10_organization_memberships(organization_id,user_id,role_id,status)
values('e1000000-0000-4000-8000-0000000000a6','a2000000-0000-4000-8000-000000000010',
       'a2000000-0000-4000-8000-000000000011','active');

set local session_replication_role = replica;

insert into public.e10_customers(id,organization_id,display_name)
values('a2000000-0000-4000-8000-000000000001','e1000000-0000-4000-8000-0000000000a6','R2 trusted native');

insert into public.e10_commercial_events(
  id,organization_id,event_type,subject_type,subject_id,occurred_at,
  idempotency_key,source_kind,payload,request_fingerprint,
  occurred_at_precision,source_event_id,evidence_quality,
  customer_activity_observation_id
) values(
  'a2000000-0000-4000-8000-000000000002','e1000000-0000-4000-8000-0000000000a6',
  'sale_committed','sale','trusted-nonmanaged','2026-01-01T00:00:00Z',
  'r2-trusted-nonmanaged-event','native','{}','r2-trusted-nonmanaged-event-fp',
  'exact','r2-trusted-nonmanaged-source','native_system',
  'a2000000-0000-4000-8000-000000000003'
);

insert into public.e10_customer_activity_observations(
  id,organization_id,activity_kind,customer_id,buyer_identity_status,
  quantity,merchandise_gross,merchandise_discount,currency,occurred_at,
  occurred_at_precision,source_kind,source_event_id,raw_payload,
  evidence_quality,idempotency_key,request_fingerprint,commercial_event_id
) values(
  'a2000000-0000-4000-8000-000000000003','e1000000-0000-4000-8000-0000000000a6',
  'retail','a2000000-0000-4000-8000-000000000001','reviewed_attributed',
  1,5,0,'CAD','2026-01-01T00:00:00Z','exact','native',
  'r2-trusted-nonmanaged-source','{}','native_system',
  'r2-trusted-nonmanaged-activity','r2-trusted-nonmanaged-activity-fp',
  'a2000000-0000-4000-8000-000000000002'
);

set local session_replication_role = origin;

select set_config('request.jwt.claims',
  '{"sub":"a2000000-0000-4000-8000-000000000010","role":"authenticated"}',true);
set local role authenticated;

do $$
declare v_draft uuid;v_tx uuid;v_result jsonb;
begin
  v_result:=public.e10_org_create_customer_transaction_draft(
    'e1000000-0000-4000-8000-0000000000a6','a2000000-0000-4000-8000-000000000001',
    'CAD','2026-01-01T00:00:00Z','exact','trusted non-managed native public flow',
    jsonb_build_array(jsonb_build_object(
      'purchase_kind','retail','capture_source','native',
      'source_line_id','r2-trusted-nonmanaged-line',
      'activity_observation_id','a2000000-0000-4000-8000-000000000003',
      'quantity',1,'merchandise_gross',5,'merchandise_discount',0)),
    'r2-trusted-nonmanaged-draft');
  v_draft:=(v_result->>'draft_id')::uuid;
  perform public.e10_org_approve_customer_transaction_draft(
    'e1000000-0000-4000-8000-0000000000a6',v_draft,1,
    'r2-trusted-nonmanaged-approve');
  v_result:=public.e10_org_post_customer_transaction_draft(
    'e1000000-0000-4000-8000-0000000000a6',v_draft,1,
    'r2-trusted-nonmanaged-post');
  v_tx:=(v_result->>'transaction_id')::uuid;

end $$;

reset role;

do $$
begin
  if not exists(
    select 1 from public.e10_customer_transaction_lines
    where source_line_id='r2-trusted-nonmanaged-line' and capture_source='native'
      and activity_observation_id='a2000000-0000-4000-8000-000000000003'
  ) then
    raise exception 'trusted non-managed native public draft/approve/post was rejected';
  end if;
  if exists(
    select 1 from public.e10_native_break_sales
    where activity_observation_id='a2000000-0000-4000-8000-000000000003'
  ) then
    raise exception 'trusted non-managed fixture became managed sale evidence';
  end if;
  if has_function_privilege('authenticated',
    'e10.customer_source_is_reviewed_new_transaction(uuid,text,text,text)',
    'execute') then
    raise exception 'internal reconciliation helper exposed to authenticated';
  end if;
end $$;

rollback;
select 'TA-R2 trusted non-managed native activity: PASS' as result;
