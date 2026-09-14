-- TA-X6h reviewed attribution, authorized-platform ingestion, and bounded reads.

create function public.e10_org_decide_presence_attribution(
  p_org uuid,p_stream uuid,p_expected_revision bigint,p_action text,p_customer uuid,
  p_reason text,p_evidence jsonb,p_idempotency_key text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_actor uuid:=auth.uid();v_stream record;v_current record;v_replay record;v_revision bigint;v_id uuid:=gen_random_uuid();v_fp text;v_result jsonb;
begin
 if v_actor is null or not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.manage_customers') then raise exception using errcode='42501',message='presence_attribution_denied';end if;
 if p_action is null or p_action not in('attribute','unattribute') or (p_action='attribute')<>(p_customer is not null) or p_expected_revision is null or p_expected_revision<0 or p_reason is null or length(btrim(p_reason)) not between 1 and 2000 or p_evidence is null or jsonb_typeof(p_evidence)<>'object' or octet_length(p_evidence::text)>65536 or p_idempotency_key is null or length(btrim(p_idempotency_key)) not between 1 and 500 then raise exception using errcode='22023',message='presence_attribution_invalid';end if;
 v_fp:=md5(jsonb_build_object('v','presence-attribution-v1','org',p_org,'stream',p_stream,'expected',p_expected_revision,'action',p_action,'customer',p_customer,'reason',p_reason,'evidence',p_evidence)::text);
 perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|customer-resolution-topology',0));
 perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|presence-attribution|'||p_stream::text,0));
 if auth.uid() is distinct from v_actor or not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.manage_customers') then raise exception using errcode='42501',message='presence_attribution_denied';end if;
 select * into v_replay from public.e10_session_presence_attribution_decisions where organization_id=p_org and idempotency_key=p_idempotency_key;
 if found then
  if v_replay.request_fingerprint<>v_fp then raise exception using errcode='22023',message='idempotency_key_mismatch';end if;
  return jsonb_build_object('ok',true,'replay',true,'decision_id',v_replay.id,'revision',v_replay.revision,'customer_id',v_replay.customer_id);
 end if;
 select * into v_stream from public.e10_session_presence_streams where organization_id=p_org and id=p_stream;
 if not found then raise exception using errcode='22023',message='presence_stream_not_found';end if;
 if p_customer is not null and not exists(select 1 from public.e10_customers c where c.organization_id=p_org and c.id=p_customer and c.status='active' and e10.customer_effective_id(p_org,c.id)=c.id) then raise exception using errcode='22023',message='presence_customer_invalid';end if;
 select * into v_current from public.e10_current_session_presence_attributions where organization_id=p_org and stream_id=p_stream;
 v_revision:=coalesce(v_current.revision,0);
 if v_revision<>p_expected_revision then raise exception using errcode='40001',message='presence_attribution_revision_conflict';end if;
 insert into public.e10_session_presence_attribution_decisions(id,organization_id,stream_id,revision,action,customer_id,supersedes_decision_id,reason,evidence,idempotency_key,request_fingerprint,decided_by)
 values(v_id,p_org,p_stream,v_revision+1,p_action,p_customer,v_current.id,p_reason,p_evidence,p_idempotency_key,v_fp,v_actor);
 v_result:=jsonb_build_object('ok',true,'replay',false,'decision_id',v_id,'revision',v_revision+1,'customer_id',p_customer);
 return v_result;
end $$;
revoke all on function public.e10_org_decide_presence_attribution(uuid,uuid,bigint,text,uuid,text,jsonb,text) from public,anon;
grant execute on function public.e10_org_decide_presence_attribution(uuid,uuid,bigint,text,uuid,text,jsonb,text) to authenticated,service_role;

create function public.e10_record_authorized_platform_presence(
 p_org uuid,p_session uuid,p_provider_key text,p_attendee_key text,p_connection_id text,
 p_event_kind text,p_provider_occurred_at timestamptz,p_provider_event_id text,
 p_corrects_event_id uuid,p_evidence jsonb
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_policy record;v_stream record;v_last record;v_segment record;v_existing record;v_now timestamptz;v_event uuid:=gen_random_uuid();v_seq bigint;v_segment_seq bigint;v_fp text;
begin
 if current_setting('role',true)<>'service_role' then raise exception using errcode='42501',message='platform_presence_service_only';end if;
 if p_provider_key is null or length(btrim(p_provider_key)) not between 1 and 100 or p_attendee_key is null or length(btrim(p_attendee_key)) not between 1 and 300 or p_connection_id is null or length(btrim(p_connection_id)) not between 1 and 200 or p_event_kind is null or p_event_kind not in('join','heartbeat','leave') or p_provider_occurred_at is null or not isfinite(p_provider_occurred_at) or p_provider_event_id is null or length(btrim(p_provider_event_id)) not between 1 and 300 or p_evidence is null or jsonb_typeof(p_evidence)<>'object' or octet_length(p_evidence::text)>65536 then raise exception using errcode='22023',message='platform_presence_invalid';end if;
 if not exists(select 1 from public.e10_break_sessions s where s.organization_id=p_org and s.id=p_session) then raise exception using errcode='22023',message='presence_session_not_found';end if;
 v_fp:=md5(jsonb_build_object('v','platform-presence-v1','org',p_org,'session',p_session,'provider',btrim(p_provider_key),'attendee',btrim(p_attendee_key),'connection',btrim(p_connection_id),'kind',p_event_kind,'event_id',btrim(p_provider_event_id),'occurred',p_provider_occurred_at,'corrects',p_corrects_event_id,'evidence',p_evidence)::text);
 perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|customer-resolution-topology',0));
 perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|presence-provider-event|'||btrim(p_provider_key)||'|'||btrim(p_provider_event_id),0));
 perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|presence-stream|'||p_session::text||'|'||btrim(p_provider_key)||'|'||btrim(p_attendee_key)||'|'||btrim(p_connection_id),0));
 v_now:=clock_timestamp();
 select * into v_policy from public.e10_presence_collection_policies where organization_id=p_org and source_class='authorized_platform' and provider_key=btrim(p_provider_key) and enabled and effective_from<=v_now and(effective_through is null or effective_through>v_now);
 if not found then raise exception using errcode='42501',message='presence_collection_disabled';end if;
 select e.*,st.session_id,st.subject_key,st.connection_id into v_existing from public.e10_session_presence_events e join public.e10_session_presence_streams st on(st.organization_id,st.id)=(e.organization_id,e.stream_id) where e.organization_id=p_org and e.provider_key=btrim(p_provider_key) and e.provider_event_id=btrim(p_provider_event_id);
 if found then
  if v_existing.request_fingerprint<>v_fp then raise exception using errcode='22023',message='provider_event_id_mismatch';end if;
  return jsonb_build_object('ok',true,'replay',true,'stream_id',v_existing.stream_id,'segment_id',v_existing.segment_id,'event_id',v_existing.id,'event_sequence',v_existing.event_sequence,'provider_occurred_at',v_existing.provider_occurred_at,'interval_eligible',false,'quarantine_reason','provider_chronology_requires_normalization','commercial_write',false);
 end if;
 select * into v_stream from public.e10_session_presence_streams where organization_id=p_org and session_id=p_session and source_class='authorized_platform' and provider_key=btrim(p_provider_key) and subject_key=btrim(p_attendee_key) and connection_id=btrim(p_connection_id);
 if not found then
  if p_event_kind<>'join' then raise exception using errcode='22023',message='presence_join_required';end if;
  insert into public.e10_session_presence_streams(organization_id,session_id,source_class,provider_key,subject_key,connection_id,platform_attendee_key,identity_status,collection_policy_version,notice_version,coverage_label,retention_expires_at)
  values(p_org,p_session,'authorized_platform',btrim(p_provider_key),btrim(p_attendee_key),btrim(p_connection_id),btrim(p_attendee_key),'unresolved',v_policy.policy_version,v_policy.notice_version,v_policy.coverage_label,v_now+v_policy.retention_interval) returning * into v_stream;
  insert into public.e10_session_presence_segments(organization_id,stream_id,segment_sequence,heartbeat_expiry_seconds,retention_expires_at,collection_policy_version,notice_version,coverage_label) values(p_org,v_stream.id,1,v_policy.heartbeat_expiry_seconds,v_now+v_policy.retention_interval,v_policy.policy_version,v_policy.notice_version,v_policy.coverage_label) returning * into v_segment;
 else
  select * into v_last from public.e10_session_presence_events where organization_id=p_org and stream_id=v_stream.id order by event_sequence desc limit 1;
  select * into v_segment from public.e10_session_presence_segments where organization_id=p_org and id=v_last.segment_id;
  if p_event_kind='heartbeat' and v_now>v_last.server_received_at+make_interval(secs=>v_segment.heartbeat_expiry_seconds) then
   select coalesce(max(segment_sequence),0)+1 into v_segment_seq from public.e10_session_presence_segments where organization_id=p_org and stream_id=v_stream.id;
   insert into public.e10_session_presence_segments(organization_id,stream_id,segment_sequence,heartbeat_expiry_seconds,retention_expires_at,collection_policy_version,notice_version,coverage_label) values(p_org,v_stream.id,v_segment_seq,v_policy.heartbeat_expiry_seconds,v_now+v_policy.retention_interval,v_policy.policy_version,v_policy.notice_version,v_policy.coverage_label) returning * into v_segment;
  end if;
 end if;
 if p_corrects_event_id is not null and not exists(select 1 from public.e10_session_presence_events e where e.organization_id=p_org and e.id=p_corrects_event_id and e.stream_id=v_stream.id) then raise exception using errcode='22023',message='presence_correction_target_invalid';end if;
 select coalesce(max(event_sequence),0)+1 into v_seq from public.e10_session_presence_events where organization_id=p_org and stream_id=v_stream.id;
 insert into public.e10_session_presence_events(id,organization_id,stream_id,segment_id,event_sequence,event_kind,server_received_at,provider_occurred_at,provider_event_id,provider_key,corrects_event_id,evidence,request_fingerprint)
 values(v_event,p_org,v_stream.id,v_segment.id,v_seq,p_event_kind,v_now,p_provider_occurred_at,btrim(p_provider_event_id),btrim(p_provider_key),p_corrects_event_id,p_evidence,v_fp);
 return jsonb_build_object('ok',true,'replay',false,'stream_id',v_stream.id,'segment_id',v_segment.id,'event_id',v_event,'event_sequence',v_seq,'provider_occurred_at',p_provider_occurred_at,'interval_eligible',false,'quarantine_reason','provider_chronology_requires_normalization','commercial_write',false);
end $$;
revoke all on function public.e10_record_authorized_platform_presence(uuid,uuid,text,text,text,text,timestamptz,text,uuid,jsonb) from public,anon,authenticated;
grant execute on function public.e10_record_authorized_platform_presence(uuid,uuid,text,text,text,text,timestamptz,text,uuid,jsonb) to service_role;

create function public.e10_org_list_presence_segments(
 p_org uuid,p_from timestamptz,p_to timestamptz,p_session uuid default null,p_customer uuid default null,
 p_limit integer default 100,p_after_started_at timestamptz default null,p_after_segment_id uuid default null
) returns table(session_id uuid,stream_id uuid,segment_id uuid,segment_sequence bigint,source_class text,provider_key text,coverage_label text,collection_policy_version bigint,notice_version text,original_customer_id uuid,attribution_action text,attribution_revision bigint,attribution_decision_id uuid,original_started_at timestamptz,original_ended_at timestamptz,clipped_started_at timestamptz,clipped_ended_at timestamptz,session_end_incomplete boolean,expiry_reason text,effective_customer_id uuid)
language plpgsql stable security definer set search_path=public as $$
begin
 if not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.view_customer_engagement') then raise exception using errcode='42501',message='presence_read_denied';end if;
 if p_from is null or p_to is null or not isfinite(p_from) or not isfinite(p_to) or p_to<=p_from or p_to-p_from>interval '366 days' or p_limit is null or p_limit not between 1 and 200 or ((p_after_started_at is null)<>(p_after_segment_id is null)) or (p_after_started_at is not null and not isfinite(p_after_started_at)) then raise exception using errcode='22023',message='presence_read_bounds_invalid';end if;
 if p_after_segment_id is not null then
  select i.original_started_at into p_after_started_at from public.e10_session_presence_segment_intervals i where i.organization_id=p_org and i.segment_id=p_after_segment_id;
  if not found then raise exception using errcode='22023',message='presence_read_cursor_invalid';end if;
 end if;
 return query
 select i.session_id,i.stream_id,i.segment_id,i.segment_sequence,i.source_class,i.provider_key,i.coverage_label,i.collection_policy_version,i.notice_version,i.original_customer_id,a.action,a.revision,a.id,
  i.original_started_at,i.original_ended_at,greatest(i.original_started_at,p_from),least(i.original_ended_at,p_to),i.session_end_incomplete,i.expiry_reason,
  e10.customer_effective_id(p_org,case when a.id is null then i.original_customer_id when a.action='attribute' then a.customer_id else null end)
 from public.e10_session_presence_segment_intervals i
 left join public.e10_current_session_presence_attributions a on(a.organization_id,a.stream_id)=(i.organization_id,i.stream_id)
 where i.organization_id=p_org and i.original_ended_at>i.original_started_at and i.original_started_at<p_to and i.original_ended_at>p_from
  and(p_session is null or i.session_id=p_session)
  and(p_customer is null or e10.customer_effective_id(p_org,case when a.id is null then i.original_customer_id when a.action='attribute' then a.customer_id else null end)=e10.customer_effective_id(p_org,p_customer))
  and(p_after_started_at is null or(i.original_started_at,i.segment_id)>(p_after_started_at,p_after_segment_id))
 order by i.original_started_at,i.segment_id limit p_limit;
end $$;
revoke all on function public.e10_org_list_presence_segments(uuid,timestamptz,timestamptz,uuid,uuid,integer,timestamptz,uuid) from public,anon;
grant execute on function public.e10_org_list_presence_segments(uuid,timestamptz,timestamptz,uuid,uuid,integer,timestamptz,uuid) to authenticated,service_role;
