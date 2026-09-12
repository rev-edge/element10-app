-- Own non-transactional step; drop this named index only if an interrupted build leaves it INVALID.
create index concurrently if not exists e10_purchase_orders_closed_by_idx
  on public.e10_purchase_orders(closed_by);
