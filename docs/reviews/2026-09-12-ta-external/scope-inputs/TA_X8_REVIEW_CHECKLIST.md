# TA-X8 integration-seam acceptance checklist

Status: review preparation, not implemented or accepted. Scope derives from
`EXPANSION_FRAMEWORK.md` sections 8-9, `EXPANSION_ACCEPTANCE_CASES.md`
(Workspace question, Draft by chat, Scope switch, Multi-membership, AI identity
ambiguity, Customer coverage/privacy), and the TA-X8 row in
`TRACK_A_EXPANSION_PLAN_2026-09-10.md`.

Use `AGENT_EXECUTION_EFFICIENCY.md`: one coherent evidence packet, consolidated
review, and delta-only follow-up. Reuse accepted underlying query and writer
contracts rather than creating a second business-rule engine.

## Read-only query boundary

- Enumerate the supported typed operations and their existing backend targets.
  No arbitrary SQL, table name, function name, or privileged execution escape.
- Prove explicit organization and actor scope for a user with two memberships;
  foreign organization, revoked access and mismatched saved context fail closed.
- Queries return bounded results with stable source references, units, metric
  definitions, freshness/coverage and explicit unknown or ambiguous outcomes.
  A stock or margin question must not write commercial or inventory state.
- Financial/contact permissions apply to returned data, not just presentation.
  Pagination, exports and any cache use the same authorized scope. Test a
  matching record beyond page one and a context reused after an org switch.
- Preserve existing reporting semantics: provisional activity is not posted
  spend; missing cost is not zero; no sales-to-copy join multiplication.

## Reviewable action drafts

- A draft identifies its ordinary command type, organization, target revision,
  typed proposed values, missing information and field provenance. Ambiguous
  product/vendor/quantity remains unresolved rather than becoming an order.
- Preparing or editing a draft does not receive stock, post a transaction,
  create a committed PO, merge identities or dispatch an external action.
- Preview and approval refer to the exact draft revision. Changed payloads or
  target revisions cannot silently reuse earlier approval.
- The eventual execution path calls the ordinary authorized writer and rechecks
  membership, capability, location, entitlement, revision and idempotency.
  Demonstrate rejection after authority changes, including a queued commit
  where applicable to the adopted locking contract.
- Exact retry cannot produce a second business effect. Reusing an idempotency
  key with a different operation or payload fails. Preserve auditable revision
  history and provenance instead of overwriting the approved proposal.
- Imported document text and model suggestions remain untrusted data. A fixture
  containing instructions to change scope or bypass approval must not acquire
  authority. Identity suggestions cannot silently merge canonical subjects.
- Scope switch invalidates use under the new context without deleting the
  original organization's draft. Document access and retention contracts.

## Dormant outbox consumer contract

- Keep external dispatch disabled. Claim/ack tests use isolated local or staging
  fixtures only; no live provider credentials, scheduler, notifications or jobs.
- Document bounded claim selection, ownership and retry/expiry semantics.
  Concurrent consumers cannot both own the same active claim.
- Crash-before-ack and retry preserve the event and avoid a duplicate durable
  acknowledgement. Wrong owner, expired/replaced claim, foreign organization
  and revoked authority follow the explicit contract and cannot acknowledge
  another consumer's work.
- Distinguish database delivery state from any future external exactly-once
  guarantee. Future consumers need replay-safe effect identity; this milestone
  does not prove delivery to a provider.

## Evidence and handoff

Provide exact commit, operation/response contracts, positive and hostile tests,
concurrency proofs where relevant, clean migration replay, exact-head CI and
explicit staging target/results with fixture cleanup and advisor disclosure.
Include representative-volume query evidence before latency claims.

Mark each supported operation versus deliberately unsupported operation.
Dependencies on unfinished X3/X4 writers remain explicit; a generic draft table
alone cannot close the reviewable purchasing action requirement. Track B gets
contracts and fixtures, not a claim that forms or conversation already use them.
Chatbot, live feeds, scheduled trackers, showcase and production remain excluded.
