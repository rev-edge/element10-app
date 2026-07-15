-- M4 STEP 2 (DESTRUCTIVE — THE ONE-WAY DOOR): retire the blob's inventory copy.
-- Apply ONLY after the M4 client (which reads inventory from e10_inventory_items via e10_inv_list and
-- patches per-row via realtime) is deployed and verified live. An OLD client that still reads
-- data->'inventory' would see EMPTY inventory after this — hence the staged deploy.
--
-- 1. Neutralize the blob dual-write in one place: _e10_inv_blob_write becomes a no-op that returns the
--    current shared rev (so every e10_inv_* RPC's {rev} return shape is unchanged) without touching data.
-- 2. Drop the blob's inventory section.
--
-- ROLLBACK: this closes the spike §6 rollback window. Reverting the client alone is no longer enough —
-- run supabase/recovery/m4_revert_down_path.sql FIRST (re-projects the blob from rows, restores
-- _e10_inv_blob_write + the recon views), THEN git-revert the M4 client commit. Any mutations committed
-- after this migration exist only in rows + ledger; the re-projection reconstructs the blob from them.

create or replace function public._e10_inv_blob_write(p_id text, p_remove boolean, p_actor text)
  returns bigint language sql security definer set search_path to 'public' as $$
  -- M4: inventory is no longer mirrored into the blob. Return the shared rev unchanged (no write).
  select coalesce((select rev from public.e10_workspace where id = 'shared'), 0::bigint);
$$;

update public.e10_workspace set data = data - 'inventory' where id = 'shared';
