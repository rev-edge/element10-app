-- Foundation Gate A6b Step 5 (PROMOTE) — STAGING/LOCAL only; production untouched. ADDITIVE + idempotent.
-- Per the 19 retrofit tables (ADR 0005 §12 step 5): CHECK(organization_id IS NOT NULL) NOT VALID -> VALIDATE ->
-- SET NOT NULL (the validated check lets SET NOT NULL skip the full-table scan) -> attach the existing standalone
-- Step-1 unique index `<t>_org_uq` as a named UNIQUE CONSTRAINT via ADD CONSTRAINT ... UNIQUE USING INDEX (converts
-- the index in place; the composite FKs that reference (org,<key>) keep enforcing — proven). Candidate keys are the
-- 16x (org,id), receipts (org,idempotency_key), obs_config (org,key), session_viewers (org,session_id,user_id) —
-- exactly the columns of each `<t>_org_uq` index. NO PK promotion (old id/pk PKs stay until CONTRACT); old single-col
-- FKs, the 16 composite FKs, the global break_sessions UNIQUE(id)/UNIQUE(share_code), and the bridge triggers are all
-- preserved. Idempotent: guards skip already-promoted tables.

do $$ begin
  if not exists (select 1 from pg_constraint where conname='e10_inventory_items_org_notnull' and conrelid='public.e10_inventory_items'::regclass) then
    alter table public.e10_inventory_items add constraint e10_inventory_items_org_notnull check (organization_id is not null) not valid;
    alter table public.e10_inventory_items validate constraint e10_inventory_items_org_notnull;
  end if;
  alter table public.e10_inventory_items alter column organization_id set not null;
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
  if not exists (select 1 from pg_constraint where conname='e10_obs_viewer_snapshots_org_uq' and contype='u' and conrelid='public.e10_obs_viewer_snapshots'::regclass) then
    alter table public.e10_obs_viewer_snapshots add constraint e10_obs_viewer_snapshots_org_uq unique using index e10_obs_viewer_snapshots_org_uq;
  end if;
end $$;

