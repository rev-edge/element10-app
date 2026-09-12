\set ON_ERROR_STOP on

begin;
set constraints all deferred;
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

insert into public.e10_customer_transaction_drafts(
  id,organization_id,status,current_revision
) values(
  'a2000000-0000-4000-8000-000000000004','e1000000-0000-4000-8000-0000000000a6','draft',1
);

insert into public.e10_customer_transaction_draft_revisions(
  organization_id,draft_id,revision,customer_id,currency,occurred_at,
  occurred_at_precision,review_note
) values(
  'e1000000-0000-4000-8000-0000000000a6','a2000000-0000-4000-8000-000000000004',1,
  'a2000000-0000-4000-8000-000000000001','CAD','2026-01-01T00:00:00Z','exact',
  'trusted non-managed native fixture'
);

set local session_replication_role = origin;

insert into public.e10_customer_transaction_draft_lines(
  organization_id,draft_id,revision,line_no,purchase_kind,capture_source,
  source_line_id,activity_observation_id,quantity,merchandise_gross,
  merchandise_discount
) values(
  'e1000000-0000-4000-8000-0000000000a6','a2000000-0000-4000-8000-000000000004',
  1,1,'retail','native','r2-trusted-nonmanaged-line',
  'a2000000-0000-4000-8000-000000000003',1,5,0
);

do $$
begin
  if not exists(
    select 1 from public.e10_customer_transaction_draft_lines
    where draft_id='a2000000-0000-4000-8000-000000000004'
      and activity_observation_id='a2000000-0000-4000-8000-000000000003'
  ) then
    raise exception 'trusted non-managed native activity was rejected';
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
