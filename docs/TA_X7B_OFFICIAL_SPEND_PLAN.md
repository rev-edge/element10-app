# TA-X7b official customer spend plan

Status: focused implementation plan for review. No migration, database, UI, or
production change is authorized by this file.

## Authority and scope

This checkpoint implements only TA-X7b from
`docs/TA_X7_REPORTING_PLAN.md`, using the customer-commercial evidence built
in X6a through X6f and the reporting revision/attendance contracts accepted in
X7a. Posted means reviewed and posted. It does not mean paid, settled,
recognized revenue, payout, proceeds, physical return, or accounting truth.
Provisional activity remains separate.

All reads require explicit organization and active membership. Financial
authority is composable:

- organization-wide access is the ordinary customizable role permission
  `act.view_customer_financials`;
- location-only access is a new
  `e10_location_role_permissions.can_view_customer_financials` grant;
- a line with NULL location requires organization-wide access because no
  location grant can authorize it;
- a line with a location is authorized by either organization-wide access or
  the caller's active-role grant for that exact active location.

The control migration implements that composition as
`e10.can_view_customer_financials_at(p_org, p_location)`. It first proves
active organization membership. For NULL location it returns only
`e10.has_org_cap(p_org, 'act.view_customer_financials')`. For a non-NULL
location it proves the location belongs to `p_org`, then accepts either the
organization capability regardless of the location's current status, or an
enabled location-role grant joined through the caller's active membership
while that location is active. Thus archiving a location never erases
organization-wide historical totals, while a narrow grant cannot be used as
continuing access to an inactive location. It has no admin-role shortcut.

The migration does **not** auto-grant the sensitive capability to any system
role. Organizations can assign it to custom roles through the existing
permission administration path and can delegate individual locations without
receiving organization-wide financial access. It is not implied by contact,
notes, attendance, reporting-export, or financial-estimate access. An
unscoped request by a location-only caller reads only authorized locations and
returns `authorization_scope='authorized_locations'`; it never returns the
count or existence of hidden rows. This extends the real X2 location grant
model rather than inventing a generic predicate that does not exist.

## Existing authoritative inputs

Official contribution uses only:

- `e10_customer_transactions`: immutable reviewed posted header, customer,
  currency, occurrence precision/time, posting time, and source draft.
- `e10_customer_transaction_lines`: immutable line grain and purchase kind
  (`retail|break|unclassified`), channel, location, source identity,
  activity link, product/configuration/copy, break session/slot, quantity,
  gross merchandise, nullable discount/shipping/tax, and generated nullable
  merchandise net.
- `e10_customer_transaction_component_finalizations`: the one reviewed
  absolute baseline for an originally unknown merchandise, shipping, or tax
  component.
- `e10_customer_transaction_adjustments`: immutable additive
  refund/cancellation/correction deltas. `increase` adds and `decrease`
  subtracts. Cancellation must zero every known component; one explicit
  correction may reinstate it. No state is inferred from event text.
- `e10_current_customer_transaction_attributions` and
  `e10.customer_transaction_effective_attribution`: current selective
  attribution/unattribution followed by the current whole-customer
  merge/split topology.
- `e10_customer_transaction_source_claims`,
  `e10_customer_transaction_reconciliation_decisions`, and
  `e10_customer_transaction_evidence_links`: source deduplication and
  drill-down lineage. A linked native/imported observation is evidence for the
  posted line, never another contribution.
- `e10_customer_activity_observations`: provisional activity for the separate
  provisional API. A row linked by an official posted line is excluded from
  the outstanding-provisional result.
- X7a current attendance intervals, reviewed coverage, stable session
  assignment, and `e10_reporting_dataset_revisions`.

No market observation, commercial event, native board sale, reconciliation
case, draft, hold, assignment, fee, payout, or source payload contributes
money by itself.

## Monetary and temporal contract

Every request supplies one ISO-4217-like uppercase three-letter currency,
`[p_from,p_to)`, and `p_observation_cutoff`, with
`p_from < p_to <= p_observation_cutoff <= clock_timestamp()` and a maximum
366-day window. There is no conversion or cross-currency total.

The temporal model stays the accepted X7 current-restated interpretation.
`p_observation_cutoff` clips eligible source occurrence, not system knowledge:
currently posted transactions whose transaction occurrence is within
`[p_from,p_to)` and before the cutoff are eligible even when posting was
recorded later. All currently effective reviewed component finalizations,
adjustments, selective transaction attribution, whole-customer mapping, and
reconciliation lineage restate that earlier period, including refunds or
finalizations recorded after the cutoff. Their recorded and occurrence times
remain visible in drill-down, and an adjustment never moves the originating
sale into a different cohort. Every such later change advances the dataset
revision and invalidates an old cursor. A historical `known-at` replay is not
claimed; it would require a separately reviewed cross-X7 temporal contract.
`occurred_at_precision='unknown'` or a NULL occurrence is excluded and
counted within authorized diagnostics. Exact and date precision remain
disclosed.

Per component:

1. The posted value is the line value when non-NULL.
2. If the posted value is NULL, use its current reviewed absolute
   finalization, if one exists.
3. Add all current eligible increases and subtract all current eligible
   decreases.
4. If neither original nor finalization establishes a baseline, the component
   is unknown. Adjustments cannot manufacture a baseline because the X6d
   writer already rejects adjustments against unknown components.

`merchandise_discount` NULL means unknown, so merchandise net is unknown
until merchandise is finalized. Gross and discount are returned separately;
official net merchandise is never reconstructed by silently treating a NULL
discount as zero. Shipping and tax stay separate and never enter merchandise
spend. A legitimate reviewed zero remains known zero.

## Projection and metric grain

Add a service-only `e10.official_customer_spend_contributions(...)` helper
with one row per posted transaction line. It returns original and effective
customer IDs, attribution lineage, transaction/line/source IDs, purchase kind,
 channel, location, product/configuration/copy, session/slot, currency,
 occurrence/posting precision and times, bounded
 base/finalization/adjustment/reconciliation lineage, known flags, gross,
 discount, pre-adjustment net, signed adjustment delta, official net
 merchandise, shipping, tax, and authorized-data diagnostic reason. Per-line
 lineage arrays are capped at 200 and accompanied by total counts and
 truncation flags.

The source cohort is the complete authorized eligible relation before
pagination or aggregation. A break line without one conserving product
allocation is categorized `mixed_unallocated`; no amount is copied to
multiple products. X7b adds no allocation schema because the approved source
model has none.

Add four bounded public RPCs:

1. `e10_org_customer_spend_summary`: grouped by effective customer and the
   requested `retail|break|unclassified|combined` scope. Returns gross,
   discount, pre-adjustment net, signed adjustment delta, official net
   merchandise, shipping, tax, distinct transaction/order count, distinct
   purchasing-break count, known/unknown component counts, authorized-data
   exclusion counts,
   provisional amount only as a separately labeled field, and explicit metric
   IDs/versions/grains.
2. `e10_org_customer_spend_contributions`: bounded keyset drill-down over the
   exact official line cohort with all monetary and source lineage above.
3. `e10_org_customer_provisional_activity`: a separate bounded projection of
   unposted X6a activity. Its fields and metric IDs contain `provisional`;
   it never appears in official totals.
4. `e10_org_customer_spend_lineage`: child pagination for one authorized
   posted line's adjustment, finalization, source-claim, and reconciliation
   evidence. Pages are capped at 200, query-bound, and repeat independent
   full-child counts and signed component totals. This prevents a line with
   more than 200 children from hiding an unbounded array inside a bounded
   parent page.

Summary and detail support optional effective customer, purchase kind,
location, channel, product, configuration, copy, session, and capture-source
filters. Inputs are scalar typed filters, not caller-provided SQL or arbitrary
JSON predicates. `combined` is one deduplicated union across purchase kinds,
not a sum of already grouped rows.

All optional customer, product, configuration, copy, channel, location,
capture-source, and session filters are first applied to official break lines.
`spend_per_purchasing_break` uses only those filtered lines and divides their
compatible known official break merchandise by their distinct non-NULL
break-session IDs.

The attended denominator is independent of purchases. With no sale-only
dimension filter, `spend_per_attended_break` counts every X7a-eligible
attended session for the same effective customer, organization, window,
cutoff, and attendance source, including sessions with zero purchases. An
explicit session filter may constrain both numerator and attendance because
session identity exists independently in both datasets. Product,
configuration, copy, sales channel, sale location, and capture source exist
only on sale lines in the current schema; they cannot truthfully classify
zero-purchase attendance. When any such filter is present, the attended ratio
is NULL with `ratio_status='unsupported_cohort'` rather than intersecting
attendance with purchased-session IDs or inventing dimensions. The filtered
official totals and purchasing-break ratio remain available.
Location-only authorization is itself an implicit sale-location filter even
when `p_location` is NULL, so its attended ratio is likewise
`unsupported_cohort` until an independent location-qualified attendance
dimension exists.

Official totals still include authorized purchases with a missing session ID
or no matching attendance. The response separates `known_official_subtotal`
from `complete_official_total`: the latter and both ratios are NULL unless
every merchandise component relevant to that ratio's break numerator is
known; an unrelated unknown retail component does not suppress a break ratio.
A purchasing-break ratio never divides amounts from missing-session lines by
only the known-session denominator: it returns NULL with a coverage-gap reason
or reports an explicitly labeled matching-session subtotal. An attended-break ratio is
also NULL unless every selected break line has a valid session, the filtered
attendance cohort is complete, and reviewed attendance coverage spans the
entire denominator. A selected purchase session that has no matching eligible
attendance does not shrink the independent denominator or disappear from
official spend; it makes the attended ratio NULL with
`ratio_status='purchase_session_not_observed'` and is counted only within the
caller's authorized spend scope. Otherwise the ratio status is `partial` or
`unavailable`, and authorized missing-session/unmatched-attendance counts and
known amounts are disclosed. Retail and unclassified money never enter either
break numerator. A zero denominator returns NULL. Each response returns
numerator, denominator, denominator coverage, completeness status, and grain.

Attendance-derived fields require the independent
`act.view_customer_engagement` capability in addition to financial access.
A financial-only caller still receives authorized spend, but attendance
denominators/counts are NULL with `ratio_status='engagement_not_authorized'`;
the response does not reveal whether hidden attendance exists.

## Revision, pagination, and concurrency

Extend the X7a organization reporting revision with row triggers on inserts to
transactions, transaction lines, component finalizations, adjustments,
transaction attribution decisions, customer resolution decisions,
reconciliation decisions/evidence links/source claims, and provisional
activity/attribution decisions. Immutable inputs need insert triggers only.

Every RPC:

- authorizes before and after acquiring the organization revision row;
- takes a shared lock on that row and reads projection data in the same
  transaction snapshot;
- returns dataset revision, metric version, observation cutoff, complete query
  fingerprint, and stable server-resolved cursor values;
- requires the prior revision and fingerprint on every later page;
- rejects a changed revision with SQLSTATE `40001` and a rebound query with
  SQLSTATE `22023`;
- caps summary/detail/provisional/lineage pages at 200 rows and uses the full
  explicit sort tuple plus stable UUIDs;
- computes totals and denominators from the full eligible cohort, never the
  current page. Every detail page repeats independently computed full-cohort
  totals/counts so arithmetic can be checked across a 201-row fixture.

## Security and grants

New helpers/views are service-only, RLS-protected where stored relations are
added, and closed to PUBLIC, `anon`, and `authenticated`. Public RPCs are
`SECURITY DEFINER`, born anon-closed, executable only by
`authenticated`/service role, and self-authorize active membership plus
organization-wide financial capability **or** the exact applicable location
grant. Attendance-derived fields additionally require engagement capability.
They expose no
email, handle, address, notes, payment instrument, credentials, raw payload,
or cross-organization existence oracle.

The implementation is additive. It does not replace existing customizable
roles with fixed application roles, and it does not grant every member
financial access.

## Proposed migrations

1. `20260911030000_e10_ta_x7b_spend_reporting_control.sql`
   adds the ungranted configurable capability contract, the location financial
   grant column and exact scoped predicate, service-only official/provisional
   contribution projections, bounded-lineage helpers, and revision triggers.
2. `20260911031500_e10_ta_x7b_spend_reporting.sql`
   adds the four bounded RPCs, ACLs, comments, and supporting indexes proven
   necessary by the complete-cohort queries.

No existing migration is edited. No materialized aggregate becomes
authoritative.

## Required tests

The focused suite must prove:

- $200 known merchandise minus a $50 eligible refund equals $150 official net,
  while $20 shipping and $10 tax remain separate;
- NULL discount/shipping/tax stay unknown, reviewed finalization including zero
  makes only that component known, and later deltas apply to the finalized
  baseline;
- full cancellation zeros known components, explicit reinstatement restores
  only the authorized effect, duplicate/replayed adjustments contribute once,
  and refund/resale remain separate sale/customer identities;
- $100 posted retail plus two $30 provisional break sales reports official
  $100 and provisional $60; after reviewed posting/reconciliation it reports
  official combined $160 and no duplicate provisional contribution;
- native plus imported evidence linked to one posted line contributes once;
  unlink/relink changes lineage, not money;
- four completely covered attended breaks and two posted $30 break purchases
  yield $15 per attended break and $30 per purchasing break; partial/unknown
  attendance coverage makes the first ratio NULL without erasing official
  spend;
- retail/unclassified amounts cannot enter break numerators; an explicit
  session filter constrains both datasets; a product/location/channel/source
  filter returns `unsupported_cohort` for attended ratio because no independent
  session dimension exists, while official totals remain correct; unmatched,
  missing-session, unknown-occurrence and unknown-component authorized rows are
  counted and not coerced to zero;
- organization-wide grant, location-only grant, NULL-location denial,
  unscoped location-only filtering, and no hidden-row counts are proved against
  a real second location and hostile organization; organization-wide historical
  totals retain an archived location while location-only access closes;
  location-only scope makes the attended ratio `unsupported_cohort`;
- financial-only access returns no attendance-derived count or denominator;
  engagement plus financial authority exposes only the authorized ratio;
- missing-session break amounts never divide against only known-session
  purchasing denominators, and unrelated unknown retail components do not
  suppress an otherwise complete break ratio;
- mixed/unallocated product evidence contributes once to the mixed bucket;
- current-restated selective unattribute/reattribute and whole-customer
  merge/split invalidate prior revisions without rewriting posted rows;
- one currency only, zero denominators, exact/date/unknown occurrence,
  366-day bounds, NULL inputs, stale revisions, cursor rebinding, missing
  financial capability, location denial, anon, and hostile foreign-org calls
  fail closed;
- one reader-first and one writer-first exact-backend lock proof prevent
  data/revision mismatch;
- 201 contribution rows page 200+1, with identical independent full-cohort
  totals on both pages and no page-subset arithmetic; one line with 201 child
  evidence rows exposes capped parent lineage and child pages 200+1 with exact
  full-child totals;
- timeout/cancellation rolls back cleanly and all fixture families have zero
  residue while the org0 sentinel and 35/41 inventory baseline survive.

Run clean local replay, the focused suite, X6c-X6f and X7a regressions, A7
hostile isolation, default-privilege probe, exact-head CI, then explicit
staging preflight/apply/session-pooler tests/advisors/residue and production
read-only proof. Stop at the X7b staging boundary before X7c.

## Explicit exclusions

No payment/settlement/proceeds/contribution-margin claim, currency conversion,
tax treatment, store credit, returns inventory mutation, arbitrary report
builder, UI, connector, live feed, scheduled aggregation, production write, or
commercial rule not already encoded by X6 is part of X7b.
