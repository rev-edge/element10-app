-- TA-X8b.6 one canonical reference-lock order across both proposal operations.

create or replace function e10.x8b_lock_references(p_org uuid,p_operation text,p_values jsonb)returns void
language plpgsql security definer set search_path=public as $$
declare x uuid;begin
 -- Global relation order: activity, customer, location, product master,
 -- configuration, configuration version, unique item, session, slot, supplier.
 if p_operation='customer_transaction.create_draft'then
  for x in select distinct(value->>'activity_observation_id')::uuid from jsonb_array_elements(p_values->'lines')where value->>'activity_observation_id'is not null order by 1 loop perform 1 from public.e10_customer_activity_observations where organization_id=p_org and id=x for update;end loop;
  if p_values->>'customer_id'is not null then perform 1 from public.e10_customers where organization_id=p_org and id=(p_values->>'customer_id')::uuid for update;end if;
 end if;
 if p_operation='purchase_order.create'then
  perform 1 from public.e10_locations where organization_id=p_org and id=(p_values->>'destination_location_id')::uuid for update;
 else
  for x in select distinct(value->>'location_id')::uuid from jsonb_array_elements(p_values->'lines')where value->>'location_id'is not null order by 1 loop perform 1 from public.e10_locations where organization_id=p_org and id=x for update;end loop;
 end if;
 if p_operation='purchase_order.create'then
  for x in select distinct p.id from jsonb_array_elements(p_values->'lines')l join public.e10_product_configuration_versions v on v.organization_id=p_org and v.id=(l->>'configuration_version_id')::uuid join public.e10_product_configurations c on c.organization_id=v.organization_id and c.id=v.configuration_id join public.e10_product_masters p on p.organization_id=c.organization_id and p.id=c.product_master_id order by 1 loop perform 1 from public.e10_product_masters where organization_id=p_org and id=x for update;end loop;
 else
  for x in select distinct id from(select(value->>'product_master_id')::uuid id from jsonb_array_elements(p_values->'lines')where value->>'product_master_id'is not null union select p.id from jsonb_array_elements(p_values->'lines')l join public.e10_product_configuration_versions v on v.organization_id=p_org and v.id=(l->>'configuration_version_id')::uuid join public.e10_product_configurations c on c.organization_id=v.organization_id and c.id=v.configuration_id join public.e10_product_masters p on p.organization_id=c.organization_id and p.id=c.product_master_id)s order by 1 loop perform 1 from public.e10_product_masters where organization_id=p_org and id=x for update;end loop;
 end if;
 for x in select distinct c.id from jsonb_array_elements(p_values->'lines')l join public.e10_product_configuration_versions v on v.organization_id=p_org and v.id=(l->>'configuration_version_id')::uuid join public.e10_product_configurations c on c.organization_id=v.organization_id and c.id=v.configuration_id order by 1 loop perform 1 from public.e10_product_configurations where organization_id=p_org and id=x for update;end loop;
 for x in select distinct(value->>'configuration_version_id')::uuid from jsonb_array_elements(p_values->'lines')where value->>'configuration_version_id'is not null order by 1 loop perform 1 from public.e10_product_configuration_versions where organization_id=p_org and id=x for update;end loop;
 if p_operation='customer_transaction.create_draft'then
  for x in select distinct(value->>'unique_item_id')::uuid from jsonb_array_elements(p_values->'lines')where value->>'unique_item_id'is not null order by 1 loop perform 1 from public.e10_unique_items where organization_id=p_org and id=x for update;end loop;
  for x in select distinct(value->>'break_session_id')::uuid from jsonb_array_elements(p_values->'lines')where value->>'break_session_id'is not null order by 1 loop perform 1 from public.e10_break_sessions where organization_id=p_org and id=x for update;end loop;
  for x in select distinct(value->>'break_slot_id')::uuid from jsonb_array_elements(p_values->'lines')where value->>'break_slot_id'is not null order by 1 loop perform 1 from public.e10_break_slots where organization_id=p_org and id=x for update;end loop;
 else
  perform 1 from public.e10_suppliers where organization_id=p_org and id=(p_values->>'supplier_id')::uuid for update;
 end if;
end $$;
revoke all on function e10.x8b_lock_references(uuid,text,jsonb)from public,anon,authenticated;
grant execute on function e10.x8b_lock_references(uuid,text,jsonb)to service_role;
