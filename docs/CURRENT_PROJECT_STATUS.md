# Current project status

Reconciled September 12, 2026 against canonical `foundation-a6` at
`ce463d6dbf51e4174c1224b9122d835691ce0766`, Track A's chat through
17:42:12 UTC, committed migrations/tests and the evidence documents below.

This is the current progress index. BOARD.md remains acceptance authority.
Older dated plans, gap descriptions and completion messages are historical
unless reaffirmed here. This reconciliation changes documentation only. It
does not rerun database tests, independently accept new code, or deploy anything.

## Two different corrective series

Do not conflate the external X1-X8 review's **R0-R8** remediation with the
later table-by-table schema expert review's **C1-C9** improvements. Both ran
after review. Track A completed C1-C9 locally, but its last explicit R2 report
still lists outstanding work. Completion of the C-series goal is not acceptance
of the R-series or of the whole application.

| Workstream | Evidence-backed status | Next action |
| --- | --- | --- |
| X1-X8 original foundation | Implemented; original unconditional acceptance superseded by external conditional acceptance | Close remaining external findings; do not rebuild the foundation |
| R0 review preservation | Report and scope snapshots committed at `43e1bf5`; trace claims reopened | Complete final finding-to-evidence closure during R8 |
| R1 inventory corrections | Independently accepted through staging at runtime `5641b18`, evidence `06d1cde` | Preserve accepted regression coverage |
| R2 customer corrections | Final local correction and complete proof implemented after `436de45`; ready for renewed independent review | Run exact-head CI and explicit staging verification in R8; do not self-accept |
| R3 intake provenance/deduplication | No closure evidence found in later commits or chat | Correct source claims, cross-batch identity and correction/reimport race |
| R4 visibility/authority | No closure evidence found | Verify internal comments, multi-membership catalog reads and suspended-org reader/writer coverage |
| R5 immutable history and identity writers | Partially overlapped by C1's checklist promotion; not closed | Map promotion against each missing X1 creation path; verify configuration/provider history immutability separately |
| R6 validation/error/replay contracts | No complete closure evidence found | Close remaining IMPL-14 subitems individually |
| R7 scope dispositions | Later schema work addresses selected architecture concerns, not every SCOPE item | Record each remaining policy/compatibility disposition without reopening already decided technical choices |
| R8 final verification | Not complete | Combined regression, exact-head CI, staging evidence and renewed independent review |
| C1-C9 schema expert corrections | All nine completed and locally verified by builder; final record `ce463d6` | Independent review and environment verification of this newer delta; no staging rollout is claimed |
| Multilingual backend | Requirements queued; no implementation evidence found | Preferences, translated labels/aliases, locale/fallback and stable message contracts after external corrections |
| Track B | Existing prototype work plus receiving preflight; latest accessible review still requires contract reconciliation | Refresh receiving design against current engine before implementation; owner retains UI acceptance |
| Production | No rollout authorized by this reconciliation | Separate explicit production go/no-go |

R2 now has executable proof for all twelve final-lock authority races, reviewed
same-slot `new_transaction` resale, symmetric native/import duplicate
prevention, official totals, altered and omitted scope, managed versus trusted
non-managed native evidence, released-after-approval denial and exact replay.
It remains unaccepted until independent review and the R8 exact-head CI/staging
gate complete.

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

The C-series packet reports clean replay, focused C1-C9 suites, C5 concurrency,
catalog regressions and default-privilege checks passing, with two pre-existing
lint findings. This reconciliation checked the chat, committed artifacts and
test inventory, not a fresh execution of those database tests. Neither staging
nor production was contacted. Historical status and environment claims must not
be extended to newer commits without fresh evidence.
