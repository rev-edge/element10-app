# TA-X3e staging evidence

Implementation head: `d01728dd88e692ff6f8b00d304925bd6e03dfc3a`

Migration: `20260911213745_e10_ta_x3e_commercial_comments.sql`

## Gates

- Independent pre-staging review: accepted exact implementation head.
- Local full migration replay: passed.
- Local focused tests: X3a predecessor, X3e functional, X3e concurrency, X5i event envelope, and default privileges passed.
- Exact-head CI: run `34651256183`, attempt 2 succeeded. Attempt 1 failed in the pre-existing X7a attendance timing test with `attendance_dataset_revision_stale`; the implementation was unchanged for the successful retry.
- Staging target was proven as database `postgres`, user `postgres`, with schema `e10` present and migration ledger count zero before apply.
- Apply used the explicit staging session pooler for project `csmbjfmoxkexcyssntbg`; no bare linked-project command was used.
- Ledger row: `20260911213745 | e10_ta_x3e_commercial_comments | explicit staging transaction; source commit d01728dd88e692ff6f8b00d304925bd6e03dfc3a`.

## Staging behavior

- `tests/ta_x3a_purchasing_documents_test.sql`: passed.
- `tests/ta_x3e_commercial_comments_test.sql`: passed.
- `tests/ta_x3e_commercial_comments_concurrent_test.js`: passed, exact waiting backend PID `1616505`.
- `tests/ta_x5i_versioned_event_envelope_test.sql`: passed.
- `tests/probe_defpriv.sql`: passed.
- Canonical padded/unpadded idempotency keys converged; changed payload was denied.
- One same-chain successor committed; the stale competitor was serialization-denied.
- Prepare authority revocation and organization suspension were reread after real lock waits and denied without residue.
- All four document types were exercised. PO, invoice, credit approval tuples and receipt state remained unchanged.
- The vendor projection returned only allowlisted document identity/status/reference and effective vendor bodies. Internal content, supersession metadata, actors, audit fields, costs, raw payloads, and unallowlisted JSON were absent.
- Generic event injection, malformed event links, wrong-type command keys, cross-audience, cross-document, and multi-membership cross-organization supersession were denied.

## Structure and cleanup

- `e10_commercial_comment_commands` has RLS enabled and no client table grants.
- Three public RPCs: anon false, authenticated true, service role true, `SECURITY DEFINER`, `search_path=public`.
- Three internal guards: anon false, authenticated false, service role true.
- Three required unique indexes are valid and unique.
- Fixture residue across test organizations, auth users, comments, and command rows: zero.

## Advisors

- Security: `0 ERROR`, `137 WARN`, `98 INFO`. The three new warnings are the intentional authenticated, self-authorizing public RPC endpoints. Client-closed tables intentionally report RLS-with-no-policy informational notices.
- Performance: `0 ERROR`, `14 WARN`, `280 INFO`, unchanged in severity counts from the preceding accepted checkpoint. New relation-specific informational notices include existing comments `created_by`, command `created_by`, and initially unused receipt/credit lookup indexes.
- Advisor references: [database linter](https://supabase.com/docs/guides/database/database-linter), [RLS performance](https://supabase.com/docs/guides/database/postgres/row-level-security#call-functions-with-select).

## Production read-only proof

Project `ddhkkumiyidorzmajwde` was queried read-only after staging verification:

- `e10` schema: absent
- migrations: `12`
- latest migration: `20260716110000`
- inventory items / movements: `35 / 41`

No production write, Track B change, UI work, or delivery channel was performed.
