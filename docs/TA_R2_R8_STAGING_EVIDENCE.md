# TA R2 through R8 consolidated staging evidence

Date: 2026-09-12

Status: implementation and staging verification complete; exact-head CI and
renewed independent acceptance remain required. This packet does not
self-accept.

## Revision and target

- Branch: `foundation-a6`
- Runtime and focused-test head: `481ea1ab452a1e196d59b19526ea4ecfdc19309f`
- Explicit staging project: `csmbjfmoxkexcyssntbg`
- Remote access method: Supabase project-scoped SQL and migration calls using
  that exact project ID. No bare linked-project command was used.
- Production: no production API, SQL, migration or deployment call was made in
  this corrective run. The standing read-only sentinel remains the last
  production evidence: no `e10` schema, 12 migrations through
  `20260716110000`, and inventory counts 35 items, 41 movements and 9
  reservations. This run does not extend that observation timestamp.

## Ledger and schema parity

- Local repository contains 145 additive `202609*.sql` migrations.
- Independent review queried staging and confirmed all 145 local September
  migration names are present.
- Independent review compared current local and staging schema manifests. They
  match except the same two previously documented comment-only function
  definition differences. There is no runtime schema drift.
- No applied migration was edited during final evidence closure.

## Staging execution

The R2 through R8 focused SQL suites were executed against the explicit staging
project and passed. This includes R5 immutable and tenant/platform writer
proofs; R6 validation, scoped identity and X4 oracle; X3c, X3d.1b, X4d, X5d,
R7, R8, X7e.1, X7e.2, X8b and X8c.

After the final reviewer correction, these complete transactional suites were
rerun against the same staging project and passed:

- `tests/ta_x4d_receipt_posting_test.sql`
- `tests/ta_x4h_noncard_core_test.sql`
- `tests/ta_r6_validation_contract_test.sql`

Those suites explicitly store labeled pre-R6 request fingerprints for receipt,
reservation and commercial-event rows, then replay each through the current
public RPC. Every fixture transaction rolls back.

The two-connection tests pass locally and are registered in exact-head CI. In
particular, `tests/ta_x4e_receipt_locking_concurrent_test.js` now proves each
waiter is blocked by the intended holder through `pg_blocking_pids`, bounds
completion, compares receipts, lines, lots, movements, allocations, commands
and events before and after rejected races, and removes only audit rows scoped
to its request/user fixture.

## Cleanup and security checks

- Final focused staging fixture-user census: `0` for the R2 through R8 and X4e
  test email namespaces.
- Transactional staging SQL tests rolled back all domain fixtures.
- Local two-connection receipt proof ends with zero receipts, commands, items,
  purchase orders, users, audit batches and audit records for its run.
- Supabase security advisors were read after staging verification. Result: zero
  `ERROR` findings. Existing informational RLS-with-no-policy findings describe
  intentionally client-closed tables, and the existing leaked-password
  protection warning is unrelated to this migration/test-only closure.
- Default-privilege and zero-anonymous-executable-function probes remain in the
  registered CI suite.

## R2 through R8 result map

- R2: final-lock authority rereads, native/import reconciliation, release and
  resale semantics, exact replay and no-write rejected races.
- R3: durable source claims, stable cross-batch identity and correction versus
  reimport serialization.
- R4: internal audience visibility, explicit multi-membership scope and
  suspended-organization reader/writer denial.
- R5: immutable configuration/provider mapping histories, supported writers
  and forced CAS races with exactly one current revision.
- R6: bounded validation, tenant-safe response identities, error/replay
  contracts, line-ID response maps and pre-R6 stored-fingerprint compatibility.
- R7: explicit compatibility and legacy-truncate dispositions.
- R8: focused acceptance rows, supported market-intake truth separation,
  unsupported action denial, cross-org draft retention and dormant external
  dispatch proof.

## Remaining gate

Exact-head CI run `34717509375` targets the runtime/test head above. A later
documentation-only commit will require its own exact-head run. Final acceptance
must be recorded by the independent reviewer after the authoritative trace,
status, matrix and this packet are committed. No production action is implied.
