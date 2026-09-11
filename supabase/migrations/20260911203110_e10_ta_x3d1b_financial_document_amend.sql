-- TA-X3d.1b full-document invoice/credit amendment with optimistic concurrency.
-- Compatible amendments may retain allocations; reductions or identity changes
-- that would strand allocated quantity/value fail closed.

create function e10.validate_financial_document_lines(
  p_org uuid,p_document_kind text,p_lines jsonb
) returns void language plpgsql stable security definer set search_path=public as $$
declare line record; line_count integer; line_id uuid;
begin
  if p_document_kind not in ('supplier_invoice','supplier_credit')
    or p_lines is null or jsonb_typeof(p_lines)<>'array' or octet_length(p_lines::text)>262144 then
    raise exception using errcode='22023',message='financial_document_lines_invalid';
  end if;
  line_count:=jsonb_array_length(p_lines);
  if line_count<1 or line_count>200 then raise exception using errcode='22023',message='financial_document_lines_count_invalid'; end if;
  for line in select x from jsonb_array_elements(p_lines) x loop
    if jsonb_typeof(line.x) is distinct from 'object'
      or jsonb_typeof(line.x->'id') is distinct from 'string'
      or jsonb_typeof(line.x->'line_no') is distinct from 'number'
      or jsonb_typeof(line.x->'line_amount') is distinct from 'number'
      or line.x ? 'configuration_version_id' and jsonb_typeof(line.x->'configuration_version_id') not in ('string','null')
      or line.x ? 'description' and jsonb_typeof(line.x->'description') not in ('string','null')
      or length(coalesce(line.x->>'description',''))>2000
      or p_document_kind='supplier_invoice' and line.x ? 'invoiced_quantity'
        and jsonb_typeof(line.x->'invoiced_quantity') not in ('number','null')
      or p_document_kind='supplier_invoice' and line.x ? 'unit_cost'
        and jsonb_typeof(line.x->'unit_cost') not in ('number','null')
      or p_document_kind='supplier_credit' and (line.x ? 'invoiced_quantity' or line.x ? 'unit_cost') then
      raise exception using errcode='22023',message='financial_document_line_encoding_invalid';
    end if;
    line_id:=(line.x->>'id')::uuid;
    if line_id is null or (line.x->>'line_no')::integer is null or (line.x->>'line_no')::integer<=0
      or (line.x->>'line_amount')::numeric<0
      or (line.x->>'line_amount')::numeric::text in ('NaN','Infinity','-Infinity')
      or p_document_kind='supplier_invoice' and jsonb_typeof(line.x->'invoiced_quantity')='number'
        and ((line.x->>'invoiced_quantity')::numeric<=0 or (line.x->>'invoiced_quantity')::numeric::text in ('NaN','Infinity','-Infinity'))
      or p_document_kind='supplier_invoice' and jsonb_typeof(line.x->'unit_cost')='number'
        and ((line.x->>'unit_cost')::numeric<0 or (line.x->>'unit_cost')::numeric::text in ('NaN','Infinity','-Infinity')) then
      raise exception using errcode='22023',message='financial_document_line_value_invalid';
    end if;
    if jsonb_typeof(line.x->'configuration_version_id')='string' and not exists(
      select 1 from public.e10_product_configuration_versions
      where organization_id=p_org and id=(line.x->>'configuration_version_id')::uuid and state='active') then
      raise exception using errcode='42501',message='financial_document_configuration_denied';
    end if;
  end loop;
  if (select count(*) from (select (x->>'id')::uuid from jsonb_array_elements(p_lines) x group by 1) q)<>line_count
    or (select count(*) from (select (x->>'line_no')::integer from jsonb_array_elements(p_lines) x group by 1) q)<>line_count then
    raise exception using errcode='22023',message='financial_document_line_identity_invalid';
  end if;
exception when invalid_text_representation or numeric_value_out_of_range then
  raise exception using errcode='22023',message='financial_document_line_encoding_invalid';
end $$;
revoke all on function e10.validate_financial_document_lines(uuid,text,jsonb) from public,anon,authenticated;
grant execute on function e10.validate_financial_document_lines(uuid,text,jsonb) to service_role;

create function e10.lock_financial_document(
  p_org uuid,p_document_kind text,p_document_id uuid
) returns void language plpgsql security definer set search_path=public as $$
declare r record;
begin
  perform pg_advisory_xact_lock(hashtextextended(
    p_org::text||'|financial-document|'||p_document_kind||'|'||p_document_id::text,0));
  if p_document_kind='supplier_invoice' then
    perform 1 from public.e10_supplier_invoices
      where organization_id=p_org and id=p_document_id for update;
    if not found then raise exception using errcode='42501',message='supplier_invoice_access_denied'; end if;
    for r in select id from public.e10_supplier_invoice_lines
      where organization_id=p_org and supplier_invoice_id=p_document_id order by id for update
    loop perform r.id; end loop;
    for r in select a.invoice_line_id,a.purchase_order_line_id from public.e10_invoice_po_allocations a
      join public.e10_supplier_invoice_lines l on l.organization_id=a.organization_id and l.id=a.invoice_line_id
      where l.organization_id=p_org and l.supplier_invoice_id=p_document_id
      order by a.invoice_line_id,a.purchase_order_line_id for update of a
    loop perform r.invoice_line_id; end loop;
    for r in select a.credit_line_id,a.invoice_line_id from public.e10_credit_invoice_allocations a
      join public.e10_supplier_invoice_lines l on l.organization_id=a.organization_id and l.id=a.invoice_line_id
      where l.organization_id=p_org and l.supplier_invoice_id=p_document_id
      order by a.credit_line_id,a.invoice_line_id for update of a
    loop perform r.invoice_line_id; end loop;
    for r in select a.receipt_line_id,a.invoice_line_id from public.e10_receipt_invoice_allocations a
      join public.e10_supplier_invoice_lines l on l.organization_id=a.organization_id and l.id=a.invoice_line_id
      where l.organization_id=p_org and l.supplier_invoice_id=p_document_id
      order by a.receipt_line_id,a.invoice_line_id for update of a
    loop perform r.invoice_line_id; end loop;
  elsif p_document_kind='supplier_credit' then
    perform 1 from public.e10_supplier_credits
      where organization_id=p_org and id=p_document_id for update;
    if not found then raise exception using errcode='42501',message='supplier_credit_access_denied'; end if;
    for r in select id from public.e10_supplier_credit_lines
      where organization_id=p_org and supplier_credit_id=p_document_id order by id for update
    loop perform r.id; end loop;
    for r in select a.credit_line_id,a.invoice_line_id from public.e10_credit_invoice_allocations a
      join public.e10_supplier_credit_lines l on l.organization_id=a.organization_id and l.id=a.credit_line_id
      where l.organization_id=p_org and l.supplier_credit_id=p_document_id
      order by a.credit_line_id,a.invoice_line_id for update of a
    loop perform r.credit_line_id; end loop;
  else
    raise exception using errcode='22023',message='financial_document_kind_invalid';
  end if;
end $$;
revoke all on function e10.lock_financial_document(uuid,text,uuid) from public,anon,authenticated;
grant execute on function e10.lock_financial_document(uuid,text,uuid) to service_role;

create function public._e10_org_amend_financial_document_x3d1b(
  p_org uuid,p_document_kind text,p_document_id uuid,p_expected_revision integer,
  p_currency text,p_document_date date,p_total_amount numeric,p_lines jsonb,
  p_reason text,p_idempotency_key text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare
  actor uuid:=auth.uid(); fp text; existing_cmd record; document record; line record;
  event_id uuid:=gen_random_uuid(); result jsonb; snapshot jsonb; new_revision integer;
  new_status text; line_exists boolean;
begin
  if actor is null or p_document_kind not in ('supplier_invoice','supplier_credit')
    or not exists(select 1 from public.e10_organizations where id=p_org and status='active')
    or not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.purchasing_prepare') then
    raise exception using errcode='42501',message='financial_document_prepare_denied';
  end if;
  if p_expected_revision is null or p_expected_revision<1
    or p_idempotency_key is null or btrim(p_idempotency_key)='' or length(p_idempotency_key)>200
    or p_reason is null or btrim(p_reason)='' or length(p_reason)>2000
    or p_currency is null or p_currency!~'^[A-Z]{3}$'
    or p_total_amount is not null and (p_total_amount<0 or p_total_amount::text in ('NaN','Infinity','-Infinity'))
    or p_document_kind='supplier_credit' and p_total_amount is null then
    raise exception using errcode='22023',message='financial_document_amend_payload_invalid';
  end if;
  perform e10.validate_financial_document_lines(p_org,p_document_kind,p_lines);
  fp:=md5(jsonb_build_object('v','financial-document-amend-v1','org',p_org,'kind',p_document_kind,
    'document_id',p_document_id,'expected_revision',p_expected_revision,'currency',p_currency,
    'document_date',p_document_date,'total_amount',p_total_amount,'lines',p_lines,'reason',btrim(p_reason))::text);
  perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|financial-document-command|'||p_idempotency_key,0));
  select c.request_fingerprint,c.result into existing_cmd from public.e10_financial_document_commands c
    where c.organization_id=p_org and c.idempotency_key=p_idempotency_key;
  if found then
    if existing_cmd.request_fingerprint<>fp then raise exception using errcode='22023',message='idempotency_key_mismatch'; end if;
    if auth.uid() is distinct from actor
      or not exists(select 1 from public.e10_organizations where id=p_org and status='active')
      or not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.purchasing_prepare') then
      raise exception using errcode='42501',message='financial_document_prepare_denied';
    end if;
    return existing_cmd.result||jsonb_build_object('replay',true);
  end if;

  perform e10.lock_financial_document(p_org,p_document_kind,p_document_id);
  if auth.uid() is distinct from actor
    or not exists(select 1 from public.e10_organizations where id=p_org and status='active')
    or not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.purchasing_prepare') then
    raise exception using errcode='42501',message='financial_document_prepare_denied';
  end if;
  perform e10.validate_financial_document_lines(p_org,p_document_kind,p_lines);
  if p_document_kind='supplier_invoice' then
    select d.* into document from public.e10_supplier_invoices d
      where d.organization_id=p_org and d.id=p_document_id;
    if exists(select 1 from public.e10_invoice_po_allocations a
        join public.e10_supplier_invoice_lines l on l.organization_id=a.organization_id and l.id=a.invoice_line_id
        join public.e10_purchase_order_lines pl on pl.organization_id=a.organization_id and pl.id=a.purchase_order_line_id
        join public.e10_purchase_orders po on po.organization_id=pl.organization_id and po.id=pl.purchase_order_id
        where l.organization_id=p_org and l.supplier_invoice_id=p_document_id
          and (po.currency<>p_currency or po.supplier_id<>document.supplier_id))
      or exists(select 1 from public.e10_credit_invoice_allocations a
        join public.e10_supplier_invoice_lines l on l.organization_id=a.organization_id and l.id=a.invoice_line_id
        join public.e10_supplier_credit_lines cl on cl.organization_id=a.organization_id and cl.id=a.credit_line_id
        join public.e10_supplier_credits c on c.organization_id=cl.organization_id and c.id=cl.supplier_credit_id
        where l.organization_id=p_org and l.supplier_invoice_id=p_document_id
          and (c.currency<>p_currency or c.supplier_id<>document.supplier_id))
      or exists(select 1 from public.e10_receipt_invoice_allocations a
        join public.e10_supplier_invoice_lines l on l.organization_id=a.organization_id and l.id=a.invoice_line_id
        join public.e10_stock_receipt_lines rl on rl.organization_id=a.organization_id and rl.id=a.receipt_line_id
        join public.e10_stock_receipts r on r.organization_id=rl.organization_id and r.id=rl.stock_receipt_id
        where l.organization_id=p_org and l.supplier_invoice_id=p_document_id
          and (r.supplier_id<>document.supplier_id or rl.currency is not null and rl.currency<>p_currency)) then
      raise exception using errcode='55000',message='financial_document_allocation_header_conflict';
    end if;
  else
    select d.* into document from public.e10_supplier_credits d
      where d.organization_id=p_org and d.id=p_document_id;
    if exists(select 1 from public.e10_credit_invoice_allocations a
      join public.e10_supplier_credit_lines l on l.organization_id=a.organization_id and l.id=a.credit_line_id
      join public.e10_supplier_invoice_lines il on il.organization_id=a.organization_id and il.id=a.invoice_line_id
      join public.e10_supplier_invoices i on i.organization_id=il.organization_id and i.id=il.supplier_invoice_id
      where l.organization_id=p_org and l.supplier_credit_id=p_document_id
        and (i.currency<>p_currency or i.supplier_id<>document.supplier_id)) then
      raise exception using errcode='55000',message='financial_document_allocation_header_conflict';
    end if;
  end if;
  if document.status='void' then raise exception using errcode='55000',message='financial_document_not_amendable'; end if;
  if document.revision<>p_expected_revision then raise exception using errcode='40001',message='financial_document_revision_conflict'; end if;
  new_revision:=document.revision+1;
  new_status:=case when document.status='draft' then 'draft' else 'reviewed' end;

  if p_document_kind='supplier_invoice' then
    for line in select x from jsonb_array_elements(p_lines) x order by (x->>'line_no')::integer loop
      select exists(select 1 from public.e10_supplier_invoice_lines where id=(line.x->>'id')::uuid) into line_exists;
      if line_exists then
        if not exists(select 1 from public.e10_supplier_invoice_lines l
          where l.organization_id=p_org and l.supplier_invoice_id=p_document_id
            and l.id=(line.x->>'id')::uuid and l.line_no=(line.x->>'line_no')::integer and l.state='active') then
          raise exception using errcode='23514',message='financial_document_line_identity_immutable';
        end if;
        if coalesce((select sum(a.allocated_quantity) from public.e10_invoice_po_allocations a
              where a.organization_id=p_org and a.invoice_line_id=(line.x->>'id')::uuid),0)>0
          and (jsonb_typeof(line.x->'invoiced_quantity')<>'number'
            or (line.x->>'invoiced_quantity')::numeric<(select sum(a.allocated_quantity)
              from public.e10_invoice_po_allocations a
              where a.organization_id=p_org and a.invoice_line_id=(line.x->>'id')::uuid))
          or exists(select 1 from public.e10_invoice_po_allocations a
            join public.e10_purchase_order_lines pl on pl.organization_id=a.organization_id and pl.id=a.purchase_order_line_id
            where a.organization_id=p_org and a.invoice_line_id=(line.x->>'id')::uuid
              and pl.configuration_version_id is distinct from case
                when jsonb_typeof(line.x->'configuration_version_id')='string'
                then (line.x->>'configuration_version_id')::uuid end)
          or exists(select 1 from public.e10_credit_invoice_allocations a
            join public.e10_supplier_credit_lines cl on cl.organization_id=a.organization_id and cl.id=a.credit_line_id
            where a.organization_id=p_org and a.invoice_line_id=(line.x->>'id')::uuid
              and cl.configuration_version_id is distinct from case
                when jsonb_typeof(line.x->'configuration_version_id')='string'
                then (line.x->>'configuration_version_id')::uuid end)
          or coalesce((select sum(a.allocated_quantity) from public.e10_receipt_invoice_allocations a
              where a.organization_id=p_org and a.invoice_line_id=(line.x->>'id')::uuid),0)>0
            and (jsonb_typeof(line.x->'invoiced_quantity')<>'number'
              or (line.x->>'invoiced_quantity')::numeric<(select sum(a.allocated_quantity)
                from public.e10_receipt_invoice_allocations a
                where a.organization_id=p_org and a.invoice_line_id=(line.x->>'id')::uuid))
          or exists(select 1 from public.e10_receipt_invoice_allocations a
            join public.e10_stock_receipt_lines rl on rl.organization_id=a.organization_id and rl.id=a.receipt_line_id
            where a.organization_id=p_org and a.invoice_line_id=(line.x->>'id')::uuid
              and rl.configuration_version_id is distinct from case
                when jsonb_typeof(line.x->'configuration_version_id')='string'
                then (line.x->>'configuration_version_id')::uuid end)
          or coalesce((select sum(a.allocated_amount) from public.e10_credit_invoice_allocations a
              where a.organization_id=p_org and a.invoice_line_id=(line.x->>'id')::uuid),0)
            >(line.x->>'line_amount')::numeric then
          raise exception using errcode='55000',message='financial_document_line_allocation_conflict';
        end if;
        update public.e10_supplier_invoice_lines set
          configuration_version_id=case when jsonb_typeof(line.x->'configuration_version_id')='string'
            then (line.x->>'configuration_version_id')::uuid end,
          description=nullif(btrim(line.x->>'description'),''),
          invoiced_quantity=case when jsonb_typeof(line.x->'invoiced_quantity')='number'
            then (line.x->>'invoiced_quantity')::numeric end,
          unit_cost=case when jsonb_typeof(line.x->'unit_cost')='number' then (line.x->>'unit_cost')::numeric end,
          line_amount=(line.x->>'line_amount')::numeric
        where organization_id=p_org and supplier_invoice_id=p_document_id and id=(line.x->>'id')::uuid;
      else
        insert into public.e10_supplier_invoice_lines(id,organization_id,supplier_invoice_id,configuration_version_id,
          line_no,description,invoiced_quantity,unit_cost,line_amount,state)
        values((line.x->>'id')::uuid,p_org,p_document_id,
          case when jsonb_typeof(line.x->'configuration_version_id')='string' then (line.x->>'configuration_version_id')::uuid end,
          (line.x->>'line_no')::integer,nullif(btrim(line.x->>'description'),''),
          case when jsonb_typeof(line.x->'invoiced_quantity')='number' then (line.x->>'invoiced_quantity')::numeric end,
          case when jsonb_typeof(line.x->'unit_cost')='number' then (line.x->>'unit_cost')::numeric end,
          (line.x->>'line_amount')::numeric,'active');
      end if;
    end loop;
    if exists(select 1 from public.e10_supplier_invoice_lines l
      where l.organization_id=p_org and l.supplier_invoice_id=p_document_id and l.state='active'
        and not exists(select 1 from jsonb_array_elements(p_lines) x where (x->>'id')::uuid=l.id)
        and (exists(select 1 from public.e10_invoice_po_allocations a
              where a.organization_id=l.organization_id and a.invoice_line_id=l.id)
          or exists(select 1 from public.e10_credit_invoice_allocations a
              where a.organization_id=l.organization_id and a.invoice_line_id=l.id)
          or exists(select 1 from public.e10_receipt_invoice_allocations a
              where a.organization_id=l.organization_id and a.invoice_line_id=l.id))) then
      raise exception using errcode='55000',message='financial_document_line_allocation_conflict';
    end if;
    update public.e10_supplier_invoice_lines l set state='cancelled'
      where l.organization_id=p_org and l.supplier_invoice_id=p_document_id and l.state='active'
        and not exists(select 1 from jsonb_array_elements(p_lines) x where (x->>'id')::uuid=l.id);
    update public.e10_supplier_invoices set currency=p_currency,document_date=p_document_date,
      total_amount=p_total_amount,revision=new_revision,status=new_status,
      reviewed_by=case when new_status='reviewed' then actor end,
      reviewed_at=case when new_status='reviewed' then now() end,
      approved_revision=null,approved_by=null,approved_at=null,updated_at=now()
      where organization_id=p_org and id=p_document_id;
  else
    for line in select x from jsonb_array_elements(p_lines) x order by (x->>'line_no')::integer loop
      select exists(select 1 from public.e10_supplier_credit_lines where id=(line.x->>'id')::uuid) into line_exists;
      if line_exists then
        if not exists(select 1 from public.e10_supplier_credit_lines l
          where l.organization_id=p_org and l.supplier_credit_id=p_document_id
            and l.id=(line.x->>'id')::uuid and l.line_no=(line.x->>'line_no')::integer and l.state='active') then
          raise exception using errcode='23514',message='financial_document_line_identity_immutable';
        end if;
        if coalesce((select sum(a.allocated_amount) from public.e10_credit_invoice_allocations a
              where a.organization_id=p_org and a.credit_line_id=(line.x->>'id')::uuid),0)
            >(line.x->>'line_amount')::numeric
          or exists(select 1 from public.e10_credit_invoice_allocations a
            join public.e10_supplier_invoice_lines il on il.organization_id=a.organization_id and il.id=a.invoice_line_id
            where a.organization_id=p_org and a.credit_line_id=(line.x->>'id')::uuid
              and il.configuration_version_id is distinct from case
                when jsonb_typeof(line.x->'configuration_version_id')='string'
                then (line.x->>'configuration_version_id')::uuid end) then
          raise exception using errcode='55000',message='financial_document_line_allocation_conflict';
        end if;
        update public.e10_supplier_credit_lines set
          configuration_version_id=case when jsonb_typeof(line.x->'configuration_version_id')='string'
            then (line.x->>'configuration_version_id')::uuid end,
          description=nullif(btrim(line.x->>'description'),''),line_amount=(line.x->>'line_amount')::numeric
        where organization_id=p_org and supplier_credit_id=p_document_id and id=(line.x->>'id')::uuid;
      else
        insert into public.e10_supplier_credit_lines(id,organization_id,supplier_credit_id,configuration_version_id,
          line_no,description,line_amount,state)
        values((line.x->>'id')::uuid,p_org,p_document_id,
          case when jsonb_typeof(line.x->'configuration_version_id')='string' then (line.x->>'configuration_version_id')::uuid end,
          (line.x->>'line_no')::integer,nullif(btrim(line.x->>'description'),''),(line.x->>'line_amount')::numeric,'active');
      end if;
    end loop;
    if exists(select 1 from public.e10_supplier_credit_lines l
      where l.organization_id=p_org and l.supplier_credit_id=p_document_id and l.state='active'
        and not exists(select 1 from jsonb_array_elements(p_lines) x where (x->>'id')::uuid=l.id)
        and exists(select 1 from public.e10_credit_invoice_allocations a
          where a.organization_id=l.organization_id and a.credit_line_id=l.id)) then
      raise exception using errcode='55000',message='financial_document_line_allocation_conflict';
    end if;
    update public.e10_supplier_credit_lines l set state='cancelled'
      where l.organization_id=p_org and l.supplier_credit_id=p_document_id and l.state='active'
        and not exists(select 1 from jsonb_array_elements(p_lines) x where (x->>'id')::uuid=l.id);
    update public.e10_supplier_credits set currency=p_currency,document_date=p_document_date,
      total_amount=p_total_amount,revision=new_revision,status=new_status,
      reviewed_by=case when new_status='reviewed' then actor end,
      reviewed_at=case when new_status='reviewed' then now() end,
      approved_revision=null,approved_by=null,approved_at=null,updated_at=now()
      where organization_id=p_org and id=p_document_id;
  end if;

  snapshot:=e10.financial_document_snapshot(p_org,p_document_kind,p_document_id);
  if p_document_kind='supplier_invoice' then
    insert into public.e10_supplier_invoice_revisions(organization_id,supplier_invoice_id,revision,status,snapshot,
      payload_fingerprint,change_reason,created_by)
    values(p_org,p_document_id,new_revision,new_status,snapshot,fp,btrim(p_reason),actor);
  else
    insert into public.e10_supplier_credit_revisions(organization_id,supplier_credit_id,revision,status,snapshot,
      payload_fingerprint,change_reason,created_by)
    values(p_org,p_document_id,new_revision,new_status,snapshot,fp,btrim(p_reason),actor);
  end if;
  result:=jsonb_build_object('ok',true,'replay',false,
    case when p_document_kind='supplier_invoice' then 'supplier_invoice_id' else 'supplier_credit_id' end,p_document_id,
    'status',new_status,'revision',new_revision,'lifecycle_event_id',event_id);
  insert into public.e10_financial_document_commands(organization_id,idempotency_key,document_kind,operation,
    document_id,request_fingerprint,result,created_by)
  values(p_org,p_idempotency_key,p_document_kind,'amend',p_document_id,fp,result,actor);
  insert into public.e10_financial_document_events(id,organization_id,document_kind,document_id,operation,revision,
    status,command_idempotency_key,payload,created_by)
  values(event_id,p_org,p_document_kind,p_document_id,'amend',new_revision,new_status,p_idempotency_key,
    jsonb_build_object('document_id',p_document_id,'document_kind',p_document_kind,'operation','amend',
      'status',new_status,'revision',new_revision,'reason',btrim(p_reason)),actor);
  return result;
exception when invalid_text_representation or numeric_value_out_of_range then
  raise exception using errcode='22023',message='financial_document_amend_encoding_invalid';
end $$;
revoke all on function public._e10_org_amend_financial_document_x3d1b(
  uuid,text,uuid,integer,text,date,numeric,jsonb,text,text
) from public,anon,authenticated;
grant execute on function public._e10_org_amend_financial_document_x3d1b(
  uuid,text,uuid,integer,text,date,numeric,jsonb,text,text
) to service_role;

create function public.e10_org_amend_supplier_invoice(
  p_org uuid,p_supplier_invoice_id uuid,p_expected_revision integer,p_currency text,
  p_document_date date,p_total_amount numeric,p_lines jsonb,p_reason text,p_idempotency_key text
) returns jsonb language sql security definer set search_path=public as $$
  select public._e10_org_amend_financial_document_x3d1b(p_org,'supplier_invoice',p_supplier_invoice_id,
    p_expected_revision,p_currency,p_document_date,p_total_amount,p_lines,p_reason,p_idempotency_key)
$$;
revoke all on function public.e10_org_amend_supplier_invoice(uuid,uuid,integer,text,date,numeric,jsonb,text,text)
  from public,anon;
grant execute on function public.e10_org_amend_supplier_invoice(uuid,uuid,integer,text,date,numeric,jsonb,text,text)
  to authenticated,service_role;

create function public.e10_org_amend_supplier_credit(
  p_org uuid,p_supplier_credit_id uuid,p_expected_revision integer,p_currency text,
  p_document_date date,p_total_amount numeric,p_lines jsonb,p_reason text,p_idempotency_key text
) returns jsonb language sql security definer set search_path=public as $$
  select public._e10_org_amend_financial_document_x3d1b(p_org,'supplier_credit',p_supplier_credit_id,
    p_expected_revision,p_currency,p_document_date,p_total_amount,p_lines,p_reason,p_idempotency_key)
$$;
revoke all on function public.e10_org_amend_supplier_credit(uuid,uuid,integer,text,date,numeric,jsonb,text,text)
  from public,anon;
grant execute on function public.e10_org_amend_supplier_credit(uuid,uuid,integer,text,date,numeric,jsonb,text,text)
  to authenticated,service_role;

comment on function public.e10_org_amend_supplier_invoice(uuid,uuid,integer,text,date,numeric,jsonb,text,text) is
  'CAS amendment. Reviewed/approved content returns to reviewed; allocated content must remain compatible and conserved.';
