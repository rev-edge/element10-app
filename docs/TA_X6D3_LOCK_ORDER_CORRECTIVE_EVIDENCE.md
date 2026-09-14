# TA-X6d.3 Source-Claim Lock-Order Corrective

## Triggering CI evidence

- Run: `34623220121`
- Head: `fefa9287cddcfd7276547953a432467126ce8dcc`
- Failed step: `TA-X6d.3 reviewed adjustment, unknown-component finalization and source-reconciliation gate`
- Test branch: concurrent reconciliation `link` versus approved-draft `post` for the same imported source component.
- PostgreSQL result: decision failed with SQLSTATE `40P01`; post failed with the expected competing-source SQLSTATE `23505`, so neither operation completed.

The server deadlock detail was:

```text
Process 616 waits for ShareLock on transaction 1749; blocked by process 617.
Process 617 waits for ShareLock on transaction 1750; blocked by process 616.
while inserting index tuple in relation "e10_reporting_dataset_revisions"
```

The decision path had locked its reconciliation/source-claim state before its
reporting-revision trigger. The post path already acquired its idempotency lock
and shared source-identity advisory lock before writes that advance the same
reporting revision. The paths therefore had no common entry lock order.

## Corrective order

The public reconciliation-decision wrapper now uses the existing order:

1. active caller membership and capability validation;
2. `customer-commercial|<idempotency key>` advisory lock;
3. `posted|source|<kind>|<connection>|<component>` advisory lock;
4. the unchanged reviewed reconciliation implementation, whose acquisitions of
   the same idempotency lock are reentrant in the transaction.

Draft posting already uses steps 2 then 3. A same-key link/post race now proves
the shared idempotency lock is first: exactly one operation succeeds and the
other returns `22023 idempotency_key_mismatch`. Existing distinct-key
revoke/post and link/post source races continue to prove source serialization.
