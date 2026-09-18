-- TA-X7c immutable, rebuildable provider-time normalization runs.

create table public.e10_provider_presence_normalization_runs(
  id uuid primary key default gen_random_uuid(),organization_id uuid not null,
  provider_key text not null check(length(btrim(provider_key)) between 1 and 100),
  policy_decision_id uuid not null,window_from timestamptz not null check(isfinite(window_from)),
  window_to timestamptz not null check(isfinite(window_to) and window_to>window_from),
  observation_cutoff timestamptz not null check(isfinite(observation_cutoff) and observation_cutoff>=window_to),
  input_reporting_revision bigint not null check(input_reporting_revision>0),
  output_reporting_revision bigint check(output_reporting_revision>input_reporting_revision),
  dependency_fingerprint text not null check(length(dependency_fingerprint)=64),
  algorithm_version text not null check(algorithm_version='provider-presence-v1'),
  status text not null check(status in('building','complete')),
  input_event_count integer not null check(input_event_count>=0),
  interval_count integer not null check(interval_count>=0),
  quarantine_count integer not null check(quarantine_count>=0),
  idempotency_key text not null check(length(btrim(idempotency_key)) between 1 and 500),
  request_fingerprint text not null check(btrim(request_fingerprint)<>''),
  created_by uuid references auth.users(id),created_at timestamptz not null default clock_timestamp(),
  completed_at timestamptz,
  unique(organization_id,id),unique(organization_id,idempotency_key),
  foreign key(organization_id,policy_decision_id)
    references public.e10_provider_presence_normalization_policy_decisions(organization_id,id),
  check((status='building' and output_reporting_revision is null and completed_at is null)
     or(status='complete' and output_reporting_revision is not null and completed_at is not null))
);
create index e10_provider_normalization_run_scope_idx on public.e10_provider_presence_normalization_runs(
  organization_id,provider_key,window_from,window_to,observation_cutoff,created_at desc,id desc
);

create table public.e10_provider_presence_normalized_intervals(
  id uuid primary key default gen_random_uuid(),organization_id uuid not null,run_id uuid not null,
  session_id uuid not null,stream_id uuid not null,
  subject_key text not null check(length(subject_key) between 1 and 300),
  connection_id text not null check(length(connection_id) between 1 and 200),
  original_customer_id uuid,effective_customer_id uuid,
  started_at timestamptz not null check(isfinite(started_at)),
  ended_at timestamptz not null check(isfinite(ended_at) and ended_at>started_at),
  expiry_reason text not null check(expiry_reason in('provider_leave','heartbeat_expiry','join_expiry','session_end','policy_end','retention_end','observation_cutoff')),
  source_event_ids uuid[] not null check(cardinality(source_event_ids) between 1 and 1000 and array_position(source_event_ids,null) is null),
  unique(organization_id,id),
  foreign key(organization_id,run_id) references public.e10_provider_presence_normalization_runs(organization_id,id),
  foreign key(organization_id,session_id) references public.e10_break_sessions(organization_id,id),
  foreign key(organization_id,stream_id) references public.e10_session_presence_streams(organization_id,id),
  foreign key(organization_id,original_customer_id) references public.e10_customers(organization_id,id),
  foreign key(organization_id,effective_customer_id) references public.e10_customers(organization_id,id)
);
create index e10_provider_normalized_interval_read_idx on public.e10_provider_presence_normalized_intervals(
  organization_id,run_id,effective_customer_id,started_at,id
);

create table public.e10_provider_presence_quarantine_rows(
  id uuid primary key default gen_random_uuid(),organization_id uuid not null,run_id uuid not null,
  session_id uuid,stream_id uuid,event_id uuid,
  reason text not null check(reason in('correction_cycle','correction_branch','cross_stream_correction','lineage_bound_exceeded','missing_provider_time','future_provider_time','late_beyond_policy','outside_session','outside_policy','retention_expired','coverage_unavailable','collection_disabled','same_time_conflict','duplicate_semantic_event','missing_join','duplicate_join','negative_interval','event_bound_exceeded')),
  evidence_event_ids uuid[] not null check(cardinality(evidence_event_ids) between 1 and 1000 and array_position(evidence_event_ids,null) is null),
  details jsonb not null check(jsonb_typeof(details)='object' and octet_length(details::text)<=65536),
  unique(organization_id,id),
  foreign key(organization_id,run_id) references public.e10_provider_presence_normalization_runs(organization_id,id),
  foreign key(organization_id,session_id) references public.e10_break_sessions(organization_id,id),
  foreign key(organization_id,stream_id) references public.e10_session_presence_streams(organization_id,id),
  foreign key(organization_id,event_id) references public.e10_session_presence_events(organization_id,id)
);
create index e10_provider_quarantine_read_idx on public.e10_provider_presence_quarantine_rows(
  organization_id,run_id,reason,id
);

alter table public.e10_provider_presence_normalization_runs enable row level security;
alter table public.e10_provider_presence_normalized_intervals enable row level security;
alter table public.e10_provider_presence_quarantine_rows enable row level security;
revoke all on public.e10_provider_presence_normalization_runs,public.e10_provider_presence_normalized_intervals,public.e10_provider_presence_quarantine_rows from public,anon,authenticated;
grant all on public.e10_provider_presence_normalization_runs,public.e10_provider_presence_normalized_intervals,public.e10_provider_presence_quarantine_rows to service_role;
create trigger e10_provider_normalized_interval_immutable before update or delete on public.e10_provider_presence_normalized_intervals for each row execute function e10.reject_append_only_change();
create trigger e10_provider_quarantine_immutable before update or delete on public.e10_provider_presence_quarantine_rows for each row execute function e10.reject_append_only_change();

create function e10.validate_provider_normalization_run_insert() returns trigger language plpgsql security definer set search_path=public as $$
begin
 if new.status<>'building' or new.output_reporting_revision is not null or new.completed_at is not null
    or not exists(select 1 from public.e10_provider_presence_normalization_policy_decisions p where(p.organization_id,p.id,p.provider_key)=(new.organization_id,new.policy_decision_id,new.provider_key))then raise exception using errcode='23503',message='provider_normalization_run_identity_invalid';end if;
 return new;
end $$;
revoke all on function e10.validate_provider_normalization_run_insert() from public,anon,authenticated;grant execute on function e10.validate_provider_normalization_run_insert() to service_role;
create trigger e10_provider_normalization_run_insert before insert on public.e10_provider_presence_normalization_runs for each row execute function e10.validate_provider_normalization_run_insert();

create function e10.validate_provider_normalization_child() returns trigger language plpgsql security definer set search_path=public as $$
declare r record;s record;ids uuid[];
begin
 select * into r from public.e10_provider_presence_normalization_runs where(organization_id,id)=(new.organization_id,new.run_id)for share;
 if not found or r.status<>'building' then raise exception using errcode='55000',message='provider_normalization_run_sealed';end if;
 select * into s from public.e10_session_presence_streams where(organization_id,id)=(new.organization_id,new.stream_id);
 if not found or s.source_class<>'authorized_platform' or s.provider_key<>r.provider_key or s.session_id is distinct from new.session_id then raise exception using errcode='23503',message='provider_normalization_child_identity_invalid';end if;
 if tg_table_name='e10_provider_presence_normalized_intervals' then if(s.subject_key,s.connection_id)is distinct from(new.subject_key,new.connection_id)then raise exception using errcode='23503',message='provider_normalization_child_identity_invalid';end if;ids:=new.source_event_ids;else ids:=new.evidence_event_ids;end if;
 if tg_table_name='e10_provider_presence_quarantine_rows' and to_jsonb(new)->>'event_id' is not null and not exists(select 1 from public.e10_session_presence_events e where(e.organization_id,e.id,e.stream_id)=(new.organization_id,(to_jsonb(new)->>'event_id')::uuid,new.stream_id))then raise exception using errcode='23503',message='provider_normalization_event_identity_invalid';end if;
 if exists(select 1 from unnest(ids)eid where not exists(select 1 from public.e10_session_presence_events e where(e.organization_id,e.id,e.stream_id)=(new.organization_id,eid,new.stream_id)))then raise exception using errcode='23503',message='provider_normalization_event_identity_invalid';end if;
 return new;
end $$;
revoke all on function e10.validate_provider_normalization_child() from public,anon,authenticated;grant execute on function e10.validate_provider_normalization_child() to service_role;
create trigger e10_provider_interval_validate before insert on public.e10_provider_presence_normalized_intervals for each row execute function e10.validate_provider_normalization_child();
create trigger e10_provider_quarantine_validate before insert on public.e10_provider_presence_quarantine_rows for each row execute function e10.validate_provider_normalization_child();

create function e10.seal_provider_normalization_run() returns trigger language plpgsql security definer set search_path=public as $$
begin
 if tg_op='DELETE' or old.status<>'building' or new.status<>'complete'
   or new.interval_count<>(select count(*) from public.e10_provider_presence_normalized_intervals where(organization_id,run_id)=(new.organization_id,new.id))
   or new.quarantine_count<>(select count(*) from public.e10_provider_presence_quarantine_rows where(organization_id,run_id)=(new.organization_id,new.id))
   or row(new.id,new.organization_id,new.provider_key,new.policy_decision_id,new.window_from,new.window_to,new.observation_cutoff,new.input_reporting_revision,new.dependency_fingerprint,new.algorithm_version,new.input_event_count,new.idempotency_key,new.request_fingerprint,new.created_by,new.created_at)
      is distinct from row(old.id,old.organization_id,old.provider_key,old.policy_decision_id,old.window_from,old.window_to,old.observation_cutoff,old.input_reporting_revision,old.dependency_fingerprint,old.algorithm_version,old.input_event_count,old.idempotency_key,old.request_fingerprint,old.created_by,old.created_at) then raise exception using errcode='55000',message='provider_normalization_run_immutable';end if;
 return new;
end $$;
revoke all on function e10.seal_provider_normalization_run() from public,anon,authenticated;grant execute on function e10.seal_provider_normalization_run() to service_role;
create trigger e10_provider_normalization_run_seal before update or delete on public.e10_provider_presence_normalization_runs for each row execute function e10.seal_provider_normalization_run();

comment on table public.e10_provider_presence_normalization_runs is
  'Immutable rebuildable provider normalization snapshots. Current eligibility requires a matching dependency fingerprint, not merely the org presentation revision.';
comment on table public.e10_provider_presence_normalized_intervals is
  'Provider-time half-open intervals. They remain source-separated from companion intervals.';
comment on table public.e10_provider_presence_quarantine_rows is
  'Bounded reasons and evidence for provider rows excluded from normalized attendance.';
