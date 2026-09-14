# TA-X7d eligible observation history and composable screener plan

Status: plan-only checkpoint for independent review. No migration or environment
change is authorized by this document alone.

## Authority and boundary

This sub-batch implements X7d from `TA_X7_REPORTING_PLAN.md` and the screener,
identity, correction, no-connector, privacy, and full-dataset cases in
`EXPANSION_ACCEPTANCE_CASES.md`. It consumes the current eligible interpretation
of immutable `e10_market_observations`, the X1 shared catalog, and organization
owned products/configurations/copies. It does not enable a connector, import a
feed, create inventory or customer spend, infer a sale from an ask, perform
currency conversion, add UI, or write production.

Every private observation remains organization-owned. Shared catalog identity
does not make another organization's observation, holding, cost, or sale
visible. The screener must work with local/manual/imported evidence when every
external connector is absent.

## Empirical schema constraints

- `e10_current_market_observations` already excludes any observation named as a
  superseded predecessor. X7d uses this view, never the raw table, for eligible
  contribution.
- An observation targets exactly one product master, configuration version,
  unique item, or shared catalog variant. The projection resolves that target
  to zero or one catalog variant without multiplying observations.
- `asking_price`, `completed_sale`, `acquisition_cost`, and `estimated_value`
  are distinct kinds. Only `completed_sale` contributes to sale count, mean,
  median, minimum, maximum, or latest-sale measures.
- Catalog variants carry direct candidate fields for exact parallel,
  color/finish, language/edition, rookie designation, and print-run denominator;
  unique items carry serial numerator and current grading fields. The direct
  columns are not, by themselves, reviewed historical evidence.
- No current relation safely proves rookie season, jersey match, syndicated
  cross-source sale equivalence, or dated player affiliation. X7d must not infer
  those facts from names, release year, current team, titles, or JSON strings.

## Additive reviewed evidence

### Governed variant facets

Add immutable global `e10_catalog_variant_facet_decisions`, with a monotonic revision
per `(variant, optional subject, facet_key)`, action `assert` or `revoke`, one
typed value column selected by a check constraint, review reason, bounded JSON
evidence, reviewer, review time, predecessor, idempotency key, and request
fingerprint. Supported v1 keys are:

- `rookie_designation` (boolean);
- `rookie_season` (integer, subject required); and
- `color_family` and `finish_family` (controlled taxonomy IDs).

Add global, immutable `e10_catalog_facet_taxonomy_terms` and alias decisions for
the `color_family` and `finish_family` namespaces. Exact filters accept stable
term IDs; display aliases never become identity. Global taxonomy and variant
facet writers are platform-curation operations and require
`e10.is_platform_admin()`. An ordinary tenant role can never change shared
catalog meaning for every organization.

Add separate immutable `e10_org_catalog_variant_facet_overrides` for an
organization's private analytical interpretation. These use the same controlled
term IDs and typed rookie fields, require active membership plus
`act.curate_market_analytics`, and affect only that organization's queries.
Responses identify `global_reviewed` versus `org_override`; the org override
takes precedence only inside its own tenant boundary. Neither relation rewrites
the base shared catalog row.

An organization override has three explicit terminal actions: `assert` supplies
the tenant-private value, `mask` makes the facet unknown for that organization
even when a global value exists, and `clear` removes the tenant override so the
current global reviewed value is used again. A generic revoke action is not
overloaded to mean both mask and fallback.

The current service-only views select the one terminal decision for each exact
key and apply the tenant-private precedence explicitly. Revocation returns
unknown, not false. Exact filters consume only current asserted values. Existing
catalog columns may be returned as unreviewed display candidates but cannot
satisfy an exact governed filter unless a reviewed global or tenant-private
decision confirms them. This deliberately avoids silently treating release
year as rookie season or a title token as color/finish proof.

### Copy and observation facts

Jersey match, grading state, and a pictured serial are not variant-wide facts.
Add immutable organization-private decisions for:

- `e10_unique_item_facet_decisions`, binding an owned physical copy to an exact
  subject and evidence-backed jersey match, pictured number/team/season
  reference, or other reviewed copy marking; and
- `e10_market_observation_fact_decisions`, binding one market observation to
  its observed `raw` or `graded` state, grader, categorical grade, qualifier,
  serial numerator/denominator when evidenced, jersey-match subject/reference,
  transaction quantity, and amount basis.

The observation fact contract distinguishes `transaction_total`, `unit_price`,
and `unknown` amount basis and may carry an explicitly conserving unit amount.
It never derives a historical sale grade from an owned copy's current grade.
When quantity exceeds one and no reviewed unit allocation exists, transaction
amount remains usable only as a transaction-total metric; per-unit price is
unavailable. Sale count is the number of canonical sale transactions, while
unit quantity is a separate nullable measure. These decisions use CAS,
predecessor, bounded evidence, idempotency, and the tenant curation capability.
Full owned-copy grading/regrade history remains X7e; X7d stores only the typed
facts necessary to describe the observation or current reviewed copy cohort.

This facet contract does not close the separate X1 remainder for dated player
affiliation history. That remains a later explicit identity checkpoint; X7d
never relabels historical cards to a player's current team.

### Cross-source observation equivalence

Add immutable `e10_market_observation_equivalence_decisions`, organization
scoped, linking an exact duplicate observation to one canonical observation of
the same kind, currency, amount, occurrence identity, and resolved cohort. It
records `link` or `unlink`, monotonic revision, reason/evidence, reviewer,
predecessor, idempotency key, and fingerprint. A partial unique successor rule,
deterministic locks, cycle/depth checks, and same-organization checks prevent a
duplicate from contributing through two canonical chains.

The current equivalence view resolves a bounded terminal canonical observation.
The screener counts one canonical contribution while the drill-down returns all
linked source observation IDs and source provenance. There is no automatic
fuzzy cross-provider merge. Without a reviewed equivalence decision, two
licensed source rows remain two observations and the response discloses that
deduplication is unreviewed.

Tenant-private facet, copy/observation fact, equivalence, and coverage writers
require active membership and a new allow-listed
`act.curate_market_analytics` capability. The capability receives no default
role grants. Global taxonomy/facet writers are separately platform-admin-only.
Evidence tables are RLS-enabled, client-closed, append-only, and service-readable
only; public writers are anon-closed and self-authorizing.

## Cohort model and grain

Build a service-only security-invoker projection with exactly one row per
eligible canonical observation and explicit:

- organization, observation, canonical observation, and linked provenance IDs;
- scope identities: catalog variant, owned unique item, product master, and
  configuration version, each nullable according to the selected scope;
- release, governed facet, observed raw/graded, grader, categorical grade,
  qualifier, and copy/observation marking values with known/unknown status;
- observation kind, currency, amount, quantity, occurred/recorded time, source
  kind/connection/reference, and correction lineage; and
- exclusion reason when an exact requested mapping or governed facet is
  unknown.

The public query accepts one explicit scope:

- `catalog`: one row per shared catalog variant matching catalog facets, even
  when the caller's organization has no sale evidence. Price aggregates are
  NULL/unavailable without qualifying price evidence.
  `observed_sale_count` is always returned and may be zero;
  `complete_selected_source_sale_count` is returned only when the selected
  observation window has reviewed complete coverage for every selected source.
- `owned`: one row per organization-owned unique item. Two copies of one variant
  remain two rows. Serial numerator filters apply to these reviewed physical
  copies and require the matching variant print-run denominator when a
  denominator is requested.
- `completed_sale_observation`: one row per eligible canonical completed-sale
  observation before optional grouping. Reviewed observation-specific serial
  and jersey evidence may filter this scope even when the observed copy is not
  owned by the organization. It never includes asks, estimates, or acquisition
  costs.

Catalog scope has no copy-level serial identity. A serial numerator filter is
therefore an existential filter over a qualifying reviewed canonical
observation for the variant, never a guess from the variant, title, or an
unrelated owned copy. A zero-observation catalog entity cannot match it.

Grouping is caller-selected from an allow-list, including catalog variant,
variant plus raw/graded state, variant plus grader and categorical grade,
subject, release, and reviewed color/finish term. The response declares the
exact ordered grouping dimensions and stable cohort key. Raw and graded rows,
different graders, and distinct categorical grades are never averaged together
unless the caller explicitly selects a broader non-price count grain; a price
metric rejects a grain that would mix incompatible grade states. The Yamal
PSA-9 case therefore groups by variant/raw-graded/grader/grade and never borrows
an owned copy's current grade for a historical observation.

Observation and owned-copy counts are computed independently before joining so
a variant with two copies and three sales reports `1 / 2 / 3`, never six.
Multi-subject matching uses an `EXISTS` predicate over
`e10_catalog_variant_subjects`, never a join that duplicates the cohort.

## Filter and aggregate order

The bounded screener takes explicit organization, scope, finite observation
window and as-of cutoff, currency, hard limit, stable cursor, selected sort, and
optional filters for:

- sport, league, subject ID, manufacturer, brand line, release ID/name/year,
  season range, language, region, edition, card number, exact parallel;
- reviewed controlled color family and finish family IDs, rookie designation,
  rookie-season dimension, copy/observation jersey match, and exact subject;
- raw versus graded, grading company, grade, serial numerator, and print-run
  denominator;
- observation source kind/connection, observation kind, and optional
  per-observation amount minimum/maximum; and
- post-aggregation completed-sale count, mean, median, latest, minimum, and
  maximum constraints.

Current eligible observations are resolved into equivalence groups before a
source filter is applied. An equivalence group qualifies for a source filter if
at least one current linked provenance row matches it; the canonical semantic
sale contributes once. Public drill-down returns only provenance fields allowed
by the selected source filter plus a disclosed total linked-provenance count, so
deduplication cannot leak excluded source details. Equivalence review requires
coherent kind, currency, amount basis/value, quantity, occurrence identity, and
resolved cohort. If a canonical or linked member is superseded/corrected, its
stored member fingerprint no longer matches and the equivalence becomes
`review_required`; it is not silently redirected to a replacement or used for
deduplication until reviewed again.

All identity, facet, source-membership, kind, date, currency, and optional
transaction amount filters are applied to the complete authorized eligible
canonical cohort before grouping. Sale aggregates are then computed over that
full filtered cohort. Aggregate thresholds are applied only after grouping. Therefore
`500,1500,500,1500` has mean `1000` and fails a strict below-1000 aggregate
filter; an explicit per-sale maximum of `800` first selects two 500 rows and
labels the resulting mean as transaction-filtered.

Asks, estimates, costs, transaction totals, reviewed unit prices, and sales are
returned as separate metric rows or columns with explicit coverage; they are
never unioned into one price. `sale_transaction_count`, `known_unit_quantity`,
`mean_transaction_total`, and `mean_reviewed_unit_price` are distinct measures.
No currency conversion occurs. A request with no currency is invalid whenever
a monetary observation metric is selected.

## Coverage, unknowns, and exclusions

X7d does not invent feed completeness. Add immutable reviewed
`e10_market_observation_coverage_decisions` scoped by organization, observation
kind, source family/connection, currency, and finite interval, with
`complete`, `partial`, or `unavailable`, supersession/revocation, CAS,
idempotency, and evidence. This is a claim about the selected source boundary,
not the whole market.

Coverage resolution is conservative. Current complete assertions are unioned,
then every overlapping current `partial` or `unavailable` interval is
subtracted. Revoked/superseded rows remain in history but only terminal current
decisions participate. This calculation runs independently for each exact
source connection, observation kind, currency, and finite interval. A selected
source universe is complete only when every selected source is complete for the
entire requested interval after subtraction; intervals or assertions from one
source can never fill a gap for another.

A coverage request names the exact source universe: source kind, an explicit
allow-list of source connections or the literal `all_reviewed_connections`,
observation kind, currency, and finite interval. `all_reviewed_connections` is
resolved to the immutable sorted set of currently reviewed, non-revoked source
connections visible to the organization at query start, and that set is bound
into the query fingerprint and cursor. An empty resolved universe has unknown
coverage, never complete coverage. No assertion about one source implies
coverage of another source or the whole market.

Observed qualifying row/transaction counts remain available and explicitly
labeled `observed_count` even when market completeness is unknown. Without
complete reviewed coverage, a no-sales catalog entry remains visible with
`observed_sale_count=0`, but `complete_selected_source_sale_count`, price
availability, and any claim of zero sales within the selected source universe
remain NULL/unavailable. The completeness field is deliberately source-scoped
because even complete internal source coverage is not proof of the whole
market. Catalog scope always returns the observed count;
it returns `observed_sale_count=0` when no qualifying evidence exists, while a
zero claim for the selected source universe appears only in
`complete_selected_source_sale_count` under exact complete coverage. Unknown
governed mappings are excluded from exact filters and counted by reason. Every
result
reports selected scope/grain, metric/version, transaction-filter label,
observation window, as-of cutoff, currency, coverage status and source universe,
eligible observed count, linked duplicate count, and unknown/excluded counts.

## Bounded APIs and cursor/revision contract

Define the reserved capability identifier `act.view_market_analytics`, with no
default grants, through the existing `e10.has_org_cap` and organization role
permission mechanism. X7d does not introduce a separate capability catalog.
Authenticated reads require active membership plus that capability. It does not
grant direct table access or customer financial/contact access.

Add two public `SECURITY DEFINER` RPCs:

1. `e10_org_market_screener(...)`: bounded cohort/aggregate rows, maximum page
   200, allow-listed sorts only, and a full stable keyset tuple ending in cohort
   UUID.
2. `e10_org_market_observation_drilldown(...)`: bounded contributing canonical
   observations and linked provenance, maximum page 200, preserving the exact
   parent query fingerprint and cohort identity.

Neither API returns raw intake payloads or unrestricted JSON. Drill-down
returns allow-listed provenance fields and IDs only.

The interpretation is restated-current as of the request's observation cutoff,
not a historical-knowledge snapshot. `occurred_at` is bounded by the cutoff;
later-recorded eligible corrections, equivalence, coverage, and reviewed facet
decisions may restate the selected historical period. Their revision changes
invalidate old cursors, while the immutable prior evidence remains auditable.

Add an organization market-reporting revision and one global shared-catalog
revision. Triggers advance the organization revision for current observations,
supersessions, equivalence, coverage, owned copies, tenant-private facet
overrides, unique-item facet decisions, and market-observation fact decisions
that affect its private cohort. Catalog release/variant/subject changes, global
facet taxonomy terms and aliases, and global variant facet decisions advance
the global revision. Reads lock/capture both revisions, recheck authority after any
wait, and return both. Cursors bind every input, metric version, organization
revision, catalog revision, cutoff, scope, sort, and parent cohort. A stale,
foreign, arbitrary, or filter-rebound cursor is rejected. Server-side cursor
resolution preserves timestamp/numeric precision. Revision triggers are
statement-safe and must not fan out by organization for a global catalog change.

## Checkpoints

### X7d.0: reviewed semantics and revision control

- Define and document the reserved capability identifiers
  `act.view_market_analytics` and `act.curate_market_analytics`; enforce them
  through the existing `e10.has_org_cap` and organization role permission
  mechanism, with no seeded/default grants.
- Add controlled facet taxonomy, separately authorized global facet decisions,
  tenant-private overrides, copy/observation facts, observation-equivalence,
  and coverage decision structures, their current service-only views, writers,
  organization/global revision rows, and bounded revision triggers.
- Prove CAS, replay/mismatch, cycle/depth defense, correction eligibility,
  cross-org denial, global-versus-tenant authority and precedence, typed amount
  basis, no automatic equivalence, no direct client table access, absent grant
  denial, explicit same-organization role grant access, and denial after revoke.

Stop for independent review before the projection or reads.

### X7d.1: eligible canonical projection

- Add the one-row-per-canonical-observation service-only projection and bounded
  helper functions.
- Prove four observation kinds and transaction-total/unit-price measures remain
  separate, superseded observations do not contribute, linked duplicates
  contribute once with filtered provenance disclosure, each
  target type resolves without fanout, multi-subject `EXISTS` behavior, and
  unknown governed facets fail closed.

Stop for independent review before public reads.

### X7d.2: screener and drill-down reads

- Add both public bounded RPCs, exact query fingerprints, stable cursor
  resolution, coverage/exclusion disclosures, and allow-listed ACLs.
- Prove catalog/owned/sale grain, full-dataset filter-before-aggregate order,
  optional transaction filters, ask/sale separation, no-sale unavailable versus
  covered zero, serial 3/50 versus 4/50, language/edition, multiple subjects,
  reviewed rookie dimensions, observation-specific grade/jersey evidence,
  configurable grouping dimensions, feed independence, and 201-row pagination.

Stop for independent review before concurrency/staging.

### X7d.3: concurrency and staging acceptance

- Exact-backend tests cover facet/equivalence/coverage CAS races, reader blocked
  on both revisions with post-wait authority recheck, input change versus stale
  cursor, correction/equivalence arriving between pages, and independent org
  revisions under a shared catalog revision.
- Run clean replay, X5e-X5i and X7 predecessor regressions, A7, default
  privileges, independent review, exact-head CI, explicit staging apply/tests,
  advisors, zero residue, and read-only production proof.

Stop at X7d. X7e remains required and no X8 work begins from this plan.

## Required acceptance fixtures

1. Four sales `500/1500/500/1500` and both aggregate-order variants.
2. One 1500 ask and one 900 sale, never mixed.
3. One reviewed duplicated sale across two source connections, counted once
   when either permitted source filter selects it, without leaking excluded
   provenance; correction of either member makes equivalence review-required.
4. One catalog variant with two owned serial copies 3/50 and 4/50 plus three
   sale observations, proving each requested grain independently.
5. Dual-subject, distinct release, language/edition, exact parallel, controlled
   color/finish, rookie designation versus rookie-season, observation-specific
   PSA/BGS/raw grade cohorts, and copy/observation jersey-match positives plus
   unknown negatives.
6. A matching catalog variant with no sale evidence: visible and unavailable
   without coverage; covered zero only under an exact reviewed complete source
   assertion.
7. Same-file replay and corrected import: only current eligible interpretation
   contributes and full lineage remains in drill-down.
8. No connector or feed enabled: local/manual/import evidence still works.
9. Two organizations share catalog IDs but cannot read or influence each
   other's observations, copies, equivalence, coverage, cursors, or exclusions.
10. Missing capability, `anon`, NULL/unbounded input, unsupported sort/scope,
    foreign cursor, stale revision, and limit above 200 fail closed.
11. Every fixture is removed and the org0/inventory baseline remains unchanged.
12. A quantity-five lot-total sale contributes one sale transaction and five
    known units but no unit-price average until an explicit conserving unit
    allocation is reviewed.

## Explicit warnings and deferred work

- Existing mutable catalog facet columns need reviewed decisions before they
  satisfy exact governed filters. X7d must not bless legacy values implicitly.
- Dated player affiliations remain the explicit X1 remainder. No current-team
  inference is permitted.
- Population snapshots, grading/regrade history, valuation/index evidence,
  listing intervals, exposure, and portfolio attribution belong to X7e.
- PO/invoice/comment/receiving workflow remainders remain X3/X4 work and are not
  pulled into a screener migration.
- A coverage assertion is reviewed source coverage, not proof of the whole
  market. Cross-shop aggregation remains forbidden without a separate consent,
  rights, and privacy design.
