-- TA-X7f staging performance corrective, revision 2. Compute reviewed effective
-- attribution once per eligible transaction before joining its contribution lines.

create or replace function e10.customer_spend_contribution_count_bounded(
  p_org uuid,p_from timestamptz,p_to timestamptz,p_observation_cutoff timestamptz,
  p_currency text,p_customer uuid default null,p_purchase_kind text default null,
  p_location uuid default null,p_channel text default null,p_product uuid default null,
  p_configuration uuid default null,p_copy uuid default null,p_session uuid default null,
  p_capture_source text default null
) returns bigint language sql stable security definer set search_path=public as $$
  with eligible_transactions as materialized(
    select t.id,ea.effective_customer_id
    from public.e10_customer_transactions t
    cross join lateral e10.customer_transaction_effective_attribution(p_org,t.id)ea
    where t.organization_id=p_org
      and t.currency=p_currency
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
    where(p_purchase_kind is null or l.purchase_kind=p_purchase_kind)
      and(p_location is null or l.location_id=p_location)
      and(p_channel is null or l.sales_channel=p_channel)
      and(p_product is null or l.product_master_id=p_product)
      and(p_configuration is null or l.configuration_version_id=p_configuration)
      and(p_copy is null or l.unique_item_id=p_copy)
      and(p_session is null or l.break_session_id=p_session)
      and(p_capture_source is null or l.capture_source=p_capture_source)
      and e10.can_view_customer_financials_at(p_org,l.location_id)
    limit 100001
  )select count(*)::bigint from bounded
$$;
revoke all on function e10.customer_spend_contribution_count_bounded(
  uuid,timestamptz,timestamptz,timestamptz,text,uuid,text,uuid,text,uuid,uuid,uuid,uuid,text
)from public,anon,authenticated;
grant execute on function e10.customer_spend_contribution_count_bounded(
  uuid,timestamptz,timestamptz,timestamptz,text,uuid,text,uuid,text,uuid,uuid,uuid,uuid,text
)to service_role;
comment on function e10.customer_spend_contribution_count_bounded(
  uuid,timestamptz,timestamptz,timestamptz,text,uuid,text,uuid,text,uuid,uuid,uuid,uuid,text
)is 'Private fixed-cap X7f eligibility counter; effective attribution is materialized once per eligible transaction before line filtering.';
