-- TA-X4a lot and reservation foundation. No posting or allocation policy is implied.

create table public.e10_inventory_lots (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.e10_organizations(id),
  configuration_version_id uuid not null, location_id uuid not null, supplier_id uuid,
  stock_receipt_line_id uuid, lot_code text, status text not null default 'quarantined'
    check(status in ('quarantined','available','exhausted','reversed')),
  accepted_quantity numeric not null default 0 check(accepted_quantity>=0),
  quarantined_quantity numeric not null default 0 check(quarantined_quantity>=0),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unique(organization_id,id),
  foreign key(organization_id,configuration_version_id) references public.e10_product_configuration_versions(organization_id,id),
  foreign key(organization_id,location_id) references public.e10_locations(organization_id,id),
  foreign key(organization_id,supplier_id) references public.e10_suppliers(organization_id,id),
  foreign key(organization_id,stock_receipt_line_id) references public.e10_stock_receipt_lines(organization_id,id),
  check(status<>'available' or accepted_quantity>0)
);
create unique index e10_inventory_lots_org_code_uq on public.e10_inventory_lots(organization_id,lower(btrim(lot_code))) where lot_code is not null and btrim(lot_code)<>'';
create index e10_inventory_lots_org_config_location_idx on public.e10_inventory_lots(organization_id,configuration_version_id,location_id,status,id);

create table public.e10_lot_cost_evidence (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.e10_organizations(id),
  lot_id uuid not null, evidence_kind text not null check(evidence_kind in ('purchase','freight','duty','tax','fee','adjustment')),
  amount numeric not null, currency text not null check(currency ~ '^[A-Z]{3}$'),
  supplier_invoice_line_id uuid, stock_receipt_line_id uuid, source_note text,
  occurred_at timestamptz not null, created_by uuid references auth.users(id), created_at timestamptz not null default now(),
  unique(organization_id,id),
  foreign key(organization_id,lot_id) references public.e10_inventory_lots(organization_id,id),
  foreign key(organization_id,supplier_invoice_line_id) references public.e10_supplier_invoice_lines(organization_id,id),
  foreign key(organization_id,stock_receipt_line_id) references public.e10_stock_receipt_lines(organization_id,id),
  check(num_nonnulls(supplier_invoice_line_id,stock_receipt_line_id)>0 or source_note is not null)
);
create index e10_lot_cost_evidence_lot_time_idx on public.e10_lot_cost_evidence(organization_id,lot_id,occurred_at desc,id);

create table public.e10_expected_inventory_allocations (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.e10_organizations(id),
  purchase_order_line_id uuid not null, destination_location_id uuid not null,
  expected_quantity numeric not null check(expected_quantity>0),
  status text not null default 'open' check(status in ('open','fulfilled','cancelled')),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unique(organization_id,id),
  foreign key(organization_id,purchase_order_line_id) references public.e10_purchase_order_lines(organization_id,id),
  foreign key(organization_id,destination_location_id) references public.e10_locations(organization_id,id)
);
create index e10_expected_inventory_allocations_po_idx on public.e10_expected_inventory_allocations(organization_id,purchase_order_line_id,status,id);

create table public.e10_lot_reservations (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.e10_organizations(id),
  lot_id uuid not null, quantity numeric not null check(quantity>0),
  source_type text not null check(source_type in ('break_session','sale_order','manual')),
  source_id text not null check(btrim(source_id)<>''),
  status text not null default 'active' check(status in ('active','released','consumed','reversed')),
  idempotency_key text not null check(btrim(idempotency_key)<>''),
  created_by uuid references auth.users(id), created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unique(organization_id,id), unique(organization_id,idempotency_key),
  foreign key(organization_id,lot_id) references public.e10_inventory_lots(organization_id,id)
);
create index e10_lot_reservations_lot_status_idx on public.e10_lot_reservations(organization_id,lot_id,status,id);
create unique index e10_lot_reservations_active_source_uq on public.e10_lot_reservations(organization_id,lot_id,source_type,source_id) where status='active';

create trigger e10_lot_cost_evidence_append_only_trg before update or delete on public.e10_lot_cost_evidence
  for each row execute function e10.reject_append_only_change();

do $$ declare t text; begin
  foreach t in array array['e10_inventory_lots','e10_lot_cost_evidence','e10_expected_inventory_allocations','e10_lot_reservations'] loop
    execute format('alter table public.%I enable row level security',t);
    execute format('revoke all on table public.%I from public,anon,authenticated',t);
    execute format('grant all on table public.%I to service_role',t);
  end loop;
end $$;

comment on table public.e10_lot_cost_evidence is 'Raw immutable cost evidence only. No landed-cost allocation method or derived unit cost is implied.';
comment on table public.e10_lot_reservations is 'Lot-backed reservation records. Availability and no-overcommit are enforced only by a later reviewed locking writer.';
