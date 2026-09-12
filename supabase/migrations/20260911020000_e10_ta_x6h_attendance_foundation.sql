-- TA-X6h source-grained observed attendance evidence. No UI telemetry or aggregation semantics.
create table public.e10_presence_collection_policies(
 organization_id uuid not null references public.e10_organizations(id),policy_version bigint not null check(policy_version>0),
 source_class text not null check(source_class in('companion','authorized_platform')),provider_key text not null,
 enabled boolean not null default false,notice_version text not null check(btrim(notice_version)<>''),
 heartbeat_expiry_seconds integer not null check(heartbeat_expiry_seconds between 1 and 300),
 min_event_interval_ms integer not null check(min_event_interval_ms between 0 and 60000),
 max_events_per_minute integer not null check(max_events_per_minute between 1 and 600),
 retention_interval interval not null check(retention_interval>interval '0' and retention_interval<=interval '10 years'),
 coverage_label text not null check(btrim(coverage_label)<>''),effective_from timestamptz not null,effective_through timestamptz,
 created_by uuid references auth.users(id),created_at timestamptz not null default now(),
 primary key(organization_id,source_class,provider_key,policy_version),
 check(isfinite(effective_from) and (effective_through is null or (isfinite(effective_through) and effective_through>effective_from)))
);
create unique index e10_presence_policy_one_current_uq on public.e10_presence_collection_policies(organization_id,source_class,provider_key) where enabled;

create table public.e10_session_presence_streams(
 id uuid primary key default gen_random_uuid(),organization_id uuid not null,session_id uuid not null,
 source_class text not null check(source_class in('companion','authorized_platform')),provider_key text not null,subject_key text not null,
 connection_id text not null,observed_user_id uuid references auth.users(id) on delete set null,platform_attendee_key text,
 original_customer_id uuid,identity_status text not null check(identity_status in('unresolved','verified_auth','reviewed_attributed')),
 client_instance_id text,collection_policy_version bigint not null,notice_version text not null,coverage_label text not null,
 retention_expires_at timestamptz not null check(isfinite(retention_expires_at)),created_by uuid references auth.users(id),created_at timestamptz not null default clock_timestamp(),
 unique(organization_id,id),unique(organization_id,session_id,source_class,provider_key,subject_key,connection_id),
 foreign key(organization_id,session_id) references public.e10_break_sessions(organization_id,id),
 foreign key(organization_id,original_customer_id) references public.e10_customers(organization_id,id),
 foreign key(organization_id,source_class,provider_key,collection_policy_version) references public.e10_presence_collection_policies(organization_id,source_class,provider_key,policy_version),
 check(length(connection_id) between 1 and 200 and length(subject_key) between 1 and 300 and length(provider_key) between 1 and 100),
 check(client_instance_id is null or length(client_instance_id) between 1 and 200),
 check((source_class='companion' and observed_user_id is not null and platform_attendee_key is null and subject_key=observed_user_id::text)
    or(source_class='authorized_platform' and observed_user_id is null and platform_attendee_key is not null and subject_key=platform_attendee_key))
);
create table public.e10_session_presence_segments(
 id uuid primary key default gen_random_uuid(),organization_id uuid not null,stream_id uuid not null,segment_sequence bigint not null check(segment_sequence>0),
 heartbeat_expiry_seconds integer not null check(heartbeat_expiry_seconds between 1 and 300),retention_expires_at timestamptz not null check(isfinite(retention_expires_at)),
 collection_policy_version bigint not null,notice_version text not null,coverage_label text not null,created_at timestamptz not null default clock_timestamp(),unique(organization_id,id),unique(organization_id,stream_id,segment_sequence),
 foreign key(organization_id,stream_id) references public.e10_session_presence_streams(organization_id,id)
);
create table public.e10_session_presence_events(
 id uuid primary key default gen_random_uuid(),organization_id uuid not null,stream_id uuid not null,segment_id uuid not null,event_sequence bigint not null check(event_sequence>0),
 event_kind text not null check(event_kind in('join','heartbeat','leave')),server_received_at timestamptz not null default clock_timestamp() check(isfinite(server_received_at)),
 client_occurred_at timestamptz,provider_occurred_at timestamptz,provider_event_id text,corrects_event_id uuid,
 provider_key text,
 evidence jsonb not null check(jsonb_typeof(evidence)='object' and octet_length(evidence::text)<=65536),request_fingerprint text not null,
 created_by uuid references auth.users(id),unique(organization_id,id),unique(organization_id,stream_id,event_sequence),
 foreign key(organization_id,stream_id) references public.e10_session_presence_streams(organization_id,id),
 foreign key(organization_id,segment_id) references public.e10_session_presence_segments(organization_id,id),
 foreign key(organization_id,corrects_event_id) references public.e10_session_presence_events(organization_id,id),
 check(client_occurred_at is null or isfinite(client_occurred_at)),check(provider_occurred_at is null or isfinite(provider_occurred_at)),
 check((provider_event_id is null and provider_key is null)or(provider_event_id is not null and provider_key is not null))
);
create unique index e10_presence_event_correction_uq on public.e10_session_presence_events(organization_id,corrects_event_id) where corrects_event_id is not null;
create unique index e10_presence_provider_event_uq on public.e10_session_presence_events(organization_id,provider_key,provider_event_id) where provider_event_id is not null;
create table public.e10_session_presence_receipts(
 organization_id uuid not null,subject_key text not null,idempotency_key text not null,operation text not null,request_fingerprint text not null,result jsonb not null,
 created_by uuid references auth.users(id),created_at timestamptz not null default now(),primary key(organization_id,subject_key,idempotency_key),
 foreign key(organization_id) references public.e10_organizations(id),check(length(idempotency_key) between 1 and 500)
);
create table public.e10_session_presence_attribution_decisions(
 id uuid primary key default gen_random_uuid(),organization_id uuid not null,stream_id uuid not null,revision bigint not null check(revision>0),
 action text not null check(action in('attribute','unattribute')),customer_id uuid,supersedes_decision_id uuid,reason text not null,evidence jsonb not null,
 idempotency_key text not null,request_fingerprint text not null,decided_by uuid references auth.users(id),decided_at timestamptz not null default now(),
 unique(organization_id,id),unique(organization_id,stream_id,revision),unique(organization_id,idempotency_key),
 foreign key(organization_id,stream_id) references public.e10_session_presence_streams(organization_id,id),
 foreign key(organization_id,customer_id) references public.e10_customers(organization_id,id),
 foreign key(organization_id,supersedes_decision_id) references public.e10_session_presence_attribution_decisions(organization_id,id),
 check((action='attribute' and customer_id is not null)or(action='unattribute' and customer_id is null)),check(jsonb_typeof(evidence)='object')
);
create unique index e10_presence_attribution_successor_uq on public.e10_session_presence_attribution_decisions(organization_id,supersedes_decision_id) where supersedes_decision_id is not null;

alter table public.e10_presence_collection_policies enable row level security;
alter table public.e10_session_presence_streams enable row level security;
alter table public.e10_session_presence_segments enable row level security;
alter table public.e10_session_presence_events enable row level security;
alter table public.e10_session_presence_receipts enable row level security;
alter table public.e10_session_presence_attribution_decisions enable row level security;
revoke all on public.e10_presence_collection_policies,public.e10_session_presence_streams,public.e10_session_presence_segments,public.e10_session_presence_events,public.e10_session_presence_receipts,public.e10_session_presence_attribution_decisions from public,anon,authenticated;
grant all on public.e10_presence_collection_policies,public.e10_session_presence_streams,public.e10_session_presence_segments,public.e10_session_presence_events,public.e10_session_presence_receipts,public.e10_session_presence_attribution_decisions to service_role;
create function e10.guard_presence_policy_change() returns trigger language plpgsql set search_path=public as $$
begin
 if tg_op='DELETE' then raise exception using errcode='42501',message='presence_policy_delete_denied';end if;
 if (to_jsonb(new)-'enabled') is distinct from (to_jsonb(old)-'enabled') then raise exception using errcode='42501',message='presence_policy_version_immutable';end if;
 return new;
end $$;
revoke all on function e10.guard_presence_policy_change() from public,anon,authenticated;grant execute on function e10.guard_presence_policy_change() to service_role;
create trigger e10_presence_policy_guard before update or delete on public.e10_presence_collection_policies for each row execute function e10.guard_presence_policy_change();
create trigger e10_presence_stream_immutable before update or delete on public.e10_session_presence_streams for each row execute function e10.reject_append_only_change();
create trigger e10_presence_segment_immutable before update or delete on public.e10_session_presence_segments for each row execute function e10.reject_append_only_change();
create trigger e10_presence_event_immutable before update or delete on public.e10_session_presence_events for each row execute function e10.reject_append_only_change();
create trigger e10_presence_receipt_immutable before update or delete on public.e10_session_presence_receipts for each row execute function e10.reject_append_only_change();
create trigger e10_presence_attribution_immutable before update or delete on public.e10_session_presence_attribution_decisions for each row execute function e10.reject_append_only_change();

create view public.e10_current_session_presence_attributions with(security_invoker=true) as select d.* from public.e10_session_presence_attribution_decisions d where not exists(select 1 from public.e10_session_presence_attribution_decisions n where n.organization_id=d.organization_id and n.supersedes_decision_id=d.id);
revoke all on public.e10_current_session_presence_attributions from public,anon,authenticated;grant select on public.e10_current_session_presence_attributions to service_role;

create function e10.presence_session_access(p_session uuid) returns boolean language sql stable security definer set search_path=public as $$
 select auth.uid() is not null and exists(select 1 from public.e10_break_sessions s where s.id=p_session and(
  e10.is_org_member(s.organization_id) or e10.owns_session(s.id) or e10.can_spectate_session(s.id)
  or exists(select 1 from public.e10_session_viewers v where v.organization_id=s.organization_id and v.session_id=s.id and v.user_id=auth.uid())
  or exists(select 1 from public.e10_break_slots sl where sl.organization_id=s.organization_id and sl.session_id=s.id and e10.owns_slot(sl.id))))
$$;
revoke all on function e10.presence_session_access(uuid) from public,anon,authenticated;
grant execute on function e10.presence_session_access(uuid) to service_role;

create function public.e10_record_own_companion_presence(p_session uuid,p_connection_id text,p_client_instance_id text,p_event_kind text,p_client_occurred_at timestamptz,p_notice_version text,p_evidence jsonb,p_idempotency_key text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_org uuid;v_status text;v_ended timestamptz;v_policy record;v_subject text:=auth.uid()::text;v_fp text;v_receipt record;v_stream record;v_segment record;v_last record;v_now timestamptz;v_customer uuid;v_identity text;v_event uuid:=gen_random_uuid();v_result jsonb;v_segment_seq bigint;v_event_seq bigint;
begin
 if auth.uid() is null or not e10.presence_session_access(p_session) then raise exception using errcode='42501',message='presence_session_denied';end if;
 if p_connection_id is null or length(btrim(p_connection_id)) not between 1 and 200 or(p_client_instance_id is not null and length(btrim(p_client_instance_id)) not between 1 and 200)or p_event_kind is null or p_event_kind not in('join','heartbeat','leave')or p_notice_version is null or btrim(p_notice_version)=''or p_evidence is null or jsonb_typeof(p_evidence)<>'object'or octet_length(p_evidence::text)>65536 or p_idempotency_key is null or length(btrim(p_idempotency_key)) not between 1 and 500 or(p_client_occurred_at is not null and not isfinite(p_client_occurred_at)) then raise exception using errcode='22023',message='presence_event_invalid';end if;
 select organization_id,status,ended_at into v_org,v_status,v_ended from public.e10_break_sessions where id=p_session;
 v_fp:=md5(jsonb_build_object('v','companion-presence-v1','session',p_session,'connection',btrim(p_connection_id),'instance',p_client_instance_id,'kind',p_event_kind,'client_time',p_client_occurred_at,'notice',p_notice_version,'evidence',p_evidence)::text);
 -- Customer-resolution topology is always the first application lock.
 perform pg_advisory_xact_lock(hashtextextended(v_org::text||'|customer-resolution-topology',0));
 perform pg_advisory_xact_lock(hashtextextended(v_org::text||'|presence-receipt|'||v_subject||'|'||p_idempotency_key,0));
 perform pg_advisory_xact_lock(hashtextextended(v_org::text||'|presence-stream|'||p_session::text||'|'||v_subject||'|'||btrim(p_connection_id),0));
 if not e10.presence_session_access(p_session) then raise exception using errcode='42501',message='presence_session_denied';end if;
 select status,ended_at into v_status,v_ended from public.e10_break_sessions where organization_id=v_org and id=p_session for update;
 if not e10.presence_session_access(p_session) then raise exception using errcode='42501',message='presence_session_denied';end if;
 v_now:=clock_timestamp();
 select request_fingerprint,result into v_receipt from public.e10_session_presence_receipts where organization_id=v_org and subject_key=v_subject and idempotency_key=p_idempotency_key;
 if found then if v_receipt.request_fingerprint<>v_fp then raise exception using errcode='22023',message='idempotency_key_mismatch';end if;return v_receipt.result||'{"replay":true}'::jsonb;end if;
 select * into v_policy from public.e10_presence_collection_policies where organization_id=v_org and source_class='companion' and provider_key='companion' and enabled and effective_from<=v_now and(effective_through is null or effective_through>v_now);
 if not found then raise exception using errcode='42501',message='presence_collection_disabled';end if;
 if v_policy.notice_version<>p_notice_version then raise exception using errcode='42501',message='presence_notice_stale';end if;
 if p_event_kind in('join','heartbeat') and v_status<>'active' then raise exception using errcode='42501',message='presence_session_ended';end if;
 if(select count(*) from public.e10_session_presence_events ev join public.e10_session_presence_streams st on(st.organization_id,st.id)=(ev.organization_id,ev.stream_id) where ev.organization_id=v_org and st.session_id=p_session and st.source_class='companion' and st.observed_user_id=auth.uid() and ev.server_received_at>v_now-interval '1 minute')>=v_policy.max_events_per_minute then raise exception using errcode='54000',message='presence_event_rate_limited';end if;
 select * into v_stream from public.e10_session_presence_streams where organization_id=v_org and session_id=p_session and source_class='companion' and provider_key='companion' and subject_key=v_subject and connection_id=btrim(p_connection_id);
 if not found then
  if p_event_kind<>'join' then raise exception using errcode='22023',message='presence_join_required';end if;
  select customer_id,identity_status into v_customer,v_identity from e10.resolve_native_break_buyer(v_org,auth.uid(),null);
  insert into public.e10_session_presence_streams(organization_id,session_id,source_class,provider_key,subject_key,connection_id,observed_user_id,original_customer_id,identity_status,client_instance_id,collection_policy_version,notice_version,coverage_label,retention_expires_at,created_by)
   values(v_org,p_session,'companion','companion',v_subject,btrim(p_connection_id),auth.uid(),v_customer,v_identity,nullif(btrim(p_client_instance_id),''),v_policy.policy_version,v_policy.notice_version,v_policy.coverage_label,v_now+v_policy.retention_interval,auth.uid()) returning * into v_stream;
  v_segment_seq:=1;
  insert into public.e10_session_presence_segments(organization_id,stream_id,segment_sequence,heartbeat_expiry_seconds,retention_expires_at,collection_policy_version,notice_version,coverage_label) values(v_org,v_stream.id,1,v_policy.heartbeat_expiry_seconds,v_now+v_policy.retention_interval,v_policy.policy_version,v_policy.notice_version,v_policy.coverage_label) returning * into v_segment;
 else
  if v_stream.collection_policy_version<>v_policy.policy_version or v_stream.notice_version<>v_policy.notice_version then raise exception using errcode='55000',message='presence_policy_reconnect_required';end if;
  select * into v_last from public.e10_session_presence_events where organization_id=v_org and stream_id=v_stream.id order by event_sequence desc limit 1;
  if v_last.event_kind='leave' or p_event_kind='join' then raise exception using errcode='22023',message='presence_transition_invalid';end if;
  if extract(epoch from(v_now-v_last.server_received_at))*1000<v_policy.min_event_interval_ms then raise exception using errcode='54000',message='presence_event_rate_limited';end if;
  if(select count(*) from public.e10_session_presence_events where organization_id=v_org and stream_id=v_stream.id and server_received_at>v_now-interval '1 minute')>=v_policy.max_events_per_minute then raise exception using errcode='54000',message='presence_event_rate_limited';end if;
  select * into v_segment from public.e10_session_presence_segments where organization_id=v_org and id=v_last.segment_id;
  if p_event_kind='heartbeat' and v_now>v_last.server_received_at+make_interval(secs=>v_segment.heartbeat_expiry_seconds) then
   select max(segment_sequence)+1 into v_segment_seq from public.e10_session_presence_segments where organization_id=v_org and stream_id=v_stream.id;
   insert into public.e10_session_presence_segments(organization_id,stream_id,segment_sequence,heartbeat_expiry_seconds,retention_expires_at,collection_policy_version,notice_version,coverage_label) values(v_org,v_stream.id,v_segment_seq,v_policy.heartbeat_expiry_seconds,v_now+v_policy.retention_interval,v_policy.policy_version,v_policy.notice_version,v_policy.coverage_label) returning * into v_segment;
  end if;
 end if;
 select coalesce(max(event_sequence),0)+1 into v_event_seq from public.e10_session_presence_events where organization_id=v_org and stream_id=v_stream.id;
 insert into public.e10_session_presence_events(id,organization_id,stream_id,segment_id,event_sequence,event_kind,server_received_at,client_occurred_at,evidence,request_fingerprint,created_by) values(v_event,v_org,v_stream.id,v_segment.id,v_event_seq,p_event_kind,v_now,p_client_occurred_at,p_evidence,v_fp,auth.uid());
 v_result:=jsonb_build_object('ok',true,'replay',false,'stream_id',v_stream.id,'segment_id',v_segment.id,'event_id',v_event,'event_sequence',v_event_seq,'source_class','companion','coverage_label',v_segment.coverage_label,'customer_id',v_stream.original_customer_id,'identity_status',v_stream.identity_status,'commercial_write',false);
 insert into public.e10_session_presence_receipts values(v_org,v_subject,p_idempotency_key,'companion_event',v_fp,v_result,auth.uid(),now());return v_result;
end $$;
revoke all on function public.e10_record_own_companion_presence(uuid,text,text,text,timestamptz,text,jsonb,text) from public,anon;
grant execute on function public.e10_record_own_companion_presence(uuid,text,text,text,timestamptz,text,jsonb,text) to authenticated,service_role;

create view public.e10_session_presence_segment_intervals with(security_invoker=true) as
with facts as(
 select sg.organization_id,st.session_id,st.id stream_id,sg.id segment_id,sg.segment_sequence,st.source_class,st.provider_key,st.subject_key,st.observed_user_id,st.original_customer_id,st.identity_status,
  sg.collection_policy_version,sg.notice_version,sg.coverage_label,sg.retention_expires_at,bs.status session_status,bs.ended_at session_ended_at,
  min(ev.server_received_at)filter(where ev.event_kind in('join','heartbeat')) started_at,
  max(ev.server_received_at)filter(where ev.event_kind in('join','heartbeat')) last_presence_at,
  min(ev.server_received_at)filter(where ev.event_kind='leave') leave_at,sg.heartbeat_expiry_seconds
 from public.e10_session_presence_segments sg join public.e10_session_presence_streams st on(st.organization_id,st.id)=(sg.organization_id,sg.stream_id)and st.source_class='companion'
 join public.e10_session_presence_events ev on(ev.organization_id,ev.segment_id)=(sg.organization_id,sg.id)
 join public.e10_break_sessions bs on(bs.organization_id,bs.id)=(st.organization_id,st.session_id)
 group by sg.organization_id,st.session_id,st.id,sg.id,sg.segment_sequence,st.source_class,st.provider_key,st.subject_key,st.observed_user_id,st.original_customer_id,st.identity_status,sg.collection_policy_version,sg.notice_version,sg.coverage_label,sg.retention_expires_at,bs.status,bs.ended_at,sg.heartbeat_expiry_seconds
),bounds as(
 select f.*,f.last_presence_at+make_interval(secs=>f.heartbeat_expiry_seconds) heartbeat_at,
  case when f.session_status='ended'and f.session_ended_at is not null and isfinite(f.session_ended_at)then f.session_ended_at else 'infinity'::timestamptz end valid_session_end,
  (f.session_status='ended'and(f.session_ended_at is null or not isfinite(f.session_ended_at))) session_end_incomplete,clock_timestamp() observation_cutoff
 from facts f where f.started_at is not null
),winner as(
 select b.*,case when b.session_end_incomplete then b.started_at else greatest(b.started_at,least(coalesce(b.leave_at,'infinity'::timestamptz),b.heartbeat_at,b.valid_session_end,b.retention_expires_at,b.observation_cutoff))end ended_at
 from bounds b
)
select organization_id,session_id,stream_id,segment_id,segment_sequence,source_class,provider_key,subject_key,observed_user_id,original_customer_id,identity_status,collection_policy_version,notice_version,coverage_label,retention_expires_at,
 started_at original_started_at,ended_at original_ended_at,session_end_incomplete,
 case when session_end_incomplete then 'session_end_incomplete' when ended_at=started_at then 'invalid_or_prestart_bound' when ended_at=coalesce(leave_at,'infinity'::timestamptz)then 'leave' when ended_at=heartbeat_at then 'heartbeat_expiry' when ended_at=valid_session_end then 'session_end' when ended_at=retention_expires_at then 'retention' else 'observation_cutoff' end expiry_reason
from winner;
revoke all on public.e10_session_presence_segment_intervals from public,anon,authenticated;grant select on public.e10_session_presence_segment_intervals to service_role;

comment on view public.e10_session_presence_segment_intervals is 'Source-grained observed presence segments only. Not overlap-unioned attendance, watch time, or weekly aggregation.';
