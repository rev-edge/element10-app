-- TA-X8b.2 closed proposal validation and server-derived reference snapshots.

create function e10.x8b_capability(p_operation text,p_action text)returns text
language sql immutable security definer set search_path=public as $$
 select case p_operation
  when'purchase_order.create'then case p_action when'prepare'then'act.purchasing_prepare'when'approve'then'act.purchasing_approve'end
  when'customer_transaction.create_draft'then case p_action when'prepare'then'act.prepare_customer_transactions'when'approve'then'act.approve_customer_transactions'end
 end
$$;

create function e10.x8b_validate_provenance(p_operation text,p_values jsonb,p_provenance jsonb,p_sources jsonb)returns void
language plpgsql immutable security definer set search_path=public as $$
declare k text;v jsonb;entry jsonb;allowed text[];begin
 allowed:=case p_operation when'purchase_order.create'then array['supplier_id','destination_location_id','order_number','currency','expected_at','lines']when'customer_transaction.create_draft'then array['customer_id','currency','occurred_at','precision','note','lines']end;
 if allowed is null or exists(select 1 from jsonb_object_keys(p_provenance)as supplied(key)where not(supplied.key=any(allowed)))then raise exception using errcode='22023',message='action_provenance_unknown_key';end if;
 for k,v in select key,value from jsonb_each(p_provenance)loop
  if k='lines'and jsonb_typeof(v)='array'then
   if jsonb_array_length(v)>coalesce(jsonb_array_length(p_values->'lines'),0)then raise exception using errcode='22023',message='action_provenance_lines_invalid';end if;
   for entry in select value from jsonb_array_elements(v)loop
    if jsonb_typeof(entry)<>'object'or exists(select 1 from jsonb_object_keys(entry)as supplied(key)where not(supplied.key=any(array['source','source_reference','confidence','text'])))
     or exists(select 1 from jsonb_each(entry)where key in('source','source_reference','text')and jsonb_typeof(value)not in('string','null'))
     or entry?'confidence'and(jsonb_typeof(entry->'confidence')not in('number','null')or coalesce((entry->>'confidence')::numeric not between 0 and 1,false))
    then raise exception using errcode='22023',message='action_provenance_entry_invalid';end if;
   end loop;
  elsif jsonb_typeof(v)<>'object'or exists(select 1 from jsonb_object_keys(v)as supplied(key)where not(supplied.key=any(array['source','source_reference','confidence','text'])))
   or exists(select 1 from jsonb_each(v)where key in('source','source_reference','text')and jsonb_typeof(value)not in('string','null'))
   or v?'confidence'and(jsonb_typeof(v->'confidence')not in('number','null')or coalesce((v->>'confidence')::numeric not between 0 and 1,false))
  then raise exception using errcode='22023',message='action_provenance_entry_invalid';end if;
 end loop;
 for entry in select value from jsonb_array_elements(p_sources)loop
  if jsonb_typeof(entry)<>'object'or exists(select 1 from jsonb_object_keys(entry)as supplied(key)where not(supplied.key=any(array['kind','source_connection_id','source_reference','source_event_id','source_component_id','text','payload'])))or jsonb_typeof(entry->'kind')is distinct from'string'or coalesce(btrim(entry->>'kind'),'')=''then raise exception using errcode='22023',message='action_source_reference_invalid';end if;
  for k in select unnest(array['source_connection_id','source_reference','source_event_id','source_component_id','text'])loop if entry?k and jsonb_typeof(entry->k)not in('string','null')then raise exception using errcode='22023',message='action_source_reference_type_invalid';end if;end loop;
  if entry?'payload'and jsonb_typeof(entry->'payload')not in('object','null')then raise exception using errcode='22023',message='action_source_payload_invalid';end if;
 end loop;
end $$;

create function e10.x8b_proposal_snapshot(p_org uuid,p_operation text,p_values jsonb,p_field_provenance jsonb,p_source_references jsonb)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare missing text[]:='{}';refs jsonb:='[]';line jsonb;n integer:=0;u uuid;q numeric;v text;k text;state jsonb;
begin
 if p_operation not in('purchase_order.create','customer_transaction.create_draft')then raise exception using errcode='22023',message='action_operation_unsupported';end if;
 if p_values is null or jsonb_typeof(p_values)<>'object'or octet_length(p_values::text)>262144
  or p_field_provenance is null or jsonb_typeof(p_field_provenance)<>'object'or octet_length(p_field_provenance::text)>262144
  or p_source_references is null or jsonb_typeof(p_source_references)<>'array'or jsonb_array_length(p_source_references)>100 or octet_length(p_source_references::text)>65536
 then raise exception using errcode='22023',message='action_proposal_container_invalid';end if;
 perform e10.x8_validate_json(p_values,0);perform e10.x8_validate_json(p_field_provenance,0);perform e10.x8_validate_json(p_source_references,0);
 perform e10.x8b_validate_provenance(p_operation,p_values,p_field_provenance,p_source_references);
 if p_operation='purchase_order.create'then
  if exists(select 1 from jsonb_object_keys(p_values)as supplied(key)where not(supplied.key=any(array['supplier_id','destination_location_id','order_number','currency','expected_at','lines'])))then raise exception using errcode='22023',message='action_proposal_unknown_key';end if;
  if p_values?'supplier_id'and jsonb_typeof(p_values->'supplier_id')not in('string','null')or p_values?'destination_location_id'and jsonb_typeof(p_values->'destination_location_id')not in('string','null')or p_values?'order_number'and jsonb_typeof(p_values->'order_number')not in('string','null')or p_values?'currency'and jsonb_typeof(p_values->'currency')not in('string','null')or p_values?'expected_at'and jsonb_typeof(p_values->'expected_at')not in('string','null')or p_values?'lines'and jsonb_typeof(p_values->'lines')not in('array','null')then raise exception using errcode='22023',message='action_proposal_type_invalid';end if;
  if p_values->>'order_number'is not null and(length(btrim(p_values->>'order_number'))not between 1 and 200)then raise exception using errcode='22023',message='action_proposal_order_number_invalid';end if;
  if coalesce(p_values->>'currency','')!~'^[A-Z]{3}$'then missing:=array_append(missing,'currency');end if;
  if p_values->>'expected_at'is not null and not isfinite((p_values->>'expected_at')::timestamptz)then raise exception using errcode='22023',message='action_proposal_time_invalid';end if;
  begin u:=nullif(p_values->>'supplier_id','')::uuid;exception when invalid_text_representation then raise exception using errcode='22023',message='action_proposal_supplier_invalid';end;
  select jsonb_build_object('relation','e10_suppliers','id',s.id,'status',s.status,'updated_at',s.updated_at)into state from public.e10_suppliers s where s.organization_id=p_org and s.id=u;
  if state is null or state->>'status'<>'active'then missing:=array_append(missing,'supplier_id');else refs:=refs||jsonb_build_array(state);end if;
  begin u:=nullif(p_values->>'destination_location_id','')::uuid;exception when invalid_text_representation then raise exception using errcode='22023',message='action_proposal_destination_invalid';end;
  select jsonb_build_object('relation','e10_locations','id',l.id,'status',l.status,'updated_at',l.updated_at)into state from public.e10_locations l where l.organization_id=p_org and l.id=u;
  if state is null or state->>'status'<>'active'then missing:=array_append(missing,'destination_location_id');else refs:=refs||jsonb_build_array(state);end if;
  if jsonb_typeof(p_values->'lines')is distinct from'array'or jsonb_array_length(p_values->'lines')not between 1 and 200 then missing:=array_append(missing,'lines');
  else for line in select value from jsonb_array_elements(p_values->'lines')loop n:=n+1;
   if jsonb_typeof(line)<>'object'or exists(select 1 from jsonb_object_keys(line)as supplied(key)where not(supplied.key=any(array['id','line_no','configuration_version_id','ordered_quantity','estimated_unit_cost'])))then raise exception using errcode='22023',message='action_proposal_line_unknown_key';end if;
   if line?'id'and jsonb_typeof(line->'id')not in('string','null')or line?'line_no'and jsonb_typeof(line->'line_no')not in('number','null')or line?'ordered_quantity'and jsonb_typeof(line->'ordered_quantity')not in('number','null')or line?'estimated_unit_cost'and jsonb_typeof(line->'estimated_unit_cost')not in('number','null')then raise exception using errcode='22023',message='action_proposal_line_type_invalid';end if;
   if line->>'id'is not null then begin u:=(line->>'id')::uuid;exception when invalid_text_representation then raise exception using errcode='22023',message='action_proposal_line_id_invalid';end;end if;
   if line->>'line_no'is null then missing:=array_append(missing,format('lines[%s].line_no',n));elsif(line->>'line_no')::numeric<>trunc((line->>'line_no')::numeric)or(line->>'line_no')::numeric<=0 then raise exception using errcode='22023',message='action_proposal_line_number_invalid';end if;
   if line->>'ordered_quantity'is null then missing:=array_append(missing,format('lines[%s].ordered_quantity',n));else q:=(line->>'ordered_quantity')::numeric;if q<=0 or q::text in('NaN','Infinity','-Infinity')then raise exception using errcode='22023',message='action_proposal_line_quantity_invalid';end if;end if;
   if line->>'estimated_unit_cost'is not null then q:=(line->>'estimated_unit_cost')::numeric;if q<0 or q::text in('NaN','Infinity','-Infinity')then raise exception using errcode='22023',message='action_proposal_line_cost_invalid';end if;end if;
   begin u:=nullif(line->>'configuration_version_id','')::uuid;exception when invalid_text_representation then raise exception using errcode='22023',message='action_proposal_configuration_invalid';end;
   select jsonb_build_object('relation','e10_product_configuration_versions','id',cv.id,'state',cv.state,'version_no',cv.version_no,'configuration_id',cv.configuration_id,'configuration_status',c.status,'configuration_updated_at',c.updated_at,'product_id',p.id,'product_status',p.status,'product_updated_at',p.updated_at)into state from public.e10_product_configuration_versions cv join public.e10_product_configurations c on c.organization_id=cv.organization_id and c.id=cv.configuration_id join public.e10_product_masters p on p.organization_id=c.organization_id and p.id=c.product_master_id where cv.organization_id=p_org and cv.id=u;
   if state is null or state->>'state'<>'active'then missing:=array_append(missing,format('lines[%s].configuration_version_id',n));else refs:=refs||jsonb_build_array(state);end if;
  end loop;end if;
 else
  if exists(select 1 from jsonb_object_keys(p_values)as supplied(key)where not(supplied.key=any(array['customer_id','currency','occurred_at','precision','note','lines'])))then raise exception using errcode='22023',message='action_proposal_unknown_key';end if;
  if p_values?'customer_id'and jsonb_typeof(p_values->'customer_id')not in('string','null')or p_values?'currency'and jsonb_typeof(p_values->'currency')not in('string','null')or p_values?'occurred_at'and jsonb_typeof(p_values->'occurred_at')not in('string','null')or p_values?'precision'and jsonb_typeof(p_values->'precision')not in('string','null')or p_values?'note'and jsonb_typeof(p_values->'note')not in('string','null')or p_values?'lines'and jsonb_typeof(p_values->'lines')not in('array','null')then raise exception using errcode='22023',message='action_proposal_type_invalid';end if;
  if coalesce(p_values->>'currency','')!~'^[A-Z]{3}$'then missing:=array_append(missing,'currency');end if;
  if coalesce(p_values->>'precision','')not in('exact','date','unknown')then missing:=array_append(missing,'precision');end if;
  if coalesce(btrim(p_values->>'note'),'')=''then missing:=array_append(missing,'note');end if;
  if(p_values->>'precision'='unknown')<>(p_values->>'occurred_at'is null)then missing:=array_append(missing,'occurred_at');elsif p_values->>'occurred_at'is not null and not isfinite((p_values->>'occurred_at')::timestamptz)then raise exception using errcode='22023',message='action_proposal_time_invalid';end if;
  begin u:=nullif(p_values->>'customer_id','')::uuid;exception when invalid_text_representation then raise exception using errcode='22023',message='action_proposal_customer_invalid';end;
  if u is not null then select jsonb_build_object('relation','e10_customers','id',c.id,'status',c.status,'revision',c.revision)into state from public.e10_customers c where c.organization_id=p_org and c.id=u;if state is null or state->>'status'<>'active'then missing:=array_append(missing,'customer_id');else refs:=refs||jsonb_build_array(state);end if;else missing:=array_append(missing,'customer_id');end if;
  if jsonb_typeof(p_values->'lines')is distinct from'array'or jsonb_array_length(p_values->'lines')not between 1 and 100 then missing:=array_append(missing,'lines');
  else for line in select value from jsonb_array_elements(p_values->'lines')loop n:=n+1;
   if jsonb_typeof(line)<>'object'or exists(select 1 from jsonb_object_keys(line)as supplied(key)where not(supplied.key=any(array['purchase_kind','sales_channel','location_id','source_session_reference','capture_source','source_connection_id','source_line_id','activity_observation_id','product_master_id','configuration_version_id','unique_item_id','break_session_id','break_slot_id','quantity','merchandise_gross','merchandise_discount','shipping_amount','tax_amount','raw_evidence'])))then raise exception using errcode='22023',message='action_proposal_line_unknown_key';end if;
   if exists(select 1 from jsonb_each(line)where key in('purchase_kind','sales_channel','source_session_reference','capture_source','source_connection_id','source_line_id')and jsonb_typeof(value)not in('string','null'))or line?'raw_evidence'and jsonb_typeof(line->'raw_evidence')not in('object','null')then raise exception using errcode='22023',message='action_proposal_line_type_invalid';end if;
   if coalesce(line->>'purchase_kind','')not in('retail','break','unclassified')then missing:=array_append(missing,format('lines[%s].purchase_kind',n));end if;
   if coalesce(line->>'capture_source','')not in('manual','import','native')then missing:=array_append(missing,format('lines[%s].capture_source',n));end if;
   if coalesce(btrim(line->>'source_line_id'),'')=''then missing:=array_append(missing,format('lines[%s].source_line_id',n));end if;
   if jsonb_typeof(line->'quantity')is distinct from'number'or(line->>'quantity')::numeric<=0 or(line->>'quantity')in('NaN','Infinity','-Infinity')then missing:=array_append(missing,format('lines[%s].quantity',n));end if;
   if jsonb_typeof(line->'merchandise_gross')is distinct from'number'or(line->>'merchandise_gross')::numeric<0 or(line->>'merchandise_gross')in('NaN','Infinity','-Infinity')then missing:=array_append(missing,format('lines[%s].merchandise_gross',n));end if;
   for k in select unnest(array['merchandise_discount','shipping_amount','tax_amount'])loop if line?k and jsonb_typeof(line->k)not in('number','null')then raise exception using errcode='22023',message='action_proposal_money_type_invalid';end if;if line->>k is not null and((line->>k)::numeric<0 or(line->>k)in('NaN','Infinity','-Infinity'))then raise exception using errcode='22023',message='action_proposal_money_invalid';end if;end loop;
   if line->>'merchandise_discount'is not null and(line->>'merchandise_discount')::numeric>(line->>'merchandise_gross')::numeric then raise exception using errcode='22023',message='action_proposal_discount_invalid';end if;
   for v in select key from jsonb_each(line)where key in('activity_observation_id','location_id','product_master_id','configuration_version_id','unique_item_id','break_session_id','break_slot_id')and jsonb_typeof(value)not in('string','null')loop raise exception using errcode='22023',message='action_proposal_reference_type_invalid';end loop;
   if nullif(line->>'activity_observation_id','')is not null then u:=(line->>'activity_observation_id')::uuid;select jsonb_build_object('relation','e10_customer_activity_observations','id',a.id,'source_kind',a.source_kind,'request_fingerprint',a.request_fingerprint,'effective_customer',e10.customer_activity_effective_customer(p_org,a.id))into state from public.e10_customer_activity_observations a where a.organization_id=p_org and a.id=u;if state is null or(state->>'effective_customer')is distinct from coalesce(p_values->>'customer_id','')then missing:=array_append(missing,format('lines[%s].activity_observation_id',n));else refs:=refs||jsonb_build_array(state);end if;end if;
   if line->>'capture_source'='native'and(nullif(line->>'activity_observation_id','')is null or state is null or state->>'relation'<>'e10_customer_activity_observations'or state->>'source_kind'<>'native')then missing:=array_append(missing,format('lines[%s].native_activity',n));end if;
   if nullif(line->>'location_id','')is not null then u:=(line->>'location_id')::uuid;select jsonb_build_object('relation','e10_locations','id',l.id,'status',l.status,'updated_at',l.updated_at)into state from public.e10_locations l where l.organization_id=p_org and l.id=u;if state is null then missing:=array_append(missing,format('lines[%s].location_id',n));else refs:=refs||jsonb_build_array(state);end if;end if;
   if nullif(line->>'product_master_id','')is not null then u:=(line->>'product_master_id')::uuid;select jsonb_build_object('relation','e10_product_masters','id',p.id,'status',p.status,'updated_at',p.updated_at)into state from public.e10_product_masters p where p.organization_id=p_org and p.id=u;if state is null then missing:=array_append(missing,format('lines[%s].product_master_id',n));else refs:=refs||jsonb_build_array(state);end if;end if;
   if nullif(line->>'configuration_version_id','')is not null then u:=(line->>'configuration_version_id')::uuid;select jsonb_build_object('relation','e10_product_configuration_versions','id',cv.id,'state',cv.state,'version_no',cv.version_no,'configuration_id',cv.configuration_id,'configuration_status',c.status,'configuration_updated_at',c.updated_at,'product_id',p.id,'product_status',p.status,'product_updated_at',p.updated_at)into state from public.e10_product_configuration_versions cv join public.e10_product_configurations c on c.organization_id=cv.organization_id and c.id=cv.configuration_id join public.e10_product_masters p on p.organization_id=c.organization_id and p.id=c.product_master_id where cv.organization_id=p_org and cv.id=u and(nullif(line->>'product_master_id','')is null or p.id=(line->>'product_master_id')::uuid);if state is null or state->>'state'<>'active'then missing:=array_append(missing,format('lines[%s].configuration_version_id',n));else refs:=refs||jsonb_build_array(state);end if;end if;
   if nullif(line->>'unique_item_id','')is not null then u:=(line->>'unique_item_id')::uuid;select jsonb_build_object('relation','e10_unique_items','id',i.id,'product_id',i.product_master_id,'configuration_version_id',i.configuration_version_id,'updated_at',i.updated_at)into state from public.e10_unique_items i where i.organization_id=p_org and i.id=u and(nullif(line->>'product_master_id','')is null or i.product_master_id=(line->>'product_master_id')::uuid)and(nullif(line->>'configuration_version_id','')is null or i.configuration_version_id=(line->>'configuration_version_id')::uuid);if state is null then missing:=array_append(missing,format('lines[%s].unique_item_id',n));else refs:=refs||jsonb_build_array(state);end if;end if;
   if nullif(line->>'break_session_id','')is not null then u:=(line->>'break_session_id')::uuid;select jsonb_build_object('relation','e10_break_sessions','id',s.id,'status',s.status,'ended_at',s.ended_at,'active_slot_id',s.active_slot_id)into state from public.e10_break_sessions s where s.organization_id=p_org and s.id=u;if state is null then missing:=array_append(missing,format('lines[%s].break_session_id',n));else refs:=refs||jsonb_build_array(state);end if;end if;
   if nullif(line->>'break_slot_id','')is not null then u:=(line->>'break_slot_id')::uuid;select jsonb_build_object('relation','e10_break_slots','id',s.id,'session_id',s.session_id,'state',s.state,'updated_at',s.updated_at,'native_sale_revision',s.native_sale_revision)into state from public.e10_break_slots s where s.organization_id=p_org and s.id=u and s.session_id=(line->>'break_session_id')::uuid;if state is null then missing:=array_append(missing,format('lines[%s].break_slot_id',n));else refs:=refs||jsonb_build_array(state);end if;end if;
   if coalesce(line->>'product_master_id',line->>'configuration_version_id',line->>'unique_item_id')is null then missing:=array_append(missing,format('lines[%s].product_identity',n));end if;
  end loop;end if;
 end if;
 select coalesce(array_agg(distinct x order by x),'{}')into missing from unnest(missing)x;
 refs:=refs||jsonb_build_array(jsonb_build_object('relation','proposal_source_references','value',p_source_references));
 return jsonb_build_object('values',p_values,'missing_fields',to_jsonb(missing),'reference_state',refs,'reference_fingerprint',encode(extensions.digest(convert_to(refs::text,'UTF8'),'sha256'),'hex'));
exception when invalid_text_representation or numeric_value_out_of_range then raise exception using errcode='22023',message='action_proposal_encoding_invalid';
end $$;

revoke all on function e10.x8b_capability(text,text),e10.x8b_validate_provenance(text,jsonb,jsonb,jsonb),e10.x8b_proposal_snapshot(uuid,text,jsonb,jsonb,jsonb) from public,anon,authenticated;
grant execute on function e10.x8b_capability(text,text),e10.x8b_validate_provenance(text,jsonb,jsonb,jsonb),e10.x8b_proposal_snapshot(uuid,text,jsonb,jsonb,jsonb) to service_role;
