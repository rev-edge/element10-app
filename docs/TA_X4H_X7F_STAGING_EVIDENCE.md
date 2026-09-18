# TA-X4h and TA-X7f staging evidence

Date: 2026-09-12

Branch: `foundation-a6`

Exact head: `1dbd2ec888fd1437f9f604160cd035eebc8544a0`

Environment boundary:

- Staging project: `csmbjfmoxkexcyssntbg`
- Every staging command used the explicit session-pooler URL in `STAGING_URL` or `E10_DB_URL`.
- No bare `supabase db push` was used.
- Production was queried only inside an explicit read-only transaction.

## Migration application

The X4h migration was already present in the staging ledger. X7f corrective
`20260912081500` was first proven absent, then its SQL and ledger insert were
applied together with:

```sh
cd /Users/tsconnely/dev/element10-app
set -a
. ./.env.local
set +a
STAGING_URL="postgresql://postgres.csmbjfmoxkexcyssntbg:${SUPABASE_STAGING_DB_PASSWORD}@aws-0-us-east-1.pooler.supabase.com:5432/postgres"
psql "$STAGING_URL" -v ON_ERROR_STOP=1 --single-transaction \
  -f supabase/migrations/20260912081500_e10_ta_x7f_set_based_financial_scope.sql \
  -c "insert into supabase_migrations.schema_migrations(version,name,statements) values ('20260912081500','e10_ta_x7f_set_based_financial_scope',array[]::text[]);"
```

Result:

```text
CREATE FUNCTION
REVOKE
GRANT
CREATE FUNCTION
REVOKE
GRANT
CREATE FUNCTION
REVOKE
GRANT
INSERT 0 1
```

Ledger proof:

```text
20260912043132|e10_ta_x4h_generic_lot_reservation
20260912044807|e10_ta_x7f_customer_spend_grid_v2
20260912061748|e10_ta_x7f_known_history_preflight
20260912065350|e10_ta_x7f_transaction_grained_preflight
20260912072113|e10_ta_x7f_batched_grid_projection
20260912081500|e10_ta_x7f_set_based_financial_scope
```

Migration file SHA-256:

```text
9e4a7b682016be87ab85a6cb92e204d2525b758bac935950bbcbb0aa5481586f  supabase/migrations/20260912043132_e10_ta_x4h_generic_lot_reservation.sql
c1697f502d2b445558ae40114eb06560fd744efedfdbd2bc5cd1d1c558a13408  supabase/migrations/20260912081500_e10_ta_x7f_set_based_financial_scope.sql
```

## X4h staging execution

Commands:

```sh
cd /Users/tsconnely/dev/element10-app
set -a
. ./.env.local
set +a
STAGING_URL="postgresql://postgres.csmbjfmoxkexcyssntbg:${SUPABASE_STAGING_DB_PASSWORD}@aws-0-us-east-1.pooler.supabase.com:5432/postgres"
psql "$STAGING_URL" -v ON_ERROR_STOP=1 -f tests/ta_x4h_noncard_core_test.sql

export E10_DB_URL="$STAGING_URL"
node tests/ta_x4h_noncard_reservation_concurrent_test.js
```

Output:

```text
BEGIN
NOTICE: TA-X4h non-card core: PASS (Cards disabled; apparel receipt/cost/reservation; unique used camera; no break session)
DO
ROLLBACK
TA-X4h non-card core PASS

TA-X4h generic reservation concurrency: PASS (one winner, no overcommit, command and item-row post-wait revocation, zero denied residue)
```

Residue:

```text
x4h_residue|0
x4h_users|0
```

## X7f staging execution

The full suite ran with the ordinary five-minute statement bound made explicit:

```sh
cd /Users/tsconnely/dev/element10-app
set -a
. ./.env.local
set +a
export E10_DB_URL="postgresql://postgres.csmbjfmoxkexcyssntbg:${SUPABASE_STAGING_DB_PASSWORD}@aws-0-us-east-1.pooler.supabase.com:5432/postgres"
export PGOPTIONS='-c statement_timeout=300000'
time node tests/ta_x7f_customer_spend_grid_test.js
```

Output:

```text
[timing] 100001 refusal 825ms
[timing] 100000 full report 3031ms
[timing] high-volume cursor page1 3279ms
[timing] high-volume cursor page2 4202ms
[timing] 2000-transaction 100000 full report 4582ms
[timing] 2000-transaction 100001 refusal 917ms
TA-X7f customer spend grid: PASS
total 2:59.70
```

The one-transaction fixture proves the one-key, many-line shape. The
2,000-transaction by 50-line fixture proves the many-key, 100,000-line shape.
The evidence is behavioral timing plus the reviewed source structure, not an
`EXPLAIN` execution plan. The source materializes eligible transactions once,
joins eligible lines set-wise, snapshots org-wide permission once, and uses a
deduplicated allowed-location set.

Security commands:

```sh
cd /Users/tsconnely/dev/element10-app
set -a
. ./.env.local
set +a
export E10_DB_URL="postgresql://postgres.csmbjfmoxkexcyssntbg:${SUPABASE_STAGING_DB_PASSWORD}@aws-0-us-east-1.pooler.supabase.com:5432/postgres"
node tests/ta_x7f_concurrent_auth_test.js

STAGING_URL="$E10_DB_URL"
psql "$STAGING_URL" -v ON_ERROR_STOP=1 -f tests/probe_defpriv.sql
```

Output:

```text
TA-X7f post-lock authorization: PASS
default-privileges probe: PASS (born-locked 4/4 + zero anon/PUBLIC-executable functions)
```

## Function identity and access proof

Local and staging `pg_get_functiondef` SHA-256 values were identical:

```text
e10.customer_spend_contribution_count_bounded|4ab5bab2fc1a64ad983d200b58b82847704f55e800dc5998f539210617771226|postgres,service_role
e10.customer_spend_grid_contributions|b756199b5c890a478ced2ebbbc72ccdd55d64b889d3f206498d1c9e2b5756763|postgres,service_role
e10.customer_spend_grid_diagnostics|389926932edac4137ca88b4f6533e439abac06e87a39f3a2c763a78d57c0a73e|postgres,service_role
public.e10_org_customer_spend_grid_v2|60aad63cee7de72bf88563c2e1c8825bfbad8b28dd7f8b216fa33fa6e1607900|postgres,service_role,authenticated
```

The three private helpers expose no `PUBLIC`, `anon`, or `authenticated`
execute grant. The public wrapper exposes no `PUBLIC` or `anon` grant.

## CI and cleanup

Exact-head CI run `34682691228` completed successfully at
`1dbd2ec888fd1437f9f604160cd035eebc8544a0`. Named X4h and X7f gates and
schema reproducibility passed. Deployment and production schema gates were
skipped.

Staging residue and tenant-zero sentinels:

```text
x7f_orgs|0
x7f_users|0
x7f_lines|0
tenant_zero_items|null_orgs=0|rows=35
tenant_zero_movements|null_orgs=0|rows=41
```

Production read-only proof:

```text
BEGIN
prod|e10_schema=false|migrations=12|latest=20260716110000|items=35|movements=41
ROLLBACK
```

No production write, main-branch change, UI change, external dispatch, or live
feed activation occurred.
