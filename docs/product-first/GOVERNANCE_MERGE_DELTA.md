# Element 10 — GOVERNANCE_MERGE_DELTA.md
## Exactly what changes in the four pending product-first docs at the later merge

**Status:** **APPROVED input** (merge delta) — **delta fully applied** during the canonical merge into `PRODUCT_FIRST_WORKFLOW.md`, `D2_PLAN_REVISION_PROPOSAL.md`, `D3_INPUT_CONTRACT.md`, and `CONTEXT.md`. Retained as approved history of the applied edits; **no longer a pending to-apply list**. (Original note preserved below.) The four pending product-first proposal docs (`PRODUCT_FIRST_WORKFLOW.md`, `D2_PLAN_REVISION_PROPOSAL.md`, `D3_INPUT_CONTRACT.md`, `CONTEXT.md`) are **not** edited now (only the four approved D3 cleanups were already applied to `D3_INPUT_CONTRACT.md`). This file lists the merge-time edits so the merge is mechanical.

**Current-use note (2026-07-27):** this remains historical merge evidence.
Current operator-job and workflow-completeness rules live in
`../OPERATOR_LIFECYCLE.md` and `../UX_WORKFLOW_CONTRACT.md`.

---

## Global sweeps (all docs)
- **Checkpoint-namespace sweep:** replace **every** stale `C4`/`C5`/`C6`/single-large-C4 reference that means *product-first work* with the dedicated **`PF-C*`** namespace (per `PRODUCT_FIRST_CHECKPOINTS.md`). Accepted **C1–C3** references stay as-is (they mean the accepted planning prototype). Do **not** edit C1–C3 source. Note that future prototype comments should refer to **object/workflow names**, not globally ambiguous checkpoint numbers.
- **Authority layering sweep:** anywhere capabilities are named, point to `CAPABILITY_CROSSWALK.md` as authoritative and adopt the **four-concern** model (RLS / entitlement-visibility / action-capability / legal-policy). Remove any implication that `mod.*` grants read authority or that `act.reporting_export` grants money/cost read.

## To `PRODUCT_FIRST_WORKFLOW.md`
1. Adopt PF-M1.1 vocabulary verbatim.
2. **Corrected object dependencies:** ProductRequirement is Show-owned at creation (optional Break attribution); **no generic later "assign to Show"** — Product/recipe assignment creates/updates requirement children. Program Templates hold **blueprint references**, not live requirement rows; generation creates new Show-owned instances with lineage that may diverge.
3. **Checklist timing:** ChecklistForUse can be approved before requirements exist; the **version pin happens at requirement create/change**.
4. Insert the **catalog seam** (governance §6) + cards-off behavior.
5. Insert **Attention/Recovery** definitions (governance §5) with current-version Recovery scoping.
6. Add the **warm/routine path** + same-night + weekly + Schedule-first (governance §9); mark the long chain as **cold-start only**.
7. Reference the **cross-checkpoint invariant set** (I1–I17) as the regression contract.

## To `D2_PLAN_REVISION_PROPOSAL.md`
8. Replace the capability-impact table with a pointer to **`CAPABILITY_CROSSWALK.md`**; adopt its **v1 rulings** (no `product.read`/`program.manage`; `session.write` for prepare + program templates in v1; `purchasing.write`/`inventory.receive`/`checklist.approve` distinct; `format.approve`/`session.approve`/`checklist.annotate` deferred decision-points; `money.read`/`cost.read` need a privacy ruling).
9. Replace the single-C4 sequence with the **PF-C1…PF-C21** decomposition + four-way acceptance (PA/IC/CR/AP); mark the earlier sequence superseded. Note the ordered **Prepared-issuance (PF-C16) → maker-checker approval (PF-C17)** boundary and that production approval requires the distinct **`session.approve`** leaf (not `session.write`).
10. State A6b decoupling explicitly (legacy six + six now; fine leaves later additive).
11. Add the **cost-first** checkpoint coverage (PF-C4/C5/C6/C9/C13/C16) and the **cost-provenance + immutable Prepared cost** invariant (I14) — immutable Prepared cost evidence is captured at issuance (PF-C16).

## To `D3_INPUT_CONTRACT.md`
12. Already carries the four approved cleanups (§-refs→§10; acting-principal audit; global `act.live_run` on live-control mutations; Case-Hit toggle default from org/show config, tags as prerequisite). Merge-time: reference `CAPABILITY_CROSSWALK.md` for capability labels; confirm the **prototype-vs-authoritative** split (RLS/atomicity/concurrency/privacy are AP, not prototype claims).

## To `CONTEXT.md`
13. Update the pending-proposal note: PF-M1.1 model **approved**, D3 contract **approved**, governance **pending**; canonical only at "Product-first workflow approved" (final merge + approval).

---

## Canonical reservation rule (must appear in merged docs, not only the test matrix)
- **Direct reservation** from free on-hand stock may occur with **`req_planned = 0`**.
- **Promotion** atomically **decreases active planned quantity by exactly the quantity confirmed**.
- A reservation must **never** cause `req_planned + req_confirmed > req_required`.
- **PlannedAllocation is optional** — not a prerequisite for every ConfirmedReservation.

## Canonical Attention/Recovery rule (must appear in merged docs)
- Attention = valid-but-incomplete; Recovery = regressed/stale/failed/conflicted/interrupted, **scoped to the current preparation/execution version**.
- No unresolved current-version blocking Recovery passes **Prepare** or **Start Live**.
- Shared resolver registry; same key → same destination; closure evidence + return-context.

---

## Sequence position
1. PF-M1.1 model — **approved**
2. D3 contract — **approved**
3. Governance (this corrective pass) — **pending** ("Product-first governance approved")
4. Merge — applies the sweeps + deltas above
5. Formal product-first approval

A6b proceeds independently throughout (Track A ruling).
