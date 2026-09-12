# TA-X1 through TA-X8 acceptance trace

Date: 2026-09-12

Status values:

- `implemented`: backend behavior exists and has executable evidence.
- `Track B`: backend contract exists; named presentation or fixture wording is a
  client/demo responsibility and is not claimed here.
- `excluded`: deliberately outside the authorized Track A expansion.
- `reopened/unproven`: an external review found that the cited assertion does
  not prove the claimed behavior. The row stays open until a focused executable
  regression exists and passes.

Every row below corresponds to one named case or checklist invariant. A file
and assertion label identify the executable proof. Evidence packet references
are collected in `TA_X1_X8_FINAL_ACCEPTANCE_MATRIX.md`.

## Expanded acceptance cases

| Named case | Status | Exact executable evidence and assertion |
| --- | --- | --- |
| Identity across releases | implemented | `tests/ta_x1_identity_foundation_test.sql`, release/variant identity fixture and `language_edition_identity`; `tests/ta_x7d2_catalog_entity_projection_test.sql`, catalog entity identity projection |
| Identity across copies | reopened/unproven | Existing citations do not assert two `e10_unique_items` for one variant remain distinct. Requires a focused executable assertion. |
| Alias uncertainty | implemented | `tests/ta_x7d0_facet_governance_test.sql`, reviewed assert/revoke chains; `tests/ta_x7d2_screener_cohorts_test.sql`, exact governed facet filtering |
| Multiple subjects | implemented | `tests/ta_x1_identity_foundation_test.sql`, `multi_subject`; `tests/ta_x7d2_catalog_entity_projection_test.sql`, dual-subject projection |
| Rookie distinction | implemented | `tests/ta_x7d0_facet_governance_test.sql`, separate designation and subject-season decisions; `tests/ta_x7d2_screener_cohorts_test.sql`, per-subject rookie filter |
| Optional sales threshold | implemented | `tests/ta_x7d2_screener_cohorts_test.sql`, optional cohort bounds and unavailable observations |
| Correct aggregate order | implemented | `tests/ta_x7d2_screener_cohorts_test.sql`, aggregate-then-filter cohort assertions |
| Optional transaction filter | implemented | `tests/ta_x7d2_screener_cohorts_test.sql`, typed transaction cohort filter and metric metadata |
| Mixed evidence | reopened/unproven | The cited market-evidence test has no `estimated_value` fixture. Requires explicit ask, sale and estimate separation evidence. |
| Syndicated duplicate | implemented | `tests/ta_x7d1_canonical_projection_test.sql`, one canonical observation with three provenance IDs |
| Exposure vs age | implemented | `tests/ta_x7e1_inventory_lifecycle_test.sql`, exact 8-day/2-day/6-day/4-day arithmetic |
| Concurrent listings | implemented | `tests/ta_x7e1_inventory_lifecycle_test.sql`, unioned intervals; `tests/ta_x7e_concurrent_test.js`, concurrent evidence serialization |
| Unsold cohort | implemented | `tests/ta_x7e1_inventory_lifecycle_test.sql`, censored unsold and precision-unavailable assertions |
| Late correction | implemented | `tests/ta_x5e_observation_corrections_test.sql`, immutable supersession; `tests/ta_x7e_temporal_regression_test.sql`, revision invalidation and cutoff behavior |
| Invoice-only intake | implemented | `tests/ta_x4e_receipt_batch_test.sql`, `invoice-only receipt fabricated PO allocation` negative and 12/10/discrepancy-2 positive |
| Duplicate document | implemented | `tests/ta_x3d1a_financial_document_create_test.sql`, exact replay and changed fingerprint reconciliation; concurrent companion test |
| Split matching | implemented | `tests/ta_x3d1d_financial_allocations_test.sql`, allocation conservation; `tests/ta_x3d1d_allocation_workflow_races_test.js`, allocation races |
| Location restriction | implemented | `tests/ta_x2_location_supplier_test.sql`, eligible destination and cross-location denial; X3c/X4e post-lock location checks |
| Historical cost | implemented | `tests/ta_x4e_receipt_batch_test.sql`, accepted receipt cost; `tests/ta_x3f_supplier_workspace_test.sql`, exact supplier/configuration/currency cost history |
| Manual price | implemented | `tests/ta_x3d1b_financial_document_amend_test.sql`, explicit amendment revision/CAS and preserved supplied values; no suggestion writer exists |
| Notes audience | implemented | `tests/ta_x3e_commercial_comments_test.sql`, vendor projection excludes internal audience and cross-audience lineage |
| Wishlist only | excluded | Wishlist is explicitly independent in `EXPANSION_FRAMEWORK.md` section 7 and the Track A plan. No wishlist save, reservation, PO, job, or notification is created by X1-X8. |
| Pause monitor | excluded | Scheduled monitoring is explicitly forbidden by the authorized objective. No monitor relation, job, or cancellation policy is claimed. |
| New-match tracking | excluded | Scheduled trackers and notifications are explicitly forbidden. No baseline scan or alert engine is claimed. |
| Auction truth | reopened/unproven | The cited evidence does not assert ask/estimate/sale separation. Requires a focused truth-transition regression. |
| Workspace question | implemented | `tests/ta_x8a_typed_dispatcher_test.sql`, `x8_business_state` unchanged around inventory queries and explicit unknown metadata |
| Draft by chat | Track B | Backend implemented in `tests/ta_x8b_action_draft_test.sql`: unresolved required values, provenance, revisions, and no business effect. Conversation/UI behavior is not claimed. |
| Scope switch | reopened/unproven | The cited permission-matrix fixture is single-org. Cross-org draft denial exists elsewhere but this claim and citation require reconciliation. |
| Multi-membership | implemented | `tests/ta_x8a_query_context_test.sql`, explicit selected org for a dual member and no first-membership fallback; X3d staging cases repeat explicit-org operation |
| Cross-shop privacy | implemented | `tests/a7_hostile_matrix_test.sql`, 29/29 cross-org family matrix; X7/X8 scopes remain organization-bound |
| Non-card core | implemented | `tests/ta_x4h_noncard_core_test.sql`, Cards-disabled apparel receipt/cost/generic reservation and one unique used camera receipt/cost/reserve/consume with no catalog variant or break session; concurrent companion proves no overcommit |
| Player affiliation | implemented | `tests/ta_x1b_player_affiliations_test.sql`, dated affiliation and preserved depicted-team context; concurrent correction/revocation companion |
| AI identity ambiguity | implemented | `tests/ta_f4_identity_ambiguity_review_test.sql`, two distinct same-name players, explicit known/unknown confidence, bounded review and rejection preservation; `tests/ta_f4_identity_ambiguity_review_guards_test.sql` and concurrent companion, hostile access, validation, append-only, idempotency, source uniqueness, CAS and post-lock authority. No approval, canonical link, merge, split or automatic candidate generation is supported. |
| Full-dataset grid | implemented | `tests/ta_x7f_customer_spend_grid_test.js`, aggregate spend bounds and stable sorts apply across the full authorized customer cohort before bounded pagination, with matching full-cohort totals and cursor traversal; 100,000-line and 2,000-transaction resource fixtures are covered by the same suite |
| Customer net spend | implemented | `tests/ta_x7b_spend_reporting_test.js`, separate merchandise/refund/shipping/tax components and visible metric definition |
| Customer duplicate sources | implemented | `tests/ta_x6d_customer_transaction_adjustments_test.js`, durable source components and one contribution after source reconciliation; the registered CI step named `TA-X6d.3 reviewed adjustment, unknown-component finalization and source-reconciliation gate` runs that executable suite |
| Customer identity correction | implemented | `tests/ta_x6e_customer_resolution_test.js` and `ta_x6f_posted_customer_attribution_test.js`, immutable merge/split/reattribution without source rewrite |
| Customer coverage/privacy | implemented | `tests/ta_x7b_spend_reporting_test.js`, coverage and financial access; `tests/ta_x8b_customer_preview_permissions_test.sql`, financial/contact redaction |
| Retail/break dimensions | implemented | `tests/ta_x6c_customer_transaction_posting_test.sql`, typed mixed lines; `tests/ta_x7b_spend_reporting_test.js`, official versus provisional and combined dimensions |
| Native then imported | implemented | `tests/ta_x6d_customer_transaction_adjustments_test.js`, source reconciliation and contribution uniqueness; `tests/ta_x6g_native_break_sale_test.js`, provisional native sale identity |
| Hold vs sale | reopened/unproven | The cited X6g test does not read provisional activity or attempt to post a released sale. IMPL-4 remains open. |
| Refund/resale | reopened/unproven | The cited X6g test does not prove a released sale is excluded from actionable provisional activity. IMPL-4 remains open. |
| Buyer resolution | implemented | `tests/ta_x6g_native_break_sale_adversarial_test.js`, unresolved buyer retained and reviewed identity checks without duplicate sale |
| Mixed/unclassified import | reopened/unproven | `unclassified` does not appear in the cited test and there is no channel-guessing negative. |
| Posting permission/retry | implemented | `tests/ta_x6c_customer_transaction_posting_test.sql` and concurrent companion, distinct prepare/approve/post capabilities and one posting effect |
| Attendance overlap | implemented | `tests/ta_x7a_attendance_reporting_test.js`, interval union and expiry-bounded companion presence |
| Weekly attendance | implemented | `tests/ta_x7a_attendance_reporting_test.js`, zero-week denominator and distinct-session counting with coverage |
| Spend denominators | implemented | `tests/ta_x7b_spend_reporting_test.js`, attended-break versus purchasing-break denominators and provisional exclusion |
| Multi-product break | implemented | `tests/ta_x6c_customer_transaction_posting_test.sql`, explicit line allocation/grain; `tests/ta_x7b_spend_reporting_test.js`, no full-value fanout |
| No-connector analytics | implemented | `tests/ta_x7d2_public_screener_test.sql`, local/manual evidence query; `tests/ta_x7e2_inventory_valuation_test.sql`, local-index method without connector |
| Observation kind separation | reopened/unproven | The cited tests do not assert inventory and customer state remain unchanged. |
| Import replay/correction | implemented | `tests/ta_x5f_atomic_correction_import_test.sql`, exact replay and atomic correction; X5f/X5g concurrency companions |
| Valuation coverage | implemented | `tests/ta_x7e2_inventory_valuation_test.sql`, valued/unvalued counts, freshness, method/version/currency, unknown cost and population date |
| Feed independence | implemented | `tests/ta_x7e2_inventory_valuation_test.sql`, manual local evidence; no connector entitlement prerequisite |
| Grading granularity | reopened/unproven | The cited test proves grade applicability only, not qualifier applicability or unknown-bucket preservation. |
| Copy regrade | implemented | `tests/ta_x7e2_inventory_valuation_test.sql`, PSA 9 then PSA 10 evidence on one unique item and mismatch labeling |
| Language/edition | implemented | `tests/ta_x1_identity_foundation_test.sql`, `language_edition_identity` creates two releases/variants for identical display strings but distinct language/edition |
| Portfolio attribution | implemented | `tests/ta_x7e2_inventory_valuation_test.sql`, separate market movement, acquisition count/value, disposal count/value, and comparability |
| Index/population evidence | implemented | `tests/ta_x7e2_inventory_valuation_test.sql`, index method/version and dated scoped population snapshot; no sale fabrication |
| Cross-catalog Yamal query | Track B | Backend query behavior is implemented by `tests/ta_x7d2_cross_product_rookie_psa9_test.sql`: one public query combines subject, per-subject rookie designation, graded condition, PSA and grade 9 across two releases, with limit-one continuation and unknown-rookie/grade-8 exclusions. The wrong-subject negative queries a subject with no variants; it is not a separate wrong-subject variant fixture. The named Yamal dataset and UI remain Track B. |
| Query grain and drill-down | reopened/unproven | The cited public-screener test exercises only catalog scope. Owned and observation grain evidence is in a different suite and must be reconciled. |

## Purchasing invariants PUR-01 through PUR-07

| Invariant | Status | Exact evidence |
| --- | --- | --- |
| PUR-01 authorized destination | implemented | `ta_x2_location_supplier_test.sql` eligible/sole destination; `ta_x3c_purchase_order_lifecycle_test.sql` and concurrency companion recheck location/authority after locks |
| PUR-02 actual cost suggestion | reopened/unproven | The unreceived-estimate assertion is not in the cited X4e test. Historical-cost evidence and citations require correction. |
| PUR-03 comment audiences | implemented | `ta_x3e_commercial_comments_test.sql`, append-only audience history and vendor allowlist projection; concurrent cross-audience denial |
| PUR-04 distinct PO/invoice/receipt | implemented | `ta_x3a_purchasing_documents_test.sql`; `ta_x3d1d_financial_allocations_test.sql`; `ta_x4e_receipt_batch_test.sql` invoice-only no-PO fixture |
| PUR-05 physical acceptance | reopened/unproven | The cited test and current schema do not contain the claimed shortage or partial-quantity concepts. |
| PUR-06 vendor workspace | implemented | `ta_x3f_supplier_workspace_test.sql`, bounded open/past documents, net credits and distinct commitment/invoice/payment states |
| PUR-07 product/offering identity | implemented | `ta_x1_identity_foundation_test.sql`; `ta_x2_location_supplier_test.sql`; supplier workspace and actual-cost exact configuration history |

## X7e checklist invariants

| Invariant | Exact executable evidence |
| --- | --- |
| Lifecycle arithmetic | `ta_x7e1_inventory_lifecycle_test.sql`, exact Jan 1/3/4/6/9 arithmetic |
| Exposure grain | `ta_x7e1_inventory_lifecycle_test.sql`, unioned channel intervals per unique item |
| Unsold and unknown | `ta_x7e1_inventory_lifecycle_test.sql`, censored and `precision_unavailable` branches |
| Eligible history | `ta_x7e_temporal_regression_test.sql`, occurrence/recorded cutoffs and supersession |
| Grading | `ta_x7e0_inventory_evidence_test.sql`, append-only assess/regrade chain |
| Population | `ta_x7e2_inventory_valuation_test.sql`, dated scoped population evidence |
| Value evidence | reopened/unproven: the cited test contains completed-sale observations and asserts only the `grade` kind; explicit cost/ask/sale/estimate evidence is required. |
| Valuation contract | `ta_x7e2_inventory_valuation_test.sql`, method/version/currency/cutoff/freshness/coverage |
| Portfolio movement | `ta_x7e2_inventory_valuation_test.sql`, market/acquisition/disposal decomposition |
| Feed independence | `ta_x7e2_inventory_valuation_test.sql`, local manual evidence |
| Access and bounds | `ta_x7e2_inventory_valuation_test.sql`, 205-row total and cursor; `ta_x7e_concurrent_test.js`, revocation/mutation races |
| Release gate | `TA_X7E_STAGING_EVIDENCE.md`, clean replay, CI, staging, advisors, cleanup and independent acceptance |

## X8 checklist invariants

| Invariant | Exact executable evidence |
| --- | --- |
| Closed typed query allowlist | `ta_x8a_typed_dispatcher_test.sql`, `arbitrary.sql` and unknown arguments rejected |
| Explicit dual-membership scope | `ta_x8a_query_context_test.sql`, selected organization; `ta_x8a_context_concurrent_test.js`, org switch/revocation |
| Bounded sourced envelopes | `ta_x8a_typed_dispatcher_test.sql` plus X7 operation regressions, grain/units/source/coverage/unknown fields |
| Returned-data permission | `ta_x8a_typed_dispatcher_test.sql`, private inventory fields excluded; `ta_x8b_customer_preview_permissions_test.sql`, financial/contact redaction |
| Read-only semantics | `ta_x8_business_state_helper.sql` assertions around every typed operation |
| Typed inert drafts | `ta_x8b_action_draft_test.sql`, values/provenance/missing/source/revision and zero business effect |
| Exact revision approval | `ta_x8b_action_draft_test.sql`, stale preview/approval and changed payload denial |
| Ordinary writer delegation | reopened/unproven: the cited test has no unsupported-operation negative. |
| Post-lock authority/reference recheck | `ta_x8b_concurrent_test.js`, exact backend waits for capability, membership and mutable references |
| Idempotency and immutable history | `ta_x8b_action_draft_test.sql` and concurrent exact commit, one effect plus one replay |
| Untrusted suggestion isolation | `ta_x8b_action_draft_test.sql`, instruction-shaped unstructured values remain inert data |
| Scope switch and retention | reopened/unproven: the cited fixture is single-org; a focused foreign-context retention assertion is required. |
| External dispatch disabled | reopened/unproven: zero seeded consumers is asserted, but absence of a dispatch function or job is not. |
| Bounded ownership and expiry | `ta_x8c_outbox_claim_ack_test.sql`, limit/lease bounds; concurrent one-owner/disjoint-batch proof |
| Crash/retry and stale owner | `ta_x8c_outbox_concurrent_test.js`, lease expiry/reclaim/new generation/stale token refusal |
| Database versus provider guarantee | `TA_X8C_OUTBOX_CONTRACT.md` and acknowledgement table comment; no provider-delivery assertion |
| X8 evidence/release gate | `TA_X8A_STAGING_EVIDENCE.md`, `TA_X8B_STAGING_EVIDENCE.md`, `TA_X8C_STAGING_EVIDENCE.md`, exact CI and cleanup |

## Remaining classifications

No in-scope backend case is currently classified as untested. Wishlist storage
is independent and monitoring cases are excluded by the owner-authorized scope.
Track B rows identify only client/demo consumption, not missing backend authority
or persistence. Any reviewer contradiction to a cited assertion reopens that row
as an implementation gap.
