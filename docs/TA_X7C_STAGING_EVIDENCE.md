# TA-X7c staging evidence

Verified 2026-09-11 against branch `foundation-a6` at
`2ee817e2c26408555bd0ba6b4d9658f4524c4869`.

## Review, replay, and CI

- The policy, immutable-run, dependency-fingerprint, normalization-runner,
  bounded-read, and exact-lock checkpoints were independently reviewed and
  accepted before staging.
- A clean local migration replay completed through
  `20260911043000_e10_ta_x7c_provider_reporting_reads.sql`.
- Exact-head CI run `34614844131` completed with conclusion `success`, including
  every X7c suite, predecessor gates, A7, schema replay, and default privileges.
- The local X6h, X7a, X7b, X7c, A7 29/29, and default-privilege regressions all
  passed again before staging.

## Explicit staging apply

- Target: staging project `csmbjfmoxkexcyssntbg` only.
- Read-only preflight through the session pooler returned
  `postgres|postgres|t|20260911031500`.
- No bare linked-project command was used. `supabase db push` received the
  explicit staging session-pooler URL.
- The apply installed exactly:
  - `20260911033000_e10_ta_x7c_provider_normalization_control.sql`
  - `20260911034500_e10_ta_x7c_provider_normalization_runs.sql`
  - `20260911040000_e10_ta_x7c_provider_dependency_fingerprint.sql`
  - `20260911041500_e10_ta_x7c_provider_normalization_runner.sql`
  - `20260911043000_e10_ta_x7c_provider_reporting_reads.sql`
- Direct ledger queries show one row for every repository version above. The
  CLI emitted its known post-apply local pg-delta certificate-cache warning
  after all five remote migrations completed; direct ledger, object, and test
  evidence proves the remote apply succeeded.

## Staging behavior

All seven X7c suites passed through the explicit staging pooler:

- policy review and policy-writer concurrency;
- immutable run/child integrity;
- deterministic dependency fingerprinting;
- provider-time normalization and edge cases; and
- exact-lock runner/read concurrency and hostile organization isolation.

The proofs cover correction lineage, provider-time ordering, bounded late
arrival, coverage and policy clipping, quarantine reasons, gap-safe expiry,
overlap union, source-separated companion/provider summaries, query-bound
cursors, explicit rebuild-required states, current attribution, provider and
cutoff coexistence, concurrent idempotency, post-wait authority checks, and a
raw correction committed while a runner waits.

The complete staging X6h, X7a, X7b, A7, and default-privilege regression set
also passed. After teardown, direct checks returned:

`x7c_residue,0,0,0,0`

for policy decisions, runs, normalized intervals, and quarantine rows.
Persistent baseline remains one organization, 35 inventory items, and 41
inventory movements.

All four X7c public evidence tables have RLS enabled and no direct `anon` or
`authenticated` CRUD privilege. The policy reviewer and three bounded reads
are authenticated, self-authorizing RPCs and anon-closed. The normalization
runner is service-only. Internal fingerprint, coverage, freshness, trigger, and
validation functions remain client-closed.

## Advisors

- Security: `0 ERROR`, `103 WARN`, `75 INFO`. The new findings are the expected
  reviewed authenticated `SECURITY DEFINER` API notices and deny-by-default RLS
  tables; leaked-password protection and older client RPC notices predate X7c.
- Performance: `0 ERROR`, `14 WARN`, `242 INFO`. The warnings remain the legacy
  RLS initialization-plan set; informational findings are unindexed-FK,
  unused-index, and Auth connection-strategy notices.
- References: [RLS without policies](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy),
  [authenticated security-definer functions](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable),
  [RLS initialization plans](https://supabase.com/docs/guides/database/postgres/row-level-security#call-functions-with-select),
  and [unindexed foreign keys](https://supabase.com/docs/guides/database/database-linter?lint=0001_unindexed_foreign_keys).

## Production and boundary

The production query was read-only and returned:

`e10_schema=false, migrations=12, latest=20260716110000, inventory_items=35, inventory_movements=41, x7c_runs=false`

No production write occurred. TA-X7c enables no connector, collector, feed,
scheduled process, client telemetry, UI, or external delivery. X7d and X7e
remain required before TA-X7 is complete.
