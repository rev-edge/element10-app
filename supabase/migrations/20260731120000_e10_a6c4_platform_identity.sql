-- Element 10 — A6c.4 platform-catalog + identity policy family (the last of the 97-policy census: rows 66-97 minus the
-- 4 workspace rows done in A6c.3 = the remaining 28). Per approved A6c plan rev 6 (2d1710bf) §8 (platform catalog) and
-- §9 (legacy role_permissions). Three moves, mirroring the A6c.1/A6c.3 standing (USING = access predicate; every WITH
-- CHECK on a write pins caller org via e10.current_org(); legacy org-blind e10_is_member/e10_is_admin/e10_is_org ->
-- org-scoped e10.* ):
--   A. 5 platform-catalog SELECTs (cards/checklists/players/sets/teams) -> e10.is_platform_admin() OR
--      (e10.current_org() IS NOT NULL): any authenticated caller who belongs to an organization may read the shared,
--      read-only platform catalog; a caller with no org (current_org null) and no platform-admin grant may not.
--   B. 8 identity-family policies org-scoped: e10_members (m_ins/m_sel/m_upd), e10_role_permissions (rp_ins/rp_del/
--      rp_sel/rp_upd), e10_viewers (vw_sel). Writes require e10.is_org_admin(e10.current_org()); a member reads its own
--      row or (as org-admin) the set; role_permissions reads like the catalog. e10_role_permissions is the LEGACY table
--      (authoritative model = A6a e10_organization_role_permissions); this is temporary compatibility, dropped at CONTRACT.
--   C. 15 platform-mutation policies DROPPED (deny-by-default): the ins/upd/del policies on the 5 catalog tables. RLS
--      stays enabled, so with no mutation policy an authenticated/anon write is refused (42501); service_role / platform
--      maintenance still bypasses RLS. No *_padmin_* policies are added; net new policies added by A6c = 0. A reviewed
--      platform-admin curation RPC is future work.
-- e10_viewers vw_ins/vw_upd are already self-scoped by user_id = auth.uid() (census "unchanged") and are NOT touched.
-- The 55 A6c.1 policies, the 4 A6c.3 workspace policies, and every delegate body are untouched.

-- =====================================================================================================================
-- A — 5 platform-catalog SELECTs -> platform-admin OR belongs-to-an-org
-- =====================================================================================================================
drop policy if exists card_sel on public.e10_cards;
create policy card_sel on public.e10_cards for select to public
  using (e10.is_platform_admin() OR (e10.current_org() IS NOT NULL));

drop policy if exists cl_sel on public.e10_checklists;
create policy cl_sel on public.e10_checklists for select to public
  using (e10.is_platform_admin() OR (e10.current_org() IS NOT NULL));

drop policy if exists plr_sel on public.e10_players;
create policy plr_sel on public.e10_players for select to public
  using (e10.is_platform_admin() OR (e10.current_org() IS NOT NULL));

drop policy if exists sets_sel on public.e10_sets;
create policy sets_sel on public.e10_sets for select to public
  using (e10.is_platform_admin() OR (e10.current_org() IS NOT NULL));

drop policy if exists team_sel on public.e10_teams;
create policy team_sel on public.e10_teams for select to public
  using (e10.is_platform_admin() OR (e10.current_org() IS NOT NULL));

-- =====================================================================================================================
-- B — 8 identity-family policies org-scoped
-- =====================================================================================================================
-- e10_members: a member reads its own row or (as org-admin) the set; inserts/updates require org-admin of current org.
drop policy if exists m_ins on public.e10_members;
create policy m_ins on public.e10_members for insert to authenticated
  with check (e10.is_org_admin(e10.current_org()));

drop policy if exists m_sel on public.e10_members;
create policy m_sel on public.e10_members for select to authenticated
  using ((e10_members.user_id = auth.uid()) OR e10.is_org_admin(e10.current_org()));

drop policy if exists m_upd on public.e10_members;
create policy m_upd on public.e10_members for update to authenticated
  using (e10.is_org_admin(e10.current_org()))
  with check (e10.is_org_admin(e10.current_org()));

-- e10_role_permissions (LEGACY table; temporary compat): read like the catalog; writes require org-admin of current org.
drop policy if exists rp_ins on public.e10_role_permissions;
create policy rp_ins on public.e10_role_permissions for insert to public
  with check (e10.is_org_admin(e10.current_org()));

drop policy if exists rp_del on public.e10_role_permissions;
create policy rp_del on public.e10_role_permissions for delete to public
  using (e10.is_org_admin(e10.current_org()));

drop policy if exists rp_sel on public.e10_role_permissions;
create policy rp_sel on public.e10_role_permissions for select to public
  using (e10.is_platform_admin() OR (e10.current_org() IS NOT NULL));

drop policy if exists rp_upd on public.e10_role_permissions;
create policy rp_upd on public.e10_role_permissions for update to public
  using (e10.is_org_admin(e10.current_org()))
  with check (e10.is_org_admin(e10.current_org()));

-- e10_viewers: a viewer reads its own row or (as org-admin) the set. vw_ins/vw_upd unchanged (self-scoped by user_id).
drop policy if exists vw_sel on public.e10_viewers;
create policy vw_sel on public.e10_viewers for select to authenticated
  using ((e10_viewers.user_id = auth.uid()) OR e10.is_org_admin(e10.current_org()));

-- =====================================================================================================================
-- C — DROP the 15 platform-mutation policies on the 5 catalog tables (deny-by-default; RLS stays enabled)
-- =====================================================================================================================
drop policy if exists card_ins on public.e10_cards;
drop policy if exists card_upd on public.e10_cards;
drop policy if exists card_del on public.e10_cards;
drop policy if exists cl_ins on public.e10_checklists;
drop policy if exists cl_upd on public.e10_checklists;
drop policy if exists cl_del on public.e10_checklists;
drop policy if exists plr_ins on public.e10_players;
drop policy if exists plr_upd on public.e10_players;
drop policy if exists plr_del on public.e10_players;
drop policy if exists sets_ins on public.e10_sets;
drop policy if exists sets_upd on public.e10_sets;
drop policy if exists sets_del on public.e10_sets;
drop policy if exists team_ins on public.e10_teams;
drop policy if exists team_upd on public.e10_teams;
drop policy if exists team_del on public.e10_teams;

-- Absence + RLS-enabled invariant (deny-by-default) asserted at migration time so a stray mutation policy or a disabled
-- RLS flag fails the apply, not just the gate.
do $$
declare v_mut int; v_rls int;
begin
  select count(*) into v_mut from pg_policies where schemaname='public'
    and tablename in ('e10_cards','e10_checklists','e10_players','e10_sets','e10_teams') and cmd <> 'SELECT';
  if v_mut <> 0 then raise exception 'A6c.4: expected 0 mutation policies on the 5 catalog tables, found %', v_mut; end if;
  select count(*) into v_rls from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relname in ('e10_cards','e10_checklists','e10_players','e10_sets','e10_teams') and c.relrowsecurity;
  if v_rls <> 5 then raise exception 'A6c.4: expected RLS enabled on all 5 catalog tables, found %', v_rls; end if;
  raise notice 'A6c.4: 5 catalog tables RLS-enabled with SELECT-only (0 mutation policies) — deny-by-default confirmed at apply';
end $$;
