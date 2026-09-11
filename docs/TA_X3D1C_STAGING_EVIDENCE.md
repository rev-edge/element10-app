# TA-X3d.1c Staging Evidence

Date: 2026-09-11

## Reviewed source

- Branch: `foundation-a6`
- Exact implementation head: `ee1849796a8c0c3e11c7845ed74248748e0624fd`
- Exact-head CI: run `34646949404`, success
- Independent implementation review: ACCEPTED on the exact head
- Staging: `csmbjfmoxkexcyssntbg`
- Production: `ddhkkumiyidorzmajwde`, read-only and unchanged

## Staging apply

Migration `20260911205210_e10_ta_x3d1c_financial_document_transitions.sql`
was applied atomically with its ledger row through the explicit staging session
pooler. No bare linked command or migration-history repair was used.

`20260911205210 | e10_ta_x3d1c_financial_document_transitions`

## Acceptance proofs

- Invoice and credit `draft -> reviewed -> approved`: PASS
- Invoice and credit void from draft, reviewed, and approved: PASS
- Draft approval and repeated void: denied
- Prepare, approve, and cancel capabilities remain independent
- Multi-membership explicit-organization operation: PASS
- Suspended, membership-less, missing-capability, and foreign-organization callers: denied
- Expected-revision CAS, changed-key-payload rejection, and historical replay after later state changes: PASS
- PO, receipt, and credit allocation families independently block void
- Approved void clears current approval while retaining the immutable approved revision and snapshot
- Every successful transition appends an immutable revision, command receipt, and lifecycle event
- No PO, receipt, lot, movement, inventory, payment, or accounting side effect
- Concurrent same-revision review creates one successor; stale peer receives `40001`
- Post-lock approval-capability revocation denies the waiter without residue
- Fixture residue: zero across every seeded and mutated relation

The staging concurrency proof observed backend PID `1612157` waiting on the
exact financial-document advisory lock.

## ACL and advisors

- Six public review/approve/void endpoints: `anon=false`, `authenticated=true`, `service_role=true`
- Internal transition helper: `anon=false`, `authenticated=false`, `service_role=true`
- All seven functions are `SECURITY DEFINER` with pinned `search_path=public`
- Security advisors: 0 ERROR, 130 WARN, 97 INFO
- Performance advisors: 0 ERROR, 14 WARN, 281 INFO

The six WARN entries above X3d.1b are the six intentional authenticated
`SECURITY DEFINER` endpoints. X3d.1c adds no tables, indexes, or foreign keys.

## Production untouched

Read-only proof:

`e10_schema=false | migrations=12 | latest=20260716110000 | items=35 | movements=41 | review_fn=false`

No production write occurred.

## Boundary

Allocation/release writers and their allocation-versus-void concurrency proofs
remain required. Reconciliation decisions, comments, and bounded supplier
workspace reads also remain unfinished.
