\set ON_ERROR_STOP on

do $$
declare v_definition text;
begin
  select pg_get_indexdef(i.indexrelid) into v_definition
  from pg_index i
  where i.indexrelid = 'public.e10_variant_facet_term_assert_idx'::regclass;

  if v_definition is null
     or v_definition not like '%(facet_key, term_key, variant_id, id)%'
     or v_definition not like '%WHERE (action = ''assert''::text)%' then
    raise exception 'C8 index has unexpected definition: %', v_definition;
  end if;

  if not exists (
    select 1 from pg_index i
    where i.indexrelid = 'public.e10_variant_facet_term_assert_idx'::regclass
      and i.indisvalid and i.indisready and not i.indisunique
  ) then
    raise exception 'C8 term-led index is not ready and valid';
  end if;
end $$;

begin;
set local enable_seqscan = off;
do $$
declare v_plan json;
begin
  execute $query$
    explain (format json)
    select d.variant_id
    from public.e10_catalog_variant_facet_decisions d
    where d.facet_key = 'color_family'
      and d.term_key = '00000000-0000-0000-0000-000000000001'::uuid
      and d.action = 'assert'
  $query$ into v_plan;
  if v_plan::text not like '%e10_variant_facet_term_assert_idx%' then
    raise exception 'C8 predicate cannot use measured index: %', v_plan;
  end if;
end $$;
rollback;

select 'schema_review_c8_catalog_term_index_test: PASS' as result;
