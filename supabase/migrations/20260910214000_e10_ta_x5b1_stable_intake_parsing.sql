-- TA-X5b.1 deterministic, non-aborting typed parsing for mixed intake batches.

create or replace function e10.try_timestamptz(p_value text) returns timestamptz
language plpgsql stable set search_path=pg_catalog as $$
declare v timestamptz;
begin
  if p_value is null or btrim(p_value) !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$' then return null; end if;
  v:=btrim(p_value)::timestamptz;
  if v in ('infinity'::timestamptz,'-infinity'::timestamptz) then return null; end if;
  return v;
exception when others then return null;
end;
$$;
create or replace function e10.try_numeric(p_value text) returns numeric
language plpgsql immutable set search_path=pg_catalog as $$
declare v numeric;
begin
  v:=nullif(btrim(p_value),'')::numeric;
  if v::text in ('NaN','Infinity','-Infinity') then return null; end if;
  return v;
exception when others then return null;
end;
$$;

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
  select p_org,v_batch,ord,elem->'raw_payload',
    case when elem->>'observation_kind' in ('acquisition_cost','asking_price','completed_sale','estimated_value','inventory_receipt','customer_activity') then elem->>'observation_kind' end,
    e10.try_timestamptz(elem->>'occurred_at'),
    case when elem->>'currency' ~ '^[A-Z]{3}$' then elem->>'currency' end,
    case when e10.try_numeric(elem->>'amount')>=0 then e10.try_numeric(elem->>'amount') end,
    case when e10.try_numeric(elem->>'quantity')>0 then e10.try_numeric(elem->>'quantity') end,
    (case when coalesce(elem->>'observation_kind','') not in ('acquisition_cost','asking_price','completed_sale','estimated_value','inventory_receipt','customer_activity') then '["observation_kind_invalid_or_required"]'::jsonb else '[]'::jsonb end)
      || (case when e10.try_timestamptz(elem->>'occurred_at') is null then '["occurred_at_invalid_or_required"]'::jsonb else '[]'::jsonb end)
      || (case when elem->>'observation_kind' in ('acquisition_cost','asking_price','completed_sale','estimated_value')
                    and (e10.try_numeric(elem->>'amount') is null or e10.try_numeric(elem->>'amount')<0) then '["amount_invalid_or_required"]'::jsonb else '[]'::jsonb end)
      || (case when elem->>'observation_kind' in ('acquisition_cost','asking_price','completed_sale','estimated_value')
                    and coalesce(elem->>'currency','') !~ '^[A-Z]{3}$' then '["currency_invalid_or_required"]'::jsonb else '[]'::jsonb end)
      || (case when elem ? 'quantity' and (e10.try_numeric(elem->>'quantity') is null or e10.try_numeric(elem->>'quantity')<=0)
                    then '["quantity_invalid"]'::jsonb else '[]'::jsonb end)
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
