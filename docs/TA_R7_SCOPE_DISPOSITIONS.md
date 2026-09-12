# TA-R7 scope dispositions

Status: owner decisions and integration constraints, 2026-09-12. These are not claims that deferred schema is already enforced.

## SCOPE-1 supported X1 writers

Closed in R5. Tenant product/configuration/version/unique-item creation is capability-scoped. Platform release/variant/subject/provider-mapping curation is platform-admin scoped. Historical configuration meaning and mapping revisions are immutable.

## SCOPE-2 location-scoped cost privacy

Decision for v1: actual commercial cost remains organization-scoped and requires `financial.actual_cost.read`; admin receives the default grant. Location membership is not used as a cost boundary. Non-admin location access stays explicit, but it does not imply cost access. A later sub-organization privacy design must introduce a first-class cost scope before streamer-specific commission or location-private cost can ship. It must not be simulated with JSON or UI filtering.

## SCOPE-3 maker-checker

Decision: capability separation alone is insufficient for approval. Invoice approval and any revision-bound over-receipt approval require a different actor from the actor who submitted the revision. Existing workflows that do not persist both identities remain pre-production and must fail closed when this rule becomes applicable. Admin emergency override, if ever allowed, requires a separately named capability and append-only reason evidence; it is not implicit in admin status.

## SCOPE-4 legacy inventory and lots

The lot model is authoritative for location, custody bucket, reservation, receipt, and cost provenance. Legacy item quantity remains a compatibility aggregate until its callers are inventoried. A production cutover must either route every legacy mutator through the lot writer or revoke it. Reporting must not combine independently mutable legacy quantity with lot quantity as two sources of truth. No legacy API is removed in this checkpoint because the current client compatibility inventory is not yet complete.

## SCOPE-5 quantity granularity

Current evidence: configuration versions store `base_unit` and positive numeric `base_units_per_package`; PO, receipt, lot, and reservation quantities are numeric. There is no configuration-level divisibility rule. Required additive shape before general receiving ships: immutable `quantity_increment numeric` on each configuration version, finite and greater than zero. Card, copy, and `each` configurations use `1`; divisible goods use an explicitly approved increment. Every purchasing, receipt, lot, reservation, disposition, and correction writer must enforce `quantity / quantity_increment` is integral. Existing rows require an explicit backfill mapping before `NOT NULL`; no heuristic based only on a free-text unit is approved.

## SCOPE-6 evidence quality

`operator_asserted` is not approved-invoice actual cost. `imported_unreviewed` is never promoted by ingestion alone. Actual cost applies only to quantities supported by approved invoice allocation evidence; unmatched quantities remain visibly provisional or unknown. Freight, credits, rebates, and corrections append evidence. Recalculation may not rewrite prepared snapshots, committed sales, or prior audit facts. A later migration must give actual-cost evidence an explicit source/review basis and reject imported claims of `reviewed_import` unless a reviewed transition supplies the reviewer and source lineage.

## SCOPE-7 legacy grants

R7 removes `TRUNCATE` from `anon` and `authenticated` on every public table because it bypasses RLS and is not a supported client operation. Existing row-level mutation grants remain temporarily where the compatibility inventory is incomplete; RLS still governs them. R8 must publish the remaining grant census and map each retained grant to a supported endpoint or mark it for cutover removal.

## SCOPE-8 staging ledger and merge strategy

Applied migrations are append-only and are never renamed or rewritten. Staging application uses an explicit staging database URL or project identifier after a target-identity probe. A bare remote push is prohibited while the CLI is linked to production. Merge review must compare the repository migration list, staging ledger, exact commit, and per-migration checksums. Any filename collision is resolved with a new later migration, preserving both ledger histories. Production remains read-only until the separately approved cutover.

## Additional owner rulings

- Provider/manual intake deduplication is conservative: stable connected source-event identity deduplicates automatically; manual or connection-less equal fingerprints remain distinct observations until a reviewed equivalence decision links them.
- Serial and print-run values describe evidence at different grains. Variant print-run denominator is catalog-level; observed serial numerator belongs to the unique physical item. Neither alone establishes global uniqueness without issuer/release provenance.
- Identical command replay is capability-authorized within the same active organization, as recorded in the R6 evidence. It is not cross-organization and does not rewrite the original actor.
