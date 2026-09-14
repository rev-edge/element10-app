-- TA-X7f staging performance corrective. The full contribution projection builds
-- adjustment, finalization and evidence arrays that do not affect row eligibility.
-- This private helper retains the exact eligibility predicate while stopping at the
-- fixed 100001-row resource boundary before those expensive projections run.

create function e10.customer_spend_contribution_count_bounded(
  p_org uuid,p_from timestamptz,p_to timestamptz,p_observation_cutoff timestamptz,
  p_currency text,p_customer uuid default null,p_purchase_kind text default null,
  p_location uuid default null,p_channel text default null,p_product uuid default null,
  p_configuration uuid default null,p_copy uuid default null,p_session uuid default null,
  p_capture_source text default null
) returns bigint language sql stable security definer set search_path=public as $$
  select count(*)::bigint from(
    select 1
    from public.e10_customer_transactions t
    join public.e10_customer_transaction_lines l
      on(l.organization_id,l.transaction_id)=(t.organization_id,t.id)
    cross join lateral e10.customer_transaction_effective_attribution(p_org,t.id) ea
    where t.organization_id=p_org
      and t.currency=p_currency
      and t.occurred_at_precision<>'unknown' and t.occurred_at is not null
      and t.occurred_at>=p_from and t.occurred_at<p_to
      and t.occurred_at<p_observation_cutoff
      and ea.effective_customer_id is not null
      and(p_customer is null or ea.effective_customer_id=p_customer)
      and(p_purchase_kind is null or l.purchase_kind=p_purchase_kind)
      and(p_location is null or l.location_id=p_location)
      and(p_channel is null or l.sales_channel=p_channel)
      and(p_product is null or l.product_master_id=p_product)
      and(p_configuration is null or l.configuration_version_id=p_configuration)
      and(p_copy is null or l.unique_item_id=p_copy)
      and(p_session is null or l.break_session_id=p_session)
      and(p_capture_source is null or l.capture_source=p_capture_source)
      and e10.can_view_customer_financials_at(p_org,l.location_id)
    limit 100001
  )bounded
$$;
revoke all on function e10.customer_spend_contribution_count_bounded(
  uuid,timestamptz,timestamptz,timestamptz,text,uuid,text,uuid,text,uuid,uuid,uuid,uuid,text
)from public,anon,authenticated;
grant execute on function e10.customer_spend_contribution_count_bounded(
  uuid,timestamptz,timestamptz,timestamptz,text,uuid,text,uuid,text,uuid,uuid,uuid,uuid,text
)to service_role;
comment on function e10.customer_spend_contribution_count_bounded(
  uuid,timestamptz,timestamptz,timestamptz,text,uuid,text,uuid,text,uuid,uuid,uuid,uuid,text
)is 'Private fixed-cap eligibility counter for the X7f known-history resource guard; eligibility predicate mirrors official_customer_spend_contributions.';

create or replace function public.e10_org_customer_spend_grid_v2(
  p_org uuid,p_window_mode text,p_from timestamptz,p_to timestamptz,
  p_observation_cutoff timestamptz,p_currency text,p_timezone text,p_week_start integer,
  p_customer uuid default null,p_purchase_kind text default null,p_location uuid default null,
  p_channel text default null,p_product uuid default null,p_configuration uuid default null,
  p_copy uuid default null,p_session uuid default null,p_capture_source text default null,
  p_min_known_official_subtotal numeric default null,
  p_max_known_official_subtotal numeric default null,
  p_sort text default 'customer_id_asc',p_limit integer default 100,p_cursor jsonb default null,
  p_expected_dataset_revision bigint default null,p_expected_query_fingerprint text default null
) returns jsonb language plpgsql security definer set search_path=public as $$
declare
  v_from timestamptz;v_revision bigint;v_scope text;v_fp text;v_count bigint;
  v_anchor_count bigint;v_anchor_num numeric;
  v_result jsonb;v_diagnostics jsonb;v_cursor jsonb;v_cursor_id uuid;v_cursor_num numeric;
  v_cursor_norm text;v_cursor_name text;v_engagement boolean;v_sale_only boolean;
begin
  if p_cursor='null'::jsonb then p_cursor:=null;end if;
  if p_cursor is not null and(jsonb_typeof(p_cursor)<>'object'
     or exists(select 1 from jsonb_object_keys(p_cursor)k where k<>all(array['sort','fingerprint','effective_customer_id','known_official_subtotal','normalized_display_name','display_name']))
     or jsonb_typeof(p_cursor->'sort')<>'string' or jsonb_typeof(p_cursor->'fingerprint')<>'string'
     or jsonb_typeof(p_cursor->'effective_customer_id')<>'string')then
    raise exception using errcode='22023',message='customer_spend_grid_cursor_invalid';end if;
  if not e10.can_view_any_customer_financials(p_org) then
    raise exception using errcode='42501',message='customer_spend_denied';
  end if;
  if p_window_mode is null or p_window_mode not in('bounded','known_history') or p_to is null
     or p_observation_cutoff is null or not isfinite(p_to) or not isfinite(p_observation_cutoff)
     or p_to>p_observation_cutoff or p_observation_cutoff>clock_timestamp()
     or (p_window_mode='bounded' and(p_from is null or not isfinite(p_from) or p_to<=p_from or p_to-p_from>interval '366 days'))
     or (p_window_mode='known_history' and p_from is not null)
     or p_currency is null or p_currency!~'^[A-Z]{3}$'
     or p_timezone is null or not exists(select 1 from pg_timezone_names where name=p_timezone)
     or p_week_start is null or p_week_start not between 1 and 7
     or(p_purchase_kind is not null and p_purchase_kind not in('retail','break','unclassified'))
     or(p_capture_source is not null and p_capture_source not in('manual','import','native'))
     or p_sort is null or p_sort not in('customer_id_asc','display_name_asc','known_official_subtotal_asc','known_official_subtotal_desc')
     or p_limit is null or p_limit not between 1 and 200
     or(p_min_known_official_subtotal is not null and p_min_known_official_subtotal::text in('NaN','Infinity','-Infinity'))
     or(p_max_known_official_subtotal is not null and p_max_known_official_subtotal::text in('NaN','Infinity','-Infinity'))
     or(p_min_known_official_subtotal is not null and p_max_known_official_subtotal is not null and p_min_known_official_subtotal>p_max_known_official_subtotal)
     or(p_cursor is not null and(p_expected_dataset_revision is null or p_expected_query_fingerprint is null)) then
    raise exception using errcode='22023',message='customer_spend_grid_bounds_invalid';
  end if;
  if p_location is not null and not e10.can_view_customer_financials_at(p_org,p_location) then
    raise exception using errcode='42501',message='customer_spend_location_denied';
  end if;
  if p_customer is not null and not exists(select 1 from public.e10_customers c where c.organization_id=p_org and c.id=p_customer and e10.customer_effective_id(p_org,c.id)=c.id) then
    raise exception using errcode='42501',message='customer_spend_filter_denied';
  end if;
  v_from:=case when p_window_mode='known_history' then '-infinity'::timestamptz else p_from end;
  select revision into v_revision from public.e10_reporting_dataset_revisions where organization_id=p_org for share;
  if not found then raise exception using errcode='55000',message='customer_spend_revision_missing';end if;
  if not e10.can_view_any_customer_financials(p_org) or(p_location is not null and not e10.can_view_customer_financials_at(p_org,p_location)) then
    raise exception using errcode='42501',message='customer_spend_denied';
  end if;
  if p_expected_dataset_revision is not null and p_expected_dataset_revision<>v_revision then
    raise exception using errcode='40001',message='customer_spend_revision_stale';end if;
  v_scope:=case when e10.has_org_cap(p_org,'act.view_customer_financials') then 'organization' else 'authorized_locations'end;
  v_engagement:=e10.has_org_cap(p_org,'act.view_customer_engagement');
  v_sale_only:=v_scope<>'organization' or num_nonnulls(p_location,p_channel,p_product,p_configuration,p_copy,p_capture_source)>0;
  v_fp:=encode(sha256(convert_to(jsonb_build_object('metric','official-customer-spend-grid-v2','org',p_org,'actor',auth.uid(),'scope',v_scope,'mode',p_window_mode,'from',p_from,'to',p_to,'cutoff',p_observation_cutoff,'currency',p_currency,'timezone',p_timezone,'week_start',p_week_start,'customer',p_customer,'kind',p_purchase_kind,'location',p_location,'channel',p_channel,'product',p_product,'configuration',p_configuration,'copy',p_copy,'session',p_session,'capture_source',p_capture_source,'min',p_min_known_official_subtotal,'max',p_max_known_official_subtotal,'sort',p_sort,'revision',v_revision)::text,'UTF8')),'hex');
  if p_cursor is not null and(p_expected_query_fingerprint is distinct from v_fp or p_cursor->>'fingerprint' is distinct from v_fp or p_cursor->>'sort' is distinct from p_sort) then
    raise exception using errcode='22023',message='customer_spend_grid_cursor_query_mismatch';end if;
  begin
    if p_cursor is not null then
      v_cursor_id:=(p_cursor->>'effective_customer_id')::uuid;
      v_cursor_num:=(p_cursor->>'known_official_subtotal')::numeric;
      if v_cursor_id is null then raise exception using errcode='22023';end if;
      if p_customer is not null and v_cursor_id is distinct from p_customer then raise exception using errcode='22023';end if;
    end if;
  exception when others then raise exception using errcode='22023',message='customer_spend_grid_cursor_invalid';end;
  if p_window_mode='known_history' then
    select e10.customer_spend_contribution_count_bounded(p_org,v_from,p_to,p_observation_cutoff,p_currency,p_customer,p_purchase_kind,p_location,p_channel,p_product,p_configuration,p_copy,p_session,p_capture_source) into v_count;
    if v_count>100000 then raise exception using errcode='54000',message='customer_spend_known_history_resource_limit';end if;
  end if;
  if p_cursor is not null then
    select count(*),coalesce(sum(r.official_net_merchandise)filter(where r.merchandise_known),0)
      into v_anchor_count,v_anchor_num
    from e10.official_customer_spend_contributions(
      p_org,v_from,p_to,p_observation_cutoff,p_currency,v_cursor_id,p_purchase_kind,
      p_location,p_channel,p_product,p_configuration,p_copy,p_session,p_capture_source)r;
    if v_anchor_count=0
       or(p_min_known_official_subtotal is not null and v_anchor_num<p_min_known_official_subtotal)
       or(p_max_known_official_subtotal is not null and v_anchor_num>p_max_known_official_subtotal)
       or(p_sort in('known_official_subtotal_asc','known_official_subtotal_desc')
          and v_cursor_num is distinct from v_anchor_num) then
      raise exception using errcode='22023',message='customer_spend_grid_cursor_invalid';
    end if;
    v_cursor_num:=v_anchor_num;
    if p_sort='display_name_asc'then
      select lower(c.display_name)collate"C",c.display_name into v_cursor_norm,v_cursor_name
      from public.e10_customers c where(c.organization_id,c.id)=(p_org,v_cursor_id);
      if not found then raise exception using errcode='22023',message='customer_spend_grid_cursor_invalid';end if;
    end if;
  end if;
  with raw as materialized(
    select * from e10.official_customer_spend_contributions(p_org,v_from,p_to,p_observation_cutoff,p_currency,p_customer,p_purchase_kind,p_location,p_channel,p_product,p_configuration,p_copy,p_session,p_capture_source)
  ), grouped as(
    select r.effective_customer_id,count(*)::bigint line_count,count(distinct r.transaction_id)::bigint order_count,
      coalesce(sum(r.merchandise_gross),0) merchandise_gross,
      coalesce(sum(r.merchandise_discount)filter(where r.merchandise_discount is not null),0) known_merchandise_discount,
      count(*)filter(where r.merchandise_discount is null)::bigint unknown_discount_count,
      coalesce(sum(r.base_merchandise_net)filter(where r.base_merchandise_net is not null),0) known_pre_adjustment_net,
      coalesce(sum(r.merchandise_adjustment_delta),0) signed_merchandise_adjustment_delta,
      coalesce(sum(r.official_net_merchandise)filter(where r.merchandise_known),0) known_official_subtotal,
      case when bool_and(r.merchandise_known)then sum(r.official_net_merchandise)end complete_official_total,
      count(*)filter(where not r.merchandise_known)::bigint unknown_merchandise_count,
      coalesce(sum(r.official_shipping)filter(where r.shipping_known),0) known_shipping_subtotal,
      count(*)filter(where not r.shipping_known)::bigint unknown_shipping_count,
      coalesce(sum(r.official_tax)filter(where r.tax_known),0) known_tax_subtotal,
      count(*)filter(where not r.tax_known)::bigint unknown_tax_count,
      coalesce(sum(r.official_net_merchandise)filter(where r.purchase_kind='break'and r.merchandise_known),0) known_break_total,
      count(*)filter(where r.purchase_kind='break'and not r.merchandise_known)::bigint unknown_break_count,
      count(*)filter(where r.purchase_kind='break'and r.break_session_id is null)::bigint missing_break_session_count,
      count(distinct r.break_session_id)filter(where r.purchase_kind='break')::bigint purchasing_breaks,
      array_agg(distinct r.break_session_id)filter(where r.purchase_kind='break'and r.break_session_id is not null) purchase_sessions,
      min(r.occurred_at) earliest_contribution
    from raw r group by r.effective_customer_id
  ), enriched as(
    select g.*,ad.attended_sessions,ad.coverage_complete,
      exists(select 1 from unnest(coalesce(g.purchase_sessions,'{}'::uuid[])) ps
        where not exists(select 1 from public.e10_current_attendance_intervals i
          where i.organization_id=p_org and i.effective_customer_id=g.effective_customer_id
            and i.session_id=ps and i.original_started_at<p_to
            and least(i.original_ended_at,p_observation_cutoff)>v_from)) purchase_session_not_observed
    from grouped g left join lateral e10.customer_attendance_denominator_if_bounded(
      p_window_mode,p_org,g.effective_customer_id,v_from,p_to,p_observation_cutoff,
      p_timezone,p_week_start,p_session
    )ad on v_engagement and not v_sale_only
  ), filtered as(
    select e.*,c.display_name,lower(c.display_name)collate"C" normalized_display_name
    from enriched e join public.e10_customers c on(c.organization_id,c.id)=(p_org,e.effective_customer_id)
    where(p_min_known_official_subtotal is null or e.known_official_subtotal>=p_min_known_official_subtotal)
      and(p_max_known_official_subtotal is null or e.known_official_subtotal<=p_max_known_official_subtotal)
  ), scoped as(
    select f.*,count(*)over() full_customer_count,sum(line_count)over() full_line_count,
      sum(known_official_subtotal)over() full_known_official_subtotal
    from filtered f
  ), eligible as(
    select * from scoped f where p_cursor is null or case p_sort
      when'customer_id_asc'then f.effective_customer_id>v_cursor_id
      when'known_official_subtotal_asc'then(f.known_official_subtotal,f.effective_customer_id)>(v_cursor_num,v_cursor_id)
      when'known_official_subtotal_desc'then f.known_official_subtotal<v_cursor_num or(f.known_official_subtotal=v_cursor_num and f.effective_customer_id>v_cursor_id)
      when'display_name_asc'then case when v_cursor_name is null
        then f.display_name is null and f.effective_customer_id>v_cursor_id
        else f.display_name is null or(f.normalized_display_name,f.display_name collate"C",f.effective_customer_id)>(v_cursor_norm,v_cursor_name collate"C",v_cursor_id)end end
  ), ordered as(
    select eligible.*,row_number()over(order by
      case when p_sort='customer_id_asc'then effective_customer_id end asc,
      case when p_sort='display_name_asc'then display_name is null end asc,
      case when p_sort='display_name_asc'then normalized_display_name end asc,
      case when p_sort='display_name_asc'then display_name collate"C"end asc,
      case when p_sort='known_official_subtotal_asc'then known_official_subtotal end asc,
      case when p_sort='known_official_subtotal_desc'then known_official_subtotal end desc,
      effective_customer_id asc)rn from eligible
  ), page as(select * from ordered where rn<=p_limit+1),
  kept as(select * from page where rn<=p_limit),
  last_row as(select * from kept order by rn desc limit 1)
  select jsonb_build_object('items',coalesce((select jsonb_agg(jsonb_build_object('effective_customer_id',effective_customer_id,'display_name',display_name,'line_count',line_count,'order_count',order_count,'merchandise_gross',merchandise_gross,'known_merchandise_discount',known_merchandise_discount,'unknown_discount_count',unknown_discount_count,'known_pre_adjustment_net',known_pre_adjustment_net,'signed_merchandise_adjustment_delta',signed_merchandise_adjustment_delta,'known_official_subtotal',known_official_subtotal,'complete_official_total',complete_official_total,'unknown_merchandise_count',unknown_merchandise_count,'known_shipping_subtotal',known_shipping_subtotal,'unknown_shipping_count',unknown_shipping_count,'known_tax_subtotal',known_tax_subtotal,'unknown_tax_count',unknown_tax_count,'known_break_subtotal',known_break_total,'unknown_break_count',unknown_break_count,'missing_break_session_count',missing_break_session_count,'purchasing_breaks',purchasing_breaks,'spend_per_purchasing_break',case when unknown_break_count=0 and missing_break_session_count=0 and purchasing_breaks>0 then known_break_total/purchasing_breaks end,'purchasing_ratio_status',case when unknown_break_count>0 then'unknown_merchandise'when missing_break_session_count>0 then'missing_session'when purchasing_breaks=0 then'zero_denominator'else'complete'end,'attended_breaks',case when p_window_mode='bounded'and v_engagement and not v_sale_only then attended_sessions end,'spend_per_attended_break',case when p_window_mode='bounded'and v_engagement and not v_sale_only and unknown_break_count=0 and missing_break_session_count=0 and not purchase_session_not_observed and coverage_complete and attended_sessions>0 then known_break_total/attended_sessions end,'attended_ratio_status',case when p_window_mode='known_history'then'unsupported_known_history_window'when not v_engagement then'engagement_not_authorized'when v_sale_only then'unsupported_cohort'when unknown_break_count>0 then'unknown_merchandise'when missing_break_session_count>0 then'missing_session'when purchase_session_not_observed then'purchase_session_not_observed'when not coverage_complete then'attendance_coverage_incomplete'when attended_sessions=0 then'zero_denominator'else'complete'end) order by rn)from kept),'[]'::jsonb),'full_cohort_totals',coalesce((select jsonb_build_object('customer_count',coalesce(max(full_customer_count),0),'line_count',coalesce(max(full_line_count),0),'known_official_subtotal',coalesce(max(full_known_official_subtotal),0))from scoped),'{"customer_count":0,"line_count":0,"known_official_subtotal":0}'::jsonb),'has_more',(select count(*)>p_limit from page),'next_cursor',case when(select count(*)>p_limit from page)then(select jsonb_build_object('sort',p_sort,'fingerprint',v_fp,'effective_customer_id',effective_customer_id,'known_official_subtotal',known_official_subtotal,'normalized_display_name',normalized_display_name,'display_name',display_name)from last_row)end,'metric_id','official_customer_spend_grid','metric_version','official-spend-grid-v2','currency',p_currency,'window_mode',p_window_mode,'observation_cutoff',p_observation_cutoff,'dataset_revision',v_revision,'query_fingerprint',v_fp,'authorization_scope',v_scope,'coverage',jsonb_build_object('requested_from',p_from,'requested_to',p_to,'effective_start',(select min(earliest_contribution)from filtered),'effective_end',least(p_to,p_observation_cutoff),'limitation','known_recorded_posted_history_only','source_history_completeness','unknown')) into v_result;
  select jsonb_build_object(
    'unknown_occurrence_line_count',count(*)filter(where
      (t.occurred_at_precision='unknown' or t.occurred_at is null)
      and ea.effective_customer_id is not null
      and(p_customer is null or ea.effective_customer_id=p_customer)),
    'unattributed_authorized_line_count',case when p_customer is null then count(*)filter(where
      t.occurred_at_precision<>'unknown' and t.occurred_at is not null
      and t.occurred_at>=v_from and t.occurred_at<p_to and t.occurred_at<p_observation_cutoff
      and ea.effective_customer_id is null)else null end,
    'scope',case when p_customer is null then'authorized_filtered_cohort'else'selected_effective_customer'end,
    'source_history_completeness','unknown',
    'unknown_occurrence_not_period_attributable',true
  ) into v_diagnostics
  from public.e10_customer_transactions t
  join public.e10_customer_transaction_lines l
    on(l.organization_id,l.transaction_id)=(t.organization_id,t.id)
  cross join lateral e10.customer_transaction_effective_attribution(p_org,t.id) ea
  where t.organization_id=p_org and t.currency=p_currency
    and e10.can_view_customer_financials_at(p_org,l.location_id)
    and(p_purchase_kind is null or l.purchase_kind=p_purchase_kind)
    and(p_location is null or l.location_id=p_location)
    and(p_channel is null or l.sales_channel=p_channel)
    and(p_product is null or l.product_master_id=p_product)
    and(p_configuration is null or l.configuration_version_id=p_configuration)
    and(p_copy is null or l.unique_item_id=p_copy)
    and(p_session is null or l.break_session_id=p_session)
    and(p_capture_source is null or l.capture_source=p_capture_source);
  return v_result||jsonb_build_object('authorized_data_diagnostics',v_diagnostics);
end $$;

revoke all on function public.e10_org_customer_spend_grid_v2(uuid,text,timestamptz,timestamptz,timestamptz,text,text,integer,uuid,text,uuid,text,uuid,uuid,uuid,uuid,text,numeric,numeric,text,integer,jsonb,bigint,text) from public,anon;
grant execute on function public.e10_org_customer_spend_grid_v2(uuid,text,timestamptz,timestamptz,timestamptz,text,text,integer,uuid,text,uuid,text,uuid,uuid,uuid,uuid,text,numeric,numeric,text,integer,jsonb,bigint,text) to authenticated,service_role;
