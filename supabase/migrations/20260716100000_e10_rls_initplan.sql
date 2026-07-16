-- Foundation Gate A4a, item 1 — RLS InitPlan (advisor 0003, 14 policies).
-- Each flagged policy re-evaluates bare `auth.uid()` per row. Fix = wrap in (select ...) so the
-- planner hoists it to a one-time InitPlan param (Supabase house pattern; newer policies already do this).
-- No-arg helpers (e10_is_admin/is_member/...) are wrapped too where present in these policies.
-- Row-argument helpers (e10_owns_session(session_id), e10_can_read_session(id)) are LEFT BARE — they
-- depend on the row and cannot be hoisted (consistent with unflagged policies like sl_del).
-- ALTER POLICY changes ONLY the expression; roles/command/permissive are untouched. Semantically identical
-- (same rows visible). Reversible down-block restores the exact prior expressions. Touches zero data.

begin;

-- e10_members.m_sel
alter policy m_sel on public.e10_members
  using (((user_id = ( select auth.uid() )) or ( select public.e10_is_admin() )));

-- e10_workspace (4)
alter policy ws_sel on public.e10_workspace
  using ((((id = any (array['shared'::text, 'universal'::text])) and ( select public.e10_is_org() ))
          or (owner = ( select auth.uid() ))
          or ( select public.e10_is_admin() )));
alter policy ws_ins on public.e10_workspace
  with check ((((id = 'shared'::text) and ( select public.e10_is_member() ) and ( select public.e10_has_cap('act.inventory_edit'::text) ))
              or ((id = 'universal'::text) and ( select public.e10_is_admin() ))
              or (owner = ( select auth.uid() ))
              or ( select public.e10_is_admin() )));
alter policy ws_upd on public.e10_workspace
  using ((((id = 'shared'::text) and ( select public.e10_is_member() ) and ( select public.e10_has_cap('act.inventory_edit'::text) ))
          or ((id = 'universal'::text) and ( select public.e10_is_admin() ))
          or (owner = ( select auth.uid() ))
          or ( select public.e10_is_admin() )))
  with check ((((id = 'shared'::text) and ( select public.e10_is_member() ) and ( select public.e10_has_cap('act.inventory_edit'::text) ))
              or ((id = 'universal'::text) and ( select public.e10_is_admin() ))
              or (owner = ( select auth.uid() ))
              or ( select public.e10_is_admin() )));
alter policy ws_del on public.e10_workspace
  using (((owner = ( select auth.uid() )) or ( select public.e10_is_admin() )));

-- e10_viewers (3)
alter policy vw_sel on public.e10_viewers
  using (((user_id = ( select auth.uid() )) or ( select public.e10_is_admin() )));
alter policy vw_ins on public.e10_viewers
  with check ((user_id = ( select auth.uid() )));
alter policy vw_upd on public.e10_viewers
  using ((user_id = ( select auth.uid() )))
  with check ((user_id = ( select auth.uid() )));

-- e10_break_sessions (4)
alter policy bs_sel on public.e10_break_sessions
  using (((streamer_uid = ( select auth.uid() )) or ( select public.e10_is_admin() ) or public.e10_can_read_session(id)));
alter policy bs_ins on public.e10_break_sessions
  with check ((((streamer_uid = ( select auth.uid() )) or ( select public.e10_is_admin() ))
              and ( select public.e10_has_cap('act.live_run'::text) )));
alter policy bs_upd on public.e10_break_sessions
  using ((((streamer_uid = ( select auth.uid() )) or ( select public.e10_is_admin() ))
          and ( select public.e10_has_cap('act.live_run'::text) )))
  with check ((((streamer_uid = ( select auth.uid() )) or ( select public.e10_is_admin() ))
              and ( select public.e10_has_cap('act.live_run'::text) )));
alter policy bs_del on public.e10_break_sessions
  using (((streamer_uid = ( select auth.uid() )) or ( select public.e10_is_admin() )));

-- e10_break_events.ev_ins  (row-arg e10_owns_session left bare)
alter policy ev_ins on public.e10_break_events
  with check ((public.e10_owns_session(session_id) and ((actor_uid = ( select auth.uid() )) or (actor_uid is null))));

-- e10_session_viewers.sv_sel  (row-arg e10_owns_session left bare)
alter policy sv_sel on public.e10_session_viewers
  using (((user_id = ( select auth.uid() )) or public.e10_owns_session(session_id)));

commit;

-- ============================================================================
-- DOWN (restore the exact prior expressions — bare auth.uid()):
-- begin;
-- alter policy m_sel on public.e10_members
--   using (((user_id = auth.uid()) or e10_is_admin()));
-- alter policy ws_sel on public.e10_workspace
--   using ((((id = any (array['shared'::text,'universal'::text])) and ( select e10_is_org() )) or (owner = auth.uid()) or ( select e10_is_admin() )));
-- alter policy ws_ins on public.e10_workspace
--   with check ((((id = 'shared'::text) and ( select e10_is_member() ) and ( select e10_has_cap('act.inventory_edit'::text) )) or ((id = 'universal'::text) and ( select e10_is_admin() )) or (owner = auth.uid()) or ( select e10_is_admin() )));
-- alter policy ws_upd on public.e10_workspace
--   using ((((id = 'shared'::text) and ( select e10_is_member() ) and ( select e10_has_cap('act.inventory_edit'::text) )) or ((id = 'universal'::text) and ( select e10_is_admin() )) or (owner = auth.uid()) or ( select e10_is_admin() )))
--   with check ((((id = 'shared'::text) and ( select e10_is_member() ) and ( select e10_has_cap('act.inventory_edit'::text) )) or ((id = 'universal'::text) and ( select e10_is_admin() )) or (owner = auth.uid()) or ( select e10_is_admin() )));
-- alter policy ws_del on public.e10_workspace
--   using (((owner = auth.uid()) or e10_is_admin()));
-- alter policy vw_sel on public.e10_viewers using (((user_id = auth.uid()) or e10_is_admin()));
-- alter policy vw_ins on public.e10_viewers with check ((user_id = auth.uid()));
-- alter policy vw_upd on public.e10_viewers using ((user_id = auth.uid())) with check ((user_id = auth.uid()));
-- alter policy bs_sel on public.e10_break_sessions using (((streamer_uid = auth.uid()) or e10_is_admin() or e10_can_read_session(id)));
-- alter policy bs_ins on public.e10_break_sessions with check ((((streamer_uid = auth.uid()) or ( select e10_is_admin() )) and ( select e10_has_cap('act.live_run'::text) )));
-- alter policy bs_upd on public.e10_break_sessions using ((((streamer_uid = auth.uid()) or ( select e10_is_admin() )) and ( select e10_has_cap('act.live_run'::text) ))) with check ((((streamer_uid = auth.uid()) or ( select e10_is_admin() )) and ( select e10_has_cap('act.live_run'::text) )));
-- alter policy bs_del on public.e10_break_sessions using (((streamer_uid = auth.uid()) or e10_is_admin()));
-- alter policy ev_ins on public.e10_break_events with check ((e10_owns_session(session_id) and ((actor_uid = auth.uid()) or (actor_uid is null))));
-- alter policy sv_sel on public.e10_session_viewers using (((user_id = auth.uid()) or e10_owns_session(session_id)));
-- commit;
