-- Own non-transactional step; drop this named index only if an interrupted build leaves it INVALID.
create index concurrently if not exists e10_purchase_order_commands_org_po_idx
  on public.e10_purchase_order_commands(organization_id,purchase_order_id);
