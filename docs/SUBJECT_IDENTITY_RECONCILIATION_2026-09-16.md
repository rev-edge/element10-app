# Subject identity reconciliation

Status: documentation-only clarification and first-slice plan, September 16,
2026. This document does not authorize migrations, deployment, canonical
catalog publication, or production changes.

Reconciled against canonical source at
`73acc48a98d8dc1c11ec64b490207f56cfb32fc7`. No database environment was
contacted. Exact-head CI run `35094423156` is green.

## Decision captured

Subject identity is a first-class, optional relationship. It supports athletes,
Pokémon, trainers, Disney characters, and other recognizable subjects without
forcing every card name or depicted character into a subject record.

An exact catalog variant may have zero, one, or many confirmed subjects. Missing
subject identity never blocks Product creation, checklist import, organization
approval, platform publication, or basic inventory intake. Unresolved source
names remain durable evidence and can be resolved later without changing the
variant identity or any owned-stock history.

Subject identity is separate from card/checklist membership, exact printing or
parallel identity, configuration applicability, and organization-owned copies.

## Existing / partial / missing / conflicting matrix

| Area | Status | Current evidence | Required reconciliation |
| --- | --- | --- | --- |
| Optional zero/one/many subject links | Existing | X1 `20260910171106_e10_ta_x1_identity_foundation.sql` defines `e10_catalog_variant_subjects` with `(variant_id, player_id)` primary key, role, and position. A variant may have no rows or several rows. `tests/ta_x1_identity_foundation_test.sql` proves two subjects on one exact variant. | Preserve the cardinality and stable IDs. Do not add a single `subject_id` column to variants or checklist entries. |
| Subject versus printing identity | Existing | `e10_catalog_variants` is the exact release/printing/parallel identity. Subject links are separate rows. Owned `e10_unique_items` link to variants, not to players as ownership identity. | Continue linking subjects to exact canonical variants where meaningful. Do not derive or merge variant identity from a subject name. |
| Generic subject vocabulary | Conflicting naming, structurally partial | Canonical subject storage is legacy `e10_players` with `name`, `aliases`, and optional sport/team/position/nationality fields. Reporting already calls linked IDs `subject_id` and arrays `subject_ids`. | Treat existing player IDs as stable legacy subject IDs for the first slice, add an explicit subject kind, and make sports fields optional context. Avoid a second canonical identity table until a reviewed compatibility/migration plan justifies it. |
| Multi-subject context | Existing for sports, not generic | X1b `20260911190000_e10_ta_x1b_player_affiliations.sql` records append-only player-team history and per-variant/player depicted-team context. | Preserve sports affiliation as a subject-type-specific extension. Do not require team/league fields for characters, creatures, trainers, or other subjects. |
| Alias and external-ID matching | Partial | `e10_players.aliases` is a mutable text array. X1 `e10_catalog_identity_mappings` supports versioned provider IDs for `entity_kind='player'`. F4 adds evidence-backed ambiguity cases and candidates. | Add governed append-only subject aliases and appropriately scoped external identifiers. Matching uses alias plus release/product/publisher/year/franchise/language/role and provider context. Similar name alone never confirms a match. |
| Ambiguity review | Partial and platform-only | F4 `20260912093000_e10_ta_f4_identity_ambiguity_review.sql` is platform-admin-only, requires 2-20 existing player candidates, and supports propose/reject only. Its own contract says no approval, canonical link, merge/split, or automatic generation. | Generalize proposals to subject kind, allow unresolved mentions with zero candidates, add reviewed resolution/link and no-match outcomes, and retain stale-revision/idempotency protection. Platform publication remains platform-authorized. |
| Organization-private unresolved names | Missing | The planned checklist-import lifecycle retains raw source rows, but no current subject-mention or private candidate relation exists. | Add organization-owned unresolved mentions linked to checklist-version entries/import rows, with raw name, context, evidence, candidates, status, and resolution lineage. These records cannot mutate platform subject or variant rows. |
| Cross-product subject reporting | Substantially existing for confirmed platform links | X7d.2 migration `20260911170045_e10_ta_x7d2_catalog_entity_projection.sql` emits `subject_ids`; screener cohorts filter and group by `subject_id`. `tests/ta_x7d2_cross_product_rookie_psa9_test.sql` proves one subject across multiple releases/variants and rejects the wrong subject. | Generalize labels/readers beyond sports naming, add subject metadata and coverage counts, and show unresolved mentions separately. Preserve full-authorized-dataset and bounded-query contracts. |
| Owned inventory and business joins | Partial | Owned copies link to catalog variants; X7d distinguishes catalog, owned, and completed-sale evidence and enforces organization-scoped readers. | Join confirmed subjects through variant identity. Catalog counts may include owned and unowned variants; owned/business facts must be restricted to the authorized organization and must expose coverage/unknowns. |
| Multi-subject totals | Conflict risk | Subject grouping expands one variant/observation across each linked subject. That is correct for inclusive discovery but can double-count if rows are summed across subjects. | Define inclusive subject reporting separately from financial attribution. Overall totals deduplicate by authoritative fact ID. No revenue/margin allocation is implied by subject membership. |

## Proposed identity and relationship semantics

### Stable canonical subject

For the first implementation slice, preserve `e10_players.id` as the physical
stable canonical subject ID. Additive metadata may broaden it with a governed
`subject_kind`, for example athlete, character, creature, trainer, personality,
team/group, or other. Exact allowed kinds require review. Existing sports fields
remain optional type-specific context.

New APIs and readers should use the neutral term `subject_id`. Existing
`player_id` signatures and foreign keys remain compatibility seams until a
separate contract migration is approved. Do not fork existing athletes into a
new subject table merely to improve naming.

### Confirmed variant link

- One canonical subject may link to many exact variants.
- One exact variant may link to zero, one, or many canonical subjects.
- Each link carries a role and position plus reviewed evidence/history.
- A role describes depiction or relevance, not financial ownership or revenue
  attribution.
- Link corrections are append-only reviewed decisions. They do not edit variant
  identity, checklist membership, or owned-copy history.

The existing `e10_catalog_variant_subjects` relation provides the cardinality,
but its direct rows lack reviewed decision lineage. A future additive writer
should make the effective link a reviewed projection while preserving existing
IDs and compatibility.

### Unresolved organization mention

An organization import may create a private `SubjectMention` tied to the exact
source row and organization checklist-version entry. It retains:

- raw and normalized source name;
- optional source role;
- product/release, publisher, year/season, franchise/sport, language, card
  number, and other relevant context;
- source file/row and mapping revision;
- zero or more candidate subject IDs with evidence and confidence category;
- status: unresolved, proposed match, confirmed private link, submitted to
  platform, resolved by platform, rejected, or superseded;
- actor, reason, revision, and idempotency evidence.

No candidate is a valid outcome. The import and checklist entry remain usable.
Later resolution attaches the stable subject ID through a new decision and does
not recreate the card, exact variant, checklist entry, or owned copy.

### Matching contract

Candidate generation may use:

- reviewed aliases and transliterations;
- provider plus entity namespace plus external identifier;
- subject kind;
- product/release, publisher/manufacturer, year/season, sport/franchise, team,
  language, edition, and depicted role;
- existing reviewed variant-subject context.

Exact scoped external-ID agreement may be strong evidence. Similar display name
alone is never sufficient for automatic confirmation. Candidate scores are
suggestions, not authority. Conflicting strong identifiers, incompatible subject
kinds, or context mismatch must remain unresolved for review.

Aliases and external identifiers need append-only assert/revoke/supersede
history. A mutable alias array is insufficient as publication evidence.

## Ownership and authority

- Canonical subjects, canonical aliases/external IDs, and canonical
  variant-subject links are platform catalog data.
- Organization subject mentions, candidates, private resolutions, and overlays
  are tenant-owned and tenant-isolated.
- `catalog.propose` may support organization-private proposals and submission to
  platform. It does not authorize canonical subject creation or canonical link
  publication.
- Platform `catalog.review` and `catalog.publish` remain platform-only and cannot
  be granted through organization roles.
- The current F4 functions use `e10.is_platform_admin()` and lack an approval or
  link transition. A later plan must decide how the registered platform review
  and publish capabilities map to distinct commands and whether separate actors
  are required.

Missing subject linkage never blocks organization checklist approval. Platform
catalog publication may publish a variant with no subject when evidence is
insufficient, while retaining unresolved source mentions outside canonical
truth.

## Reporting contract

### Inclusive subject reporting

A subject reader should return all confirmed canonical variants and checklist
entries for that subject across products, releases, years, publishers,
languages, and editions, whether the variants are owned or unowned.

For an authenticated organization it may additionally return authorized:

- owned-copy and available-quantity counts;
- acquisition and actual-cost coverage;
- listing/sale counts and other business metrics;
- coverage timestamps, source scope, and unknown/unmatched counts.

Catalog facts remain platform-scoped. Owned inventory and commercial facts are
joined only within the requested organization after active membership and exact
capability checks. An organization must not infer another organization's stock,
cost, listing, customer, revenue, or margin.

### Coverage and unresolved results

Readers report confirmed-link counts separately from unresolved mention counts.
Unresolved records appear in an organization-authorized review/coverage section,
not mixed into canonical subject results. Coverage status must disclose that
missing links can make subject totals incomplete.

### Multi-subject aggregation

Inclusive subject reporting intentionally places the same variant under each
confirmed subject. Overall totals must deduplicate by their authoritative grain:
variant ID, owned-copy ID, inventory fact ID, commercial-event component ID, or
other declared metric fact ID.

Subject membership does not allocate revenue, cost, or margin. Until Trent
selects an attribution policy, subject financial reports should provide:

- inclusive event/fact presence, clearly labeled non-additive across subjects;
- deduplicated overall totals outside subject grouping;
- no summed subject shares that claim to reconcile to overall financial totals.

Potential future methods include primary-subject attribution, equal allocation,
manual weights, or no attribution. The selected method must be versioned,
metric-specific, and preserve the original unallocated fact.

## First implementation slice

The first slice should prove useful reporting without exhaustive cataloging:

1. Add a governed subject-kind seam to existing stable player/subject IDs.
2. Add append-only reviewed aliases and scoped external identifiers.
3. Add organization-private unresolved subject mentions for checklist-import
   entries, with zero-or-more evidence-backed candidates.
4. Add a platform-reviewed resolution command that can link a mention to an
   existing canonical subject and exact variant without recreating either.
   Canonical subject creation remains a separate platform-authorized command.
5. Extend the existing subject reader/screener contract to return neutral subject
   metadata, cross-product variants, confirmed coverage, unresolved coverage,
   and organization-scoped owned counts.
6. Demonstrate at least one athlete and one non-sports subject across multiple
   releases/products, including one multi-subject variant and one unresolved
   source name.

This slice does not require every depicted person or character to be cataloged,
does not require organization users to publish canonical subjects, and does not
implement financial attribution.

## Acceptance scenarios

1. A sports subject appears on exact variants in two products and two release
   years; one bounded query returns all confirmed variants.
2. A Pokémon or character subject uses the same stable relationship without
   sport/team fields and appears across multiple releases.
3. A checklist entry and variant with no subject publish and remain usable.
4. One exact variant links to two confirmed subjects. It appears in both subject
   result sets, while deduplicated overall variant/owned/sale totals count it
   once.
5. Two different subjects share the same normalized name. Name-only matching
   confirms neither; contextual or scoped external-ID evidence is required.
6. An unknown source name is retained with no candidates. Product creation,
   checklist approval, applicability review, and basic intake still succeed.
7. Resolving that mention later links the existing variant and leaves checklist,
   owned-copy, acquisition, cost, reservation, and sale IDs unchanged.
8. An organization proposes a private match but cannot create or alter a
   canonical subject/link. Platform review/publish remains required.
9. A subject report includes unowned catalog variants and authorized owned-copy
   counts for organization A, returns no organization B business facts, and
   discloses unresolved coverage separately.
10. Exact replay returns the same mention/decision/link result; changed replay
    fails; stale or concurrent resolution cannot create duplicate effective
    links.

## Open product decisions

1. Approved `subject_kind` vocabulary and whether teams/groups are subjects or a
   separate linked entity.
2. Whether an organization may confirm a private subject link for its own
   overlay, or only propose one pending platform resolution.
3. Whether platform review and canonical publication require different people,
   not merely different capabilities and recorded steps.
4. Which alias and external-ID namespaces qualify as strong evidence for each
   subject kind.
5. Whether a canonical subject can intentionally represent a fictional persona,
   costume/character appearance, duo/group, or only individual entities.
6. Financial attribution method for multi-subject cards. Safe default: none.

## Documentation impact on configuration applicability

Configuration applicability remains entry/variant-based. A subject link neither
makes a card applicable nor changes packaging composition. Applicability readers
may offer subject filters only over confirmed links and must expose unresolved
coverage. A later subject resolution may improve prospective filtering but must
not rewrite a confirmed historical applicability snapshot or Prepared version.

Stop after review. No implementation begins until explicitly approved.
