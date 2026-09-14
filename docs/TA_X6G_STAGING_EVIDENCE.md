# TA-X6g staging evidence

Verified: 2026-09-11

## Revision and CI

- Implementation commit: `5938cef72b83f9787487a23f694785e629fe502f`.
- CI-stability correction: `f06c62a2a53e940e587fe261f9e18bcaccbd0b22`.
- Exact-head CI: run `34546165061`, green in 4m10s. The run includes both X6g gates, A7 hostile isolation, all TA-X1 through TA-X6 predecessor gates, clean migration replay, and the default-privilege probe.
- The first exact-head run `34545812829` exposed an expected-error promise that could reject before its later assertion under CI's unhandled-rejection mode. The correction attaches outcome handlers at query creation while retaining the exact backend lock-wait and exact error assertions. Both X6g gates then passed five consecutive local repetitions.

## Local acceptance

- Full `supabase db reset --local`: PASS through `20260911014500_e10_ta_x6g_native_break_sales.sql`.
- TA-X6a through TA-X6f regression chain: PASS.
- `tests/ta_x6g_native_break_sale_test.js`: PASS.
- `tests/ta_x6g_native_break_sale_adversarial_test.js`: PASS.
- `tests/probe_defpriv.sql`: PASS, born-locked 4/4 and zero anon/PUBLIC-executable functions.

The X6g gates prove atomic sale/event/activity capture, exact replay and mismatched reuse, monotonic slot CAS, release/resale identity, exact topology and session-end lock waits, current verified/revoked/conflicting/merged/archived customer resolution, foreign organization and real non-owner/viewer/missing-capability denial, generic-writer native-provenance refusal, malformed input bounds, and zero cleanup residue.

## Guarded staging application

- Explicit target: Supabase project `csmbjfmoxkexcyssntbg` (`element10-staging`, `ACTIVE_HEALTHY`).
- Preflight maximum migration: `20260911013000_e10_ta_x6f_posted_customer_attribution`.
- Preflight target facts: database `postgres`, user `postgres`, `e10` schema present, inventory counts `35 items / 41 movements`.
- Applied only `20260911014500_e10_ta_x6g_native_break_sales.sql` through the Supabase migration API with explicit project ID.
- The API-generated ledger version `20260911002617` was reconciled immediately to the repository filename version. Final ledger row: `20260911014500 | e10_ta_x6g_native_break_sales`.
- Staging session-pooler execution used the explicit `postgres.csmbjfmoxkexcyssntbg` target on port 5432. Both X6g suites passed and removed all transient fixtures.

Post-test staging proof:

- Ledger row: 1.
- RLS enabled on all 3 new tables; client policies: 0.
- `authenticated` and `anon` table SELECT on native sales: false.
- `authenticated` execute on the two self-authorizing RPCs: true; `anon` execute: false.
- Native append-only/managed-slot protection triggers: 4.
- Native sale/transition/receipt residue: 0.
- Inventory remains `35 items / 41 movements`.

Supabase advisors reported no ERROR findings. Expected X6g findings are the three INFO `rls_enabled_no_policy` notices for intentionally client-closed tables, two WARN `authenticated_security_definer_function_executable` notices for the intentionally client-callable self-authorizing RPCs, and one new unused-index INFO before production traffic. The explicit ACL, hostile-identity, and self-authorization gates above cover those intentional choices.

## Production read-only proof

Production project `ddhkkumiyidorzmajwde` was queried read-only after staging verification:

- native sale table: absent;
- native transition table: absent;
- commit RPC: absent;
- `e10_break_slots.native_sale_revision`: absent;
- migration count: 12;
- latest migration: `20260716110000`;
- inventory remains `35 items / 41 movements`.

No production or UI write occurred. TA-X6g remains provisional commercial evidence only and does not post spend, payment, settlement, refund, or accounting recognition.
