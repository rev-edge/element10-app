# TA-X7b staging evidence

Date: 2026-09-11

## Scope and revision

- Branch: `foundation-a6`
- Implementation commit: `cebb6e3f128ecb62975c5223a525fb50c439c99b`
- Independent scoped review: accepted against the implementation above.
- Exact-head CI: run `34555756720`, conclusion `success`.
- Target: staging project `csmbjfmoxkexcyssntbg` only.
- Production remained read-only and unchanged.

## Guarded staging apply

The target preflight returned `postgres|postgres|t|20260911024500` through the
explicit staging session pooler. No bare linked-project command was used.

The following migrations were then applied through that same explicit URL:

- `20260911030000_e10_ta_x7b_spend_reporting_control.sql`
- `20260911031500_e10_ta_x7b_spend_reporting.sql`

Both versions are present in `supabase_migrations.schema_migrations`. The CLI
reported a post-apply local catalog-cache certificate warning after both remote
migrations completed. Direct ledger and object checks prove the apply itself
succeeded.

## Staging verification

All focused suites passed against the staging session pooler:

- `tests/ta_x7b_spend_control_test.js`
- `tests/ta_x7b_financial_permission_concurrent_test.js`
- `tests/ta_x7b_spend_reporting_test.js`
- `tests/ta_x7b_spend_reporting_concurrent_test.js`
- `tests/ta_x7b_spend_lifecycle_test.js`

The concurrency evidence proved:

- an exact blocked financial-permission backend re-read revoked authority;
- a reader-first report held its revision while the authority writer waited;
- a blocked authenticated report reader re-read and rejected revoked authority;
- a writer-first report rejected a stale revision; and
- a blocked source-component mapping caller re-read revoked authority, with no
  mapping or revision-trigger effect surviving rollback.

Direct checks confirmed the typed mapping table and bounded spend contribution
and summary RPCs exist. `anon` cannot execute the mapping writer, and
`authenticated` cannot select the mapping table directly. No temporary X7b
organization remained. The four `@x.invalid` staging auth shells predate this
batch; every X7b suite verified its own run-owned fixture cleanup.

Database lint reported the pre-existing `public.e10_slot_partition` reference to
the function-local `_slotmap` temporary relation. This batch did not create or
change that function, and the exact-head clean replay and complete CI suite
passed. No new X7b lint error was reported.

## Production proof

The read-only production query returned:

`e10_schema=false, migrations=12, latest=20260716110000, inventory_items=35, inventory_movements=41`

No production write was issued.

