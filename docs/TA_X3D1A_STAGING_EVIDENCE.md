# TA-X3d.1a Staging Evidence

Date: 2026-09-11

## Reviewed source

- Branch: `foundation-a6`
- Exact implementation head: `e0e0882b5aa8808474d7a3722e19f03b8557fdc1`
- Exact-head CI: run `34643932626`, success
- Independent review: ACCEPT on the exact head
- Staging: `csmbjfmoxkexcyssntbg` (`element10-staging`)
- Production: `ddhkkumiyidorzmajwde`, read-only and unchanged

## Staging apply

The single reviewed migration was applied transactionally through the explicit staging session pooler. No bare linked command was used. Ledger proof:

`20260911200637 | e10_ta_x3d1a_financial_document_create`

## Acceptance proofs

- Authenticated invoice and credit create behavior: PASS
- Durable revisions, events, stable caller line UUIDs, numeric precision, and recoverable reconciliation snapshots: PASS
- Identical command-key replay and normalized manual-identity convergence: PASS
- Changed manual and connected payloads converge on immutable reconciliation cases without overwriting originals: PASS
- Organization suspension and capability revocation are reread after exact command-lock waits: PASS
- Concurrent connected conflicts converge on one reconciliation case: PASS
- Legacy ambiguous normalized identities are denied deterministically: PASS
- No fabricated PO, receipt, stock, lot, movement, payment, or accounting side effect: PASS
- Fixture residue: zero across the scoped organization, identity, document, command, revision, event, reconciliation, role, membership, and auth rows

The staging concurrency proof observed backend PID `1609186` waiting on each exact advisory-lock boundary.

## Security and schema

- `e10_financial_document_events`: RLS enabled; no `anon` or `authenticated` table privileges
- Public endpoints: invoice create and credit create executable by `authenticated`, not `anon`
- Private helpers: 3; client/PUBLIC executable: 0
- New indexes: 2; valid and ready: 2
- Security advisors: 0 ERROR, 122 WARN, 97 INFO
- Performance advisors: 0 ERROR, 14 WARN, 281 INFO

The two WARN entries above the X3d.0 baseline are the two intentional authenticated SECURITY DEFINER endpoints. The INFO increase reflects the newly client-closed RLS table and fresh index state.

## Production untouched

Read-only proof:

`e10_schema=false | migrations=12 | latest=20260716110000 | items=35 | movements=41 | financial_document_events=false`

No production write occurred.

## Boundary

TA-X3d.1a creates governed invoice and credit drafts only. Amend, review, approve, void, allocation, release, and reconciliation-decision writers remain unfinished.
