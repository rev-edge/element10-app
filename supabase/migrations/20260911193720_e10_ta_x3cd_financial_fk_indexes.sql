-- TA-X3c/X3d covering indexes. This migration must run as its own non-transactional step.
-- If a concurrent build is interrupted, drop only the named INVALID index and rerun this file.

create index concurrently if not exists e10_purchase_order_commands_created_by_idx
  on public.e10_purchase_order_commands(created_by);
