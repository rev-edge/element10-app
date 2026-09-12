# Shared core and Cards intelligence framework

Status: September 10 owner-directed scope extension and implementation contract proposal. Existing approved arithmetic, costing, approval, tenant isolation and history rules remain authoritative. This is not a physical migration, production acceptance, or approval to activate external feeds.

Read with [the evidence audit](EXPANSION_AUDIT_2026-09-10.md), [domain map](DOMAIN_MAP.md), [operator lifecycle](OPERATOR_LIFECYCLE.md) and [product-supply model](product-first/PRODUCT_SUPPLY_MODEL.md). Where a new requirement refines an accepted rule, the refinement is named below and must be tested before adoption. Do not treat the historical `Today` columns elsewhere as cross-environment status.

## 1. Product boundary

One inventory and cost engine, optional domain modules. The core owns organization, membership, locations, products, packaging/conversions, suppliers, purchasing, invoices, receipts, lots, individually tracked items, reservations, listings, sales, fulfillment and corrections. Cards owns canonical card identity, player/set/parallel terminology, grading and copy-specific card attributes, checklists, breaks and card presentation.

Generic individually tracked items are a target core seam. Existing `CardInstance` workflows are not renamed or migrated by this document. Extract their generic acquisition, ownership, location and disposition behavior without duplicating the ledger, and prove a non-card unique-item fixture before declaring the core independent.

Product variants and packaging are different: size/color/material describe what the item is; case/box/each describe stocking and conversion. Existing Product Configuration version binding remains intact. Add a variant reference or equivalent explicit relation before supporting variant-heavy shops; never repurpose the conversion chain to mean clothing size.

Customization permits labels, visible fields, saved views and versioned typed extensions. Each extension has owner namespace, stable field ID, data type, units, allowed values, validation, cardinality, permissions and index eligibility. Extensions cannot redefine core IDs, cost basis, quantity, lifecycle or access rules. Unknown is distinct from false, zero and not applicable. Disabling Cards blocks card workflows without deleting history or making shared core workflows depend on Cards.

## 2. Purchasing and relationships

| ID | Requirement and boundary |
|---|---|
| PUR-01 | Intended destination suggests active authorized locations. A sole eligible destination is selected and locked. Free text is an additional advisory delivery description, not a substitute for a required location ID. Zero authorized destinations blocks creation where destination restriction applies. Recheck on commit and after role/org changes. This refines the R1 advisory-only field and extends PF-M4's optional location filter to purchasing. |
| PUR-02 | Suggest the most recent eligible actual purchase unit cost for the exact vendor, product and packaging version, with currency, date and source. An unreceived PO estimate is not last price paid. Use deterministic validated conversion only, with provenance. Manual edits are never silently replaced. Quantity-tier or different-vendor references require explicit labels/selection. Unknown stays empty and preserves approval. |
| PUR-03 | Separate internal notes and vendor-facing comments in creation, detail and later amendment history. Both are organization-private until an explicit authorized vendor output is requested. A vendor-output allowlist excludes internal notes, audit comments, costs not meant for the vendor and hidden metadata. |
| PUR-04 | Two receiving entry points: PO-first and direct invoice/purchase-first. PO, invoice and receipt are distinct objects. Never fabricate an approved PO for an invoice-only purchase. Match invoice lines to PO lines through explicit quantity allocations so partial invoices and multiple orders are representable without duplicating charges. |
| PUR-05 | Receive accepted physical quantities separately from charge approval. Record inspection, shortages, damaged/quarantined stock, partial receipts and authorized correction. Invoice import alone creates no on-hand stock. Existing overcommit and receipt-reversal rules stand; over-receipt needs explicit exception authority, not a silent increased PO. |
| PUR-06 | Vendor workspace links open/past POs, invoices, receipts, credits and source documents to the same underlying IDs. Separate open commitments, invoiced purchases net of credits, payments, and unused credits. Never label ordered value as lifetime spend. |
| PUR-07 | Product workspace links all supplier offerings. Keep internal master item ID, configuration identifier/barcode and vendor item code distinct. Vendor offering references exact purchasable configuration, currency and observed cost provenance. Renaming a supplier/product never breaks history. |

Invoices and credit memos need their own source identity, revision/status, currency, amounts, allocations and additive corrections. Duplicate import identity is tenant + source connection + external document ID, with payload fingerprint; manual imports use documented supplier-document identity and explicit duplicate review. Attachments corroborate database facts; losing a PDF must not erase balances or audit facts. Pending shortage is not automatically a vendor credit. Invoice approval, receipt posting and payment are three different events.

## 3. Canonical identity and hygienic matching

The [Card Ladder / PriceCharting review](CARD_DATA_COMPARATIVE_REVIEW_2026-09-10.md) adds required refinements: language/region/edition and release precision; categorical grading designations, autograph assessments and regrade history; dated population snapshots distinct from print run; typed provider-entity mappings; versioned valuation provenance; and portfolio changes separated from market return. Preserve progressive entry and source granularity rather than forcing every field or inventing exact grades from aggregate buckets. These are design requirements, not implemented-schema claims.

Keep four layers separate:

1. Platform catalog identity: subject(s), manufacturer, brand/line, release/season, set/subset, card number and exact parallel.
2. Governed attributes: broad color family, finish/pattern, source-specific parallel name, rookie designation and print-run denominator. Alias mappings carry namespace, source, confidence/review status and revision. `True gold` is not a universal string comparison.
3. Physical copy: canonical identity reference, owned-item ID, condition, grading company/grade/certification, serial numerator and observed markings. Existing serial/print-run separation is reused. Jersey match names the reference team/season or pictured number and supporting evidence.
4. Observations/transactions: each source listing or sale references the best-supported identity/copy and stores its source text and match status. A title match is not an exact-copy match.

Every input route uses the same resolver: UI, CSV, image-assisted input, invoice and future chat. Exact verified link, candidate awaiting review, or visibly unresolved are legal outcomes. No 100% identification guarantee. Unresolved items remain usable for intake but do not silently enter exact-card aggregates. Corrections retain prior mapping, reason, actor and effective version; merges preserve aliases and lineage rather than deleting evidence. Platform curation is distinct from org-private overlays. Names and prices never act as primary keys.

### Catalog promotion identity correction required

PF-M5's provisional composition-key proposal cites the prototype duplicate-warning key. Do not promote that warning heuristic into a canonical uniqueness constraint unchanged: the R1 key excludes release year and includes the physical serial numerator. It can conflate different releases and separate two copies of the same catalog variant. The canonical key needs a stable release/set identity plus the exact entry/parallel identity within that release; copy serial stays on the instance/observation. Subject cardinality must support multi-player cards rather than assume one player name makes every identity unique. This is a required PF-M5 refinement before promotion implementation, not an unreviewed change to current duplicate warnings.

## 4. Commercial lifecycle facts now, reports later

Extend, do not replace, the inventory movement and cost ledgers. A commercial event is not necessarily an inventory movement. Capture typed events for acquisition, receipt, available-for-sale, listing created/published/paused/resumed/ended/relisted, asking-price change, hold/release, sale committed, fulfillment, fee/payout, refund/return and cost correction. Listing intervals on multiple channels must reference the same physical copy.

Required event envelope: tenant, stable event ID, event type/schema version, subject identity, source entity/lineage references, business occurrence time, recorded/ingested time, actor or integration identity, source event ID, idempotency key and fingerprint, correlation/causation, evidence quality and correction/supersession reference where relevant. Versioned payload schemas validate event-specific fields; avoid free-form event strings as the only analytical substrate. Backdated entry does not claim contemporaneous observation. Preserve unknown timestamps.

Inventory writer remains the single authoritative writer, atomic with its movement and idempotency receipt. Commercial actions atomically write their state change and event; integration delivery can use a transactional outbox with replay-safe consumers. Never bolt analytics logging onto a successful action as an untracked best-effort second write. Preserve the accepted no-item-FK ledger rule; validate references at the writer and retain historical value references.

### Metric contracts

- On-hand, reserved, free, expected and in-transit are separate quantities with scope, unit and as-of time.
- Inventory age: receipt to sale or as-of. Intake delay: receipt to first eligible published listing. Time since first listing and active exposure are different metrics. Item-level active exposure is the union of eligible listing intervals, not their sum across channels.
- Sale velocity reports show cohort definition, number sold, number still unsold, observation window, missing history and censoring. Mean days among sold copies is labeled as such, not a prediction for all stock. Never guarantee a six-day sale.
- Gross margin and contribution after fees/shipping/labor have distinct names and definitions. Use cost evidence effective under the accepted cost contract, with late adjustments traceable and provisional costs visible. Last paid price is a reference, not retroactive replacement of recorded basis.
- External asking prices, external completed sales, estimated market value and the shop's actual transactions are separate datasets. Deduplicate the same sale syndicated across sources. A disappeared active listing does not prove a completed sale.

## 5. Composable card-market screener

**Owner priority: relational reporting first.** The main analytical surface is a cross-catalog workspace, not a player-page navigation funnel. Users combine dimensions in one query across releases and products, choose columns/grouping/measures, and drill into subjects, variants, grade cohorts, copies and underlying observations without losing the query. Player/card pages are useful detail views, not prerequisites for filtering. This is a business-intelligence-style query experience over governed relationships, not simply a searchable list of display titles.

Example: canonical subject Lamine Yamal + evidence-backed rookie-card designation + grading company PSA + card grade 9 returns all matching catalog-variant/grade cohorts across products. No specific year or parallel is assumed from the player's name. Distinguish rookie-card designation from a user-selected rookie-season release filter; make that choice visible. A catalog cohort does not assert that an owned PSA 9 copy exists. Users choose catalog, owned inventory or sale-observation scope; counts name their grain. Sales metrics aggregate eligible observations after deduplication, while inventory quantities derive from actual copies. Show unknown rookie/grade mappings separately, never silently include them. Saving or changing a query does not change source records.

Optional filters: sport/league, player, maker, line/set, release-year or season range, rookie designation, exact parallel, governed color/finish family, raw/grade, print run, known copy serial, jersey match, source, currency, observation window, sale count and price measures. All numeric thresholds are user parameters, never hardcoded five-sales or $1,000 rules.

Separate catalog discovery from observed sales/copies. Show known matching catalog entries with no price when no sales requirement is selected. Serial-specific results cover observed copies only. Broad gold-family grouping preserves exact identities in drill-down; raw and graded variants are not silently averaged together.

Query order: resolve canonical facets; select authorized eligible observations and transaction-level filters; deduplicate; aggregate using explicit grouping keys; apply aggregate constraints such as minimum count or mean price range; paginate/sort; expose underlying observations. Filtering each sale below $1,000 before calculating a supposedly unrestricted mean is incorrect. Price measures identify latest sale, mean, median, active ask or estimate, with dates/source/currency/sample size.

## 6. Pricing workspace and feed boundary

### First-party and user-imported data work without live feeds

Owner requirement: catalog screening, price-history analysis, collection-value views and configurable reporting must work with the tenant's own records and validated manual/bulk uploads when every external connector is disabled. Live feeds are optional enrichment, not the source of authority or a prerequisite for these surfaces. Reuse the same governed identity, parallel/color/finish facets, observation model and metric contracts across all intake paths.

Accept manual observations and spreadsheet/CSV imports through mapped, typed staging with row-level validation, preview and explicit commit. Preserve original files/rows, source attribution, observation date versus import date, currency, observation kind, identity-match status and correction history. Acquisition cost, asking price, completed sale and estimated value remain different facts. Importing a market sale does not create owned inventory or a posted customer transaction. Reimport is deduplicated; uncertain identities and invalid rows are reviewable, not silently coerced into matches or zeros. Document partial-import policy before commit. User-supplied external data still needs permitted use; upload is not a bypass for source restrictions or redistribution rights.

Internal-only reports expose dataset scope and coverage. A shop's realized sale history is not the entire market; acquisition history alone cannot establish current market prices. Collection cost basis and estimated value appear separately. Valuation identifies selected method, eligible evidence, currency, as-of date and age, and shows valued versus unvalued holdings. No evidence means unknown value, not zero. Sparse observations stay sparse, with no fabricated trend. External enrichment adds separately sourced observations without overwriting local facts; disabling a feed leaves local-data reporting functional. Shared cross-shop data is a separate consent/rights boundary, never automatic pooling.

Show exact product/configuration, current retail, actual cost, target margin, stock/age, sourced observations and recent trend together. Mark stale, sparse, estimated and unmatched evidence. Recommendations are previews, with source records and assumptions. Price publishing is a separate permission-checked, revision-bound action; no automatic repricing is authorized.

Before promising any external source: prove licensed use, production API access, exact sealed/singles/grade coverage, market/currency coverage, rate limits, refresh cadence, retention and redistribution rights. Do not presume Card Ladder/TCGplayer partnerships or scrape around restrictions. Cross-shop analytics requires separate opt-in, purpose, revocation, minimum cohort and anti-reidentification design. Private tenant transactions never become shared reference merely because many shops use the platform.

## 7. Wishlist and optional listing monitoring

WishlistEntry is a personal desired-item record in an explicit account/org context, not owned stock, reservation or PO. It references an exact catalog identity or an unresolved desired query, optional grade/condition, target buy price/currency and notes. Wishlist can exist with monitoring off forever.

MonitorRule is optional and disabled by default. Enabling requires explicit cadence, query and notification preferences. Disabling stops future checks/alerts while preserving the entry and preferences. Once or twice weekly is a valid user choice, not an actual automation activated by these requirements.

ListingObservation and MatchNotification are separate from SaleObservation. Store source listing identity, first/last seen, current bid versus buy-now, shipping-known status, auction end, match evidence and last successful check. Baseline existing matches before new-match alerts. Retry safely; no duplicate alert on the same observation. A paused/error state is visible. A listing that starts and ends between checks can be missed. No bidding or purchasing automation.

## 8. AI-ready access layer

Forms, imports and future conversation call the same typed permission-checked queries and commands. Query tools return bounded data, source links, metric definitions, freshness and unresolved ambiguity. They cannot write. Mutation tools prepare ordinary drafts, identify missing information, preserve field provenance, preview effects and require explicit approval before commit. The server rechecks tenant, role, location, entitlement, object revision and idempotency at commit.

The model gets no database superuser role, arbitrary SQL mutation endpoint or client-side service key. Document text is untrusted data, not command authority. Financial fields are projected according to permissions, not merely hidden in the UI. An org switch invalidates stale conversational context and drafts. Conversational history and query caches obey tenant/access scope and retention policy.

### Multi-company context is an explicit integration gate

The staging legacy `current_org()` helper fails closed for multiple active memberships. The prototype selector does not establish a persisted selected-org context. The future query/command layer must use the accepted explicit-org authorization path or a separately reviewed selected-org contract, and verify membership on every request. Never change the helper to pick the first membership or trust a client-provided org without checking it.

## 9. Query and performance seams

Target bounded, server-side filters and cursor pagination. Candidate indexes must follow measured query plans, not index every custom field: tenant/entity/event-time/event-ID for lifecycle drill-down; canonical identity/source/sold-time for sale observations; source/external-ID uniqueness for deduplication; tenant/user/enabled/next-check for monitors; explicit facets for governed catalog filters. Tenant private data never enters shared cache keys. Incremental rebuildable aggregates carry version, cutoff and correction watermark. Record an as-of snapshot so pages do not silently compare different windows.

Acceptance needs representative volume and two-org hostile cases before latency claims. Cached means are not enough: changing identity mappings, refunds, late fees, deleted/withdrawn evidence and overlapping listings must update or invalidate aggregates correctly. AI response speed comes from these bounded queries, not loading all inventory into a prompt.

## 10. Delivery order and acceptance

1. Capture requirements and evidence, label environment maturity, preserve accepted model history.
2. PO trust revision: comments; then destination authority and actual-cost suggestion once their source/permission contracts are in place. Keep R1 frozen as baseline; each candidate gets its own evidence.
3. Invoice-first receiving preflight and source-document/credit model, aligned to PF-C5 and PF-M4. Test partials, duplicate imports, damaged goods, unapproved charges and additive cost finalization.
4. Lifecycle/identity contract and fixtures before production intake/listing implementation. Test collection allocation, direct sale, competing channel reports, overlapping exposure, return and correction.
5. Generic core seam proof using one non-card finished-good and one individually tracked non-card item. No restaurant, recipe or manufacturing engine.
6. Read-only screener and wishlist prototype with clearly synthetic fixtures, optional thresholds and monitoring off. No fabricated live prices or feed connectivity.
7. Feed feasibility and permission-scoped query layer. External adapter pilot and AI surface follow evidence and approval, not placeholder buttons.

Unchanged production cutover, curation and independent acceptance gates still apply. These steps do not grant themselves acceptance.

## 11. Owner review: player hygiene, shared grids and customer intelligence

September 10 follow-up confirms the planner as critical, player identity as foundational, grid/query quality as central, and customer intelligence as essential for hobby shops. These are requirements, not implemented-feature claims.

### Player identity without burdensome entry

Use a stable canonical subject ID with source-specific identifiers and aliases. Sports, leagues and dated team affiliations are separate relationships: a player changing teams does not change identity. Cards reference subject(s) and the depicted release/team context, not an unqualified current-team string. Same-name people remain distinct. Rookie designation and affiliations require source evidence; unknown stays unknown.

Intake asks only what is needed for a useful, non-misleading record. Search/select first, suggest matches from context, and route uncertainty to an actionable enrichment queue without unnecessarily blocking intake. Optional fields appear progressively. Bulk review groups repeated corrections while retaining per-record provenance and exclusions.

AI proposes aliases, mappings, duplicates and explanations for conflicting sources. Keep source, proposed value, model/tool version and confidence separate from verified facts. Apply deterministic validation; authorized review is required for ambiguous identity links, merges/splits and shared-catalog changes. Preserve prior mappings. No silent overwrite, invented affiliation or name-only merge. Measure precision, unresolved rate and review effort against a labeled sample before claiming reliable automation.

### Shared grid/query contract

Supported fields have typed operators and clear units. Filters compose; grouping/aggregates have explicit grain; sorting has a stable tie-breaker and defined null ordering. Saved views preserve filters, columns and scope without freezing former permissions. Server-side semantics are consistent across pagination, totals, export and future chat. The loaded page is not the whole dataset. Selection distinguishes current page, selected IDs and all matches; bulk actions revalidate permissions and versions.

Acceptance covers matches beyond the first page, relationship/aggregate filters, nulls, changed queries while loading, return navigation/focus, keyboard access, empty/error states and representative-volume measurements. Saved views and exports are tenant/user scoped. Small fixtures alone do not prove performance.

### Customer records and insight

Keep the tenant's Customer relationship separate from global login identity. Stored fields include stable org customer ID, display name, channel-scoped account IDs and alias history, optional verified account link, permitted contact details, communication preferences/consent provenance where applicable, visibility-controlled org tags/notes and creation/source provenance. Behavior comes from linked transactions, not manually maintained totals. Fulfillment addresses are sensitive mutable records, not matching keys. Anonymous/walk-in sales remain possible without inventing a customer or collecting unnecessary personal data.

Derived/filterable metrics include gross/net merchandise spend, completed order count, purchased units, first/last purchase, recency, frequency, average order value, refunds/returns, new/repeat status within known history, channel/location mix and observed product/category/player/team affinities. Cost-sensitive contribution requires permission and sufficient reconciliation. Affinities derive from actual purchases or explicit preferences, not sensitive demographic inference. Ranges and date windows are optional parameters.

Define `lifetime spend` before labeling it: eligible deduplicated transaction lines over known history, with explicit discount/refund/tax/shipping and currency rules. Show history coverage and completeness. Do not silently combine currencies or count pending commitments. Store-credit issuance is not a purchase; redemption/payment methods do not create a second sale. Drill into contributing transactions and exclusions.

Customer merge/split uses verified channel IDs and reviewed evidence, not name/address similarity. Recompute projections after corrections without rewriting original orders; retain recoverable association history. Two shops serving one customer never gain access to each other's private relationship. Contact details, internal notes and financial metrics need independent projections and permissions, including exports and AI answers.

### Retail versus break spend; three capture paths

Owner clarification: customer reports separate ordinary product purchases (sealed boxes or singles in-store/online) from break purchases, with a combined deduplicated total when requested.

Keep line-level **purchase kind** (retail product, break participation, unclassified), **sales channel**, **location** and **capture source** (manual, imported, native live-session action) independent. A marketplace sale is not necessarily a break; auction is a sale method, not a purchase kind. Mixed orders retain line-level classification. Unknown imported classification stays visible and unresolved.

Three paths feed a shared evidence and transaction lifecycle. Capture alone never implies accounting approval or posting:

1. **Import:** supported Whatnot or future Fanatics Live files/adapters provide source order/line IDs, buyer, amount, currency, sale time and adjustments where available. Verify actual formats/access before promising support; preserve raw rows and interpretation lineage.
2. **Manual:** operator records a retail or break sale linked to customer and, where applicable, session and slot/purchase. Retain actor, occurrence time, amount, currency and evidence status. Recorded sale is not proof of payment settlement.
3. **Native live operation:** committing a sale in the live-break control workflow records provisional customer activity atomically with the board action, not an automatically posted financial transaction. Retain organization, customer/alias, session, slot/purchase, quantity, amount, currency, sale method and occurrence time. Holds, bids, assignment and opening the viewer companion create no spend. The viewer companion remains read-only for commercial actions.

Sale-event identity is distinct from slot identity: a slot can be reopened/refunded/resold, but a retry of one sale creates no duplicate transaction. Unresolved buyers remain in a reconciliation queue. Linking an existing sale to a verified customer changes attribution, not revenue.

Later imports attach evidence to the same native/manual transaction. Prefer durable external IDs or reviewed links; name/price/date similarity alone cannot safely auto-merge sales. Ambiguous overlaps are visible and excluded from purported reconciled totals until resolved, with provisional totals clearly labeled. Preserve both source facts and reconcile differences in price, fees or refunds rather than silently overwriting or adding them together.

Customer views expose retail, break, unclassified and combined spend, filtering/drilling by session, slot/purchase, product, channel, capture source, period and evidence/payment status. Additive refunds/cancellations adjust the originating purchase kind. Fees affect proceeds/contribution, not buyer spend; settlement remains separate.

### Provisional activity versus posted customer spend

Owner clarification supersedes any implication that a board sale finalizes customer spend. Keep reportable operational placeholders and official financial transactions distinct but linked. Official lifetime spend and average spend use eligible approved, posted lines and posted adjustments only. Unposted board amounts remain visible in a clearly labeled provisional activity view, never silently added to official totals. Retail/break/combined comparisons must use the same basis, currency and period.

Offer an optional **review and post** workflow from board activity. It prepares a financial draft with source links; an authorized operator validates customer attribution, amounts, currency, adjustments and duplicate matches before posting. Running a break does not itself grant posting permission. Manual/imported records follow the same gate; source type alone is not approval. Reconcile later imports to the existing activity/financial record, retaining both evidence sources without creating a second sale. Repeated posting is idempotent. Show linked/posted status so operational and financial views cannot be mistaken for independent purchases.

Posting, approval, matching and payment/settlement are distinct concepts. Posted does not mean paid, payout settled or immune to later correction. Refunds, credits and corrections preserve the original fact and append authorized adjustments with occurrence/posting times; reports define period and as-of treatment. This is a customer reporting contract, not a claim that a full accounting ledger is implemented.

### Customer engagement and break-level analysis

Provide customer grids/charts and drill-down for average session duration, distinct break sessions attended per week, average spend, and spend by break, product and other supported dimensions. Separate posted-spend metrics from provisional observed amounts. Define each denominator: average per order, per attended break, per purchasing break or per customer must be named, not conflated. Define reporting timezone, week boundaries, partial weeks and coverage; include zero-attendance weeks within the selected observed period when calculating a weekly average.

Attendance needs its own evidence, not inference from purchasing. Capture permission-scoped session/customer presence intervals with join/leave, heartbeat expiry, reconnect and visibility/source signals where supported. Deduplicate overlapping devices/tabs and bound intervals to session duration; missing disconnects cannot imply infinite presence. Companion presence is not proof of video viewing. Label it **observed companion time** unless an authorized platform source actually measures watch time. Platform attendance and companion attendance retain separate source/coverage labels; anonymous or unmatched presence is not silently attributed to a customer. Apply disclosed collection, retention and access rules. Telemetry must not grant viewers commercial write access.

For a break funded by several products, product-level spend requires explicit allocation whose amounts sum to the original sale. Without an allocation, show a mixed/unallocated category rather than repeating the entire sale under every product. All charts and AI answers use the same metric definitions and link to contributing records. These are new requirements; telemetry, posting workflows and analytics visuals are not claimed implemented.

## 12. Deferred collector showcase

Final roadmap phase, not a near-term shop requirement. Build a personal display experience with themed collections, front/optional-back images for raw cards and slabs, surface-level editable details and personal stories. Curated themes, reorderable cards, enlarge/flip and restrained shimmer support attractive sharing. Respect reduced motion, keyboard/touch access and mobile image budgets. Missing backs do not get invented. Upload validation, metadata stripping, storage limits and abuse handling are launch requirements, not reasons to require valuation or inventory accounting.

Use a stable personal display-item identity plus collection-membership records so one item can appear in several galleries. Optional catalog and owned-item links later connect to the actual tracking system through permission-checked projections; they are not prerequisites for upload or display. Linking is not acquisition, ownership verification, inventory movement or a new sale. Preserve original media and user-authored display text independently of upstream catalog changes. Do not repurpose seller-private customer records as a collector's public identity.

Collections start private. Sharing publishes only explicitly selected display fields/media to a read-only projection, with preview and revocable link. Personal notes require explicit inclusion; costs, addresses, private certificates/identifiers and shop notes must not leak from linked records. Revocation must stop subsequent access including cached projections/assets under the chosen serving model; downloaded copies cannot be recalled. Catalog/media rights and theme assets need review before public launch. No API, marketplace, public social feed, automatic pricing or tracking dependency in the initial showcase scope.

This records owner direction and a future compatibility seam, not a built collector product or a change to current tenant/security policies.
