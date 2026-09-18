# TA-X7a staging evidence

Verified 2026-09-11 against branch `foundation-a6`, implementation commit
`b501d4fcf317d89e0ec0e77da43b405219cde7b3`.

## Code and CI

- Exact-head CI run `34551023988` completed green in 4m44s.
- The run included the focused X7a suite, all predecessor gates, A7 hostile
  isolation, clean schema replay, and the default-privileges probe.
- Independent precommit review accepted the implementation before staging.

## Explicit staging apply

- Target: staging project `csmbjfmoxkexcyssntbg` only.
- Preflight: database `postgres`; accepted X6h objects present; X7a objects
  absent; inventory baseline `35` items / `41` movements.
- Applied only `20260911023000_e10_ta_x7a_reporting_control.sql` and
  `20260911024500_e10_ta_x7a_attendance_reporting.sql` through the explicit
  Supabase staging project ID.
- Supabase-generated ledger stamps were reconciled to the repository versions.
  The staging ledger contains exactly one row for each version.

## Staging acceptance proof

The focused suite passed through the explicit staging session pooler:

```text
[proof] concurrent coverage create serialized to one assertion
[proof] report snapshot held dataset revision against concurrent writer
[proof] reader waited behind writer and rejected stale revision
TA-X7a attendance reporting: PASS
```

The suite also proved bounded 201-contributor lineage as pages of 200 and 1,
with the independent full-cohort union fixed at 600 seconds on every page;
overlap union rather than summation; timezone and DST week boundaries; stable
session assignment; distinct-session and customer-session duration grains;
zero versus unknown coverage; partial and unavailable coverage; reviewed
coverage CAS, replay, revocation and authorization; historical policy-state
behavior; attribution and customer-merge invalidation; query-bound cursors;
hostile-org and missing-capability denial; cancellation; and rollback cleanup.

Coverage assertions are immutable reviewed claims, not measured telemetry.
Every reported average declares its grain, observation cutoff, coverage state,
dataset revision, metric version, and query fingerprint.

## Post-test staging state

- `e10_attendance_coverage_assertions`: `0` rows.
- `e10_presence_policy_state_history`: `0` rows.
- `e10_presence_collection_policies`: `0` rows.
- `e10_reporting_dataset_revisions`: `1` row for the one persistent org. This
  is the designed baseline, not fixture residue.
- Persistent organizations: `1`; inventory remains `35` items / `41`
  movements.
- All three X7a control tables have RLS enabled, zero policies, and no direct
  `anon` or `authenticated` CRUD privileges.
- The coverage and policy-state immutability triggers are installed, as are
  revision triggers for policies, policy state, streams, segments, events,
  attribution, customer resolution, session bounds, coverage, and future orgs.
- The four public X7a RPCs are executable by `authenticated` and not by `anon`.
  The internal contribution helper is not client executable.

## Advisors

- Security advisor: `0 ERROR`; existing findings are `93 WARN` and `69 INFO`.
  X7a's three client-closed tables intentionally produce
  `RLS Enabled No Policy` INFO findings. Authenticated `SECURITY DEFINER`
  warnings include the four reviewed public X7a RPCs; internal helpers remain
  closed.
- Performance advisor: `0 ERROR`; existing findings are `14 WARN` and
  `228 INFO`, comprising legacy RLS initialization-plan warnings plus
  unindexed-FK, unused-index, and Auth connection-strategy information.
- Remediation references: [RLS without policies](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy),
  [authenticated security-definer functions](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable),
  [RLS initialization plans](https://supabase.com/docs/guides/database/database-linter?lint=0003_auth_rls_initplan),
  and [unindexed foreign keys](https://supabase.com/docs/guides/database/database-linter?lint=0001_unindexed_foreign_keys).

## Production untouched

Read-only production project `ddhkkumiyidorzmajwde` has no X7a table or weekly
attendance RPC, exactly `12` migrations through `20260716110000`, and `35`
inventory items / `41` movements. No production write occurred.

## Boundary and required remainder

TA-X7a is a companion-only reporting checkpoint. Authorized-platform evidence
remains quarantined until X7c defines provider normalization. Official spend,
screener, inventory/grading/population/valuation, remaining purchasing and
receiving writers, dated affiliations, and X8 remain required. No X7b work was
started in this checkpoint.
