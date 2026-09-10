# TA-X6f selective posted-customer attribution plan

Status: proposed for review. Plan only.

## Contract

A posted customer transaction is immutable commercial evidence. Correcting which customer it belongs to appends a reviewed attribution decision and never updates the transaction header, lines, activity snapshots, commercial event, adjustment, finalization or reconciliation evidence. The result explicitly reports `revenue_changed=false` and `source_rows_rewritten=false`.

Transaction-header grain is deliberate: all lines and every refund, cancellation, correction and component finalization attached to that transaction inherit the same effective customer for customer reporting. Attribution cannot split gross and net effects across different customers.

This stream is distinct from whole-record merge/unmerge. Merge resolves all records through an effective customer; selective attribution correction changes one transaction's effective customer source before that merge resolution is applied. Together they cover the acceptance case where two customer records are merged and one mistakenly associated purchase is later split back out.

## Additive storage and authority

Add immutable `public.e10_customer_transaction_attribution_decisions` keyed by organization and transaction, with monotonic revision, action `attribute` or `unattribute`, optional customer, predecessor decision, bounded reviewed reason/evidence, idempotency key/fingerprint, actor and time. Same-organization composite foreign keys protect the transaction, customer and predecessor. One root and one successor per stream prevent forks.

The relation is RLS-enabled, append-only and client-table-closed. A service-only security-invoker current-decision view supplies the latest decision. Add `act.correct_customer_attribution` with zero default grants. Mutation requires membership plus that capability. Bounded reads may also be used by `act.manage_customers`.

## Effective projection

The effective customer for one posted transaction is:

1. the current attribution decision's customer when its action is `attribute`;
2. `NULL` when its action is `unattribute`;
3. otherwise the immutable transaction header's original customer;
4. finally resolved through `e10.customer_effective_id` when nonnull.

The implementation must preserve the distinction between no attribution decision and an explicit `unattribute`; an explicit `NULL` must never fall back to the original header customer. Resolver output includes original customer, selected attribution action/customer/revision/decision ID, and terminal effective customer.

The correction target must be an active terminal customer at decision time. Attribution to a merged/nonterminal source is rejected; use its terminal customer. Later reviewed merge/split decisions may change the derived terminal mapping without rewriting the attribution decision.

## Concurrency and API

`public.e10_org_decide_customer_transaction_attribution` performs authorization before locks, then acquires the organization customer-topology lock before its transaction-attribution lock. It checks the shared customer mutation receipt namespace immediately after authorization and idempotency locking, before mutable target validation. It then validates an expected attribution revision, locks the transaction, rechecks the new target customer and appends exactly one successor. Exact retries replay even if a former target is later archived; changed or cross-operation reuse of a key fails. Ordinary reattribution to a new active terminal customer remains legal after the earlier target is archived.

Add bounded `public.e10_org_list_customer_transaction_attribution_history` with a maximum page of 100 and a bounded `public.e10_org_resolve_customer_transactions` accepting at most 100 distinct transaction UUIDs. Both are organization-scoped and return only the minimum identity and decision provenance required for customer reconciliation. They do not return line-level financial details.

## Required proofs

1. Two immutable posted transactions begin on customer A. Whole-record merge A to B resolves both to B.
2. Split A, then selectively reattribute one transaction to B. One resolves to A and one to B; each transaction and all lines/events retain their original hashes and the complete contribution cardinality/value set is unchanged.
3. Reassign a transaction with a refund and prove the header, every line, refund/cancellation/correction and finalization resolve to one customer without dividing gross and net effects.
4. `unattribute` yields a deliberate unresolved customer without deleting the transaction; a later reviewed attribute supersedes it.
5. Reject nonterminal, archived, missing and real foreign customers/transactions; reject foreign direct table/history access and missing-cap mutation.
6. Exact retry, cross-operation/idempotency mismatch, stale revision and two-connection same-revision race produce one chain without forks or deadlock.
7. Deterministically overlap target-customer topology change with transaction attribution using the shared lock and prove one serialized effective result.
8. Bound UUID arrays, page sizes, text and evidence; reject `NULL`, duplicates and over-limit requests.
9. Prove zero default capability grants, RLS enabled, direct authenticated table access denied, anon RPC execution denied, default-privilege and advisor gates green, and zero fixture residue.
10. Run clean local replay, X6b through X6e regressions, A7, exact-head CI, explicitly targeted staging verification and production read-only proof.

## Stop boundary

This closes selective customer attribution of posted purchases. It does not alter money, payment, settlement, accounting, contact data, cross-shop pooling or automatic identity matching. Native slot capture, attendance provenance and reporting-level non-duplication remain separate X6 requirements.
