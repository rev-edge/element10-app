-- TA-X3a purchasing document foundation. Separate commercial objects and additive comments.

create table public.e10_purchase_orders (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.e10_organizations(id),
  supplier_id uuid not null, destination_location_id uuid not null, order_number text,
  revision integer not null default 1 check (revision>0), status text not null default 'draft'
    check (status in ('draft','submitted','approved','cancelled','closed')),
  currency text not null check (currency ~ '^[A-Z]{3}$'), expected_at timestamptz,
  created_by uuid default auth.uid() references auth.users(id), created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unique (organization_id,id),
  foreign key (organization_id,supplier_id) references public.e10_suppliers(organization_id,id),
  foreign key (organization_id,destination_location_id) references public.e10_locations(organization_id,id)
);
create unique index e10_purchase_orders_org_number_uq on public.e10_purchase_orders(organization_id,lower(btrim(order_number))) where order_number is not null and btrim(order_number)<>'';
create index e10_purchase_orders_org_supplier_status_idx on public.e10_purchase_orders(organization_id,supplier_id,status,created_at desc,id);

create table public.e10_purchase_order_lines (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.e10_organizations(id),
  purchase_order_id uuid not null, configuration_version_id uuid not null, line_no integer not null check(line_no>0),
  ordered_quantity numeric not null check(ordered_quantity>0), estimated_unit_cost numeric check(estimated_unit_cost is null or estimated_unit_cost>=0),
  created_at timestamptz not null default now(), unique(organization_id,id), unique(organization_id,purchase_order_id,line_no),
  foreign key (organization_id,purchase_order_id) references public.e10_purchase_orders(organization_id,id) on delete cascade,
  foreign key (organization_id,configuration_version_id) references public.e10_product_configuration_versions(organization_id,id)
);
create index e10_purchase_order_lines_config_idx on public.e10_purchase_order_lines(organization_id,configuration_version_id,purchase_order_id,id);

create table public.e10_supplier_invoices (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.e10_organizations(id), supplier_id uuid not null,
  supplier_document_number text, revision integer not null default 1 check(revision>0), status text not null default 'draft'
    check(status in ('draft','reviewed','approved','void')),
  currency text not null check(currency ~ '^[A-Z]{3}$'), document_date date, total_amount numeric check(total_amount is null or total_amount>=0),
  source_connection text, external_document_id text, payload_fingerprint text,
  created_by uuid default auth.uid() references auth.users(id), created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unique(organization_id,id), foreign key (organization_id,supplier_id) references public.e10_suppliers(organization_id,id),
  check ((source_connection is null and external_document_id is null) or (source_connection is not null and external_document_id is not null and payload_fingerprint is not null))
);
create unique index e10_supplier_invoices_source_uq on public.e10_supplier_invoices(organization_id,source_connection,external_document_id) where source_connection is not null;
create index e10_supplier_invoices_supplier_idx on public.e10_supplier_invoices(organization_id,supplier_id,document_date desc,id);

create table public.e10_supplier_invoice_lines (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.e10_organizations(id), supplier_invoice_id uuid not null,
  configuration_version_id uuid, line_no integer not null check(line_no>0), description text,
  invoiced_quantity numeric check(invoiced_quantity is null or invoiced_quantity>0), unit_cost numeric check(unit_cost is null or unit_cost>=0),
  line_amount numeric not null check(line_amount>=0), created_at timestamptz not null default now(),
  unique(organization_id,id), unique(organization_id,supplier_invoice_id,line_no),
  foreign key (organization_id,supplier_invoice_id) references public.e10_supplier_invoices(organization_id,id) on delete cascade,
  foreign key (organization_id,configuration_version_id) references public.e10_product_configuration_versions(organization_id,id)
);

create table public.e10_stock_receipts (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.e10_organizations(id), supplier_id uuid not null,
  destination_location_id uuid not null, receipt_number text, status text not null default 'draft'
    check(status in ('draft','posted','corrected','reversed')),
  received_at timestamptz, created_by uuid default auth.uid() references auth.users(id), created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unique(organization_id,id),
  foreign key (organization_id,supplier_id) references public.e10_suppliers(organization_id,id),
  foreign key (organization_id,destination_location_id) references public.e10_locations(organization_id,id)
);
create unique index e10_stock_receipts_org_number_uq on public.e10_stock_receipts(organization_id,lower(btrim(receipt_number))) where receipt_number is not null and btrim(receipt_number)<>'';

create table public.e10_stock_receipt_lines (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.e10_organizations(id), stock_receipt_id uuid not null,
  configuration_version_id uuid not null, line_no integer not null check(line_no>0),
  received_quantity numeric not null check(received_quantity>0), accepted_quantity numeric not null check(accepted_quantity>=0),
  damaged_quantity numeric not null default 0 check(damaged_quantity>=0), quarantined_quantity numeric not null default 0 check(quarantined_quantity>=0),
  actual_unit_cost numeric check(actual_unit_cost is null or actual_unit_cost>=0), currency text check(currency is null or currency ~ '^[A-Z]{3}$'),
  created_at timestamptz not null default now(), unique(organization_id,id), unique(organization_id,stock_receipt_id,line_no),
  check(accepted_quantity+damaged_quantity+quarantined_quantity<=received_quantity),
  foreign key (organization_id,stock_receipt_id) references public.e10_stock_receipts(organization_id,id) on delete cascade,
  foreign key (organization_id,configuration_version_id) references public.e10_product_configuration_versions(organization_id,id)
);

create table public.e10_supplier_credits (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.e10_organizations(id), supplier_id uuid not null,
  supplier_document_number text, revision integer not null default 1 check(revision>0), status text not null default 'draft'
    check(status in ('draft','reviewed','approved','void')),
  currency text not null check(currency ~ '^[A-Z]{3}$'), document_date date, total_amount numeric not null check(total_amount>=0),
  source_connection text, external_document_id text, payload_fingerprint text,
  created_by uuid default auth.uid() references auth.users(id), created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unique(organization_id,id), foreign key (organization_id,supplier_id) references public.e10_suppliers(organization_id,id),
  check ((source_connection is null and external_document_id is null) or (source_connection is not null and external_document_id is not null and payload_fingerprint is not null))
);
create unique index e10_supplier_credits_source_uq on public.e10_supplier_credits(organization_id,source_connection,external_document_id) where source_connection is not null;

create table public.e10_supplier_credit_lines (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.e10_organizations(id), supplier_credit_id uuid not null,
  line_no integer not null check(line_no>0), description text, line_amount numeric not null check(line_amount>=0),
  created_at timestamptz not null default now(), unique(organization_id,id), unique(organization_id,supplier_credit_id,line_no),
  foreign key (organization_id,supplier_credit_id) references public.e10_supplier_credits(organization_id,id) on delete cascade
);

create table public.e10_invoice_po_allocations (
  organization_id uuid not null, invoice_line_id uuid not null, purchase_order_line_id uuid not null,
  allocated_quantity numeric not null check(allocated_quantity>0), created_at timestamptz not null default now(),
  primary key(organization_id,invoice_line_id,purchase_order_line_id),
  foreign key (organization_id,invoice_line_id) references public.e10_supplier_invoice_lines(organization_id,id) on delete cascade,
  foreign key (organization_id,purchase_order_line_id) references public.e10_purchase_order_lines(organization_id,id)
);
create table public.e10_receipt_po_allocations (
  organization_id uuid not null, receipt_line_id uuid not null, purchase_order_line_id uuid not null,
  allocated_quantity numeric not null check(allocated_quantity>0), created_at timestamptz not null default now(),
  primary key(organization_id,receipt_line_id,purchase_order_line_id),
  foreign key (organization_id,receipt_line_id) references public.e10_stock_receipt_lines(organization_id,id) on delete cascade,
  foreign key (organization_id,purchase_order_line_id) references public.e10_purchase_order_lines(organization_id,id)
);
create table public.e10_receipt_invoice_allocations (
  organization_id uuid not null, receipt_line_id uuid not null, invoice_line_id uuid not null,
  allocated_quantity numeric not null check(allocated_quantity>0), created_at timestamptz not null default now(),
  primary key(organization_id,receipt_line_id,invoice_line_id),
  foreign key (organization_id,receipt_line_id) references public.e10_stock_receipt_lines(organization_id,id) on delete cascade,
  foreign key (organization_id,invoice_line_id) references public.e10_supplier_invoice_lines(organization_id,id)
);
create table public.e10_credit_invoice_allocations (
  organization_id uuid not null, credit_line_id uuid not null, invoice_line_id uuid not null,
  allocated_amount numeric not null check(allocated_amount>0), created_at timestamptz not null default now(),
  primary key(organization_id,credit_line_id,invoice_line_id),
  foreign key (organization_id,credit_line_id) references public.e10_supplier_credit_lines(organization_id,id) on delete cascade,
  foreign key (organization_id,invoice_line_id) references public.e10_supplier_invoice_lines(organization_id,id)
);

create table public.e10_commercial_comments (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.e10_organizations(id),
  audience text not null check(audience in ('internal','vendor')), body text not null check(btrim(body)<>''),
  purchase_order_id uuid, supplier_invoice_id uuid, stock_receipt_id uuid, supplier_credit_id uuid,
  supersedes_comment_id uuid, created_by uuid not null default auth.uid() references auth.users(id), created_at timestamptz not null default now(),
  unique(organization_id,id),
  check(num_nonnulls(purchase_order_id,supplier_invoice_id,stock_receipt_id,supplier_credit_id)=1),
  foreign key (organization_id,purchase_order_id) references public.e10_purchase_orders(organization_id,id),
  foreign key (organization_id,supplier_invoice_id) references public.e10_supplier_invoices(organization_id,id),
  foreign key (organization_id,stock_receipt_id) references public.e10_stock_receipts(organization_id,id),
  foreign key (organization_id,supplier_credit_id) references public.e10_supplier_credits(organization_id,id),
  foreign key (organization_id,supersedes_comment_id) references public.e10_commercial_comments(organization_id,id)
);
create index e10_commercial_comments_po_idx on public.e10_commercial_comments(organization_id,purchase_order_id,created_at,id) where purchase_order_id is not null;
create index e10_commercial_comments_invoice_idx on public.e10_commercial_comments(organization_id,supplier_invoice_id,created_at,id) where supplier_invoice_id is not null;

create or replace function e10.reject_append_only_change() returns trigger
language plpgsql set search_path=public as $$
begin
  raise exception using errcode='55000',message=tg_table_name||'_is_append_only';
end;
$$;
revoke all on function e10.reject_append_only_change() from public,anon,authenticated;
grant execute on function e10.reject_append_only_change() to service_role;
create trigger e10_commercial_comments_append_only_trg
  before update or delete on public.e10_commercial_comments
  for each row execute function e10.reject_append_only_change();

do $$ declare t text; begin
  foreach t in array array['e10_purchase_orders','e10_purchase_order_lines','e10_supplier_invoices','e10_supplier_invoice_lines','e10_stock_receipts','e10_stock_receipt_lines','e10_supplier_credits','e10_supplier_credit_lines','e10_invoice_po_allocations','e10_receipt_po_allocations','e10_receipt_invoice_allocations','e10_credit_invoice_allocations','e10_commercial_comments'] loop
    execute format('alter table public.%I enable row level security',t);
    execute format('revoke all on table public.%I from public,anon,authenticated',t);
    execute format('grant all on table public.%I to service_role',t);
  end loop;
end $$;

-- Operational headers expose no costs; same-org members may read them directly.
create policy e10_purchase_orders_sel on public.e10_purchase_orders for select to authenticated using(e10.is_org_member(organization_id));
create policy e10_stock_receipts_sel on public.e10_stock_receipts for select to authenticated using(e10.is_org_member(organization_id));
grant select on public.e10_purchase_orders,public.e10_stock_receipts to authenticated;

-- Cost-bearing documents and allocations require the approved financial-read capability.
do $$ declare t text; begin
  foreach t in array array['e10_purchase_order_lines','e10_supplier_invoices','e10_supplier_invoice_lines','e10_stock_receipt_lines','e10_supplier_credits','e10_supplier_credit_lines','e10_invoice_po_allocations','e10_receipt_po_allocations','e10_receipt_invoice_allocations','e10_credit_invoice_allocations'] loop
    execute format('create policy %I on public.%I for select to authenticated using (e10.has_org_cap(organization_id,%L))',t||'_financial_sel',t,'act.view_financial_estimates');
    execute format('grant select on table public.%I to authenticated',t);
  end loop;
end $$;

-- Comments remain server-only until an audience-safe workflow projection is added in TA-X3b.

comment on table public.e10_stock_receipts is 'Physical receipt is separate from invoice approval and payment.';
comment on table public.e10_commercial_comments is 'Append-only audience-separated purchasing comments; vendor output must select audience=vendor explicitly.';
