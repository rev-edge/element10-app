-- TA-X5e immutable observation correction and reviewed re-import lineage.
alter table public.e10_market_observations alter column intake_commit_id drop not null;
alter table public.e10_market_observations alter column intake_row_id drop not null;
alter table public.e10_market_observations add constraint e10_market_observations_origin_pair_chk
  check ((intake_commit_id is null)=(intake_row_id is null));
alter table public.e10_market_observations add constraint e10_market_observations_finite_chk check(
  occurred_at not in ('infinity'::timestamptz,'-infinity'::timestamptz)
  and amount::text not in ('NaN','Infinity','-Infinity')
  and (quantity is null or quantity::text not in ('NaN','Infinity','-Infinity')));

create table public.e10_market_observation_supersessions(
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.e10_organizations(id),
  superseded_observation_id uuid not null,
  replacement_observation_id uuid not null,
  lineage_kind text not null check(lineage_kind in ('manual_correction','reviewed_reimport')),
  correction_reason text not null check(btrim(correction_reason)<>''),
  idempotency_key text not null check(btrim(idempotency_key)<>''),
  request_fingerprint text not null,
  created_by uuid references auth.users(id), created_at timestamptz not null default now(),
  unique(organization_id,id), unique(organization_id,superseded_observation_id),
  unique(organization_id,replacement_observation_id), unique(organization_id,idempotency_key),
  foreign key(organization_id,superseded_observation_id) references public.e10_market_observations(organization_id,id),
  foreign key(organization_id,replacement_observation_id) references public.e10_market_observations(organization_id,id),
  check(superseded_observation_id<>replacement_observation_id));
alter table public.e10_market_observation_supersessions enable row level security;
revoke all on public.e10_market_observation_supersessions from public,anon,authenticated;
grant all on public.e10_market_observation_supersessions to service_role;
create trigger e10_market_observation_supersessions_append_only_trg before update or delete
  on public.e10_market_observation_supersessions for each row execute function e10.reject_append_only_change();

create function public.e10_org_correct_market_observation(
  p_org uuid,p_observation_id uuid,p_observation_kind text,p_target_type text,p_target_id uuid,
  p_occurred_at timestamptz,p_currency text,p_amount numeric,p_quantity numeric,
  p_source_reference text,p_raw_payload jsonb,p_reason text,p_idempotency_key text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare x record; fp text; new_id uuid; product_id uuid; configuration_id uuid; item_id uuid;
begin
  if not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.manage_intake') then raise exception using errcode='42501',message='manage_intake_denied'; end if;
  if p_idempotency_key is null or btrim(p_idempotency_key)='' then raise exception using errcode='22004',message='idempotency_key_required'; end if;
  if p_reason is null or btrim(p_reason)='' then raise exception using errcode='22004',message='correction_reason_required'; end if;
  if p_observation_kind not in ('acquisition_cost','asking_price','completed_sale','estimated_value') then raise exception using errcode='22023',message='observation_kind_invalid'; end if;
  if p_occurred_at is null or p_occurred_at in ('infinity'::timestamptz,'-infinity'::timestamptz) then raise exception using errcode='22023',message='occurred_at_invalid'; end if;
  if p_currency is null or p_currency!~'^[A-Z]{3}$' then raise exception using errcode='22023',message='currency_invalid'; end if;
  if p_amount is null or p_amount::text in ('NaN','Infinity','-Infinity') or p_amount<0 then raise exception using errcode='22023',message='amount_invalid'; end if;
  if p_quantity is not null and (p_quantity::text in ('NaN','Infinity','-Infinity') or p_quantity<=0) then raise exception using errcode='22023',message='quantity_invalid'; end if;
  if p_raw_payload is null or jsonb_typeof(p_raw_payload)<>'object' or octet_length(p_raw_payload::text)>262144 then raise exception using errcode='22023',message='raw_payload_invalid'; end if;
  if p_target_type='product' then select id into product_id from public.e10_product_masters where organization_id=p_org and id=p_target_id;
  elsif p_target_type='configuration' then select id into configuration_id from public.e10_product_configuration_versions where organization_id=p_org and id=p_target_id;
  elsif p_target_type='unique_item' then select id into item_id from public.e10_unique_items where organization_id=p_org and id=p_target_id;
  else raise exception using errcode='22023',message='target_invalid'; end if;
  if coalesce(product_id,configuration_id,item_id) is null then raise exception using errcode='42501',message='observation_target_access_denied'; end if;
  fp:=md5(jsonb_build_object('v','manual-v1','old',p_observation_id,'kind',p_observation_kind,
    'target_type',p_target_type,'target_id',p_target_id,'occurred_epoch',extract(epoch from p_occurred_at)::numeric,
    'currency',p_currency,'amount',p_amount,'quantity',p_quantity,'source_reference',p_source_reference,
    'payload',p_raw_payload,'reason',p_reason)::text);
  perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|obs-key|'||p_idempotency_key,0));
  select * into x from public.e10_market_observation_supersessions where organization_id=p_org and idempotency_key=p_idempotency_key;
  if found then
    if x.request_fingerprint<>fp then raise exception using errcode='22023',message='idempotency_key_mismatch'; end if;
    return jsonb_build_object('ok',true,'replay',true,'supersession_id',x.id,'observation_id',x.replacement_observation_id);
  end if;
  perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|obs|'||p_observation_id,0));
  if not exists(select 1 from public.e10_market_observations where organization_id=p_org and id=p_observation_id) then raise exception using errcode='42501',message='market_observation_access_denied'; end if;
  if exists(select 1 from public.e10_market_observation_supersessions where organization_id=p_org and superseded_observation_id=p_observation_id) then raise exception using errcode='55000',message='market_observation_already_superseded'; end if;
  insert into public.e10_market_observations(organization_id,intake_commit_id,intake_row_id,observation_kind,
    product_master_id,configuration_version_id,unique_item_id,occurred_at,currency,amount,quantity,source_kind,source_reference,raw_payload_snapshot)
  values(p_org,null,null,p_observation_kind,product_id,configuration_id,item_id,p_occurred_at,p_currency,p_amount,p_quantity,'manual',p_source_reference,p_raw_payload)
  returning id into new_id;
  insert into public.e10_market_observation_supersessions(organization_id,superseded_observation_id,replacement_observation_id,
    lineage_kind,correction_reason,idempotency_key,request_fingerprint,created_by)
  values(p_org,p_observation_id,new_id,'manual_correction',p_reason,p_idempotency_key,fp,auth.uid()) returning * into x;
  return jsonb_build_object('ok',true,'replay',false,'supersession_id',x.id,'observation_id',new_id);
end $$;

create function public.e10_org_reconcile_market_observation_reimport(
  p_org uuid,p_observation_id uuid,p_replacement_observation_id uuid,p_reason text,p_idempotency_key text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare x record; replacement record; fp text;
begin
  if not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.manage_intake') then raise exception using errcode='42501',message='manage_intake_denied'; end if;
  if p_idempotency_key is null or btrim(p_idempotency_key)='' then raise exception using errcode='22004',message='idempotency_key_required'; end if;
  if p_reason is null or btrim(p_reason)='' then raise exception using errcode='22004',message='correction_reason_required'; end if;
  fp:=md5(jsonb_build_object('v','reimport-v1','old',p_observation_id,
    'replacement',p_replacement_observation_id,'reason',p_reason)::text);
  perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|obs-key|'||p_idempotency_key,0));
  select * into x from public.e10_market_observation_supersessions where organization_id=p_org and idempotency_key=p_idempotency_key;
  if found then
    if x.request_fingerprint<>fp then raise exception using errcode='22023',message='idempotency_key_mismatch'; end if;
    return jsonb_build_object('ok',true,'replay',true,'supersession_id',x.id,'observation_id',x.replacement_observation_id);
  end if;
  -- Serialize lineage graph mutations per organization. This makes the recursive cycle proof race-free,
  -- including simultaneous A->B and B->A requests.
  perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|observation-lineage-graph',0));
  if not exists(select 1 from public.e10_market_observations where organization_id=p_org and id=p_observation_id) then raise exception using errcode='42501',message='market_observation_access_denied'; end if;
  select * into replacement from public.e10_market_observations where organization_id=p_org and id=p_replacement_observation_id;
  if not found or replacement.intake_commit_id is null or replacement.intake_row_id is null then raise exception using errcode='22023',message='replacement_must_be_reviewed_reimport'; end if;
  if exists(
    with recursive chain(id) as (
      select p_replacement_observation_id
      union all
      select s.replacement_observation_id from chain c
      join public.e10_market_observation_supersessions s
        on s.organization_id=p_org and s.superseded_observation_id=c.id
    ) select 1 from chain where id=p_observation_id
  ) then raise exception using errcode='22023',message='observation_lineage_cycle'; end if;
  if exists(select 1 from public.e10_market_observation_supersessions where organization_id=p_org and superseded_observation_id=p_observation_id) then raise exception using errcode='55000',message='market_observation_already_superseded'; end if;
  insert into public.e10_market_observation_supersessions(organization_id,superseded_observation_id,replacement_observation_id,lineage_kind,
    correction_reason,idempotency_key,request_fingerprint,created_by)
  values(p_org,p_observation_id,p_replacement_observation_id,'reviewed_reimport',p_reason,p_idempotency_key,fp,auth.uid()) returning * into x;
  return jsonb_build_object('ok',true,'replay',false,'supersession_id',x.id,'observation_id',x.replacement_observation_id);
end $$;

revoke all on function public.e10_org_correct_market_observation(uuid,uuid,text,text,uuid,timestamptz,text,numeric,numeric,text,jsonb,text,text) from public,anon;
grant execute on function public.e10_org_correct_market_observation(uuid,uuid,text,text,uuid,timestamptz,text,numeric,numeric,text,jsonb,text,text) to authenticated,service_role;
revoke all on function public.e10_org_reconcile_market_observation_reimport(uuid,uuid,uuid,text,text) from public,anon;
grant execute on function public.e10_org_reconcile_market_observation_reimport(uuid,uuid,uuid,text,text) to authenticated,service_role;
comment on table public.e10_market_observation_supersessions is 'Immutable old-to-replacement lineage; replacement re-imports retain their committed intake row and batch provenance.';
