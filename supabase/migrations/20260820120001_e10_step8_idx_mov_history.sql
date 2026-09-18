-- STEP8 — history keyset index (org-scoped, newest-first). CONCURRENTLY (own file, non-transactional) for zero-downtime.
-- Recovery: a failed CONCURRENTLY leaves an INVALID index -> detect (indisvalid=false), DROP INDEX, re-run this step.
create index concurrently if not exists e10_invmov_org_created_id_idx
  on public.e10_inventory_movements (organization_id, created_at desc, id desc);
