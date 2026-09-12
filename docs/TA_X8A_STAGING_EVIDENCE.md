# TA-X8a staging acceptance evidence

Date: 2026-09-12

Scope: explicit actor and organization query contexts plus a closed typed
dispatcher over thirteen reviewed read operations. Production remained
read-only.

## Source revision and CI

- Branch: `foundation-a6`
- Accepted source head: `e5a387cbf32d1a1ccdf0d097d899440e8bad2780`
- Runtime migration implementation through:
  `40795290e820d75f49d9897bb7d2997f7845eac9`
- The later commit is test-only. It immediately settles the intentionally
  stale X7a reader promise before its lock poll so a fast staging rejection is
  asserted instead of becoming an unhandled Node rejection.
- Exact-head CI: run `34669156487`, success
- CI URL: https://github.com/rev-edge/element10-app/actions/runs/34669156487
- The test job passed. Production-only schema and deploy jobs were skipped.

## Guarded staging apply

- Explicit target: Supabase staging project `csmbjfmoxkexcyssntbg` through its
  session pooler at port 5432.
- Preflight returned database `postgres`, PostgreSQL `17.6`, and the `e10`
  schema present.
- Before apply, the ledger head was `20260912000365`, neither X8a migration was
  present, both X8a tables were absent, and the tenant-zero inventory sentinel
  was `35/41/9`.
- Both migrations were applied in separate fail-closed transactions. Their
  exact ledger rows are:
  - `20260912000380 | e10_ta_x8a_query_contexts`
  - `20260912000381 | e10_ta_x8a_typed_dispatcher`
- No bare or linked-project push was used.

## Functional, concurrency, and isolation gates

The following passed through the explicit staging pooler:

- `tests/ta_x8a_query_context_test.sql`
- `tests/ta_x8a_typed_dispatcher_test.sql`
- `tests/ta_x8a_context_concurrent_test.js`
- the X3f supplier workspace fixture;
- the X7a attendance fixture;
- the X7b spend fixture;
- the X7d screener and observation-drilldown fixtures;
- the X7e lifecycle and valuation fixtures;
- `tests/a7_hostile_matrix_test.sql`, `29/29`; and
- `tests/probe_defpriv.sql`, born-locked `4/4` with zero anonymous or
  `PUBLIC`-executable functions.

Together the authoritative reader fixtures exercise all thirteen dispatcher
operations. Query execution preserves the complete business-table fingerprint.
The two-connection suite proved the per-actor capacity lock, replay and revoke
authorization rechecks, expiry behind a context-row wait, expiry during a
nested market-reader wait, the final post-wait context check, and zero denied
call metadata residue.

## Definition hashes

Full `pg_get_functiondef` SHA-256 values on staging:

| Function | SHA-256 |
| --- | --- |
| `e10.purge_query_contexts(integer)` | `4d821b4b55c2974f5eed9ab789873807865f3ed20ae03a7cc3fe93eef906427a` |
| `e10.reject_query_context_command_change()` | `23f80d014a5afa73df73caa33a5ba7694b70aad0cb6ff8a857085f610df04475` |
| `e10.x8_assert_args(jsonb,text[])` | `00d0ecc6b6839655c2109073a66ee59a8546fcb145aa674e2528ca0f21461c4e` |
| `e10.x8_assert_inventory_filters(jsonb)` | `4f339164a5dd4622f5f48f563cec5c821b0b62ce4466d2322cea6869e6d850ed` |
| `e10.x8_query_context_actor(uuid,uuid,boolean)` | `da045f3b8f68851c5fa3f197cceb352809284c048f90fb1e2ea52cf90f9b02bc` |
| `e10.x8_query_envelope(...)` | `a36a173052d7df8d159cc9a536f7c655328dc4a6185f9e9fb1da3d2ab72fac26` |
| `e10.x8_redact_inventory_result(jsonb)` | `b5ea036dc40c80626bb085a4b6b43fd9d9006cd54034744faeb4b3333b6fee4e` |
| `e10.x8_result_sources(text,jsonb)` | `fdf71907e2884f635f7c742f492b683237a2b3694c4649edb3b607d03af48472` |
| `e10.x8_validate_json(jsonb,integer)` | `2f5ea2cffa28c78d011a721bf12368090598896bc316838f1dcc52b1988a372b` |
| `public.e10_org_create_query_context(...)` | `825372c28a9098f750d72bb85001382818d3f76583bc49c974ff383c445e7d8e` |
| `public.e10_org_revoke_query_context(...)` | `15dd780a1f1c14ce03dc807ee0958940ca8683fb285875ad71bca70611304d09` |
| `public.e10_org_typed_query(...)` | `842ad30e6e4a098fc66d0b33666411ab1dfdbaecafae00ae64a62b6e395fbb2a` |

The reviewer independently confirmed every full definition hash matches local
and staging.

## Access controls and advisors

- `e10_query_contexts` and `e10_query_context_commands` have RLS enabled,
  zero policies, and service-role-only table access.
- Nine internal `e10` helpers are `SECURITY DEFINER` and service-role-only.
- Three public RPCs are `SECURITY DEFINER`, executable by `authenticated` and
  `service_role`, and not executable by `anon` or `PUBLIC`.
- Security advisors: ERROR `0`; INFO `110` deny-by-default RLS tables; WARN
  `149`, comprising `148` intentional authenticated `SECURITY DEFINER` notices
  and the existing leaked-password-protection notice.
- Performance advisors: ERROR `0`; WARN `14` existing RLS init-plan notices;
  INFO `292`, comprising `235` unindexed-foreign-key notices, `56`
  unused-index notices, and one Auth connection-setting notice.

## Cleanup correction and sentinels

The first staging X7a fixture run rejected its intentionally stale reader fast
enough to terminate Node before its `finally` cleanup. The audit identified
only run `e06ab3cf-dbed-4bbc-b3fd-bab72b214344`, including its two exact
fixture organizations, two users, query context and command, and associated
attendance rows. No process owned the fixture.

A fixture-only transaction through the guarded staging pooler deleted rows
from every `public` or `e10` base table whose `organization_id` matched either
exact fixture organization, then deleted those organizations and exact fixture
users. The self-failing post-cleanup census proved:

- failed-run fixture organizations: `0`;
- failed-run fixture users: `0`;
- matching organization rows across all `public` and `e10` base tables: `0`;
- total query contexts and commands: `0/0`;
- orphan query contexts and commands: `0/0`; and
- tenant-zero inventory sentinel: `35/41/9` unchanged.

The test-only promise-settlement correction passed locally and on staging, and
the successful run completed its ordinary cleanup.

## Production read-only proof

An explicit `BEGIN READ ONLY` transaction against production project
`ddhkkumiyidorzmajwde` returned:

- `e10` schema absent;
- migration count `12`, latest `20260716110000`;
- inventory items/movements `35/41`;
- `e10_query_contexts` absent; and
- `e10_org_typed_query` absent.

The transaction rolled back. No production write, `main` merge, UI work, live
feed, scheduled monitor, chatbot behavior, secret, or unresolved commercial
rule was introduced.

## Independent acceptance

The outside reviewer independently accepted TA-X8a staging at exact commit
`e5a387cbf32d1a1ccdf0d097d899440e8bad2780`. The reviewer independently
confirmed the exact-head CI result, ledger, all twelve definition hashes,
ACL/RLS state, advisor counts, cleanup census, tenant-zero sentinels, and the
production read-only proof.

This closes TA-X8a only. TA-X8b and TA-X8c remain required before the expanded
Track A goal is complete.
