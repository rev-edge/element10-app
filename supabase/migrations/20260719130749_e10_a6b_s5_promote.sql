-- Foundation Gate A6b Step 5 (PROMOTE) — STAGING/LOCAL only; production untouched. ADDITIVE + idempotent.
-- For each of the 19 retrofit tables (ADR 0005 §12 step 5): add CHECK(organization_id IS NOT NULL) NOT VALID ->
-- VALIDATE (the validated check lets SET NOT NULL skip the full-table scan) -> SET NOT NULL -> DROP the now-redundant
-- temporary check -> attach the existing valid standalone Step-1 unique index `<t>_org_uq` as the named candidate
-- UNIQUE constraint via ALTER TABLE ... ADD CONSTRAINT <t>_org_uq UNIQUE USING INDEX <t>_org_uq (converts the index
-- in place, same name; the composite FKs that reference (org,<key>) keep enforcing). Candidate keys are exactly the
-- columns of each `<t>_org_uq` index: 16x (org,id), receipts (org,idempotency_key), obs_config (org,key),
-- session_viewers (org,session_id,user_id).
-- Preserves: every existing PK (NO PK promotion); all legacy single-col FKs; the 14 corrected composite FKs + their
-- ON DELETE actions; both e10.assert_ledger_item_org ledger triggers; all 19 e10.stamp_org bridge triggers; the
-- global break_sessions PK/UNIQUE(id)+UNIQUE(share_code) and live_sessions UNIQUE(id)+UNIQUE(share_code). No policy,
-- predicate, RPC-wrapper, realtime, or CONTRACT change.

do $$ begin
  if not exists (select 1 from pg_constraint where conname='e10_inventory_items_org_notnull' and conrelid='public.e10_inventory_items'::regclass) then
    alter table public.e10_inventory_items add constraint e10_inventory_items_org_notnull check (organization_id is not null) not valid;
    alter table public.e10_inventory_items validate constraint e10_inventory_items_org_notnull;
  end if;
  alter table public.e10_inventory_items alter column organization_id set not null;
  alter table public.e10_inventory_items drop constraint if exists e10_inventory_items_org_notnull;
  if not exists (select 1 from pg_constraint where conname='e10_inventory_items_org_uq' and contype='u' and conrelid='public.e10_inventory_items'::regclass) then
    alter table public.e10_inventory_items add constraint e10_inventory_items_org_uq unique using index e10_inventory_items_org_uq;
  end if;
end $$;

do $$ begin
  if not exists (select 1 from pg_constraint where conname='e10_inventory_movements_org_notnull' and conrelid='public.e10_inventory_movements'::regclass) then
    alter table public.e10_inventory_movements add constraint e10_inventory_movements_org_notnull check (organization_id is not null) not valid;
    alter table public.e10_inventory_movements validate constraint e10_inventory_movements_org_notnull;
  end if;
  alter table public.e10_inventory_movements alter column organization_id set not null;
  alter table public.e10_inventory_movements drop constraint if exists e10_inventory_movements_org_notnull;
  if not exists (select 1 from pg_constraint where conname='e10_inventory_movements_org_uq' and contype='u' and conrelid='public.e10_inventory_movements'::regclass) then
    alter table public.e10_inventory_movements add constraint e10_inventory_movements_org_uq unique using index e10_inventory_movements_org_uq;
  end if;
end $$;

do $$ begin
  if not exists (select 1 from pg_constraint where conname='e10_inventory_reservations_org_notnull' and conrelid='public.e10_inventory_reservations'::regclass) then
    alter table public.e10_inventory_reservations add constraint e10_inventory_reservations_org_notnull check (organization_id is not null) not valid;
    alter table public.e10_inventory_reservations validate constraint e10_inventory_reservations_org_notnull;
  end if;
  alter table public.e10_inventory_reservations alter column organization_id set not null;
  alter table public.e10_inventory_reservations drop constraint if exists e10_inventory_reservations_org_notnull;
  if not exists (select 1 from pg_constraint where conname='e10_inventory_reservations_org_uq' and contype='u' and conrelid='public.e10_inventory_reservations'::regclass) then
    alter table public.e10_inventory_reservations add constraint e10_inventory_reservations_org_uq unique using index e10_inventory_reservations_org_uq;
  end if;
end $$;

do $$ begin
  if not exists (select 1 from pg_constraint where conname='e10_mutation_receipts_org_notnull' and conrelid='public.e10_mutation_receipts'::regclass) then
    alter table public.e10_mutation_receipts add constraint e10_mutation_receipts_org_notnull check (organization_id is not null) not valid;
    alter table public.e10_mutation_receipts validate constraint e10_mutation_receipts_org_notnull;
  end if;
  alter table public.e10_mutation_receipts alter column organization_id set not null;
  alter table public.e10_mutation_receipts drop constraint if exists e10_mutation_receipts_org_notnull;
  if not exists (select 1 from pg_constraint where conname='e10_mutation_receipts_org_uq' and contype='u' and conrelid='public.e10_mutation_receipts'::regclass) then
    alter table public.e10_mutation_receipts add constraint e10_mutation_receipts_org_uq unique using index e10_mutation_receipts_org_uq;
  end if;
end $$;

do $$ begin
  if not exists (select 1 from pg_constraint where conname='e10_workspace_org_notnull' and conrelid='public.e10_workspace'::regclass) then
    alter table public.e10_workspace add constraint e10_workspace_org_notnull check (organization_id is not null) not valid;
    alter table public.e10_workspace validate constraint e10_workspace_org_notnull;
  end if;
  alter table public.e10_workspace alter column organization_id set not null;
  alter table public.e10_workspace drop constraint if exists e10_workspace_org_notnull;
  if not exists (select 1 from pg_constraint where conname='e10_workspace_org_uq' and contype='u' and conrelid='public.e10_workspace'::regclass) then
    alter table public.e10_workspace add constraint e10_workspace_org_uq unique using index e10_workspace_org_uq;
  end if;
end $$;

do $$ begin
  if not exists (select 1 from pg_constraint where conname='e10_break_sessions_org_notnull' and conrelid='public.e10_break_sessions'::regclass) then
    alter table public.e10_break_sessions add constraint e10_break_sessions_org_notnull check (organization_id is not null) not valid;
    alter table public.e10_break_sessions validate constraint e10_break_sessions_org_notnull;
  end if;
  alter table public.e10_break_sessions alter column organization_id set not null;
  alter table public.e10_break_sessions drop constraint if exists e10_break_sessions_org_notnull;
  if not exists (select 1 from pg_constraint where conname='e10_break_sessions_org_uq' and contype='u' and conrelid='public.e10_break_sessions'::regclass) then
    alter table public.e10_break_sessions add constraint e10_break_sessions_org_uq unique using index e10_break_sessions_org_uq;
  end if;
end $$;

do $$ begin
  if not exists (select 1 from pg_constraint where conname='e10_break_slots_org_notnull' and conrelid='public.e10_break_slots'::regclass) then
    alter table public.e10_break_slots add constraint e10_break_slots_org_notnull check (organization_id is not null) not valid;
    alter table public.e10_break_slots validate constraint e10_break_slots_org_notnull;
  end if;
  alter table public.e10_break_slots alter column organization_id set not null;
  alter table public.e10_break_slots drop constraint if exists e10_break_slots_org_notnull;
  if not exists (select 1 from pg_constraint where conname='e10_break_slots_org_uq' and contype='u' and conrelid='public.e10_break_slots'::regclass) then
    alter table public.e10_break_slots add constraint e10_break_slots_org_uq unique using index e10_break_slots_org_uq;
  end if;
end $$;

do $$ begin
  if not exists (select 1 from pg_constraint where conname='e10_break_events_org_notnull' and conrelid='public.e10_break_events'::regclass) then
    alter table public.e10_break_events add constraint e10_break_events_org_notnull check (organization_id is not null) not valid;
    alter table public.e10_break_events validate constraint e10_break_events_org_notnull;
  end if;
  alter table public.e10_break_events alter column organization_id set not null;
  alter table public.e10_break_events drop constraint if exists e10_break_events_org_notnull;
  if not exists (select 1 from pg_constraint where conname='e10_break_events_org_uq' and contype='u' and conrelid='public.e10_break_events'::regclass) then
    alter table public.e10_break_events add constraint e10_break_events_org_uq unique using index e10_break_events_org_uq;
  end if;
end $$;

do $$ begin
  if not exists (select 1 from pg_constraint where conname='e10_session_viewers_org_notnull' and conrelid='public.e10_session_viewers'::regclass) then
    alter table public.e10_session_viewers add constraint e10_session_viewers_org_notnull check (organization_id is not null) not valid;
    alter table public.e10_session_viewers validate constraint e10_session_viewers_org_notnull;
  end if;
  alter table public.e10_session_viewers alter column organization_id set not null;
  alter table public.e10_session_viewers drop constraint if exists e10_session_viewers_org_notnull;
  if not exists (select 1 from pg_constraint where conname='e10_session_viewers_org_uq' and contype='u' and conrelid='public.e10_session_viewers'::regclass) then
    alter table public.e10_session_viewers add constraint e10_session_viewers_org_uq unique using index e10_session_viewers_org_uq;
  end if;
end $$;

do $$ begin
  if not exists (select 1 from pg_constraint where conname='e10_obs_breaks_org_notnull' and conrelid='public.e10_obs_breaks'::regclass) then
    alter table public.e10_obs_breaks add constraint e10_obs_breaks_org_notnull check (organization_id is not null) not valid;
    alter table public.e10_obs_breaks validate constraint e10_obs_breaks_org_notnull;
  end if;
  alter table public.e10_obs_breaks alter column organization_id set not null;
  alter table public.e10_obs_breaks drop constraint if exists e10_obs_breaks_org_notnull;
  if not exists (select 1 from pg_constraint where conname='e10_obs_breaks_org_uq' and contype='u' and conrelid='public.e10_obs_breaks'::regclass) then
    alter table public.e10_obs_breaks add constraint e10_obs_breaks_org_uq unique using index e10_obs_breaks_org_uq;
  end if;
end $$;

do $$ begin
  if not exists (select 1 from pg_constraint where conname='e10_obs_captures_org_notnull' and conrelid='public.e10_obs_captures'::regclass) then
    alter table public.e10_obs_captures add constraint e10_obs_captures_org_notnull check (organization_id is not null) not valid;
    alter table public.e10_obs_captures validate constraint e10_obs_captures_org_notnull;
  end if;
  alter table public.e10_obs_captures alter column organization_id set not null;
  alter table public.e10_obs_captures drop constraint if exists e10_obs_captures_org_notnull;
  if not exists (select 1 from pg_constraint where conname='e10_obs_captures_org_uq' and contype='u' and conrelid='public.e10_obs_captures'::regclass) then
    alter table public.e10_obs_captures add constraint e10_obs_captures_org_uq unique using index e10_obs_captures_org_uq;
  end if;
end $$;

do $$ begin
  if not exists (select 1 from pg_constraint where conname='e10_obs_channels_org_notnull' and conrelid='public.e10_obs_channels'::regclass) then
    alter table public.e10_obs_channels add constraint e10_obs_channels_org_notnull check (organization_id is not null) not valid;
    alter table public.e10_obs_channels validate constraint e10_obs_channels_org_notnull;
  end if;
  alter table public.e10_obs_channels alter column organization_id set not null;
  alter table public.e10_obs_channels drop constraint if exists e10_obs_channels_org_notnull;
  if not exists (select 1 from pg_constraint where conname='e10_obs_channels_org_uq' and contype='u' and conrelid='public.e10_obs_channels'::regclass) then
    alter table public.e10_obs_channels add constraint e10_obs_channels_org_uq unique using index e10_obs_channels_org_uq;
  end if;
end $$;

do $$ begin
  if not exists (select 1 from pg_constraint where conname='e10_obs_config_org_notnull' and conrelid='public.e10_obs_config'::regclass) then
    alter table public.e10_obs_config add constraint e10_obs_config_org_notnull check (organization_id is not null) not valid;
    alter table public.e10_obs_config validate constraint e10_obs_config_org_notnull;
  end if;
  alter table public.e10_obs_config alter column organization_id set not null;
  alter table public.e10_obs_config drop constraint if exists e10_obs_config_org_notnull;
  if not exists (select 1 from pg_constraint where conname='e10_obs_config_org_uq' and contype='u' and conrelid='public.e10_obs_config'::regclass) then
    alter table public.e10_obs_config add constraint e10_obs_config_org_uq unique using index e10_obs_config_org_uq;
  end if;
end $$;

do $$ begin
  if not exists (select 1 from pg_constraint where conname='e10_obs_products_org_notnull' and conrelid='public.e10_obs_products'::regclass) then
    alter table public.e10_obs_products add constraint e10_obs_products_org_notnull check (organization_id is not null) not valid;
    alter table public.e10_obs_products validate constraint e10_obs_products_org_notnull;
  end if;
  alter table public.e10_obs_products alter column organization_id set not null;
  alter table public.e10_obs_products drop constraint if exists e10_obs_products_org_notnull;
  if not exists (select 1 from pg_constraint where conname='e10_obs_products_org_uq' and contype='u' and conrelid='public.e10_obs_products'::regclass) then
    alter table public.e10_obs_products add constraint e10_obs_products_org_uq unique using index e10_obs_products_org_uq;
  end if;
end $$;

do $$ begin
  if not exists (select 1 from pg_constraint where conname='e10_obs_product_prices_org_notnull' and conrelid='public.e10_obs_product_prices'::regclass) then
    alter table public.e10_obs_product_prices add constraint e10_obs_product_prices_org_notnull check (organization_id is not null) not valid;
    alter table public.e10_obs_product_prices validate constraint e10_obs_product_prices_org_notnull;
  end if;
  alter table public.e10_obs_product_prices alter column organization_id set not null;
  alter table public.e10_obs_product_prices drop constraint if exists e10_obs_product_prices_org_notnull;
  if not exists (select 1 from pg_constraint where conname='e10_obs_product_prices_org_uq' and contype='u' and conrelid='public.e10_obs_product_prices'::regclass) then
    alter table public.e10_obs_product_prices add constraint e10_obs_product_prices_org_uq unique using index e10_obs_product_prices_org_uq;
  end if;
end $$;

do $$ begin
  if not exists (select 1 from pg_constraint where conname='e10_obs_slots_org_notnull' and conrelid='public.e10_obs_slots'::regclass) then
    alter table public.e10_obs_slots add constraint e10_obs_slots_org_notnull check (organization_id is not null) not valid;
    alter table public.e10_obs_slots validate constraint e10_obs_slots_org_notnull;
  end if;
  alter table public.e10_obs_slots alter column organization_id set not null;
  alter table public.e10_obs_slots drop constraint if exists e10_obs_slots_org_notnull;
  if not exists (select 1 from pg_constraint where conname='e10_obs_slots_org_uq' and contype='u' and conrelid='public.e10_obs_slots'::regclass) then
    alter table public.e10_obs_slots add constraint e10_obs_slots_org_uq unique using index e10_obs_slots_org_uq;
  end if;
end $$;

do $$ begin
  if not exists (select 1 from pg_constraint where conname='e10_obs_streams_org_notnull' and conrelid='public.e10_obs_streams'::regclass) then
    alter table public.e10_obs_streams add constraint e10_obs_streams_org_notnull check (organization_id is not null) not valid;
    alter table public.e10_obs_streams validate constraint e10_obs_streams_org_notnull;
  end if;
  alter table public.e10_obs_streams alter column organization_id set not null;
  alter table public.e10_obs_streams drop constraint if exists e10_obs_streams_org_notnull;
  if not exists (select 1 from pg_constraint where conname='e10_obs_streams_org_uq' and contype='u' and conrelid='public.e10_obs_streams'::regclass) then
    alter table public.e10_obs_streams add constraint e10_obs_streams_org_uq unique using index e10_obs_streams_org_uq;
  end if;
end $$;

do $$ begin
  if not exists (select 1 from pg_constraint where conname='e10_obs_upcoming_shows_org_notnull' and conrelid='public.e10_obs_upcoming_shows'::regclass) then
    alter table public.e10_obs_upcoming_shows add constraint e10_obs_upcoming_shows_org_notnull check (organization_id is not null) not valid;
    alter table public.e10_obs_upcoming_shows validate constraint e10_obs_upcoming_shows_org_notnull;
  end if;
  alter table public.e10_obs_upcoming_shows alter column organization_id set not null;
  alter table public.e10_obs_upcoming_shows drop constraint if exists e10_obs_upcoming_shows_org_notnull;
  if not exists (select 1 from pg_constraint where conname='e10_obs_upcoming_shows_org_uq' and contype='u' and conrelid='public.e10_obs_upcoming_shows'::regclass) then
    alter table public.e10_obs_upcoming_shows add constraint e10_obs_upcoming_shows_org_uq unique using index e10_obs_upcoming_shows_org_uq;
  end if;
end $$;

do $$ begin
  if not exists (select 1 from pg_constraint where conname='e10_obs_viewer_snapshots_org_notnull' and conrelid='public.e10_obs_viewer_snapshots'::regclass) then
    alter table public.e10_obs_viewer_snapshots add constraint e10_obs_viewer_snapshots_org_notnull check (organization_id is not null) not valid;
    alter table public.e10_obs_viewer_snapshots validate constraint e10_obs_viewer_snapshots_org_notnull;
  end if;
  alter table public.e10_obs_viewer_snapshots alter column organization_id set not null;
  alter table public.e10_obs_viewer_snapshots drop constraint if exists e10_obs_viewer_snapshots_org_notnull;
  if not exists (select 1 from pg_constraint where conname='e10_obs_viewer_snapshots_org_uq' and contype='u' and conrelid='public.e10_obs_viewer_snapshots'::regclass) then
    alter table public.e10_obs_viewer_snapshots add constraint e10_obs_viewer_snapshots_org_uq unique using index e10_obs_viewer_snapshots_org_uq;
  end if;
end $$;

