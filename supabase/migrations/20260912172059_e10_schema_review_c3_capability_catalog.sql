-- Schema-review checkpoint 3: governed capability vocabulary.
-- Existing text keys and composite permission identity remain byte-compatible.

create table public.e10_capabilities(
  id uuid primary key default gen_random_uuid(),
  capability_key text not null unique check(capability_key ~ '^[a-z][a-z0-9_.]{1,99}$'),
  owning_module text not null check(owning_module in('core','inventory','reporting','schedule','settings','toolkit','catalog','customers','purchasing','receiving','platform')),
  operation_group text not null check(length(btrim(operation_group)) between 1 and 100),
  sensitivity text not null check(sensitivity in('ordinary','sensitive','restricted')),
  authority_scope text not null check(authority_scope in('organization','platform')),
  status text not null default 'active' check(status in('active','deprecated','retired')),
  replacement_capability_id uuid references public.e10_capabilities(id),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  check((status='deprecated')=(replacement_capability_id is not null)),
  check(replacement_capability_id is null or replacement_capability_id<>id)
);

insert into public.e10_capabilities(capability_key,owning_module,operation_group,sensitivity,authority_scope)
select capability,
  case when capability like'mod.%'then'core'
       when capability like'financial.%'then'purchasing'
       when capability like'act.view_market%'or capability like'act.curate_market%'then'reporting'
       when capability like'act.purchasing%'then'purchasing'
       when capability like'act.%customer%'or capability like'act.%attendance%'then'customers'
       when capability like'act.%inventory%'or capability in('act.create_receiving','act.reserve_inventory')then'inventory'
       when capability like'act.%schedule%'or capability='act.create_session'then'schedule'
       else'core'end,
  case when capability like'mod.%'then'navigation'else split_part(capability,'.',2)end,
  case when capability like'financial.%'or capability like'%approve%'or capability like'%permissions%'then'restricted'
       when capability like'%customer%'or capability like'%receiv%'then'sensitive'else'ordinary'end,
  'organization'
from(select distinct capability from public.e10_organization_role_permissions)s;

insert into public.e10_capabilities(capability_key,owning_module,operation_group,sensitivity,authority_scope) values
('act.adjust_customer_transactions','customers','customer_transactions','sensitive','organization'),
('act.approve_customer_transactions','customers','customer_transactions','restricted','organization'),
('act.configure_attendance_normalization','customers','attendance','restricted','organization'),
('act.correct_customer_attribution','customers','customer_identity','sensitive','organization'),
('act.curate_market_analytics','reporting','market_analytics','restricted','organization'),
('act.manage_attendance_coverage','customers','attendance','restricted','organization'),
('act.manage_customers','customers','customer_identity','sensitive','organization'),
('act.manage_intake','inventory','intake','sensitive','organization'),
('act.merge_customers','customers','customer_identity','restricted','organization'),
('act.post_customer_transactions','customers','customer_transactions','restricted','organization'),
('act.prepare_customer_transactions','customers','customer_transactions','sensitive','organization'),
('act.purchasing_approve','purchasing','purchasing_documents','restricted','organization'),
('act.purchasing_cancel','purchasing','purchasing_documents','restricted','organization'),
('act.purchasing_prepare','purchasing','purchasing_documents','sensitive','organization'),
('act.reconcile_customer_transactions','customers','customer_transactions','restricted','organization'),
('act.record_commercial_events','customers','commercial_events','sensitive','organization'),
('act.view_customer_engagement','customers','customer_reporting','sensitive','organization'),
('act.view_customer_financials','customers','customer_reporting','restricted','organization'),
('act.view_market_analytics','reporting','market_analytics','sensitive','organization'),
('financial.actual_cost.read','purchasing','actual_cost','restricted','organization'),
('receiving.over_accept','receiving','over_receipt','restricted','organization'),
('catalog.read','catalog','catalog','ordinary','organization'),
('catalog.propose','catalog','catalog_curation','sensitive','organization'),
('catalog.review','platform','catalog_curation','restricted','platform'),
('catalog.publish','platform','catalog_curation','restricted','platform'),
('custom_fields.read','core','custom_fields','sensitive','organization'),
('custom_fields.write','core','custom_fields','sensitive','organization')
on conflict(capability_key)do update set
  owning_module=excluded.owning_module,operation_group=excluded.operation_group,
  sensitivity=excluded.sensitivity,authority_scope=excluded.authority_scope;

alter table public.e10_organization_role_permissions
  add constraint e10_organization_role_permissions_capability_fkey
  foreign key(capability)references public.e10_capabilities(capability_key) not valid;
alter table public.e10_organization_role_permissions
  validate constraint e10_organization_role_permissions_capability_fkey;

alter table public.e10_custom_field_definitions
  add constraint e10_custom_field_definitions_read_capability_fkey
  foreign key(read_capability)references public.e10_capabilities(capability_key) not valid,
  add constraint e10_custom_field_definitions_write_capability_fkey
  foreign key(write_capability)references public.e10_capabilities(capability_key) not valid;
alter table public.e10_custom_field_definitions
  validate constraint e10_custom_field_definitions_read_capability_fkey;
alter table public.e10_custom_field_definitions
  validate constraint e10_custom_field_definitions_write_capability_fkey;

create function e10.validate_org_capability_grant()returns trigger
language plpgsql security definer set search_path=public as $$
begin
  if not exists(select 1 from public.e10_capabilities c where c.capability_key=new.capability and c.authority_scope='organization'and c.status='active')then
    raise exception using errcode='23514',message='organization_capability_not_grantable';end if;
  return new;
end $$;
revoke all on function e10.validate_org_capability_grant()from public,anon,authenticated;
grant execute on function e10.validate_org_capability_grant()to service_role;
create trigger e10_organization_role_permissions_capability_guard
  before insert or update of capability on public.e10_organization_role_permissions
  for each row execute function e10.validate_org_capability_grant();

alter table public.e10_capabilities enable row level security;
create policy e10_capabilities_sel on public.e10_capabilities for select to authenticated
  using(authority_scope='organization'or e10.is_platform_admin());
revoke all on public.e10_capabilities from public,anon,authenticated;
grant select on public.e10_capabilities to authenticated;
grant all on public.e10_capabilities to service_role;

comment on table public.e10_capabilities is
  'Governed operation capability vocabulary. Organization grants retain their natural composite key; platform operations cannot be granted through tenant roles.';
comment on column public.e10_organization_role_permissions.allowed is
  'Current administrative toggle. False rows are retained for UI/audit compatibility; missing and false both deny. This is not deny precedence across multiple roles.';
