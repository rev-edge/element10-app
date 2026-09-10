# Track A expansion execution plan

Status: execution plan and evidence matrix for the owner-authorized September 10 backend expansion. This document does not authorize production writes, UI changes, external feeds, monitoring jobs, or deployment. Staging changes require explicit project targeting and empirical verification.

## Evidence baseline

- Canonical checkout: `/Users/tsconnely/dev/element10-app`, branch `foundation-a6`.
- Tenant engine: A6a through A7 are implemented in migrations `20260717120000` through `20260731120000` and accepted on staging. Production remains pre-tenant and parked.
- Existing shared catalog: `e10_cards`, `e10_checklists`, `e10_players`, `e10_sets`, and `e10_teams`; A6c.4 makes them member-readable and tenant-mutation deny-by-default.
- Existing tenant inventory: `e10_inventory_items`, movements, reservations, and idempotency receipts. It has no stable product/configuration, supplier, purchasing, lot, physical-copy, listing, customer-transaction, or commercial-event relations.
- Existing market observations: `e10_obs_product_prices` is organization-private competitive evidence, not a shared feed or complete transaction model.
- Accepted constraints: `docs/EXPANSION_FRAMEWORK.md`, `docs/EXPANSION_ACCEPTANCE_CASES.md`, `docs/DOMAIN_MAP.md`, `docs/SECURITY.md`, and the approved product-supply invariants.

## Requirement-to-existing-system matrix

| Requirement | Status | Existing evidence | Required backend delta | Dependency or warning |
|---|---|---|---|---|
| Explicit tenant authority | Verified on staging | `e10_organizations`, memberships, roles, entitlements, `e10.*` predicates, A6c policies | Reuse explicit organization arguments and predicates | Never infer the first membership; production is not migrated |
| Stable product master | Missing | Inventory carries denormalized text; catalog card rows are platform references | Org-owned product master with stable UUID and lifecycle status | Product variant and packaging must remain separate |
| Product configuration and version | Missing | Prototype contracts only | Org-owned configuration plus immutable version rows and identifiers | Historical commercial lines bind a version, not mutable defaults |
| Subject/player identity | Partial | `e10_players` has UUID, name, aliases, sport | Add governed provider mappings and time-aware affiliations later | Existing player rows remain platform catalog references |
| Release/set identity | Partial/conflicting | `e10_sets` has UUID, name, year, sport, brand | Add release identity precision and aliases without destructive replacement | Do not use the PF-M5 heuristic; it omits year |
| Catalog variant identity | Missing | `e10_cards` mixes catalog and copy fields, including `serial` | Separate release-scoped variant and many-to-many subjects | Serial numerator belongs to a physical copy |
| Physical unique copy | Missing | Inventory item text fields approximate copies | Org-owned unique-item record linked to inventory and optional catalog variant | Cards-off must support a non-card fixture |
| Locations and purchasing destinations | Missing | No location relation in the schema snapshot | Active org locations plus permission-scoped eligible-destination query | Location policy is a prerequisite for PO commit |
| Suppliers and offerings | Missing | No supplier relation | Supplier, exact configuration offering, vendor code and currency | Internal IDs, barcodes and vendor codes stay distinct |
| PO, invoice, receipt and credit | Missing | `e10_mutation_receipts` is only an idempotency ledger | Separate versioned commercial objects, lines and allocations | Invoice approval never creates stock; no fabricated PO |
| Last actual purchase cost | Missing | Item `cost` and movement JSON lack eligible historical lookup contract | Derive from accepted receipt/lot evidence with source/date/currency | Unreceived PO price is not last paid; overrides persist |
| Internal/vendor comments | Prototype-only | Memory-only September candidate | Separate org-private comment classes and allowlisted output projection | Internal comments must never enter vendor output |
| Lots and landed cost | Missing | Inventory movements exist, no lot relation | Receipt-linked lots, accepted quantity, quarantine and additive adjustments | Preserve no-item-FK ledger history |
| Reservations against supply | Partial | Show-ref item reservations exist | Add lot-backed confirmed reservations and expected-supply allocations | No overcommit; concurrency boundary is mandatory |
| Idempotent intake and evidence | Partial | Org-scoped mutation receipts exist | Typed intake batch/row staging, fingerprints, review state and corrections | Manual, CSV and native routes use one resolver |
| Commercial lifecycle history | Missing | Inventory movement types cover quantity changes only | Typed immutable events with source, event time, ingest time and correction lineage | Events are atomic with state changes or an outbox |
| Customer retail and break activity | Partial | Break slots/viewers exist; no official customer transaction model | Provisional observations separate from reviewed posted transactions and adjustments | Presence is not watch time; imports must reconcile, not duplicate |
| Reporting and screener | Partial | Bounded inventory reads and catalog indexes exist | Permission-scoped typed query functions, explicit grain, filters, grouping, cursor and drill-down | Apply row filters before aggregation; local data must suffice |
| Valuation, grading and population history | Missing/partial | Catalog grade fields are denormalized | Typed assessments, grade events, population snapshots and versioned valuation runs | Acquisition basis and appreciation are separate |
| AI query/action seam | Missing | No bounded tool contract | Read-only sourced queries and reviewable command drafts using ordinary authorization | No arbitrary SQL, superuser, chatbot or silent action |
| Wishlist and monitoring | Missing/deferred | No relations | Wishlist can be added independently; monitor rules remain deferred | Saving a wishlist item must not schedule a monitor |

## Dependency-ordered execution batches

1. **TA-X1, identity foundation.** Add organization product master, configuration/version, release-scoped catalog variant identity, variant subjects, provider mappings, and generic physical unique-item identity. Preserve existing catalog and inventory tables. Prove tenant isolation, copy-versus-variant separation, multi-subject identity, Cards-off use, and born-locked functions.
2. **TA-X2, location, supplier and offering foundation.** Add active organization locations, location grants, suppliers, supplier offerings and exact configuration identifiers. Add bounded permission-checked reads. Do not yet create accounting events.
3. **TA-X3, purchasing documents and comments.** Add PO, invoice, credit and receipt headers/lines/revisions, explicit allocations, separate internal/vendor comments, source-document identity and duplicate fingerprints. Preserve distinct approval, receipt and payment events.
4. **TA-X4, receipt, lot and reservation writers.** Add accepted/quarantined quantities, lots, landed-cost evidence, expected allocations and lot-backed confirmed reservations. Implement compare-and-set or locking proofs, idempotent RPCs, partial receipt, reversal and no-overcommit tests.
5. **TA-X5, typed intake and lifecycle.** Add intake batches/rows, resolver decisions, immutable commercial events and correction lineage. Connect native/manual/import actions atomically or through a transactional outbox.
6. **TA-X6, customer reconciliation.** Add provisional break/retail observations, reviewed posted transactions, refunds and source reconciliation. Prove that later imports link rather than double-count and that presence remains source-labeled.
7. **TA-X7, reporting contracts.** Add bounded permission-scoped queries with explicit scope/grain, full-dataset filtering, grouping, sorting, cursor pagination, source drill-down and metric definitions. Add grading/population/valuation provenance where the underlying facts exist.
8. **TA-X8, future integration seams.** Add read-only query contracts and reviewable action-draft records. Wishlist may be added independently. Live integrations, scheduled monitors, chatbot behavior and collector showcase remain outside scope.

## Verification required for every batch

- New additive migration files only; never edit an applied migration.
- Local clean replay from baseline, batch-specific tests, existing tenant/RLS regressions, and default-privilege probe.
- RLS on every new public table. No policy may rely on `TO authenticated` without an organization/object predicate.
- `SECURITY DEFINER` functions live behind explicit self-authorization, pinned search path and revoked `PUBLIC`/`anon`; grants are allowlisted.
- Two-organization positive and hostile negative cases, including cross-org IDs supplied directly.
- Idempotency retry, mismatch and concurrent-call tests for every mutator.
- Explicit staging project identity check immediately before each remote write, then explicit staging target. Never use bare remote push while linked to production.
- Exact migration ledger, object census, advisors, CI head and production read-only untouched evidence.
- Batch report distinguishes proposed, implemented locally, applied to staging, independently accepted, and absent from production.

## Genuine escalation boundaries

Stop for owner direction rather than inventing: accounting recognition or payment rules; landed-cost allocation method; over-receipt authority; cross-shop data pooling; provider licensing; automatic financial or price publication; capability namespace replacement; or any request to migrate production. Additive identity fields, explicit source provenance, tenant isolation, idempotency, bounded reads and reviewed-draft seams are within the approved technical scope.
