-- TA-X3b immutable commercial-document revision history.
-- This is storage foundation only. It grants no document mutation authority.

create table public.e10_purchase_order_revisions (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.e10_organizations(id),
  purchase_order_id uuid not null, revision integer not null check(revision>0), status text not null,
  snapshot jsonb not null check(jsonb_typeof(snapshot)='object'), payload_fingerprint text not null check(btrim(payload_fingerprint)<>''),
  change_reason text, created_by uuid references auth.users(id), created_at timestamptz not null default now(),
  unique(organization_id,id), unique(organization_id,purchase_order_id,revision),
  foreign key(organization_id,purchase_order_id) references public.e10_purchase_orders(organization_id,id)
);

create table public.e10_supplier_invoice_revisions (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.e10_organizations(id),
  supplier_invoice_id uuid not null, revision integer not null check(revision>0), status text not null,
  snapshot jsonb not null check(jsonb_typeof(snapshot)='object'), payload_fingerprint text not null check(btrim(payload_fingerprint)<>''),
  change_reason text, created_by uuid references auth.users(id), created_at timestamptz not null default now(),
  unique(organization_id,id), unique(organization_id,supplier_invoice_id,revision),
  foreign key(organization_id,supplier_invoice_id) references public.e10_supplier_invoices(organization_id,id)
);

create table public.e10_stock_receipt_revisions (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.e10_organizations(id),
  stock_receipt_id uuid not null, revision integer not null check(revision>0), status text not null,
  snapshot jsonb not null check(jsonb_typeof(snapshot)='object'), payload_fingerprint text not null check(btrim(payload_fingerprint)<>''),
  change_reason text, created_by uuid references auth.users(id), created_at timestamptz not null default now(),
  unique(organization_id,id), unique(organization_id,stock_receipt_id,revision),
  foreign key(organization_id,stock_receipt_id) references public.e10_stock_receipts(organization_id,id)
);

create table public.e10_supplier_credit_revisions (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.e10_organizations(id),
  supplier_credit_id uuid not null, revision integer not null check(revision>0), status text not null,
  snapshot jsonb not null check(jsonb_typeof(snapshot)='object'), payload_fingerprint text not null check(btrim(payload_fingerprint)<>''),
  change_reason text, created_by uuid references auth.users(id), created_at timestamptz not null default now(),
  unique(organization_id,id), unique(organization_id,supplier_credit_id,revision),
  foreign key(organization_id,supplier_credit_id) references public.e10_supplier_credits(organization_id,id)
);

do $$ declare t text; begin
  foreach t in array array['e10_purchase_order_revisions','e10_supplier_invoice_revisions','e10_stock_receipt_revisions','e10_supplier_credit_revisions'] loop
    execute format('alter table public.%I enable row level security',t);
    execute format('revoke all on table public.%I from public,anon,authenticated',t);
    execute format('grant all on table public.%I to service_role',t);
    execute format('create trigger %I before update or delete on public.%I for each row execute function e10.reject_append_only_change()',t||'_append_only_trg',t);
  end loop;
end $$;

comment on table public.e10_purchase_order_revisions is 'Immutable PO snapshots. Writer authority and transitions are defined separately.';
comment on table public.e10_supplier_invoice_revisions is 'Immutable supplier-invoice snapshots; invoice approval does not create stock.';
comment on table public.e10_stock_receipt_revisions is 'Immutable physical-receipt snapshots; receipt remains distinct from invoice and payment.';
comment on table public.e10_supplier_credit_revisions is 'Immutable supplier-credit snapshots; accounting recognition remains separately governed.';
