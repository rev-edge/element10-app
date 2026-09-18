-- Own non-transactional step; drop this named index only if an interrupted build leaves it INVALID.
create index concurrently if not exists e10_credit_invoice_allocation_events_created_by_idx
  on public.e10_credit_invoice_allocation_events(created_by);
