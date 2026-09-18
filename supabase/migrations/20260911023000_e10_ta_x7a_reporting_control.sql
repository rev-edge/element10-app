-- TA-X7a reporting control plane: reviewed coverage and transaction-consistent dataset revisions.

create table public.e10_attendance_coverage_assertions(
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.e10_organizations(id),
  coverage_key uuid not null,
  revision bigint not null check(revision>0),
  action text not null check(action in('assert','revoke')),
  source_class text not null check(source_class in('companion','authorized_platform')),
  provider_key text not null check(length(btrim(provider_key)) between 1 and 100),
  covered_from timestamptz not null check(isfinite(covered_from)),
  covered_to timestamptz not null check(isfinite(covered_to) and covered_to>covered_from),
  coverage_status text,
  policy_version bigint not null check(policy_version>0),
  review_basis text not null check(length(btrim(review_basis)) between 1 and 2000),
  evidence jsonb not null check(jsonb_typeof(evidence)='object' and octet_length(evidence::text)<=65536),
  supersedes_assertion_id uuid,
  idempotency_key text not null check(length(btrim(idempotency_key)) between 1 and 500),
  request_fingerprint text not null check(btrim(request_fingerprint)<>''),
  reviewed_by uuid references auth.users(id),
  reviewed_at timestamptz not null default clock_timestamp(),
  unique(organization_id,id),
  unique(organization_id,coverage_key,revision),
  unique(organization_id,idempotency_key),
  foreign key(organization_id,supersedes_assertion_id)
    references public.e10_attendance_coverage_assertions(organization_id,id),
  check((action='assert' and coverage_status is not null and coverage_status in('complete','partial','unavailable'))
     or(action='revoke' and coverage_status is null))
);
create unique index e10_attendance_coverage_root_uq
  on public.e10_attendance_coverage_assertions(organization_id,coverage_key)
  where supersedes_assertion_id is null;
create unique index e10_attendance_coverage_successor_uq
  on public.e10_attendance_coverage_assertions(organization_id,supersedes_assertion_id)
  where supersedes_assertion_id is not null;
create index e10_attendance_coverage_window_idx
  on public.e10_attendance_coverage_assertions(organization_id,source_class,provider_key,covered_from,covered_to);

create table public.e10_reporting_dataset_revisions(
  organization_id uuid primary key references public.e10_organizations(id) on delete cascade,
  revision bigint not null default 1 check(revision>0),
  changed_at timestamptz not null default clock_timestamp()
);
insert into public.e10_reporting_dataset_revisions(organization_id)
select id from public.e10_organizations on conflict(organization_id) do nothing;

create table public.e10_presence_policy_state_history(
  id uuid primary key default gen_random_uuid(),organization_id uuid not null,
  source_class text not null,provider_key text not null,policy_version bigint not null,
  enabled boolean not null,state_from timestamptz not null check(isfinite(state_from)),
  recorded_at timestamptz not null default clock_timestamp(),
  unique(organization_id,id),unique(organization_id,source_class,provider_key,policy_version,state_from),
  foreign key(organization_id,source_class,provider_key,policy_version)
    references public.e10_presence_collection_policies(organization_id,source_class,provider_key,policy_version)
);
insert into public.e10_presence_policy_state_history(
  organization_id,source_class,provider_key,policy_version,enabled,state_from
)
select organization_id,source_class,provider_key,policy_version,enabled,clock_timestamp()
from public.e10_presence_collection_policies;

alter table public.e10_attendance_coverage_assertions enable row level security;
alter table public.e10_reporting_dataset_revisions enable row level security;
alter table public.e10_presence_policy_state_history enable row level security;
revoke all on public.e10_attendance_coverage_assertions,public.e10_reporting_dataset_revisions
  from public,anon,authenticated;
revoke all on public.e10_presence_policy_state_history from public,anon,authenticated;
grant all on public.e10_attendance_coverage_assertions,public.e10_reporting_dataset_revisions to service_role;
grant all on public.e10_presence_policy_state_history to service_role;

create trigger e10_attendance_coverage_immutable
  before update or delete on public.e10_attendance_coverage_assertions
  for each row execute function e10.reject_append_only_change();
create trigger e10_presence_policy_state_immutable
  before update or delete on public.e10_presence_policy_state_history
  for each row execute function e10.reject_append_only_change();

create function e10.record_presence_policy_state() returns trigger
language plpgsql security definer set search_path=public as $$
declare v_from timestamptz;
begin
  if tg_op='INSERT' then v_from:=clock_timestamp();
  elsif new.enabled is not distinct from old.enabled then return new;
  else v_from:=clock_timestamp();end if;
  insert into public.e10_presence_policy_state_history(
    organization_id,source_class,provider_key,policy_version,enabled,state_from
  ) values(new.organization_id,new.source_class,new.provider_key,new.policy_version,new.enabled,v_from);
  return new;
end $$;
revoke all on function e10.record_presence_policy_state() from public,anon,authenticated;
grant execute on function e10.record_presence_policy_state() to service_role;
create trigger e10_presence_policy_state_record
  after insert or update of enabled on public.e10_presence_collection_policies
  for each row execute function e10.record_presence_policy_state();

create function e10.presence_policy_supports_complete_coverage(
  p_org uuid,p_source_class text,p_provider_key text,p_policy_version bigint,
  p_from timestamptz,p_to timestamptz
) returns boolean language sql stable security definer set search_path=public as $$
  with states as(
    select h.enabled,h.state_from,
      lead(h.state_from,1,'infinity'::timestamptz)over(order by h.state_from) state_to
    from public.e10_presence_policy_state_history h
    where h.organization_id=p_org and h.source_class=p_source_class
      and h.provider_key=p_provider_key and h.policy_version=p_policy_version
  )
  select exists(
    select 1 from public.e10_presence_collection_policies p
    where p.organization_id=p_org and p.source_class=p_source_class
      and p.provider_key=p_provider_key and p.policy_version=p_policy_version
      and p_from>=p.effective_from and(p.effective_through is null or p_to<=p.effective_through)
  ) and not exists(select 1 from states where not enabled and state_from<p_to and state_to>p_from)
$$;
revoke all on function e10.presence_policy_supports_complete_coverage(uuid,text,text,bigint,timestamptz,timestamptz)
  from public,anon,authenticated;
grant execute on function e10.presence_policy_supports_complete_coverage(uuid,text,text,bigint,timestamptz,timestamptz)
  to service_role;

create view public.e10_current_attendance_coverage_assertions with(security_invoker=true) as
select a.*
from public.e10_attendance_coverage_assertions a
where a.action='assert'
  and not exists(
    select 1 from public.e10_attendance_coverage_assertions n
    where n.organization_id=a.organization_id and n.supersedes_assertion_id=a.id
  );
revoke all on public.e10_current_attendance_coverage_assertions from public,anon,authenticated;
grant select on public.e10_current_attendance_coverage_assertions to service_role;

create function e10.bump_reporting_dataset_revision() returns trigger
language plpgsql security definer set search_path=public as $$
declare v_org uuid;
begin
  v_org:=case when tg_op='DELETE' then old.organization_id else new.organization_id end;
  insert into public.e10_reporting_dataset_revisions(organization_id,revision,changed_at)
  values(v_org,1,clock_timestamp())
  on conflict(organization_id) do update
    set revision=public.e10_reporting_dataset_revisions.revision+1,
        changed_at=excluded.changed_at;
  return case when tg_op='DELETE' then old else new end;
end $$;
revoke all on function e10.bump_reporting_dataset_revision() from public,anon,authenticated;
grant execute on function e10.bump_reporting_dataset_revision() to service_role;

create function e10.initialize_reporting_dataset_revision() returns trigger
language plpgsql security definer set search_path=public as $$
begin
  insert into public.e10_reporting_dataset_revisions(organization_id) values(new.id)
  on conflict(organization_id) do nothing;
  return new;
end $$;
revoke all on function e10.initialize_reporting_dataset_revision() from public,anon,authenticated;
grant execute on function e10.initialize_reporting_dataset_revision() to service_role;
create trigger e10_reporting_revision_org_init
  after insert on public.e10_organizations
  for each row execute function e10.initialize_reporting_dataset_revision();

create trigger e10_reporting_revision_presence_policy
  after insert or update or delete on public.e10_presence_collection_policies
  for each row execute function e10.bump_reporting_dataset_revision();
create trigger e10_reporting_revision_presence_policy_state
  after insert on public.e10_presence_policy_state_history
  for each row execute function e10.bump_reporting_dataset_revision();
create trigger e10_reporting_revision_presence_stream
  after insert on public.e10_session_presence_streams
  for each row execute function e10.bump_reporting_dataset_revision();
create trigger e10_reporting_revision_presence_segment
  after insert on public.e10_session_presence_segments
  for each row execute function e10.bump_reporting_dataset_revision();
create trigger e10_reporting_revision_presence_event
  after insert on public.e10_session_presence_events
  for each row execute function e10.bump_reporting_dataset_revision();
create trigger e10_reporting_revision_presence_attribution
  after insert on public.e10_session_presence_attribution_decisions
  for each row execute function e10.bump_reporting_dataset_revision();
create trigger e10_reporting_revision_customer_resolution
  after insert on public.e10_customer_resolution_decisions
  for each row execute function e10.bump_reporting_dataset_revision();
create trigger e10_reporting_revision_session_bounds
  after update of status,ended_at on public.e10_break_sessions
  for each row
  when(old.status is distinct from new.status or old.ended_at is distinct from new.ended_at)
  execute function e10.bump_reporting_dataset_revision();
create trigger e10_reporting_revision_coverage
  after insert on public.e10_attendance_coverage_assertions
  for each row execute function e10.bump_reporting_dataset_revision();

create function public.e10_org_review_attendance_coverage(
  p_org uuid,p_coverage_key uuid,p_expected_revision bigint,p_action text,
  p_source_class text,p_provider_key text,p_from timestamptz,p_to timestamptz,
  p_coverage_status text,p_policy_version bigint,p_review_basis text,p_evidence jsonb,
  p_idempotency_key text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare
  v_actor uuid:=auth.uid();v_key uuid:=p_coverage_key;
  v_prior record;v_replay record;v_id uuid:=gen_random_uuid();v_fp text;v_result jsonb;
begin
  if v_actor is null or not e10.is_org_member(p_org)
     or not e10.has_org_cap(p_org,'act.manage_attendance_coverage') then
    raise exception using errcode='42501',message='attendance_coverage_review_denied';
  end if;
  if p_expected_revision is null or p_expected_revision<0
     or p_action is null or p_action not in('assert','revoke')
     or p_source_class is null or p_source_class not in('companion','authorized_platform')
     or p_provider_key is null or length(btrim(p_provider_key)) not between 1 and 100
     or p_from is null or p_to is null or not isfinite(p_from) or not isfinite(p_to)
     or p_to<=p_from or p_to-p_from>interval '366 days'
     or p_policy_version is null or p_policy_version<1
     or p_review_basis is null or length(btrim(p_review_basis)) not between 1 and 2000
     or p_evidence is null or jsonb_typeof(p_evidence)<>'object' or octet_length(p_evidence::text)>65536
     or p_idempotency_key is null or length(btrim(p_idempotency_key)) not between 1 and 500
     or (p_action='assert' and coalesce(p_coverage_status,'') not in('complete','partial','unavailable'))
     or (p_action='revoke' and p_coverage_status is not null) then
    raise exception using errcode='22023',message='attendance_coverage_review_invalid';
  end if;
  if not exists(
    select 1 from public.e10_presence_collection_policies p
    where p.organization_id=p_org and p.source_class=p_source_class
      and p.provider_key=btrim(p_provider_key) and p.policy_version=p_policy_version
  ) then raise exception using errcode='22023',message='attendance_coverage_policy_not_found';end if;
  v_fp:=md5(jsonb_build_object('v','attendance-coverage-v1','org',p_org,'key',p_coverage_key,
    'expected',p_expected_revision,'action',p_action,'source',p_source_class,
    'provider',btrim(p_provider_key),'from',p_from,'to',p_to,'status',p_coverage_status,
    'policy',p_policy_version,'basis',btrim(p_review_basis),'evidence',p_evidence)::text);
  perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|attendance-coverage-idempotency|'||p_idempotency_key,0));
  if auth.uid() is distinct from v_actor or not e10.is_org_member(p_org)
     or not e10.has_org_cap(p_org,'act.manage_attendance_coverage') then
    raise exception using errcode='42501',message='attendance_coverage_review_denied';
  end if;
  select * into v_replay from public.e10_attendance_coverage_assertions
    where organization_id=p_org and idempotency_key=p_idempotency_key;
  if found then
    if v_replay.request_fingerprint<>v_fp then
      raise exception using errcode='22023',message='idempotency_key_mismatch';
    end if;
    return jsonb_build_object('ok',true,'replay',true,'assertion_id',v_replay.id,
      'coverage_key',v_replay.coverage_key,'revision',v_replay.revision,
      'action',v_replay.action,'coverage_status',v_replay.coverage_status);
  end if;
  v_key:=coalesce(p_coverage_key,gen_random_uuid());
  perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|attendance-coverage-key|'||v_key::text,0));
  if auth.uid() is distinct from v_actor or not e10.is_org_member(p_org)
     or not e10.has_org_cap(p_org,'act.manage_attendance_coverage') then
    raise exception using errcode='42501',message='attendance_coverage_review_denied';
  end if;
  if not exists(
    select 1 from public.e10_presence_collection_policies p
    where p.organization_id=p_org and p.source_class=p_source_class
      and p.provider_key=btrim(p_provider_key) and p.policy_version=p_policy_version
  ) then raise exception using errcode='22023',message='attendance_coverage_policy_not_found';end if;
  if p_action='assert' and p_coverage_status='complete' and not
    e10.presence_policy_supports_complete_coverage(p_org,p_source_class,btrim(p_provider_key),
      p_policy_version,p_from,p_to) then
    raise exception using errcode='22023',message='attendance_complete_coverage_not_supported';
  end if;
  select * into v_prior from public.e10_attendance_coverage_assertions a
    where a.organization_id=p_org and a.coverage_key=v_key
      and not exists(select 1 from public.e10_attendance_coverage_assertions n
        where n.organization_id=a.organization_id and n.supersedes_assertion_id=a.id);
  if coalesce(v_prior.revision,0)<>p_expected_revision then
    raise exception using errcode='40001',message='attendance_coverage_revision_conflict';
  end if;
  if p_coverage_key is null and p_expected_revision<>0 then
    raise exception using errcode='22023',message='attendance_coverage_key_required';
  end if;
  if p_coverage_key is not null and p_expected_revision=0 then
    raise exception using errcode='22023',message='attendance_coverage_existing_key_invalid';
  end if;
  if p_action='revoke' and v_prior.id is null then
    raise exception using errcode='22023',message='attendance_coverage_revoke_requires_current';
  end if;
  insert into public.e10_attendance_coverage_assertions(
    id,organization_id,coverage_key,revision,action,source_class,provider_key,
    covered_from,covered_to,coverage_status,policy_version,review_basis,evidence,
    supersedes_assertion_id,idempotency_key,request_fingerprint,reviewed_by
  ) values(
    v_id,p_org,v_key,p_expected_revision+1,p_action,p_source_class,btrim(p_provider_key),
    p_from,p_to,p_coverage_status,p_policy_version,btrim(p_review_basis),p_evidence,
    v_prior.id,p_idempotency_key,v_fp,v_actor
  );
  v_result:=jsonb_build_object('ok',true,'replay',false,'assertion_id',v_id,
    'coverage_key',v_key,'revision',p_expected_revision+1,'action',p_action,
    'coverage_status',p_coverage_status);
  return v_result;
end $$;
revoke all on function public.e10_org_review_attendance_coverage(uuid,uuid,bigint,text,text,text,timestamptz,timestamptz,text,bigint,text,jsonb,text)
  from public,anon;
grant execute on function public.e10_org_review_attendance_coverage(uuid,uuid,bigint,text,text,text,timestamptz,timestamptz,text,bigint,text,jsonb,text)
  to authenticated,service_role;

comment on table public.e10_attendance_coverage_assertions is
  'Immutable reviewed collection-coverage assertions. Query windows never imply coverage; overlapping current assertions resolve pessimistically in TA-X7a reads.';
comment on table public.e10_reporting_dataset_revisions is
  'Per-organization invalidation revision locked by reporting reads so data and revision share one transaction snapshot.';
