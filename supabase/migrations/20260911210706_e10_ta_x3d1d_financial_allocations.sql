-- TA-X3d.1d atomic invoice-to-PO and credit-to-invoice allocation workflow.

-- Matching is part of immutable financial-document state. Earlier snapshots
-- remain unchanged; snapshots created from this migration onward include every
-- current allocation projection touching the document.
create or replace function e10.financial_document_snapshot(
  p_org uuid,p_document_kind text,p_document_id uuid
) returns jsonb language plpgsql stable security definer set search_path=public as $$
declare result jsonb;
begin
  if p_document_kind='supplier_invoice' then
    select jsonb_build_object(
      'id',d.id,'organization_id',d.organization_id,'supplier_id',d.supplier_id,
      'supplier_document_number',d.supplier_document_number,'revision',d.revision,
      'status',d.status,'currency',d.currency,'document_date',d.document_date,
      'total_amount',d.total_amount,'source_connection',d.source_connection,
      'external_document_id',d.external_document_id,'payload_fingerprint',d.payload_fingerprint,
      'lines',coalesce((select jsonb_agg(jsonb_build_object(
        'id',l.id,'line_no',l.line_no,'configuration_version_id',l.configuration_version_id,
        'description',l.description,'invoiced_quantity',l.invoiced_quantity,
        'unit_cost',l.unit_cost,'line_amount',l.line_amount,'state',l.state
      ) order by l.line_no,l.id) from public.e10_supplier_invoice_lines l
        where l.organization_id=d.organization_id and l.supplier_invoice_id=d.id),'[]'::jsonb),
      'purchase_order_allocations',coalesce((select jsonb_agg(jsonb_build_object(
        'invoice_line_id',a.invoice_line_id,'purchase_order_line_id',a.purchase_order_line_id,
        'allocated_quantity',a.allocated_quantity) order by a.invoice_line_id,a.purchase_order_line_id)
        from public.e10_invoice_po_allocations a join public.e10_supplier_invoice_lines l
          on l.organization_id=a.organization_id and l.id=a.invoice_line_id
        where l.organization_id=d.organization_id and l.supplier_invoice_id=d.id),'[]'::jsonb),
      'receipt_allocations',coalesce((select jsonb_agg(jsonb_build_object(
        'receipt_line_id',a.receipt_line_id,'invoice_line_id',a.invoice_line_id,
        'allocated_quantity',a.allocated_quantity) order by a.receipt_line_id,a.invoice_line_id)
        from public.e10_receipt_invoice_allocations a join public.e10_supplier_invoice_lines l
          on l.organization_id=a.organization_id and l.id=a.invoice_line_id
        where l.organization_id=d.organization_id and l.supplier_invoice_id=d.id),'[]'::jsonb),
      'credit_allocations',coalesce((select jsonb_agg(jsonb_build_object(
        'credit_line_id',a.credit_line_id,'invoice_line_id',a.invoice_line_id,
        'allocated_amount',a.allocated_amount) order by a.credit_line_id,a.invoice_line_id)
        from public.e10_credit_invoice_allocations a join public.e10_supplier_invoice_lines l
          on l.organization_id=a.organization_id and l.id=a.invoice_line_id
        where l.organization_id=d.organization_id and l.supplier_invoice_id=d.id),'[]'::jsonb)
    ) into result from public.e10_supplier_invoices d
      where d.organization_id=p_org and d.id=p_document_id;
  elsif p_document_kind='supplier_credit' then
    select jsonb_build_object(
      'id',d.id,'organization_id',d.organization_id,'supplier_id',d.supplier_id,
      'supplier_document_number',d.supplier_document_number,'revision',d.revision,
      'status',d.status,'currency',d.currency,'document_date',d.document_date,
      'total_amount',d.total_amount,'source_connection',d.source_connection,
      'external_document_id',d.external_document_id,'payload_fingerprint',d.payload_fingerprint,
      'lines',coalesce((select jsonb_agg(jsonb_build_object(
        'id',l.id,'line_no',l.line_no,'configuration_version_id',l.configuration_version_id,
        'description',l.description,'line_amount',l.line_amount,'state',l.state
      ) order by l.line_no,l.id) from public.e10_supplier_credit_lines l
        where l.organization_id=d.organization_id and l.supplier_credit_id=d.id),'[]'::jsonb),
      'invoice_allocations',coalesce((select jsonb_agg(jsonb_build_object(
        'credit_line_id',a.credit_line_id,'invoice_line_id',a.invoice_line_id,
        'allocated_amount',a.allocated_amount) order by a.credit_line_id,a.invoice_line_id)
        from public.e10_credit_invoice_allocations a join public.e10_supplier_credit_lines l
          on l.organization_id=a.organization_id and l.id=a.credit_line_id
        where l.organization_id=d.organization_id and l.supplier_credit_id=d.id),'[]'::jsonb)
    ) into result from public.e10_supplier_credits d
      where d.organization_id=p_org and d.id=p_document_id;
  else
    raise exception using errcode='22023',message='financial_document_kind_invalid';
  end if;
  return result;
end $$;
revoke all on function e10.financial_document_snapshot(uuid,text,uuid) from public,anon,authenticated;
grant execute on function e10.financial_document_snapshot(uuid,text,uuid) to service_role;

-- Document advisory locks serialize every writer that can change matching.
-- Do not additionally lock invoice/credit allocation rows from both endpoints:
-- crossmatched graphs can otherwise acquire those rows in opposite order.
create or replace function e10.lock_financial_document(
  p_org uuid,p_document_kind text,p_document_id uuid
) returns void language plpgsql security definer set search_path=public as $$
declare r record;
begin
  perform pg_advisory_xact_lock(hashtextextended(
    p_org::text||'|financial-document|'||p_document_kind||'|'||p_document_id::text,0));
  if p_document_kind='supplier_invoice' then
    perform 1 from public.e10_supplier_invoices where organization_id=p_org and id=p_document_id for update;
    if not found then raise exception using errcode='42501',message='supplier_invoice_access_denied'; end if;
    for r in select id from public.e10_supplier_invoice_lines
      where organization_id=p_org and supplier_invoice_id=p_document_id order by id for update
    loop perform r.id; end loop;
    for r in select a.receipt_line_id,a.invoice_line_id from public.e10_receipt_invoice_allocations a
      join public.e10_supplier_invoice_lines l on l.organization_id=a.organization_id and l.id=a.invoice_line_id
      where l.organization_id=p_org and l.supplier_invoice_id=p_document_id
      order by a.receipt_line_id,a.invoice_line_id for update of a
    loop perform r.invoice_line_id; end loop;
  elsif p_document_kind='supplier_credit' then
    perform 1 from public.e10_supplier_credits where organization_id=p_org and id=p_document_id for update;
    if not found then raise exception using errcode='42501',message='supplier_credit_access_denied'; end if;
    for r in select id from public.e10_supplier_credit_lines
      where organization_id=p_org and supplier_credit_id=p_document_id order by id for update
    loop perform r.id; end loop;
  else
    raise exception using errcode='22023',message='financial_document_kind_invalid';
  end if;
end $$;

create or replace function e10.lock_purchase_order(p_org uuid,p_purchase_order_id uuid) returns void
language plpgsql security definer set search_path=public as $$
declare r record;
begin
  perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|purchase-order|'||p_purchase_order_id::text,0));
  perform 1 from public.e10_purchase_orders where organization_id=p_org and id=p_purchase_order_id for update;
  if not found then raise exception using errcode='42501',message='purchase_order_access_denied'; end if;
  for r in select id from public.e10_purchase_order_lines
    where organization_id=p_org and purchase_order_id=p_purchase_order_id order by id for update
  loop perform r.id; end loop;
  for r in select a.receipt_line_id,a.purchase_order_line_id from public.e10_receipt_po_allocations a
    join public.e10_purchase_order_lines l on l.organization_id=a.organization_id and l.id=a.purchase_order_line_id
    where l.organization_id=p_org and l.purchase_order_id=p_purchase_order_id
    order by a.receipt_line_id,a.purchase_order_line_id for update of a
  loop perform r.receipt_line_id; end loop;
  for r in select a.id from public.e10_expected_inventory_allocations a
    join public.e10_purchase_order_lines l on l.organization_id=a.organization_id and l.id=a.purchase_order_line_id
    where l.organization_id=p_org and l.purchase_order_id=p_purchase_order_id order by a.id for update of a
  loop perform r.id; end loop;
end $$;

-- Acquire every logical document lock before either existing helper locks rows.
-- This prevents invoice/credit pair operations from holding allocation rows
-- while waiting for the other document header.
create function e10.lock_financial_allocation_targets(
  p_org uuid,p_allocation_kind text,p_source_line_id uuid,p_target_line_id uuid
) returns void language plpgsql security definer set search_path=public as $$
declare invoice_id uuid; credit_id uuid; purchase_order_id uuid;
begin
  if p_allocation_kind='invoice_to_po' then
    select l.supplier_invoice_id into invoice_id from public.e10_supplier_invoice_lines l
      where l.organization_id=p_org and l.id=p_source_line_id;
    select l.purchase_order_id into purchase_order_id from public.e10_purchase_order_lines l
      where l.organization_id=p_org and l.id=p_target_line_id;
    if invoice_id is null or purchase_order_id is null then
      raise exception using errcode='42501',message='financial_allocation_target_denied';
    end if;
    perform pg_advisory_xact_lock(hashtextextended(
      p_org::text||'|financial-document|supplier_invoice|'||invoice_id::text,0));
    perform pg_advisory_xact_lock(hashtextextended(
      p_org::text||'|purchase-order|'||purchase_order_id::text,0));
    perform e10.lock_financial_document(p_org,'supplier_invoice',invoice_id);
    perform e10.lock_purchase_order(p_org,purchase_order_id);
  elsif p_allocation_kind='credit_to_invoice' then
    select l.supplier_credit_id into credit_id from public.e10_supplier_credit_lines l
      where l.organization_id=p_org and l.id=p_source_line_id;
    select l.supplier_invoice_id into invoice_id from public.e10_supplier_invoice_lines l
      where l.organization_id=p_org and l.id=p_target_line_id;
    if credit_id is null or invoice_id is null then
      raise exception using errcode='42501',message='financial_allocation_target_denied';
    end if;
    perform pg_advisory_xact_lock(hashtextextended(
      p_org::text||'|financial-document|supplier_invoice|'||invoice_id::text,0));
    perform pg_advisory_xact_lock(hashtextextended(
      p_org::text||'|financial-document|supplier_credit|'||credit_id::text,0));
    perform e10.lock_financial_document(p_org,'supplier_invoice',invoice_id);
    perform e10.lock_financial_document(p_org,'supplier_credit',credit_id);
  else
    raise exception using errcode='22023',message='financial_allocation_kind_invalid';
  end if;
end $$;
revoke all on function e10.lock_financial_allocation_targets(uuid,text,uuid,uuid)
  from public,anon,authenticated;
grant execute on function e10.lock_financial_allocation_targets(uuid,text,uuid,uuid) to service_role;

create function public._e10_org_financial_allocation_x3d1d(
  p_org uuid,p_allocation_kind text,p_operation text,p_source_line_id uuid,p_target_line_id uuid,
  p_expected_source_revision integer,p_expected_target_revision integer,p_value numeric,
  p_reason text,p_idempotency_key text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare
  actor uuid:=auth.uid(); fp text; existing_cmd record; event_id uuid:=gen_random_uuid();
  result jsonb; source_doc record; target_doc record; source_line record; target_line record;
  pair_value numeric; source_total numeric; target_total numeric;
  source_revision integer; target_revision integer; source_status text; target_status text;
  source_snapshot jsonb; target_snapshot jsonb;
begin
  if actor is null or p_allocation_kind not in ('invoice_to_po','credit_to_invoice')
    or p_operation not in ('allocate','release')
    or not exists(select 1 from public.e10_organizations where id=p_org and status='active')
    or not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.purchasing_prepare') then
    raise exception using errcode='42501',message='financial_allocation_denied';
  end if;
  if p_source_line_id is null or p_target_line_id is null
    or p_expected_source_revision is null or p_expected_source_revision<1
    or p_expected_target_revision is null or p_expected_target_revision<1
    or p_value is null or p_value<=0 or p_value::text in ('NaN','Infinity','-Infinity')
    or p_reason is null or btrim(p_reason)='' or length(p_reason)>2000
    or p_idempotency_key is null or btrim(p_idempotency_key)='' or length(p_idempotency_key)>200 then
    raise exception using errcode='22023',message='financial_allocation_payload_invalid';
  end if;
  fp:=md5(jsonb_build_object('v','financial-allocation-v1','org',p_org,'kind',p_allocation_kind,
    'operation',p_operation,'source_line_id',p_source_line_id,'target_line_id',p_target_line_id,
    'expected_source_revision',p_expected_source_revision,
    'expected_target_revision',p_expected_target_revision,'value',p_value,'reason',btrim(p_reason))::text);

  perform pg_advisory_xact_lock(hashtextextended(
    p_org::text||'|financial-allocation-command|'||p_idempotency_key,0));
  select c.request_fingerprint,c.result into existing_cmd
  from public.e10_financial_allocation_commands c
  where c.organization_id=p_org and c.idempotency_key=p_idempotency_key;
  if found then
    if existing_cmd.request_fingerprint<>fp then
      raise exception using errcode='22023',message='idempotency_key_mismatch';
    end if;
    if auth.uid() is distinct from actor
      or not exists(select 1 from public.e10_organizations where id=p_org and status='active')
      or not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.purchasing_prepare') then
      raise exception using errcode='42501',message='financial_allocation_denied';
    end if;
    return existing_cmd.result||jsonb_build_object('replay',true);
  end if;

  perform e10.lock_financial_allocation_targets(
    p_org,p_allocation_kind,p_source_line_id,p_target_line_id);
  if auth.uid() is distinct from actor
    or not exists(select 1 from public.e10_organizations where id=p_org and status='active')
    or not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.purchasing_prepare') then
    raise exception using errcode='42501',message='financial_allocation_denied';
  end if;

  if p_allocation_kind='invoice_to_po' then
    select l.*,d.supplier_id,d.currency,d.revision,d.status
      into source_line
    from public.e10_supplier_invoice_lines l
    join public.e10_supplier_invoices d
      on d.organization_id=l.organization_id and d.id=l.supplier_invoice_id
    where l.organization_id=p_org and l.id=p_source_line_id;
    select l.*,d.supplier_id,d.currency,d.revision,d.status,d.destination_location_id
      into target_line
    from public.e10_purchase_order_lines l
    join public.e10_purchase_orders d
      on d.organization_id=l.organization_id and d.id=l.purchase_order_id
    where l.organization_id=p_org and l.id=p_target_line_id;
    if source_line.id is null or target_line.id is null
      or source_line.state<>'active' or target_line.state<>'active'
      or source_line.status='void'
      or p_operation='allocate' and target_line.status not in ('submitted','approved')
      or source_line.supplier_id<>target_line.supplier_id
      or source_line.currency<>target_line.currency
      or source_line.configuration_version_id is distinct from target_line.configuration_version_id
      or source_line.invoiced_quantity is null then
      raise exception using errcode='55000',message='financial_allocation_incompatible';
    end if;
    if p_operation='allocate' and (
      not exists(select 1 from public.e10_suppliers s where s.organization_id=p_org
        and s.id=source_line.supplier_id and s.status='active')
      or source_line.configuration_version_id is not null and not exists(
        select 1 from public.e10_product_configuration_versions v
        where v.organization_id=p_org and v.id=source_line.configuration_version_id and v.state='active')
      or not exists(select 1 from public.e10_locations l where l.organization_id=p_org
        and l.id=target_line.destination_location_id and l.status='active')
      or not e10.can_receive_at(p_org,target_line.destination_location_id)) then
      raise exception using errcode='42501',message='financial_allocation_current_eligibility_denied';
    end if;
    if source_line.revision<>p_expected_source_revision
      or target_line.revision<>p_expected_target_revision then
      raise exception using errcode='40001',message='financial_allocation_revision_conflict';
    end if;
    select allocated_quantity into pair_value from public.e10_invoice_po_allocations
      where organization_id=p_org and invoice_line_id=p_source_line_id
        and purchase_order_line_id=p_target_line_id;
    pair_value:=coalesce(pair_value,0);
    if p_operation='allocate' then
      source_total:=coalesce((select sum(allocated_quantity) from public.e10_invoice_po_allocations
        where organization_id=p_org and invoice_line_id=p_source_line_id),0);
      target_total:=coalesce((select sum(allocated_quantity) from public.e10_invoice_po_allocations
        where organization_id=p_org and purchase_order_line_id=p_target_line_id),0);
      if source_total+p_value>source_line.invoiced_quantity
        or target_total+p_value>target_line.ordered_quantity then
        raise exception using errcode='23514',message='financial_allocation_conservation_violation';
      end if;
      insert into public.e10_invoice_po_allocations
        (organization_id,invoice_line_id,purchase_order_line_id,allocated_quantity)
      values(p_org,p_source_line_id,p_target_line_id,p_value)
      on conflict(organization_id,invoice_line_id,purchase_order_line_id) do update
        set allocated_quantity=e10_invoice_po_allocations.allocated_quantity+excluded.allocated_quantity;
    else
      if pair_value<p_value then
        raise exception using errcode='23514',message='financial_allocation_release_exceeds_pair';
      end if;
      if pair_value=p_value then
        delete from public.e10_invoice_po_allocations where organization_id=p_org
          and invoice_line_id=p_source_line_id and purchase_order_line_id=p_target_line_id;
      else
        update public.e10_invoice_po_allocations set allocated_quantity=allocated_quantity-p_value
          where organization_id=p_org and invoice_line_id=p_source_line_id
            and purchase_order_line_id=p_target_line_id;
      end if;
    end if;
    source_revision:=source_line.revision+1;
    source_status:=case when source_line.status='draft' then 'draft' else 'reviewed' end;
    update public.e10_supplier_invoices set revision=source_revision,status=source_status,
      reviewed_by=case when source_status='reviewed' then actor else reviewed_by end,
      reviewed_at=case when source_status='reviewed' then now() else reviewed_at end,
      approved_revision=null,approved_by=null,approved_at=null,updated_at=now()
      where organization_id=p_org and id=source_line.supplier_invoice_id;
    source_snapshot:=e10.financial_document_snapshot(
      p_org,'supplier_invoice',source_line.supplier_invoice_id);
    insert into public.e10_supplier_invoice_revisions
      (organization_id,supplier_invoice_id,revision,status,snapshot,payload_fingerprint,change_reason,created_by)
    values(p_org,source_line.supplier_invoice_id,source_revision,source_status,
      source_snapshot,fp,btrim(p_reason),actor);
    result:=jsonb_build_object('ok',true,'replay',false,'allocation_event_id',event_id,
      'invoice_line_id',p_source_line_id,'purchase_order_line_id',p_target_line_id,
      'allocated_quantity',case when p_operation='allocate' then pair_value+p_value else pair_value-p_value end,
      'supplier_invoice_id',source_line.supplier_invoice_id,
      'supplier_invoice_revision',source_revision,'supplier_invoice_status',source_status,
      'purchase_order_id',target_line.purchase_order_id,'purchase_order_revision',target_line.revision);
    insert into public.e10_financial_allocation_commands
      (organization_id,idempotency_key,allocation_kind,operation,allocation_event_id,
       request_fingerprint,result,created_by)
    values(p_org,p_idempotency_key,p_allocation_kind,p_operation,event_id,fp,result,actor);
    insert into public.e10_invoice_po_allocation_events
      (id,organization_id,invoice_line_id,purchase_order_line_id,operation,quantity_delta,
       reason,command_idempotency_key,created_by)
    values(event_id,p_org,p_source_line_id,p_target_line_id,p_operation,
      case when p_operation='allocate' then p_value else -p_value end,
      btrim(p_reason),p_idempotency_key,actor);
  else
    select l.*,d.supplier_id,d.currency,d.revision,d.status
      into source_line
    from public.e10_supplier_credit_lines l
    join public.e10_supplier_credits d
      on d.organization_id=l.organization_id and d.id=l.supplier_credit_id
    where l.organization_id=p_org and l.id=p_source_line_id;
    select l.*,d.supplier_id,d.currency,d.revision,d.status
      into target_line
    from public.e10_supplier_invoice_lines l
    join public.e10_supplier_invoices d
      on d.organization_id=l.organization_id and d.id=l.supplier_invoice_id
    where l.organization_id=p_org and l.id=p_target_line_id;
    if source_line.id is null or target_line.id is null
      or source_line.state<>'active' or target_line.state<>'active'
      or source_line.status='void' or target_line.status='void'
      or source_line.supplier_id<>target_line.supplier_id
      or source_line.currency<>target_line.currency
      or source_line.configuration_version_id is distinct from target_line.configuration_version_id then
      raise exception using errcode='55000',message='financial_allocation_incompatible';
    end if;
    if p_operation='allocate' and (
      not exists(select 1 from public.e10_suppliers s where s.organization_id=p_org
        and s.id=source_line.supplier_id and s.status='active')
      or source_line.configuration_version_id is not null and not exists(
        select 1 from public.e10_product_configuration_versions v
        where v.organization_id=p_org and v.id=source_line.configuration_version_id and v.state='active')) then
      raise exception using errcode='42501',message='financial_allocation_current_eligibility_denied';
    end if;
    if source_line.revision<>p_expected_source_revision
      or target_line.revision<>p_expected_target_revision then
      raise exception using errcode='40001',message='financial_allocation_revision_conflict';
    end if;
    select allocated_amount into pair_value from public.e10_credit_invoice_allocations
      where organization_id=p_org and credit_line_id=p_source_line_id
        and invoice_line_id=p_target_line_id;
    pair_value:=coalesce(pair_value,0);
    if p_operation='allocate' then
      source_total:=coalesce((select sum(allocated_amount) from public.e10_credit_invoice_allocations
        where organization_id=p_org and credit_line_id=p_source_line_id),0);
      target_total:=coalesce((select sum(allocated_amount) from public.e10_credit_invoice_allocations
        where organization_id=p_org and invoice_line_id=p_target_line_id),0);
      if source_total+p_value>source_line.line_amount or target_total+p_value>target_line.line_amount then
        raise exception using errcode='23514',message='financial_allocation_conservation_violation';
      end if;
      insert into public.e10_credit_invoice_allocations
        (organization_id,credit_line_id,invoice_line_id,allocated_amount)
      values(p_org,p_source_line_id,p_target_line_id,p_value)
      on conflict(organization_id,credit_line_id,invoice_line_id) do update
        set allocated_amount=e10_credit_invoice_allocations.allocated_amount+excluded.allocated_amount;
    else
      if pair_value<p_value then
        raise exception using errcode='23514',message='financial_allocation_release_exceeds_pair';
      end if;
      if pair_value=p_value then
        delete from public.e10_credit_invoice_allocations where organization_id=p_org
          and credit_line_id=p_source_line_id and invoice_line_id=p_target_line_id;
      else
        update public.e10_credit_invoice_allocations set allocated_amount=allocated_amount-p_value
          where organization_id=p_org and credit_line_id=p_source_line_id
            and invoice_line_id=p_target_line_id;
      end if;
    end if;
    source_revision:=source_line.revision+1;
    target_revision:=target_line.revision+1;
    source_status:=case when source_line.status='draft' then 'draft' else 'reviewed' end;
    target_status:=case when target_line.status='draft' then 'draft' else 'reviewed' end;
    update public.e10_supplier_credits set revision=source_revision,status=source_status,
      reviewed_by=case when source_status='reviewed' then actor else reviewed_by end,
      reviewed_at=case when source_status='reviewed' then now() else reviewed_at end,
      approved_revision=null,approved_by=null,approved_at=null,updated_at=now()
      where organization_id=p_org and id=source_line.supplier_credit_id;
    update public.e10_supplier_invoices set revision=target_revision,status=target_status,
      reviewed_by=case when target_status='reviewed' then actor else reviewed_by end,
      reviewed_at=case when target_status='reviewed' then now() else reviewed_at end,
      approved_revision=null,approved_by=null,approved_at=null,updated_at=now()
      where organization_id=p_org and id=target_line.supplier_invoice_id;
    source_snapshot:=e10.financial_document_snapshot(
      p_org,'supplier_credit',source_line.supplier_credit_id);
    target_snapshot:=e10.financial_document_snapshot(
      p_org,'supplier_invoice',target_line.supplier_invoice_id);
    insert into public.e10_supplier_credit_revisions
      (organization_id,supplier_credit_id,revision,status,snapshot,payload_fingerprint,change_reason,created_by)
    values(p_org,source_line.supplier_credit_id,source_revision,source_status,
      source_snapshot,fp,btrim(p_reason),actor);
    insert into public.e10_supplier_invoice_revisions
      (organization_id,supplier_invoice_id,revision,status,snapshot,payload_fingerprint,change_reason,created_by)
    values(p_org,target_line.supplier_invoice_id,target_revision,target_status,
      target_snapshot,fp,btrim(p_reason),actor);
    result:=jsonb_build_object('ok',true,'replay',false,'allocation_event_id',event_id,
      'credit_line_id',p_source_line_id,'invoice_line_id',p_target_line_id,
      'allocated_amount',case when p_operation='allocate' then pair_value+p_value else pair_value-p_value end,
      'supplier_credit_id',source_line.supplier_credit_id,
      'supplier_credit_revision',source_revision,'supplier_credit_status',source_status,
      'supplier_invoice_id',target_line.supplier_invoice_id,
      'supplier_invoice_revision',target_revision,'supplier_invoice_status',target_status);
    insert into public.e10_financial_allocation_commands
      (organization_id,idempotency_key,allocation_kind,operation,allocation_event_id,
       request_fingerprint,result,created_by)
    values(p_org,p_idempotency_key,p_allocation_kind,p_operation,event_id,fp,result,actor);
    insert into public.e10_credit_invoice_allocation_events
      (id,organization_id,credit_line_id,invoice_line_id,operation,amount_delta,
       reason,command_idempotency_key,created_by)
    values(event_id,p_org,p_source_line_id,p_target_line_id,p_operation,
      case when p_operation='allocate' then p_value else -p_value end,
      btrim(p_reason),p_idempotency_key,actor);
  end if;
  return result;
end $$;
revoke all on function public._e10_org_financial_allocation_x3d1d(
  uuid,text,text,uuid,uuid,integer,integer,numeric,text,text) from public,anon,authenticated;
grant execute on function public._e10_org_financial_allocation_x3d1d(
  uuid,text,text,uuid,uuid,integer,integer,numeric,text,text) to service_role;

create function public.e10_org_allocate_invoice_to_po(
  p_org uuid,p_invoice_line_id uuid,p_purchase_order_line_id uuid,
  p_expected_invoice_revision integer,p_expected_purchase_order_revision integer,
  p_quantity numeric,p_reason text,p_idempotency_key text
) returns jsonb language sql security definer set search_path=public as $$
  select public._e10_org_financial_allocation_x3d1d(p_org,'invoice_to_po','allocate',
    p_invoice_line_id,p_purchase_order_line_id,p_expected_invoice_revision,
    p_expected_purchase_order_revision,p_quantity,p_reason,p_idempotency_key)
$$;
create function public.e10_org_release_invoice_from_po(
  p_org uuid,p_invoice_line_id uuid,p_purchase_order_line_id uuid,
  p_expected_invoice_revision integer,p_expected_purchase_order_revision integer,
  p_quantity numeric,p_reason text,p_idempotency_key text
) returns jsonb language sql security definer set search_path=public as $$
  select public._e10_org_financial_allocation_x3d1d(p_org,'invoice_to_po','release',
    p_invoice_line_id,p_purchase_order_line_id,p_expected_invoice_revision,
    p_expected_purchase_order_revision,p_quantity,p_reason,p_idempotency_key)
$$;
create function public.e10_org_allocate_credit_to_invoice(
  p_org uuid,p_credit_line_id uuid,p_invoice_line_id uuid,
  p_expected_credit_revision integer,p_expected_invoice_revision integer,
  p_amount numeric,p_reason text,p_idempotency_key text
) returns jsonb language sql security definer set search_path=public as $$
  select public._e10_org_financial_allocation_x3d1d(p_org,'credit_to_invoice','allocate',
    p_credit_line_id,p_invoice_line_id,p_expected_credit_revision,
    p_expected_invoice_revision,p_amount,p_reason,p_idempotency_key)
$$;
create function public.e10_org_release_credit_from_invoice(
  p_org uuid,p_credit_line_id uuid,p_invoice_line_id uuid,
  p_expected_credit_revision integer,p_expected_invoice_revision integer,
  p_amount numeric,p_reason text,p_idempotency_key text
) returns jsonb language sql security definer set search_path=public as $$
  select public._e10_org_financial_allocation_x3d1d(p_org,'credit_to_invoice','release',
    p_credit_line_id,p_invoice_line_id,p_expected_credit_revision,
    p_expected_invoice_revision,p_amount,p_reason,p_idempotency_key)
$$;

revoke all on function public.e10_org_allocate_invoice_to_po(uuid,uuid,uuid,integer,integer,numeric,text,text)
  from public,anon;
revoke all on function public.e10_org_release_invoice_from_po(uuid,uuid,uuid,integer,integer,numeric,text,text)
  from public,anon;
revoke all on function public.e10_org_allocate_credit_to_invoice(uuid,uuid,uuid,integer,integer,numeric,text,text)
  from public,anon;
revoke all on function public.e10_org_release_credit_from_invoice(uuid,uuid,uuid,integer,integer,numeric,text,text)
  from public,anon;
grant execute on function public.e10_org_allocate_invoice_to_po(uuid,uuid,uuid,integer,integer,numeric,text,text)
  to authenticated,service_role;
grant execute on function public.e10_org_release_invoice_from_po(uuid,uuid,uuid,integer,integer,numeric,text,text)
  to authenticated,service_role;
grant execute on function public.e10_org_allocate_credit_to_invoice(uuid,uuid,uuid,integer,integer,numeric,text,text)
  to authenticated,service_role;
grant execute on function public.e10_org_release_credit_from_invoice(uuid,uuid,uuid,integer,integer,numeric,text,text)
  to authenticated,service_role;
