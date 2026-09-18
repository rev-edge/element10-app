-- Foundation Gate A6b Step 1 — INVALID concurrent-index recovery (ADR 0005 §12 step 2 recovery rule).
--
-- WHY: the 19 Step-1 index migrations use `CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS`. If a concurrent build
-- fails (uniqueness violation, deadlock, cancel), PostgreSQL leaves behind a NAMED but INVALID index
-- (`pg_index.indisvalid = false`). Re-running the migration would then skip it via `IF NOT EXISTS` and falsely
-- advance history while the index is unusable. This script is the executable recovery the migrations only described.
--
-- WHAT: for the FIXED allowlist of the 19 Step-1 concurrent indexes ONLY, drop any that are `indisvalid = false`
-- using `DROP INDEX CONCURRENTLY`. Indexes NOT in the allowlist are never selected and never dropped (refuses unknown
-- by construction). Valid indexes are left untouched. If nothing is invalid, this is a no-op.
--
-- HOW TO RUN (guarded staging path — the CLI is linked to prod, so NEVER a bare command):
--   psql "postgresql://postgres.csmbjfmoxkexcyssntbg:<SUPABASE_STAGING_DB_PASSWORD>@aws-0-us-east-1.pooler.supabase.com:5432/postgres" \
--        -v ON_ERROR_STOP=1 -f supabase/recovery/a6b_s1_reindex_recovery.sql
-- Run in AUTOCOMMIT — do NOT wrap in a transaction (DROP INDEX CONCURRENTLY forbids it; psql -f is autocommit).
-- THEN re-run the corresponding unapplied migration through `supabase db push --db-url <staging session pooler>`.

\set ON_ERROR_STOP on

-- Emit `DROP INDEX CONCURRENTLY` for exactly the allowlisted indexes that are invalid, then \gexec runs them.
select format('drop index concurrently if exists public.%I;', c.relname) as _cmd
from pg_index i
join pg_class c on c.oid = i.indexrelid
join pg_namespace n on n.oid = c.relnamespace and n.nspname = 'public'
where i.indisvalid = false
  and c.relname = any (array[
    'e10_inventory_items_org_uq','e10_inventory_movements_org_uq','e10_inventory_reservations_org_uq',
    'e10_mutation_receipts_org_uq','e10_workspace_org_uq','e10_break_sessions_org_uq','e10_break_slots_org_uq',
    'e10_break_events_org_uq','e10_session_viewers_org_uq','e10_obs_breaks_org_uq','e10_obs_captures_org_uq',
    'e10_obs_channels_org_uq','e10_obs_config_org_uq','e10_obs_products_org_uq','e10_obs_product_prices_org_uq',
    'e10_obs_slots_org_uq','e10_obs_streams_org_uq','e10_obs_upcoming_shows_org_uq','e10_obs_viewer_snapshots_org_uq'
  ]::text[])
\gexec
