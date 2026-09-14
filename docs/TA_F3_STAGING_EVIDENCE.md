# Track A final F3 staging evidence

Date: 2026-09-12

Branch head tested: `d0d097f2398eb7339f6ecd212c7d70d4a3733c6a`

Exact-head CI: run `34683432065`, completed successfully. The combined F3
proof ran inside the named TA-X7d gate. Schema reproducibility and the full test
job also passed. Deployment and production schema gates were skipped.

The staging test used only the explicit staging session-pooler target:

```sh
cd /Users/tsconnely/dev/element10-app
set -a
. ./.env.local
set +a
STAGING_URL="postgresql://postgres.csmbjfmoxkexcyssntbg:${SUPABASE_STAGING_DB_PASSWORD}@aws-0-us-east-1.pooler.supabase.com:5432/postgres"
psql "$STAGING_URL" -v ON_ERROR_STOP=1 \
  -f tests/ta_x7d2_cross_product_rookie_psa9_test.sql
```

Raw result:

```text
BEGIN
DO
ROLLBACK
TA-X7d.2 F3 cross-product rookie PSA 9 public pagination PASS
```

The rollback fixture proves the public reader, under the real authenticated SQL
role and JWT, applies the combined subject, reviewed rookie designation, graded
condition, PSA grader, and grade 9 predicates. Two matching variants belong to
the same subject across distinct releases and manufacturers. Limit-one cursor
traversal reaches the second match without duplication and preserves the query
fingerprint and organization/catalog revisions. Unknown-rookie, wrong-grade,
and wrong-subject variants are excluded. Changed-filter cursor reuse and a
foreign-organization reader are denied.

Post-rollback residue:

```text
f3_orgs|0
f3_users|0
```

No migration, staging data, production, main-branch, UI, external dispatch, or
live-feed change was made by F3.
