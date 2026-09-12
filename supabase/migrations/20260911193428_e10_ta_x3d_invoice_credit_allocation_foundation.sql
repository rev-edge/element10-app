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
    num_nonnulls(reviewed_by,reviewed_at) in (0,2)),
  add constraint e10_supplier_invoices_approval_state_chk check(
    num_nonnulls(approved_revision,approved_by,approved_at) in (0,3)
    and (approved_revision is null or approved_revision=revision)),
  add constraint e10_supplier_invoices_void_state_chk check(
    num_nonnulls(voided_by,voided_at) in (0,2));

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
    num_nonnulls(reviewed_by,reviewed_at) in (0,2)),
  add constraint e10_supplier_credits_approval_state_chk check(
    num_nonnulls(approved_revision,approved_by,approved_at) in (0,3)
    and (approved_revision is null or approved_revision=revision)),
  add constraint e10_supplier_credits_void_state_chk check(
    num_nonnulls(voided_by,voided_at) in (0,2));

alter table public.e10_supplier_invoices
  add constraint e10_supplier_invoices_manual_identity_chk check(
    num_nonnulls(duplicate_review_outcome,duplicate_review_reason) in (0,2)
    and (duplicate_review_reason is null or btrim(duplicate_review_reason)<>''));
alter table public.e10_supplier_credits
  add constraint e10_supplier_credits_manual_identity_chk check(
    num_nonnulls(duplicate_review_outcome,duplicate_review_reason) in (0,2)
    and (duplicate_review_reason is null or btrim(duplicate_review_reason)<>''));

create index e10_supplier_invoices_manual_identity_idx
  on public.e10_supplier_invoices(organization_id,supplier_id,lower(btrim(supplier_document_number)))
  where source_connection is null and supplier_document_number is not null and btrim(supplier_document_number)<>'';
create index e10_supplier_credits_manual_identity_idx
  on public.e10_supplier_credits(organization_id,supplier_id,lower(btrim(supplier_document_number)))
  where source_connection is null and supplier_document_number is not null and btrim(supplier_document_number)<>'';

create function e10.guard_financial_manual_identity() returns trigger
language plpgsql security definer set search_path=public as $$
declare v_kind text:=tg_argv[0];
begin
  if new.source_connection is null
    and nullif(btrim(new.supplier_document_number),'') is null
    and new.duplicate_review_outcome is null then
    if tg_op='INSERT'
      or old.organization_id is distinct from new.organization_id
      or old.supplier_id is distinct from new.supplier_id
      or old.source_connection is distinct from new.source_connection
      or old.supplier_document_number is distinct from new.supplier_document_number
      or old.duplicate_review_outcome is distinct from new.duplicate_review_outcome
      or old.duplicate_review_reason is distinct from new.duplicate_review_reason then
      raise exception using errcode='23514',message='financial_identity_required';
    end if;
  end if;
  if new.source_connection is null and nullif(btrim(new.supplier_document_number),'') is not null then
    perform pg_advisory_xact_lock(hashtextextended(new.organization_id::text||'|'||v_kind||'|manual|'||
      new.supplier_id::text||'|'||lower(btrim(new.supplier_document_number)),0));
    if (v_kind='supplier_invoice' and exists(select 1 from public.e10_supplier_invoices d
        where d.organization_id=new.organization_id and d.supplier_id=new.supplier_id
          and d.source_connection is null and lower(btrim(d.supplier_document_number))=lower(btrim(new.supplier_document_number))
          and d.id<>new.id))
      or (v_kind='supplier_credit' and exists(select 1 from public.e10_supplier_credits d
        where d.organization_id=new.organization_id and d.supplier_id=new.supplier_id
          and d.source_connection is null and lower(btrim(d.supplier_document_number))=lower(btrim(new.supplier_document_number))
          and d.id<>new.id)) then
      raise exception using errcode='23505',message='financial_manual_identity_conflict';
    end if;
  end if;
  return new;
end $$;
create trigger e10_supplier_invoices_manual_identity_trg before insert or update of
  organization_id,supplier_id,supplier_document_number,source_connection,
  duplicate_review_outcome,duplicate_review_reason on public.e10_supplier_invoices
  for each row execute function e10.guard_financial_manual_identity('supplier_invoice');
create trigger e10_supplier_credits_manual_identity_trg before insert or update of
  organization_id,supplier_id,supplier_document_number,source_connection,
  duplicate_review_outcome,duplicate_review_reason on public.e10_supplier_credits
  for each row execute function e10.guard_financial_manual_identity('supplier_credit');

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
  check((document_kind='supplier_invoice' and coalesce(result->>'supplier_invoice_id','')=document_id::text)
    or (document_kind='supplier_credit' and coalesce(result->>'supplier_credit_id','')=document_id::text))
);

create table public.e10_financial_document_reconciliation_cases (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.e10_organizations(id),
  document_kind text not null check(document_kind in ('supplier_invoice','supplier_credit')),
  identity_kind text not null check(identity_kind in ('connected','manual')),
  source_connection text,
  external_document_id text,
  supplier_id uuid,
  normalized_document_number text,
  existing_document_id uuid not null,
  existing_fingerprint text not null check(btrim(existing_fingerprint)<>''),
  received_fingerprint text not null check(btrim(received_fingerprint)<>''),
  status text not null default 'requires_review' check(status='requires_review'),
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  unique(organization_id,id),
  check(existing_fingerprint<>received_fingerprint),
  check((identity_kind='connected' and source_connection is not null and btrim(source_connection)<>''
      and external_document_id is not null and btrim(external_document_id)<>''
      and supplier_id is null and normalized_document_number is null)
    or (identity_kind='manual' and source_connection is null and external_document_id is null
      and supplier_id is not null and normalized_document_number is not null
      and btrim(normalized_document_number)<>'' and normalized_document_number=lower(btrim(normalized_document_number)))),
  foreign key(organization_id,supplier_id) references public.e10_suppliers(organization_id,id)
);
create unique index e10_financial_reconciliation_connected_uq
  on public.e10_financial_document_reconciliation_cases
    (organization_id,document_kind,source_connection,external_document_id,received_fingerprint)
  where identity_kind='connected';
create unique index e10_financial_reconciliation_manual_uq
  on public.e10_financial_document_reconciliation_cases
    (organization_id,document_kind,supplier_id,normalized_document_number,received_fingerprint)
  where identity_kind='manual';

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
    coalesce(result->>'allocation_event_id','')=allocation_event_id::text);

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

create function e10.guard_financial_document_command() returns trigger
language plpgsql security definer set search_path=public as $$
begin
  if (new.document_kind='supplier_invoice' and (
      new.result->>'supplier_invoice_id' is distinct from new.document_id::text
      or not exists(select 1 from public.e10_supplier_invoices d
        where d.organization_id=new.organization_id and d.id=new.document_id)))
    or (new.document_kind='supplier_credit' and (
      new.result->>'supplier_credit_id' is distinct from new.document_id::text
      or not exists(select 1 from public.e10_supplier_credits d
        where d.organization_id=new.organization_id and d.id=new.document_id))) then
    raise exception using errcode='23514',message='financial_document_command_target_invalid';
  end if;
  return new;
end $$;

create function e10.guard_financial_reconciliation_case() returns trigger
language plpgsql security definer set search_path=public as $$
begin
  if (new.document_kind='supplier_invoice' and not exists(
      select 1 from public.e10_supplier_invoices d where d.organization_id=new.organization_id
        and d.id=new.existing_document_id
        and ((new.identity_kind='connected' and d.source_connection=new.source_connection
          and d.external_document_id=new.external_document_id)
          or (new.identity_kind='manual' and d.source_connection is null and d.supplier_id=new.supplier_id
            and lower(btrim(d.supplier_document_number))=new.normalized_document_number))))
    or (new.document_kind='supplier_credit' and not exists(
      select 1 from public.e10_supplier_credits d where d.organization_id=new.organization_id
        and d.id=new.existing_document_id
        and ((new.identity_kind='connected' and d.source_connection=new.source_connection
          and d.external_document_id=new.external_document_id)
          or (new.identity_kind='manual' and d.source_connection is null and d.supplier_id=new.supplier_id
            and lower(btrim(d.supplier_document_number))=new.normalized_document_number)))) then
    raise exception using errcode='23514',message='financial_reconciliation_target_invalid';
  end if;
  return new;
end $$;

create function e10.guard_invoice_po_allocation_event() returns trigger
language plpgsql security definer set search_path=public as $$
begin
  if not exists(select 1 from public.e10_financial_allocation_commands c
    where c.organization_id=new.organization_id and c.idempotency_key=new.command_idempotency_key
      and c.allocation_kind='invoice_to_po' and c.operation=new.operation
      and c.allocation_event_id=new.id and c.result->>'allocation_event_id'=new.id::text) then
    raise exception using errcode='23514',message='invoice_po_allocation_event_command_invalid';
  end if;
  return new;
end $$;

create function e10.guard_credit_invoice_allocation_event() returns trigger
language plpgsql security definer set search_path=public as $$
begin
  if not exists(select 1 from public.e10_financial_allocation_commands c
    where c.organization_id=new.organization_id and c.idempotency_key=new.command_idempotency_key
      and c.allocation_kind='credit_to_invoice' and c.operation=new.operation
      and c.allocation_event_id=new.id and c.result->>'allocation_event_id'=new.id::text) then
    raise exception using errcode='23514',message='credit_invoice_allocation_event_command_invalid';
  end if;
  return new;
end $$;

create constraint trigger e10_financial_allocation_command_event_trg
  after insert on public.e10_financial_allocation_commands deferrable initially deferred
  for each row execute function e10.guard_financial_allocation_command();
create constraint trigger e10_financial_document_command_target_trg
  after insert on public.e10_financial_document_commands deferrable initially deferred
  for each row execute function e10.guard_financial_document_command();
create constraint trigger e10_financial_reconciliation_target_trg
  after insert on public.e10_financial_document_reconciliation_cases deferrable initially deferred
  for each row execute function e10.guard_financial_reconciliation_case();
create constraint trigger e10_invoice_po_allocation_event_command_trg
  after insert on public.e10_invoice_po_allocation_events deferrable initially deferred
  for each row execute function e10.guard_invoice_po_allocation_event();
create constraint trigger e10_credit_invoice_allocation_event_command_trg
  after insert on public.e10_credit_invoice_allocation_events deferrable initially deferred
  for each row execute function e10.guard_credit_invoice_allocation_event();

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

revoke all on function e10.guard_financial_manual_identity() from public,anon,authenticated;
revoke all on function e10.guard_financial_allocation_command() from public,anon,authenticated;
revoke all on function e10.guard_financial_document_command() from public,anon,authenticated;
revoke all on function e10.guard_financial_reconciliation_case() from public,anon,authenticated;
revoke all on function e10.guard_invoice_po_allocation_event() from public,anon,authenticated;
revoke all on function e10.guard_credit_invoice_allocation_event() from public,anon,authenticated;
grant execute on function e10.guard_financial_manual_identity() to service_role;
grant execute on function e10.guard_financial_allocation_command() to service_role;
grant execute on function e10.guard_financial_document_command() to service_role;
grant execute on function e10.guard_financial_reconciliation_case() to service_role;
grant execute on function e10.guard_invoice_po_allocation_event() to service_role;
grant execute on function e10.guard_credit_invoice_allocation_event() to service_role;

create index e10_financial_document_reconciliation_cases_source_idx
  on public.e10_financial_document_reconciliation_cases
    (organization_id,document_kind,identity_kind,source_connection,external_document_id,created_at desc,id);
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
