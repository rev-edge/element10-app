# TA-X7d Market Read API Contract

Status: implementation binding for TA-X7d.2. This contract does not authorize
staging apply before X7d.3 acceptance.

## Authority

The binding behavioral authority is `docs/TA_X7D_SCREENER_PLAN.md`. This file
fixes the integration shape for that approved behavior. Both reads require an
active organization membership and `act.view_market_analytics`. That capability
has no default grant. Anonymous callers and members without the capability are
denied.

## Screener

```sql
public.e10_org_market_screener(
  p_org uuid,
  p_scope text,
  p_grouping text,
  p_metric text,
  p_observation_kind text,
  p_observed_from timestamptz,
  p_observed_to timestamptz,
  p_as_of timestamptz,
  p_currency text,
  p_source_mode text,
  p_source_kind text,
  p_source_connections jsonb,
  p_filters jsonb default '{}'::jsonb,
  p_sort text default 'cohort_asc',
  p_limit integer default 50,
  p_cursor uuid default null
) returns jsonb
```

Allowed scopes are `catalog`, `owned`, and `completed_sale_observation`.
Allowed grouping values are `entity`, `variant`, `variant_condition`,
`variant_grader_grade`, `subject`, `release`, `color`, and `finish`.
Allowed metrics are `count`, `transaction_total`, and `reviewed_unit_price`.
`entity` preserves the scope's natural identity: catalog variant, owned unique
item, or canonical observation. Price metrics are accepted only when every row
is partitioned by the full condition-state, grader, grade, and grade-qualifier
tuple in addition to the requested identity grouping. Unknown values remain a
separate explicit tuple and never imply compatibility with a known cohort.
Count-only requests may use any allowed grouping. Monetary metrics require a
three-letter currency. A count-only request may omit currency only when
`p_source_mode='none'`; any source-scoped count also requires the exact
three-letter currency used to resolve its source universe and coverage.

`p_observation_kind` always selects one exact kind. The
`completed_sale_observation` scope requires `completed_sale`. Sale count and
sale price labels are emitted only for `completed_sale`. Asking-price,
acquisition-cost, and estimated-value results use their own observation-kind
and metric labels and are never relabeled or combined as sales.

`p_observed_from`, `p_observed_to`, and `p_as_of` are finite. The observation
interval is nonempty and cannot end after the as-of cutoff. Limits are 1 through
200. Sorts are allow-listed and always end in the stable cohort key.

`p_filters` is an object with no unknown keys. The recognized keys are:

- identity: `sport`, `league`, `subject_id`, `manufacturer`, `brand_line`,
  `release_id`, `release_name`, `release_year`, `release_year_from`,
  `release_year_to`, `season_from`, `season_to`,
  `language`, `region`, `edition`, `card_number`, `exact_parallel`;
- governed facets: `color_family_term_id`, `finish_family_term_id`,
  `rookie_designation`, `rookie_season`, `exact_subject`;
- copy and observation facts: `condition_state`, `graded`, `grader_code`,
  `grade_label`, `grade_qualifier`, `serial_numerator`,
  `observed_serial_denominator`, `variant_print_run_denominator`,
  `jersey_match`;
- transaction filters: `amount_min`, `amount_max`;
- aggregate filters: `sale_count_min`, `sale_count_max`, `mean_min`, `mean_max`,
  `median_min`, `median_max`, `latest_min`, `latest_max`, `minimum_min`,
  `minimum_max`, `maximum_min`, and `maximum_max`.

Unknown governed values do not match exact filters. Subject filtering uses
existence and does not multiply observations. Transaction filters run before
grouping. Aggregate filters run after the full filtered group is computed.
Owned-copy and observation counts are aggregated independently.
In catalog scope, `owned_copy_count` is organization inventory context for the
catalog variants in that result cohort. It does not claim those copies share an
observation-specific grade, serial, condition, or jersey fact used to qualify
the market-evidence cohort. Copy-specific matching belongs to `owned` scope.

`release_year` is mutually exclusive with either year-range bound. Range bounds
are inclusive. `subject_id` matches membership in the variant's subject array.
`exact_subject=true` is invalid without `subject_id`. In `owned` scope it
requires a current reviewed unique-item facet for that subject. In
`completed_sale_observation` scope it requires the current reviewed observation
subject fact. It is rejected in `catalog` scope because catalog subject
membership is already expressed by `subject_id` and is not copy-specific.
`variant_print_run_denominator` filters the catalog variant value, while
`observed_serial_denominator` filters the reviewed observation fact.

Aggregate amount filters and amount sorts always apply to the selected amount
metric. `transaction_total` exposes and filters transaction-total aggregates;
`reviewed_unit_price` exposes and filters reviewed-unit aggregates. A `count`
request rejects monetary aggregate filters and monetary sorts. Sale-count
filters are valid only when `p_observation_kind='completed_sale'`.

Allowed sorts are `cohort_asc`, `observed_count_desc`, `latest_desc`,
`mean_asc`, `mean_desc`, `median_asc`, and `median_desc`. Metric sorts are
invalid when their metric is unavailable. Every sort ends with `cohort_key`.

The response contains `query_fingerprint`, `organization_revision`,
`catalog_revision`, `scope`, `grouping`, `metric`, `coverage_status`,
`metric_version`, `transaction_filter_applied`, `observed_from`, `observed_to`,
`as_of`, `currency`, `resolved_source_universe`, `unknown_counts`,
`exclusion_counts`, `rows`, and `next_cursor`. Every row contains
`cohort_key`, `entity_id` when the grain has one natural identity,
`catalog_variant_id`, `release_id`, `subject_id` when grouped by subject,
`condition_state`, `grader_code`, `grade_label`, `grade_qualifier`, reviewed
color/finish/rookie fields applicable to the group, `catalog_entity_count`,
`owned_copy_count`, `observed_count`, `linked_duplicate_count`,
`known_unit_quantity`, `mean_transaction_total`, `median_transaction_total`,
`latest_transaction_total`, `minimum_transaction_total`,
`maximum_transaction_total`, `mean_reviewed_unit_price`,
`median_reviewed_unit_price`, `latest_reviewed_unit_price`,
`minimum_reviewed_unit_price`, `maximum_reviewed_unit_price`,
`complete_selected_source_sale_count`, and `price_availability`. Fields are
typed JSON scalars or null, not caller-controlled payload fragments.

Catalog scope retains matching catalog entities when there are no observations.
Such rows report observed count zero, while a source-scoped complete zero is
reported only as
`complete_selected_source_sale_count = 0` under exact complete coverage.
Missing observation amounts make that row's amount aggregates null and its
price availability unavailable; they do not make an otherwise valid catalog
query invalid. Amount sorts use deterministic `NULLS LAST` plus `cohort_key`,
so no-observation catalog entries remain pageable.

Copy and observation fact filters in catalog scope are existential filters over
qualifying reviewed canonical observations for the catalog variant. They do not
reinterpret catalog columns as historical evidence. Consequently a catalog
query filtered to a reviewed grade, serial, condition, or jersey-match fact may
return variants supported by matching observations, while a zero-observation
variant does not match that evidence filter. Without those evidence filters,
zero-observation catalog variants remain present. `exact_subject` remains
invalid in catalog scope because catalog subject membership is not a reviewed
copy-specific fact.

## Drill-down

```sql
public.e10_org_market_observation_drilldown(
  p_org uuid,
  p_parent_query_fingerprint text,
  p_cohort_key text,
  p_observation_kind text,
  p_observed_from timestamptz,
  p_observed_to timestamptz,
  p_as_of timestamptz,
  p_currency text,
  p_source_mode text,
  p_source_kind text,
  p_source_connections jsonb,
  p_limit integer default 50,
  p_cursor uuid default null
) returns jsonb
```

The parent fingerprint and cohort key must resolve to a saved screener query
context created for the same organization, caller, revisions, and normalized
inputs. A bounded service-only query-context record is created for every
successful screener request, including a one-page response with no next cursor.
It stores the full normalized filters, resolved source universe, grouping,
metric, scope, sort, revision pair, eligible cohort-key membership, total row
count, creation time, and expiry. The cohort membership is capped by the same
bounded query work contract and cannot be supplied by the client. Drill-down
reapplies the saved parent filters and rejects any caller-supplied observation,
window, cutoff, currency, or source argument that differs from that context.
Drill-down returns
one row per contributing canonical observation. It discloses canonical ID,
occurred time, observation kind, currency, typed transaction and reviewed-unit
amounts, known quantity, governed grade and copy facts, corrected observation
IDs, total linked provenance count, and only the linked provenance IDs and
source fields allowed by the selected source universe. It never returns raw
payloads or unrestricted source JSON.

Corrected predecessor IDs are audit lineage, not source provenance. They may be
reported as IDs, but no predecessor source kind, connection, reference, or
other provenance field is disclosed unless that predecessor independently
matches the saved source universe.

## Source universe and coverage

Source mode is `none`, `explicit`, or `all_reviewed_connections`. `none`
requires null source kind and connections and makes coverage `unknown`.
`explicit` requires 1 through 50 string-or-null connection identifiers.
`all_reviewed_connections` resolves at query start to a sorted immutable set of
at most 50 current reviewed connections for the exact organization,
observation kind, source kind, and currency. More than 50 is rejected, never
truncated. An empty resolved universe matches no provenance and has unknown
coverage.

An equivalence group matches when any current linked member matches the selected
source universe. The canonical sale contributes once. Coverage is computed
independently for every selected source connection and the exact finite window.
Intervals from different sources cannot fill each other's gaps. Current partial
or unavailable decisions override overlapping complete decisions. Completeness
is explicitly selected-source coverage, never whole-market completeness.

## Revisions, fingerprints, and cursors

Each read locks and captures the organization's market revision and the global
catalog revision, then rechecks membership and capability. The fingerprint
binds the API version, caller, organization, normalized inputs, resolved source
universe, scope, grouping, metric, sort, cutoff, and both revisions.

Cursors are random server-side identifiers. Their precise typed sort position,
parent cohort when applicable, fingerprint, caller, organization, and revisions
are stored in service-only tables with bounded row count and expiry. Query
contexts and cursors have an implementation-enforced maximum lifetime and are
deleted or made unusable after expiry. The v1 bounds are a 15-minute lifetime,
100 live query contexts and 1,000 live cursors per actor and organization, and
100,000 eligible cohort keys per context. A request exceeding a bound is
rejected and never truncated. A cursor is rejected if
it is missing, expired, belongs to another caller or organization, is for the
other endpoint, has stale revisions, or does not match the recomputed query
fingerprint. The client never supplies decoded timestamp or numeric positions.

Any eligible correction, equivalence, coverage, owned-copy, or private facet
change advances the organization revision. Shared catalog identity, taxonomy,
or global facet changes advance the global revision. Either change invalidates
prior cursors. Results are restated-current as of the request, not a historical
knowledge snapshot.

Every read first verifies that the organization is active. It then acquires the
global catalog revision lock followed by the organization revision lock, which
is the single reader lock order, captures both revisions, and rechecks active
organization, caller identity, membership, and capability after the locks are
held. Implementations that also touch both revision rows must use this order.
