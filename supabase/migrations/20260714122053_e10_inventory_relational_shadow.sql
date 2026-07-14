-- Migration: e10_inventory_relational_shadow  (Chain M — M1: schema + shadow projection)
-- D1 chose (a) migrate inventory to relational rows. This is the SHADOW step: it builds the
-- relational tables and backfills them 1:1 from the blob, but the blob stays authoritative and
-- NOTHING reads these tables yet (client cutover is M3). ADDITIVE ONLY.
--
-- Builds:
--   1. public.e10_inventory_items         — one row per item, PK = the EXISTING text id (never
--      regenerated: 30/35 ids are seed/import strings and the ledger's item_id maps to them 1:1).
--   2. public.e10_inventory_reservations  — one row per reservation, FK -> items (spike §5).
--   3. Member SELECT-only RLS on both. NO client insert/update/delete — mutations happen only inside
--      the M2 SECURITY DEFINER RPCs (which run as owner and bypass RLS).
--   4. Backfill tagged migration_version='chainM_m1', reconciled IN-MIGRATION (raises -> rollback).
--   5. public.e10_inventory_recon         — report-only view: blob vs rows vs ledger, per item.
--
-- The JSONB workspace 'shared' remains the production source of truth through M3.

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Items. PK is the existing JSONB item id (text). All columns nullable; every quantity/cost is
--    numeric (never integer) so fractional qty is never truncated. Column names are snake_case of the
--    JSON keys; card_set maps JSON "set" (reserved word), and the camelCase keys are mapped in backfill.
create table if not exists public.e10_inventory_items (
  id                text primary key,
  name              text,
  cat               text,
  card_set          text,        -- JSON "set"
  set_id            text,        -- JSON "setId"
  cond              text,
  year              text,
  parallel          text,
  card_number       text,        -- JSON "cardNumber"
  rarity            text,
  grade             text,
  grading_company   text,        -- JSON "gradingCompany"
  img               text,
  qty               numeric,
  cost              numeric,
  value             numeric,
  per_box_cost      numeric,     -- JSON "perBoxCost"
  boxes_per_case    numeric,     -- JSON "boxesPerCase"
  sold_qty          numeric,     -- JSON "soldQty"
  sold_proceeds     numeric,     -- JSON "soldProceeds"
  sold_at           numeric,     -- JSON "soldAt" (epoch ms)
  card_id           text,        -- JSON "cardId"
  player_id         text,        -- JSON "playerId"
  owner             text,
  added_at          numeric,     -- JSON "addedAt" (epoch ms)
  seed              boolean,
  migration_version text,
  updated_by        uuid,
  updated_at        timestamptz default now()
);

-- 2. Reservations. The blob reservation object is {qty,showId,showLabel,streamerUid}; it has no id,
--    so we mint one. streamer_uid stays text (blob-origin, loosely typed). available = qty − Σ active.
create table if not exists public.e10_inventory_reservations (
  id                uuid primary key default gen_random_uuid(),
  item_id           text not null references public.e10_inventory_items(id) on delete cascade,
  show_ref          text,        -- JSON "showId"
  show_label        text,        -- JSON "showLabel"
  streamer_uid      text,        -- JSON "streamerUid"
  qty               numeric,
  status            text not null default 'active',   -- 'active' | 'released'
  migration_version text,
  created_at        timestamptz default now(),
  created_by        uuid
);
create index if not exists e10_invres_item_active_idx
  on public.e10_inventory_reservations (item_id) where status = 'active';

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. RLS: member SELECT only, InitPlan-wrapped (mirrors the imov_sel predicate; per-row eval was the
--    root cause of the card-search regression, so wrap it). No INSERT/UPDATE/DELETE policy exists, and
--    the table grants exclude write, so a member cannot mutate either table directly — only the M2 RPCs
--    (SECURITY DEFINER, owner, BYPASSRLS) can. anon gets nothing.
alter table public.e10_inventory_items        enable row level security;
alter table public.e10_inventory_reservations enable row level security;

revoke all on public.e10_inventory_items        from public, anon, authenticated;
revoke all on public.e10_inventory_reservations from public, anon, authenticated;
grant select on public.e10_inventory_items        to authenticated;
grant select on public.e10_inventory_reservations to authenticated;

create policy inv_items_sel on public.e10_inventory_items
  for select to authenticated using ((select public.e10_is_member()));
create policy inv_res_sel on public.e10_inventory_reservations
  for select to authenticated using ((select public.e10_is_member()));

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. Backfill 1:1 from the blob (postgres bypasses RLS in-migration). idempotent via ON CONFLICT.
insert into public.e10_inventory_items (
  id, name, cat, card_set, set_id, cond, year, parallel, card_number, rarity, grade, grading_company,
  img, qty, cost, value, per_box_cost, boxes_per_case, sold_qty, sold_proceeds, sold_at,
  card_id, player_id, owner, added_at, seed, migration_version)
select
  i->>'id', i->>'name', i->>'cat', i->>'set', i->>'setId', i->>'cond', i->>'year', i->>'parallel',
  i->>'cardNumber', i->>'rarity', i->>'grade', i->>'gradingCompany', i->>'img',
  nullif(i->>'qty','')::numeric, nullif(i->>'cost','')::numeric, nullif(i->>'value','')::numeric,
  nullif(i->>'perBoxCost','')::numeric, nullif(i->>'boxesPerCase','')::numeric,
  nullif(i->>'soldQty','')::numeric, nullif(i->>'soldProceeds','')::numeric, nullif(i->>'soldAt','')::numeric,
  i->>'cardId', i->>'playerId', i->>'owner', nullif(i->>'addedAt','')::numeric,
  (i->>'seed')::boolean, 'chainM_m1'
from public.e10_workspace w, jsonb_array_elements(w.data->'inventory') i
where w.id = 'shared'
on conflict (id) do nothing;

insert into public.e10_inventory_reservations (item_id, show_ref, show_label, streamer_uid, qty, status, migration_version)
select i->>'id', r->>'showId', r->>'showLabel', r->>'streamerUid',
       nullif(r->>'qty','')::numeric, 'active', 'chainM_m1'
from public.e10_workspace w, jsonb_array_elements(w.data->'inventory') i,
     jsonb_array_elements(coalesce(i->'reservations','[]'::jsonb)) r
where w.id = 'shared';

-- In-migration reconciliation: any mismatch raises and rolls back the WHOLE migration.
do $$
declare v_items int; v_onhand numeric; v_reserved numeric;
begin
  select count(*), coalesce(sum(qty),0) into v_items, v_onhand
    from public.e10_inventory_items where migration_version = 'chainM_m1';
  select coalesce(sum(qty),0) into v_reserved
    from public.e10_inventory_reservations where status = 'active';
  if v_items <> 35 then raise exception 'M1 backfill: expected 35 items, got %', v_items; end if;
  if v_onhand <> 223 then raise exception 'M1 backfill: expected on-hand 223, got %', v_onhand; end if;
  if v_reserved <> 21 then raise exception 'M1 backfill: expected reserved 21, got %', v_reserved; end if;
end $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. Reconciliation view (report-only; security_invoker => runs under the querying member's RLS,
--    mirroring e10_inventory_reserved_recon). Per item: blob vs relational rows vs ledger-derived
--    on-hand and reserved, with drift signals. Must read zero drift at M1 close and stay zero
--    through M3. It writes/corrects/reconciles nothing.
create or replace view public.e10_inventory_recon with (security_invoker = true) as
  with blob as (
    select i->>'id' as item_id,
           max(i->>'name') as name,
           coalesce(max(nullif(i->>'qty','')::numeric), 0) as blob_onhand,
           coalesce(sum((r->>'qty')::numeric), 0) as blob_reserved
      from public.e10_workspace w,
           jsonb_array_elements(w.data->'inventory') i
      left join lateral jsonb_array_elements(coalesce(i->'reservations','[]'::jsonb)) r on true
     where w.id = 'shared'
     group by i->>'id'
  ),
  rows_ as (
    select it.id as item_id,
           coalesce(it.qty, 0) as row_onhand,
           coalesce((select sum(rr.qty) from public.e10_inventory_reservations rr
                      where rr.item_id = it.id and rr.status = 'active'), 0) as row_reserved
      from public.e10_inventory_items it
  ),
  led as (
    select item_id,
           coalesce(sum(on_hand_delta), 0) as led_onhand,
           coalesce(sum(reserved_delta), 0) as led_reserved
      from public.e10_inventory_movements
     where workspace_id = 'shared'
     group by item_id
  )
  select coalesce(b.item_id, r.item_id, l.item_id) as item_id,
         b.name,
         coalesce(b.blob_onhand, 0)   as blob_onhand,
         coalesce(r.row_onhand, 0)    as row_onhand,
         coalesce(l.led_onhand, 0)    as led_onhand,
         coalesce(b.blob_reserved, 0) as blob_reserved,
         coalesce(r.row_reserved, 0)  as row_reserved,
         coalesce(l.led_reserved, 0)  as led_reserved,
         coalesce(r.row_onhand,0)   - coalesce(b.blob_onhand,0)   as drift_row_blob_onhand,
         coalesce(l.led_onhand,0)   - coalesce(b.blob_onhand,0)   as drift_led_blob_onhand,
         coalesce(r.row_reserved,0) - coalesce(b.blob_reserved,0) as drift_row_blob_reserved,
         coalesce(l.led_reserved,0) - coalesce(b.blob_reserved,0) as drift_led_blob_reserved
    from blob b
    full outer join rows_ r on r.item_id = b.item_id
    full outer join led  l on l.item_id = coalesce(b.item_id, r.item_id);

revoke all on public.e10_inventory_recon from anon;
grant select on public.e10_inventory_recon to authenticated;
