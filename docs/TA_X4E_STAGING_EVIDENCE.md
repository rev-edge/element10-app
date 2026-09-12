# TA-X4e source-neutral receipt batch staging evidence

Date: 2026-09-12  
Candidate commit: `6c462d7b0c292cba986f6afbc2890597978d68cb`  
Branch: `foundation-a6`  
Environment: staging only (`csmbjfmoxkexcyssntbg`)

## Gate status

The independent implementation reviewer accepted the frozen X4e candidate at
`6c462d7b0c292cba986f6afbc2890597978d68cb` before staging application.

Exact-head CI run
[34661788581](https://github.com/rev-edge/element10-app/actions/runs/34661788581)
completed successfully at that SHA. The `test` job passed. `schema-gate` and
`deploy` were skipped as intended for this branch workflow.

## Explicit staging application

The target was verified before application:

```text
project_id=csmbjfmoxkexcyssntbg
database=postgres
user=postgres
server=PostgreSQL 17.6
e10_schema=true
organizations_table=true
prior_x4e_ledger_rows=0
```

The migration was applied through the explicitly targeted Supabase staging
project. No bare `supabase db push` was used. Supabase initially recorded its
generated apply timestamp `20260912003636`; in the same staging-only workflow,
that ledger entry was transactionally corrected to the repository migration
version. The final authoritative ledger row is:

```csv
version,name
20260912000335,e10_ta_x4e_source_neutral_receipt_batch
```

## Local replay and regression evidence

A clean local database reset applied the migration chain successfully. The
following suites passed against the frozen candidate:

```text
TA-X4e SQL contract and ACL: PASS, transaction rolled back
TA-X4e source races: PASS
  void wins
  receipt wins against void
  combined PO and invoice capacity
  receipt wins against incompatible amend
  independent invoice-only capacity
TA-X4e locking races: PASS
  same-key exact-backend wait and stable replay
  post-wait authority revocation denial
  opposite item order across different supplier/location without deadlock
TA-X3f: PASS
TA-X4d: PASS
A7 hostile tenant isolation: 29/29 PASS
default privilege probe: PASS
TA-X3d1b SQL and concurrent suites: PASS
TA-X3d1d SQL and concurrent suites: PASS
TA-X5c and TA-X5c.1: PASS
TA-X6a: PASS
TA-X6g native and adversarial suites: PASS
```

## Staging verification

Tests ran through the explicit staging session-pooler target and passed:

```text
TA-X4e SQL contract: PASS, transaction rolled back
TA-X4e ACL: PASS
TA-X4e source races: PASS, exact waiting backend pid=1627449
TA-X4e locking races: PASS, exact waiting backend pid=1627452
TA-X3f: PASS
A7 hostile tenant isolation: 29/29 PASS
default privilege probe: PASS
```

The new command table is RLS-enabled and not directly available to client
roles:

```csv
relation,rls_enabled,anon_any,authenticated_any
e10_receipt_commands,true,false,false
```

The public batch API is `SECURITY DEFINER`, volatile, has a fixed `public`
search path, is not executable by `anon` or `PUBLIC`, and is executable by
`authenticated` and `service_role`. The three internal helper functions are
service-role-only and are not executable by `anon`, `PUBLIC`, or
`authenticated`.

Fixture cleanup and preserved production-copy counts:

```csv
fixture_users,fixture_commands,fixture_receipts,fixture_items,items,movements,reservations
0,0,0,0,35,41,9
```

## Advisor evidence

Staging security advisors reported:

```text
ERROR=0
WARN=144
INFO=105
```

The warnings are the existing authenticated security-definer and leaked-password
classes. X4e introduced no new warning or error. Its service-only command table
is intentionally represented by an RLS-enabled-without-policy informational
finding.

Staging performance advisors reported:

```text
ERROR=0
unindexed_foreign_key INFO=224
auth_rls_initplan WARN=14
unused_index INFO=58
auth_connection INFO=1
```

The command table adds one informational unindexed-FK finding for
`(organization_id, stock_receipt_id)`. It is not a correctness or isolation
failure and no corrective index is included in X4e.

## Production untouched proof

Production `ddhkkumiyidorzmajwde` was queried through its session pooler only
inside `BEGIN READ ONLY`. The exact result was:

```csv
transaction_read_only,default_transaction_read_only,e10_schema,migration_count,latest_migration,items,movements
on,off,false,12,20260716110000,35,41
```

The transaction was rolled back. No production write occurred.

## Held boundaries

- No production or `main` changes.
- No UI, live-feed, scheduled-monitor, chatbot, or collector-showcase work.
- No secrets committed or printed.
- No consequential unresolved commercial rule was encoded.
- Existing native inventory-event and customer-activity semantics remain intact.
- The held-closed owner decisions remain untouched.

X4e is complete through staging and is frozen pending independent staging
acceptance. X4f must not begin before that acceptance.
