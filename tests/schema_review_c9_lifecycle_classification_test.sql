\set ON_ERROR_STOP on

create temporary table e10_c9_lifecycle_classification as
select
  t.tablename as table_name,
  case
    when t.tablename in ('e10_bigimport_backup', 'e10_seed_backup')
      then 'snapshot'
    when t.tablename ~ '(_events?|_decisions?|_revisions?|_transitions?|_observations?|_evidence|_history|_assertions|_snapshots|_receipts|_commands|_replays|_commits|_adjustments|_finalizations|_supersessions|_assessments|_acknowledgements|_promotion_rows)$'
      then 'append_only'
    when t.tablename ~ '(_allocations|_memberships|_permissions|_subjects|_viewers|_links|_components|_lines|_mappings|_claims)$'
      then 'relationship'
    when t.tablename in (
      'e10_obs_config',
      'e10_inventory_cursor_secrets',
      'e10_market_catalog_revision',
      'e10_market_org_revisions',
      'e10_platform_admins',
      'e10_role_permissions'
    ) then 'singleton_or_compatibility'
    else 'mutable_current_state'
  end as lifecycle
from pg_tables t
where t.schemaname = 'public'
  and t.tablename like 'e10_%';

do $$
declare
  v_public_tables integer;
  v_classified integer;
begin
  select count(*) into v_public_tables
  from pg_tables
  where schemaname = 'public' and tablename like 'e10_%';

  select count(*) into v_classified
  from e10_c9_lifecycle_classification
  where lifecycle is not null;

  if v_public_tables <> v_classified then
    raise exception 'C9 lifecycle coverage mismatch: tables %, classified %',
      v_public_tables, v_classified;
  end if;

  if (select lifecycle from e10_c9_lifecycle_classification
      where table_name = 'e10_break_events') <> 'append_only'
     or (select lifecycle from e10_c9_lifecycle_classification
         where table_name = 'e10_organization_memberships') <> 'relationship'
     or (select lifecycle from e10_c9_lifecycle_classification
         where table_name = 'e10_organizations') <> 'mutable_current_state'
     or (select lifecycle from e10_c9_lifecycle_classification
         where table_name = 'e10_obs_config') <> 'singleton_or_compatibility' then
    raise exception 'C9 semantic anchor classification failed';
  end if;
end $$;

select lifecycle, count(*) as table_count
from e10_c9_lifecycle_classification
group by lifecycle
order by lifecycle;

select 'schema_review_c9_lifecycle_classification_test: PASS' as result;
