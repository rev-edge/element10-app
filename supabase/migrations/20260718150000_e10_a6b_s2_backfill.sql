-- Foundation Gate A6b Step 2 (BACKFILL) — STAGING/LOCAL only; production untouched. ADDITIVE + idempotent.
-- Sets organization_id = org0 on every existing row of the 19 retrofit tables, then creates a STRICT 1:1
-- e10_live_sessions parent per existing break_session (Ruling D — one parent per session, NO source_show_ref
-- grouping) and links break_sessions.live_session_id.
--
-- Ordering: PARENTS are backfilled before CHILDREN so the Step-1 composite FKs enforce org-consistency throughout
-- (a child (org0, fk) can only be set once its parent is already (org0, id)). No orphans exist (pre-verified), so
-- every FK check passes. workspace rows are re-keyed to org0's namespace and mutation_receipts idempotency is
-- re-scoped to (org0, idempotency_key) by the same backfill (their Step-1 (org,*) unique indexes already exist;
-- the CAS write path and the global idempotency PK are untouched until CONTRACT). Idempotent via
-- `where organization_id is null` / `where live_session_id is null` / `on conflict do nothing`.

do $$
declare v_org uuid := 'e1000000-0000-4000-8000-0000000000a6';
begin
  -- (1) org0 backfill — PARENTS first (items, sessions, slots, obs channels/products/streams/breaks)
  update public.e10_inventory_items       set organization_id = v_org where organization_id is null;
  update public.e10_break_sessions         set organization_id = v_org where organization_id is null;
  update public.e10_break_slots            set organization_id = v_org where organization_id is null;
  update public.e10_obs_channels           set organization_id = v_org where organization_id is null;
  update public.e10_obs_products           set organization_id = v_org where organization_id is null;
  update public.e10_obs_streams            set organization_id = v_org where organization_id is null;
  update public.e10_obs_breaks             set organization_id = v_org where organization_id is null;
  -- then children / independent tables
  update public.e10_inventory_movements    set organization_id = v_org where organization_id is null;
  update public.e10_inventory_reservations set organization_id = v_org where organization_id is null;
  update public.e10_mutation_receipts      set organization_id = v_org where organization_id is null;  -- idempotency re-scope -> (org0, idempotency_key)
  update public.e10_break_events           set organization_id = v_org where organization_id is null;
  update public.e10_session_viewers        set organization_id = v_org where organization_id is null;
  update public.e10_workspace              set organization_id = v_org where organization_id is null;  -- re-key workspace rows to org0
  update public.e10_obs_config             set organization_id = v_org where organization_id is null;
  update public.e10_obs_captures           set organization_id = v_org where organization_id is null;
  update public.e10_obs_product_prices     set organization_id = v_org where organization_id is null;
  update public.e10_obs_slots              set organization_id = v_org where organization_id is null;
  update public.e10_obs_upcoming_shows     set organization_id = v_org where organization_id is null;
  update public.e10_obs_viewer_snapshots   set organization_id = v_org where organization_id is null;
end $$;

-- (2) STRICT 1:1 live_sessions parents (Ruling D). Deterministic parent id per break_session (md5 of the session id)
-- => exactly one parent per session, keyed by the SESSION id (never by source_show_ref, so retried starts that share
-- a source_show_ref still get distinct parents). Parent is created BEFORE the child link so the composite FK holds.
insert into public.e10_live_sessions (organization_id, id, source_show_ref, name, status)
select 'e1000000-0000-4000-8000-0000000000a6'::uuid,
       md5('a6b_live_session:' || bs.id::text)::uuid,
       bs.source_show_ref,
       bs.name,
       case when bs.ended_at is not null then 'ended' else 'active' end
from public.e10_break_sessions bs
where bs.live_session_id is null
on conflict (organization_id, id) do nothing;

update public.e10_break_sessions bs
   set live_session_id = md5('a6b_live_session:' || bs.id::text)::uuid
 where bs.live_session_id is null;
