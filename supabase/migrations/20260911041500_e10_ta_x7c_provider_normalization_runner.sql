-- TA-X7c atomic service-only provider-time normalization runner.
create function e10.provider_normalization_coverage_parts(
  p_org uuid,p_provider text,p_policy_version bigint,p_from timestamptz,p_to timestamptz
)returns table(started_at timestamptz,ended_at timestamptz,disposition text)
language sql stable security definer set search_path=public as $$
  with states as(
    select h.enabled,h.state_from,
      lead(h.state_from,1,'infinity'::timestamptz)over(order by h.state_from,h.id)state_to
    from public.e10_presence_policy_state_history h
    where h.organization_id=p_org and h.source_class='authorized_platform'
      and h.provider_key=btrim(p_provider)and h.policy_version=p_policy_version
  ),coverage as(
    select coalesce(range_agg(tstzrange(greatest(a.covered_from,p_from),least(a.covered_to,p_to),'[)'))filter(where a.coverage_status='complete'),'{}'::tstzmultirange)complete_mr,
      coalesce(range_agg(tstzrange(greatest(a.covered_from,p_from),least(a.covered_to,p_to),'[)'))filter(where a.coverage_status in('partial','unavailable')),'{}'::tstzmultirange)degraded_mr
    from public.e10_current_attendance_coverage_assertions a
    where a.organization_id=p_org and a.source_class='authorized_platform'
      and a.provider_key=btrim(p_provider)and a.policy_version=p_policy_version
      and a.covered_from<p_to and a.covered_to>p_from
  ),policy as(
    select coalesce(range_agg(tstzrange(greatest(p.effective_from,p_from),least(coalesce(p.effective_through,p_to),p_to),'[)')),'{}'::tstzmultirange)policy_mr
    from public.e10_presence_collection_policies p
    where p.organization_id=p_org and p.source_class='authorized_platform'
      and p.provider_key=btrim(p_provider)and p.policy_version=p_policy_version
      and p.effective_from<p_to and coalesce(p.effective_through,p_to)>p_from
  ),disabled as(
    select coalesce(range_agg(tstzrange(greatest(state_from,p_from),least(state_to,p_to),'[)')),'{}'::tstzmultirange)disabled_mr
    from states where not enabled and state_from<p_to and state_to>p_from
  ),enabled as(
    select coalesce(range_agg(tstzrange(greatest(state_from,p_from),least(state_to,p_to),'[)')),'{}'::tstzmultirange)enabled_mr
    from states where enabled and state_from<p_to and state_to>p_from
  ),m as(
    select tstzmultirange(tstzrange(p_from,p_to,'[)'))full_mr,
      (c.complete_mr-c.degraded_mr)*p.policy_mr coverage_mr,d.disabled_mr,e.enabled_mr
    from coverage c cross join policy p cross join disabled d cross join enabled e
  ),parts as(
    select unnest(coverage_mr*enabled_mr)r,'eligible'::text as disposition from m
    union all select unnest(coverage_mr*disabled_mr),'collection_disabled'::text from m
    union all select unnest(full_mr-(coverage_mr*enabled_mr)-(coverage_mr*disabled_mr)),'coverage_unavailable'::text from m
  )select lower(r),upper(r),disposition from parts where not isempty(r)order by lower(r),disposition
$$;
revoke all on function e10.provider_normalization_coverage_parts(uuid,text,bigint,timestamptz,timestamptz)from public,anon,authenticated;
grant execute on function e10.provider_normalization_coverage_parts(uuid,text,bigint,timestamptz,timestamptz)to service_role;

create function public.e10_service_run_provider_presence_normalization(
  p_org uuid,p_provider text,p_policy_decision_id uuid,
  p_from timestamptz,p_to timestamptz,p_observation_cutoff timestamptz,
  p_max_events integer,p_idempotency_key text
) returns jsonb language plpgsql security definer
set search_path=public set timezone='UTC' set intervalstyle='postgres' as $$
declare
  v_provider text:=btrim(p_provider);v_policy record;v_replay record;
  v_dependency text;v_request text;v_run uuid:=gen_random_uuid();
  v_revision bigint;v_input_count integer;v_interval_count integer:=0;
  v_quarantine_count integer:=0;v_stream record;v_event record;v_parent record;
  v_coverage record;v_cursor uuid;v_seen uuid[];v_evidence uuid[];v_segment record;
  v_source_ids uuid[];v_open boolean;v_open_at timestamptz;v_last_at timestamptz;
  v_end timestamptz;v_started timestamptz;v_reason text;v_depth integer;
  v_invalid text;v_covered boolean;v_retention timestamptz;v_bound_exceeded boolean;
begin
  if p_org is null or p_provider is null or length(v_provider) not between 1 and 100
     or p_policy_decision_id is null or p_from is null or p_to is null
     or p_observation_cutoff is null or not isfinite(p_from) or not isfinite(p_to)
     or not isfinite(p_observation_cutoff) or p_to<=p_from
     or p_observation_cutoff<p_to or p_to-p_from>interval '366 days'
     or p_max_events is null or p_max_events not between 1 and 100000
     or p_idempotency_key is null or length(btrim(p_idempotency_key)) not between 1 and 500 then
    raise exception using errcode='22023',message='provider_normalization_run_invalid';
  end if;
  if coalesce(auth.role(),'')<>'service_role' and session_user not in('postgres','supabase_admin') then
    raise exception using errcode='42501',message='provider_normalization_service_denied';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|provider-normalization-idem|'||btrim(p_idempotency_key),0));
  perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|provider-normalization|'||v_provider||'|'||p_observation_cutoff::text,0));
  if coalesce(auth.role(),'')<>'service_role' and session_user not in('postgres','supabase_admin') then
    raise exception using errcode='42501',message='provider_normalization_service_denied';
  end if;
  select * into v_policy from public.e10_provider_presence_normalization_policy_decisions
    where organization_id=p_org and id=p_policy_decision_id and provider_key=v_provider;
  if not found or v_policy.action not in('enable','supersede')
     or v_policy.effective_from>p_from or v_policy.effective_through<p_to
     or not exists(select 1 from e10.provider_presence_normalization_policy_at(
       p_org,v_provider,p_from)p where p.id=v_policy.id)
     or not exists(select 1 from e10.provider_presence_normalization_policy_at(
       p_org,v_provider,p_to-interval '1 microsecond')p where p.id=v_policy.id)
     or not exists(select 1 from public.e10_presence_collection_policies p
       where p.organization_id=p_org and p.source_class='authorized_platform'
         and p.provider_key=v_provider and p.policy_version=v_policy.collection_policy_version) then
    raise exception using errcode='22023',message='provider_normalization_policy_unavailable';
  end if;

  v_dependency:=e10.provider_normalization_dependency_fingerprint(
    p_org,v_provider,p_from,p_to,p_observation_cutoff,p_max_events);
  v_request:=encode(extensions.digest(jsonb_build_object(
    'v','provider-run-v1','org',p_org,'provider',v_provider,'policy',p_policy_decision_id,
    'from',p_from,'to',p_to,'cutoff',p_observation_cutoff,'max_events',p_max_events,
    'dependency',v_dependency)::text,'sha256'),'hex');
  select * into v_replay from public.e10_provider_presence_normalization_runs
    where organization_id=p_org and idempotency_key=btrim(p_idempotency_key);
  if found then
    if v_replay.request_fingerprint<>v_request then
      raise exception using errcode='22023',message='idempotency_key_mismatch';end if;
    return jsonb_build_object('ok',true,'replay',true,'run_id',v_replay.id,
      'status',v_replay.status,'interval_count',v_replay.interval_count,
      'quarantine_count',v_replay.quarantine_count,
      'output_reporting_revision',v_replay.output_reporting_revision);
  end if;

  select revision into v_revision from public.e10_reporting_dataset_revisions
    where organization_id=p_org for update;
  if not found then raise exception using errcode='23503',message='reporting_revision_not_found';end if;
  if coalesce(auth.role(),'')<>'service_role' and session_user not in('postgres','supabase_admin') then
    raise exception using errcode='42501',message='provider_normalization_service_denied';end if;
  if e10.provider_normalization_dependency_fingerprint(
      p_org,v_provider,p_from,p_to,p_observation_cutoff,p_max_events)<>v_dependency then
    raise exception using errcode='40001',message='provider_normalization_input_changed';end if;

  select count(*) into v_input_count
  from public.e10_session_presence_events e
  join public.e10_session_presence_streams s on(s.organization_id,s.id)=(e.organization_id,e.stream_id)
  join public.e10_break_sessions bs on(bs.organization_id,bs.id)=(s.organization_id,s.session_id)
  where s.organization_id=p_org and s.source_class='authorized_platform'and s.provider_key=v_provider
    and bs.created_at<p_to and coalesce(bs.ended_at,p_observation_cutoff)>p_from
    and(e.provider_occurred_at is null or e.provider_occurred_at<p_to
      or e.provider_occurred_at>e.server_received_at
      or e.provider_occurred_at>p_observation_cutoff or e.corrects_event_id is not null);

  insert into public.e10_provider_presence_normalization_runs(
    id,organization_id,provider_key,policy_decision_id,window_from,window_to,
    observation_cutoff,input_reporting_revision,dependency_fingerprint,
    algorithm_version,status,input_event_count,interval_count,quarantine_count,
    idempotency_key,request_fingerprint
  )values(v_run,p_org,v_provider,p_policy_decision_id,p_from,p_to,p_observation_cutoff,
    v_revision,v_dependency,'provider-presence-v1','building',v_input_count,0,0,
    btrim(p_idempotency_key),v_request);

  create temporary table e10_x7c_candidates(
    event_id uuid,stream_id uuid,session_id uuid,event_kind text,event_at timestamptz,
    evidence_ids uuid[],retention_expires_at timestamptz,primary key(event_id)
  )on commit drop;

  -- Every correction walk uses exactly the bounded input relation. Long
  -- no-leaf components fail the whole run rather than silently disappearing.
  with recursive input_events as materialized(
    select e.* from public.e10_session_presence_events e
    join public.e10_session_presence_streams s on(s.organization_id,s.id)=(e.organization_id,e.stream_id)
    join public.e10_break_sessions bs on(bs.organization_id,bs.id)=(s.organization_id,s.session_id)
    where s.organization_id=p_org and s.source_class='authorized_platform'and s.provider_key=v_provider
      and bs.created_at<p_to and coalesce(bs.ended_at,p_observation_cutoff)>p_from
      and(e.provider_occurred_at is null or e.provider_occurred_at<p_to
        or e.provider_occurred_at>e.server_received_at
        or e.provider_occurred_at>p_observation_cutoff or e.corrects_event_id is not null)
  ),walk(root_id,organization_id,stream_id,current_id,path,depth)as(
    select e.id,e.organization_id,e.stream_id,e.id,array[e.id],0 from input_events e
    union all select w.root_id,w.organization_id,w.stream_id,n.id,w.path||n.id,w.depth+1
    from walk w join input_events n on(n.organization_id,n.corrects_event_id,n.stream_id)=(w.organization_id,w.current_id,w.stream_id)
    where w.depth<32 and not n.id=any(w.path)
  )select exists(select 1 from walk w join input_events n
    on(n.organization_id,n.corrects_event_id,n.stream_id)=(w.organization_id,w.current_id,w.stream_id)
    where w.depth>=32 and not n.id=any(w.path))into v_bound_exceeded;
  if v_bound_exceeded then raise exception using errcode='54000',message='provider_normalization_lineage_bound_exceeded';end if;

  -- A bounded cycle has no leaf and must be disclosed explicitly.
  with recursive input_events as materialized(
    select e.* from public.e10_session_presence_events e
    join public.e10_session_presence_streams s on(s.organization_id,s.id)=(e.organization_id,e.stream_id)
    join public.e10_break_sessions bs on(bs.organization_id,bs.id)=(s.organization_id,s.session_id)
    where s.organization_id=p_org and s.source_class='authorized_platform'and s.provider_key=v_provider
      and bs.created_at<p_to and coalesce(bs.ended_at,p_observation_cutoff)>p_from
      and(e.provider_occurred_at is null or e.provider_occurred_at<p_to
        or e.provider_occurred_at>e.server_received_at
        or e.provider_occurred_at>p_observation_cutoff or e.corrects_event_id is not null)
  ),selected(root_id,organization_id,stream_id,current_id,path,depth)as(
    select e.id,e.organization_id,e.stream_id,e.id,array[e.id],0 from input_events e
    union all select w.root_id,w.organization_id,w.stream_id,n.id,w.path||n.id,w.depth+1
    from selected w join input_events n on(n.organization_id,n.corrects_event_id,n.stream_id)=(w.organization_id,w.current_id,w.stream_id)
    where w.depth<32 and not n.id=any(w.path)
  ),cycles as(
    select distinct on(w.root_id)w.root_id id,w.organization_id,w.stream_id,n.id cycle_target
    from selected w join input_events n on(n.organization_id,n.corrects_event_id,n.stream_id)=(w.organization_id,w.current_id,w.stream_id)
    where n.id=any(w.path)order by w.root_id,n.id
  )insert into public.e10_provider_presence_quarantine_rows(
    organization_id,run_id,session_id,stream_id,event_id,reason,evidence_event_ids,details
  )select p_org,v_run,s.session_id,c.stream_id,c.id,'correction_cycle',array[c.id],
    jsonb_build_object('cycle_target',c.cycle_target)from cycles c
    join public.e10_session_presence_streams s on(s.organization_id,s.id)=(c.organization_id,c.stream_id);
  get diagnostics v_depth=row_count;v_quarantine_count:=v_quarantine_count+v_depth;

  for v_stream in
    select s.*,bs.created_at session_started_at,bs.ended_at session_ended_at
    from public.e10_session_presence_streams s join public.e10_break_sessions bs
      on(bs.organization_id,bs.id)=(s.organization_id,s.session_id)
    where s.organization_id=p_org and s.source_class='authorized_platform'
      and s.provider_key=v_provider and bs.created_at<p_to
      and coalesce(bs.ended_at,p_observation_cutoff)>p_from
    order by s.id
  loop
    for v_event in
      select e.* from public.e10_session_presence_events e
      where(e.organization_id,e.stream_id)=(p_org,v_stream.id)
        and(e.provider_occurred_at is null or e.provider_occurred_at<p_to
          or e.provider_occurred_at>e.server_received_at
          or e.provider_occurred_at>p_observation_cutoff or e.corrects_event_id is not null)
        and not exists(select 1 from public.e10_session_presence_events n
          where(n.organization_id,n.corrects_event_id,n.stream_id)=(e.organization_id,e.id,e.stream_id)
            and(n.provider_occurred_at is null or n.provider_occurred_at<p_to
              or n.provider_occurred_at>n.server_received_at
              or n.provider_occurred_at>p_observation_cutoff or n.corrects_event_id is not null))
      order by e.event_sequence,e.id
    loop
      v_invalid:=null;v_cursor:=v_event.id;v_seen:='{}';v_evidence:='{}';v_depth:=0;
      loop
        if v_cursor=any(v_seen) then v_invalid:='correction_cycle';exit;end if;
        v_seen:=array_append(v_seen,v_cursor);v_evidence:=array_append(v_evidence,v_cursor);
        v_depth:=v_depth+1;
        if v_depth>32 then v_invalid:='lineage_bound_exceeded';exit;end if;
        select * into v_parent from public.e10_session_presence_events where organization_id=p_org and id=v_cursor;
        if not found or v_parent.stream_id<>v_stream.id then v_evidence:=array_remove(v_evidence,v_cursor);v_invalid:='cross_stream_correction';exit;end if;
        if(select count(*) from public.e10_session_presence_events n where(n.organization_id,n.corrects_event_id,n.stream_id)=(p_org,v_cursor,v_stream.id)and(n.provider_occurred_at is null or n.provider_occurred_at<p_to or n.provider_occurred_at>n.server_received_at or n.provider_occurred_at>p_observation_cutoff or n.corrects_event_id is not null))>1 then v_invalid:='correction_branch';exit;end if;
        exit when v_parent.corrects_event_id is null;v_cursor:=v_parent.corrects_event_id;
      end loop;
      if v_invalid is null and v_event.provider_occurred_at is null then v_invalid:='missing_provider_time';end if;
      if v_invalid is null and(v_event.provider_occurred_at>v_event.server_received_at or v_event.provider_occurred_at>p_observation_cutoff)then v_invalid:='future_provider_time';end if;
      if v_invalid is null and v_event.server_received_at-v_event.provider_occurred_at>v_policy.maximum_late_arrival then v_invalid:='late_beyond_policy';end if;
      if v_invalid is null and(v_event.provider_occurred_at<v_stream.session_started_at or(v_stream.session_ended_at is not null and v_event.provider_occurred_at>v_stream.session_ended_at))then v_invalid:='outside_session';end if;
      if v_invalid is null and(v_event.provider_occurred_at<v_policy.effective_from or v_event.provider_occurred_at>=v_policy.effective_through)then v_invalid:='outside_policy';end if;
      select * into v_segment from public.e10_session_presence_segments where(organization_id,id)=(p_org,v_event.segment_id);
      if v_invalid is null and(not found or v_segment.stream_id<>v_stream.id or v_segment.collection_policy_version<>v_policy.collection_policy_version)then v_invalid:='collection_disabled';end if;
      if v_invalid is null and v_event.provider_occurred_at>=least(v_stream.retention_expires_at,v_segment.retention_expires_at)then v_invalid:='retention_expired';end if;
      if v_invalid is null then
        insert into e10_x7c_candidates values(v_event.id,v_stream.id,v_stream.session_id,v_event.event_kind,v_event.provider_occurred_at,v_evidence,least(v_stream.retention_expires_at,v_segment.retention_expires_at));
      else
        insert into public.e10_provider_presence_quarantine_rows(
          organization_id,run_id,session_id,stream_id,event_id,reason,evidence_event_ids,details
        )values(p_org,v_run,v_stream.session_id,v_stream.id,v_event.id,v_invalid,v_evidence,
          jsonb_build_object('provider_event_time',v_event.provider_occurred_at,
            'server_received_at',v_event.server_received_at,
            'corrects_event_id',v_event.corrects_event_id));
        v_quarantine_count:=v_quarantine_count+1;
      end if;
    end loop;
  end loop;

  -- No lexical tie-break can decide equal-time semantics. Quarantine every
  -- conflicting or duplicate candidate at that timestamp.
  for v_event in
    select c.stream_id,c.session_id,c.event_at,
      case when count(distinct c.event_kind)>1 then 'same_time_conflict' else 'duplicate_semantic_event' end reason,
      array_agg(c.event_id order by c.event_id) event_ids
    from e10_x7c_candidates c group by c.stream_id,c.session_id,c.event_at having count(*)>1
  loop
    insert into public.e10_provider_presence_quarantine_rows(
      organization_id,run_id,session_id,stream_id,event_id,reason,evidence_event_ids,details
    )select p_org,v_run,v_event.session_id,v_event.stream_id,c.event_id,v_event.reason,
      c.evidence_ids,jsonb_build_object('provider_event_time',v_event.event_at)
      from e10_x7c_candidates c where c.event_id=any(v_event.event_ids);
    get diagnostics v_depth=row_count;v_quarantine_count:=v_quarantine_count+v_depth;
    delete from e10_x7c_candidates where event_id=any(v_event.event_ids);
  end loop;

  for v_stream in
    select s.*,bs.ended_at session_ended_at,
      case when a.id is null then s.original_customer_id
           when a.action='attribute' then a.customer_id else null end attributed_customer_id
    from public.e10_session_presence_streams s
    join public.e10_break_sessions bs on(bs.organization_id,bs.id)=(s.organization_id,s.session_id)
    left join public.e10_current_session_presence_attributions a
      on(a.organization_id,a.stream_id)=(s.organization_id,s.id)
    where s.organization_id=p_org and exists(select 1 from e10_x7c_candidates c where c.stream_id=s.id)
    order by s.id
  loop
    v_open:=false;v_source_ids:='{}';
    for v_event in select * from e10_x7c_candidates where stream_id=v_stream.id order by event_at,event_id
    loop
      if v_open and v_event.event_at>v_last_at+v_policy.heartbeat_expiry then
        v_end:=least(v_last_at+v_policy.heartbeat_expiry,coalesce(v_stream.session_ended_at,p_observation_cutoff),v_policy.effective_through,v_retention,p_observation_cutoff,p_to);
        v_started:=greatest(v_open_at,p_from);v_reason:=case
          when v_end=v_last_at+v_policy.heartbeat_expiry then case when cardinality(v_source_ids)=1 then'join_expiry'else'heartbeat_expiry'end
          when v_stream.session_ended_at is not null and v_end=v_stream.session_ended_at then'session_end'
          when v_end=v_policy.effective_through then'policy_end'
          when v_end=v_retention then'retention_end'else'observation_cutoff'end;v_covered:=false;
        if v_end>v_started then
          for v_coverage in select * from e10.provider_normalization_coverage_parts(
            p_org,v_provider,v_policy.collection_policy_version,v_started,v_end)
          loop
            if v_coverage.disposition='eligible'then
              insert into public.e10_provider_presence_normalized_intervals(
                organization_id,run_id,session_id,stream_id,subject_key,connection_id,
                original_customer_id,effective_customer_id,started_at,ended_at,expiry_reason,source_event_ids
              )values(p_org,v_run,v_stream.session_id,v_stream.id,v_stream.subject_key,v_stream.connection_id,
                v_stream.original_customer_id,e10.customer_effective_id(p_org,v_stream.attributed_customer_id),
                v_coverage.started_at,v_coverage.ended_at,v_reason,v_source_ids);
              v_interval_count:=v_interval_count+1;
            else
              insert into public.e10_provider_presence_quarantine_rows(organization_id,run_id,session_id,stream_id,event_id,reason,evidence_event_ids,details)
              values(p_org,v_run,v_stream.session_id,v_stream.id,v_source_ids[1],v_coverage.disposition,v_source_ids,jsonb_build_object('from',v_coverage.started_at,'to',v_coverage.ended_at));
              v_quarantine_count:=v_quarantine_count+1;
            end if;
            if greatest(v_interval_count,v_quarantine_count)>p_max_events then raise exception using errcode='54000',message='provider_normalization_output_bound_exceeded';end if;
          end loop;
        end if;
        v_open:=false;v_source_ids:='{}';
      end if;
      if v_event.event_kind='join' then
        if v_open then
          insert into public.e10_provider_presence_quarantine_rows(organization_id,run_id,session_id,stream_id,event_id,reason,evidence_event_ids,details)
          values(p_org,v_run,v_stream.session_id,v_stream.id,v_event.event_id,'duplicate_join',v_event.evidence_ids,jsonb_build_object('provider_event_time',v_event.event_at));v_quarantine_count:=v_quarantine_count+1;
        else v_open:=true;v_open_at:=v_event.event_at;v_last_at:=v_event.event_at;v_source_ids:=v_event.evidence_ids;v_retention:=v_event.retention_expires_at;end if;
      elsif not v_open then
        insert into public.e10_provider_presence_quarantine_rows(organization_id,run_id,session_id,stream_id,event_id,reason,evidence_event_ids,details)
        values(p_org,v_run,v_stream.session_id,v_stream.id,v_event.event_id,'missing_join',v_event.evidence_ids,jsonb_build_object('provider_event_time',v_event.event_at));v_quarantine_count:=v_quarantine_count+1;
      else
        v_source_ids:=array(select distinct x from unnest(v_source_ids||v_event.evidence_ids)x order by x);
        if cardinality(v_source_ids)>1000 then raise exception using errcode='54000',message='provider_normalization_lineage_bound_exceeded';end if;
        v_retention:=least(v_retention,v_event.retention_expires_at);
        if v_event.event_kind='heartbeat' then v_last_at:=v_event.event_at;
        else
          v_end:=least(v_event.event_at,coalesce(v_stream.session_ended_at,p_observation_cutoff),v_policy.effective_through,v_retention,p_observation_cutoff,p_to);
          v_started:=greatest(v_open_at,p_from);v_reason:=case
            when v_end=v_event.event_at then'provider_leave'
            when v_stream.session_ended_at is not null and v_end=v_stream.session_ended_at then'session_end'
            when v_end=v_policy.effective_through then'policy_end'
            when v_end=v_retention then'retention_end'else'observation_cutoff'end;v_covered:=false;
          if v_end<=v_started then
            insert into public.e10_provider_presence_quarantine_rows(organization_id,run_id,session_id,stream_id,event_id,reason,evidence_event_ids,details)
            values(p_org,v_run,v_stream.session_id,v_stream.id,v_event.event_id,'negative_interval',v_source_ids,jsonb_build_object('from',v_started,'to',v_end));v_quarantine_count:=v_quarantine_count+1;
          else
            for v_coverage in select * from e10.provider_normalization_coverage_parts(
              p_org,v_provider,v_policy.collection_policy_version,v_started,v_end)
            loop
              if v_coverage.disposition='eligible'then
                insert into public.e10_provider_presence_normalized_intervals(organization_id,run_id,session_id,stream_id,subject_key,connection_id,original_customer_id,effective_customer_id,started_at,ended_at,expiry_reason,source_event_ids)
                values(p_org,v_run,v_stream.session_id,v_stream.id,v_stream.subject_key,v_stream.connection_id,v_stream.original_customer_id,e10.customer_effective_id(p_org,v_stream.attributed_customer_id),v_coverage.started_at,v_coverage.ended_at,v_reason,v_source_ids);v_interval_count:=v_interval_count+1;
              else
                insert into public.e10_provider_presence_quarantine_rows(organization_id,run_id,session_id,stream_id,event_id,reason,evidence_event_ids,details)
                values(p_org,v_run,v_stream.session_id,v_stream.id,v_event.event_id,v_coverage.disposition,v_source_ids,jsonb_build_object('from',v_coverage.started_at,'to',v_coverage.ended_at));v_quarantine_count:=v_quarantine_count+1;
              end if;
              if greatest(v_interval_count,v_quarantine_count)>p_max_events then raise exception using errcode='54000',message='provider_normalization_output_bound_exceeded';end if;
            end loop;
          end if;
          v_open:=false;v_source_ids:='{}';
        end if;
      end if;
    end loop;
    if v_open then
      v_end:=least(v_last_at+v_policy.heartbeat_expiry,coalesce(v_stream.session_ended_at,p_observation_cutoff),v_policy.effective_through,v_retention,p_observation_cutoff,p_to);
      v_started:=greatest(v_open_at,p_from);v_reason:=case when v_end=v_last_at+v_policy.heartbeat_expiry then case when v_source_ids[1] is not null and cardinality(v_source_ids)=1 then 'join_expiry'else'heartbeat_expiry'end when v_stream.session_ended_at is not null and v_end=v_stream.session_ended_at then'session_end'when v_end=v_policy.effective_through then'policy_end'when v_end=v_retention then'retention_end'else'observation_cutoff'end;v_covered:=false;
      if v_end>v_started then
        for v_coverage in select * from e10.provider_normalization_coverage_parts(
          p_org,v_provider,v_policy.collection_policy_version,v_started,v_end)
        loop
          if v_coverage.disposition='eligible'then
            insert into public.e10_provider_presence_normalized_intervals(organization_id,run_id,session_id,stream_id,subject_key,connection_id,original_customer_id,effective_customer_id,started_at,ended_at,expiry_reason,source_event_ids)
            values(p_org,v_run,v_stream.session_id,v_stream.id,v_stream.subject_key,v_stream.connection_id,v_stream.original_customer_id,e10.customer_effective_id(p_org,v_stream.attributed_customer_id),v_coverage.started_at,v_coverage.ended_at,v_reason,v_source_ids);v_interval_count:=v_interval_count+1;
          else
            insert into public.e10_provider_presence_quarantine_rows(organization_id,run_id,session_id,stream_id,event_id,reason,evidence_event_ids,details)
            values(p_org,v_run,v_stream.session_id,v_stream.id,v_source_ids[1],v_coverage.disposition,v_source_ids,jsonb_build_object('from',v_coverage.started_at,'to',v_coverage.ended_at));v_quarantine_count:=v_quarantine_count+1;
          end if;
          if greatest(v_interval_count,v_quarantine_count)>p_max_events then raise exception using errcode='54000',message='provider_normalization_output_bound_exceeded';end if;
        end loop;
      end if;
    end if;
  end loop;

  if greatest(v_interval_count,v_quarantine_count)>p_max_events then
    raise exception using errcode='54000',message='provider_normalization_output_bound_exceeded';
  end if;
  drop table e10_x7c_candidates;
  if e10.provider_normalization_dependency_fingerprint(p_org,v_provider,p_from,p_to,p_observation_cutoff,p_max_events)<>v_dependency then raise exception using errcode='40001',message='provider_normalization_input_changed';end if;
  update public.e10_provider_presence_normalization_runs set status='complete',interval_count=v_interval_count,quarantine_count=v_quarantine_count,output_reporting_revision=v_revision+1,completed_at=clock_timestamp() where organization_id=p_org and id=v_run;
  update public.e10_reporting_dataset_revisions set revision=v_revision+1,changed_at=clock_timestamp() where organization_id=p_org and revision=v_revision;
  if not found then raise exception using errcode='40001',message='provider_normalization_input_changed';end if;
  return jsonb_build_object('ok',true,'replay',false,'run_id',v_run,'status','complete','interval_count',v_interval_count,'quarantine_count',v_quarantine_count,'output_reporting_revision',v_revision+1);
end $$;
revoke all on function public.e10_service_run_provider_presence_normalization(uuid,text,uuid,timestamptz,timestamptz,timestamptz,integer,text)from public,anon,authenticated;
grant execute on function public.e10_service_run_provider_presence_normalization(uuid,text,uuid,timestamptz,timestamptz,timestamptz,integer,text)to service_role;
