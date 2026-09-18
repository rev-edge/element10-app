# TA-X3d.1b Staging Evidence

Date: 2026-09-11

## Reviewed source

- Branch: `foundation-a6`
- Exact implementation head: `7de1b5ba07ffb86a6622468b4c04375fb3107b89`
- Exact-head CI: run `34645628212`, success
- Independent implementation review: ACCEPTED on the exact head
- Staging: `csmbjfmoxkexcyssntbg` (`element10-staging`)
- Production: `ddhkkumiyidorzmajwde`, read-only and unchanged

## Staging apply

The reviewed migration was applied atomically through the explicit staging
session pooler. A bare linked command was not used. The CLI first refused a
bulk push because staging contains reviewed historical ledger versions not
represented by local filenames; no ledger repair or history rewrite was
performed. The transaction applied the repository migration and its ledger row
together:

`20260911203110 | e10_ta_x3d1b_financial_document_amend`

## Acceptance proofs

- Compatible allocated description, quantity, and amount increases: PASS
- PO, receipt, and credit allocation conservation on amendment: PASS
- Missing and explicit-null required quantities fail closed: PASS
- Allocated configuration, currency, omission, and reduction conflicts: PASS
- Stable line IDs and reserved cancelled line numbers: PASS
- Draft amendment remains draft; reviewed/approved amendment returns to reviewed and clears approval: PASS
- Expected-revision CAS and command-key idempotency: PASS
- Exact replay survives later configuration retirement; a new request does not: PASS
- Immutable create, revision-2, and revision-3 history passes forced deferred validation: PASS
- Malformed document/kind/revision/status/event links fail deferred validation: PASS
- Missing-capability and foreign-organization callers: denied
- Concurrent same-revision amendment: one revision-2 successor, stale peer denied with `40001`
- Post-lock capability revocation: denied with no mutation residue
- No PO, receipt, stock, lot, movement, payment, or accounting side effect
- Fixture residue: zero

The staging concurrency proof observed backend PID `1610730` waiting on the
exact financial-document advisory lock.

## Security and advisors

- Public amendment endpoints: executable by `authenticated` and `service_role`, not `anon` or `PUBLIC`
- Private amendment helper, line validator, and document-lock helper: service-role-only
- New anonymous/PUBLIC-executable functions: zero
- Security advisors: 0 ERROR, 124 WARN, 97 INFO
- Performance advisors: 0 ERROR, 14 WARN, 281 INFO

The two security WARN entries above X3d.1a are the two intentional authenticated
`SECURITY DEFINER` amendment endpoints. No table, index, or foreign key was
introduced by X3d.1b.

## Production untouched

Read-only proof:

`e10_schema=false | migrations=12 | latest=20260716110000 | items=35 | movements=41 | amend_fn=false`

No production write occurred.

## Boundary

TA-X3d.1b supplies amendment only. Review, approve, void, allocation,
release/correction, and reconciliation-decision writers remain unfinished.
Allocation writers must adopt the same document/line/allocation lock protocol
and prove allocation-versus-amendment races before they are exposed.
