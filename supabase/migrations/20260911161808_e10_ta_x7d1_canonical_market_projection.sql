-- TA-X7d.1 canonical, service-only market eligibility projection.
create index e10_market_equivalence_canonical_idx on public.e10_market_observation_equivalence_decisions(organization_id,canonical_observation_id,duplicate_observation_id)where action='link';

create function e10.resolve_market_observation_canonical(p_org uuid,p_observation uuid)returns uuid
language plpgsql stable security definer set search_path=public as $$
declare v_current uuid:=p_observation;v_next uuid;v_seen uuid[]:=array[p_observation];v_depth integer:=0;
begin
 if p_org is null or p_observation is null or not exists(select 1 from public.e10_current_market_observations where organization_id=p_org and id=p_observation)then return null;end if;
 loop
  select canonical_observation_id into v_next from public.e10_current_market_observation_equivalences where organization_id=p_org and duplicate_observation_id=v_current;
  if v_next is null then return v_current;end if;
  v_depth:=v_depth+1;
  if v_depth>32 then raise exception using errcode='54000',message='market_equivalence_depth_exceeded';end if;
  if v_next=any(v_seen)then raise exception using errcode='23514',message='market_equivalence_cycle';end if;
  v_seen:=array_append(v_seen,v_next);v_current:=v_next;
 end loop;
end $$;
revoke all on function e10.resolve_market_observation_canonical(uuid,uuid)from public,anon,authenticated;grant execute on function e10.resolve_market_observation_canonical(uuid,uuid)to service_role;

create view public.e10_market_eligible_canonical_observations with(security_invoker=true)as
with resolved as(
 select o.organization_id,o.id member_observation_id,e10.resolve_market_observation_canonical(o.organization_id,o.id)canonical_observation_id
 from public.e10_current_market_observations o
),groups as(
 select organization_id,canonical_observation_id,array_agg(member_observation_id order by member_observation_id)provenance_observation_ids,count(*)::integer provenance_count
 from resolved group by organization_id,canonical_observation_id
)
select
 c.organization_id,c.id observation_id,c.id canonical_observation_id,g.provenance_observation_ids,g.provenance_count,
 coalesce((select count(*) from public.e10_market_observation_equivalence_status es where es.organization_id=c.organization_id and es.review_status='review_required'and(es.duplicate_observation_id=any(g.provenance_observation_ids)or es.canonical_observation_id=any(g.provenance_observation_ids))),0)::integer review_required_equivalence_count,
 c.catalog_variant_id direct_catalog_variant_id,c.unique_item_id,c.product_master_id direct_product_master_id,c.configuration_version_id direct_configuration_version_id,
 coalesce(c.catalog_variant_id,ui.catalog_variant_id)catalog_variant_id,
 coalesce(c.product_master_id,ui.product_master_id,pc.product_master_id)product_master_id,
 coalesce(c.configuration_version_id,ui.configuration_version_id)configuration_version_id,
 r.id release_id,r.manufacturer,r.brand_line,r.release_name,r.release_year,r.season release_season,r.sport,r.language release_language,r.region,r.edition release_edition,
 cv.card_number,cv.exact_parallel,cv.language variant_language,cv.edition variant_edition,cv.print_run_denominator,
 coalesce((select array_agg(s.player_id order by s.position,s.player_id)from public.e10_catalog_variant_subjects s where s.variant_id=cv.id),array[]::uuid[])subject_ids,
 case when cv.id is not null then'catalog_variant'when c.unique_item_id is not null then'unique_item'when coalesce(c.configuration_version_id,ui.configuration_version_id)is not null then'configuration_version'else'product_master'end cohort_target_type,
 coalesce(cv.id,c.unique_item_id,coalesce(c.configuration_version_id,ui.configuration_version_id),coalesce(c.product_master_id,ui.product_master_id,pc.product_master_id))cohort_target_id,
 md5(concat_ws('|',case when cv.id is not null then'catalog_variant'when c.unique_item_id is not null then'unique_item'when coalesce(c.configuration_version_id,ui.configuration_version_id)is not null then'configuration_version'else'product_master'end,coalesce(cv.id,c.unique_item_id,coalesce(c.configuration_version_id,ui.configuration_version_id),coalesce(c.product_master_id,ui.product_master_id,pc.product_master_id))::text))base_target_cohort_key,
 md5(jsonb_build_array('metric-cohort-v1',case when cv.id is not null then'catalog_variant'when c.unique_item_id is not null then'unique_item'when coalesce(c.configuration_version_id,ui.configuration_version_id)is not null then'configuration_version'else'product_master'end,coalesce(cv.id,c.unique_item_id,coalesce(c.configuration_version_id,ui.configuration_version_id),coalesce(c.product_master_id,ui.product_master_id,pc.product_master_id)),f.condition_state,f.grader_code,f.grade_label,f.grade_qualifier)::text)metric_cohort_key,
 case when coalesce(cv.id,c.unique_item_id,coalesce(c.configuration_version_id,ui.configuration_version_id),coalesce(c.product_master_id,ui.product_master_id,pc.product_master_id))is null then'unknown'else'known'end cohort_resolution_status,
 case when coalesce(cv.id,c.unique_item_id,coalesce(c.configuration_version_id,ui.configuration_version_id),coalesce(c.product_master_id,ui.product_master_id,pc.product_master_id))is null then'unknown_target_mapping'else null end exclusion_reason,
 c.observation_kind,c.currency,c.amount,c.quantity recorded_quantity,c.occurred_at,c.recorded_at,c.source_kind,c.source_connection_id,c.source_reference,
 coalesce((select array_agg(s.superseded_observation_id order by s.superseded_observation_id)from public.e10_market_observation_supersessions s where s.organization_id=c.organization_id and s.replacement_observation_id=c.id),array[]::uuid[])corrected_observation_ids,
 f.condition_state,(f.condition_state is not null)condition_state_known,f.grader_code,(f.grader_code is not null)grader_known,f.grade_label,(f.grade_label is not null)grade_known,f.grade_qualifier,
 f.serial_numerator,f.serial_denominator,(f.serial_numerator is not null)serial_known,f.jersey_match,f.subject_id observation_subject_id,f.pictured_number observation_pictured_number,f.team_reference observation_team_reference,f.season_reference observation_season_reference,
 f.transaction_quantity,coalesce(f.transaction_quantity,c.quantity)known_unit_quantity,f.amount_basis,(f.amount_basis is not null and f.amount_basis<>'unknown')amount_basis_known,f.reviewed_unit_amount,
 case when f.amount_basis='transaction_total'then c.amount else null end transaction_total_amount,case when f.amount_basis in('unit_price','transaction_total')then f.reviewed_unit_amount else null end reviewed_unit_price_amount,
 coalesce((select array_agg(x.subject_id order by x.subject_id)filter(where x.jersey_match is true)from public.e10_current_unique_item_facets x where x.organization_id=c.organization_id and x.unique_item_id=c.unique_item_id),array[]::uuid[])copy_jersey_match_subject_ids,
 coalesce((select array_agg(x.marking_text order by x.subject_id)filter(where x.marking_text is not null)from public.e10_current_unique_item_facets x where x.organization_id=c.organization_id and x.unique_item_id=c.unique_item_id),array[]::text[])copy_marking_texts,
 case when color_o.action='assert'then case when color_ot.action='assert'then color_o.term_key else null end when color_o.action='mask'then null when color_g.action='assert'and color_gt.action='assert'then color_g.term_key else null end color_family_term_id,
 case when color_o.action='mask'then'org_masked'when color_o.action='assert'and color_ot.action='assert'then'org_override'when color_o.action='assert'then'org_term_revoked'when color_g.action='assert'and color_gt.action='assert'then'global_reviewed'when color_g.action='assert'then'global_term_revoked'else'unknown'end color_family_status,
 case when finish_o.action='assert'then case when finish_ot.action='assert'then finish_o.term_key else null end when finish_o.action='mask'then null when finish_g.action='assert'and finish_gt.action='assert'then finish_g.term_key else null end finish_family_term_id,
 case when finish_o.action='mask'then'org_masked'when finish_o.action='assert'and finish_ot.action='assert'then'org_override'when finish_o.action='assert'then'org_term_revoked'when finish_g.action='assert'and finish_gt.action='assert'then'global_reviewed'when finish_g.action='assert'then'global_term_revoked'else'unknown'end finish_family_status,
 case when rookie_o.action='assert'then rookie_o.boolean_value when rookie_o.action='mask'then null when rookie_g.action='assert'then rookie_g.boolean_value else null end rookie_designation,
 case when rookie_o.action='assert'then'org_override'when rookie_o.action='mask'then'org_masked'when rookie_g.action='assert'then'global_reviewed'else'unknown'end rookie_designation_status,
 coalesce((select jsonb_object_agg(s.player_id::text,jsonb_build_object('value',case when oo.action='assert'then oo.boolean_value when oo.action='mask'then null when gg.action='assert'then gg.boolean_value when rookie_o.action='assert'then rookie_o.boolean_value when rookie_o.action='mask'then null when rookie_g.action='assert'then rookie_g.boolean_value else null end,'status',case when oo.action='assert'then'org_subject_override'when oo.action='mask'then'org_subject_masked'when gg.action='assert'then'global_subject_reviewed'when rookie_o.action='assert'then'org_variant_override'when rookie_o.action='mask'then'org_variant_masked'when rookie_g.action='assert'then'global_variant_reviewed'else'unknown'end)order by s.position)
  from public.e10_catalog_variant_subjects s left join public.e10_current_catalog_variant_facets gg on gg.variant_id=s.variant_id and gg.subject_id=s.player_id and gg.facet_key='rookie_designation'
  left join public.e10_current_org_catalog_variant_facet_overrides oo on oo.organization_id=c.organization_id and oo.variant_id=s.variant_id and oo.subject_id=s.player_id and oo.facet_key='rookie_designation'where s.variant_id=cv.id),'{}'::jsonb)rookie_designation_by_subject,
 coalesce((select jsonb_object_agg(s.player_id::text,jsonb_build_object('value',case when oo.action='assert'then oo.integer_value when oo.action='mask'then null when gg.action='assert'then gg.integer_value else null end,'status',case when oo.action='assert'then'org_override'when oo.action='mask'then'org_masked'when gg.action='assert'then'global_reviewed'else'unknown'end)order by s.position)
  from public.e10_catalog_variant_subjects s left join public.e10_current_catalog_variant_facets gg on gg.variant_id=s.variant_id and gg.subject_id=s.player_id and gg.facet_key='rookie_season'
  left join public.e10_current_org_catalog_variant_facet_overrides oo on oo.organization_id=c.organization_id and oo.variant_id=s.variant_id and oo.subject_id=s.player_id and oo.facet_key='rookie_season'where s.variant_id=cv.id),'{}'::jsonb)rookie_season_by_subject
from groups g join public.e10_current_market_observations c on c.organization_id=g.organization_id and c.id=g.canonical_observation_id
left join public.e10_unique_items ui on ui.organization_id=c.organization_id and ui.id=c.unique_item_id
left join public.e10_product_configuration_versions pcv on pcv.organization_id=c.organization_id and pcv.id=coalesce(c.configuration_version_id,ui.configuration_version_id)
left join public.e10_product_configurations pc on pc.organization_id=pcv.organization_id and pc.id=pcv.configuration_id
left join public.e10_catalog_variants cv on cv.id=coalesce(c.catalog_variant_id,ui.catalog_variant_id)
left join public.e10_catalog_releases r on r.id=cv.release_id
left join public.e10_current_market_observation_facts f on f.organization_id=c.organization_id and f.observation_id=c.id
left join public.e10_current_catalog_variant_facets color_g on color_g.variant_id=cv.id and color_g.subject_id is null and color_g.facet_key='color_family'
left join public.e10_current_org_catalog_variant_facet_overrides color_o on color_o.organization_id=c.organization_id and color_o.variant_id=cv.id and color_o.subject_id is null and color_o.facet_key='color_family'
left join public.e10_current_catalog_facet_taxonomy_terms color_gt on color_gt.term_key=color_g.term_key
left join public.e10_current_catalog_facet_taxonomy_terms color_ot on color_ot.term_key=color_o.term_key
left join public.e10_current_catalog_variant_facets finish_g on finish_g.variant_id=cv.id and finish_g.subject_id is null and finish_g.facet_key='finish_family'
left join public.e10_current_org_catalog_variant_facet_overrides finish_o on finish_o.organization_id=c.organization_id and finish_o.variant_id=cv.id and finish_o.subject_id is null and finish_o.facet_key='finish_family'
left join public.e10_current_catalog_facet_taxonomy_terms finish_gt on finish_gt.term_key=finish_g.term_key
left join public.e10_current_catalog_facet_taxonomy_terms finish_ot on finish_ot.term_key=finish_o.term_key
left join public.e10_current_catalog_variant_facets rookie_g on rookie_g.variant_id=cv.id and rookie_g.subject_id is null and rookie_g.facet_key='rookie_designation'
left join public.e10_current_org_catalog_variant_facet_overrides rookie_o on rookie_o.organization_id=c.organization_id and rookie_o.variant_id=cv.id and rookie_o.subject_id is null and rookie_o.facet_key='rookie_designation';

revoke all on public.e10_market_eligible_canonical_observations from public,anon,authenticated;grant select on public.e10_market_eligible_canonical_observations to service_role;
comment on view public.e10_market_eligible_canonical_observations is'One row per current valid canonical observation. Stale equivalence edges are surfaced as review-required and never merged; unknown reviewed semantics remain explicit NULL/status values.';
