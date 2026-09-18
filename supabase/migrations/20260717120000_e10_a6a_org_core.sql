-- Foundation Gate A6a — org-core bootstrap (NEW objects only; STAGING/LOCAL, ZERO production changes at apply time).
-- Binding spec: docs/decisions/0005-tenant-spine.md rev 3.2.1. NO retrofit of existing tables here (no
-- organization_id columns, no stamp_org, no wrappers, no policy changes on existing tables — those are A6b/A6c).
-- Idempotent: applies cleanly twice (if-not-exists / on-conflict / create-or-replace / drop-policy-if-exists).
-- Functions are born private (A5.1a) and explicitly granted to `authenticated` only. Schema `e10` is NEVER added
-- to PostgREST's exposed schema list. Order: schema → tables → predicates → grants/RLS → RPCs → seeds
-- (predicates reference the tables, so the tables come first).
--
-- Tenant-zero pinned identifiers (recorded here + in docs):
--   org0 (organization):  e1000000-0000-4000-8000-0000000000a6
--   role admin:           e1000000-0000-4000-8000-000000000001
--   role manager:         e1000000-0000-4000-8000-000000000002
--   role streamer:        e1000000-0000-4000-8000-000000000003
--   role ops:             e1000000-0000-4000-8000-000000000004

-- ============================================================================
-- 1. Internal schema `e10` (non-REST-exposed)
-- ============================================================================
create schema if not exists e10;
grant usage on schema e10 to authenticated, service_role;

-- ============================================================================
-- 2. Org-core tables (§1 DDL — verbatim; if-not-exists for idempotency)
-- ============================================================================
create table if not exists public.e10_organizations (
  id uuid primary key default gen_random_uuid(),
  slug text unique not null check (slug ~ '^[a-z0-9-]{2,40}$'),
  name text not null,
  status text not null default 'active' check (status in ('active','suspended')),
  settings jsonb not null default '{}'::jsonb,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create table if not exists public.e10_organization_roles (
  organization_id uuid not null references public.e10_organizations(id) on delete cascade,
  id uuid not null default gen_random_uuid(),
  key text not null,
  name text not null,
  is_system boolean not null default false,
  created_at timestamptz not null default now(),
  primary key (organization_id, id),
  unique (organization_id, key)
);

create table if not exists public.e10_organization_role_permissions (
  organization_id uuid not null,
  role_id uuid not null,
  capability text not null,
  allowed boolean not null default true,
  updated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now(),
  primary key (organization_id, role_id, capability),
  foreign key (organization_id, role_id) references public.e10_organization_roles(organization_id, id) on delete cascade
);
create index if not exists e10_orp_org_cap_idx on public.e10_organization_role_permissions (organization_id, capability);

create table if not exists public.e10_organization_memberships (
  organization_id uuid not null references public.e10_organizations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role_id uuid not null,
  display_name text,
  status text not null default 'active' check (status in ('active','invited','suspended')),
  created_at timestamptz not null default now(),
  primary key (organization_id, user_id),
  foreign key (organization_id, role_id) references public.e10_organization_roles(organization_id, id)
);
create index if not exists e10_memberships_user_idx on public.e10_organization_memberships (user_id);
create index if not exists e10_memberships_role_idx on public.e10_organization_memberships (organization_id, role_id);

create table if not exists public.e10_organization_invitations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.e10_organizations(id) on delete cascade,
  email text not null,
  role_id uuid not null,
  token_hash text not null unique,
  invited_by uuid references auth.users(id) on delete set null,
  status text not null default 'pending' check (status in ('pending','accepted','revoked','expired')),
  expires_at timestamptz not null check (expires_at > created_at),
  created_at timestamptz not null default now(),
  foreign key (organization_id, role_id) references public.e10_organization_roles(organization_id, id)
);
create index if not exists e10_invitations_role_idx on public.e10_organization_invitations (organization_id, role_id);
create index if not exists e10_invitations_org_email_idx on public.e10_organization_invitations (organization_id, lower(email));

create table if not exists public.e10_organization_modules (
  organization_id uuid not null references public.e10_organizations(id) on delete cascade,
  module_key text not null check (module_key in ('core','cards')),
  enabled boolean not null default true,
  settings jsonb not null default '{}'::jsonb,
  primary key (organization_id, module_key)
);

create table if not exists public.e10_platform_admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

-- §6 handle-to-account verification (one canonical source; generated handle_norm; verified-only unique)
create table if not exists public.e10_viewer_handle_claims (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  whatnot_handle text not null,
  handle_norm text generated always as (lower(btrim(regexp_replace(whatnot_handle, '^@', '')))) stored,
  status text not null default 'pending' check (status in ('pending','verified','rejected')),
  evidence jsonb,
  verified_at timestamptz,
  expires_at timestamptz not null check (expires_at > created_at),
  created_at timestamptz not null default now()
);
create unique index if not exists e10_vhc_verified_handle on public.e10_viewer_handle_claims (handle_norm) where status = 'verified';
create index if not exists e10_vhc_user_idx on public.e10_viewer_handle_claims (user_id);

-- §7 live-session parent (org-scoped from birth; global unique(id) for the viewer/session lookup — blocker 3)
create table if not exists public.e10_live_sessions (
  organization_id uuid not null references public.e10_organizations(id) on delete cascade,
  id uuid not null default gen_random_uuid(),
  source_show_ref text,
  name text,
  status text not null default 'active' check (status in ('active','ended')),
  created_at timestamptz not null default now(),
  primary key (organization_id, id),
  unique (id)
);
create index if not exists e10_live_sessions_show_idx on public.e10_live_sessions (organization_id, source_show_ref);
create index if not exists e10_live_sessions_status_idx on public.e10_live_sessions (organization_id, status);

-- ============================================================================
-- 3. Predicate helpers in `e10` (§1.2) — SECURITY DEFINER, STABLE, pinned path. (Tables exist now.)
-- ============================================================================
create or replace function e10.is_platform_admin() returns boolean
  language sql stable security definer set search_path = public as $$
  select exists(select 1 from public.e10_platform_admins where user_id = auth.uid());
$$;

create or replace function e10.is_org_member(org uuid) returns boolean
  language sql stable security definer set search_path = public as $$
  select e10.is_platform_admin() or exists(
    select 1 from public.e10_organization_memberships m
    where m.organization_id = org and m.user_id = auth.uid() and m.status = 'active');
$$;

create or replace function e10.is_org_admin(org uuid) returns boolean
  language sql stable security definer set search_path = public as $$
  select e10.is_platform_admin() or exists(
    select 1 from public.e10_organization_memberships m
    join public.e10_organization_roles r on r.organization_id = m.organization_id and r.id = m.role_id
    where m.organization_id = org and m.user_id = auth.uid() and m.status = 'active' and r.key = 'admin');
$$;

create or replace function e10.has_org_cap(org uuid, cap text) returns boolean
  language sql stable security definer set search_path = public as $$
  select e10.is_platform_admin() or exists(
    select 1 from public.e10_organization_memberships m
    join public.e10_organization_role_permissions p
      on p.organization_id = m.organization_id and p.role_id = m.role_id
    where m.organization_id = org and m.user_id = auth.uid() and m.status = 'active'
      and p.capability = cap and p.allowed = true);
$$;

-- sole active membership → its org, else null (single-membership fast path)
create or replace function e10.current_org() returns uuid
  language sql stable security definer set search_path = public as $$
  select case when count(*) = 1 then (array_agg(m.organization_id))[1] end
  from public.e10_organization_memberships m
  where m.user_id = auth.uid() and m.status = 'active';
$$;

-- owning buyer: the slot's buyer_uid is the caller, OR its buyer_handle matches a VERIFIED handle claim.
create or replace function e10.owns_slot(slot uuid) returns boolean
  language sql stable security definer set search_path = public as $$
  select exists(
    select 1 from public.e10_break_slots s
    where s.id = slot and (
      s.buyer_uid = auth.uid()
      or (s.buyer_handle is not null and exists(
            select 1 from public.e10_viewer_handle_claims c
            where c.user_id = auth.uid() and c.status = 'verified'
              and c.handle_norm = lower(btrim(regexp_replace(s.buyer_handle, '^@', ''))))) ));
$$;

-- A6a INTERIM (approved deviation): the ADR-final gate is e10_break_sessions.visibility = 'published', a column
-- added in A6b (A6a must not touch e10_break_sessions). Until then: authenticated AND the session has been shared
-- (share_code present). No consumer exists in A6a (spectator projection + Broadcast are A9). A6b TIGHTENS to
-- `visibility = 'published'`.
create or replace function e10.can_spectate_session(sess uuid) returns boolean
  language sql stable security definer set search_path = public as $$
  select auth.uid() is not null and exists(
    select 1 from public.e10_break_sessions s where s.id = sess and s.share_code is not null);
$$;

do $$ declare fn text; begin
  for fn in select 'e10.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')'
            from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'e10'
  loop execute 'revoke all on function '||fn||' from anon, public'; execute 'grant execute on function '||fn||' to authenticated'; end loop;
end $$;

-- ============================================================================
-- 4. Grants + RLS (§1.2) — no direct DML to authenticated; SELECT via RLS; writes via SECURITY DEFINER RPCs.
-- ============================================================================
do $$ declare t text; begin
  foreach t in array array[
    'e10_organizations','e10_organization_roles','e10_organization_role_permissions','e10_organization_memberships',
    'e10_organization_invitations','e10_organization_modules','e10_platform_admins','e10_viewer_handle_claims','e10_live_sessions']
  loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
  end loop;
end $$;

-- platform_admins gets NO policy + NO select grant → deny-all (service-role/definer only).
grant select on public.e10_organizations, public.e10_organization_roles, public.e10_organization_role_permissions,
                public.e10_organization_memberships, public.e10_organization_invitations, public.e10_organization_modules,
                public.e10_viewer_handle_claims, public.e10_live_sessions to authenticated;

drop policy if exists e10_org_sel on public.e10_organizations;
create policy e10_org_sel on public.e10_organizations for select to authenticated using (e10.is_org_member(id));

drop policy if exists e10_roles_sel on public.e10_organization_roles;
create policy e10_roles_sel on public.e10_organization_roles for select to authenticated using (e10.is_org_member(organization_id));

drop policy if exists e10_orp_sel on public.e10_organization_role_permissions;
create policy e10_orp_sel on public.e10_organization_role_permissions for select to authenticated using (e10.is_org_member(organization_id));

drop policy if exists e10_mem_sel on public.e10_organization_memberships;
create policy e10_mem_sel on public.e10_organization_memberships for select to authenticated
  using (e10.is_org_member(organization_id) or user_id = (select auth.uid()));

drop policy if exists e10_inv_sel on public.e10_organization_invitations;
create policy e10_inv_sel on public.e10_organization_invitations for select to authenticated using (e10.is_org_admin(organization_id));

drop policy if exists e10_mod_sel on public.e10_organization_modules;
create policy e10_mod_sel on public.e10_organization_modules for select to authenticated using (e10.is_org_member(organization_id));

drop policy if exists e10_vhc_sel on public.e10_viewer_handle_claims;
create policy e10_vhc_sel on public.e10_viewer_handle_claims for select to authenticated
  using (user_id = (select auth.uid()) or e10.is_platform_admin());

drop policy if exists e10_ls_sel on public.e10_live_sessions;
create policy e10_ls_sel on public.e10_live_sessions for select to authenticated using (e10.is_org_member(organization_id));
-- e10_platform_admins: RLS enabled above, intentionally NO policy → deny-all.

-- ============================================================================
-- 5. Client RPCs shipped in A6a (public; SECURITY DEFINER; born private → granted authenticated only)
-- ============================================================================
create or replace function public.e10_org_role_clone(p_org uuid, p_src_role uuid, p_dst_role uuid)
  returns integer language plpgsql security definer set search_path = public as $$
declare n integer;
begin
  if not (e10.is_org_admin(p_org) and e10.has_org_cap(p_org, 'act.permissions_config')) then raise exception 'forbidden'; end if;
  if not exists(select 1 from e10_organization_roles where organization_id = p_org and id = p_src_role)
     or not exists(select 1 from e10_organization_roles where organization_id = p_org and id = p_dst_role) then raise exception 'role_not_in_org'; end if;
  insert into e10_organization_role_permissions(organization_id, role_id, capability, allowed, updated_by)
    select p_org, p_dst_role, capability, allowed, auth.uid()
    from e10_organization_role_permissions where organization_id = p_org and role_id = p_src_role
    on conflict (organization_id, role_id, capability) do update set allowed = excluded.allowed, updated_by = excluded.updated_by, updated_at = now();
  get diagnostics n = row_count; return n;
end $$;

create or replace function public.e10_claim_handle(p_handle text)
  returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_norm text;
begin
  if auth.uid() is null then raise exception 'auth_required'; end if;
  v_norm := lower(btrim(regexp_replace(p_handle, '^@', '')));
  if v_norm = '' then raise exception 'empty_handle'; end if;
  insert into e10_viewer_handle_claims(user_id, whatnot_handle, status, expires_at)
    values (auth.uid(), p_handle, 'pending', now() + interval '7 days') returning id into v_id;
  return v_id;
end $$;

create or replace function public.e10_verify_handle_claim(p_claim_id uuid)
  returns void language plpgsql security definer set search_path = public as $$
declare v_norm text;
begin
  if not e10.is_platform_admin() then raise exception 'forbidden'; end if;
  select handle_norm into v_norm from e10_viewer_handle_claims where id = p_claim_id and status = 'pending';
  if v_norm is null then raise exception 'claim_not_found_or_not_pending'; end if;
  perform pg_advisory_xact_lock(hashtext(v_norm));           -- §6 concurrency rule
  if exists(select 1 from e10_viewer_handle_claims where handle_norm = v_norm and status = 'verified') then raise exception 'handle_already_verified'; end if;
  update e10_viewer_handle_claims set status = 'verified', verified_at = now() where id = p_claim_id;
end $$;

create or replace function public.e10_reject_handle_claim(p_claim_id uuid)
  returns void language plpgsql security definer set search_path = public as $$
begin
  if not e10.is_platform_admin() then raise exception 'forbidden'; end if;
  update e10_viewer_handle_claims set status = 'rejected' where id = p_claim_id and status = 'pending';
end $$;

do $$ declare fn text; begin
  for fn in select 'public.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')'
            from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public' and p.proname in ('e10_org_role_clone','e10_claim_handle','e10_verify_handle_claim','e10_reject_handle_claim')
  loop execute 'revoke all on function '||fn||' from anon, public'; execute 'grant execute on function '||fn||' to authenticated'; end loop;
end $$;

-- ============================================================================
-- 6. BOOTSTRAP seeds (blocker-1: must exist before any A6b bridge). Idempotent. Org-independent parts seed on
--    every environment; member/platform-admin parts are DATA-DRIVEN from e10_members (populated on prod at A10;
--    empty on a bare local/staging until users are provisioned — proven on LOCAL, see the A6a report).
-- ============================================================================
insert into public.e10_organizations (id, slug, name)
  values ('e1000000-0000-4000-8000-0000000000a6', 'org-zero', 'Tenant Zero (Element 10)')
  on conflict (id) do nothing;

insert into public.e10_organization_roles (organization_id, id, key, name, is_system) values
  ('e1000000-0000-4000-8000-0000000000a6','e1000000-0000-4000-8000-000000000001','admin','Admin',true),
  ('e1000000-0000-4000-8000-0000000000a6','e1000000-0000-4000-8000-000000000002','manager','Manager',true),
  ('e1000000-0000-4000-8000-0000000000a6','e1000000-0000-4000-8000-000000000003','streamer','Streamer',true),
  ('e1000000-0000-4000-8000-0000000000a6','e1000000-0000-4000-8000-000000000004','ops','Operations Team Member',true)
  on conflict (organization_id, id) do nothing;

insert into public.e10_organization_modules (organization_id, module_key, enabled) values
  ('e1000000-0000-4000-8000-0000000000a6','core',true),
  ('e1000000-0000-4000-8000-0000000000a6','cards',true)
  on conflict (organization_id, module_key) do nothing;

-- Parity allow-grants: admin + manager get ALL 12 caps (tenant-zero's current admin/member both have every cap
-- today under the deny-list — the mapping preserves that exactly). streamer/ops get sensible-default subsets (no
-- current member maps to them). All concrete strings (§1.1).
insert into public.e10_organization_role_permissions (organization_id, role_id, capability, allowed)
select 'e1000000-0000-4000-8000-0000000000a6'::uuid, g.role_id, g.cap, true from (
  select 'e1000000-0000-4000-8000-000000000001'::uuid role_id, unnest(array[
    'act.inventory_edit','act.lists_edit','act.live_run','act.permissions_config','act.reporting_export','act.team_manage',
    'mod.home','mod.inventory','mod.reporting','mod.schedule','mod.settings','mod.toolkit']) cap
  union all select 'e1000000-0000-4000-8000-000000000002'::uuid, unnest(array[
    'act.inventory_edit','act.lists_edit','act.live_run','act.permissions_config','act.reporting_export','act.team_manage',
    'mod.home','mod.inventory','mod.reporting','mod.schedule','mod.settings','mod.toolkit'])
  union all select 'e1000000-0000-4000-8000-000000000003'::uuid, unnest(array[
    'act.live_run','act.lists_edit','mod.home','mod.inventory','mod.toolkit'])
  union all select 'e1000000-0000-4000-8000-000000000004'::uuid, unnest(array[
    'act.reporting_export','mod.home','mod.reporting','mod.toolkit'])
) g on conflict (organization_id, role_id, capability) do nothing;

-- Map current e10_members → org0 memberships (admin → admin role; anything else → manager role, which also carries
-- the full parity cap set). Data-driven + idempotent.
insert into public.e10_organization_memberships (organization_id, user_id, role_id, display_name, status)
select 'e1000000-0000-4000-8000-0000000000a6'::uuid, m.user_id,
       case when m.role = 'admin' then 'e1000000-0000-4000-8000-000000000001'::uuid
            else 'e1000000-0000-4000-8000-000000000002'::uuid end,
       m.display_name, 'active'
from public.e10_members m
on conflict (organization_id, user_id) do nothing;

-- Platform admin = the first org admin's identity (separate concept from org membership; on prod A10 this is
-- Trent's platform account). Data-driven from the admin member.
insert into public.e10_platform_admins (user_id)
select user_id from public.e10_members where role = 'admin' order by created_at limit 1
on conflict (user_id) do nothing;
