-- TA-X7d.2g bounded public market screener over the reviewed cohort engine.
create function public.e10_org_market_screener(
 p_org uuid,p_scope text,p_grouping text,p_metric text,p_observation_kind text,p_observed_from timestamptz,p_observed_to timestamptz,p_as_of timestamptz,p_currency text,p_source_mode text,p_source_kind text,p_source_connections jsonb,
 p_filters jsonb default'{}'::jsonb,p_sort text default'cohort_asc',p_limit integer default 50,p_cursor uuid default null
)returns jsonb language plpgsql volatile security definer set search_path=public as $$
declare
 req jsonb;src jsonb;actor uuid;org_rev bigint;cat_rev bigint;fp text;ctx uuid;keys text[];page_keys text[];page_rows jsonb:='[]'::jsonb;unknowns jsonb;exclusions jsonb;coverage text:='unknown';material jsonb;
 pos jsonb;pos_key text;pos_count bigint;pos_latest numeric;pos_mean numeric;pos_median numeric;page_count integer;material_count integer;last_key text;last_count bigint;last_latest numeric;last_mean numeric;last_median numeric;next_cursor uuid;
begin
 select s.actor_id,s.organization_revision,s.catalog_revision into actor,org_rev,cat_rev from e10.lock_market_read_snapshot(p_org)s;
 req:=e10.normalize_market_screener_request(p_org,p_scope,p_grouping,p_metric,p_observation_kind,p_observed_from,p_observed_to,p_as_of,p_currency,p_source_mode,p_source_kind,p_source_connections,p_filters,p_sort,p_limit);src:=req->'resolved_source_universe';
 fp:=e10.market_query_fingerprint('market-read-v1',p_org,actor,'screener',req,src,org_rev,cat_rev);
 if p_cursor is not null then
  select c.sort_position,c.context_id into pos,ctx from public.e10_market_query_cursors c join public.e10_market_query_contexts q on q.organization_id=c.organization_id and q.id=c.context_id
  where c.id=p_cursor and c.organization_id=p_org and c.actor_id=actor and c.endpoint='screener'and c.query_fingerprint=fp and c.organization_revision=org_rev and c.catalog_revision=cat_rev and c.expires_at>clock_timestamp()
  and q.actor_id=actor and q.endpoint='screener'and q.query_fingerprint=fp and q.organization_revision=org_rev and q.catalog_revision=cat_rev and q.expires_at>clock_timestamp();
  if not found then raise exception using errcode='22023',message='market_cursor_invalid';end if;
  pos_key:=pos->>'cohort_key';pos_count:=(pos->>'observed_count')::bigint;pos_latest:=(pos->>'latest')::numeric;pos_mean:=(pos->>'mean')::numeric;pos_median:=(pos->>'median')::numeric;
 end if;
 select coalesce(jsonb_agg(to_jsonb(q)),'[]'::jsonb),count(*)into material,material_count from(select*from e10.market_screener_rows(p_org,req)limit 100001)q;
 if material_count>100000 then raise exception using errcode='54000',message='market_query_cohort_limit';end if;
 with q as(select*from jsonb_to_recordset(material)as x(cohort_key text,row_data jsonb,sort_observed_count bigint,sort_latest numeric,sort_mean numeric,sort_median numeric))select array_agg(q.cohort_key order by
  case when p_sort='cohort_asc'then q.cohort_key end,
  case when p_sort='observed_count_desc'then q.sort_observed_count end desc nulls last,
  case when p_sort='latest_desc'then q.sort_latest end desc nulls last,
  case when p_sort='mean_asc'then q.sort_mean end asc nulls last,case when p_sort='mean_desc'then q.sort_mean end desc nulls last,
  case when p_sort='median_asc'then q.sort_median end asc nulls last,case when p_sort='median_desc'then q.sort_median end desc nulls last,q.cohort_key)
 into keys from q;
 keys:=coalesce(keys,array[]::text[]);
 ctx:=e10.save_market_query_context('market-read-v1',p_org,actor,'screener',fp,req,src,org_rev,cat_rev,keys);
 with q as(select*from jsonb_to_recordset(material)as x(cohort_key text,row_data jsonb,sort_observed_count bigint,sort_latest numeric,sort_mean numeric,sort_median numeric)),after_cursor as(
  select*from q where p_cursor is null or
   p_sort='cohort_asc'and q.cohort_key>pos_key or
   p_sort='observed_count_desc'and(q.sort_observed_count<pos_count or q.sort_observed_count=pos_count and q.cohort_key>pos_key)or
   p_sort='latest_desc'and(case when pos_latest is null then q.sort_latest is null and q.cohort_key>pos_key else q.sort_latest<pos_latest or q.sort_latest is null or q.sort_latest=pos_latest and q.cohort_key>pos_key end)or
   p_sort='mean_asc'and(case when pos_mean is null then q.sort_mean is null and q.cohort_key>pos_key else q.sort_mean>pos_mean or q.sort_mean is null or q.sort_mean=pos_mean and q.cohort_key>pos_key end)or
   p_sort='mean_desc'and(case when pos_mean is null then q.sort_mean is null and q.cohort_key>pos_key else q.sort_mean<pos_mean or q.sort_mean is null or q.sort_mean=pos_mean and q.cohort_key>pos_key end)or
   p_sort='median_asc'and(case when pos_median is null then q.sort_median is null and q.cohort_key>pos_key else q.sort_median>pos_median or q.sort_median is null or q.sort_median=pos_median and q.cohort_key>pos_key end)or
   p_sort='median_desc'and(case when pos_median is null then q.sort_median is null and q.cohort_key>pos_key else q.sort_median<pos_median or q.sort_median is null or q.sort_median=pos_median and q.cohort_key>pos_key end)
 ),page as(select*from after_cursor order by
  case when p_sort='cohort_asc'then cohort_key end,
  case when p_sort='observed_count_desc'then sort_observed_count end desc nulls last,
  case when p_sort='latest_desc'then sort_latest end desc nulls last,
  case when p_sort='mean_asc'then sort_mean end asc nulls last,case when p_sort='mean_desc'then sort_mean end desc nulls last,
  case when p_sort='median_asc'then sort_median end asc nulls last,case when p_sort='median_desc'then sort_median end desc nulls last,cohort_key limit p_limit+1)
 select array_agg(cohort_key order by
  case when p_sort='cohort_asc'then cohort_key end,
  case when p_sort='observed_count_desc'then sort_observed_count end desc nulls last,
  case when p_sort='latest_desc'then sort_latest end desc nulls last,
  case when p_sort='mean_asc'then sort_mean end asc nulls last,case when p_sort='mean_desc'then sort_mean end desc nulls last,
  case when p_sort='median_asc'then sort_median end asc nulls last,case when p_sort='median_desc'then sort_median end desc nulls last,cohort_key)
 into page_keys from page;
 page_keys:=coalesce(page_keys,array[]::text[]);page_count:=least(cardinality(page_keys),p_limit);
 if jsonb_array_length(src)>0 then coverage:=e10.market_coverage_status(p_org,p_observation_kind,p_source_kind,p_currency,p_observed_from,p_observed_to,src);end if;
 select coalesce(jsonb_agg(q.row_data||jsonb_build_object('complete_selected_source_sale_count',case when p_observation_kind='completed_sale'and coverage='complete'then(q.row_data->>'observed_count')::bigint end,'price_availability',case when p_metric<>'count'and(case when p_metric='transaction_total'then q.row_data->'mean_transaction_total'else q.row_data->'mean_reviewed_unit_price'end)<> 'null'::jsonb then'available'else'unavailable'end)order by u.ord),'[]'::jsonb)
 into page_rows from unnest(page_keys[1:page_count])with ordinality u(k,ord)join jsonb_to_recordset(material)as q(cohort_key text,row_data jsonb,sort_observed_count bigint,sort_latest numeric,sort_mean numeric,sort_median numeric)on q.cohort_key=u.k;
 if cardinality(page_keys)>p_limit then
  last_key:=page_keys[p_limit];select sort_observed_count,sort_latest,sort_mean,sort_median into last_count,last_latest,last_mean,last_median from jsonb_to_recordset(material)as q(cohort_key text,row_data jsonb,sort_observed_count bigint,sort_latest numeric,sort_mean numeric,sort_median numeric)where cohort_key=last_key;
  next_cursor:=e10.save_market_query_cursor(ctx,p_org,actor,'screener',fp,jsonb_build_object('cohort_key',last_key,'observed_count',last_count,'latest',last_latest,'mean',last_mean,'median',last_median),null,org_rev,cat_rev);
 end if;
 select jsonb_build_object('condition_state',case when p_metric<>'count'or p_grouping in('variant_condition','variant_grader_grade')then count(*)filter(where row_data->>'condition_state'is null)end,'grade',case when p_metric<>'count'or p_grouping='variant_grader_grade'then count(*)filter(where row_data->>'grade_label'is null)end,'color_family',case when p_grouping='color'then count(*)filter(where row_data->>'color_family_term_id'is null)end,'finish_family',case when p_grouping='finish'then count(*)filter(where row_data->>'finish_family_term_id'is null)end)into unknowns from jsonb_to_recordset(material)as q(cohort_key text,row_data jsonb,sort_observed_count bigint,sort_latest numeric,sort_mean numeric,sort_median numeric);
 select jsonb_build_object('unknown_target_mapping',count(*))into exclusions from public.e10_market_eligible_canonical_observations o where o.organization_id=p_org and o.observation_kind=p_observation_kind and o.occurred_at>=p_observed_from and o.occurred_at<p_observed_to and o.occurred_at<=p_as_of and(p_currency is null or o.currency=p_currency)and o.exclusion_reason='unknown_target_mapping'and(p_source_mode='none'or jsonb_array_length(src)>0 and e10.market_provenance_matches(p_org,o.provenance_observation_ids,p_source_kind,src));
 if auth.uid()is distinct from actor or not exists(select 1 from public.e10_organizations where id=p_org and status='active')or not e10.is_org_member(p_org)or not e10.has_org_cap(p_org,'act.view_market_analytics')then raise exception using errcode='42501',message='market_read_denied';end if;
 return jsonb_build_object('query_fingerprint',fp,'organization_revision',org_rev,'catalog_revision',cat_rev,'scope',p_scope,'grouping',p_grouping,'metric',p_metric,'observation_kind',p_observation_kind,'coverage_status',coverage,'metric_version','market-read-v1','transaction_filter_applied',p_filters?|array['amount_min','amount_max'],'observed_from',req->>'observed_from','observed_to',req->>'observed_to','as_of',req->>'as_of','currency',p_currency,'resolved_source_universe',src,'owned_copy_count_context',case when p_scope='catalog'then'organization_variant_inventory'else'matching_scope_entities'end,'unknown_counts',unknowns,'exclusion_counts',exclusions,'rows',page_rows,'next_cursor',next_cursor);
end $$;
revoke all on function public.e10_org_market_screener(uuid,text,text,text,text,timestamptz,timestamptz,timestamptz,text,text,text,jsonb,jsonb,text,integer,uuid)from public,anon;
grant execute on function public.e10_org_market_screener(uuid,text,text,text,text,timestamptz,timestamptz,timestamptz,text,text,text,jsonb,jsonb,text,integer,uuid)to authenticated,service_role;
comment on function public.e10_org_market_screener(uuid,text,text,text,text,timestamptz,timestamptz,timestamptz,text,text,text,jsonb,jsonb,text,integer,uuid)is'Bounded tenant market screener. Every call rechecks active membership/capability after revision locks and uses opaque server-side keyset cursor state.';
