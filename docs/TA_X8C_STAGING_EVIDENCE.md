# TA-X8c staging acceptance evidence

Date: 2026-09-12

Scope: dormant, service-managed outbox consumer registration, bounded leasing,
and immutable acknowledgement receipts. This checkpoint performs no external
delivery and seeds no consumer. It adds no scheduler, UI, live feed, production
change, secret, or unresolved commercial rule.

## Source revision and CI

- Branch: `foundation-a6`
- Implementation review commit: `602086471aab7adde019880de3918edac67d2849`
- Exact staging source head: `87e3e675d4b096a458ae28736f3e9d477fbfbf79`
- The only change after the reviewed implementation commit strengthens the
  positive consumer ACL test to assert `SELECT`, `INSERT`, and `UPDATE`
  individually. It does not change a migration or function.
- Independent local-review verdict: `APPROVED TA-X8c LOCAL IMPLEMENTATION` at
  `602086471aab7adde019880de3918edac67d2849`.
- Exact-head CI: run `34672627839`, success.
- CI URL: https://github.com/rev-edge/element10-app/actions/runs/34672627839

The complete registered test job passed, including TA-X8c, the hostile A7
matrix, predecessor-schema compatibility, clean schema replay, and the
born-locked default-privilege probe. Production-only jobs were skipped.

## Guarded staging apply

- Explicit target: staging project `csmbjfmoxkexcyssntbg` through its session
  pooler on port 5432.
- Preflight returned database `postgres`, PostgreSQL `17.6`, the `e10` schema
  present, prior ledger head `20260912000397`, all three X8c tables absent, and
  tenant-zero inventory `35/41/9`.
- The single additive migration and its exact ledger row ran in one transaction.
  No bare or linked-project push was used.
- Applied ledger row:
  `20260912035932 | e10_ta_x8c_dormant_outbox_claim_ack`

## Staging behavior and concurrency gates

The following passed through the explicit staging session pooler:

- `tests/ta_x8c_outbox_claim_ack_test.sql`
- `tests/ta_x8c_outbox_concurrent_test.js`
- `tests/ta_x5a_typed_intake_lifecycle_test.sql`
- `tests/ta_x5b_intake_lifecycle_writers_test.sql`
- `tests/ta_x5b_writers_concurrent_test.js`
- `tests/a7_hostile_matrix_test.sql`: PASS `29/29`
- `tests/probe_defpriv.sql`: PASS, born-locked `4/4` and zero anonymous or
  `PUBLIC`-executable functions

The SQL gate proves every specified bound, exact replay and changed-key refusal,
authoritative replay flag, inactive organization denial, disabled consumer and
removed-destination denial, claim-generation and attempt overflow refusal,
stale-token denial, delivered/retry/dead outcomes, retry and multibyte-error
bounds, immutable receipts, and the service-role ACL matrix.

The two-connection gate proves one owner for one eligible row, disjoint bounded
batches, exact claim and acknowledgement replay serialization, post-wait
consumer and destination revocation, fresh post-row-lock lease expiry, reclaim
with a new generation, and stale-token refusal. Its lock proofs identify the
exact waiting backend rather than an unrelated waiter.

## Definition identity

Local and staging `pg_get_functiondef` SHA-256 values match exactly:

| Function | SHA-256 |
| --- | --- |
| `e10.x8c_consumer_authorized(uuid,uuid,text)` | `07a7cf0de79355192b52fe4efe5fd00120fc6a46d2266e3afe8621448a000e28` |
| `e10.x8c_valid_destination_keys(text[])` | `8d78c66dfcfdc6d44bd835584b4342d244b1fff684c7a69afb2ce2bda0040686` |
| `public.e10_ack_outbox(uuid,uuid,uuid,uuid,integer,text,integer,text,text)` | `f614a87996c5b0db10f8a8081b564312733af3c78165c14fd7232b09e403cd6b` |
| `public.e10_claim_outbox(uuid,uuid,integer,integer,text)` | `290f40ec1212dd84141983e13d354c2c64d26946501d639d45a41519629f0b93` |

## RLS, ACLs and advisors

- `e10_outbox_consumers`, `e10_outbox_claim_commands`, and
  `e10_outbox_acknowledgements` have RLS enabled, zero policies, and no table
  privilege for `anon` or `authenticated`.
- `service_role` has `SELECT`, `INSERT`, and `UPDATE` on consumers, with no
  `DELETE` or `TRUNCATE`. It has `SELECT` only on both immutable receipt tables.
- Both public RPCs and both internal helpers deny `PUBLIC`, `anon`, and
  `authenticated`, grant only `service_role`, and fix `search_path=public`.
- Security advisors: ERROR `0`; INFO `117` deny-by-default RLS tables; WARN
  `155`, consisting of the unchanged `154` authenticated privileged-function
  notices plus the existing leaked-password-protection notice. The X8c delta is
  exactly three intended client-closed tables and no new privileged-function
  warning. Reference:
  https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy
- Performance advisors: ERROR `0`; WARN `14` existing RLS init-plan notices;
  INFO consists of `240` unindexed-FK notices, `57` unused-index notices, and
  one Auth connection-setting notice. X8c adds no missing-FK notice. The one
  newly unused index is expected immediately after creating a dormant protocol
  with no consumer or dispatched row. Reference:
  https://supabase.com/docs/guides/database/database-linter?lint=0001_unindexed_foreign_keys

## Cleanup and tenant-zero sentinels

The post-suite census returned:

- consumers/claim commands/acknowledgements: `0/0/0`;
- integration-outbox rows with an active claim token: `0`; and
- tenant-zero inventory items/movements/reservations: `35/41/9`.

No consumer is seeded, so the protocol remains dormant.

## Production read-only proof

An explicit `BEGIN READ ONLY` transaction against production project
`ddhkkumiyidorzmajwde` returned:

- `e10` schema absent;
- migration count `12`, latest `20260716110000`;
- inventory items/movements/reservations `35/41/9`; and
- all three X8c tables plus both public X8c RPCs absent.

The transaction rolled back. Production and `main` were not written.

## Acceptance boundary

This packet requests independent TA-X8c staging acceptance. It does not claim
external dispatch or close the final TA-X1 through TA-X8 requirements and
contracts audit.
