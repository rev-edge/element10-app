-- TA-R6 14d/14f: stable dispatcher errors and timezone-neutral v1 event replay.
create or replace function e10.x8_assert_args(p_args jsonb,p_allowed text[])
returns void language plpgsql immutable security definer set search_path=public as $$
declare arg_key text;arg_value jsonb;arg_type text;n numeric;
begin
 if p_args is null or jsonb_typeof(p_args)<>'object'or octet_length(p_args::text)>65536 or exists(select 1 from jsonb_object_keys(p_args)as supplied(key)where not(supplied.key=any(p_allowed)))then raise exception using errcode='22023',message='x8_query_args_invalid';end if;
 perform e10.x8_validate_json(p_args,0);
 for arg_key,arg_value in select key,value from jsonb_each(p_args)loop
  if arg_value='null'::jsonb then continue;end if;arg_type:=jsonb_typeof(arg_value);
  if arg_key=any(array['limit','week_start','freshness_days','expected_dataset_revision'])then
    if arg_type<>'number'or(arg_value#>>'{}')!~'^[0-9]+$'then raise exception using errcode='22023',message='x8_query_args_invalid';end if;
    begin n:=(arg_value#>>'{}')::numeric;exception when others then raise exception using errcode='22023',message='x8_query_args_invalid';end;
    if n>9223372036854775807 or(arg_key<>'expected_dataset_revision'and n>2147483647)then raise exception using errcode='22023',message='x8_query_args_invalid';end if;
  end if;
  if arg_key=any(array['after_created','from','to','observation_cutoff','as_of','closing_cutoff','opening_cutoff','observed_from','observed_to','after_occurred_at'])then begin if arg_type<>'string'or not isfinite((arg_value#>>'{}')::timestamptz)then raise exception using errcode='22023',message='x8_query_args_invalid';end if;exception when others then raise exception using errcode='22023',message='x8_query_args_invalid';end;end if;
  if arg_key='after_week_start'then begin if arg_type<>'string'or not isfinite((arg_value#>>'{}')::date)then raise exception using errcode='22023',message='x8_query_args_invalid';end if;exception when others then raise exception using errcode='22023',message='x8_query_args_invalid';end;end if;
  if arg_key=any(array['after_id','supplier_id','configuration_version_id','customer','location','product','configuration','copy','session','after_customer_id','after_transaction_id','after_line_id','after_activity_id','unique_item_id'])then begin perform(arg_value#>>'{}')::uuid;exception when others then raise exception using errcode='22023',message='x8_query_args_invalid';end;end if;
  if arg_key='filters'and arg_type<>'object'then raise exception using errcode='22023',message='x8_query_args_invalid';end if;
  if arg_key='source_connections'and(arg_type<>'array'or exists(select 1 from jsonb_array_elements(arg_value)e where jsonb_typeof(e)not in('string','null')))then raise exception using errcode='22023',message='x8_query_args_invalid';end if;
  if arg_key<>all(array['limit','week_start','freshness_days','expected_dataset_revision','filters','source_connections'])and arg_type<>'string'then raise exception using errcode='22023',message='x8_query_args_invalid';end if;
 end loop;
end $$;

alter function public.e10_org_typed_query(uuid,uuid,text,jsonb) rename to _e10_org_typed_query_r6;
revoke all on function public._e10_org_typed_query_r6(uuid,uuid,text,jsonb) from public,anon,authenticated;
grant execute on function public._e10_org_typed_query_r6(uuid,uuid,text,jsonb) to service_role;
create function public.e10_org_typed_query(p_org uuid,p_context_id uuid,p_operation text,p_args jsonb)returns jsonb
language plpgsql security definer set search_path=public as $$begin
  return public._e10_org_typed_query_r6(p_org,p_context_id,p_operation,p_args);
exception when invalid_text_representation or numeric_value_out_of_range then raise exception using errcode='22023',message='x8_query_args_invalid';end$$;

alter function public.e10_org_record_commercial_event(uuid,text,text,text,timestamptz,text,text,jsonb,uuid,text[],text) rename to _e10_org_record_commercial_event_r6;
revoke all on function public._e10_org_record_commercial_event_r6(uuid,text,text,text,timestamptz,text,text,jsonb,uuid,text[],text) from public,anon,authenticated;
grant execute on function public._e10_org_record_commercial_event_r6(uuid,text,text,text,timestamptz,text,text,jsonb,uuid,text[],text) to service_role;
create function public.e10_org_record_commercial_event(p_org uuid,p_event_type text,p_subject_type text,p_subject_id text,p_occurred_at timestamptz,p_source_kind text,p_source_reference text,p_payload jsonb,p_corrects_event_id uuid,p_outbox_destinations text[],p_idempotency_key text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare prior_timezone text:=current_setting('TimeZone');result jsonb;
begin
  perform set_config('TimeZone','UTC',true);
  begin result:=public._e10_org_record_commercial_event_r6(p_org,p_event_type,p_subject_type,p_subject_id,p_occurred_at,p_source_kind,p_source_reference,p_payload,p_corrects_event_id,p_outbox_destinations,p_idempotency_key);
  exception when others then perform set_config('TimeZone',prior_timezone,true);raise;end;
  perform set_config('TimeZone',prior_timezone,true);return result;
end$$;
revoke all on function public.e10_org_typed_query(uuid,uuid,text,jsonb),public.e10_org_record_commercial_event(uuid,text,text,text,timestamptz,text,text,jsonb,uuid,text[],text) from public,anon;
grant execute on function public.e10_org_typed_query(uuid,uuid,text,jsonb),public.e10_org_record_commercial_event(uuid,text,text,text,timestamptz,text,text,jsonb,uuid,text[],text) to authenticated,service_role;
