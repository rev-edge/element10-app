# TA-X3d.1d staging evidence

Date: 2026-09-11

## Exact implementation

- Branch: `foundation-a6`
- Accepted head: `9d10db3af7fe2f66506ae8910021ed7e8228ee11`
- CI: run `34649406876`, success on the exact accepted head
- Independent pre-staging review: accepted exact `9d10db3`
- Staging project: `csmbjfmoxkexcyssntbg`
- Apply path: explicit staging session-pooler URL, never the linked-project default
- Applied migration: `20260911210706_e10_ta_x3d1d_financial_allocations`

## Staging behavior

All accepted gates passed against staging:

- `tests/ta_x3d1d_financial_allocations_test.sql`
  - partial and split invoice-to-PO and credit-to-invoice matching
  - independent source and target conservation
  - allocation and release event history
  - replay-before-CAS and mismatch denial
  - approval invalidation and immutable snapshots containing exact allocation values
  - both-null optional financial configuration accepted; mismatched optional configuration denied
  - inactive supplier, inactive referenced configuration, and denied destination block only new matching
  - historical replay and release survive later loss of mutable eligibility
  - authorized multi-membership positive path and foreign-organization line denial
  - no receipt, lot, inventory movement, payment, or purchase-order fabrication
- `tests/ta_x3d1d_allocation_lifecycle_test.sql`
  - real match, receipt posting, PO close, release against the closed PO, then invoice void
  - receipt, on-hand quantity, and movement history remain intact after release and void
- `tests/ta_x3d1d_financial_allocations_concurrent_test.js`
  - competing source documents serialized on a common PO target; one accepted and one conservation-denied
  - crossed invoice/PO graph completed without deadlock
  - crossed credit/invoice graph completed without deadlock
  - backend PID `1613666` rechecked prepare authority after its exact lock wait and left no residue
  - every relation in the fixture cleanup list plus organization/auth identity was checked before PASS
- `tests/ta_x3d1d_allocation_workflow_races_test.js`
  - backend PID `1613665` waited on a real description amendment; the stale allocation was CAS-denied
  - void-first denied the later match; match-first caused the stale void to be CAS-denied, with the separate functional gate proving the active-allocation void barrier
  - backend PID `1613665` waited on the real receipt writer; receipt and matching both completed with conserved stock and financial state
  - every relation in the fixture cleanup list plus organization/auth identity was checked before PASS

## ACL and helper replacement

The four public wrappers are `SECURITY DEFINER`, pinned to `search_path=public`, executable by `authenticated` and `service_role`, and not executable by `anon`:

- `e10_org_allocate_invoice_to_po`
- `e10_org_release_invoice_from_po`
- `e10_org_allocate_credit_to_invoice`
- `e10_org_release_credit_from_invoice`

The private command engine and the four shared helpers are `SECURITY DEFINER`, pinned to `search_path=public`, executable only by `service_role`, and denied to `anon` and `authenticated`:

- `public._e10_org_financial_allocation_x3d1d`
- `e10.lock_financial_allocation_targets`
- `e10.lock_financial_document`
- `e10.lock_purchase_order`
- `e10.financial_document_snapshot`

The replaced shared lock helpers retain document, line, receipt-allocation, and expected-supply serialization while removing redundant incident invoice/credit allocation-row locks that created crossed-graph deadlock cycles. Allocation writers acquire their endpoint advisory locks in one order before row locks.

## Advisors

- Security: `0 ERROR`, `134 WARN`, `97 INFO`
- Performance: `0 ERROR`, `14 WARN`, `280 INFO`
- Security delta from the prior accepted checkpoint: four expected authenticated `SECURITY DEFINER` warnings, one for each reviewed public endpoint; no new error
- No new table, policy, or index was introduced by this migration
- Advisor reference: <https://supabase.com/docs/guides/database/database-linter>

## Residue and production exclusion

- Staging fixture residue: organization `0`, auth users `0`, allocation commands `0` for both concurrency fixture namespaces
- Production project `ddhkkumiyidorzmajwde` was queried read-only only
- Production proof: `e10_schema=false`, `migrations=12`, `latest=20260716110000`, `items=35`, `movements=41`, `allocation_fn=false`
- No production write occurred

## Remaining scope

This accepts only TA-X3d.1d. Remaining work still includes the rest of X3 reconciliation, comments, and bounded reads; remaining X4 work; X7e; X8; and the broader TA-X1 through TA-X8 completion matrix. No UI or production work is included.
