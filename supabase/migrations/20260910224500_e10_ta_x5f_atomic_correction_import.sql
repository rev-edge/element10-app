-- TA-X5f atomic corrected-file import and eligible-observation interpretation.

alter table public.e10_intake_batches add column supersedes_intake_batch_id uuid;
alter table public.e10_intake_batches add constraint e10_intake_batches_org_supersedes_fkey
 foreign key(organization_id,supersedes_intake_batch_id) references public.e10_intake_batches(organization_id,id);
alter table public.e10_intake_batches add constraint e10_intake_batches_not_self_supersede_chk
 check(supersedes_intake_batch_id is null or supersedes_intake_batch_id<>id);
drop index public.e10_intake_batches_external_source_uq;
create unique index e10_intake_batches_durable_source_payload_uq
 on public.e10_intake_batches(organization_id,source_kind,source_connection_id,source_reference,payload_fingerprint)
 where source_kind in ('csv','api','native') and source_connection_id is not null and source_reference is not null;

create table public.e10_intake_stage_replays(
 organization_id uuid not null references public.e10_organizations(id), idempotency_key text not null check(btrim(idempotency_key)<>''),
 intake_batch_id uuid not null, request_fingerprint text not null, created_at timestamptz not null default now(),
 primary key(organization_id,idempotency_key),
 foreign key(organization_id,intake_batch_id) references public.e10_intake_batches(organization_id,id));
alter table public.e10_intake_stage_replays enable row level security;
revoke all on public.e10_intake_stage_replays from public,anon,authenticated;
grant all on public.e10_intake_stage_replays to service_role;
create trigger e10_intake_stage_replays_append_only_trg before update or delete on public.e10_intake_stage_replays
 for each row execute function e10.reject_append_only_change();

create table public.e10_corrected_intake_commits(
 id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.e10_organizations(id),
 intake_batch_id uuid not null, intake_commit_id uuid not null, classifications jsonb not null check(jsonb_typeof(classifications)='array'),
 idempotency_key text not null check(btrim(idempotency_key)<>''), request_fingerprint text not null,
 committed_by uuid references auth.users(id), committed_at timestamptz not null default now(),
 unique(organization_id,id),unique(organization_id,intake_batch_id),unique(organization_id,intake_commit_id),unique(organization_id,idempotency_key),
 foreign key(organization_id,intake_batch_id) references public.e10_intake_batches(organization_id,id),
 foreign key(organization_id,intake_commit_id) references public.e10_intake_commits(organization_id,id));
alter table public.e10_corrected_intake_commits enable row level security;
revoke all on public.e10_corrected_intake_commits from public,anon,authenticated;
grant all on public.e10_corrected_intake_commits to service_role;
create trigger e10_corrected_intake_commits_append_only_trg before update or delete on public.e10_corrected_intake_commits
 for each row execute function e10.reject_append_only_change();

alter function public.e10_org_stage_intake(uuid,text,text,text,text,text,jsonb,text) rename to _e10_org_stage_intake_x5b;
revoke all on function public._e10_org_stage_intake_x5b(uuid,text,text,text,text,text,jsonb,text) from public,anon,authenticated;
grant execute on function public._e10_org_stage_intake_x5b(uuid,text,text,text,text,text,jsonb,text) to service_role;

create function public.e10_org_stage_intake(
 p_org uuid,p_source_kind text,p_source_connection_id text,p_source_reference text,p_original_file_reference text,
 p_payload_fingerprint text,p_rows jsonb,p_idempotency_key text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare keyed record; exact record; prior_batch uuid; result jsonb; fp text; durable boolean;
begin
 if not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.manage_intake') then raise exception using errcode='42501',message='manage_intake_denied'; end if;
 if p_idempotency_key is null or btrim(p_idempotency_key)='' then raise exception using errcode='22004',message='idempotency_key_required'; end if;
 fp:=md5(coalesce(p_source_kind,'')||'|'||coalesce(p_source_connection_id,'')||'|'||coalesce(p_source_reference,'')||'|'||
   coalesce(p_original_file_reference,'')||'|'||coalesce(p_payload_fingerprint,'')||'|'||coalesce(p_rows::text,''));
 perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|intake|'||p_idempotency_key,0));
 select id,status,request_fingerprint into keyed from public.e10_intake_batches where organization_id=p_org and idempotency_key=p_idempotency_key;
 if not found then select b.id,b.status,a.request_fingerprint into keyed from public.e10_intake_stage_replays a
  join public.e10_intake_batches b on b.organization_id=a.organization_id and b.id=a.intake_batch_id
  where a.organization_id=p_org and a.idempotency_key=p_idempotency_key; end if;
 if found then
  if keyed.request_fingerprint is distinct from fp then raise exception using errcode='22023',message='idempotency_key_mismatch'; end if;
  return jsonb_build_object('ok',true,'replay',true,'batch_id',keyed.id,'status',keyed.status,
   'row_count',(select count(*) from public.e10_intake_rows where organization_id=p_org and batch_id=keyed.id));
 end if;
 durable:=p_source_kind in ('csv','api','native') and p_source_connection_id is not null and p_source_reference is not null;
 if durable then
  perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|durable-intake-source|'||p_source_kind||'|'||p_source_connection_id||'|'||p_source_reference,0));
  select id,status,request_fingerprint into exact from public.e10_intake_batches where organization_id=p_org
   and source_kind=p_source_kind and source_connection_id=p_source_connection_id and source_reference=p_source_reference
   and payload_fingerprint=p_payload_fingerprint order by created_at,id limit 1;
  if found then
   if exact.request_fingerprint is distinct from fp then raise exception using errcode='22023',message='source_payload_fingerprint_mismatch'; end if;
   insert into public.e10_intake_stage_replays(organization_id,idempotency_key,intake_batch_id,request_fingerprint)
    values(p_org,p_idempotency_key,exact.id,fp);
   return jsonb_build_object('ok',true,'replay',true,'batch_id',exact.id,'status',exact.status,
    'row_count',(select count(*) from public.e10_intake_rows where organization_id=p_org and batch_id=exact.id));
  end if;
  select id into prior_batch from public.e10_intake_batches where organization_id=p_org and source_kind=p_source_kind
   and source_connection_id=p_source_connection_id and source_reference=p_source_reference order by created_at desc,id desc limit 1;
 end if;
 result:=public._e10_org_stage_intake_x5b(p_org,p_source_kind,p_source_connection_id,p_source_reference,
   p_original_file_reference,p_payload_fingerprint,p_rows,p_idempotency_key);
 if prior_batch is not null then update public.e10_intake_batches set supersedes_intake_batch_id=prior_batch
   where organization_id=p_org and id=(result->>'batch_id')::uuid; end if;
 return result||jsonb_build_object('supersedes_batch_id',prior_batch);
end $$;

alter function public.e10_org_commit_intake(uuid,uuid,bigint,text) rename to _e10_org_commit_intake_x5d;
revoke all on function public._e10_org_commit_intake_x5d(uuid,uuid,bigint,text) from public,anon,authenticated;
grant execute on function public._e10_org_commit_intake_x5d(uuid,uuid,bigint,text) to service_role;

create function public.e10_org_commit_intake(p_org uuid,p_batch_id uuid,p_expected_review_revision bigint,p_idempotency_key text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare supersedes uuid;
begin
 if not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.manage_intake') then raise exception using errcode='42501',message='manage_intake_denied'; end if;
 select supersedes_intake_batch_id into supersedes from public.e10_intake_batches where organization_id=p_org and id=p_batch_id;
 if not found then raise exception using errcode='42501',message='intake_batch_access_denied'; end if;
 if supersedes is not null then raise exception using errcode='55000',message='changed_source_requires_corrected_commit'; end if;
 return public._e10_org_commit_intake_x5d(p_org,p_batch_id,p_expected_review_revision,p_idempotency_key);
end $$;

create function public.e10_org_commit_corrected_intake(
 p_org uuid,p_batch_id uuid,p_expected_review_revision bigint,p_classifications jsonb,p_idempotency_key text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare batch_state record; existing record; result jsonb; fp text; commit_id uuid;
begin
 if not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.manage_intake') then raise exception using errcode='42501',message='manage_intake_denied'; end if;
 if p_idempotency_key is null or btrim(p_idempotency_key)='' then raise exception using errcode='22004',message='idempotency_key_required'; end if;
 if p_classifications is null or jsonb_typeof(p_classifications)<>'array' then raise exception using errcode='22023',message='classifications_must_be_array'; end if;
 if jsonb_array_length(p_classifications)>1000 or octet_length(p_classifications::text)>1000000 then raise exception using errcode='22023',message='classifications_limit_exceeded'; end if;
 fp:=md5(jsonb_build_object('v','corrected-commit-v1','batch',p_batch_id,'revision',p_expected_review_revision,'classifications',p_classifications)::text);
 perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|corrected-commit-key|'||p_idempotency_key,0));
 select * into existing from public.e10_corrected_intake_commits where organization_id=p_org and idempotency_key=p_idempotency_key;
 if found then
  if existing.request_fingerprint<>fp then raise exception using errcode='22023',message='idempotency_key_mismatch'; end if;
  return public._e10_org_commit_intake_x5d(p_org,p_batch_id,p_expected_review_revision,'corrected:'||p_idempotency_key)||jsonb_build_object('corrected',true);
 end if;
 select id,status,review_revision,supersedes_intake_batch_id,source_kind,source_connection_id into batch_state from public.e10_intake_batches
  where organization_id=p_org and id=p_batch_id for update;
 if not found then raise exception using errcode='42501',message='intake_batch_access_denied'; end if;
 if batch_state.supersedes_intake_batch_id is null then raise exception using errcode='55000',message='corrected_commit_requires_changed_source'; end if;
 if batch_state.review_revision<>p_expected_review_revision then raise exception using errcode='40001',message='intake_review_revision_conflict'; end if;
 if exists(select 1 from jsonb_array_elements(p_classifications) e
  where jsonb_typeof(e)<>'object' or coalesce(e->>'classification','') not in ('replacement','new')
   or coalesce(e->>'source_row_number','')!~'^[1-9][0-9]*$'
   or (e->>'classification'='replacement' and ((e->>'superseded_observation_id') is null or btrim(coalesce(e->>'reason',''))=''))
   or (e->>'classification'='new' and (e ? 'superseded_observation_id' or btrim(coalesce(e->>'reason',''))=''
     or jsonb_typeof(e->'duplicate_reviewed') is distinct from 'boolean' or (e->>'duplicate_reviewed')::boolean is not true)))
 then raise exception using errcode='22023',message='classification_invalid'; end if;
 if (select count(*) from jsonb_array_elements(p_classifications))<>(select count(*) from public.e10_intake_rows
   where organization_id=p_org and batch_id=p_batch_id and match_status='matched'
   and observation_kind in ('acquisition_cost','asking_price','completed_sale','estimated_value'))
  or exists(select 1 from jsonb_array_elements(p_classifications) e group by (e->>'source_row_number')::bigint having count(*)>1)
  or exists(select 1 from jsonb_array_elements(p_classifications) e left join public.e10_intake_rows r
    on r.organization_id=p_org and r.batch_id=p_batch_id and r.source_row_number=(e->>'source_row_number')::bigint
    where r.id is null or r.match_status<>'matched' or r.observation_kind not in ('acquisition_cost','asking_price','completed_sale','estimated_value'))
 then raise exception using errcode='22023',message='classification_coverage_invalid'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|observation-lineage-graph',0));
 if exists(select 1 from jsonb_array_elements(p_classifications) e
   join public.e10_intake_rows current_row on current_row.organization_id=p_org and current_row.batch_id=p_batch_id
    and current_row.source_row_number=(e->>'source_row_number')::bigint
   join public.e10_market_observations prior_observation on prior_observation.organization_id=p_org
    and prior_observation.source_kind=batch_state.source_kind
    and prior_observation.source_connection_id is not distinct from batch_state.source_connection_id
   where e->>'classification'='new' and nullif(current_row.raw_payload->>'source_event_id','') is not null
    and prior_observation.raw_payload_snapshot->>'source_event_id'=current_row.raw_payload->>'source_event_id')
 then raise exception using errcode='22023',message='stable_source_event_requires_replacement'; end if;
 if exists(select 1 from jsonb_array_elements(p_classifications) e
   join public.e10_intake_rows current_row on current_row.organization_id=p_org and current_row.batch_id=p_batch_id
    and current_row.source_row_number=(e->>'source_row_number')::bigint
   join public.e10_market_observations prior_observation on prior_observation.organization_id=p_org
    and prior_observation.id=(e->>'superseded_observation_id')::uuid
   where e->>'classification'='replacement' and nullif(current_row.raw_payload->>'source_event_id','') is not null
    and nullif(prior_observation.raw_payload_snapshot->>'source_event_id','') is not null
    and current_row.raw_payload->>'source_event_id'<>prior_observation.raw_payload_snapshot->>'source_event_id')
 then raise exception using errcode='22023',message='stable_source_event_mismatch'; end if;
 if exists(select 1 from jsonb_array_elements(p_classifications) e
   left join public.e10_market_observations o on o.organization_id=p_org and o.id=(e->>'superseded_observation_id')::uuid
   left join public.e10_market_observation_supersessions s on s.organization_id=p_org and s.superseded_observation_id=o.id
   where e->>'classification'='replacement' and (o.id is null or s.id is not null))
 then raise exception using errcode='55000',message='superseded_observation_not_current'; end if;
 result:=public._e10_org_commit_intake_x5d(p_org,p_batch_id,p_expected_review_revision,'corrected:'||p_idempotency_key);
 commit_id:=(result->>'commit_id')::uuid;
 insert into public.e10_corrected_intake_commits(organization_id,intake_batch_id,intake_commit_id,classifications,idempotency_key,request_fingerprint,committed_by)
 values(p_org,p_batch_id,commit_id,p_classifications,p_idempotency_key,fp,auth.uid());
 insert into public.e10_market_observation_supersessions(organization_id,superseded_observation_id,replacement_observation_id,lineage_kind,
  correction_reason,idempotency_key,request_fingerprint,created_by)
 select p_org,(e->>'superseded_observation_id')::uuid,n.id,'reviewed_reimport',e->>'reason',
  'corrected-commit:'||p_idempotency_key||':'||(e->>'source_row_number'),
  md5(jsonb_build_object('v','corrected-link-v1','commit',commit_id,'row',e->>'source_row_number','old',e->>'superseded_observation_id')::text),auth.uid()
 from jsonb_array_elements(p_classifications) e join public.e10_intake_rows r on r.organization_id=p_org and r.batch_id=p_batch_id
  and r.source_row_number=(e->>'source_row_number')::bigint
 join public.e10_market_observations n on n.organization_id=r.organization_id and n.intake_row_id=r.id
 where e->>'classification'='replacement';
 return result||jsonb_build_object('corrected',true);
end $$;

create view public.e10_current_market_observations with(security_invoker=true) as select o.*
 from public.e10_market_observations o where not exists(select 1 from public.e10_market_observation_supersessions s
  where s.organization_id=o.organization_id and s.superseded_observation_id=o.id);
revoke all on public.e10_current_market_observations from public,anon,authenticated;
grant select on public.e10_current_market_observations to service_role;

revoke all on function public.e10_org_stage_intake(uuid,text,text,text,text,text,jsonb,text),
 public.e10_org_commit_intake(uuid,uuid,bigint,text),public.e10_org_commit_corrected_intake(uuid,uuid,bigint,jsonb,text) from public,anon;
grant execute on function public.e10_org_stage_intake(uuid,text,text,text,text,text,jsonb,text),
 public.e10_org_commit_intake(uuid,uuid,bigint,text),public.e10_org_commit_corrected_intake(uuid,uuid,bigint,jsonb,text) to authenticated,service_role;
