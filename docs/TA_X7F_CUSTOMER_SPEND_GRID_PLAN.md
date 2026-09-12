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

The response will include:

- the existing per-customer official-spend fields and unknown-component statuses;
- customer display name, without contact or identity-channel data;
- `full_cohort_totals` computed after every line-level and aggregate filter but before pagination;
- `coverage` with mode, requested bounds, earliest eligible contribution, effective coverage start/end, observation cutoff, and the explicit limitation `known_recorded_posted_history_only`;
- selected sort, dataset revision, and query fingerprint;
- a next keyset cursor when more matching rows exist.

Aggregate min/max filtering uses `known_official_subtotal`. It never coerces a customer's incomplete `complete_official_total` into a known value. Currency remains a single required ISO-style three-letter input; currencies are never combined.

## Stable pagination, totals, and export

All authorization, contribution selection, customer aggregation, channel and other line filters, aggregate spend filters, and supported sorting execute in PostgreSQL before the page limit. Every sort has `effective_customer_id` as its final unique tie-breaker. NULL display names sort after known names; numeric ordering uses the explicitly returned known subtotal and UUID tie-breaker.

The query fingerprint binds organization, actor authorization scope, window mode and bounds, cutoff, currency, every line and aggregate filter, sort, and dataset revision. A cursor is rejected if any bound input, authorization scope, or revision changes. A cursor row must still exist in the filtered cohort.

There is no unbounded export RPC. Export means traversing this same bounded function to exhaustion with its returned cursor. Tests must prove that the concatenated traversal equals the complete authorized filtered cohort and that totals remain identical on every page.

## Typed query seam

Extend the existing X8 allow-listed `customer.spend_summary` operation to accept the new window mode, aggregate filters, sort, and typed cursor and dispatch to `e10_org_customer_spend_grid_v2`. Existing callers that send the original argument set continue to dispatch to `e10_org_customer_spend_summary`; use of any v2-only argument selects v2. Unknown keys remain rejected. X8 redaction remains limited to effective customer IDs and cannot expose contact fields.

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
7. duplicate-source reconciliation, additive refunds/corrections, purchase-kind separation, unknown merchandise, shipping and tax, currency isolation, and coverage disclosure retain X7b semantics;
8. a restricted location reader sees only authorized-location contributions and totals, while a cross-org actor is denied;
9. X8 accepts the exact new allow-list, rejects unknown arguments, preserves v1 dispatch for old callers, and returns no customer contact data;
10. all fixtures and authorization grants are removed after the test.

Verification sequence after approval: clean local replay, X7f gate, X7b/X7c/X8a regressions, A7 hostile matrix, default-privilege probe, exact-head CI, explicit staging-target preflight and apply, staging rerun, definition/ACL/advisor evidence, fixture-residue proof, and read-only production-untouched proof. Stop at the X7f staging boundary for independent review.

## Recovery

Before staging apply, save exact definitions and ACLs for the X8 dispatcher and every function replaced. Recovery is a forward additive migration that restores those definitions and removes the new v2 function only after confirming no caller depends on it. Never edit an applied migration.
