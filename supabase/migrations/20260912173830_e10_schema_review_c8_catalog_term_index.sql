-- C8: measured term-led lookup support for reportable catalog facets.
-- A 50,000-variant local fixture showed the term predicate scanning all
-- decisions. Keep this generic across governed namespaces and asserted rows.
create index e10_variant_facet_term_assert_idx
  on public.e10_catalog_variant_facet_decisions
    (facet_key, term_key, variant_id, id)
  where action = 'assert';
