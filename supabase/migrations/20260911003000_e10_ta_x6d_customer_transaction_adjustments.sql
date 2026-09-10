-- TA-X6d.1 reviewed posted-spend adjustments. No payment, settlement, fee/proceeds or inventory-return assertion.

alter table public.e10_customer_transaction_adjustments
  add column effect text not null default 'decrease' check(effect in ('increase','decrease')),
  add column source_kind text not null default 'manual' check(source_kind in ('manual','import')),
  add column source_connection_id text,
  add column source_event_id text not null,
  add column source_component_id text not null,
  add column reinstates_cancellation_id uuid,
  add column evidence jsonb not null default '{}' check(jsonb_typeof(evidence)='object'),
  add column idempotency_key text not null,
  add column request_fingerprint text not null;
alter table public.e10_customer_transaction_adjustments alter column transaction_line_id set not null;
alter table public.e10_customer_transaction_adjustments alter column commercial_event_id set not null;
alter table public.e10_customer_transaction_adjustments add constraint e10_customer_adjustment_effect_kind_chk
  check(((adjustment_kind in ('refund','cancellation') and effect='decrease') or adjustment_kind='correction')
    and (reinstates_cancellation_id is null or (adjustment_kind='correction' and effect='increase')));
alter table public.e10_customer_transaction_adjustments add constraint e10_customer_adjustment_source_identity_chk
  check(btrim(source_event_id)<>'' and btrim(source_component_id)<>'' and btrim(idempotency_key)<>'' and btrim(request_fingerprint)<>'' and (source_connection_id is null or btrim(source_connection_id)<>''));
create unique index e10_customer_adjustment_idempotency_uq on public.e10_customer_transaction_adjustments(organization_id,idempotency_key);
create unique index e10_customer_adjustment_source_component_uq on public.e10_customer_transaction_adjustments(organization_id,source_kind,coalesce(source_connection_id,''),source_event_id,source_component_id);
create unique index e10_customer_adjustment_reinstatement_uq on public.e10_customer_transaction_adjustments(organization_id,reinstates_cancellation_id) where reinstates_cancellation_id is not null;
create index e10_customer_adjustment_line_time_idx on public.e10_customer_transaction_adjustments(organization_id,transaction_line_id,occurred_at,id);
alter table public.e10_customer_transaction_adjustments add constraint e10_customer_adjustment_org_reinstated_fkey
  foreign key(organization_id,reinstates_cancellation_id) references public.e10_customer_transaction_adjustments(organization_id,id);

alter table public.e10_commercial_events add column customer_transaction_adjustment_id uuid;
alter table public.e10_commercial_events add constraint e10_commercial_events_org_customer_adjustment_fkey
  foreign key(organization_id,customer_transaction_adjustment_id) references public.e10_customer_transaction_adjustments(organization_id,id) deferrable initially deferred;
alter table public.e10_customer_transaction_adjustments add constraint e10_customer_adjustments_org_event_fkey
  foreign key(organization_id,commercial_event_id) references public.e10_commercial_events(organization_id,id) deferrable initially deferred;
alter table public.e10_customer_commercial_receipts drop constraint e10_customer_commercial_receipts_operation_check;
alter table public.e10_customer_commercial_receipts add constraint e10_customer_commercial_receipts_operation_check
  check(operation in ('create_draft','amend_draft','approve_draft','reopen_draft','post_draft','adjust_transaction'));

create function e10.enforce_customer_adjustment_event_link() returns trigger language plpgsql security definer set search_path=public as $$
begin
  if new.customer_transaction_adjustment_id is not null and not exists(
    select 1 from public.e10_customer_transaction_adjustments a
    where a.organization_id=new.organization_id and a.id=new.customer_transaction_adjustment_id and a.commercial_event_id=new.id
      and new.subject_type='customer_transaction' and new.subject_id=a.transaction_id::text
      and ((a.adjustment_kind='refund' and new.event_type='refund') or (a.adjustment_kind in ('cancellation','correction') and new.event_type='correction'))
  ) then raise exception using errcode='42501',message='customer_adjustment_event_link_invalid'; end if;
  return new;
end $$;
revoke all on function e10.enforce_customer_adjustment_event_link() from public,anon,authenticated;
grant execute on function e10.enforce_customer_adjustment_event_link() to service_role;
create trigger e10_customer_adjustment_event_link_trg before insert on public.e10_commercial_events for each row execute function e10.enforce_customer_adjustment_event_link();

create function public.e10_org_adjust_customer_transaction(
  p_org uuid,p_transaction_id uuid,p_transaction_line_id uuid,p_adjustment_kind text,p_effect text,p_currency text,
  p_merchandise_amount numeric,p_shipping_amount numeric,p_tax_amount numeric,p_occurred_at timestamptz,p_occurred_at_precision text,
  p_reason text,p_source_kind text,p_source_connection_id text,p_source_event_id text,p_source_component_id text,p_reinstates_cancellation_id uuid,p_evidence jsonb,p_idempotency_key text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_fp text;v_old record;v_line record;v_adjustment uuid:=gen_random_uuid();v_event uuid:=gen_random_uuid();v_event_type text;v_result jsonb;
  v_merch numeric;v_ship numeric;v_tax numeric;v_total numeric;
begin
  if not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.adjust_customer_transactions') then raise exception using errcode='42501',message='adjust_customer_transaction_denied';end if;
  if p_idempotency_key is null or btrim(p_idempotency_key)='' or p_source_event_id is null or btrim(p_source_event_id)='' or p_source_component_id is null or btrim(p_source_component_id)='' or p_reason is null or btrim(p_reason)='' then raise exception using errcode='22004',message='adjustment_identity_required';end if;
  if p_adjustment_kind not in ('refund','cancellation','correction') or p_effect not in ('increase','decrease') or (p_adjustment_kind in ('refund','cancellation') and p_effect<>'decrease') then raise exception using errcode='22023',message='adjustment_semantics_invalid';end if;
  if p_reinstates_cancellation_id is not null and (p_adjustment_kind<>'correction' or p_effect<>'increase') then raise exception using errcode='22023',message='reinstatement_semantics_invalid';end if;
  if p_currency is null or p_currency!~'^[A-Z]{3}$' or p_source_kind not in ('manual','import') or p_evidence is null or jsonb_typeof(p_evidence)<>'object' or octet_length(p_evidence::text)>65536 then raise exception using errcode='22023',message='adjustment_provenance_invalid';end if;
  if p_occurred_at_precision not in ('exact','date','unknown') or ((p_occurred_at_precision='unknown')<>(p_occurred_at is null)) or (p_occurred_at is not null and not isfinite(p_occurred_at)) then raise exception using errcode='22023',message='adjustment_occurrence_invalid';end if;
  if num_nonnulls(p_merchandise_amount,p_shipping_amount,p_tax_amount)=0 or coalesce(p_merchandise_amount,0)+coalesce(p_shipping_amount,0)+coalesce(p_tax_amount,0)<=0
    or (p_merchandise_amount is not null and (p_merchandise_amount<0 or p_merchandise_amount::text in ('NaN','Infinity','-Infinity')))
    or (p_shipping_amount is not null and (p_shipping_amount<0 or p_shipping_amount::text in ('NaN','Infinity','-Infinity')))
    or (p_tax_amount is not null and (p_tax_amount<0 or p_tax_amount::text in ('NaN','Infinity','-Infinity'))) then raise exception using errcode='22023',message='adjustment_amount_invalid';end if;
  v_fp:=md5(jsonb_build_object('v','customer-adjustment-v1','transaction',p_transaction_id,'line',p_transaction_line_id,'kind',p_adjustment_kind,'effect',p_effect,'currency',p_currency,'merchandise',p_merchandise_amount,'shipping',p_shipping_amount,'tax',p_tax_amount,'occurred',extract(epoch from p_occurred_at)::numeric,'precision',p_occurred_at_precision,'reason',p_reason,'source_kind',p_source_kind,'connection',p_source_connection_id,'source_event',p_source_event_id,'source_component',p_source_component_id,'reinstates_cancellation_id',p_reinstates_cancellation_id,'evidence',p_evidence)::text);
  perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|customer-commercial|'||p_idempotency_key,0));
  select request_fingerprint,result into v_old from public.e10_customer_commercial_receipts where organization_id=p_org and idempotency_key=p_idempotency_key;
  if found then if v_old.request_fingerprint<>v_fp then raise exception using errcode='22023',message='idempotency_key_mismatch';end if;return v_old.result||'{"replay":true}'::jsonb;end if;
  perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|customer-adjustment|'||p_transaction_line_id::text,0));
  select l.*,t.currency,t.commercial_event_id as original_event_id into v_line from public.e10_customer_transaction_lines l join public.e10_customer_transactions t on t.organization_id=l.organization_id and t.id=l.transaction_id
    where l.organization_id=p_org and l.id=p_transaction_line_id and l.transaction_id=p_transaction_id;
  if not found then raise exception using errcode='42501',message='adjustment_line_denied';end if;
  if v_line.currency<>p_currency then raise exception using errcode='22023',message='adjustment_currency_mismatch';end if;
  select v_line.merchandise_net+coalesce(sum(case effect when 'increase' then merchandise_amount else -merchandise_amount end),0),
    v_line.shipping_amount+coalesce(sum(case effect when 'increase' then shipping_amount else -shipping_amount end),0),
    v_line.tax_amount+coalesce(sum(case effect when 'increase' then tax_amount else -tax_amount end),0)
    into v_merch,v_ship,v_tax from public.e10_customer_transaction_adjustments where organization_id=p_org and transaction_line_id=p_transaction_line_id;
  if (p_merchandise_amount is not null and v_merch is null) or (p_shipping_amount is not null and v_ship is null) or (p_tax_amount is not null and v_tax is null) then raise exception using errcode='22023',message='adjustment_component_unknown';end if;
  if p_effect='decrease' and (coalesce(p_merchandise_amount,0)>coalesce(v_merch,0) or coalesce(p_shipping_amount,0)>coalesce(v_ship,0) or coalesce(p_tax_amount,0)>coalesce(v_tax,0)) then raise exception using errcode='22023',message='adjustment_exceeds_remaining_amount';end if;
  if p_reinstates_cancellation_id is not null and not exists(select 1 from public.e10_customer_transaction_adjustments cancelled where cancelled.organization_id=p_org and cancelled.id=p_reinstates_cancellation_id and cancelled.transaction_line_id=p_transaction_line_id and cancelled.adjustment_kind='cancellation' and not exists(select 1 from public.e10_customer_transaction_adjustments prior_reinstatement where prior_reinstatement.organization_id=p_org and prior_reinstatement.reinstates_cancellation_id=cancelled.id)) then raise exception using errcode='22023',message='reinstatement_target_invalid';end if;
  if p_reinstates_cancellation_id is null and p_effect='increase' and exists(select 1 from public.e10_customer_transaction_adjustments cancelled where cancelled.organization_id=p_org and cancelled.transaction_line_id=p_transaction_line_id and cancelled.adjustment_kind='cancellation' and not exists(select 1 from public.e10_customer_transaction_adjustments prior_reinstatement where prior_reinstatement.organization_id=p_org and prior_reinstatement.reinstates_cancellation_id=cancelled.id)) then raise exception using errcode='22023',message='cancelled_line_requires_explicit_reinstatement';end if;
  if p_adjustment_kind='cancellation' and exists(select 1 from public.e10_customer_transaction_adjustments cancelled where cancelled.organization_id=p_org and cancelled.transaction_line_id=p_transaction_line_id and cancelled.adjustment_kind='cancellation' and not exists(select 1 from public.e10_customer_transaction_adjustments prior_reinstatement where prior_reinstatement.organization_id=p_org and prior_reinstatement.reinstates_cancellation_id=cancelled.id)) then raise exception using errcode='22023',message='transaction_line_already_cancelled';end if;
  if p_adjustment_kind='cancellation' and ((v_merch is not null and coalesce(p_merchandise_amount,0)<>v_merch) or (v_ship is not null and coalesce(p_shipping_amount,0)<>v_ship) or (v_tax is not null and coalesce(p_tax_amount,0)<>v_tax)) then raise exception using errcode='22023',message='cancellation_must_zero_known_components';end if;
  v_event_type:=case when p_adjustment_kind='refund' then 'refund' else 'correction' end;v_total:=coalesce(p_merchandise_amount,0)+coalesce(p_shipping_amount,0)+coalesce(p_tax_amount,0);
  insert into public.e10_customer_transaction_adjustments(id,organization_id,transaction_id,transaction_line_id,adjustment_kind,currency,merchandise_amount,shipping_amount,tax_amount,occurred_at,occurred_at_precision,reason,source_reference,commercial_event_id,created_by,effect,source_kind,source_connection_id,source_event_id,source_component_id,reinstates_cancellation_id,evidence,idempotency_key,request_fingerprint)
  values(v_adjustment,p_org,p_transaction_id,p_transaction_line_id,p_adjustment_kind,p_currency,p_merchandise_amount,p_shipping_amount,p_tax_amount,p_occurred_at,p_occurred_at_precision,btrim(p_reason),p_source_event_id,v_event,auth.uid(),p_effect,p_source_kind,nullif(btrim(p_source_connection_id),''),btrim(p_source_event_id),btrim(p_source_component_id),p_reinstates_cancellation_id,p_evidence,p_idempotency_key,v_fp);
  insert into public.e10_commercial_events(id,organization_id,event_type,event_schema_version,subject_type,subject_id,occurred_at,occurred_at_precision,idempotency_key,source_kind,source_connection_id,source_event_id,correlation_id,evidence_quality,payload,created_by,request_fingerprint,customer_transaction_adjustment_id,corrects_event_id)
  values(v_event,p_org,v_event_type,1,'customer_transaction',p_transaction_id::text,p_occurred_at,p_occurred_at_precision,'customer-adjustment:'||p_idempotency_key,p_source_kind,p_source_connection_id,p_source_event_id||'#'||p_source_component_id,p_transaction_id::text,case when p_source_kind='import' then 'reviewed_import' else 'operator_asserted' end,
    case when v_event_type='refund' then jsonb_build_object('refund_id',v_adjustment,'currency',p_currency,'amount',v_total,'effect',p_effect) else jsonb_build_object('reason',btrim(p_reason),'adjustment_id',v_adjustment,'currency',p_currency,'amount',v_total,'effect',p_effect) end,
    auth.uid(),md5('customer-adjustment-event|'||v_fp),v_adjustment,case when v_event_type='correction' then v_line.original_event_id else null end);
  v_result:=jsonb_build_object('ok',true,'replay',false,'adjustment_id',v_adjustment,'event_id',v_event,'transaction_id',p_transaction_id,'line_id',p_transaction_line_id,'effect',p_effect,'paid_changed',false,'settlement_changed',false,'inventory_returned',false);
  insert into public.e10_customer_commercial_receipts values(p_org,p_idempotency_key,'adjust_transaction',v_adjustment,v_fp,v_result,auth.uid(),now());return v_result;
exception when unique_violation then
  if exists(select 1 from public.e10_customer_transaction_adjustments where organization_id=p_org and source_kind=p_source_kind and coalesce(source_connection_id,'')=coalesce(p_source_connection_id,'') and source_event_id=p_source_event_id and source_component_id=p_source_component_id) then raise exception using errcode='23505',message='adjustment_source_component_already_recorded';end if;raise;
end $$;

revoke all on function public.e10_org_adjust_customer_transaction(uuid,uuid,uuid,text,text,text,numeric,numeric,numeric,timestamptz,text,text,text,text,text,text,uuid,jsonb,text) from public,anon;
grant execute on function public.e10_org_adjust_customer_transaction(uuid,uuid,uuid,text,text,text,numeric,numeric,numeric,timestamptz,text,text,text,text,text,text,uuid,jsonb,text) to authenticated,service_role;
comment on function public.e10_org_adjust_customer_transaction(uuid,uuid,uuid,text,text,text,numeric,numeric,numeric,timestamptz,text,text,text,text,text,text,uuid,jsonb,text) is 'Appends reviewed delta changes to known posted-spend components; NULL means unaffected, not an applied unknown amount. Unknown-component absolute finalization is required in TA-X6d.2. Never asserts payment, settlement, fee/proceeds, or physical return.';
