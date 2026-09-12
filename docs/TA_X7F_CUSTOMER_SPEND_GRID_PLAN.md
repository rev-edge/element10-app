# TA-X7f Customer Spend Grid and Known-History Plan

Status: PROPOSED, implementation blocked pending review.

## Defect and authority

`EXPANSION_ACCEPTANCE_CASES.md` requires a matching customer beyond page one to appear when spend and channel filters are combined, with totals and export using the same full-authorized semantics. `EXPANSION_FRAMEWORK.md` also requires official lifetime spend over eligible deduplicated posted lines in known history, with coverage and completeness disclosed.

The current `public.e10_org_customer_spend_summary` is insufficient because it:

- accepts line-level channel filtering but no aggregate spend-range filter or supported grid sort;
- applies UUID pagination after aggregation;
- rejects every interval longer than 366 days; and
- exposes no explicit known-history coverage contract.

The existing X7b function and its callers remain supported. TA-X7f is additive and does not change posting, attribution, deduplication, correction, currency, or authorization rules.

## Additive database contract

Add a versioned `public.e10_org_customer_spend_grid_v2` SECURITY DEFINER function. It will reuse `e10.official_customer_spend_contributions` as the only monetary contribution source and accept the existing organization, cutoff, currency, customer, purchase-kind, location, channel, product, configuration, copy, session, capture-source, timezone, and week-start inputs plus:

- `p_window_mode text`: allow-list `bounded` or `known_history`;
- `p_from timestamptz` and `p_to timestamptz`: required for `bounded`; `p_from` must be NULL for `known_history`; `p_to` remains the exclusive finite report end;
- `p_min_known_official_subtotal numeric` and `p_max_known_official_subtotal numeric`: optional aggregate filters applied after customer aggregation and before pagination;
- `p_sort text`: allow-list `customer_id_asc`, `display_name_asc`, `known_official_subtotal_asc`, or `known_official_subtotal_desc`;
- a typed keyset cursor containing the selected sort value and effective customer UUID, plus expected dataset revision and query fingerprint;
- `p_limit integer` bounded to 1 through 200.

For `known_history`, the function derives the lower bound from the earliest eligible, authorized, currency-matching posted contribution before the supplied cutoff and report end. It does not manufacture a business start date and does not remove the finite observation cutoff. If no eligible contribution exists, items and totals are empty and coverage is reported as empty rather than complete history.

Attendance ratios remain available only in `bounded` mode because the current attendance denominator has a bounded interval contract. In `known_history` mode the monetary fields are computed across recorded history, while `attended_breaks` and `spend_per_attended_break` are NULL and `attended_ratio_status` is `unsupported_known_history_window`. The implementation must not call the bounded attendance helper for that mode, truncate attendance, or combine independently computed annual denominators.

The response will include:

- the existing per-customer official-spend fields and unknown-component statuses;
- customer display name from the org-private `e10_customers.display_name` field, without contact or identity-channel data; access is covered by the same financial authorization as the grid and does not grant direct table access;
- `full_cohort_totals` computed after every line-level and aggregate filter but before pagination;
- `coverage` with mode, requested bounds, earliest eligible contribution, effective coverage start/end, observation cutoff, unknown-occurrence count, authorized unattributed contribution count, and explicit limitations `known_recorded_posted_history_only` and `source_history_completeness_unknown`;
- selected sort, dataset revision, and query fingerprint;
- a next keyset cursor when more matching rows exist.

Aggregate min/max filtering uses `known_official_subtotal`, including zero for an unknown-only customer, while retaining its nonzero unknown-component counts and NULL `complete_official_total`. It never coerces incomplete spend into a complete value. Currency remains a single required ISO-style three-letter input; currencies are never combined. The earliest recorded eligible contribution is provenance, not evidence that earlier source history was imported.

## Stable pagination, totals, and export

All authorization, contribution selection, customer aggregation, channel and other line filters, aggregate spend filters, and supported sorting execute in PostgreSQL before the page limit. Every sort has `effective_customer_id` as its final unique tie-breaker. Display-name ordering is `lower(display_name) COLLATE "C"`, then original `display_name COLLATE "C"`, then UUID, with NULL names last. Numeric ordering uses the explicitly returned known subtotal and UUID tie-breaker.

Add an AFTER INSERT OR UPDATE OF `display_name`, `status` OR DELETE reporting-revision trigger on `e10_customers`. A rename, archive, merge-visible state change, or deletion therefore invalidates every outstanding grid cursor before the next page can be read.

The query fingerprint binds organization, actor authorization scope, window mode and bounds, cutoff, currency, every line and aggregate filter, sort, and dataset revision. A cursor is rejected if any bound input, authorization scope, or revision changes. A cursor row must still exist in the filtered cohort.

There is no unbounded export RPC. Export means traversing this same bounded function to exhaustion with its returned cursor. Tests must prove that the concatenated traversal equals the complete authorized filtered cohort and that totals remain identical on every page.

Known-history execution has a fixed server-owned ceiling of 100,000 eligible contribution rows per request. The projection reads at most 100,001 qualifying rows under the finite cutoff; finding the extra row fails with `customer_spend_known_history_resource_limit` and returns no partial result. The ceiling is not caller-adjustable. Supporting indexes and the existing organization/currency/time predicates bound the lookup; normal database statement timeouts remain an additional fail-closed limit. No row, period, or customer is silently omitted.

## Typed query seam

Extend the existing X8 allow-listed `customer.spend_summary` operation to accept the exact v2-only keys `window_mode`, `min_known_official_subtotal`, `max_known_official_subtotal`, `sort`, and `cursor`. Existing callers that contain none of those keys continue to dispatch unchanged to `e10_org_customer_spend_summary`. Presence of `window_mode` selects v2 and requires the v2 argument contract. Any other v2-only key without `window_mode`, any v1 `after_customer_id` combined with v2 inputs, or a cursor shape from the other version is rejected. Unknown keys remain rejected. X8 redaction remains limited to effective customer IDs and cannot expose names or contact fields.

## Authorization and safety

- Preserve `e10.can_view_any_customer_financials(p_org)` and location-scoped financial access exactly.
- Recheck authorization after acquiring the shared dataset-revision row lock, matching X7b's anti-revocation pattern.
- Reuse current effective-customer resolution, deduplication, posted-adjustment, refund, and correction logic. Do not sum separately paged reports or yearly distinct counts.
- Revoke execution from PUBLIC and anon; grant authenticated and service_role only. The internal contribution helper remains private.
- Add no product, UI, production, live-feed, scheduling, chatbot, or commercial-rule behavior.

## Required verification

Create a dedicated X7f SQL/Node gate with more than 200 effective customers and a target customer beyond page one. It must prove:

1. channel plus minimum/maximum spend filters find the target after server-side aggregation;
2. each supported sort is stable, correctly tied by UUID, and traverses without duplicates or omissions;
3. full-cohort totals are identical on every page and equal an independently computed authorized expectation;
4. bounded export traversal returns exactly the same cohort and ordering as the grid;
5. changing spend bounds, channel, sort, cutoff, actor scope, or dataset revision rejects an old cursor;
6. known-history mode includes eligible posted rows separated by more than 366 days while bounded mode retains the 366-day guard;
7. with engagement authority enabled, known-history monetary totals remain correct while attendance fields are explicitly unavailable; no bounded attendance helper result is presented as lifetime;
8. duplicate-source reconciliation, additive refunds/corrections, purchase-kind separation, unknown merchandise, shipping and tax, currency isolation, and coverage disclosure retain X7b semantics, including an unknown-only customer whose known subtotal is zero and whose unknown counts remain visible under aggregate bounds;
9. missing import-history completeness is reported unknown, and unknown-occurrence plus authorized-unattributed diagnostics are disclosed rather than hidden;
10. a display-name rename between pages advances the dataset revision and rejects the old cursor; deterministic collation, NULL ordering, and a contact-restricted financial reader are proved;
11. 100,000 eligible contributions succeed, 100,001 fail with the resource-limit error, and no partial result is returned;
12. a restricted location reader sees only authorized-location contributions and totals, while a cross-org actor is denied;
13. X8 accepts the exact new allow-list, rejects mixed-version arguments and cursor rebinding, preserves byte-for-byte v1 dispatch behavior for old callers, and returns no customer name or contact data;
14. all fixtures and authorization grants are removed after the test.

Verification sequence after approval: clean local replay, X7f gate, X7b/X7c/X8a regressions, A7 hostile matrix, default-privilege probe, exact-head CI, explicit staging-target preflight and apply, staging rerun, definition/ACL/advisor evidence, fixture-residue proof, and read-only production-untouched proof. Stop at the X7f staging boundary for independent review.

## Recovery

Before staging apply, save exact definitions and ACLs for the X8 dispatcher and every function replaced. Recovery is a forward additive migration that restores those definitions and removes the new v2 function only after confirming no caller depends on it. Never edit an applied migration.
