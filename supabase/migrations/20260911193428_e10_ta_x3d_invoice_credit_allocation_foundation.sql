-- TA-X3d.0 invoice, credit and allocation workflow foundation.
-- Storage and client-closed helpers only. Public mutation APIs follow separately.

alter table public.e10_supplier_invoices
  add column reviewed_by uuid references auth.users(id),
  add column reviewed_at timestamptz,
  add column approved_revision integer,
  add column approved_by uuid references auth.users(id),
  add column approved_at timestamptz,
  add column voided_by uuid references auth.users(id),
  add column voided_at timestamptz,
  add column duplicate_review_outcome text
    check(duplicate_review_outcome in ('confirmed_distinct','possible_duplicate_accepted')),
  add column duplicate_review_reason text,
  add constraint e10_supplier_invoices_review_state_chk check(
    status<>'reviewed' or ((reviewed_by is null and reviewed_at is null)
      or (reviewed_by is not null and reviewed_at is not null))),
  add constraint e10_supplier_invoices_approval_state_chk check(
    status<>'approved' or ((approved_revision is null and approved_by is null and approved_at is null)
      or (approved_revision=revision and approved_by is not null and approved_at is not null))),
  add constraint e10_supplier_invoices_void_state_chk check(
    status<>'void' or ((voided_by is null and voided_at is null)
      or (voided_by is not null and voided_at is not null))),
  add constraint e10_supplier_invoices_manual_identity_chk check(
    source_connection is not null
    or (supplier_document_number is not null and btrim(supplier_document_number)<>'')
    or (duplicate_review_outcome is not null and duplicate_review_reason is not null
      and btrim(duplicate_review_reason)<>''));

alter table public.e10_supplier_credits
  add column reviewed_by uuid references auth.users(id),
  add column reviewed_at timestamptz,
  add column approved_revision integer,
  add column approved_by uuid references auth.users(id),
  add column approved_at timestamptz,
  add column voided_by uuid references auth.users(id),
  add column voided_at timestamptz,
  add column duplicate_review_outcome text
    check(duplicate_review_outcome in ('confirmed_distinct','possible_duplicate_accepted')),
  add column duplicate_review_reason text,
  add constraint e10_supplier_credits_review_state_chk check(
    status<>'reviewed' or ((reviewed_by is null and reviewed_at is null)
      or (reviewed_by is not null and reviewed_at is not null))),
  add constraint e10_supplier_credits_approval_state_chk check(
    status<>'approved' or ((approved_revision is null and approved_by is null and approved_at is null)
      or (approved_revision=revision and approved_by is not null and approved_at is not null))),
  add constraint e10_supplier_credits_void_state_chk check(
    status<>'void' or ((voided_by is null and voided_at is null)
      or (voided_by is not null and voided_at is not null))),
  add constraint e10_supplier_credits_manual_identity_chk check(
    source_connection is not null
    or (supplier_document_number is not null and btrim(supplier_document_number)<>'')
    or (duplicate_review_outcome is not null and duplicate_review_reason is not null
      and btrim(duplicate_review_reason)<>''));

create unique index e10_supplier_invoices_manual_identity_uq
  on public.e10_supplier_invoices(organization_id,supplier_id,lower(btrim(supplier_document_number)))
  where source_connection is null and supplier_document_number is not null and btrim(supplier_document_number)<>'';
create unique index e10_supplier_credits_manual_identity_uq
  on public.e10_supplier_credits(organization_id,supplier_id,lower(btrim(supplier_document_number)))
  where source_connection is null and supplier_document_number is not null and btrim(supplier_document_number)<>'';

alter table public.e10_supplier_invoice_lines
  add column state text not null default 'active' check(state in ('active','cancelled'));
alter table public.e10_supplier_invoice_lines
  drop constraint e10_supplier_invoice_lines_organization_id_supplier_invoice_key,
  add constraint e10_supplier_invoice_lines_org_invoice_line_no_uq
    unique(organization_id,supplier_invoice_id,line_no) deferrable initially immediate;

alter table public.e10_supplier_credit_lines
  add column configuration_version_id uuid,
  add column state text not null default 'active' check(state in ('active','cancelled')),
  add constraint e10_supplier_credit_lines_org_configuration_fkey
    foreign key(organization_id,configuration_version_id)
    references public.e10_product_configuration_versions(organization_id,id);
alter table public.e10_supplier_credit_lines
  drop constraint e10_supplier_credit_lines_organization_id_supplier_credit_i_key,
  add constraint e10_supplier_credit_lines_org_credit_line_no_uq
    unique(organization_id,supplier_credit_id,line_no) deferrable initially immediate;

create table public.e10_financial_document_commands (
  organization_id uuid not null references public.e10_organizations(id),
  idempotency_key text not null check(btrim(idempotency_key)<>''),
  document_kind text not null check(document_kind in ('supplier_invoice','supplier_credit')),
  operation text not null check(operation in ('create','amend','review','approve','void')),
  document_id uuid not null,
  request_fingerprint text not null check(btrim(request_fingerprint)<>''),
  result jsonb not null check(jsonb_typeof(result)='object'),
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  primary key(organization_id,idempotency_key),
  check((document_kind='supplier_invoice' and result->>'supplier_invoice_id'=document_id::text)
    or (document_kind='supplier_credit' and result->>'supplier_credit_id'=document_id::text))
);

create table public.e10_financial_document_reconciliation_cases (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.e10_organizations(id),
  document_kind text not null check(document_kind in ('supplier_invoice','supplier_credit')),
  source_connection text not null check(btrim(source_connection)<>''),
  external_document_id text not null check(btrim(external_document_id)<>''),
  existing_document_id uuid not null,
  existing_fingerprint text not null check(btrim(existing_fingerprint)<>''),
  received_fingerprint text not null check(btrim(received_fingerprint)<>''),
  status text not null default 'requires_review' check(status='requires_review'),
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  unique(organization_id,id),
  unique(organization_id,document_kind,source_connection,external_document_id,received_fingerprint),
  check(existing_fingerprint<>received_fingerprint)
);

create table public.e10_financial_allocation_commands (
  organization_id uuid not null references public.e10_organizations(id),
  idempotency_key text not null check(btrim(idempotency_key)<>''),
  allocation_kind text not null check(allocation_kind in ('invoice_to_po','credit_to_invoice')),
  operation text not null check(operation in ('allocate','release')),
  allocation_event_id uuid not null,
  request_fingerprint text not null check(btrim(request_fingerprint)<>''),
  result jsonb not null check(jsonb_typeof(result)='object'),
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  primary key(organization_id,idempotency_key)
);

create table public.e10_invoice_po_allocation_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.e10_organizations(id),
  invoice_line_id uuid not null,
  purchase_order_line_id uuid not null,
  operation text not null check(operation in ('allocate','release')),
  quantity_delta numeric not null check(quantity_delta<>0 and quantity_delta::text not in ('NaN','Infinity','-Infinity')),
  reason text not null check(btrim(reason)<>'' and length(reason)<=2000),
  command_idempotency_key text not null,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  unique(organization_id,id),
  unique(organization_id,command_idempotency_key),
  foreign key(organization_id,invoice_line_id)
    references public.e10_supplier_invoice_lines(organization_id,id),
  foreign key(organization_id,purchase_order_line_id)
    references public.e10_purchase_order_lines(organization_id,id),
  foreign key(organization_id,command_idempotency_key)
    references public.e10_financial_allocation_commands(organization_id,idempotency_key)
    deferrable initially deferred,
  check((operation='allocate' and quantity_delta>0) or (operation='release' and quantity_delta<0))
);

create table public.e10_credit_invoice_allocation_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.e10_organizations(id),
  credit_line_id uuid not null,
  invoice_line_id uuid not null,
  operation text not null check(operation in ('allocate','release')),
  amount_delta numeric not null check(amount_delta<>0 and amount_delta::text not in ('NaN','Infinity','-Infinity')),
  reason text not null check(btrim(reason)<>'' and length(reason)<=2000),
  command_idempotency_key text not null,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  unique(organization_id,id),
  unique(organization_id,command_idempotency_key),
  foreign key(organization_id,credit_line_id)
    references public.e10_supplier_credit_lines(organization_id,id),
  foreign key(organization_id,invoice_line_id)
    references public.e10_supplier_invoice_lines(organization_id,id),
  foreign key(organization_id,command_idempotency_key)
    references public.e10_financial_allocation_commands(organization_id,idempotency_key)
    deferrable initially deferred,
  check((operation='allocate' and amount_delta>0) or (operation='release' and amount_delta<0))
);

alter table public.e10_financial_allocation_commands
  add constraint e10_financial_allocation_commands_org_event_invoice_fkey
    foreign key(organization_id,allocation_event_id)
    references public.e10_invoice_po_allocation_events(organization_id,id)
    deferrable initially deferred,
  add constraint e10_financial_allocation_commands_event_kind_chk check(
    (allocation_kind='invoice_to_po' and result->>'allocation_event_id'=allocation_event_id::text)
    or (allocation_kind='credit_to_invoice' and result->>'allocation_event_id'=allocation_event_id::text));

-- The second event-kind FK cannot be expressed conditionally. A trigger validates the target table.
alter table public.e10_financial_allocation_commands
  drop constraint e10_financial_allocation_commands_org_event_invoice_fkey;

create function e10.guard_financial_allocation_command() returns trigger
language plpgsql security definer set search_path=public as $$
begin
  if new.result->>'allocation_event_id' is distinct from new.allocation_event_id::text
    or (new.allocation_kind='invoice_to_po' and not exists(
      select 1 from public.e10_invoice_po_allocation_events e
      where e.organization_id=new.organization_id and e.id=new.allocation_event_id
        and e.command_idempotency_key=new.idempotency_key))
    or (new.allocation_kind='credit_to_invoice' and not exists(
      select 1 from public.e10_credit_invoice_allocation_events e
      where e.organization_id=new.organization_id and e.id=new.allocation_event_id
        and e.command_idempotency_key=new.idempotency_key)) then
    raise exception using errcode='23514',message='financial_allocation_command_event_invalid';
  end if;
  return new;
end $$;

create constraint trigger e10_financial_allocation_command_event_trg
  after insert on public.e10_financial_allocation_commands deferrable initially deferred
  for each row execute function e10.guard_financial_allocation_command();

do $$ declare t text; begin
  foreach t in array array[
    'e10_financial_document_commands','e10_financial_document_reconciliation_cases',
    'e10_financial_allocation_commands','e10_invoice_po_allocation_events',
    'e10_credit_invoice_allocation_events'
  ] loop
    execute format('alter table public.%I enable row level security',t);
    execute format('revoke all on table public.%I from public,anon,authenticated',t);
    execute format('grant all on table public.%I to service_role',t);
    execute format('create trigger %I before update or delete on public.%I for each row execute function e10.reject_append_only_change()',t||'_append_only_trg',t);
  end loop;
end $$;

revoke all on function e10.guard_financial_allocation_command() from public,anon,authenticated;
grant execute on function e10.guard_financial_allocation_command() to service_role;

create index e10_financial_document_reconciliation_cases_source_idx
  on public.e10_financial_document_reconciliation_cases
    (organization_id,document_kind,source_connection,external_document_id,created_at desc,id);
create index e10_invoice_po_allocation_events_invoice_idx
  on public.e10_invoice_po_allocation_events(organization_id,invoice_line_id,created_at,id);
create index e10_invoice_po_allocation_events_po_idx
  on public.e10_invoice_po_allocation_events(organization_id,purchase_order_line_id,created_at,id);
create index e10_credit_invoice_allocation_events_credit_idx
  on public.e10_credit_invoice_allocation_events(organization_id,credit_line_id,created_at,id);
create index e10_credit_invoice_allocation_events_invoice_idx
  on public.e10_credit_invoice_allocation_events(organization_id,invoice_line_id,created_at,id);

comment on table public.e10_financial_document_commands is
  'Client-closed idempotency receipts for supplier invoice and credit lifecycle commands.';
comment on table public.e10_financial_document_reconciliation_cases is
  'Changed-payload connected-document identity conflicts requiring explicit review; no source document is overwritten.';
comment on table public.e10_invoice_po_allocation_events is
  'Append-only quantity allocation and release evidence. Current allocation rows are a derived transactional projection.';
comment on table public.e10_credit_invoice_allocation_events is
  'Append-only amount allocation and release evidence. Credits remain distinct from invoices and payment.';
