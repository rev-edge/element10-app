-- TA-X5b bounded idempotent intake/resolution/lifecycle writers.
-- New capabilities are configurable and intentionally receive no automatic role grants.

alter table public.e10_intake_resolver_decisions add column idempotency_key text;
alter table public.e10_intake_resolver_decisions add column request_fingerprint text;
alter table public.e10_intake_resolver_decisions add constraint e10_resolver_idempotency_chk
  check(idempotency_key is null or btrim(idempotency_key)<>'');
alter table public.e10_intake_resolver_decisions add constraint e10_resolver_fingerprint_chk
  check((idempotency_key is null)=(request_fingerprint is null));
create unique index e10_resolver_org_idempotency_uq
  on public.e10_intake_resolver_decisions(organization_id,idempotency_key) where idempotency_key is not null;

alter table public.e10_commercial_events add column request_fingerprint text;
alter table public.e10_commercial_events add constraint e10_commercial_events_fingerprint_chk
  check(request_fingerprint is null or btrim(request_fingerprint)<>'');

create or replace function e10.try_timestamptz(p_value text) returns timestamptz
language plpgsql immutable set search_path=pg_catalog as $$
begin return nullif(btrim(p_value),'')::timestamptz; exception when others then return null; end;
$$;
create or replace function e10.try_numeric(p_value text) returns numeric
language plpgsql immutable set search_path=pg_catalog as $$
begin return nullif(btrim(p_value),'')::numeric; exception when others then return null; end;
$$;
revoke all on function e10.try_timestamptz(text),e10.try_numeric(text) from public,anon,authenticated;
grant execute on function e10.try_timestamptz(text),e10.try_numeric(text) to service_role;

create or replace function public.e10_org_stage_intake(
  p_org uuid, p_source_kind text, p_source_connection_id text, p_source_reference text,
  p_original_file_reference text, p_payload_fingerprint text, p_rows jsonb, p_idempotency_key text
) returns jsonb
language plpgsql security definer set search_path=public as $$
declare v_fp text; v_existing record; v_batch uuid; v_count integer; v_errors integer;
begin
  if not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.manage_intake') then
    raise exception using errcode='42501',message='manage_intake_denied';
  end if;
  if p_idempotency_key is null or btrim(p_idempotency_key)='' then raise exception using errcode='22004',message='idempotency_key_required'; end if;
  if p_payload_fingerprint is null or btrim(p_payload_fingerprint)='' then raise exception using errcode='22004',message='payload_fingerprint_required'; end if;
  if p_rows is null or jsonb_typeof(p_rows)<>'array' then raise exception using errcode='22023',message='rows_must_be_array'; end if;
  if octet_length(p_rows::text)>5000000 then raise exception using errcode='22023',message='rows_payload_exceeds_5mb'; end if;
  v_count:=jsonb_array_length(p_rows);
  if v_count<1 or v_count>1000 then raise exception using errcode='22023',message='row_count_must_be_between_1_and_1000'; end if;
  v_fp:=md5(coalesce(p_source_kind,'')||'|'||coalesce(p_source_connection_id,'')||'|'||coalesce(p_source_reference,'')||'|'||
    coalesce(p_original_file_reference,'')||'|'||p_payload_fingerprint||'|'||p_rows::text);
  perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|intake|'||p_idempotency_key,0));
  select id,request_fingerprint,status into v_existing from public.e10_intake_batches
    where organization_id=p_org and idempotency_key=p_idempotency_key;
  if found then
    if v_existing.request_fingerprint is distinct from v_fp then raise exception using errcode='22023',message='idempotency_key_mismatch'; end if;
    return jsonb_build_object('ok',true,'replay',true,'batch_id',v_existing.id,'status',v_existing.status,
      'row_count',(select count(*) from public.e10_intake_rows where organization_id=p_org and batch_id=v_existing.id));
  end if;
  insert into public.e10_intake_batches(organization_id,source_kind,source_connection_id,source_reference,
    original_file_reference,payload_fingerprint,status,created_by,idempotency_key,request_fingerprint)
  values(p_org,p_source_kind,p_source_connection_id,p_source_reference,p_original_file_reference,p_payload_fingerprint,
    'staged',auth.uid(),p_idempotency_key,v_fp) returning id into v_batch;
  insert into public.e10_intake_rows(organization_id,batch_id,source_row_number,raw_payload,observation_kind,
    occurred_at,currency,amount,quantity,validation_errors)
  select p_org,v_batch,ord,
    elem->'raw_payload',elem->>'observation_kind',e10.try_timestamptz(elem->>'occurred_at'),
    case when elem->>'currency' ~ '^[A-Z]{3}$' then elem->>'currency' end,
    e10.try_numeric(elem->>'amount'),e10.try_numeric(elem->>'quantity'),
    (case when elem->>'observation_kind' is null then '["observation_kind_required"]'::jsonb else '[]'::jsonb end)
      || (case when e10.try_timestamptz(elem->>'occurred_at') is null then '["occurred_at_invalid_or_required"]'::jsonb else '[]'::jsonb end)
      || (case when elem->>'observation_kind' in ('acquisition_cost','asking_price','completed_sale','estimated_value')
                    and e10.try_numeric(elem->>'amount') is null then '["amount_invalid_or_required"]'::jsonb else '[]'::jsonb end)
      || (case when elem->>'observation_kind' in ('acquisition_cost','asking_price','completed_sale','estimated_value')
                    and coalesce(elem->>'currency','') !~ '^[A-Z]{3}$' then '["currency_invalid_or_required"]'::jsonb else '[]'::jsonb end)
      || (case when elem ? 'quantity' and e10.try_numeric(elem->>'quantity') is null then '["quantity_invalid"]'::jsonb else '[]'::jsonb end)
  from jsonb_array_elements(p_rows) with ordinality r(elem,ord)
  where jsonb_typeof(elem->'raw_payload')='object';
  if (select count(*) from public.e10_intake_rows where organization_id=p_org and batch_id=v_batch)<>v_count then
    raise exception using errcode='22023',message='each_row_requires_raw_payload_object';
  end if;
  select count(*) into v_errors from public.e10_intake_rows
    where organization_id=p_org and batch_id=v_batch and jsonb_array_length(validation_errors)>0;
  update public.e10_intake_batches set status=case when v_errors=0 then 'validated' else 'staged' end,updated_at=now()
    where organization_id=p_org and id=v_batch returning status into v_existing.status;
  return jsonb_build_object('ok',true,'replay',false,'batch_id',v_batch,'status',v_existing.status,'row_count',v_count,'invalid_row_count',v_errors);
end;
$$;

create or replace function public.e10_org_resolve_intake_row(
  p_org uuid, p_intake_row_id uuid, p_decision text, p_target_id uuid,
  p_reason text, p_corrects_decision_id uuid, p_idempotency_key text
) returns jsonb
language plpgsql security definer set search_path=public as $$
declare v_fp text; v_existing record; v_decision uuid; v_product uuid; v_config uuid; v_unique uuid; v_match text;
begin
  if not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.manage_intake') then
    raise exception using errcode='42501',message='manage_intake_denied';
  end if;
  if p_idempotency_key is null or btrim(p_idempotency_key)='' then raise exception using errcode='22004',message='idempotency_key_required'; end if;
  if p_reason is null or btrim(p_reason)='' then raise exception using errcode='22004',message='resolution_reason_required'; end if;
  if p_decision not in ('match_product','match_configuration','match_unique_item','reject','clear_match') then
    raise exception using errcode='22023',message='invalid_resolution_decision';
  end if;
  if (p_decision like 'match_%')<>(p_target_id is not null) then raise exception using errcode='22023',message='resolution_target_mismatch'; end if;
  v_fp:=md5(p_intake_row_id::text||'|'||p_decision||'|'||coalesce(p_target_id::text,'')||'|'||p_reason||'|'||coalesce(p_corrects_decision_id::text,''));
  perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|resolve|'||p_idempotency_key,0));
  select id,request_fingerprint,decision into v_existing from public.e10_intake_resolver_decisions
    where organization_id=p_org and idempotency_key=p_idempotency_key;
  if found then
    if v_existing.request_fingerprint is distinct from v_fp then raise exception using errcode='22023',message='idempotency_key_mismatch'; end if;
    return jsonb_build_object('ok',true,'replay',true,'decision_id',v_existing.id,'decision',v_existing.decision);
  end if;
  perform 1 from public.e10_intake_rows where organization_id=p_org and id=p_intake_row_id for update;
  if not found then raise exception using errcode='42501',message='intake_row_access_denied'; end if;
  if p_decision='match_product' then
    perform 1 from public.e10_product_masters where organization_id=p_org and id=p_target_id;
    if not found then raise exception using errcode='42501',message='resolution_target_denied'; end if; v_product:=p_target_id; v_match:='matched';
  elsif p_decision='match_configuration' then
    perform 1 from public.e10_product_configuration_versions where organization_id=p_org and id=p_target_id;
    if not found then raise exception using errcode='42501',message='resolution_target_denied'; end if; v_config:=p_target_id; v_match:='matched';
  elsif p_decision='match_unique_item' then
    perform 1 from public.e10_unique_items where organization_id=p_org and id=p_target_id;
    if not found then raise exception using errcode='42501',message='resolution_target_denied'; end if; v_unique:=p_target_id; v_match:='matched';
  elsif p_decision='reject' then v_match:='rejected'; else v_match:='unresolved'; end if;
  insert into public.e10_intake_resolver_decisions(organization_id,intake_row_id,decision,product_master_id,
    configuration_version_id,unique_item_id,reason,corrects_decision_id,decided_by,idempotency_key,request_fingerprint)
  values(p_org,p_intake_row_id,p_decision,v_product,v_config,v_unique,p_reason,p_corrects_decision_id,auth.uid(),p_idempotency_key,v_fp)
  returning id into v_decision;
  update public.e10_intake_rows set match_status=v_match,product_master_id=v_product,configuration_version_id=v_config,unique_item_id=v_unique
    where organization_id=p_org and id=p_intake_row_id;
  return jsonb_build_object('ok',true,'replay',false,'decision_id',v_decision,'decision',p_decision,'match_status',v_match);
end;
$$;

create or replace function public.e10_org_record_commercial_event(
  p_org uuid, p_event_type text, p_subject_type text, p_subject_id text, p_occurred_at timestamptz,
  p_source_kind text, p_source_reference text, p_payload jsonb, p_corrects_event_id uuid,
  p_outbox_destinations text[], p_idempotency_key text
) returns jsonb
language plpgsql security definer set search_path=public as $$
declare v_fp text; v_existing record; v_event uuid; v_destination text;
begin
  if not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.record_commercial_events') then
    raise exception using errcode='42501',message='record_commercial_event_denied';
  end if;
  if p_idempotency_key is null or btrim(p_idempotency_key)='' then raise exception using errcode='22004',message='idempotency_key_required'; end if;
  if p_payload is null or jsonb_typeof(p_payload)<>'object' then raise exception using errcode='22023',message='payload_must_be_object'; end if;
  if octet_length(p_payload::text)>262144 then raise exception using errcode='22023',message='event_payload_exceeds_256kb'; end if;
  if coalesce(array_length(p_outbox_destinations,1),0)>20 then raise exception using errcode='22023',message='outbox_destination_limit_exceeded'; end if;
  if (select count(*) from unnest(coalesce(p_outbox_destinations,'{}'::text[])) d) <>
     (select count(distinct d) from unnest(coalesce(p_outbox_destinations,'{}'::text[])) d) then
    raise exception using errcode='22023',message='duplicate_outbox_destination';
  end if;
  if p_subject_type='inventory_item' then perform 1 from public.e10_inventory_items where organization_id=p_org and id=p_subject_id;
  elsif p_subject_type='unique_item' then perform 1 from public.e10_unique_items where organization_id=p_org and id=p_subject_id::uuid;
  elsif p_subject_type='lot' then perform 1 from public.e10_inventory_lots where organization_id=p_org and id=p_subject_id::uuid;
  elsif p_subject_type='receipt' then perform 1 from public.e10_stock_receipts where organization_id=p_org and id=p_subject_id::uuid;
  else raise exception using errcode='22023',message='subject_type_not_yet_supported'; end if;
  if not found then raise exception using errcode='42501',message='commercial_event_subject_denied'; end if;
  v_fp:=md5(p_event_type||'|'||p_subject_type||'|'||p_subject_id||'|'||p_occurred_at::text||'|'||p_source_kind||'|'||
    coalesce(p_source_reference,'')||'|'||p_payload::text||'|'||coalesce(p_corrects_event_id::text,'')||'|'||coalesce(p_outbox_destinations,'{}')::text);
  perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|commercial-event|'||p_idempotency_key,0));
  select id,request_fingerprint,event_type into v_existing from public.e10_commercial_events
    where organization_id=p_org and idempotency_key=p_idempotency_key;
  if found then
    if v_existing.request_fingerprint is distinct from v_fp then raise exception using errcode='22023',message='idempotency_key_mismatch'; end if;
    return jsonb_build_object('ok',true,'replay',true,'event_id',v_existing.id,'event_type',v_existing.event_type);
  end if;
  insert into public.e10_commercial_events(organization_id,event_type,subject_type,subject_id,occurred_at,idempotency_key,
    source_kind,source_reference,payload,corrects_event_id,created_by,request_fingerprint)
  values(p_org,p_event_type,p_subject_type,p_subject_id,p_occurred_at,p_idempotency_key,p_source_kind,p_source_reference,
    p_payload,p_corrects_event_id,auth.uid(),v_fp) returning id into v_event;
  foreach v_destination in array coalesce(p_outbox_destinations,'{}'::text[]) loop
    if v_destination is null or btrim(v_destination)='' then raise exception using errcode='22023',message='outbox_destination_required'; end if;
    insert into public.e10_integration_outbox(organization_id,commercial_event_id,destination_key,payload)
      values(p_org,v_event,v_destination,jsonb_build_object('event_id',v_event,'event_type',p_event_type,'subject_type',p_subject_type,'subject_id',p_subject_id));
  end loop;
  return jsonb_build_object('ok',true,'replay',false,'event_id',v_event,'event_type',p_event_type,'outbox_count',coalesce(array_length(p_outbox_destinations,1),0));
end;
$$;

revoke all on function public.e10_org_stage_intake(uuid,text,text,text,text,text,jsonb,text) from public,anon;
revoke all on function public.e10_org_resolve_intake_row(uuid,uuid,text,uuid,text,uuid,text) from public,anon;
revoke all on function public.e10_org_record_commercial_event(uuid,text,text,text,timestamptz,text,text,jsonb,uuid,text[],text) from public,anon;
grant execute on function public.e10_org_stage_intake(uuid,text,text,text,text,text,jsonb,text) to authenticated,service_role;
grant execute on function public.e10_org_resolve_intake_row(uuid,uuid,text,uuid,text,uuid,text) to authenticated,service_role;
grant execute on function public.e10_org_record_commercial_event(uuid,text,text,text,timestamptz,text,text,jsonb,uuid,text[],text) to authenticated,service_role;
