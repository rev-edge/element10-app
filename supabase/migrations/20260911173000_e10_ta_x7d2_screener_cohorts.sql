-- TA-X7d.2f service-only cohort execution. Public authorization/cursors wrap this engine later.
alter table public.e10_catalog_releases add column league text check(league is null or length(btrim(league))between 1 and 100);
comment on column public.e10_catalog_releases.league is'Optional reviewed shared release league used by exact market filters; NULL remains unknown and never matches an exact league filter.';

create function e10.numeric_median(p_values numeric[])returns numeric language sql immutable security definer set search_path=public as $$
 select avg(v)from(select v from unnest(p_values)v order by v limit 2-mod(cardinality(p_values),2)offset(cardinality(p_values)-1)/2)s
$$;
revoke all on function e10.numeric_median(numeric[])from public,anon,authenticated;grant execute on function e10.numeric_median(numeric[])to service_role;
comment on function e10.numeric_median(numeric[])is'Exact odd/even numeric median for nonempty NULL-free arrays; the cohort engine supplies filtered amount arrays only.';
create function e10.market_screener_rows(p_org uuid,p_request jsonb)
returns table(cohort_key text,row_data jsonb,sort_observed_count bigint,sort_latest numeric,sort_mean numeric,sort_median numeric)
language sql stable security definer set search_path=public as $$
with p as(
 select p_request->>'scope' scope,p_request->>'grouping' grouping,p_request->>'metric' metric,p_request->>'observation_kind' kind,
 (p_request->>'observed_from')::timestamptz observed_from,(p_request->>'observed_to')::timestamptz observed_to,(p_request->>'as_of')::timestamptz as_of,
 p_request->>'currency' currency,p_request->>'source_mode' source_mode,p_request->>'source_kind' source_kind,p_request->'resolved_source_universe' sources,p_request->'filters' f
),catalog as(select*from e10.market_catalog_entities(p_org)),
entities as(
 select c.catalog_variant_id entity_id,null::uuid owned_copy_id,null::integer owned_serial_numerator,c.*from catalog c,p where p.scope='catalog'
 union all
 select u.id,u.id,u.serial_numerator,c.*from public.e10_unique_items u join catalog c on c.catalog_variant_id=u.catalog_variant_id,p where p.scope='owned'and u.organization_id=p_org
 union all
 select o.observation_id,o.unique_item_id,null::integer,c.*from public.e10_market_eligible_canonical_observations o left join catalog c on c.catalog_variant_id=o.catalog_variant_id,p where p.scope='completed_sale_observation'and o.organization_id=p_org and o.observation_kind='completed_sale'
),identity_filtered as(
 select e.*from entities e,p where
 (not(p.f?'sport')or e.sport=p.f->>'sport')and(not(p.f?'league')or exists(select 1 from public.e10_catalog_releases rr where rr.id=e.release_id and rr.league=p.f->>'league'))and
 (not(p.f?'subject_id')or(p.f->>'subject_id')::uuid=any(e.subject_ids))and
 (not(p.f?'manufacturer')or e.manufacturer=p.f->>'manufacturer')and(not(p.f?'brand_line')or e.brand_line=p.f->>'brand_line')and
 (not(p.f?'release_id')or e.release_id=(p.f->>'release_id')::uuid)and(not(p.f?'release_name')or e.release_name=p.f->>'release_name')and
 (not(p.f?'release_year')or e.release_year=(p.f->>'release_year')::integer)and(not(p.f?'release_year_from')or e.release_year>=(p.f->>'release_year_from')::integer)and(not(p.f?'release_year_to')or e.release_year<=(p.f->>'release_year_to')::integer)and
 (not(p.f?'season_from')or e.release_season>=p.f->>'season_from')and(not(p.f?'season_to')or e.release_season<=p.f->>'season_to')and
 (not(p.f?'language')or coalesce(e.variant_language,e.release_language)=p.f->>'language')and(not(p.f?'region')or e.release_region=p.f->>'region')and(not(p.f?'edition')or coalesce(e.variant_edition,e.release_edition)=p.f->>'edition')and
 (not(p.f?'card_number')or e.card_number=p.f->>'card_number')and(not(p.f?'exact_parallel')or e.exact_parallel=p.f->>'exact_parallel')and
 (not(p.f?'color_family_term_id')or e.color_family_term_id=(p.f->>'color_family_term_id')::uuid)and(not(p.f?'finish_family_term_id')or e.finish_family_term_id=(p.f->>'finish_family_term_id')::uuid)and
 (not(p.f?'rookie_designation')or case when p.f?'subject_id'then e.rookie_designation_by_subject->(p.f->>'subject_id')->>'value'=p.f->>'rookie_designation'else e.rookie_designation=(p.f->>'rookie_designation')::boolean end)and
 (not(p.f?'rookie_season')or case when p.f?'subject_id'then e.rookie_season_by_subject->(p.f->>'subject_id')->>'value'=p.f->>'rookie_season'else exists(select 1 from jsonb_each(e.rookie_season_by_subject)x where x.value->>'value'=p.f->>'rookie_season')end)and
 (not(p.f?'variant_print_run_denominator')or e.variant_print_run_denominator=(p.f->>'variant_print_run_denominator')::integer)and
 ((p.f->>'exact_subject')::boolean is not true or p.scope<>'owned'or exists(select 1 from public.e10_current_unique_item_facets x where x.organization_id=p_org and x.unique_item_id=e.owned_copy_id and x.subject_id=(p.f->>'subject_id')::uuid))and
 (p.scope<>'owned'or not(p.f?'serial_numerator')or e.owned_serial_numerator=(p.f->>'serial_numerator')::integer)and
 (p.scope<>'owned'or not(p.f?'jersey_match')or exists(select 1 from public.e10_current_unique_item_facets x where x.organization_id=p_org and x.unique_item_id=e.owned_copy_id and x.jersey_match=(p.f->>'jersey_match')::boolean and(not(p.f?'subject_id')or x.subject_id=(p.f->>'subject_id')::uuid)))
),joined as(
 select e.*,o.observation_id,o.provenance_observation_ids,o.provenance_count,o.occurred_at,o.transaction_total_amount,o.reviewed_unit_price_amount,o.known_unit_quantity,
 o.condition_state,o.grader_code,o.grade_label,o.grade_qualifier,o.serial_numerator,o.serial_denominator,o.jersey_match observation_jersey_match,o.observation_subject_id
 from identity_filtered e cross join p left join public.e10_market_eligible_canonical_observations o on o.organization_id=p_org
 and((p.scope='catalog'and o.catalog_variant_id=e.catalog_variant_id)or(p.scope='owned'and o.unique_item_id=e.entity_id)or(p.scope='completed_sale_observation'and o.observation_id=e.entity_id))
 and o.observation_kind=p.kind and o.occurred_at>=p.observed_from and o.occurred_at<p.observed_to and o.occurred_at<=p.as_of
 and(p.currency is null or o.currency=p.currency)
 and(p.source_mode='none'or jsonb_array_length(p.sources)>0 and e10.market_provenance_matches(p_org,o.provenance_observation_ids,p.source_kind,p.sources))
 and(not(p.f?'condition_state')or o.condition_state=p.f->>'condition_state')and(not(p.f?'graded')or case when(p.f->>'graded')::boolean then o.condition_state='graded'else o.condition_state='raw'end)and
 (not(p.f?'grader_code')or o.grader_code=p.f->>'grader_code')and(not(p.f?'grade_label')or o.grade_label=p.f->>'grade_label')and(not(p.f?'grade_qualifier')or o.grade_qualifier=p.f->>'grade_qualifier')and
 (p.scope='owned'or not(p.f?'serial_numerator')or o.serial_numerator=(p.f->>'serial_numerator')::integer)and(not(p.f?'observed_serial_denominator')or o.serial_denominator=(p.f->>'observed_serial_denominator')::integer)and
 (p.scope='owned'or not(p.f?'jersey_match')or o.jersey_match=(p.f->>'jersey_match')::boolean)and
 ((p.f->>'exact_subject')::boolean is not true or p.scope<>'completed_sale_observation'or o.observation_subject_id=(p.f->>'subject_id')::uuid)and
 (not(p.f?'amount_min')or(case when p.metric='transaction_total'then o.transaction_total_amount else o.reviewed_unit_price_amount end)>=(p.f->>'amount_min')::numeric)and
 (not(p.f?'amount_max')or(case when p.metric='transaction_total'then o.transaction_total_amount else o.reviewed_unit_price_amount end)<=(p.f->>'amount_max')::numeric)
),evidence_filtered as(
 select j.*from joined j,p where(p.scope<>'completed_sale_observation'or j.observation_id is not null)and(not(p.f?|array['condition_state','graded','grader_code','grade_label','grade_qualifier','observed_serial_denominator','amount_min','amount_max'])and(p.scope='owned'or not(p.f?|array['serial_numerator','jersey_match']))or j.observation_id is not null)
),expanded as(
 select j.*,s.subject_id,
 case when p.metric<>'count'or p.grouping in('variant_condition','variant_grader_grade')then j.condition_state end group_condition,
 case when p.metric<>'count'or p.grouping='variant_grader_grade'then j.grader_code end group_grader,
 case when p.metric<>'count'or p.grouping='variant_grader_grade'then j.grade_label end group_grade,
 case when p.metric<>'count'or p.grouping='variant_grader_grade'then j.grade_qualifier end group_qualifier,
 case p.grouping when'entity'then j.entity_id when'variant'then j.catalog_variant_id when'variant_condition'then j.catalog_variant_id when'variant_grader_grade'then j.catalog_variant_id when'release'then j.release_id when'color'then j.color_family_term_id when'finish'then j.finish_family_term_id else s.subject_id end group_id
 from evidence_filtered j,p cross join lateral(select x subject_id from unnest(case when p.grouping='subject'and cardinality(j.subject_ids)>0 then j.subject_ids else array[null::uuid]end)x)s
),keyed as(
 select x.*,encode(sha256(convert_to(jsonb_build_array('market-cohort-v1',p.scope,p.grouping,x.group_id,x.group_condition,x.group_grader,x.group_grade,x.group_qualifier)::text,'UTF8')),'hex')ck
 from expanded x,p
),owned_counts as(
 select k.ck,count(distinct case when p.scope='catalog'then u.id else k.owned_copy_id end)::bigint owned_copy_count
 from keyed k cross join p left join public.e10_unique_items u on p.scope='catalog'and u.organization_id=p_org and u.catalog_variant_id=k.catalog_variant_id
 group by k.ck
),agg as(
 select ck,(array_agg(entity_id order by entity_id)filter(where p.grouping='entity'))[1]entity_id,case when p.grouping in('entity','variant','variant_condition','variant_grader_grade')then(array_agg(catalog_variant_id order by catalog_variant_id)filter(where catalog_variant_id is not null))[1]end catalog_variant_id,case when p.grouping in('entity','release')then(array_agg(release_id order by release_id)filter(where release_id is not null))[1]end release_id,case when p.grouping='subject'then(array_agg(subject_id order by subject_id)filter(where subject_id is not null))[1]end subject_id,
 min(group_condition)condition_state,min(group_grader)grader_code,min(group_grade)grade_label,min(group_qualifier)grade_qualifier,
 case when p.grouping='color'then(array_agg(color_family_term_id order by color_family_term_id)filter(where color_family_term_id is not null))[1]end color_family_term_id,case when p.grouping='finish'then(array_agg(finish_family_term_id order by finish_family_term_id)filter(where finish_family_term_id is not null))[1]end finish_family_term_id,case when p.grouping in('entity','variant','variant_condition','variant_grader_grade')then bool_or(rookie_designation)filter(where rookie_designation is not null)end rookie_designation,
 count(distinct catalog_variant_id)::bigint catalog_entity_count,count(distinct observation_id)::bigint observed_count,
 coalesce(sum(greatest(provenance_count-1,0))filter(where observation_id is not null),0)::bigint linked_duplicate_count,
 sum(known_unit_quantity)filter(where observation_id is not null)known_unit_quantity,
 avg(transaction_total_amount)mean_transaction_total,e10.numeric_median(array_agg(transaction_total_amount order by transaction_total_amount)filter(where transaction_total_amount is not null))median_transaction_total,
 (array_agg(transaction_total_amount order by occurred_at desc,observation_id desc)filter(where transaction_total_amount is not null))[1]latest_transaction_total,min(transaction_total_amount)minimum_transaction_total,max(transaction_total_amount)maximum_transaction_total,
 avg(reviewed_unit_price_amount)mean_reviewed_unit_price,e10.numeric_median(array_agg(reviewed_unit_price_amount order by reviewed_unit_price_amount)filter(where reviewed_unit_price_amount is not null))median_reviewed_unit_price,
 (array_agg(reviewed_unit_price_amount order by occurred_at desc,observation_id desc)filter(where reviewed_unit_price_amount is not null))[1]latest_reviewed_unit_price,min(reviewed_unit_price_amount)minimum_reviewed_unit_price,max(reviewed_unit_price_amount)maximum_reviewed_unit_price
 from keyed,p group by ck,p.grouping
),post_filtered as(
 select a.*from agg a,p where
 (not(p.f?'sale_count_min')or a.observed_count>=(p.f->>'sale_count_min')::bigint)and(not(p.f?'sale_count_max')or a.observed_count<=(p.f->>'sale_count_max')::bigint)and
 (not(p.f?'mean_min')or(case when p.metric='transaction_total'then a.mean_transaction_total else a.mean_reviewed_unit_price end)>=(p.f->>'mean_min')::numeric)and(not(p.f?'mean_max')or(case when p.metric='transaction_total'then a.mean_transaction_total else a.mean_reviewed_unit_price end)<=(p.f->>'mean_max')::numeric)and
 (not(p.f?'median_min')or(case when p.metric='transaction_total'then a.median_transaction_total else a.median_reviewed_unit_price end)>=(p.f->>'median_min')::numeric)and(not(p.f?'median_max')or(case when p.metric='transaction_total'then a.median_transaction_total else a.median_reviewed_unit_price end)<=(p.f->>'median_max')::numeric)and
 (not(p.f?'latest_min')or(case when p.metric='transaction_total'then a.latest_transaction_total else a.latest_reviewed_unit_price end)>=(p.f->>'latest_min')::numeric)and(not(p.f?'latest_max')or(case when p.metric='transaction_total'then a.latest_transaction_total else a.latest_reviewed_unit_price end)<=(p.f->>'latest_max')::numeric)and
 (not(p.f?'minimum_min')or(case when p.metric='transaction_total'then a.minimum_transaction_total else a.minimum_reviewed_unit_price end)>=(p.f->>'minimum_min')::numeric)and(not(p.f?'minimum_max')or(case when p.metric='transaction_total'then a.minimum_transaction_total else a.minimum_reviewed_unit_price end)<=(p.f->>'minimum_max')::numeric)and
 (not(p.f?'maximum_min')or(case when p.metric='transaction_total'then a.maximum_transaction_total else a.maximum_reviewed_unit_price end)>=(p.f->>'maximum_min')::numeric)and(not(p.f?'maximum_max')or(case when p.metric='transaction_total'then a.maximum_transaction_total else a.maximum_reviewed_unit_price end)<=(p.f->>'maximum_max')::numeric)
)
select a.ck,jsonb_build_object('cohort_key',a.ck,'entity_id',entity_id,'catalog_variant_id',catalog_variant_id,'release_id',release_id,'subject_id',subject_id,'condition_state',condition_state,'grader_code',grader_code,'grade_label',grade_label,'grade_qualifier',grade_qualifier,'color_family_term_id',color_family_term_id,'finish_family_term_id',finish_family_term_id,'rookie_designation',rookie_designation,'catalog_entity_count',catalog_entity_count,'owned_copy_count',oc.owned_copy_count,'observed_count',observed_count,'linked_duplicate_count',linked_duplicate_count,'known_unit_quantity',known_unit_quantity,'mean_transaction_total',case when p.metric='count'then null else mean_transaction_total end,'median_transaction_total',case when p.metric='count'then null else median_transaction_total end,'latest_transaction_total',case when p.metric='count'then null else latest_transaction_total end,'minimum_transaction_total',case when p.metric='count'then null else minimum_transaction_total end,'maximum_transaction_total',case when p.metric='count'then null else maximum_transaction_total end,'mean_reviewed_unit_price',case when p.metric='count'then null else mean_reviewed_unit_price end,'median_reviewed_unit_price',case when p.metric='count'then null else median_reviewed_unit_price end,'latest_reviewed_unit_price',case when p.metric='count'then null else latest_reviewed_unit_price end,'minimum_reviewed_unit_price',case when p.metric='count'then null else minimum_reviewed_unit_price end,'maximum_reviewed_unit_price',case when p.metric='count'then null else maximum_reviewed_unit_price end),observed_count,
case when p.metric='transaction_total'then latest_transaction_total else latest_reviewed_unit_price end,case when p.metric='transaction_total'then mean_transaction_total else mean_reviewed_unit_price end,case when p.metric='transaction_total'then median_transaction_total else median_reviewed_unit_price end
from post_filtered a join owned_counts oc on oc.ck=a.ck cross join p
$$;
revoke all on function e10.market_screener_rows(uuid,jsonb)from public,anon,authenticated;
grant execute on function e10.market_screener_rows(uuid,jsonb)to service_role;
comment on function e10.market_screener_rows(uuid,jsonb)is'Service-only cohort engine. Evidence filters are conjoined on one canonical observation before grouping; catalog rows without evidence survive only when no evidence filter is requested.';
