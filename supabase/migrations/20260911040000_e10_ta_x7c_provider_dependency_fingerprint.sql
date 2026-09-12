-- TA-X7c bounded dependency identity for current-run eligibility.
-- The same selected-input relations are consumed by the normalization runner.
create function e10.provider_normalization_dependency_fingerprint(
  p_org uuid,p_provider text,p_from timestamptz,p_to timestamptz,
  p_cutoff timestamptz,p_max_events integer
) returns text language plpgsql stable security definer
set search_path=public set timezone='UTC' set intervalstyle='postgres' as $$
declare v_provider text:=btrim(p_provider);v_count bigint;v_payload jsonb;
begin
  if p_provider is null or length(v_provider) not between 1 and 100
     or p_from is null or p_to is null or p_cutoff is null
     or not isfinite(p_from) or not isfinite(p_to) or not isfinite(p_cutoff)
     or p_to<=p_from or p_cutoff<p_to or p_to-p_from>interval '366 days'
     or p_max_events is null or p_max_events not between 1 and 100000 then
    raise exception using errcode='22023',message='provider_normalization_dependency_bounds_invalid';
  end if;

  -- Bound every dependency family before aggregation. The caller's event bound
  -- is also the maximum related-input cardinality, so zero-event rows cannot
  -- make dependency computation unbounded.
  with selected_streams as materialized(
    select s.* from public.e10_session_presence_streams s
    join public.e10_break_sessions bs on(bs.organization_id,bs.id)=(s.organization_id,s.session_id)
    where s.organization_id=p_org and s.source_class='authorized_platform'
      and s.provider_key=v_provider and bs.created_at<p_to
      and coalesce(bs.ended_at,p_cutoff)>p_from
  ),selected_events as materialized(
    select e.* from public.e10_session_presence_events e join selected_streams s
      on(s.organization_id,s.id)=(e.organization_id,e.stream_id)
    where e.provider_occurred_at is null or e.provider_occurred_at<p_to
       or e.provider_occurred_at>e.server_received_at
       or e.provider_occurred_at>p_cutoff or e.corrects_event_id is not null
  ),counts as(
    select count(*) n from selected_events
    union all select count(*) from selected_streams
    union all select count(*) from public.e10_session_presence_segments g join selected_streams s on(s.organization_id,s.id)=(g.organization_id,g.stream_id)
    union all select count(*) from public.e10_current_attendance_coverage_assertions a where a.organization_id=p_org and a.source_class='authorized_platform' and a.provider_key=v_provider and a.covered_from<p_to and a.covered_to>p_from
    union all select count(*) from public.e10_provider_presence_normalization_policy_decisions d where d.organization_id=p_org and d.provider_key=v_provider and d.effective_from<p_to
    union all select count(*) from public.e10_presence_collection_policies p where p.organization_id=p_org and p.source_class='authorized_platform' and p.provider_key=v_provider and p.effective_from<p_to and coalesce(p.effective_through,p_cutoff)>p_from
    union all select count(*) from public.e10_presence_policy_state_history h where h.organization_id=p_org and h.source_class='authorized_platform' and h.provider_key=v_provider and h.state_from<p_to
    union all select count(*) from public.e10_current_session_presence_attributions a join selected_streams s on(s.organization_id,s.id)=(a.organization_id,a.stream_id)
  )select n into v_count from counts where n>p_max_events order by n desc limit 1;
  if found then raise exception using errcode='54000',message='provider_normalization_dependency_bound_exceeded';end if;

  with recursive selected_streams as materialized(
    select s.* from public.e10_session_presence_streams s
    join public.e10_break_sessions bs on(bs.organization_id,bs.id)=(s.organization_id,s.session_id)
    where s.organization_id=p_org and s.source_class='authorized_platform'
      and s.provider_key=v_provider and bs.created_at<p_to
      and coalesce(bs.ended_at,p_cutoff)>p_from
  ),customer_ids(id)as(
    select original_customer_id from selected_streams where original_customer_id is not null
    union select a.customer_id from public.e10_current_session_presence_attributions a join selected_streams s on(s.organization_id,s.id)=(a.organization_id,a.stream_id) where a.action='attribute' and a.customer_id is not null
    union select r.target_customer_id from public.e10_current_customer_resolutions r join customer_ids c on c.id=r.source_customer_id where r.organization_id=p_org and r.action='merge'
  ),counts as(
    select count(*) n from customer_ids
    union all select count(*) from public.e10_customer_resolution_decisions r where r.organization_id=p_org and(r.source_customer_id in(select id from customer_ids)or r.target_customer_id in(select id from customer_ids))
  )select max(n)into v_count from counts;
  if v_count>p_max_events then raise exception using errcode='54000',message='provider_normalization_dependency_bound_exceeded';end if;

  with recursive selected_streams as materialized(
    select s.* from public.e10_session_presence_streams s
    join public.e10_break_sessions bs on(bs.organization_id,bs.id)=(s.organization_id,s.session_id)
    where s.organization_id=p_org and s.source_class='authorized_platform'
      and s.provider_key=v_provider and bs.created_at<p_to
      and coalesce(bs.ended_at,p_cutoff)>p_from
  ),selected_events as materialized(
    select e.* from public.e10_session_presence_events e join selected_streams s on(s.organization_id,s.id)=(e.organization_id,e.stream_id)
    where e.provider_occurred_at is null or e.provider_occurred_at<p_to
       or e.provider_occurred_at>e.server_received_at
       or e.provider_occurred_at>p_cutoff or e.corrects_event_id is not null
  ),customer_ids(id)as(
    select original_customer_id from selected_streams where original_customer_id is not null
    union select a.customer_id from public.e10_current_session_presence_attributions a join selected_streams s on(s.organization_id,s.id)=(a.organization_id,a.stream_id) where a.action='attribute' and a.customer_id is not null
    union select r.target_customer_id from public.e10_current_customer_resolutions r join customer_ids c on c.id=r.source_customer_id where r.organization_id=p_org and r.action='merge'
  )select jsonb_build_object(
    'v','provider-dependencies-v2','scope',jsonb_build_array(p_org,v_provider,p_from,p_to,p_cutoff),
    'normalization_policies',(select coalesce(jsonb_agg(to_jsonb(d)order by d.revision,d.id),'[]')from public.e10_provider_presence_normalization_policy_decisions d where d.organization_id=p_org and d.provider_key=v_provider and d.effective_from<p_to),
    'collection_policies',(select coalesce(jsonb_agg(to_jsonb(p)order by p.policy_version),'[]')from public.e10_presence_collection_policies p where p.organization_id=p_org and p.source_class='authorized_platform'and p.provider_key=v_provider and p.effective_from<p_to and coalesce(p.effective_through,p_cutoff)>p_from),
    'collection_policy_states',(select coalesce(jsonb_agg(to_jsonb(h)order by h.policy_version,h.state_from,h.id),'[]')from public.e10_presence_policy_state_history h where h.organization_id=p_org and h.source_class='authorized_platform'and h.provider_key=v_provider and h.state_from<p_to),
    'coverage',(select coalesce(jsonb_agg(to_jsonb(a)order by a.coverage_key,a.revision,a.id),'[]')from public.e10_current_attendance_coverage_assertions a where a.organization_id=p_org and a.source_class='authorized_platform'and a.provider_key=v_provider and a.covered_from<p_to and a.covered_to>p_from),
    'sessions_streams',(select coalesce(jsonb_agg(jsonb_build_array(s.id,s.session_id,s.subject_key,s.connection_id,s.original_customer_id,s.identity_status,s.collection_policy_version,s.retention_expires_at,bs.created_at,bs.status,bs.ended_at)order by s.id),'[]')from selected_streams s join public.e10_break_sessions bs on(bs.organization_id,bs.id)=(s.organization_id,s.session_id)),
    'segments',(select coalesce(jsonb_agg(to_jsonb(g)order by g.stream_id,g.segment_sequence,g.id),'[]')from public.e10_session_presence_segments g join selected_streams s on(s.organization_id,s.id)=(g.organization_id,g.stream_id)),
    'events',(select coalesce(jsonb_agg(to_jsonb(e)order by e.stream_id,e.event_sequence,e.id),'[]')from selected_events e),
    'attributions',(select coalesce(jsonb_agg(to_jsonb(a)order by a.stream_id,a.revision,a.id),'[]')from public.e10_current_session_presence_attributions a join selected_streams s on(s.organization_id,s.id)=(a.organization_id,a.stream_id)),
    'customers',(select coalesce(jsonb_agg(to_jsonb(c)order by c.id),'[]')from public.e10_customers c where c.organization_id=p_org and c.id in(select id from customer_ids)),
    'customer_resolutions',(select coalesce(jsonb_agg(to_jsonb(r)order by r.source_customer_id,r.revision,r.id),'[]')from public.e10_customer_resolution_decisions r where r.organization_id=p_org and(r.source_customer_id in(select id from customer_ids)or r.target_customer_id in(select id from customer_ids)))
  )into v_payload;
  return encode(extensions.digest(v_payload::text,'sha256'),'hex');
end $$;
revoke all on function e10.provider_normalization_dependency_fingerprint(uuid,text,timestamptz,timestamptz,timestamptz,integer)from public,anon,authenticated;
grant execute on function e10.provider_normalization_dependency_fingerprint(uuid,text,timestamptz,timestamptz,timestamptz,integer)to service_role;
