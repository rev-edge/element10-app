# Current project status

## September 17 shared import, export, and AI architecture

`SHARED_IMPORT_EXPORT_AI_ARCHITECTURE_2026-09-17.md` reconciles the existing
checklist mapper, X5 intake, X8 assistant/query/draft seams, export authority,
entitlements, and checklist-led product contracts against four owner-confirmed
execution options: Element 10-managed AI, organization-funded AI, external
assistant connectors, and fully manual operation. The current smart mapper is a
useful prototype but not an accepted shared architecture: it is provider-bound
and lacks organization policy, durable jobs, funding/usage accounting, governed
import revisions, and deployment evidence. Companion requirements, acceptance,
and dependency registers are recorded in the three `SHARED_IMPORT_EXPORT_AI_*`
documents. No migration, credential connection, paid call, environment contact,
integration activation, or deployment is authorized.

## September 16 CRM data-layer reconciliation

`CRM_DATA_LAYER_RECONCILIATION_2026-09-16.md` audits CRM-01 through CRM-05 and
CRM-A01 through CRM-A10 against the canonical customer, transaction, native
break-sale, reconciliation, and spend-reporting implementation. The current
core is substantial, but two-way acquisition/consignment links, contact and
shipping history, declared preferences and derived affinities,
payment/settlement facts, validated Whatnot intake, field-level privacy, and
module-disable behavior remain partial or missing. The document separates
current local source from historical staging evidence and absent production
verification, records official Whatnot export limits, and proposes additive
increments only. No migration, database contact, integration activation, or
production change is authorized.

## September 16 checklist ingestion design

`CHECKLIST_INGESTION_DESIGN_2026-09-16.md` verifies all 43 supplied checklist
samples and reconciles the operator lifecycle, card/release/variant identity,
optional subject linking, provenance, bounded reporting, current catalog
authority, and a small Panini Prizm first slice. The design separates an
organization-approved checklist version from platform publication and creates
no inventory or commercial facts. Eight owner decisions remain in
`CHECKLIST_INGESTION_DESIGN_2026-09-16_COVER_NOTE.md`. No implementation or
environment change is authorized.

## September 16 subject identity clarification

`SUBJECT_IDENTITY_RECONCILIATION_2026-09-16.md` records subject identity as an
optional, zero-to-many relationship on exact catalog variants. Current source
already supports multi-subject variant links and cross-product subject queries,
but canonical storage and review remain player/sports-named and organization
imports lack a durable unresolved-name path. The proposal preserves stable IDs,
adds governed subject kinds, aliases/external IDs and private unresolved
mentions, keeps canonical publication platform-controlled, and forbids implicit
financial attribution or cross-organization business leakage. Missing subject
links remain non-blocking. No implementation or environment change is
authorized.

## September 16 configuration applicability proposal

`CONFIGURATION_CHECKLIST_APPLICABILITY_RECONCILIATION_2026-09-16.md` reconciles
the proposed many-to-many relationship between immutable Configuration Versions
and versioned checklist entries. Current source has the product/configuration
and canonical catalog foundations but no physical applicability contract. The
proposal uses organization-owned revisioned reviews and immutable confirmed
snapshots, explicit packaging composition, unknown-by-default semantics, and
exact preparation pins. It preserves checklist-independent purchasing and
receiving and optional source provenance for owned singles. Capability,
confirmation, inheritance, completeness, and platform packaging decisions
remain open. No migration or environment change is authorized.

## September 16 Product/checklist scope delta

`PRODUCT_CHECKLIST_SCOPE_RECONCILIATION_2026-09-16.md` reconciles the permanent
Products workspace and staged checklist-import lifecycle against current Track
A source. The product/configuration foundation and platform catalog promotion
are real, but the organization-owned upload, mapping, row review, approved
version, readiness, and full-grid contracts remain partial or missing. It also
corrects the module boundary: Product checklist maintenance is not inherently a
Cards entitlement. Shop operational approval, organization overlay publication,
and platform canonical promotion are three distinct transitions. No schema or
environment change is authorized by that document.

## September 14 modular-scope reconciliation

The owner-confirmed Inventory/Cards boundary is recorded in
`MODULAR_SCOPE_2026-09-14.md` and reconciled against Track A source and the
latest vendor-bill evidence in
`MODULAR_SCOPE_RECONCILIATION_2026-09-14.md`. The shared backend core is
substantial, but the dedicated Cards workspace, presentation modes, stable
module transition behavior, and cross-channel listing reconciliation remain
partial or missing. Solo-owner invoice approval is intentionally fail-closed
pending an explicit owner policy; the existing reviewer/approver separation is
not weakened. This documentation update changes no schema or environment and
does not self-accept MOD-01 through MOD-10.

Reconciled September 12, 2026 against canonical `foundation-a6` implementation at
`6e4beb5a424f562e871726cfedf52ff7c393959e`, committed migrations/tests,
explicit staging verification and the evidence documents below.

This is the current progress index. BOARD.md remains acceptance authority.
Older dated plans, gap descriptions and completion messages are historical
unless reaffirmed here. The reconciliation document itself changes no runtime
state and does not self-accept the implementation.

## Two different corrective series

Do not conflate the external X1-X8 review's **R0-R8** remediation with the
later table-by-table schema expert review's **C1-C9** improvements. Both ran
after review. Track A completed C1-C9 locally, but its last explicit R2 report
still lists outstanding work. Completion of the C-series goal is not acceptance
of the R-series or of the whole application.

| Workstream | Evidence-backed status | Next action |
| --- | --- | --- |
| X1-X8 original foundation | Implemented; original unconditional acceptance superseded by external conditional acceptance | Close remaining external findings; do not rebuild the foundation |
| R0 review preservation | Report and scope snapshots preserved; authoritative trace reconciled to current executable evidence | Preserve the audit trail |
| R1 inventory corrections | Independently accepted through staging at runtime `5641b18`, evidence `06d1cde` | Preserve accepted regression coverage |
| R2 customer corrections | Implemented with all final-lock authority, native/import reconciliation and no-write loser proofs | Await exact-head CI and final independent verdict |
| R3 intake provenance/deduplication | Implemented with source claims, cross-batch identity and correction/reimport race evidence | Await final independent verdict |
| R4 visibility/authority | Implemented with audience, multi-membership and suspended-organization reader/writer proofs | Await final independent verdict |
| R5 immutable history and identity writers | Implemented with immutable configuration/provider mapping history and forced CAS races | Await final independent verdict |
| R6 validation/error/replay contracts | Implemented, including explicit pre-R6 stored-fingerprint receipt/reservation/event replay | Await final independent verdict |
| R7 scope dispositions | Implemented with legacy-truncate closure and retained compatibility boundaries | Await final independent verdict |
| R8 final verification | Runtime and staging evidence complete; exact-head CI and renewed independent review in progress | Do not self-accept |
| C1-C9 schema expert corrections | All nine completed; current live verification confirms their migration names are included in staging's 147/147 ledger parity | Preserve in combined regression and final review |
| Multilingual backend | Requirements queued; no implementation evidence found | Preferences, translated labels/aliases, locale/fallback and stable message contracts after external corrections |
| Track B | Existing prototype work plus receiving preflight; latest accessible review still requires contract reconciliation | Refresh receiving design against current engine before implementation; owner retains UI acceptance |
| Production | No rollout authorized by this reconciliation | Separate explicit production go/no-go |

R2 now has executable proof for all twelve final-lock authority races, reviewed
same-slot `new_transaction` resale, symmetric native/import duplicate
prevention, official totals, altered and omitted scope, managed versus trusted
non-managed native evidence, released-after-approval denial and exact replay.
The combined R2-R8 result remains unaccepted until exact-head CI and renewed
independent review complete.

## Newer work that closes or narrows old gaps

| Former gap | Actual newer result | What remains |
| --- | --- | --- |
| Checklist data cannot enter canonical catalog | C1 `3a84af2`: governed platform-admin checklist promotion, subject links, reviewed facet resolution and unresolved evidence | General identity creation coverage, UI curation and final publication are not all implied |
| No typed custom-field registry | C2 `fe048a8`: definitions, controlled terms, typed values and organization/capability checks | Environment-specific JSON census/backfill, UI and multilingual labels; do not claim complete versioned-definition history |
| Ungoverned capability strings | C3 `0223cff`: registry, validated grant keys and separate catalog propose/review/publish operations | Complete proposal-to-publication workflow and consistent privacy-safe readers |
| No platform registry or buyer presentation bridge | C4 `1c5ce7f`: platform identity, live buyer lookup and assignment/release presentation outbox events | Unknown-buyer onboarding, public payload sanitization, realtime delivery, reconnect and actual OBS/companion UI |
| Checklist count can drift | C5 `8640c1d`: transactional insert/delete/reassignment maintenance and drift rejection | Environment verification, not another implementation batch |
| No suspension history | C6 `9464488`: reversible status command, timestamps, unknown-time baseline and append-only history | Does not by itself prove every API rejects suspended organizations (R4) |
| No central administrative audit | C7 `ef8154f`: restricted append-only mutable-data audit index | Does not replace domain histories or automatically close IMPL-12 immutability |
| Catalog term query index absent | C8 `ea80135`: measured term-led index | Broader scale measurements only when justified by workload |
| Blanket IDs/timestamps requested | C9 `1601d49`: all 182 tables classified; no blanket schema retrofit justified | Keep this disposition closed unless new lifecycle evidence appears |

C4's outbox is service-only and contains internal identifiers. It is not a
viewer-safe response. A downstream allowlisted projection is still required.

## Track B and cross-track dependencies

The latest accessible Track B receiving review was against old head `ee18497`.
Its old quantity-only allocation and whole-lot-status descriptions must be
rechecked against the later X3/X4 implementation, not blindly reopened as
current defects. No completed reconciliation artifact was found under the
proposed `TA_C5_RECEIVING_RECONCILIATION.md` name during this audit.

- Receiving: reconcile PO-first, invoice-first, partial/damaged/quarantined
  receipt, allocation and cost display against current contracts, then implement
  and walk through the complete journey.
- Live breaking, companion and OBS: the session/customer/inventory foundations
  and C4 bridge are backend progress, not proof that revised screens shipped.
  Significant-pull ownership/notification/buyback remains a separately recorded
  richer workflow gap, not satisfied by a `case_hit` event.
- Customer/market grids, planners and relational navigation remain Track B
  implementation and user-review work. Backend reporting APIs are not screens.
- Multilingual UI follows backend contracts. Chat, live feeds, scheduled
  trackers and collector showcase remain deferred, not silently included in
  the completed backend goal.

## Evidence and freshness

- [External report](reviews/2026-09-12-ta-external/EXTERNAL_REVIEW_REPORT.txt)
- [R-series plan](TA_EXTERNAL_REVIEW_REMEDIATION_PLAN_2026-09-12.md)
- [Independent R1 acceptance](TA_REMEDIATION_INDEPENDENT_REVIEW_2026-09-12.md)
- [R1 staging packet](TA_R1_STAGING_EVIDENCE.md)
- [R2 initial staging packet](TA_R2_STAGING_EVIDENCE.md), historical to `d1a2b44`; later corrections reach `436de45`
- [C1-C9 execution and completion audit](BACKEND_SCHEMA_EXPERT_FEEDBACK_PLAN_2026-09-12.md#execution-checkpoints)
- [Backend integration contracts](TRACK_A_BACKEND_INTEGRATION_HANDOFF.md)

The older `ce463d6` C-series packet reported local replay and did not itself
contact staging or production. The current R2-R8 closure subsequently contacted
staging explicitly and verified all 147 migration names, including C1-C9 and
the two R6 closure deltas. The original 145-name schema manifest retains its
recorded parity result; both later function deltas were applied and separately
introspected on staging. Production was not contacted. Historical environment
claims are not extended beyond their recorded observations.
