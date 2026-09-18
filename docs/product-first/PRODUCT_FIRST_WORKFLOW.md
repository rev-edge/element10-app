# Element 10 — PRODUCT_FIRST_WORKFLOW.md
## Canonical product-first operating workflow (documentation merge)

**Status:** approved product-first workflow, with a proposed operator-lifecycle
alignment overlay dated 2026-07-27. This document remains the canonical
sealed-product operating workflow. `../OPERATOR_LIFECYCLE.md` governs the broader
operator jobs and handoffs; `../UX_WORKFLOW_CONTRACT.md` governs UI workflow
planning and acceptance. The overlay does not change approved schema, arithmetic,
capability, or security decisions.

| Input | Canonical status |
|---|---|
| PF-M1.1 model (`PRODUCT_SUPPLY_MODEL.md` + test matrix) | **approved** |
| D3 contract (`D3_INPUT_CONTRACT.md`) | **approved**, with the explicit governance extension in §7 (Start Live ↔ approval binding) |
| Product-first governance (`PRODUCT_FIRST_GOVERNANCE.md`, `CAPABILITY_CROSSWALK.md`, `PRODUCT_FIRST_CHECKPOINTS.md`, `GOVERNANCE_MERGE_DELTA.md`) | **approved (v3)** |
| Product-first workflow (this document) | **approved; lifecycle alignment overlay proposed 2026-07-27** |
| Operator lifecycle (`../OPERATOR_LIFECYCLE.md`) | **proposed UI/job coordination authority; no schema or authority grant** |
| UX workflow contract (`../UX_WORKFLOW_CONTRACT.md`) | **proposed planning and acceptance overlay** |
| Accepted C1–C3 prototypes | **retained pre-pivot evidence** (frozen; not product-first) |
| Product-first prototype implementation | **not started** |
| PF-0 (provenance/hub relabel) | next **only after** "Product-first workflow approved." |
| PF-C1 … PF-C21 | **planned, not built** |
| Track A A6b catalog | **independent and unaffected** (frozen) |

**Design/documentation only.** No prototype HTML/CSS/JS, screens 01–07, source/live mirrors, archives, application code, schema, migrations, or A6b rows changed in this pass. No approved model decision was silently changed. A6b remains frozen and independent.

**Workflow-completeness rule:** every implementation checkpoint still owns one
primary object or transaction boundary, but its UI must close the operator task
loop at that boundary. A deferred downstream object is not built early; the
current surface instead provides a truthful review, return, resume, or unavailable
state. Scope limits implementation, not adjacent-gap analysis.

**Preserved from approved D2 (unchanged):** Planned Show = mutable planning object · Planned Break = its Cards planning child · Prepared vN = immutable snapshot · LiveSession = separate D3 execution (one Show → N executions) · runtime Breaks = children of LiveSession (`live_session_id`; `source_show_ref` lineage-only) · capability-driven access · tenant isolation · core-vs-Cards entitlement · canonical lifecycle `Created → Ready → Live → Ended → Corrected` · cancellation as a disposition.

---

## 1. Canonical object model (PF-M1.1 vocabulary)

Conceptual only — no tables/migrations. Every row-bearing entity is **organization-owned** (tenancy root) unless explicitly marked platform-owned.

Platform Card Catalog · Organization Product Master · Product Configuration · Vendor · PO + POLine · Receipt · Inventory Lot · additive inventory & cost-adjustment events · Planned Show · optional Planned Break attribution · ProductRequirement · PlannedAllocation · ConfirmedReservation · ChecklistForUse · Product Format Recipe · reusable versioned Format Template · Program Template · Prepared vN · approval record · LiveSession · runtime Break · consumption & additive reversal.

### 1.1 Catalog seam (hard boundary)
- **Platform Card Catalog** — platform-owned shared reference data.
- **Organization Product Master** — tenant-owned commercial product-release record (manufacturer · year · line · sport/category · edition · identifiers · reference MSRP · metadata). Holds zero or more Product Configurations. Changing Product defaults never overwrites historical cost basis on POs/receipts.
- **Product Configuration** — the purchasable & stockable packaging variant (hobby/jumbo/retail/blaster/case/box; boxes-per-case, packs-per-box, cards-per-pack). Independent children; never overwrite one another.
- Organization-private vendors, POs, receipts, lots, costs, allocations, reservations, overlays, and operations **never** become shared catalog data.
- Cards-off organizations never surface Card Catalog, checklist, Break, chase, tier, or spot concepts.
- **No shared Product catalog is built now.**

### 1.2 Vendor + purchasing facts
Preferred vendor may be an advisory Product-level default. **Actual** vendor, ordered quantity, unit cost, freight/landed inputs, and ETA belong to the **PO / POLine**, not the Product. Historical cost basis is immutable once received.

### 1.3 PO + POLine
Creates **expected supply**, not on-hand inventory. A POLine references a Product Configuration and carries ordered qty, unit cost, freight/landed inputs, ETA, vendor.

### 1.4 Receipt + Inventory Lot
A receipt against a POLine creates **on-hand quantity** and an authoritative **lot-level landed cost basis**. Partial receipts create partial on-hand and leave an explicit remaining shortfall.

### 1.5 ProductRequirement (Show-owned)
- A ProductRequirement belongs to **exactly one Planned Show at creation**.
- It **may optionally be attributed to one Planned Break**.
- **There is no later generic "assign ProductRequirement to Show" operation.**
- Assigning a Product or Product Format Recipe **creates or updates the Show-owned ProductRequirement children** (with template/version lineage where generated).
- **Cards ProductRequirements pin an approved applicable ChecklistForUse** (with chase annotations) at creation/change.
- **Core / cards-off requirements expose no checklist concept.**
- A Show may hold many ProductRequirements; a single Break may carry **multiple** (a mixer Break = multiple checklist pins + reservation groups). A core zero-Break Show carries Show-level ProductRequirements only.

### 1.6 PlannedAllocation vs ConfirmedReservation
- **PlannedAllocation** commits eligible **expected PO-line supply** (pre-receipt). Advisory; optional.
- **ConfirmedReservation** commits received **on-hand Inventory Lot supply**. Required for Prepared and Start Live.
- Both attach through **ProductRequirements** (not a generic "inventory per Break").

### 1.7 Checklist entities (per ADR 0005 — unchanged)
- **ChecklistCatalogEntry** — platform-owned, read-only to tenants.
- **OrgChecklistSubmission** — org-private staging of a source.
- **OrgChecklistOverlay** — org-private corrections + annotations (incl. chase tags).
- **ChecklistForUse** — org-approved, version-pinned result pinned by a cards ProductRequirement.
- Chase designation is org overlay metadata, never an edit to the platform catalog. Chase classifications: `auto`, `ssp`, `case_hit`, `significant_pull`, plus org-defined tags.

### 1.8 Format entities
1. **Format Template** — org-owned reusable, versioned template (slot structure, assignment shape, fee/labor assumptions). Not product-specific.
2. **Product Format Recipe** — a template applied to a specific Product Configuration (consumption, slot structure, tiers, **modeled non-authoritative** gross, cost-basis reference, fee/labor assumptions, checklist compatibility). May be LLM-suggested as a draft; requires a qualified human to accept. LLM may never publish a recipe or alter authoritative cost data.
3. **Planned Break configuration** — the concrete Break on a Planned Show (D2/C3).
4. **Runtime Break execution** — child of LiveSession (D3).

### 1.9 Program Template (org-owned, recurring)
- Contains **reusable schedule, Break-format, and product-requirement blueprint references** — **not** live ProductRequirement rows.
- **Instantiates** concrete Planned Shows; generated Shows receive **new Show-owned ProductRequirement instances with template/version lineage**.
- Generated Show instances may diverge without mutating the Program Template or sibling Shows.
- Editing a Program Template affects **future** instantiations only.

---

## 2. Ownership + cardinalities

| Entity | Owner | Cardinality |
|---|---|---|
| Platform Card Catalog | **Platform** | shared reference |
| Product Master | Organization | 1 org — * products |
| Product Configuration | Organization | 1 product — * configs |
| Vendor | Organization | 1 org — * vendors; product 0..1 preferred |
| PO / POLine | Organization | 1 org — * POs; 1 PO — * lines; 1 line — 1 config |
| Receipt / Lot | Organization | 1 line — * receipts; 1 receipt — 1 lot (cost basis) |
| **ProductRequirement** | Organization | **1 Show — * requirements; 0..1 Break; 1 — 1 config** |
| PlannedAllocation | Organization | 1 requirement — * allocations (vs expected supply) |
| ConfirmedReservation | Organization | 1 requirement — * reservations (vs on-hand lots; may span lots) |
| ChecklistCatalogEntry | **Platform** | 1 entry — * org submissions/overlays |
| OrgChecklistSubmission/Overlay | Organization | overlay patches 1 catalog entry |
| ChecklistForUse | Organization | 1 config — * versions; pinned by cards requirement |
| Format Template | Organization | 1 org — * templates; * versions each |
| Product Format Recipe | Organization | 1 config — * recipes; references 1 template version |
| Program Template | Organization | 1 org — * programs; 1 program — * planned shows |
| Planned Show / Break | Organization | per approved D2 |
| Prepared vN | Organization | 1 show — * versions; 1 current |
| LiveSession / runtime Break | Organization | D3; runtime break — 1 live session |

---

## 3. Canonical reservation & supply rules

Stated directly here (not only in the test matrix):

- **PlannedAllocation** commits eligible expected PO-line supply; it is **optional**.
- **ConfirmedReservation** commits received on-hand Inventory Lot supply.
- **Direct reservation** may occur from free on-hand stock with **`req_planned = 0`** (no PlannedAllocation required).
- **Promotion** from PlannedAllocation to ConfirmedReservation **atomically decreases active planned quantity by exactly the quantity confirmed.**
- Every path preserves conservation: **`req_planned + req_confirmed ≤ req_required`.**
- **Prepare requires `req_confirmed = req_required` and `req_planned = 0`** for every ProductRequirement.
- **All-or-nothing is the default** reservation behavior; **partial fulfillment requires explicit `allow_partial`**.
- A partial result reports requested, confirmed, remaining, lots used, and resulting requirement state.
- Reservation and promotion are **atomic and idempotent**; authoritative writes **reread state after acquiring the concurrency guard**.
- **No expected/received double counting** — a unit is either expected-allocated or on-hand-reserved, tracked by lot.
- A ProductRequirement **may reserve across multiple lots**.
- Historical released/consumed/superseded/cancelled commitments remain **additive history**, not active commitments.

---

## 4. Cancellation, reversal, and substitution

Placement and semantics per approved governance (acceptance placed at the earliest checkpoint where the objects exist, rerun cumulatively once dependents exist — see §10):

- **PO cancellation before receipt** makes unreceived expected supply unavailable while preserving history.
- **Once PlannedAllocations exist**, PO cancellation **releases affected active allocations** and leaves ProductRequirements as **unmet demand**.
- **PO reduction** cannot go below net received or strand active allocations.
- **Base receipt reversal is additive.** Once ConfirmedReservations exist, reversal is **blocked when it would violate active reservations unless an authorized atomic correction releases or reassigns them.**
- **Reservation release does not silently recreate a PlannedAllocation.**
- **Show cancellation** releases active allocations and reservations while retaining history.
- **Break removal** cancels only **Break-attributed** ProductRequirements and releases only their commitments; **Show-level and sibling-Break requirements remain intact.**
- **Product substitution uses release-and-create lineage** — existing commitments are never re-pointed destructively; a different Product Configuration creates a **replacement ProductRequirement** linked through replacement lineage.
- **Cost adjustments are additive** and never rewrite original receipt or Prepared evidence.

---

## 5. Cost-first workflow (cost is first-class)

- **PO** captures entered quantity/unit, vendor price, expected cost, amendments, and cancellation evidence.
- **Receipt + Inventory Lot** capture actual received quantity and authoritative **landed-cost evidence**.
- **Freight, vendor credits, rebates, invoice corrections** are **additive** cost-adjustment events.
- **Product Format Recipe economics are modeled and non-authoritative.**
- **ConfirmedReservation preserves exact source-lot lineage.**
- **Prepared vN captures immutable effective-cost evidence** from its reserved lots.
- A **pre-Live** cost change reruns economics and **invalidates preparation only when organization policy marks the affected threshold preparation-critical.**
- A **post-Live** cost adjustment **preserves the execution** and flows **additively to D6**; D6 receives both original and adjustment lineage.

**Canonical cost invariants (folded into §6 I1–I17):** cost provenance (PO → receipt → lot → reservation → Prepared vN) and **immutable Prepared cost evidence** (I14).

---

## 6. Attention, Recovery, and resolver behavior

- **Attention** = current state is **valid but incomplete**.
- **Recovery** = a previously valid state **regressed, became stale, failed, conflicted, or was interrupted**.
- Recovery is **scoped to the relevant current preparation or execution version**; historical resolved items do not block forever.
- **No unresolved current-version blocking Recovery item may pass Prepared issuance or Start Live.**
- Attention and Recovery use the **shared resolver registry**: the same readiness key always resolves to the same destination; top-level and row-level actions for the same blocker use the **same resolver**.
- **Resolution records closure evidence**; detours **return to the invoking Show, Break, Product, filter, and focus context.**
- A **cancelled Show** presents retained closure/history rather than active resolver controls.

**Canonical invariant set (I1–I17)** is carried from governance v3 into all workflow/checkpoint references: conservation, no-double-count, atomic/idempotent reservation & promotion, source-lot lineage, additive reversal history, cost provenance (I14), immutable Prepared cost evidence (I14), current-version Recovery scoping, resolver-key consistency, closure evidence, return-context, cards-off determinism, isolation.

---

## 7. Prepared vN, approval, and the D3 governance extension

Ordered boundary (governance v3 — issuance precedes approval):

### PF-C16 — Prepared vN issuance
- **Maker** issues an **immutable Prepared vN** from the current **all-green** plan.
- Issuance captures: exact Planned Show + Planned Break configuration; ProductRequirements; checklist pins; ConfirmedReservations; reserved lots; **effective cost evidence**; readiness evidence; preparation version.
- **No unresolved current-version blocking Recovery passes issuance.**
- Maker uses **`session.write`** for v1.
- Editing the plan after issuance **supersedes Prepared vN, returns the plan to Preparing, and requires a new version.** Prepared vN is never edited in place.

### PF-C17 — maker-checker approval
- **Checker** approves or rejects **exactly one immutable Prepared vN**.
- Approval references the exact **`prepared_version_id`** and immutable **content digest**.
- **Maker cannot approve their own Prepared version.** Approval never targets a mutable plan state.
- **A superseded version's approval cannot authorize Start Live.** Re-preparation creates a new version requiring new approval.
- The approved artifact is **Prepared vN + its approval record.** Approval does not create or reconstruct a different snapshot.

### D3 extension (explicit governance extension to the approved D3 contract)
Recorded openly in the merge manifest. Start Live now requires **the current Prepared vN + a valid approval bound to that exact `prepared_version_id` and content digest**, atomically verifying: version is current; not superseded/invalidated; approval belongs to that exact version/digest; maker ≠ checker; all readiness/checklist/reservation/operator/entitlement/capability conditions still valid; no unresolved current-version blocking Recovery. Same-key retry returns the same LiveSession; concurrent attempts cannot create multiple active executions; intentional later executions require a distinct explicit start intent + valid lifecycle state. (See `D3_INPUT_CONTRACT.md` §1a/§9/§10.)

---

## 8. Capability & authorization model

Authority vocabulary is governed by `CAPABILITY_CROSSWALK.md`. **Four separate concerns:** (1) identity + organization/ownership-scoped **database authorization**; (2) **module entitlement/navigation visibility**; (3) **action capability** for mutation; (4) **legal/policy gate**.

- `mod.*` controls **visibility, not authoritative database access.**
- Organization-owned reads are protected through **membership + RLS**; participant-private reads require **verified ownership**; Public/Broadcast uses **allowlisted projections**.
- A future `*.read` capability may narrow role/UI access but **never replaces RLS**.
- `act.reporting_export` is **not** money/cost read authority.
- **Prototype gating is not production authorization.**

**v1 rulings (from the approved crosswalk):**
- **No `product.read` in v1** — Product read remains within inventory read scope.
- **No `program.manage`** — Program Templates use **`session.write`**.
- **Preparation issuance uses `session.write`** for v1.
- **Chase annotation uses checklist staging/editing authority** for v1.
- **`format.approve` deferred** until its maker-checker boundary exists.
- **`inventory.receive`** distinct (changes authoritative stock/cost); **`purchasing.write`** distinct before production; **`checklist.approve`** distinct where approval ≠ staging.
- **`money.read` / `cost.read`** require explicit privacy rulings.
- **`trade.commit` / `offer.buyback`** required only before those participant-facing features are operational.

**Preparation approval authority (recorded accurately):** the prototype **may simulate** checker authority. **`session.write` must never be the production checker authority.** Production maker-checker requires a **distinct `session.approve`** capability — **later-additive, A6b-unaffected, not currently persisted**; a **human ruling is required before its additive migration**, and **PF-C17 production implementation cannot become operational without that ruling and capability.** No proposed future leaf is treated as approved or persisted.

---

## 9. Workflow paths (four)

### 9.1 Cold-start product setup
Product Master → Product Configuration → Vendor/PO → Receipt/Lot → ChecklistForUse → Product Format Recipe → Program/Show → ProductRequirement → PlannedAllocation *or* direct ConfirmedReservation → readiness → Prepared vN → approval → Start Live. This is **cold-start setup**, not the routine path.

### 9.2 Warm routine workflow
When Product, Configuration, ChecklistForUse, Format Recipe, and Program Template already exist:
- begin from **Schedule** or recurring **Program**;
- generate/open upcoming Shows;
- select or swap Product Configuration;
- **inherited checklist, format, slot, and program defaults apply**;
- eligible expected & on-hand supply **appears inline**;
- inventory/money commitments **require confirmation**;
- **only blockers/exceptions create resolver detours**;
- review allocation, reservation, readiness;
- **maker issues Prepared vN → checker approves → Start Live becomes eligible.**

Already-green setup stages **do not require page visits.** Target: **one guided Schedule/Show flow**; Product, Checklist, and Format Builder are visited only for exceptions/intentional edits. **Ergonomics record** preserved: surfaces visited · deliberate actions · required confirmations · resolver detours · return context.

### 9.3 Same-night fast path
The product-first Admin path for rapid same-night setup, using the **same canonical objects** at higher velocity.

### 9.4 Schedule-first exception
An operator may create the Show first and resolve Product, Configuration, checklist, format, requirements, allocation/reservation, and operator through the **shared resolver registry**. All detours return to the same Show/Break context.

### 9.5 Whole-business operator lifecycle

The four paths above cover sealed-product planning and live execution. They sit
inside the broader business lifecycle in `../OPERATOR_LIFECYCLE.md`:

Plan demand → source/acquire → receive/intake → identify → establish cost →
choose destination → list/allocate/prepare → reserve/commit → sell/go live →
fulfill → reconcile → learn/restock.

Direct singles and collection acquisitions use Acquisition and guarded
CardInstance intake before converging on cost, destination, Listing/Disposition,
fulfillment, and reconciliation. Distribution class, acquisition channel, sales
channel, and fulfillment route remain separate concepts. Channel adapters do not
own physical inventory, cost, reservation, or sale truth.

Every workflow implementation records entry/origin, commit point, immediate
result, state-aware continuation, review/correction, Back/Cancel, repeat,
incomplete exit/resume, denied/conflicted recovery, and next handoff. This is a UI
acceptance overlay, not a new product-supply invariant.

---

## 10. PF-C checkpoint sequence

Adopt **PF-C1 … PF-C21** exactly from the approved governance v3 matrix (`PRODUCT_FIRST_CHECKPOINTS.md`). **Do not reuse old C4/C5/C6 meanings.** Preserved: PF-C namespace · dependency ordering · **PA/IC/CR/AP** evidence categories · one primary boundary per checkpoint · individual stop gates · prototype-vs-authoritative-proof distinction · **PF-C16** Prepared issuance · **PF-C17** approval · **PF-C18** D3 handoff · **PF-C19** warm workflow · **PF-C20** prototype-simulated org/cards-off verification · **PF-C21** final regeneration.

Every PF-C prototype surface also satisfies the universal lifecycle acceptance
overlay in `PRODUCT_FIRST_CHECKPOINTS.md` and `../UX_WORKFLOW_CONTRACT.md`. This
does not authorize a checkpoint to implement its successor’s domain contract.

Accepted **C1–C3** references remain valid where they refer to the accepted planning prototype. Future prototype comments should use **object/workflow names** rather than ambiguous historical checkpoint numbers.

---

## 11. Prototype status

- Screens **01–07 are accepted pre-pivot evidence**; they **do not yet implement** the product-first workflow, and their existing behavior **remains frozen** until implementation begins.
- **PF-0** will update provenance + hub labeling **after** final product-first approval.
- **PF-C1** is the first product-first implementation checkpoint after PF-0 acceptance.
- No prototype file was edited in this pass.

---

## 12. Invalidation rules (extend approved D2 §2/§4)

A change invalidates the current Prepared vN (→ superseded, lifecycle → Created, step → Preparing, Recovery item) when it touches a **preparation-critical** fact: attached checklist version changes; a confirmed reservation drops below required (lot correction, receipt reversal); a bound format recipe/template version changes slots/consumption; operator/date-time/product-assignment change; a pre-Live cost change on an org-marked preparation-critical threshold. Advisory changes (cosmetic metadata, non-binding notes, reference-price updates not touching captured cost basis) do **not** invalidate.

---

## 13. Cards-off (core) behavior
Core organizations retain Product Master, Configuration, PO, receiving, inventory, allocation/reservation, programming, and fulfillment **without any Cards terms or Break requirements**. Card Catalog, checklists, chase tags, break formats, Breaks, tiers, and spots are Cards-module concepts, entitlement-gated off. A core Show carries **Show-level ProductRequirements** with no checklist concept and reaches Prepared with zero Breaks.
