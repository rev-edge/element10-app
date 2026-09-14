# Element 10 — PRODUCT_SUPPLY_MODEL.md
## PF-M1.1: Product demand & supply domain model (design-only)

**Status:** **APPROVED input** to the canonical product-first workflow (PF-M1.1 arithmetic & lineage). **No longer awaiting "Product supply model approved."** Semantics, arithmetic, and lineage are **unchanged during the canonical merge**; retained as approved model authority. Design/model only. No changes to HTML/CSS/prototypes/live mirrors/application code/database schema. Track A retains authority over physical database schema and concurrency mechanism. This settles the domain model all later product-first checkpoints will use. The four existing product-first proposal docs are **not** modified in this pass (see `PF_M1_DELTA.md`).

**Rulings encoded (Trent):** canonical name `ProductRequirement` (child of Planned Show, optional Planned Break attribution); multi-product Breaks = multiple ProductRequirements; V1 overcommit **prohibited**; Program Templates use `session.write` initially; packaging normalization + cost-basis lineage are in **this** model pass; Platform Card Catalog vs Org Product Master seam explicit; fine capabilities deferred to a later additive migration.

**Operator-lifecycle relationship:** `../OPERATOR_LIFECYCLE.md` places these
objects in the operator’s end-to-end job. `../UX_WORKFLOW_CONTRACT.md` governs
how the UI enters, commits, continues, reviews, and recovers from those jobs.
Neither document changes this model’s arithmetic, lineage, concurrency, or
authority requirements.

---

## 1. Canonical vocabulary

**`ProductRequirement`** — the only name used. Never BreakProductRequirement, BreakInput, ProductInput, or "Product demand line."

Definition: an **organization-owned quantity requirement** belonging to **one Planned Show** and **optionally attributed to one Planned Break**.

Cardinality:
- one Planned Show → 0..* ProductRequirements
- one Planned Break → 0..* attributed ProductRequirements
- a Cards Break may require **multiple** Product Configurations (multiple ProductRequirements)
- a core zero-Break Show may own ProductRequirements directly
- one ProductRequirement → exactly **one** Product Configuration
- one ProductRequirement may be fulfilled by **multiple** supply records and lots

ProductRequirement records: organization · parent Planned Show · optional Planned Break · Product Configuration · required quantity · canonical base unit · optional purpose (`primary` | `mixer` | `bonus` | `replacement`) · pinned `ChecklistForUse` version (where applicable) · format-recipe requirement identity · planned allocations · confirmed reservations · consumption lineage.

---

## 2. Multi-product & mixer Breaks

A Planned Break consumes one or more Product Configurations; a Break with three products has **three ProductRequirements**, never one composite field. A `ProductFormatRecipe` may define multiple required Product inputs, with an optional **primary Product anchor** for discovery while still supporting mixers. **Checklist attachment is per ProductRequirement** (per its Product Configuration), not a single `0..1 ChecklistForUse` on the whole Break.

---

## 3. Demand & supply objects (kept distinct)

| Role | Object | Meaning |
|---|---|---|
| **Demand** | `ProductRequirement` | how much of a Product Configuration a Show/Break needs |
| **Expected supply** | `POLine` | ordered, not yet received |
| **Planned commitment** | `PlannedAllocation` | links part of a ProductRequirement to eligible **open expected** PO-line supply; advisory; does not make on-hand |
| **Received supply** | `Receipt` + `InventoryLot` | receipt against a PO line creates received qty in one or more lots (authoritative landed cost basis) |
| **Confirmed commitment** | `ConfirmedReservation` | links part of a ProductRequirement to **received** qty in one or more lots; required for Prepared + Start Live |
| **Consumption** | consumption event | decrements confirmed source lots; retains full lineage |

Consumption retains ProductRequirement → reservation → lot → receipt → PO line → runtime Break → LiveSession → Prepared-version lineage. **PlannedAllocation history is never destructively replaced** when reservations are created (allocations are released/superseded additively, not deleted).

---

## 4. Quantity & packaging normalization

**Product Configuration** defines: canonical stocked/base unit · allowed purchasing units · boxes-per-case · packs-per-box · cards-per-pack · other validated conversions (with a conversion version).

**PO Lines & Receipts** record: entered quantity · entered unit · normalized base quantity · cost per entered unit · normalized cost (where required) · conversion version / captured conversion evidence.

Rules:
- **Never** use ambiguous unlabeled "units." Every quantity carries a unit + normalized base quantity.
- A receipt may use an allowed unit different from the PO entry **only** when the conversion is deterministic and preserved.
- The actual source lot and conversion used are retained through reservation and consumption.

Canonical base unit for arithmetic in §5 is the Product Configuration's base unit; all quantities normalize to it before comparison.

---

## 5. Arithmetic invariants (all in normalized base units)

**PO Line** — preserve original ordered qty, additive amendments, cancellation evidence, net accepted receipts:
- `effective_ordered` = original order **+** accepted quantity amendments
- `net_received` = accepted receipt quantity **−** posted receipt reversals
- `remaining_expected` = `effective_ordered − net_received`, **except** cancelled unreceived supply is unavailable
- `available_remaining_expected` = `remaining_expected` minus any cancelled/unavailable unreceived supply
- `committed_expected` = Σ **active** PlannedAllocations against this line
- `open_expected` = `available_remaining_expected − committed_expected`
- A **cancelled PO line** has zero available expected supply; its historical ordered/received quantities remain visible.
- A PO quantity reduction **below `net_received` must be rejected** or handled as an explicit correction workflow — it never erases received inventory.

**Inventory Lot** — on-hand is derived from **posted inventory movements**, not merely receipts−consumption:
- `lot_on_hand` = Σ(receipt · consumption-reversal · count-adjustment-up · transfer-in · approved-correction-up) − Σ(receipt-reversal · consumption · count-adjustment-down · damage/loss · transfer-out · approved-correction-down)
- **Reservations do not change on-hand.**
- `lot_confirmed_reserved` = Σ **active** ConfirmedReservations against the lot
- `lot_free` = `lot_on_hand − lot_confirmed_reserved`

**Requirement** (per ProductRequirement, active commitments only): `req_required` · `req_planned` = Σ active PlannedAllocations · `req_confirmed` = Σ active ConfirmedReservations · `req_consumed` = Σ consumption (runtime). Historical released/superseded/consumed/cancelled rows are **not** active commitments.

**Invariants (V1):**
1. `lot_confirmed_reserved ≤ lot_on_hand` (confirmed reservations never exceed **total on-hand**; `lot_free` is what remains after). *Not* "confirmed ≤ free."
2. `committed_expected ≤ available_remaining_expected` → `open_expected ≥ 0` (allocations never exceed open expected).
3. **Requirement conservation:** `req_planned + req_confirmed ≤ req_required` (summing active commitments only). A PlannedAllocation cannot exceed the unfulfilled requirement; a ConfirmedReservation cannot push planned+confirmed above required; **promotion decreases active planned by exactly the quantity confirmed** (planned→confirmed is a move, not an add).
4. **No overcommit** — no allocation/reservation may push a source line/lot negative or breach invariant 3; **no escape hatch in V1.**
5. A ProductRequirement may be **partially planned and partially confirmed** simultaneously, bounded by invariant 3.
6. A ProductRequirement may reserve **across multiple lots** (Example I).
7. Receiving a physical unit must not leave it counted as **both** open expected and received (receipt raises `net_received`, lowering `remaining_expected`, and raises `lot_on_hand`; promotion moves planned→confirmed).
8. Promotion/reconciliation is **atomic and idempotent**; same idempotency key → same result, no duplicate holds.
9. Partial fulfillment stays explicit (`req_confirmed < req_required` is a visible shortfall).
10. **Prepared requires** `req_confirmed = req_required` **and** `req_planned = 0` for every ProductRequirement of the Show (and its breaks). V1 does not intentionally over-reserve.

**Pre-Live vs Live:** the conservation + Prepare invariants govern the **pre-Live** plan. **After Live begins**, `req_consumed` is tracked separately and the pre-Live Prepare invariant is not re-evaluated as if still preparing. Overcommit is prohibited in V1; a future overcommit policy is a separate design with explicit authority, limits, clearing, and audit.

---

## 6. Reservation concurrency (invariant, not SQL)

Two operators reserving the same free lot quantity concurrently must not over-reserve. Required behavior at the authoritative write boundary:
- serialize or use equivalent **compare-and-set** protection;
- **reread** free quantity after acquiring the guard;
- validate post-guard state before mutation;
- commit reservation + receipt/allocation reconciliation **atomically**;
- use **idempotency keys**;
- return a deterministic **conflict** or a permitted **partial** result;
- never derive success from a stale client-side availability value.

**Partial-reservation policy (V1):** reservation requests are **all-or-nothing by default**. A caller may request partial fulfillment only via an explicit **`allow_partial`** option. When allowed, the result returns: requested qty · confirmed qty · remaining unfulfilled qty · exact lots used · resulting requirement state. A retry with the same idempotency key returns the **same** quantities and lot assignments. The system **never silently** converts a full request into a partial reservation. The same concurrency guard + post-guard reread apply to full and partial requests.

Track A chooses the physical mechanism. Acceptance: a bounded-concurrency scenario where two full requests compete for the last free quantity and total confirmed reservations never exceed on-hand (Example C), plus an explicit partial-request scenario (Example J).

---

## 7. Supply-side cancellation & reversal

All effects are **additive to history** (no destructive rewrite). Effects use **net/active** values from §5.

**PO cancellation before receipt:** release active PlannedAllocations against the cancelled supply; that line's `open_expected` → 0 (historical ordered/received remain visible); ProductRequirements **remain as unmet demand**; ConfirmedReservations are **unaffected** (none came from unreceived qty). Previously incomplete demand stays **Attention**; previously satisfied demand becomes **Recovery only if a separate confirmed fact actually regresses**. PO cancellation does **not** directly reduce confirmed inventory.

**PO line quantity reduction:** may reduce **only unreceived, uncommitted** expected supply; **cannot** go below `net_received`; **cannot** strand active PlannedAllocations (they must be released/moved through additive events before the reduction commits). ConfirmedReservations against already-received Lots remain intact.

**Confirmed reservation release:** returns quantity to `lot_free`; reduces `req_confirmed`; leaves demand **unmet**. It does **not** auto-"revert to planned" — a new PlannedAllocation is created only through an explicit, valid allocation op against eligible open expected supply.

**Receipt reversal / lot correction (when it would make reservations exceed on-hand):** operate under the **same authoritative concurrency boundary** as reservation; deterministically identify affected reservations; **V1 default: block** the destructive reversal until affected reservations are explicitly released/reassigned — **except** an authorized correction workflow that performs both **atomically**. Never leave `lot_confirmed_reserved > lot_on_hand`. Invalidate Prepared versions whose requirements regress.

**Vendor shortfall:** recompute `open_expected`; mark affected PlannedAllocations unsatisfied; demand remains; Recovery if a satisfied requirement regresses.

**Product substitution:** see §7a (history-preserving; never re-point).

### 7a. Substitution (history-preserving)

**Same Product Configuration, different supply:** release the old supply commitment; create a **new** allocation/reservation; retain linkage between the replacement events. Never re-point an existing allocation/reservation.

**Different Product Configuration:** supersede/cancel the old ProductRequirement; create a **replacement ProductRequirement** referencing the new Configuration; link via `replaces_requirement_id` (conceptual); rerun checklist, format compatibility, allocation, reservation, readiness, approval; invalidate current Prepared evidence. History remains additive.

---

## 8. Demand-side cancellation (carries the accepted C2 contract)

**Planned Show cancellation** (atomic, idempotent): cancel all active child ProductRequirements · release every active PlannedAllocation → return released expected qty to eligible open PO supply · release every active ConfirmedReservation → return released received qty to free on-hand lot supply · close dependent Attention/Recovery · retain all historical allocation/reservation/preparation/audit evidence.

**Planned Break removal/cancellation** (atomic): cancel/release only ProductRequirements **attributed to that Break** · preserve Show-level and sibling-Break requirements · release that break's expected + on-hand commitments · recompute Show readiness · retain history. Removing the last Break does **not** delete the Planned Show.

No orphaned allocations; no quantity disappears (released quantities return to their source pool). Proven in Examples D & E.

---

## 9. Cost-basis model

**Modeled (non-binding):** BreakFormatTemplate + ProductFormatRecipe may hold modeled cost assumptions, target gross, fee/labor assumptions, comparison scenarios. These **never** bind authoritative Inventory Lot cost basis.

**Authoritative:** cost lineage lives on PO Line → Receipt → Inventory Lot → additive cost-adjustment events → ConfirmedReservation + consumption references. **Prepared vN captures** the reserved lot references + effective cost evidence at issue time.

Late freight, vendor credits, rebates, invoice corrections = **additive cost-adjustment events**; they never destructively rewrite the original receipt or erase evidence used by an earlier Prepared version/execution. D6 receives both original and adjustment lineage (Example G).

**Cost-adjustment effect on preparation (ruling):**
- A cost adjustment **never mutates an issued Prepared snapshot** (original receipt evidence stays immutable).
- **Before Live:** it reruns any policy-based economics / margin approval; it **invalidates preparation only if** the org's approval/readiness policy declares that economic threshold **preparation-critical**.
- **After Live:** it flows into **D6** reconciliation via additive evidence and does **not** rewrite the execution.
- A late freight adjustment does **not** automatically invalidate operational readiness (Example G).

---

## 10. Checklist ownership & cardinality

- Platform **ChecklistCatalogEntry** = canonical shared reference data.
- Checklist source/version belongs to the relevant **Product release**; applicability to Product Configurations is **explicit**.
- **OrgChecklistSubmission** + **OrgChecklistOverlay** stay organization-private; **chase annotations live in the overlay**.
- **ChecklistForUse** = organization-approved, **version-pinned** result.
- **Each relevant ProductRequirement pins the ChecklistForUse version** applicable to its Product Configuration.
- Changing a pinned checklist version is **preparation-critical** (invalidates the affected Prepared vN).

Ownership is no longer "Product or Product Configuration" — it is: catalog=platform; source/version=Product release; applicability=explicit to Configuration; pin=per ProductRequirement.

---

## 11. Catalog distinction

**Platform Card Catalog** — shared canonical reference for cards, sets, checklist entries, and card identities. Platform-owned, with organization overlays where approved.

**Organization Product Master** — the business's org-owned commercial **product release record**. **Product Configuration** is its purchasable/stockable **packaging variant** (a Product Master has child Configurations).

- Product Master: *2026 Topps Chrome Baseball*
- Product Configurations: *Hobby Box · Hobby Case · Jumbo Box · Retail Blaster*

A box/case is a **Configuration**, never itself a Product Master. A ProductRequirement references exactly one **Product Configuration** (§1). An Org Product Master **may reference** shared Card Catalog / checklist data but **is not** the shared catalog. Organization-private costs, vendors, POs, lots, allocations, reservations, and operational annotations **never** become platform-shared catalog data. Provide stable external identifiers + an **optional future platform-product reference seam** without building a shared Product catalog now.
