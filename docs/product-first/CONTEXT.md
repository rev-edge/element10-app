# Element 10 — Operator Experience Prototypes: Context Summary

**Current lifecycle alignment (2026-07-27):** the product-first workflow is
approved. `../OPERATOR_LIFECYCLE.md` is the operator-job and handoff authority,
and `../UX_WORKFLOW_CONTRACT.md` is the UI workflow Definition of Done. They
overlay, but do not replace, the approved model, governance, capability, D3, or
Track A security contracts. The older merge-status paragraphs below are retained
as provenance and are not the current gate state.

**Canonical product-first merge (this pass):** the product-first workflow is **merged into canonical documentation** and **awaits the literal approval "Product-first workflow approved."** Canonical status of inputs: **PF-M1.1 model — approved**; **D3 contract — approved, plus one explicit governance extension** (Start Live bound to a valid maker-checker approval of the exact Prepared version, recorded in the merge manifest); **product-first governance (v3) — approved**; **product-first workflow (`PRODUCT_FIRST_WORKFLOW.md`) — merged, awaiting final approval**. Accepted **C1–C3 prototypes are retained pre-pivot evidence**; **product-first prototype implementation has not started**. **PF-0** (provenance/hub relabel) is next **only after** approval; **PF-C1 … PF-C21** are planned, not built. The approved capability v1 rulings (`CAPABILITY_CROSSWALK.md`) govern authority: no `product.read`/`program.manage` in v1; `session.write` for programs + preparation issuance; distinct later-additive `session.approve` for production maker-checker (not persisted; human ruling required; `session.write` must never be the production checker authority). **Track A A6b remains frozen and independent.** No prototype/source/live/archive/schema/Track-A file changed in this pass.

**Status (planning-foundation history):** **D2-0.4 was approved and C1–C3 were accepted.** Their prototype implementation (screens 01–07) is **retained as pre-pivot evidence**; the **canonical product-first workflow (`PRODUCT_FIRST_WORKFLOW.md`) now governs future implementation**. **PF-0** is next **only after** final product-first workflow approval; **PF-C1 … PF-C21** remain planned and unbuilt. Design docs only; no HTML/CSS/live/archive changes since D1.2.1. The approved D2 foundation (retained): **planned Show (D2-owned) vs Prepared vN snapshot vs LiveSession execution (D3-owned, one Show → N executions)**; zero-break core Shows with **Show-owned** allocation/reservation; canonical lifecycle `Created→Ready→Live→Ended→Corrected` with Draft/Scheduled/Preparing as computed UI labels over `Created`; `core`/`cards` separate entitlement; `e10_live_sessions`/`e10_break_sessions` mapping with `source_show_ref` as lineage-only; read-vs-mutation authorization; Attention/Recovery semantics; hostile two-org acceptance. *(The A6b capability catalog is governed by the approved `CAPABILITY_CROSSWALK.md` v1 rulings; A6b is frozen and independent.)*

**What this is:** A suite of self-contained, clickable HTML prototypes of the Element 10 **operator experience** — the organization-member Operator OS for a trading-card live-commerce business (streaming-first today, general card-business capable later). Files live in `prototypes/` (source; shared styling in `e10.css`) with inlined mirrors in `prototypes/live/` for shareable single-file review. `prototypes/index.html` is the hub. Realistic fake data, no backend. This is the **Operator OS only** — the buyer companion and the public/OBS surface are separate products, not roles here.

## Authoritative references (read before editing)
**Current product-first authority (read first, in order):**
- `../OPERATOR_LIFECYCLE.md` — end-to-end operator jobs, multi-channel handoffs,
  task-loop completeness.
- `../UX_WORKFLOW_CONTRACT.md` — required workflow preflight, navigation, and
  behavioral acceptance.
- `prototypes/PRODUCT_FIRST_WORKFLOW.md` — the canonical product-first operating workflow.
- `prototypes/PRODUCT_SUPPLY_MODEL.md` + `prototypes/PRODUCT_SUPPLY_MODEL_TEST_MATRIX.md` — approved PF-M1.1 model + worked examples.
- `prototypes/PRODUCT_FIRST_GOVERNANCE.md` — approved governance (v3).
- `prototypes/CAPABILITY_CROSSWALK.md` — approved authority vocabulary + v1 rulings.
- `prototypes/PRODUCT_FIRST_CHECKPOINTS.md` — approved PF-C1…PF-C21 sequence.
- `prototypes/D3_INPUT_CONTRACT.md` — approved D3 contract + the recorded governance extension.

**Foundation & visual references (retained history):**
- `prototypes/DESIGN_LANGUAGE.md` — the visual-language authority (D1.2).
- `prototypes/00-design-system.html` — the rendered visual contract (type, color, geometry, primitives, states, width modes).
- D0.1 reconciliation package (architecture: surfaces, capability model, lifecycle/visibility separation) — approved.
- ADR 0004 (viewer/two-principal contract) · ADR 0005 (tenant spine + checklist ruling).
- `prototypes/D2_PLAN.md` — accepted **planning-foundation history** (the Plan→Schedule→Prepare design gate, D2-0); **not** the current product-first authority.

## Screen index (exact paths)
- Hub: `prototypes/index.html`
- Visual contract: `prototypes/00-design-system.html`
- ① Operator shell + navigation — `prototypes/01-app-shell.html` **(accepted shell + visual/navigation foundation; does not yet expose the product-first workflow)**
- ② Journey S1 · Streamer day-of — `prototypes/02-journey-s1-streamer.html` *(earlier journey evidence; reconciled in D2/D3)*
- ③ Journey O1 · Owner same-night — `prototypes/03-journey-o1-owner.html` *(earlier journey evidence; reconciled in D2)*
- ④ Journey M1 · Manager's Monday — `prototypes/04-journey-m1-manager.html` *(earlier journey evidence; reconciled in D2)*
- ⑤ Review & reconcile — `prototypes/05-close-reconcile.html` *(earlier journey evidence; reconciled in D6)*
- ⑥ Repack product designer — `prototypes/06-repack-designer.html` *(earlier journey evidence; reconciled in D7)*
- ⑦ Planning & schedule — `prototypes/07-planning-schedule.html` *(accepted **C1–C3** schedule/preparation evidence)*
- Inlined shareable copies under `prototypes/live/`.

> **Pre-PF implementation evidence:** all screens above are **pre-product-first-implementation evidence**; **none currently implements PF-C1 through PF-C21.** 01 is the accepted shell/visual foundation; 02–06 are earlier journey evidence; 07 holds accepted C1–C3 evidence.

> **Evidence, not authority:** ②–⑥ predate the approved architecture. They demonstrate useful interaction ideas but their role language, terminology, and some flows are **superseded** by D0.1/D1. Do not treat them as the spec; see `D2_PLAN.md` §10 for the per-concept reconciliation.

## Product architecture (approved, D0.1)

**Three separate surfaces + adapters:**
- **Operator OS** — desktop-first, organization-scoped, member-authorized. Everything in this prototype suite.
- **Buyer companion** — mobile-first. Viewer authentication + verified handles are platform-global identity; but shows/sessions/purchases/custody/fulfillment/seller relationships stay organization-scoped. A viewer reads only rows they own or are explicitly entitled to. Seller-private cost/valuation/notes never enter the companion. Not a role in the operator shell.
- **Public / OBS** — allowlisted spectator projection only; never mixed with participant-private or operator data.
- **External systems** (Whatnot, payments, shipping, accounting, comms) are **adapters**, not information architecture.

**Capability model (not role apps):** roles are **customizable permission bundles**, not separate applications and not hardcoded modes. Default bundles: **Admin · Manager · Streamer · Operations Team Member**. The shell computes navigation + home content from the active member's **capabilities** and the org's **module entitlements**. Platform administration is separate from organization Admin.

**Tenancy + entitlement:** the active organization is always visible and switchable (when multi-member). Switching clears object context + org-owned data and recomputes nav. **Entitlement** (does the org have the Cards module) is distinct from **permission** (may this member use a destination). Cards-off orgs never show cards terminology.

**Core vs Cards module:** core nouns are **Home · Schedule · Inventory · Live · Fulfill · Money**. Cards-specific destinations (**Breaks · Checklists · Repacks**) are an entitlement-gated module group, never spine peers. Core capabilities (store credit, buyback, commission, approvals, procurement, matching) are reusable platform patterns that remain optional/entitlement-gated — not mandatory for every org.

## Cross-cutting principles
- **Two connected spines.** Universal card-business (reconciled to the canonical flow): Source/Procure → Receive → Inventory/Cost → Identify/enrich → Value → Decide destination → Sell → Fulfill → Reconcile → Learn/restock. **Canonical product-first operating sequence (current):** Product/Configuration → Vendor/PO → Receipt/Lot → ChecklistForUse (where applicable) → Product Format Recipe → Program/Show → ProductRequirement → PlannedAllocation or direct ConfirmedReservation → readiness → Prepared vN → maker-checker approval → Start Live → Complete → Fulfill → Reconcile. **Schedule-first is an explicitly supported exception, not the conceptual origin.** Cards features are modules on the shared spine — **not** a generic multi-vertical configurator.
- **Handoff objects are first-class:** a *prepared session (versioned)*, an *approved checklist-for-use*, a *completed session*, a *published repack product/batch*.
- **Readiness is computed data,** never prose — chips/dots with glyph+label+text (not color alone).
- **Lifecycle ≠ visibility.** A live session's lifecycle (Created→Ready→Live→Ended→Corrected/Reconciled) is separate from its visibility (Private↔Published). "Published" is never a liveness state.
- **Approval is its own dimension,** risk/policy-driven: Not-required · Proposed(vN) · Approved(vN) · Rejected · Stale(vN superseded). Objects keep their own lifecycle; not everything needs approval.
- **Detour rule:** any "I need to fix X first" is a nested task that returns the user to exactly where they were with work intact; focus returns to the triggering control.
- **Attention vs Recovery are distinct queues.** Attention = valid-but-incomplete work. Recovery = broken/stale/conflicted/interrupted. Never one generic notification list.
- **Context strip hierarchy:** organization · current primary object (show/session) · current task/detour · signed-in user.

## Visual language (D1.2, see DESIGN_LANGUAGE.md)
- Sans-first Inter; page titles ~32–36/600 tight; section 20–22; body 14–15; **tabular numerals** for figures; monospace narrowed to IDs, shortcuts, timestamps, machine states (the old widespread uppercase-mono label treatment is retired).
- Warm canvas, white surfaces, **light stone rail**, hairlines over shadows; **volt reserved for the single primary action per view**; blue/green/amber/red semantic only.
- Geometry: panels 6px, inputs/nav/buttons 4px, dialogs 10px; pills only for genuine chips; ruled tile bands + bordered work areas over floating 14px cards.
- Shell: slim top bar with prominent global command/search (⌘K), persistent org identity, thin subordinate context strip, breadcrumb above detail titles, wide workspace.
- **Content-width modes:** focused / standard / wide workbench (documented + demonstrated in `00-design-system.html`).

## ① Operator shell + navigation — `01-app-shell.html` (current)
- Organization-member Operator OS frame. Active organization (mark + name + effective role) with multi-org switching + unsaved-work guard; switching clears context and recomputes nav from the new org's entitlements.
- Capability-driven left rail: Operate (Home · Live · Fulfill) · Plan & stock (Schedule · Inventory) · Review (Money) · **Cards tools** (Breaks · Checklists · Repacks, entitlement-gated) · Admin (Settings). Unauthorized destinations are absent (not shown-then-disabled); empty permission set renders explicit denied.
- Distinct **Needs attention** and **Recovery** topbar queues with right-sheet detail → return.
- Role homes derive from capability: Admin (op snapshot + directional money + queues), Manager (week readiness + risk-based approvals), Streamer (today's prepared session, no Money), Operations (two-parallel-queue fulfillment).
- Personal account / organization settings / platform administration kept separate. Prototype-only scenario harness (outside the app frame) drives role, membership, entitlement, context, and shell state.

## ②–⑥ (pre-D1 evidence — see D2_PLAN.md for reconciliation)
- **② S1 streamer day-of** — prepared-session review → resolve blockers → live board → complete → hand off. Useful: actionable readiness chips + return-intact detour, boxes/cases reservation with case-first depletion, tier-availability board, multi-break-per-session. Superseded: "admin" inline role gating, instant store-credit buyback (gated/removed), streamer-ships assumption (completion now hands to Operations). Live board itself is **D3**.
- **③ O1 same-night** — create → checklist-missing detour → return → format compare + efficiency model → editable slot layout → reserve → save prepared. Same-night and weekly paths must converge on one session+preparation model (D2).
- **④ M1 manager's Monday** — week grid + draggable breaker rail, order-driven receiving + vendor credit, searchable inventory grid with grid count mode. Superseded: Manager↔Owner **role toggle** (replaced by capability model). Planning + inventory converge in D2.
- **⑤ Review & reconcile** — flash snapshot + drill tree, inventory-control audit, directional flash P&L. "Book & close" terminology retired → **operational close** vs financial settlement (D6).
- **⑥ Repack designer** — five-step designer with the three distinct measures (value-back %, inventory gross margin, contribution margin after fees/labor/packaging). Term "published odds" → **manifest & allocation disclosure**; odds/fairness/paid-allocation remain compliance-gated (D7).

## Open / TBD (carried)
- Commission model: **composable component rows (summed) are decided** (Trent, 2026-07-17: org config + per-streamer override); **implementation is deferred** and **D2 stays formula-neutral** (no commission math in prototypes).
- Cost-model numbers shown only as clearly-labeled sample configuration, never embedded product defaults.
- Platform payout/settlement math is directional pending a real settlement model.
- Cross-seller "My Cards" aggregation deferred (consent/privacy/provenance unresolved).
