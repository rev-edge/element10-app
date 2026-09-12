-- Schema-review checkpoint 2: governed, typed organization custom fields.
-- Raw source JSON remains unchanged. No field is promoted or backfilled here.

create table public.e10_custom_field_definitions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.e10_organizations(id),
  object_type text not null check(object_type in(
    'catalog_variant','checklist','inventory_item','unique_item','product_master',
    'product_configuration','product_configuration_version','customer','supplier','location')),
  field_key text not null check(field_key ~ '^[a-z][a-z0-9_]{0,62}$'),
  display_label text not null check(length(btrim(display_label)) between 1 and 100),
  data_type text not null check(data_type in('text','numeric','boolean','date','timestamp','term')),
  unit text check(unit is null or length(btrim(unit)) between 1 and 40),
  cardinality text not null default 'single' check(cardinality in('single','multiple')),
  index_mode text not null default 'none' check(index_mode in('none','exact','range')),
  read_capability text check(read_capability is null or read_capability ~ '^[a-z][a-z0-9_.]{0,99}$'),
  write_capability text check(write_capability is null or write_capability ~ '^[a-z][a-z0-9_.]{0,99}$'),
  status text not null default 'active' check(status in('active','retired')),
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique(organization_id,id),
  unique(organization_id,object_type,field_key),
  check((data_type='numeric')=(unit is not null) or unit is null),
  check(index_mode<>'range' or data_type in('numeric','date','timestamp'))
);

create table public.e10_custom_field_terms (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  field_definition_id uuid not null,
  term_key text not null check(term_key ~ '^[a-z0-9][a-z0-9_-]{0,62}$'),
  display_label text not null check(length(btrim(display_label)) between 1 and 100),
  status text not null default 'active' check(status in('active','retired')),
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique(organization_id,id),
  unique(organization_id,field_definition_id,term_key),
  foreign key(organization_id,field_definition_id)
    references public.e10_custom_field_definitions(organization_id,id) on delete restrict
);

create table public.e10_custom_field_values (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  field_definition_id uuid not null,
  object_type text not null,
  object_id text not null check(length(btrim(object_id)) between 1 and 200),
  position integer not null default 1 check(position>0),
  value_text text,
  value_numeric numeric,
  value_boolean boolean,
  value_date date,
  value_timestamp timestamptz,
  value_term_id uuid,
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamptz not null default clock_timestamp(),
  updated_by uuid default auth.uid() references auth.users(id) on delete set null,
  updated_at timestamptz not null default clock_timestamp(),
  unique(organization_id,id),
  unique(organization_id,field_definition_id,object_type,object_id,position),
  foreign key(organization_id,field_definition_id)
    references public.e10_custom_field_definitions(organization_id,id) on delete restrict,
  foreign key(organization_id,value_term_id)
    references public.e10_custom_field_terms(organization_id,id) on delete restrict,
  check(num_nonnulls(value_text,value_numeric,value_boolean,value_date,value_timestamp,value_term_id)=1)
);

create index e10_custom_field_values_object_idx
  on public.e10_custom_field_values(organization_id,object_type,object_id,field_definition_id,position);
create index e10_custom_field_values_text_idx
  on public.e10_custom_field_values(organization_id,field_definition_id,value_text,object_id)
  where value_text is not null;
create index e10_custom_field_values_numeric_idx
  on public.e10_custom_field_values(organization_id,field_definition_id,value_numeric,object_id)
  where value_numeric is not null;
create index e10_custom_field_values_boolean_idx
  on public.e10_custom_field_values(organization_id,field_definition_id,value_boolean,object_id)
  where value_boolean is not null;
create index e10_custom_field_values_date_idx
  on public.e10_custom_field_values(organization_id,field_definition_id,value_date,object_id)
  where value_date is not null;
create index e10_custom_field_values_timestamp_idx
  on public.e10_custom_field_values(organization_id,field_definition_id,value_timestamp,object_id)
  where value_timestamp is not null;
create index e10_custom_field_values_term_idx
  on public.e10_custom_field_values(organization_id,field_definition_id,value_term_id,object_id)
  where value_term_id is not null;

create function e10.custom_field_object_exists(p_org uuid,p_type text,p_id text)
returns boolean language plpgsql stable security definer set search_path=public as $$
declare v_uuid uuid;
begin
  if p_type='inventory_item' then return exists(select 1 from public.e10_inventory_items where organization_id=p_org and id=p_id);end if;
  begin v_uuid:=p_id::uuid; exception when invalid_text_representation then return false;end;
  case p_type
    when 'catalog_variant' then return exists(select 1 from public.e10_catalog_variants where id=v_uuid);
    when 'checklist' then return exists(select 1 from public.e10_checklists where id=v_uuid);
    when 'unique_item' then return exists(select 1 from public.e10_unique_items where organization_id=p_org and id=v_uuid);
    when 'product_master' then return exists(select 1 from public.e10_product_masters where organization_id=p_org and id=v_uuid);
    when 'product_configuration' then return exists(select 1 from public.e10_product_configurations where organization_id=p_org and id=v_uuid);
    when 'product_configuration_version' then return exists(select 1 from public.e10_product_configuration_versions where organization_id=p_org and id=v_uuid);
    when 'customer' then return exists(select 1 from public.e10_customers where organization_id=p_org and id=v_uuid);
    when 'supplier' then return exists(select 1 from public.e10_suppliers where organization_id=p_org and id=v_uuid);
    when 'location' then return exists(select 1 from public.e10_locations where organization_id=p_org and id=v_uuid);
    else return false;
  end case;
end $$;
revoke all on function e10.custom_field_object_exists(uuid,text,text) from public,anon,authenticated;
grant execute on function e10.custom_field_object_exists(uuid,text,text) to service_role;

create function e10.validate_custom_field_value() returns trigger
language plpgsql security definer set search_path=public as $$
declare d record;t record;
begin
  select * into d from public.e10_custom_field_definitions
  where organization_id=new.organization_id and id=new.field_definition_id and status='active' for share;
  if not found or d.object_type<>new.object_type then raise exception using errcode='23514',message='custom_field_definition_invalid';end if;
  if d.cardinality='single' and new.position<>1 then raise exception using errcode='23514',message='custom_field_single_position_invalid';end if;
  if not e10.custom_field_object_exists(new.organization_id,new.object_type,new.object_id) then raise exception using errcode='23503',message='custom_field_object_not_found';end if;
  if (d.data_type='text') is distinct from (new.value_text is not null)
    or (d.data_type='numeric') is distinct from (new.value_numeric is not null)
    or (d.data_type='boolean') is distinct from (new.value_boolean is not null)
    or (d.data_type='date') is distinct from (new.value_date is not null)
    or (d.data_type='timestamp') is distinct from (new.value_timestamp is not null)
    or (d.data_type='term') is distinct from (new.value_term_id is not null) then
    raise exception using errcode='23514',message='custom_field_value_type_mismatch';
  end if;
  if new.value_term_id is not null then
    select * into t from public.e10_custom_field_terms
    where organization_id=new.organization_id and field_definition_id=new.field_definition_id
      and id=new.value_term_id and status='active';
    if not found then raise exception using errcode='23514',message='custom_field_term_invalid';end if;
  end if;
  return new;
end $$;
revoke all on function e10.validate_custom_field_value() from public,anon,authenticated;
grant execute on function e10.validate_custom_field_value() to service_role;
create trigger e10_custom_field_values_guard before insert or update on public.e10_custom_field_values
  for each row execute function e10.validate_custom_field_value();

alter table public.e10_custom_field_definitions enable row level security;
alter table public.e10_custom_field_terms enable row level security;
alter table public.e10_custom_field_values enable row level security;
create policy e10_custom_field_definitions_sel on public.e10_custom_field_definitions for select to authenticated
  using(e10.is_org_member(organization_id) and (read_capability is null or e10.has_org_cap(organization_id,read_capability)));
create policy e10_custom_field_terms_sel on public.e10_custom_field_terms for select to authenticated
  using(exists(select 1 from public.e10_custom_field_definitions d where d.organization_id=e10_custom_field_terms.organization_id and d.id=field_definition_id));
create policy e10_custom_field_values_sel on public.e10_custom_field_values for select to authenticated
  using(exists(select 1 from public.e10_custom_field_definitions d where d.organization_id=e10_custom_field_values.organization_id and d.id=field_definition_id));
revoke all on public.e10_custom_field_definitions,public.e10_custom_field_terms,public.e10_custom_field_values from public,anon,authenticated;
grant select on public.e10_custom_field_definitions,public.e10_custom_field_terms,public.e10_custom_field_values to authenticated;
grant all on public.e10_custom_field_definitions,public.e10_custom_field_terms,public.e10_custom_field_values to service_role;

create function public.e10_org_define_custom_field(
  p_org uuid,p_object_type text,p_field_key text,p_display_label text,p_data_type text,
  p_unit text default null,p_cardinality text default 'single',p_index_mode text default 'none',
  p_read_capability text default null,p_write_capability text default null
) returns uuid language plpgsql security definer set search_path=public as $$
declare v_id uuid;v_actor uuid:=auth.uid();
begin
  if v_actor is null or not e10.is_org_admin(p_org) or not e10.has_org_cap(p_org,'act.permissions_config') then
    raise exception using errcode='42501',message='custom_field_definition_denied';end if;
  insert into public.e10_custom_field_definitions(
    organization_id,object_type,field_key,display_label,data_type,unit,cardinality,index_mode,
    read_capability,write_capability,created_by)
  values(p_org,p_object_type,btrim(p_field_key),btrim(p_display_label),p_data_type,nullif(btrim(p_unit),''),
    p_cardinality,p_index_mode,p_read_capability,p_write_capability,v_actor) returning id into v_id;
  return v_id;
end $$;

create function public.e10_org_add_custom_field_term(
  p_org uuid,p_definition uuid,p_term_key text,p_display_label text
) returns uuid language plpgsql security definer set search_path=public as $$
declare v_id uuid;v_actor uuid:=auth.uid();
begin
  if v_actor is null or not e10.is_org_admin(p_org) or not e10.has_org_cap(p_org,'act.permissions_config') then
    raise exception using errcode='42501',message='custom_field_definition_denied';end if;
  if not exists(select 1 from public.e10_custom_field_definitions where organization_id=p_org and id=p_definition and data_type='term' and status='active') then
    raise exception using errcode='22023',message='custom_field_term_definition_invalid';end if;
  insert into public.e10_custom_field_terms(organization_id,field_definition_id,term_key,display_label,created_by)
  values(p_org,p_definition,btrim(p_term_key),btrim(p_display_label),v_actor) returning id into v_id;
  return v_id;
end $$;

create function public.e10_org_set_custom_field_value(
  p_org uuid,p_definition uuid,p_object_id text,p_position integer,p_value jsonb
) returns uuid language plpgsql security definer set search_path=public as $$
declare d record;v_id uuid;v_actor uuid:=auth.uid();v_term uuid;
begin
  select * into d from public.e10_custom_field_definitions where organization_id=p_org and id=p_definition and status='active';
  if not found then raise exception using errcode='22023',message='custom_field_definition_invalid';end if;
  if v_actor is null or not e10.is_org_member(p_org)
    or (case when d.write_capability is null then not e10.is_org_admin(p_org) else not e10.has_org_cap(p_org,d.write_capability) end) then
    raise exception using errcode='42501',message='custom_field_value_write_denied';end if;
  if p_value is null or p_value='null'::jsonb then raise exception using errcode='22023',message='custom_field_value_required';end if;
  if d.data_type='term' then
    select id into v_term from public.e10_custom_field_terms
    where organization_id=p_org and field_definition_id=p_definition and term_key=p_value#>>'{}' and status='active';
    if not found then raise exception using errcode='22023',message='custom_field_term_invalid';end if;
  end if;
  insert into public.e10_custom_field_values(
    organization_id,field_definition_id,object_type,object_id,position,
    value_text,value_numeric,value_boolean,value_date,value_timestamp,value_term_id,created_by,updated_by)
  values(p_org,p_definition,d.object_type,btrim(p_object_id),coalesce(p_position,1),
    case when d.data_type='text' then p_value#>>'{}' end,
    case when d.data_type='numeric' then (p_value#>>'{}')::numeric end,
    case when d.data_type='boolean' then (p_value#>>'{}')::boolean end,
    case when d.data_type='date' then (p_value#>>'{}')::date end,
    case when d.data_type='timestamp' then (p_value#>>'{}')::timestamptz end,
    v_term,v_actor,v_actor)
  on conflict(organization_id,field_definition_id,object_type,object_id,position) do update set
    value_text=excluded.value_text,value_numeric=excluded.value_numeric,value_boolean=excluded.value_boolean,
    value_date=excluded.value_date,value_timestamp=excluded.value_timestamp,value_term_id=excluded.value_term_id,
    updated_by=v_actor,updated_at=clock_timestamp()
  returning id into v_id;
  return v_id;
end $$;

do $$declare f regprocedure;begin
  foreach f in array array[
    'public.e10_org_define_custom_field(uuid,text,text,text,text,text,text,text,text,text)'::regprocedure,
    'public.e10_org_add_custom_field_term(uuid,uuid,text,text)'::regprocedure,
    'public.e10_org_set_custom_field_value(uuid,uuid,text,integer,jsonb)'::regprocedure
  ] loop execute format('revoke all on function %s from public,anon',f);execute format('grant execute on function %s to authenticated,service_role',f);end loop;
end $$;
