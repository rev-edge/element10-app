# Incident — M4 pre-deploy blob clobber (2026-07-15)

**Status:** closed. No data loss. Root cause institutionalized as Foundation Gate Track A 2–3.

## Summary
During M4 verification (retiring the inventory JSONB blob in favor of relational rows), a **local M4 client run against the production database emptied the live `shared` blob's `inventory` section** before the M4 client was deployed or the destructive migration was applied. Production rows (`e10_inventory_items`) were never affected; the still-deployed **old** client, which read inventory from the blob, would have shown empty inventory until restore.

## What happened
1. M4's client stops writing inventory to the blob: `_sharedPayload()` no longer includes an `inventory` key, and `writeRow()` writes the **whole** `data` column from the merged `SHARED_KEYS`.
2. The M4 realtime test loaded the **local M4 client against live Supabase**. On a shared-row write (triggered via the realtime/flush path), the client wrote `data` without an `inventory` section → the live blob's inventory was dropped to `[]`.
3. Detected immediately by a re-projection equivalence check (`blob_count: 0` while rows = 35).

## Restore
Re-projected the blob from the authoritative rows (the M4 down-path, run as an immediate restore):
```sql
update public.e10_workspace
   set data = jsonb_set(coalesce(data,'{}'), '{inventory}',
         (select coalesce(jsonb_agg(public._e10_inv_item_json(id) order by id),'[]') from public.e10_inventory_items)),
       rev = rev+1, updated_at = now()
 where id = 'shared';
```
Result: blob restored to 35 items, drift 0. The staged deploy then proceeded (client live → destructive migration), after which there is no blob inventory to clobber.

## Second, related regression (same day)
M4's read-source migration recreated the reconciliation views (`e10_inventory_recon`, `e10_inventory_reserved_recon`) with **plain `CREATE VIEW`** — no `security_invoker` (so SECURITY DEFINER, bypassing RLS) **and** SELECT still granted to `anon`. That made reserved-inventory data **readable unauthenticated** via the public anon key (Supabase advisor 0010). Hotfixed by the reviewer: `security_invoker = true` + `revoke select … from anon` (migration `e10_p0_recon_view_security`, now a verbatim repo file).

## Lessons → institutionalized
- **A local client must never be able to mutate/read production as if it were local.** → Track A2: production demotion (no prod defaults in tests; `E10_ALLOW_PROD=1` + read-only only) and a **fail-closed schema-version handshake** so a client refuses mutations against a schema it wasn't built for.
- **A one-way migration needs its down-path proven before the window closes** (M4 shipped `supabase/recovery/m4_revert_down_path.sql`, rehearsed non-destructively).
- **New/redefined views default to SECURITY DEFINER + anon-granted** — always `security_invoker = true` + explicit `revoke … from anon`. → Track A3 CI runs the Supabase advisors.
- **Blueprint + environments are prerequisites, not follow-ups** → the entire Foundation Gate.
