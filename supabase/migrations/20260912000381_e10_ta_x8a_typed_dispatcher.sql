-- TA-X8a.2 closed typed query dispatcher over reviewed readers.

create function e10.x8_validate_json(p_value jsonb,p_depth integer default 0)
returns void language plpgsql immutable security definer set search_path=public as $$
declare v jsonb;k text;
begin
 if p_value is null or p_depth>16 then raise exception using errcode='22023',message='x8_query_args_invalid';end if;
 if jsonb_typeof(p_value)='string'and octet_length(p_value#>>'{}')>2000 then raise exception using errcode='22023',message='x8_query_args_invalid';end if;
 if jsonb_typeof(p_value)='number'and(p_value#>>'{}')in('NaN','Infinity','-Infinity')then raise exception using errcode='22023',message='x8_query_args_invalid';end if;
 if jsonb_typeof(p_value)='array'then
  if jsonb_array_length(p_value)>100 then raise exception using errcode='22023',message='x8_query_args_invalid';end if;
  for v in select value from jsonb_array_elements(p_value)loop perform e10.x8_validate_json(v,p_depth+1);end loop;
 elsif jsonb_typeof(p_value)='object'then
  if(select count(*)from jsonb_object_keys(p_value))>100 then raise exception using errcode='22023',message='x8_query_args_invalid';end if;
  for k,v in select key,value from jsonb_each(p_value)loop if octet_length(k)>200 then raise exception using errcode='22023',message='x8_query_args_invalid';end if;perform e10.x8_validate_json(v,p_depth+1);end loop;
 end if;
end $$;

create function e10.x8_assert_args(p_args jsonb,p_allowed text[])
returns void language plpgsql immutable security definer set search_path=public as $$
declare arg_key text;arg_value jsonb;arg_type text;
begin
 if p_args is null or jsonb_typeof(p_args)<>'object'or octet_length(p_args::text)>65536 or exists(select 1 from jsonb_object_keys(p_args)as supplied(key)where not(supplied.key=any(p_allowed)))then raise exception using errcode='22023',message='x8_query_args_invalid';end if;
 perform e10.x8_validate_json(p_args,0);
 for arg_key,arg_value in select key,value from jsonb_each(p_args)loop
  if arg_value='null'::jsonb then continue;end if;arg_type:=jsonb_typeof(arg_value);
  if arg_key=any(array['limit','week_start','freshness_days','expected_dataset_revision'])and(arg_type<>'number'or(arg_value#>>'{}')!~'^[0-9]+$')then raise exception using errcode='22023',message='x8_query_args_invalid';end if;
  if arg_key='filters'and arg_type<>'object'then raise exception using errcode='22023',message='x8_query_args_invalid';end if;
  if arg_key='source_connections'and(arg_type<>'array'or exists(select 1 from jsonb_array_elements(arg_value)e where jsonb_typeof(e)<>'string'))then raise exception using errcode='22023',message='x8_query_args_invalid';end if;
  if arg_key<>all(array['limit','week_start','freshness_days','expected_dataset_revision','filters','source_connections'])and arg_type<>'string'then raise exception using errcode='22023',message='x8_query_args_invalid';end if;
 end loop;
 if p_args?'filters'then
  for arg_key,arg_value in select key,value from jsonb_each(p_args->'filters')loop
   if arg_value='null'::jsonb then continue;end if;arg_type:=jsonb_typeof(arg_value);
   if arg_key='year'and arg_type not in('string','number')then raise exception using errcode='22023',message='x8_query_args_invalid';end if;
   if arg_key<>'year'and arg_type<>'string'then raise exception using errcode='22023',message='x8_query_args_invalid';end if;
  end loop;
 end if;
end $$;

create function e10.x8_redact_inventory_result(p_result jsonb)
returns jsonb language sql immutable security definer set search_path=public as $$
 select case when jsonb_typeof(p_result->'items')='array'then jsonb_set(p_result,'{items}',coalesce((select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
  'id',value->'id','name',value->'name','cat',value->'cat','set',value->'set','setId',value->'setId','cond',value->'cond','year',value->'year','parallel',value->'parallel','cardNumber',value->'cardNumber','rarity',value->'rarity','grade',value->'grade','gradingCompany',value->'gradingCompany','img',value->'img','qty',value->'qty','boxesPerCase',value->'boxesPerCase','soldQty',value->'soldQty','soldAt',value->'soldAt','cardId',value->'cardId','playerId',value->'playerId','owner',value->'owner','addedAt',value->'addedAt','seed',value->'seed','reservations',value->'reservations')))from jsonb_array_elements(p_result->'items')),'[]'::jsonb))
 when jsonb_typeof(p_result->'movements')='array'then jsonb_set(p_result,'{movements}',coalesce((select jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
  'id',value->'id','item_id',value->'item_id','movement_type',value->'movement_type','on_hand_delta',value->'on_hand_delta','reserved_delta',value->'reserved_delta','source_entity_type',value->'source_entity_type','source_entity_id',value->'source_entity_id','source_action',value->'source_action','reason_code',value->'reason_code','created_at',value->'created_at')))from jsonb_array_elements(p_result->'movements')),'[]'::jsonb))else p_result end
$$;

create function e10.x8_query_envelope(p_org uuid,p_context uuid,p_operation text,p_args jsonb,p_result jsonb,p_grain text,p_units jsonb,p_unknowns jsonb default'[]'::jsonb)
returns jsonb language sql stable security definer set search_path=public as $$
 select jsonb_build_object(
  'version','x8-query-v1','operation',p_operation,'organization_id',p_org,'context_id',p_context,
  'query_fingerprint',coalesce(p_result->>'query_fingerprint',p_result->>'request_fingerprint',encode(sha256(convert_to(jsonb_build_object('v','x8-query-v1','org',p_org,'actor',auth.uid(),'operation',p_operation,'args',p_args)::text,'UTF8')),'hex')),
  'as_of',coalesce(nullif(p_result->'as_of','null'::jsonb),nullif(p_args->'as_of','null'::jsonb)),'cutoff',coalesce(nullif(p_result->'observation_cutoff','null'::jsonb),nullif(p_result->'closing_cutoff','null'::jsonb),nullif(p_args->'observation_cutoff','null'::jsonb),nullif(p_args->'closing_cutoff','null'::jsonb)),
  'grain',p_grain,'units',coalesce(p_units,'null'::jsonb),'metric_definition',coalesce(p_result->'metric_version','null'::jsonb),
  'coverage',coalesce(nullif(p_result->'coverage','null'::jsonb),nullif(p_result->'summary'->'coverage','null'::jsonb),'null'::jsonb),
  'sources',coalesce(p_result->'sources','[]'::jsonb),'unknowns',coalesce(p_unknowns,'[]'::jsonb)
   ||case when coalesce(nullif(p_result->'as_of','null'::jsonb),nullif(p_args->'as_of','null'::jsonb))is null then'["as_of"]'::jsonb else'[]'::jsonb end
   ||case when coalesce(nullif(p_result->'observation_cutoff','null'::jsonb),nullif(p_result->'closing_cutoff','null'::jsonb),nullif(p_args->'observation_cutoff','null'::jsonb),nullif(p_args->'closing_cutoff','null'::jsonb))is null then'["cutoff"]'::jsonb else'[]'::jsonb end
   ||case when p_units is null or p_units='null'::jsonb then'["units"]'::jsonb else'[]'::jsonb end
   ||case when nullif(p_result->'metric_version','null'::jsonb)is null then'["metric_definition"]'::jsonb else'[]'::jsonb end
   ||case when coalesce(nullif(p_result->'coverage','null'::jsonb),nullif(p_result->'summary'->'coverage','null'::jsonb))is null then'["coverage"]'::jsonb else'[]'::jsonb end,
  'result',p_result)
$$;

create function public.e10_org_typed_query(p_org uuid,p_context_id uuid,p_operation text,p_args jsonb)
returns jsonb language plpgsql volatile security definer set search_path=public as $$
declare actor uuid;res jsonb;grain text;units jsonb:='null'::jsonb;unknowns jsonb:='[]'::jsonb;
begin
 actor:=e10.x8_query_context_actor(p_org,p_context_id,false);
 if p_operation is null or length(p_operation)not between 1 and 100 then raise exception using errcode='22023',message='x8_query_operation_invalid';end if;

 case p_operation
 when'inventory.page'then
  perform e10.x8_assert_args(p_args,array['after','limit','filters']);
  perform e10.x8_assert_args(coalesce(p_args->'filters','{}'::jsonb),array['cat','set','year','grade','q']);
  if not coalesce((p_args->>'limit')::integer between 1 and 500,false)then raise exception using errcode='22023',message='x8_query_args_invalid';end if;
  res:=public.e10_org_inv_page(p_org,p_args->>'after',(p_args->>'limit')::integer,coalesce(p_args->'filters','{}'::jsonb));
  res:=e10.x8_redact_inventory_result(res);grain:='inventory_item';units:=jsonb_build_object('quantity','stored_item_quantity');unknowns:='["coverage","revision","cutoff"]';
 when'inventory.history'then
  perform e10.x8_assert_args(p_args,array['after_created','after_id','limit','item_id']);
  if not coalesce((p_args->>'limit')::integer between 1 and 500,false)or num_nonnulls(p_args->>'after_created',p_args->>'after_id')not in(0,2)then raise exception using errcode='22023',message='x8_query_args_invalid';end if;
  res:=public.e10_org_inv_history(p_org,(p_args->>'after_created')::timestamptz,(p_args->>'after_id')::uuid,(p_args->>'limit')::integer,p_args->>'item_id');
  res:=e10.x8_redact_inventory_result(res);grain:='inventory_movement';units:=jsonb_build_object('on_hand_delta','stored_item_quantity','reserved_delta','stored_item_quantity');unknowns:='["coverage"]';
 when'supplier.workspace'then
  perform e10.x8_assert_args(p_args,array['supplier_id','limit','cursor']);
  if p_args->>'supplier_id'is null or not coalesce((p_args->>'limit')::integer between 1 and 100,false)then raise exception using errcode='22023',message='x8_query_args_invalid';end if;
  res:=public.e10_org_supplier_workspace(p_org,(p_args->>'supplier_id')::uuid,(p_args->>'limit')::integer,p_args->>'cursor');grain:='supplier_document';unknowns:='["payment_status"]';
 when'supplier.actual_cost_history'then
  perform e10.x8_assert_args(p_args,array['supplier_id','configuration_version_id','currency','as_of','limit','cursor']);
  if p_args->>'supplier_id'is null or p_args->>'configuration_version_id'is null or coalesce(p_args->>'currency','')!~'^[A-Z]{3}$'or p_args->>'as_of'is null or not coalesce((p_args->>'limit')::integer between 1 and 100,false)then raise exception using errcode='22023',message='x8_query_args_invalid';end if;
  res:=public.e10_org_supplier_actual_cost_history(p_org,(p_args->>'supplier_id')::uuid,(p_args->>'configuration_version_id')::uuid,p_args->>'currency',(p_args->>'as_of')::timestamptz,(p_args->>'limit')::integer,p_args->>'cursor');grain:='accepted_receipt_cost_evidence';units:=jsonb_build_object('currency',p_args->>'currency','quantity','configuration_base_unit');
 when'customer.spend_summary'then
  perform e10.x8_assert_args(p_args,array['from','to','observation_cutoff','currency','timezone','week_start','customer','purchase_kind','location','channel','product','configuration','copy','session','capture_source','limit','after_customer_id','expected_dataset_revision','expected_query_fingerprint']);
  if not coalesce((p_args->>'limit')::integer between 1 and 100,false)or not coalesce((p_args->>'week_start')::integer between 1 and 7,false)then raise exception using errcode='22023',message='x8_query_args_invalid';end if;
  res:=public.e10_org_customer_spend_summary(p_org,(p_args->>'from')::timestamptz,(p_args->>'to')::timestamptz,(p_args->>'observation_cutoff')::timestamptz,p_args->>'currency',p_args->>'timezone',(p_args->>'week_start')::integer,(p_args->>'customer')::uuid,p_args->>'purchase_kind',(p_args->>'location')::uuid,p_args->>'channel',(p_args->>'product')::uuid,(p_args->>'configuration')::uuid,(p_args->>'copy')::uuid,(p_args->>'session')::uuid,p_args->>'capture_source',(p_args->>'limit')::integer,(p_args->>'after_customer_id')::uuid,(p_args->>'expected_dataset_revision')::bigint,p_args->>'expected_query_fingerprint');grain:='effective_customer';units:=jsonb_build_object('money',p_args->>'currency');
 when'customer.spend_contributions'then
  perform e10.x8_assert_args(p_args,array['from','to','observation_cutoff','currency','customer','purchase_kind','location','channel','product','configuration','copy','session','capture_source','limit','after_occurred_at','after_transaction_id','after_line_id','expected_dataset_revision','expected_query_fingerprint']);
  if not coalesce((p_args->>'limit')::integer between 1 and 100,false)or num_nonnulls(p_args->>'after_occurred_at',p_args->>'after_transaction_id',p_args->>'after_line_id')not in(0,3)then raise exception using errcode='22023',message='x8_query_args_invalid';end if;
  res:=public.e10_org_customer_spend_contributions(p_org,(p_args->>'from')::timestamptz,(p_args->>'to')::timestamptz,(p_args->>'observation_cutoff')::timestamptz,p_args->>'currency',(p_args->>'customer')::uuid,p_args->>'purchase_kind',(p_args->>'location')::uuid,p_args->>'channel',(p_args->>'product')::uuid,(p_args->>'configuration')::uuid,(p_args->>'copy')::uuid,(p_args->>'session')::uuid,p_args->>'capture_source',(p_args->>'limit')::integer,(p_args->>'after_occurred_at')::timestamptz,(p_args->>'after_transaction_id')::uuid,(p_args->>'after_line_id')::uuid,(p_args->>'expected_dataset_revision')::bigint,p_args->>'expected_query_fingerprint');grain:='posted_transaction_line_contribution';units:=jsonb_build_object('money',p_args->>'currency');
 when'customer.provisional_activity'then
  perform e10.x8_assert_args(p_args,array['from','to','observation_cutoff','currency','customer','limit','after_occurred_at','after_activity_id','expected_dataset_revision','expected_query_fingerprint']);
  if not coalesce((p_args->>'limit')::integer between 1 and 100,false)or num_nonnulls(p_args->>'after_occurred_at',p_args->>'after_activity_id')not in(0,2)then raise exception using errcode='22023',message='x8_query_args_invalid';end if;
  res:=public.e10_org_customer_provisional_activity(p_org,(p_args->>'from')::timestamptz,(p_args->>'to')::timestamptz,(p_args->>'observation_cutoff')::timestamptz,p_args->>'currency',(p_args->>'customer')::uuid,(p_args->>'limit')::integer,(p_args->>'after_occurred_at')::timestamptz,(p_args->>'after_activity_id')::uuid,(p_args->>'expected_dataset_revision')::bigint,p_args->>'expected_query_fingerprint');grain:='provisional_activity';units:=jsonb_build_object('money',p_args->>'currency');
 when'attendance.weekly'then
  perform e10.x8_assert_args(p_args,array['from','to','observation_cutoff','timezone','week_start','customer','source_class','provider_key','limit','after_week_start','expected_dataset_revision','expected_query_fingerprint']);
  if not coalesce((p_args->>'limit')::integer between 1 and 54,false)or not coalesce((p_args->>'week_start')::integer between 1 and 7,false)then raise exception using errcode='22023',message='x8_query_args_invalid';end if;
  select jsonb_build_object('items',coalesce(jsonb_agg(to_jsonb(w)order by w.week_start_date),'[]'::jsonb),'query_fingerprint',max(w.query_fingerprint),'observation_cutoff',max(w.observation_cutoff),'dataset_revision',max(w.dataset_revision),'metric_version',max(w.metric_version),'coverage',jsonb_build_object('statuses',coalesce(jsonb_agg(distinct w.coverage_status),'[]'::jsonb)))into res from public.e10_org_weekly_attendance(p_org,(p_args->>'from')::timestamptz,(p_args->>'to')::timestamptz,(p_args->>'observation_cutoff')::timestamptz,p_args->>'timezone',(p_args->>'week_start')::integer,(p_args->>'customer')::uuid,coalesce(p_args->>'source_class','companion'),coalesce(p_args->>'provider_key','companion'),(p_args->>'limit')::integer,(p_args->>'after_week_start')::date,(p_args->>'expected_dataset_revision')::bigint,p_args->>'expected_query_fingerprint')w;
  grain:=case when p_args->>'customer'is not null then'customer_local_calendar_week'else'organization_local_calendar_week'end;units:=jsonb_build_object('duration','observed_presence_seconds','session_count','distinct_sessions');
 when'inventory.lifecycle'then
  perform e10.x8_assert_args(p_args,array['as_of','unique_item_id','limit','cursor']);if p_args->>'as_of'is null or not coalesce((p_args->>'limit')::integer between 1 and 100,false)then raise exception using errcode='22023',message='x8_query_args_invalid';end if;
  res:=public.e10_org_inventory_lifecycle(p_org,(p_args->>'as_of')::timestamptz,(p_args->>'unique_item_id')::uuid,(p_args->>'limit')::integer,p_args->>'cursor');grain:='unique_item_ownership_episode';units:=jsonb_build_object('duration','seconds');
 when'inventory.unique_item_evidence'then
  perform e10.x8_assert_args(p_args,array['unique_item_id','as_of','limit','cursor']);if p_args->>'unique_item_id'is null or p_args->>'as_of'is null or not coalesce((p_args->>'limit')::integer between 1 and 50,false)then raise exception using errcode='22023',message='x8_query_args_invalid';end if;
  res:=public.e10_org_unique_item_evidence(p_org,(p_args->>'unique_item_id')::uuid,(p_args->>'as_of')::timestamptz,(p_args->>'limit')::integer,p_args->>'cursor');grain:='evidence_record';
 when'inventory.valuation_coverage'then
  perform e10.x8_assert_args(p_args,array['method','method_version','currency','closing_cutoff','opening_cutoff','freshness_days','limit','cursor']);if p_args->>'method'is null or p_args->>'method_version'is null or p_args->>'closing_cutoff'is null or not coalesce((p_args->>'freshness_days')::integer between 1 and 3650,false)or not coalesce((p_args->>'limit')::integer between 1 and 100,false)then raise exception using errcode='22023',message='x8_query_args_invalid';end if;
  res:=public.e10_org_inventory_valuation_coverage(p_org,p_args->>'method',p_args->>'method_version',p_args->>'currency',(p_args->>'closing_cutoff')::timestamptz,(p_args->>'opening_cutoff')::timestamptz,(p_args->>'freshness_days')::integer,(p_args->>'limit')::integer,p_args->>'cursor');grain:='unique_item_holding';units:=jsonb_build_object('money',p_args->>'currency');
 when'market.screener'then
  perform e10.x8_assert_args(p_args,array['scope','grouping','metric','observation_kind','observed_from','observed_to','as_of','currency','source_mode','source_kind','source_connections','filters','sort','limit','cursor']);if not coalesce((p_args->>'limit')::integer between 1 and 100,false)then raise exception using errcode='22023',message='x8_query_args_invalid';end if;
  res:=public.e10_org_market_screener(p_org,p_args->>'scope',p_args->>'grouping',p_args->>'metric',p_args->>'observation_kind',(p_args->>'observed_from')::timestamptz,(p_args->>'observed_to')::timestamptz,(p_args->>'as_of')::timestamptz,p_args->>'currency',p_args->>'source_mode',p_args->>'source_kind',p_args->'source_connections',coalesce(p_args->'filters','{}'),coalesce(p_args->>'sort','cohort_asc'),(p_args->>'limit')::integer,(p_args->>'cursor')::uuid);grain:=coalesce(res->>'grain','market_cohort');units:=coalesce(res->'units','null');
 when'market.observation_drilldown'then
  perform e10.x8_assert_args(p_args,array['parent_query_fingerprint','cohort_key','observation_kind','observed_from','observed_to','as_of','currency','source_mode','source_kind','source_connections','limit','cursor']);if not coalesce((p_args->>'limit')::integer between 1 and 50,false)then raise exception using errcode='22023',message='x8_query_args_invalid';end if;
  res:=public.e10_org_market_observation_drilldown(p_org,p_args->>'parent_query_fingerprint',p_args->>'cohort_key',p_args->>'observation_kind',(p_args->>'observed_from')::timestamptz,(p_args->>'observed_to')::timestamptz,(p_args->>'as_of')::timestamptz,p_args->>'currency',p_args->>'source_mode',p_args->>'source_kind',p_args->'source_connections',(p_args->>'limit')::integer,(p_args->>'cursor')::uuid);grain:=coalesce(res->>'grain','market_observation');units:=coalesce(res->'units','null');
 else raise exception using errcode='22023',message='x8_query_operation_unsupported';
 end case;
 if e10.x8_query_context_actor(p_org,p_context_id,false)is distinct from actor then raise exception using errcode='42501',message='x8_query_denied';end if;
 return e10.x8_query_envelope(p_org,p_context_id,p_operation,p_args,res,grain,units,unknowns);
end $$;

revoke all on function e10.x8_validate_json(jsonb,integer),e10.x8_assert_args(jsonb,text[]),e10.x8_redact_inventory_result(jsonb),e10.x8_query_envelope(uuid,uuid,text,jsonb,jsonb,text,jsonb,jsonb)from public,anon,authenticated;
grant execute on function e10.x8_validate_json(jsonb,integer),e10.x8_assert_args(jsonb,text[]),e10.x8_redact_inventory_result(jsonb),e10.x8_query_envelope(uuid,uuid,text,jsonb,jsonb,text,jsonb,jsonb)to service_role;
revoke all on function public.e10_org_typed_query(uuid,uuid,text,jsonb)from public,anon;
grant execute on function public.e10_org_typed_query(uuid,uuid,text,jsonb)to authenticated,service_role;
comment on function public.e10_org_typed_query(uuid,uuid,text,jsonb)is'Closed TA-X8a typed query allowlist. Business-read-only; query-control metadata writes only.';
