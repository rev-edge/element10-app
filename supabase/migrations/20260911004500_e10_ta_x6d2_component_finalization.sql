-- TA-X6d.2a reviewed absolute finalization of monetary components that were unknown at posting.
-- Original posted facts remain immutable. A finalization establishes one known baseline; later deltas remain additive.

create table public.e10_customer_transaction_component_finalizations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.e10_organizations(id),
  transaction_id uuid not null,
  transaction_line_id uuid not null,
  component text not null check(component in ('merchandise','shipping','tax')),
  final_amount numeric not null check(final_amount>=0 and final_amount::text not in ('NaN','Infinity','-Infinity')),
  currency text not null check(currency~'^[A-Z]{3}$'),
  reason text not null check(btrim(reason)<>''),
  evidence jsonb not null check(jsonb_typeof(evidence)='object' and octet_length(evidence::text)<=65536),
  source_kind text not null check(source_kind in ('manual','import')),
  source_connection_id text,
  source_event_id text not null,
  source_component_id text not null,
  idempotency_key text not null,
  request_fingerprint text not null,
  commercial_event_id uuid not null,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  unique(organization_id,id),
  unique(organization_id,transaction_line_id,component),
  unique(organization_id,idempotency_key),
  foreign key(organization_id,transaction_id) references public.e10_customer_transactions(organization_id,id),
  foreign key(organization_id,transaction_line_id) references public.e10_customer_transaction_lines(organization_id,id),
  check(btrim(source_event_id)<>'' and btrim(source_component_id)<>'' and btrim(idempotency_key)<>'' and btrim(request_fingerprint)<>''),
  check(source_connection_id is null or btrim(source_connection_id)<>'')
);
create unique index e10_customer_component_finalization_source_uq
  on public.e10_customer_transaction_component_finalizations(organization_id,source_kind,coalesce(source_connection_id,''),source_event_id,source_component_id);
create index e10_customer_component_finalization_line_idx
  on public.e10_customer_transaction_component_finalizations(organization_id,transaction_line_id,component);

alter table public.e10_commercial_events add column customer_transaction_component_finalization_id uuid;
alter table public.e10_commercial_events add constraint e10_commercial_events_org_component_finalization_fkey
  foreign key(organization_id,customer_transaction_component_finalization_id)
  references public.e10_customer_transaction_component_finalizations(organization_id,id) deferrable initially deferred;
alter table public.e10_customer_transaction_component_finalizations add constraint e10_customer_component_finalization_org_event_fkey
  foreign key(organization_id,commercial_event_id) references public.e10_commercial_events(organization_id,id) deferrable initially deferred;

alter table public.e10_customer_commercial_receipts drop constraint e10_customer_commercial_receipts_operation_check;
alter table public.e10_customer_commercial_receipts add constraint e10_customer_commercial_receipts_operation_check
  check(operation in ('create_draft','amend_draft','approve_draft','reopen_draft','post_draft','adjust_transaction','finalize_transaction_component'));

alter table public.e10_customer_transaction_component_finalizations enable row level security;
revoke all on public.e10_customer_transaction_component_finalizations from public,anon,authenticated;
grant all on public.e10_customer_transaction_component_finalizations to service_role;
create trigger e10_customer_component_finalization_append_only_trg before update or delete
  on public.e10_customer_transaction_component_finalizations for each row execute function e10.reject_append_only_change();

create function e10.customer_transaction_component_balance(p_org uuid,p_line uuid,p_component text)
returns numeric language sql stable security definer set search_path=public as $$
  with base as (
    select case p_component
      when 'merchandise' then l.merchandise_net
      when 'shipping' then l.shipping_amount
      when 'tax' then l.tax_amount
      else null end original_amount
    from public.e10_customer_transaction_lines l
    where l.organization_id=p_org and l.id=p_line
  ), established as (
    select f.final_amount
    from public.e10_customer_transaction_component_finalizations f
    where f.organization_id=p_org and f.transaction_line_id=p_line and f.component=p_component
  ), delta as (
    select coalesce(sum(case a.effect when 'increase' then 1 else -1 end * case p_component
      when 'merchandise' then a.merchandise_amount
      when 'shipping' then a.shipping_amount
      when 'tax' then a.tax_amount end),0) amount
    from public.e10_customer_transaction_adjustments a
    where a.organization_id=p_org and a.transaction_line_id=p_line
  )
  select case when coalesce(base.original_amount,established.final_amount) is null then null
    else coalesce(base.original_amount,established.final_amount)+delta.amount end
  from base cross join delta left join established on true
$$;
revoke all on function e10.customer_transaction_component_balance(uuid,uuid,text) from public,anon,authenticated;
grant execute on function e10.customer_transaction_component_balance(uuid,uuid,text) to service_role;

create function e10.enforce_customer_component_finalization_event_link() returns trigger
language plpgsql security definer set search_path=public as $$
begin
  if new.customer_transaction_component_finalization_id is not null and not exists(
    select 1 from public.e10_customer_transaction_component_finalizations f
    where f.organization_id=new.organization_id and f.id=new.customer_transaction_component_finalization_id
      and f.commercial_event_id=new.id and new.event_type='correction'
      and new.subject_type='customer_transaction' and new.subject_id=f.transaction_id::text
      and new.corrects_event_id=(select t.commercial_event_id from public.e10_customer_transactions t where t.organization_id=f.organization_id and t.id=f.transaction_id)
  ) then raise exception using errcode='42501',message='customer_component_finalization_event_link_invalid'; end if;
  return new;
end $$;
revoke all on function e10.enforce_customer_component_finalization_event_link() from public,anon,authenticated;
grant execute on function e10.enforce_customer_component_finalization_event_link() to service_role;
create trigger e10_customer_component_finalization_event_link_trg before insert on public.e10_commercial_events
  for each row execute function e10.enforce_customer_component_finalization_event_link();

create function public.e10_org_finalize_customer_transaction_component(
  p_org uuid,p_transaction_id uuid,p_transaction_line_id uuid,p_component text,p_final_amount numeric,p_currency text,
  p_reason text,p_source_kind text,p_source_connection_id text,p_source_event_id text,p_source_component_id text,
  p_evidence jsonb,p_idempotency_key text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_fp text;v_old record;v_line record;v_id uuid:=gen_random_uuid();v_event uuid:=gen_random_uuid();v_result jsonb;v_original numeric;
begin
  if not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.reconcile_customer_transactions') then raise exception using errcode='42501',message='finalize_customer_component_denied';end if;
  if p_component not in ('merchandise','shipping','tax') or p_final_amount is null or p_final_amount<0 or p_final_amount::text in ('NaN','Infinity','-Infinity') then raise exception using errcode='22023',message='component_finalization_invalid';end if;
  if p_currency is null or p_currency!~'^[A-Z]{3}$' or p_reason is null or btrim(p_reason)='' or p_source_kind not in ('manual','import') or p_source_event_id is null or btrim(p_source_event_id)='' or p_source_component_id is null or btrim(p_source_component_id)='' or p_idempotency_key is null or btrim(p_idempotency_key)='' or p_evidence is null or jsonb_typeof(p_evidence)<>'object' or octet_length(p_evidence::text)>65536 then raise exception using errcode='22023',message='component_finalization_provenance_invalid';end if;
  v_fp:=md5(jsonb_build_object('v','customer-component-finalization-v1','transaction',p_transaction_id,'line',p_transaction_line_id,'component',p_component,'final_amount',p_final_amount,'currency',p_currency,'reason',p_reason,'source_kind',p_source_kind,'connection',p_source_connection_id,'source_event',p_source_event_id,'source_component',p_source_component_id,'evidence',p_evidence)::text);
  perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|customer-commercial|'||p_idempotency_key,0));
  select request_fingerprint,result into v_old from public.e10_customer_commercial_receipts where organization_id=p_org and idempotency_key=p_idempotency_key;
  if found then if v_old.request_fingerprint<>v_fp then raise exception using errcode='22023',message='idempotency_key_mismatch';end if;return v_old.result||'{"replay":true}'::jsonb;end if;
  perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|customer-adjustment|'||p_transaction_line_id::text,0));
  select l.*,t.currency,t.commercial_event_id as original_event_id into v_line
  from public.e10_customer_transaction_lines l join public.e10_customer_transactions t on t.organization_id=l.organization_id and t.id=l.transaction_id
  where l.organization_id=p_org and l.id=p_transaction_line_id and l.transaction_id=p_transaction_id;
  if not found then raise exception using errcode='42501',message='component_finalization_line_denied';end if;
  if v_line.currency<>p_currency then raise exception using errcode='22023',message='component_finalization_currency_mismatch';end if;
  v_original:=case p_component when 'merchandise' then v_line.merchandise_net when 'shipping' then v_line.shipping_amount when 'tax' then v_line.tax_amount end;
  if v_original is not null then raise exception using errcode='22023',message='component_already_known_at_posting';end if;
  if exists(select 1 from public.e10_customer_transaction_component_finalizations f where f.organization_id=p_org and f.transaction_line_id=p_transaction_line_id and f.component=p_component) then raise exception using errcode='40001',message='component_already_finalized';end if;
  if p_final_amount>0 and exists(select 1 from public.e10_customer_transaction_adjustments cancelled where cancelled.organization_id=p_org and cancelled.transaction_line_id=p_transaction_line_id and cancelled.adjustment_kind='cancellation' and not exists(select 1 from public.e10_customer_transaction_adjustments reinstatement where reinstatement.organization_id=p_org and reinstatement.reinstates_cancellation_id=cancelled.id)) then raise exception using errcode='22023',message='cancelled_line_requires_explicit_reinstatement';end if;
  insert into public.e10_customer_transaction_component_finalizations(id,organization_id,transaction_id,transaction_line_id,component,final_amount,currency,reason,evidence,source_kind,source_connection_id,source_event_id,source_component_id,idempotency_key,request_fingerprint,commercial_event_id,created_by)
  values(v_id,p_org,p_transaction_id,p_transaction_line_id,p_component,p_final_amount,p_currency,btrim(p_reason),p_evidence,p_source_kind,nullif(btrim(p_source_connection_id),''),btrim(p_source_event_id),btrim(p_source_component_id),p_idempotency_key,v_fp,v_event,auth.uid());
  insert into public.e10_commercial_events(id,organization_id,event_type,event_schema_version,subject_type,subject_id,occurred_at,occurred_at_precision,idempotency_key,source_kind,source_connection_id,source_event_id,correlation_id,causation_event_id,evidence_quality,payload,created_by,request_fingerprint,corrects_event_id,customer_transaction_component_finalization_id)
  values(v_event,p_org,'correction',1,'customer_transaction',p_transaction_id::text,null,'unknown','customer-component-finalization:'||p_idempotency_key,p_source_kind,p_source_connection_id,jsonb_build_array(p_source_event_id,p_source_component_id)::text,p_transaction_id::text,v_line.original_event_id,case when p_source_kind='import' then 'reviewed_import' else 'operator_asserted' end,jsonb_build_object('reason',btrim(p_reason),'component_finalization_id',v_id,'component',p_component,'known_final_value',p_final_amount,'currency',p_currency,'external_source_event_id',p_source_event_id,'external_source_component_id',p_source_component_id),auth.uid(),md5('customer-component-finalization-event|'||v_fp),v_line.original_event_id,v_id);
  v_result:=jsonb_build_object('ok',true,'replay',false,'finalization_id',v_id,'event_id',v_event,'transaction_id',p_transaction_id,'line_id',p_transaction_line_id,'component',p_component,'known_final_value',p_final_amount,'paid_changed',false,'settlement_changed',false,'inventory_returned',false);
  insert into public.e10_customer_commercial_receipts values(p_org,p_idempotency_key,'finalize_transaction_component',v_id,v_fp,v_result,auth.uid(),now());
  return v_result;
exception when unique_violation then
  if exists(select 1 from public.e10_customer_transaction_component_finalizations f where f.organization_id=p_org and f.source_kind=p_source_kind and coalesce(f.source_connection_id,'')=coalesce(p_source_connection_id,'') and f.source_event_id=p_source_event_id and f.source_component_id=p_source_component_id) then raise exception using errcode='23505',message='component_finalization_source_already_recorded';end if;
  raise;
end $$;
revoke all on function public.e10_org_finalize_customer_transaction_component(uuid,uuid,uuid,text,numeric,text,text,text,text,text,text,jsonb,text) from public,anon;
grant execute on function public.e10_org_finalize_customer_transaction_component(uuid,uuid,uuid,text,numeric,text,text,text,text,text,text,jsonb,text) to authenticated,service_role;
comment on function public.e10_org_finalize_customer_transaction_component(uuid,uuid,uuid,text,numeric,text,text,text,text,text,text,jsonb,text) is 'Reviews one previously unknown posted monetary component into a known absolute value, including legitimate zero, without rewriting the posted fact or asserting payment/settlement/return.';

-- Replace the delta writer so every subsequent adjustment uses the original-or-finalized baseline under the same line lock.
create or replace function public.e10_org_adjust_customer_transaction(
  p_org uuid,p_transaction_id uuid,p_transaction_line_id uuid,p_adjustment_kind text,p_effect text,p_currency text,
  p_merchandise_amount numeric,p_shipping_amount numeric,p_tax_amount numeric,p_occurred_at timestamptz,p_occurred_at_precision text,
  p_reason text,p_source_kind text,p_source_connection_id text,p_source_event_id text,p_source_component_id text,p_reinstates_cancellation_id uuid,p_evidence jsonb,p_idempotency_key text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_fp text;v_old record;v_line record;v_adjustment uuid:=gen_random_uuid();v_event uuid:=gen_random_uuid();v_event_type text;v_result jsonb;v_merch numeric;v_ship numeric;v_tax numeric;v_total numeric;
begin
  if not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.adjust_customer_transactions') then raise exception using errcode='42501',message='adjust_customer_transaction_denied';end if;
  if p_idempotency_key is null or btrim(p_idempotency_key)='' or p_source_event_id is null or btrim(p_source_event_id)='' or p_source_component_id is null or btrim(p_source_component_id)='' or p_reason is null or btrim(p_reason)='' then raise exception using errcode='22004',message='adjustment_identity_required';end if;
  if p_adjustment_kind not in ('refund','cancellation','correction') or p_effect not in ('increase','decrease') or (p_adjustment_kind in ('refund','cancellation') and p_effect<>'decrease') then raise exception using errcode='22023',message='adjustment_semantics_invalid';end if;
  if p_reinstates_cancellation_id is not null and (p_adjustment_kind<>'correction' or p_effect<>'increase') then raise exception using errcode='22023',message='reinstatement_semantics_invalid';end if;
  if p_currency is null or p_currency!~'^[A-Z]{3}$' or p_source_kind not in ('manual','import') or p_evidence is null or jsonb_typeof(p_evidence)<>'object' or octet_length(p_evidence::text)>65536 then raise exception using errcode='22023',message='adjustment_provenance_invalid';end if;
  if p_occurred_at_precision not in ('exact','date','unknown') or ((p_occurred_at_precision='unknown')<>(p_occurred_at is null)) or (p_occurred_at is not null and not isfinite(p_occurred_at)) then raise exception using errcode='22023',message='adjustment_occurrence_invalid';end if;
  if num_nonnulls(p_merchandise_amount,p_shipping_amount,p_tax_amount)=0 or coalesce(p_merchandise_amount,0)+coalesce(p_shipping_amount,0)+coalesce(p_tax_amount,0)<=0 or (p_merchandise_amount is not null and (p_merchandise_amount<0 or p_merchandise_amount::text in ('NaN','Infinity','-Infinity'))) or (p_shipping_amount is not null and (p_shipping_amount<0 or p_shipping_amount::text in ('NaN','Infinity','-Infinity'))) or (p_tax_amount is not null and (p_tax_amount<0 or p_tax_amount::text in ('NaN','Infinity','-Infinity'))) then raise exception using errcode='22023',message='adjustment_amount_invalid';end if;
  v_fp:=md5(jsonb_build_object('v','customer-adjustment-v1','transaction',p_transaction_id,'line',p_transaction_line_id,'kind',p_adjustment_kind,'effect',p_effect,'currency',p_currency,'merchandise',p_merchandise_amount,'shipping',p_shipping_amount,'tax',p_tax_amount,'occurred',extract(epoch from p_occurred_at)::numeric,'precision',p_occurred_at_precision,'reason',p_reason,'source_kind',p_source_kind,'connection',p_source_connection_id,'source_event',p_source_event_id,'source_component',p_source_component_id,'reinstates_cancellation_id',p_reinstates_cancellation_id,'evidence',p_evidence)::text);
  perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|customer-commercial|'||p_idempotency_key,0));
  select request_fingerprint,result into v_old from public.e10_customer_commercial_receipts where organization_id=p_org and idempotency_key=p_idempotency_key;
  if found then if v_old.request_fingerprint<>v_fp then raise exception using errcode='22023',message='idempotency_key_mismatch';end if;return v_old.result||'{"replay":true}'::jsonb;end if;
  perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|customer-adjustment|'||p_transaction_line_id::text,0));
  select l.*,t.currency,t.commercial_event_id as original_event_id into v_line from public.e10_customer_transaction_lines l join public.e10_customer_transactions t on t.organization_id=l.organization_id and t.id=l.transaction_id where l.organization_id=p_org and l.id=p_transaction_line_id and l.transaction_id=p_transaction_id;
  if not found then raise exception using errcode='42501',message='adjustment_line_denied';end if;
  if v_line.currency<>p_currency then raise exception using errcode='22023',message='adjustment_currency_mismatch';end if;
  select e10.customer_transaction_component_balance(p_org,p_transaction_line_id,'merchandise'),e10.customer_transaction_component_balance(p_org,p_transaction_line_id,'shipping'),e10.customer_transaction_component_balance(p_org,p_transaction_line_id,'tax') into v_merch,v_ship,v_tax;
  if (p_merchandise_amount is not null and v_merch is null) or (p_shipping_amount is not null and v_ship is null) or (p_tax_amount is not null and v_tax is null) then raise exception using errcode='22023',message='adjustment_component_unknown';end if;
  if p_effect='decrease' and (coalesce(p_merchandise_amount,0)>coalesce(v_merch,0) or coalesce(p_shipping_amount,0)>coalesce(v_ship,0) or coalesce(p_tax_amount,0)>coalesce(v_tax,0)) then raise exception using errcode='22023',message='adjustment_exceeds_remaining_amount';end if;
  if p_reinstates_cancellation_id is not null and not exists(select 1 from public.e10_customer_transaction_adjustments cancelled where cancelled.organization_id=p_org and cancelled.id=p_reinstates_cancellation_id and cancelled.transaction_line_id=p_transaction_line_id and cancelled.adjustment_kind='cancellation' and not exists(select 1 from public.e10_customer_transaction_adjustments prior_reinstatement where prior_reinstatement.organization_id=p_org and prior_reinstatement.reinstates_cancellation_id=cancelled.id)) then raise exception using errcode='22023',message='reinstatement_target_invalid';end if;
  if p_reinstates_cancellation_id is null and p_effect='increase' and exists(select 1 from public.e10_customer_transaction_adjustments cancelled where cancelled.organization_id=p_org and cancelled.transaction_line_id=p_transaction_line_id and cancelled.adjustment_kind='cancellation' and not exists(select 1 from public.e10_customer_transaction_adjustments prior_reinstatement where prior_reinstatement.organization_id=p_org and prior_reinstatement.reinstates_cancellation_id=cancelled.id)) then raise exception using errcode='22023',message='cancelled_line_requires_explicit_reinstatement';end if;
  if p_adjustment_kind='cancellation' and exists(select 1 from public.e10_customer_transaction_adjustments cancelled where cancelled.organization_id=p_org and cancelled.transaction_line_id=p_transaction_line_id and cancelled.adjustment_kind='cancellation' and not exists(select 1 from public.e10_customer_transaction_adjustments prior_reinstatement where prior_reinstatement.organization_id=p_org and prior_reinstatement.reinstates_cancellation_id=cancelled.id)) then raise exception using errcode='22023',message='transaction_line_already_cancelled';end if;
  if p_adjustment_kind='cancellation' and ((v_merch is not null and coalesce(p_merchandise_amount,0)<>v_merch) or (v_ship is not null and coalesce(p_shipping_amount,0)<>v_ship) or (v_tax is not null and coalesce(p_tax_amount,0)<>v_tax)) then raise exception using errcode='22023',message='cancellation_must_zero_known_components';end if;
  v_event_type:=case when p_adjustment_kind='refund' then 'refund' else 'correction' end;v_total:=coalesce(p_merchandise_amount,0)+coalesce(p_shipping_amount,0)+coalesce(p_tax_amount,0);
  insert into public.e10_customer_transaction_adjustments(id,organization_id,transaction_id,transaction_line_id,adjustment_kind,currency,merchandise_amount,shipping_amount,tax_amount,occurred_at,occurred_at_precision,reason,source_reference,commercial_event_id,created_by,effect,source_kind,source_connection_id,source_event_id,source_component_id,reinstates_cancellation_id,evidence,idempotency_key,request_fingerprint) values(v_adjustment,p_org,p_transaction_id,p_transaction_line_id,p_adjustment_kind,p_currency,p_merchandise_amount,p_shipping_amount,p_tax_amount,p_occurred_at,p_occurred_at_precision,btrim(p_reason),p_source_event_id,v_event,auth.uid(),p_effect,p_source_kind,nullif(btrim(p_source_connection_id),''),btrim(p_source_event_id),btrim(p_source_component_id),p_reinstates_cancellation_id,p_evidence,p_idempotency_key,v_fp);
  insert into public.e10_commercial_events(id,organization_id,event_type,event_schema_version,subject_type,subject_id,occurred_at,occurred_at_precision,idempotency_key,source_kind,source_connection_id,source_event_id,correlation_id,evidence_quality,payload,created_by,request_fingerprint,customer_transaction_adjustment_id,corrects_event_id) values(v_event,p_org,v_event_type,1,'customer_transaction',p_transaction_id::text,p_occurred_at,p_occurred_at_precision,'customer-adjustment:'||p_idempotency_key,p_source_kind,p_source_connection_id,jsonb_build_array(p_source_event_id,p_source_component_id)::text,p_transaction_id::text,case when p_source_kind='import' then 'reviewed_import' else 'operator_asserted' end,case when v_event_type='refund' then jsonb_build_object('refund_id',v_adjustment,'currency',p_currency,'amount',v_total,'effect',p_effect,'external_source_event_id',p_source_event_id,'external_source_component_id',p_source_component_id) else jsonb_build_object('reason',btrim(p_reason),'adjustment_id',v_adjustment,'currency',p_currency,'amount',v_total,'effect',p_effect,'external_source_event_id',p_source_event_id,'external_source_component_id',p_source_component_id) end,auth.uid(),md5('customer-adjustment-event|'||v_fp),v_adjustment,case when v_event_type='correction' then v_line.original_event_id else null end);
  v_result:=jsonb_build_object('ok',true,'replay',false,'adjustment_id',v_adjustment,'event_id',v_event,'transaction_id',p_transaction_id,'line_id',p_transaction_line_id,'effect',p_effect,'paid_changed',false,'settlement_changed',false,'inventory_returned',false);
  insert into public.e10_customer_commercial_receipts values(p_org,p_idempotency_key,'adjust_transaction',v_adjustment,v_fp,v_result,auth.uid(),now());return v_result;
exception when unique_violation then
  if exists(select 1 from public.e10_customer_transaction_adjustments where organization_id=p_org and source_kind=p_source_kind and coalesce(source_connection_id,'')=coalesce(p_source_connection_id,'') and source_event_id=p_source_event_id and source_component_id=p_source_component_id) then raise exception using errcode='23505',message='adjustment_source_component_already_recorded';end if;raise;
end $$;
comment on function public.e10_org_adjust_customer_transaction(uuid,uuid,uuid,text,text,text,numeric,numeric,numeric,timestamptz,text,text,text,text,text,text,uuid,jsonb,text) is 'Appends reviewed deltas to original-or-finalized known components under the shared line lock. NULL means unaffected. Never asserts payment, settlement, fee/proceeds, or physical return.';
