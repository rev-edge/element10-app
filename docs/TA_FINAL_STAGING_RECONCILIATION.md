# Track A final staging reconciliation

Date: 2026-09-12

## Migration ledger audit

A direct comparison found 108 local `202609*.sql` migration files and initially
107 staging `202609*` ledger rows. Sixteen staging timestamps differ from their
current local timestamps, but their migration names match the X7d, X1b and X3c
files. Those historical timestamp renames explain the guarded CLI dry-run
refusal and were not repaired or replayed.

One local migration was genuinely absent from staging:

`20260911164840_e10_ta_x6d3_source_claim_lock_order.sql`

Before correction, the staging definition hash for
`e10_org_decide_customer_transaction_reconciliation` differed from local and
its lock-order comment was absent. This disproved staging completion for that
corrective even though later migrations and earlier X6d evidence were present.

## Explicit correction

The target preflight through the explicit staging session pooler returned:

`postgres|postgres|e10_schema=true|migration_absent=true`

The exact committed migration and ledger insert were applied together using
`psql --single-transaction` against staging project
`csmbjfmoxkexcyssntbg`. No bare linked-project command was used.

Exact ledger row after commit:

`20260911164840|e10_ta_x6d3_source_claim_lock_order|0`

The staging September ledger now contains 108 rows, matching the repository's
108 September migration files. Historical timestamp differences remain and are
identified by matching migration names rather than rewritten.

## Runtime and behavioral proof

Local and staging now have the same function-definition SHA-256 and comment:

`75d23f22b0ef1c308ff7e9bc0127f1700de5e2d0aa3b4e15c5207bde037d17f9`

`X6d.3 decision API with source-identity lock ordered before the existing reviewed decision implementation, preventing link/revoke versus post deadlocks.`

The exact staging test invocation used the explicit environment-variable URL:

```sh
cd /Users/tsconnely/dev/element10-app
set -a
. ./.env.local
set +a
STAGING_URL="postgresql://postgres.csmbjfmoxkexcyssntbg:${SUPABASE_STAGING_DB_PASSWORD}@aws-0-us-east-1.pooler.supabase.com:5432/postgres"
E10_DB_URL="$STAGING_URL" node tests/ta_x6d_customer_transaction_adjustments_test.js
psql "$STAGING_URL" -v ON_ERROR_STOP=1 -f tests/probe_defpriv.sql
```

Captured output:

```text
TA-X6d.3 customer reconciliation: PASS (unknown finalization, deterministic deltas, reviewed/durable links, ambiguity/discrepancy retention, one contribution, native trust, hostile tenant, races)
NOTICE: default-privileges probe: PASS (born-locked 4/4 + zero anon/PUBLIC-executable functions)
DO
```

The test's `finally` block deletes by its generated user, role, customer,
organization, draft, transaction and idempotency/source identifiers, commits,
then runs one aggregate residue query over those exact identifiers. The query
returned `n=0`; the test raises `X6d teardown residue` before printing PASS for
any other result. An independent post-test named-fixture query also returned:

```text
x6d_customers|0
x6d_foreign_orgs|0
x6d_roles|0
```

## Clean-local versus staging schema parity

Fresh schema-only dumps of application schemas `public,e10` were captured from
the clean local replay and staging after the corrective. Their only textual
differences were the generated dump `restrict/unrestrict` token and historical
comment/whitespace formatting inside `e10.module_bundle` and
`e10.verify_handle_claim`. The SQL behavior of those two old functions was not
changed by this correction.

A committed, reproducible system-catalog manifest now covers both application
schemas and every requested object class. Run it against the clean local replay
and the explicitly targeted staging pooler:

```sh
cd /Users/tsconnely/dev/element10-app
psql postgresql://postgres:postgres@127.0.0.1:54322/postgres \
  -X -v ON_ERROR_STOP=1 -f tests/ta_final_schema_manifest.sql \
  > /tmp/e10-local-manifest.txt
psql "$STAGING_URL" -X -v ON_ERROR_STOP=1 \
  -f tests/ta_final_schema_manifest.sql \
  > /tmp/e10-staging-manifest.txt
diff -u /tmp/e10-local-manifest.txt /tmp/e10-staging-manifest.txt
```

The manifest emits one SHA-256 row per object and deliberately does not erase
differences through whitespace normalization. It produced 5,529 catalog rows
on each target:

| Category | Local | Staging | Result |
| --- | ---: | ---: | --- |
| Function metadata, including signatures, result, language, volatility, strictness, security definer, leakproof, parallel, search-path/config and ACL | 336 | 336 | exact |
| Raw function definitions | 336 | 336 | 334 exact; 2 historical text-only exceptions below |
| Tables, relkind, RLS/forced-RLS and ACL | 170 | 170 | exact |
| Columns, types, nullability, defaults, identity and generated state | 2,042 | 2,042 | exact |
| Constraints, validation and deferrability | 1,671 | 1,671 | exact |
| Index definitions | 649 | 649 | exact |
| Noninternal trigger definitions and enabled state | 228 | 228 | exact |
| RLS policy commands, roles, mode, USING and WITH CHECK expressions | 97 | 97 | exact |

The raw manifest file hashes differ only because the following two
`function_definition` rows differ:

| Function | Local definition SHA-256 | Staging definition SHA-256 | Exact difference |
| --- | --- | --- | --- |
| `e10.module_bundle(p_key text)` | `e521ed210ee9ab593cff25f3c7a61a20e7ff062d2918993abdd574d4991800a7` | `fb908a9f71636ae7897aff386dd851ad2aea14546e95a764e9b1c12072c431cc` | Local retains explanatory comments and multiline CASE formatting; staging has the same six-key-to-`core` CASE on one line. |
| `public.e10_verify_handle_claim(p_claim_id uuid)` | `70b61bee557daead35755d17db3cccd8bd52edec84a484d192bfc0976fad32fa` | `47be731efd878feafa2d63a8dcc06fd0cbc92dfb06cd194c569dda3e02868bfe` | Local retains nine numbered inline comments; staging omits only those comments. Executable statements are identical. |

The complete schema-dump diff independently contains only those comment and
formatting changes plus the random `pg_dump` restrict/unrestrict token. No
arbitrary normalizer was used to make these exceptions disappear. The complete
manifest file hashes are local
`8f89959df5476c4bda03d7a72b6b6df250b52780dac3f5a7bb91f2d646656913`
and staging
`b990c5026c877cf2284c7035f58beca78981905f7499e00ab9e4818186c943ba`.

This manifest excludes nonapplication system schemas. It proves the current
application schema shape and explicitly records its two text-only historical
exceptions; it does not claim equality of staging fixture data with an empty
local database.

Production was not contacted by the corrective and received no write.
