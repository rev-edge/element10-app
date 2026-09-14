-- A8 P1 (EXPAND) down-recovery. Returns the DB to pre-cutover (prod head 20260716110000). Drilled on the scratch
-- restore: with the COMPLETE enumeration below, the DB returns to the exact pre-cutover fingerprint
-- (29 e10 tables, 0 e10 schema, 0 org columns, ledger md5 f54a1fe9..., counts md5 7cd10aba...).
-- IDEMPOTENT (if exists / cascade). Enumerated FROM the migrations, not by hand — the 9 added tables are every
-- table created by A6a+A6b (organizations, roles, memberships, role_permissions, invitations, modules,
-- platform_admins, viewer_handle_claims, live_sessions); the 19 org columns are every ADD COLUMN in s1_expand.
set client_min_messages = warning;
-- 1) org columns (CASCADE removes the 19 org_uq indexes, 16 composite FKs, stamp_org triggers)
do $$ declare t text; begin
  foreach t in array array['e10_inventory_items','e10_inventory_movements','e10_inventory_reservations','e10_mutation_receipts','e10_workspace','e10_break_sessions','e10_break_slots','e10_break_events','e10_session_viewers','e10_obs_breaks','e10_obs_captures','e10_obs_channels','e10_obs_config','e10_obs_products','e10_obs_product_prices','e10_obs_slots','e10_obs_streams','e10_obs_upcoming_shows','e10_obs_viewer_snapshots'] loop
    execute format('alter table public.%I drop column if exists organization_id cascade', t);
  end loop; end $$;
alter table public.e10_break_sessions drop column if exists live_session_id cascade;
-- 2) the 9 added tables
drop table if exists public.e10_live_sessions cascade;
drop table if exists public.e10_organization_role_permissions cascade;
drop table if exists public.e10_organization_memberships cascade;
drop table if exists public.e10_organization_invitations cascade;
drop table if exists public.e10_organization_modules cascade;
drop table if exists public.e10_organization_roles cascade;
drop table if exists public.e10_organizations cascade;
drop table if exists public.e10_platform_admins cascade;
drop table if exists public.e10_viewer_handle_claims cascade;
-- 3) the e10 predicate schema (drops predicates + stamp_org; cascade-drops any remaining dependents)
drop schema if exists e10 cascade;
