# TA-X4f atomic receipt reversal staging evidence

Date: 2026-09-12  
Implementation commit: `239a47e20ee9506af193a11d6175602f34fc00a1`  
Branch: `foundation-a6`  
Environment: staging only (`csmbjfmoxkexcyssntbg`)

## Implementation and CI gates

The independent reviewer accepted the implementation and local-review gate at
the exact implementation commit above. The accepted contract is
`286f3325cd6763dd9bf82348144506e6b0b1a085`.

Exact-head CI run
[34663120859](https://github.com/rev-edge/element10-app/actions/runs/34663120859)
completed successfully. The `test` job passed; `schema-gate` and `deploy` were
skipped as intended.

## Local evidence

A clean local database reset applied the complete migration chain, including
`20260912000350_e10_ta_x4f_atomic_receipt_reversal.sql`.

```text
TA-X4f SQL contract: PASS, transaction rolled back
TA-X4f ACL: PASS
TA-X4f exact-lock races: PASS
  real X4b reservation wins against reversal
  real X4c consumption wins against reversal
  reversal wins against real X4b reservation
  post-wait authority revocation denies reversal
  same-key reversal replays exact result
  opposite multi-line order completes without deadlock
TA-X4d SQL and reversal race: PASS
TA-X4e SQL and all source/locking races: PASS
TA-X3f: PASS
TA-X5c and TA-X5c.1: PASS
A7 hostile tenant isolation: 29/29 PASS
default privilege probe: PASS
```

The X4f SQL test also proves:

- three-line full reversal with two accepted lines and one zero-accepted line;
- exact receipt-line, lot, reversal, movement, origin-event, and correction-event mapping;
- source allocation rows remain intact;
- expected-allocation fulfillment is reversed exactly once;
- stable exact replay and changed-reason rejection;
- incomplete line/lot/item topology fails with no effect;
- one consumed line blocks the complete multi-line reversal with no partial effect;
- a valid organization member cannot reverse a real foreign-organization receipt ID;
- the command table is client-closed.

## Explicit staging application

Preflight through the explicit staging session pooler returned:

```csv
database,current_user,server_version,e10_schema,organizations,prior_x4f_rows,x4e_name
postgres,postgres,17.6,true,true,0,e10_ta_x4e_source_neutral_receipt_batch
```

The guarded CLI push refused because staging contains historical
MCP-generated ledger versions that do not map one-for-one to local filenames.
No migration history repair was attempted. The migration was instead applied
through the Supabase migration API with explicit project ID
`csmbjfmoxkexcyssntbg`.

The API initially recorded generated version `20260912010048`. After asserting
that this exact generated row existed once and repository version
`20260912000350` did not exist, that one staging ledger row was transactionally
reconciled to the repository version. Final ledger proof:

```csv
version,name
20260912000350,e10_ta_x4f_atomic_receipt_reversal
```

## Staging verification

The following ran through the explicit staging session-pooler target:

```text
TA-X4f SQL contract: PASS, transaction rolled back
TA-X4f ACL: PASS
TA-X4f exact-lock races: PASS
  real reserve wait backend pid=1629598
  real consume wait backend pid=1629598
  reverse-wins reserve wait backend pid=1629598
  authority wait backend pid=1629598
  same-key wait backend pid=1629598
  opposite line order completed
TA-X4e SQL contract and ACL: PASS
TA-X4e source races: PASS, backend pid=1629608
TA-X4e locking races: PASS, backend pid=1629598
TA-X3f: PASS
A7 hostile tenant isolation: 29/29 PASS
default privilege probe: PASS
```

The repeated PID reflects session-pooler backend reuse across sequential test
cases. Each proof identifies the exact waiting backend during its own bounded
race.

Function definitions match the clean local replay:

```csv
function,local_md5,staging_md5
e10_org_reverse_receipt_batch(uuid,uuid,text,text),4c193c689e0bba230b73d5af67f82f60,4c193c689e0bba230b73d5af67f82f60
e10.capture_native_inventory_event(),580963cc02f025860fd3e02eba72fd8c,580963cc02f025860fd3e02eba72fd8c
e10.normalize_commercial_event_envelope(),d671ca0eb6ff71c04dd5ac213f5f11a8,d671ca0eb6ff71c04dd5ac213f5f11a8
```

RLS and direct table privileges:

```csv
relation,rls_enabled,anon_any,authenticated_any
e10_receipt_reversal_commands,true,false,false
```

Function ACLs:

```csv
function,security_definer,volatility,search_path,public_execute,anon_execute,authenticated_execute,service_execute
e10_org_reverse_receipt_batch(uuid,uuid,text,text),true,volatile,public,false,false,true,true
e10.capture_native_inventory_event(),true,volatile,public,false,false,false,true
e10.normalize_commercial_event_envelope(),true,volatile,public,false,false,false,true
```

Fixture cleanup and preserved production-copy counts:

```csv
fixture_users,fixture_reversal_commands,fixture_receipts,fixture_items,items,movements,reservations
0,0,0,0,35,41,9
```

## Advisor evidence

Security advisors:

```text
ERROR=0
rls_enabled_no_policy INFO=106
authenticated_security_definer_function_executable WARN=144
auth_leaked_password_protection WARN=1
```

The new command table adds one expected deny-by-default RLS/no-policy INFO.
The authenticated security-definer count remains 144. The new public RPC is
intentionally authenticated-executable and self-authorizing. No unexpected
client table or helper-function exposure exists.

Performance advisors:

```text
ERROR=0
unindexed_foreign_keys INFO=226
auth_rls_initplan WARN=14
unused_index INFO=58
auth_db_connections_absolute INFO=1
```

The two new command-table foreign keys account for the increase from 224 to 226
unindexed-FK informational findings. They are not correctness or isolation
failures and no corrective index is included in X4f.

## Production untouched proof

Production `ddhkkumiyidorzmajwde` was queried only inside `BEGIN READ ONLY`:

```csv
transaction_read_only,default_transaction_read_only,e10_schema,migration_count,latest_migration,items,movements
on,off,false,12,20260716110000,35,41
```

The transaction was rolled back. No production write occurred.

## Held boundaries

- No production or `main` change.
- No UI, live-feed, scheduled-monitor, chatbot, or collector-showcase work.
- No secret was committed or printed.
- No supplier credit, payment, settlement, write-off, over-receipt authority,
  landed-cost allocation, or unresolved commercial consequence was invented.
- X4g remains separate and must prove disposition-accepted reversal quantities,
  terminal post-reversal disposition denial, and reversal/disposition atomicity.

X4f is complete through staging and frozen pending independent staging
acceptance. X4g must not begin before that acceptance.
