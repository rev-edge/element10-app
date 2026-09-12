-- TA-X7a bounded attendance reporting. Companion source only until X7c normalization.

create view public.e10_current_attendance_intervals with(security_invoker=true) as
select i.organization_id,i.session_id,i.stream_id,i.segment_id,i.segment_sequence,
  i.source_class,i.provider_key,i.original_customer_id,
  a.action attribution_action,a.revision attribution_revision,a.id attribution_decision_id,
  e10.customer_effective_id(i.organization_id,
    case when a.id is null then i.original_customer_id
         when a.action='attribute' then a.customer_id else null end) effective_customer_id,
  i.original_started_at,i.original_ended_at,i.collection_policy_version,
  i.notice_version,i.coverage_label,i.expiry_reason
from public.e10_session_presence_segment_intervals i
left join public.e10_current_session_presence_attributions a
  on(a.organization_id,a.stream_id)=(i.organization_id,i.stream_id)
where i.source_class='companion' and i.original_ended_at>i.original_started_at
  and not i.session_end_incomplete;
revoke all on public.e10_current_attendance_intervals from public,anon,authenticated;
grant select on public.e10_current_attendance_intervals to service_role;

create function public.e10_org_weekly_attendance(
  p_org uuid,p_from timestamptz,p_to timestamptz,p_observation_cutoff timestamptz,
  p_timezone text,p_week_start integer,p_customer uuid default null,
  p_source_class text default 'companion',p_provider_key text default 'companion',
  p_limit integer default 54,p_after_week_start date default null,
  p_expected_dataset_revision bigint default null,p_expected_query_fingerprint text default null
) returns table(
  week_start_date date,week_started_at timestamptz,week_ended_at timestamptz,
  selected_started_at timestamptz,selected_ended_at timestamptz,partial_week boolean,
  coverage_status text,complete_coverage_seconds numeric,unknown_coverage_seconds numeric,
  distinct_attended_sessions bigint,observed_attendance_seconds numeric,
  attended_customer_sessions bigint,average_observed_seconds_per_customer_session numeric,
  excluded_unattributed_segments bigint,excluded_anomalous_segments bigint,
  complete_window_average_sessions_per_week numeric,metric_id text,metric_version text,
  session_count_grain text,duration_grain text,observation_cutoff timestamptz,
  dataset_revision bigint,query_fingerprint text
) language plpgsql security definer set search_path=public as $$
declare
  v_revision bigint;v_changed_at timestamptz;v_query_fingerprint text;
begin
  if not e10.is_org_member(p_org)
     or not e10.has_org_cap(p_org,'act.view_customer_engagement') then
    raise exception using errcode='42501',message='attendance_report_denied';
  end if;
  if p_from is null or p_to is null or p_observation_cutoff is null
     or not isfinite(p_from) or not isfinite(p_to) or not isfinite(p_observation_cutoff)
     or p_to<=p_from or p_to-p_from>interval '366 days'
     or p_observation_cutoff<p_to or p_observation_cutoff>clock_timestamp()
     or p_timezone is null or not exists(select 1 from pg_timezone_names z where z.name=p_timezone)
     or p_week_start is null or p_week_start not between 1 and 7
     or p_source_class is null or p_source_class<>'companion'
     or p_provider_key is null or p_provider_key<>'companion'
     or p_limit is null or p_limit not between 1 and 54
     or (p_after_week_start is not null and
       (p_expected_dataset_revision is null or p_expected_query_fingerprint is null)) then
    raise exception using errcode='22023',message='attendance_report_bounds_invalid';
  end if;
  if p_customer is not null and not exists(
    select 1 from public.e10_customers c where c.organization_id=p_org and c.id=p_customer
      and c.status='active' and e10.customer_effective_id(p_org,c.id)=c.id
  ) then raise exception using errcode='22023',message='attendance_report_customer_invalid';end if;

  -- Holding this row lock through the statement prevents a source writer from committing
  -- its revision bump between revision capture and the projection read.
  select r.revision,r.changed_at into v_revision,v_changed_at
  from public.e10_reporting_dataset_revisions r where r.organization_id=p_org for share;
  if not found then raise exception using errcode='55000',message='attendance_dataset_revision_missing';end if;
  if p_expected_dataset_revision is not null and p_expected_dataset_revision<>v_revision then
    raise exception using errcode='40001',message='attendance_dataset_revision_stale';
  end if;
  if not e10.is_org_member(p_org)
     or not e10.has_org_cap(p_org,'act.view_customer_engagement') then
    raise exception using errcode='42501',message='attendance_report_denied';
  end if;
  v_query_fingerprint:=md5(jsonb_build_object('metric','attendance-weekly-v1','org',p_org,
    'from',p_from,'to',p_to,'cutoff',p_observation_cutoff,'timezone',p_timezone,
    'week_start',p_week_start,'customer',p_customer,'source',p_source_class,
    'provider',p_provider_key,'revision',v_revision)::text);
  if p_after_week_start is not null and p_expected_query_fingerprint<>v_query_fingerprint then
    raise exception using errcode='22023',message='attendance_report_cursor_query_mismatch';
  end if;

  return query
  with recursive
  bounds as(
    select ((p_from at time zone p_timezone)::date
      - mod(extract(isodow from (p_from at time zone p_timezone)::date)::integer-p_week_start+7,7))::date first_week
  ),
  weeks as(
    select g::date local_start,
      (g::timestamp at time zone p_timezone) instant_start,
      ((g+interval '7 days')::timestamp at time zone p_timezone) instant_end
    from bounds b cross join lateral generate_series(
      b.first_week::timestamp,
      (p_to at time zone p_timezone)::date::timestamp,
      interval '7 days') g
  ), selected_weeks as(
    select w.local_start,w.instant_start,w.instant_end,
      greatest(w.instant_start,p_from) selected_start,least(w.instant_end,p_to) selected_end
    from weeks w
    where w.instant_start<p_to and w.instant_end>p_from
      and(p_after_week_start is null or w.local_start>p_after_week_start)
    order by w.local_start limit p_limit
  ),
  coverage_ranges as(
    select w.local_start,
      case when a.coverage_status='complete' and e10.presence_policy_supports_complete_coverage(
             a.organization_id,a.source_class,a.provider_key,a.policy_version,a.covered_from,a.covered_to)
           then 'complete'
           when a.coverage_status='unavailable' then 'unavailable' else 'partial' end coverage_status,
      tstzrange(greatest(a.covered_from,w.selected_start),least(a.covered_to,w.selected_end),'[)') r
    from selected_weeks w
    join public.e10_current_attendance_coverage_assertions a
      on a.organization_id=p_org and a.source_class=p_source_class
     and a.provider_key=p_provider_key and a.covered_from<w.selected_end
     and a.covered_to>w.selected_start
    join public.e10_presence_collection_policies p
      on(p.organization_id,p.source_class,p.provider_key,p.policy_version)
       =(a.organization_id,a.source_class,a.provider_key,a.policy_version)
  ),
  coverage_multis as(
    select w.local_start,
      coalesce(range_agg(c.r)filter(where c.coverage_status='complete'),'{}'::tstzmultirange) complete_mr,
      coalesce(range_agg(c.r)filter(where c.coverage_status in('partial','unavailable')),'{}'::tstzmultirange) degraded_mr,
      bool_or(c.coverage_status='unavailable') has_unavailable,
      bool_or(c.coverage_status='partial') has_partial
    from selected_weeks w left join coverage_ranges c using(local_start)
    group by w.local_start
  ),
  coverage_calc as(
    select w.local_start,
      coalesce((select sum(extract(epoch from upper(r)-lower(r)))
        from unnest(cm.complete_mr-cm.degraded_mr) r),0)::numeric complete_seconds,
      extract(epoch from w.selected_end-w.selected_start)::numeric selected_seconds,
      coalesce(cm.has_unavailable,false) has_unavailable,
      coalesce(cm.has_partial,false) has_partial
    from selected_weeks w join coverage_multis cm using(local_start)
  ),
  eligible as(
    select i.* from public.e10_current_attendance_intervals i
    where i.organization_id=p_org and i.source_class=p_source_class
      and i.provider_key=p_provider_key and i.effective_customer_id is not null
      and(p_customer is null or i.effective_customer_id=p_customer)
      and i.original_started_at<p_observation_cutoff
      and least(i.original_ended_at,p_observation_cutoff)>i.original_started_at
  ),
  session_ranges as(
    select e.effective_customer_id,e.session_id,e.source_class,e.provider_key,
      range_agg(tstzrange(e.original_started_at,least(e.original_ended_at,p_observation_cutoff),'[)')) unioned,
      min(e.original_started_at) first_attendance
    from eligible e group by e.effective_customer_id,e.session_id,e.source_class,e.provider_key
  ),
  duration_rows as(
    select w.local_start,s.effective_customer_id,s.session_id,
      sum(extract(epoch from upper(x)-lower(x)))::numeric observed_seconds
    from selected_weeks w join session_ranges s on s.unioned&&tstzmultirange(tstzrange(w.selected_start,w.selected_end,'[)'))
    cross join lateral unnest(s.unioned) r
    cross join lateral(select r*tstzrange(w.selected_start,w.selected_end,'[)') x) q
    where not isempty(x)
    group by w.local_start,s.effective_customer_id,s.session_id
  ),
  durations as(
    select local_start,sum(observed_seconds)::numeric observed_seconds,count(*)::bigint customer_sessions,
      avg(observed_seconds)::numeric average_seconds from duration_rows group by local_start
  ),
  count_sessions as(
    select s.session_id,min(s.first_attendance) first_attendance
    from session_ranges s group by s.session_id
  ),
  session_counts as(
    select w.local_start,count(*)::bigint session_count
    from selected_weeks w join count_sessions s
      on (s.first_attendance at time zone p_timezone)::date
       - mod(extract(isodow from (s.first_attendance at time zone p_timezone)::date)::integer-p_week_start+7,7)
       =w.local_start
      and s.first_attendance>=p_from and s.first_attendance<p_to
    group by w.local_start
  ),
  exclusions as(
    select w.local_start,
      count(*)filter(where i.segment_id is not null and e10.customer_effective_id(p_org,
        case when a.id is null then i.original_customer_id
             when a.action='attribute' then a.customer_id else null end) is null)::bigint unattributed,
      count(*)filter(where i.segment_id is not null and(i.session_end_incomplete or i.original_ended_at<=i.original_started_at))::bigint anomalous
    from selected_weeks w
    left join public.e10_session_presence_segment_intervals i
      on i.organization_id=p_org and i.source_class=p_source_class and i.provider_key=p_provider_key
     and i.original_started_at>=w.selected_start and i.original_started_at<w.selected_end
     and i.original_started_at<p_observation_cutoff
    left join public.e10_current_session_presence_attributions a
      on(a.organization_id,a.stream_id)=(i.organization_id,i.stream_id)
    group by w.local_start
  ),
  all_window_weeks as(
    select count(*)::numeric n from weeks w where w.instant_start<p_to and w.instant_end>p_from
  ),
  full_coverage as(
    select not exists(
      select 1 from weeks w
      left join lateral(
        select coalesce((select sum(extract(epoch from upper(r)-lower(r)))
          from unnest(
            coalesce(range_agg(tstzrange(greatest(a.covered_from,greatest(w.instant_start,p_from)),least(a.covered_to,least(w.instant_end,p_to)),'[)'))
              filter(where a.coverage_status='complete' and e10.presence_policy_supports_complete_coverage(
                a.organization_id,a.source_class,a.provider_key,a.policy_version,a.covered_from,a.covered_to)),'{}'::tstzmultirange)
            -coalesce(range_agg(tstzrange(greatest(a.covered_from,greatest(w.instant_start,p_from)),least(a.covered_to,least(w.instant_end,p_to)),'[)'))
              filter(where a.coverage_status in('partial','unavailable')
                or(a.coverage_status='complete' and not e10.presence_policy_supports_complete_coverage(
                  a.organization_id,a.source_class,a.provider_key,a.policy_version,a.covered_from,a.covered_to))),'{}'::tstzmultirange)
          ) r),0) seconds
        from public.e10_current_attendance_coverage_assertions a
        join public.e10_presence_collection_policies p
          on(p.organization_id,p.source_class,p.provider_key,p.policy_version)
           =(a.organization_id,a.source_class,a.provider_key,a.policy_version)
        where a.organization_id=p_org and a.source_class=p_source_class and a.provider_key=p_provider_key
          and a.covered_from<least(w.instant_end,p_to) and a.covered_to>greatest(w.instant_start,p_from)
      ) c on true
      where w.instant_start<p_to and w.instant_end>p_from
        and c.seconds<extract(epoch from least(w.instant_end,p_to)-greatest(w.instant_start,p_from))
    ) complete
  ),
  total_sessions as(
    select count(*)::numeric n from count_sessions s where s.first_attendance>=p_from and s.first_attendance<p_to
  )
  select w.local_start,w.instant_start,w.instant_end,w.selected_start,w.selected_end,
    (w.selected_start<>w.instant_start or w.selected_end<>w.instant_end),
    case when c.complete_seconds>=c.selected_seconds then 'complete'
         when c.has_unavailable then 'unavailable' else 'partial' end,
    least(c.complete_seconds,c.selected_seconds),greatest(c.selected_seconds-c.complete_seconds,0),
    coalesce(sc.session_count,0),coalesce(d.observed_seconds,0),
    coalesce(d.customer_sessions,0),d.average_seconds,
    coalesce(ex.unattributed,0),coalesce(ex.anomalous,0),
    case when fc.complete then ts.n/nullif(aw.n,0) else null end,
    'observed_distinct_sessions_per_calendar_week','attendance-weekly-v1',
    'distinct_session','customer_session_attendee_seconds',
    p_observation_cutoff,v_revision,v_query_fingerprint
  from selected_weeks w join coverage_calc c using(local_start)
  left join session_counts sc using(local_start) left join durations d using(local_start)
  left join exclusions ex using(local_start)
  cross join all_window_weeks aw cross join full_coverage fc cross join total_sessions ts
  order by w.local_start;
end $$;

create function e10.attendance_contribution_rows(
  p_org uuid,p_from timestamptz,p_to timestamptz,p_observation_cutoff timestamptz,
  p_customer uuid,p_source_class text,p_provider_key text
) returns table(
  effective_customer_id uuid,session_id uuid,first_attendance timestamptz,
  observed_seconds numeric,contributor_count bigint,contributors_truncated boolean,
  stream_ids uuid[],segment_ids uuid[],attribution_decision_ids uuid[],
  collection_policy_versions bigint[],notice_versions text[]
) language sql stable security definer set search_path=public as $$
  with eligible as(
    select i.* from public.e10_current_attendance_intervals i
    where i.organization_id=p_org and i.source_class=p_source_class
      and i.provider_key=p_provider_key and i.effective_customer_id is not null
      and(p_customer is null or i.effective_customer_id=p_customer)
      and i.original_started_at<p_observation_cutoff
      and least(i.original_ended_at,p_observation_cutoff)>i.original_started_at
  ), windowed as(
    select e.* from eligible e where e.original_started_at<p_to
      and least(e.original_ended_at,p_observation_cutoff)>p_from
  ), grouped as(
    select w.effective_customer_id,w.session_id,
      (select min(a.original_started_at) from eligible a
        where(a.effective_customer_id,a.session_id)=(w.effective_customer_id,w.session_id)) first_attendance,
      range_agg(tstzrange(greatest(w.original_started_at,p_from),
        least(w.original_ended_at,p_observation_cutoff,p_to),'[)')) unioned,
      count(distinct w.segment_id)::bigint contributor_count,
      (array_agg(distinct w.stream_id order by w.stream_id))[1:200] stream_ids,
      (array_agg(distinct w.segment_id order by w.segment_id))[1:200] segment_ids,
      (array_remove(array_agg(distinct w.attribution_decision_id order by w.attribution_decision_id),null))[1:200] attribution_ids,
      (array_agg(distinct w.collection_policy_version order by w.collection_policy_version))[1:200] policy_versions,
      (array_agg(distinct w.notice_version order by w.notice_version))[1:200] notices
    from windowed w group by w.effective_customer_id,w.session_id
  )
  select g.effective_customer_id,g.session_id,g.first_attendance,
    (select sum(extract(epoch from upper(r)-lower(r))) from unnest(g.unioned) r)::numeric,
    g.contributor_count,g.contributor_count>200,g.stream_ids,g.segment_ids,
    g.attribution_ids,g.policy_versions,g.notices
  from grouped g
$$;
revoke all on function e10.attendance_contribution_rows(uuid,timestamptz,timestamptz,timestamptz,uuid,text,text)
  from public,anon,authenticated;
grant execute on function e10.attendance_contribution_rows(uuid,timestamptz,timestamptz,timestamptz,uuid,text,text)
  to service_role;

create function public.e10_org_attendance_contributions(
  p_org uuid,p_from timestamptz,p_to timestamptz,p_observation_cutoff timestamptz,
  p_customer uuid default null,p_source_class text default 'companion',
  p_provider_key text default 'companion',p_limit integer default 100,
  p_after_session_id uuid default null,p_after_customer_id uuid default null,
  p_expected_dataset_revision bigint default null,p_expected_query_fingerprint text default null
) returns table(
  effective_customer_id uuid,session_id uuid,first_attendance timestamptz,
  observed_seconds numeric,contributor_count bigint,contributors_truncated boolean,
  stream_ids uuid[],segment_ids uuid[],attribution_decision_ids uuid[],
  collection_policy_versions bigint[],notice_versions text[],source_class text,
  provider_key text,metric_id text,metric_version text,grain text,
  observation_cutoff timestamptz,dataset_revision bigint,query_fingerprint text
) language plpgsql security definer set search_path=public as $$
declare v_revision bigint;v_fp text;v_after_at timestamptz;
begin
  if not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.view_customer_engagement') then
    raise exception using errcode='42501',message='attendance_detail_denied';
  end if;
  if p_from is null or p_to is null or p_observation_cutoff is null
     or not isfinite(p_from) or not isfinite(p_to) or not isfinite(p_observation_cutoff)
     or p_to<=p_from or p_to-p_from>interval '366 days'
     or p_observation_cutoff<p_to or p_observation_cutoff>clock_timestamp()
     or p_source_class is null or p_source_class<>'companion'
     or p_provider_key is null or p_provider_key<>'companion'
     or p_limit is null or p_limit not between 1 and 200
     or((p_after_session_id is null)<>(p_after_customer_id is null))
     or(p_after_session_id is not null and
       (p_expected_dataset_revision is null or p_expected_query_fingerprint is null)) then
    raise exception using errcode='22023',message='attendance_detail_bounds_invalid';
  end if;
  if p_customer is not null and not exists(
    select 1 from public.e10_customers c where c.organization_id=p_org and c.id=p_customer
      and c.status='active' and e10.customer_effective_id(p_org,c.id)=c.id
  ) then raise exception using errcode='22023',message='attendance_detail_customer_invalid';end if;
  select revision into v_revision from public.e10_reporting_dataset_revisions
    where organization_id=p_org for share;
  if not found then raise exception using errcode='55000',message='attendance_dataset_revision_missing';end if;
  if p_expected_dataset_revision is not null and p_expected_dataset_revision<>v_revision then
    raise exception using errcode='40001',message='attendance_dataset_revision_stale';
  end if;
  if not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.view_customer_engagement') then
    raise exception using errcode='42501',message='attendance_detail_denied';
  end if;
  v_fp:=md5(jsonb_build_object('metric','attendance-contributions-v1','org',p_org,
    'from',p_from,'to',p_to,'cutoff',p_observation_cutoff,'customer',p_customer,
    'source',p_source_class,'provider',p_provider_key,'revision',v_revision)::text);
  if p_after_session_id is not null then
    if p_expected_query_fingerprint<>v_fp then
      raise exception using errcode='22023',message='attendance_detail_cursor_query_mismatch';
    end if;
    select r.first_attendance into v_after_at
    from e10.attendance_contribution_rows(p_org,p_from,p_to,p_observation_cutoff,
      p_customer,p_source_class,p_provider_key) r
    where(r.session_id,r.effective_customer_id)=(p_after_session_id,p_after_customer_id);
    if not found then raise exception using errcode='22023',message='attendance_detail_cursor_invalid';end if;
  end if;
  return query
  select r.effective_customer_id,r.session_id,r.first_attendance,r.observed_seconds,
    r.contributor_count,r.contributors_truncated,r.stream_ids,r.segment_ids,
    r.attribution_decision_ids,r.collection_policy_versions,r.notice_versions,
    p_source_class,p_provider_key,'observed_attendance_contribution','attendance-contributions-v1',
    'effective_customer_session',p_observation_cutoff,v_revision,v_fp
  from e10.attendance_contribution_rows(p_org,p_from,p_to,p_observation_cutoff,
    p_customer,p_source_class,p_provider_key) r
  where v_after_at is null or(r.first_attendance,r.session_id,r.effective_customer_id)>
    (v_after_at,p_after_session_id,p_after_customer_id)
  order by r.first_attendance,r.session_id,r.effective_customer_id limit p_limit;
end $$;

revoke all on function public.e10_org_attendance_contributions(uuid,timestamptz,timestamptz,timestamptz,uuid,text,text,integer,uuid,uuid,bigint,text)
  from public,anon;
grant execute on function public.e10_org_attendance_contributions(uuid,timestamptz,timestamptz,timestamptz,uuid,text,text,integer,uuid,uuid,bigint,text)
  to authenticated,service_role;

create function public.e10_org_attendance_contribution_segments(
  p_org uuid,p_from timestamptz,p_to timestamptz,p_observation_cutoff timestamptz,
  p_customer uuid,p_session uuid,p_source_class text default 'companion',
  p_provider_key text default 'companion',p_limit integer default 100,
  p_after_segment_id uuid default null,p_expected_dataset_revision bigint default null,
  p_expected_query_fingerprint text default null
) returns table(
  segment_id uuid,stream_id uuid,original_started_at timestamptz,original_ended_at timestamptz,
  clipped_started_at timestamptz,clipped_ended_at timestamptz,raw_clipped_seconds numeric,
  attribution_decision_id uuid,collection_policy_version bigint,notice_version text,
  coverage_label text,expiry_reason text,session_union_observed_seconds numeric,
  contributor_count bigint,metric_id text,metric_version text,grain text,
  observation_cutoff timestamptz,dataset_revision bigint,query_fingerprint text
) language plpgsql security definer set search_path=public as $$
declare v_revision bigint;v_fp text;v_after_at timestamptz;v_union numeric;v_count bigint;
begin
  if not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.view_customer_engagement') then
    raise exception using errcode='42501',message='attendance_segment_detail_denied';
  end if;
  if p_from is null or p_to is null or p_observation_cutoff is null or p_customer is null or p_session is null
     or not isfinite(p_from) or not isfinite(p_to) or not isfinite(p_observation_cutoff)
     or p_to<=p_from or p_to-p_from>interval '366 days'
     or p_observation_cutoff<p_to or p_observation_cutoff>clock_timestamp()
     or p_source_class is null or p_source_class<>'companion'
     or p_provider_key is null or p_provider_key<>'companion'
     or p_limit is null or p_limit not between 1 and 200
     or(p_after_segment_id is not null and
       (p_expected_dataset_revision is null or p_expected_query_fingerprint is null)) then
    raise exception using errcode='22023',message='attendance_segment_detail_bounds_invalid';
  end if;
  if not exists(select 1 from public.e10_customers c where c.organization_id=p_org and c.id=p_customer
      and c.status='active' and e10.customer_effective_id(p_org,c.id)=c.id)
     or not exists(select 1 from public.e10_break_sessions s where s.organization_id=p_org and s.id=p_session) then
    raise exception using errcode='22023',message='attendance_segment_detail_scope_invalid';
  end if;
  select revision into v_revision from public.e10_reporting_dataset_revisions
    where organization_id=p_org for share;
  if not found then raise exception using errcode='55000',message='attendance_dataset_revision_missing';end if;
  if p_expected_dataset_revision is not null and p_expected_dataset_revision<>v_revision then
    raise exception using errcode='40001',message='attendance_dataset_revision_stale';
  end if;
  if not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.view_customer_engagement') then
    raise exception using errcode='42501',message='attendance_segment_detail_denied';
  end if;
  v_fp:=md5(jsonb_build_object('metric','attendance-contribution-segments-v1','org',p_org,
    'from',p_from,'to',p_to,'cutoff',p_observation_cutoff,'customer',p_customer,
    'session',p_session,'source',p_source_class,'provider',p_provider_key,'revision',v_revision)::text);
  select r.observed_seconds,r.contributor_count into v_union,v_count
  from e10.attendance_contribution_rows(p_org,p_from,p_to,p_observation_cutoff,
    p_customer,p_source_class,p_provider_key) r
  where(r.session_id,r.effective_customer_id)=(p_session,p_customer);
  if not found then raise exception using errcode='22023',message='attendance_segment_detail_scope_invalid';end if;
  if p_after_segment_id is not null then
    if p_expected_query_fingerprint<>v_fp then
      raise exception using errcode='22023',message='attendance_segment_detail_cursor_query_mismatch';
    end if;
    select i.original_started_at into v_after_at from public.e10_current_attendance_intervals i
    where i.organization_id=p_org and i.segment_id=p_after_segment_id
      and i.session_id=p_session and i.effective_customer_id=p_customer
      and i.source_class=p_source_class and i.provider_key=p_provider_key
      and i.original_started_at<p_to and least(i.original_ended_at,p_observation_cutoff)>p_from;
    if not found then raise exception using errcode='22023',message='attendance_segment_detail_cursor_invalid';end if;
  end if;
  return query
  select i.segment_id,i.stream_id,i.original_started_at,i.original_ended_at,
    greatest(i.original_started_at,p_from),least(i.original_ended_at,p_observation_cutoff,p_to),
    extract(epoch from least(i.original_ended_at,p_observation_cutoff,p_to)-greatest(i.original_started_at,p_from))::numeric,
    i.attribution_decision_id,i.collection_policy_version,i.notice_version,i.coverage_label,i.expiry_reason,
    v_union,v_count,'observed_attendance_contributor','attendance-contribution-segments-v1',
    'presence_segment',p_observation_cutoff,v_revision,v_fp
  from public.e10_current_attendance_intervals i
  where i.organization_id=p_org and i.session_id=p_session and i.effective_customer_id=p_customer
    and i.source_class=p_source_class and i.provider_key=p_provider_key
    and i.original_started_at<p_to and least(i.original_ended_at,p_observation_cutoff)>p_from
    and(v_after_at is null or(i.original_started_at,i.segment_id)>(v_after_at,p_after_segment_id))
  order by i.original_started_at,i.segment_id limit p_limit;
end $$;
revoke all on function public.e10_org_attendance_contribution_segments(uuid,timestamptz,timestamptz,timestamptz,uuid,uuid,text,text,integer,uuid,bigint,text)
  from public,anon;
grant execute on function public.e10_org_attendance_contribution_segments(uuid,timestamptz,timestamptz,timestamptz,uuid,uuid,text,text,integer,uuid,bigint,text)
  to authenticated,service_role;

revoke all on function public.e10_org_weekly_attendance(uuid,timestamptz,timestamptz,timestamptz,text,integer,uuid,text,text,integer,date,bigint,text)
  from public,anon;
grant execute on function public.e10_org_weekly_attendance(uuid,timestamptz,timestamptz,timestamptz,text,integer,uuid,text,text,integer,date,bigint,text)
  to authenticated,service_role;

comment on function public.e10_org_weekly_attendance(uuid,timestamptz,timestamptz,timestamptz,text,integer,uuid,text,text,integer,date,bigint,text) is
  'Bounded restated-current companion attendance. Unknown coverage is never zero; provider evidence remains excluded until TA-X7c.';
comment on function public.e10_org_attendance_contributions(uuid,timestamptz,timestamptz,timestamptz,uuid,text,text,integer,uuid,uuid,bigint,text) is
  'Bounded session/customer contribution drill-down for TA-X7a weekly duration metrics; IDs are capped with explicit truncation.';
comment on function public.e10_org_attendance_contribution_segments(uuid,timestamptz,timestamptz,timestamptz,uuid,uuid,text,text,integer,uuid,bigint,text) is
  'Complete bounded contributor pagination for one session/customer. Union total is computed from the full cohort, never from a page.';
