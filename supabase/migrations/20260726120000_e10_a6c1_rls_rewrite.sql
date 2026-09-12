-- Foundation Gate A6c.1 (RLS POLICY REWRITE) — STAGING/LOCAL only; production read-only. ADDITIVE migration.
-- Authorization: BOARD.md Approvals Ledger "A6c.0 additive prerequisites | GRANTED | CPI | 2026-07-20 | commit 7f0d383"
-- + "A6c authorization plan rev 6 | GRANTED | CPI | 2026-07-20 | Element10_A6c_PLAN.md SHA-256 2d1710bf...".
-- Rewrites EXACTLY the 55 checkpoint=A6c.1 policies from the reviewed 97-policy census (Element10_A6c_census.csv,
-- SHA-256 a5b60af1...): the 3 inventory SELECTs + 40 OBS + 12 session policies. Legacy org-blind predicates
-- (e10_is_member/e10_is_org/e10_is_admin/e10_has_cap/e10_can_read_session/e10_owns_session) -> org-scoped e10.*
-- predicates, every correlated outer reference table-qualified. NO wrapper cutover (A6c.2) and NO relocation of legacy
-- mechanics (A6c.2); the A6c.0 delegates stay additive. Workspace (4, A6c.3), identity (8) and platform (5 SELECT +
-- 15 removed) policies (A6c.4) are OUT OF SCOPE here. Stops before A6c.2. The append-only ledger has no item FKs;
-- imov_sel filters by organization_id only, never the item's existence.

drop policy if exists ev_ins on public.e10_break_events;
create policy ev_ins on public.e10_break_events for insert to authenticated
  with check (e10.owns_session(e10_break_events.session_id) AND ((e10_break_events.actor_uid = auth.uid()) OR (e10_break_events.actor_uid IS NULL)) AND (e10_break_events.organization_id = e10.current_org()));

drop policy if exists ev_sel on public.e10_break_events;
create policy ev_sel on public.e10_break_events for select to authenticated
  using (e10.is_org_member(organization_id) OR e10.owns_session(e10_break_events.session_id) OR exists(select 1 from public.e10_session_viewers v where v.session_id = e10_break_events.session_id and v.user_id = auth.uid()) OR exists(select 1 from public.e10_break_slots owned_slot where owned_slot.session_id = e10_break_events.session_id and e10.owns_slot(owned_slot.id)));

drop policy if exists bs_ins on public.e10_break_sessions;
create policy bs_ins on public.e10_break_sessions for insert to public
  with check ((((e10_break_sessions.streamer_uid = auth.uid()) OR e10.is_org_admin(e10_break_sessions.organization_id)) AND e10.has_org_cap(e10_break_sessions.organization_id,'act.live_run')) AND (e10_break_sessions.organization_id = e10.current_org()));

drop policy if exists bs_del on public.e10_break_sessions;
create policy bs_del on public.e10_break_sessions for delete to authenticated
  using ((e10_break_sessions.streamer_uid = auth.uid()) OR e10.is_org_admin(e10_break_sessions.organization_id));

drop policy if exists bs_sel on public.e10_break_sessions;
create policy bs_sel on public.e10_break_sessions for select to authenticated
  using (e10.is_org_member(organization_id) OR e10.owns_session(e10_break_sessions.id) OR exists(select 1 from public.e10_session_viewers v where v.session_id = e10_break_sessions.id and v.user_id = auth.uid()) OR exists(select 1 from public.e10_break_slots owned_slot where owned_slot.session_id = e10_break_sessions.id and e10.owns_slot(owned_slot.id)));

drop policy if exists bs_upd on public.e10_break_sessions;
create policy bs_upd on public.e10_break_sessions for update to public
  using (((e10_break_sessions.streamer_uid = auth.uid()) OR e10.is_org_admin(e10_break_sessions.organization_id)) AND e10.has_org_cap(e10_break_sessions.organization_id,'act.live_run'))
  with check ((((e10_break_sessions.streamer_uid = auth.uid()) OR e10.is_org_admin(e10_break_sessions.organization_id)) AND e10.has_org_cap(e10_break_sessions.organization_id,'act.live_run')) AND (e10_break_sessions.organization_id = e10.current_org()));

drop policy if exists sl_ins on public.e10_break_slots;
create policy sl_ins on public.e10_break_slots for insert to public
  with check (e10.owns_session(e10_break_slots.session_id) AND e10.has_org_cap(e10_break_slots.organization_id,'act.live_run') AND (e10_break_slots.organization_id = e10.current_org()));

drop policy if exists sl_del on public.e10_break_slots;
create policy sl_del on public.e10_break_slots for delete to public
  using (e10.owns_session(e10_break_slots.session_id) AND e10.has_org_cap(e10_break_slots.organization_id,'act.live_run'));

drop policy if exists sl_sel on public.e10_break_slots;
create policy sl_sel on public.e10_break_slots for select to authenticated
  using (e10.is_org_member(organization_id) OR e10.owns_session(e10_break_slots.session_id) OR e10.owns_slot(e10_break_slots.id) OR exists(select 1 from public.e10_session_viewers v where v.session_id = e10_break_slots.session_id and v.user_id = auth.uid()));

drop policy if exists sl_upd on public.e10_break_slots;
create policy sl_upd on public.e10_break_slots for update to public
  using (e10.owns_session(e10_break_slots.session_id) AND e10.has_org_cap(e10_break_slots.organization_id,'act.live_run'))
  with check (e10.owns_session(e10_break_slots.session_id) AND e10.has_org_cap(e10_break_slots.organization_id,'act.live_run') AND (e10_break_slots.organization_id = e10.current_org()));

drop policy if exists inv_items_sel on public.e10_inventory_items;
create policy inv_items_sel on public.e10_inventory_items for select to authenticated
  using (e10.is_org_member(organization_id));

drop policy if exists imov_sel on public.e10_inventory_movements;
create policy imov_sel on public.e10_inventory_movements for select to authenticated
  using (e10.is_org_member(organization_id));

drop policy if exists inv_res_sel on public.e10_inventory_reservations;
create policy inv_res_sel on public.e10_inventory_reservations for select to authenticated
  using (e10.is_org_member(organization_id));

drop policy if exists e10_obs_breaks_ins on public.e10_obs_breaks;
create policy e10_obs_breaks_ins on public.e10_obs_breaks for insert to authenticated
  with check (e10.is_org_member(organization_id) AND organization_id = e10.current_org());

drop policy if exists e10_obs_breaks_del on public.e10_obs_breaks;
create policy e10_obs_breaks_del on public.e10_obs_breaks for delete to authenticated
  using (e10.is_org_member(organization_id));

drop policy if exists e10_obs_breaks_sel on public.e10_obs_breaks;
create policy e10_obs_breaks_sel on public.e10_obs_breaks for select to public
  using (e10.is_org_member(organization_id));

drop policy if exists e10_obs_breaks_upd on public.e10_obs_breaks;
create policy e10_obs_breaks_upd on public.e10_obs_breaks for update to authenticated
  using (e10.is_org_member(organization_id))
  with check (e10.is_org_member(organization_id) AND organization_id = e10.current_org());

drop policy if exists e10_obs_captures_ins on public.e10_obs_captures;
create policy e10_obs_captures_ins on public.e10_obs_captures for insert to authenticated
  with check (e10.is_org_member(organization_id) AND organization_id = e10.current_org());

drop policy if exists e10_obs_captures_del on public.e10_obs_captures;
create policy e10_obs_captures_del on public.e10_obs_captures for delete to authenticated
  using (e10.is_org_member(organization_id));

drop policy if exists e10_obs_captures_sel on public.e10_obs_captures;
create policy e10_obs_captures_sel on public.e10_obs_captures for select to public
  using (e10.is_org_member(organization_id));

drop policy if exists e10_obs_captures_upd on public.e10_obs_captures;
create policy e10_obs_captures_upd on public.e10_obs_captures for update to authenticated
  using (e10.is_org_member(organization_id))
  with check (e10.is_org_member(organization_id) AND organization_id = e10.current_org());

drop policy if exists e10_obs_channels_ins on public.e10_obs_channels;
create policy e10_obs_channels_ins on public.e10_obs_channels for insert to authenticated
  with check (e10.is_org_member(organization_id) AND organization_id = e10.current_org());

drop policy if exists e10_obs_channels_del on public.e10_obs_channels;
create policy e10_obs_channels_del on public.e10_obs_channels for delete to authenticated
  using (e10.is_org_member(organization_id));

drop policy if exists e10_obs_channels_sel on public.e10_obs_channels;
create policy e10_obs_channels_sel on public.e10_obs_channels for select to public
  using (e10.is_org_member(organization_id));

drop policy if exists e10_obs_channels_upd on public.e10_obs_channels;
create policy e10_obs_channels_upd on public.e10_obs_channels for update to authenticated
  using (e10.is_org_member(organization_id))
  with check (e10.is_org_member(organization_id) AND organization_id = e10.current_org());

drop policy if exists e10_obs_config_ins on public.e10_obs_config;
create policy e10_obs_config_ins on public.e10_obs_config for insert to authenticated
  with check (e10.is_org_member(organization_id) AND organization_id = e10.current_org());

drop policy if exists e10_obs_config_del on public.e10_obs_config;
create policy e10_obs_config_del on public.e10_obs_config for delete to authenticated
  using (e10.is_org_member(organization_id));

drop policy if exists e10_obs_config_sel on public.e10_obs_config;
create policy e10_obs_config_sel on public.e10_obs_config for select to public
  using (e10.is_org_member(organization_id));

drop policy if exists e10_obs_config_upd on public.e10_obs_config;
create policy e10_obs_config_upd on public.e10_obs_config for update to authenticated
  using (e10.is_org_member(organization_id))
  with check (e10.is_org_member(organization_id) AND organization_id = e10.current_org());

drop policy if exists e10_obs_product_prices_ins on public.e10_obs_product_prices;
create policy e10_obs_product_prices_ins on public.e10_obs_product_prices for insert to authenticated
  with check (e10.is_org_member(organization_id) AND organization_id = e10.current_org());

drop policy if exists e10_obs_product_prices_del on public.e10_obs_product_prices;
create policy e10_obs_product_prices_del on public.e10_obs_product_prices for delete to authenticated
  using (e10.is_org_member(organization_id));

drop policy if exists e10_obs_product_prices_sel on public.e10_obs_product_prices;
create policy e10_obs_product_prices_sel on public.e10_obs_product_prices for select to public
  using (e10.is_org_member(organization_id));

drop policy if exists e10_obs_product_prices_upd on public.e10_obs_product_prices;
create policy e10_obs_product_prices_upd on public.e10_obs_product_prices for update to authenticated
  using (e10.is_org_member(organization_id))
  with check (e10.is_org_member(organization_id) AND organization_id = e10.current_org());

drop policy if exists e10_obs_products_ins on public.e10_obs_products;
create policy e10_obs_products_ins on public.e10_obs_products for insert to authenticated
  with check (e10.is_org_member(organization_id) AND organization_id = e10.current_org());

drop policy if exists e10_obs_products_del on public.e10_obs_products;
create policy e10_obs_products_del on public.e10_obs_products for delete to authenticated
  using (e10.is_org_member(organization_id));

drop policy if exists e10_obs_products_sel on public.e10_obs_products;
create policy e10_obs_products_sel on public.e10_obs_products for select to public
  using (e10.is_org_member(organization_id));

drop policy if exists e10_obs_products_upd on public.e10_obs_products;
create policy e10_obs_products_upd on public.e10_obs_products for update to authenticated
  using (e10.is_org_member(organization_id))
  with check (e10.is_org_member(organization_id) AND organization_id = e10.current_org());

drop policy if exists e10_obs_slots_ins on public.e10_obs_slots;
create policy e10_obs_slots_ins on public.e10_obs_slots for insert to authenticated
  with check (e10.is_org_member(organization_id) AND organization_id = e10.current_org());

drop policy if exists e10_obs_slots_del on public.e10_obs_slots;
create policy e10_obs_slots_del on public.e10_obs_slots for delete to authenticated
  using (e10.is_org_member(organization_id));

drop policy if exists e10_obs_slots_sel on public.e10_obs_slots;
create policy e10_obs_slots_sel on public.e10_obs_slots for select to public
  using (e10.is_org_member(organization_id));

drop policy if exists e10_obs_slots_upd on public.e10_obs_slots;
create policy e10_obs_slots_upd on public.e10_obs_slots for update to authenticated
  using (e10.is_org_member(organization_id))
  with check (e10.is_org_member(organization_id) AND organization_id = e10.current_org());

drop policy if exists e10_obs_streams_ins on public.e10_obs_streams;
create policy e10_obs_streams_ins on public.e10_obs_streams for insert to authenticated
  with check (e10.is_org_member(organization_id) AND organization_id = e10.current_org());

drop policy if exists e10_obs_streams_del on public.e10_obs_streams;
create policy e10_obs_streams_del on public.e10_obs_streams for delete to authenticated
  using (e10.is_org_member(organization_id));

drop policy if exists e10_obs_streams_sel on public.e10_obs_streams;
create policy e10_obs_streams_sel on public.e10_obs_streams for select to public
  using (e10.is_org_member(organization_id));

drop policy if exists e10_obs_streams_upd on public.e10_obs_streams;
create policy e10_obs_streams_upd on public.e10_obs_streams for update to authenticated
  using (e10.is_org_member(organization_id))
  with check (e10.is_org_member(organization_id) AND organization_id = e10.current_org());

drop policy if exists e10_obs_upcoming_shows_ins on public.e10_obs_upcoming_shows;
create policy e10_obs_upcoming_shows_ins on public.e10_obs_upcoming_shows for insert to authenticated
  with check (e10.is_org_member(organization_id) AND organization_id = e10.current_org());

drop policy if exists e10_obs_upcoming_shows_del on public.e10_obs_upcoming_shows;
create policy e10_obs_upcoming_shows_del on public.e10_obs_upcoming_shows for delete to authenticated
  using (e10.is_org_member(organization_id));

drop policy if exists e10_obs_upcoming_shows_sel on public.e10_obs_upcoming_shows;
create policy e10_obs_upcoming_shows_sel on public.e10_obs_upcoming_shows for select to public
  using (e10.is_org_member(organization_id));

drop policy if exists e10_obs_upcoming_shows_upd on public.e10_obs_upcoming_shows;
create policy e10_obs_upcoming_shows_upd on public.e10_obs_upcoming_shows for update to authenticated
  using (e10.is_org_member(organization_id))
  with check (e10.is_org_member(organization_id) AND organization_id = e10.current_org());

drop policy if exists e10_obs_viewer_snapshots_ins on public.e10_obs_viewer_snapshots;
create policy e10_obs_viewer_snapshots_ins on public.e10_obs_viewer_snapshots for insert to authenticated
  with check (e10.is_org_member(organization_id) AND organization_id = e10.current_org());

drop policy if exists e10_obs_viewer_snapshots_del on public.e10_obs_viewer_snapshots;
create policy e10_obs_viewer_snapshots_del on public.e10_obs_viewer_snapshots for delete to authenticated
  using (e10.is_org_member(organization_id));

drop policy if exists e10_obs_viewer_snapshots_sel on public.e10_obs_viewer_snapshots;
create policy e10_obs_viewer_snapshots_sel on public.e10_obs_viewer_snapshots for select to public
  using (e10.is_org_member(organization_id));

drop policy if exists e10_obs_viewer_snapshots_upd on public.e10_obs_viewer_snapshots;
create policy e10_obs_viewer_snapshots_upd on public.e10_obs_viewer_snapshots for update to authenticated
  using (e10.is_org_member(organization_id))
  with check (e10.is_org_member(organization_id) AND organization_id = e10.current_org());

drop policy if exists sv_ins on public.e10_session_viewers;
create policy sv_ins on public.e10_session_viewers for insert to authenticated
  with check (e10.owns_session(e10_session_viewers.session_id) AND (e10_session_viewers.organization_id = e10.current_org()));

drop policy if exists sv_sel on public.e10_session_viewers;
create policy sv_sel on public.e10_session_viewers for select to authenticated
  using (e10.is_org_member(organization_id) OR e10.owns_session(e10_session_viewers.session_id) OR (e10_session_viewers.user_id = auth.uid()));

