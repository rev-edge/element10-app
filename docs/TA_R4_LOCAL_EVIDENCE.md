# TA-R4 local evidence

Status: implemented and locally verified. Hosted staging and exact-head CI are
deferred to the consolidated R8 gate.

Migration `20260912194500_e10_ta_r4_visibility_suspension.sql` makes four
corrections:

- organization capabilities are false while the organization is suspended;
- the shared catalog policies use any active organization membership rather
  than `current_org()` selection;
- commercial comment reads and writes require document-specific authority,
  with invoice and credit history additionally requiring
  `financial.actual_cost.read`; vendor output remains the existing body-only
  projection;
- supplier workspace results omit receipt-line identifiers unless the caller
  has actual-cost authority. Invoice and credit headers remain absent for that
  caller as before.

The stock-receipt comment writer preserves its existing purchasing-prepare
requirement and additionally requires create-receiving. The corrective
`20260912200500_e10_ta_r4_post_lock_authority.sql` rechecks the complete
document-specific authority after the delegated writer returns from all command,
document and supersession locks. A failed final check rolls back the entire
delegate call, including its comment, event, command receipt and replay path.

The X2 purchase-destination entry point now explicitly rejects suspended
organizations. X3 financial and comment paths use active-status checks directly
or through the fail-closed capability predicate. X7 paths must be classified by
their direct status check or their dependency on the amended capability helper;
the exact inventory and direct suspension cases remain required before R4 is
accepted.

Local proof after clean replay:

```text
TA-R4 visibility/suspension: PASS
TA-X3e authenticated writer/read/projection behavior: PASS
TA-X3e durable lineage, approval preservation and ACL: PASS
TA-X3e concurrent single-successor and post-lock authorization: PASS
TA-X3f supplier workspace PASS
```

The catalog regression uses one authenticated user with two simultaneous active
memberships and proves all four shared policies remain readable while
`e10.current_org()` is null. It then suspends the memberships' organizations one
at a time: access remains while either organization is active and disappears
when neither is active. This demonstrates membership eligibility without
selecting or widening into tenant-owned data.

The concurrent comment suite holds the exact purchase-order or financial-
document lock, confirms the writer backend is waiting, revokes the relevant
capability, and then releases the lock. Both purchasing-prepare and
actual-cost-read revocations return SQLSTATE 42501 and leave zero matching
command, comment, or event rows. The existing replay race separately suspends
the organization during the exact command-key wait and proves replay denial
without changing command cardinality.

No hosted environment or production was contacted.
