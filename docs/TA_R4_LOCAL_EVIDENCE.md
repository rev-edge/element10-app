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

The X2 purchase-destination entry point now explicitly rejects suspended
organizations. X3 financial and comment paths use active-status checks directly
or through the fail-closed capability predicate. Existing X7 public reporting
entry points already carry explicit active-organization checks; their regression
suites remain part of the consolidated gate.

Local proof after clean replay:

```text
TA-R4 visibility/suspension: PASS
TA-X3e authenticated writer/read/projection behavior: PASS
TA-X3e durable lineage, approval preservation and ACL: PASS
TA-X3e concurrent single-successor and post-lock authorization: PASS
TA-X3f supplier workspace PASS
```

No hosted environment or production was contacted.
