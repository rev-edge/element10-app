-- TA-X3d.1a bounded supplier-invoice and supplier-credit creation.
-- No PO, receipt, stock, lot, movement, payment or accounting side effect is created here.

alter table public.e10_financial_document_reconciliation_cases
  add column received_snapshot jsonb
    check(received_snapshot is null or jsonb_typeof(received_snapshot)='object'
      and octet_length(received_snapshot::text)<=262144);

create table public.e10_financial_document_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.e10_organizations(id),
  document_kind text not null check(document_kind in ('supplier_invoice','supplier_credit')),
  document_id uuid not null,
  operation text not null check(operation in ('create','amend','review','approve','void')),
  revision integer not null check(revision>0),
  status text not null check(status in ('draft','reviewed','approved','void')),
  command_idempotency_key text not null,
  payload jsonb not null check(jsonb_typeof(payload)='object'),
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  unique(organization_id,id),
  unique(organization_id,command_idempotency_key),
  foreign key(organization_id,command_idempotency_key)
    references public.e10_financial_document_commands(organization_id,idempotency_key)
    deferrable initially deferred
);
alter table public.e10_financial_document_events enable row level security;
revoke all on public.e10_financial_document_events from public,anon,authenticated;
grant all on public.e10_financial_document_events to service_role;
create trigger e10_financial_document_events_append_only_trg
  before update or delete on public.e10_financial_document_events
  for each row execute function e10.reject_append_only_change();

create function e10.guard_financial_document_event() returns trigger
language plpgsql security definer set search_path=public as $$
begin
  if not exists(
    select 1 from public.e10_financial_document_commands c
    where c.organization_id=new.organization_id
      and c.idempotency_key=new.command_idempotency_key
      and c.document_kind=new.document_kind
      and c.operation=new.operation
      and c.document_id=new.document_id
      and c.result->>'lifecycle_event_id'=new.id::text
      and c.result->>'revision'=new.revision::text
      and c.result->>'status'=new.status
  ) or (new.document_kind='supplier_invoice' and not exists(
    select 1 from public.e10_supplier_invoices d
    where d.organization_id=new.organization_id and d.id=new.document_id
      and d.revision=new.revision and d.status=new.status
  )) or (new.document_kind='supplier_credit' and not exists(
    select 1 from public.e10_supplier_credits d
    where d.organization_id=new.organization_id and d.id=new.document_id
      and d.revision=new.revision and d.status=new.status
  )) then
    raise exception using errcode='23514',message='financial_document_event_link_invalid';
  end if;
  return new;
end $$;
revoke all on function e10.guard_financial_document_event() from public,anon,authenticated;
grant execute on function e10.guard_financial_document_event() to service_role;
create constraint trigger e10_financial_document_event_link_trg
  after insert on public.e10_financial_document_events deferrable initially deferred
  for each row execute function e10.guard_financial_document_event();

create function e10.financial_document_snapshot(
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

create function public._e10_org_create_financial_document_x3d1a(
  p_org uuid,p_document_kind text,p_supplier_id uuid,p_supplier_document_number text,
  p_currency text,p_document_date date,p_total_amount numeric,p_source_connection text,
  p_external_document_id text,p_payload_fingerprint text,p_duplicate_review_outcome text,
  p_duplicate_review_reason text,p_lines jsonb,p_idempotency_key text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare
  actor uuid:=auth.uid(); fp text; existing_cmd record; existing_doc record;
  doc_id uuid:=gen_random_uuid(); event_id uuid:=gen_random_uuid(); result jsonb; snapshot jsonb;
  line record; line_count integer; line_id uuid; v_identity_kind text; normalized_number text;
  existing_fp text; received_fp text; reconciliation_id uuid; document_count integer;
  reconciliation_replay boolean;
  incoming_snapshot jsonb;
begin
  if actor is null or p_document_kind not in ('supplier_invoice','supplier_credit')
    or not exists(select 1 from public.e10_organizations where id=p_org and status='active')
    or not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.purchasing_prepare') then
    raise exception using errcode='42501',message='financial_document_prepare_denied';
  end if;
  if p_idempotency_key is null or btrim(p_idempotency_key)='' or length(p_idempotency_key)>200
    or p_currency is null or p_currency!~'^[A-Z]{3}$'
    or p_total_amount is not null and (p_total_amount<0 or p_total_amount::text in ('NaN','Infinity','-Infinity'))
    or p_document_kind='supplier_credit' and p_total_amount is null
    or p_supplier_document_number is not null and (btrim(p_supplier_document_number)='' or length(p_supplier_document_number)>200)
    or p_source_connection is not null and (btrim(p_source_connection)='' or length(p_source_connection)>200)
    or p_external_document_id is not null and (btrim(p_external_document_id)='' or length(p_external_document_id)>500)
    or p_payload_fingerprint is not null and (btrim(p_payload_fingerprint)='' or length(p_payload_fingerprint)>200)
    or p_duplicate_review_reason is not null and length(p_duplicate_review_reason)>2000
    or p_lines is null or jsonb_typeof(p_lines)<>'array' or octet_length(p_lines::text)>262144 then
    raise exception using errcode='22023',message='financial_document_payload_invalid';
  end if;
  if (p_source_connection is null)<>(p_external_document_id is null)
    or p_source_connection is not null and p_payload_fingerprint is null
    or p_source_connection is null and p_supplier_document_number is null
      and (p_duplicate_review_outcome is null or p_duplicate_review_reason is null or btrim(p_duplicate_review_reason)='')
    or num_nonnulls(p_duplicate_review_outcome,p_duplicate_review_reason) not in (0,2)
    or p_duplicate_review_outcome is not null
      and p_duplicate_review_outcome not in ('confirmed_distinct','possible_duplicate_accepted') then
    raise exception using errcode='22023',message='financial_document_identity_invalid';
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
  end loop;
  if (select count(*) from (select (x->>'id')::uuid from jsonb_array_elements(p_lines) x group by 1) q)<>line_count
    or (select count(*) from (select (x->>'line_no')::integer from jsonb_array_elements(p_lines) x group by 1) q)<>line_count then
    raise exception using errcode='22023',message='financial_document_line_identity_invalid';
  end if;

  v_identity_kind:=case when p_source_connection is null then 'manual' else 'connected' end;
  normalized_number:=lower(btrim(p_supplier_document_number));
  incoming_snapshot:=jsonb_build_object('document_kind',p_document_kind,'supplier_id',p_supplier_id,
    'supplier_document_number',case when v_identity_kind='manual' then normalized_number
      else nullif(btrim(p_supplier_document_number),'') end,'currency',p_currency,
    'document_date',p_document_date,'total_amount',p_total_amount,
    'source_connection',nullif(btrim(p_source_connection),''),
    'external_document_id',nullif(btrim(p_external_document_id),''),
    'source_payload_fingerprint',nullif(btrim(p_payload_fingerprint),''),
    'duplicate_review_outcome',p_duplicate_review_outcome,
    'duplicate_review_reason',nullif(btrim(p_duplicate_review_reason),''),'lines',p_lines);
  fp:=md5(jsonb_build_object('v','financial-document-create-v1','org',p_org,'kind',p_document_kind,
    'supplier',p_supplier_id,'number',case when v_identity_kind='manual' then normalized_number
      else nullif(btrim(p_supplier_document_number),'') end,'currency',p_currency,
    'date',p_document_date,'total',p_total_amount,'source',nullif(btrim(p_source_connection),''),
    'external',nullif(btrim(p_external_document_id),''),'payload_fp',nullif(btrim(p_payload_fingerprint),''),
    'duplicate_outcome',p_duplicate_review_outcome,'duplicate_reason',nullif(btrim(p_duplicate_review_reason),''),
    'lines',p_lines)::text);
  -- Persist and reconcile the server-derived canonical request fingerprint. The supplied
  -- source payload fingerprint remains one input to it, never the authority by itself.
  received_fp:=fp;
  perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|financial-document-command|'||p_idempotency_key,0));
  select c.request_fingerprint,c.result into existing_cmd from public.e10_financial_document_commands c
    where c.organization_id=p_org and c.idempotency_key=p_idempotency_key;
  if found then
    if existing_cmd.request_fingerprint<>fp then raise exception using errcode='22023',message='idempotency_key_mismatch'; end if;
    if auth.uid() is distinct from actor
      or not exists(select 1 from public.e10_organizations where id=p_org and status='active')
      or not e10.is_org_member(p_org)
      or not e10.has_org_cap(p_org,'act.purchasing_prepare') then
      raise exception using errcode='42501',message='financial_document_prepare_denied';
    end if;
    return existing_cmd.result||jsonb_build_object('replay',true);
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|'||p_document_kind||'|'||v_identity_kind||'|'||
    case when v_identity_kind='connected' then btrim(p_source_connection)||'|'||btrim(p_external_document_id)
      else p_supplier_id::text||'|'||coalesce(normalized_number,'<missing-reviewed>') end,0));
  if auth.uid() is distinct from actor or not exists(select 1 from public.e10_organizations where id=p_org and status='active')
    or not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.purchasing_prepare') then
    raise exception using errcode='42501',message='financial_document_prepare_denied';
  end if;
  perform 1 from public.e10_suppliers where organization_id=p_org and id=p_supplier_id and status='active';
  if not found then raise exception using errcode='42501',message='financial_document_supplier_denied'; end if;

  for line in select x from jsonb_array_elements(p_lines) x loop
    if jsonb_typeof(line.x->'configuration_version_id')='string' and not exists(
      select 1 from public.e10_product_configuration_versions
      where organization_id=p_org and id=(line.x->>'configuration_version_id')::uuid and state='active') then
      raise exception using errcode='42501',message='financial_document_configuration_denied';
    end if;
  end loop;

  if p_document_kind='supplier_invoice' then
    select count(*) into document_count from public.e10_supplier_invoices
      where organization_id=p_org and ((v_identity_kind='connected' and source_connection=btrim(p_source_connection)
        and external_document_id=btrim(p_external_document_id)) or (v_identity_kind='manual' and source_connection is null
        and supplier_id=p_supplier_id and lower(btrim(supplier_document_number))=normalized_number));
    if document_count>1 then raise exception using errcode='23514',message='financial_document_identity_ambiguous'; end if;
    select id,payload_fingerprint,revision,status into existing_doc from public.e10_supplier_invoices
      where organization_id=p_org and ((v_identity_kind='connected' and source_connection=btrim(p_source_connection)
        and external_document_id=btrim(p_external_document_id)) or (v_identity_kind='manual' and source_connection is null
        and supplier_id=p_supplier_id and lower(btrim(supplier_document_number))=normalized_number)) limit 1;
  else
    select count(*) into document_count from public.e10_supplier_credits
      where organization_id=p_org and ((v_identity_kind='connected' and source_connection=btrim(p_source_connection)
        and external_document_id=btrim(p_external_document_id)) or (v_identity_kind='manual' and source_connection is null
        and supplier_id=p_supplier_id and lower(btrim(supplier_document_number))=normalized_number));
    if document_count>1 then raise exception using errcode='23514',message='financial_document_identity_ambiguous'; end if;
    select id,payload_fingerprint,revision,status into existing_doc from public.e10_supplier_credits
      where organization_id=p_org and ((v_identity_kind='connected' and source_connection=btrim(p_source_connection)
        and external_document_id=btrim(p_external_document_id)) or (v_identity_kind='manual' and source_connection is null
        and supplier_id=p_supplier_id and lower(btrim(supplier_document_number))=normalized_number)) limit 1;
  end if;
  if found then
    existing_fp:=existing_doc.payload_fingerprint;
    if existing_fp is not distinct from received_fp then
      result:=jsonb_build_object('ok',true,'replay',true,'identity_replay',true,
        case when p_document_kind='supplier_invoice' then 'supplier_invoice_id' else 'supplier_credit_id' end,existing_doc.id,
        'status',existing_doc.status,'revision',existing_doc.revision);
    else
      select c.id into reconciliation_id from public.e10_financial_document_reconciliation_cases c
      where c.organization_id=p_org and c.document_kind=p_document_kind
        and c.identity_kind=v_identity_kind and c.existing_document_id=existing_doc.id
        and c.received_fingerprint=received_fp
        and (v_identity_kind='connected' and c.source_connection=btrim(p_source_connection)
          and c.external_document_id=btrim(p_external_document_id)
          or v_identity_kind='manual' and c.supplier_id=p_supplier_id
          and c.normalized_document_number=normalized_number);
      reconciliation_replay:=found;
      if not found then
        insert into public.e10_financial_document_reconciliation_cases(
          organization_id,document_kind,identity_kind,source_connection,external_document_id,
          supplier_id,normalized_document_number,existing_document_id,existing_fingerprint,
          received_fingerprint,received_snapshot,created_by)
        values(p_org,p_document_kind,v_identity_kind,
          case when v_identity_kind='connected' then btrim(p_source_connection) end,
          case when v_identity_kind='connected' then btrim(p_external_document_id) end,
          case when v_identity_kind='manual' then p_supplier_id end,
          case when v_identity_kind='manual' then normalized_number end,
          existing_doc.id,coalesce(existing_fp,'legacy-unfingerprinted'),received_fp,incoming_snapshot,actor)
        returning id into reconciliation_id;
      end if;
      result:=jsonb_build_object('ok',false,'replay',false,'status','requires_review',
        case when p_document_kind='supplier_invoice' then 'supplier_invoice_id' else 'supplier_credit_id' end,existing_doc.id,
        'revision',existing_doc.revision,'reconciliation_case_id',reconciliation_id,
        'reconciliation_replay',reconciliation_replay);
    end if;
    insert into public.e10_financial_document_commands(organization_id,idempotency_key,document_kind,operation,
      document_id,request_fingerprint,result,created_by)
    values(p_org,p_idempotency_key,p_document_kind,'create',existing_doc.id,fp,result,actor);
    return result;
  end if;

  if p_document_kind='supplier_invoice' then
    insert into public.e10_supplier_invoices(id,organization_id,supplier_id,supplier_document_number,revision,status,
      currency,document_date,total_amount,source_connection,external_document_id,payload_fingerprint,
      duplicate_review_outcome,duplicate_review_reason,created_by)
    values(doc_id,p_org,p_supplier_id,nullif(btrim(p_supplier_document_number),''),1,'draft',p_currency,p_document_date,
      p_total_amount,nullif(btrim(p_source_connection),''),nullif(btrim(p_external_document_id),''),received_fp,
      p_duplicate_review_outcome,nullif(btrim(p_duplicate_review_reason),''),actor);
    insert into public.e10_supplier_invoice_lines(id,organization_id,supplier_invoice_id,configuration_version_id,
      line_no,description,invoiced_quantity,unit_cost,line_amount,state)
    select (x->>'id')::uuid,p_org,doc_id,case when jsonb_typeof(x->'configuration_version_id')='null' then null
      else (x->>'configuration_version_id')::uuid end,(x->>'line_no')::integer,nullif(btrim(x->>'description'),''),
      case when jsonb_typeof(x->'invoiced_quantity')='number' then (x->>'invoiced_quantity')::numeric end,
      case when jsonb_typeof(x->'unit_cost')='number' then (x->>'unit_cost')::numeric end,
      (x->>'line_amount')::numeric,'active' from jsonb_array_elements(p_lines) x;
  else
    insert into public.e10_supplier_credits(id,organization_id,supplier_id,supplier_document_number,revision,status,
      currency,document_date,total_amount,source_connection,external_document_id,payload_fingerprint,
      duplicate_review_outcome,duplicate_review_reason,created_by)
    values(doc_id,p_org,p_supplier_id,nullif(btrim(p_supplier_document_number),''),1,'draft',p_currency,p_document_date,
      p_total_amount,nullif(btrim(p_source_connection),''),nullif(btrim(p_external_document_id),''),received_fp,
      p_duplicate_review_outcome,nullif(btrim(p_duplicate_review_reason),''),actor);
    insert into public.e10_supplier_credit_lines(id,organization_id,supplier_credit_id,configuration_version_id,
      line_no,description,line_amount,state)
    select (x->>'id')::uuid,p_org,doc_id,case when jsonb_typeof(x->'configuration_version_id')='null' then null
      else (x->>'configuration_version_id')::uuid end,(x->>'line_no')::integer,nullif(btrim(x->>'description'),''),
      (x->>'line_amount')::numeric,'active' from jsonb_array_elements(p_lines) x;
  end if;
  snapshot:=e10.financial_document_snapshot(p_org,p_document_kind,doc_id);
  if p_document_kind='supplier_invoice' then
    insert into public.e10_supplier_invoice_revisions(organization_id,supplier_invoice_id,revision,status,snapshot,
      payload_fingerprint,change_reason,created_by) values(p_org,doc_id,1,'draft',snapshot,fp,'created',actor);
  else
    insert into public.e10_supplier_credit_revisions(organization_id,supplier_credit_id,revision,status,snapshot,
      payload_fingerprint,change_reason,created_by) values(p_org,doc_id,1,'draft',snapshot,fp,'created',actor);
  end if;
  result:=jsonb_build_object('ok',true,'replay',false,
    case when p_document_kind='supplier_invoice' then 'supplier_invoice_id' else 'supplier_credit_id' end,doc_id,
    'status','draft','revision',1,'lifecycle_event_id',event_id);
  insert into public.e10_financial_document_commands(organization_id,idempotency_key,document_kind,operation,
    document_id,request_fingerprint,result,created_by)
  values(p_org,p_idempotency_key,p_document_kind,'create',doc_id,fp,result,actor);
  insert into public.e10_financial_document_events(id,organization_id,document_kind,document_id,operation,revision,
    status,command_idempotency_key,payload,created_by)
  values(event_id,p_org,p_document_kind,doc_id,'create',1,'draft',p_idempotency_key,
    jsonb_build_object('document_id',doc_id,'document_kind',p_document_kind,'operation','create',
      'status','draft','revision',1),actor);
  return result;
exception when invalid_text_representation or numeric_value_out_of_range then
  raise exception using errcode='22023',message='financial_document_encoding_invalid';
end $$;
revoke all on function public._e10_org_create_financial_document_x3d1a(
  uuid,text,uuid,text,text,date,numeric,text,text,text,text,text,jsonb,text
) from public,anon,authenticated;
grant execute on function public._e10_org_create_financial_document_x3d1a(
  uuid,text,uuid,text,text,date,numeric,text,text,text,text,text,jsonb,text
) to service_role;

create function public.e10_org_create_supplier_invoice(
  p_org uuid,p_supplier_id uuid,p_supplier_document_number text,p_currency text,p_document_date date,
  p_total_amount numeric,p_source_connection text,p_external_document_id text,p_payload_fingerprint text,
  p_duplicate_review_outcome text,p_duplicate_review_reason text,p_lines jsonb,p_idempotency_key text
) returns jsonb language sql security definer set search_path=public as $$
  select public._e10_org_create_financial_document_x3d1a(p_org,'supplier_invoice',p_supplier_id,
    p_supplier_document_number,p_currency,p_document_date,p_total_amount,p_source_connection,
    p_external_document_id,p_payload_fingerprint,p_duplicate_review_outcome,p_duplicate_review_reason,
    p_lines,p_idempotency_key)
$$;
revoke all on function public.e10_org_create_supplier_invoice(
  uuid,uuid,text,text,date,numeric,text,text,text,text,text,jsonb,text
) from public,anon;
grant execute on function public.e10_org_create_supplier_invoice(
  uuid,uuid,text,text,date,numeric,text,text,text,text,text,jsonb,text
) to authenticated,service_role;

create function public.e10_org_create_supplier_credit(
  p_org uuid,p_supplier_id uuid,p_supplier_document_number text,p_currency text,p_document_date date,
  p_total_amount numeric,p_source_connection text,p_external_document_id text,p_payload_fingerprint text,
  p_duplicate_review_outcome text,p_duplicate_review_reason text,p_lines jsonb,p_idempotency_key text
) returns jsonb language sql security definer set search_path=public as $$
  select public._e10_org_create_financial_document_x3d1a(p_org,'supplier_credit',p_supplier_id,
    p_supplier_document_number,p_currency,p_document_date,p_total_amount,p_source_connection,
    p_external_document_id,p_payload_fingerprint,p_duplicate_review_outcome,p_duplicate_review_reason,
    p_lines,p_idempotency_key)
$$;
revoke all on function public.e10_org_create_supplier_credit(
  uuid,uuid,text,text,date,numeric,text,text,text,text,text,jsonb,text
) from public,anon;
grant execute on function public.e10_org_create_supplier_credit(
  uuid,uuid,text,text,date,numeric,text,text,text,text,text,jsonb,text
) to authenticated,service_role;

create index e10_financial_document_events_document_idx
  on public.e10_financial_document_events(organization_id,document_kind,document_id,revision,id);
create index e10_financial_document_events_created_by_idx
  on public.e10_financial_document_events(created_by) where created_by is not null;

comment on table public.e10_financial_document_events is
  'Append-only invoice/credit lifecycle evidence. Creation does not imply receipt, stock, payment or accounting recognition.';
