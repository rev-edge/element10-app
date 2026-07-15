# Element 10 — S1: Inventory storage decision spike

**Status:** read-only analysis. No code, no migration, no DB write, no throwaway rows. Only read-only SQL and source inspection were used. **No checkpoint-gate script was run because nothing changed** — the chain's gate applies to H1/H2, not to this document.

**Evidence base:** commit `1ed1e96` (`main`, post-H2), file `index.html`; live Supabase project `ddhkkumiyidorzmajwde` via read-only `select`.

**Question in one line:** inventory currently lives as a JSONB array inside the `shared` `e10_workspace` row and is *also* shadowed by an append-only relational ledger (`e10_inventory_movements`). Should the **system of record** for inventory move to relational tables now (Pass 2.7's cutover), stay in the blob, or stay in the blob behind migration-ready contracts?

**Recommendation up front:** option **(c) — keep the blob as source of truth now, but route every inventory mutation through a small set of RPC-shaped client functions** so 2.7's cutover becomes a server-side swap rather than a client rewrite. Rationale and the two strongest counterarguments are in §10.

---

## Standing facts (measured, not assumed)

| Fact | Value | Evidence |
|---|---|---|
| `shared` row size | 6,360 bytes (`pg_column_size`), 21,027 JSON chars | `select pg_column_size(data)…` |
| Sections in `shared` | 8 (`SHARED_KEYS`) | `index.html`; `top_keys=8` |
| `shared` lifetime writes | rev **144** | `select rev … id='shared'` |
| Inventory items | **35**, all distinct stable ids | `jsonb_array_elements` count |
| Item shape | ~27 keys/item (display + economic + structural + `reservations[]`) | `distinct jsonb_object_keys` |
| Relational ledger | `e10_inventory_movements`, 19 cols, **35 rows (opening balances only)** | `list_tables`; row count |
| Ledger write model | append-only: RLS has **INSERT + SELECT policies only** (`imov_ins`, `imov_sel`), no UPDATE/DELETE | `pg_policies` |
| id → ledger mapping | 35 blob ids ↔ 35 ledger `item_id`, **0 missing, 0 orphans** | join query below |
| id shape | only **5/35** match `^i[0-9]+$`; 30 are seed/import-origin strings | `nonstandard_id_shape=30` |

Inventory is roughly **half** the 6 KB blob. Every inventory write today rewrites the whole 8-section row (write amplification), and — after H2 — a concurrent edit to any other item in the `inventory` section is a *section-level* conflict, because H2's merge granularity is the section, not the item.

---

## 1. Every read of `S.inventory` — call site, computation, sync-vs-snapshot

25 read sites. None requires *synchronous* access to a live authoritative store; every one already reads the in-memory `S.inventory` snapshot that realtime keeps fresh. A cached relational projection would serve all of them identically.

| Line | Call site | Computes | Needs live sync? |
|---|---|---|---|
| 205 | quick-search box | name-filtered slice for the picker | No — snapshot |
| 352 | reservation rollup | `invReserved` per show from `it.reservations` | No |
| 353 | break "available" list | `invAvailable(i)>0` filter | No |
| 418 | overview capital | capital deployed + `realizedMargin(S.inventory)` | No |
| 542 | sold P&L | Σ realized proceeds−cost | No |
| 639 | inventory `<select>` | option list for reserve picker | No |
| 866/867/878 | reserve / mark-sold lookups | `find(x.id===itemId)` before a **mutation** | Reads snapshot; the *write* re-reads fresh (see §2) |
| 1690 | filter dropdowns | distinct `set` / `year` | No |
| 1719/1725/1726 | buy-list by set | demand vs free supply per set | No |
| 1844/1869/1893/1908 | edit / delete lookups | `find(x.id===id)` | Reads snapshot; write re-reads |
| 1984/2021/2030 | reserve/release/sold lookups | item resolve | Reads snapshot; write re-reads |
| 2427 | `invView` | Mine/Everyone owner filter | No |
| 2437/2450 | `_sharedPayload` build | serialize section for cloud write | No |
| 3008/3024 | break-pull lookups | resolve item for `bkAddFromInv` | Reads snapshot; write re-reads |

**Finding:** reads are display/derivation only. The one place correctness depends on freshness is the *write* path, which already re-reads the authoritative copy under CAS (blob) or would under an RPC (relational). So a cached relational projection loses nothing the blob snapshot doesn't already lose.

## 2. Every mutation of `S.inventory` — the write-path inventory 2.7's RPCs must own

Six client mutation entry points. These are exactly the surface a relational cutover must reproduce as RPCs:

| Line | Function | Mutation | Fresh-read guard today |
|---|---|---|---|
| 1744 | `addInv` | `push` new item (`id:'i'+Date.now()`) | blob CAS via `doCloudWrite`/`writeRow` (H2) |
| 1888 | bulk/import add | `push rec` | CAS |
| 1908 | delete | `S.inventory = filter(id!==id)` | CAS |
| 2077 / 2079 | import/restore | `push it` | CAS |
| 2348 | `invEditSave` | `S.inventory[+ix]` field assign | CAS |
| reserve/sold/release | `reserveUnits` / `markSold` / `releaseReservation` | mutate `it.reservations`, `qty`, `soldQty/soldProceeds/soldAt` via **`cloudCommitShared(mutate)`** (read-modify-write on fresh `shared`) | fresh re-read + rev CAS |

`cloudCommitShared` (the reservation spine) is already the shape a relational RPC takes: fetch latest → recompute availability on fresh data → reject if it no longer fits → write. Porting it to relational means the same function body updates a row instead of a JSON path.

## 3. Cache design if relational

An in-memory relational cache would be **`S.inventory` unchanged in shape** — the client keeps the same array of item objects; only its *source* changes from `splitLegacy(sharedRow).inventory` to a projection built from `e10_inventory_movements` (or a materialized `e10_inventory_items` table). Consumers: every read in §1, verbatim. Realtime would subscribe to the inventory table's changes instead of the `shared` row and patch the array by `item_id`.

**Staleness vs the rev-checked blob H2 just built:** the blob is coarser but simpler — one `rev` guards the whole 8-section document, so a stale write is caught atomically but conflicts are section-wide. A relational cache is finer — realtime patches per row, so two users editing *different items* never conflict, and per-item writes stop rewriting 6 KB. The cost is that "consistency" is now per-row and the client must reconcile N row-events instead of one row-version. Net: relational has strictly better contention behavior and strictly more moving parts.

## 4. ID mapping

**Holds for all 35 items, verified:** blob item ids ↔ ledger `item_id (text)` is a clean 1:1 (0 missing, 0 orphans). The ledger already keys on the *stable text id* the blob assigns, so the relational PK is simply that text id — **no renumbering, no serial**. This matters because only 5/35 ids match the `i<timestamp>` pattern; the other 30 are seed/import-origin strings. A migration that regenerated ids would break the ledger's existing `item_id` linkage and every `reservations[].showId`-style reference. Keep the text id as the natural key; the ledger proves it already works.

## 5. Reservations: array-on-item vs child rows

- **Today:** `reservations:[{showId,showLabel,streamerUid,qty}]` nested on each item (added in the reservation pass).
- **Relational option:** `e10_inventory_items` (one row/item) + `e10_reservations` (one row per reservation, FK to item).

Which does **2.8** (reservation depth) less violence to? **Child rows.** 2.8 wants per-reservation lifecycle (created/fulfilled/released, actor, timestamps, partial fulfillment). As a nested array that means rewriting the parent item (and today the whole blob) on every reservation state change, and it can't be queried or RLS-scoped independently. As child rows, a reservation state change is a single-row update, joins cleanly to shows, and `reserved_delta` already exists in the ledger to reconcile against. **Conclusion: reservations are the strongest single argument for relational**, and 2.8 is where the array model actually starts to hurt.

## 6. Rollback of a relational migration

Because the ledger already carries `migration_version` and the blob remains the current source of truth, rollback is clean **if the migration is staged as dual-write, not cutover-in-one-shot**:

1. Migration writes rows into `e10_inventory_items`/`e10_reservations` *projected from the current blob*, tagged `migration_version`.
2. For a grace period the blob stays authoritative and is still written; the relational tables are a shadow (mirror of today's ledger relationship, inverted).
3. Cutover flips the client's read source to the projection and mutation source to RPCs.
4. **Rollback = flip the client source back to the blob and stop writing the tables.** No data is stranded because the blob was never abandoned during the grace period. Drop the tables by `migration_version`.

The irreversible risk is only present *after* the blob stops being written; keep that window explicit and short.

## 7. Residual shared-document write risks that REMAIN after inventory moves

Moving inventory out of `shared` does **not** close H2's problem for the other 7 sections. After inventory leaves, these still ride the single `shared` row under one `rev`:

`comments, todos, streamers, lists, attachments, checklists, repacks` — all still section-level-conflict-bound, all still rewrite the (now smaller) blob on every edit. `checklists` also has its own `e10_checklists` table (9 cols) already, so it is the next candidate. **Implication:** H2's CAS+merge is still load-bearing for the shared row indefinitely; inventory's departure shrinks the blob and removes its hottest writer but does not retire the mechanism. This feeds H2's long-term scope and 2.7's sequencing, not this decision.

## 8. The 2.7 RPC shape under each option — same client contract either way

The client contract is identical regardless of storage:

```
reserveUnits(itemId, showRef, qty)  -> {ok, msg}
releaseReservation(itemId, idx)     -> {ok, msg}
markSold(itemId, qty, proceeds)     -> {ok, msg}
addItem(fields) / editItem(id, patch) / deleteItem(id) -> {ok, msg}
```

- **Blob:** the RPC (or client fn) `fetch shared → recompute on fresh → mutate the JSON path → CAS-write` — exactly what `cloudCommitShared` does today.
- **Relational:** the RPC `UPDATE the item row / INSERT a reservation row / append a movement`, in one transaction.

Because the signature and `{ok,msg}` result are the same, **the client does not know or care which backs it.** This equivalence is the whole basis for the recommendation in §10.

## 9. Pass-impact table

For each downstream pass, what each option does to it (delete / shrink / keep):

| Downstream | (a) Migrate now | (b) Keep blob + blob-side machinery | (c) Keep blob behind migration-ready RPC contracts |
|---|---|---|---|
| **2.7a machinery** (mutation-locking layer) | **deletes** — RPCs are the layer | **keeps** — must build blob-side locking (H2's `cloudCommitShared` extended) | **shrinks** — contracts exist; only the body swaps at cutover |
| **2.10 scope** (per-item concurrency / history) | **deletes** — per-row realtime + ledger give it for free | **keeps** — still section-level; per-item history needs bespoke work | **keeps now, deletes at cutover** |
| **2.11** (reservation depth / 2.8 lifecycle) | **shrinks** — child rows make it a row update | **keeps** — nested-array rewrite pain remains | **shrinks at cutover**; unchanged before |
| **2.12** (reporting / cross-entity queries) | **shrinks** — SQL joins vs blob scans | **keeps** — client-side aggregation over the array | **keeps now, shrinks at cutover** |

## 10. Total implementation cost per option (engineer-days, honest ranges)

Comparing *total* cost — schema + RPCs + cache + realtime + rewriting ~25 reads / 6 writes + migration + rollback + RLS + tests — not row count.

| Option | Eng-days | What you pay for |
|---|---|---|
| **(a) Migrate now** | **6–10** | 2 new tables + RLS, project-from-ledger, 6 mutation RPCs, in-memory relational cache, per-row realtime, rewrite all read/write sites, staged dual-write migration + rollback, tests |
| **(b) Keep blob + build blob-side machinery** | **2–3** | Extend `cloudCommitShared` for all mutations, blob-side reservation locking, buy-list; **inherits** write-amplification + section-conflict ceiling forever |
| **(c) Keep blob behind migration-ready RPC contracts** | **3–5** | Wrap all 6 mutations behind the §8 client contract writing the blob today; front-loads the 2.7 client surface so cutover is a server swap; no data move now |

### Recommendation: (c)

Keep the blob authoritative now; route every inventory mutation through the §8 RPC-shaped client functions. The ledger already proves the id mapping (§4) and the append-only pattern; `cloudCommitShared` already *is* the contract (§2, §8). Pay the ~3–5 days to lock the client contract, and defer the full 6–10-day migration until inventory write-contention or real query needs (per-item history, cross-entity reporting, 2.8 reservation lifecycle) actually force it. At that point cutover is a server-side swap the client can't see.

### The two strongest arguments against (c)

1. **It postpones the drift/amplification tax that only grows.** As long as the blob is authoritative and the ledger is written behind it, the two can diverge, and every pass touching inventory keeps paying the "rewrite 6 KB + section-level conflict" cost that H2's granularity structurally cannot fix. If inventory editing volume climbs, (a)'s per-row model is the correct end state and (c) is just interest on a loan you'll take anyway. **2.8 (reservations, §5) is the concrete point where the array model starts actively hurting** — if 2.8 is imminent, migrate now.
2. **Migration-ready contracts without moving data is speculative abstraction.** If 2.7's real relational schema differs from what the contract assumes today, the "migration-ready" functions get rewritten at cutover anyway — you paid for indirection that bought nothing. Strict YAGNI says migrate when forced (option a) or stay plainly blob-side (option b), and skip the middle.

**Net:** (c) is the right call *if* 2.8/2.12 are not the very next passes. If they are, jump to (a) and skip the interest.
