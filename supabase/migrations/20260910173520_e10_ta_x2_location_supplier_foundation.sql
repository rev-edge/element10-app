-- TA-X2 location, supplier, and offering foundation. Additive staging/local work only.

create table public.e10_locations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.e10_organizations(id),
  code text,
  name text not null check (btrim(name) <> ''),
  status text not null default 'active' check (status in ('active','inactive','archived')),
  address jsonb not null default '{}'::jsonb,
  attrs jsonb not null default '{}'::jsonb,
  created_by uuid default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, id)
);
create unique index e10_locations_org_code_uq
  on public.e10_locations (organization_id, lower(btrim(code)))
  where code is not null and btrim(code) <> '';
create index e10_locations_org_status_name_idx
  on public.e10_locations (organization_id, status, lower(name), id);

create table public.e10_location_role_permissions (
  organization_id uuid not null,
  location_id uuid not null,
  role_id uuid not null,
  can_receive boolean not null default false,
  updated_by uuid references auth.users(id),
  updated_at timestamptz not null default now(),
  primary key (organization_id, location_id, role_id),
  constraint e10_location_role_permissions_org_location_fkey
    foreign key (organization_id, location_id)
    references public.e10_locations (organization_id, id) on delete cascade,
  constraint e10_location_role_permissions_org_role_fkey
    foreign key (organization_id, role_id)
    references public.e10_organization_roles (organization_id, id) on delete cascade
);
create index e10_location_role_permissions_role_idx
  on public.e10_location_role_permissions (organization_id, role_id, location_id)
  where can_receive;

create table public.e10_suppliers (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.e10_organizations(id),
  code text,
  name text not null check (btrim(name) <> ''),
  status text not null default 'active' check (status in ('active','inactive','archived')),
  contact jsonb not null default '{}'::jsonb,
  attrs jsonb not null default '{}'::jsonb,
  created_by uuid default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, id)
);
create unique index e10_suppliers_org_code_uq
  on public.e10_suppliers (organization_id, lower(btrim(code)))
  where code is not null and btrim(code) <> '';
create index e10_suppliers_org_status_name_idx
  on public.e10_suppliers (organization_id, status, lower(name), id);

create table public.e10_supplier_offerings (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.e10_organizations(id),
  supplier_id uuid not null,
  configuration_version_id uuid not null,
  vendor_item_code text,
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  status text not null default 'active' check (status in ('active','inactive','archived')),
  attrs jsonb not null default '{}'::jsonb,
  created_by uuid default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, id),
  constraint e10_supplier_offerings_org_supplier_fkey
    foreign key (organization_id, supplier_id)
    references public.e10_suppliers (organization_id, id),
  constraint e10_supplier_offerings_org_config_version_fkey
    foreign key (organization_id, configuration_version_id)
    references public.e10_product_configuration_versions (organization_id, id)
);
create unique index e10_supplier_offerings_vendor_code_uq
  on public.e10_supplier_offerings (organization_id, supplier_id, lower(btrim(vendor_item_code)))
  where vendor_item_code is not null and btrim(vendor_item_code) <> '';
create index e10_supplier_offerings_config_idx
  on public.e10_supplier_offerings (organization_id, configuration_version_id, supplier_id, id);

alter table public.e10_locations enable row level security;
alter table public.e10_location_role_permissions enable row level security;
alter table public.e10_suppliers enable row level security;
alter table public.e10_supplier_offerings enable row level security;

create policy e10_locations_sel on public.e10_locations for select to authenticated
  using (e10.is_org_member(organization_id));
create policy e10_location_role_permissions_sel on public.e10_location_role_permissions for select to authenticated
  using (e10.is_org_member(organization_id));
create policy e10_suppliers_sel on public.e10_suppliers for select to authenticated
  using (e10.is_org_member(organization_id));
create policy e10_supplier_offerings_sel on public.e10_supplier_offerings for select to authenticated
  using (e10.is_org_member(organization_id));

revoke all on table public.e10_locations from public, anon, authenticated;
revoke all on table public.e10_location_role_permissions from public, anon, authenticated;
revoke all on table public.e10_suppliers from public, anon, authenticated;
revoke all on table public.e10_supplier_offerings from public, anon, authenticated;
grant select on table public.e10_locations, public.e10_location_role_permissions,
  public.e10_suppliers, public.e10_supplier_offerings to authenticated;
grant all on table public.e10_locations, public.e10_location_role_permissions,
  public.e10_suppliers, public.e10_supplier_offerings to service_role;

create or replace function e10.can_receive_at(p_org uuid, p_location uuid)
returns boolean
language sql stable security definer set search_path=public as $$
  select e10.is_org_admin(p_org) or exists (
    select 1
    from public.e10_organization_memberships m
    join public.e10_location_role_permissions p
      on p.organization_id=m.organization_id and p.role_id=m.role_id
    join public.e10_locations l
      on l.organization_id=p.organization_id and l.id=p.location_id
    where m.organization_id=p_org
      and m.user_id=auth.uid()
      and m.status='active'
      and p.location_id=p_location
      and p.can_receive
      and l.status='active'
  );
$$;
revoke all on function e10.can_receive_at(uuid,uuid) from public, anon;
grant execute on function e10.can_receive_at(uuid,uuid) to authenticated, service_role;

create or replace function public.e10_org_purchase_destinations(
  p_org uuid,
  p_after_name text default null,
  p_after_id uuid default null,
  p_limit integer default 50
) returns table (
  id uuid,
  code text,
  name text,
  eligible_count bigint,
  sole_eligible boolean
)
language plpgsql stable security definer set search_path=public as $$
begin
  if not e10.is_org_member(p_org) then
    raise exception using errcode='42501', message='organization_access_denied';
  end if;
  if (p_after_name is null) <> (p_after_id is null) then
    raise exception using errcode='22023', message='cursor_requires_name_and_id';
  end if;
  return query
  with eligible as materialized (
    select l.id,l.code,l.name
    from public.e10_locations l
    where l.organization_id=p_org and l.status='active'
      and e10.can_receive_at(p_org,l.id)
  ), counted as (
    select e.*,count(*) over() as total
    from eligible e
  )
  select c.id,c.code,c.name,c.total,(c.total=1)
  from counted c
  where p_after_name is null or (lower(c.name),c.id) > (lower(p_after_name),p_after_id)
  order by lower(c.name),c.id
  limit least(greatest(coalesce(p_limit,50),1),100);
end;
$$;
revoke all on function public.e10_org_purchase_destinations(uuid,text,uuid,integer) from public, anon;
grant execute on function public.e10_org_purchase_destinations(uuid,text,uuid,integer) to authenticated, service_role;

comment on function public.e10_org_purchase_destinations(uuid,text,uuid,integer) is
  'Bounded authorized purchasing destinations. Free-text delivery descriptions do not replace returned location IDs.';
