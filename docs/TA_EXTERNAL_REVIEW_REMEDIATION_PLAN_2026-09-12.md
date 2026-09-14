# Track A external-review remediation plan

Date: 2026-09-12

Status: PLAN ONLY, awaiting coordinator approval. The prior unconditional
acceptance is superseded by the external CONDITIONAL ACCEPT. No runtime,
migration, database, staging or production change is authorized by this plan.

Source reviewed:
`/Users/tsconnely/.codex/attachments/b60a21ff-4aac-4e97-8338-4e15ca7aeedf/pasted-text.txt`

The external `kit/` files were not attached. Reconstruct every reported failure
on the supported local Supabase/PostgreSQL stack before accepting a correction.

## Dependency-ordered remediation

### R0: Evidence and authority correction

- Preserve the external report as a project review artifact.
- Preserve the coordinator's withdrawn-acceptance disposition without erasing
  the chronological prior review.
- Commit the nine referenced scope/checklist sources with exact hashes and
  provenance, or remove unsupported citations.
- Correct every overstated acceptance-trace row.
- Add a trace mapping every finding below to migration, test and evidence.
- Record exact local, staging, CLI and PostgreSQL versions.
- Do not commit unrelated owner edits.

Stop for review after R0.

### R1: Inventory reversal and authorization safety

Correct together because the affected paths share receipt, lot, item and
location locks:

- IMPL-1: retire or redirect the unsafe single-line reversal.
- IMPL-13: give quarantine-only X4d receipts complete origin evidence.
- IMPL-2: post-lock organization, membership, capability and location rechecks
  for X4b/X4c/X4d.
- IMPL-9: require location authority for both reversal paths.
- Audit every still-granted legacy receipt/reservation RPC, including paths
  omitted from the handoff.

Preferred shape:

- `e10_org_reverse_receipt` becomes a compatibility wrapper over the
  disposition-aware batch reverser.
- The old `_x4d` reversal body becomes client-inaccessible.
- X4d emits receipt evidence for every physical receipt, including zero
  accepted quantity.
- Rechecks occur after the final blocking lock and immediately before mutation.

Proof: real PID-specific lock waits, mid-wait revocation/suspension, disposition
then reversal, quarantine-only reversal, cleanup and movement/lot/item
reconciliation.

### R2: Customer transaction truth and authorization

- IMPL-3: post-lock rechecks in every X6a-X6d mutator.
- IMPL-4: released native sales are not actionable provisional activity and
  cannot post.
- IMPL-6: a native sale and corresponding import cannot both become official
  spend.
- IMPL-14a: draft currency must equal each referenced activity currency.
- IMPL-14c: reject missing, non-finite and duplicate draft amounts before write.

Do not impose blanket uniqueness on `(session, slot)`. Valid release/resale
history can contain multiple sales. Posting a native line must require a current
sale under lock. Slot-bearing imports must reconcile with current native-sale
evidence. Released sales remain historical evidence but are ineligible to post.

### R3: Intake provenance and source deduplication

- IMPL-5: authenticated intake cannot assert `native` or `system` provenance.
- IMPL-11: use stable source-event identity in ordinary and corrected commits.
- Normalize durable connection/reference values before lineage lookup.
- Define connection-less/manual identical-fingerprint handling.
- Add the EVID-5 manual-correction versus reviewed-reimport race.
- Include corrected-key namespace hardening if additive and compatible.
- Prevent committed intake from returning to an editable lifecycle state.

Durable imports deduplicate by normalized connection plus stable source event.
Uncertain manual/connection-less matches become reviewed candidates unless an
owner-approved replay rule applies.

### R4: Visibility and suspended-organization enforcement

- IMPL-7: gate commercial comments by document authority and audience.
- IMPL-8: shared-catalog RLS tests for any active membership, not
  `current_org()`.
- IMPL-10: direct X2/X3/X7 APIs deny suspended organizations like X8.
- IMPL-14h: permission-filter invoice/credit metadata and receipt-line IDs.

Invoice/credit internal comments require actual financial-document authority.
Vendor comments use the vendor-safe projection. Multi-org members can read the
shared catalog without selecting an arbitrary first organization. Org overlays
remain tenant-scoped.

### R5: Immutable identity history and supported X1 creation

- IMPL-12: enforce immutable configuration-version content.
- Enforce append-only provider-mapping revisions.
- Permit only reviewed configuration state transitions and the old mapping's
  `is_current` retirement when its successor is appended.
- Block direct UPDATE/DELETE of historical meaning, including service-role
  accidents.
- Resolve SCOPE-1 with bounded, permission-scoped, idempotent creation/revision
  APIs for product master, configuration, configuration version, catalog
  release, variant/subjects, provider mapping and unique physical item.

This is integration readiness, not UI work.

### R6: Deterministic robustness contract

| ID | Required correction |
| --- | --- |
| 14a | Enforce activity/draft currency equality. |
| 14b | Preserve full-cohort totals on an empty trailing v1 page, or explicitly retire v1 traversal for v2. |
| 14c | Validate finite/required amounts and duplicate activities before draft creation. |
| 14d | Validate dispatcher UUID syntax and bounded integers before casts; return `22023`. |
| 14e-1 | Map duplicate active reservation to a stable domain error. |
| 14e-2 | Reject duplicate batch `lot_code` deterministically. |
| 14e-3 | Detect cross-receipt-writer idempotency-key reuse as `idempotency_key_mismatch`. |
| 14e-4 | Canonicalize numeric fingerprints so `5` and `5.0` replay identically. |
| 14f | Make v1 event timestamp fingerprints timezone-neutral, or retire authenticated v1 execution. |
| 14g | Remove cross-org existence oracles by scoping lookups before identity checks/inserts. |
| 14h | Permission-filter vendor document metadata and supplier-workspace receipt identifiers. |
| 14i | Validate F4/X1b UUIDs and subject types before casts/FKs. |
| 14j | Escape LIKE metacharacters unless wildcard search is explicitly requested. |
| 14k | Bind command replay to its actor, or explicitly approve/test shared capability-authorized replay. |

Also bind X7e limits into signed cursors and source total count from the ranked
cohort, with regression tests.

### R7: Scope dispositions

| Finding | Disposition |
| --- | --- |
| SCOPE-1 | Implement safe X1 writers in R5. Direct table writes are not an integration contract. |
| SCOPE-2 | Current purchasing cost visibility is organization-level. Location-scoped cost privacy needs an owner ruling. |
| SCOPE-3 | Current lifecycle separation is capability-only, not maker-checker. Distinct actors need an owner ruling. |
| SCOPE-4 | Reconcile legacy item consumption with lots, or retire incompatible mutators before lot reporting is authoritative. |
| SCOPE-5 | Add configuration-level quantity granularity; reject fractional `each`/card quantities without banning divisible units. |
| SCOPE-6 | Distinguish operator-asserted cost from approved invoice-backed actual cost and restrict imported evidence-quality claims. |
| SCOPE-7 | Remove legacy direct-SQL TRUNCATE and unnecessary mutation grants after a compatibility inventory. |
| SCOPE-8 | Produce a renamed-migration staging runbook and merge-review strategy without rewriting applied migrations or hiding ledger history. |

SCOPE-2 and SCOPE-3 require Trent. Serial/print-run uniqueness and treatment of
manual/connection-less identical fingerprints also require owner decisions.

### R8: Evidence closure

- Add post-lock revocation races for every corrected writer.
- Reconstruct all external counterexamples on the supported local stack.
- Correct every EVID-3 trace row with real assertions and correct citations.
- Commit sanitized reproducible manifest/evidence outputs and commands.
- Add exact assertions for both EVID-5 notes.
- Add missing `act.view_market_analytics` and conditional
  `financial.actual_cost.read` handoff mappings.
- Run clean local replay, targeted suites, hostile tenant tests, default
  privileges, exact-head CI and explicit staging application.
- Produce one consolidated packet per milestone. Production remains read-only.

## Complete finding matrix

### Implementation findings

| Finding | Severity | Milestone | Disposition |
| --- | --- | --- | --- |
| IMPL-1 | High | R1 | Disposition-aware single-line reversal compatibility. |
| IMPL-2 | High | R1 | Post-lock X4/legacy authorization rereads. |
| IMPL-3 | High | R2 | Post-lock X6a-X6d authorization rereads. |
| IMPL-4 | High | R2 | Released native sale cannot post or count as actionable provisional activity. |
| IMPL-5 | Medium | R3 | Client intake cannot claim native/system provenance. |
| IMPL-6 | Medium | R2 | Native/import reconciliation prevents double posting without blocking resale. |
| IMPL-7 | Medium | R4 | Document- and audience-specific comment authority. |
| IMPL-8 | Medium | R4 | Dual-membership shared-catalog visibility. |
| IMPL-9 | Medium | R1 | Location authority for reversal after locks. |
| IMPL-10 | Medium | R4 | Suspended-organization denial across direct APIs. |
| IMPL-11 | Medium | R3 | Stable source identity and normalized lineage. |
| IMPL-12 | Medium | R5 | Database-enforced immutable version/mapping history. |
| IMPL-13 | Medium | R1 | Receipt-origin evidence for quarantine-only X4d receipt. |
| IMPL-14a-k | Low, except 14a financial correctness | R2/R4/R6 | Close every enumerated validation, privacy, idempotency and error-contract item. |

### Evidence findings

| Finding | Milestone | Disposition |
| --- | --- | --- |
| EVID-1 | R0 | Commit exact sources with provenance or remove citations. |
| EVID-2 | R1/R2 | Add missing two-connection authority-revocation tests. |
| EVID-3 | R8 | Replace labels with executable assertions and correct paths. |
| EVID-4 | R8 | Commit sanitized reproducible evidence; avoid environment-dependent whole-file claims. |
| EVID-5 | R3/R8 | Add correction/reimport race and reporting capability documentation. |

### Optional findings

| Finding | Disposition |
| --- | --- |
| Namespace derived corrected-import keys | Include in R3 if compatible. |
| Block committed intake returning to editable | Include in R3. |
| Bind X7e limit into cursor | Include in R6. |
| Correct X7e total-count source | Include in R6. |
| Prevent copy-level keys in variant attributes | Include in R5; serial rules need owner approval. |
| Escape customer-search LIKE metacharacters | Required by IMPL-14j. |

## Review sequence

1. R0 evidence/source reconciliation.
2. R1 inventory/reversal safety.
3. R2 customer transaction correctness.
4. R3 intake provenance/deduplication.
5. R4 visibility and organization status.
6. R5 immutable history and X1 supported writers.
7. R6 deterministic robustness.
8. R7 scope dispositions.
9. R8 consolidated final evidence.
10. Independent unconditional-accept review.
11. Multilingual backend design review.
12. Multilingual implementation only after design approval.

## Multilingual boundary

After remediation is empirically accepted, design a separate backend slice for:

- per-user language/locale preference and organization default;
- deterministic fallback and validated BCP 47-style tags;
- translated catalog names/aliases keyed to canonical IDs;
- separation from card edition language;
- preservation of original text and source language;
- locale-neutral dates, numbers and currencies;
- stable API message/error keys with parameters;
- versioned translation-resource integration contract;
- RTL and text-expansion requirements for Track B;
- tenant, permission, idempotency, fallback and Unicode tests.

Not authorized: screen translation/redesign, automatic machine translation,
choice of launch languages, chatbot, feeds, trackers or showcase work.

No implementation begins until this remediation plan is reviewed and approved.
