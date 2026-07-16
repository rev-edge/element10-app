-- Foundation Gate A4a, item 2 — covering indexes for unindexed foreign keys (advisor 0001).
-- The advisor lists 8 (the prompt estimated 5; the extra 3 are on e10_obs_* tables added later — advisor
-- is source of truth). Single-column btree on each FK column; additive, reversible, touches zero data.
--
-- A6 NOTE (deferred, NOT built here): when org scoping lands, the composite indexes that will supersede
-- these lead with organization_id (e.g. (organization_id, session_id) on the break child tables,
-- (organization_id, set_id) on checklists/products). Left single-column now to avoid premature composites.

begin;

create index if not exists e10_break_events_slot_id_idx      on public.e10_break_events   (slot_id);
create index if not exists e10_break_sessions_streamer_idx    on public.e10_break_sessions (streamer_uid);
create index if not exists e10_break_slots_buyer_uid_idx      on public.e10_break_slots    (buyer_uid);
create index if not exists e10_checklists_set_id_idx          on public.e10_checklists     (set_id);
create index if not exists e10_obs_captures_stream_id_idx     on public.e10_obs_captures   (stream_id);
create index if not exists e10_obs_products_set_id_idx        on public.e10_obs_products   (set_id);
create index if not exists e10_obs_slots_team_id_idx          on public.e10_obs_slots      (team_id);
create index if not exists e10_session_viewers_user_id_idx    on public.e10_session_viewers(user_id);

commit;

-- ============================================================================
-- DOWN:
-- begin;
-- drop index if exists public.e10_break_events_slot_id_idx;
-- drop index if exists public.e10_break_sessions_streamer_idx;
-- drop index if exists public.e10_break_slots_buyer_uid_idx;
-- drop index if exists public.e10_checklists_set_id_idx;
-- drop index if exists public.e10_obs_captures_stream_id_idx;
-- drop index if exists public.e10_obs_products_set_id_idx;
-- drop index if exists public.e10_obs_slots_team_id_idx;
-- drop index if exists public.e10_session_viewers_user_id_idx;
-- commit;
