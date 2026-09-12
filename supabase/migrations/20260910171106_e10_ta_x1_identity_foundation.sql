-- TA-X1 identity foundation. Additive staging/local work only.
-- Separates tenant commercial identity, immutable configuration versions,
-- platform catalog releases/variants, and organization-owned physical copies.
-- No legacy catalog or inventory row is rewritten by this migration.

create table public.e10_product_masters (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.e10_organizations(id),
  name text not null check (btrim(name) <> ''),
  internal_code text,
  status text not null default 'active' check (status in ('active','inactive','archived')),
  attrs jsonb not null default '{}'::jsonb,
  created_by uuid default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, id)
);
create unique index e10_product_masters_org_code_uq
  on public.e10_product_masters (organization_id, lower(btrim(internal_code)))
  where internal_code is not null and btrim(internal_code) <> '';
create index e10_product_masters_org_name_idx
  on public.e10_product_masters (organization_id, lower(name), id);

create table public.e10_product_configurations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.e10_organizations(id),
  product_master_id uuid not null,
  name text not null check (btrim(name) <> ''),
  internal_code text,
  status text not null default 'active' check (status in ('active','inactive','archived')),
  attrs jsonb not null default '{}'::jsonb,
  created_by uuid default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, id),
  constraint e10_product_configurations_org_product_fkey
    foreign key (organization_id, product_master_id)
    references public.e10_product_masters (organization_id, id)
);
create unique index e10_product_configurations_org_code_uq
  on public.e10_product_configurations (organization_id, lower(btrim(internal_code)))
  where internal_code is not null and btrim(internal_code) <> '';
create index e10_product_configurations_org_product_idx
  on public.e10_product_configurations (organization_id, product_master_id, id);

create table public.e10_product_configuration_versions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.e10_organizations(id),
  configuration_id uuid not null,
  version_no integer not null check (version_no > 0),
  state text not null default 'draft' check (state in ('draft','active','retired')),
  packaging_kind text not null check (btrim(packaging_kind) <> ''),
  base_unit text not null check (btrim(base_unit) <> ''),
  base_units_per_package numeric not null check (base_units_per_package > 0),
  barcode text,
  attrs jsonb not null default '{}'::jsonb,
  created_by uuid default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  unique (organization_id, id),
  unique (organization_id, configuration_id, version_no),
  constraint e10_product_configuration_versions_org_config_fkey
    foreign key (organization_id, configuration_id)
    references public.e10_product_configurations (organization_id, id)
);
create unique index e10_product_configuration_versions_org_barcode_uq
  on public.e10_product_configuration_versions (organization_id, lower(btrim(barcode)))
  where state = 'active' and barcode is not null and btrim(barcode) <> '';
create unique index e10_product_configuration_versions_one_active_uq
  on public.e10_product_configuration_versions (organization_id, configuration_id)
  where state = 'active';

create table public.e10_catalog_releases (
  id uuid primary key default gen_random_uuid(),
  legacy_set_id uuid references public.e10_sets(id) on delete set null,
  manufacturer text,
  brand_line text,
  release_name text not null check (btrim(release_name) <> ''),
  release_year integer,
  season text,
  sport text,
  language text,
  region text,
  edition text,
  attrs jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index e10_catalog_releases_lookup_idx
  on public.e10_catalog_releases (release_year, lower(release_name), id);

create table public.e10_catalog_variants (
  id uuid primary key default gen_random_uuid(),
  release_id uuid not null references public.e10_catalog_releases(id),
  legacy_card_id uuid references public.e10_cards(id) on delete set null,
  card_number text,
  exact_parallel text,
  color_family text,
  finish_pattern text,
  language text,
  edition text,
  rookie_designation boolean,
  print_run_denominator integer check (print_run_denominator is null or print_run_denominator > 0),
  attrs jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index e10_catalog_variants_release_lookup_idx
  on public.e10_catalog_variants (release_id, card_number, exact_parallel, id);
create index e10_catalog_variants_facets_idx
  on public.e10_catalog_variants (rookie_designation, color_family, finish_pattern, id);

create table public.e10_catalog_variant_subjects (
  variant_id uuid not null references public.e10_catalog_variants(id) on delete cascade,
  player_id uuid not null references public.e10_players(id),
  subject_role text not null default 'featured' check (btrim(subject_role) <> ''),
  position integer not null default 1 check (position > 0),
  primary key (variant_id, player_id),
  unique (variant_id, position)
);
create index e10_catalog_variant_subjects_player_idx
  on public.e10_catalog_variant_subjects (player_id, variant_id);

create table public.e10_catalog_identity_mappings (
  id uuid primary key default gen_random_uuid(),
  provider text not null check (btrim(provider) <> ''),
  entity_kind text not null check (entity_kind in ('player','release','variant')),
  external_id text not null check (btrim(external_id) <> ''),
  mapping_revision integer not null default 1 check (mapping_revision > 0),
  player_id uuid references public.e10_players(id),
  release_id uuid references public.e10_catalog_releases(id),
  variant_id uuid references public.e10_catalog_variants(id),
  match_status text not null check (match_status in ('verified','candidate','rejected','superseded')),
  is_current boolean not null default true,
  confidence numeric check (confidence is null or (confidence >= 0 and confidence <= 1)),
  source_payload jsonb not null default '{}'::jsonb,
  reviewed_by uuid references auth.users(id),
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  unique (provider, entity_kind, external_id, mapping_revision),
  constraint e10_catalog_identity_mappings_target_chk check (
    (entity_kind = 'player' and player_id is not null and release_id is null and variant_id is null)
    or (entity_kind = 'release' and player_id is null and release_id is not null and variant_id is null)
    or (entity_kind = 'variant' and player_id is null and release_id is null and variant_id is not null)
  ),
  constraint e10_catalog_identity_mappings_review_chk check (
    (match_status = 'verified' and reviewed_by is not null and reviewed_at is not null)
    or match_status <> 'verified'
  )
);
create unique index e10_catalog_identity_mappings_current_uq
  on public.e10_catalog_identity_mappings (provider, entity_kind, external_id)
  where is_current;
create index e10_catalog_identity_mappings_target_idx
  on public.e10_catalog_identity_mappings (entity_kind, player_id, release_id, variant_id, id);

create table public.e10_unique_items (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.e10_organizations(id),
  inventory_item_id text,
  catalog_variant_id uuid references public.e10_catalog_variants(id),
  item_kind text not null check (btrim(item_kind) <> ''),
  condition text,
  grading_company text,
  grade text,
  certification_number text,
  serial_numerator integer check (serial_numerator is null or serial_numerator > 0),
  observed_markings jsonb not null default '{}'::jsonb,
  attrs jsonb not null default '{}'::jsonb,
  created_by uuid default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, id),
  constraint e10_unique_items_org_inventory_fkey
    foreign key (organization_id, inventory_item_id)
    references public.e10_inventory_items (organization_id, id)
    on delete set null (inventory_item_id)
);
create unique index e10_unique_items_org_inventory_uq
  on public.e10_unique_items (organization_id, inventory_item_id)
  where inventory_item_id is not null;
create index e10_unique_items_org_variant_idx
  on public.e10_unique_items (organization_id, catalog_variant_id, id);

alter table public.e10_product_masters enable row level security;
alter table public.e10_product_configurations enable row level security;
alter table public.e10_product_configuration_versions enable row level security;
alter table public.e10_catalog_releases enable row level security;
alter table public.e10_catalog_variants enable row level security;
alter table public.e10_catalog_variant_subjects enable row level security;
alter table public.e10_catalog_identity_mappings enable row level security;
alter table public.e10_unique_items enable row level security;

create policy e10_product_masters_sel on public.e10_product_masters
  for select to authenticated using (e10.is_org_member(organization_id));
create policy e10_product_configurations_sel on public.e10_product_configurations
  for select to authenticated using (e10.is_org_member(organization_id));
create policy e10_product_configuration_versions_sel on public.e10_product_configuration_versions
  for select to authenticated using (e10.is_org_member(organization_id));
create policy e10_unique_items_sel on public.e10_unique_items
  for select to authenticated using (e10.is_org_member(organization_id));

create policy e10_catalog_releases_sel on public.e10_catalog_releases
  for select to authenticated using (e10.is_platform_admin() or e10.current_org() is not null);
create policy e10_catalog_variants_sel on public.e10_catalog_variants
  for select to authenticated using (e10.is_platform_admin() or e10.current_org() is not null);
create policy e10_catalog_variant_subjects_sel on public.e10_catalog_variant_subjects
  for select to authenticated using (e10.is_platform_admin() or e10.current_org() is not null);
create policy e10_catalog_identity_mappings_sel on public.e10_catalog_identity_mappings
  for select to authenticated using (e10.is_platform_admin() or e10.current_org() is not null);

revoke all on table public.e10_product_masters from public, anon, authenticated;
revoke all on table public.e10_product_configurations from public, anon, authenticated;
revoke all on table public.e10_product_configuration_versions from public, anon, authenticated;
revoke all on table public.e10_catalog_releases from public, anon, authenticated;
revoke all on table public.e10_catalog_variants from public, anon, authenticated;
revoke all on table public.e10_catalog_variant_subjects from public, anon, authenticated;
revoke all on table public.e10_catalog_identity_mappings from public, anon, authenticated;
revoke all on table public.e10_unique_items from public, anon, authenticated;

grant select on table public.e10_product_masters to authenticated;
grant select on table public.e10_product_configurations to authenticated;
grant select on table public.e10_product_configuration_versions to authenticated;
grant select on table public.e10_catalog_releases to authenticated;
grant select on table public.e10_catalog_variants to authenticated;
grant select on table public.e10_catalog_variant_subjects to authenticated;
grant select on table public.e10_catalog_identity_mappings to authenticated;
grant select on table public.e10_unique_items to authenticated;

grant all on table public.e10_product_masters to service_role;
grant all on table public.e10_product_configurations to service_role;
grant all on table public.e10_product_configuration_versions to service_role;
grant all on table public.e10_catalog_releases to service_role;
grant all on table public.e10_catalog_variants to service_role;
grant all on table public.e10_catalog_variant_subjects to service_role;
grant all on table public.e10_catalog_identity_mappings to service_role;
grant all on table public.e10_unique_items to service_role;

comment on table public.e10_catalog_variants is
  'Platform catalog variant identity. Physical-copy serial numerators and grades belong in e10_unique_items.';
comment on table public.e10_unique_items is
  'Organization-owned generic physical instance. Cards are optional through catalog_variant_id.';
