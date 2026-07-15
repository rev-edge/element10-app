-- M4 REVERT / DOWN-PATH (ship it, tested; run ONLY to roll back M4). This is the emergency exit that makes
-- the one-way door survivable: it re-projects the blob's inventory section from the relational rows (the
-- authoritative state), restores the pre-M4 blob dual-write and blob-inclusive recon views, and undoes the
-- realtime changes — so a `git revert` of the M4 client commit can read inventory from the blob again with
-- ZERO stranded data. Array order is NOT load-bearing (the client reads by id); we project in id order.
--
-- Rehearsed non-destructively before the window closed (into a scratch workspace row), confirming the
-- re-projection reproduces e10_inv_list() exactly (per-item deep-equal after null-normalization).
--
-- Order to roll back M4:  (1) run THIS script  →  (2) git revert the M4 client commit + redeploy.

-- 1. Re-project the blob inventory section from rows (the P2R down-path)
update public.e10_workspace
   set data = jsonb_set(coalesce(data, '{}'::jsonb), '{inventory}',
         (select coalesce(jsonb_agg(public._e10_inv_item_json(it.id) order by it.id), '[]'::jsonb)
            from public.e10_inventory_items it)),
       rev = coalesce(rev, 0) + 1, updated_at = now()
 where id = 'shared';

-- 2. Restore the blob dual-write (verbatim pre-M4 body) so mutations keep the blob in sync again
create or replace function public._e10_inv_blob_write(p_id text, p_remove boolean, p_actor text)
  returns bigint language plpgsql security definer set search_path to 'public' as $function$
declare v_arr jsonb; v_new jsonb; v_rev bigint;
begin
  select coalesce(data->'inventory', '[]'::jsonb) into v_arr
    from public.e10_workspace where id = 'shared' for update;
  select coalesce(jsonb_agg(e), '[]'::jsonb) into v_new
    from jsonb_array_elements(v_arr) e where e->>'id' <> p_id;
  if not p_remove then
    v_new := v_new || jsonb_build_array(public._e10_inv_item_json(p_id));
  end if;
  update public.e10_workspace
     set data = jsonb_set(coalesce(data, '{}'::jsonb), '{inventory}', v_new),
         rev = coalesce(rev, 0) + 1,
         updated_by = coalesce(p_actor, updated_by),
         updated_at = now()
   where id = 'shared'
   returning rev into v_rev;
  return v_rev;
end;
$function$;

-- 3. Restore the blob-inclusive recon views (verbatim pre-M4 definitions)
drop view if exists public.e10_inventory_reserved_recon;
create view public.e10_inventory_reserved_recon as
with jsonb_res as (
  select (i.value ->> 'id') as item_id, max(i.value ->> 'name') as item_name,
    coalesce(sum((r.value ->> 'qty')::numeric), 0::numeric) as reserved_jsonb
  from public.e10_workspace w,
    lateral jsonb_array_elements(w.data -> 'inventory') i(value)
      left join lateral jsonb_array_elements(coalesce(i.value -> 'reservations', '[]'::jsonb)) r(value) on true
  where w.id = 'shared' group by (i.value ->> 'id')
), ledger_res as (
  select item_id, sum(reserved_delta) as reserved_ledger
  from public.e10_inventory_movements where workspace_id = 'shared' group by item_id
)
select coalesce(j.item_id, l.item_id) as item_id, j.item_name,
  coalesce(j.reserved_jsonb, 0::numeric) as reserved_jsonb,
  coalesce(l.reserved_ledger, 0::numeric) as reserved_ledger,
  (coalesce(l.reserved_ledger, 0::numeric) - coalesce(j.reserved_jsonb, 0::numeric)) as drift
from jsonb_res j full join ledger_res l on l.item_id = j.item_id;

drop view if exists public.e10_inventory_recon;
create view public.e10_inventory_recon as
with blob as (
  select (i.value ->> 'id') as item_id, max(i.value ->> 'name') as name,
    coalesce(max(nullif(i.value ->> 'qty', '')::numeric), 0::numeric) as blob_onhand,
    coalesce(sum((r_1.value ->> 'qty')::numeric), 0::numeric) as blob_reserved
  from public.e10_workspace w,
    lateral jsonb_array_elements(w.data -> 'inventory') i(value)
      left join lateral jsonb_array_elements(coalesce(i.value -> 'reservations', '[]'::jsonb)) r_1(value) on true
  where w.id = 'shared' group by (i.value ->> 'id')
), rows_ as (
  select it.id as item_id, coalesce(it.qty, 0::numeric) as row_onhand,
    coalesce((select sum(rr.qty) from public.e10_inventory_reservations rr where rr.item_id = it.id and rr.status = 'active'), 0::numeric) as row_reserved
  from public.e10_inventory_items it
), led as (
  select item_id, coalesce(sum(on_hand_delta), 0::numeric) as led_onhand, coalesce(sum(reserved_delta), 0::numeric) as led_reserved
  from public.e10_inventory_movements where workspace_id = 'shared' group by item_id
)
select coalesce(b.item_id, r.item_id, l.item_id) as item_id, b.name,
  coalesce(b.blob_onhand, 0::numeric) as blob_onhand, coalesce(r.row_onhand, 0::numeric) as row_onhand, coalesce(l.led_onhand, 0::numeric) as led_onhand,
  coalesce(b.blob_reserved, 0::numeric) as blob_reserved, coalesce(r.row_reserved, 0::numeric) as row_reserved, coalesce(l.led_reserved, 0::numeric) as led_reserved,
  (coalesce(r.row_onhand, 0::numeric) - coalesce(b.blob_onhand, 0::numeric)) as drift_row_blob_onhand,
  (coalesce(l.led_onhand, 0::numeric) - coalesce(b.blob_onhand, 0::numeric)) as drift_led_blob_onhand,
  (coalesce(r.row_reserved, 0::numeric) - coalesce(b.blob_reserved, 0::numeric)) as drift_row_blob_reserved,
  (coalesce(l.led_reserved, 0::numeric) - coalesce(b.blob_reserved, 0::numeric)) as drift_led_blob_reserved
from (blob b full join rows_ r on r.item_id = b.item_id) full join led l on l.item_id = coalesce(b.item_id, r.item_id);

-- 4. Undo the realtime changes (M4's read source no longer needed)
alter publication supabase_realtime drop table public.e10_inventory_reservations;
alter publication supabase_realtime drop table public.e10_inventory_items;
alter table public.e10_inventory_reservations replica identity default;
alter table public.e10_inventory_items replica identity default;
