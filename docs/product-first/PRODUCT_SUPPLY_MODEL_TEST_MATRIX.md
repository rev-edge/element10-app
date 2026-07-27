# Element 10 — PRODUCT_SUPPLY_MODEL_TEST_MATRIX.md
## PF-M1.1 worked examples (exact quantities before → after each transition)

**Status:** **APPROVED input** (worked examples) to the canonical product-first workflow — companion to `PRODUCT_SUPPLY_MODEL.md`. Arithmetic **unchanged during the canonical merge**; retained as approved evidence. Latest corrected copy (Examples D/K/L, direct-vs-promotion). All quantities in normalized base units unless a unit is named. Prepare gate: `req_confirmed = req_required` **and** `req_planned = 0`. Lot invariant: `lot_confirmed_reserved ≤ lot_on_hand` (**total on-hand**, not free).

These worked examples prove domain transitions, not operator navigation. When a UI
implements one of them, pair it with the task-loop scenarios in
`../OPERATOR_LIFECYCLE.md` and `../UX_WORKFLOW_CONTRACT.md`, including the
immediate result, continuation, review, Cancel, resume, and conflict recovery.

---

## Example A — Multi-product mixer Break

Planned Show S, one mixer Break B, two Product Configurations of two different Product Masters.

- **PR-1**: config *Topps Chrome — Hobby Box*, `req_required`=6, checklist TC-2026-v3, purpose primary.
- **PR-2**: config *Pokémon 151 — Booster Box*, `req_required`=4, checklist P151-v2, purpose mixer.

Supply: PO-1/L1 = 12 boxes TC → Lot-A; PO-2/L2 = 4 boxes P151 → Lot-B.

| Step | PR-1 planned/confirmed | PR-2 planned/confirmed |
|---|---|---|
| allocate | 6 / 0 | 4 / 0 |
| receive L1=12, L2=4 | 6 / 0 | 4 / 0 |
| promote (planned→confirmed) | 0 / 6 (Lot-A) | 0 / 4 (Lot-B) |
| Prepare gate | planned 0, confirmed 6=6 ✓ | planned 0, confirmed 4=4 ✓ → Show preparable |

This example models **two products = two ProductRequirements**; a third would follow identically. Each pins its own checklist version + lot lineage.

---

## Example B — Partial receipt (blocks Prepare) — exact arithmetic

Config *Topps Chrome — Hobby Case* (base unit = case). Show A, PR-A `req_required`=4.

**Initial (ordered + allocated):**
- `effective_ordered` = 12
- `net_received` = 0
- `remaining_expected` = 12
- active PlannedAllocation = 4 → `committed_expected` = 4
- `open_expected` = 12 − 4 = 8
- `req_planned` = 4, `req_confirmed` = 0 (planned+confirmed = 4 = required ✓)

**Receive 2 into Lot-1 and promote 2:**
- `net_received` = 2
- `remaining_expected` = 12 − 2 = 10
- active PlannedAllocation 4 → **2** (promotion moves 2 planned→confirmed)
- `committed_expected` = 2
- `open_expected` = 10 − 2 = **8**
- Lot-1 `lot_on_hand` = 2, `lot_confirmed_reserved` = 2, `lot_free` = 0
- `req_planned` = 2, `req_confirmed` = 2 (planned+confirmed = 4 = required ✓)
- **Prepare blocked:** `req_confirmed`(2) ≠ `req_required`(4), `req_planned`(2) ≠ 0.

No placeholder, no double-count: the 2 received cases moved remaining-expected→on-hand→confirmed; the 2 still owed remain expected (planned) only.

---

## Example C — Concurrent full reservation (last free quantity)

Lot-1 `lot_on_hand`=2, `lot_free`=2. Operator X requests 2, Operator Y requests 2 (both full, concurrent).

- Both read stale `lot_free`=2.
- X acquires guard, rereads free=2, commits 2 → `lot_free`=0, `lot_confirmed_reserved`=2, key kX.
- Y acquires guard, rereads free=0, validates → cannot fulfill full 2 → **deterministic conflict**.
- Total confirmed = 2 = `lot_on_hand`. Invariant `lot_confirmed_reserved ≤ lot_on_hand` holds. Retry kX = same result, no duplicate hold.

---

## Example D — Cancel an unprepared Show (both commitment kinds)

Show S: PR-1 `req_required`=6, `req_planned`=4 (vs PO open), `req_confirmed`=2 (Lot-1). No Prepared version. (Starting state is valid: planned 4 + confirmed 2 = 6 = required.)

Cancel S (atomic, idempotent): cancel PR-1; release PlannedAllocation 4 → `open_expected` +4; release ConfirmedReservation 2 → `lot_free` +2; close dependent items; retain history (additive `cancelled` events).

Before: `open_expected` X, `lot_free` 0. After: `open_expected` X+4, `lot_free` 2. No orphaned commitments; no quantity lost.

---

## Example E — Remove one Break from a mixer Show

Show S: Break B1 (PR-1=6), Break B2 (PR-2=4), Show-level PR-0=2. Remove B2.

- Release only PR-2's commitments (planned/confirmed) → quantities return to source pools.
- PR-1 (B1) and PR-0 (Show-level) untouched.
- Recompute Show readiness (now PR-0 + PR-1).
- Removing the last Break leaves PR-0; the Planned Show is **not** deleted.

---

## Example F — Receipt reversal after Prepared (blocked by V1 policy)

Show S Prepared v1: PR-1 `req_required`=4, `req_confirmed`=4 (Lot-1, `lot_on_hand`=4). Attempt to reverse a receipt removing 2.

- The reversal would make `lot_confirmed_reserved`(4) > `lot_on_hand`(2) → **V1 default: blocked** at the authoritative boundary until the affected 2 units of reservation are explicitly released/reassigned (or an authorized correction workflow does both atomically).
- Authorized correction path (atomic): release 2 reservation → `req_confirmed` 4→2; post reversal → `lot_on_hand` 4→2, `lot_confirmed_reserved` 2, `lot_free` 0.
- Result: `req_confirmed`(2) < `req_required`(4) → **Prepared v1 → stale**, lifecycle → Created, step → Preparing, **Recovery** raised (shortfall 2). v1 retained; re-prepare → v2.

---

## Example G — Cost adjustment (additive; readiness ruling)

Lot-1 received 4 cases @ landed $1,847/case (Receipt R1). Prepared v1 captured Lot-1 refs + effective cost. Late freight +$120 arrives.

- Add cost-adjustment event CA1 (+$120 across Lot-1) — additive; R1 unchanged.
- Prepared v1's captured evidence (R1 at issue) **unchanged**; effective basis now R1+CA1 for new preparations.
- **Readiness:** freight is not a policy-declared preparation-critical threshold → operational readiness **not** invalidated. (If org policy declared a margin threshold critical and it were breached, economics/margin approval reruns and preparation invalidates.)
- D6 receives both R1 and CA1 lineage; execution not rewritten.

---

## Example H — Core zero-Break Show

Core (cards-off) Show C, Show-level PR-C: config *Sealed Wax Box*, `req_required`=10. No Breaks/checklist/chase/Cards terms.

- Allocate 10 vs PO open → `req_planned`=10.
- Receive 10 into Lot-C; promote → `req_confirmed`=10, `req_planned`=0; `lot_free` decremented by 10.
- Prepare gate: confirmed 10=10, planned 0 ✓ → preparable with **zero Breaks**.
- Same allocation/reservation/concurrency/cancellation invariants as cards Shows.

---

## Example I — Single ProductRequirement across multiple lots

PR-M: config *Topps Chrome — Hobby Box*, `req_required`=6. Two lots: Lot-A `lot_on_hand`/`free`=4, Lot-B `on_hand`/`free`=5.

**Reserve across lots:**
- Reserve 4 from Lot-A → Lot-A `confirmed_reserved`=4, `free`=0.
- Reserve 2 from Lot-B → Lot-B `confirmed_reserved`=2, `free`=3.
- `req_confirmed` = 4 + 2 = 6 = `req_required`; `req_planned`=0 → **Prepare quantity gate passes.**

**Release part of one reservation (Lot-B's 2):**
- Lot-B `confirmed_reserved` 2→0, `free` 3→5. **Lot-A unchanged** (`confirmed_reserved`=4, `free`=0).
- `req_confirmed` 6→4 < required → shortfall 2, demand unmet (no auto-revert to planned).

Both invariants hold per lot: `lot_confirmed_reserved ≤ lot_on_hand`.

---

## Example J — Explicit partial reservation (`allow_partial`)

PR-P `req_required`=6, starting `req_planned`=0, `req_confirmed`=0 (direct reservation path — no active planned commitment). Available: Lot-A `free`=4 only. Caller requests 6 with `allow_partial=true`.

- Result: requested=6, confirmed=4 (Lot-A), remaining_unfulfilled=2, lots_used=[Lot-A:4], requirement state `req_confirmed`=4, `req_planned`=0 (direct path, nothing to release).
- Lot-A `confirmed_reserved`=4, `free`=0.
- Retry same idempotency key → identical {confirmed 4, Lot-A:4}; no duplicate hold.
- A **full** (default) request for 6 against `free`=4 → **all-or-nothing failure** (no silent partial).

**Reservation-path rule (conservation-preserving):**
- **Direct reservation** with no active planned commitment leaves `req_planned`=0 and raises `req_confirmed` (this example).
- **Promotion** of active planned quantity atomically **releases that same planned quantity** as it confirms stock (Example B: planned 4→2 as confirmed 0→2).
- Either path preserves `req_planned + req_confirmed ≤ req_required`.

---

## Example K — PO-line cancellation before receipt

PO-1/L1 for config *Topps Chrome — Hobby Case*: `effective_ordered`=12, `net_received`=0. Show A PR-A `req_required`=4, `req_planned`=4 (allocated vs L1), `req_confirmed`=0. Cancel L1 before any receipt.

- L1 `available_remaining_expected` → 0 (historical ordered=12 stays visible).
- Release active PlannedAllocation 4 → `req_planned` 4→0; `committed_expected` 4→0.
- `req_confirmed`=0 **unaffected** (none came from unreceived qty) — PO cancellation never reduces confirmed inventory.
- PR-A **remains unmet demand** (`req_required`=4, planned 0, confirmed 0) → **Attention** (first-time incomplete, not a regression).
- History retained (additive `cancelled` event on L1 + released allocation).

---

## Example L — Product substitution (history-preserving)

**L1 — same Configuration, different supply:** PR-1 confirmed 4 from Lot-A; Lot-A found damaged. Release Lot-A reservation (4→0; Lot-A `free`+4) → create **new** ConfirmedReservation 4 against Lot-C; retain replacement linkage. PR-1 identity unchanged; no re-point. `req_confirmed` returns to 4.

**L2 — different Configuration:** PR-2 was *Pokémon 151 Booster Box* ×4; substitute to *Pokémon 151 ETB* ×4. Supersede/cancel PR-2; create replacement **PR-2′** referencing the new Configuration with `replaces_requirement_id=PR-2`; rerun checklist pin, format compatibility, allocation, reservation, readiness, approval; invalidate current Prepared evidence. Both PR-2 (superseded) and PR-2′ (active) retained.

---

## Invariant coverage map

| Invariant (§5/§6/§7) | Example(s) |
|---|---|
| `lot_confirmed_reserved ≤ lot_on_hand` (total on-hand) | C, F, I |
| `committed_expected ≤ available_remaining_expected` | B |
| requirement conservation `req_planned + req_confirmed ≤ req_required` | B, A, H |
| promotion moves planned→confirmed (no add) | A, B, H |
| no overcommit (V1) | B, C, I |
| partial planned + partial confirmed | B |
| reserve across multiple lots | **I** |
| no double-count on receive | B |
| atomic + idempotent promotion/reservation | C, J |
| partial fulfillment explicit (`allow_partial`) | **J** |
| Prepare requires confirmed = required AND planned = 0 | A, B, H, I |
| concurrency compare-and-set (full) | C |
| receipt reversal under concurrency boundary + V1 block policy | F |
| PO cancellation (no confirmed reduction) | **K** |
| demand-side cancel returns quantity | D, E |
| substitution history-preserving (no re-point) | **L** |
| additive cost adjustment + readiness ruling | G |
| core zero-Break parity | H |
