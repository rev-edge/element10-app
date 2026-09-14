-- Cross-vendor bill register, invoice-after-receipt linking, and immutable
-- financial duplicate/conflict dispositions. No stock or payment side effect.

create table public.e10_receipt_invoice_link_events(
 id uuid primary key default gen_random_uuid(),organization_id uuid not null references public.e10_organizations(id),
 receipt_line_id uuid not null,invoice_line_id uuid not null,operation text not null check(operation in('link','release')),
 quantity_delta numeric not null check(quantity_delta<>0),reason text not null check(btrim(reason)<>''),
 idempotency_key text not null,request_fingerprint text not null,created_by uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp(),
 unique(organization_id,id),unique(organization_id,idempotency_key),
 foreign key(organization_id,receipt_line_id) references public.e10_stock_receipt_lines(organization_id,id),
 foreign key(organization_id,invoice_line_id) references public.e10_supplier_invoice_lines(organization_id,id)
);
create trigger e10_receipt_invoice_link_events_append_only_trg before update or delete on public.e10_receipt_invoice_link_events for each row execute function e10.reject_append_only_change();
alter table public.e10_receipt_invoice_link_events enable row level security;
revoke all on public.e10_receipt_invoice_link_events from public,anon,authenticated;grant all on public.e10_receipt_invoice_link_events to service_role;

create function public.e10_org_link_receipt_to_invoice(p_org uuid,p_receipt_line uuid,p_invoice_line uuid,p_quantity numeric,p_operation text,p_reason text,p_idempotency_key text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare actor uuid:=auth.uid();fp text;ev record;rl record;il record;pair numeric;rt numeric;it numeric;result jsonb;eid uuid:=gen_random_uuid();
begin
 if actor is null or not exists(select 1 from public.e10_organizations where id=p_org and status='active')or not e10.is_org_member(p_org)
  or not e10.has_org_cap(p_org,'act.purchasing_prepare')or not e10.has_org_cap(p_org,'financial.actual_cost.read')then raise exception using errcode='42501',message='receipt_invoice_link_denied';end if;
 if p_operation not in('link','release')or p_quantity is null or p_quantity<=0 or p_quantity::text in('NaN','Infinity','-Infinity')
  or p_reason is null or btrim(p_reason)=''or length(p_reason)>2000 or p_idempotency_key is null or btrim(p_idempotency_key)=''or length(p_idempotency_key)>200 then raise exception using errcode='22023',message='receipt_invoice_link_payload_invalid';end if;
 fp:=md5(jsonb_build_array('receipt-invoice-link-v1',p_org,p_receipt_line,p_invoice_line,p_quantity,p_operation,btrim(p_reason))::text);
 perform pg_advisory_xact_lock(hashtextextended(p_org||'|receipt-invoice-link|'||btrim(p_idempotency_key),0));
 select * into ev from public.e10_receipt_invoice_link_events where organization_id=p_org and idempotency_key=btrim(p_idempotency_key);
 if found then if ev.request_fingerprint<>fp then raise exception using errcode='22023',message='idempotency_key_mismatch';end if;
  if auth.uid()is distinct from actor or not e10.is_org_member(p_org)or not e10.has_org_cap(p_org,'act.purchasing_prepare')or not e10.has_org_cap(p_org,'financial.actual_cost.read')then raise exception using errcode='42501',message='receipt_invoice_link_denied';end if;
  return jsonb_build_object('ok',true,'replay',true,'link_event_id',ev.id);end if;
 perform pg_advisory_xact_lock(hashtextextended(p_org||'|receipt-line|'||p_receipt_line,0));perform pg_advisory_xact_lock(hashtextextended(p_org||'|invoice-line|'||p_invoice_line,0));
 if auth.uid()is distinct from actor or not exists(select 1 from public.e10_organizations where id=p_org and status='active')or not e10.is_org_member(p_org)
  or not e10.has_org_cap(p_org,'act.purchasing_prepare')or not e10.has_org_cap(p_org,'financial.actual_cost.read')then raise exception using errcode='42501',message='receipt_invoice_link_denied';end if;
 select l.*,r.supplier_id,r.status receipt_status into rl from public.e10_stock_receipt_lines l join public.e10_stock_receipts r on(r.organization_id,r.id)=(l.organization_id,l.stock_receipt_id)where l.organization_id=p_org and l.id=p_receipt_line for update of l,r;
 select l.*,d.supplier_id,d.status invoice_status into il from public.e10_supplier_invoice_lines l join public.e10_supplier_invoices d on(d.organization_id,d.id)=(l.organization_id,l.supplier_invoice_id)where l.organization_id=p_org and l.id=p_invoice_line for update of l,d;
 if rl.id is null or il.id is null or rl.receipt_status not in('posted','corrected')or il.invoice_status='void'or rl.supplier_id<>il.supplier_id or rl.configuration_version_id is distinct from il.configuration_version_id then raise exception using errcode='55000',message='receipt_invoice_link_incompatible';end if;
 perform e10.assert_configuration_quantity(p_org,rl.configuration_version_id,p_quantity,'receipt_invoice_link.quantity');
 select coalesce(allocated_quantity,0)into pair from public.e10_receipt_invoice_allocations where organization_id=p_org and receipt_line_id=p_receipt_line and invoice_line_id=p_invoice_line;pair:=coalesce(pair,0);
 if p_operation='link'then
  select coalesce(sum(allocated_quantity),0)into rt from public.e10_receipt_invoice_allocations where organization_id=p_org and receipt_line_id=p_receipt_line;
  select coalesce(sum(allocated_quantity),0)into it from public.e10_receipt_invoice_allocations where organization_id=p_org and invoice_line_id=p_invoice_line;
  if rt+p_quantity>rl.received_quantity or il.invoiced_quantity is null or it+p_quantity>il.invoiced_quantity then raise exception using errcode='23514',message='receipt_invoice_link_conservation_violation';end if;
  insert into public.e10_receipt_invoice_allocations values(p_org,p_receipt_line,p_invoice_line,p_quantity,now())on conflict(organization_id,receipt_line_id,invoice_line_id)do update set allocated_quantity=e10_receipt_invoice_allocations.allocated_quantity+excluded.allocated_quantity;
 else if pair<p_quantity then raise exception using errcode='23514',message='receipt_invoice_link_release_exceeds_pair';end if;
  if pair=p_quantity then delete from public.e10_receipt_invoice_allocations where organization_id=p_org and receipt_line_id=p_receipt_line and invoice_line_id=p_invoice_line;
  else update public.e10_receipt_invoice_allocations set allocated_quantity=allocated_quantity-p_quantity where organization_id=p_org and receipt_line_id=p_receipt_line and invoice_line_id=p_invoice_line;end if;
 end if;
 insert into public.e10_receipt_invoice_link_events(id,organization_id,receipt_line_id,invoice_line_id,operation,quantity_delta,reason,idempotency_key,request_fingerprint,created_by)
 values(eid,p_org,p_receipt_line,p_invoice_line,p_operation,case when p_operation='link'then p_quantity else-p_quantity end,btrim(p_reason),btrim(p_idempotency_key),fp,actor);
 result:=jsonb_build_object('ok',true,'replay',false,'link_event_id',eid,'allocated_quantity',case when p_operation='link'then pair+p_quantity else pair-p_quantity end,'stock_changed',false,'payment_status','unavailable_not_modeled');return result;
end$$;
revoke all on function public.e10_org_link_receipt_to_invoice(uuid,uuid,uuid,numeric,text,text,text)from public,anon;grant execute on function public.e10_org_link_receipt_to_invoice(uuid,uuid,uuid,numeric,text,text,text)to authenticated,service_role;

create table public.e10_financial_reconciliation_decisions(
 id uuid primary key default gen_random_uuid(),organization_id uuid not null references public.e10_organizations(id),case_id uuid not null,
 outcome text not null check(outcome in('same_document','different_document','cannot_determine')),reason text not null check(btrim(reason)<>''),evidence jsonb not null default'{}',
 idempotency_key text not null,request_fingerprint text not null,decided_by uuid not null references auth.users(id),decided_at timestamptz not null default clock_timestamp(),
 unique(organization_id,id),unique(organization_id,case_id),unique(organization_id,idempotency_key),
 foreign key(organization_id,case_id)references public.e10_financial_document_reconciliation_cases(organization_id,id),check(jsonb_typeof(evidence)='object')
);
create trigger e10_fin_recon_decisions_append_only_trg before update or delete on public.e10_financial_reconciliation_decisions for each row execute function e10.reject_append_only_change();
alter table public.e10_financial_reconciliation_decisions enable row level security;revoke all on public.e10_financial_reconciliation_decisions from public,anon,authenticated;grant all on public.e10_financial_reconciliation_decisions to service_role;

create function public.e10_org_decide_financial_document_reconciliation(p_org uuid,p_case uuid,p_outcome text,p_reason text,p_evidence jsonb,p_idempotency_key text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare actor uuid:=auth.uid();fp text;d record;new_id uuid:=gen_random_uuid();
begin
 if actor is null or not e10.is_org_member(p_org)or not e10.has_org_cap(p_org,'act.purchasing_approve')then raise exception using errcode='42501',message='financial_reconciliation_decision_denied';end if;
 if p_outcome not in('same_document','different_document','cannot_determine')or p_reason is null or btrim(p_reason)=''or p_evidence is null or jsonb_typeof(p_evidence)<>'object'or p_idempotency_key is null or btrim(p_idempotency_key)=''then raise exception using errcode='22023',message='financial_reconciliation_decision_payload_invalid';end if;
 fp:=md5(jsonb_build_array('financial-reconciliation-decision-v1',p_org,p_case,p_outcome,btrim(p_reason),p_evidence)::text);
 perform pg_advisory_xact_lock(hashtextextended(p_org||'|financial-reconciliation|'||p_case,0));
 select * into d from public.e10_financial_reconciliation_decisions where organization_id=p_org and(case_id=p_case or idempotency_key=btrim(p_idempotency_key));
 if found then if d.request_fingerprint<>fp then raise exception using errcode='22023',message='financial_reconciliation_already_decided';end if;return jsonb_build_object('ok',true,'replay',true,'decision_id',d.id,'outcome',d.outcome);end if;
 if not exists(select 1 from public.e10_financial_document_reconciliation_cases c where c.organization_id=p_org and c.id=p_case)then raise exception using errcode='42501',message='financial_reconciliation_case_access_denied';end if;
 if auth.uid()is distinct from actor or not e10.is_org_member(p_org)or not e10.has_org_cap(p_org,'act.purchasing_approve')then raise exception using errcode='42501',message='financial_reconciliation_decision_denied';end if;
 insert into public.e10_financial_reconciliation_decisions values(new_id,p_org,p_case,p_outcome,btrim(p_reason),p_evidence,btrim(p_idempotency_key),fp,actor,clock_timestamp());
 return jsonb_build_object('ok',true,'replay',false,'decision_id',new_id,'outcome',p_outcome);
end$$;
revoke all on function public.e10_org_decide_financial_document_reconciliation(uuid,uuid,text,text,jsonb,text)from public,anon;grant execute on function public.e10_org_decide_financial_document_reconciliation(uuid,uuid,text,text,jsonb,text)to authenticated,service_role;

create function public.e10_org_bill_register(p_org uuid,p_status text[],p_supplier uuid,p_currency text,p_from date,p_to date,p_limit integer,p_cursor text)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare actor uuid:=auth.uid();fp text;cur jsonb;after_date date;after_id uuid;items jsonb;more boolean;lastrow record;totals jsonb;
begin
 if actor is null or not exists(select 1 from public.e10_organizations where id=p_org and status='active')or not e10.is_org_member(p_org)or not e10.has_org_cap(p_org,'financial.actual_cost.read')then raise exception using errcode='42501',message='bill_register_denied';end if;
 if p_limit not between 1 and 200 or p_from is not null and p_to is not null and p_from>p_to or p_currency is not null and p_currency!~'^[A-Z]{3}$'then raise exception using errcode='22023',message='bill_register_bounds_invalid';end if;
 fp:=md5(jsonb_build_array('bill-register-v1',actor,p_status,p_supplier,p_currency,p_from,p_to)::text);if p_cursor is not null then cur:=e10.inventory_cursor_decode(p_org,p_cursor);if cur->>'fp'<>fp then raise exception using errcode='40001',message='bill_register_cursor_mismatch';end if;after_date:=(cur->>'document_date')::date;after_id:=(cur->>'id')::uuid;end if;
 with scoped as(select i.*,s.name supplier_name,coalesce((select sum(a.allocated_quantity)from public.e10_invoice_po_allocations a join public.e10_supplier_invoice_lines l on(l.organization_id,l.id)=(a.organization_id,a.invoice_line_id)where l.organization_id=i.organization_id and l.supplier_invoice_id=i.id),0)po_matched,
  coalesce((select sum(a.allocated_quantity)from public.e10_receipt_invoice_allocations a join public.e10_supplier_invoice_lines l on(l.organization_id,l.id)=(a.organization_id,a.invoice_line_id)where l.organization_id=i.organization_id and l.supplier_invoice_id=i.id),0)received
  from public.e10_supplier_invoices i join public.e10_suppliers s on(s.organization_id,s.id)=(i.organization_id,i.supplier_id)where i.organization_id=p_org and(p_status is null or i.status=any(p_status))and(p_supplier is null or i.supplier_id=p_supplier)and(p_currency is null or i.currency=p_currency)and(p_from is null or i.document_date>=p_from)and(p_to is null or i.document_date<=p_to)),
 page as(select * from scoped where after_id is null or(coalesce(document_date,'-infinity'::date),id)<(after_date,after_id)order by document_date desc nulls last,id desc limit p_limit+1),shown as(select * from page order by document_date desc nulls last,id desc limit p_limit)
 select coalesce(jsonb_agg(jsonb_build_object('invoice_id',id,'supplier_id',supplier_id,'supplier_name',supplier_name,'document_number',supplier_document_number,'document_date',document_date,'currency',currency,'total_amount',total_amount,'document_status',status,'matching_status',case when po_matched=0 then'unmatched'else'partially_or_fully_matched'end,'receipt_status',case when received=0 then'not_received'else'partially_or_fully_received'end,'payment_status','unavailable_not_modeled','revision',revision)order by document_date desc nulls last,id desc),'[]'),(select count(*)>p_limit from page)into items,more from shown;
 select jsonb_object_agg(currency,jsonb_build_object('document_count',n,'known_total_amount',amount,'unknown_total_count',unknowns))into totals from(select currency,count(*)n,coalesce(sum(total_amount),0)amount,count(*)filter(where total_amount is null)unknowns from public.e10_supplier_invoices where organization_id=p_org and(p_status is null or status=any(p_status))and(p_supplier is null or supplier_id=p_supplier)and(p_currency is null or currency=p_currency)and(p_from is null or document_date>=p_from)and(p_to is null or document_date<=p_to)group by currency)q;
 if jsonb_array_length(items)>0 then
  select coalesce(i.document_date,'-infinity'::date) as document_date,i.id into lastrow
  from public.e10_supplier_invoices i
  where i.organization_id=p_org
    and i.id=(items->(jsonb_array_length(items)-1)->>'invoice_id')::uuid;
 end if;
 return jsonb_build_object('items',items,'full_dataset_totals_by_currency',coalesce(totals,'{}'),'has_more',more,'next_cursor',case when more then e10.inventory_cursor_encode(p_org,jsonb_build_object('fp',fp,'document_date',lastrow.document_date,'id',lastrow.id))end,'payment_status','unavailable_not_modeled');
end$$;
revoke all on function public.e10_org_bill_register(uuid,text[],uuid,text,date,date,integer,text)from public,anon;grant execute on function public.e10_org_bill_register(uuid,text[],uuid,text,date,date,integer,text)to authenticated,service_role;
