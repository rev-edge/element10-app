-- TA-X3d.1c governed invoice/credit review, approval and void transitions.
-- Approval is financial review only: no stock, payment, accounting or PO side effect.

create function public._e10_org_transition_financial_document_x3d1c(
  p_org uuid,p_document_kind text,p_document_id uuid,p_expected_revision integer,
  p_action text,p_reason text,p_idempotency_key text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare
  actor uuid:=auth.uid(); required_cap text; fp text; existing_cmd record; document record;
  event_id uuid:=gen_random_uuid(); new_revision integer; new_status text; snapshot jsonb; result jsonb;
begin
  required_cap:=case p_action
    when 'review' then 'act.purchasing_prepare'
    when 'approve' then 'act.purchasing_approve'
    when 'void' then 'act.purchasing_cancel'
  end;
  if actor is null or p_document_kind not in ('supplier_invoice','supplier_credit')
    or required_cap is null
    or not exists(select 1 from public.e10_organizations where id=p_org and status='active')
    or not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,required_cap) then
    raise exception using errcode='42501',message='financial_document_transition_denied';
  end if;
  if p_expected_revision is null or p_expected_revision<1
    or p_reason is null or btrim(p_reason)='' or length(p_reason)>2000
    or p_idempotency_key is null or btrim(p_idempotency_key)='' or length(p_idempotency_key)>200 then
    raise exception using errcode='22023',message='financial_document_transition_payload_invalid';
  end if;
  fp:=md5(jsonb_build_object('v','financial-document-transition-v1','org',p_org,
    'kind',p_document_kind,'document_id',p_document_id,'expected_revision',p_expected_revision,
    'action',p_action,'reason',btrim(p_reason))::text);
  perform pg_advisory_xact_lock(hashtextextended(
    p_org::text||'|financial-document-command|'||p_idempotency_key,0));
  select c.request_fingerprint,c.result into existing_cmd
    from public.e10_financial_document_commands c
    where c.organization_id=p_org and c.idempotency_key=p_idempotency_key;
  if found then
    if existing_cmd.request_fingerprint<>fp then
      raise exception using errcode='22023',message='idempotency_key_mismatch';
    end if;
    if auth.uid() is distinct from actor
      or not exists(select 1 from public.e10_organizations where id=p_org and status='active')
      or not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,required_cap) then
      raise exception using errcode='42501',message='financial_document_transition_denied';
    end if;
    return existing_cmd.result||jsonb_build_object('replay',true);
  end if;

  perform e10.lock_financial_document(p_org,p_document_kind,p_document_id);
  if auth.uid() is distinct from actor
    or not exists(select 1 from public.e10_organizations where id=p_org and status='active')
    or not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,required_cap) then
    raise exception using errcode='42501',message='financial_document_transition_denied';
  end if;
  if p_document_kind='supplier_invoice' then
    select d.* into document from public.e10_supplier_invoices d
      where d.organization_id=p_org and d.id=p_document_id;
  else
    select d.* into document from public.e10_supplier_credits d
      where d.organization_id=p_org and d.id=p_document_id;
  end if;
  if document.revision<>p_expected_revision then
    raise exception using errcode='40001',message='financial_document_revision_conflict';
  end if;

  if p_action in ('review','approve') then
    if not exists(select 1 from public.e10_suppliers s
      where s.organization_id=p_org and s.id=document.supplier_id and s.status='active') then
      raise exception using errcode='55000',message='financial_document_supplier_inactive';
    end if;
    if (p_document_kind='supplier_invoice' and not exists(
        select 1 from public.e10_supplier_invoice_lines l
        where l.organization_id=p_org and l.supplier_invoice_id=p_document_id and l.state='active'))
      or (p_document_kind='supplier_credit' and not exists(
        select 1 from public.e10_supplier_credit_lines l
        where l.organization_id=p_org and l.supplier_credit_id=p_document_id and l.state='active')) then
      raise exception using errcode='55000',message='financial_document_has_no_active_lines';
    end if;
    if (p_document_kind='supplier_invoice' and exists(
        select 1 from public.e10_supplier_invoice_lines l
        left join public.e10_product_configuration_versions v
          on v.organization_id=l.organization_id and v.id=l.configuration_version_id and v.state='active'
        where l.organization_id=p_org and l.supplier_invoice_id=p_document_id and l.state='active'
          and l.configuration_version_id is not null and v.id is null))
      or (p_document_kind='supplier_credit' and exists(
        select 1 from public.e10_supplier_credit_lines l
        left join public.e10_product_configuration_versions v
          on v.organization_id=l.organization_id and v.id=l.configuration_version_id and v.state='active'
        where l.organization_id=p_org and l.supplier_credit_id=p_document_id and l.state='active'
          and l.configuration_version_id is not null and v.id is null)) then
      raise exception using errcode='55000',message='financial_document_configuration_inactive';
    end if;
  end if;

  if p_action='review' then
    if document.status<>'draft' then
      raise exception using errcode='55000',message='financial_document_transition_invalid';
    end if;
    new_status:='reviewed';
  elsif p_action='approve' then
    if document.status<>'reviewed' then
      raise exception using errcode='55000',message='financial_document_transition_invalid';
    end if;
    new_status:='approved';
  else
    if document.status not in ('draft','reviewed','approved') then
      raise exception using errcode='55000',message='financial_document_transition_invalid';
    end if;
    if p_document_kind='supplier_invoice' and (
      exists(select 1 from public.e10_invoice_po_allocations a
        join public.e10_supplier_invoice_lines l on l.organization_id=a.organization_id and l.id=a.invoice_line_id
        where l.organization_id=p_org and l.supplier_invoice_id=p_document_id)
      or exists(select 1 from public.e10_receipt_invoice_allocations a
        join public.e10_supplier_invoice_lines l on l.organization_id=a.organization_id and l.id=a.invoice_line_id
        where l.organization_id=p_org and l.supplier_invoice_id=p_document_id)
      or exists(select 1 from public.e10_credit_invoice_allocations a
        join public.e10_supplier_invoice_lines l on l.organization_id=a.organization_id and l.id=a.invoice_line_id
        where l.organization_id=p_org and l.supplier_invoice_id=p_document_id)
    ) or p_document_kind='supplier_credit' and exists(
      select 1 from public.e10_credit_invoice_allocations a
      join public.e10_supplier_credit_lines l on l.organization_id=a.organization_id and l.id=a.credit_line_id
      where l.organization_id=p_org and l.supplier_credit_id=p_document_id) then
      raise exception using errcode='55000',message='financial_document_has_active_allocations';
    end if;
    new_status:='void';
  end if;
  new_revision:=document.revision+1;

  if p_document_kind='supplier_invoice' then
    update public.e10_supplier_invoices set status=new_status,revision=new_revision,updated_at=now(),
      reviewed_by=case when p_action='review' then actor else reviewed_by end,
      reviewed_at=case when p_action='review' then now() else reviewed_at end,
      approved_revision=case when p_action='approve' then new_revision end,
      approved_by=case when p_action='approve' then actor end,
      approved_at=case when p_action='approve' then now() end,
      voided_by=case when p_action='void' then actor else voided_by end,
      voided_at=case when p_action='void' then now() else voided_at end
      where organization_id=p_org and id=p_document_id;
  else
    update public.e10_supplier_credits set status=new_status,revision=new_revision,updated_at=now(),
      reviewed_by=case when p_action='review' then actor else reviewed_by end,
      reviewed_at=case when p_action='review' then now() else reviewed_at end,
      approved_revision=case when p_action='approve' then new_revision end,
      approved_by=case when p_action='approve' then actor end,
      approved_at=case when p_action='approve' then now() end,
      voided_by=case when p_action='void' then actor else voided_by end,
      voided_at=case when p_action='void' then now() else voided_at end
      where organization_id=p_org and id=p_document_id;
  end if;

  snapshot:=e10.financial_document_snapshot(p_org,p_document_kind,p_document_id);
  if p_document_kind='supplier_invoice' then
    insert into public.e10_supplier_invoice_revisions
      (organization_id,supplier_invoice_id,revision,status,snapshot,payload_fingerprint,change_reason,created_by)
    values(p_org,p_document_id,new_revision,new_status,snapshot,fp,btrim(p_reason),actor);
  else
    insert into public.e10_supplier_credit_revisions
      (organization_id,supplier_credit_id,revision,status,snapshot,payload_fingerprint,change_reason,created_by)
    values(p_org,p_document_id,new_revision,new_status,snapshot,fp,btrim(p_reason),actor);
  end if;
  result:=jsonb_build_object('ok',true,'replay',false,
    case when p_document_kind='supplier_invoice' then 'supplier_invoice_id' else 'supplier_credit_id' end,p_document_id,
    'status',new_status,'revision',new_revision,'lifecycle_event_id',event_id);
  insert into public.e10_financial_document_commands
    (organization_id,idempotency_key,document_kind,operation,document_id,request_fingerprint,result,created_by)
  values(p_org,p_idempotency_key,p_document_kind,p_action,p_document_id,fp,result,actor);
  insert into public.e10_financial_document_events
    (id,organization_id,document_kind,document_id,operation,revision,status,
      command_idempotency_key,payload,created_by)
  values(event_id,p_org,p_document_kind,p_document_id,p_action,new_revision,new_status,
    p_idempotency_key,jsonb_build_object('document_id',p_document_id,'document_kind',p_document_kind,
      'operation',p_action,'status',new_status,'revision',new_revision,'reason',btrim(p_reason)),actor);
  return result;
end $$;
revoke all on function public._e10_org_transition_financial_document_x3d1c(
  uuid,text,uuid,integer,text,text,text) from public,anon,authenticated;
grant execute on function public._e10_org_transition_financial_document_x3d1c(
  uuid,text,uuid,integer,text,text,text) to service_role;

create function public.e10_org_review_supplier_invoice(
  p_org uuid,p_supplier_invoice_id uuid,p_expected_revision integer,p_reason text,p_idempotency_key text
) returns jsonb language sql security definer set search_path=public as $$
 select public._e10_org_transition_financial_document_x3d1c(
   p_org,'supplier_invoice',p_supplier_invoice_id,p_expected_revision,'review',p_reason,p_idempotency_key)
$$;
create function public.e10_org_approve_supplier_invoice(
  p_org uuid,p_supplier_invoice_id uuid,p_expected_revision integer,p_reason text,p_idempotency_key text
) returns jsonb language sql security definer set search_path=public as $$
 select public._e10_org_transition_financial_document_x3d1c(
   p_org,'supplier_invoice',p_supplier_invoice_id,p_expected_revision,'approve',p_reason,p_idempotency_key)
$$;
create function public.e10_org_void_supplier_invoice(
  p_org uuid,p_supplier_invoice_id uuid,p_expected_revision integer,p_reason text,p_idempotency_key text
) returns jsonb language sql security definer set search_path=public as $$
 select public._e10_org_transition_financial_document_x3d1c(
   p_org,'supplier_invoice',p_supplier_invoice_id,p_expected_revision,'void',p_reason,p_idempotency_key)
$$;
create function public.e10_org_review_supplier_credit(
  p_org uuid,p_supplier_credit_id uuid,p_expected_revision integer,p_reason text,p_idempotency_key text
) returns jsonb language sql security definer set search_path=public as $$
 select public._e10_org_transition_financial_document_x3d1c(
   p_org,'supplier_credit',p_supplier_credit_id,p_expected_revision,'review',p_reason,p_idempotency_key)
$$;
create function public.e10_org_approve_supplier_credit(
  p_org uuid,p_supplier_credit_id uuid,p_expected_revision integer,p_reason text,p_idempotency_key text
) returns jsonb language sql security definer set search_path=public as $$
 select public._e10_org_transition_financial_document_x3d1c(
   p_org,'supplier_credit',p_supplier_credit_id,p_expected_revision,'approve',p_reason,p_idempotency_key)
$$;
create function public.e10_org_void_supplier_credit(
  p_org uuid,p_supplier_credit_id uuid,p_expected_revision integer,p_reason text,p_idempotency_key text
) returns jsonb language sql security definer set search_path=public as $$
 select public._e10_org_transition_financial_document_x3d1c(
   p_org,'supplier_credit',p_supplier_credit_id,p_expected_revision,'void',p_reason,p_idempotency_key)
$$;

revoke all on function public.e10_org_review_supplier_invoice(uuid,uuid,integer,text,text) from public,anon;
revoke all on function public.e10_org_approve_supplier_invoice(uuid,uuid,integer,text,text) from public,anon;
revoke all on function public.e10_org_void_supplier_invoice(uuid,uuid,integer,text,text) from public,anon;
revoke all on function public.e10_org_review_supplier_credit(uuid,uuid,integer,text,text) from public,anon;
revoke all on function public.e10_org_approve_supplier_credit(uuid,uuid,integer,text,text) from public,anon;
revoke all on function public.e10_org_void_supplier_credit(uuid,uuid,integer,text,text) from public,anon;
grant execute on function public.e10_org_review_supplier_invoice(uuid,uuid,integer,text,text) to authenticated,service_role;
grant execute on function public.e10_org_approve_supplier_invoice(uuid,uuid,integer,text,text) to authenticated,service_role;
grant execute on function public.e10_org_void_supplier_invoice(uuid,uuid,integer,text,text) to authenticated,service_role;
grant execute on function public.e10_org_review_supplier_credit(uuid,uuid,integer,text,text) to authenticated,service_role;
grant execute on function public.e10_org_approve_supplier_credit(uuid,uuid,integer,text,text) to authenticated,service_role;
grant execute on function public.e10_org_void_supplier_credit(uuid,uuid,integer,text,text) to authenticated,service_role;

comment on function public.e10_org_approve_supplier_invoice(uuid,uuid,integer,text,text) is
  'Approves financial content only. Creates no receipt, inventory, payment, accounting entry or purchase order.';
