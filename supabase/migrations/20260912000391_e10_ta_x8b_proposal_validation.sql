-- TA-X8b.2 closed proposal validation and server-derived reference snapshots.

create function e10.x8b_capability(p_operation text,p_action text)returns text
language sql immutable security definer set search_path=public as $$
 select case p_operation
  when'purchase_order.create'then case p_action when'prepare'then'act.purchasing_prepare'when'approve'then'act.purchasing_approve'end
  when'customer_transaction.create_draft'then case p_action when'prepare'then'act.prepare_customer_transactions'when'approve'then'act.approve_customer_transactions'end
 end
$$;

create function e10.x8b_proposal_snapshot(p_org uuid,p_operation text,p_values jsonb,p_field_provenance jsonb,p_source_references jsonb)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare missing text[]:='{}';refs jsonb:='[]';line jsonb;n integer:=0;u uuid;q numeric;v text;state jsonb;
begin
 if p_operation not in('purchase_order.create','customer_transaction.create_draft')then raise exception using errcode='22023',message='action_operation_unsupported';end if;
 if p_values is null or jsonb_typeof(p_values)<>'object'or octet_length(p_values::text)>262144
  or p_field_provenance is null or jsonb_typeof(p_field_provenance)<>'object'or octet_length(p_field_provenance::text)>262144
  or p_source_references is null or jsonb_typeof(p_source_references)<>'array'or jsonb_array_length(p_source_references)>100 or octet_length(p_source_references::text)>65536
 then raise exception using errcode='22023',message='action_proposal_container_invalid';end if;
 perform e10.x8_validate_json(p_values,0);perform e10.x8_validate_json(p_field_provenance,0);perform e10.x8_validate_json(p_source_references,0);
 if p_operation='purchase_order.create'then
  perform e10.x8_assert_args(p_values,array['supplier_id','destination_location_id','order_number','currency','expected_at','lines']);
  if p_values?'supplier_id'and jsonb_typeof(p_values->'supplier_id')not in('string','null')or p_values?'destination_location_id'and jsonb_typeof(p_values->'destination_location_id')not in('string','null')or p_values?'currency'and jsonb_typeof(p_values->'currency')not in('string','null')or p_values?'expected_at'and jsonb_typeof(p_values->'expected_at')not in('string','null')or p_values?'lines'and jsonb_typeof(p_values->'lines')not in('array','null')then raise exception using errcode='22023',message='action_proposal_type_invalid';end if;
  if coalesce(p_values->>'currency','')!~'^[A-Z]{3}$'then missing:=array_append(missing,'currency');end if;
  if p_values->>'expected_at'is not null and not isfinite((p_values->>'expected_at')::timestamptz)then raise exception using errcode='22023',message='action_proposal_time_invalid';end if;
  begin u:=nullif(p_values->>'supplier_id','')::uuid;exception when invalid_text_representation then raise exception using errcode='22023',message='action_proposal_supplier_invalid';end;
  select jsonb_build_object('relation','e10_suppliers','id',s.id,'status',s.status,'updated_at',s.updated_at)into state from public.e10_suppliers s where s.organization_id=p_org and s.id=u;
  if state is null or state->>'status'<>'active'then missing:=array_append(missing,'supplier_id');else refs:=refs||jsonb_build_array(state);end if;
  begin u:=nullif(p_values->>'destination_location_id','')::uuid;exception when invalid_text_representation then raise exception using errcode='22023',message='action_proposal_destination_invalid';end;
  select jsonb_build_object('relation','e10_locations','id',l.id,'status',l.status,'updated_at',l.updated_at,'receivable',e10.can_receive_at(p_org,l.id))into state from public.e10_locations l where l.organization_id=p_org and l.id=u;
  if state is null or state->>'status'<>'active'or not coalesce((state->>'receivable')::boolean,false)then missing:=array_append(missing,'destination_location_id');else refs:=refs||jsonb_build_array(state);end if;
  if jsonb_typeof(p_values->'lines')is distinct from'array'or jsonb_array_length(p_values->'lines')not between 1 and 200 then missing:=array_append(missing,'lines');
  else for line in select value from jsonb_array_elements(p_values->'lines')loop n:=n+1;
   perform e10.x8_assert_args(line,array['id','line_no','configuration_version_id','ordered_quantity','estimated_unit_cost']);
   if jsonb_typeof(line->'line_no')is distinct from'number'or jsonb_typeof(line->'ordered_quantity')is distinct from'number'then raise exception using errcode='22023',message='action_proposal_line_type_invalid';end if;
   q:=(line->>'ordered_quantity')::numeric;if q<=0 or q::text in('NaN','Infinity','-Infinity')then missing:=array_append(missing,format('lines[%s].ordered_quantity',n));end if;
   begin u:=nullif(line->>'configuration_version_id','')::uuid;exception when invalid_text_representation then raise exception using errcode='22023',message='action_proposal_configuration_invalid';end;
   select jsonb_build_object('relation','e10_product_configuration_versions','id',cv.id,'state',cv.state,'version_no',cv.version_no,'configuration_id',cv.configuration_id)into state from public.e10_product_configuration_versions cv where cv.organization_id=p_org and cv.id=u;
   if state is null or state->>'state'<>'active'then missing:=array_append(missing,format('lines[%s].configuration_version_id',n));else refs:=refs||jsonb_build_array(state);end if;
  end loop;end if;
 else
  perform e10.x8_assert_args(p_values,array['customer_id','currency','occurred_at','precision','note','lines']);
  if coalesce(p_values->>'currency','')!~'^[A-Z]{3}$'then missing:=array_append(missing,'currency');end if;
  if coalesce(p_values->>'precision','')not in('exact','date','unknown')then missing:=array_append(missing,'precision');end if;
  if coalesce(p_values->>'note','')=''then missing:=array_append(missing,'note');end if;
  if(p_values->>'precision'='unknown')<>(p_values->>'occurred_at'is null)then missing:=array_append(missing,'occurred_at');elsif p_values->>'occurred_at'is not null and not isfinite((p_values->>'occurred_at')::timestamptz)then raise exception using errcode='22023',message='action_proposal_time_invalid';end if;
  begin u:=nullif(p_values->>'customer_id','')::uuid;exception when invalid_text_representation then raise exception using errcode='22023',message='action_proposal_customer_invalid';end;
  if u is not null then select jsonb_build_object('relation','e10_customers','id',c.id,'status',c.status,'revision',c.revision)into state from public.e10_customers c where c.organization_id=p_org and c.id=u;if state is null or state->>'status'<>'active'then missing:=array_append(missing,'customer_id');else refs:=refs||jsonb_build_array(state);end if;else missing:=array_append(missing,'customer_id');end if;
  if jsonb_typeof(p_values->'lines')is distinct from'array'or jsonb_array_length(p_values->'lines')not between 1 and 100 then missing:=array_append(missing,'lines');
  else for line in select value from jsonb_array_elements(p_values->'lines')loop n:=n+1;
   if coalesce(line->>'purchase_kind','')not in('retail','break','unclassified')then missing:=array_append(missing,format('lines[%s].purchase_kind',n));end if;
   if coalesce(line->>'capture_source','')not in('manual','import','native')then missing:=array_append(missing,format('lines[%s].capture_source',n));end if;
   if coalesce(btrim(line->>'source_line_id'),'')=''then missing:=array_append(missing,format('lines[%s].source_line_id',n));end if;
   if jsonb_typeof(line->'quantity')is distinct from'number'or(line->>'quantity')::numeric<=0 then missing:=array_append(missing,format('lines[%s].quantity',n));end if;
   if jsonb_typeof(line->'merchandise_gross')is distinct from'number'or(line->>'merchandise_gross')::numeric<0 then missing:=array_append(missing,format('lines[%s].merchandise_gross',n));end if;
   for v in select key from jsonb_each(line)where key in('activity_observation_id','location_id','product_master_id','configuration_version_id','unique_item_id','break_session_id','break_slot_id')and jsonb_typeof(value)not in('string','null')loop raise exception using errcode='22023',message='action_proposal_reference_type_invalid';end loop;
   if nullif(line->>'activity_observation_id','')is not null then u:=(line->>'activity_observation_id')::uuid;select jsonb_build_object('relation','e10_customer_activity_observations','id',a.id,'request_fingerprint',a.request_fingerprint,'effective_customer',e10.customer_activity_effective_customer(p_org,a.id))into state from public.e10_customer_activity_observations a where a.organization_id=p_org and a.id=u;if state is null or(state->>'effective_customer')is distinct from coalesce(p_values->>'customer_id','')then missing:=array_append(missing,format('lines[%s].activity_observation_id',n));else refs:=refs||jsonb_build_array(state);end if;end if;
   if nullif(line->>'configuration_version_id','')is not null then u:=(line->>'configuration_version_id')::uuid;select jsonb_build_object('relation','e10_product_configuration_versions','id',cv.id,'state',cv.state,'version_no',cv.version_no,'configuration_id',cv.configuration_id)into state from public.e10_product_configuration_versions cv where cv.organization_id=p_org and cv.id=u;if state is null or state->>'state'<>'active'then missing:=array_append(missing,format('lines[%s].configuration_version_id',n));else refs:=refs||jsonb_build_array(state);end if;end if;
   if coalesce(line->>'product_master_id',line->>'configuration_version_id',line->>'unique_item_id')is null then missing:=array_append(missing,format('lines[%s].product_identity',n));end if;
  end loop;end if;
 end if;
 select coalesce(array_agg(distinct x order by x),'{}')into missing from unnest(missing)x;
 return jsonb_build_object('values',p_values,'missing_fields',to_jsonb(missing),'reference_state',refs,'reference_fingerprint',encode(extensions.digest(convert_to(refs::text,'UTF8'),'sha256'),'hex'));
exception when invalid_text_representation or numeric_value_out_of_range then raise exception using errcode='22023',message='action_proposal_encoding_invalid';
end $$;

revoke all on function e10.x8b_capability(text,text),e10.x8b_proposal_snapshot(uuid,text,jsonb,jsonb,jsonb) from public,anon,authenticated;
grant execute on function e10.x8b_capability(text,text),e10.x8b_proposal_snapshot(uuid,text,jsonb,jsonb,jsonb) to service_role;
