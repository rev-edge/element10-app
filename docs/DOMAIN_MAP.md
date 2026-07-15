# Element 10 — Domain & Module Map (Track B, step 1)

_v1.0 — 2026-07-15. Classifies every concept in the system into four layers. This document drives three things: the new app's information architecture and navigation naming, the tenancy spine's data model (Track A step 6), and the boundary between the core product and the cards vertical. Sources: Workflow Inventory (journeys S1/M1/O1/R1/F1 + complaints), Platform Overview, the tenancy spec._

## The four layers

1. **CORE PRODUCT** — the platform machinery every vertical and tenant uses. Exists once.
2. **COMPANY-OWNED (tenant)** — business data each organization owns exclusively. Gets `organization_id`; isolated by RLS.
3. **SHARED REFERENCE** — canonical data all tenants read, none own. Curated at platform level with provenance.
4. **CARDS VERTICAL** — the first vertical's module. Other industries get sibling modules; the core never depends on these.

Plus a fifth minor layer: **PERSONAL** — per-user preferences inside an organization (saved views, dashboard layout, module memory).

---

## Core product

| Concept | Today | Notes |
|---|---|---|
| Organization | ✗ missing (single-org) | Track A6 builds it. Roles: Owner / Manager / Streamer (from the journey map) + platform admin kept separate. |
| Membership + invitations | partial (`e10_members`, one org, global roles) | Re-keyed `(org, user)`; roles become org-scoped. |
| Module entitlements | ✗ missing | Which verticals/features an org has. A6. |
| **Show (event)** | JSONB workspace | Core, not cards-specific: every live-commerce vertical schedules events. Carries the **readiness state** (computable: checklist ✓ inventory ✓ format ✓ assigned ✓) — the manager→streamer handoff object. |
| **Live session** | relational (`e10_break_sessions` etc.) | Core: any vertical runs live selling sessions. Carries `source_show_ref`. The streamer→fulfillment handoff object. |
| **Inventory item + reservation** | relational (post-M4) | Core: every vertical stocks and reserves product. Vertical-specific *attributes* ride the `extra` pattern (see cards vertical). |
| **Movement ledger + receipts** | relational, append-only | Core, and the crown jewel — cost basis, consumption, idempotency are industry-agnostic. |
| Order / line item | ✗ (Phase 8) | Core; marketplace-agnostic shape, Whatnot-first implementation. |
| Fulfillment / shipment | minimal (ship view) | Core. Per F1: two-phase (spot-ordered pull + hits-attribution queue → buyer-consolidated packing). Labels/slips stay platform-side (Whatnot's). |
| Customer / buyer + aliases | ✗ (Phase 9) | Core; platform identity, never shipping details as key. |
| **Cost model configuration** | ✗ missing — NEW from R1 | Marketplace fee %, **per-employee labor benchmarks**, packing-supplies cost. Tenant-configured; feeds session P&L. |
| Session P&L + reconciliation | ✗ (Phase 10) | Per R1: net = hammer − fee% − labor − supplies − product cost; rollups day/week/month; recorded-vs-deposits comparison. |
| Schedule / week programming | JSONB workspace | Core; the manager's working object is the WEEK, not the show. |
| Attention queue | ✗ (prototyped in shell ①) | Core: unassigned shows, missing checklists, unshipped sales, unresolved drift. Derived, never manually curated. |
| Notes / to-dos / attachments | JSONB workspace | Core collaboration light-data; stays CAS-protected JSONB (low-write). |
| Import provenance | ✗ (Phase 6 prerequisite) | Which file/batch/edit produced a value. Core pattern used by all reference data. |

## Company-owned (tenant) — the isolation list for Track A6

Everything an org's operators create: inventory items, reservations, movements, receipts, shows, sessions/slots/events, schedules, break models, checklists *they upload*, repacks, copy sets, chase lists, notes/todos/attachments, cost-model config, orders, fulfillment records, customers, saved org-level views. **Every one of these tables gets `organization_id NOT NULL`** and org-scoped RLS/RPCs/idempotency in A6.

## Shared reference

| Concept | Today | Decision needed |
|---|---|---|
| Sports / leagues / canonical teams | relational, seeded (176 rosters) | Clean platform reference. Tenants read; platform curates; tenant additions possible as org-scoped overlays. |
| Canonical card catalog (cards/sets/players) | relational, single-org (~57k cards) | **OPEN DECISION, flag for Trent:** (a) platform-level shared catalog — one checklist upload benefits every cards tenant, big product moat, but requires curation/provenance/dedup governance; or (b) per-tenant catalogs — simpler isolation, duplicated effort per tenant. Recommendation: **(a) shared canonical + org-scoped overlay for custom/corrected entries**, with provenance (Phase 6) as the governance mechanism. Affects A6 schema for `e10_cards`/`e10_players`/`e10_sets`. |
| Marketplace definitions (Whatnot fee structures, export formats) | hardcoded/docs | Platform reference; versioned as marketplaces change formats. |

## Cards vertical (module #1)

Break models & formats, spot/slot generation (team/player/rules + partition checks), tiers & viability projection, chases & chase lists, checklist import (LLM + direct), grading attributes (company/grade/cert), card-specific item attributes (parallel, card #, year — the structured-field set riding `extra`), repacks + pack opener, the break-specific overlay surfaces (team board, chase cross-off), generated naming rules (Year·Brand·Line·…). **Rule: core never references these; the vertical plugs into core seams (inventory attributes, session types, event formats, overlay slots).** A second vertical (e.g. sneakers, coins) would supply its own module filling the same seams.

## Personal

Saved grid views, dashboard/dashlet layout (complaint #9), module memory (last-used view), notification prefs. Per-user within an org; survives device changes (cloud, not localStorage — current localStorage-only views are a known gap).

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
