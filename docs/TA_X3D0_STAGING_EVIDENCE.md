# TA-X3d.0 Staging Evidence

Date: 2026-09-11

## Reviewed source

- Branch: `foundation-a6`
- Exact implementation head: `bf434dac5094c1d326c629154311184f40b946e0`
- Exact-head CI: run `34641410776`, success
- Independent review: ACCEPT on the exact head
- Staging project: `csmbjfmoxkexcyssntbg` (`element10-staging`, PostgreSQL 17.6)
- Production project: `ddhkkumiyidorzmajwde`, read-only and unchanged

## Apply path

The CLI remains linked to production, so no bare remote command was used. The target was first proven through the staging session pooler as database `postgres`, PostgreSQL 17.6, with the `e10` schema present. The staging migration ledger contains earlier MCP wall-clock versions that do not share all repo filenames, so a bulk push was intentionally not used.

The reviewed foundation migration was applied through the explicit staging session-pooler URL in a single transaction. Each of the 17 concurrent-index migrations was then applied through its own autocommit connection. The exact repo versions were recorded in `supabase_migrations.schema_migrations`:

- `20260911193428`
- `20260911193720`
- `20260911193801` through `20260911193816`

Ledger proof: 18 rows, minimum `20260911193428`, maximum `20260911193816`.

## Functional and concurrency proofs

The transactional staging suite reported:

- `TA-X3d.0 financial workflow foundation: PASS`
- `TA-X3d.0 fail-closed ACL: PASS`

It covers required identity, normalized duplicate rejection, metadata completeness, document-command target integrity, connected/manual reconciliation separation, exact command/event linkage, allocation and release evidence, cross-org rejection, immutability, RLS, and ACL closure.

The two-connection staging suite proved that backend PID `1607678` waited on the exact normalized manual-identity advisory lock. One insert committed and the competing normalized duplicate failed with SQLSTATE `23505`. The suite reported `TA-X3d.0 concurrent manual identity: PASS (fixture-free)`.

Post-test residue for the concurrency supplier fixture: zero rows.

## Schema and security proofs

- New client-closed tables: 5
- New tables with RLS enabled: 5
- New tables directly accessible to `anon`: 0
- New tables directly accessible to `authenticated`: 0
- New guard functions: 6
- Guard functions executable by `anon`, `authenticated`, or `PUBLIC`: 0
- Concurrent indexes expected: 17
- Concurrent indexes valid: 17
- Concurrent indexes ready: 17

Supabase advisors after apply:

- Security: 0 ERROR, 120 WARN, 96 INFO
- Performance: 0 ERROR, 14 WARN, 280 INFO
- No new WARN or ERROR relative to the accepted X3c staging baseline. The new performance INFO entries are expected unused-index notices immediately after creating the X3d indexes.

## Production untouched

A read-only production transaction returned:

`e10_schema=false | migrations=12 | latest=20260716110000 | items=35 | movements=41 | financial_document_commands=false`

The transaction was rolled back. No production write occurred.

## Boundary

TA-X3d.0 is accepted on staging as a storage and integrity foundation. Public invoice/credit lifecycle writers, allocation/reconciliation writers, and the remaining X3d/X3e/X3f work are not yet complete.
