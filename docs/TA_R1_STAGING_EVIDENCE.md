# TA R1 staging evidence

Date: 2026-09-12

Status: submitted for independent review, not self-accepted.

## Scope and commits

- R0 evidence preservation: `43e1bf5`
- Initial R1 runtime correction: `fc6ca6d`
- Receipt-origin test contract correction: `bee4ce1`
- R1 evidence and serialization follow-up: `6aa9a70`
- Branch: `foundation-a6`
- Production and `main`: not contacted or changed.

## Additive migrations

```text
2995adcd5cf0cb3054cf924ac38cb43a262b9335151bb65d7c18f043f832321e  20260912140932_e10_ta_r1_x4_authority_and_reversal_corrective.sql
52f9000627edddd044b1ccd9ffc30b17b9cbb56d4c4c5aac18a6d7b94e7c6f6c  20260912143252_e10_ta_r1_origin_evidence_serialization.sql
```

Staging ledger:

```text
20260912140932|e10_ta_r1_x4_authority_and_reversal_corrective
20260912143252|e10_ta_r1_origin_evidence_serialization
```

Both were applied to staging project `csmbjfmoxkexcyssntbg` through the explicit
session-pooler URL. The target preflight returned `postgres|t` for database name
and existence of the `e10` schema. No bare linked-project push was used. The
known renamed-migration ledger mismatch made `supabase db push --db-url` refuse
before writing, so each new additive migration and its ledger row were applied
atomically with `psql --single-transaction` against the explicit staging URL.

## Local replay and exact-head CI

`supabase db reset` applied every migration through `20260912143252` cleanly.
The focused local suite passed:

```text
TA-X4d receipt posting: PASS
TA-X4d receipt races: PASS (reservation floor; post-lock capability; zero residue)
TA-X4f atomic receipt reversal: PASS
TA-X4f reversal races: PASS
TA-X4g reviewed receipt disposition: PASS
TA-X4g disposition races: PASS
TA-X5c native action linkage: PASS
TA-X5c.1 source time + receipt-origin/reversal linkage: PASS
default-privileges probe: PASS (born-locked 4/4 + zero anon/PUBLIC-executable functions)
```

Exact-head CI for `6aa9a7034d150db3e44c22d87ed7e6effb325df2` passed:
https://github.com/rev-edge/element10-app/actions/runs/34699893109

## Staging commands and results

Secrets are replaced with placeholders. Commands were run from the repository
root with `ON_ERROR_STOP=1`.

```text
E10_DB_URL=postgresql://postgres.csmbjfmoxkexcyssntbg:<redacted>@aws-0-us-east-1.pooler.supabase.com:5432/postgres
node tests/ta_x4d_receipt_reverse_concurrent_test.js
TA-X4d receipt races: PASS (reservation floor; post-lock capability pid=1692007; zero residue)

node tests/ta_x4g_receipt_disposition_concurrent_test.js
TA-X4g disposition races: PASS (initial/CAS/reversal, compatibility reversal, origin evidence, authority/location/org rereads, replay; waiter pid=1692007)

psql "$E10_DB_URL" -v ON_ERROR_STOP=1 -f tests/ta_x5c_native_movement_events_test.sql
TA-X5c native action linkage: PASS
TA-X5c.1 source time + receipt-origin/reversal linkage: PASS

psql "$E10_DB_URL" -v ON_ERROR_STOP=1 -f tests/probe_defpriv.sql
default-privileges probe: PASS (born-locked 4/4 + zero anon/PUBLIC-executable functions)
```

The X4d and X4g suites use two real connections, set the caller connection to
`ROLE authenticated`, prove its exact PID is waiting, revoke mutable authority,
release the blocking row, require SQLSTATE `42501`, and assert no denied command,
event, movement, reservation, transition, lot or item effect remains as applicable.
The matrix covers:

- current lot reserve: capability revoked after the final item-row wait;
- current lot consume: membership suspended after the final item-row wait;
- current lot release: organization suspended after the final item-row wait;
- PO-line receive: capability revoked after the final item-row wait;
- batch reversal: location grant removed after the final item-row wait;
- legacy single reversal: capability revoked after the final item-row wait;
- legacy reserve: capability revoked after the item-row wait;
- legacy release: membership suspended after the item-row wait;
- legacy consume: organization suspended after the item-row wait;
- historical origin repair: capability revoked while waiting on the serialized
  receipt row, with zero origin or command residue.

Functional receipt evidence includes actual X4d `e10_org_receive_po_line` cases:

- zero accepted plus quarantined quantity, damage disposition, batch reversal;
- zero accepted plus quarantined quantity, accept disposition, legacy-name
  reversal delegated to the batch implementation;
- exact retries for both reversal names;
- one PO allocation per source line, final item quantity zero, no phantom stock;
- a separately constructed historical originless receipt repaired with
  `captured_retroactively=true`.

New receipts record `captured_retroactively=false`. Historical compatibility
repair records `true`. Receipt-origin creation locks the receipt row, validates
that a matching origin exists after any uniqueness conflict, and rechecks
authority after the lock before proceeding.

## ACL and cleanup

For the nine public compatibility/current writers, staging reports:

```text
anon executable=0|authenticated executable=9|service_role executable=9
```

`e10.ensure_receipt_origin_evidence(uuid,uuid)` is service-role-only.

Post-suite staging cleanup:

```text
receipts|0
movements|0
events|0
test_users|0
```

## Advisors

Post-apply Supabase advisors:

```text
security ERROR=0
security INFO rls_enabled_no_policy=120
security WARN authenticated_security_definer_function_executable=159
security WARN auth_leaked_password_protection=1
performance ERROR=0
performance WARN auth_rls_initplan=14
performance INFO unindexed_foreign_keys=242
performance INFO unused_index=57
performance INFO auth_db_connections_absolute=1
```

The R1 migrations add no table, index, RLS policy or new authenticated public
entry point. The public functions keep their prior client signatures and ACLs;
the new origin helper is not client executable. The remaining advisor findings
are the existing registered classes, and no advisor reports an error.
