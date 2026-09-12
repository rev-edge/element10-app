-- Own non-transactional step; drop this named index only if an interrupted build leaves it INVALID.
create index concurrently if not exists e10_supplier_credits_approved_by_idx
  on public.e10_supplier_credits(approved_by);
