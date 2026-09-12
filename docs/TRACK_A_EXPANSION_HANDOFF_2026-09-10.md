# Track A expanded scope handoff

## Current execution handoff, 2026-09-12

The owner-approved TA-X1 through TA-X8 backend foundation has been implemented
and verified through staging. Production remains untouched and `main` remains
unchanged. The authoritative completion artifacts are:

- `TA_X1_X8_FINAL_ACCEPTANCE_MATRIX.md`, batch and universal-gate audit
- `TA_X1_X8_ACCEPTANCE_TRACE.md`, one row per named acceptance case
- `TRACK_A_BACKEND_INTEGRATION_HANDOFF.md`, exact consumer-facing contracts,
  signatures, permissions, bounds and non-claims
- batch-specific staging evidence files cited by the matrix

The final independent-review findings are closed as follows:

| Finding | Closure | Evidence |
| --- | --- | --- |
| F1, full authorized customer cohort before paging | X7f v2 aggregate bounds, stable sorting, query-bound cursor and full-cohort totals | Runtime/test head `1dbd2ec`; staging acceptance `26442b8`; `TA_X4H_X7F_STAGING_EVIDENCE.md` |
| F2, official known-history spend with coverage | X7f `known_history` mode, stable cutoff, refunds/deduplication, explicit unknown/source-history coverage and bounded resources | Same X7f evidence and exact-head CI `34682691228` |
| F3, combined cross-product rookie PSA 9 query | Public reader combines subject, rookie, graded, PSA and grade 9 across two releases with bounded continuation | Test head `d0d097f`; staging evidence `65751b6`; CI `34683432065` |
| F4, same-name identity ambiguity | Platform-admin-only append-only proposal/candidate/rejection review; same-name uniqueness removed while UUID identity remains; no approval/link/merge/split | Runtime/test head `bf99230`; staging evidence `f359fb0`; CI `34684368998` |

F4 replay warning: an exact proposal replay returns the original operation
result. Its status is historical and is not the current case status after a
later rejection. Consumers must call the bounded reader for current state.

No unresolved approved backend requirement is knowingly hidden behind a UI or
demo label. Named presentation fixtures remain Track B only where the generic
backend behavior is executable. Wishlist storage is independent. Live feeds,
scheduled monitors, chatbot behavior, collector showcase, external dispatch,
secrets, unresolved commercial policy, production deployment and `main` merge
remain outside this completed staging foundation.

## Later owner authorization

The owner subsequently approved the expanded Track A implementation goal via Codex, including isolated tests and explicitly targeted staging migrations. See BOARD.md, "September 10 owner authorization: expanded Track A goal." The documentation-only and parked-implementation limits in the original relay below are historical and superseded for that approved backend scope. Production cutover, UI work, and excluded integrations remain unauthorized. Direct Claude Code delivery remains unconfirmed; the active executor is the existing Codex task `Track A: Data Layer`.

## Backend completion versus product surfaces

The live-breaking control board, viewer/customer companion, OBS overlay, and
customer reporting screens remain in the product vision. Excluding their UI
implementation from this Track A goal does not remove them from the roadmap.

Track A's integration handoff must identify the existing or newly verified
contracts each surface can use, its permission boundary, required fixtures, and
any remaining backend gap. Native board activity stays provisional until the
separate authorized posting workflow; companion presence is not verified video
watch time. Viewer and overlay access must not expose shop-private operational
or customer data.

Track B owns presentation and adoption of those contracts after the owner's
design decisions. Existing screens, standalone pages, and earlier prototypes
are not proof that the expanded backend is wired into them. UI integration,
cross-surface end-to-end verification, and separately authorized production
release remain distinct gates. Current backend progress and evidence belong in
`TRACK_A_EXPANSION_PLAN_2026-09-10.md`, not the historical relay below.

## Original documentation-reconciliation relay

Prepared for Claude Code following owner request. Delivery to Claude is not yet confirmed. This is a design/plan reconciliation task, not authorization for production cutover or broad implementation. Preserve Track A's parked execution status until the owner approves a scoped plan.

Canonical checkout: `/Users/tsconnely/dev/element10-app`. Read its current project instructions and `BOARD.md` first. Preserve existing dirty changes. The Streaming folder holds review artifacts, not the authoritative git checkout.

## Required review

Read `docs/EXPANSION_AUDIT_2026-09-10.md`, `docs/EXPANSION_FRAMEWORK.md`, `docs/EXPANSION_ACCEPTANCE_CASES.md`, `docs/CARD_DATA_COMPARATIVE_REVIEW_2026-09-10.md`, `docs/ROADMAP.md` and their linked domain/lifecycle authorities. Owner review notes are at `/Users/tsconnely/Library/Mobile Documents/com~apple~CloudDocs/Streaming/element10-app/OWNER_REVIEW_NOTES_2026-09-10.md`.

Reconcile Track A's data architecture and implementation plan against these decisions:

- Permission-aware purchasing destinations, historical cost suggestions, internal/vendor comments and linked PO/invoice/receipt/credit workflows.
- Shared transaction core with optional Cards module; stable product/vendor/configuration/subject identifiers and reviewed mappings.
- Canonical release/variant versus physical-copy separation. Do not promote the prototype duplicate key: it omits year and includes serial numerator.
- Typed lifecycle history, idempotent imported/manual/native evidence and auditable corrections.
- Customer retail/break dimensions; provisional board activity separate from eligible approved posted spend. Optional reviewed posting, no double counting. Presence telemetry is not video watch time.
- Internal-data-first cross-catalog BI: composable dimensions, explicit query grain, governed parallel/color/rookie/grade facets, full-dataset filters and source drill-down. External feeds optional.
- Grading assessments/history, population snapshots, source-aware valuation runs, and portfolio acquisition versus appreciation attribution.
- AI-ready permission-checked query/action seams; drafts reviewed, answers sourced. No chatbot build implied.
- Wishlist independent of monitoring; future monitors have explicit cadence and evidence basis.
- Final deferred collector showcase with standalone media/display items and optional later tracking references. No near-term dependency.

Produce a requirement-to-existing-schema/contract matrix: verified existing, partial, missing, conflicting, deferred. Cite exact files and evidence; do not equate a written requirement with an implemented feature. Identify changes to the current Track A plan, dependencies on prototype decisions, and the smallest next design gate. Update relevant Track A planning documents only, preserving historical accepted evidence. Do not apply migrations, change policies, push, deploy or initiate production cutover. Do not weaken tenant isolation or expose secrets.

## Prototype status to respect

R1 review HTML remains unchanged. The separate candidate at `/Users/tsconnely/Library/Mobile Documents/com~apple~CloudDocs/Streaming/element10-app/review/vision-2026-09-10/08-product-workspace.html` adds purchasing comments only. Its `DELIVERY_REPORT.md` describes browser verification, memory-only behavior and five inherited sweep failures. The full expanded vision is not implemented in that candidate or production. UI work needs a separate verified Track B plan and must not be represented as shipped by a documentation update.
