# TA-X6e customer merge/split plan

Status: proposed for review. Plan only. No migration or database change is authorized by this file.

## Contract

Customer merge/split is reviewed identity resolution, not source-data mutation. Existing customer rows, identity decisions, activity observations, approval snapshots, posted transactions, lines and commercial events remain byte-for-byte unchanged. A merge changes only the effective customer used by derived reads. A split appends a decision that restores the source customer as its own effective customer. No name, address or price similarity can authorize either operation. Effective merge status is derived from the decision graph rather than written onto `e10_customers`.

## Additive storage

Add `public.e10_customer_resolution_decisions` with:

- `id`, `organization_id`, `source_customer_id`, monotonic `revision`;
- `action` in `merge` or `split`;
- `target_customer_id` required only for `merge` and different from the source;
- `supersedes_decision_id`, reviewed `reason`, bounded object `evidence`;
- `review_basis` in `operator_review` or `channel_identity` and `identity_decision_ids uuid[]` containing any exact current channel-account decisions reviewed by the operator;
- idempotency key, request fingerprint, actor and timestamp;
- same-organization composite foreign keys, one root per source customer, one successor per decision and one revision per source.

The table is append-only, RLS-enabled, and inaccessible directly to `anon` and `authenticated`; `service_role` retains maintenance access. A security-invoker current-decision view remains service-only. A new additive `act.merge_customers` capability gates the decision RPC and receives no default role grant. Ordinary customer lookup and selective activity-attribution correction continue to use `act.manage_customers`.

## Evidence rule

An explicit `operator_review` merge is legal with a bounded nonempty reason and evidence object, including for duplicate walk-in/manual records. `channel_identity` is an optional stronger basis and must cite at least two distinct current `attach` decisions of kind `channel_account`, covering both the source and target effective components. Each cited decision is re-read under the same organization after locking. Alias-only citations are rejected. Neither basis becomes an automatic merge rule. The RPC records the supplied evidence and actor; it does not infer identity from display names, contact details or addresses.

Regardless of the caller-selected basis or citations, the RPC inspects all current verified identities in both effective components. If more than one distinct verified user is present, the merge is rejected. This prevents cherry-picking unverified evidence to combine different verified people. After merge, effective-identity reads map retained source identities to the terminal customer. New identity attachment is allowed only on the active terminal customer and must recheck the entire effective component for verified-user conflicts under the same topology lock.

The old partial unique index on `(organization_id, auth_user_id)` is replaced by a nonunique lookup index. That column is only a cache, and duplicate pre-review customer records may legitimately project the same verified user. The immutable verified identity decisions plus effective-component guards become authority: same-user duplicates may merge, different verified users may not, and a later conflicting verified attachment to the merged component is rejected.

A split must supersede the current merge for that source. It preserves the cited merge evidence and records a new reviewed reason/evidence object. It does not delete or move identity decisions.

## Concurrency and graph rules

`public.e10_org_decide_customer_resolution` takes an organization-scoped advisory lock for customer-resolution topology, then an idempotency lock. The organization lock is intentionally coarse because merges are rare and graph correctness matters more than concurrent merge throughput. It rechecks membership and `act.merge_customers`, locks the source and target customer rows in UUID order, and validates expected source/target customer revisions plus the expected source resolution revision. X6b customer update and identity-decision writers are replaced to acquire this same topology lock before their existing locks, preventing detach, reassignment or archive from racing merge evidence validation.

The active merge graph must be acyclic and readable within a fixed maximum depth of 32. A recursive same-organization traversal rejects self-merges, cycles, missing/archived targets and any merge whose resulting longest upstream chain would exceed the resolver bound. Chains are legal within that bound; the effective customer is the terminal active customer. A split of an intermediate source restores that source and therefore intentionally changes the effective projection for upstream sources that currently resolve through it. Original evidence rows remain unchanged and the decision history explains the change.

The immutable decision chain is resolution authority. Source and target customer revisions are checked but not modified by a merge or split. Generic update/archive acquires the topology lock first and cannot archive any source or target participating in an active merge. Split therefore cannot resurrect an archived customer. A target may later merge, producing a legal bounded chain. Customer lookup hides nonterminal sources through derived resolution rather than mutable status.

## Bounded reads

Add a private helper that resolves one customer to its terminal effective customer with an explicit depth bound and cycle failure. Add `public.e10_org_list_customer_resolution_history(p_org, p_source_customer_id, p_limit, p_before_revision)` with a maximum page size of 100. It returns decision IDs, revisions, source/target IDs, action, basis, reason, evidence, cited identity-decision IDs, actor and timestamp. Evidence is capped at 64 KiB, reason and idempotency text are bounded, and the citation UUID array is capped at 32 entries.

Add a bounded effective-customer projection used in tests to map original customer IDs on activity and posted transaction rows. This projection must not rewrite source rows or add commercial contributions. Full reporting aggregates and their invalidation/version contract remain in the later TA-X6 reporting slice.

## Required proofs

1. Merge two same-organization customers using current channel-account evidence. Existing activity, transaction, line, identity and event rows keep their original customer IDs and hashes.
2. Effective activity and transaction projections resolve both records to one terminal customer without duplicating any source row or monetary contribution.
3. Split the source and prove the effective projection restores the original association while all merge/split history remains.
4. Reject alias-only evidence, stale/detached identity decisions, mismatched verified users, missing or archived customers, self-merge, cross-organization IDs and a graph cycle.
5. Prove exact idempotent replay and mismatched-key rejection.
6. Race two decisions at the same expected revision: one winner, one `40001`, no deadlock. Race a split against a downstream merge and prove a serializable acyclic result. Race verified-identity detach/reassignment against merge and prove evidence is evaluated from one serialized state.
7. Prove an unrelated organization cannot read history or influence resolution, even when it knows all UUIDs.
8. Prove bounded pagination, `NULL`/zero/over-limit rejection, RLS enabled, direct authenticated table read denied, anon RPC execution denied, no unintended PUBLIC-executable definer and zero fixture residue.
9. Run clean local replay, X6b/X6c/X6d regressions, A7 hostile matrix, default-privilege probe, security advisors, exact-head CI and explicitly targeted staging verification. Re-prove production unchanged and read-only.

## Stop boundary

This slice closes reviewed whole-record merge/unmerge and recoverable association history. It does not claim selective splitting of a mistakenly combined subset. Selective correction remains available for activity observations through the immutable X6b attribution-decision stream; selective posted-purchase attribution requires a later additive correction stream and remains required for the X6 end state. This slice does not add contact records, consent, private notes, cross-shop identity pooling, automated matching, reporting aggregates, native slot capture, attendance, payment/accounting recognition or production changes.
