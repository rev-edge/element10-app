# Checklist ingestion and optional subject linking

Status: investigation and documentation only, September 16, 2026. This
document does not authorize application code, migrations, deployment, catalog
publication, or production changes.

Reconciled against repository head
`73acc48a98d8dc1c11ec64b490207f56cfb32fc7`. Exact-head CI run `35094423156`
was green. No database environment was contacted.

## Executive contract

The operator lifecycle is:

1. Select a source.
2. Confirm product and release details.
3. Review the parser and field mapping.
4. Review the complete prepared record set.
5. Save or approve an organization-owned checklist version.
6. Publish to the shared catalog only through a separate platform-authorized
   action.

Manual product creation and checklist-led creation enter the same lifecycle.
An import may select an existing release or propose a new release in its draft.
A file containing more than one product must be split through explicit routing.
The importer never creates owned inventory, acquisition cost, asking prices,
reservations, listings, or sales.

Subject identity is optional and many-to-many. A confirmed subject link improves
discovery and reporting, but a missing or unresolved subject never blocks
product creation, checklist import, organization approval, shared-catalog
publication, or basic inventory intake.

## Evidence reviewed

### Active contracts

| Contract | Established fact |
| --- | --- |
| `BOARD.md`, PF-M5.1 | Tenant clients may not mutate platform catalog tables. Organization submissions remain private until platform curation. Canonical hard deletion is replaced by withdrawal or supersession. |
| `DOMAIN_MAP.md` | Shared catalog data is platform-level and read-only to tenants. Organization overlays and submissions are tenant-owned. |
| `PRODUCT_CHECKLIST_SCOPE_RECONCILIATION_2026-09-16.md` | The complete checklist ingestion lifecycle is missing. It proposes organization sources, batches, mapping revisions, full preview, decisions, approved versions, and a separate publication boundary. |
| `CONFIGURATION_CHECKLIST_APPLICABILITY_RECONCILIATION_2026-09-16.md` | Configuration applicability is versioned, optional, and independent of checklist identity. Missing applicability means unknown. |
| X1 migration `20260910171106` | Current source has organization product masters, configurations and immutable configuration versions, plus platform catalog releases, exact variants, many-to-many variant subjects, external identity mappings, and organization-owned unique items. |
| C1 migration `20260912171106` | Current source has a one-time platform-admin legacy checklist promotion path. It is not an organization upload, mapping, draft, or approval workflow. |
| X8b migrations `20260912000390` through `20260912000397` | Immutable revisions, field provenance, source references, reference fingerprints, exact replay, changed-replay refusal, stale approval rejection, and commit revalidation are implemented patterns. Their fixed operation enum and tables do not cover checklist ingestion. |
| C3 capability registry | Organization capabilities include `catalog.read` and `catalog.propose`. Platform-only capabilities include `catalog.review` and `catalog.publish`. Legacy workflow capabilities `act.submit_checklist_sources` and `act.approve_checklists` also exist and require reconciliation. |

### Existing, partial, missing, and conflicting matrix

| Area | Status | Exact evidence | Required disposition |
| --- | --- | --- | --- |
| Shared release identity | Implemented foundation | `e10_catalog_releases` stores manufacturer, brand line, release name, year, season, sport, language, region, edition, and attributes. | Reuse it as the platform release. A tenant draft may reference an existing release or propose one, but cannot publish it. |
| Organization product and configuration | Implemented foundation | `e10_product_masters`, `e10_product_configurations`, and immutable `e10_product_configuration_versions` are organization-owned. | Link organization purchasing/configuration records to a platform release without making the shared release tenant-owned. |
| Legacy checklist | Implemented but insufficient | `e10_checklists` stores name, set, source, cached count, attributes, and timestamps. It has no organization, versions, mapping, review, or provenance model. | Keep it as compatibility data. Add an organization draft/version workflow and a distinct platform-published version model. |
| Checklist-led creation | Missing | No source, batch, sheet/header selection, mapping revision, prepared-row, or routing tables exist. | Add the staged lifecycle described below. |
| Exact variant | Implemented foundation | `e10_catalog_variants` stores release, card number, exact parallel, color family, finish pattern, language, edition, rookie flag, print-run denominator, and attributes. | Preserve as exact printing identity. Do not attach owned-copy serial numerator or cost to it. |
| Base card identity within a release | Missing | Current X1 goes directly from release to exact variant. Legacy `e10_cards.card_id_ref` is not a governed release-scoped identity. | Add a stable release-scoped card identity so all parallels of the same card can group without collapsing exact variants. |
| Checklist membership | Partial | C1 `e10_catalog_checklist_entries` links a legacy checklist row to one exact variant and is append-only. | Version membership. A published checklist version contains ordered exact-variant membership and preserves the source row lineage. |
| Subject cardinality | Implemented foundation | `e10_catalog_variant_subjects` has primary key `(variant_id, player_id)` and unique `(variant_id, position)`. Tests prove two subjects on one variant. | Preserve zero, one, or many subjects. Neutralize naming in new APIs while retaining stable IDs. |
| Generic subjects | Structurally partial, naming conflict | Canonical storage is `e10_players` with sport-specific optional fields. Reporting already uses `subject_id`. | Preserve existing IDs, add governed subject kind and neutral readers, and keep sport affiliation as an optional extension. |
| Unresolved subject evidence | Missing | F4 ambiguity cases require existing player candidates and do not approve or create links. Organization imports have no durable unresolved-name row. | Add organization-private subject mentions and revisioned candidate/resolution decisions. Zero candidates is valid. |
| Canonical publication | Partial | C1 promotion is platform-admin-only, idempotent, and creates variants, entries, subject links, and reviewed color/finish facets from legacy rows. | Build a reviewed platform publication command over the new approved organization version. Do not let tenant approval imply publication. |
| Configuration applicability | Planned, not implemented | The September 16 applicability proposal defines included/excluded/unknown evidence and configuration-version pinning. | Checklist ingestion records candidates for later applicability review. It must not silently infer applicability from checklist membership. |
| Full-dataset grids | Pattern exists | X7d bounded readers and query contexts apply filters before cursor pagination. | Use the same bounded-query discipline for prepared rows and subject reports. A 200-row screen is not the full dataset. |
| Current duplicate helper | Conflicting with canonical identity | `BOARD.md` and `EXPANSION_AUDIT_2026-09-10.md` record that `cardDupKey()` omits year and includes physical serial numerator. Different releases can collide and two copies of one variant can separate. `cardTitle()` is presentation composition, not a key. The helper source is not present at the canonical head. | Keep the old helper only as a warning heuristic until the client is replaced. Never use it as a catalog uniqueness constraint or publication key. |

### Active-document contradictions

1. `BOARD.md` says a checklist is organization-scoped, while `DOMAIN_MAP.md`
   says checklists are platform shared and tenant-read-only. Both needs are real.
   The correction is two layers: an organization-owned draft/approved version
   and a separately platform-published canonical checklist version.
2. Earlier UI wording treats `name` or Player/Character as required card
   identity. The current requirement makes subject linkage optional. A prepared
   source label may be required for review, but canonical subject resolution is
   not a publication prerequisite.
3. The heuristic "if it shares a checklist, it is the same Product Master" is
   useful for configuration grouping but is not a canonical identity rule.
   Reprints, regional editions, language editions, and corrected checklist
   versions require explicit release identity.
4. Legacy `e10_cards` has one `player_id`, while X1 correctly supports multiple
   subjects. New ingestion must target the many-to-many model.
5. C1 promotion maps legacy `parallel` to both color and finish candidates. The
   reviewed facet taxonomy correctly separates color family and finish family.
   Source strings such as "Black Shimmer FOTL" must not be flattened into one
   permanent field.

## Verified sample inventory

Every supplied file was opened and inspected. No sample was missing. Forty
files were directly readable. The three Topps legacy XLS files could not be read
by the bundled Python XLS engine because `xlrd` was absent, so they were
converted read-only with LibreOffice and the resulting sheets were inspected.
The source XLS files were not changed.

### Topps

| File | Verified content |
| --- | --- |
| `topps_2025-26_chrome_basketball.pdf` | 28 pages, 51,915 extracted characters. Sectioned text beginning with BASE and BASE CARDS, followed by insert sections. |
| `topps_2025-26_chrome_uefa_club.pdf` | 22 pages, 33,797 characters. BASE, VETERANS AND ROOKIES, FUTURE STARS, and many insert sections. |
| `topps_2025_chrome_football.pdf` | 49 pages, 95,320 characters. BASE CARDS, ROOKIES, variations, inserts, and at least one multi-subject row, `Joe Burrow & Ja'Marr Chase`. |
| `topps_2026_bowman_baseball.pdf` | 15 pages, 48,595 characters. Base, paper prospects, chrome prospects, variations, and inserts. |
| `topps_2026_chrome_baseball.pdf` | 63 pages, 65,310 characters. Base, insert and variation sections. Product disclaimer repeats on pages and is not a card row. |
| `topps_2026_series1_baseball.pdf` | 53 pages, 131,609 characters. Starts `*SUBJECT TO CHANGE`; base and many variation/insert sections. |
| `topps_2026_star_wars_chrome.pdf` | 31 pages, 39,354 characters. Character checklist with names such as `BB-8`, `C-3PO`, and `V3-4 Sevn And IV-A4 On The Run`; conjunctions and hyphens are not reliable subject separators. |
| `topps_2026_chrome_ufc.xls` | One `Checklist` sheet, 981 rows by 4 columns, 940 nonempty rows by 3 columns. Title/disclaimer precede `BASE CARDS I`; rows contain number, subject, and optional flag such as Rookie. |
| `topps_2026_chrome_ufc_sapphire.xls` | One `Checklist` sheet, 446 by 4, 427 nonempty by 3. Same base numbers as UFC can appear in a distinct Sapphire product. |
| `topps_2026_universe_wwe.xls` | One `Checklist` sheet, 1,023 by 4, 969 nonempty by 4. Rows include number, performer, roster/legend context, and optional flags. |
| `topps_checklist_index.json` | JSON array of 900 title/URL records. URLs include inconsistent publisher filenames, so title and filename are candidates, not trusted release identity. |

### Panini

| File | Verified content |
| --- | --- |
| `panini_2025_basketball_court_kings_1530_site-download.csv` | 4,573 rows, 10 columns, 167 distinct CARD SET values, 172 distinct ATHLETE strings. Ten slash-delimited multi-name strings were observed. |
| `panini_2025_basketball_prizm_25-26_1533.csv` | 16,489 rows, 246 CARD SET values, 215 ATHLETE strings, 200 card numbers. Exact row tuple `(CARD SET, ATHLETE, TEAM, CARD NUMBER)` had zero duplicates. |
| `panini_2025_football_donruss_1452.csv` | 11,749 rows, 196 CARD SET values, 618 ATHLETE strings. Seventy-six multi-name-like strings include repeated names and triples. |
| `panini_2025_football_prizm_1476.csv` | 34,723 rows, 316 CARD SET values, 615 ATHLETE strings, 442 card numbers. Fifty-seven slash-delimited multi-name strings were observed. |
| `panini_2025_soccer_obsidian_25-26_1534.csv` | 8,796 rows, 213 CARD SET values, 545 ATHLETE strings. Source contains whitespace noise and repeated slash names such as `Lamine Yamal/Lamine Yamal`; slash count is not subject count. |
| `panini_blog_NBA-2020-21-Final-Checklist.xlsx` | Two sheets. `Sticker Collection` is 504 by 9 with the header on row 4 and 100 yellow-filled cells carrying foil meaning. `Trading Cards` is 104 by 8 with the header on row 4 and side notes about parallel cardsets. Formatting and off-table notes are evidence. |
| `panini_program_index_2024-2025.json` | Nested sport, year, brand and program records with program IDs and release dates. It is a picker/source index, not card membership. |

### Pokémon

| File | Verified content |
| --- | --- |
| `pokemontcg-data_cards_en_base1.json` | JSON array, 102 cards. Typed records include ID, name, supertype, subtypes, number, rarity, artist, Pokédex numbers and images. |
| `pokemontcg-data_cards_en_me1.json` | 188 cards. Some records omit artist, proving field availability differs by source/version. |
| `pokemontcg-data_cards_en_sv1.json` | 258 cards. |
| `pokemontcg-data_cards_en_sv10.json` | 244 cards. |
| `pokemontcg-data_cards_en_sv3pt5.json` | 207 cards. |
| `pokemontcg-data_cards_en_sv8.json` | 252 cards. |
| `pokemontcg-data_sets_en.json` | JSON array, 174 set records. |
| `tcgdex_card_sv01-001.ts` | TypeScript object for one card with nested typed fields. |
| `tcgdex_set_sv01_index.ts` | TypeScript set index with nested card summaries. |
| `tradingcarddex_Pokemon-151.csv` | 207 rows with only Name, Number and Rarity. |
| `tradingcarddex_Pokemon-Base.csv` | 102 rows with the same minimal shape. |
| `tradingcarddex_Pokemon-Evolving-Skies.csv` | 237 rows with the same shape. |
| `tradingcarddex_Pokemon-Surging-Sparks.csv` | 252 rows with the same shape. |
| `pokemontcg-data_README.md` and `tradingcarddex_README.md` | Source documentation was read and treated as provenance, not card data. |

### Magic: The Gathering

| File | Verified content |
| --- | --- |
| `mtgjson_BLB.json.zip` | ZIP contains nested `BLB.json` with 398 card printings. A card has MTGJSON UUID, name, collector number, finishes, rarity, language, artist and namespaced identifiers. |
| `mtgjson_FDN.json.zip` | Nested set JSON with 771 card printings. |
| `mtgjson_LEA.json.zip` | Nested set JSON with 295 card printings. |
| `mtgjson_SetList.json.zip` | Nested JSON list with 869 set records. |
| `mtgjson_cards_BLB_FDN_LEA.csv` | 1,464 rows and 82 columns of printing/game data. |
| `mtgjson_cardIdentifiers_BLB_FDN_LEA.csv` | 1,464 rows and 25 identifier columns. `scryfallOracleId` identifies a game-card concept, while `scryfallId`, MTGJSON UUID and marketplace IDs identify printings or provider records. |
| `mtgjson_sets.csv` | 869 set rows and 22 columns. |
| `mtgjson_meta.csv` | One dataset version row. |
| `scryfall_search_set-blb_page1.csv` | 175 search-result rows. It is page 1, not proof of full set coverage. Includes printing IDs and observed prices. |
| `scryfall_search_set-lea_page1.csv` | 175 page-1 rows with the same bounded search shape. |

## Card and product model

### Distinct identities

| Concept | Grain | Existing anchor | Rule |
| --- | --- | --- | --- |
| Platform release | Publisher release/edition/language context | `e10_catalog_releases` | Different year, edition, language, or publisher release is not merged merely because titles resemble each other. |
| Organization product master | The tenant's sellable/purchasable product concept | `e10_product_masters` | May link to one platform release. It is not the platform release itself. |
| Configuration version | Immutable packaging composition or SKU version | `e10_product_configuration_versions` | Box, blaster, hobby, retail, case, and pack semantics belong here. Applicability is pinned to the version. |
| Checklist version | Ordered release membership snapshot | New versioned layer | Draft, organization-approved, and platform-published states are distinct. |
| Card identity | Release-scoped base content identity | Missing | Groups exact variants of the same numbered card or insert without owning subject identity. |
| Exact variant or printing | One exact catalog expression | `e10_catalog_variants` | Includes card identity, exact parallel, color, finish, language, edition and print-run denominator where evidenced. |
| Subject | Reusable athlete/person/character identity | Legacy `e10_players` plus subject links | Optional and many-to-many. Not the card identity. |
| Owned copy | Organization-owned physical unit | `e10_unique_items` | May reference a variant. Condition, grade, certification and serial numerator are copy facts. |

The smallest additive correction is a release-scoped canonical card-identity row
and an optional foreign key from existing variants. Existing variant IDs remain
stable. Publication can backfill card identities without changing inventory or
historical variant references.

### Canonical fields and source coverage

First-class release fields are manufacturer/publisher, brand line, release
name, year/season, category or sport/franchise, language, region and edition.
First-class card fields are subset/insert name, card number as text, source
display label, ordered position and flags with governed meaning. Exact-variant
fields are exact parallel, color family, finish family, language, edition and
print-run denominator. Subject links, team shown, rookie designation, rarity,
artist and game mechanics are separate typed or category-scoped facts.

- Panini CSV supplies release and row fields directly, but CARD SET combines
  subset and parallel. SEQUENCE often behaves like a print-run denominator, but
  it remains raw until the mapping review confirms that meaning.
- Topps PDF/XLS supplies product identity through page title, filename or index,
  and uses section headers as row context. It usually does not enumerate every
  parallel or print run.
- Minimal Pokémon CSV supplies only name, number and rarity. Release identity
  must be operator-confirmed from source/file context.
- Pokémon JSON supplies stable provider card IDs and category fields but no
  universal finish/parallel vocabulary.
- MTGJSON separates printing UUIDs from Scryfall Oracle IDs. Oracle identity is a
  game-card identity, not automatically a depicted-character subject.
- Scryfall page-1 CSV is a bounded market/search response and cannot establish
  complete checklist membership.

All raw source values remain attached to provenance even after typed mapping.
Unknown source fields may become scoped custom fields only after an operator
chooses scope and type. A parser may not silently pour identity-critical values
into an unqueryable JSON object.

### Prizm mapping without duplication

For the 34,723-row 2025 Football Prizm CSV:

1. Confirm one platform release from SPORT, YEAR, BRAND, PROGRAM and the Panini
   program ID `1476`.
2. Preserve every source row and source location.
3. Map each reviewed CARD SET value into a subset/base identity plus an exact
   parallel expression. For example, `Base Prizms Black Shimmer FOTL` preserves
   the full exact string while reviewed facets may separately assert black as
   color and shimmer as finish.
4. Group only after review into release-scoped card identities. Card number,
   subset/base family and other disambiguating source context form the candidate
   grouping evidence. Subject text is not the sole identity key.
5. Create one exact variant per reviewed exact expression. Blank or unnumbered
   SEQUENCE remains unknown, not zero. A value such as `299` may become print-run
   denominator only under the approved mapping.
6. Do not create 34,723 owned items. Publication creates catalog identities and
   membership only.

The source contains zero exact duplicates at `(CARD SET, ATHLETE, TEAM, CARD
NUMBER)`, but that empirical fact is not a universal key guarantee. The 316 CARD
SET values and 442 card-number strings show why release, subset and exact variant
must remain explicit.

## Ingestion state and provenance

### Proposed additive relationships

1. `ChecklistImportSource`: organization, digest, filename, media type, source
   URI/provider, byte size, received time and uploader.
2. `ChecklistImportBatch`: source, parser adapter/version, lifecycle state,
   selected product/release route and current mapping revision.
3. `ChecklistSourceUnit`: sheet, page, section, table or JSON path with stable
   source locator and extraction digest.
4. `ChecklistMappingRevision`: immutable header/field mappings, transforms,
   type choices, source-to-product routing and reviewer overrides.
5. `ChecklistPreparedRow`: immutable normalized proposal plus raw values,
   source locator, transformation trace, warnings and candidate identity links.
6. `OrganizationChecklistDraft` and immutable revisions: selected release,
   ordered prepared membership, row decisions and completeness summary.
7. `OrganizationChecklistVersion`: an approved organization snapshot pinned to
   one draft/mapping/data revision.
8. `CatalogPublicationSubmission`: a request to platform review, never authority
   to publish.
9. `CatalogChecklistVersion`: the immutable platform-published release
   membership and provenance snapshot.

These are new shapes, not instructions to reuse X8b tables. They reuse X8b's
revision, fingerprint, idempotency, lock, authorization recheck and stale
reference patterns.

### State transitions

Import batch states: `uploaded -> detected -> mapped -> prepared -> in_review ->
approved | rejected | superseded`. Mapping edits create a new immutable mapping
revision and a new prepared dataset. They do not alter reviewed rows in place.

Publication states are separate: `not_submitted -> submitted -> under_review ->
published | rejected | superseded`. Organization approval does not advance this
state automatically.

Identical replay against the same organization, source digest, adapter version,
mapping revision and route returns the existing result. Reuse of an idempotency
key with changed input fails. Corrected files create a new source revision and a
row-level difference report. Stable identity uses reviewed source identifiers
and content keys, never row number alone.

### Adapter contracts and observed traps

- Sectioned PDF/text: detect page title and section headers, then parse row
  shapes under explicit section state. Exclude repeated disclaimers, page
  headers/footers and `SUBJECT TO CHANGE`. Preserve page and line/bounding-box
  locators. Low-confidence extraction requires review.
- Sectioned XLS: select sheet, detect title rows and section rows, and preserve
  flags. UFC and WWE have title/disclaimer rows before data.
- Title-above-header XLSX: detect the header on row 4, preserve off-table notes
  and cell formatting. The Panini sticker sheet's yellow fill carries foil
  evidence that value-only parsing would lose.
- Flat CSV: verify delimiter, encoding and exact headers. Panini CARD SET needs
  reviewed decomposition; slashes and repeated names cannot be blindly split.
- Nested JSON/TypeScript: require an adapter for the exact provider schema and
  version. Preserve provider namespaces. Arrays such as MTG finishes are not
  automatically one-to-one with sports parallels.
- Paged API/search exports: mark coverage as partial unless a complete cursor or
  authoritative set export proves completion.

## Optional subject linking

### Confirmed and unresolved states

- Confirmed canonical link: one stable subject ID linked to one exact variant,
  with role, position and reviewed evidence.
- Unresolved source name: organization-private evidence tied to source row,
  prepared row and checklist revision. It may have zero candidates.
- Suggested match: one candidate with alias, identifier and contextual evidence.
  It has no canonical effect.
- Organization-private resolution: allowed only if the owner confirms that
  policy. It can affect that organization's overlay/readers, not platform truth.
- Platform resolution: reviewed creation or linkage under platform review and
  publish authority.

Candidate generation may use governed aliases, punctuation/accent folding,
transliteration, subject kind, release/product/year/publisher, sport/franchise,
team or roster context, language, depicted role and appropriately scoped
external IDs. Similar names alone never confirm a match. A slash is only a split
candidate: Court Kings contains genuine pairs, Donruss contains triples and
repetitions, and Obsidian contains duplicated same-name strings.

Allen Iverson demonstrates the required cross-product behavior. The Court Kings
sample has 32 rows for him, including Base card 89 and many parallels. The
Basketball Prizm sample has 93 rows, including Base card 143 and exact variants
such as Black Shimmer FOTL and Blue Ice. These become two release-scoped card
identities and many exact variants linked to one confirmed subject. Team shown
is Philadelphia 76ers context on those cards, not the subject's timeless team.
Name agreement is strong discovery evidence but still requires a reviewed link.

For manually entered inventory with no catalog match, retain a source label and
optional organization-private subject mention on the intake record. Later
catalog matching may add a variant link and subject link without changing the
owned item, acquisition, cost, reservation or sale history.

## Subject reporting

A bounded subject reader returns all confirmed canonical variants and checklist
entries for a subject across releases, brands, publishers and years, including
unowned catalog rows. When an organization is supplied and authorized, it may
join that organization's owned-copy, quantity, acquisition, cost, listing, sale,
revenue and margin facts. It never exposes another organization's business data.

Filters apply to the full authorized dataset before keyset pagination. Required
indexes include normalized/alias and scoped-external-ID subject lookups,
variant-subject `(subject_id, variant_id)`, release/year/publisher, exact variant
facets, organization-owned `(organization_id, catalog_variant_id, id)`, and
unresolved mention status/context. Reader results carry query fingerprint,
dataset revision, coverage status and next cursor.

Confirmed results and unresolved mentions are separate result sections. Free
text remains searchable but is labeled incomplete identity resolution. Current
subject attributes stay separate from card-specific facts such as team shown,
rookie season, costume, character role or historical affiliation.

A multi-subject card may appear under every confirmed subject. Overall inventory,
sale and margin totals deduplicate by authoritative fact ID. Subject membership
does not allocate money. Revenue/margin attribution remains an owner decision;
the safe default is no attribution and no summing of inclusive subject totals.

Market trends identify the exact variant/printing, time window, source universe,
currency and evidence coverage. The system does not invent a blended price for
unrelated cards merely because they share a subject.

## Readers, writers, and capabilities

- Source upload and mapping draft require organization membership plus the
  reconciled submission capability.
- Organization checklist approval requires `act.approve_checklists` unless the
  capability vocabulary is deliberately replaced through a separate decision.
- Catalog reading requires `catalog.read`.
- Organization-private catalog or subject proposals require `catalog.propose`.
- Canonical review requires platform `catalog.review`.
- Canonical publication requires platform `catalog.publish`.

Owner input is required on whether `act.submit_checklist_sources` remains the
workflow entry capability alongside `catalog.propose`, or whether one delegates
to the other. They must not become two accidental names for the same unchecked
authority. Tenant review never grants canonical creation or publication.

The prepared-record reader returns counts over the full filtered revision and a
bounded page. Bulk actions carry explicit `selected_rows` or
`all_filtered_results` scope plus a revision-bound query fingerprint. The
publication writer consumes only an approved immutable organization version and
rechecks every referenced release, identity and capability after locks.

## First implementation slice

Use the official Panini 2025 Basketball Prizm (25-26), program 1533, CSV as the
first end-to-end sample. It is large enough to prove bounded review and exact
variant handling, but its flat ten-column shape isolates lifecycle correctness
before PDF/OCR and workbook-format complexity. It has 16,489 rows, 246 CARD SET
values, 215 subject strings and 200 card numbers.

The slice includes:

1. Source, batch, routing, mapping revision, prepared rows, save/resume and full
   review readers.
2. One organization checklist draft and approved immutable version.
3. No platform publication until the publication command receives its own
   review.
4. Reviewed grouping into base card identity and exact variants without owned
   stock creation.
5. Optional subject mentions and confirmed links. Allen Iverson links to the
   existing or fixture Court Kings identity to prove cross-product reporting.
6. One deliberately unresolved same-name or malformed source mention.
7. A multi-subject acceptance fixture from the Court Kings sample, since the
   Prizm sample has no slash-delimited subject rows.

### Acceptance tests

1. Product/release confirmation is explicit and records whether an existing
   release or a proposal was chosen.
2. Human mapping review shows raw headers, typed destinations, transformations,
   examples, warnings and any inferred print-run interpretation.
3. The operator can inspect all 16,489 prepared records through bounded pages;
   counts and filters cover the complete authorized revision before pagination.
4. Save/resume returns the same batch, mapping and review progress.
5. Identical re-import produces no duplicate source, card identity, exact
   variant, subject link or checklist membership.
6. Corrected re-import creates a new revision and an explicit added/changed/
   removed difference set. It does not rewrite the approved version.
7. An approved version remains readable while a new draft revision exists.
8. Allen Iverson filtering returns confirmed Court Kings and Prizm variants,
   including unowned entries, while organization stock metrics remain isolated.
9. An unresolved subject name is visible as unresolved and does not block intake
   or approval.
10. A multi-subject card appears in each subject result but one overall owned
    copy or sale counts once.
11. An organization approver cannot publish platform rows. Platform review and
    publish capabilities are checked separately at the writer after locks.
12. Import, approval and publication create zero inventory, acquisitions,
    costs, asking prices, reservations, listings or sales.
13. Changed idempotency-key reuse fails, stale approval fails, and concurrent
    publication cannot create duplicate effective identities or memberships.

## Additive implementation sequence

1. Contract correction: approve the owner decisions below and reconcile the two
   checklist layers and capability vocabulary in active docs.
2. Ingestion evidence: add organization source, batch, source-unit, mapping and
   immutable prepared-row storage with fail-closed RLS and born-locked writers.
3. Organization checklist versions: add draft revisions, full prepared readers,
   row decisions, approval snapshots and save/resume.
4. Catalog identity seam: add release-scoped card identity and optional variant
   link; backfill without changing variant or owned-item IDs.
5. Subject evidence: add neutral subject kind, append-only aliases/scoped IDs,
   private mentions, candidates and reviewed resolutions.
6. Publication: add submission, platform review and publication commands with
   immutable versions, exact replay, stale-reference rejection and withdrawal.
7. Reporting: add bounded subject/checklist readers, unresolved coverage and
   deduplicated organization metrics.
8. Adapter expansion: add Topps PDF/XLS, Panini title-above-header XLSX,
   Pokémon flat/nested JSON and MTGJSON adapters one at a time with fixture
   tests for each observed trap.

Applied migrations are not edited. Every schema step is additive and receives
local replay, exact-head CI, staging proof, tenant-isolation tests, capability
tests, idempotency/concurrency tests and production-untouched evidence before
advancing.

## Owner decisions required

1. Confirm the two-layer checklist model: organization-approved version plus
   separately platform-published canonical version.
2. Confirm capability reconciliation for source submission, organization
   approval, private proposal, platform review and platform publication.
3. Confirm whether organizations may assert private subject links or may only
   retain proposals until platform resolution.
4. Approve the subject-kind vocabulary and whether teams/groups are subjects or
   separate entities.
5. Approve release-scoped base card identity as an additive layer above exact
   variants.
6. Decide the financial attribution method for multi-subject cards. Safe default:
   none.
7. Confirm whether organization approval may include unresolved subjects and
   unknown configuration applicability. Recommended: yes, with visible coverage.
8. Confirm the first slice: full 2025 Basketball Prizm import with Court Kings
   fixtures for cross-product and multi-subject proofs.

Stop after review. No implementation begins from this document alone.
