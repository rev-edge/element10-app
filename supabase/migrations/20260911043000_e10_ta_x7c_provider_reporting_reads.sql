-- TA-X7c freshness-aware, bounded provider attendance reads.

create function e10.current_provider_normalization_run(
  p_org uuid,p_provider text,p_from timestamptz,p_to timestamptz,p_cutoff timestamptz
) returns public.e10_provider_presence_normalization_runs
language plpgsql stable security definer set search_path=public set timezone='UTC' as $$
declare v_run public.e10_provider_presence_normalization_runs;v_fingerprint text;
begin
  select r.* into v_run from public.e10_provider_presence_normalization_runs r
  where r.organization_id=p_org and r.provider_key=btrim(p_provider)
    and r.window_from=p_from and r.window_to=p_to and r.observation_cutoff=p_cutoff
    and r.status='complete' order by r.completed_at desc,r.id desc limit 1;
  if not found then return null;end if;
  v_fingerprint:=e10.provider_normalization_dependency_fingerprint(
    p_org,btrim(p_provider),p_from,p_to,p_cutoff,100000);
  if v_run.dependency_fingerprint<>v_fingerprint then return null;end if;
  return v_run;
end $$;
revoke all on function e10.current_provider_normalization_run(uuid,text,timestamptz,timestamptz,timestamptz) from public,anon,authenticated;
grant execute on function e10.current_provider_normalization_run(uuid,text,timestamptz,timestamptz,timestamptz) to service_role;

create function public.e10_org_provider_attendance_intervals(
  p_org uuid,p_provider text,p_session uuid,p_customer uuid,
  p_from timestamptz,p_to timestamptz,p_cutoff timestamptz,
  p_limit integer default 100,p_after_started_at timestamptz default null,
  p_after_interval_id uuid default null,p_expected_dataset_revision bigint default null,
  p_expected_query_fingerprint text default null
) returns table(
  availability text,interval_id uuid,session_id uuid,effective_customer_id uuid,
  started_at timestamptz,ended_at timestamptz,observed_seconds numeric,
  expiry_reason text,source_class text,provider_key text,run_id uuid,
  dataset_revision bigint,query_fingerprint text
) language plpgsql security definer set search_path=public set timezone='UTC' as $$
declare v_revision bigint;v_run public.e10_provider_presence_normalization_runs;v_fp text;
begin
  if not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.view_customer_engagement') then
    raise exception using errcode='42501',message='provider_attendance_denied';end if;
  if p_org is null or p_provider is null or length(btrim(p_provider)) not between 1 and 100
     or p_session is null or p_from is null or p_to is null or p_cutoff is null
     or not isfinite(p_from) or not isfinite(p_to) or not isfinite(p_cutoff)
     or p_to<=p_from or p_to-p_from>interval '366 days' or p_cutoff<p_to
     or p_cutoff>clock_timestamp() or p_limit is null or p_limit not between 1 and 200
     or((p_after_started_at is null)<>(p_after_interval_id is null))
     or(p_after_interval_id is not null and(p_expected_dataset_revision is null or p_expected_query_fingerprint is null))then
    raise exception using errcode='22023',message='provider_attendance_bounds_invalid';end if;
  if not exists(select 1 from public.e10_break_sessions s where(s.organization_id,s.id)=(p_org,p_session))
     or(p_customer is not null and not exists(select 1 from public.e10_customers c where(c.organization_id,c.id)=(p_org,p_customer)and c.status='active'and e10.customer_effective_id(p_org,c.id)=c.id))then
    raise exception using errcode='22023',message='provider_attendance_scope_invalid';end if;
  select r.revision into v_revision from public.e10_reporting_dataset_revisions r where r.organization_id=p_org for share;
  if not found then raise exception using errcode='55000',message='attendance_dataset_revision_missing';end if;
  if p_expected_dataset_revision is not null and p_expected_dataset_revision<>v_revision then
    raise exception using errcode='40001',message='attendance_dataset_revision_stale';end if;
  if not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.view_customer_engagement') then
    raise exception using errcode='42501',message='provider_attendance_denied';end if;
  v_run:=e10.current_provider_normalization_run(p_org,p_provider,p_from,p_to,p_cutoff);
  v_fp:=md5(jsonb_build_object('metric','provider-attendance-intervals-v1','org',p_org,
    'provider',btrim(p_provider),'session',p_session,'customer',p_customer,'from',p_from,
    'to',p_to,'cutoff',p_cutoff,'revision',v_revision,'run',v_run.id)::text);
  if p_after_interval_id is not null and p_expected_query_fingerprint<>v_fp then
    raise exception using errcode='22023',message='provider_attendance_cursor_query_mismatch';end if;
  if v_run.id is null then
    return query select 'unavailable_rebuild_required'::text,null::uuid,p_session,p_customer,
      null::timestamptz,null::timestamptz,null::numeric,null::text,
      'authorized_platform'::text,btrim(p_provider),null::uuid,v_revision,v_fp;return;
  end if;
  if p_after_interval_id is not null and not exists(select 1 from public.e10_provider_presence_normalized_intervals i
      where(i.organization_id,i.run_id,i.id,i.started_at,i.session_id)=(p_org,v_run.id,p_after_interval_id,p_after_started_at,p_session)
        and(p_customer is null or i.effective_customer_id=p_customer))then
    raise exception using errcode='22023',message='provider_attendance_cursor_invalid';end if;
  return query select 'available'::text,i.id,i.session_id,i.effective_customer_id,i.started_at,i.ended_at,
    extract(epoch from i.ended_at-i.started_at)::numeric,i.expiry_reason,'authorized_platform'::text,
    btrim(p_provider),v_run.id,v_revision,v_fp
  from public.e10_provider_presence_normalized_intervals i
  where(i.organization_id,i.run_id,i.session_id)=(p_org,v_run.id,p_session)
    and(p_customer is null or i.effective_customer_id=p_customer)
    and(p_after_interval_id is null or(i.started_at,i.id)>(p_after_started_at,p_after_interval_id))
  order by i.started_at,i.id limit p_limit;
end $$;
revoke all on function public.e10_org_provider_attendance_intervals(uuid,text,uuid,uuid,timestamptz,timestamptz,timestamptz,integer,timestamptz,uuid,bigint,text) from public,anon;
grant execute on function public.e10_org_provider_attendance_intervals(uuid,text,uuid,uuid,timestamptz,timestamptz,timestamptz,integer,timestamptz,uuid,bigint,text) to authenticated,service_role;

create function public.e10_org_provider_attendance_quarantine(
  p_org uuid,p_provider text,p_from timestamptz,p_to timestamptz,p_cutoff timestamptz,
  p_reason text default null,p_limit integer default 100,p_after_id uuid default null,
  p_expected_dataset_revision bigint default null,p_expected_query_fingerprint text default null
) returns table(
  availability text,quarantine_id uuid,session_id uuid,reason text,event_id uuid,
  evidence_event_count integer,source_class text,provider_key text,run_id uuid,
  dataset_revision bigint,query_fingerprint text
) language plpgsql security definer set search_path=public set timezone='UTC' as $$
declare v_revision bigint;v_run public.e10_provider_presence_normalization_runs;v_fp text;
begin
  if not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.view_customer_engagement')then raise exception using errcode='42501',message='provider_quarantine_denied';end if;
  if p_org is null or p_provider is null or length(btrim(p_provider))not between 1 and 100
    or p_from is null or p_to is null or p_cutoff is null or not isfinite(p_from)or not isfinite(p_to)or not isfinite(p_cutoff)
    or p_to<=p_from or p_to-p_from>interval '366 days'or p_cutoff<p_to or p_cutoff>clock_timestamp()
    or p_limit is null or p_limit not between 1 and 200
    or(p_after_id is not null and(p_expected_dataset_revision is null or p_expected_query_fingerprint is null))then raise exception using errcode='22023',message='provider_quarantine_bounds_invalid';end if;
  select revision into v_revision from public.e10_reporting_dataset_revisions where organization_id=p_org for share;
  if not found then raise exception using errcode='55000',message='attendance_dataset_revision_missing';end if;
  if p_expected_dataset_revision is not null and p_expected_dataset_revision<>v_revision then raise exception using errcode='40001',message='attendance_dataset_revision_stale';end if;
  if not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.view_customer_engagement')then raise exception using errcode='42501',message='provider_quarantine_denied';end if;
  v_run:=e10.current_provider_normalization_run(p_org,p_provider,p_from,p_to,p_cutoff);
  v_fp:=md5(jsonb_build_object('metric','provider-attendance-quarantine-v1','org',p_org,'provider',btrim(p_provider),'from',p_from,'to',p_to,'cutoff',p_cutoff,'reason',p_reason,'revision',v_revision,'run',v_run.id)::text);
  if p_after_id is not null and p_expected_query_fingerprint<>v_fp then raise exception using errcode='22023',message='provider_quarantine_cursor_query_mismatch';end if;
  if v_run.id is null then return query select 'unavailable_rebuild_required'::text,null::uuid,null::uuid,p_reason,null::uuid,null::integer,'authorized_platform'::text,btrim(p_provider),null::uuid,v_revision,v_fp;return;end if;
  if p_after_id is not null and not exists(select 1 from public.e10_provider_presence_quarantine_rows q where(q.organization_id,q.run_id,q.id)=(p_org,v_run.id,p_after_id)and(p_reason is null or q.reason=p_reason))then raise exception using errcode='22023',message='provider_quarantine_cursor_invalid';end if;
  return query select 'available'::text,q.id,q.session_id,q.reason,q.event_id,cardinality(q.evidence_event_ids),
    'authorized_platform'::text,btrim(p_provider),v_run.id,v_revision,v_fp
  from public.e10_provider_presence_quarantine_rows q where(q.organization_id,q.run_id)=(p_org,v_run.id)
    and(p_reason is null or q.reason=p_reason)and(p_after_id is null or q.id>p_after_id)order by q.id limit p_limit;
end $$;
revoke all on function public.e10_org_provider_attendance_quarantine(uuid,text,timestamptz,timestamptz,timestamptz,text,integer,uuid,bigint,text) from public,anon;
grant execute on function public.e10_org_provider_attendance_quarantine(uuid,text,timestamptz,timestamptz,timestamptz,text,integer,uuid,bigint,text) to authenticated,service_role;

create function public.e10_org_source_attendance_summary(
  p_org uuid,p_provider text,p_session uuid,p_customer uuid,
  p_from timestamptz,p_to timestamptz,p_cutoff timestamptz
) returns table(source_class text,provider_key text,availability text,observed_seconds numeric,run_id uuid,dataset_revision bigint)
language plpgsql security definer set search_path=public set timezone='UTC' as $$
declare v_revision bigint;v_run public.e10_provider_presence_normalization_runs;
  v_provider_eligible tstzmultirange:='{}';v_companion_eligible tstzmultirange:='{}';
  v_provider_status text;v_companion_status text;v_full_seconds numeric:=extract(epoch from p_to-p_from);
begin
  if not e10.is_org_member(p_org)or not e10.has_org_cap(p_org,'act.view_customer_engagement')then raise exception using errcode='42501',message='attendance_summary_denied';end if;
  if p_org is null or p_provider is null or length(btrim(p_provider))not between 1 and 100 or p_session is null or p_customer is null
    or p_from is null or p_to is null or p_cutoff is null or not isfinite(p_from)or not isfinite(p_to)or not isfinite(p_cutoff)
    or p_to<=p_from or p_to-p_from>interval '366 days'or p_cutoff<p_to or p_cutoff>clock_timestamp()then raise exception using errcode='22023',message='attendance_summary_bounds_invalid';end if;
  if not exists(select 1 from public.e10_break_sessions s where(s.organization_id,s.id)=(p_org,p_session))
    or not exists(select 1 from public.e10_customers c where(c.organization_id,c.id)=(p_org,p_customer)and c.status='active'and e10.customer_effective_id(p_org,c.id)=c.id)then raise exception using errcode='22023',message='attendance_summary_scope_invalid';end if;
  select revision into v_revision from public.e10_reporting_dataset_revisions where organization_id=p_org for share;
  if not found then raise exception using errcode='55000',message='attendance_dataset_revision_missing';end if;
  if not e10.is_org_member(p_org)or not e10.has_org_cap(p_org,'act.view_customer_engagement')then raise exception using errcode='42501',message='attendance_summary_denied';end if;
  v_run:=e10.current_provider_normalization_run(p_org,p_provider,p_from,p_to,p_cutoff);
  if v_run.id is not null then
    select coalesce(range_agg(tstzrange(c.started_at,c.ended_at,'[)')),'{}')into v_provider_eligible
    from e10.provider_normalization_coverage_parts(p_org,btrim(p_provider),
      (select d.collection_policy_version from public.e10_provider_presence_normalization_policy_decisions d where d.id=v_run.policy_decision_id),p_from,p_to)c
    where c.disposition='eligible';
  end if;
  with coverage as(
    select coalesce(range_agg(tstzrange(greatest(a.covered_from,p_from),least(a.covered_to,p_to),'[)'))filter(where a.coverage_status='complete'and e10.presence_policy_supports_complete_coverage(a.organization_id,a.source_class,a.provider_key,a.policy_version,a.covered_from,a.covered_to)),'{}'::tstzmultirange)complete_mr,
      coalesce(range_agg(tstzrange(greatest(a.covered_from,p_from),least(a.covered_to,p_to),'[)'))filter(where a.coverage_status in('partial','unavailable')),'{}'::tstzmultirange)degraded_mr
    from public.e10_current_attendance_coverage_assertions a where a.organization_id=p_org and a.source_class='companion'and a.provider_key='companion'and a.covered_from<p_to and a.covered_to>p_from
  )select complete_mr-degraded_mr into v_companion_eligible from coverage;
  v_provider_status:=case when v_run.id is null then'unavailable_rebuild_required'when coalesce((select sum(extract(epoch from upper(r)-lower(r)))from unnest(v_provider_eligible)r),0)=0 then'unavailable_coverage_required'when coalesce((select sum(extract(epoch from upper(r)-lower(r)))from unnest(v_provider_eligible)r),0)<v_full_seconds then'available_partial_coverage'else'available_complete_coverage'end;
  v_companion_status:=case when coalesce((select sum(extract(epoch from upper(r)-lower(r)))from unnest(v_companion_eligible)r),0)=0 then'unavailable_coverage_required'when coalesce((select sum(extract(epoch from upper(r)-lower(r)))from unnest(v_companion_eligible)r),0)<v_full_seconds then'available_partial_coverage'else'available_complete_coverage'end;
  return query
  select 'authorized_platform'::text,btrim(p_provider),v_provider_status,
    case when v_provider_status like'unavailable%'then null else coalesce((select sum(extract(epoch from upper(r)-lower(r)))from unnest((
      coalesce((select range_agg(tstzrange(greatest(i.started_at,p_from),least(i.ended_at,p_to,p_cutoff),'[)'))
        from public.e10_provider_presence_normalized_intervals i where(i.organization_id,i.run_id,i.session_id,i.effective_customer_id)=(p_org,v_run.id,p_session,p_customer)
          and i.started_at<least(p_to,p_cutoff)and i.ended_at>p_from),'{}'::tstzmultirange)*v_provider_eligible))r),0)::numeric end,v_run.id,v_revision
  union all
  select 'companion'::text,'companion'::text,v_companion_status,
    case when v_companion_status like'unavailable%'then null else coalesce((select sum(extract(epoch from upper(r)-lower(r)))from unnest((
      coalesce((select range_agg(tstzrange(greatest(i.original_started_at,p_from),least(i.original_ended_at,p_to,p_cutoff),'[)'))
        from public.e10_current_attendance_intervals i where(i.organization_id,i.session_id,i.effective_customer_id)=(p_org,p_session,p_customer)
          and i.source_class='companion'and i.provider_key='companion'and i.original_started_at<least(p_to,p_cutoff)and i.original_ended_at>p_from),'{}'::tstzmultirange)*v_companion_eligible))r),0)::numeric end,
    null::uuid,v_revision;
end $$;
revoke all on function public.e10_org_source_attendance_summary(uuid,text,uuid,uuid,timestamptz,timestamptz,timestamptz) from public,anon;
grant execute on function public.e10_org_source_attendance_summary(uuid,text,uuid,uuid,timestamptz,timestamptz,timestamptz) to authenticated,service_role;

comment on function public.e10_org_provider_attendance_intervals(uuid,text,uuid,uuid,timestamptz,timestamptz,timestamptz,integer,timestamptz,uuid,bigint,text) is
  'Freshness-aware bounded provider interval detail. Raw attendee keys, contact fields and financials are never returned.';
comment on function public.e10_org_provider_attendance_quarantine(uuid,text,timestamptz,timestamptz,timestamptz,text,integer,uuid,bigint,text) is
  'Freshness-aware bounded provider quarantine detail. Evidence content remains service-only.';
comment on function public.e10_org_source_attendance_summary(uuid,text,uuid,uuid,timestamptz,timestamptz,timestamptz) is
  'Source-separated provider and companion attendance. Source seconds are never silently unioned.';
