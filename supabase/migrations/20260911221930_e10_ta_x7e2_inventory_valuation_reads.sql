-- TA-X7e.2 grade-aware evidence and two-cutoff valuation coverage.

create function e10.inventory_grade_at(p_org uuid,p_item uuid,p_cutoff timestamptz)
returns table(condition_state text,grader_code text,grade_label text,grade_qualifier text,autograph_designation text,assessment_id uuid,applicability_key text)
language sql stable security definer set search_path=public as $$
 select g.condition_state,g.grader_code,g.grade_label,g.grade_qualifier,g.autograph_designation,g.id,
  concat_ws('|',g.condition_state,g.grader_code,g.grade_label,coalesce(g.grade_qualifier,''),coalesce(g.autograph_designation,''))
 from public.e10_current_unique_item_grade_assessments g
 where g.organization_id=p_org and g.unique_item_id=p_item and g.assessed_at<=p_cutoff
 order by g.assessed_at desc,g.recorded_at desc,g.source_kind,g.id desc limit 1
$$;

create function e10.inventory_holdings_at(p_org uuid,p_cutoff timestamptz)
returns table(unique_item_id uuid,catalog_variant_id uuid,episode_key text,origin_event_id uuid,origin_at timestamptz,origin_recorded_at timestamptz,holding_evidence text)
language sql stable security definer set search_path=public as $$
 with primary_origins as(
  select e.*from public.e10_current_inventory_lifecycle_events e
  where e.organization_id=p_org and e.occurred_at<=p_cutoff and(
   e.event_type='acquisition'and not exists(select 1 from public.e10_current_inventory_lifecycle_events a where a.organization_id=e.organization_id and a.unique_item_id=e.unique_item_id and a.event_type='acquisition'and a.occurred_at<=p_cutoff and a.episode_key=e.episode_key and a.id<>e.id)or e.event_type='receipt'and not exists(
    select 1 from public.e10_current_inventory_lifecycle_events a where a.organization_id=e.organization_id
     and a.unique_item_id=e.unique_item_id and a.event_type='acquisition'and a.occurred_at<=p_cutoff
     and a.episode_key=e.episode_key))
 ),eligible_dispositions as materialized(
  select d.*from public.e10_current_inventory_dispositions d where d.organization_id=p_org and d.disposed_at<=p_cutoff
   and not(d.source_basis='trusted_posted_transaction'and exists(select 1 from public.e10_current_inventory_dispositions r where r.organization_id=d.organization_id and r.unique_item_id=d.unique_item_id and r.episode_key=d.episode_key and r.source_basis='reviewed_link'and r.disposed_at<=p_cutoff))
 ),unresolved_items as materialized(
  select distinct d.unique_item_id from eligible_dispositions d where not exists(select 1 from primary_origins o where o.unique_item_id=d.unique_item_id and o.episode_key=d.episode_key)
 ),origins as(
  select e.unique_item_id,e.episode_key,e.id,e.occurred_at,e.recorded_at,d.disposition_count,u.unique_item_id is not null unresolved_finality,
   row_number()over(partition by e.unique_item_id order by e.occurred_at desc,e.recorded_at desc,e.id desc)rn,
   count(*)over(partition by e.unique_item_id)open_count
  from primary_origins e cross join lateral(select count(*)disposition_count from eligible_dispositions d where d.unique_item_id=e.unique_item_id and d.episode_key=e.episode_key)d
  left join unresolved_items u on u.unique_item_id=e.unique_item_id
  where d.disposition_count<>1 or u.unique_item_id is not null
 ),known as(
  select o.unique_item_id,o.episode_key,o.id origin_event_id,o.occurred_at origin_at,o.recorded_at origin_recorded_at,case when o.unresolved_finality or o.disposition_count>1 then'episode_finality_conflict'when o.open_count=1 then'episode'else'episode_ambiguous'end evidence
  from origins o where o.rn=1
 ),record_only as(
  select u.id,null::text,null::uuid,null::timestamptz,null::timestamptz,'record_only'
  from public.e10_unique_items u where u.organization_id=p_org and u.created_at<=p_cutoff
   and not exists(select 1 from origins o where o.unique_item_id=u.id)
   and not exists(select 1 from public.e10_current_inventory_dispositions d where d.organization_id=p_org and d.unique_item_id=u.id and d.disposed_at<=p_cutoff)
 )
 select h.unique_item_id,u.catalog_variant_id,h.episode_key,h.origin_event_id,h.origin_at,h.origin_recorded_at,h.evidence from(select*from known union all select*from record_only)h
 join public.e10_unique_items u on u.organization_id=p_org and u.id=h.unique_item_id
$$;

create function e10.inventory_estimate_at(p_org uuid,p_item uuid,p_variant uuid,p_cutoff timestamptz,p_freshness interval,p_method text,p_method_version text,p_currency text)
returns table(evidence_id uuid,amount numeric,observed_at timestamptz,recorded_at timestamptz,source_kind text,source_reference text,selected_basis text,applicability_key text)
language sql stable security definer set search_path=public as $$
 with grade as(select*from e10.inventory_grade_at(p_org,p_item,p_cutoff)),eligible as(
  select v.*,case when v.unique_item_id is not null then'copy'else'variant'end basis
  from public.e10_current_valuation_evidence v left join grade g on true
  where v.organization_id=p_org and(v.unique_item_id=p_item or v.unique_item_id is null and v.catalog_variant_id=p_variant)
   and v.method=p_method and v.method_version=p_method_version and v.currency=p_currency
   and v.observed_at<=p_cutoff and v.observed_at>=p_cutoff-p_freshness
   and(v.condition_state='raw'and g.condition_state='raw'and v.autograph_designation is not distinct from g.autograph_designation
    or v.condition_state='graded'and g.condition_state='graded'and v.grader_code=g.grader_code and v.grade_label=g.grade_label
      and v.grade_qualifier is not distinct from g.grade_qualifier and v.autograph_designation is not distinct from g.autograph_designation)
 )
 select e.id,e.amount,e.observed_at,e.recorded_at,e.source_kind,e.source_reference,e.basis,
  concat_ws('|',e.condition_state,e.grader_code,e.grade_label,coalesce(e.grade_qualifier,''),coalesce(e.autograph_designation,'')) from eligible e
 order by(e.unique_item_id is not null)desc,e.observed_at desc,e.recorded_at desc,e.source_kind,e.id desc limit 1
$$;

create function e10.inventory_population_at(p_org uuid,p_variant uuid,p_item uuid,p_cutoff timestamptz)
returns table(snapshot_id uuid,population_count bigint,observed_at timestamptz,source_kind text,source_reference text,applicability_key text,population_scope text)
language sql stable security definer set search_path=public as $$
 with grade as(select*from e10.inventory_grade_at(p_org,p_item,p_cutoff))
 select p.id,p.population_count,p.observed_at,p.source_kind,p.source_reference,
  concat_ws('|',p.condition_state,p.grader_code,p.grade_label,coalesce(p.grade_qualifier,''),coalesce(p.autograph_designation,'')),p.population_scope
 from public.e10_current_catalog_population_snapshots p left join grade g on true
 where p.organization_id=p_org and p.catalog_variant_id=p_variant and p.observed_at<=p_cutoff
  and(p.condition_state='raw'and g.condition_state='raw'and p.autograph_designation is not distinct from g.autograph_designation
   or p.condition_state='graded'and g.condition_state='graded'and p.grader_code=g.grader_code and p.grade_label=g.grade_label
    and p.grade_qualifier is not distinct from g.grade_qualifier and p.autograph_designation is not distinct from g.autograph_designation)
 order by p.observed_at desc,p.recorded_at desc,p.source_kind,p.id desc limit 1
$$;

revoke all on function e10.inventory_grade_at(uuid,uuid,timestamptz),e10.inventory_holdings_at(uuid,timestamptz),e10.inventory_estimate_at(uuid,uuid,uuid,timestamptz,interval,text,text,text),e10.inventory_population_at(uuid,uuid,uuid,timestamptz)from public,anon,authenticated;
grant execute on function e10.inventory_grade_at(uuid,uuid,timestamptz),e10.inventory_holdings_at(uuid,timestamptz),e10.inventory_estimate_at(uuid,uuid,uuid,timestamptz,interval,text,text,text),e10.inventory_population_at(uuid,uuid,uuid,timestamptz)to service_role;

create function public.e10_org_unique_item_evidence(p_org uuid,p_unique_item_id uuid,p_as_of timestamptz,p_limit integer default 50,p_cursor text default null)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare actor uuid:=auth.uid();rev bigint;fp text;cur jsonb;after_recorded timestamptz;after_id uuid;items jsonb;has_more boolean;next_cursor text;last_recorded timestamptz;last_id uuid;total integer;
begin
 if actor is null or p_org is null or p_unique_item_id is null or p_as_of is null or not isfinite(p_as_of)or p_limit is null or p_limit not between 1 and 100 or not exists(select 1 from public.e10_organizations where id=p_org and status='active')or not e10.is_org_member(p_org)or not e10.has_org_cap(p_org,'act.view_market_analytics')or not exists(select 1 from public.e10_unique_items where organization_id=p_org and id=p_unique_item_id)then raise exception using errcode='42501',message='inventory_evidence_read_denied';end if;
 select revision into rev from public.e10_inventory_reporting_revisions where organization_id=p_org;
 fp:=encode(sha256(convert_to(jsonb_build_object('v','inventory-item-evidence-v1','org',p_org,'actor',actor,'item',p_unique_item_id,'as_of',extract(epoch from p_as_of),'revision',rev)::text,'UTF8')),'hex');
 if p_cursor is not null then cur:=e10.inventory_cursor_decode(p_org,p_cursor);if cur->>'fingerprint'<>fp or(cur->>'actor')::uuid<>actor or(cur->>'revision')::bigint<>rev then raise exception using errcode='40001',message='inventory_cursor_stale_or_foreign';end if;after_recorded:=(cur->>'recorded_at')::timestamptz;after_id:=(cur->>'id')::uuid;end if;
 with u as(select catalog_variant_id from public.e10_unique_items where organization_id=p_org and id=p_unique_item_id),all_evidence as(
  select'grade'::text kind,g.id,g.recorded_at,jsonb_build_object('assessment_key',g.assessment_key,'revision',g.revision,'action',g.action,'supersedes_id',g.supersedes_assessment_id,'current',not exists(select 1 from public.e10_unique_item_grade_assessments n where n.organization_id=g.organization_id and n.supersedes_assessment_id=g.id),'applicability_status',case when exists(select 1 from e10.inventory_grade_at(p_org,p_unique_item_id,p_as_of)a where a.assessment_id=g.id)then'applicable'when g.action='revoke'or g.review_status<>'reviewed'or exists(select 1 from public.e10_unique_item_grade_assessments n where n.organization_id=g.organization_id and n.supersedes_assessment_id=g.id)then'superseded_or_ineligible'when g.assessed_at is null then'time_unknown'else'not_selected_at_cutoff'end,'reason',g.reason,'condition_state',g.condition_state,'grader_code',g.grader_code,'grade_label',g.grade_label,'grade_qualifier',g.grade_qualifier,'autograph_designation',g.autograph_designation,'assessed_at',g.assessed_at,'assessed_at_precision',g.assessed_at_precision,'source_kind',g.source_kind,'source_reference',g.source_reference,'method',g.method,'method_version',g.method_version,'review_status',g.review_status)body from public.e10_unique_item_grade_assessments g where g.organization_id=p_org and g.unique_item_id=p_unique_item_id and(g.action='revoke'or g.assessed_at<=p_as_of)
  union all select'valuation',v.id,v.recorded_at,jsonb_build_object('evidence_key',v.evidence_key,'revision',v.revision,'action',v.action,'supersedes_id',v.supersedes_evidence_id,'current',not exists(select 1 from public.e10_valuation_evidence n where n.organization_id=v.organization_id and n.supersedes_evidence_id=v.id),'applicability_status',case when v.action='revoke'or v.review_status<>'reviewed'or exists(select 1 from public.e10_valuation_evidence n where n.organization_id=v.organization_id and n.supersedes_evidence_id=v.id)then'superseded_or_ineligible'when not exists(select 1 from e10.inventory_grade_at(p_org,p_unique_item_id,p_as_of))then'condition_unknown'when exists(select 1 from e10.inventory_grade_at(p_org,p_unique_item_id,p_as_of)g where v.condition_state=g.condition_state and v.grader_code is not distinct from g.grader_code and v.grade_label is not distinct from g.grade_label and v.grade_qualifier is not distinct from g.grade_qualifier and v.autograph_designation is not distinct from g.autograph_designation)then'applicable'else'condition_mismatch'end,'reason',v.reason,'condition_state',v.condition_state,'grader_code',v.grader_code,'grade_label',v.grade_label,'grade_qualifier',v.grade_qualifier,'autograph_designation',v.autograph_designation,'method',v.method,'method_version',v.method_version,'currency',v.currency,'amount',v.amount,'observed_at',v.observed_at,'source_kind',v.source_kind,'source_reference',v.source_reference,'review_status',v.review_status,'target',case when v.unique_item_id is null then'variant'else'copy'end)from public.e10_valuation_evidence v,u where v.organization_id=p_org and(v.unique_item_id=p_unique_item_id or v.unique_item_id is null and v.catalog_variant_id=u.catalog_variant_id)and(v.action='revoke'or v.observed_at<=p_as_of)
  union all select'population',p.id,p.recorded_at,jsonb_build_object('snapshot_key',p.snapshot_key,'revision',p.revision,'action',p.action,'supersedes_id',p.supersedes_snapshot_id,'current',not exists(select 1 from public.e10_catalog_population_snapshots n where n.organization_id=p.organization_id and n.supersedes_snapshot_id=p.id),'applicability_status',case when p.action='revoke'or p.review_status<>'reviewed'or exists(select 1 from public.e10_catalog_population_snapshots n where n.organization_id=p.organization_id and n.supersedes_snapshot_id=p.id)then'superseded_or_ineligible'when not exists(select 1 from e10.inventory_grade_at(p_org,p_unique_item_id,p_as_of))then'condition_unknown'when exists(select 1 from e10.inventory_grade_at(p_org,p_unique_item_id,p_as_of)g where p.condition_state=g.condition_state and p.grader_code is not distinct from g.grader_code and p.grade_label is not distinct from g.grade_label and p.grade_qualifier is not distinct from g.grade_qualifier and p.autograph_designation is not distinct from g.autograph_designation)then'applicable'else'condition_mismatch'end,'reason',p.reason,'condition_state',p.condition_state,'grader_code',p.grader_code,'grade_label',p.grade_label,'grade_qualifier',p.grade_qualifier,'autograph_designation',p.autograph_designation,'population_count',p.population_count,'population_scope',p.population_scope,'observed_at',p.observed_at,'source_kind',p.source_kind,'source_reference',p.source_reference,'method',p.method,'method_version',p.method_version,'review_status',p.review_status)from public.e10_catalog_population_snapshots p,u where p.organization_id=p_org and p.catalog_variant_id=u.catalog_variant_id and(p.action='revoke'or p.observed_at<=p_as_of)
 ),ranked as(select e.*,count(*)over()full_count from all_evidence e),page as(select*from ranked where after_recorded is null or(recorded_at,id)<(after_recorded,after_id)order by recorded_at desc,id desc limit p_limit+1),shown as(select*from page order by recorded_at desc,id desc limit p_limit)
 select coalesce((select max(full_count)from page),0),(select count(*)from page)>p_limit,coalesce(jsonb_agg(jsonb_build_object('kind',kind,'id',id,'recorded_at',recorded_at,'data',body)order by recorded_at desc,id desc),'[]'),(select recorded_at from shown order by recorded_at,id limit 1),(select id from shown order by recorded_at,id limit 1)
 into total,has_more,items,last_recorded,last_id from shown;
 if has_more then next_cursor:=e10.inventory_cursor_encode(p_org,jsonb_build_object('fingerprint',fp,'actor',actor,'revision',rev,'recorded_at',last_recorded,'id',last_id));end if;
 return jsonb_build_object('metric_version','inventory-item-evidence-v1','organization_revision',rev,'as_of',p_as_of,'total_count',total,'items',items,'next_cursor',next_cursor);
end $$;

create function public.e10_org_inventory_valuation_coverage(p_org uuid,p_method text,p_method_version text,p_currency text,p_closing_cutoff timestamptz,p_opening_cutoff timestamptz default null,p_freshness_days integer default 365,p_limit integer default 100,p_cursor text default null)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare actor uuid:=auth.uid();rev bigint;fp text;cur jsonb;after_item uuid;can_cost boolean;summary jsonb;items jsonb;has_more boolean;next_cursor text;last_item uuid;
begin
 if actor is null or p_org is null or p_method is null or length(btrim(p_method))not between 1 and 100 or p_method_version is null or length(btrim(p_method_version))not between 1 and 100 or p_currency is null or p_currency!~'^[A-Z]{3}$'or p_closing_cutoff is null or not isfinite(p_closing_cutoff)or p_opening_cutoff is not null and(not isfinite(p_opening_cutoff)or p_opening_cutoff>=p_closing_cutoff)or p_freshness_days is null or p_freshness_days not between 1 and 3650 or p_limit is null or p_limit not between 1 and 200 or not exists(select 1 from public.e10_organizations where id=p_org and status='active')or not e10.is_org_member(p_org)or not e10.has_org_cap(p_org,'act.view_market_analytics')then raise exception using errcode='42501',message='inventory_valuation_read_denied';end if;
 can_cost:=e10.has_org_cap(p_org,'financial.actual_cost.read');select revision into rev from public.e10_inventory_reporting_revisions where organization_id=p_org;
 fp:=encode(sha256(convert_to(jsonb_build_object('v','inventory-valuation-v1','org',p_org,'actor',actor,'method',btrim(p_method),'method_version',btrim(p_method_version),'currency',p_currency,'closing',extract(epoch from p_closing_cutoff),'opening',extract(epoch from p_opening_cutoff),'freshness_days',p_freshness_days,'revision',rev)::text,'UTF8')),'hex');
 if p_cursor is not null then cur:=e10.inventory_cursor_decode(p_org,p_cursor);if cur->>'fingerprint'<>fp or(cur->>'actor')::uuid<>actor or(cur->>'revision')::bigint<>rev then raise exception using errcode='40001',message='inventory_cursor_stale_or_foreign';end if;after_item:=(cur->>'unique_item_id')::uuid;end if;
 with close_h as materialized(select*from e10.inventory_holdings_at(p_org,p_closing_cutoff)),open_h as materialized(select*from e10.inventory_holdings_at(p_org,p_opening_cutoff)where p_opening_cutoff is not null),all_ids as materialized(select unique_item_id from close_h union select unique_item_id from open_h),facts as materialized(
  select i.unique_item_id,coalesce(c.catalog_variant_id,o.catalog_variant_id)catalog_variant_id,c.episode_key closing_episode_key,o.episode_key opening_episode_key,c.origin_event_id closing_origin_event_id,o.origin_event_id opening_origin_event_id,c.holding_evidence closing_holding,o.holding_evidence opening_holding,
   ce.amount closing_value,ce.evidence_id closing_evidence_id,ce.observed_at closing_evidence_at,ce.source_kind closing_source,ce.selected_basis closing_basis,
   ce.applicability_key closing_applicability,oe.amount opening_value,oe.evidence_id opening_evidence_id,oe.applicability_key opening_applicability,
   pop.population_count,pop.observed_at population_observed_at,pop.applicability_key population_applicability,pop.population_scope,
   case when can_cost then cost.amount end actual_cost,cost.id actual_cost_evidence_id,cost.occurred_at actual_cost_observed_at,cost.source_kind actual_cost_source_kind,cost.source_reference actual_cost_source_reference,
   case when not can_cost then'not_authorized'when cost.amount is null then'unknown'else'available'end actual_cost_access,
   c.episode_key is not null and c.episode_key=o.episode_key and c.holding_evidence='episode'and o.holding_evidence='episode'
    and ce.amount is not null and oe.amount is not null and ce.applicability_key=oe.applicability_key as comparable,
   case when c.holding_evidence in('record_only','episode_ambiguous','episode_finality_conflict')then c.holding_evidence
    when o.holding_evidence is not null and c.holding_evidence is not null and o.episode_key is distinct from c.episode_key then'ownership_episode_changed'
    when o.holding_evidence is not null and c.holding_evidence is not null and oe.applicability_key is distinct from ce.applicability_key then'applicability_changed'
    when c.holding_evidence is not null and ce.amount is null then'closing_value_unavailable'
    when o.holding_evidence is not null and oe.amount is null then'opening_value_unavailable'end uncomparable_reason
  from all_ids i left join close_h c using(unique_item_id)left join open_h o using(unique_item_id)
  left join lateral e10.inventory_estimate_at(p_org,i.unique_item_id,coalesce(c.catalog_variant_id,o.catalog_variant_id),p_closing_cutoff,make_interval(days=>p_freshness_days),btrim(p_method),btrim(p_method_version),p_currency)ce on c.holding_evidence='episode'
  left join lateral e10.inventory_estimate_at(p_org,i.unique_item_id,coalesce(c.catalog_variant_id,o.catalog_variant_id),p_opening_cutoff,make_interval(days=>p_freshness_days),btrim(p_method),btrim(p_method_version),p_currency)oe on o.holding_evidence='episode'and p_opening_cutoff is not null
  left join lateral e10.inventory_population_at(p_org,coalesce(c.catalog_variant_id,o.catalog_variant_id),i.unique_item_id,p_closing_cutoff)pop on c.holding_evidence='episode'
  left join lateral(select m.id,m.amount,m.occurred_at,m.source_kind,m.source_reference from public.e10_current_market_observations m where m.organization_id=p_org and m.unique_item_id=i.unique_item_id and m.observation_kind='acquisition_cost'and m.currency=p_currency and m.occurred_at>=c.origin_at and m.occurred_at<=p_closing_cutoff and m.source_reference=c.origin_event_id::text order by m.occurred_at desc,m.recorded_at desc,m.id desc limit 1)cost on can_cost and c.holding_evidence='episode'
 ),totals as(select jsonb_build_object(
   'closing_holding_count',count(*)filter(where closing_holding is not null),'closing_valued_count',count(*)filter(where closing_holding is not null and closing_value is not null),'closing_unvalued_count',count(*)filter(where closing_holding is not null and closing_value is null),'closing_value',sum(closing_value)filter(where closing_holding is not null),
   'opening_holding_count',count(*)filter(where opening_holding is not null),'opening_valued_count',count(*)filter(where opening_holding is not null and opening_value is not null),'opening_value',sum(opening_value)filter(where opening_holding is not null),
   'comparable_count',count(*)filter(where comparable),'market_movement',sum(closing_value-opening_value)filter(where comparable),
   'acquisition_count',count(*)filter(where closing_holding is not null and(opening_holding is null or opening_episode_key is distinct from closing_episode_key)),'acquisition_endpoint_value',sum(closing_value)filter(where closing_holding is not null and(opening_holding is null or opening_episode_key is distinct from closing_episode_key)),
   'disposal_count',count(*)filter(where opening_holding is not null and(closing_holding is null or opening_episode_key is distinct from closing_episode_key)),'disposal_endpoint_value',sum(opening_value)filter(where opening_holding is not null and(closing_holding is null or opening_episode_key is distinct from closing_episode_key)),
   'uncomparable_count',count(*)filter(where opening_holding is not null and closing_holding is not null and not coalesce(comparable,false)),
   'record_only_count',count(*)filter(where closing_holding='record_only'),'ambiguous_episode_count',count(*)filter(where closing_holding in('episode_ambiguous','episode_finality_conflict')),
   'unknown_cost_count',count(*)filter(where closing_holding is not null and(can_cost and actual_cost is null)),'actual_cost_contribution',case when can_cost then sum(actual_cost)filter(where closing_holding is not null)end,'actual_cost_access',case when can_cost then'authorized'else'not_authorized'end)j from facts),
 page as(select*from facts where closing_holding is not null and(after_item is null or unique_item_id>after_item)order by unique_item_id limit p_limit+1),shown as(select*from page order by unique_item_id limit p_limit)
 select(select j from totals),(select count(*)from page)>p_limit,coalesce(jsonb_agg(jsonb_build_object('unique_item_id',unique_item_id,'episode_key',closing_episode_key,'origin_event_id',closing_origin_event_id,'holding_evidence',closing_holding,'value',closing_value,'valuation_evidence_id',closing_evidence_id,'evidence_observed_at',closing_evidence_at,'source_kind',closing_source,'selected_basis',closing_basis,'applicability_key',closing_applicability,'population_count',population_count,'population_observed_at',population_observed_at,'population_scope',population_scope,'population_applicability_key',population_applicability,'actual_cost',actual_cost,'actual_cost_evidence_id',actual_cost_evidence_id,'actual_cost_observed_at',actual_cost_observed_at,'actual_cost_source_kind',actual_cost_source_kind,'actual_cost_source_reference',actual_cost_source_reference,'actual_cost_access',actual_cost_access,'comparable',comparable,'uncomparable_reason',uncomparable_reason)order by unique_item_id),'[]'),(select unique_item_id from shown order by unique_item_id desc limit 1)
 into summary,has_more,items,last_item from shown;
 if has_more then next_cursor:=e10.inventory_cursor_encode(p_org,jsonb_build_object('fingerprint',fp,'actor',actor,'revision',rev,'unique_item_id',last_item));end if;
 return jsonb_build_object('metric_version','inventory-valuation-v1','organization_revision',rev,'method',btrim(p_method),'method_version',btrim(p_method_version),'currency',p_currency,'opening_cutoff',p_opening_cutoff,'closing_cutoff',p_closing_cutoff,'freshness_days',p_freshness_days,'summary',summary,'items',items,'next_cursor',next_cursor);
end $$;

revoke all on function public.e10_org_unique_item_evidence(uuid,uuid,timestamptz,integer,text),public.e10_org_inventory_valuation_coverage(uuid,text,text,text,timestamptz,timestamptz,integer,integer,text)from public,anon;
grant execute on function public.e10_org_unique_item_evidence(uuid,uuid,timestamptz,integer,text),public.e10_org_inventory_valuation_coverage(uuid,text,text,text,timestamptz,timestamptz,integer,integer,text)to authenticated,service_role;
