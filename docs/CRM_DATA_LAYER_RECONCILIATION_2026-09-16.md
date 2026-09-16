# CRM data-layer reconciliation

Date: 2026-09-16

Status: investigation and documentation only. This document does not authorize
migrations, deployment, integration activation, customer communication, or
production access. It does not self-accept CRM-01 through CRM-05 or CRM-A01
through CRM-A10.

## 1. Scope and evidence boundary

This review reconciles `CRM_REQUIREMENTS_2026-09-16.md` with the canonical
`foundation-a6` checkout at source head
`af62de737e4d11af9ca335410df8920aa90d2e87`, plus the current status, `BOARD.md`,
`EXPANSION_FRAMEWORK.md` section 11, and `ROADMAP.md` phase 9.

Evidence levels are deliberately separate:

| Evidence level | What was verified |
| --- | --- |
| Current local source | Migrations, functions, indexes, tests, and active documentation in the canonical checkout were inspected directly at the head above. No local database was changed or replayed in this pass. |
| Hosted staging | No hosted call was made in this pass. The latest committed packet, `TA_R2_R8_STAGING_EVIDENCE.md`, records explicit project `csmbjfmoxkexcyssntbg`, runtime/test head `481ea1ab452a1e196d59b19526ea4ecfdc19309f`, 147/147 September migration-name parity, focused staging suites, and zero new advisor errors. That is historical evidence, not verification of the current documentation head. |
| Production | Not contacted. The latest packet only preserves an older read-only sentinel showing no `e10` schema and 12 migrations through `20260716110000`. Nothing in this review is claimed deployed to production. |
| External source feasibility | No customer-supplied Whatnot export was present in the canonical checkout. Official Whatnot Help Center documentation was reviewed for documented export surfaces and fields. Actual account access, sample headers, retention, cadence, and permitted automation remain unverified. |

The repository remains dirty with pre-existing work. This review adds only this
document and a current-status pointer. It does not edit any applied migration.

## 2. Current data-layer facts

The current implementation is not an empty CRM placeholder. It has a coherent
customer and transaction foundation:

1. `e10_customers` is an organization-owned stable relationship, distinct from
   optional `auth_user_id`. `e10_customer_identity_decisions` stores immutable
   reviewed channel-account and alias attach/detach history. The current
   identity projection does not make ordinary aliases globally unique and does
   not infer matches from names or addresses.
2. `e10_customer_activity_observations` stores provisional manual, imported, or
   native activity with source identity, raw evidence, buyer handle snapshot,
   purchase kind, session/slot, components, currency, and an explicit identity
   status. It is never official spend, payment, or settlement.
3. Reviewed drafts become immutable `e10_customer_transactions` and
   `e10_customer_transaction_lines`. Lines independently retain purchase kind,
   channel, location, capture source, source IDs, optional product,
   configuration, owned-copy, session, slot, quantity, and monetary components.
4. Refunds, cancellations, corrections, and previously unknown component
   finalizations are additive facts. Source-reconciliation claims attach later
   evidence to an existing commercial line instead of silently creating a
   duplicate.
5. Customer merge/split and both provisional and posted reattribution are
   immutable reviewed decisions. They change association, not the source sale,
   revenue, or inventory fact.
6. `e10_native_break_sales` gives every sale attempt a distinct identity while
   retaining `(organization_id, slot_id, sale_sequence)`. Release and resale do
   not overwrite the original sale. Native capture remains provisional.
7. Spend readers derive official values from eligible posted lines and additive
   changes, with currency, time window, as-of cutoff, source coverage,
   authorization scope, dataset revision, query fingerprint, full-cohort totals,
   and line-level lineage. Provisional activity has a separate reader.

These facts are substantial but do not implement contact management,
fulfillment, acquisition/consignment relationships, settlement, preferences,
or marketplace ingestion merely because generic commercial events can name
those concepts.

## 3. Requirement coverage matrix

Classification meanings:

- **Supported**: the current source has the required persisted contract,
  authorized action/query, and focused executable proof.
- **Partial**: a material subset exists, but the requirement cannot be accepted
  end to end.
- **Missing**: no adequate current persisted contract/action/query exists.
- **Conflicting**: current behavior or authority is incompatible with the
  requirement.
- **Source-dependent**: completion depends on an external source whose access or
  field coverage is not yet verified.

| ID | Status | Exact current evidence | Readiness gaps |
| --- | --- | --- | --- |
| CRM-01 Customer identity and two-way history | **Partial** | `20260910234500...x6a...` creates `e10_customers` and provisional activity; `20260911000000...x6b...` adds reviewed channel/alias and activity-attribution decisions; `20260911001500...x6c...` adds posted transactions/lines; `20260911003000...x6d...`, `...004500...x6d2...`, and `...010000...x6d3...` add adjustments, finalization, and reconciliation; `20260911011500...x6e...` and `...013000...x6f...` preserve merge/split and posted attribution history. Tests: `ta_x6a_customer_activity_foundation_test.sql`, `ta_x6b_customer_identity_attribution_test.sql`, `ta_x6c_customer_transaction_posting_test.sql`, `ta_x6d_customer_transaction_adjustments_test.js`, `ta_x6e_customer_resolution_test.js`, `ta_x6f_posted_customer_attribution_test.js`. | No customer link from purchasing/acquisition records, no buy-ticket/customer-as-seller contract, no consignment agreement or payout model, and no payment, credit, shipment, or fulfillment relationship. Supplier identity must remain distinct. A generic `e10_commercial_events.event_type` is evidence, not an implemented lifecycle. |
| CRM-02 Buyer profile, preferences, discovery | **Partial** | `e10_org_customer_spend_contributions`, `...spend_lineage`, `...spend_summary`, `...customer_provisional_activity`, and `e10_org_customer_spend_grid_v2` implement bounded official/provisional separation, adjustment lineage, separate currency, retail/break/unclassified filters, dates, channels, locations, product/configuration/copy/session filters, and full-cohort totals. Tests: `ta_x7b_spend_control_test.js`, `ta_x7b_spend_lifecycle_test.js`, `ta_x7b_spend_reporting_test.js`, `ta_x7f_customer_spend_grid_test.js`, `ta_x7f_concurrent_auth_test.js`. | No declared favorite/preference records, provenance, removals, or unresolved private labels. No observed affinity snapshot with timeframe/basis/sample/coverage. No safe subject/team/product allocation rule. Current grid lacks full CRM sorting/filtering, saved views, authorized export, order-frequency/recency fields as a stable public contract, and explicit acquisition/consignment summaries. Payment/settlement are intentionally absent. |
| CRM-03 Contact and shipping | **Missing**, with identity handles partial | Channel handles and alias history exist in `e10_customer_identity_decisions`; verified login linkage remains optional. `act.manage_customers` controls current customer mutations, and financial reporting has distinct org/location capabilities. | No normalized email/phone/contact points, addresses, defaults, delivery instructions, consent, communication preference, private notes, order-address snapshots, shipment-address snapshots, open-shipment redirect action, retention/redaction state, or customer export/AI permissions. Using `act.manage_customers` for all private profile fields would be overbroad. Shared addresses cannot yet be represented safely as non-identity facts. |
| CRM-04 Live breaks and Whatnot | **Partial** and **source-dependent** | `20260911014500...x6g...` implements native sale/release/replay and buyer resolution. Transaction lines can link customer, session, slot, product, configuration, and owned copy. `e10_customer_transaction_reconciliation_cases`, decisions, evidence links, and source claims support reviewed source attachment. Tests: `ta_x6g_native_break_sale_test.js`, `ta_x6g_native_break_sale_adversarial_test.js`, X6c/X6d reconciliation tests, and R2 final-lock tests. | No implemented Whatnot raw-file adapter or validated headers in the repository; no marketplace order/line/shipment tables; no customer-to-allocated-card or fulfillment link; no consolidated/partial shipment state; no payment/settlement import. The native path has no automatic entitlement to posting. Live viewer/chat/bid/watch-time API access is not verified and must not be assumed. |
| CRM-05 Modular adoption | **Partial** | Customer, identity, transaction, and spend tables are organization-owned and do not require a Cards identity on every line. Product/configuration/copy/session/slot links are nullable. This supports a core customer record plus optional enrichment. | No approved customer module entitlement or disable-state machine, no proof that disabling Live/Cards preserves all core readers, no active-commitment policy, and no package decision. Capability `owning_module='customers'` metadata is not itself entitlement enforcement. |

## 4. Acceptance-scenario matrix

| ID | Status | Evidence and exact limitation |
| --- | --- | --- |
| CRM-A01 One buyer, seller, consignor | **Missing** | Retail and break lines can share one `e10_customers.id`, but acquisitions, buy tickets, consignment agreements, and customer payouts do not link to that relationship. Spend readers only consume customer sale lines and adjustments, so they do not currently miscount nonexistent payout facts, but the complete two-way history cannot be represented. |
| CRM-A02 Provisional, manual, import, replay | **Partial** | X6a records provisional activity idempotently; X6c posts reviewed lines; X6d.3 reconciles source evidence with durable claims; tests reject duplicate activity and mismatched idempotency. There is no validated Whatnot adapter or sample export contract, so the real import half is unproven. |
| CRM-A03 Partial refund, cancellation, slot resale | **Partial**, strong current core | X6d adjustments are additive and bounded; X6g release preserves sale identity and allows a later sequence. Focused tests cover refunds/cancellations/release/resale and no-write race losers. There is no corresponding shipment, payment, settlement, or returned-inventory fact, and the adjustment API explicitly does not imply them. |
| CRM-A04 Handle changes, same names, shared address, anonymous sale | **Partial** | X6b preserves attach/detach history, permits ambiguous ordinary aliases, rejects verified-handle theft, supports unresolved activity, and does not rewrite source facts. Names and addresses are not auto-match inputs. Address representation and reviewed address-neutral candidate workflows are still missing. |
| CRM-A05 Favorites, random teams, multi-subject card | **Missing** | Canonical variant-subject and player/team context contracts can be reused, including zero-to-many subjects, but no customer favorite or affinity contract exists. Nothing currently separates declared favorites from random assignment, received hit, or observed purchase evidence. No monetary allocation prevents multi-subject multiplication. |
| CRM-A06 Address change, consolidated/partial shipment | **Missing** | No customer address, immutable order/shipment address snapshot, shipment, shipment-line, consolidation, partial-fulfillment, or audited redirect writer exists. Legacy slot shipping fields are not an authoritative CRM fulfillment model. |
| CRM-A07 Missing source fields and incomplete history | **Partial** and **source-dependent** | Activity/transaction source kind, raw evidence, occurrence precision, unknown components, reconciliation state, and spend coverage diagnostics exist. Manual and generic import capture can retain unknowns. A Whatnot-specific schema/profile, validated-file path, retention statement, and explicit unsupported-field manifest are missing. |
| CRM-A08 Two tenants, differentiated employee/export/AI access | **Partial**, with permission gap | All customer records and actions are organization-scoped; cross-org and revoked-capability tests exist. Financial reads distinguish org-wide from location scope. Contact/export/AI data classes do not exist, so independent field projections and capabilities cannot yet be proved. No cross-shop global customer profile is exposed, which is correct. |
| CRM-A09 Mixed currency and monetary components | **Partial** | Posted lines enforce header currency coherence, retain gross/discount/shipping/tax separately, allow unknown components, and use additive refund/correction/finalization. Spend readers require one currency and do not silently combine currencies. Credit issuance/redemption, payment methods, outstanding balances, mixed-product allocations, and formal historical coverage declarations are missing. |
| CRM-A10 Reattribution/merge, then disable modules | **Partial** | X6e/X6f preserve immutable association history and spend projection can resolve current effective customer without rewriting money. Cards/Live links are nullable. No module-disable action or regression proves history remains available while active commitments are resolved. |

## 5. Schema, action, query, index, and test evidence

### 5.1 Identity and attribution

| Contract | Current reference | Commit introducing current foundation |
| --- | --- | --- |
| Organization customer relationship | `public.e10_customers`; org/name index; later org/auth-user partial unique index | `c6d0ed9`, later `10307d2` |
| Channel account and alias history | `public.e10_customer_identity_decisions`, `public.e10_current_customer_identities`, identity-stream index; `e10_org_decide_customer_identity` | `abeff93` |
| Provisional attribution correction | `e10_customer_activity_attribution_decisions`, current projection, `e10_org_attribute_customer_activity` | `abeff93` |
| Merge/split | `e10_customer_resolution_decisions`, effective-identity projections, `e10_org_resolve_customers` | `10307d2` |
| Posted attribution correction | `e10_customer_transaction_attribution_decisions`, current projection, `e10_org_resolve_customer_transaction` | `953338b` |

Important correction: `e10_customers.auth_user_id` is an optional verified
account link, not the customer key. Channel handles belong to an organization
customer identity stream and remain usable for customers without Element 10
accounts.

### 5.2 Commercial facts and spend

| Contract | Current reference | Commit |
| --- | --- | --- |
| Provisional evidence | `e10_customer_activity_observations`; customer/time and session/slot indexes; `e10_org_record_customer_activity` | `c6d0ed9` |
| Reviewed posting | transaction drafts/revisions/lines, `e10_customer_transactions`, `e10_customer_transaction_lines`; customer/time index; prepare/approve/reopen/post actions | `f38fe05` |
| Additive changes | `e10_customer_transaction_adjustments`, component finalizations, reconciliation cases/decisions/evidence/source claims | `a855983` and later additive X6d migrations |
| Native live sale | `e10_native_break_sales`, receipts/transitions, current-sale projection, buyer resolver, commit/release actions; customer/time index | `5938cef` |
| Official reporting | spend contribution, lineage, summary, provisional readers | `cebb6e3` |
| Full customer grid | `e10_org_customer_spend_grid_v2`, helper contribution grain, stable cursor, revision and query fingerprint | `9e35153` plus later X7f/R6 additive corrections |

Official buyer spend currently has the correct high-level exclusion boundary:
only eligible posted customer transaction lines plus authorized adjustments and
finalizations contribute. Provisional activity does not. Purchasing documents,
supplier invoices, inventory receipts, and generic events do not. Once customer
acquisitions and consignor payouts exist, the spend helper must continue to
select sale-to-customer direction explicitly rather than summing all customer
events.

### 5.3 Authorization

The capability registry includes `act.manage_customers`,
`act.merge_customers`, `act.correct_customer_attribution`, customer transaction
prepare/approve/post/adjust/reconcile capabilities,
`act.record_commercial_events`, `act.view_customer_engagement`, and
`act.view_customer_financials`. R2 tests exercise post-lock capability and
membership revocation for twelve customer writers.

Missing independent authorities:

- contact read and contact write;
- address read, address write, and open-fulfillment redirect;
- private notes;
- declared preference management;
- customer export;
- AI access to contact, notes, financial, and affinity classes;
- acquisition/consignment relationship and payout reads;
- source-import administration and reviewed source reconciliation where the
  existing transaction capabilities are too broad.

These must be data-projection authorities, not presentation flags. Every new
client-facing table should remain private by default and be exposed through
bounded, permission-aware RPCs or views with explicit grants and RLS. Current
Supabase platform behavior also no longer makes new public-schema tables
automatically available through the Data API, which is consistent with this
fail-closed design.

## 6. Whatnot source feasibility

No supplied Whatnot CSV or authoritative account-level API grant was found in
the checkout, so exact headers and stable identifiers cannot be accepted yet.
Official Whatnot documentation currently establishes only these usable facts:

1. A seller can export a per-show Show Report CSV from Seller Hub. Whatnot says
   it contains purchase, item, buyer, shipment, sale-price, fee, and total
   details, but the public article does not enumerate every header.
2. The Weekly Orders Report is a CSV of completed order-related transactions.
   It documents order ID, listing title/description/category, buy format,
   quantity, optional SKU/COGS, livestream ID/title, transaction timestamps and
   types, fees, earnings, and completed partial/full refund rows. It omits
   pending, failed, and cancelled orders and is weekly, so it cannot be the sole
   order-state feed.
3. Seller Hub Orders exposes buyer, item count, channel, price, and status.
   Shipments expose buyer username, item count, shipment status, and tracking
   when available. One shipment may bundle several purchases.
4. The Ledger CSV is transaction-level net balance activity. It includes
   processing/completed status and payouts, but excludes cancelled orders and
   failed payments and does not itemize all order fees. A 31-day date range is
   documented for export.
5. Whatnot exposes viewer lists, chat, and live analytics in its own seller UI,
   sometimes under limited availability. That is not evidence of an exportable
   or permitted Element 10 API. No live connector, viewer-list feed, chat feed,
   bid history, follower feed, or watch-time API is verified here.

Official sources reviewed:

- <https://help.whatnot.com/hc/en-us/articles/36107067835533-Export-a-Show-Report-CSV>
- <https://help.whatnot.com/hc/en-us/articles/36772664621837-Seller-Weekly-Orders-Report>
- <https://help.whatnot.com/hc/en-us/articles/44413003987981-Ledger-Transactions-Page-in-Seller-Hub>
- <https://help.whatnot.com/hc/en-us/articles/48366158177165-Manage-orders-after-you-sell>

The first implementation contract must therefore accept a manually supplied,
validated file. It must preserve the original file hash, raw row, parser/schema
version, seller/account scope, import batch, source row, source order, source
line, and later interpretation revisions. Unsupported or absent fields stay
unknown. A connector can later feed the same intake and reconciliation
contracts without replacing them.

## 7. Required additive changes

### 7.1 Relationships and events

1. Add explicit organization-customer roles or role observations for buyer,
   seller-to-shop, and consignor without cloning `e10_customers`.
2. Link reviewed acquisition/buy-ticket headers and lines to the customer
   relationship, while preserving supplier/entity separation and transaction
   direction. Current purchase orders and supplier invoices are not customer
   acquisitions.
3. Add consignment agreement, consigned-item, sale allocation, payable, and
   payout facts. They must not enter buyer-spend contributions.
4. Add payment/credit/settlement evidence as separate state machines linked to
   posted customer transactions. Posting must continue not to imply payment or
   settlement.
5. Add fulfillment and shipment headers/lines that link transaction lines,
   break sale/slot where relevant, allocated cards or owned copies, packages,
   tracking, and immutable address snapshots. Consolidation is a many-to-many
   shipment-line relationship, not a rewrite of sales.
6. Add explicit customer-to-card allocation/fulfillment linkage. A transaction
   line may have zero, one, or many delivered owned/copy facts, with conserved
   quantity and no ownership mutation hidden inside reporting.

### 7.2 Contact, address, preference, and affinity data

1. Add versioned contact points and addresses with type, source, verification,
   effective/current status, defaults, actor, timestamps, and retention/redaction
   state. Keep immutable order/shipment snapshots separate.
2. Add append-only delivery-instruction and open-shipment address-change actions
   with optimistic revision checks and audit facts.
3. Add declared customer preferences with subject kind, optional canonical
   team/subject/product/release/configuration/category reference, unresolved
   private text, provenance, actor, decision status, and effective history.
4. Add derived affinity snapshots or reproducible query results with metric
   basis, time window, as-of/cutoff, sample size, coverage, currency where
   monetary, and source lineage. Never overwrite declared preferences.
5. At contribution grain, allocate each monetary/unit fact once. Multi-subject
   discovery may return the same line under several subjects, but aggregate
   totals require distinct line identity or an approved conserved attribution
   method. Mixed products need an unallocated bucket unless explicit allocation
   sums to the source line.

### 7.3 Queries and indexes

Required bounded readers:

- customer profile projection with independently authorized identity, contact,
  address, note, financial, fulfillment, acquisition, and consignment sections;
- two-way commercial timeline keyed by stable event and line identities;
- official spend/profile query with order count, units, first/last purchase,
  recency, frequency, average order value, refunds, channel/location mix, and
  explicit coverage;
- declared-preference and observed-affinity queries that keep the classes
  separate;
- customer to order/line or slot to session to product/configuration to
  allocation/fulfillment traversal, plus reverse lookup;
- unresolved buyer and source-reconciliation queues;
- permission-aware export based on the full authorized cohort, never the loaded
  page.

Likely additive indexes must follow actual query shapes, at minimum organization
plus customer/time on each new event stream; source account/order/line unique
claims; organization plus normalized channel identity; active defaults for
contact/address; shipment-to-line and line-to-shipment; allocation-to-owned-item;
and preference/affinity canonical target plus customer. Partial unique indexes
must enforce one current default per customer and type without erasing history.
No index design should be finalized before representative query plans and data
volume fixtures exist.

### 7.4 Migration and backfill implications

- All changes are additive. Do not rewrite any applied migration.
- Existing customers remain stable. Backfill only relationships supported by
  deterministic source identity or reviewed mappings.
- Existing buyer handles can seed identity candidates, not automatic merges.
- Existing posted transactions already form the official spend base. New
  payment, shipment, acquisition, and consignment facts link to them or to their
  own directional facts; they do not duplicate transaction lines.
- Legacy slot `ship_state`/`ship_note` and OBS buyer handles require a reviewed
  migration plan. They cannot be promoted into authoritative shipment/contact
  records without source and identity evidence.
- Historical addresses should only be imported from authoritative order or
  shipment snapshots. Never synthesize them from current customer fields.
- Whatnot backfill begins with raw immutable batches and source-coverage
  assertions, then reviewed matching to current activity/lines. Reimport and
  corrected-file behavior must be idempotent and revisioned.
- Existing spend dataset revisions must advance when effective customer
  attribution or eligible monetary facts change. Contact-only changes should
  not invalidate financial datasets unless the selected projection includes
  them.

## 8. Metric definitions that must be fixed before implementation

1. **Buyer merchandise spend**: posted eligible sale-to-customer line gross less
   merchandise discount plus additive merchandise adjustments, by currency and
   as-of cutoff. State whether shipping and tax are displayed separately or
   included in a named collected-total metric. Do not call both values spend.
2. **Refunds**: additive decreases attached to the originating line, reported by
   occurrence and as-of policy. Pending requests are not posted refunds.
3. **Order count**: owner must choose posted transaction count, source order
   count, or purchasing occasion. Marketplace lines and consolidated shipments
   must not inflate it accidentally.
4. **Frequency/recency**: define event grain, timezone, known-history start, and
   unknown occurrence handling.
5. **Credits**: issuance is not spend. Redemption is a tender against a sale and
   cannot create another sale.
6. **Payments and settlement**: separate from posted sale and from marketplace
   payout availability.
7. **Acquisition and consignment**: amounts paid by the shop to the customer and
   consignor payouts are directional summaries excluded from buyer spend.
8. **Affinities**: define spend, units, line frequency, participation, and
   received-card signals independently. Random assignment is evidence of
   participation, not preference.
9. **Historical coverage**: every lifetime label must show earliest supported
   date, included source classes, unresolved/unmatched counts, and completeness
   status. Current source can report known history but cannot claim complete
   lifetime coverage.

## 9. Genuine owner decisions

1. Define the acquisition/buy-ticket and consignment business lifecycles,
   including when the counterparty is a customer relationship versus a supplier
   entity and whether explicit links between them are allowed.
2. Define buyer-spend presentation: merchandise net, shipping, tax, discounts,
   refunds, tips, and store-credit redemption, with separate collected and
   settled metrics if needed.
3. Choose order-count grain and the time basis for refunds, recency, and
   lifetime/known-history labels.
4. Approve customer privacy capabilities and default role grants for contact,
   address, notes, financial insights, acquisition/consignment history, export,
   and AI access.
5. Define contact retention, redaction, consent, marketing preference, and
   source-license limits.
6. Decide whether preferences may be organization-private only, and whether any
   can be shared with or proposed to platform catalog governance. The default
   recommendation is private customer evidence only.
7. Define multi-subject and multi-product financial attribution. The safe
   default is inclusive discovery with distinct-line totals and no fractional
   financial attribution until approved.
8. Approve Whatnot source priority: Show Report, Weekly Orders, Orders/Shipments
   operational export, and Ledger; provide representative files and confirm
   permitted retention/automation.
9. Define behavior when Live or Cards is disabled with open breaks, unresolved
   imports, unfulfilled allocations, or active consignments. History must remain
   readable under appropriate authority.
10. Decide whether a customer relationship can be linked across two platform
    accounts within one organization, and how reviewed split/merge handles that
    history. Cross-organization sharing remains prohibited.

## 10. Small sequenced implementation plan

Each increment stops for review and must pass local replay, exact-head CI, then
explicit staging verification before the next increment. Production remains a
separate gate.

1. **CRM-D0 definitions and source samples**: approve metric and privacy rulings;
   obtain representative Whatnot exports; publish a field/availability/retention
   manifest; define import identity and unsupported fields. Documentation and
   fixtures only.
2. **CRM-D1 profile privacy and contact foundation**: additive contact/address,
   consent/preference, snapshot, and audit tables; independent capabilities;
   bounded profile projection; tenant, field, export, and AI-denial tests.
3. **CRM-D2 two-way relationship links**: customer roles plus additive links to
   reviewed acquisitions, consignment, payouts, payment/credit/settlement, and
   fulfillment. Keep each direction and lifecycle separate. Add shipment
   consolidation, partial fulfillment, address snapshots, and card-allocation
   links.
4. **CRM-D3 preferences and affinities**: declared preference history with
   canonical-or-unresolved targets; reproducible observed affinity contributions
   and snapshots; multi-subject/product anti-multiplication tests.
5. **CRM-D4 Whatnot file intake and reconciliation**: immutable raw file/row,
   typed revision, validation/preview, reviewed matching to existing activity or
   transaction, order/refund/shipment evidence, corrected-file and replay
   controls. Manual capture remains first-class.
6. **CRM-D5 bounded CRM readers**: two-way timeline, profile metrics, reverse
   live-break/fulfillment traversal, unresolved queues, full-authorized-dataset
   filters and export. Reuse X7/X8 query controls and spend contribution grain.
7. **CRM-D6 module and historical backfill proof**: reviewed backfill, unknown
   coverage, Live/Cards disable tests, active-commitment handling, adversarial
   tenant/privacy proof, representative-volume plans, exact-head CI, and staging
   evidence.

## 11. Tests required before CRM readiness can be accepted

At minimum:

- one org customer linked as buyer, collection seller, and consignor, with
  directional totals and no duplicate commercial or inventory fact;
- identity attach/detach/rename, ambiguous same-name buyers, shared address,
  anonymous/unresolved sale, reviewed correction, split/merge, replay, stale
  revision, and concurrent final-lock revocation;
- provisional native sale plus manual evidence plus matching import and replay
  producing one posted line and one source-claim set;
- partial refund, full cancellation, release, resale sequence, corrected import,
  and no-write loser proof;
- mixed currency and unknown components, with drill-through sums reconciling to
  every displayed subtotal;
- acquisition/consignment payments excluded from buyer spend;
- multiple current/contact/address candidates, one default per type, immutable
  shipment snapshot, explicit open-shipment redirect, consolidated orders, and
  partial shipment;
- declared favorite versus random team/received hit; zero/one/multiple subjects;
  unresolved private text; no multiplied spend or units;
- customer to order/line or spot to session to product/configuration to
  card/fulfillment traversal and every reverse lookup;
- missing source fields remain unknown; unsupported viewer/chat/bid/watch-time
  claims rejected; manual-only path remains complete enough to operate;
- cross-organization denial plus differentiated contact, note, finance, export,
  and AI projections, including cursor and saved-view rebinding after authority
  changes;
- Live/Cards disabled with history retained and active commitments explicitly
  resolved or blocked;
- representative-volume query plans for customer/time, normalized identity,
  source claims, shipment links, preferences, affinities, full-cohort totals,
  and export.

## 12. Conclusion

Element 10 should extend the existing `e10_customers`, customer evidence,
reviewed transaction, reconciliation, native-sale, and spend-reporting contracts.
It should not introduce a second CRM identity table or another transaction
ledger. Current source is strong enough to support reviewed customer identity,
unresolved buyers, provisional-versus-posted separation, additive corrections,
native break resale history, and bounded official spend. It is not yet ready to
claim the complete CRM because the two-way acquisition/consignment side,
contact/shipping history, preferences/affinities, payment/settlement,
fulfillment/card allocation, source-validated Whatnot imports, field-level
privacy, and module-disable behavior are still absent or partial.
