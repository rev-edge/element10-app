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

A compact system-catalog manifest compared application-owned function
signatures/security/ACL/search paths and all table, column, constraint, RLS/ACL
and index structure. Local and staging counts and SHA-256 values match exactly:

| Catalog | Count | SHA-256 |
| --- | ---: | --- |
| Functions and ACL/search-path metadata | 192 | `aecb12197f092a17d127302c98803a853f219c1da2638ad3e0f9389647c7f40a` |
| Tables and RLS/ACL metadata | 170 | `42439609414807b59cdb579d522e3c4c91e35be69d56ac9808288a89a78d1387` |
| Columns, types, nullability and defaults | 2042 | `5d0d0256f7819ecb25c2122713f37eaebd0a15020046911cea2e5c3b9c2d9fbc` |
| Constraints and validation state | 1671 | `0a5e0854dd2f62a34c2c3143b4ab60e7a9824b9f1fe81ec68d08d52984202dc6` |
| Index definitions | 649 | `34818e18e0ad9310d3093debff330059ba25beb148cb45222e73b2f68cfe13c6` |

This manifest excludes nonapplication system schemas. It proves the current
application schema shape, not equality of staging fixture data with an empty
local database.

Production was not contacted by the corrective and received no write.
