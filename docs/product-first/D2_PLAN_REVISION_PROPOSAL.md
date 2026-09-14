# Element 10 — D2_PLAN_REVISION_PROPOSAL.md
## Proposed revisions to the approved D2 plan (design-only)

**Status — reconciled to canonical (merge pass).** The D2 changes below are folded into the canonical `PRODUCT_FIRST_WORKFLOW.md`, which is the single document that carries the pending "Product-first workflow approved." gate; this document is retained as the D2-delta record and does not independently await approval. Superseded specifics are marked. Does not supersede the approved D2 plan or accepted C1–C3 until the canonical workflow is approved. A6b remains frozen and independent.

**Current-use note (2026-07-27):** retained as historical delta evidence. For
current operator sequencing and UI completeness, use
`../OPERATOR_LIFECYCLE.md` and `../UX_WORKFLOW_CONTRACT.md`. Those documents do
not revive superseded D2 checkpoint meanings.

---

## 1. Exact changes required in D2

| D2 section | Change | Type |
|---|---|---|
| §1 terminology | Add Product Master, Product Configuration/SKU, Vendor, PO/PO line, Receipt/Lot, Planned Allocation vs Confirmed Reservation, BreakFormatTemplate, ProductFormatRecipe, Program Template. | NEW |
| §2 lifecycle | Unchanged canonical lifecycle. Add invalidation triggers: checklist-version change, reservation drop below required, format-recipe/template-version change. | EXTEND |
| §3 entity model | Replace flat "allocated/reserved" booleans with expected-supply (PlannedAllocation) vs on-hand (ConfirmedReservation) split; add Product/PO/Receipt/Lot; **allocation/reservation attach through Show-owned ProductRequirements** (0..1 Break attribution). *(Supersedes the earlier "session-owned" phrasing — canonical owner is the ProductRequirement, created on exactly one Show.)* | REVISE |
| §4 readiness | Split inventory checks: "planned allocation exists (expected)" advisory-until-schedule vs "confirmed reservation ≥ required (on-hand)" blocking for Prepared/Start Live. Add "Product assigned" blocking check (Schedule-first exception → Attention). Add "approved format attached" + "approved checklist version attached" (cards). | REVISE |
| §5/§6 capability | Add product/PO/format/chase actions (see §5 capability impact); keep C1-surface leaves. | EXTEND |
| §8 screen architecture | Add Product workspace as primary orchestration surface; Schedule remains a view, not the conceptual origin. | REVISE |
| new | Program Template (recurring programming) object + weekly instantiation. | NEW |
| §15.3 | Unchanged (Show plan ↔ `e10_live_sessions` via handoff + `source_show_ref`; runtime breaks via `live_session_id`). | KEEP |

---

## 2. What remains accepted from C1–C3 (no rework)

- **C1** — Schedule workspace, hash routing + route auth, Planned Show creation, Draft/Scheduled computed labels over Created. *(Schedule remains valid; it is reframed as one entry point, not the sole origin. No code change required to accept product-first; Product workspace implementation begins in the approved PF-C sequence.)*
- **C2** — computed readiness engine, canonical lifecycle projection, Prepared vN append-only history, cancellation disposition, distinct core dataset, capability separation, computed conflict.
- **C3** — Break plan/format workbench, editable slots/tiers, integer-cents money, a11y, single zero-break blocker, guarded reopen, terminal cancellation.

All three stay accepted; product-first is **additive** (new surfaces + new objects), not a rewrite of C1–C3 behavior.

---

## 3. Checkpoint sequence — SUPERSEDED by PF-C1 … PF-C21

> **The former C4–C10 product-first sequence in this section is superseded** by the approved governance v3 checkpoint matrix in `PRODUCT_FIRST_CHECKPOINTS.md` (**PF-C1 … PF-C21**, dedicated namespace). Old product-first `C4/C5/C6` meanings are **not** reused. Accepted **C1–C3** remain valid where they refer to the accepted planning prototype. See `PRODUCT_FIRST_WORKFLOW.md` §10 for the canonical pointer and evidence categories (PA/IC/CR/AP).

The C4–C10 draft is retained below only as historical provenance for the merge manifest; it carries **no current authority**.

<details><summary>Historical C4–C10 draft (no authority)</summary>

- **C4 — Product workspace + inventory foundation** (was: Inventory allocation). Product Master + Configuration, quantities (expected/received/on-hand/allocated/reserved/free), PO create, receiving, movement history, standalone inventory. Derived condition chips (no manual status).
- **C5 — Checklist staging + chase annotation** (was: checklist detour). Select/stage/overlay/approve → ChecklistForUse; mass chase-tagging (overlay); version pinning + invalidation.
- **C6 — Break formats: templates + product recipes.** Reusable template versions; product-specific recipe drafts (LLM-suggested, human-accept); attach approved recipe/version to a Planned Break; "save as new template version" (never overwrite history).
- **C7 — Programming + scheduling.** Program Templates → weekly instantiation; assign Product + format to concrete Planned Shows; Schedule-first exception (Product-not-assigned Attention).
- **C8 — Allocation → reservation → Prepare gating.** Planned allocation vs confirmed reservation; partial-receipt shortfalls; promote allocations to reservations without double-count; block Prepare/Start-Live until sufficient confirmed reservations.
- **C9 — Approval + Attention/Recovery + Prepared handoff** (was C6). Approval dimension, invalidation, resolver registry consistency, read-only Streamer handoff.
- **C10 — Hostile isolation + cards-off determinism + regen.** Two-org isolation (incl. Products/POs/overlays/templates/costs), deterministic cards-off, regenerate live mirror + archives.

Each checkpoint keeps its own browser verification + explicit stop gate + "Cn accepted."

</details>

---

## 4. Revised browser acceptance matrix (product-first additions)

Carries the 17 required design-acceptance scenarios from the gate prompt. Key rows:

1. New Product Master + Hobby config, zero stock.
2. Create PO → expected qty up, on-hand stays zero.
3. Allocate incoming Product to a Planned Show without representing it as received.
4. Partial receipt exposes remaining shortfall.
5. Promote satisfied allocations → confirmed reservations, no double-count.
6. Block Prepare + Start Live until sufficient received stock reserved.
7. Stage + approve checklist, mass-tag chase cards.
8. Use tags during Significant Pull / Case Hit logging (D3 input).
9. Product-specific format draft → approve → attach to Planned Break.
10. Save live/inline format edits as new template version without changing history.
11. Instantiate next week from Program Template; change only Product assignments.
12. Resolve Checklist blocker from both UI locations → same detour (resolver registry).
13. Buyer lookup immediately filters Live grid (D3).
14. Trade action appears only after eligible slots selected (D3).
15. Every Live toggle → visible + auditable behavior (D3).
16. Two orgs, similar Product names, cannot see/reuse each other's private costs/POs/overlays/allocations/templates.
17. Cards-off org retains Product/PO/inventory/programming/fulfillment without Cards terms or Break requirements.

---

## 5. Capability impact — SUPERSEDED by CAPABILITY_CROSSWALK.md v1 rulings

> **The table below is superseded.** The authoritative capability vocabulary and v1 rulings live in `CAPABILITY_CROSSWALK.md` (four-concern authority model) and are summarized in `PRODUCT_FIRST_WORKFLOW.md` §8. In particular the earlier recommendations here are **corrected** by the approved rulings: **no `product.read` in v1** (inventory read scope); **no `program.manage`** (Program Templates use `session.write`); **preparation issuance uses `session.write`**; **chase annotation uses checklist staging/editing authority**; **`format.approve` deferred** until its maker-checker boundary exists; **`session.approve`** is the distinct production maker-checker leaf (later-additive, not persisted, human ruling required) and **`session.write` must never be the production checker authority**; `inventory.receive` / `purchasing.write` / `checklist.approve` remain defensibly distinct.

The original impact table is retained below as historical provenance only; it carries **no current authority**.

<details><summary>Historical capability-impact draft (no authority)</summary>

### Frozen leaves (historical framing) `session.read/write/prepare/approve`, `break.configure`, `inventory.read/reserve/receive`, `checklist.stage/approve`, `money.read`.

| New action | Exact existing leaf? | Temp legacy authority | Recommended new leaf | Entitlement | Default roles | Overload risk |
|---|---|---|---|---|---|---|
| Create/edit Product Master | none fits | `act.inventory_edit` (interim) | `product.write` | core | Admin, Manager | **High** — do NOT reuse `inventory.receive`/`inventory.reserve` (those are stock ops, not catalog) |
| Create/edit Product Configuration | none | `act.inventory_edit` (interim) | `product.write` | core | Admin, Manager | High (same) |
| Create/manage PO | none | `act.inventory_edit` (interim) | `purchasing.write` | core | Admin, Manager | **High** — distinct from receiving; a receiver ≠ a purchaser |
| Receive PO → on-hand | `inventory.receive` ✓ | — | — | core | Admin, Manager, Ops | fits exactly |
| Reserve on-hand | `inventory.reserve` ✓ | — | — | core | Admin, Manager, Ops | fits |
| Read inventory/product | `inventory.read` ✓ | — | (`product.read` optional) | core | broad | fits |
| Manage Break format template | `break.configure` (partial) | `break.configure` | `format.manage` (recommended) | cards | Admin, Manager | Medium — template versioning is broader than per-break configure |
| Accept LLM format draft | none | `break.configure` (interim) | `format.approve` | cards | Admin, Manager | Medium |
| Mass chase-tag (overlay) | `checklist.stage` (partial) | `checklist.stage` | `checklist.annotate` (recommended) | cards | Admin, Manager | Low–Medium |
| Manage Program Template | none | `session.write` (interim) | `program.manage` | core | Admin, Manager | Medium — recurring structure ≠ single session write |

**Do NOT** silently redefine `inventory.receive` as permission to create Products or POs. Editing the frozen catalog requires an explicit **Track A decision** (see §6).

</details>

---

## 6. Track A handoff items — current contract

**A6b remains frozen and independent, and is not blocked by product-first.** Product-first fine capabilities are **later-additive decisions**, not pending installations into A6b.

**Capability rulings (v1, from `CAPABILITY_CROSSWALK.md`):**
- **No `product.read` and no `program.manage` in v1.**
- **Program Templates and preparation issuance use `session.write`** in v1.
- **Production checker approval requires the later-additive `session.approve`** (not persisted; human ruling required before its additive migration; `session.write` must never be the production checker authority).
- **`purchasing.write`, `inventory.receive`, and `checklist.approve`** remain justified **future production** authorities (distinct before production).
- **`money.read` and `cost.read`** require explicit **privacy rulings**.
- **`trade.commit` and `offer.buyback`** are required only **before those features become operational**.

**Future implementation contracts for Track A** (after the appropriate foundation gates; none blocks A6b):
- Product/PO/Receipt/Lot data model — relational shape, cost-basis immutability, lot tracking.
- PlannedAllocation vs ConfirmedReservation — persistence + no-double-count / conservation invariant.
- Program Template — storage + instantiation lineage to Planned Shows.
- Format template versioning — immutable version history; "save as new version" semantics.
- Checklist version pinning + invalidation propagation to Prepared vN.

See the collapsed historical block in §5 for the earlier (superseded) proposed-leaf table — it carries **no current authority**.

<details><summary>Historical Track A handoff draft (no authority)</summary>

1. **New capability leaves** beyond the frozen 11: `product.write`, `purchasing.write`, `format.manage`, `format.approve`, `checklist.annotate`, `program.manage` (+ optional `product.read`). Approve set + names, or map to interim legacy authorities. **Blocks A6b Step 3 catalog install.**
2. **Product/PO/Receipt/Lot data model** — confirm relational shape vs abstract service; cost-basis immutability + lot tracking.
3. **Planned allocation vs confirmed reservation** — persistence model + no-double-count invariant.
4. **Program Template** — storage + instantiation lineage to Planned Shows.
5. **Format template versioning** — immutable version history; "save as new version" semantics.
6. **Checklist version pinning + invalidation** propagation to Prepared vN.

Track A note: **do not derive A6b Step 3 finer catalog from this proposal until "Product-first workflow approved."** The 11-leaf catalog remains frozen; these are additions requiring a ruling.

</details>
