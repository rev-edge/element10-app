# TA-X7e staging acceptance evidence

Date: 2026-09-11

Scope: governed inventory evidence, correction-safe inventory episodes, cutoff-aware lifecycle reads, and bounded inventory valuation reads. Production remained read-only.

## Source revision and CI

- Branch: `foundation-a6`
- Exact source head: `3dab83dd559a2471fe457f774c6989ced55d6c58`
- Exact-head CI: run `34657019537`, success
- CI URL: https://github.com/rev-edge/element10-app/actions/runs/34657019537
- The CI test job passed the X7e evidence, lifecycle, valuation, temporal-regression, and exact-backend concurrency gates; A7 hostile isolation; every registered TA-X1 through TA-X7d predecessor gate; predecessor-schema compatibility; clean schema replay; and the born-locked default-privilege probe.
- The `schema-gate` and `deploy` jobs were skipped because this was a pull-request run on `foundation-a6`, not a production release from `main`.

## Guarded staging apply

- Explicit target: Supabase staging project `csmbjfmoxkexcyssntbg` only.
- Preflight through the session pooler returned database `postgres`, PostgreSQL `17.6`, the `e10` schema present, and prior migration head `20260911213745`.
- A guarded `supabase db push --db-url ... --dry-run` was attempted first. It safely refused because staging contains reconciled wall-clock migration versions from earlier MCP applies that are not local filenames.
- The documented direct-`psql` alternative was therefore used against `postgres.csmbjfmoxkexcyssntbg` on the staging session pooler at port 5432. Each migration ran in its own fail-closed transaction and its exact repository version/name was inserted into `supabase_migrations.schema_migrations` in the same transaction. No bare or linked-project push was used.
- Applied and reconciled ledger rows:
  - `20260911220834 | e10_ta_x7e0_governed_inventory_evidence`
  - `20260911221039 | e10_ta_x7e0_inventory_evidence_writers`
  - `20260911221436 | e10_ta_x7e1_inventory_lifecycle_reads`
  - `20260911221930 | e10_ta_x7e2_inventory_valuation_reads`

## Staging functional and isolation gates

All SQL suites used rollback-contained fixtures and passed through the explicit staging session pooler:

- `tests/ta_x7e0_inventory_evidence_test.sql`
- `tests/ta_x7e1_inventory_lifecycle_test.sql`
- `tests/ta_x7e2_inventory_valuation_test.sql`
- `tests/ta_x7e_temporal_regression_test.sql`
- `tests/a7_hostile_matrix_test.sql`: PASS 29/29, including the anonymous-role checks
- `tests/probe_defpriv.sql`: PASS, born-locked 4/4 and zero anonymous/PUBLIC-executable functions

The two-connection `tests/ta_x7e_concurrent_test.js` also passed through the staging session pooler. It proved:

- one winner and one revision conflict for concurrent evidence successors;
- one canonical episode root for an acquisition racing its correlated receipt;
- exact target-row blocking and post-wait authorization recheck;
- predecessor-row blocking and active-organization recheck;
- exact-command snapshot behavior with stale-state rejection on the next page; and
- mid-read authority revocation with denial on the next command.

## Security and cleanup evidence

- All five governed X7e evidence/revision tables have RLS enabled.
- Client table grants across those five tables: `0` for `anon` and `authenticated`.
- The four public X7e APIs are `SECURITY DEFINER`, fix `search_path=public`, grant `authenticated` intentionally, and deny `anon` and `PUBLIC` execution.
- Post-apply security advisors: ERROR `0`; WARN `141` total, comprising `140` authenticated `SECURITY DEFINER` API notices and the existing staging leaked-password-protection notice; INFO `104` deny-by-default RLS tables without client policies. The four new public X7e APIs account for four intended authenticated-function notices, and the five new governed tables account for five intended no-policy notices.
- Post-apply performance advisors: ERROR `0`; WARN `14` existing RLS init-plan notices; INFO comprises `224` unindexed-FK notices, `58` unused-index notices, and one connection-setting notice. These findings are recorded, not suppressed by weakening constraints or dropping protective indexes.
- Cleanup census after every suite: X7e fixture organizations `0`, X7e fixture users `0`, and rows in the four governed evidence tables `0/0/0/0`.
- Tenant-zero inventory sentinel after verification: items `35`, movements `41`, reservations `9`.
- The original 41-row movement content digest remains `82ee6d5583db1e6c58eafea84848d8a2` / `a912647c683442c28b8a1a05a136a3a48d59f58e14174810126560f09fff2b41`.

## Production read-only proof

A transaction declared `READ ONLY` against production project `ddhkkumiyidorzmajwde` returned:

- `e10` schema: absent
- migration count: `12`
- latest migration: `20260716110000`
- inventory items: `35`
- inventory movements: `41`

No production write, `main` merge, UI change, live-feed work, monitor, chatbot, secret, or unresolved commercial-rule implementation occurred.

## Acceptance boundary

The outside reviewer independently accepted this staging checkpoint at exact
commit `5d9da22ac3a8f7dc3d2df524909cd5706141ebba`. The review independently
confirmed CI run `34657638742` attempt 1 at the exact SHA; all four staging
ledger rows; table RLS and client-grant denial; public API ACLs and fixed search
paths; the episode-mismatch and unresolved-valuation guards in stored function
definitions; zero fixture residue; advisor counts; the tenant-zero `35/41`
inventory sentinel; and the production read-only state. The reviewer made no
file or database change and did not claim to rerun the mutating suites.

This acceptance closes TA-X7e staging verification only. It does not declare
the complete TA-X1 through TA-X8 objective finished. X3f supplier reads, the
approved X4 remainder, X8 seams, and final coverage/integration handoff remain.
