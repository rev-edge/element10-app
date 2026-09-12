-- TA-X8c dormant, replay-safe database claim/ack contract.
-- Seeds no consumer and creates no worker, scheduler, notification, credential,
-- provider call or external dispatch.

create function e10.x8c_valid_destination_keys(p_keys text[]) returns boolean
language plpgsql immutable set search_path=public as $$
declare v_key text;
begin
  if p_keys is null then return false; end if;
  foreach v_key in array p_keys loop
    if v_key is null or v_key<>btrim(v_key) or octet_length(v_key) not between 1 and 160 then return false; end if;
  end loop;
  return cardinality(p_keys)=(select count(distinct k) from unnest(p_keys) k);
end;
$$;
revoke all on function e10.x8c_valid_destination_keys(text[]) from public,anon,authenticated;
grant execute on function e10.x8c_valid_destination_keys(text[]) to service_role;

create table public.e10_outbox_consumers (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.e10_organizations(id),
  consumer_key text not null check (consumer_key=btrim(consumer_key) and octet_length(consumer_key) between 1 and 160),
  enabled boolean not null default true,
  allowed_destination_keys text[] not null default '{}'::text[] check (e10.x8c_valid_destination_keys(allowed_destination_keys)),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unique (organization_id,id), unique (organization_id,consumer_key)
);

alter table public.e10_integration_outbox
  add column claim_owner_consumer_id uuid,
  add column claim_token uuid,
  add column claim_generation integer not null default 0 check (claim_generation>=0),
  add column claimed_at timestamptz,
  add column claim_expires_at timestamptz,
  add constraint e10_integration_outbox_destination_bytes_ck check (octet_length(destination_key) between 1 and 160) not valid,
  add constraint e10_integration_outbox_claim_shape_ck check (
    (claim_owner_consumer_id is null and claim_token is null and claimed_at is null and claim_expires_at is null)
    or (claim_owner_consumer_id is not null and claim_token is not null and claimed_at is not null
      and claim_expires_at is not null and claim_generation>0 and claim_expires_at>claimed_at)
  ),
  add constraint e10_integration_outbox_claim_owner_fk foreign key (organization_id,claim_owner_consumer_id)
    references public.e10_outbox_consumers(organization_id,id);
alter table public.e10_integration_outbox validate constraint e10_integration_outbox_destination_bytes_ck;

create table public.e10_outbox_claim_commands (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null, consumer_id uuid not null,
  idempotency_key text not null check (btrim(idempotency_key)<>'' and octet_length(idempotency_key)<=200),
  request_fingerprint text not null, result jsonb not null check (jsonb_typeof(result)='object'),
  created_at timestamptz not null default now(),
  unique (organization_id,id), unique (organization_id,consumer_id,idempotency_key),
  foreign key (organization_id,consumer_id) references public.e10_outbox_consumers(organization_id,id)
);

create table public.e10_outbox_acknowledgements (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null, outbox_id uuid not null,
  commercial_event_id uuid not null, destination_key text not null, consumer_id uuid not null,
  claim_generation integer not null check (claim_generation>0), claim_token uuid not null,
  outcome text not null check (outcome in ('delivered','retry','dead')), retry_at timestamptz,
  error_text text check (error_text is null or octet_length(error_text)<=2000), error_digest text not null,
  idempotency_key text not null check (btrim(idempotency_key)<>'' and octet_length(idempotency_key)<=200),
  request_fingerprint text not null, result jsonb not null check (jsonb_typeof(result)='object'),
  recorded_at timestamptz not null default now(),
  unique (organization_id,id), unique (organization_id,consumer_id,idempotency_key),
  unique (organization_id,outbox_id,claim_generation),
  foreign key (organization_id,outbox_id) references public.e10_integration_outbox(organization_id,id),
  foreign key (organization_id,commercial_event_id) references public.e10_commercial_events(organization_id,id),
  foreign key (organization_id,consumer_id) references public.e10_outbox_consumers(organization_id,id)
);

create index e10_outbox_ack_event_idx on public.e10_outbox_acknowledgements(organization_id,commercial_event_id);
create index e10_integration_outbox_claim_owner_idx on public.e10_integration_outbox(organization_id,claim_owner_consumer_id)
  where claim_owner_consumer_id is not null;
create index e10_integration_outbox_claimable_idx on public.e10_integration_outbox(organization_id,destination_key,next_attempt_at,created_at,id)
  where status in ('pending','failed');

alter table public.e10_outbox_consumers enable row level security;
alter table public.e10_outbox_claim_commands enable row level security;
alter table public.e10_outbox_acknowledgements enable row level security;
revoke all on table public.e10_outbox_consumers,public.e10_outbox_claim_commands,public.e10_outbox_acknowledgements from public,anon,authenticated;
grant select,insert,update on table public.e10_outbox_consumers to service_role;
grant select on table public.e10_outbox_claim_commands,public.e10_outbox_acknowledgements to service_role;
create trigger e10_outbox_claim_commands_append_only_trg before update or delete on public.e10_outbox_claim_commands
  for each row execute function e10.reject_append_only_change();
create trigger e10_outbox_acknowledgements_append_only_trg before update or delete on public.e10_outbox_acknowledgements
  for each row execute function e10.reject_append_only_change();

create function e10.x8c_consumer_authorized(p_org uuid,p_consumer uuid,p_destination text default null)
returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.e10_organizations o join public.e10_outbox_consumers c on c.organization_id=o.id
    where o.id=p_org and o.status='active' and c.id=p_consumer and c.enabled
      and (p_destination is null or p_destination=any(c.allowed_destination_keys)))
$$;
revoke all on function e10.x8c_consumer_authorized(uuid,uuid,text) from public,anon,authenticated;
grant execute on function e10.x8c_consumer_authorized(uuid,uuid,text) to service_role;

create function public.e10_claim_outbox(p_org uuid,p_consumer_id uuid,p_limit integer,p_lease_seconds integer,p_idempotency_key text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_fp text; v_existing public.e10_outbox_claim_commands%rowtype; v_row public.e10_integration_outbox%rowtype;
  v_now timestamptz; v_token uuid; v_claim jsonb; v_claims jsonb:='[]'; v_result jsonb; v_authoritative boolean;
begin
  if p_org is null or p_consumer_id is null then raise exception using errcode='22004',message='outbox_claim_scope_required'; end if;
  if p_limit is null or p_limit not between 1 and 100 then raise exception using errcode='22023',message='outbox_claim_limit_out_of_range'; end if;
  if p_lease_seconds is null or p_lease_seconds not between 5 and 300 then raise exception using errcode='22023',message='outbox_claim_lease_out_of_range'; end if;
  if p_idempotency_key is null or btrim(p_idempotency_key)='' or octet_length(p_idempotency_key)>200 then raise exception using errcode='22023',message='outbox_claim_idempotency_key_invalid'; end if;
  if not e10.x8c_consumer_authorized(p_org,p_consumer_id,null) then raise exception using errcode='42501',message='outbox_consumer_denied'; end if;
  v_fp:=encode(extensions.digest(convert_to(jsonb_build_object('v','x8c-claim-v1','org',p_org,'consumer',p_consumer_id,'limit',p_limit,'lease_seconds',p_lease_seconds)::text,'UTF8'),'sha256'),'hex');
  perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|x8c-claim|'||p_consumer_id::text||'|'||p_idempotency_key,0));
  if not e10.x8c_consumer_authorized(p_org,p_consumer_id,null) then raise exception using errcode='42501',message='outbox_consumer_denied'; end if;
  select * into v_existing from public.e10_outbox_claim_commands where organization_id=p_org and consumer_id=p_consumer_id and idempotency_key=p_idempotency_key;
  if found then
    if v_existing.request_fingerprint<>v_fp then raise exception using errcode='22023',message='outbox_claim_idempotency_mismatch'; end if;
    if exists(select 1 from jsonb_array_elements(v_existing.result->'claims') j where not e10.x8c_consumer_authorized(p_org,p_consumer_id,j->>'destination_key')) then
      raise exception using errcode='42501',message='outbox_destination_denied'; end if;
    select jsonb_array_length(v_existing.result->'claims')>0 and not exists(
      select 1 from jsonb_array_elements(v_existing.result->'claims') j left join public.e10_integration_outbox o on o.organization_id=p_org and o.id=(j->>'outbox_id')::uuid
      where o.id is null or o.claim_owner_consumer_id is distinct from p_consumer_id or o.claim_token is distinct from (j->>'claim_token')::uuid
        or o.claim_generation<>(j->>'claim_generation')::integer or o.claim_expires_at<=clock_timestamp()) into v_authoritative;
    return v_existing.result||jsonb_build_object('replay',true,'authoritative',v_authoritative);
  end if;
  for v_row in select o.* from public.e10_integration_outbox o join public.e10_outbox_consumers c on c.organization_id=p_org and c.id=p_consumer_id
    where o.organization_id=p_org and o.status in ('pending','failed') and o.destination_key=any(c.allowed_destination_keys)
      and (o.next_attempt_at is null or o.next_attempt_at<=clock_timestamp()) and (o.claim_token is null or o.claim_expires_at<=clock_timestamp())
    order by coalesce(o.next_attempt_at,o.created_at),o.created_at,o.id for update of o skip locked limit p_limit
  loop
    v_now:=clock_timestamp();
    if not e10.x8c_consumer_authorized(p_org,p_consumer_id,v_row.destination_key) then raise exception using errcode='42501',message='outbox_destination_denied'; end if;
    if v_row.status not in ('pending','failed') or (v_row.next_attempt_at is not null and v_row.next_attempt_at>v_now)
       or (v_row.claim_token is not null and v_row.claim_expires_at>v_now) then continue; end if;
    if v_row.attempt_count=2147483647 or v_row.claim_generation=2147483647 then raise exception using errcode='22003',message='outbox_claim_counter_overflow'; end if;
    v_token:=gen_random_uuid();
    update public.e10_integration_outbox set claim_owner_consumer_id=p_consumer_id,claim_token=v_token,claim_generation=v_row.claim_generation+1,
      claimed_at=v_now,claim_expires_at=v_now+make_interval(secs=>p_lease_seconds),attempt_count=v_row.attempt_count+1,status='pending',updated_at=v_now
    where organization_id=p_org and id=v_row.id returning jsonb_build_object('outbox_id',id,'commercial_event_id',commercial_event_id,
      'destination_key',destination_key,'payload',payload,'claim_token',claim_token,'claim_generation',claim_generation,'lease_expires_at',claim_expires_at) into v_claim;
    v_claims:=v_claims||jsonb_build_array(v_claim);
  end loop;
  v_result:=jsonb_build_object('ok',true,'claims',v_claims,'count',jsonb_array_length(v_claims));
  insert into public.e10_outbox_claim_commands(organization_id,consumer_id,idempotency_key,request_fingerprint,result) values(p_org,p_consumer_id,p_idempotency_key,v_fp,v_result);
  return v_result||jsonb_build_object('replay',false,'authoritative',jsonb_array_length(v_claims)>0);
end; $$;

create function public.e10_ack_outbox(p_org uuid,p_consumer_id uuid,p_outbox_id uuid,p_claim_token uuid,p_claim_generation integer,
  p_outcome text,p_retry_after_seconds integer,p_error text,p_idempotency_key text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_fp text; v_error_digest text; v_existing public.e10_outbox_acknowledgements%rowtype;
  v_outbox public.e10_integration_outbox%rowtype; v_now timestamptz; v_retry_at timestamptz; v_result jsonb;
begin
  if p_org is null or p_consumer_id is null or p_outbox_id is null or p_claim_token is null or p_claim_generation is null then raise exception using errcode='22004',message='outbox_ack_scope_required'; end if;
  if p_outcome not in ('delivered','retry','dead') then raise exception using errcode='22023',message='outbox_ack_outcome_invalid'; end if;
  if p_error is not null and octet_length(p_error)>2000 then raise exception using errcode='22023',message='outbox_ack_error_too_long'; end if;
  if (p_outcome='delivered' and (p_retry_after_seconds is not null or p_error is not null))
     or (p_outcome='retry' and (p_retry_after_seconds is null or p_retry_after_seconds not between 5 and 86400 or p_error is null or btrim(p_error)=''))
     or (p_outcome='dead' and (p_retry_after_seconds is not null or p_error is null or btrim(p_error)='')) then
    raise exception using errcode='22023',message='outbox_ack_outcome_fields_invalid'; end if;
  if p_idempotency_key is null or btrim(p_idempotency_key)='' or octet_length(p_idempotency_key)>200 then raise exception using errcode='22023',message='outbox_ack_idempotency_key_invalid'; end if;
  if not e10.x8c_consumer_authorized(p_org,p_consumer_id,null) then raise exception using errcode='42501',message='outbox_consumer_denied'; end if;
  v_error_digest:=encode(extensions.digest(convert_to(coalesce(p_error,''),'UTF8'),'sha256'),'hex');
  v_fp:=encode(extensions.digest(convert_to(jsonb_build_object('v','x8c-ack-v1','org',p_org,'consumer',p_consumer_id,'outbox',p_outbox_id,'token',p_claim_token,
    'generation',p_claim_generation,'outcome',p_outcome,'retry_seconds',p_retry_after_seconds,'error_digest',v_error_digest)::text,'UTF8'),'sha256'),'hex');
  perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|x8c-ack|'||p_consumer_id::text||'|'||p_idempotency_key,0));
  if not e10.x8c_consumer_authorized(p_org,p_consumer_id,null) then raise exception using errcode='42501',message='outbox_consumer_denied'; end if;
  select * into v_existing from public.e10_outbox_acknowledgements where organization_id=p_org and consumer_id=p_consumer_id and idempotency_key=p_idempotency_key;
  if found then
    if v_existing.request_fingerprint<>v_fp then raise exception using errcode='22023',message='outbox_ack_idempotency_mismatch'; end if;
    if not e10.x8c_consumer_authorized(p_org,p_consumer_id,v_existing.destination_key) then raise exception using errcode='42501',message='outbox_destination_denied'; end if;
    return v_existing.result||jsonb_build_object('replay',true);
  end if;
  select * into v_outbox from public.e10_integration_outbox where organization_id=p_org and id=p_outbox_id for update;
  if not found then raise exception using errcode='42501',message='outbox_ack_denied'; end if;
  v_now:=clock_timestamp();
  if not e10.x8c_consumer_authorized(p_org,p_consumer_id,v_outbox.destination_key) then raise exception using errcode='42501',message='outbox_destination_denied'; end if;
  if v_outbox.claim_owner_consumer_id is distinct from p_consumer_id or v_outbox.claim_token is distinct from p_claim_token
     or v_outbox.claim_generation<>p_claim_generation then raise exception using errcode='42501',message='outbox_claim_not_owned'; end if;
  if v_outbox.claim_expires_at<=v_now then raise exception using errcode='40001',message='outbox_claim_expired'; end if;
  v_retry_at:=case when p_outcome='retry' then v_now+make_interval(secs=>p_retry_after_seconds) end;
  update public.e10_integration_outbox set status=case p_outcome when 'delivered' then 'delivered' when 'retry' then 'failed' else 'dead' end,
    delivered_at=case when p_outcome='delivered' then v_now end,next_attempt_at=v_retry_at,last_error=case when p_outcome='delivered' then null else p_error end,
    claim_owner_consumer_id=null,claim_token=null,claimed_at=null,claim_expires_at=null,updated_at=v_now where organization_id=p_org and id=p_outbox_id;
  v_result:=jsonb_build_object('ok',true,'outbox_id',p_outbox_id,'commercial_event_id',v_outbox.commercial_event_id,
    'destination_key',v_outbox.destination_key,'claim_generation',p_claim_generation,'outcome',p_outcome,'retry_at',v_retry_at,'recorded_at',v_now);
  insert into public.e10_outbox_acknowledgements(organization_id,outbox_id,commercial_event_id,destination_key,consumer_id,claim_generation,claim_token,
    outcome,retry_at,error_text,error_digest,idempotency_key,request_fingerprint,result,recorded_at)
  values(p_org,p_outbox_id,v_outbox.commercial_event_id,v_outbox.destination_key,p_consumer_id,p_claim_generation,p_claim_token,
    p_outcome,v_retry_at,p_error,v_error_digest,p_idempotency_key,v_fp,v_result,v_now);
  return v_result||jsonb_build_object('replay',false);
end; $$;

revoke all on function public.e10_claim_outbox(uuid,uuid,integer,integer,text) from public,anon,authenticated;
revoke all on function public.e10_ack_outbox(uuid,uuid,uuid,uuid,integer,text,integer,text,text) from public,anon,authenticated;
grant execute on function public.e10_claim_outbox(uuid,uuid,integer,integer,text) to service_role;
grant execute on function public.e10_ack_outbox(uuid,uuid,uuid,uuid,integer,text,integer,text,text) to service_role;
comment on table public.e10_outbox_consumers is 'Dormant service-managed org consumer allowlist. No row is seeded by TA-X8c.';
comment on table public.e10_outbox_claim_commands is 'Immutable idempotency receipts for bounded dormant outbox claims.';
comment on table public.e10_outbox_acknowledgements is 'Immutable database-protocol acknowledgements, not proof of provider delivery.';
comment on function public.e10_claim_outbox(uuid,uuid,integer,integer,text) is 'Claims at most 100 due rows for 5-300 seconds; performs no external delivery.';
comment on function public.e10_ack_outbox(uuid,uuid,uuid,uuid,integer,text,integer,text,text) is 'Records delivered, retry or dead for one current lease; performs no external delivery.';
