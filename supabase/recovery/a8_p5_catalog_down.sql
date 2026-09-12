-- A8 P5 (CATALOG hole closure: A6c.4) down-recovery -> re-opens the catalog write hole and restores the pre-A6c.4
-- catalog/identity policies. Instant (catalog-only). This is the DOCUMENTED ABORT for P5: if catalog-write errors spike
-- because the curation path (Track B PF-M5) is not yet live, re-adding these 15 mutation policies restores operator
-- catalog creation while P5 is held. The 5 catalog SELECT + 8 identity policies additionally revert to their pre-A6c.4
-- (legacy) predicates via the pre-P4 backup; the 15 mutation policies below are simple single-predicate legacy forms and
-- are reconstructed safely. IDEMPOTENT (drop+create). e10_is_member()/e10_is_admin() must exist (restored by P4-down).
set client_min_messages = warning;
-- cards/checklists/players/sets: member-writable (legacy)
do $$ declare t text; begin
  foreach t in array array['e10_cards','e10_checklists','e10_players','e10_sets'] loop
    execute format('drop policy if exists %I on public.%I; create policy %I on public.%I for insert to authenticated with check ((select e10_is_member()))', replace(t,'e10_','')||'_ins', t, replace(t,'e10_','')||'_ins', t);
    execute format('drop policy if exists %I on public.%I; create policy %I on public.%I for update to authenticated using ((select e10_is_member())) with check ((select e10_is_member()))', replace(t,'e10_','')||'_upd', t, replace(t,'e10_','')||'_upd', t);
    execute format('drop policy if exists %I on public.%I; create policy %I on public.%I for delete to authenticated using ((select e10_is_member()))', replace(t,'e10_','')||'_del', t, replace(t,'e10_','')||'_del', t);
  end loop; end $$;
-- teams: admin-writable (legacy)
drop policy if exists team_ins on public.e10_teams; create policy team_ins on public.e10_teams for insert to authenticated with check ((select e10_is_admin()));
drop policy if exists team_upd on public.e10_teams; create policy team_upd on public.e10_teams for update to authenticated using ((select e10_is_admin())) with check ((select e10_is_admin()));
drop policy if exists team_del on public.e10_teams; create policy team_del on public.e10_teams for delete to authenticated using ((select e10_is_admin()));
