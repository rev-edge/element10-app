-- Foundation Gate A6b — composite-FK ON DELETE corrective (Step 1 correction). STAGING/LOCAL only; production
-- untouched. ADDITIVE + idempotent. Step 1 created the 16 composite (organization_id,<fk>) FKs with the default
-- NO ACTION, but the parallel legacy single-column FKs use CASCADE / SET NULL. Once the data is org-consistent this
-- makes parent deletes fail (the old FK cascades the child while the composite NO ACTION blocks it) — e.g.
-- e10_inv_delete_item (bare DELETE relying on the reservations CASCADE). This migration:
--   (A) DROPs the two ledger composite FKs movements->items and receipts->items. Ruling (Trent 2026-07-18): the
--       append-only ledger INTENTIONALLY references hard-deleted items (e10_inv_delete_item records a `correction`
--       movement then deletes the item); the legacy schema had no such FKs. Explicit correction to the Step 1 spec.
--   (B) recreates the other 12 composite FKs with ON DELETE matching the legacy FKs: 11 CASCADE + break_events->slots
--       ON DELETE SET NULL (slot_id) (column-specific, PG15+, because plain SET NULL would null the NOT NULL-bound
--       organization_id). obs_breaks->products and break_sessions->live_sessions stay NO ACTION (matches legacy / new).
--   (C) preserves the org/item boundary the dropped FKs used to give WITHOUT blocking deletes: a BEFORE INSERT
--       org-scoped item lookup on movements + receipts rejects any ledger row whose organization_id disagrees with
--       the referenced item's organization_id. This is NOT stamp_org() alone — it is an explicit cross-org check.
-- Does NOT touch the standalone (organization_id,id) unique indexes (Step 5 PROMOTE, deferred, attaches those).

-- (A) drop the two append-only-ledger composite FKs
alter table public.e10_inventory_movements drop constraint if exists e10_inventory_movements_org_item_id_fkey;
alter table public.e10_mutation_receipts   drop constraint if exists e10_mutation_receipts_org_item_id_fkey;

-- (B) recreate the 11 CASCADE composite FKs (drop the NO ACTION one, re-add ON DELETE CASCADE, validate)
alter table public.e10_inventory_reservations drop constraint if exists e10_inventory_reservations_org_item_id_fkey;
alter table public.e10_inventory_reservations add constraint e10_inventory_reservations_org_item_id_fkey foreign key (organization_id, item_id) references public.e10_inventory_items (organization_id, id) on delete cascade not valid;
alter table public.e10_inventory_reservations validate constraint e10_inventory_reservations_org_item_id_fkey;

alter table public.e10_break_slots drop constraint if exists e10_break_slots_org_session_id_fkey;
alter table public.e10_break_slots add constraint e10_break_slots_org_session_id_fkey foreign key (organization_id, session_id) references public.e10_break_sessions (organization_id, id) on delete cascade not valid;
alter table public.e10_break_slots validate constraint e10_break_slots_org_session_id_fkey;

alter table public.e10_break_events drop constraint if exists e10_break_events_org_session_id_fkey;
alter table public.e10_break_events add constraint e10_break_events_org_session_id_fkey foreign key (organization_id, session_id) references public.e10_break_sessions (organization_id, id) on delete cascade not valid;
alter table public.e10_break_events validate constraint e10_break_events_org_session_id_fkey;

alter table public.e10_session_viewers drop constraint if exists e10_session_viewers_org_session_id_fkey;
alter table public.e10_session_viewers add constraint e10_session_viewers_org_session_id_fkey foreign key (organization_id, session_id) references public.e10_break_sessions (organization_id, id) on delete cascade not valid;
alter table public.e10_session_viewers validate constraint e10_session_viewers_org_session_id_fkey;

alter table public.e10_obs_slots drop constraint if exists e10_obs_slots_org_break_id_fkey;
alter table public.e10_obs_slots add constraint e10_obs_slots_org_break_id_fkey foreign key (organization_id, break_id) references public.e10_obs_breaks (organization_id, id) on delete cascade not valid;
alter table public.e10_obs_slots validate constraint e10_obs_slots_org_break_id_fkey;

alter table public.e10_obs_breaks drop constraint if exists e10_obs_breaks_org_stream_id_fkey;
alter table public.e10_obs_breaks add constraint e10_obs_breaks_org_stream_id_fkey foreign key (organization_id, stream_id) references public.e10_obs_streams (organization_id, id) on delete cascade not valid;
alter table public.e10_obs_breaks validate constraint e10_obs_breaks_org_stream_id_fkey;

alter table public.e10_obs_captures drop constraint if exists e10_obs_captures_org_stream_id_fkey;
alter table public.e10_obs_captures add constraint e10_obs_captures_org_stream_id_fkey foreign key (organization_id, stream_id) references public.e10_obs_streams (organization_id, id) on delete cascade not valid;
alter table public.e10_obs_captures validate constraint e10_obs_captures_org_stream_id_fkey;

alter table public.e10_obs_product_prices drop constraint if exists e10_obs_product_prices_org_product_id_fkey;
alter table public.e10_obs_product_prices add constraint e10_obs_product_prices_org_product_id_fkey foreign key (organization_id, product_id) references public.e10_obs_products (organization_id, id) on delete cascade not valid;
alter table public.e10_obs_product_prices validate constraint e10_obs_product_prices_org_product_id_fkey;

alter table public.e10_obs_streams drop constraint if exists e10_obs_streams_org_channel_id_fkey;
alter table public.e10_obs_streams add constraint e10_obs_streams_org_channel_id_fkey foreign key (organization_id, channel_id) references public.e10_obs_channels (organization_id, id) on delete cascade not valid;
alter table public.e10_obs_streams validate constraint e10_obs_streams_org_channel_id_fkey;

alter table public.e10_obs_upcoming_shows drop constraint if exists e10_obs_upcoming_shows_org_channel_id_fkey;
alter table public.e10_obs_upcoming_shows add constraint e10_obs_upcoming_shows_org_channel_id_fkey foreign key (organization_id, channel_id) references public.e10_obs_channels (organization_id, id) on delete cascade not valid;
alter table public.e10_obs_upcoming_shows validate constraint e10_obs_upcoming_shows_org_channel_id_fkey;

alter table public.e10_obs_viewer_snapshots drop constraint if exists e10_obs_viewer_snapshots_org_stream_id_fkey;
alter table public.e10_obs_viewer_snapshots add constraint e10_obs_viewer_snapshots_org_stream_id_fkey foreign key (organization_id, stream_id) references public.e10_obs_streams (organization_id, id) on delete cascade not valid;
alter table public.e10_obs_viewer_snapshots validate constraint e10_obs_viewer_snapshots_org_stream_id_fkey;

-- (B) break_events->slots: legacy ON DELETE SET NULL — column-specific so organization_id (NOT NULL) is untouched
alter table public.e10_break_events drop constraint if exists e10_break_events_org_slot_id_fkey;
alter table public.e10_break_events add constraint e10_break_events_org_slot_id_fkey
  foreign key (organization_id, slot_id) references public.e10_break_slots (organization_id, id) on delete set null (slot_id) not valid;
alter table public.e10_break_events validate constraint e10_break_events_org_slot_id_fkey;

-- (C) org-scoped ledger boundary: reject a movement/receipt whose organization_id disagrees with its item's org.
-- Named e10_zz_* so it fires AFTER e10_stamp_org_trg (BEFORE triggers fire in name order) — the org is stamped first.
create or replace function e10.assert_ledger_item_org() returns trigger language plpgsql
  security definer set search_path to 'public' as $fn$
begin
  if new.item_id is not null and new.organization_id is not null and exists (
    select 1 from public.e10_inventory_items i
    where i.id = new.item_id and i.organization_id <> new.organization_id
  ) then
    raise exception 'e10 cross-org ledger row rejected: item % is not in organization %', new.item_id, new.organization_id
      using errcode = '42501';
  end if;
  return new;
end;
$fn$;

drop trigger if exists e10_zz_assert_ledger_item_org on public.e10_inventory_movements;
create trigger e10_zz_assert_ledger_item_org before insert on public.e10_inventory_movements
  for each row execute function e10.assert_ledger_item_org();
drop trigger if exists e10_zz_assert_ledger_item_org on public.e10_mutation_receipts;
create trigger e10_zz_assert_ledger_item_org before insert on public.e10_mutation_receipts
  for each row execute function e10.assert_ledger_item_org();
