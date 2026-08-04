-- A8 P3 (PROMOTE) down-recovery -> returns organization_id to NULLABLE on the 19 retrofit tables. Drilled (A8-PREP F2).
-- IMPORTANT (drilled finding): the org_uq UNIQUE constraints are NOT dropped here — the composite (org,<key>) FKs DEPEND
-- on them (dropping errors "other objects depend on it"), and a unique constraint is functionally equivalent to the
-- Step-1 unique index for both FK enforcement and a P3 re-run (whose guard skips the existing constraint). Reverting NOT
-- NULL is sufficient to return to a valid post-P2 (nullable, backfilled) state. For a full teardown use a8_p1 (CASCADE).
-- IDEMPOTENT.
set client_min_messages = warning;
do $$ declare t text; begin
  foreach t in array array['e10_inventory_items','e10_inventory_movements','e10_inventory_reservations','e10_mutation_receipts','e10_workspace','e10_break_sessions','e10_break_slots','e10_break_events','e10_session_viewers','e10_obs_breaks','e10_obs_captures','e10_obs_channels','e10_obs_config','e10_obs_products','e10_obs_product_prices','e10_obs_slots','e10_obs_streams','e10_obs_upcoming_shows','e10_obs_viewer_snapshots'] loop
    execute format('alter table public.%I alter column organization_id drop not null', t);
  end loop; end $$;
