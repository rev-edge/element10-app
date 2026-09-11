-- TA-X7e.0 guarded reviewed-evidence writer.

create function e10.inventory_episode_key(p_org uuid,p_item uuid,p_origin uuid)returns text
language plpgsql stable security definer set search_path=public as $$
declare o record;
begin
 select*into o from public.e10_current_inventory_lifecycle_events e where e.organization_id=p_org and e.unique_item_id=p_item and e.id=p_origin and e.event_type in('acquisition','receipt');
 if not found then raise exception using errcode='23514',message='inventory_disposition_origin_invalid';end if;
 return case when o.correlation_id is null then'event:'||o.id::text else'corr:'||o.correlation_id end;
end $$;
revoke all on function e10.inventory_episode_key(uuid,uuid,uuid)from public,anon,authenticated;
grant execute on function e10.inventory_episode_key(uuid,uuid,uuid)to service_role;

create function e10.inventory_episode_origin(p_org uuid,p_item uuid,p_origin uuid)returns uuid
language plpgsql stable security definer set search_path=public as $$
declare o record;a uuid;n integer;
begin
 select*into o from public.e10_current_inventory_lifecycle_events e where e.organization_id=p_org and e.unique_item_id=p_item and e.id=p_origin and e.event_type in('acquisition','receipt');
 if not found then raise exception using errcode='23514',message='inventory_disposition_origin_invalid';end if;
 if o.correlation_id is null then return o.id;end if;
 select(array_agg(e.id order by e.id))[1],count(*)into a,n from public.e10_current_inventory_lifecycle_events e where e.organization_id=p_org and e.unique_item_id=p_item and e.event_type='acquisition'and e.correlation_id=o.correlation_id;
 if n>1 then raise exception using errcode='23514',message='inventory_episode_correlation_ambiguous';end if;
 return case when n=1 then a else o.id end;
end $$;
revoke all on function e10.inventory_episode_origin(uuid,uuid,uuid)from public,anon,authenticated;
grant execute on function e10.inventory_episode_origin(uuid,uuid,uuid)to service_role;

create function e10.validate_inventory_reporting_evidence()returns trigger
language plpgsql security definer set search_path=public as $$
declare p record;v_item uuid;v_origin record;v_source_time timestamptz;v_source_precision text;
begin
 if new.recorded_at is null or not isfinite(new.recorded_at)then raise exception using errcode='23514',message='inventory_evidence_recorded_at_invalid';end if;
 if tg_table_name='e10_unique_item_grade_assessments'then
  if new.supersedes_assessment_id is null then
   if new.action<>'assert'or new.revision<>1 then raise exception using errcode='23514',message='inventory_evidence_root_revision_invalid';end if;
  else
   select*into p from public.e10_unique_item_grade_assessments where organization_id=new.organization_id and id=new.supersedes_assessment_id;
   if not found or p.assessment_key<>new.assessment_key or p.unique_item_id<>new.unique_item_id or new.revision<>p.revision+1 then raise exception using errcode='23514',message='inventory_evidence_successor_invalid';end if;
  end if;
 elsif tg_table_name='e10_catalog_population_snapshots'then
  if new.supersedes_snapshot_id is null then
   if new.action<>'assert'or new.revision<>1 then raise exception using errcode='23514',message='inventory_evidence_root_revision_invalid';end if;
  else
   select*into p from public.e10_catalog_population_snapshots where organization_id=new.organization_id and id=new.supersedes_snapshot_id;
   if not found or p.snapshot_key<>new.snapshot_key or p.catalog_variant_id<>new.catalog_variant_id or new.revision<>p.revision+1 then raise exception using errcode='23514',message='inventory_evidence_successor_invalid';end if;
  end if;
 elsif tg_table_name='e10_valuation_evidence'then
  if new.supersedes_evidence_id is null then
   if new.action<>'assert'or new.revision<>1 then raise exception using errcode='23514',message='inventory_evidence_root_revision_invalid';end if;
  else
   select*into p from public.e10_valuation_evidence where organization_id=new.organization_id and id=new.supersedes_evidence_id;
   if not found or p.evidence_key<>new.evidence_key or p.unique_item_id is distinct from new.unique_item_id or p.catalog_variant_id is distinct from new.catalog_variant_id or p.method<>new.method or p.method_version<>new.method_version or new.revision<>p.revision+1 then raise exception using errcode='23514',message='inventory_evidence_successor_invalid';end if;
  end if;
 else
  if new.supersedes_link_id is null then
   new.episode_key:=e10.inventory_episode_key(new.organization_id,new.unique_item_id,new.origin_event_id);
   new.episode_origin_event_id:=e10.inventory_episode_origin(new.organization_id,new.unique_item_id,new.origin_event_id);
   if new.action<>'assert'or new.revision<>1 then raise exception using errcode='23514',message='inventory_evidence_root_revision_invalid';end if;
  else
   select*into p from public.e10_inventory_disposition_links where organization_id=new.organization_id and id=new.supersedes_link_id;
   new.episode_key:=p.episode_key;new.episode_origin_event_id:=p.episode_origin_event_id;
   if not found or p.disposition_key<>new.disposition_key or p.unique_item_id<>new.unique_item_id or new.revision<>p.revision+1 then raise exception using errcode='23514',message='inventory_evidence_successor_invalid';end if;
  end if;
  if new.action='assert'then
   select e.* into v_origin from public.e10_current_inventory_lifecycle_events e
   where e.organization_id=new.organization_id and e.id=new.origin_event_id
     and e.unique_item_id=new.unique_item_id and e.event_type in('acquisition','receipt');
   if not found then raise exception using errcode='23514',message='inventory_disposition_origin_invalid';end if;
   if new.customer_transaction_id is not null and new.disposition_kind='sale'then
    select max(t.occurred_at),max(t.occurred_at_precision)into v_source_time,v_source_precision from public.e10_customer_transactions t join public.e10_customer_transaction_lines l on l.organization_id=t.organization_id and l.transaction_id=t.id where t.organization_id=new.organization_id and t.id=new.customer_transaction_id and l.unique_item_id=new.unique_item_id;
   elsif new.market_observation_id is not null and new.disposition_kind='sale'then
    select o.occurred_at,'exact'into v_source_time,v_source_precision from public.e10_current_market_observations o where o.organization_id=new.organization_id and o.id=new.market_observation_id and o.unique_item_id=new.unique_item_id and o.observation_kind='completed_sale'and o.source_kind in('manual','csv');
   elsif new.commercial_event_id is not null and new.disposition_kind in('return','disposal')then
    select e.occurred_at,e.occurred_at_precision into v_source_time,v_source_precision from public.e10_current_inventory_lifecycle_events e where e.organization_id=new.organization_id and e.id=new.commercial_event_id and e.event_type=case when new.disposition_kind='return'then'return'else'fulfillment'end and e.unique_item_id=new.unique_item_id;
   end if;
   if v_source_time is null or new.disposed_at is distinct from v_source_time or new.disposed_at_precision is distinct from v_source_precision or new.disposed_at<v_origin.occurred_at then raise exception using errcode='23514',message='inventory_disposition_source_invalid';end if;
  end if;
 end if;
 return new;
end $$;
revoke all on function e10.validate_inventory_reporting_evidence()from public,anon,authenticated;
grant execute on function e10.validate_inventory_reporting_evidence()to service_role;
create trigger e10_grade_assessment_insert_guard before insert on public.e10_unique_item_grade_assessments for each row execute function e10.validate_inventory_reporting_evidence();
create trigger e10_population_snapshot_insert_guard before insert on public.e10_catalog_population_snapshots for each row execute function e10.validate_inventory_reporting_evidence();
create trigger e10_valuation_evidence_insert_guard before insert on public.e10_valuation_evidence for each row execute function e10.validate_inventory_reporting_evidence();
create trigger e10_inventory_disposition_insert_guard before insert on public.e10_inventory_disposition_links for each row execute function e10.validate_inventory_reporting_evidence();

create function public.e10_org_review_inventory_evidence(
 p_org uuid,p_kind text,p_key uuid,p_expected_revision bigint,p_action text,p_payload jsonb,p_reason text,p_idempotency_key text
)returns jsonb language plpgsql security definer set search_path=public as $$
declare actor uuid:=auth.uid();k uuid:=coalesce(p_key,gen_random_uuid());prior record;replay record;rid uuid:=gen_random_uuid();fp text;out_id uuid;episode_origin uuid;episode_key_value text;
begin
 if actor is null or not exists(select 1 from public.e10_organizations where id=p_org and status='active')or not e10.is_org_member(p_org)or not e10.has_org_cap(p_org,'act.curate_market_analytics')then raise exception using errcode='42501',message='inventory_evidence_review_denied';end if;
 if p_org is null or p_kind is null or p_kind not in('grade_assessment','population_snapshot','valuation_evidence','disposition_link')or p_expected_revision is null or p_expected_revision<0 or p_action is null or p_action not in('assert','revoke')or p_payload is null or jsonb_typeof(p_payload)<>'object'or octet_length(p_payload::text)>65536 or p_reason is null or length(btrim(p_reason))not between 1 and 2000 or p_idempotency_key is null or length(btrim(p_idempotency_key))not between 1 and 500 then raise exception using errcode='22023',message='inventory_evidence_review_invalid';end if;
 fp:=md5(jsonb_build_object('v','inventory-evidence-v1','org',p_org,'kind',p_kind,'key',p_key,'expected',p_expected_revision,'action',p_action,'payload',p_payload,'reason',btrim(p_reason))::text);
 perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|inventory-evidence-idempotency|'||btrim(p_idempotency_key),0));
 if auth.uid()is distinct from actor or not exists(select 1 from public.e10_organizations where id=p_org and status='active')or not e10.is_org_member(p_org)or not e10.has_org_cap(p_org,'act.curate_market_analytics')then raise exception using errcode='42501',message='inventory_evidence_review_denied';end if;
 if p_kind='grade_assessment'then select id,request_fingerprint,assessment_key as evidence_key,revision into replay from public.e10_unique_item_grade_assessments where organization_id=p_org and idempotency_key=btrim(p_idempotency_key);
 elsif p_kind='population_snapshot'then select id,request_fingerprint,snapshot_key as evidence_key,revision into replay from public.e10_catalog_population_snapshots where organization_id=p_org and idempotency_key=btrim(p_idempotency_key);
 elsif p_kind='valuation_evidence'then select id,request_fingerprint,evidence_key,revision into replay from public.e10_valuation_evidence where organization_id=p_org and idempotency_key=btrim(p_idempotency_key);
 else select id,request_fingerprint,disposition_key as evidence_key,revision into replay from public.e10_inventory_disposition_links where organization_id=p_org and idempotency_key=btrim(p_idempotency_key);end if;
 if found then if replay.request_fingerprint<>fp then raise exception using errcode='22023',message='idempotency_key_mismatch';end if;return jsonb_build_object('ok',true,'replay',true,'kind',p_kind,'evidence_id',replay.id,'evidence_key',replay.evidence_key,'revision',replay.revision);end if;
 perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|inventory-evidence|'||p_kind||'|'||k::text,0));
 if p_kind='grade_assessment'then perform 1 from public.e10_unique_items where organization_id=p_org and id=(p_payload->>'unique_item_id')::uuid for key share;
 elsif p_kind='population_snapshot'then perform 1 from public.e10_catalog_variants where id=(p_payload->>'catalog_variant_id')::uuid for key share;
 elsif p_kind='valuation_evidence'then
  if p_payload->>'unique_item_id'is not null then perform 1 from public.e10_unique_items where organization_id=p_org and id=(p_payload->>'unique_item_id')::uuid for key share;else perform 1 from public.e10_catalog_variants where id=(p_payload->>'catalog_variant_id')::uuid for key share;end if;
 else
  perform 1 from public.e10_unique_items where organization_id=p_org and id=(p_payload->>'unique_item_id')::uuid for key share;
  perform 1 from public.e10_commercial_events where organization_id=p_org and id=(p_payload->>'origin_event_id')::uuid for key share;
  if p_payload->>'customer_transaction_id'is not null then
   perform 1 from public.e10_customer_transactions where organization_id=p_org and id=(p_payload->>'customer_transaction_id')::uuid for key share;
   perform 1 from public.e10_customer_transaction_lines where organization_id=p_org and transaction_id=(p_payload->>'customer_transaction_id')::uuid and unique_item_id=(p_payload->>'unique_item_id')::uuid for key share;
  elsif p_payload->>'market_observation_id'is not null then perform 1 from public.e10_market_observations where organization_id=p_org and id=(p_payload->>'market_observation_id')::uuid for key share;
  elsif p_payload->>'commercial_event_id'is not null then perform 1 from public.e10_commercial_events where organization_id=p_org and id=(p_payload->>'commercial_event_id')::uuid for key share;end if;
  if p_key is null then
   episode_key_value:=e10.inventory_episode_key(p_org,(p_payload->>'unique_item_id')::uuid,(p_payload->>'origin_event_id')::uuid);
   episode_origin:=e10.inventory_episode_origin(p_org,(p_payload->>'unique_item_id')::uuid,(p_payload->>'origin_event_id')::uuid);
  else
   select d.episode_key,d.episode_origin_event_id into episode_key_value,episode_origin from public.e10_inventory_disposition_links d where d.organization_id=p_org and d.disposition_key=p_key and not exists(select 1 from public.e10_inventory_disposition_links n where n.organization_id=d.organization_id and n.supersedes_link_id=d.id);
   if not found then raise exception using errcode='22023',message='inventory_evidence_key_invalid';end if;
  end if;
  perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|inventory-episode|'||(p_payload->>'unique_item_id')||'|'||episode_key_value,0));
 end if;
 if auth.uid()is distinct from actor or not exists(select 1 from public.e10_organizations where id=p_org and status='active')or not e10.is_org_member(p_org)or not e10.has_org_cap(p_org,'act.curate_market_analytics')then raise exception using errcode='42501',message='inventory_evidence_review_denied';end if;

 if p_kind='grade_assessment'then
  select*into prior from public.e10_unique_item_grade_assessments d where d.organization_id=p_org and d.assessment_key=k and not exists(select 1 from public.e10_unique_item_grade_assessments n where n.organization_id=d.organization_id and n.supersedes_assessment_id=d.id)for update;
  if p_key is null then if found or p_expected_revision<>0 then raise exception using errcode='22023',message='inventory_evidence_transition_invalid';end if;else if not found then raise exception using errcode='22023',message='inventory_evidence_key_invalid';end if;if prior.revision<>p_expected_revision then raise exception using errcode='40001',message='inventory_evidence_revision_conflict';end if;end if;
  if auth.uid()is distinct from actor or not exists(select 1 from public.e10_organizations where id=p_org and status='active')or not e10.is_org_member(p_org)or not e10.has_org_cap(p_org,'act.curate_market_analytics')then raise exception using errcode='42501',message='inventory_evidence_review_denied';end if;
  insert into public.e10_unique_item_grade_assessments(id,organization_id,assessment_key,unique_item_id,revision,action,condition_state,grader_code,grade_label,grade_qualifier,autograph_designation,assessed_at,assessed_at_precision,source_kind,source_connection_id,source_reference,method,method_version,review_status,supersedes_assessment_id,reason,evidence,idempotency_key,request_fingerprint,reviewed_by)
  values(rid,p_org,k,(p_payload->>'unique_item_id')::uuid,p_expected_revision+1,p_action,p_payload->>'condition_state',p_payload->>'grader_code',p_payload->>'grade_label',p_payload->>'grade_qualifier',p_payload->>'autograph_designation',(p_payload->>'assessed_at')::timestamptz,p_payload->>'assessed_at_precision',p_payload->>'source_kind',p_payload->>'source_connection_id',p_payload->>'source_reference',p_payload->>'method',p_payload->>'method_version',p_payload->>'review_status',prior.id,btrim(p_reason),coalesce(p_payload->'evidence','{}'),btrim(p_idempotency_key),fp,actor)returning id into out_id;
 elsif p_kind='population_snapshot'then
  select*into prior from public.e10_catalog_population_snapshots d where d.organization_id=p_org and d.snapshot_key=k and not exists(select 1 from public.e10_catalog_population_snapshots n where n.organization_id=d.organization_id and n.supersedes_snapshot_id=d.id)for update;
  if p_key is null then if found or p_expected_revision<>0 then raise exception using errcode='22023',message='inventory_evidence_transition_invalid';end if;else if not found then raise exception using errcode='22023',message='inventory_evidence_key_invalid';end if;if prior.revision<>p_expected_revision then raise exception using errcode='40001',message='inventory_evidence_revision_conflict';end if;end if;
  if auth.uid()is distinct from actor or not exists(select 1 from public.e10_organizations where id=p_org and status='active')or not e10.is_org_member(p_org)or not e10.has_org_cap(p_org,'act.curate_market_analytics')then raise exception using errcode='42501',message='inventory_evidence_review_denied';end if;
  insert into public.e10_catalog_population_snapshots(id,organization_id,snapshot_key,catalog_variant_id,revision,action,condition_state,grader_code,grade_label,grade_qualifier,autograph_designation,population_count,population_scope,observed_at,observed_at_precision,source_kind,source_connection_id,source_reference,method,method_version,review_status,supersedes_snapshot_id,reason,evidence,idempotency_key,request_fingerprint,reviewed_by)
  values(rid,p_org,k,(p_payload->>'catalog_variant_id')::uuid,p_expected_revision+1,p_action,p_payload->>'condition_state',p_payload->>'grader_code',p_payload->>'grade_label',p_payload->>'grade_qualifier',p_payload->>'autograph_designation',(p_payload->>'population_count')::bigint,p_payload->>'population_scope',(p_payload->>'observed_at')::timestamptz,p_payload->>'observed_at_precision',p_payload->>'source_kind',p_payload->>'source_connection_id',p_payload->>'source_reference',p_payload->>'method',p_payload->>'method_version',p_payload->>'review_status',prior.id,btrim(p_reason),coalesce(p_payload->'evidence','{}'),btrim(p_idempotency_key),fp,actor)returning id into out_id;
 elsif p_kind='valuation_evidence'then
  select*into prior from public.e10_valuation_evidence d where d.organization_id=p_org and d.evidence_key=k and not exists(select 1 from public.e10_valuation_evidence n where n.organization_id=d.organization_id and n.supersedes_evidence_id=d.id)for update;
  if p_key is null then if found or p_expected_revision<>0 then raise exception using errcode='22023',message='inventory_evidence_transition_invalid';end if;else if not found then raise exception using errcode='22023',message='inventory_evidence_key_invalid';end if;if prior.revision<>p_expected_revision then raise exception using errcode='40001',message='inventory_evidence_revision_conflict';end if;end if;
  if auth.uid()is distinct from actor or not exists(select 1 from public.e10_organizations where id=p_org and status='active')or not e10.is_org_member(p_org)or not e10.has_org_cap(p_org,'act.curate_market_analytics')then raise exception using errcode='42501',message='inventory_evidence_review_denied';end if;
  insert into public.e10_valuation_evidence(id,organization_id,evidence_key,revision,action,unique_item_id,catalog_variant_id,condition_state,grader_code,grade_label,grade_qualifier,autograph_designation,method,method_version,currency,amount,observed_at,observed_at_precision,source_kind,source_connection_id,source_reference,review_status,supersedes_evidence_id,reason,input_evidence,idempotency_key,request_fingerprint,reviewed_by)
  values(rid,p_org,k,p_expected_revision+1,p_action,(p_payload->>'unique_item_id')::uuid,(p_payload->>'catalog_variant_id')::uuid,p_payload->>'condition_state',p_payload->>'grader_code',p_payload->>'grade_label',p_payload->>'grade_qualifier',p_payload->>'autograph_designation',p_payload->>'method',p_payload->>'method_version',p_payload->>'currency',(p_payload->>'amount')::numeric,(p_payload->>'observed_at')::timestamptz,p_payload->>'observed_at_precision',p_payload->>'source_kind',p_payload->>'source_connection_id',p_payload->>'source_reference',p_payload->>'review_status',prior.id,btrim(p_reason),coalesce(p_payload->'input_evidence','{}'),btrim(p_idempotency_key),fp,actor)returning id into out_id;
 else
  select*into prior from public.e10_inventory_disposition_links d where d.organization_id=p_org and d.disposition_key=k and not exists(select 1 from public.e10_inventory_disposition_links n where n.organization_id=d.organization_id and n.supersedes_link_id=d.id)for update;
  if p_key is null then if found or p_expected_revision<>0 then raise exception using errcode='22023',message='inventory_evidence_transition_invalid';end if;else if not found then raise exception using errcode='22023',message='inventory_evidence_key_invalid';end if;if prior.revision<>p_expected_revision then raise exception using errcode='40001',message='inventory_evidence_revision_conflict';end if;end if;
  if auth.uid()is distinct from actor or not exists(select 1 from public.e10_organizations where id=p_org and status='active')or not e10.is_org_member(p_org)or not e10.has_org_cap(p_org,'act.curate_market_analytics')then raise exception using errcode='42501',message='inventory_evidence_review_denied';end if;
  insert into public.e10_inventory_disposition_links(id,organization_id,disposition_key,unique_item_id,origin_event_id,episode_origin_event_id,episode_key,revision,action,disposition_kind,disposed_at,disposed_at_precision,customer_transaction_id,market_observation_id,commercial_event_id,supersedes_link_id,reason,evidence,idempotency_key,request_fingerprint,reviewed_by)
  values(rid,p_org,k,(p_payload->>'unique_item_id')::uuid,case when p_action='revoke'then prior.origin_event_id else(p_payload->>'origin_event_id')::uuid end,episode_origin,episode_key_value,p_expected_revision+1,p_action,p_payload->>'disposition_kind',(p_payload->>'disposed_at')::timestamptz,case when p_action='revoke'then'unknown'else p_payload->>'disposed_at_precision'end,(p_payload->>'customer_transaction_id')::uuid,(p_payload->>'market_observation_id')::uuid,(p_payload->>'commercial_event_id')::uuid,prior.id,btrim(p_reason),coalesce(p_payload->'evidence','{}'),btrim(p_idempotency_key),fp,actor)returning id into out_id;
 end if;
 return jsonb_build_object('ok',true,'replay',false,'kind',p_kind,'evidence_id',out_id,'evidence_key',k,'revision',p_expected_revision+1);
exception when invalid_text_representation or datetime_field_overflow then raise exception using errcode='22023',message='inventory_evidence_payload_invalid';
end $$;
revoke all on function public.e10_org_review_inventory_evidence(uuid,text,uuid,bigint,text,jsonb,text,text)from public,anon;
grant execute on function public.e10_org_review_inventory_evidence(uuid,text,uuid,bigint,text,jsonb,text,text)to authenticated,service_role;
comment on function public.e10_org_review_inventory_evidence(uuid,text,uuid,bigint,text,jsonb,text,text)is'Reviews immutable grading, population, valuation, or local-disposition reporting evidence. Does not mutate inventory or accounting.';
