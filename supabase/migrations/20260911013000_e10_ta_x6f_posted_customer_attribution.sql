-- TA-X6f selective reviewed customer attribution for immutable posted transactions.

alter table public.e10_customer_mutation_receipts drop constraint e10_customer_mutation_receipts_operation_check;
alter table public.e10_customer_mutation_receipts add constraint e10_customer_mutation_receipts_operation_check
  check(operation in ('create','update','identity','attribution','resolution','transaction_attribution'));

create table public.e10_customer_transaction_attribution_decisions (
  id uuid primary key default gen_random_uuid(),organization_id uuid not null,transaction_id uuid not null,
  revision integer not null check(revision>0),decision_action text not null check(decision_action in ('attribute','unattribute')),
  customer_id uuid,supersedes_decision_id uuid,
  reason text not null check(length(btrim(reason)) between 1 and 2000),
  evidence jsonb not null check(jsonb_typeof(evidence)='object' and octet_length(evidence::text)<=65536),
  idempotency_key text not null check(length(btrim(idempotency_key)) between 1 and 500),request_fingerprint text not null check(btrim(request_fingerprint)<>''),
  decided_by uuid references auth.users(id),decided_at timestamptz not null default now(),
  unique(organization_id,id),unique(organization_id,transaction_id,revision),unique(organization_id,idempotency_key),
  foreign key(organization_id,transaction_id) references public.e10_customer_transactions(organization_id,id),
  foreign key(organization_id,customer_id) references public.e10_customers(organization_id,id),
  foreign key(organization_id,supersedes_decision_id) references public.e10_customer_transaction_attribution_decisions(organization_id,id),
  check((decision_action='attribute' and customer_id is not null) or (decision_action='unattribute' and customer_id is null))
);
create unique index e10_customer_transaction_attribution_root_uq on public.e10_customer_transaction_attribution_decisions(organization_id,transaction_id)
  where supersedes_decision_id is null;
create unique index e10_customer_transaction_attribution_successor_uq on public.e10_customer_transaction_attribution_decisions(organization_id,supersedes_decision_id)
  where supersedes_decision_id is not null;
create index e10_customer_transaction_attribution_customer_idx on public.e10_customer_transaction_attribution_decisions(organization_id,customer_id,transaction_id)
  where customer_id is not null;

alter table public.e10_customer_transaction_attribution_decisions enable row level security;
revoke all on public.e10_customer_transaction_attribution_decisions from public,anon,authenticated;
grant all on public.e10_customer_transaction_attribution_decisions to service_role;
create trigger e10_customer_transaction_attribution_append_only_trg before update or delete on public.e10_customer_transaction_attribution_decisions
  for each row execute function e10.reject_append_only_change();

create view public.e10_current_customer_transaction_attributions with (security_invoker=true) as
select d.* from public.e10_customer_transaction_attribution_decisions d
where not exists(select 1 from public.e10_customer_transaction_attribution_decisions s
  where s.organization_id=d.organization_id and s.supersedes_decision_id=d.id);
revoke all on public.e10_current_customer_transaction_attributions from public,anon,authenticated;
grant select on public.e10_current_customer_transaction_attributions to service_role;

create function e10.customer_transaction_effective_attribution(p_org uuid,p_transaction uuid)
returns table(original_customer_id uuid,attribution_action text,attribution_customer_id uuid,attribution_revision integer,attribution_decision_id uuid,effective_customer_id uuid)
language sql stable security definer set search_path=public as $$
  select t.customer_id,d.decision_action,d.customer_id,d.revision,d.id,
    case when d.id is not null and d.decision_action='unattribute' then null
         else e10.customer_effective_id(t.organization_id,case when d.id is null then t.customer_id else d.customer_id end) end
  from public.e10_customer_transactions t
  left join public.e10_current_customer_transaction_attributions d on d.organization_id=t.organization_id and d.transaction_id=t.id
  where t.organization_id=p_org and t.id=p_transaction
$$;
revoke all on function e10.customer_transaction_effective_attribution(uuid,uuid) from public,anon,authenticated;
grant execute on function e10.customer_transaction_effective_attribution(uuid,uuid) to service_role;

create function public.e10_org_decide_customer_transaction_attribution(
  p_org uuid,p_transaction_id uuid,p_expected_revision integer,p_customer_id uuid,p_reason text,p_evidence jsonb,p_idempotency_key text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_action text;v_fp text;v_receipt record;v_prior record;v_id uuid:=gen_random_uuid();v_result jsonb;
begin
  if not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.correct_customer_attribution') then raise exception using errcode='42501',message='transaction_customer_attribution_denied';end if;
  if p_expected_revision is null or p_expected_revision<0 or p_reason is null or length(btrim(p_reason)) not between 1 and 2000
    or p_evidence is null or jsonb_typeof(p_evidence)<>'object' or octet_length(p_evidence::text)>65536
    or p_idempotency_key is null or length(btrim(p_idempotency_key)) not between 1 and 500 then raise exception using errcode='22023',message='transaction_customer_attribution_invalid';end if;
  v_action:=case when p_customer_id is null then 'unattribute' else 'attribute' end;
  v_fp:=md5(jsonb_build_object('v','transaction-customer-attribution-v1','transaction',p_transaction_id,'expected_revision',p_expected_revision,'customer',p_customer_id,'reason',btrim(p_reason),'evidence',p_evidence)::text);
  perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|customer-resolution-topology',0));
  if not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.correct_customer_attribution') then raise exception using errcode='42501',message='transaction_customer_attribution_denied';end if;
  perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|customer-mutation|'||p_idempotency_key,0));
  select operation,request_fingerprint,result into v_receipt from public.e10_customer_mutation_receipts where organization_id=p_org and idempotency_key=p_idempotency_key;
  if found then
    if v_receipt.operation<>'transaction_attribution' or v_receipt.request_fingerprint<>v_fp then raise exception using errcode='22023',message='idempotency_key_mismatch';end if;
    return v_receipt.result||'{"replay":true}'::jsonb;
  end if;
  perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|transaction-customer-attribution|'||p_transaction_id::text,0));
  perform 1 from public.e10_customer_transactions where organization_id=p_org and id=p_transaction_id for share;
  if not found then raise exception using errcode='42501',message='transaction_customer_attribution_transaction_denied';end if;
  select * into v_prior from public.e10_current_customer_transaction_attributions where organization_id=p_org and transaction_id=p_transaction_id;
  if coalesce(v_prior.revision,0)<>p_expected_revision then raise exception using errcode='40001',message='transaction_customer_attribution_revision_conflict';end if;
  if p_customer_id is not null then
    if not exists(select 1 from public.e10_customers where organization_id=p_org and id=p_customer_id and status='active') then raise exception using errcode='42501',message='transaction_customer_attribution_customer_denied';end if;
    if e10.customer_effective_id(p_org,p_customer_id)<>p_customer_id then raise exception using errcode='22023',message='transaction_customer_attribution_requires_effective_customer';end if;
  end if;
  if v_prior.id is not null and v_prior.customer_id is not distinct from p_customer_id then raise exception using errcode='22023',message='transaction_customer_attribution_unchanged';end if;
  insert into public.e10_customer_transaction_attribution_decisions(id,organization_id,transaction_id,revision,decision_action,customer_id,supersedes_decision_id,reason,evidence,idempotency_key,request_fingerprint,decided_by)
  values(v_id,p_org,p_transaction_id,p_expected_revision+1,v_action,p_customer_id,v_prior.id,btrim(p_reason),p_evidence,p_idempotency_key,v_fp,auth.uid());
  v_result:=jsonb_build_object('ok',true,'replay',false,'decision_id',v_id,'transaction_id',p_transaction_id,'revision',p_expected_revision+1,'action',v_action,'customer_id',p_customer_id,'effective_customer_id',case when p_customer_id is null then null else e10.customer_effective_id(p_org,p_customer_id) end,'source_rows_rewritten',false,'revenue_changed',false);
  insert into public.e10_customer_mutation_receipts values(p_org,p_idempotency_key,'transaction_attribution',v_id,v_fp,v_result,auth.uid(),now());
  return v_result;
end $$;

create function public.e10_org_list_customer_transaction_attribution_history(p_org uuid,p_transaction_id uuid,p_limit integer default 25,p_before_revision integer default null)
returns table(decision_id uuid,revision integer,decision_action text,customer_id uuid,reason text,evidence jsonb,decided_by uuid,decided_at timestamptz)
language plpgsql stable security definer set search_path=public as $$
begin
  if not e10.is_org_member(p_org) or not (e10.has_org_cap(p_org,'act.manage_customers') or e10.has_org_cap(p_org,'act.correct_customer_attribution')) then raise exception using errcode='42501',message='transaction_customer_attribution_history_denied';end if;
  if p_limit is null or p_limit<1 or p_limit>100 or (p_before_revision is not null and p_before_revision<1) then raise exception using errcode='22023',message='transaction_customer_attribution_page_invalid';end if;
  if not exists(select 1 from public.e10_customer_transactions where organization_id=p_org and id=p_transaction_id) then raise exception using errcode='42501',message='transaction_customer_attribution_transaction_denied';end if;
  return query select d.id,d.revision,d.decision_action,d.customer_id,d.reason,d.evidence,d.decided_by,d.decided_at
    from public.e10_customer_transaction_attribution_decisions d where d.organization_id=p_org and d.transaction_id=p_transaction_id and (p_before_revision is null or d.revision<p_before_revision)
    order by d.revision desc limit p_limit;
end $$;

create function public.e10_org_resolve_customer_transactions(p_org uuid,p_transaction_ids uuid[])
returns table(transaction_id uuid,original_customer_id uuid,attribution_action text,attribution_customer_id uuid,attribution_revision integer,attribution_decision_id uuid,effective_customer_id uuid)
language plpgsql stable security definer set search_path=public as $$
begin
  if not e10.is_org_member(p_org) or not (e10.has_org_cap(p_org,'act.manage_customers') or e10.has_org_cap(p_org,'act.correct_customer_attribution')) then raise exception using errcode='42501',message='resolve_customer_transactions_denied';end if;
  if p_transaction_ids is null or cardinality(p_transaction_ids)<1 or cardinality(p_transaction_ids)>100 or cardinality(p_transaction_ids)<>(select count(distinct x) from unnest(p_transaction_ids)x) then raise exception using errcode='22023',message='resolve_customer_transactions_input_invalid';end if;
  if (select count(*) from public.e10_customer_transactions where organization_id=p_org and id=any(p_transaction_ids))<>cardinality(p_transaction_ids) then raise exception using errcode='42501',message='resolve_customer_transactions_denied';end if;
  return query select t.id,a.original_customer_id,a.attribution_action,a.attribution_customer_id,a.attribution_revision,a.attribution_decision_id,a.effective_customer_id
    from public.e10_customer_transactions t cross join lateral e10.customer_transaction_effective_attribution(p_org,t.id)a
    where t.organization_id=p_org and t.id=any(p_transaction_ids) order by t.id;
end $$;

revoke all on function public.e10_org_decide_customer_transaction_attribution(uuid,uuid,integer,uuid,text,jsonb,text) from public,anon;
revoke all on function public.e10_org_list_customer_transaction_attribution_history(uuid,uuid,integer,integer) from public,anon;
revoke all on function public.e10_org_resolve_customer_transactions(uuid,uuid[]) from public,anon;
grant execute on function public.e10_org_decide_customer_transaction_attribution(uuid,uuid,integer,uuid,text,jsonb,text),public.e10_org_list_customer_transaction_attribution_history(uuid,uuid,integer,integer),public.e10_org_resolve_customer_transactions(uuid,uuid[]) to authenticated,service_role;

comment on table public.e10_customer_transaction_attribution_decisions is 'Immutable reviewed selective customer attribution. Posted transaction facts and every monetary effect remain unchanged.';
