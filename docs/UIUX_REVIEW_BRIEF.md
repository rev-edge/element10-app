# Element 10 — UI/UX Review Brief
### Operator-walked modules, layout and workflows · prepared for reviewer handoff

Prepared by the CPI, 2026-07-26, against the accepted build of screen
`08-product-workspace.html` (SHA-256 `a0e3de7be87989e675a05ffe2ad08a054c30e06ab1e5460b5128ea60c0f645ca`,
PF-C-S1.4). Everything below has passed both CPI source audit and an operator
hands-on walkthrough unless marked otherwise. A further corrective (PF-C-S1.5,
eight operator findings) is dispatched but not yet delivered; its items are
listed at the end so the reviewer does not re-report them.

---

## 1. What this artifact is

A single-file browser prototype (`08-product-workspace.html` + frozen `e10.css`)
that is the behavioral specification for the multi-tenant rebuild. It is the
working surface for the product-first pivot; screens 01–07 are frozen pre-pivot
evidence and are NOT in scope for review. No network, no backend: state is
in-memory, seeded per organization. Every rule it enforces is a contract for the
engine (Track A) — refusals seen in the UI become RLS policies and guarded RPCs.

This brief describes the reviewed artifact. `OPERATOR_LIFECYCLE.md` now governs
the surrounding operator jobs and handoffs; `UX_WORKFLOW_CONTRACT.md` governs
workflow planning and acceptance. A surface description here is never evidence
that the complete task loop is finished.

## 2. Global layout

Top to bottom:

- **Harness bar** (dark, labelled "PROTOTYPE HARNESS · NOT PRODUCTION"): a
  capability dropdown (e.g. "Admin — Inventory read + write", read-only roles), an
  organization toggle (**Org A · cards** = Rip City Breaks, cards-entitled;
  **Org B · core** = Cascade Supply Co, no cards module), cards-module toggles,
  and a live readout of the capability claims in effect. This bar is test
  scaffolding, not product UI.
- **App chrome**: Element 10 logotype, current-organization badge with role,
  global search field (decorative in prototype), person chip.
- **Left nav rail**, two zones:
  - Core: Operate (Home, Live, Fulfill) · Plan & stock (Schedule, **Inventory →
    Products**, **Vendors** (core — every organization buys from someone)) · Review (Money) · Organization
    (Settings).
  - **Cards module** (renders ONLY for a cards-entitled organization): Breaks,
    Checklists, Repacks, **Card inventory**. On a core org this entire section is
    absent — not disabled, absent.
- **Main surface** (`#main`): the current screen.
- **Overlay host** (`#ovhost`): all dialogs/wizards render here as a scrim +
  centered dialog. **Toast** (`#toast`): transient confirmations bottom-center.

Full-screen working surfaces (checklist review grid, focused exception
resolution) replace `#main` entirely rather than stacking on the dialog.

## 3. The shared grid (one component, four consumers)

Products, the checklist review grid, Vendors, and Card inventory all render
through one spec-driven grid. Uniform behavior everywhere:

- Per-column filter boxes composing with a global "search all visible columns"
  input; segmented chips where a surface defines them (e.g. All/Numbered/
  Unnumbered); active filters visible and clearable; live "N of M rows" count.
- Click-to-sort headers with ▲/▼; column show/hide via a **Columns ▾** picker
  (core columns hide but never delete); drag header to reorder; drag right edge
  to resize; content-aware default widths.
- Add column opens a per-surface **catalog** of known fields; minting a new
  field is admin-only and fails closed for others.
- Row selection where the surface is editable: header checkbox selects the
  visible page only, with an explicit disclosed "Select all N matching"
  escalation; bulk actions confirm in place on the button ("Confirm: set X = Y on
  N") and the last bulk action is undoable.
- Grid preferences (visible columns, widths, order, sort, operator-added
  columns) persist per organization per user; they never cross orgs.
- Read-only capability keeps every non-editing feature (filter, sort, resize,
  hide); create/edit/bulk controls are absent AND their mutators refuse if
  probed.

## 4. Products — list, detail, manual entry

**List** (Inventory → Products): grid of Product Masters — Product (name +
notes), Year, Brand·line, Category chip, Identifier, State (Ready / In setup /
Archived), with category chips and an "Include archived (N)" toggle as grid
filters. Two creation paths, deliberately ranked: a prominent **Set up from
documents** (the intended path) and a secondary **+ Manual entry**.

**Detail**: identity block (display name, year, brand, line, category, edition,
external identifier), state banners (Archived = read-only until restored; In
setup = not usable for ordering until at least one configuration exists and the
operator presses **Mark ready** — refusal at zero configurations), the
configurations list with packaging ladders, an advisory **Preferred vendor**
seam, and a read-only **Cost seam** stating cost will derive from purchase lots
(no number, no input, by ruling).

**Manual entry**: dialog with identity fields; duplicate identity (normalized
year·brand·line·category·edition) is refused within the organization, and a
conflict with an ARCHIVED product names it and offers View/Restore instead of
allowing a duplicate.

**Configurations**: each is "what you buy and stock" (Hobby Box, Blaster, Case)
with a channel (Hobby/Retail), defined top-down either as levels (box → 24 packs
→ 15 cards, base unit derived and displayed live) or as a reference to another
configuration plus a count (Case = 12 × Hobby Box). Cycle-protection prevents
self-referential chains at selection AND at save. Saving appends a new version;
history is retained; removing a configuration that others reference is refused
with the dependents named.

## 5. Product setup from documents — the flagship workflow

Five-step wizard (steps shown as a progress bar): **1 Source → 2 Documents → 3
Confirm product → 4 Extract → 5 Review & approve**.

1. **Source**: pick the publisher (Panini, Topps — extensible list, operator-
   selected, never inferred).
2. **Documents**: attached files listed, each with an editable kind
   (checklist spreadsheet, packaging table, odds document…); the operator can
   re-label anything the system guessed wrong.
3. **Confirm product**: the manual-entry identity form, AUTOFILLED from the
   documents. Every field carries a provenance badge — green "read from
   document", amber "inferred", or "edited" once touched — plus a source line.
   Correcting identity here flows into everything extracted after.
4. **Extract** (simulated in prototype; fixtures derive from the operator's real
   Panini/Topps files): shows the confirmed identity, the proposed configuration
   table (name, cards/pack × packs/box × boxes/case, per-case total, editable
   **Channel** column with basis "inferred from name" → "set by operator";
   confirming channels here discharges that decision), and checklist totals.
5. **Review & approve — exceptions first.** Cards needing a decision (blockers)
   at top, suspicious items below, auto-resolved exclusivity findings recorded
   with their resolution basis ("Hobby SKU Exclusive" resolves to a *channel*;
   "Mega Exclusive" to a *configuration*; "Breaker Exclusive" to a *route*;
   resolving to nothing raises a human decision — never invents a
   configuration). Actions per card: Confirm / Dismiss / **Resolve these rows…**
   (only where checklist rows are actually implicated).

**Resolve these rows…** opens a focused full-screen surface scoped to exactly
the matched rows (count + reason stated, remaining-exceptions counter), editable
with bulk actions. **Done** discharges the exception; **Cancel** reverts edits
and leaves it blocking. Entering alone never discharges (resolutions are
earned).

**Save and review →** (enabled once decisions are resolved) leaves the dialog
for the full-screen **checklist review grid**: the shared grid over a labelled
representative subset (1,616 rows loaded, true totals — 55,677 cards, 535 sets —
displayed), rows touched by an edited exception tinted amber with a per-row
badge and a "show only tagged" toggle. Its primary button **Approve & create
product** is the single mutator path: approval refuses unless the review surface
was genuinely entered, decisions are resolved, and authority is held. Paths with
no browsable checklist (core org; Topps derived-only) get a direct approve with
no empty review detour.

On approval the product is created with configurations and a **persisted
checklist** (reachable later from the Checklists nav, reopening in the same grid
in saved mode).

## 6. Vendors

Grid list (Vendor, Contact, Email, Phone, Type, State) + detail + dialog form.
Identity only by design: name, contacts, secondary contact, website, account
number, vendor type, repeatable **addresses with a role each** (mailing /
billing / ship-from), notes. NO payment terms, credit, pricing, tax, lead time —
purchasing belongs to later checkpoints and the screen says so.

Product ↔ vendor: a product may name **0..1 preferred vendor, advisory only** —
on-screen language states the actual vendor/qty/cost/ETA are decided on the
purchase order. Archiving a referenced vendor succeeds, clears the advisory
links, and tells the operator exactly which products were affected. Duplicate
identity refused (including against archived, with View/Restore). Archive-not-
delete throughout.

## 7. Card inventory (singles) — cards orgs only

**Acquisition-first flow**: every card references exactly one acquisition (no
orphans, refused at save). The parent Acquisition is also the durable review and
resume surface.

- **New acquisition**: name/description, date, total paid, and a three-mode vendor
  row — **Pick vendor** / **Name the seller** / **Create vendor now**. Acquisition
  channel is a required lifecycle concept but remains deferred to S2 in this
  artifact. Distribution, acquisition channel, sales channel, and fulfillment
  route remain four separate concepts. Shape is **Single card** or **Collection**.
  Expected card count on a collection is advisory metadata only. Saving creates
  zero blank CardInstances and offers Add first card or Review acquisition.
- **Add/Edit card**: Acquisition stays preselected. **Player / Character** uses a
  checklist-backed typeahead. Picking can fill name, brand, line, set, number,
  parallel, print run, year, and team with compact provenance; manual entry is
  always available. Card display identity is composed from its structured fields.
  Cost basis is never directly editable: single-card basis derives from the
  Acquisition; collection cards remain zero until cost assignment.
- **Identity and condition guards**: name, brand, line, and year are required;
  company+cert is org-unique including archived records; likely raw duplicates
  warn without blocking; raw-or-graded consistency refuses invalid combinations.
- **Save continuation is state-aware**:
  - collection below its advisory expected count: Add another is primary;
  - collection at/above expected count: Review acquisition is primary;
  - single-card acquisition: Review acquisition is primary and no second-card
    invitation is shown;
  - edit existing: return to the invoking grid/detail context.
- **Acquisition review** shows `N of ~M entered`, cards, amount paid, current cost
  state, Add card, Edit acquisition, and available lifecycle actions. It supports
  incomplete exit and later resume. Before S2 exists, cost assignment is described
  as planned and unavailable, never as a reachable immediate next step.
- **Grid** uses the shared component and preserves filters, selection, and origin
  through edit and return.
- States in UI: active and archived ONLY (held/sold/repack states exist in the
  approved model but are deliberately not rendered until their gates build the
  events that reach them).

## 8. Cross-cutting behavior a reviewer should test against

- **Organization isolation**: switching Org A ↔ Org B swaps all data; nothing
  crosses — including grid preferences, operator-added columns, open dialogs
  (cleared on switch), and the checklist search index (Org B: 0 rows).
- **Cards-off**: a core organization has no cards nav, cannot reach singles/
  checklists surfaces at all, and completes product setup with neutral document
  kinds and zero card vocabulary anywhere (enforced by a 28-term forbidden scan
  over `#app` + `#ovhost` + `#toast`).
- **Fail-closed**: every mutator refuses independently on authority, org
  mismatch, archived state, and missing target — the UI not offering a button is
  never the enforcement.
- **Archive, never delete**; append-only versioning on configurations;
  provenance marks on anything inferred; no browser-native dialogs anywhere.
- **Task-loop completion**: every mutation shows its committed result and offers
  a state-aware continuation, review/correction, and safe exit. A toast is never
  the sole success state.
- **Workflow evidence**: first-time, repeat, incomplete/resume, final-item,
  edit/return, Cancel-no-creation, and denial/conflict recovery are exercised
  before packaging. Static screenshots alone are insufficient.

## 9. Known and already dispositioned

Do not duplicate these as undiscovered defects. Still inspect their surrounding
task loops and report any continuation, review, return, resume, or recovery gap
that remains after the named correction.

CORRECTION (2026-07-26): an earlier revision of this brief said Vendors render
only for cards organizations. Wrong — Vendors are core, reachable by every
organization, per PF-C3. The source behavior is correct.


PF-C-S1.5 was dispatched for: dropdowns not dismissing on outside click/Escape
(universal); grid filter-row placeholder styling and richer filter operations
(contains / does not contain / equals / empty); **brand + line + year required**
on every card; print-run "/" affordance and serial redirect; acquisition save
auto-opening first card entry; per-card images/links/asking price (advisory,
outside money math); cert-format sanity warning (warn, not block).

## 10. Not built yet

Cost-basis assignment workflow (S2) · selling a single / disposition (S3) ·
repack assembly (S4) · margin reporting (S5) · sealed-product purchasing:
PO/receipt/lot (PF-C4+) · any real extraction, storage, or backend. Breaks,
Repacks, Schedule, Live, Fulfill, Money screens are pre-pivot artifacts, frozen,
replaced at PF-C21.

These boundaries remain out of implementation scope until their gates. They are
not out of design-analysis scope. Every preceding workflow must report the seam
and end in an honest usable state without promising an unavailable next action.
