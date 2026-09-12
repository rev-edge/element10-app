# TA-X1 through TA-X8 final acceptance matrix

Date: 2026-09-12

Status: implementation and staging evidence complete; final independent
requirements review requested.

This is the authoritative completion audit for the owner-approved Track A
backend expansion. It supersedes only stale progress labels in planning and
review-preparation documents. It does not alter their requirements or any
product decision. The existing user-edited planning files remain untouched.

## Scope and authority

Audited against:

- `docs/TRACK_A_EXPANSION_PLAN_2026-09-10.md`
- `docs/EXPANSION_FRAMEWORK.md`
- `docs/EXPANSION_ACCEPTANCE_CASES.md`
- `docs/DOMAIN_MAP.md`
- `docs/SECURITY.md`
- `docs/TA_X7E_REVIEW_CHECKLIST.md`
- `docs/TA_X8_REVIEW_CHECKLIST.md`
- `docs/TA_X8_IMPLEMENTATION_CONTRACT.md`

The implementation consists of 101 additive `202609*` migrations and 113
`tests/ta_x*` files. Current implementation head `87e3e675d4b096a458ae28736f3e9d477fbfbf79`
passed the entire registered CI suite in run `34672627839`. Evidence-only head
`f438f5e79de556e7c07d32fefe521a1ef70edb3c` adds the X8c staging packet.

## Batch reconciliation

| Batch | Implemented contract | Executable evidence | Staging evidence and disposition |
| --- | --- | --- | --- |
| X1 | Org product master; immutable configuration versions; release-scoped variants and subjects; provider mappings; physical unique items; dated player affiliations and depicted-team context | `ta_x1_identity_foundation_test.sql`; `ta_x1b_player_affiliations_test.sql`; `ta_x1b_player_affiliation_concurrent_test.js`; A7; default privileges | Migrations `20260910171106`, `20260911190000`, `20260911190001`; X1b independently accepted at `cd71d198`; tenant isolation, multi-subject, Cards-off, copy/variant and correction/revocation cases pass |
| X2 | Active locations and actor grants; suppliers; exact-configuration offerings; bounded eligible-destination read; hardened location predicate | `ta_x2_location_supplier_test.sql`; A7; default privileges | Migrations `20260910173520`, `20260910174555`; CI/staging verified; no accounting event or forbidden text-location override introduced |
| X3 | Separate PO, invoice, credit and receipt documents and lines; immutable revisions; source deduplication; explicit quantity and amount allocations; distinct lifecycle authority; audience-safe comments; bounded supplier workspace reads | `ta_x3a_*` through `ta_x3f_*`, including all SQL and two-connection suites; predecessor upgrade; A7; default privileges | Migrations `20260910174308` through `20260911223000`, including FK indexes; evidence packets `TA_X3C_STAGING_EVIDENCE.md`, `TA_X3D0_STAGING_EVIDENCE.md`, `TA_X3D1A_STAGING_EVIDENCE.md`, `TA_X3D1B_STAGING_EVIDENCE.md`, `TA_X3D1C_STAGING_EVIDENCE.md`, `TA_X3D1D_STAGING_EVIDENCE.md`, `TA_X3E_STAGING_EVIDENCE.md`, `TA_X3F_STAGING_EVIDENCE.md` |
| X4 | Lots; expected allocations; lot-backed reservations; atomic reserve/consume/release; source-neutral partial and invoice-only receipts; full reversal; inspection/quarantine disposition and correction; no-overcommit | `ta_x4a_*` through `ta_x4g_*`, including competing reserve, receipt, void, reversal and disposition races; A7; default privileges | Migrations `20260910191000` through `20260912000365`; evidence packets `TA_X4E_STAGING_EVIDENCE.md`, `TA_X4F_STAGING_EVIDENCE.md`, `TA_X4G_STAGING_EVIDENCE.md`; no fabricated PO; ledger-history boundary preserved |
| X5 | Typed intake batches/rows; resolver decisions; atomic reviewed commits; native movement linkage; immutable correction and supersession lineage; durable-source and explicit source-less corrected imports; catalog-variant observations; versioned 20-family event envelope; dormant integration outbox | `ta_x5a_*` through `ta_x5i_*`, sequential and concurrent; X8 regressions; A7; default privileges | Migrations `20260910210000` through `20260910233000`; every step locally replayed, CI/staging verified; X5 complete for the approved evidence-foundation slice |
| X6 | Provisional customer activity; reviewed identity and attribution; mixed-order drafts; distinct prepare/approve/post; posted line-level spend; refunds/cancellations/corrections; unknown-component finalization; source reconciliation; merge/unmerge and selective posted attribution; atomic native break sales; source-grained attendance evidence | `ta_x6a_*` through `ta_x6h_*`, including lock-order, idempotency, topology, attribution, session-end and source-dedup races; A7; default privileges | Migrations `20260910234500` through `20260911021500`; evidence includes `TA_X6D3_LOCK_ORDER_CORRECTIVE_EVIDENCE.md`, `TA_X6G_STAGING_EVIDENCE.md`, `TA_X6H_STAGING_EVIDENCE.md`; provisional evidence remains distinct from official spend |
| X7 | Coverage-aware attendance; official spend denominators; reviewed provider-time normalization; governed market facets; canonical eligible observations; bounded screener/drill-down; inventory lifecycle, exposure, grading, population and valuation provenance | `ta_x7a_*` through `ta_x7e_*`, including full-dataset, cursor, snapshot, cohort, normalization, dependency-fingerprint and temporal/concurrency suites; A7; default privileges | Migrations `20260911023000` through `20260911221930`; evidence packets `TA_X7A_STAGING_EVIDENCE.md`, `TA_X7B_STAGING_EVIDENCE.md`, `TA_X7C_STAGING_EVIDENCE.md`, `TA_X7D_ACCEPTANCE_EVIDENCE_2026-09-11.md`, `TA_X7E_STAGING_EVIDENCE.md`; X7d and X7e independently accepted |
| X8 | Explicit scoped query contexts and closed typed dispatcher; inert revisioned action proposals delegating to ordinary writers; dormant service-only bounded outbox claim/ack protocol | `ta_x8a_*`, `ta_x8b_*`, `ta_x8c_*`; underlying X3/X5/X6/X7 regressions; A7; default privileges | Migrations `20260912000380` through `20260912035932`; evidence packets `TA_X8A_STAGING_EVIDENCE.md`, `TA_X8B_STAGING_EVIDENCE.md`, `TA_X8C_STAGING_EVIDENCE.md`; X8c independently approved against evidence commit `f438f5e` |

## Acceptance-case coverage

Each implemented case has a positive fixture, a negative or ambiguity control,
and durable-state or rollback assertions in the named batch suites.

| Acceptance family | Covered cases | Evidence owner |
| --- | --- | --- |
| Identity | Identity across releases/copies; alias uncertainty; multiple subjects; rookie distinction; non-card core; player affiliation; language/edition; AI identity ambiguity | X1/X1b identity suites; X7d facet and catalog-entity suites; A7 |
| Market evidence and screening | Optional sales threshold and transaction filter; aggregate order; mixed evidence; syndicated duplicate; no-connector analytics; observation-kind separation; import replay/correction; feed independence; cross-catalog subject query; query grain/drill-down | X5d-X5i; X7c; X7d0-X7d3; X8a typed dispatcher |
| Inventory lifecycle and valuation | Exposure versus age; concurrent listings; unsold cohort; late correction; grading granularity; copy regrade; valuation coverage; portfolio attribution; population evidence | X5 correction lineage; X7e0-X7e2 and concurrency/temporal suites |
| Purchasing and receiving | Invoice-only intake; duplicate document; split matching; location restriction; historical cost; manual price; notes audience | X2; X3a-X3f; X4d-X4g and their exact-lock suites |
| Customer and transaction truth | Full-dataset grid; net spend; duplicate sources; identity correction; coverage/privacy; retail/break dimensions; native then imported; hold versus sale; refund/resale; buyer resolution; mixed/unclassified import; posting permission/retry; multi-product break | X6a-X6g; X7b; X8a; permission and hostile-tenant suites |
| Attendance | Attendance overlap; weekly attendance including zero week; spend denominators; partial coverage and source labels | X6h; X7a-X7c |
| Scoped integration | Workspace question; draft by chat; scope switch; multi-membership; immutable proposal provenance; authority revocation; outbox ownership/retry/expiry | X8a-X8c and their two-connection suites |
| Privacy | Cross-shop privacy; contact/financial permission filtering; tenant-scoped exports/cursors/caches; foreign identifiers | X6 bounded reads; X7 public readers; X8 query context; A7 `29/29` |

The wishlist-only case is deliberately independent of this backend expansion.
Monitor enable/pause/new-match behavior is deliberately excluded because the
authorized scope forbids scheduled monitors. Their absence is not represented
as implemented functionality.

## Universal engineering gates

| Requirement | Result |
| --- | --- |
| Additive migrations only | PASS. Applied September migrations remain separate files; no applied migration was rewritten for this audit. |
| Clean local replay | PASS in exact implementation CI run `34672627839`, including predecessor-schema compatibility. |
| Batch-specific tests | PASS. All registered X1-X8 SQL and two-connection gates passed at the implementation head. |
| RLS and tenant authority | PASS. New exposed-schema tables are RLS-enabled and client-closed or use object/org predicates. A7 passes `29/29`. |
| Privileged functions | PASS. Pinned search paths, explicit allowlisted grants, and the born-locked probe pass; zero anonymous or `PUBLIC`-executable functions. |
| Idempotency and concurrency | PASS for every mutator family through retry, changed-key, concurrent-call, post-lock authorization and residue assertions. |
| Bounded reads | PASS through explicit limits, stable scope-bound cursors, full-dataset filtering before pagination/aggregation, source/grain/unit/coverage metadata, and unavailable rather than fabricated values. |
| Explicit staging target | PASS. Remote writes used the staging session pooler for project `csmbjfmoxkexcyssntbg`; no bare production-linked push was used. |
| Staging cleanup | PASS. Batch evidence records rollback or cleanup, foreign-key/object census, and zero batch fixture residue. X8c ends with zero consumers, commands, acknowledgements and active claims. |
| Current CI | PASS. Run `34672627839` completed successfully at implementation head `87e3e675`. |
| Production untouched | PASS. Latest read-only proof reports no `e10` schema, 12 migrations through `20260716110000`, inventory `35/41/9`, and no X8c objects. |

## Explicit non-claims and retained decision boundaries

- No production migration, `main` merge, UI adoption, live feed, scheduler,
  monitor, chatbot, collector showcase, external dispatch, or provider credential
  is included.
- X8 action drafts support only the operation allowlist in the approved X8
  contract and execute only by calling ordinary authorized writers.
- X8c acknowledgement proves database protocol state, not external exactly-once
  delivery. No consumer is seeded.
- Provisional activity is not official spend. Posting does not assert payment,
  settlement, accounting recognition, or inventory return.
- Missing cost, precision, coverage, identity, allocation, and valuation remain
  explicit unknown/unavailable states, never silently zero or inferred.
- No cross-shop pooling, provider-licensing policy, automatic financial/price
  publication, capability-namespace replacement, over-receipt authority, or
  landed-cost allocation method was invented.
- The retained commercial and licensing decisions are future owner rulings, not
  defects in the approved foundation slice.

## Audit conclusion

The repository, CI, staging ledger, executable tests, evidence packets and
read-only production sentinels support completion of the approved TA-X1 through
TA-X8 backend foundation through staging. Final closure requires an independent
review of this matrix against the cited authorities. Any unsupported scoped
requirement found by that review remains a real implementation gap and must be
closed before the overall goal is marked complete.
