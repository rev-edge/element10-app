-- A6b Step 1 EXPAND — standalone UNIQUE INDEX CONCURRENTLY on (organization_id, idempotency_key). Own non-transactional step (ADR §12 s2).
-- Recovery: a failed CONCURRENTLY leaves an INVALID index; detect (indisvalid=false), DROP INDEX, re-run this step.
create unique index concurrently if not exists e10_mutation_receipts_org_uq on public.e10_mutation_receipts (organization_id, idempotency_key);
