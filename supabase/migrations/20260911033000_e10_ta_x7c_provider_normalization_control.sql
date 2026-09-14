-- TA-X7c provider-time normalization control plane. No provider is enabled here.

create table public.e10_provider_presence_normalization_policy_decisions(
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.e10_organizations(id),
  provider_key text not null check(length(btrim(provider_key)) between 1 and 100),
  revision bigint not null check(revision>0),
  action text not null check(action in('enable','supersede','revoke')),
  effective_from timestamptz not null check(isfinite(effective_from)),
  effective_through timestamptz not null check(isfinite(effective_through) and effective_through>effective_from),
  heartbeat_expiry interval,
  maximum_late_arrival interval,
  collection_policy_version bigint not null check(collection_policy_version>0),
  reason text not null check(length(btrim(reason)) between 1 and 2000),
  evidence jsonb not null check(jsonb_typeof(evidence)='object' and octet_length(evidence::text)<=65536),
  supersedes_decision_id uuid,
  idempotency_key text not null check(length(btrim(idempotency_key)) between 1 and 500),
  request_fingerprint text not null check(btrim(request_fingerprint)<>''),
  reviewed_by uuid references auth.users(id),reviewed_at timestamptz not null default clock_timestamp(),
  unique(organization_id,id),unique(organization_id,provider_key,revision),unique(organization_id,idempotency_key),
  foreign key(organization_id,supersedes_decision_id)
    references public.e10_provider_presence_normalization_policy_decisions(organization_id,id),
  check((action in('enable','supersede') and heartbeat_expiry is not null
       and maximum_late_arrival is not null and heartbeat_expiry>interval '0'
       and heartbeat_expiry<=interval '1 hour' and maximum_late_arrival>=interval '0'
       and maximum_late_arrival<=interval '30 days')
     or(action='revoke' and heartbeat_expiry is null and maximum_late_arrival is null))
);
create unique index e10_provider_normalization_policy_root_uq
  on public.e10_provider_presence_normalization_policy_decisions(organization_id,provider_key)
  where supersedes_decision_id is null;
create unique index e10_provider_normalization_policy_successor_uq
  on public.e10_provider_presence_normalization_policy_decisions(organization_id,supersedes_decision_id)
  where supersedes_decision_id is not null;
alter table public.e10_provider_presence_normalization_policy_decisions enable row level security;
revoke all on public.e10_provider_presence_normalization_policy_decisions from public,anon,authenticated;
grant all on public.e10_provider_presence_normalization_policy_decisions to service_role;
create trigger e10_provider_normalization_policy_immutable before update or delete
  on public.e10_provider_presence_normalization_policy_decisions for each row
  execute function e10.reject_append_only_change();

create view public.e10_current_provider_presence_normalization_policies with(security_invoker=true) as
select d.* from public.e10_provider_presence_normalization_policy_decisions d
where d.action in('enable','supersede') and d.effective_from<=clock_timestamp()
  and d.effective_through>clock_timestamp() and not exists(
  select 1 from public.e10_provider_presence_normalization_policy_decisions n
  where n.organization_id=d.organization_id and n.provider_key=d.provider_key
    and n.revision>d.revision and n.effective_from<=clock_timestamp()
);
revoke all on public.e10_current_provider_presence_normalization_policies from public,anon,authenticated;
grant select on public.e10_current_provider_presence_normalization_policies to service_role;

create function e10.provider_presence_normalization_policy_at(p_org uuid,p_provider text,p_at timestamptz)
returns setof public.e10_provider_presence_normalization_policy_decisions
language sql stable security definer set search_path=public as $$
  select d.* from public.e10_provider_presence_normalization_policy_decisions d
  where d.organization_id=p_org and d.provider_key=btrim(p_provider)
    and p_at is not null and isfinite(p_at) and d.action in('enable','supersede')
    and d.effective_from<=p_at and d.effective_through>p_at
    and not exists(select 1 from public.e10_provider_presence_normalization_policy_decisions n
      where n.organization_id=d.organization_id and n.provider_key=d.provider_key
        and n.revision>d.revision and n.effective_from<=p_at)
  order by d.revision desc limit 1
$$;
revoke all on function e10.provider_presence_normalization_policy_at(uuid,text,timestamptz) from public,anon,authenticated;
grant execute on function e10.provider_presence_normalization_policy_at(uuid,text,timestamptz) to service_role;

create function public.e10_org_review_provider_presence_normalization_policy(
  p_org uuid,p_provider_key text,p_expected_revision bigint,p_action text,
  p_effective_from timestamptz,p_effective_through timestamptz,
  p_heartbeat_expiry interval,p_maximum_late_arrival interval,
  p_collection_policy_version bigint,p_reason text,p_evidence jsonb,p_idempotency_key text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_actor uuid:=auth.uid();v_fp text;v_replay record;v_prior record;v_id uuid:=gen_random_uuid();
begin
  if not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.configure_attendance_normalization') then
    raise exception using errcode='42501',message='provider_normalization_policy_denied';end if;
  if p_provider_key is null or length(btrim(p_provider_key)) not between 1 and 100
     or p_expected_revision is null or p_expected_revision<0 or p_action is null
     or p_action not in('enable','supersede','revoke')
     or p_effective_from is null or not isfinite(p_effective_from)
     or p_effective_through is null or not isfinite(p_effective_through)
     or p_effective_through<=p_effective_from
     or p_collection_policy_version is null or p_collection_policy_version<1
     or p_reason is null or length(btrim(p_reason)) not between 1 and 2000
     or p_evidence is null or jsonb_typeof(p_evidence)<>'object' or octet_length(p_evidence::text)>65536
     or p_idempotency_key is null or length(btrim(p_idempotency_key)) not between 1 and 500
     or(p_action in('enable','supersede') and(p_heartbeat_expiry is null or p_heartbeat_expiry<=interval '0' or p_heartbeat_expiry>interval '1 hour' or p_maximum_late_arrival is null or p_maximum_late_arrival<interval '0' or p_maximum_late_arrival>interval '30 days'))
     or(p_action='revoke' and(p_heartbeat_expiry is not null or p_maximum_late_arrival is not null)) then
    raise exception using errcode='22023',message='provider_normalization_policy_invalid';end if;
  v_fp:=md5(jsonb_build_object('v','provider-normalization-policy-v1','org',p_org,'provider',btrim(p_provider_key),'expected',p_expected_revision,'action',p_action,'from',p_effective_from,'through',p_effective_through,'expiry',p_heartbeat_expiry,'late',p_maximum_late_arrival,'collection_policy',p_collection_policy_version,'reason',btrim(p_reason),'evidence',p_evidence)::text);
  perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|provider-normalization-policy-idem|'||p_idempotency_key,0));
  if auth.uid() is distinct from v_actor or not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.configure_attendance_normalization') then raise exception using errcode='42501',message='provider_normalization_policy_denied';end if;
  select * into v_replay from public.e10_provider_presence_normalization_policy_decisions where organization_id=p_org and idempotency_key=p_idempotency_key;
  if found then if v_replay.request_fingerprint<>v_fp then raise exception using errcode='22023',message='idempotency_key_mismatch';end if;return jsonb_build_object('ok',true,'replay',true,'decision_id',v_replay.id,'revision',v_replay.revision,'action',v_replay.action);end if;
  perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|provider-normalization-policy|'||btrim(p_provider_key),0));
  if auth.uid() is distinct from v_actor or not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.configure_attendance_normalization') then raise exception using errcode='42501',message='provider_normalization_policy_denied';end if;
  select * into v_prior from public.e10_provider_presence_normalization_policy_decisions d where d.organization_id=p_org and d.provider_key=btrim(p_provider_key) and not exists(select 1 from public.e10_provider_presence_normalization_policy_decisions n where n.organization_id=d.organization_id and n.supersedes_decision_id=d.id);
  if coalesce(v_prior.revision,0)<>p_expected_revision then raise exception using errcode='40001',message='provider_normalization_policy_revision_conflict';end if;
  if(p_expected_revision=0 and p_action<>'enable')or(p_expected_revision>0 and p_action='enable')or(p_action in('supersede','revoke')and v_prior.id is null)then raise exception using errcode='22023',message='provider_normalization_policy_transition_invalid';end if;
  if not exists(select 1 from public.e10_presence_collection_policies p where p.organization_id=p_org and p.source_class='authorized_platform' and p.provider_key=btrim(p_provider_key) and p.policy_version=p_collection_policy_version)then raise exception using errcode='22023',message='provider_normalization_collection_policy_not_found';end if;
  insert into public.e10_provider_presence_normalization_policy_decisions(id,organization_id,provider_key,revision,action,effective_from,effective_through,heartbeat_expiry,maximum_late_arrival,collection_policy_version,reason,evidence,supersedes_decision_id,idempotency_key,request_fingerprint,reviewed_by)values(v_id,p_org,btrim(p_provider_key),p_expected_revision+1,p_action,p_effective_from,p_effective_through,p_heartbeat_expiry,p_maximum_late_arrival,p_collection_policy_version,btrim(p_reason),p_evidence,v_prior.id,p_idempotency_key,v_fp,v_actor);
  if auth.uid() is distinct from v_actor or not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.configure_attendance_normalization') then raise exception using errcode='42501',message='provider_normalization_policy_denied';end if;
  return jsonb_build_object('ok',true,'replay',false,'decision_id',v_id,'revision',p_expected_revision+1,'action',p_action);
end $$;
revoke all on function public.e10_org_review_provider_presence_normalization_policy(uuid,text,bigint,text,timestamptz,timestamptz,interval,interval,bigint,text,jsonb,text) from public,anon;
grant execute on function public.e10_org_review_provider_presence_normalization_policy(uuid,text,bigint,text,timestamptz,timestamptz,interval,interval,bigint,text,jsonb,text) to authenticated,service_role;

create trigger e10_reporting_revision_provider_normalization_policy after insert
  on public.e10_provider_presence_normalization_policy_decisions for each row
  execute function e10.bump_reporting_dataset_revision();

comment on table public.e10_provider_presence_normalization_policy_decisions is
  'Immutable reviewed enable/supersede/revoke decisions. No provider policy or capability grant is seeded.';
