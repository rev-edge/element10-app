# Configuration-to-checklist applicability reconciliation

Status: investigation, contract proposal, and implementation plan only,
September 16, 2026. This document authorizes no migration, deployment, or
production change and does not self-accept the proposal.

Reconciled against canonical source at
`be6808b4056ad1be97874497339a0a8290b7849c`, the approved product supply model,
the September 16 Product/checklist lifecycle delta, and committed migrations and
tests. No database environment was contacted in this pass.

## Conclusion

The proposed many-to-many model agrees with the approved conceptual contract:
checklist source/version belongs to the release, applicability to configurations
is explicit, and each ProductRequirement pins the applicable ChecklistForUse
version. The physical backend does not yet implement organization checklist
versions, configuration applicability, ProductRequirements, or Prepared
snapshots.

Applicability must bind one exact organization checklist version to one exact
immutable configuration version. Confirmation produces an immutable effective
snapshot. Inheritance pins another confirmed snapshot and never follows a
mutable "current" pointer. Missing entry decisions resolve to unknown, never to
excluded. Applicability creates no inventory, quantity, cost, reservation,
listing, or canonical catalog identity.

## Existing / partial / missing / conflicting matrix

| Contract area | Status | Evidence | Reconciliation |
| --- | --- | --- | --- |
| Organization product release and configuration hierarchy | Existing | `20260910171106_e10_ta_x1_identity_foundation.sql` defines organization-owned Product Masters, child Product Configurations, and immutable numbered Configuration Versions. `20260912210000_e10_ta_r5_supported_x1_tenant_writers.sql` supplies idempotent creation commands. | Keep this hierarchy. Product Master is the organization release; applicability targets Configuration Version, not a new product/configuration tree. |
| Immutable configuration history | Existing | `20260912203000_e10_ta_r5_immutable_identity_history.sql` prevents deletion and content mutation of configuration versions and permits only draft to active/retired and active to retired transitions. `tests/ta_r5_immutable_identity_history_test.sql` proves the guard. | Do not add mutable applicability columns to `e10_product_configuration_versions`. Version applicability separately and pin it wherever history matters. |
| Platform release, exact variant, and checklist entry identity | Existing but platform-oriented | X1 defines `e10_catalog_releases` and exact `e10_catalog_variants`. C1 `20260912171106_e10_schema_review_c1_checklist_promotion.sql` adds platform `e10_catalog_checklist_entries` linked to legacy checklist/card rows and canonical variants. | Reuse canonical identities. Organization applicability references approved organization checklist-version entries that in turn reference canonical entries/variants when known. It never clones canonical variants. |
| Release-owned checklist versions | Missing physically | `PRODUCT_SUPPLY_MODEL.md` section 10 says source/version belongs to the release. Legacy `e10_checklists` is an unversioned shared catalog table. `PRODUCT_CHECKLIST_SCOPE_RECONCILIATION_2026-09-16.md` records the missing organization version lifecycle. | Applicability depends on the planned organization checklist-version model. It must not attach directly to mutable legacy checklist rows. |
| Many-to-many configuration applicability | Missing | No applicability or composition relation exists in committed migrations. Current catalog variants have no configuration field, which is correct for canonical identity. | Add versioned organization applicability reviews/snapshots and entry decisions. Do not add `configuration_id` to card/catalog identity. |
| Included, excluded, unknown versus proposed, confirmed | Missing | C1 promotion rows distinguish resolved/unresolved facet mappings, but not configuration applicability or review status. | Store applicability conclusion and review state as independent dimensions. An absent decision is effective unknown; explicit unknown may retain evidence and rationale. |
| Packaging composition and inheritance | Partial, conceptual only | Configuration versions store `packaging_kind`, `base_unit`, `base_units_per_package`, and immutable quantity increment. `PRODUCT_SUPPLY_MODEL.md` requires versioned conversions such as boxes per case and packs per box. No parent/child configuration relation or conversion version exists. | Add explicit, acyclic, version-pinned composition revisions. Identical-content inheritance and mixed composition require different semantics. Quantities stay in composition, not applicability. |
| Ordering and receiving while applicability is unknown | Existing behavior is compatible | PO and source-neutral receipt writers require an active `configuration_version_id`; they do not require a checklist. `tests/ta_x4e_receipt_batch_test.sql` proves source-neutral and invoice-only receipt behavior. | Preserve this independence. Unknown applicability is a limitation for applicability-dependent preparation/display only, not a purchasing or receiving blocker. |
| Owned-card provenance | Partial and compatible | `e10_unique_items` optionally links a physical copy to `catalog_variant_id`; lots, receipts, and inventory items link to configuration versions where applicable. Singles can exist with no catalog variant or source configuration. | Add only an optional provenance association from an owned copy/acquisition fact to source configuration/version when known. Never require it for singles intake or use it as ownership identity. |
| Preparation pinning and invalidation | Approved design, not physically implemented | `PRODUCT_SUPPLY_MODEL.md` sections 1, 7a, and 10 require each ProductRequirement to pin ChecklistForUse; changing the pin or substituting configuration is preparation-critical. `D3_INPUT_CONTRACT.md` requires immutable Prepared vN and atomic stale/invalid checks at Start Live. No physical ProductRequirement or Prepared tables exist. | A ProductRequirement must pin checklist version plus confirmed applicability snapshot. New checklist/configuration/applicability revisions invalidate only affected unexecuted preparation. Issued historical snapshots remain immutable. |
| Authorization and ownership | Partial; new organization authority undecided | Registry contains organization `catalog.read`, `catalog.propose`, `custom_fields.read/write`, and platform-only `catalog.review`/`catalog.publish`. X1 product writers currently use `catalog.propose`. A6c removes tenant catalog mutation policies. | `catalog.propose` can authorize draft proposals, not confirmation by assumption. No current organization capability authorizes applicability confirmation. Trent must approve a capability and role defaults. Platform publication remains platform-only. |
| Full-dataset readers and bulk scope | Missing for this domain | Roadmap requires server filtering/aggregation before paging. Existing X7/X8 readers demonstrate bounded, query-bound patterns in other domains. No Product/checklist applicability reader exists. | Add configuration-scoped and checklist-scoped readers with stable cursors, exact counts, and explicit selected IDs versus all-filtered query fingerprints. |

## Proposed relationships

Names below are planning labels, not approved migration identifiers.

### Checklist membership

1. `OrgChecklistVersion` belongs to one organization Product Master/release and
   is immutable after approval.
2. `OrgChecklistVersionEntry` belongs to that exact version. It has a stable ID,
   preserves source/import lineage, and optionally references a platform
   `ChecklistCatalogEntry` and exact `CatalogVariant`.
3. A new checklist version creates new version-membership rows or immutable
   lineage references. It does not mutate an approved version.

### Configuration applicability review

1. `ConfigurationApplicabilityReview` is organization-owned and binds exactly:
   organization, Configuration Version, Org Checklist Version, review revision,
   basis, and status.
2. Basis is one of:
   - `release_wide_proposal`: propose the checklist version's whole entry set;
   - `inherited_snapshot`: start from one or more pinned confirmed source
     applicability snapshots;
   - `explicit_selection`: begin with reviewed entry decisions;
   - `unknown`: no applicability conclusion yet.
3. `ConfigurationApplicabilityDecision` is append-only per review revision and
   checklist-version entry. It separates:
   - `applicability`: included, excluded, or unknown;
   - `decision_state`: proposed or confirmed;
   - `content_role`: potential pull or guaranteed component, only where included;
   - source evidence, reason, actor, and superseded decision linkage.
4. Missing decision rows are read as unknown and unreviewed. They are never read
   as excluded.
5. Confirmation materializes an immutable
   `ConfigurationApplicabilitySnapshot` and effective snapshot entries for the
   complete checklist version. This supports stable counts, historical pins,
   and bounded readers without recomputing old inheritance against new data.

The confirmed snapshot must contain an outcome for every entry in the pinned
checklist version, including effective unknowns. That makes later additions to a
new checklist version visible as unresolved rather than silently included.

### Packaging composition

Packaging composition is separate from card applicability.

1. A versioned `ConfigurationComposition` binds one parent Configuration Version
   to child Configuration Versions and quantities in labeled units.
2. `identical_container` means a parent such as a case contains N identical
   units of one child box version. It may propose applicability inheritance from
   a pinned confirmed child snapshot.
3. `mixed_bundle` means the parent contains two or more potentially different
   child configuration versions. Its proposed pool is the union of pinned child
   snapshots with source attribution retained. It is not treated as equivalent
   to any one child.
4. Guaranteed promos/components use a separate versioned composition fact with
   entry identity, quantity, and unit. A guaranteed quantity is not stored in
   the applicability decision and does not imply pull odds.
5. Case/box/pack edges must be acyclic. Writers lock a deterministic
   organization/product topology guard, rerun a recursive cycle check after the
   lock, and reject self-links or paths back to the parent.
6. Composition revisions and confirmed applicability snapshots are immutable.
   A source change creates a new proposal/revision. Historical snapshots keep
   their pinned component and source snapshot IDs.

### Platform and organization evidence

- Platform canonical identities and any future platform-published applicability
  evidence are platform-owned.
- Organization imports, applicability proposals, confirmations, overrides, and
  evidence are organization-owned and tenant-isolated.
- The current catalog has no platform packaging/configuration archetype to which
  platform applicability can safely attach. Until that identity seam is
  designed, platform evidence may be cited as source evidence but organization
  confirmation targets the organization Configuration Version.
- Ordinary organization actions never update platform catalog rows.

## State transitions

### Review lifecycle

`draft -> proposed -> confirmed -> superseded`

- Draft revisions may be amended additively through new revisions.
- Proposed means ready for review but not authoritative.
- Confirmed requires the approved organization capability, exact expected review
  revision, unchanged checklist-version fingerprint, unchanged configuration
  version, unchanged pinned inheritance snapshots, and a final authority recheck
  after locks.
- Confirmed snapshots are immutable. Correction creates a successor review and
  snapshot; it never edits the old one.
- Superseded means a newer confirmed snapshot is current for prospective work.
  Historical ProductRequirements and Prepared snapshots keep their old pins.

### New configuration

Creation remains valid with applicability unknown. The operator may select one
of four proposal bases:

1. release-wide pool, explicitly proposed and then reviewed;
2. inheritance from a matching configuration's pinned confirmed snapshot;
3. an explicitly selected set of entries;
4. unknown, with no fabricated decisions.

The existing configuration creation command should remain backward compatible.
A separate applicability-proposal command follows it. A future orchestration API
may make both atomic, but it must preserve separate records and idempotency.

### New checklist version or source change

- Create a new immutable checklist version.
- Create new applicability review drafts for relevant active Configuration
  Versions or report that they are missing.
- Carry forward prior decisions only as proposals with lineage. Newly introduced
  entries are unknown/unreviewed. Removed entries remain in historical snapshots
  and are absent from the new version, not rewritten as exclusions.
- Mapping/source changes invalidate only decisions whose dependency fingerprint
  changed. Confirmation of a stale review fails.

### Preparation

Each ProductRequirement pins:

- Configuration Version;
- Org Checklist Version, when applicable;
- confirmed Configuration Applicability Snapshot;
- any required composition revision;
- inventory reservation/cost evidence already required by the supply model.

Unknown applicability does not block sealed ordering or receiving. It does block
or limit only features whose declared policy requires confirmed applicability,
such as configuration-scoped card preparation, checklist-based slot design, or
claims that a card can be pulled from that configuration. Readiness must name
the limitation rather than collapsing it into missing inventory or no checklist.

Changing any pin before Live invalidates the affected Prepared version and
requires a successor. After Live, old Prepared and execution evidence remains
unchanged. Start Live rechecks the exact Prepared approval and applicability
pins; a current-but-different snapshot is not a substitute.

## API effects

### Existing writers

- Keep `e10_org_create_product_master`,
  `e10_org_create_product_configuration`, and
  `e10_org_create_configuration_version` signatures unchanged.
- Do not add checklist requirements to PO, invoice, receipt, lot, reservation,
  unique-item, or singles-intake writers.
- Do not extend `e10_platform_promote_checklist` into an organization writer.

### Additive writers to plan

- create/amend/submit applicability review;
- bulk propose entry decisions with explicit selection scope;
- confirm applicability review into one immutable effective snapshot;
- supersede/correct through a successor review;
- create/confirm composition revision with cycle protection;
- record guaranteed components separately;
- optionally adopt platform evidence as organization proposal evidence without
  copying or changing canonical identity.

Every writer must use organization-scoped idempotency receipts, changed-replay
rejection, expected revisions, deterministic lock ordering, post-lock authority
and dependency rechecks, append-only audit facts, and born-locked function ACLs.

### Readers

1. **Checklist grid:** one row per checklist-version entry with an `Available
   in` aggregate containing only configurations the actor may read. It reports
   confirmed included, confirmed excluded, unknown/unreviewed, and proposed
   separately.
2. **Configuration checklist grid:** exact Configuration Version plus Checklist
   Version and selected snapshot/review. It returns effective status, decision
   state, content role, inheritance origin, evidence coverage, and guaranteed
   quantity where independently recorded.
3. **Readiness:** distinguishes checklist unavailable, applicability unknown,
   review proposed, confirmed partial/complete, and stale/superseded pins.
4. **Bulk review:** request declares either `selected_ids` or `all_filtered`.
   All-filtered carries a typed normalized query and query fingerprint; the
   server reruns authorization/filtering over the full cohort before locking.
   A loaded page is never the selection set.

Readers require stable sorting, bounded pagination, query-bound cursors, full
authorized-cohort counts, explicit unknowns, and no leakage of another
organization's proposals or evidence.

## Entitlement and capability effects

The actual registry currently provides:

- organization: `catalog.read`, `catalog.propose`, `custom_fields.read`, and
  `custom_fields.write`;
- platform only: `catalog.review` and `catalog.publish`.

`catalog.propose` is the existing authority used by Product/configuration create
writers and is suitable for draft applicability proposals. It does not clearly
authorize organization confirmation. Do not reuse platform `catalog.review` or
`catalog.publish`; the registry prevents tenant grants for those keys.

Required owner decision: either approve a new organization capability for
applicability confirmation, with explicit default role grants, or explicitly
declare which existing organization capability carries that authority. The safe
interim behavior is proposal-only and fail-closed confirmation.

Product/checklist applicability belongs to the Products workflow and must not be
implicitly denied when specialist Cards is disabled. Commercial packaging and
the exact Product entitlement key remain unresolved. Every commit rechecks both
the applicable entitlement and capability independently.

## Migration and backfill implications

- Add new migrations only. Do not edit X1, C1, C2, C3, C5, R5, or applied A6
  migrations.
- Add organization-owned, RLS-enabled private tables for review, decisions,
  snapshots, composition, guaranteed components, command receipts, and audit.
  Prefer service-only tables behind reviewed RPCs; do not expose privileged
  SECURITY DEFINER functions through default PUBLIC execution.
- Lead tenant indexes and foreign keys with `organization_id`. Use composite
  tenant FKs for every organization-owned relationship.
- Index the principal reader paths: organization plus checklist version plus
  entry; organization plus configuration version plus snapshot; current review
  status; and composition parent/child traversal.
- Existing configurations backfill to no applicability snapshot, meaning
  unknown. Do not manufacture release-wide inclusion or exclusions.
- Existing platform checklist promotion remains canonical evidence. It is not
  backfilled as organization confirmation unless an explicit reviewed adoption
  command is later run.
- Existing owned singles and inventory rows receive no required source
  configuration. Optional provenance is additive only.
- Existing preparation is design-only, so there is no Prepared-row backfill.
  When built, it must require explicit pins for applicability-dependent paths.
- Before any future apply: local replay, concurrency tests, ACL/RLS tests,
  advisors, exact-head CI, explicit staging target, environment-qualified
  evidence, and independent review. Production remains a separate go/no-go.

## Open product decisions

1. Which organization capability confirms applicability and which system roles
   receive it by default?
2. Does organization confirmation require maker-checker separation, or may one
   suitably authorized user propose and confirm with an explicit audit label?
3. What exact evidence threshold permits `confirmed` rather than `proposed`?
4. Does "release-wide pool" mean all entries in the selected organization
   checklist version, and can that basis be confirmed in bulk without reviewing
   every exception individually?
5. What distinguishes identical-content inheritance from similar packaging in
   operator terms, and who may assert it?
6. For mixed bundles, should parent readiness require every child snapshot to be
   confirmed, or may the parent have explicit unknown components?
7. Are guaranteed promos expressed per package, per case, or both, and how are
   variable/random promo assortments represented without implying guarantee?
8. Is a platform packaging/configuration archetype required for reusable
   platform-published applicability evidence? No such identity exists today.
9. Which applicability-dependent features fail closed, and which remain usable
   with an explicit unknown/partial warning?
10. What exact Product module entitlement governs these operations? It must be
    independent of specialist Cards presentation.

## Small sequenced implementation plan

1. **CA-0, decisions and contract lock:** resolve the ten product decisions,
   capability/default grants, and platform packaging identity seam. Review this
   document without schema work.
2. **CA-1, checklist-version prerequisite:** implement the previously planned
   organization checklist versions and stable version entries, including source
   lineage and approval, before applicability.
3. **CA-2, composition:** add immutable composition revisions, child quantities,
   guaranteed components, acyclic writer, history reader, and concurrency proof.
4. **CA-3, applicability drafts:** add reviews, append-only decisions, four basis
   modes, evidence, dependency fingerprints, idempotency, and proposal readers.
5. **CA-4, confirmation snapshots:** add revision-bound confirmation, complete
   effective snapshot materialization, stale rejection, successor correction,
   and final-lock authorization tests.
6. **CA-5, readers/readiness:** add checklist and configuration grids,
   full-cohort counts/filtering, explicit bulk scope, and readiness states.
7. **CA-6, preparation pins:** when ProductRequirement/Prepared persistence is
   implemented, pin exact checklist, applicability, composition, reservation,
   and approval versions and prove invalidation/history behavior.
8. **CA-7, staging review:** apply each approved increment through the guarded
   staging path, audit evidence at every boundary, and stop before production.

## Acceptance scenarios

1. **Shared base entry:** one checklist-version entry is confirmed included for
   Hobby and Retail Configuration Versions. It has one canonical identity and
   two organization applicability relationships, with correct Available-in
   counts.
2. **Configuration-exclusive parallel:** a parallel is confirmed included for
   Hobby and confirmed excluded for Retail, with independent evidence. Missing
   decisions for a third configuration read unknown, not excluded.
3. **Identical case inheritance:** a Case Version explicitly contains 12 of one
   Box Version and inherits a pinned confirmed box snapshot. Later box changes
   do not mutate the case snapshot; a successor case review is required.
4. **Packs plus guaranteed promo:** the pack pool records potential pulls. A
   separate guaranteed-component fact records one promo per box. Neither fact
   invents pull odds or owned inventory.
5. **Unknown but purchasable:** a sealed Configuration Version with unknown
   applicability can be ordered, invoiced, received, costed, and reserved.
   Configuration-card preparation reports applicability unknown and does not
   claim a pool.
6. **Later configuration:** adding Retail to an approved release creates no
   confirmed applicability by default. An explicit release-wide, inherited,
   selected, or unknown proposal must be reviewed.
7. **New checklist version:** a successor checklist version carries old
   decisions only as lineage-backed proposals; new entries are unknown. The old
   confirmed snapshot remains readable and pinned history is unchanged.
8. **Preparation stability:** Prepared vN pins exact configuration, checklist,
   applicability, and composition versions. A later confirmed snapshot
   invalidates affected unexecuted preparation but never rewrites Prepared vN
   or completed execution. Approval against a stale review fingerprint fails.
9. **Replay and concurrency:** identical idempotent replay returns the same
   review/snapshot IDs. Changed replay fails. Two concurrent confirmations yield
   one confirmed snapshot and no duplicate `(snapshot, entry)` relationships;
   the loser receives the deterministic committed result or conflict.
10. **Owned single without origin:** an owned single links to its catalog variant
    with no source Configuration Version. Intake, ownership, cost, and history
    remain valid; configuration provenance stays unknown.
11. **Tenant/platform boundary:** cross-organization reads and writes fail;
    organization confirmation changes no platform catalog row; tenant actors
    cannot use platform review/publish authority.
12. **Bulk scope:** selected-row review changes exactly the supplied authorized
    IDs. All-filtered review applies the server-recomputed full query, including
    matches beyond page one, and rejects a stale query/revision fingerprint.

Stop after review of this plan. No implementation begins until explicitly
approved.

## Subject identity clarification

Subject identity is optional and many-to-many at the exact catalog-variant
level. Missing links do not block Product, checklist, applicability, or basic
inventory workflows. Confirmed subject links may filter applicability readers,
but they do not determine applicability, packaging composition, pull odds, or
financial attribution. See `SUBJECT_IDENTITY_RECONCILIATION_2026-09-16.md` for
the current player/subject evidence, unresolved-name path, authority boundary,
reporting rules, and first implementation slice.
