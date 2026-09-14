-- Vendor bill cost evidence. Existing receipt cost remains compatible but is
-- explicitly provisional. Approved-invoice support is separate and append-only.

create table public.e10_receipt_cost_evidence(
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.e10_organizations(id),
  receipt_line_id uuid not null,
  evidence_basis text not null check(evidence_basis in('operator_entered','approved_invoice_supported')),
  supported_quantity numeric not null check(supported_quantity>0 and supported_quantity::text not in('NaN','Infinity','-Infinity')),
  unit_cost numeric not null check(unit_cost>=0 and unit_cost::text not in('NaN','Infinity','-Infinity')),
  currency text not null check(currency~'^[A-Z]{3}$'),
  supplier_invoice_line_id uuid,
  supplier_invoice_revision integer,
  corrects_evidence_id uuid,
  reason text not null check(btrim(reason)<>'' and length(reason)<=2000),
  idempotency_key text not null check(btrim(idempotency_key)<>'' and length(idempotency_key)<=200),
  request_fingerprint text not null,
  recorded_by uuid references auth.users(id),
  recorded_at timestamptz not null default clock_timestamp(),
  unique(organization_id,id),
  unique(organization_id,idempotency_key),
  unique(organization_id,corrects_evidence_id),
  foreign key(organization_id,receipt_line_id) references public.e10_stock_receipt_lines(organization_id,id),
  foreign key(organization_id,supplier_invoice_line_id) references public.e10_supplier_invoice_lines(organization_id,id),
  foreign key(organization_id,corrects_evidence_id) references public.e10_receipt_cost_evidence(organization_id,id),
  check((evidence_basis='operator_entered' and supplier_invoice_line_id is null and supplier_invoice_revision is null)
    or (evidence_basis='approved_invoice_supported' and supplier_invoice_line_id is not null and supplier_invoice_revision is not null))
);
create index e10_receipt_cost_evidence_line_time_idx on public.e10_receipt_cost_evidence
  (organization_id,receipt_line_id,recorded_at desc,id);
alter table public.e10_receipt_cost_evidence enable row level security;
revoke all on table public.e10_receipt_cost_evidence from public,anon,authenticated;
grant all on table public.e10_receipt_cost_evidence to service_role;
create trigger e10_receipt_cost_evidence_append_only_trg before update or delete
on public.e10_receipt_cost_evidence for each row execute function e10.reject_append_only_change();

comment on table public.e10_receipt_cost_evidence is
  'Append-only receipt cost provenance. operator_entered is provisional; approved_invoice_supported is not payment evidence.';

create function e10.capture_operator_receipt_cost() returns trigger
language plpgsql security definer set search_path=public as $$
declare fp text;
begin
  if new.actual_unit_cost is null or new.accepted_quantity<=0 then return new;end if;
  fp:=md5(jsonb_build_array('receipt-cost-v1',new.organization_id,new.id,'operator_entered',
    new.accepted_quantity,new.actual_unit_cost,new.currency)::text);
  insert into public.e10_receipt_cost_evidence(organization_id,receipt_line_id,evidence_basis,
    supported_quantity,unit_cost,currency,reason,idempotency_key,request_fingerprint,recorded_by)
  values(new.organization_id,new.id,'operator_entered',new.accepted_quantity,new.actual_unit_cost,new.currency,
    'Cost entered during physical receipt; provisional until supported by approved invoice evidence.',
    'receipt-line-origin:'||new.id,fp,auth.uid()) on conflict(organization_id,idempotency_key) do nothing;
  return new;
end $$;
revoke all on function e10.capture_operator_receipt_cost() from public,anon,authenticated;
grant execute on function e10.capture_operator_receipt_cost() to service_role;
create trigger e10_capture_operator_receipt_cost_trg after insert on public.e10_stock_receipt_lines
for each row execute function e10.capture_operator_receipt_cost();

-- Backfill is explicit and semantics-preserving: legacy receipt-entered costs
-- become provisional operator evidence, never approved, finalized, or paid.
insert into public.e10_receipt_cost_evidence(organization_id,receipt_line_id,evidence_basis,
  supported_quantity,unit_cost,currency,reason,idempotency_key,request_fingerprint,recorded_by,recorded_at)
select l.organization_id,l.id,'operator_entered',l.accepted_quantity,l.actual_unit_cost,l.currency,
  'Legacy receipt-entered cost backfill; provisional until approved invoice support is recorded.',
  'receipt-line-origin:'||l.id,
  md5(jsonb_build_array('receipt-cost-v1',l.organization_id,l.id,'operator_entered',l.accepted_quantity,l.actual_unit_cost,l.currency)::text),
  r.created_by,l.created_at
from public.e10_stock_receipt_lines l join public.e10_stock_receipts r
  on(r.organization_id,r.id)=(l.organization_id,l.stock_receipt_id)
where l.actual_unit_cost is not null and l.accepted_quantity>0;

create function public.e10_org_record_approved_invoice_receipt_cost(
  p_org uuid,p_receipt_line_id uuid,p_invoice_line_id uuid,p_supported_quantity numeric,
  p_unit_cost numeric,p_reason text,p_idempotency_key text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare actor uuid:=auth.uid();fp text;existing record;rl record;il record;result jsonb;evidence_id uuid:=gen_random_uuid();
begin
  if actor is null or not exists(select 1 from public.e10_organizations where id=p_org and status='active')
    or not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.purchasing_approve')
    or not e10.has_org_cap(p_org,'financial.actual_cost.read') then
    raise exception using errcode='42501',message='receipt_cost_evidence_denied';
  end if;
  if p_supported_quantity is null or p_supported_quantity<=0 or p_supported_quantity::text in('NaN','Infinity','-Infinity')
    or p_unit_cost is null or p_unit_cost<0 or p_unit_cost::text in('NaN','Infinity','-Infinity')
    or p_reason is null or btrim(p_reason)='' or length(p_reason)>2000
    or p_idempotency_key is null or btrim(p_idempotency_key)='' or length(p_idempotency_key)>200 then
    raise exception using errcode='22023',message='receipt_cost_evidence_payload_invalid';
  end if;
  fp:=md5(jsonb_build_array('approved-receipt-cost-v1',p_org,p_receipt_line_id,p_invoice_line_id,
    p_supported_quantity,p_unit_cost,btrim(p_reason))::text);
  perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|receipt-cost|'||btrim(p_idempotency_key),0));
  select request_fingerprint,id into existing from public.e10_receipt_cost_evidence
    where organization_id=p_org and idempotency_key=btrim(p_idempotency_key);
  if found then
    if existing.request_fingerprint<>fp then raise exception using errcode='22023',message='idempotency_key_mismatch';end if;
    if auth.uid() is distinct from actor or not e10.is_org_member(p_org)
      or not e10.has_org_cap(p_org,'act.purchasing_approve') or not e10.has_org_cap(p_org,'financial.actual_cost.read') then
      raise exception using errcode='42501',message='receipt_cost_evidence_denied';end if;
    return jsonb_build_object('ok',true,'replay',true,'cost_evidence_id',existing.id,'payment_status','unavailable_not_modeled');
  end if;
  perform 1 from public.e10_stock_receipt_lines where organization_id=p_org and id=p_receipt_line_id for update;
  perform 1 from public.e10_supplier_invoice_lines where organization_id=p_org and id=p_invoice_line_id for update;
  if auth.uid() is distinct from actor or not exists(select 1 from public.e10_organizations where id=p_org and status='active')
    or not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.purchasing_approve')
    or not e10.has_org_cap(p_org,'financial.actual_cost.read') then
    raise exception using errcode='42501',message='receipt_cost_evidence_denied';end if;
  select l.configuration_version_id,q.effective_accepted into rl from public.e10_stock_receipt_lines l
    cross join lateral e10.receipt_line_effective_quantities(p_org,l.id) q
    where l.organization_id=p_org and l.id=p_receipt_line_id;
  select l.configuration_version_id,l.unit_cost,d.currency,d.revision,d.approved_revision,d.status into il
    from public.e10_supplier_invoice_lines l join public.e10_supplier_invoices d
      on(d.organization_id,d.id)=(l.organization_id,l.supplier_invoice_id)
    where l.organization_id=p_org and l.id=p_invoice_line_id and l.state='active';
  if rl.configuration_version_id is null or il.configuration_version_id is distinct from rl.configuration_version_id
    or il.status<>'approved' or il.approved_revision is distinct from il.revision
    or not exists(select 1 from public.e10_receipt_invoice_allocations a
      where a.organization_id=p_org and a.receipt_line_id=p_receipt_line_id and a.invoice_line_id=p_invoice_line_id
        and a.allocated_quantity>=p_supported_quantity)
    or p_supported_quantity>rl.effective_accepted or il.unit_cost is null or p_unit_cost<>il.unit_cost then
    raise exception using errcode='55000',message='receipt_cost_evidence_not_supported';
  end if;
  perform e10.assert_configuration_quantity(p_org,rl.configuration_version_id,p_supported_quantity,'supported_quantity');
  insert into public.e10_receipt_cost_evidence(id,organization_id,receipt_line_id,evidence_basis,
    supported_quantity,unit_cost,currency,supplier_invoice_line_id,supplier_invoice_revision,
    reason,idempotency_key,request_fingerprint,recorded_by)
  values(evidence_id,p_org,p_receipt_line_id,'approved_invoice_supported',p_supported_quantity,p_unit_cost,
    il.currency,p_invoice_line_id,il.revision,btrim(p_reason),btrim(p_idempotency_key),fp,actor);
  result:=jsonb_build_object('ok',true,'replay',false,'cost_evidence_id',evidence_id,
    'evidence_basis','approved_invoice_supported','supported_quantity',p_supported_quantity,
    'currency',il.currency,'payment_status','unavailable_not_modeled');
  return result;
end $$;
revoke all on function public.e10_org_record_approved_invoice_receipt_cost(uuid,uuid,uuid,numeric,numeric,text,text)
  from public,anon;
grant execute on function public.e10_org_record_approved_invoice_receipt_cost(uuid,uuid,uuid,numeric,numeric,text,text)
  to authenticated,service_role;
