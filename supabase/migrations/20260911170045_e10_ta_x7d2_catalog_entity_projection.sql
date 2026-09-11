-- TA-X7d.2d organization-aware catalog rows independent of sale evidence.
create function e10.market_catalog_entities(p_org uuid)
returns table(
 catalog_variant_id uuid,release_id uuid,manufacturer text,brand_line text,release_name text,release_year integer,release_season text,sport text,
 release_language text,release_region text,release_edition text,card_number text,exact_parallel text,variant_language text,variant_edition text,
 variant_print_run_denominator integer,subject_ids uuid[],color_family_term_id uuid,color_family_status text,finish_family_term_id uuid,finish_family_status text,
 rookie_designation boolean,rookie_designation_status text,rookie_designation_by_subject jsonb,rookie_season_by_subject jsonb
)language sql stable security definer set search_path=public as $$
 select cv.id,r.id,r.manufacturer,r.brand_line,r.release_name,r.release_year,r.season,r.sport,r.language,r.region,r.edition,cv.card_number,cv.exact_parallel,cv.language,cv.edition,cv.print_run_denominator,
 coalesce((select array_agg(s.player_id order by s.position,s.player_id)from public.e10_catalog_variant_subjects s where s.variant_id=cv.id),array[]::uuid[]),
 case when color_o.action='assert'then case when color_ot.action='assert'then color_o.term_key else null end when color_o.action='mask'then null when color_g.action='assert'and color_gt.action='assert'then color_g.term_key else null end,
 case when color_o.action='mask'then'org_masked'when color_o.action='assert'and color_ot.action='assert'then'org_override'when color_o.action='assert'then'org_term_revoked'when color_g.action='assert'and color_gt.action='assert'then'global_reviewed'when color_g.action='assert'then'global_term_revoked'else'unknown'end,
 case when finish_o.action='assert'then case when finish_ot.action='assert'then finish_o.term_key else null end when finish_o.action='mask'then null when finish_g.action='assert'and finish_gt.action='assert'then finish_g.term_key else null end,
 case when finish_o.action='mask'then'org_masked'when finish_o.action='assert'and finish_ot.action='assert'then'org_override'when finish_o.action='assert'then'org_term_revoked'when finish_g.action='assert'and finish_gt.action='assert'then'global_reviewed'when finish_g.action='assert'then'global_term_revoked'else'unknown'end,
 case when rookie_o.action='assert'then rookie_o.boolean_value when rookie_o.action='mask'then null when rookie_g.action='assert'then rookie_g.boolean_value else null end,
 case when rookie_o.action='assert'then'org_override'when rookie_o.action='mask'then'org_masked'when rookie_g.action='assert'then'global_reviewed'else'unknown'end,
 coalesce((select jsonb_object_agg(s.player_id::text,jsonb_build_object('value',case when oo.action='assert'then oo.boolean_value when oo.action='mask'then null when gg.action='assert'then gg.boolean_value when rookie_o.action='assert'then rookie_o.boolean_value when rookie_o.action='mask'then null when rookie_g.action='assert'then rookie_g.boolean_value else null end,'status',case when oo.action='assert'then'org_subject_override'when oo.action='mask'then'org_subject_masked'when gg.action='assert'then'global_subject_reviewed'when rookie_o.action='assert'then'org_variant_override'when rookie_o.action='mask'then'org_variant_masked'when rookie_g.action='assert'then'global_variant_reviewed'else'unknown'end)order by s.position)
  from public.e10_catalog_variant_subjects s left join public.e10_current_catalog_variant_facets gg on gg.variant_id=s.variant_id and gg.subject_id=s.player_id and gg.facet_key='rookie_designation'left join public.e10_current_org_catalog_variant_facet_overrides oo on oo.organization_id=p_org and oo.variant_id=s.variant_id and oo.subject_id=s.player_id and oo.facet_key='rookie_designation'where s.variant_id=cv.id),'{}'::jsonb),
 coalesce((select jsonb_object_agg(s.player_id::text,jsonb_build_object('value',case when oo.action='assert'then oo.integer_value when oo.action='mask'then null when gg.action='assert'then gg.integer_value else null end,'status',case when oo.action='assert'then'org_override'when oo.action='mask'then'org_masked'when gg.action='assert'then'global_reviewed'else'unknown'end)order by s.position)
  from public.e10_catalog_variant_subjects s left join public.e10_current_catalog_variant_facets gg on gg.variant_id=s.variant_id and gg.subject_id=s.player_id and gg.facet_key='rookie_season'left join public.e10_current_org_catalog_variant_facet_overrides oo on oo.organization_id=p_org and oo.variant_id=s.variant_id and oo.subject_id=s.player_id and oo.facet_key='rookie_season'where s.variant_id=cv.id),'{}'::jsonb)
 from public.e10_catalog_variants cv join public.e10_catalog_releases r on r.id=cv.release_id
 left join public.e10_current_catalog_variant_facets color_g on color_g.variant_id=cv.id and color_g.subject_id is null and color_g.facet_key='color_family'
 left join public.e10_current_org_catalog_variant_facet_overrides color_o on color_o.organization_id=p_org and color_o.variant_id=cv.id and color_o.subject_id is null and color_o.facet_key='color_family'
 left join public.e10_current_catalog_facet_taxonomy_terms color_gt on color_gt.term_key=color_g.term_key left join public.e10_current_catalog_facet_taxonomy_terms color_ot on color_ot.term_key=color_o.term_key
 left join public.e10_current_catalog_variant_facets finish_g on finish_g.variant_id=cv.id and finish_g.subject_id is null and finish_g.facet_key='finish_family'
 left join public.e10_current_org_catalog_variant_facet_overrides finish_o on finish_o.organization_id=p_org and finish_o.variant_id=cv.id and finish_o.subject_id is null and finish_o.facet_key='finish_family'
 left join public.e10_current_catalog_facet_taxonomy_terms finish_gt on finish_gt.term_key=finish_g.term_key left join public.e10_current_catalog_facet_taxonomy_terms finish_ot on finish_ot.term_key=finish_o.term_key
 left join public.e10_current_catalog_variant_facets rookie_g on rookie_g.variant_id=cv.id and rookie_g.subject_id is null and rookie_g.facet_key='rookie_designation'
 left join public.e10_current_org_catalog_variant_facet_overrides rookie_o on rookie_o.organization_id=p_org and rookie_o.variant_id=cv.id and rookie_o.subject_id is null and rookie_o.facet_key='rookie_designation'
 where p_org is not null
$$;
revoke all on function e10.market_catalog_entities(uuid)from public,anon,authenticated;
grant execute on function e10.market_catalog_entities(uuid)to service_role;
comment on function e10.market_catalog_entities(uuid)is'Organization-aware reviewed catalog entity projection that retains variants with zero market observations.';
