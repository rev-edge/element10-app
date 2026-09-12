-- TA-X7f staging performance corrective, revision 4. Snapshot the caller's
-- financial scope once per private helper invocation instead of re-running the
-- authorization predicates for every contribution line.

create or replace function e10.customer_spend_contribution_count_bounded(
  p_org uuid,p_from timestamptz,p_to timestamptz,p_observation_cutoff timestamptz,
  p_currency text,p_customer uuid default null,p_purchase_kind text default null,
  p_location uuid default null,p_channel text default null,p_product uuid default null,
  p_configuration uuid default null,p_copy uuid default null,p_session uuid default null,
  p_capture_source text default null
) returns bigint language sql stable security definer set search_path=public as $$
  with permission_context as materialized(
    select e10.is_org_member(p_org)is_member,
      e10.has_org_cap(p_org,'act.view_customer_financials')org_wide
  ),allowed_locations as materialized(
    select distinct lp.location_id
    from public.e10_organization_memberships m
    join public.e10_location_role_permissions lp
      on lp.organization_id=m.organization_id and lp.role_id=m.role_id
    join public.e10_locations location_scope
      on(location_scope.organization_id,location_scope.id)=(lp.organization_id,lp.location_id)
    where m.organization_id=p_org and m.user_id=auth.uid() and m.status='active'
      and lp.can_view_customer_financials and location_scope.status='active'
  ),eligible_transactions as materialized(
    select t.id,ea.effective_customer_id
    from public.e10_customer_transactions t
    cross join lateral e10.customer_transaction_effective_attribution(p_org,t.id)ea
    where t.organization_id=p_org and t.currency=p_currency
      and t.occurred_at_precision<>'unknown' and t.occurred_at is not null
      and t.occurred_at>=p_from and t.occurred_at<p_to
      and t.occurred_at<p_observation_cutoff
      and ea.effective_customer_id is not null
      and(p_customer is null or ea.effective_customer_id=p_customer)
  ),bounded as(
    select 1
    from eligible_transactions t
    join public.e10_customer_transaction_lines l
      on l.organization_id=p_org and l.transaction_id=t.id
    cross join permission_context pc
    left join public.e10_locations line_location
      on(line_location.organization_id,line_location.id)=(p_org,l.location_id)
    where(p_purchase_kind is null or l.purchase_kind=p_purchase_kind)
      and(p_location is null or l.location_id=p_location)
      and(p_channel is null or l.sales_channel=p_channel)
      and(p_product is null or l.product_master_id=p_product)
      and(p_configuration is null or l.configuration_version_id=p_configuration)
      and(p_copy is null or l.unique_item_id=p_copy)
      and(p_session is null or l.break_session_id=p_session)
      and(p_capture_source is null or l.capture_source=p_capture_source)
      and pc.is_member and(
        (l.location_id is null and pc.org_wide)
        or(l.location_id is not null and line_location.id is not null and(
          pc.org_wide or exists(select 1 from allowed_locations a where a.location_id=l.location_id)
        ))
      )
    limit 100001
  )select count(*)::bigint from bounded
$$;
revoke all on function e10.customer_spend_contribution_count_bounded(uuid,timestamptz,timestamptz,timestamptz,text,uuid,text,uuid,text,uuid,uuid,uuid,uuid,text)from public,anon,authenticated;
grant execute on function e10.customer_spend_contribution_count_bounded(uuid,timestamptz,timestamptz,timestamptz,text,uuid,text,uuid,text,uuid,uuid,uuid,uuid,text)to service_role;

create or replace function e10.customer_spend_grid_contributions(
  p_org uuid,p_from timestamptz,p_to timestamptz,p_observation_cutoff timestamptz,
  p_currency text,p_customer uuid default null,p_purchase_kind text default null,
  p_location uuid default null,p_channel text default null,p_product uuid default null,
  p_configuration uuid default null,p_copy uuid default null,p_session uuid default null,
  p_capture_source text default null
) returns table(
  effective_customer_id uuid,transaction_id uuid,transaction_line_id uuid,
  purchase_kind text,break_session_id uuid,occurred_at timestamptz,
  merchandise_gross numeric,merchandise_discount numeric,base_merchandise_net numeric,
  merchandise_adjustment_delta numeric,official_net_merchandise numeric,
  official_shipping numeric,official_tax numeric,merchandise_known boolean,
  shipping_known boolean,tax_known boolean
)language sql stable security definer set search_path=public as $$
  with permission_context as materialized(
    select e10.is_org_member(p_org)is_member,
      e10.has_org_cap(p_org,'act.view_customer_financials')org_wide
  ),allowed_locations as materialized(
    select distinct lp.location_id
    from public.e10_organization_memberships m
    join public.e10_location_role_permissions lp
      on lp.organization_id=m.organization_id and lp.role_id=m.role_id
    join public.e10_locations location_scope
      on(location_scope.organization_id,location_scope.id)=(lp.organization_id,lp.location_id)
    where m.organization_id=p_org and m.user_id=auth.uid() and m.status='active'
      and lp.can_view_customer_financials and location_scope.status='active'
  ),eligible_transactions as materialized(
    select t.id,t.occurred_at,ea.effective_customer_id
    from public.e10_customer_transactions t
    cross join lateral e10.customer_transaction_effective_attribution(p_org,t.id)ea
    where t.organization_id=p_org and t.currency=p_currency
      and t.occurred_at_precision<>'unknown' and t.occurred_at is not null
      and t.occurred_at>=p_from and t.occurred_at<p_to
      and t.occurred_at<p_observation_cutoff
      and ea.effective_customer_id is not null
      and(p_customer is null or ea.effective_customer_id=p_customer)
  ),eligible_lines as materialized(
    select t.effective_customer_id,t.occurred_at,l.*
    from eligible_transactions t
    join public.e10_customer_transaction_lines l
      on l.organization_id=p_org and l.transaction_id=t.id
    cross join permission_context pc
    left join public.e10_locations line_location
      on(line_location.organization_id,line_location.id)=(p_org,l.location_id)
    where(p_purchase_kind is null or l.purchase_kind=p_purchase_kind)
      and(p_location is null or l.location_id=p_location)
      and(p_channel is null or l.sales_channel=p_channel)
      and(p_product is null or l.product_master_id=p_product)
      and(p_configuration is null or l.configuration_version_id=p_configuration)
      and(p_copy is null or l.unique_item_id=p_copy)
      and(p_session is null or l.break_session_id=p_session)
      and(p_capture_source is null or l.capture_source=p_capture_source)
      and pc.is_member and(
        (l.location_id is null and pc.org_wide)
        or(l.location_id is not null and line_location.id is not null and(
          pc.org_wide or exists(select 1 from allowed_locations a where a.location_id=l.location_id)
        ))
      )
  ),finalized as(
    select x.transaction_line_id,
      max(x.final_amount)filter(where x.component='merchandise')merchandise_final,
      max(x.final_amount)filter(where x.component='shipping')shipping_final,
      max(x.final_amount)filter(where x.component='tax')tax_final
    from public.e10_customer_transaction_component_finalizations x
    join eligible_lines l on(l.organization_id,l.id)=(x.organization_id,x.transaction_line_id)
    group by x.transaction_line_id
  ),adjusted as(
    select x.transaction_line_id,
      coalesce(sum(case x.effect when'increase'then x.merchandise_amount else-x.merchandise_amount end),0)merchandise_delta,
      coalesce(sum(case x.effect when'increase'then x.shipping_amount else-x.shipping_amount end),0)shipping_delta,
      coalesce(sum(case x.effect when'increase'then x.tax_amount else-x.tax_amount end),0)tax_delta
    from public.e10_customer_transaction_adjustments x
    join eligible_lines l on(l.organization_id,l.id)=(x.organization_id,x.transaction_line_id)
    group by x.transaction_line_id
  )select l.effective_customer_id,l.transaction_id,l.id,l.purchase_kind,l.break_session_id,l.occurred_at,
    l.merchandise_gross,l.merchandise_discount,
    coalesce(l.merchandise_net,f.merchandise_final),coalesce(a.merchandise_delta,0),
    case when coalesce(l.merchandise_net,f.merchandise_final)is null then null else coalesce(l.merchandise_net,f.merchandise_final)+coalesce(a.merchandise_delta,0)end,
    case when coalesce(l.shipping_amount,f.shipping_final)is null then null else coalesce(l.shipping_amount,f.shipping_final)+coalesce(a.shipping_delta,0)end,
    case when coalesce(l.tax_amount,f.tax_final)is null then null else coalesce(l.tax_amount,f.tax_final)+coalesce(a.tax_delta,0)end,
    coalesce(l.merchandise_net,f.merchandise_final)is not null,
    coalesce(l.shipping_amount,f.shipping_final)is not null,
    coalesce(l.tax_amount,f.tax_final)is not null
  from eligible_lines l
  left join finalized f on f.transaction_line_id=l.id
  left join adjusted a on a.transaction_line_id=l.id
$$;
revoke all on function e10.customer_spend_grid_contributions(uuid,timestamptz,timestamptz,timestamptz,text,uuid,text,uuid,text,uuid,uuid,uuid,uuid,text)from public,anon,authenticated;
grant execute on function e10.customer_spend_grid_contributions(uuid,timestamptz,timestamptz,timestamptz,text,uuid,text,uuid,text,uuid,uuid,uuid,uuid,text)to service_role;

create or replace function e10.customer_spend_grid_diagnostics(
  p_org uuid,p_from timestamptz,p_to timestamptz,p_observation_cutoff timestamptz,
  p_currency text,p_customer uuid default null,p_purchase_kind text default null,
  p_location uuid default null,p_channel text default null,p_product uuid default null,
  p_configuration uuid default null,p_copy uuid default null,p_session uuid default null,
  p_capture_source text default null
)returns jsonb language sql stable security definer set search_path=public as $$
  with permission_context as materialized(
    select e10.is_org_member(p_org)is_member,
      e10.has_org_cap(p_org,'act.view_customer_financials')org_wide
  ),allowed_locations as materialized(
    select distinct lp.location_id
    from public.e10_organization_memberships m
    join public.e10_location_role_permissions lp
      on lp.organization_id=m.organization_id and lp.role_id=m.role_id
    join public.e10_locations location_scope
      on(location_scope.organization_id,location_scope.id)=(lp.organization_id,lp.location_id)
    where m.organization_id=p_org and m.user_id=auth.uid() and m.status='active'
      and lp.can_view_customer_financials and location_scope.status='active'
  ),attributed_transactions as materialized(
    select t.id,t.occurred_at,t.occurred_at_precision,ea.effective_customer_id
    from public.e10_customer_transactions t
    cross join lateral e10.customer_transaction_effective_attribution(p_org,t.id)ea
    where t.organization_id=p_org and t.currency=p_currency
  ),authorized_lines as materialized(
    select t.*
    from attributed_transactions t
    join public.e10_customer_transaction_lines l
      on l.organization_id=p_org and l.transaction_id=t.id
    cross join permission_context pc
    left join public.e10_locations line_location
      on(line_location.organization_id,line_location.id)=(p_org,l.location_id)
    where pc.is_member and(
        (l.location_id is null and pc.org_wide)
        or(l.location_id is not null and line_location.id is not null and(
          pc.org_wide or exists(select 1 from allowed_locations a where a.location_id=l.location_id)
        ))
      )
      and(p_purchase_kind is null or l.purchase_kind=p_purchase_kind)
      and(p_location is null or l.location_id=p_location)
      and(p_channel is null or l.sales_channel=p_channel)
      and(p_product is null or l.product_master_id=p_product)
      and(p_configuration is null or l.configuration_version_id=p_configuration)
      and(p_copy is null or l.unique_item_id=p_copy)
      and(p_session is null or l.break_session_id=p_session)
      and(p_capture_source is null or l.capture_source=p_capture_source)
  )select jsonb_build_object(
    'unknown_occurrence_line_count',count(*)filter(where(occurred_at_precision='unknown'or occurred_at is null)and effective_customer_id is not null and(p_customer is null or effective_customer_id=p_customer)),
    'unattributed_authorized_line_count',case when p_customer is null then count(*)filter(where occurred_at_precision<>'unknown'and occurred_at is not null and occurred_at>=p_from and occurred_at<p_to and occurred_at<p_observation_cutoff and effective_customer_id is null)else null end,
    'scope',case when p_customer is null then'authorized_filtered_cohort'else'selected_effective_customer'end,
    'source_history_completeness','unknown','unknown_occurrence_not_period_attributable',true)
  from authorized_lines
$$;
revoke all on function e10.customer_spend_grid_diagnostics(uuid,timestamptz,timestamptz,timestamptz,text,uuid,text,uuid,text,uuid,uuid,uuid,uuid,text)from public,anon,authenticated;
grant execute on function e10.customer_spend_grid_diagnostics(uuid,timestamptz,timestamptz,timestamptz,text,uuid,text,uuid,text,uuid,uuid,uuid,uuid,text)to service_role;
