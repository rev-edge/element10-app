# Element 10 — PF_M1_DELTA.md
## What PF-M1 requires changing in the pending product-first package (later)

**Status:** **APPROVED input** (PF-M1.1) — companion to `PRODUCT_SUPPLY_MODEL.md`. **Delta fully applied** during the canonical merge (folded into `PRODUCT_FIRST_WORKFLOW.md` and the approved governance docs). Retained as approved history of what was applied; **no longer a pending to-apply list**.

**Current-use note (2026-07-27):** this remains historical model-delta evidence.
Use `../OPERATOR_LIFECYCLE.md` for operator sequencing and
`../UX_WORKFLOW_CONTRACT.md` for UI workflow acceptance. Neither changes the
approved PF-M1 arithmetic.

**PF-M1.1 correction summary (this revision):** added requirement-conservation invariant `req_planned + req_confirmed ≤ req_required` with promotion-as-move and Prepare = `confirmed=required ∧ planned=0`; replaced source arithmetic with net/effective definitions (`effective_ordered`, `net_received`, `available_remaining_expected`, `open_expected`); defined `lot_on_hand` from all posted movements (receipt/reversal/consumption/reversal/count-adj/damage/transfer/correction); corrected lot invariant to `confirmed ≤ on-hand` (not `≤ free`); fixed Example B (removed `−?` placeholder, exact transitions); added real multi-lot Example I and explicit partial-reservation Example J with `allow_partial` policy; corrected §7 PO-cancel/line-reduction/reservation-release/receipt-reversal effects (V1 block-by-default); replaced substitution "re-point" with history-preserving release+create / `replaces_requirement_id`; restored Product Master (release) vs Product Configuration (packaging variant) with Topps Chrome example; added cost-adjustment-vs-preparation ruling (not auto-invalidating). Domain architecture from PF-M1 unchanged.

---

## Deltas to `PRODUCT_FIRST_WORKFLOW.md`

1. **Rename demand object to `ProductRequirement`** everywhere; it is a child of Planned Show with optional Planned Break attribution (not a break-only field). Remove "planned allocation is a Show/Break claim" looseness in favor of the demand/expected/planned/received/confirmed/consumption chain.
2. **Multi-product Breaks** — replace any single-product-per-break implication with "a Break has multiple ProductRequirements"; checklist pin is **per ProductRequirement**, not `0..1 ChecklistForUse` on the Break.
3. **Packaging normalization** moves **into the model** (base unit, allowed units, conversions with version) — not deferred.
4. **Cost-basis lineage** (PO line → receipt → lot → additive adjustments; Prepared captures effective evidence) belongs in the first model, not D3/D6-only.
5. **Catalog seam** — split "Product Master" references into **Platform Card Catalog** vs **Organization Product Master**; add stable external identifiers + optional future platform-product reference seam.
6. **Overcommit** — state explicitly prohibited in V1 (remove any "flag overcommit" language).

## Deltas to `D2_PLAN_REVISION_PROPOSAL.md`

7. **Capability impact** — decouple from A6b entirely; fine leaves (`product.write`, `purchasing.write`, `format.manage`, `format.approve`, `checklist.annotate`, `program.manage`) become a **later additive migration after vocabulary stabilizes**. Program Templates use **`session.write`** initially; `program.manage` deferred unless a real authorization boundary emerges. A6b proves only the stable legacy six action + six module keys (see Track A ruling).
8. **Checkpoint sequencing** — do not finalize C4–C10 numbering here; sequencing is the later **governance pass**, not PF-M1. Mark the earlier proposed sequence as superseded-pending-governance.
9. **Acceptance matrix** — add the concurrency, partial-receipt, cost-adjustment, and multi-product-mixer rows from the PF-M1 test matrix.

## Deltas to `D3_INPUT_CONTRACT.md`

10. **Prepared vN inputs** — express reservations as **ConfirmedReservations against lots** with captured effective cost evidence and per-ProductRequirement checklist version pins; consumption lineage chain named explicitly.
11. Live controls, buyer identity/trades remain the **D3 contract pass** (pass 2), not PF-M1 — no change here beyond referencing ConfirmedReservation/lot lineage.

## Deltas to `CONTEXT.md`

12. Update the pending-proposal note to reference PF-M1 as the settled model layer once approved; keep it non-superseding until "Product-first workflow approved" (final merge pass).

---

## Sequencing (Trent's revised 5-step path)

1. **PF-M1 model pass** (this) — demand/supply/cost/checklist cardinality/cancellation/concurrency. → "Product supply model approved."
2. **D3 contract pass** — Prepared/runtime boundary, Live controls, buyer identity/trades.
3. **Governance pass** — capability leaves, catalog seam finalization, checkpoint decomposition.
4. **Merge** approved results into the product-first package.
5. **Formal product-first approval.**

A6b proceeds independently (Track A ruling) and is **not** blocked on any of the above.
