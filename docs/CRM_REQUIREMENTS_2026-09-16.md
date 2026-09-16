# Customer CRM requirements

Status: owner-requested product scope, September 16, 2026. Requirements and acceptance scenarios, not implementation or environment verification. Extends EXPANSION_FRAMEWORK.md section 11 and ROADMAP.md phase 9. Preserve existing posted/provisional, tenant, inventory and approval contracts. Track A must reconcile against current source before calling any capability missing or supported.

Current evidence-backed reconciliation: [CRM_DATA_LAYER_RECONCILIATION_2026-09-16.md](CRM_DATA_LAYER_RECONCILIATION_2026-09-16.md). It records current support, gaps, source dependencies, owner decisions, and an additive implementation sequence. It does not mark these requirements accepted or authorize implementation.

## CRM-01 Customer identity and two-way commercial history

Provide a permanent Customers workspace with a comprehensive shared-toolkit grid and customer record. A person can buy from the shop, sell to the shop, consign goods, or occupy several roles without duplicate customer profiles. Link the same organization-owned relationship to sales/orders and lines, private acquisitions/buy tickets and lines, consignment agreements and payouts where supported, returns/refunds, credits, payments and fulfillment. Preserve the role and transaction direction on each event. Customer lifetime purchase spend must never include money the shop paid that customer for acquisitions or consignment.

Use stable organization customer IDs and channel/account-scoped external identifiers with alias history. A Whatnot handle, platform account identity and customer relationship are distinct concepts. Preserve historical handles and source identifiers. Names, email or shipping-address similarity alone must not silently merge people. Support reviewed matching, unmatched historical transactions, anonymous retail sales, and auditable reversible attribution corrections/merge handling. Reattribution changes the customer association, not the underlying revenue or stock movement. Separate customer relationships from global login identities and supplier entities; allow explicit linkage without duplicating transactions.

## CRM-02 Buyer profile, preferences and discovery

Show lifetime spend over known history, retail versus break spend, order count, first/last purchase, frequency, refunds and channel mix, with drill-through to eligible contributing records. Reuse the existing official posted-transaction metric contract: pending orders, bids, holds, assignments and provisional live-board entries are not official spend. Show provisional activity separately. Define gross versus net, discounts, tax, shipping, refunds, currency, as-of time and data coverage. Do not silently combine currencies. Payment, posting and settlement remain separate. Show shop purchases from this person, payouts and consignment activity as separate summaries, never netted into buyer spend.

Support explicit customer-stated favorite teams, players/characters, products/releases, categories and formats. Store provenance, who recorded the preference and when; allow updates or removal. Separately show observed affinities derived from eligible transaction lines with timeframe, basis (spend, units, participation or frequency), sample size and source coverage. An inferred affinity must not overwrite a declared favorite or be presented as a fact about the person.

Link preferences and observations to existing canonical teams, subjects, releases and configurations when known. Preserve unresolved private text when no reliable identity exists; do not require every character to have a canonical master. Multi-subject or multi-product joins must not multiply transactions. Team picked in a break, team randomly assigned, and a card actually received are different signals. Receiving a randomly assigned team or hit does not establish a favorite. Multi-product spending needs an explicit allocation or mixed/unallocated bucket; do not credit the full purchase amount to every subject or product.

Provide composable filtering, sorting, columns, saved views and authorized export, including spend ranges, purchase recency, favorite team/subject/product and channel handles. Query the full authorized dataset. Everyday presents contact, shipping, recent history and clear actions; Advanced exposes detailed history, provenance, segmentation and reconciliation using the same records and permissions. No new UI implementation is authorized by this document.

## CRM-03 Contact and shipping

Support display/legal or recipient names as appropriate, email, phone, channel handles, multiple shipping addresses, default address and operational delivery instructions. Separate current contact/address records from immutable historical order/shipment address snapshots. Editing a default address must not rewrite shipped-order history or silently redirect an existing shipment. Address changes for open fulfillment require an explicit authorized action and audit trail. Shared household addresses are not identity keys.

Distinguish operational contact permissions from marketing consent and communication preferences, with source and timestamps where applicable. Restrict contact details, addresses, internal notes, exports and financial insights by capability and organization. Viewing a profile or identifying a favorite does not authorize outreach. Record retention/redaction behavior and source-imposed limits as reconciliation decisions. No cross-shop sharing of customer history or profiles.

## CRM-04 Live breaks and Whatnot are central inputs

The customer record must unify supported Whatnot evidence, native live-break operations and manual entry while retaining provenance. Where the source supplies them, retain marketplace seller/account scope, buyer/account ID and handle snapshot, source order/line/event IDs, stream/show/session, break, slot/spot, team selection or assignment, sale method, product/configuration, quantities, amounts, currency, occurrence/import times, cancellation/refund state, fulfillment/tracking and linked settlement evidence. Preserve card/hit allocations and delivery links when captured by the operator; do not imply Whatnot supplies them.

Allow drill-through customer -> order/spot -> break/session -> product/configuration -> allocated cards/fulfillment, and reverse lookup from each operational record. Support multiple purchases consolidated into one shipment and partial shipments without changing spend or losing customer attribution. A slot may be resold after cancellation; sale-event identity must remain distinct from slot identity.

Native board activity remains provisional until the existing authorized review-and-post workflow. Later marketplace imports attach evidence to the same activity/transaction rather than creating another sale. Replays, corrected files, refunds, partial refunds, renamed handles and unresolved buyers must be reviewable and idempotent. Retain raw source lineage and reconciliation status.

Source feasibility is an explicit dependency. Track A must verify actual available Whatnot files, permitted APIs/access, field coverage, retention and update cadence. Do not promise live sync, viewer lists, chat, bid histories, follower data or watch time without verified access. Authorized manual/CSV capture must remain useful without a connector. Clearly distinguish transaction-derived participation from observed attendance; companion presence is not video watch time. Existing engagement requirements remain conditional on reliable evidence.

## CRM-05 Modular adoption and scope

Basic customer records and historical transaction links must remain usable independently of Live, specialist Cards or analytics. Optional modules enrich the same relationship. Disabling a module preserves history and authorized access while active commitments receive explicit handling. Entitlement, presentation and permissions remain separate. Exact commercial packaging is unresolved. Campaigns, outbound messaging, loyalty mechanics and automatic recommendations/actions are outside this scope.

## Required acceptance scenarios

| ID | Scenario | Required result |
|---|---|---|
| CRM-A01 | One person buys retail, buys break spots, sells a collection and consigns cards | One relationship; linked history by direction/role; acquisition payments and consignor payouts excluded from buyer spend. |
| CRM-A02 | Native provisional sale, manual evidence, then matching Whatnot import and replay | One commercial fact after reconciliation; provenance retained; posting distinct from settlement; no double stock/spend. |
| CRM-A03 | Partial refund, cancellation and resale of the same slot | Original history preserved; posted adjustments and separate sale-event IDs produce correct totals. |
| CRM-A04 | Handle changes, same-name buyers, shared address and anonymous sale | Reviewed matching; no name/address auto-merge; unmatched/anonymous transactions remain valid. |
| CRM-A05 | Favorite Charizard plus randomly assigned team and dual-subject card | Declared preferences remain distinct from observed evidence; no false favorite inference or multiplied spend. |
| CRM-A06 | Default address changes after shipment; two orders consolidated; partial shipment | Historical snapshots unchanged; open-shipment changes explicit; transaction/line links retained. |
| CRM-A07 | Missing Whatnot attendance/API fields; incomplete historical coverage | Unknown/unavailable labeled; manual/import path works; no invented watch time or complete-lifetime claim. |
| CRM-A08 | Two tenants share a platform buyer; employee/export/AI access differs | No cross-tenant relationship leakage; field-level projections honor authority. |
| CRM-A09 | Mixed currencies, discounts, shipping, tax, credit redemption and unknown allocations | Defined metric basis; no duplicate sale or silent currency merge; unknowns and excluded amounts visible. |
| CRM-A10 | Correct customer attribution or merge, then disable Live/Cards | Recomputed profile with audit lineage; financial facts unchanged; basic history retained. |

## Track A deliverable

Provide a requirement-to-contract matrix for CRM-01 through CRM-05 and CRM-A01 through CRM-A10: supported with evidence, partial, missing, conflicting, or source-dependent. Distinguish local, staging and production verification. Cite exact schema/actions/query contracts/tests and commit/environment, not merely similarly named tables. Reconcile existing customer scope instead of creating a second CRM or transaction ledger. Return missing relationships/events/indexes, privacy and permission projections, import/reconciliation gaps, metric definitions, migration/backfill needs and a small sequenced implementation plan. Identify genuine owner decisions separately. This request authorizes investigation and documentation, not migrations, production changes or integration activation.
