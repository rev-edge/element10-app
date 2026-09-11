# TA-X6h staging evidence

Verified 2026-09-10/11 against branch `foundation-a6`, implementation commit `fc901adb27e7fbb6723529443b7809f053521604`.

## Code and CI

- Exact-head CI run `34548650734` completed green in 4m4s.
- The run included both X6h suites, every predecessor gate, A7 hostile isolation, a clean full migration replay and the default-privileges probe.
- Precommit functional/security review accepted after the fixtures moved to unique per-run organizations and cleanup proved every owned table empty while preserving the org0 sentinel.

## Explicit staging apply

- Target: staging project `csmbjfmoxkexcyssntbg` only.
- Preflight: database `postgres`; prior max migration `20260911014500`; no X6h table; inventory `35` items / `41` movements.
- Applied only `20260911020000_e10_ta_x6h_attendance_foundation.sql` and `20260911021500_e10_ta_x6h_attendance_access.sql` through the explicit Supabase staging project ID.
- Supabase-generated ledger stamps were reconciled to the repository versions. The ledger now contains exactly one row for `20260911020000` and one for `20260911021500`.

## Staging acceptance proof

Both suites passed through the explicit staging session pooler:

- `TA-X6h attendance foundation: PASS`
- concurrent first join serialized;
- concurrent heartbeat/leave serialized;
- provider event identity serialized across streams;
- the exact backend waited on whole-record merge and used the effective target;
- the exact backend waited on verified-identity detach and reread current evidence;
- the exact backend waited on session end and denied the heartbeat;
- `TA-X6h attendance concurrency: PASS`.

The proof includes disabled/unconfigured and stale-notice denial, membership-less admitted-viewer access, private unredeemed denial, cross-user connection/key isolation, actor/session event bounds, policy immutability and reconnect, gap-safe segments, delayed-leave expiry, fail-closed incomplete session ends, historical attribution replay, explicit unattribute, bounded keyset reads, hostile/missing-cap denial, provider chronology/correction quarantine, ACLs, no commercial side effects and strict cleanup.

Post-test staging state:

- six X6h tables have RLS enabled and zero client policies;
- all six tables are closed to `anon` and `authenticated` direct CRUD;
- six policy/evidence protection triggers are installed;
- authenticated companion writer: allowed; anon companion writer: denied;
- authenticated platform writer: denied; authenticated internal access helper: denied;
- policies/streams/segments/events/receipts/attribution decisions: all `0` rows;
- inventory remains `35` items / `41` movements.

Supabase advisors report no security or performance `ERROR`. Expected X6h findings are six deny-by-default `RLS Enabled No Policy` INFO notices and three intentional authenticated `SECURITY DEFINER` warnings for the companion writer, reviewed attribution writer and bounded read. The platform writer and internal helper are not client executable. Unindexed-FK/unused-index findings are INFO and do not alter the bounded API or isolation result.

## Production untouched

Read-only production project `ddhkkumiyidorzmajwde` still has no X6h table or companion RPC, exactly 12 migrations through `20260716110000`, and `35` inventory items / `41` movements. No production write occurred.

## Required remainder

X6h stores source-grained evidence only. Authorized-platform rows are deliberately quarantined from interval projection. TA-X7 must define provider-time normalization/promotion, overlap union, timezone/week boundaries, coverage completeness, distinct-session denominators and spend separation before any reporting claim. No UI telemetry, connector, live feed, scheduled job, retention executor, external dispatch or production work is included.
