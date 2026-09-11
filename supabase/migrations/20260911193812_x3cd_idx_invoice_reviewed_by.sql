-- Own non-transactional step; drop this named index only if an interrupted build leaves it INVALID.
create index concurrently if not exists e10_supplier_invoices_reviewed_by_idx
  on public.e10_supplier_invoices(reviewed_by);
