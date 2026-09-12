-- STEP8 — per-item history keyset index (org + item_id, newest-first). CONCURRENTLY.
create index concurrently if not exists e10_invmov_org_item_created_id_idx
  on public.e10_inventory_movements (organization_id, item_id, created_at desc, id desc);
