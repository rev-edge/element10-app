-- M4 STEP 1 (ADDITIVE, backward-compatible): the client's inventory READ source becomes relational.
-- Applied BEFORE the M4 client deploys; the old client is unaffected (blob still written + read).
--   * e10_inv_list() / e10_inv_get(text): member-gated read RPCs projecting rows via _e10_inv_item_json
--     (the canonical shape the blob held — proven byte-equivalent in P2R). anon revoked.
--   * e10_inventory_items + e10_inventory_reservations added to supabase_realtime, REPLICA IDENTITY FULL
--     (so DELETE events carry item_id) — the client patches S.inventory per-row.
--   * Recon views redefined rows-vs-ledger (blob CTE dropped) so they survive the blob's removal; the gate
--     reads e10_inventory_reserved_recon.drift, which stays 0 (rows==blob==ledger while the blob still exists).

create or replace function public.e10_inv_list()
  returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
begin
  if not (select public.e10_is_member()) then
    raise exception 'e10_inv_list: caller is not a member' using errcode = '42501';
  end if;
  return (select coalesce(jsonb_agg(public._e10_inv_item_json(it.id) order by it.id), '[]'::jsonb)
            from public.e10_inventory_items it);
end; $$;

create or replace function public.e10_inv_get(p_id text)
  returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
begin
  if not (select public.e10_is_member()) then
    raise exception 'e10_inv_get: caller is not a member' using errcode = '42501';
  end if;
  return public._e10_inv_item_json(p_id);
end; $$;

revoke all on function public.e10_inv_list() from public, anon;
revoke all on function public.e10_inv_get(text) from public, anon;
grant execute on function public.e10_inv_list() to authenticated;
grant execute on function public.e10_inv_get(text) to authenticated;

alter publication supabase_realtime add table public.e10_inventory_items;
alter publication supabase_realtime add table public.e10_inventory_reservations;
alter table public.e10_inventory_items replica identity full;
alter table public.e10_inventory_reservations replica identity full;

drop view if exists public.e10_inventory_reserved_recon;
create view public.e10_inventory_reserved_recon as
with rows_res as (
  select item_id, sum(qty) as reserved_rows
  from public.e10_inventory_reservations where status = 'active' group by item_id
), ledger_res as (
  select item_id, sum(reserved_delta) as reserved_ledger
  from public.e10_inventory_movements where workspace_id = 'shared' group by item_id
)
select coalesce(r.item_id, l.item_id) as item_id,
  (select name from public.e10_inventory_items i where i.id = coalesce(r.item_id, l.item_id)) as item_name,
  coalesce(r.reserved_rows, 0::numeric) as reserved_rows,
  coalesce(l.reserved_ledger, 0::numeric) as reserved_ledger,
  (coalesce(l.reserved_ledger, 0::numeric) - coalesce(r.reserved_rows, 0::numeric)) as drift
from rows_res r full join ledger_res l on l.item_id = r.item_id;

drop view if exists public.e10_inventory_recon;
create view public.e10_inventory_recon as
with rows_ as (
  select it.id as item_id, it.name,
    coalesce(it.qty, 0::numeric) as row_onhand,
    coalesce((select sum(rr.qty) from public.e10_inventory_reservations rr
              where rr.item_id = it.id and rr.status = 'active'), 0::numeric) as row_reserved
  from public.e10_inventory_items it
), led as (
  select item_id,
    coalesce(sum(on_hand_delta), 0::numeric) as led_onhand,
    coalesce(sum(reserved_delta), 0::numeric) as led_reserved
  from public.e10_inventory_movements where workspace_id = 'shared' group by item_id
)
select coalesce(r.item_id, l.item_id) as item_id, r.name,
  coalesce(r.row_onhand, 0::numeric) as row_onhand,
  coalesce(l.led_onhand, 0::numeric) as led_onhand,
  coalesce(r.row_reserved, 0::numeric) as row_reserved,
  coalesce(l.led_reserved, 0::numeric) as led_reserved,
  (coalesce(l.led_onhand, 0::numeric) - coalesce(r.row_onhand, 0::numeric)) as drift_onhand,
  (coalesce(l.led_reserved, 0::numeric) - coalesce(r.row_reserved, 0::numeric)) as drift_reserved
from rows_ r full join led l on l.item_id = r.item_id;
