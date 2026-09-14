-- A8 P2 (BACKFILL) down-recovery -> returns to post-P1 (nullable, empty org). Data-safe: only clears the org stamp and
-- removes the derived live_sessions parents + capability seeds; ledger CONTENT is never touched (movements md5 invariant).
-- Drilled finding (A8-PREP F2): the org backfill went PARENTS-first (a child can only get org after its parent has it);
-- nulling must therefore go CHILDREN-first or the composite (org,<key>) FKs are violated mid-way. Rather than hand-order
-- 19 tables, we disable FK triggers for the bulk null-out (session_replication_role=replica) — the same mechanism the
-- prod dump uses to restore. IDEMPOTENT.
set client_min_messages = warning;
set session_replication_role = replica;   -- suspend FK/triggers for the bulk clear
do $$ declare t text; begin
  foreach t in array array['e10_inventory_items','e10_inventory_movements','e10_inventory_reservations','e10_mutation_receipts','e10_workspace','e10_break_sessions','e10_break_slots','e10_break_events','e10_session_viewers','e10_obs_breaks','e10_obs_captures','e10_obs_channels','e10_obs_config','e10_obs_products','e10_obs_product_prices','e10_obs_slots','e10_obs_streams','e10_obs_upcoming_shows','e10_obs_viewer_snapshots'] loop
    execute format('update public.%I set organization_id = null where organization_id is not null', t);
  end loop; end $$;
update public.e10_break_sessions set live_session_id = null where live_session_id is not null;
delete from public.e10_live_sessions;
delete from public.e10_organization_role_permissions;
set session_replication_role = origin;     -- restore normal enforcement
