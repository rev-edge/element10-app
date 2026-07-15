# ADR 0002 — M4: retire the inventory blob (one-way door)

**Date:** 2026-07-15 · **Status:** accepted, deployed (`c21c5d5` / `722e5cf`)

## Context
Post-M3, relational rows were the write authority but the `shared` blob still held a dual-written `inventory` copy that the client read. ADR 0001 mandated finishing the cutover.

## Decision
Move the inventory **read source** to `e10_inventory_items` (projected by `e10_inv_list()` / patched per-row by `e10_inv_get()` + realtime), remove `inventory` from the blob write path, and **drop the blob copy**. Irreversible once dropped.

## How (staged, prod-safe)
1. Additive DB: read RPCs, realtime + `REPLICA IDENTITY FULL` on the inventory tables, recon views redefined rows-vs-ledger. Old client unaffected.
2. Deploy the M4 client (reads rows; `SHARED.inventory` row-owned, preserved across blob re-splits).
3. Destructive DB: `_e10_inv_blob_write` → no-op; `data - 'inventory'`. **Rollback window closes here.**

Down-path shipped + rehearsed: `supabase/recovery/m4_revert_down_path.sql` re-projects the blob from rows.

## Consequences / lessons
- Verified on prod: `m4_realtime` 12/12, `live_flow` 17/17, gate 0 HARD, recon drift 0, read-site rollups byte-identical.
- **Two regressions caught** (see `docs/incidents/2026-07-15-m4-blob-clobber.md`): the pre-deploy blob clobber (local client vs prod) and the recon-view SECURITY DEFINER + anon-grant hole (P0 hotfix). Both fed the Foundation Gate (ADR 0003).
