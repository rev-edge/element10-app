# Element 10 — PRODUCT_FIRST_GOVERNANCE.md
## How the approved PF-M1.1 model + D3 contract deliver through small reviewable checkpoints

**Status:** **APPROVED input (governance v3)** to the canonical product-first workflow — issuance→approval order + maker-checker capability closure applied. **No longer awaiting "Product-first governance approved."** Governance substance is **unchanged during the canonical merge**; retained as approved authority. Design/documentation only. A6b independent. Inputs: approved **PF-M1.1** (`PRODUCT_SUPPLY_MODEL.md`), approved **D3 contract** (`D3_INPUT_CONTRACT.md`), accepted **C1–C3**, ADR 0005 / A6b catalog, current D2 plan.

**Lifecycle alignment:** `../OPERATOR_LIFECYCLE.md` and
`../UX_WORKFLOW_CONTRACT.md` add a cross-cutting UI planning and acceptance
overlay. They do not change checkpoint dependencies, I1–I17, PA/IC/CR/AP,
authority, or the one-primary-boundary rule.

**Checkpoint namespace:** the product-first sequence uses a dedicated **PF-C1, PF-C2, …** namespace — never C4/C5/C6 or any C1–C3 numbering (which are taken and would collide). Accepted C1–C3 source is **not** edited in this pass.

---

## 1. Object dependencies (corrected)

**ProductRequirement ownership:**
- Belongs to **exactly one Planned Show** at creation; **optionally attributed to one Planned Break**.
- **No later generic "assign ProductRequirement to Show" operation exists.** Assigning a Product/recipe to a Show/Break **creates or updates its ProductRequirement children** in place.
- Creating/editing a ProductRequirement includes: Show ownership, optional Break attribution, Product Configuration, quantity, unit, recipe lineage, and checklist pin (where applicable).

**Checklist:**
- Staging/overlay/approval can produce an approved **ChecklistForUse for a Product release/Configuration before any ProductRequirement exists**.
- The **version pin to a ProductRequirement** happens when that requirement is created or changed — **not** proven at the checklist checkpoint (requirements don't exist yet there).

**Program Templates:**
- Contain **reusable schedule + Break-format + product-requirement blueprint references** — not live ProductRequirement rows.
- Generating a Planned Show **creates new Show-owned ProductRequirement instances** carrying template/version lineage.
- Generated instances may later **diverge** without mutating the Program Template or sibling Shows.

---

## 2. Reservation paths (both preserved)

Allocation-before-reservation is acceptable **implementation sequencing**, but **PlannedAllocation is optional — not a prerequisite for every ConfirmedReservation.** The reservation checkpoint demonstrates: direct reservation from free on-hand lots (`req_planned=0`); promotion from active PlannedAllocation (atomically decreasing planned by the confirmed quantity); partial promotion; direct multi-lot reservation; all-or-nothing default; explicit `allow_partial`; idempotent retry; deterministic concurrency conflict; conservation under every path. No dependency wording implies every reservation requires an allocation.

---

## 3. Cost-first delivery (explicit lineage throughout)

The workflow begins with product quantity **and cost**. Cost lineage appears at every relevant checkpoint: PO (entered qty/unit, vendor price, expected cost, amendments, cancellation evidence) → Receipt/Lot (actual received qty, authoritative landed-cost evidence, lot creation) → cost-adjustment (freight/credit/rebate/correction as **additive** events) → Format Recipe (modeled, **non-authoritative** cost + margin scenarios) → Reservation (exact source-lot lineage) → Prepared (**immutable** capture of reserved lots + effective cost, issued at PF-C16). Pre-Live cost-policy change reruns economics and invalidates **only** when the org marks that threshold preparation-critical; post-Live adjustment preserves execution and hands additive evidence to D6.

---

## 4. Cross-checkpoint invariants (cumulative regression set)

Rerun after every affected checkpoint (distinct from a checkpoint's local acceptance):

1. Organization isolation (prototype-simulated; authoritative RLS proof deferred — §7).
2. Product / Configuration identity.
3. Unit normalization (base unit + versioned conversions).
4. Expected-supply arithmetic.
5. Requirement conservation (`req_planned + req_confirmed ≤ req_required`).
6. No expected/received double counting.
7. Reservation concurrency (contract; authoritative proof deferred — §7).
8. Additive history.
9. Cancellation release behavior.
10. Checklist pin invalidation.
11. Prepared immutability.
12. D3 Start Live boundary (contract; authoritative atomicity deferred — §7).
13. Companion / participant-private / public channel separation (contract; authoritative privacy deferred — §7).
14. **Cost provenance + immutable Prepared cost evidence.**
15. **Attention generation + closure** (valid-but-incomplete).
16. **Recovery generation after regression** (stale/failed/conflicted/interrupted), **scoped to the current preparation/execution version**.
17. **Resolver consistency** (same readiness key → same destination) + **closure evidence** + no stale blocker surviving valid resolution.

**Universal UI invariant, separate from I1–I17:** every touched operator task has
an explicit entry/origin, commit point, immediate result, state-aware
continuation, review/correction, Back/Cancel, repeat, incomplete exit/resume,
recovery, and lifecycle handoff. A later checkpoint may remain unimplemented, but
the current checkpoint may not end in a dead or misleading state.

---

## 5. Attention & Recovery (restored; C2/C3 depend on them)

- **Attention** = current state valid but **incomplete**; needs work before progression.
- **Recovery** = a previously-valid state **regressed / went stale / failed / conflicted / was interrupted**; applies **only when tied to the relevant current preparation/execution state** (historical resolved items never block forever).
- **No unresolved blocking Recovery item tied to the current preparation version** may pass **Prepare** or **Start Live**.
- Both use the **shared resolver registry** (D3 §2): same readiness key → same resolver destination; resolution records **closure evidence** and returns to the invoking Show/Break/Product context with focus intact.
- A **cancelled Show** exposes retained closure/history, not active Attention/Recovery controls.

**Checkpoint ownership:** product/supply/checklist/format checkpoints **produce** their applicable Attention/Recovery conditions; the readiness/invalidation checkpoint (PF-C15) **aggregates** and owns state transitions; the **Prepared-issuance checkpoint (PF-C16)** captures immutable reserved-lot + cost evidence and **enforces the blocking rule** (no unresolved current-version blocking Recovery passes issuance); the **maker-checker approval checkpoint (PF-C17)** approves exactly that immutable version (maker ≠ checker; production `session.approve`, not `session.write`); **D3 handoff (PF-C18) requires the current Prepared vN + a valid approval bound to that exact version** and refuses an unresolved current-version blocking Recovery.

---

## 6. Catalog seam (authoritative)

- **Platform Card Catalog** — platform-owned shared reference (cards, sets, checklist entries, card identities) with **approved organization overlays**.
- **Organization Product Master** — tenant-owned commercial **product release** record (*2026 Topps Chrome Baseball*).
- **Product Configuration** — purchasable/stockable **packaging variant** (*Hobby Box · Hobby Case · Jumbo Box · Retail Blaster*).
- Organization-private vendor/PO/receipt/lot/cost/allocation/reservation/overlay/operational data **never** becomes shared catalog data.
- Optional stable external identifiers + a future platform-product reference may exist; **no shared Product catalog is built now**.
- **Cards-off organizations** never surface Card Catalog, checklist, break, chase, tier, or spot concepts — the Product → Configuration → PO → Lot → Show-level ProductRequirement chain is fully usable without cards vocabulary.

---

## 7. Prototype evidence vs authoritative proof

Track B browser prototypes **can prove**: workflow composition; visible permission/entitlement states; deterministic success/failure fixtures; cards-off terminology; return context; responsive + accessibility behavior. They **cannot prove**: database RLS isolation; transaction atomicity; compare-and-set correctness; concurrent reservation safety; idempotent server execution; realtime channel privacy.

Every checkpoint therefore splits acceptance into: **(a) prototype acceptance** (browser), **(b) implementation-contract acceptance** (preserved for Track A/production), **(c) cumulative prototype regression**, **(d) future authoritative integration/security proof**. **PF-C20 (hostile two-org)** may *simulate* two organizations in the prototype but must **not** call that a hostile RLS proof — that claim is reserved for the implementation security gate.

Prototype acceptance includes workflow evidence, not only component presence and
screenshots. The design package runs the scenarios in
`../UX_WORKFLOW_CONTRACT.md`: first-time, repeat, incomplete/resume, final-item,
edit/return, Cancel-no-creation, and denial/conflict recovery. Screenshots prove
paint; the behavioral run proves task-loop completion.

---

## 8. Four-concern authority model

The crosswalk separates: **(1) identity + org/ownership-scoped DB authorization (RLS)**; **(2) module entitlement + nav visibility**; **(3) action capability for mutation**; **(4) legal/policy gates**. Rules: `mod.*` visibility is **not** authoritative read permission; every org-owned read stays org-scoped via membership/RLS; participant-private reads use **verified ownership**, not org membership; public/Broadcast uses an **allowlisted projection**; a future `*.read` leaf may narrow UI/role access but **never replaces RLS/ownership**; `act.reporting_export` is **not** money/cost read authorization; interim prototype behavior is **never** described as safe production authorization; purchasing/cost/approval/trade/buyback authorities stay **narrow** before production. See `CAPABILITY_CROSSWALK.md` (authoritative).

---

## 9. Workflow paths (all four preserved)

- **Cold-start (setup):** Product → Configuration → PO → Receipt/Lot → ChecklistForUse → Format Recipe → Program/Show → ProductRequirement → Allocation **or direct** Reservation → Prepare → D3.
- **Warm / routine (Tuesday night):** existing Product/Configuration/ChecklistForUse/Recipe/Program → operator starts from Schedule or the recurring Program → generate/open upcoming Shows → select/swap Configuration → inherited checklist/format/slot/program defaults auto-apply → eligible expected/on-hand supply surfaced inline → automatic actions still **confirm** where they commit inventory/money → only **blockers/exceptions** create resolver detours → review allocation/reservation/readiness → Prepare. Already-green stages need no page visit. **Ergonomics record** reports: surfaces visited, deliberate actions, required confirmations, resolver detours, returned context. Target: **one guided Schedule/Show flow** for the routine case; Product/Checklist/Format Builder visited only on exception/intentional edit.
- **Same-night fast path** (Admin, product-first velocity) and **weekly recurring-program path** preserved.
- **Schedule-first exception:** create the Show first; resolve Product/Configuration, checklist, format, requirement, allocation/reservation, operator via the **single resolver registry**; each detour names its primary object + returns to the same Show/Break context intact.

See `PRODUCT_FIRST_CHECKPOINTS.md` for the dependency-ordered PF-C sequence and per-checkpoint acceptance.

---

## 10. Planning before implementation

Every new or materially changed UI workflow produces the preflight defined in
`../UX_WORKFLOW_CONTRACT.md` before code. The preflight inspects the adjacent
lifecycle steps and separates findings into:

- continuity required in the current checkpoint;
- a larger model, capability, tenancy, financial, or channel contract requiring a
  later gate.

The agent may not silently implement the second category. It may not omit or hide
it either. The present workflow must end with an honest review, return, resume, or
unavailable state.
