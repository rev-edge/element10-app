# Element 10 — Domain & Module Map (Track B, step 1)

_v1.3 — 2026-07-17. Classifies every concept in the system into four layers. This document drives three things: the new app's information architecture and navigation naming, the tenancy spine's data model (Track A step 6), and the boundary between the core product and the cards vertical. Sources: Workflow Inventory (journeys S1/M1/O1/R1/F1/RP1 + complaints), Platform Overview, the tenancy spec, ADR 0005, D0.1, and D2-0._

> **v1.2 catch-up (folds in everything decided/discovered 2026-07-15 → 07-17):** the ADR 0005 gate rulings (A–D), the checklist + role corrections below, and the prototype ①–⑥ product concepts + repack model. Applied as corrections in place where they supersede an existing line, and as new sections at the end. Nothing decided is dropped.

> **v1.3 catch-up (D0.1 + D2-0 reconciliation, 2026-07-17):** adds the viewer/privacy boundary, independent state axes, preparation versioning, capability-vocabulary reconciliation, entitlement-gated cards workflow, and the final commission ruling. It preserves the verified A6a.1 mapping of all six legacy module keys (`home`, `inventory`, `reporting`, `schedule`, `settings`, `toolkit`) to `core`.

## The four layers

1. **CORE PRODUCT** — reusable platform machinery shared across verticals. Exists once, but a core capability is not necessarily enabled for every organization: credit/buyback, commission, approvals, procurement, customer matching, and similar patterns may be entitlement-gated.
2. **COMPANY-OWNED (tenant)** — business data each organization owns exclusively. Gets `organization_id`; isolated by RLS.
3. **SHARED REFERENCE** — canonical data all tenants read, none own. Curated at platform level with provenance.
4. **CARDS VERTICAL** — the first vertical's module. Other industries get sibling modules; the core never depends on these.

Plus a fifth minor layer: **PERSONAL** — per-user preferences inside an organization (saved views, dashboard layout, module memory).

---

## Core product

| Concept | Today | Notes |
|---|---|---|
| Organization | ✗ missing (single-org) | Track A6 builds it. **Four org roles (final): Admin · Manager · Streamer · Operations Team Member** (Ops home = the fulfillment queue); **platform admin is separate, above all four.** Roles are org-defined with **allow-list permission sets (empty = deny), customizable + copyable role-to-role** (clone-then-adjust) — ADR 0005. |
| Membership + invitations | partial (`e10_members`, one org, global roles) | Re-keyed `(org, user)`; roles become org-scoped. |
| Module entitlements | ✗ missing | Which verticals/features an org has. A6. |
| **Show (event)** | JSONB workspace | Core, not cards-specific: every live-commerce vertical schedules events. In D2-0, the editable **Live session / Show** plan corresponds to today's workspace show. Carries the **readiness state** (computable: checklist ✓ inventory ✓ format ✓ assigned ✓), the manager→streamer handoff object. |
| **Live session** | relational (`e10_live_sessions`, `e10_break_sessions`) | Core: any vertical runs live selling sessions. The D2-0 **Prepared → Live** handoff corresponds to creating the relational `e10_live_sessions` row, which carries `source_show_ref`. The streamer→fulfillment handoff object. |
| **Inventory item + reservation** | relational (post-M4) | Core: every vertical stocks and reserves product. Model five orthogonal axes rather than one overloaded status: **ownership** (org / viewer / consigned / pending-transfer), **custody** (facility / allocated / in-transit / grading / customer / unknown), **availability** (available / reserved / allocated / sold / consumed / transformed / held), **item lifecycle** (active / transformed / retired / reversed), and **fulfillment** (n-a / pending / pulled / consolidated / packed / shipped / delivered / exception). Vertical-specific *attributes* ride the `extra` pattern (see cards vertical). |
| **Movement ledger + receipts** | relational, append-only | Core, and the crown jewel — cost basis, consumption, idempotency are industry-agnostic. |
| Order / line item | ✗ (Phase 8) | Core; marketplace-agnostic shape, Whatnot-first implementation. |
| Fulfillment / shipment | minimal (ship view) | Core. Per F1: two-phase (spot-ordered pull + hits-attribution queue → buyer-consolidated packing). Labels/slips stay platform-side (Whatnot's). |
| Customer / buyer + aliases | ✗ (Phase 9) | Viewer identity is platform-global; purchases, slots, cards in custody, fulfillment, and seller relationships are organization-owned. A viewer may read only their own rows across organizations, with seller-private cost, valuation, and notes excluded. An org member may not see that viewer's relationship with another org. Near-term companion experiences are seller-branded and org-contextual; a cross-seller **My Cards** view is deferred. Never use shipping details as identity keys. |
| Preparation version / approved snapshot | JSONB workspace today | **Unresolved Track A decision:** relational preparation tables versus versioned workspace JSONB. A preparation is a versioned readiness snapshot (`vN`). Editing a preparation-critical field (operator, date/time, break format/slots/tiers, allocation, required quantity, attached checklist version, or a dropped reservation) creates `vN+1`, marks the prior approval stale, and returns the session to Preparing with a Recovery item. Whichever representation wins, approved snapshots are immutable and append-only. |
| Approval state | ✗ missing | Independent from the business object's lifecycle: `Not-required` / `Proposed-vs-vN` / `Approved-for-vN` / `Rejected` / `Stale`. Approval is risk-based and optional by capability, not a mandatory stage for every object. |
| **Cost model configuration** | ✗ missing — NEW from R1 | Marketplace fee %, **per-employee labor benchmarks**, packing-supplies cost. Tenant-configured; feeds session P&L. |
| Session P&L + reconciliation | ✗ (Phase 10) | Per R1: net = hammer − fee% − labor − supplies − product cost; rollups day/week/month; recorded-vs-deposits comparison. **Store-credit issued/redeemed/outstanding enters this math** (concept 1). This IS the Phase 10 metric contract, seeded from reality. |
| **Store credit / buyback liability** | ✗ missing — NEW (prototype, 2026-07-16) | CORE, ledger-grade. A **second append-only ledger** (issue/redeem/adjust) with receipt + lock rigor; balances per **(organization, viewer, currency)**, never cross-org spendable. **Outstanding credit is a customer LIABILITY, tracked separately from inventory cost basis** (not the same number). Depends on verified handles (ADR 0005 §6). Tax/legal (closed-loop / escheatment) review before any external org carries balances. See concept 1. |
| Schedule / week programming | JSONB workspace | Core; the manager's working object is the WEEK, not the show. |
| Attention queue | ✗ (prototyped in shell ①) | Core: unassigned shows, missing checklists, unshipped sales, unresolved drift. Derived, never manually curated. |
| Notes / to-dos / attachments | JSONB workspace | Core collaboration light-data; stays CAS-protected JSONB (low-write). |
| Import provenance | ✗ (Phase 6 prerequisite) | Which file/batch/edit produced a value. Core pattern used by all reference data. |

## Company-owned (tenant) — the isolation list for Track A6

**A6's migration list is the currently-existing company-owned TABLES only — the authoritative, exact list is [ADR 0005 §0.2](decisions/0005-tenant-spine.md) (19 existing tables + the new `e10_live_sessions`).** In short: the inventory tables (`items`/`movements`/`reservations`), `mutation_receipts`, `workspace`, the break tables (`sessions`/`slots`/`events`), `session_viewers`, and the ten `e10_obs_*` competitive-intel tables. **Each gets `organization_id NOT NULL` + composite `(organization_id, id)`** and org-scoped RLS/RPCs/idempotency in A6 (ADR 0005).

**Not separate tables — do NOT get their own `organization_id` in A6:** break models, cost-model config, notes/todos/attachments, and saved org-level views **live inside `e10_workspace` JSONB** (they inherit the workspace row's org), or **do not exist yet** — they become org-scoped only when/if promoted to their own tables. (The conceptual "company-owned" list here describes DATA ownership; the table migration scope is §0.2.)

Corrections (supersede the old flat list):
- **Checklists are PLATFORM-LEVEL, read-only to tenants (ADR 0005 Ruling A)** — they do NOT get `organization_id`. A tenant's "uploaded checklist" is a private submission that lands in an **org-scoped staging/overlay hook (not built in A6)**, promoted to the shared catalog by **platform curation only**. Companies may modify their own *view* of catalog records and **add their own custom fields** (overlay `patch jsonb`), but never write the platform catalog tables directly.
- **Orders, fulfillment records, customers are Phase 8/9 — NOT in A6's list.** They become org-scoped when built, but A6 migrates only what exists today.
- **Repacks / buybacks are FUTURE** (recorded invariants, ADR 0005 §13 + the Repack section below) — not built in A6.
- `e10_obs_*` are **derived records carrying provenance + a consent/lawful-basis marker** (Ruling B).

## Shared reference

| Concept | Today | Decision needed |
|---|---|---|
| Sports / leagues / canonical teams | relational, seeded (176 rosters) | Clean platform reference. Tenants read; platform curates; tenant additions possible as org-scoped overlays. |
| Canonical card catalog (cards/sets/players/checklists) | relational, single-org (~57k cards) | **✅ DECIDED (ADR 0005 Ruling A):** platform-level shared canonical catalog, **read-only to tenants**. `e10_cards`/`e10_players`/`e10_sets`/`e10_teams`/`e10_checklists` are platform-reference (NOT org-scoped). Org overlays add corrections + custom fields via `patch jsonb`; promotion of a private upload to the shared catalog is **platform-curated with review** (Phase 6 provenance). No tenant writes the platform catalog directly. |
| Marketplace definitions (Whatnot fee structures, export formats) | hardcoded/docs | Platform reference; versioned as marketplaces change formats. |

## Cards vertical (module #1)

Break models & formats, spot/slot generation (team/player/rules + partition checks), tiers & viability projection, chases & chase lists, checklist import (LLM + direct), grading attributes (company/grade/cert), card-specific item attributes (parallel, card #, year — the structured-field set riding `extra`), repacks + pack opener, the break-specific overlay surfaces (team board, chase cross-off), generated naming rules (Year·Brand·Line·…). **Rule: core never references these; the vertical plugs into core seams (inventory attributes, session types, event formats, overlay slots).** A second vertical (e.g. sneakers, coins) would supply its own module filling the same seams.

## Personal

Saved grid views, dashboard/dashlet layout (complaint #9), module memory (last-used view), notification prefs. Per-user within an org; survives device changes (cloud, not localStorage — current localStorage-only views are a known gap).

## Independent state dimensions (D0.1)

- **Lifecycle and visibility are independent.** Event/session lifecycle is `Created → Ready → Live → Ended → Corrected`; visibility changes independently between `Private ↔ Published`. Publishing does not advance lifecycle, and correcting an ended record does not implicitly republish it.
- **Sale state and assignment state are independent.** Sale state is `Available → Pending → Sold → Reopened/void/refund`; assignment state is `Unassigned → Assigned → Trade-pending → Reassigned → Locked`. Random formats sell before assignment; pick-your-team formats assign at purchase. A refund does not erase assignment history, and reassignment does not rewrite the sale.
- **Assignment trades preserve auditability.** Trades are non-monetary; both parties must be verified, mutually confirm, and may withdraw before confirmation. An operator commits the atomic swap. All open trades expire at break lock, with no post-start changes except an explicit operator correction.
- **Approval is a separate dimension.** Use the approval values defined above only where the organization's enabled capability and risk policy require maker–checker review.

## Track A reconciliation from D2-0 (before A6b)

1. **Preparation storage:** settle relational preparation tables versus versioned workspace JSONB. Preserve an immutable, append-only approved snapshot and the stale-approval/recovery behavior either way.
2. **Capability vocabulary:** reconcile D2-0's finer action set (`create_session`, `scheduling`, `assign_operators`, `configure_breaks`, `reserve_inventory`, `submit_checklist_sources`, `approve_checklists`, `approve_preparation`, `create_receiving`, `resolve_recovery`, `view_financial_estimates`) with the A6 allow-list vocabulary. Separate read from mutation where required: viewing Schedule without creating, viewing Inventory without reserving/receiving, reading the prepared handoff, `live_run` for Start-Live, and an edit capability for reopen-prep. Direct-route authorization must be deterministic. Settle this before the A6b parity seed is treated as final. Do not change `e10.module_bundle`: the verified A6a.1 ruling maps all six legacy keys (`home`, `inventory`, `reporting`, `schedule`, `settings`, `toolkit`) to `core`.
3. **Core session, cards entitlement:** `LiveSession` is core. A core-only organization can run sessions with no breaks. A cards-entitled Show may have zero or more card breaks while being prepared; going live through the break workflow requires one or more. When cards is disabled, card breaks, slots, and card checklists are absent rather than merely hidden.
4. **Multi-org UI acceptance:** organization switching and isolation behavior must satisfy the same hostile two-company proof required by A7. Test two orgs with distinct sessions, reservations, and queues; clear context on switch; deny a direct URL to another org's session at both UI and RLS layers; prevent all cross-org leakage; and keep cards terminology absent when cards is disabled. Include seller-private viewer data and cross-org relationship isolation.

---

## What this changes immediately

1. **Navigation naming (prototypes):** the rail's nouns come from CORE — Home, Schedule, Inventory, Live, Fulfill, Money — with cards-vertical surfaces (Breaks, Checklists, Repacks) as module entries, not top-level peers of the spine.
2. **Track A6 work list:** the "company-owned" list above IS the `organization_id` migration checklist; the card-catalog decision must be made before A6 finalizes the catalog tables.
3. **New concepts entering the system** (no current implementation): organization + entitlements, cost-model config, per-employee labor benchmarks, session P&L, attention queue, hits-attribution queue, import provenance, readiness state as stored/computed data.
4. **Prototype ⑤ addendum** (close & reconcile) designs against R1's cost model and F1's two-phase fulfillment — not a generic dashboard.

## Decisions (Trent, 2026-07-15)

1. **Card catalog: SHARED CANONICAL + org-scoped overlays.** ✅ Decided. One platform-curated catalog all card tenants read; private/corrected entries as overlays. Binding on Track A6's schema for `e10_cards`/`e10_players`/`e10_sets` (these become platform-reference tables, NOT org-scoped) and on Phase 6 provenance design.
2. **Roles: ✅ Decided (2026-07-15) — four org roles: Admin · Manager · Streamer · Operations Team Member** (shipping/fulfillment help). Platform admin stays separate above all of these. **Permission model: roles carry CUSTOMIZABLE permission sets, and a role's permission set is COPYABLE role-to-role** (clone as starting point, then adjust) — an evolution of the existing roles × capabilities matrix (`e10_role_permissions`), org-scoped in A6, with sensible defaults shipped per role. Consequences: (a) A6's role tables are org-defined roles + permission sets, not a hardcoded enum; (b) the Ops Team Member is a fourth persona whose home is the fulfillment queue — journey F1 gets an actor; (c) prototypes rename Owner→Admin and add the Ops home state.
3. **Checklist promotion flywheel: YES, with review** — ✅ Decided, with the note that platform (Trent's team) would likely manage or entirely drive the curation. Tenant uploads land privately; a platform review step promotes to shared. Phase 6 provenance is the mechanism; curation effort is a platform operating cost to plan for.

---

## ADR 0005 gate rulings (2026-07-16, Trent)

- **A — Card catalog + checklists:** shared canonical, platform-level, **read-only to tenants**; org overlays add corrections + custom fields; promotion to shared is **platform-curated (with review)**. **No tenant writes to the platform catalog.**
- **B — `e10_obs_*` competitive intel:** **company-private**, stored as **derived records carrying provenance + a consent/lawful-basis marker.**
- **C — Keys:** composite **`(organization_id, id)` everywhere** (structural cross-org isolation).
- **D — Session ⊃ breaks:** a **live-session parent hook ships in A6**; **one parent per existing break (no grouping)** — a retried show start produces two live events on one show.

## New product concepts discovered by the prototypes ①–⑥ (2026-07-16) — each needs a data-model home

Layer tag in brackets. **None built in A6** (recorded so the spine anticipates them); order/PO/credit/commission land in later phases.

1. **Store credit / buyback liability** [CORE, ledger-grade] — a **second append-only ledger** (issue/redeem/adjust) with receipt + lock rigor. Balances per **(organization, viewer, currency)** — **never cross-org spendable** (that would make the platform a money-holder). A bought-back card **re-enters inventory as an intake movement** (cost = credit paid). **Outstanding credit is a customer LIABILITY, tracked separately from inventory cost basis — not the same accounting number.** Depends on verified handles (ADR 0005 §6). **Tax/legal review** (gift-card / closed-loop rules, possible escheatment; per-company closed-loop reduces but does not eliminate exposure) before any external org carries balances.
2. **Multiple breaks per go-live session** [CORE] — session ⊃ breaks (1–n) with per-break save points/rollups. ADR 0005 §7 provides the hook.
3. **Purchase orders + receiving + vendor-owed credit** [CORE] — procurement mini-domain; shortfall = vendor credit.
4. **Cycle counts + variance** [CORE] — counting events; variances resolve to **correction movements** (through the ledger).
5. **Commission engine** [CORE, extends R1 cost model] — ✅ **DECIDED: composable component rows**, supporting flat per show, percentage of margin, percentage of break, and combinations such as a flat base plus margin bonus or per-break kicker. A rule is org-scoped configuration containing component rows (`type ∈ flat | pct_margin | pct_break | …`, rate/amount, and conditions such as “only if profitable”); evaluation sums the components. Organizations define defaults and may override them per streamer. A streamer sees only their own formula and total; admins see and manage all. It feeds the P&L labor line and live commission display and sits alongside the per-employee labor benchmark.
6. **Approvals queue (maker–checker)** [CORE] — managers propose (formats, POs, counts, receiving, checklist uploads), admins clear; **admin actions apply immediately.**
7. **Buyer session tools** [CARDS-VERTICAL, live] — buyer lookup filters the board to owned teams; multi-select combined-price sales; trade-in / re-spin with re-spin profit tracking.
8. **Significant-pull logging** [CARDS-VERTICAL] — checklist-linked, auto team-assignment; feeds companion hit-tracking; **hosts the buyback offer.**
9. **Aging-inventory bands** [CORE] — days-past-release hot/warm bands + "Break in" action.
10. **Owner-set weekly show target; pack-slip import auto-marking fulfillment; format-compare efficiency metrics** (Margin/hr, Gross/hr) [CORE].
11. **Case-first depletion** with box/case unit toggle on reservations [CORE inventory].

## Repack products (journey RP1 + prototype ⑥, 2026-07-16) — CARDS VERTICAL

- **Repack-eligibility is an item attribute;** value-completeness is a validation gate before the format math runs.
- **Bucket/odds configuration is org-scoped product data.**
- The **margin calculator is a PURE client function (no schema)** and must show **THREE distinct numbers, never conflated:** (a) **assigned value-back %** (buyer receives ÷ price), (b) **inventory gross margin** (price − card cost basis), (c) **contribution margin** (after fees, labor, packaging). [Refines the earlier two-lens note — gross vs contribution correctly split.]
- **Repack assembly = a transactional inventory TRANSFORMATION, not a simple transfer:** linked `transformation_consume` (source cards leave) + `transformation_output` (the pack appears) movements; **output cost basis is conserved from the consumed components, never hand-set** (ADR 0005 §13).
- **Manifest and allocation disclosure requires MORE than the ledger:** the movement ledger proves inventory moved, while disclosure additionally needs a **frozen versioned batch manifest** (component ids, quantities, assigned-value + cost-basis snapshots, bucket definitions, exact integer hit counts) plus an **immutable allocation method / algorithm version / pack numbering** (potentially seed commit-reveal or external audit). Recorded as the standard repacks must eventually meet; **not built in A6.**
- **Compliance:** do not make “provably fair,” odds, or equivalent consumer claims by default. Any such claim requires legal review and evidence that the disclosed manifest, allocation method, and actual assembly agree. The legal review rides with the buyback review.

## Money reconciliation (journey R1) — CORE, the Phase 10 metric contract

Session P&L = **hammer − marketplace fee% − per-employee labor benchmark − packing supplies − product cost basis.** Rollups day/week/month; **compare recorded totals vs marketplace deposits.** Store-credit issued/redeemed/outstanding enters this math (concept 1). Seeded from reality, not invented.

## Fulfillment reality (journey F1) — CORE

**Cubbies by spot number;** chases/hits set aside and **buyer-attributed post-stream** (a distinct **hits-attribution queue**); **Whatnot generates labels/slips — the app never prints them;** ship view is **two-phase** (spot-ordered pull + hits queue → buyer-consolidated packing). This is the **Operations Team Member's home.**
