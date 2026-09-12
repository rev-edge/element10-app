-- TA-X5h catalog-variant observations. A shared catalog target is evidence scope, never ownership.

alter table public.e10_intake_rows add column catalog_variant_id uuid references public.e10_catalog_variants(id);
alter table public.e10_intake_rows drop constraint e10_intake_rows_check;
alter table public.e10_intake_rows drop constraint e10_intake_rows_one_target_chk;
alter table public.e10_intake_rows add constraint e10_intake_rows_match_target_chk
  check(match_status<>'matched' or num_nonnulls(product_master_id,configuration_version_id,unique_item_id,catalog_variant_id)=1);
alter table public.e10_intake_rows add constraint e10_intake_rows_one_target_chk
  check(num_nonnulls(product_master_id,configuration_version_id,unique_item_id,catalog_variant_id)<=1);

alter table public.e10_intake_resolver_decisions add column catalog_variant_id uuid references public.e10_catalog_variants(id);
alter table public.e10_intake_resolver_decisions drop constraint e10_intake_resolver_decisions_decision_check;
alter table public.e10_intake_resolver_decisions drop constraint e10_intake_resolver_decisions_check1;
alter table public.e10_intake_resolver_decisions add constraint e10_intake_resolver_decisions_decision_check
  check(decision in ('match_product','match_configuration','match_unique_item','match_catalog_variant','reject','clear_match'));
alter table public.e10_intake_resolver_decisions add constraint e10_intake_resolver_decisions_target_chk check(
  (decision='match_product' and product_master_id is not null and num_nonnulls(configuration_version_id,unique_item_id,catalog_variant_id)=0)
  or (decision='match_configuration' and configuration_version_id is not null and num_nonnulls(product_master_id,unique_item_id,catalog_variant_id)=0)
  or (decision='match_unique_item' and unique_item_id is not null and num_nonnulls(product_master_id,configuration_version_id,catalog_variant_id)=0)
  or (decision='match_catalog_variant' and catalog_variant_id is not null and num_nonnulls(product_master_id,configuration_version_id,unique_item_id)=0)
  or (decision in ('reject','clear_match') and num_nonnulls(product_master_id,configuration_version_id,unique_item_id,catalog_variant_id)=0));

alter table public.e10_market_observations add column catalog_variant_id uuid references public.e10_catalog_variants(id);
alter table public.e10_market_observations drop constraint e10_market_observations_check;
alter table public.e10_market_observations add constraint e10_market_observations_one_target_chk
  check(num_nonnulls(product_master_id,configuration_version_id,unique_item_id,catalog_variant_id)=1);
create index e10_market_observations_variant_time_idx
  on public.e10_market_observations(catalog_variant_id,observation_kind,occurred_at desc,id)
  where catalog_variant_id is not null;

create or replace view public.e10_current_market_observations with(security_invoker=true) as
  select o.* from public.e10_market_observations o
  where not exists(select 1 from public.e10_market_observation_supersessions s
    where s.organization_id=o.organization_id and s.superseded_observation_id=o.id);
revoke all on public.e10_current_market_observations from public,anon,authenticated;
grant select on public.e10_current_market_observations to service_role;

create or replace function public._e10_org_resolve_intake_row_x5b(
  p_org uuid,p_intake_row_id uuid,p_decision text,p_target_id uuid,p_reason text,p_corrects_decision_id uuid,p_idempotency_key text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_fp text; v_existing record; v_decision uuid; v_product uuid; v_config uuid; v_unique uuid; v_variant uuid; v_match text;
begin
  if not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.manage_intake') then raise exception using errcode='42501',message='manage_intake_denied'; end if;
  if p_idempotency_key is null or btrim(p_idempotency_key)='' then raise exception using errcode='22004',message='idempotency_key_required'; end if;
  if p_reason is null or btrim(p_reason)='' then raise exception using errcode='22004',message='resolution_reason_required'; end if;
  if p_decision not in ('match_product','match_configuration','match_unique_item','match_catalog_variant','reject','clear_match') then raise exception using errcode='22023',message='invalid_resolution_decision'; end if;
  if (p_decision like 'match_%')<>(p_target_id is not null) then raise exception using errcode='22023',message='resolution_target_mismatch'; end if;
  v_fp:=md5(p_intake_row_id::text||'|'||p_decision||'|'||coalesce(p_target_id::text,'')||'|'||p_reason||'|'||coalesce(p_corrects_decision_id::text,''));
  perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|resolve|'||p_idempotency_key,0));
  select id,request_fingerprint,decision into v_existing from public.e10_intake_resolver_decisions where organization_id=p_org and idempotency_key=p_idempotency_key;
  if found then
    if v_existing.request_fingerprint is distinct from v_fp then raise exception using errcode='22023',message='idempotency_key_mismatch'; end if;
    return jsonb_build_object('ok',true,'replay',true,'decision_id',v_existing.id,'decision',v_existing.decision);
  end if;
  perform 1 from public.e10_intake_rows where organization_id=p_org and id=p_intake_row_id for update;
  if not found then raise exception using errcode='42501',message='intake_row_access_denied'; end if;
  if p_decision='match_product' then select id into v_product from public.e10_product_masters where organization_id=p_org and id=p_target_id;
  elsif p_decision='match_configuration' then select id into v_config from public.e10_product_configuration_versions where organization_id=p_org and id=p_target_id;
  elsif p_decision='match_unique_item' then select id into v_unique from public.e10_unique_items where organization_id=p_org and id=p_target_id;
  elsif p_decision='match_catalog_variant' then select id into v_variant from public.e10_catalog_variants where id=p_target_id;
  elsif p_decision='reject' then v_match:='rejected';
  else v_match:='unresolved'; end if;
  if p_decision like 'match_%' and coalesce(v_product,v_config,v_unique,v_variant) is null then raise exception using errcode='42501',message='resolution_target_denied'; end if;
  if p_decision like 'match_%' then v_match:='matched'; end if;
  insert into public.e10_intake_resolver_decisions(organization_id,intake_row_id,decision,product_master_id,configuration_version_id,unique_item_id,catalog_variant_id,reason,corrects_decision_id,decided_by,idempotency_key,request_fingerprint)
  values(p_org,p_intake_row_id,p_decision,v_product,v_config,v_unique,v_variant,p_reason,p_corrects_decision_id,auth.uid(),p_idempotency_key,v_fp) returning id into v_decision;
  update public.e10_intake_rows set match_status=v_match,product_master_id=v_product,configuration_version_id=v_config,unique_item_id=v_unique,catalog_variant_id=v_variant where organization_id=p_org and id=p_intake_row_id;
  return jsonb_build_object('ok',true,'replay',false,'decision_id',v_decision,'decision',p_decision,'match_status',v_match);
end $$;

create or replace function public._e10_org_commit_intake_x5d(p_org uuid,p_batch_id uuid,p_expected_review_revision bigint,p_idempotency_key text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_batch record; v_existing record; v_fp text; v_commit uuid; v_included integer; v_rejected integer;
begin
  if not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.manage_intake') then raise exception using errcode='42501',message='manage_intake_denied'; end if;
  if p_idempotency_key is null or btrim(p_idempotency_key)='' then raise exception using errcode='22004',message='idempotency_key_required'; end if;
  if p_expected_review_revision is null or p_expected_review_revision<0 then raise exception using errcode='22023',message='expected_review_revision_required'; end if;
  v_fp:=md5(p_batch_id::text||'|'||p_expected_review_revision::text||'|commit-v1');
  perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|intake-commit|'||p_idempotency_key,0));
  select id,request_fingerprint,intake_batch_id,included_observation_count,rejected_row_count into v_existing from public.e10_intake_commits where organization_id=p_org and idempotency_key=p_idempotency_key;
  if found then
    if v_existing.request_fingerprint is distinct from v_fp then raise exception using errcode='22023',message='idempotency_key_mismatch'; end if;
    return jsonb_build_object('ok',true,'replay',true,'commit_id',v_existing.id,'batch_id',v_existing.intake_batch_id,'observation_count',v_existing.included_observation_count,'rejected_row_count',v_existing.rejected_row_count);
  end if;
  select id,status,source_kind,source_connection_id,source_reference,review_revision into v_batch from public.e10_intake_batches where organization_id=p_org and id=p_batch_id for update;
  if not found then raise exception using errcode='42501',message='intake_batch_access_denied'; end if;
  if v_batch.status='committed' then raise exception using errcode='23505',message='intake_batch_already_committed'; end if;
  if v_batch.status<>'validated' then raise exception using errcode='55000',message='intake_batch_not_validated'; end if;
  if v_batch.review_revision<>p_expected_review_revision then raise exception using errcode='40001',message='intake_review_revision_conflict'; end if;
  if exists(select 1 from public.e10_intake_rows where organization_id=p_org and batch_id=p_batch_id and (jsonb_array_length(validation_errors)>0 or match_status='unresolved')) then raise exception using errcode='55000',message='intake_rows_require_resolution'; end if;
  if exists(select 1 from public.e10_intake_rows where organization_id=p_org and batch_id=p_batch_id and match_status='matched' and observation_kind in ('inventory_receipt','customer_activity')) then raise exception using errcode='55000',message='actionable_intake_requires_domain_writer'; end if;
  select count(*) filter(where match_status='matched'),count(*) filter(where match_status='rejected') into v_included,v_rejected from public.e10_intake_rows where organization_id=p_org and batch_id=p_batch_id;
  insert into public.e10_intake_commits(organization_id,intake_batch_id,idempotency_key,request_fingerprint,included_observation_count,rejected_row_count,committed_by)
  values(p_org,p_batch_id,p_idempotency_key,v_fp,v_included,v_rejected,auth.uid()) returning id into v_commit;
  insert into public.e10_market_observations(organization_id,intake_commit_id,intake_row_id,observation_kind,product_master_id,configuration_version_id,unique_item_id,catalog_variant_id,occurred_at,currency,amount,quantity,source_kind,source_connection_id,source_reference,raw_payload_snapshot)
  select p_org,v_commit,r.id,r.observation_kind,r.product_master_id,r.configuration_version_id,r.unique_item_id,r.catalog_variant_id,r.occurred_at,r.currency,r.amount,r.quantity,v_batch.source_kind,v_batch.source_connection_id,v_batch.source_reference,r.raw_payload
  from public.e10_intake_rows r where r.organization_id=p_org and r.batch_id=p_batch_id and r.match_status='matched' and r.observation_kind in ('acquisition_cost','asking_price','completed_sale','estimated_value') order by r.source_row_number,r.id;
  update public.e10_intake_batches set status='committed',updated_at=now() where organization_id=p_org and id=p_batch_id;
  return jsonb_build_object('ok',true,'replay',false,'commit_id',v_commit,'batch_id',p_batch_id,'observation_count',v_included,'rejected_row_count',v_rejected);
end $$;

create or replace function public.e10_org_correct_market_observation(
  p_org uuid,p_observation_id uuid,p_observation_kind text,p_target_type text,p_target_id uuid,p_occurred_at timestamptz,p_currency text,p_amount numeric,p_quantity numeric,p_source_reference text,p_raw_payload jsonb,p_reason text,p_idempotency_key text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare x record; fp text; new_id uuid; product_id uuid; configuration_id uuid; item_id uuid; variant_id uuid;
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
  elsif p_target_type='catalog_variant' then select id into variant_id from public.e10_catalog_variants where id=p_target_id;
  else raise exception using errcode='22023',message='target_invalid'; end if;
  if coalesce(product_id,configuration_id,item_id,variant_id) is null then raise exception using errcode='42501',message='observation_target_access_denied'; end if;
  fp:=md5(jsonb_build_object('v','manual-v1','old',p_observation_id,'kind',p_observation_kind,'target_type',p_target_type,'target_id',p_target_id,'occurred_epoch',extract(epoch from p_occurred_at)::numeric,'currency',p_currency,'amount',p_amount,'quantity',p_quantity,'source_reference',p_source_reference,'payload',p_raw_payload,'reason',p_reason)::text);
  perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|obs-key|'||p_idempotency_key,0));
  select * into x from public.e10_market_observation_supersessions where organization_id=p_org and idempotency_key=p_idempotency_key;
  if found then if x.request_fingerprint<>fp then raise exception using errcode='22023',message='idempotency_key_mismatch'; end if; return jsonb_build_object('ok',true,'replay',true,'supersession_id',x.id,'observation_id',x.replacement_observation_id); end if;
  perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|obs|'||p_observation_id,0));
  if not exists(select 1 from public.e10_market_observations where organization_id=p_org and id=p_observation_id) then raise exception using errcode='42501',message='market_observation_access_denied'; end if;
  if exists(select 1 from public.e10_market_observation_supersessions where organization_id=p_org and superseded_observation_id=p_observation_id) then raise exception using errcode='55000',message='market_observation_already_superseded'; end if;
  insert into public.e10_market_observations(organization_id,intake_commit_id,intake_row_id,observation_kind,product_master_id,configuration_version_id,unique_item_id,catalog_variant_id,occurred_at,currency,amount,quantity,source_kind,source_reference,raw_payload_snapshot)
  values(p_org,null,null,p_observation_kind,product_id,configuration_id,item_id,variant_id,p_occurred_at,p_currency,p_amount,p_quantity,'manual',p_source_reference,p_raw_payload) returning id into new_id;
  insert into public.e10_market_observation_supersessions(organization_id,superseded_observation_id,replacement_observation_id,lineage_kind,correction_reason,idempotency_key,request_fingerprint,created_by)
  values(p_org,p_observation_id,new_id,'manual_correction',p_reason,p_idempotency_key,fp,auth.uid()) returning * into x;
  return jsonb_build_object('ok',true,'replay',false,'supersession_id',x.id,'observation_id',new_id);
end $$;

revoke all on function public._e10_org_resolve_intake_row_x5b(uuid,uuid,text,uuid,text,uuid,text) from public,anon,authenticated;
grant execute on function public._e10_org_resolve_intake_row_x5b(uuid,uuid,text,uuid,text,uuid,text) to service_role;
revoke all on function public._e10_org_commit_intake_x5d(uuid,uuid,bigint,text) from public,anon,authenticated;
grant execute on function public._e10_org_commit_intake_x5d(uuid,uuid,bigint,text) to service_role;
revoke all on function public.e10_org_correct_market_observation(uuid,uuid,text,text,uuid,timestamptz,text,numeric,numeric,text,jsonb,text,text) from public,anon;
grant execute on function public.e10_org_correct_market_observation(uuid,uuid,text,text,uuid,timestamptz,text,numeric,numeric,text,jsonb,text,text) to authenticated,service_role;

comment on column public.e10_market_observations.catalog_variant_id is
  'Shared catalog evidence target only. It does not assert organization ownership or the existence of an owned copy.';
