-- TA-R3: trusted intake provenance, normalized durable lineage, stable source
-- event identity, and immutable committed-batch lifecycle.

create function e10.reject_committed_intake_batch_change() returns trigger
language plpgsql set search_path=public as $$
begin
  if old.status='committed' and (tg_op='DELETE' or new.status is distinct from old.status) then
    raise exception using errcode='55000',message='committed_intake_batch_is_immutable';
  end if;
  return case when tg_op='DELETE' then old else new end;
end $$;
revoke all on function e10.reject_committed_intake_batch_change() from public,anon,authenticated;
grant execute on function e10.reject_committed_intake_batch_change() to service_role;
create trigger e10_intake_batches_committed_immutable_trg before update or delete
on public.e10_intake_batches for each row execute function e10.reject_committed_intake_batch_change();

create table public.e10_intake_commit_authorizations(
  transaction_id bigint not null,backend_pid integer not null,organization_id uuid not null,
  intake_batch_id uuid not null,source_row_number bigint not null,predecessor_observation_id uuid not null,
  primary key(transaction_id,backend_pid,organization_id,intake_batch_id,source_row_number)
);
revoke all on public.e10_intake_commit_authorizations from public,anon,authenticated;
grant all on public.e10_intake_commit_authorizations to service_role;

create function e10.enforce_stable_market_source_event() returns trigger
language plpgsql set search_path=public as $$
declare
  v_event text;v_prior uuid;v_row bigint;v_batch uuid;v_allowed uuid;
begin
  new.source_connection_id:=nullif(btrim(new.source_connection_id),'');
  new.source_reference:=nullif(btrim(new.source_reference),'');
  v_event:=nullif(btrim(new.raw_payload_snapshot->>'source_event_id'),'');
  if v_event is not null then
    new.raw_payload_snapshot:=jsonb_set(new.raw_payload_snapshot,'{source_event_id}',to_jsonb(v_event),true);
  end if;
  if new.source_kind not in ('csv','api','native') or new.source_connection_id is null or v_event is null then
    return new;
  end if;
  perform pg_advisory_xact_lock(hashtextextended(new.organization_id::text||'|stable-source-event|'||new.source_kind||'|'||new.source_connection_id||'|'||v_event,0));
  select o.id into v_prior from public.e10_market_observations o
  where o.organization_id=new.organization_id and o.source_kind=new.source_kind
    and nullif(btrim(o.source_connection_id),'')=new.source_connection_id
    and nullif(btrim(o.raw_payload_snapshot->>'source_event_id'),'')=v_event
    and not exists(select 1 from public.e10_market_observation_supersessions s
      where s.organization_id=o.organization_id and s.superseded_observation_id=o.id)
  order by o.recorded_at desc,o.id desc limit 1;
  if v_prior is null then return new;end if;
  select r.source_row_number,c.intake_batch_id into v_row,v_batch
  from public.e10_intake_rows r join public.e10_intake_commits c
    on(c.organization_id,c.id)=(r.organization_id,new.intake_commit_id)
  where r.organization_id=new.organization_id and r.id=new.intake_row_id;
  select predecessor_observation_id into v_allowed
  from public.e10_intake_commit_authorizations
  where transaction_id=txid_current() and backend_pid=pg_backend_pid()
    and organization_id=new.organization_id and intake_batch_id=v_batch and source_row_number=v_row;
  if v_allowed is distinct from v_prior then
    raise exception using errcode='23505',message='stable_source_event_duplicate';
  end if;
  return new;
end $$;
revoke all on function e10.enforce_stable_market_source_event() from public,anon,authenticated;
grant execute on function e10.enforce_stable_market_source_event() to service_role;
create trigger e10_market_observations_stable_source_event_trg before insert
on public.e10_market_observations for each row execute function e10.enforce_stable_market_source_event();

alter function public.e10_org_stage_intake(uuid,text,text,text,text,text,jsonb,text)
rename to _e10_org_stage_intake_r3;
revoke all on function public._e10_org_stage_intake_r3(uuid,text,text,text,text,text,jsonb,text) from public,anon,authenticated;
grant execute on function public._e10_org_stage_intake_r3(uuid,text,text,text,text,text,jsonb,text) to service_role;
create function public.e10_org_stage_intake(
  p_org uuid,p_source_kind text,p_source_connection_id text,p_source_reference text,
  p_original_file_reference text,p_payload_fingerprint text,p_rows jsonb,p_idempotency_key text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_rows jsonb;
begin
  if p_source_kind in ('native','system') and current_setting('role',true)<>'service_role' then
    raise exception using errcode='42501',message='intake_source_provenance_invalid';
  end if;
  select jsonb_agg(
    case when nullif(btrim(e->'raw_payload'->>'source_event_id'),'') is null then e
      else jsonb_set(e,'{raw_payload,source_event_id}',to_jsonb(btrim(e->'raw_payload'->>'source_event_id')),true)
    end order by ord)
  into v_rows from jsonb_array_elements(p_rows) with ordinality a(e,ord);
  return public._e10_org_stage_intake_r3(
    p_org,p_source_kind,nullif(btrim(p_source_connection_id),''),nullif(btrim(p_source_reference),''),
    p_original_file_reference,p_payload_fingerprint,coalesce(v_rows,'[]'::jsonb),p_idempotency_key);
end $$;

alter function public.e10_org_commit_intake(uuid,uuid,bigint,text)
rename to _e10_org_commit_intake_r3;
revoke all on function public._e10_org_commit_intake_r3(uuid,uuid,bigint,text) from public,anon,authenticated;
grant execute on function public._e10_org_commit_intake_r3(uuid,uuid,bigint,text) to service_role;
create function public.e10_org_commit_intake(p_org uuid,p_batch_id uuid,p_expected_review_revision bigint,p_idempotency_key text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_source text;
begin
  if p_idempotency_key like 'corrected:%' then
    raise exception using errcode='22023',message='intake_idempotency_namespace_reserved';
  end if;
  select source_kind into v_source from public.e10_intake_batches where organization_id=p_org and id=p_batch_id;
  if v_source in ('native','system') and current_setting('role',true)<>'service_role' then
    raise exception using errcode='42501',message='intake_source_provenance_invalid';
  end if;
  delete from public.e10_intake_commit_authorizations where transaction_id=txid_current() and backend_pid=pg_backend_pid();
  perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|observation-lineage-graph',0));
  return public._e10_org_commit_intake_r3(p_org,p_batch_id,p_expected_review_revision,p_idempotency_key);
end $$;

alter function public.e10_org_commit_corrected_intake(uuid,uuid,bigint,jsonb,text)
rename to _e10_org_commit_corrected_intake_r3;
revoke all on function public._e10_org_commit_corrected_intake_r3(uuid,uuid,bigint,jsonb,text) from public,anon,authenticated;
grant execute on function public._e10_org_commit_corrected_intake_r3(uuid,uuid,bigint,jsonb,text) to service_role;
create function public.e10_org_commit_corrected_intake(p_org uuid,p_batch_id uuid,p_expected_review_revision bigint,p_classifications jsonb,p_idempotency_key text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_result jsonb;v_source text;
begin
  select source_kind into v_source from public.e10_intake_batches where organization_id=p_org and id=p_batch_id;
  if v_source in ('native','system') and current_setting('role',true)<>'service_role' then
    raise exception using errcode='42501',message='intake_source_provenance_invalid';
  end if;
  delete from public.e10_intake_commit_authorizations where transaction_id=txid_current() and backend_pid=pg_backend_pid();
  insert into public.e10_intake_commit_authorizations(transaction_id,backend_pid,organization_id,intake_batch_id,source_row_number,predecessor_observation_id)
  select txid_current(),pg_backend_pid(),p_org,p_batch_id,(e->>'source_row_number')::bigint,(e->>'superseded_observation_id')::uuid
  from jsonb_array_elements(coalesce(p_classifications,'[]'::jsonb))e
  where e->>'classification'='replacement' and coalesce(e->>'source_row_number','')~'^[1-9][0-9]*$'
    and coalesce(e->>'superseded_observation_id','')~'^[0-9a-fA-F-]{36}$';
  v_result:=public._e10_org_commit_corrected_intake_r3(p_org,p_batch_id,p_expected_review_revision,p_classifications,p_idempotency_key);
  delete from public.e10_intake_commit_authorizations where transaction_id=txid_current() and backend_pid=pg_backend_pid();
  return v_result;
end $$;

alter function public.e10_org_correct_market_observation(uuid,uuid,text,text,uuid,timestamptz,text,numeric,numeric,text,jsonb,text,text)
rename to _e10_org_correct_market_observation_r3;
revoke all on function public._e10_org_correct_market_observation_r3(uuid,uuid,text,text,uuid,timestamptz,text,numeric,numeric,text,jsonb,text,text) from public,anon,authenticated;
grant execute on function public._e10_org_correct_market_observation_r3(uuid,uuid,text,text,uuid,timestamptz,text,numeric,numeric,text,jsonb,text,text) to service_role;
create function public.e10_org_correct_market_observation(
  p_org uuid,p_observation_id uuid,p_observation_kind text,p_target_type text,p_target_id uuid,
  p_occurred_at timestamptz,p_currency text,p_amount numeric,p_quantity numeric,
  p_source_reference text,p_raw_payload jsonb,p_reason text,p_idempotency_key text
) returns jsonb language plpgsql security definer set search_path=public as $$
begin
  perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|observation-lineage-graph',0));
  return public._e10_org_correct_market_observation_r3(p_org,p_observation_id,p_observation_kind,p_target_type,p_target_id,p_occurred_at,p_currency,p_amount,p_quantity,p_source_reference,p_raw_payload,p_reason,p_idempotency_key);
end $$;

revoke all on function public.e10_org_stage_intake(uuid,text,text,text,text,text,jsonb,text),
  public.e10_org_commit_intake(uuid,uuid,bigint,text),
  public.e10_org_commit_corrected_intake(uuid,uuid,bigint,jsonb,text),
  public.e10_org_correct_market_observation(uuid,uuid,text,text,uuid,timestamptz,text,numeric,numeric,text,jsonb,text,text)
from public,anon;
grant execute on function public.e10_org_stage_intake(uuid,text,text,text,text,text,jsonb,text),
  public.e10_org_commit_intake(uuid,uuid,bigint,text),
  public.e10_org_commit_corrected_intake(uuid,uuid,bigint,jsonb,text),
  public.e10_org_correct_market_observation(uuid,uuid,text,text,uuid,timestamptz,text,numeric,numeric,text,jsonb,text,text)
to authenticated,service_role;
