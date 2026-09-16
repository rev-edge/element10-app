# Product and checklist scope reconciliation

Status: Track A documentation and contract reconciliation, September 16, 2026.
This is a delta to `MODULAR_SCOPE_2026-09-14.md` and
`MODULAR_SCOPE_RECONCILIATION_2026-09-14.md`. It does not authorize schema,
environment, UI, or production changes and does not self-accept any workflow.

Reconciled against canonical source at
`a97fd32bd06af9b555d2232a092b75c2fea93b36`. No database environment was
contacted for this pass. Existing recorded staging evidence through the
vendor-bill series remains unchanged, and no production support is inferred.

## Corrected product boundary

Products is a permanent workspace and the operational home for organization
product releases, configurations, packaging relationships, checklist imports,
organization checklist versions, and checklist maintenance. A Product Master
is the organization-owned release record. Its Product Configurations are the
purchasable or stockable packaging variants. A release can exist without a
checklist or owned stock.

Cards remains the specialist workspace for shared card-catalog browsing,
organization-owned copies, card analysis, valuation, and individual-card
listing preparation. Inventory and Cards operate on the same owned stock.
Navigation location does not define subscription packaging.

The September 14 wording that placed all checklist functionality inside Cards
is superseded only in this respect. Disabling the specialist Cards module must
not, by itself, disable authorized Product/checklist creation or maintenance.

## Existing, partial, missing, and decision-required matrix

| Delta | Status | Current evidence | Required correction |
| --- | --- | --- | --- |
| Product/release as the starting point | Partial | `20260910171106_e10_ta_x1_identity_foundation.sql` defines organization-owned `e10_product_masters`, child `e10_product_configurations`, immutable numbered `e10_product_configuration_versions`, and distinct platform `e10_catalog_releases`. `20260912210000_e10_ta_r5_supported_x1_tenant_writers.sql` provides idempotent create commands for master, configuration, and version. `tests/ta_x1_identity_foundation_test.sql` proves version history, tenant isolation, and catalog/owned separation. | Add governed amend/archive/reactivate commands and bounded readers for the complete Product workspace. Add an explicit, versioned relationship from organization product release/configuration to applicable checklist version or platform release. Do not add a second product hierarchy. |
| Durable checklist-led creation | Missing as an organization workflow; reusable patterns exist | Legacy `e10_checklists` has only name, set, source, cached count, attrs, and timestamps. A6c removes tenant mutation policies from the platform catalog. `20260912171106_e10_schema_review_c1_checklist_promotion.sql` is a one-time, platform-admin promotion of legacy checklist rows, not an upload/review workflow. X8b action drafts demonstrate immutable revisions, provenance, preview, approval, idempotency, and stale-reference checks, but only for purchase orders and customer-transaction drafts. C2 custom fields provide typed definitions/terms/values. | Add organization-owned import sources, batches, sheets/header selections, mapping revisions, row review results, duplicate/conflict decisions, deferred records, checklist drafts, and approved checklist versions. Reuse the X8b revision/idempotency pattern, not its two-operation enum or tables directly. Publication must create no inventory, cost, asking price, reservation, or listing. |
| Meaning of publish | Decision required and current implementation only partially separates authority | The capability registry in `20260912172059_e10_schema_review_c3_capability_catalog.sql` distinguishes organization `catalog.propose` from platform `catalog.review` and `catalog.publish`. A6c makes the five legacy catalog tables tenant-read-only. The current `e10_platform_promote_checklist` uses `e10.is_platform_admin()` and combines promotion into one operation. | Adopt the three-level transition contract below. Ordinary organization users must never overwrite platform catalog rows. Decide organization checklist capabilities and whether platform review and publish require distinct actors or only distinct capabilities. |
| Checklist ownership and module access | Conflicting documentation; backend entitlement mapping is too coarse | A6 has organization module entitlements plus capability checks, but the legacy six module keys all map to the `core` bundle. Current platform checklist rows are shared/read-only; no organization checklist-version object exists. | Assign Product/checklist operational capabilities independently of specialist Cards access. Cards-off must leave authorized Product/checklist maintenance available. Exact commercial bundle keys remain an owner decision; backend authorization must use governed operation capabilities, not navigation visibility. |
| Approval, completeness, and readiness | Partial count primitive; authoritative readiness missing | `20260912172924_e10_schema_review_c5_checklist_count_consistency.sql` transactionally maintains the legacy checklist card count. Product configuration versions have draft/active/retired state. There is no organization checklist draft/approved-version model, deferred-row count, coverage decision, or shared readiness reader. | Add the single readiness/count contract below. Approval, coverage completeness, operational readiness, and pack-odds evidence remain separate facts. Home must show the active approved version and a newer draft simultaneously. |
| Full-grid behavior and preferences | Query principles documented; Product/checklist/import support missing | C2 typed custom fields are queryable relational values with per-field capabilities. Existing reporting readers demonstrate server-side filtering and bounded cursors for other domains. Roadmap requires full-authorized-dataset filtering before pagination. No Product/checklist/import grid readers or durable saved-view/sidebar preference contract was found. | Add typed server query contracts for Products, releases/configurations, checklist versions, and import review. Filters, groups, sorts, aggregates, and export must use the same complete authorized cohort. Add scoped preferences separately from entitlements and permissions. |

## Stage-to-contract mapping

| Operator stage | Existing contract that can be reused | Missing contract |
| --- | --- | --- |
| Upload | Vendor-document work provides durable source, attachment, processing, provenance, and retry patterns. | Checklist-specific source/batch records; immutable file digest; sheet enumeration; selected sheet/header revision; parser version; exact-reimport identity. Vendor bills and checklist imports must remain typed domains. |
| Review product details | Product masters/configurations/versions and X1 idempotent creation writers exist. | Draft product facts labeled extracted, suggested, or manually supplied; existing-release selection; create-within-import proposal; before/after comparison; no product write before approved commit. |
| Review mapping | C2 supplies typed custom-field definitions and terms. Catalog facet governance supplies reviewed color/finish vocabularies. | Per-source-column disposition of mapped, custom field, or excluded; target field identity and type; mixed-set routing; immutable mapping revisions; mapping-change invalidation of affected row review results. |
| Inspect complete resulting checklist | Legacy checklist/card count and platform promotion rows expose basic resolved/unresolved outcomes. | Draft checklist-version projection containing every source row and its disposition; duplicate groups; conflict candidates; deferred rows; excluded rows; errors; corrected values; stable row identities; full-dataset query/read contract. |
| Approve publication | X8b demonstrates revision-bound approval and stale-reference rejection. Platform catalog promotion is idempotent and platform-admin-only. | Organization operational approval distinct from organization overlay publication and platform canonical promotion; exact capability/actor rules; approved-version immutability; approval of only the reviewed mapping and row revision. |
| Maintain approved versions | Product configuration versions demonstrate append-only numbered history. | Organization checklist version lineage, supersession/correction drafts, effective approved version, diff reader, rollback-by-new-version, and simultaneous active-approved plus newer-draft state. |

## Three meanings of publication

The UI must use distinct labels and backend commands for these transitions.

### 1. Approve for organization operational use

- **Owner:** organization.
- **Input:** one reviewed import/checklist draft revision.
- **Actor:** active organization member with a new governed Product/checklist
  approval capability. Prepare and approve capabilities should be separate even
  if v1 role defaults grant both to an admin.
- **Output:** immutable organization checklist version with stable entry IDs and
  an organization-specific applicability link to the product release and, where
  needed, configurations.
- **Effect:** usable by authorized Product, Inventory, preparation, and Cards
  workflows. It creates no owned inventory or commercial facts.

### 2. Publish organization-specific corrections or custom fields

- **Owner:** organization.
- **Actor:** active organization member with `catalog.propose` plus the exact
  custom-field write authority where applicable.
- **Output:** versioned organization overlay/proposal retaining source evidence,
  actor, target canonical identity, and supersession history.
- **Effect:** visible only through organization-authorized overlay readers. It
  does not mutate or masquerade as shared canonical catalog truth.

### 3. Promote into the shared canonical catalog

- **Owner:** platform.
- **Actor:** platform authority only. `catalog.review` and `catalog.publish` are
  platform capabilities and cannot be granted through organization roles.
- **Output:** append-only platform review decision and published canonical
  version or promotion linked back to its organization proposal and evidence.
- **Effect:** changes shared catalog projections only after platform review.
  Ordinary shop approval cannot invoke it.

The existing `e10_platform_promote_checklist` proves a protected platform
promotion path, but it currently combines review and promotion under the broad
platform-admin predicate. It is not the organization approval command and must
not be reused as one.

## Authoritative checklist readiness and count contract

One server-owned reader should supply Products, import review, Home, and other
authorized consumers. It accepts organization, product release, optional
configuration, and an as-of boundary, then returns at least:

- current approved organization checklist version ID, version number, approval
  timestamp, and approver;
- latest draft version ID and number, with `newer_than_approved`;
- source row count and exact counts for mapped, custom-field, excluded,
  deferred, unresolved-conflict, invalid, and approved entries;
- `coverage_status` as `unknown`, `partial`, or `complete`, plus the explicit
  policy/version that produced it;
- applicable configuration IDs and any missing applicability decisions;
- `operational_status` as no checklist, draft only, approved partial, approved
  complete, or approved with newer draft;
- blockers and warnings with stable machine codes;
- a revision/fingerprint suitable for cache and stale-write protection.

The reader must not report "no checklist" when an approved version exists, even
if a corrected draft is newer. A draft never silently replaces an approved
version. Deferred rows count as unresolved coverage unless the future
completeness policy explicitly permits them. Excluded rows remain auditable but
do not automatically count as checklist entries.

What constitutes complete coverage is still an owner/domain decision. Pack odds
require separate evidence and must never be inferred solely from checklist
completeness or card count.

## Small additive implementation sequence

Each increment requires plan approval, local replay, exact-head CI, explicit
staging evidence, and an independent verdict before the next increment. No
applied migration is rewritten.

1. **PC-0, contract decisions:** approve organization checklist ownership,
   capability names/default grants, completeness policy, organization overlay
   visibility, and platform review/publish separation.
2. **PC-1, Product lifecycle:** add missing amend/status commands, complete
   bounded Product readers, and explicit organization product-to-checklist
   applicability. Prove a release without checklist or stock.
3. **PC-2, import provenance:** add source, file digest, parser run, sheet/header
   selection, exact-reimport receipt, and immutable raw-row identity. Identical
   input and settings must replay without new business records.
4. **PC-3, mapping and review:** add versioned column dispositions, custom-field
   targets, mixed-release routing, duplicate/conflict candidates, row decisions,
   deferred records, and dependency fingerprints. Changing a mapping creates a
   new revision and invalidates only affected review results.
5. **PC-4, organization checklist versions:** add draft revisions, full preview,
   revision-bound approval, immutable approved versions, supersession, and
   before/after readers. Publication writes no inventory or commercial records.
6. **PC-5, overlay and canonical seam:** add organization overlay proposals and
   separate platform review/publish decisions. Preserve the existing canonical
   catalog and migrate no organization-private data into it automatically.
7. **PC-6, readiness and grids:** add the authoritative readiness reader,
   full-cohort Product/checklist/import queries, typed filters, aggregates,
   query-bound cursors, permitted export, and separately scoped preferences.
8. **PC-7, UI acceptance:** implement the Products lifecycle and verify Upload
   through maintenance, Home coexistence states, Cards-off access, keyboard and
   responsive behavior, and unchanged Inventory/Cards owned-stock identity.

## Acceptance tests required

- Create a Product release manually with zero configurations, checklist rows,
  and owned inventory; retrieve it from the Products reader.
- Create configurations and packaging versions without requiring a checklist.
- Upload a multi-sheet file, choose a header, route mixed releases, and retain
  file/parser/sheet/header provenance.
- Require every source column to be mapped, custom, or excluded. Reject silent
  omission and type-incompatible custom-field mappings.
- Preserve extracted, suggested, and manual values separately and show their
  before/after review history.
- Change one mapping revision and prove only dependent row reviews become stale.
- Re-import identical bytes with identical settings and prove unchanged
  business IDs, counts, and versions.
- Resolve duplicates as same, different, or deferred with evidence and actor.
- Approve an organization checklist while platform canonical rows remain byte
  and count unchanged.
- Prove an organization member cannot execute platform review or publish.
- Keep approved version N operational while corrected version N+1 is draft;
  Home reports both and never says no checklist.
- Prove partial approval and deferred rows return honest counts/readiness and do
  not imply complete coverage or pack odds.
- With Cards disabled, authorize Product/checklist maintenance while specialist
  Cards operations remain denied.
- Query Product, release, checklist, and import grids with a matching row beyond
  page one; totals, export, and traversal must use the same full authorized
  cohort.
- Revoke capability or module access after task start and prove the final commit
  rechecks authority.
- Prove checklist approval creates zero inventory, acquisition-cost, asking-
  price, reservation, and listing rows.

## Decisions still requiring Trent

- The exact rule and evidence for checklist `complete` status.
- Organization capability names and default role grants for import preparation,
  checklist approval, and maintenance.
- Whether organization operational approval requires maker-checker separation.
- Which organization overlays may be visible outside the organization, if any.
- Whether platform review and platform publish require different people or only
  different capabilities and recorded steps.
- Commercial packaging of Products/checklist functionality versus Cards. The
  safe functional default is that Cards-off does not remove authorized Product
  checklist maintenance.
- Saved-view and sidebar preference ownership: personal, shared workspace, or
  both, including who may publish a shared view.

Existing vendor-bill, receipt, quantity-grain, cost-evidence, and
reviewer/approver work remains valid and is not reopened by this delta.

## Configuration applicability follow-up

The many-to-many Configuration Version to Checklist Version Entry proposal,
including packaging inheritance, immutable effective snapshots, preparation
pinning, reader semantics, migration implications, and unresolved authority
decisions, is reconciled in
`CONFIGURATION_CHECKLIST_APPLICABILITY_RECONCILIATION_2026-09-16.md`. That
document is plan-only and stops before implementation.
