-- TA-X7b official spend reporting control. Current-restated, service-only projections.

alter table public.e10_location_role_permissions
  add column can_view_customer_financials boolean not null default false;
create index e10_location_role_permissions_financial_idx
  on public.e10_location_role_permissions(organization_id,role_id,location_id)
  where can_view_customer_financials;

create table public.e10_location_financial_permission_decisions(
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  location_id uuid not null,
  role_id uuid not null,
  previous_allowed boolean not null,
  allowed boolean not null,
  reason text not null check(length(btrim(reason)) between 1 and 2000),
  evidence jsonb not null check(jsonb_typeof(evidence)='object' and octet_length(evidence::text)<=65536),
  idempotency_key text not null check(length(btrim(idempotency_key)) between 1 and 500),
  request_fingerprint text not null check(btrim(request_fingerprint)<>''),
  result jsonb not null,
  decided_by uuid references auth.users(id),
  decided_at timestamptz not null default clock_timestamp(),
  unique(organization_id,id),unique(organization_id,idempotency_key),
  foreign key(organization_id,location_id) references public.e10_locations(organization_id,id),
  foreign key(organization_id,role_id) references public.e10_organization_roles(organization_id,id)
);
alter table public.e10_location_financial_permission_decisions enable row level security;
revoke all on public.e10_location_financial_permission_decisions from public,anon,authenticated;
grant all on public.e10_location_financial_permission_decisions to service_role;
create trigger e10_location_financial_permission_decision_immutable
  before update or delete on public.e10_location_financial_permission_decisions
  for each row execute function e10.reject_append_only_change();

create function e10.can_view_customer_financials_at(p_org uuid,p_location uuid)
returns boolean language sql stable security definer set search_path=public as $$
  select e10.is_org_member(p_org) and (
    case when p_location is null then
      e10.has_org_cap(p_org,'act.view_customer_financials')
    else
      exists(
        select 1 from public.e10_locations l
        where l.organization_id=p_org and l.id=p_location
          and (
            e10.has_org_cap(p_org,'act.view_customer_financials')
            or (
              l.status='active' and exists(
                select 1
                from public.e10_organization_memberships m
                join public.e10_location_role_permissions lp
                  on lp.organization_id=m.organization_id and lp.role_id=m.role_id
                where m.organization_id=p_org and m.user_id=auth.uid()
                  and m.status='active' and lp.location_id=l.id
                  and lp.can_view_customer_financials
              )
            )
          )
      )
    end
  )
$$;
revoke all on function e10.can_view_customer_financials_at(uuid,uuid)
  from public,anon,authenticated;
grant execute on function e10.can_view_customer_financials_at(uuid,uuid) to service_role;

create function e10.can_view_any_customer_financials(p_org uuid)
returns boolean language sql stable security definer set search_path=public as $$
  select e10.is_org_member(p_org) and (
    e10.has_org_cap(p_org,'act.view_customer_financials')
    or exists(
      select 1
      from public.e10_organization_memberships m
      join public.e10_location_role_permissions lp
        on lp.organization_id=m.organization_id and lp.role_id=m.role_id
      join public.e10_locations l
        on l.organization_id=lp.organization_id and l.id=lp.location_id
      where m.organization_id=p_org and m.user_id=auth.uid() and m.status='active'
        and lp.can_view_customer_financials and l.status='active'
    )
  )
$$;
revoke all on function e10.can_view_any_customer_financials(uuid)
  from public,anon,authenticated;
grant execute on function e10.can_view_any_customer_financials(uuid) to service_role;

create function public.e10_org_set_location_financial_access(
  p_org uuid,p_location uuid,p_role uuid,p_expected_updated_at timestamptz,
  p_allowed boolean,p_reason text,p_evidence jsonb,p_idempotency_key text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_fp text;v_replay record;v_prior record;v_result jsonb;v_id uuid:=gen_random_uuid();v_updated_at timestamptz;
begin
  if not e10.is_org_admin(p_org) or not e10.has_org_cap(p_org,'act.permissions_config') then
    raise exception using errcode='42501',message='location_financial_permission_denied';
  end if;
  if p_location is null or p_role is null or p_allowed is null
     or p_reason is null or length(btrim(p_reason)) not between 1 and 2000
     or p_evidence is null or jsonb_typeof(p_evidence)<>'object' or octet_length(p_evidence::text)>65536
     or p_idempotency_key is null or length(btrim(p_idempotency_key)) not between 1 and 500 then
    raise exception using errcode='22023',message='location_financial_permission_invalid';
  end if;
  v_fp:=md5(jsonb_build_object('v','location-financial-permission-v1','org',p_org,
    'location',p_location,'role',p_role,'expected_updated_at',p_expected_updated_at,
    'allowed',p_allowed,'reason',btrim(p_reason),'evidence',p_evidence)::text);
  perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|location-financial-idempotency|'||p_idempotency_key,0));
  if not e10.is_org_admin(p_org) or not e10.has_org_cap(p_org,'act.permissions_config') then
    raise exception using errcode='42501',message='location_financial_permission_denied';
  end if;
  select * into v_replay from public.e10_location_financial_permission_decisions
    where organization_id=p_org and idempotency_key=p_idempotency_key;
  if found then
    if v_replay.request_fingerprint<>v_fp then raise exception using errcode='22023',message='idempotency_key_mismatch';end if;
    return v_replay.result||'{"replay":true}'::jsonb;
  end if;
  perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|location-financial|'||p_location::text||'|'||p_role::text,0));
  if not e10.is_org_admin(p_org) or not e10.has_org_cap(p_org,'act.permissions_config') then
    raise exception using errcode='42501',message='location_financial_permission_denied';
  end if;
  if not exists(select 1 from public.e10_locations where organization_id=p_org and id=p_location)
     or not exists(select 1 from public.e10_organization_roles where organization_id=p_org and id=p_role) then
    raise exception using errcode='42501',message='location_financial_permission_target_denied';
  end if;
  select * into v_prior from public.e10_location_role_permissions
    where organization_id=p_org and location_id=p_location and role_id=p_role for update;
  if not e10.is_org_admin(p_org) or not e10.has_org_cap(p_org,'act.permissions_config') then
    raise exception using errcode='42501',message='location_financial_permission_denied';
  end if;
  if (found and p_expected_updated_at is distinct from v_prior.updated_at)
     or (not found and p_expected_updated_at is not null) then
    raise exception using errcode='40001',message='location_financial_permission_revision_conflict';
  end if;
  insert into public.e10_location_role_permissions(
    organization_id,location_id,role_id,can_view_customer_financials,updated_by,updated_at
  ) values(p_org,p_location,p_role,p_allowed,auth.uid(),clock_timestamp())
  on conflict(organization_id,location_id,role_id) do update
    set can_view_customer_financials=excluded.can_view_customer_financials,
        updated_by=excluded.updated_by,updated_at=excluded.updated_at
  returning updated_at into v_updated_at;
  if not e10.is_org_admin(p_org) or not e10.has_org_cap(p_org,'act.permissions_config') then
    raise exception using errcode='42501',message='location_financial_permission_denied';
  end if;
  v_result:=jsonb_build_object('ok',true,'replay',false,'decision_id',v_id,
    'organization_id',p_org,'location_id',p_location,'role_id',p_role,
    'previous_allowed',coalesce(v_prior.can_view_customer_financials,false),'allowed',p_allowed,
    'updated_at',v_updated_at);
  insert into public.e10_location_financial_permission_decisions(
    id,organization_id,location_id,role_id,previous_allowed,allowed,reason,evidence,
    idempotency_key,request_fingerprint,result,decided_by
  ) values(v_id,p_org,p_location,p_role,coalesce(v_prior.can_view_customer_financials,false),
    p_allowed,btrim(p_reason),p_evidence,p_idempotency_key,v_fp,v_result,auth.uid());
  if not e10.is_org_admin(p_org) or not e10.has_org_cap(p_org,'act.permissions_config') then
    raise exception using errcode='42501',message='location_financial_permission_denied';
  end if;
  return v_result;
end $$;
revoke all on function public.e10_org_set_location_financial_access(
  uuid,uuid,uuid,timestamptz,boolean,text,jsonb,text
) from public,anon;
grant execute on function public.e10_org_set_location_financial_access(
  uuid,uuid,uuid,timestamptz,boolean,text,jsonb,text
) to authenticated,service_role;

create function e10.official_customer_spend_contributions(
  p_org uuid,p_from timestamptz,p_to timestamptz,p_observation_cutoff timestamptz,
  p_currency text,p_customer uuid default null,p_purchase_kind text default null,
  p_location uuid default null,p_channel text default null,p_product uuid default null,
  p_configuration uuid default null,p_copy uuid default null,p_session uuid default null,
  p_capture_source text default null
) returns table(
  effective_customer_id uuid,original_customer_id uuid,attribution_action text,
  attribution_revision integer,attribution_decision_id uuid,
  transaction_id uuid,transaction_line_id uuid,line_no integer,purchase_kind text,
  sales_channel text,location_id uuid,capture_source text,source_connection_id text,
  source_line_id text,activity_observation_id uuid,product_master_id uuid,
  configuration_version_id uuid,unique_item_id uuid,break_session_id uuid,
  break_slot_id uuid,quantity numeric,currency text,occurred_at timestamptz,
  occurred_at_precision text,posted_at timestamptz,merchandise_gross numeric,
  merchandise_discount numeric,base_merchandise_net numeric,
  merchandise_adjustment_delta numeric,official_net_merchandise numeric,
  official_shipping numeric,official_tax numeric,merchandise_known boolean,
  shipping_known boolean,tax_known boolean,adjustment_count bigint,
  finalization_count bigint,evidence_link_count bigint,adjustment_ids uuid[],
  finalization_ids uuid[],evidence_link_ids uuid[],lineage_truncated boolean,
  product_bucket text
) language sql stable security definer set search_path=public as $$
  select
    ea.effective_customer_id,ea.original_customer_id,ea.attribution_action,
    ea.attribution_revision,ea.attribution_decision_id,
    t.id,l.id,l.line_no,l.purchase_kind,l.sales_channel,l.location_id,l.capture_source,
    l.source_connection_id,l.source_line_id,l.activity_observation_id,l.product_master_id,
    l.configuration_version_id,l.unique_item_id,l.break_session_id,l.break_slot_id,
    l.quantity,t.currency,t.occurred_at,t.occurred_at_precision,t.posted_at,
    l.merchandise_gross,l.merchandise_discount,
    coalesce(l.merchandise_net,f.merchandise_final),
    coalesce(a.merchandise_delta,0),
    case when coalesce(l.merchandise_net,f.merchandise_final) is null then null
         else coalesce(l.merchandise_net,f.merchandise_final)+coalesce(a.merchandise_delta,0) end,
    case when coalesce(l.shipping_amount,f.shipping_final) is null then null
         else coalesce(l.shipping_amount,f.shipping_final)+coalesce(a.shipping_delta,0) end,
    case when coalesce(l.tax_amount,f.tax_final) is null then null
         else coalesce(l.tax_amount,f.tax_final)+coalesce(a.tax_delta,0) end,
    coalesce(l.merchandise_net,f.merchandise_final) is not null,
    coalesce(l.shipping_amount,f.shipping_final) is not null,
    coalesce(l.tax_amount,f.tax_final) is not null,
    coalesce(a.adjustment_count,0),coalesce(f.finalization_count,0),
    coalesce(el.evidence_link_count,0),
    coalesce(a.adjustment_ids,'{}'::uuid[]),coalesce(f.finalization_ids,'{}'::uuid[]),
    coalesce(el.evidence_link_ids,'{}'::uuid[]),
    coalesce(a.adjustment_count,0)>200 or coalesce(f.finalization_count,0)>200
      or coalesce(el.evidence_link_count,0)>200,
    case when l.purchase_kind='break' and l.product_master_id is null
         then 'mixed_unallocated' else 'identified_or_not_applicable' end
  from public.e10_customer_transactions t
  join public.e10_customer_transaction_lines l
    on(l.organization_id,l.transaction_id)=(t.organization_id,t.id)
  cross join lateral e10.customer_transaction_effective_attribution(p_org,t.id) ea
  left join lateral(
    select
      max(final_amount)filter(where component='merchandise') merchandise_final,
      max(final_amount)filter(where component='shipping') shipping_final,
      max(final_amount)filter(where component='tax') tax_final,
      count(*)::bigint finalization_count,
      array(select x2.id from public.e10_customer_transaction_component_finalizations x2
        where x2.organization_id=p_org and x2.transaction_line_id=l.id
        order by x2.created_at,x2.id limit 200) finalization_ids
    from public.e10_customer_transaction_component_finalizations x
    where x.organization_id=p_org and x.transaction_line_id=l.id
  ) f on true
  left join lateral(
    select
      coalesce(sum(case effect when 'increase' then merchandise_amount else -merchandise_amount end),0) merchandise_delta,
      coalesce(sum(case effect when 'increase' then shipping_amount else -shipping_amount end),0) shipping_delta,
      coalesce(sum(case effect when 'increase' then tax_amount else -tax_amount end),0) tax_delta,
      count(*)::bigint adjustment_count,
      array(select x2.id from public.e10_customer_transaction_adjustments x2
        where x2.organization_id=p_org and x2.transaction_line_id=l.id
        order by x2.created_at,x2.id limit 200) adjustment_ids
    from public.e10_customer_transaction_adjustments x
    where x.organization_id=p_org and x.transaction_line_id=l.id
  ) a on true
  left join lateral(
    select count(*)::bigint evidence_link_count,
      array(select x2.id from public.e10_customer_transaction_evidence_links x2
        where x2.organization_id=p_org and x2.transaction_line_id=l.id
        order by x2.linked_at,x2.id limit 200) evidence_link_ids
    from public.e10_customer_transaction_evidence_links x
    where x.organization_id=p_org and x.transaction_line_id=l.id
  ) el on true
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
$$;
revoke all on function e10.official_customer_spend_contributions(
  uuid,timestamptz,timestamptz,timestamptz,text,uuid,text,uuid,text,uuid,uuid,uuid,uuid,text
) from public,anon,authenticated;
grant execute on function e10.official_customer_spend_contributions(
  uuid,timestamptz,timestamptz,timestamptz,text,uuid,text,uuid,text,uuid,uuid,uuid,uuid,text
) to service_role;

-- Every current-restated source that can change X7b output invalidates report cursors.
create trigger e10_reporting_revision_customer_transaction
  after insert on public.e10_customer_transactions for each row
  execute function e10.bump_reporting_dataset_revision();
create trigger e10_reporting_revision_customer_transaction_line
  after insert on public.e10_customer_transaction_lines for each row
  execute function e10.bump_reporting_dataset_revision();
create trigger e10_reporting_revision_customer_component_finalization
  after insert on public.e10_customer_transaction_component_finalizations for each row
  execute function e10.bump_reporting_dataset_revision();
create trigger e10_reporting_revision_customer_adjustment
  after insert on public.e10_customer_transaction_adjustments for each row
  execute function e10.bump_reporting_dataset_revision();
create trigger e10_reporting_revision_customer_transaction_attribution
  after insert on public.e10_customer_transaction_attribution_decisions for each row
  execute function e10.bump_reporting_dataset_revision();
create trigger e10_reporting_revision_customer_reconciliation_decision
  after insert on public.e10_customer_transaction_reconciliation_decisions for each row
  execute function e10.bump_reporting_dataset_revision();
create trigger e10_reporting_revision_customer_evidence_link
  after insert on public.e10_customer_transaction_evidence_links for each row
  execute function e10.bump_reporting_dataset_revision();
create trigger e10_reporting_revision_customer_source_claim
  after insert or update on public.e10_customer_transaction_source_claims for each row
  execute function e10.bump_reporting_dataset_revision();
create trigger e10_reporting_revision_customer_activity
  after insert on public.e10_customer_activity_observations for each row
  execute function e10.bump_reporting_dataset_revision();
create trigger e10_reporting_revision_customer_activity_attribution
  after insert on public.e10_customer_activity_attribution_decisions for each row
  execute function e10.bump_reporting_dataset_revision();
create trigger e10_reporting_revision_financial_org_grant
  after insert or update or delete on public.e10_organization_role_permissions
  for each row execute function e10.bump_reporting_dataset_revision();
create trigger e10_reporting_revision_financial_location_grant
  after insert or update or delete on public.e10_location_role_permissions
  for each row execute function e10.bump_reporting_dataset_revision();
create trigger e10_reporting_revision_financial_location_status
  after update of status on public.e10_locations for each row
  when(old.status is distinct from new.status)
  execute function e10.bump_reporting_dataset_revision();
create trigger e10_reporting_revision_financial_membership
  after insert or update or delete on public.e10_organization_memberships
  for each row execute function e10.bump_reporting_dataset_revision();
create trigger e10_reporting_revision_location_financial_decision
  after insert on public.e10_location_financial_permission_decisions
  for each row execute function e10.bump_reporting_dataset_revision();

comment on function e10.official_customer_spend_contributions(
  uuid,timestamptz,timestamptz,timestamptz,text,uuid,text,uuid,text,uuid,uuid,uuid,uuid,text
) is 'Service-only current-restated official posted-line projection. Unknown remains NULL; provisional activity, payment, settlement and proceeds are excluded.';
