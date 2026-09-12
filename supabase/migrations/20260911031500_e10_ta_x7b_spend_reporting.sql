-- TA-X7b bounded official-spend reads. Current-restated and revision-bound.

create function public.e10_org_customer_spend_contributions(
  p_org uuid,p_from timestamptz,p_to timestamptz,p_observation_cutoff timestamptz,
  p_currency text,p_customer uuid default null,p_purchase_kind text default null,
  p_location uuid default null,p_channel text default null,p_product uuid default null,
  p_configuration uuid default null,p_copy uuid default null,p_session uuid default null,
  p_capture_source text default null,p_limit integer default 100,
  p_after_occurred_at timestamptz default null,p_after_transaction_id uuid default null,
  p_after_line_id uuid default null,p_expected_dataset_revision bigint default null,
  p_expected_query_fingerprint text default null
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_revision bigint;v_fp text;v_items jsonb;v_totals jsonb;v_scope text;
  v_cursor_time timestamptz;v_cursor_tx uuid;
begin
  if not e10.can_view_any_customer_financials(p_org) then
    raise exception using errcode='42501',message='customer_spend_denied';
  end if;
  if p_from is null or p_to is null or p_observation_cutoff is null
     or not isfinite(p_from) or not isfinite(p_to) or not isfinite(p_observation_cutoff)
     or p_to<=p_from or p_to-p_from>interval '366 days'
     or p_to>p_observation_cutoff or p_observation_cutoff>clock_timestamp()
     or p_currency is null or p_currency!~'^[A-Z]{3}$'
     or(p_purchase_kind is not null and p_purchase_kind not in('retail','break','unclassified'))
     or(p_capture_source is not null and p_capture_source not in('manual','import','native'))
     or p_limit is null or p_limit not between 1 and 200
     or num_nonnulls(p_after_occurred_at,p_after_transaction_id,p_after_line_id) not in(0,3)
     or (p_after_line_id is not null and
       (p_expected_dataset_revision is null or p_expected_query_fingerprint is null)) then
    raise exception using errcode='22023',message='customer_spend_bounds_invalid';
  end if;
  if p_location is not null and not e10.can_view_customer_financials_at(p_org,p_location) then
    raise exception using errcode='42501',message='customer_spend_location_denied';
  end if;
  if p_customer is not null and not exists(
    select 1 from public.e10_customers c where c.organization_id=p_org and c.id=p_customer
      and e10.customer_effective_id(p_org,c.id)=c.id
  ) then raise exception using errcode='42501',message='customer_spend_filter_denied';end if;
  if p_product is not null and not exists(select 1 from public.e10_product_masters where organization_id=p_org and id=p_product)
     or p_configuration is not null and not exists(select 1 from public.e10_product_configuration_versions where organization_id=p_org and id=p_configuration)
     or p_copy is not null and not exists(select 1 from public.e10_unique_items where organization_id=p_org and id=p_copy)
     or p_session is not null and not exists(select 1 from public.e10_break_sessions where organization_id=p_org and id=p_session) then
    raise exception using errcode='42501',message='customer_spend_filter_denied';
  end if;
  select revision into v_revision from public.e10_reporting_dataset_revisions
    where organization_id=p_org for share;
  if not found then raise exception using errcode='55000',message='customer_spend_revision_missing';end if;
  if not e10.can_view_any_customer_financials(p_org)
     or (p_location is not null and not e10.can_view_customer_financials_at(p_org,p_location)) then
    raise exception using errcode='42501',message='customer_spend_denied';
  end if;
  if p_expected_dataset_revision is not null and p_expected_dataset_revision<>v_revision then
    raise exception using errcode='40001',message='customer_spend_revision_stale';
  end if;
  v_scope:=case when e10.has_org_cap(p_org,'act.view_customer_financials')
    then 'organization' else 'authorized_locations' end;
  v_fp:=md5(jsonb_build_object('metric','official-customer-spend-lines-v1','org',p_org,
    'from',p_from,'to',p_to,'cutoff',p_observation_cutoff,'currency',p_currency,
    'customer',p_customer,'kind',p_purchase_kind,'location',p_location,'channel',p_channel,
    'product',p_product,'configuration',p_configuration,'copy',p_copy,'session',p_session,
    'capture_source',p_capture_source,'authorization_scope',v_scope,'revision',v_revision)::text);
  if p_after_line_id is not null and p_expected_query_fingerprint<>v_fp then
    raise exception using errcode='22023',message='customer_spend_cursor_query_mismatch';
  end if;
  if p_after_line_id is not null then
    select r.occurred_at,r.transaction_id into v_cursor_time,v_cursor_tx
    from e10.official_customer_spend_contributions(
      p_org,p_from,p_to,p_observation_cutoff,p_currency,p_customer,p_purchase_kind,
      p_location,p_channel,p_product,p_configuration,p_copy,p_session,p_capture_source) r
    where r.transaction_line_id=p_after_line_id;
    if not found then raise exception using errcode='22023',message='customer_spend_cursor_invalid';end if;
  end if;
  with all_rows as materialized(
    select * from e10.official_customer_spend_contributions(
      p_org,p_from,p_to,p_observation_cutoff,p_currency,p_customer,p_purchase_kind,
      p_location,p_channel,p_product,p_configuration,p_copy,p_session,p_capture_source)
  ), page as(
    select * from all_rows r
    where p_after_line_id is null
       or(r.occurred_at,r.transaction_id,r.transaction_line_id)>
         (v_cursor_time,v_cursor_tx,p_after_line_id)
    order by r.occurred_at,r.transaction_id,r.transaction_line_id limit p_limit
  )
  select coalesce(jsonb_agg(to_jsonb(page) order by occurred_at,transaction_id,transaction_line_id),'[]'::jsonb)
    into v_items from page;
  with all_rows as materialized(
    select * from e10.official_customer_spend_contributions(
      p_org,p_from,p_to,p_observation_cutoff,p_currency,p_customer,p_purchase_kind,
      p_location,p_channel,p_product,p_configuration,p_copy,p_session,p_capture_source)
  )
  select jsonb_build_object(
    'line_count',count(*),
    'known_merchandise_line_count',count(*)filter(where merchandise_known),
    'unknown_merchandise_line_count',count(*)filter(where not merchandise_known),
    'known_official_merchandise_subtotal',coalesce(sum(official_net_merchandise)filter(where merchandise_known),0),
    'complete_official_merchandise_total',case when count(*)>0 and bool_and(merchandise_known) then sum(official_net_merchandise) else null end,
    'known_shipping_subtotal',coalesce(sum(official_shipping)filter(where shipping_known),0),
    'unknown_shipping_line_count',count(*)filter(where not shipping_known),
    'known_tax_subtotal',coalesce(sum(official_tax)filter(where tax_known),0),
    'unknown_tax_line_count',count(*)filter(where not tax_known),
    'distinct_orders',count(distinct transaction_id),
    'distinct_purchasing_breaks',count(distinct break_session_id)filter(where purchase_kind='break'),
    'missing_break_session_lines',count(*)filter(where purchase_kind='break' and break_session_id is null)
  ) into v_totals from all_rows;
  return jsonb_build_object('items',v_items,'totals',v_totals,'limit',p_limit,
    'metric_id','official_customer_spend_line_contributions','metric_version','official-spend-v1',
    'grain','posted_transaction_line','currency',p_currency,'observation_cutoff',p_observation_cutoff,
    'dataset_revision',v_revision,'query_fingerprint',v_fp,'authorization_scope',v_scope);
end $$;

create function public.e10_org_customer_spend_lineage(
  p_org uuid,p_transaction_line_id uuid,p_observation_cutoff timestamptz,
  p_limit integer default 100,p_after_recorded_at timestamptz default null,
  p_after_kind text default null,p_after_id uuid default null,
  p_expected_dataset_revision bigint default null,p_expected_query_fingerprint text default null
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_revision bigint;v_fp text;v_items jsonb;v_total bigint;v_delta jsonb;v_location uuid;
  v_cursor_time timestamptz;v_cursor_kind text;
begin
  if not e10.can_view_any_customer_financials(p_org) then
    raise exception using errcode='42501',message='customer_spend_lineage_denied';
  end if;
  if p_transaction_line_id is null or p_observation_cutoff is null or not isfinite(p_observation_cutoff)
     or p_observation_cutoff>clock_timestamp() or p_limit is null or p_limit not between 1 and 200
     or num_nonnulls(p_after_recorded_at,p_after_kind,p_after_id) not in(0,3)
     or(p_after_id is not null and(p_expected_dataset_revision is null or p_expected_query_fingerprint is null)) then
    raise exception using errcode='22023',message='customer_spend_lineage_bounds_invalid';
  end if;
  select location_id into v_location from public.e10_customer_transaction_lines
    where organization_id=p_org and id=p_transaction_line_id;
  if not found or not e10.can_view_customer_financials_at(p_org,v_location) then
    raise exception using errcode='42501',message='customer_spend_lineage_denied';
  end if;
  select revision into v_revision from public.e10_reporting_dataset_revisions
    where organization_id=p_org for share;
  if not found then raise exception using errcode='55000',message='customer_spend_revision_missing';end if;
  if not e10.can_view_customer_financials_at(p_org,v_location) then
    raise exception using errcode='42501',message='customer_spend_lineage_denied';
  end if;
  if p_expected_dataset_revision is not null and p_expected_dataset_revision<>v_revision then
    raise exception using errcode='40001',message='customer_spend_revision_stale';
  end if;
  v_fp:=md5(jsonb_build_object('metric','official-spend-lineage-v1','org',p_org,
    'line',p_transaction_line_id,'cutoff',p_observation_cutoff,'revision',v_revision)::text);
  if p_after_id is not null and p_expected_query_fingerprint<>v_fp then
    raise exception using errcode='22023',message='customer_spend_lineage_cursor_query_mismatch';
  end if;
  if p_after_id is not null then
    select z.recorded_at,z.kind into v_cursor_time,v_cursor_kind from(
      select a.created_at recorded_at,'adjustment'::text kind,a.id from public.e10_customer_transaction_adjustments a where a.organization_id=p_org and a.transaction_line_id=p_transaction_line_id
      union all select f.created_at,'finalization',f.id from public.e10_customer_transaction_component_finalizations f where f.organization_id=p_org and f.transaction_line_id=p_transaction_line_id
      union all select l.linked_at,'evidence_link',l.id from public.e10_customer_transaction_evidence_links l where l.organization_id=p_org and l.transaction_line_id=p_transaction_line_id
      union all select s.created_at,'source_claim',s.id from public.e10_customer_transaction_source_claims s where s.organization_id=p_org and s.posted_line_id=p_transaction_line_id
    )z where z.id=p_after_id and z.kind=p_after_kind;
    if not found then raise exception using errcode='22023',message='customer_spend_lineage_cursor_invalid';end if;
  end if;
  with lineage as materialized(
    select a.created_at recorded_at,'adjustment'::text kind,a.id,
      jsonb_build_object('adjustment_kind',a.adjustment_kind,'effect',a.effect,
        'merchandise_amount',a.merchandise_amount,'shipping_amount',a.shipping_amount,
        'tax_amount',a.tax_amount,'occurred_at',a.occurred_at,
        'reinstates_cancellation_id',a.reinstates_cancellation_id) data
    from public.e10_customer_transaction_adjustments a
    where a.organization_id=p_org and a.transaction_line_id=p_transaction_line_id
    union all
    select f.created_at,'finalization',f.id,jsonb_build_object('component',f.component,'final_amount',f.final_amount)
    from public.e10_customer_transaction_component_finalizations f
    where f.organization_id=p_org and f.transaction_line_id=p_transaction_line_id
    union all
    select l.linked_at,'evidence_link',l.id,jsonb_build_object('case_id',l.case_id,'decision_id',l.decision_id)
    from public.e10_customer_transaction_evidence_links l
    where l.organization_id=p_org and l.transaction_line_id=p_transaction_line_id
    union all
    select s.created_at,'source_claim',s.id,jsonb_build_object('source_kind',s.source_kind,
      'source_connection_id',s.source_connection_id,'source_line_id',s.source_line_id,
      'reconciliation_case_id',s.reconciliation_case_id)
    from public.e10_customer_transaction_source_claims s
    where s.organization_id=p_org and s.posted_line_id=p_transaction_line_id
  ), page as(
    select * from lineage x where p_after_id is null
      or(x.recorded_at,x.kind,x.id)>(v_cursor_time,v_cursor_kind,p_after_id)
    order by x.recorded_at,x.kind,x.id limit p_limit
  )
  select coalesce(jsonb_agg(jsonb_build_object('recorded_at',recorded_at,'kind',kind,'id',id,'data',data)
    order by recorded_at,kind,id),'[]'::jsonb) into v_items from page;
  select count(*),jsonb_build_object(
    'merchandise_delta',coalesce(sum(case effect when 'increase' then merchandise_amount else -merchandise_amount end),0),
    'shipping_delta',coalesce(sum(case effect when 'increase' then shipping_amount else -shipping_amount end),0),
    'tax_delta',coalesce(sum(case effect when 'increase' then tax_amount else -tax_amount end),0))
  into v_total,v_delta from public.e10_customer_transaction_adjustments
  where organization_id=p_org and transaction_line_id=p_transaction_line_id;
  v_total:=v_total
    +(select count(*) from public.e10_customer_transaction_component_finalizations where organization_id=p_org and transaction_line_id=p_transaction_line_id)
    +(select count(*) from public.e10_customer_transaction_evidence_links where organization_id=p_org and transaction_line_id=p_transaction_line_id)
    +(select count(*) from public.e10_customer_transaction_source_claims where organization_id=p_org and posted_line_id=p_transaction_line_id);
  return jsonb_build_object('items',v_items,'full_child_count',v_total,'full_adjustment_totals',v_delta,
    'limit',p_limit,'metric_version','official-spend-lineage-v1','observation_cutoff',p_observation_cutoff,
    'dataset_revision',v_revision,'query_fingerprint',v_fp);
end $$;

create function e10.customer_attendance_denominator(
  p_org uuid,p_customer uuid,p_from timestamptz,p_to timestamptz,
  p_observation_cutoff timestamptz,p_timezone text,p_week_start integer,p_session uuid
) returns table(attended_sessions bigint,coverage_complete boolean)
language plpgsql stable security definer set search_path=public as $$
declare v_all bigint;v_complete boolean;
begin
  if not e10.has_org_cap(p_org,'act.view_customer_engagement') then
    return query select null::bigint,false;
    return;
  end if;
  select coalesce(sum(w.distinct_attended_sessions),0),
    coalesce(bool_and(w.coverage_status='complete' and w.unknown_coverage_seconds=0),false)
  into v_all,v_complete
  from public.e10_org_weekly_attendance(
    p_org,p_from,p_to,p_observation_cutoff,p_timezone,p_week_start,p_customer,
    'companion','companion',54,null,null,null) w;
  if p_session is null then
    return query select v_all,v_complete;
  else
    return query select
      (case when exists(
        select 1 from public.e10_current_attendance_intervals i
        where i.organization_id=p_org and i.effective_customer_id=p_customer and i.session_id=p_session
        group by i.organization_id,i.effective_customer_id,i.session_id
        having min(i.original_started_at)>=p_from
          and min(i.original_started_at)<least(p_to,p_observation_cutoff)
      ) then 1 else 0 end)::bigint,v_complete;
  end if;
end $$;
revoke all on function e10.customer_attendance_denominator(
  uuid,uuid,timestamptz,timestamptz,timestamptz,text,integer,uuid
) from public,anon,authenticated;
grant execute on function e10.customer_attendance_denominator(
  uuid,uuid,timestamptz,timestamptz,timestamptz,text,integer,uuid
) to service_role;

create function public.e10_org_customer_spend_summary(
  p_org uuid,p_from timestamptz,p_to timestamptz,p_observation_cutoff timestamptz,
  p_currency text,p_timezone text,p_week_start integer,p_customer uuid default null,
  p_purchase_kind text default null,p_location uuid default null,p_channel text default null,
  p_product uuid default null,p_configuration uuid default null,p_copy uuid default null,
  p_session uuid default null,p_capture_source text default null,p_limit integer default 100,
  p_after_customer_id uuid default null,p_expected_dataset_revision bigint default null,
  p_expected_query_fingerprint text default null
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_revision bigint;v_fp text;v_items jsonb;v_totals jsonb;v_diagnostics jsonb;v_scope text;v_engagement boolean;v_sale_only boolean;
begin
  if not e10.can_view_any_customer_financials(p_org) then
    raise exception using errcode='42501',message='customer_spend_denied';
  end if;
  if p_from is null or p_to is null or p_observation_cutoff is null
     or not isfinite(p_from) or not isfinite(p_to) or not isfinite(p_observation_cutoff)
     or p_to<=p_from or p_to-p_from>interval '366 days' or p_to>p_observation_cutoff
     or p_observation_cutoff>clock_timestamp() or p_currency is null or p_currency!~'^[A-Z]{3}$'
     or p_timezone is null or not exists(select 1 from pg_timezone_names where name=p_timezone)
     or p_week_start is null or p_week_start not between 1 and 7
     or(p_purchase_kind is not null and p_purchase_kind not in('retail','break','unclassified'))
     or(p_capture_source is not null and p_capture_source not in('manual','import','native'))
     or p_limit is null or p_limit not between 1 and 200
     or(p_after_customer_id is not null and(p_expected_dataset_revision is null or p_expected_query_fingerprint is null)) then
    raise exception using errcode='22023',message='customer_spend_summary_bounds_invalid';
  end if;
  if p_location is not null and not e10.can_view_customer_financials_at(p_org,p_location) then
    raise exception using errcode='42501',message='customer_spend_location_denied';
  end if;
  if p_customer is not null and not exists(
    select 1 from public.e10_customers c where c.organization_id=p_org and c.id=p_customer
      and e10.customer_effective_id(p_org,c.id)=c.id
  ) then raise exception using errcode='42501',message='customer_spend_filter_denied';end if;
  if p_product is not null and not exists(select 1 from public.e10_product_masters where organization_id=p_org and id=p_product)
     or p_configuration is not null and not exists(select 1 from public.e10_product_configuration_versions where organization_id=p_org and id=p_configuration)
     or p_copy is not null and not exists(select 1 from public.e10_unique_items where organization_id=p_org and id=p_copy)
     or p_session is not null and not exists(select 1 from public.e10_break_sessions where organization_id=p_org and id=p_session) then
    raise exception using errcode='42501',message='customer_spend_filter_denied';
  end if;
  select revision into v_revision from public.e10_reporting_dataset_revisions
    where organization_id=p_org for share;
  if not found then raise exception using errcode='55000',message='customer_spend_revision_missing';end if;
  if not e10.can_view_any_customer_financials(p_org)
     or(p_location is not null and not e10.can_view_customer_financials_at(p_org,p_location)) then
    raise exception using errcode='42501',message='customer_spend_denied';
  end if;
  if p_expected_dataset_revision is not null and p_expected_dataset_revision<>v_revision then
    raise exception using errcode='40001',message='customer_spend_revision_stale';
  end if;
  v_scope:=case when e10.has_org_cap(p_org,'act.view_customer_financials')
    then 'organization' else 'authorized_locations' end;
  v_engagement:=e10.has_org_cap(p_org,'act.view_customer_engagement');
  v_sale_only:=v_scope<>'organization' or num_nonnulls(p_location,p_channel,p_product,p_configuration,p_copy,p_capture_source)>0;
  v_fp:=md5(jsonb_build_object('metric','official-customer-spend-summary-v1','org',p_org,
    'from',p_from,'to',p_to,'cutoff',p_observation_cutoff,'currency',p_currency,
    'timezone',p_timezone,'week_start',p_week_start,'customer',p_customer,
    'kind',p_purchase_kind,'location',p_location,'channel',p_channel,'product',p_product,
    'configuration',p_configuration,'copy',p_copy,'session',p_session,
    'capture_source',p_capture_source,'authorization_scope',v_scope,'revision',v_revision)::text);
  if p_after_customer_id is not null and p_expected_query_fingerprint<>v_fp then
    raise exception using errcode='22023',message='customer_spend_summary_cursor_query_mismatch';
  end if;
  with all_rows as materialized(
    select * from e10.official_customer_spend_contributions(
      p_org,p_from,p_to,p_observation_cutoff,p_currency,p_customer,p_purchase_kind,
      p_location,p_channel,p_product,p_configuration,p_copy,p_session,p_capture_source)
  ), grouped as(
    select r.effective_customer_id,
      count(*)::bigint line_count,count(distinct r.transaction_id)::bigint order_count,
      coalesce(sum(r.merchandise_gross),0) gross_total,
      coalesce(sum(r.merchandise_discount)filter(where r.merchandise_discount is not null),0) known_discount_total,
      count(*)filter(where r.merchandise_discount is null)::bigint unknown_discount_count,
      coalesce(sum(r.base_merchandise_net)filter(where r.base_merchandise_net is not null),0) known_pre_adjustment_total,
      coalesce(sum(r.merchandise_adjustment_delta),0) signed_adjustment_delta,
      coalesce(sum(r.official_net_merchandise)filter(where r.merchandise_known),0) known_total,
      case when bool_and(r.merchandise_known) then sum(r.official_net_merchandise) else null end complete_total,
      count(*)filter(where not r.merchandise_known)::bigint unknown_merchandise_count,
      coalesce(sum(r.official_shipping)filter(where r.shipping_known),0) known_shipping,
      count(*)filter(where not r.shipping_known)::bigint unknown_shipping_count,
      coalesce(sum(r.official_tax)filter(where r.tax_known),0) known_tax,
      count(*)filter(where not r.tax_known)::bigint unknown_tax_count,
      coalesce(sum(r.official_net_merchandise)filter(where r.purchase_kind='break' and r.merchandise_known),0) known_break_total,
      count(*)filter(where r.purchase_kind='break' and not r.merchandise_known)::bigint unknown_break_count,
      count(*)filter(where r.purchase_kind='break' and r.break_session_id is null)::bigint missing_break_session_count,
      count(distinct r.break_session_id)filter(where r.purchase_kind='break')::bigint purchasing_breaks,
      array_agg(distinct r.break_session_id)filter(where r.purchase_kind='break' and r.break_session_id is not null) purchase_sessions
    from all_rows r group by r.effective_customer_id
  ), enriched as(
    select g.*,ad.attended_sessions,ad.coverage_complete,
      exists(
        select 1 from unnest(coalesce(g.purchase_sessions,'{}'::uuid[])) ps
        where not exists(
          select 1 from public.e10_current_attendance_intervals i
          where i.organization_id=p_org and i.effective_customer_id=g.effective_customer_id
            and i.session_id=ps and i.original_started_at<p_to
            and least(i.original_ended_at,p_observation_cutoff)>p_from
        )
      ) purchase_session_not_observed
    from grouped g
    left join lateral e10.customer_attendance_denominator(
      p_org,g.effective_customer_id,p_from,p_to,p_observation_cutoff,p_timezone,p_week_start,p_session
    ) ad on v_engagement and not v_sale_only
  ), checked as(
    select *,count(*) over() full_customer_count,sum(line_count)over() full_line_count,
      sum(known_total)over() full_known_official_subtotal
    from enriched
  ), page as(
    select * from checked where p_after_customer_id is null or effective_customer_id>p_after_customer_id
    order by effective_customer_id limit p_limit
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'effective_customer_id',effective_customer_id,'line_count',line_count,'order_count',order_count,
    'merchandise_gross',gross_total,'known_merchandise_discount',known_discount_total,
    'unknown_discount_count',unknown_discount_count,'known_pre_adjustment_net',known_pre_adjustment_total,
    'signed_merchandise_adjustment_delta',signed_adjustment_delta,
    'known_official_subtotal',known_total,'complete_official_total',complete_total,
    'unknown_merchandise_count',unknown_merchandise_count,
    'known_shipping_subtotal',known_shipping,'unknown_shipping_count',unknown_shipping_count,
    'known_tax_subtotal',known_tax,'unknown_tax_count',unknown_tax_count,
    'known_break_subtotal',known_break_total,'unknown_break_count',unknown_break_count,
    'missing_break_session_count',missing_break_session_count,'purchasing_breaks',purchasing_breaks,
    'spend_per_purchasing_break',case when unknown_break_count=0 and missing_break_session_count=0 and purchasing_breaks>0 then known_break_total/purchasing_breaks else null end,
    'purchasing_ratio_status',case when unknown_break_count>0 then 'unknown_merchandise'
      when missing_break_session_count>0 then 'missing_session' when purchasing_breaks=0 then 'zero_denominator' else 'complete' end,
    'attended_breaks',case when v_engagement and not v_sale_only then attended_sessions else null end,
    'spend_per_attended_break',case when v_engagement and not v_sale_only and unknown_break_count=0
      and missing_break_session_count=0 and not purchase_session_not_observed and coverage_complete
      and attended_sessions>0 then known_break_total/attended_sessions else null end,
    'attended_ratio_status',case when not v_engagement then 'engagement_not_authorized'
      when v_sale_only then 'unsupported_cohort' when unknown_break_count>0 then 'unknown_merchandise'
      when missing_break_session_count>0 then 'missing_session'
      when purchase_session_not_observed then 'purchase_session_not_observed'
      when not coverage_complete then 'attendance_coverage_incomplete'
      when attended_sessions=0 then 'zero_denominator' else 'complete' end
  ) order by effective_customer_id),'[]'::jsonb),
    jsonb_build_object('customer_count',coalesce(max(full_customer_count),0),
      'line_count',coalesce(max(full_line_count),0),
      'known_official_subtotal',coalesce(max(full_known_official_subtotal),0))
    into v_items,v_totals from page;
  if p_after_customer_id is not null and not exists(
    select 1 from e10.official_customer_spend_contributions(
      p_org,p_from,p_to,p_observation_cutoff,p_currency,p_customer,p_purchase_kind,
      p_location,p_channel,p_product,p_configuration,p_copy,p_session,p_capture_source) r
    where r.effective_customer_id=p_after_customer_id
  ) then raise exception using errcode='22023',message='customer_spend_summary_cursor_invalid';end if;
  select jsonb_build_object(
    'unknown_occurrence_line_count',count(*)filter(where (t.occurred_at_precision='unknown' or t.occurred_at is null)
      and(p_customer is null or ea.effective_customer_id=p_customer)),
    'unattributed_org_authorized_line_count',case when p_customer is null then count(*)filter(where t.occurred_at_precision<>'unknown' and t.occurred_at is not null
      and t.occurred_at>=p_from and t.occurred_at<p_to and t.occurred_at<p_observation_cutoff
      and ea.effective_customer_id is null) else null end,
    'scope',case when p_customer is null then 'authorized_organization_cohort' else 'selected_effective_customer' end,
    'unassigned_diagnostics_scope','organization_only','unknown_occurrence_not_period_attributable',true
  ) into v_diagnostics
  from public.e10_customer_transactions t
  join public.e10_customer_transaction_lines l on(l.organization_id,l.transaction_id)=(t.organization_id,t.id)
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
  return jsonb_build_object('items',v_items,'limit',p_limit,'currency',p_currency,
    'metric_id','official_customer_spend_summary','metric_version','official-spend-v1',
    'grain','effective_customer','observation_cutoff',p_observation_cutoff,
    'dataset_revision',v_revision,'query_fingerprint',v_fp,'authorization_scope',v_scope,
    'purchase_kind_scope',coalesce(p_purchase_kind,'combined'),'full_cohort_totals',v_totals,
    'authorized_data_diagnostics',v_diagnostics);
end $$;

create table public.e10_customer_activity_source_components(
  organization_id uuid not null,
  activity_observation_id uuid not null,
  source_kind text not null check(source_kind in('manual','import','native')),
  source_connection_id text,
  source_event_id text not null check(btrim(source_event_id)<>''),
  source_component_id text not null check(btrim(source_component_id)<>''),
  mapping_reason text not null check(btrim(mapping_reason)<>''),
  idempotency_key text not null check(btrim(idempotency_key)<>''),
  request_fingerprint text not null check(btrim(request_fingerprint)<>''),
  mapped_by uuid references auth.users(id),mapped_at timestamptz not null default clock_timestamp(),
  primary key(organization_id,activity_observation_id),unique(organization_id,idempotency_key),
  foreign key(organization_id,activity_observation_id)
    references public.e10_customer_activity_observations(organization_id,id)
);
create unique index e10_customer_activity_source_component_identity_uq
  on public.e10_customer_activity_source_components(
    organization_id,source_kind,coalesce(source_connection_id,''),source_event_id,source_component_id
  );
alter table public.e10_customer_activity_source_components enable row level security;
revoke all on public.e10_customer_activity_source_components from public,anon,authenticated;
grant all on public.e10_customer_activity_source_components to service_role;
create trigger e10_customer_activity_source_component_append_only
  before update or delete on public.e10_customer_activity_source_components
  for each row execute function e10.reject_append_only_change();
create trigger e10_reporting_revision_customer_activity_source_component
  after insert on public.e10_customer_activity_source_components
  for each row execute function e10.bump_reporting_dataset_revision();

create function public.e10_org_bind_customer_activity_source_component(
  p_org uuid,p_activity uuid,p_source_component_id text,p_reason text,p_idempotency_key text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_activity record;v_fp text;v_existing record;v_result jsonb;
begin
  if not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.reconcile_customer_transactions') then
    raise exception using errcode='42501',message='customer_activity_source_mapping_denied';
  end if;
  if p_activity is null or p_source_component_id is null or btrim(p_source_component_id)=''
     or length(p_source_component_id)>500 or p_reason is null or btrim(p_reason)=''
     or length(p_reason)>2000 or p_idempotency_key is null or btrim(p_idempotency_key)=''
     or length(p_idempotency_key)>500 then
    raise exception using errcode='22023',message='customer_activity_source_mapping_invalid';
  end if;
  select source_kind,source_connection_id,source_event_id into v_activity
  from public.e10_customer_activity_observations where organization_id=p_org and id=p_activity;
  if not found then raise exception using errcode='42501',message='customer_activity_source_mapping_denied';end if;
  v_fp:=md5(jsonb_build_object('v','activity-source-component-v1','activity',p_activity,
    'source_kind',v_activity.source_kind,'connection',v_activity.source_connection_id,
    'event',v_activity.source_event_id,'component',btrim(p_source_component_id),'reason',btrim(p_reason))::text);
  perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|activity-source-map|'||p_idempotency_key,0));
  if not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.reconcile_customer_transactions') then
    raise exception using errcode='42501',message='customer_activity_source_mapping_denied';
  end if;
  select * into v_existing from public.e10_customer_activity_source_components
    where organization_id=p_org and idempotency_key=p_idempotency_key;
  if found then
    if v_existing.request_fingerprint<>v_fp then raise exception using errcode='22023',message='idempotency_key_mismatch';end if;
    return jsonb_build_object('ok',true,'replay',true,'activity_observation_id',v_existing.activity_observation_id,
      'source_event_id',v_existing.source_event_id,'source_component_id',v_existing.source_component_id);
  end if;
  insert into public.e10_customer_activity_source_components(
    organization_id,activity_observation_id,source_kind,source_connection_id,source_event_id,
    source_component_id,mapping_reason,idempotency_key,request_fingerprint,mapped_by
  ) values(p_org,p_activity,v_activity.source_kind,v_activity.source_connection_id,v_activity.source_event_id,
    btrim(p_source_component_id),btrim(p_reason),p_idempotency_key,v_fp,auth.uid());
  -- INSERT may wait on the immutable identity or revision rows. Recheck authority
  -- after every such wait before returning; an exception rolls the mapping back.
  if not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.reconcile_customer_transactions') then
    raise exception using errcode='42501',message='customer_activity_source_mapping_denied';
  end if;
  v_result:=jsonb_build_object('ok',true,'replay',false,'activity_observation_id',p_activity,
    'source_event_id',v_activity.source_event_id,'source_component_id',btrim(p_source_component_id));
  return v_result;
exception when unique_violation then
  raise exception using errcode='23505',message='customer_activity_source_component_already_mapped';
end $$;
revoke all on function public.e10_org_bind_customer_activity_source_component(uuid,uuid,text,text,text) from public,anon;
grant execute on function public.e10_org_bind_customer_activity_source_component(uuid,uuid,text,text,text) to authenticated,service_role;

comment on table public.e10_customer_activity_source_components is
  'Immutable reviewed source-component bindings. Incorrect bindings are not amended in place; correction requires a separately reviewed future workflow.';
comment on function public.e10_org_bind_customer_activity_source_component(uuid,uuid,text,text,text) is
  'Creates one immutable reviewed source-component binding. Replay is idempotent; correction/amendment is intentionally not implemented.';

create function public.e10_org_customer_provisional_activity(
  p_org uuid,p_from timestamptz,p_to timestamptz,p_observation_cutoff timestamptz,
  p_currency text,p_customer uuid default null,p_limit integer default 100,
  p_after_occurred_at timestamptz default null,p_after_activity_id uuid default null,
  p_expected_dataset_revision bigint default null,p_expected_query_fingerprint text default null
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_revision bigint;v_fp text;v_items jsonb;v_totals jsonb;v_cursor_time timestamptz;
begin
  if not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.view_customer_financials') then
    raise exception using errcode='42501',message='customer_provisional_activity_denied';
  end if;
  if p_from is null or p_to is null or p_observation_cutoff is null
     or not isfinite(p_from) or not isfinite(p_to) or not isfinite(p_observation_cutoff)
     or p_to<=p_from or p_to-p_from>interval '366 days' or p_to>p_observation_cutoff
     or p_observation_cutoff>clock_timestamp() or p_currency is null or p_currency!~'^[A-Z]{3}$'
     or p_limit is null or p_limit not between 1 and 200
     or num_nonnulls(p_after_occurred_at,p_after_activity_id) not in(0,2)
     or(p_after_activity_id is not null and(p_expected_dataset_revision is null or p_expected_query_fingerprint is null)) then
    raise exception using errcode='22023',message='customer_provisional_activity_bounds_invalid';
  end if;
  select revision into v_revision from public.e10_reporting_dataset_revisions
    where organization_id=p_org for share;
  if not found then raise exception using errcode='55000',message='customer_spend_revision_missing';end if;
  if not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.view_customer_financials') then
    raise exception using errcode='42501',message='customer_provisional_activity_denied';
  end if;
  if p_expected_dataset_revision is not null and p_expected_dataset_revision<>v_revision then
    raise exception using errcode='40001',message='customer_spend_revision_stale';
  end if;
  v_fp:=md5(jsonb_build_object('metric','provisional-customer-activity-v1','org',p_org,
    'from',p_from,'to',p_to,'cutoff',p_observation_cutoff,'currency',p_currency,
    'customer',p_customer,'revision',v_revision)::text);
  if p_after_activity_id is not null and p_expected_query_fingerprint<>v_fp then
    raise exception using errcode='22023',message='customer_provisional_cursor_query_mismatch';
  end if;
  if p_after_activity_id is not null then
    select a.occurred_at into v_cursor_time from public.e10_customer_activity_observations a
    left join public.e10_customer_activity_source_components m
      on(m.organization_id,m.activity_observation_id)=(a.organization_id,a.id)
    where a.organization_id=p_org and a.id=p_after_activity_id and a.currency=p_currency
      and a.occurred_at>=p_from and a.occurred_at<p_to and a.occurred_at<p_observation_cutoff
      and e10.customer_activity_effective_customer(p_org,a.id) is not null
      and(p_customer is null or e10.customer_effective_id(p_org,e10.customer_activity_effective_customer(p_org,a.id))=p_customer)
      and not exists(select 1 from public.e10_customer_transaction_lines l where l.organization_id=p_org and l.activity_observation_id=a.id)
      and not exists(select 1 from public.e10_customer_transaction_source_claims sc
        join public.e10_customer_transaction_reconciliation_cases rc
          on(rc.organization_id,rc.id)=(sc.organization_id,sc.reconciliation_case_id)
        left join lateral(select d.action from public.e10_customer_transaction_reconciliation_decisions d
          where d.organization_id=sc.organization_id and d.case_id=sc.reconciliation_case_id order by d.revision desc limit 1) latest on true
        where sc.organization_id=p_org and sc.source_kind=a.source_kind
          and coalesce(sc.source_connection_id,'')=coalesce(a.source_connection_id,'')
          and rc.source_event_id=m.source_event_id
          and rc.source_component_id=m.source_component_id
          and(sc.posted_line_id is not null or latest.action='link'));
    if not found then raise exception using errcode='22023',message='customer_provisional_cursor_invalid';end if;
  end if;
  with eligible as materialized(
    select a.id,e10.customer_effective_id(p_org,e10.customer_activity_effective_customer(p_org,a.id)) effective_customer_id,
      a.activity_kind,a.break_session_id,a.break_slot_id,a.quantity,a.merchandise_gross,
      a.merchandise_discount,a.merchandise_net,a.shipping_amount,a.tax_amount,a.currency,
      a.sale_method,a.occurred_at,a.occurred_at_precision,a.source_kind,a.source_connection_id,
      a.source_reference,a.evidence_quality,m.source_event_id,m.source_component_id,
      case when m.activity_observation_id is null then 'unmapped_source_component'
           else 'mapped_source_component' end posting_linkage_status
    from public.e10_customer_activity_observations a
    left join public.e10_customer_activity_source_components m
      on(m.organization_id,m.activity_observation_id)=(a.organization_id,a.id)
    where a.organization_id=p_org and a.currency=p_currency and a.occurred_at is not null
      and a.occurred_at>=p_from and a.occurred_at<p_to and a.occurred_at<p_observation_cutoff
      and e10.customer_activity_effective_customer(p_org,a.id) is not null
      and(p_customer is null or e10.customer_effective_id(p_org,e10.customer_activity_effective_customer(p_org,a.id))=p_customer)
      and not exists(select 1 from public.e10_customer_transaction_lines l
        where l.organization_id=p_org and l.activity_observation_id=a.id)
      and not exists(select 1 from public.e10_customer_transaction_source_claims sc
        join public.e10_customer_transaction_reconciliation_cases rc
          on(rc.organization_id,rc.id)=(sc.organization_id,sc.reconciliation_case_id)
        left join lateral(select d.action from public.e10_customer_transaction_reconciliation_decisions d
          where d.organization_id=sc.organization_id and d.case_id=sc.reconciliation_case_id order by d.revision desc limit 1) latest on true
        where sc.organization_id=p_org and sc.source_kind=a.source_kind
          and coalesce(sc.source_connection_id,'')=coalesce(a.source_connection_id,'')
          and rc.source_event_id=m.source_event_id
          and rc.source_component_id=m.source_component_id
          and(sc.posted_line_id is not null or latest.action='link'))
  ), page as(
    select * from eligible e where p_after_activity_id is null
      or(e.occurred_at,e.id)>(v_cursor_time,p_after_activity_id)
    order by e.occurred_at,e.id limit p_limit
  )
  select coalesce(jsonb_agg(to_jsonb(page) order by occurred_at,id),'[]'::jsonb) into v_items from page;
  with eligible as(
    select a.merchandise_net,a.shipping_amount,a.tax_amount,m.activity_observation_id mapped_activity_id
    from public.e10_customer_activity_observations a
    left join public.e10_customer_activity_source_components m
      on(m.organization_id,m.activity_observation_id)=(a.organization_id,a.id)
    where a.organization_id=p_org and a.currency=p_currency and a.occurred_at is not null
      and a.occurred_at>=p_from and a.occurred_at<p_to and a.occurred_at<p_observation_cutoff
      and e10.customer_activity_effective_customer(p_org,a.id) is not null
      and(p_customer is null or e10.customer_effective_id(p_org,e10.customer_activity_effective_customer(p_org,a.id))=p_customer)
      and not exists(select 1 from public.e10_customer_transaction_lines l where l.organization_id=p_org and l.activity_observation_id=a.id)
      and not exists(select 1 from public.e10_customer_transaction_source_claims sc
        join public.e10_customer_transaction_reconciliation_cases rc
          on(rc.organization_id,rc.id)=(sc.organization_id,sc.reconciliation_case_id)
        left join lateral(select d.action from public.e10_customer_transaction_reconciliation_decisions d
          where d.organization_id=sc.organization_id and d.case_id=sc.reconciliation_case_id order by d.revision desc limit 1) latest on true
        where sc.organization_id=p_org and sc.source_kind=a.source_kind
          and coalesce(sc.source_connection_id,'')=coalesce(a.source_connection_id,'')
          and rc.source_event_id=m.source_event_id
          and rc.source_component_id=m.source_component_id
          and(sc.posted_line_id is not null or latest.action='link'))
  )
  select jsonb_build_object('activity_count',count(*),
    'known_provisional_merchandise_subtotal',coalesce(sum(merchandise_net)filter(where merchandise_net is not null),0),
    'mapped_source_component_count',count(*)filter(where mapped_activity_id is not null),
    'unmapped_source_component_count',count(*)filter(where mapped_activity_id is null),
    'unknown_merchandise_count',count(*)filter(where merchandise_net is null),
    'known_shipping_subtotal',coalesce(sum(shipping_amount)filter(where shipping_amount is not null),0),
    'known_tax_subtotal',coalesce(sum(tax_amount)filter(where tax_amount is not null),0))
  into v_totals from eligible;
  return jsonb_build_object('items',v_items,'totals',v_totals,'limit',p_limit,
    'metric_id','provisional_customer_activity','metric_version','provisional-activity-v1',
    'grain','activity_observation','currency',p_currency,'observation_cutoff',p_observation_cutoff,
    'dataset_revision',v_revision,'query_fingerprint',v_fp,'official_spend',false);
end $$;

revoke all on function public.e10_org_customer_spend_contributions(
  uuid,timestamptz,timestamptz,timestamptz,text,uuid,text,uuid,text,uuid,uuid,uuid,uuid,text,
  integer,timestamptz,uuid,uuid,bigint,text
) from public,anon;
revoke all on function public.e10_org_customer_spend_lineage(
  uuid,uuid,timestamptz,integer,timestamptz,text,uuid,bigint,text
) from public,anon;
revoke all on function public.e10_org_customer_spend_summary(
  uuid,timestamptz,timestamptz,timestamptz,text,text,integer,uuid,text,uuid,text,uuid,uuid,uuid,uuid,text,
  integer,uuid,bigint,text
) from public,anon;
revoke all on function public.e10_org_customer_provisional_activity(
  uuid,timestamptz,timestamptz,timestamptz,text,uuid,integer,timestamptz,uuid,bigint,text
) from public,anon;
grant execute on function public.e10_org_customer_spend_contributions(
  uuid,timestamptz,timestamptz,timestamptz,text,uuid,text,uuid,text,uuid,uuid,uuid,uuid,text,
  integer,timestamptz,uuid,uuid,bigint,text
) to authenticated,service_role;
grant execute on function public.e10_org_customer_spend_lineage(
  uuid,uuid,timestamptz,integer,timestamptz,text,uuid,bigint,text
) to authenticated,service_role;
grant execute on function public.e10_org_customer_spend_summary(
  uuid,timestamptz,timestamptz,timestamptz,text,text,integer,uuid,text,uuid,text,uuid,uuid,uuid,uuid,text,
  integer,uuid,bigint,text
) to authenticated,service_role;
grant execute on function public.e10_org_customer_provisional_activity(
  uuid,timestamptz,timestamptz,timestamptz,text,uuid,integer,timestamptz,uuid,bigint,text
) to authenticated,service_role;

comment on function public.e10_org_customer_spend_contributions(
  uuid,timestamptz,timestamptz,timestamptz,text,uuid,text,uuid,text,uuid,uuid,uuid,uuid,text,
  integer,timestamptz,uuid,uuid,bigint,text
) is 'Bounded authorized official posted-line detail. Totals use the complete eligible cohort, never the current page.';
comment on function public.e10_org_customer_spend_lineage(
  uuid,uuid,timestamptz,integer,timestamptz,text,uuid,bigint,text
) is 'Bounded child lineage for one authorized posted line with full-child counts and adjustment totals repeated on every page.';
comment on function public.e10_org_customer_spend_summary(
  uuid,timestamptz,timestamptz,timestamptz,text,text,integer,uuid,text,uuid,text,uuid,uuid,uuid,uuid,text,
  integer,uuid,bigint,text
) is 'Current-restated official customer spend. Purchasing and attendance denominators are named, cohort-compatible and NULL when incomplete.';
comment on function public.e10_org_customer_provisional_activity(
  uuid,timestamptz,timestamptz,timestamptz,text,uuid,integer,timestamptz,uuid,bigint,text
) is 'Bounded unposted operational activity, explicitly provisional and excluded from official spend.';
