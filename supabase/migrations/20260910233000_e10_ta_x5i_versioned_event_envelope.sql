-- TA-X5i versioned commercial-event envelope. This records operational evidence only.

create table public.e10_commercial_event_schemas (
  event_type text not null,
  schema_version integer not null check(schema_version>0),
  required_payload_keys text[] not null default '{}',
  description text not null check(btrim(description)<>''),
  primary key(event_type,schema_version),
  check(array_position(required_payload_keys,null) is null)
);

insert into public.e10_commercial_event_schemas(event_type,schema_version,required_payload_keys,description) values
 ('acquisition',1,array['acquisition_id'],'Acquisition evidence, not accounting recognition.'),
 ('receipt',1,array['receipt_id'],'Physical receipt evidence.'),
 ('available_for_sale',1,array['availability_state'],'Availability transition.'),
 ('listing_created',1,array['listing_id','channel'],'Listing identity and channel.'),
 ('listing_published',1,array['listing_id','channel'],'Published listing identity and channel.'),
 ('listing_paused',1,array['listing_id','channel'],'Paused listing identity and channel.'),
 ('listing_resumed',1,array['listing_id','channel'],'Resumed listing identity and channel.'),
 ('listing_ended',1,array['listing_id','channel'],'Ended listing identity and channel.'),
 ('listing_relisted',1,array['listing_id','channel'],'Relisted listing identity and channel.'),
 ('asking_price_changed',1,array['listing_id','channel','currency','amount'],'Observed asking-price change.'),
 ('hold',1,array['hold_id'],'Inventory hold evidence.'),
 ('release',1,array['hold_id'],'Inventory hold release evidence.'),
 ('sale_committed',1,array['sale_id'],'Operational sale commitment, not official posted spend.'),
 ('fulfillment',1,array['fulfillment_id'],'Fulfillment evidence.'),
 ('fee',1,array['fee_id','currency','amount'],'Fee evidence, not accounting posting.'),
 ('payout',1,array['payout_id','currency','amount'],'Payout evidence, not settlement assertion.'),
 ('refund',1,array['refund_id','currency','amount'],'Refund evidence, not official posted adjustment.'),
 ('return',1,array['return_id'],'Return evidence.'),
 ('cost_correction',1,array['cost_adjustment_id','currency','amount'],'Cost correction evidence.'),
 ('correction',1,array['reason'],'Generic correction evidence.');

alter table public.e10_commercial_event_schemas enable row level security;
revoke all on public.e10_commercial_event_schemas from public,anon,authenticated;
grant select on public.e10_commercial_event_schemas to service_role;

alter table public.e10_commercial_events
  add column event_schema_version integer not null default 1,
  add column occurred_at_precision text not null default 'exact' check(occurred_at_precision in ('exact','date','unknown')),
  add column source_connection_id text,
  add column source_event_id text,
  add column correlation_id text,
  add column causation_event_id uuid,
  add column evidence_quality text not null default 'operator_asserted'
    check(evidence_quality in ('operator_asserted','native_system','imported_unreviewed','reviewed_import'));
alter table public.e10_commercial_events alter column occurred_at drop not null;
alter table public.e10_commercial_events add constraint e10_commercial_events_occurrence_precision_chk check(
  (occurred_at_precision='unknown' and occurred_at is null) or (occurred_at_precision in ('exact','date') and occurred_at is not null));
alter table public.e10_commercial_events add constraint e10_commercial_events_finite_occurrence_chk
  check(occurred_at is null or isfinite(occurred_at));
alter table public.e10_commercial_events add constraint e10_commercial_events_schema_fkey
  foreign key(event_type,event_schema_version) references public.e10_commercial_event_schemas(event_type,schema_version);
alter table public.e10_commercial_events add constraint e10_commercial_events_org_causation_fkey
  foreign key(organization_id,causation_event_id) references public.e10_commercial_events(organization_id,id);
update public.e10_commercial_events set evidence_quality='native_system',source_connection_id='inventory-ledger',
  source_event_id=inventory_movement_id::text,correlation_id=coalesce(source_reference,inventory_movement_id::text)
where source_kind='native' and inventory_movement_id is not null;

create function e10.valid_commercial_event_payload(p_event_type text,p_payload jsonb) returns boolean
language plpgsql immutable set search_path=pg_catalog as $$
declare k text; required_text_keys text[]; amount_value numeric;
begin
  if p_payload is null or jsonb_typeof(p_payload) is distinct from 'object' then return false; end if;
  required_text_keys:=case p_event_type
    when 'acquisition' then array['acquisition_id'] when 'receipt' then array['receipt_id']
    when 'available_for_sale' then array['availability_state']
    when 'listing_created' then array['listing_id','channel'] when 'listing_published' then array['listing_id','channel']
    when 'listing_paused' then array['listing_id','channel'] when 'listing_resumed' then array['listing_id','channel']
    when 'listing_ended' then array['listing_id','channel'] when 'listing_relisted' then array['listing_id','channel']
    when 'asking_price_changed' then array['listing_id','channel','currency']
    when 'hold' then array['hold_id'] when 'release' then array['hold_id'] when 'sale_committed' then array['sale_id']
    when 'fulfillment' then array['fulfillment_id'] when 'fee' then array['fee_id','currency']
    when 'payout' then array['payout_id','currency'] when 'refund' then array['refund_id','currency']
    when 'return' then array['return_id'] when 'cost_correction' then array['cost_adjustment_id','currency']
    when 'correction' then array['reason'] else null end;
  if required_text_keys is null then return false; end if;
  foreach k in array required_text_keys loop
    if jsonb_typeof(p_payload->k) is distinct from 'string' or coalesce(btrim(p_payload->>k),'')='' then return false; end if;
  end loop;
  if p_event_type in ('asking_price_changed','fee','payout','refund','cost_correction') then
    if jsonb_typeof(p_payload->'amount') is distinct from 'number' or coalesce(p_payload->>'currency','')!~'^[A-Z]{3}$' then return false; end if;
    amount_value:=(p_payload->>'amount')::numeric;
    if amount_value<0 or amount_value::text in ('NaN','Infinity','-Infinity') then return false; end if;
  end if;
  return true;
exception when others then return false;
end $$;
revoke all on function e10.valid_commercial_event_payload(text,jsonb) from public,anon,authenticated;
grant execute on function e10.valid_commercial_event_payload(text,jsonb) to service_role;

create function e10.normalize_commercial_event_envelope() returns trigger language plpgsql security definer set search_path=public as $$
begin
  if new.source_kind='native' then
    if new.inventory_movement_id is null then raise exception using errcode='42501',message='native_evidence_requires_inventory_movement'; end if;
    new.evidence_quality:='native_system';
    new.source_connection_id:=coalesce(nullif(btrim(new.source_connection_id),''),'inventory-ledger');
    new.source_event_id:=coalesce(nullif(btrim(new.source_event_id),''),new.inventory_movement_id::text);
    new.correlation_id:=coalesce(nullif(btrim(new.correlation_id),''),nullif(btrim(new.source_reference),''),new.inventory_movement_id::text);
  elsif new.source_kind='system' then
    raise exception using errcode='42501',message='system_evidence_requires_trusted_writer';
  elsif new.source_kind='import' and new.evidence_quality='operator_asserted' then
    new.evidence_quality:='imported_unreviewed';
  end if;
  if new.source_kind<>'native' and not e10.valid_commercial_event_payload(new.event_type,new.payload) then
    raise exception using errcode='22023',message='event_payload_invalid_for_schema';
  end if;
  return new;
end $$;
revoke all on function e10.normalize_commercial_event_envelope() from public,anon,authenticated;
grant execute on function e10.normalize_commercial_event_envelope() to service_role;
create trigger e10_commercial_event_envelope_trg before insert on public.e10_commercial_events
  for each row execute function e10.normalize_commercial_event_envelope();

create unique index e10_commercial_events_source_event_uq
  on public.e10_commercial_events(organization_id,source_kind,coalesce(source_connection_id,''),source_event_id)
  where source_event_id is not null;
create index e10_commercial_events_correlation_idx
  on public.e10_commercial_events(organization_id,correlation_id,occurred_at,id)
  where correlation_id is not null;

create function public.e10_org_record_commercial_event_v2(
  p_org uuid,p_event_type text,p_event_schema_version integer,p_subject_type text,p_subject_id text,
  p_occurred_at timestamptz,p_occurred_at_precision text,p_source_kind text,p_source_connection_id text,
  p_source_reference text,p_source_event_id text,p_correlation_id text,p_causation_event_id uuid,
  p_evidence_quality text,p_payload jsonb,p_corrects_event_id uuid,p_outbox_destinations text[],p_idempotency_key text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_fp text; v_existing record; v_schema record; v_event uuid; v_destination text;
begin
  if not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.record_commercial_events') then raise exception using errcode='42501',message='record_commercial_event_denied'; end if;
  if p_idempotency_key is null or btrim(p_idempotency_key)='' then raise exception using errcode='22004',message='idempotency_key_required'; end if;
  if p_payload is null or jsonb_typeof(p_payload)<>'object' or octet_length(p_payload::text)>262144 then raise exception using errcode='22023',message='event_payload_invalid'; end if;
  if p_occurred_at_precision not in ('exact','date','unknown') or ((p_occurred_at_precision='unknown')<>(p_occurred_at is null)) or (p_occurred_at is not null and not isfinite(p_occurred_at)) then raise exception using errcode='22023',message='event_occurrence_precision_invalid'; end if;
  if p_evidence_quality not in ('operator_asserted','native_system','imported_unreviewed','reviewed_import') then raise exception using errcode='22023',message='event_evidence_quality_invalid'; end if;
  if p_source_kind not in ('manual','import') or (p_source_kind='manual' and p_evidence_quality<>'operator_asserted') or (p_source_kind='import' and p_evidence_quality not in ('imported_unreviewed','reviewed_import')) then raise exception using errcode='42501',message='event_source_provenance_invalid'; end if;
  if coalesce(array_length(p_outbox_destinations,1),0)>20 then raise exception using errcode='22023',message='outbox_destination_limit_exceeded'; end if;
  if (select count(*) from unnest(coalesce(p_outbox_destinations,'{}'::text[])) d)<>(select count(distinct d) from unnest(coalesce(p_outbox_destinations,'{}'::text[])) d) then raise exception using errcode='22023',message='duplicate_outbox_destination'; end if;
  select * into v_schema from public.e10_commercial_event_schemas where event_type=p_event_type and schema_version=p_event_schema_version;
  if not found then raise exception using errcode='22023',message='event_schema_unknown'; end if;
  if not p_payload ?& v_schema.required_payload_keys then raise exception using errcode='22023',message='event_payload_missing_required_keys'; end if;
  if not e10.valid_commercial_event_payload(p_event_type,p_payload) then raise exception using errcode='22023',message='event_payload_invalid_for_schema'; end if;
  if p_subject_type='inventory_item' then perform 1 from public.e10_inventory_items where organization_id=p_org and id=p_subject_id;
  elsif p_subject_type='unique_item' then perform 1 from public.e10_unique_items where organization_id=p_org and id=p_subject_id::uuid;
  elsif p_subject_type='lot' then perform 1 from public.e10_inventory_lots where organization_id=p_org and id=p_subject_id::uuid;
  elsif p_subject_type='receipt' then perform 1 from public.e10_stock_receipts where organization_id=p_org and id=p_subject_id::uuid;
  else raise exception using errcode='22023',message='subject_type_not_yet_supported'; end if;
  if not found then raise exception using errcode='42501',message='commercial_event_subject_denied'; end if;
  if p_causation_event_id is not null and not exists(select 1 from public.e10_commercial_events where organization_id=p_org and id=p_causation_event_id) then raise exception using errcode='42501',message='causation_event_denied'; end if;
  v_fp:=md5(jsonb_build_object('v','event-v2','type',p_event_type,'schema',p_event_schema_version,'subject_type',p_subject_type,'subject_id',p_subject_id,'occurred_epoch',extract(epoch from p_occurred_at)::numeric,'precision',p_occurred_at_precision,'source_kind',p_source_kind,'connection',p_source_connection_id,'reference',p_source_reference,'source_event_id',p_source_event_id,'correlation',p_correlation_id,'causation',p_causation_event_id,'quality',p_evidence_quality,'payload',p_payload,'corrects',p_corrects_event_id,'destinations',p_outbox_destinations)::text);
  perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|commercial-event-v2|'||p_idempotency_key,0));
  select id,request_fingerprint,event_type into v_existing from public.e10_commercial_events where organization_id=p_org and idempotency_key=p_idempotency_key;
  if found then
    if v_existing.request_fingerprint is distinct from v_fp then raise exception using errcode='22023',message='idempotency_key_mismatch'; end if;
    return jsonb_build_object('ok',true,'replay',true,'event_id',v_existing.id,'event_type',v_existing.event_type);
  end if;
  insert into public.e10_commercial_events(organization_id,event_type,event_schema_version,subject_type,subject_id,occurred_at,occurred_at_precision,idempotency_key,source_kind,source_connection_id,source_reference,source_event_id,correlation_id,causation_event_id,evidence_quality,payload,corrects_event_id,created_by,request_fingerprint)
  values(p_org,p_event_type,p_event_schema_version,p_subject_type,p_subject_id,p_occurred_at,p_occurred_at_precision,p_idempotency_key,p_source_kind,p_source_connection_id,p_source_reference,nullif(btrim(p_source_event_id),''),nullif(btrim(p_correlation_id),''),p_causation_event_id,p_evidence_quality,p_payload,p_corrects_event_id,auth.uid(),v_fp) returning id into v_event;
  foreach v_destination in array coalesce(p_outbox_destinations,'{}'::text[]) loop
    if v_destination is null or btrim(v_destination)='' then raise exception using errcode='22023',message='outbox_destination_required'; end if;
    insert into public.e10_integration_outbox(organization_id,commercial_event_id,destination_key,payload) values(p_org,v_event,v_destination,jsonb_build_object('event_id',v_event,'event_type',p_event_type,'event_schema_version',p_event_schema_version,'subject_type',p_subject_type,'subject_id',p_subject_id));
  end loop;
  return jsonb_build_object('ok',true,'replay',false,'event_id',v_event,'event_type',p_event_type,'event_schema_version',p_event_schema_version,'outbox_count',coalesce(array_length(p_outbox_destinations,1),0));
exception when unique_violation then
  if p_source_event_id is not null and exists(select 1 from public.e10_commercial_events where organization_id=p_org and source_kind=p_source_kind and coalesce(source_connection_id,'')=coalesce(p_source_connection_id,'') and source_event_id=p_source_event_id) then raise exception using errcode='23505',message='source_event_already_recorded'; end if;
  raise;
end $$;

revoke all on function public.e10_org_record_commercial_event_v2(uuid,text,integer,text,text,timestamptz,text,text,text,text,text,text,uuid,text,jsonb,uuid,text[],text) from public,anon;
grant execute on function public.e10_org_record_commercial_event_v2(uuid,text,integer,text,text,timestamptz,text,text,text,text,text,text,uuid,text,jsonb,uuid,text[],text) to authenticated,service_role;

comment on function public.e10_org_record_commercial_event_v2(uuid,text,integer,text,text,timestamptz,text,text,text,text,text,text,uuid,text,jsonb,uuid,text[],text) is
  'Records versioned operational evidence. It does not post customer spend, accounting recognition, payment, payout settlement, or inventory state.';
