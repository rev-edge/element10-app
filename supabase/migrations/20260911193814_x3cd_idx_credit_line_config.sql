-- Own non-transactional step; drop this named index only if an interrupted build leaves it INVALID.
create index concurrently if not exists e10_supplier_credit_lines_configuration_idx
  on public.e10_supplier_credit_lines(organization_id,configuration_version_id)
  where configuration_version_id is not null;
