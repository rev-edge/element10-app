# TA-X7e implementation plan

Status: implementation candidate for consolidated review. This plan maps the
approved X7e requirements to additive contracts and tests. It authorizes no
production change, UI, connector, monitor, automatic valuation, accounting
rule, currency conversion, or default role grant.

## Authority and capability boundary

The controlling requirements are `TA_X7_REPORTING_PLAN.md` X7e,
`TA_X7E_REVIEW_CHECKLIST.md`, `EXPANSION_FRAMEWORK.md`, and
`EXPANSION_ACCEPTANCE_CASES.md`.

- `act.curate_market_analytics` authorizes reviewed grading, population, and
  estimate evidence writers. It retains zero default grants.
- `act.view_market_analytics` authorizes lifecycle, exposure, grading,
  population, and estimate reads.
- Add `financial.actual_cost.read` as an independent configurable capability
  with zero default grants. It does not broaden `act.view_financial_estimates`,
  `act.view_market_analytics`, or `act.reporting_export`. Actual-cost fields are
  returned only when the caller also holds this capability. No role assignment
  is inferred.
- All public RPCs are explicit-org, `SECURITY DEFINER`, anon/PUBLIC closed,
  self-authorizing at entry and after the report snapshot lock. Internal
  helpers and source relations are client-closed and service-only.

## X7e.0: governed evidence and revisions

Add immutable, organization-owned relations:

1. `e10_unique_item_grade_assessments`: one assessment or regrade of one
   `e10_unique_items` row. Store grader code, grade label, optional qualifier,
   optional autograph assessment, assessment and recorded timestamps,
   source kind/connection/reference, method/version, review status, reason,
   evidence, revision, supersession, idempotency fingerprint, and reviewer.
2. `e10_catalog_population_snapshots`: one dated provider population
   observation for a catalog variant, grader, grade label, population scope,
   population count, source and method/version. Population is explicitly not
   print run. Corrections append a successor.
3. `e10_valuation_evidence`: versioned estimated/index evidence targeting
   exactly one unique item or catalog variant. Store method and version,
   currency, amount, observed and recorded timestamps, source, input evidence,
   review status, and supersession. It is never a completed sale.
4. `e10_inventory_reporting_revisions`: one monotonic revision per
   organization. Triggers advance it for every dependency named below. Writers
   do not pre-lock this row before their source row, avoiding a reverse
   revision-to-source lock order.

Grade, population, and valuation evidence carries typed applicability:
`condition_state` (`raw`, `graded`, or explicit `all_conditions` only for an
aggregate), grader code, grade label, grade qualifier, and optional autograph
designation. A graded scope requires grader and grade. A raw scope forbids
them. A copy matches only exact known dimensions; unknown dimensions are
unavailable and no grade, grader, qualifier, or condition conversion is
implicit. Copy-specific valuation evidence wins over variant evidence only
when both are otherwise eligible. Remaining ties resolve by observed time,
recorded time, source key, then evidence ID, and the response discloses the
selected basis.

Every evidence table has RLS, no client table grants, append-only update/delete
guards, composite tenant foreign keys, one successor per predecessor, bounded
text/JSON, finite numeric/time checks, and current service-only
`security_invoker` projections. Writers canonicalize the idempotency key once,
take a deterministic evidence-key advisory lock followed by the target and
predecessor rows, validate same-org targets and supersession, recheck
authorization after the wait, and return stable replay. Their insert trigger
advances the reporting revision only after source locks are held.
No writer creates a source row when evidence is absent.

## X7e.1: lifecycle and exposure projection

Create a service-only projection over current eligible commercial events.
Correction chains select the terminal eligible interpretation without deleting
history. Eligibility is current-restated at a requested observation cutoff:
event occurrence must be at or before the cutoff, while a later-recorded
eligible correction may restate that occurrence. The response returns both
occurrence and recorded times. Ties order by occurrence time, recorded time,
then event ID. Eligible lifecycle events require exact/date occurrence time and an
unambiguous physical-copy subject:

- `subject_type='unique_item'` directly identifies the copy; or
- `subject_type='inventory_item'` maps only when exactly one unique item is
  attached to that organization inventory row.

Date-precision events may establish calendar ordering but never produce an
exact intraday duration; affected measures are returned unavailable with a
precision exclusion. Ambiguous quantity or identity is excluded with a counted reason. Listing
events are keyed by copy, `listing_id`, and channel. `listing_published` and
`listing_resumed` open an interval. `listing_paused`, `listing_ended`, or a
qualifying final sale closes it. `sale_committed` alone is provisional and does
not establish final sale. Final sale requires a linked posted customer
transaction for the same organization/copy, or an eligible completed-sale
market observation with exact copy identity. Release, return, resale, and
reacquisition start or end distinct ownership episodes only where linked
evidence resolves the same copy and chronology. Ambiguous/unmatched transitions
are excluded; the projection never spans earliest acquisition to latest resale
as one episode. Acquisition and physical receipt are separately labeled origins
and never silently coalesced. A disappearance never closes a listing. Duplicate opens do not add
exposure. At the requested finite cutoff, open intervals are censored. Ranges
are unioned per physical copy before duration is summed, so simultaneous
channels do not double-count.

For each copy, return distinct nullable measures and explicit availability:

- receipt/acquisition to sale or cutoff inventory age;
- receipt/acquisition to first publish intake delay;
- first publish to sale or cutoff listed span;
- unioned active exposure;
- sale state, censoring state, contributing event IDs, and exclusion reasons.

The exact-timestamp Jan 1 receipt, Jan 3 publish, Jan 4 pause, Jan 6 resume,
Jan 9 final-sale fixture
must yield age 8 days, intake delay 2 days, first-list-to-sale 6 days, and active
exposure 4 days under `[start,end)` boundaries.

## X7e.2: bounded reads

Add three JSON RPCs:

1. `e10_org_inventory_lifecycle`: explicit organization, finite cutoff,
   optional copy filter, hard limit at most 200, and revision-bound keyset
   cursor. Returns lifecycle metrics and a bounded source-event drill-down.
2. `e10_org_unique_item_evidence`: explicit organization and copy, finite
   cutoff, hard limit at most 100, and revision-bound cursor. Returns current
   and historical grade assessments, applicable population snapshots, and
   valuation evidence with provenance and freshness.
3. `e10_org_inventory_valuation_coverage`: explicit organization, method,
   method version, currency, finite closing cutoff, optional finite opening
   cutoff earlier than closing, freshness interval bounded to 3650 days, and
   hard detail-page limit at most 200. Compute totals and coverage over the
   complete filtered holding population before applying the detail-page limit.
   Select the newest eligible, reviewed, non-stale estimate for each holding at
   each cutoff without converting currency, using its grade/condition as of
   that cutoff. Return
   valued/unvalued counts, evidence age/source/method/version, population date,
   and unknown cost count. Acquisition-cost contribution is separate from
   estimate movement. Actual-cost amounts and contribution are NULL with
   `actual_cost_access='not_authorized'` unless the caller holds
   `financial.actual_cost.read`; missing authorized evidence remains
   `unknown`, never zero. Portfolio change partitions same-copy comparable
   opening-to-closing valuation movement from acquisitions, disposals, and
   uncomparable holdings. Comparable movement requires the same physical copy,
   currency, method/version, and eligible applicability at both cutoffs.
   Acquisitions and disposals are counts plus separately labeled endpoint
   values, not appreciation and not cost allocation. A disposed then
   reacquired copy is separate episodes unless explicit lifecycle evidence
   proves continuous ownership. Unknown/uncomparable counts are always
   returned.

All cursors bind organization, normalized request fingerprint, metric version,
cutoff(s), and organization revision. Each RPC executes as one top-level SQL
statement, so PostgreSQL supplies one command snapshot. It reads the revision,
all source facts, and the same revision again within that snapshot without a
`FOR SHARE` lock. A concurrent writer is therefore either wholly absent or
wholly visible; its trigger advances the revision in its own transaction. A
follow-on page compares its cursor with the then-current committed revision and
rejects stale state. Authorization is checked before source work and again
immediately before return. This avoids the revision-to-source/source-to-revision
deadlock cycle while preserving snapshot consistency.

Revision invalidators include commercial events and their corrections/schema
eligibility links; unique-item identity and inventory-item attachment; inventory
quantity/ownership state; lots, receipts, reversals, and lot-cost evidence;
posted transaction lines and attribution/correction/finalization facts used for
sale finality; market observations, supersessions, reviewed facts and
equivalences; grade assessments; population snapshots; valuation evidence; and
any reviewed applicability or source-status row consumed by the projection.
Full-dataset filtering and aggregation precede pagination. No materialized
aggregate is authoritative.

## Test mapping

| Requirement | Required proof |
|---|---|
| Lifecycle arithmetic | Exact Jan 1/3/4/6/9 values and `[start,end)` boundaries. |
| Exposure grain | Two overlapping channel intervals union once for one copy. |
| Unsold/unknown | Open listing censors at cutoff; missing occurrence time is unavailable; disappearance alone does not close. |
| Eligible history | Correction successor changes projection while both source rows remain. |
| Grading | Regrade adds a new assessment to the same copy; supersession and source remain traceable. |
| Population | Snapshot date/source/freshness returned; value never substitutes for print run. |
| Value evidence | Cost, ask, sale, and estimate remain typed; estimate creates no sale. |
| Valuation | Method/version/currency/cutoff/freshness bind result; stale or absent evidence yields unvalued. |
| Portfolio movement | Acquisition contribution and estimate movement are distinct; adding a copy cannot appear as appreciation. |
| Feed independence | Manual/import evidence works with zero connector rows. |
| Access | Hostile organization, missing market capability, missing cost capability, NULL/unbounded input, foreign cursor, stale revision, and post-lock revocation fail closed with positive controls. |
| Integrity | Same-key replay stable; different payload rejected; concurrent successors have one winner; update/delete denied. |
| Applicability | Raw, PSA 9, and PSA 10 remain distinct; regrade changes only later-cutoff applicability; unknown/ambiguous provider dimensions are unavailable. |
| Episodes | Sale/disposal/reacquisition does not bridge ownership episodes; provisional sale does not close one. |
| Portfolio arithmetic | Added copy with unchanged comparable values is acquisition only; sold and reacquired copy is not appreciation; totals precede a 200-row detail page. |
| Snapshot race | An ordinary source writer blocked mid-transaction cannot produce mixed source/revision output; its commit makes the prior cursor stale. |
| Cleanup | Every run-owned row removed and tenant-zero sentinel unchanged. |

## Delivery and stop boundary

Use additive migrations created by `supabase migration new`, one coherent
implementation commit, focused functional and two-connection tests, clean local
replay, X7d and A7 regressions, default-privilege probe, exact-head CI, explicit
staging session-pooler preflight/apply/tests, advisors, zero fixture residue,
and production read-only proof. Submit one compact evidence file linked to raw
logs. Stop at the X7e staging boundary for consolidated review.

X7e does not choose a cost-allocation method, recognize accounting/payment,
convert currency, publish a price, infer a sale from listing disappearance,
enable a provider, or grant any new capability to a role.
