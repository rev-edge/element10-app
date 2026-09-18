-- Own non-transactional step; drop this named index only if an interrupted build leaves it INVALID.
create index concurrently if not exists e10_financial_allocation_commands_created_by_idx
  on public.e10_financial_allocation_commands(created_by);
