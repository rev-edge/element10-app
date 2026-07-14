-- Migration: e10_m31_mutation_hardening  (M3.1a — pre-M4 blocker closure)
-- Closes the seven pre-M4 blockers in the inventory mutation layer. ADDITIVE + REPLACE only.
-- Inserts ZERO ledger rows. The JSONB workspace 'shared' stays the operational source of truth;
-- these RPCs record + drive the relational rows/reservations/ledger in ONE transaction each.
--
-- ═══════════════════════════════════════════════════════════════════════════════
-- RECONCILIATION FIRST — a stopped earlier M3.1 run left partial artifacts on the live DB
-- (verified 2026-07-14): an old e10_mutation_receipts (response/no fingerprint, 0 rows), overloaded
-- e10_inv_consume / e10_inv_reverse_consumption signatures, a per-item e10_inv_set_reservation, and an
-- unwhitelisted p_remove_keys on e10_inv_edit_item. Everything below is rebuilt from the M3 baseline
-- (migrations ..124500/..130000/..131500), trusting nothing the stopped run wrote.
-- ═══════════════════════════════════════════════════════════════════════════════

-- Drop the stopped run's overloaded / superseded signatures so no ambiguous name survives.
drop function if exists public.e10_inv_consume(text, text, numeric, numeric, text);              -- stopped-run overload (p_reserved_qty)
drop function if exists public.e10_inv_consume(text, text, numeric, text);                        -- M3 baseline (single show ref)
drop function if exists public.e10_inv_reverse_consumption(text, text, numeric, numeric, uuid, text); -- stopped-run overload (p_reserved_qty)
drop function if exists public.e10_inv_reverse_consumption(text, text, numeric, uuid, text);      -- M3 baseline
drop function if exists public.e10_inv_set_reservation(text, text, text, numeric, text);          -- per-item, superseded by the batch RPC
-- Drop the 3-arg baseline edit_item so a 3-arg client call cannot resolve to the UNHARDENED body
-- instead of the 4-arg (p_remove_keys default null) hardened version below.
drop function if exists public.e10_inv_edit_item(text, jsonb, text);

-- Drop the old receipts table (old schema: has `response`, lacks movement_id/input_fingerprint; 0 rows).
drop table if exists public.e10_mutation_receipts;

-- ─────────────────────────────────────────────────────────────────────────────
-- Blocker 3: mutation-level idempotency RECEIPTS. One receipt per successfully committed mutation,
-- written in the SAME transaction. Validation/authorization failures write NOTHING. Members never
-- touch this table directly (no grants, RLS on, no policies) — only the SECURITY DEFINER RPCs.
create table public.e10_mutation_receipts (
  idempotency_key   text primary key,
  rpc               text not null,
  item_id           text,
  actor_uid         uuid,
  movement_id       uuid,           -- null for no-movement mutations (name edit, add qty 0, delete 0/0) and batch ops
  input_fingerprint text not null,  -- md5 of the normalized request payload; a key reused with altered args is rejected
  created_at        timestamptz not null default now()
);
alter table public.e10_mutation_receipts enable row level security;
revoke all on public.e10_mutation_receipts from public, anon, authenticated;
-- (no policies, no client grants: locked down; definer RPCs owned by postgres bypass RLS)

-- ─────────────────────────────────────────────────────────────────────────────
-- Shared hardening helpers (all SECURITY DEFINER, private).

-- Numeric guard: returns the first key in p_keys whose value in p_obj is present, non-empty, and NOT a
-- valid number (blocker 6 — garbage numeric strings are rejected cleanly, never cast-crash to 500).
create or replace function public._e10_inv_bad_num(p_obj jsonb, p_keys text[])
  returns text language sql immutable set search_path to 'public' as $$
  select k from unnest(p_keys) k
   where p_obj ? k and btrim(coalesce(p_obj->>k,'')) <> ''
     and btrim(p_obj->>k) !~ '^-?\d+(\.\d+)?$'
   limit 1;
$$;
revoke all on function public._e10_inv_bad_num(jsonb, text[]) from public, anon, authenticated;

-- Receipt check: takes the per-key advisory xact lock (blocker 3 — concurrent same-key calls serialize),
-- then looks up the receipt. Returns null (new → proceed), {'_mismatch':true} (key reused for a different
-- rpc/item/actor/args → reject), or {'replay':true, movement_id, idempotency_key}.
create or replace function public._e10_inv_receipt_check(p_key text, p_rpc text, p_item_id text, p_fp text)
  returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v public.e10_mutation_receipts;
begin
  perform pg_advisory_xact_lock(hashtext(p_key));
  select * into v from public.e10_mutation_receipts where idempotency_key = p_key;
  if not found then return null; end if;
  if v.rpc is distinct from p_rpc
     or v.item_id is distinct from p_item_id
     or v.actor_uid is distinct from auth.uid()
     or v.input_fingerprint is distinct from p_fp then
    return jsonb_build_object('_mismatch', true);
  end if;
  return jsonb_build_object('replay', true, 'movement_id', v.movement_id, 'idempotency_key', v.idempotency_key);
end;
$$;
revoke all on function public._e10_inv_receipt_check(text, text, text, text) from public, anon, authenticated;

-- Receipt write: committed-mutations only, same transaction as the mutation + movement.
create or replace function public._e10_inv_receipt_write(p_key text, p_rpc text, p_item_id text, p_fp text, p_mid uuid)
  returns void language sql security definer set search_path to 'public' as $$
  insert into public.e10_mutation_receipts (idempotency_key, rpc, item_id, actor_uid, movement_id, input_fingerprint)
  values (p_key, p_rpc, p_item_id, auth.uid(), p_mid, p_fp);
$$;
revoke all on function public._e10_inv_receipt_write(text, text, text, text, uuid) from public, anon, authenticated;

-- Replay response builder: never returns stored state verbatim — always the CURRENT authoritative item
-- state + revision, plus the original receipt identity + movement_id (blocker 3).
create or replace function public._e10_inv_replay_json(p_item_id text, p_rec jsonb)
  returns jsonb language sql security definer set search_path to 'public' stable as $$
  select jsonb_build_object('ok', true, 'replay', true, 'msg', 'replay',
    'item', case when p_item_id is null then null else public._e10_inv_item_json(p_item_id) end,
    'rev', (select rev from public.e10_workspace where id = 'shared'),
    'movement_id', p_rec->'movement_id',
    'idempotency_key', p_rec->'idempotency_key');
$$;
revoke all on function public._e10_inv_replay_json(text, jsonb) from public, anon, authenticated;

-- ═══════════════════════════════════════════════════════════════════════════════
-- REWRITTEN RPCs. Uniform shape: guard → require key → fingerprint → advisory-lock+receipt-check
-- (replay/mismatch) → lock row(s) → validate (invariants) → mutate → clamp (qty-reducers) → blob write
-- → emit movement → write receipt → return {ok,msg,item,rev,movement_id}.
-- ═══════════════════════════════════════════════════════════════════════════════

-- 1. add_item ────────────────────────────────────────────────────────────────
create or replace function public.e10_inv_add_item(p_item jsonb, p_idempotency_key text)
  returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_actor text := auth.jwt()->>'email'; v_id text := p_item->>'id';
        v_qty numeric; v_mid uuid; v_rev bigint; v_extra jsonb; v_fp text; v_rc jsonb; v_bad text;
begin
  perform public._e10_inv_guard();
  if p_idempotency_key is null or btrim(p_idempotency_key) = '' then
    return jsonb_build_object('ok',false,'msg','idempotency_key required'); end if;
  if v_id is null or btrim(v_id) = '' then return jsonb_build_object('ok',false,'msg','item id required'); end if;
  v_fp := md5(coalesce(p_item::text,''));
  v_rc := public._e10_inv_receipt_check(p_idempotency_key, 'add_item', v_id, v_fp);
  if v_rc ? '_mismatch' then return jsonb_build_object('ok',false,'msg','idempotency key reused with different arguments'); end if;
  if v_rc is not null then return public._e10_inv_replay_json(v_id, v_rc); end if;
  -- invariants (blocker 6)
  v_bad := public._e10_inv_bad_num(p_item, array['qty','cost','value','perBoxCost','boxesPerCase','soldQty','soldProceeds','soldAt','addedAt']);
  if v_bad is not null then return jsonb_build_object('ok',false,'msg',v_bad||' must be a number'); end if;
  v_qty := coalesce(nullif(p_item->>'qty','')::numeric, 0);
  if v_qty < 0 then return jsonb_build_object('ok',false,'msg','qty cannot be negative'); end if;
  if coalesce(nullif(p_item->>'cost','')::numeric,0) < 0 then return jsonb_build_object('ok',false,'msg','cost cannot be negative'); end if;
  if coalesce(nullif(p_item->>'value','')::numeric,0) < 0 then return jsonb_build_object('ok',false,'msg','value cannot be negative'); end if;
  if coalesce(nullif(p_item->>'perBoxCost','')::numeric,0) < 0 then return jsonb_build_object('ok',false,'msg','perBoxCost cannot be negative'); end if;
  if p_item ? 'boxesPerCase' and nullif(p_item->>'boxesPerCase','') is not null
     and (p_item->>'boxesPerCase')::numeric < 1 then return jsonb_build_object('ok',false,'msg','boxesPerCase must be >= 1'); end if;
  if exists (select 1 from public.e10_inventory_items where id = v_id) then
    return jsonb_build_object('ok',false,'msg','item already exists'); end if;
  v_extra := nullif(p_item - array['id','name','cat','set','setId','cond','year','parallel','cardNumber',
    'rarity','grade','gradingCompany','img','qty','cost','value','perBoxCost','boxesPerCase','soldQty',
    'soldProceeds','soldAt','cardId','playerId','owner','addedAt','seed','reservations'], '{}'::jsonb);
  insert into public.e10_inventory_items (
    id,name,cat,card_set,set_id,cond,year,parallel,card_number,rarity,grade,grading_company,img,
    qty,cost,value,per_box_cost,boxes_per_case,sold_qty,sold_proceeds,sold_at,card_id,player_id,
    owner,added_at,seed,extra,updated_by,updated_at)
  values (
    v_id, p_item->>'name', p_item->>'cat', p_item->>'set', p_item->>'setId', p_item->>'cond',
    p_item->>'year', p_item->>'parallel', p_item->>'cardNumber', p_item->>'rarity', p_item->>'grade',
    p_item->>'gradingCompany', p_item->>'img', v_qty, nullif(p_item->>'cost','')::numeric,
    nullif(p_item->>'value','')::numeric, nullif(p_item->>'perBoxCost','')::numeric,
    nullif(p_item->>'boxesPerCase','')::numeric, nullif(p_item->>'soldQty','')::numeric,
    nullif(p_item->>'soldProceeds','')::numeric, nullif(p_item->>'soldAt','')::numeric,
    p_item->>'cardId', p_item->>'playerId', coalesce(p_item->>'owner', v_actor),
    coalesce(nullif(p_item->>'addedAt','')::numeric, (extract(epoch from now())*1000)::numeric),
    (p_item->>'seed')::boolean, v_extra, auth.uid(), now());
  v_rev := public._e10_inv_blob_write(v_id, false, v_actor);
  v_mid := public.e10_emit_inventory_movement(v_id, 'intake', v_qty, 0, p_idempotency_key,
             'add', 'new item', 'inventory', v_id, 'add_item', null, '{}'::jsonb);
  perform public._e10_inv_receipt_write(p_idempotency_key, 'add_item', v_id, v_fp, v_mid);
  return jsonb_build_object('ok',true,'msg','added','item',public._e10_inv_item_json(v_id),'rev',v_rev,'movement_id',v_mid);
end;
$$;

-- 2. edit_item ───────────────────────────────────────────────────────────────
--    + p_remove_keys (blocker 7): WHITELIST-enforced structured/extra-key deletion. Removal of anything
--    outside the whitelist is rejected. Dual twins (set/year, product_line/product_year) are independent.
create or replace function public.e10_inv_edit_item(p_id text, p_patch jsonb, p_idempotency_key text, p_remove_keys text[] default null)
  returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_actor text := auth.jwt()->>'email'; v_old numeric; v_new numeric; v_d numeric;
        v_mid uuid; v_rev bigint; v_item public.e10_inventory_items; v_pextra jsonb;
        v_fp text; v_rc jsonb; v_bad text; v_rm text[] := coalesce(p_remove_keys, '{}');
        v_extra_rm text[]; v_badkeys text[];
        -- whitelist: removable structured columns (token->column below) + removable extra keys.
        v_wl_col text[] := array['cardId','playerId','grade','grading_company','card_number','parallel','set','year'];
        v_wl_extra text[] := array['domain','sport','game','franchise','category_detail','manufacturer',
          'product_year','product_line','configuration','package_type','certification_number','description',
          'item_count','inventory_type','units_per_case','cost_basis_mode'];
begin
  perform public._e10_inv_guard();
  if p_idempotency_key is null or btrim(p_idempotency_key) = '' then
    return jsonb_build_object('ok',false,'msg','idempotency_key required'); end if;
  v_fp := md5(coalesce(p_patch::text,'') || '|rm:' || coalesce(array_to_string(v_rm, ','), ''));
  v_rc := public._e10_inv_receipt_check(p_idempotency_key, 'edit_item', p_id, v_fp);
  if v_rc ? '_mismatch' then return jsonb_build_object('ok',false,'msg','idempotency key reused with different arguments'); end if;
  if v_rc is not null then return public._e10_inv_replay_json(p_id, v_rc); end if;
  -- blocker 7: reject any remove key outside the whitelist BEFORE mutating.
  select array_agg(k) into v_badkeys from unnest(v_rm) k where k <> all(v_wl_col) and k <> all(v_wl_extra);
  if v_badkeys is not null then return jsonb_build_object('ok',false,'msg','cannot remove protected key(s): '||array_to_string(v_badkeys,', ')); end if;
  -- invariants (blocker 6)
  v_bad := public._e10_inv_bad_num(p_patch, array['qty','cost','value','perBoxCost','boxesPerCase','soldQty','soldProceeds','soldAt']);
  if v_bad is not null then return jsonb_build_object('ok',false,'msg',v_bad||' must be a number'); end if;
  if p_patch ? 'qty' and nullif(p_patch->>'qty','') is not null and (p_patch->>'qty')::numeric < 0 then
    return jsonb_build_object('ok',false,'msg','qty cannot be negative'); end if;
  if p_patch ? 'cost' and nullif(p_patch->>'cost','') is not null and (p_patch->>'cost')::numeric < 0 then
    return jsonb_build_object('ok',false,'msg','cost cannot be negative'); end if;
  if p_patch ? 'value' and nullif(p_patch->>'value','') is not null and (p_patch->>'value')::numeric < 0 then
    return jsonb_build_object('ok',false,'msg','value cannot be negative'); end if;
  if p_patch ? 'perBoxCost' and nullif(p_patch->>'perBoxCost','') is not null and (p_patch->>'perBoxCost')::numeric < 0 then
    return jsonb_build_object('ok',false,'msg','perBoxCost cannot be negative'); end if;
  if p_patch ? 'boxesPerCase' and nullif(p_patch->>'boxesPerCase','') is not null and (p_patch->>'boxesPerCase')::numeric < 1 then
    return jsonb_build_object('ok',false,'msg','boxesPerCase must be >= 1'); end if;
  select * into v_item from public.e10_inventory_items where id = p_id for update;
  if not found then return jsonb_build_object('ok',false,'msg','item not found'); end if;
  v_old := coalesce(v_item.qty, 0);
  v_extra_rm := array(select k from unnest(v_rm) k where k = any(v_wl_extra));
  v_pextra := p_patch - array['id','name','cat','set','setId','cond','year','parallel','cardNumber',
    'rarity','grade','gradingCompany','img','qty','cost','value','perBoxCost','boxesPerCase','soldQty',
    'soldProceeds','soldAt','cardId','playerId','owner','addedAt','seed','reservations'];
  update public.e10_inventory_items set
    name            = case when p_patch ? 'name' then p_patch->>'name' else name end,
    cat             = case when p_patch ? 'cat' then p_patch->>'cat' else cat end,
    card_set        = case when 'set' = any(v_rm) then null when p_patch ? 'set' then p_patch->>'set' else card_set end,
    set_id          = case when p_patch ? 'setId' then p_patch->>'setId' else set_id end,
    cond            = case when p_patch ? 'cond' then p_patch->>'cond' else cond end,
    year            = case when 'year' = any(v_rm) then null when p_patch ? 'year' then p_patch->>'year' else year end,
    parallel        = case when 'parallel' = any(v_rm) then null when p_patch ? 'parallel' then p_patch->>'parallel' else parallel end,
    card_number     = case when 'card_number' = any(v_rm) then null when p_patch ? 'cardNumber' then p_patch->>'cardNumber' else card_number end,
    rarity          = case when p_patch ? 'rarity' then p_patch->>'rarity' else rarity end,
    grade           = case when 'grade' = any(v_rm) then null when p_patch ? 'grade' then p_patch->>'grade' else grade end,
    grading_company = case when 'grading_company' = any(v_rm) then null when p_patch ? 'gradingCompany' then p_patch->>'gradingCompany' else grading_company end,
    img             = case when p_patch ? 'img' then p_patch->>'img' else img end,
    qty             = case when p_patch ? 'qty' then nullif(p_patch->>'qty','')::numeric else qty end,
    cost            = case when p_patch ? 'cost' then nullif(p_patch->>'cost','')::numeric else cost end,
    value           = case when p_patch ? 'value' then nullif(p_patch->>'value','')::numeric else value end,
    per_box_cost    = case when p_patch ? 'perBoxCost' then nullif(p_patch->>'perBoxCost','')::numeric else per_box_cost end,
    boxes_per_case  = case when p_patch ? 'boxesPerCase' then nullif(p_patch->>'boxesPerCase','')::numeric else boxes_per_case end,
    card_id         = case when 'cardId' = any(v_rm) then null when p_patch ? 'cardId' then p_patch->>'cardId' else card_id end,
    player_id       = case when 'playerId' = any(v_rm) then null when p_patch ? 'playerId' then p_patch->>'playerId' else player_id end,
    owner           = case when p_patch ? 'owner' then p_patch->>'owner' else owner end,
    extra           = (case when v_pextra = '{}'::jsonb then coalesce(extra,'{}'::jsonb) else coalesce(extra,'{}'::jsonb) || v_pextra end) - v_extra_rm,
    updated_by = auth.uid(), updated_at = now()
  where id = p_id;
  perform public._e10_inv_clamp_res(p_id, p_idempotency_key);
  select qty into v_new from public.e10_inventory_items where id = p_id;
  v_new := coalesce(v_new, 0);
  v_rev := public._e10_inv_blob_write(p_id, false, v_actor);
  v_d := v_new - v_old;
  if v_d > 0 then
    v_mid := public.e10_emit_inventory_movement(p_id, 'manual_increase', v_d, 0, p_idempotency_key,
               'manual_edit', 'qty adjusted', 'inventory', p_id, 'edit_item', null, '{}'::jsonb);
  elsif v_d < 0 then
    v_mid := public.e10_emit_inventory_movement(p_id, 'manual_decrease', v_d, 0, p_idempotency_key,
               'manual_edit', 'qty adjusted', 'inventory', p_id, 'edit_item', null, '{}'::jsonb);
  end if;
  perform public._e10_inv_receipt_write(p_idempotency_key, 'edit_item', p_id, v_fp, v_mid);
  return jsonb_build_object('ok',true,'msg','saved','item',public._e10_inv_item_json(p_id),'rev',v_rev,'movement_id',v_mid);
end;
$$;

-- 3. delete_item ─────────────────────────────────────────────────────────────
create or replace function public.e10_inv_delete_item(p_id text, p_idempotency_key text)
  returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_actor text := auth.jwt()->>'email'; v_qty numeric; v_res numeric; v_mid uuid; v_rev bigint;
        v_fp text; v_rc jsonb;
begin
  perform public._e10_inv_guard();
  if p_idempotency_key is null or btrim(p_idempotency_key) = '' then
    return jsonb_build_object('ok',false,'msg','idempotency_key required'); end if;
  v_fp := md5(coalesce(p_id,''));
  v_rc := public._e10_inv_receipt_check(p_idempotency_key, 'delete_item', p_id, v_fp);
  if v_rc ? '_mismatch' then return jsonb_build_object('ok',false,'msg','idempotency key reused with different arguments'); end if;
  if v_rc is not null then return jsonb_build_object('ok',true,'replay',true,'msg','replay','item',null,
    'rev',(select rev from public.e10_workspace where id='shared'),'movement_id',v_rc->'movement_id','idempotency_key',v_rc->'idempotency_key'); end if;
  select qty into v_qty from public.e10_inventory_items where id = p_id for update;
  if not found then return jsonb_build_object('ok',false,'msg','item not found'); end if;
  v_qty := coalesce(v_qty, 0);
  select coalesce(sum(qty),0) into v_res from public.e10_inventory_reservations
    where item_id = p_id and status = 'active';
  if v_qty <> 0 or v_res <> 0 then
    v_mid := public.e10_emit_inventory_movement(p_id, 'correction', -v_qty, -v_res, p_idempotency_key,
               'item_deleted', 'item removed from inventory', 'inventory', p_id, 'delete_item', null, '{}'::jsonb);
  end if;
  delete from public.e10_inventory_items where id = p_id;  -- cascades reservations
  v_rev := public._e10_inv_blob_write(p_id, true, v_actor);
  perform public._e10_inv_receipt_write(p_idempotency_key, 'delete_item', p_id, v_fp, v_mid);
  return jsonb_build_object('ok',true,'msg','deleted','item',null,'rev',v_rev,'movement_id',v_mid);
end;
$$;

-- 4. mark_sold ───────────────────────────────────────────────────────────────
--    Invariants (blocker 6): sell qty positive; NEVER drive qty negative (rejected for EVERYONE incl
--    admin); non-admin still capped to available; admin may sell into reserved (clamp trims reserved).
create or replace function public.e10_inv_mark_sold(p_id text, p_qty numeric, p_proceeds numeric, p_idempotency_key text)
  returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_actor text := auth.jwt()->>'email'; v_qty numeric; v_res numeric; v_avail numeric;
        v_mid uuid; v_rev bigint; v_fp text; v_rc jsonb;
begin
  perform public._e10_inv_guard();
  if p_idempotency_key is null or btrim(p_idempotency_key) = '' then
    return jsonb_build_object('ok',false,'msg','idempotency_key required'); end if;
  v_fp := md5(coalesce(p_id,'')||'|'||coalesce(p_qty::text,'')||'|'||coalesce(p_proceeds::text,''));
  v_rc := public._e10_inv_receipt_check(p_idempotency_key, 'mark_sold', p_id, v_fp);
  if v_rc ? '_mismatch' then return jsonb_build_object('ok',false,'msg','idempotency key reused with different arguments'); end if;
  if v_rc is not null then return public._e10_inv_replay_json(p_id, v_rc); end if;
  if p_qty is null or p_qty <= 0 then return jsonb_build_object('ok',false,'msg','sell qty must be positive'); end if;
  if p_proceeds is not null and p_proceeds < 0 then return jsonb_build_object('ok',false,'msg','proceeds cannot be negative'); end if;
  select qty into v_qty from public.e10_inventory_items where id = p_id for update;
  if not found then return jsonb_build_object('ok',false,'msg','item not found'); end if;
  select coalesce(sum(qty),0) into v_res from public.e10_inventory_reservations where item_id = p_id and status = 'active';
  v_avail := coalesce(v_qty,0) - v_res;
  if p_qty > coalesce(v_qty,0) then return jsonb_build_object('ok',false,'msg','cannot sell more than '||coalesce(v_qty,0)||' on hand'); end if;  -- no negative, everyone
  if p_qty > v_avail and not (select public.e10_is_admin()) then
    return jsonb_build_object('ok',false,'msg','only '||v_avail||' available'); end if;
  update public.e10_inventory_items set
    qty = coalesce(qty,0) - p_qty,
    sold_qty = coalesce(sold_qty,0) + p_qty,
    sold_proceeds = coalesce(sold_proceeds,0) + coalesce(p_proceeds,0),
    sold_at = (extract(epoch from now())*1000)::numeric,
    updated_by = auth.uid(), updated_at = now()
  where id = p_id;
  perform public._e10_inv_clamp_res(p_id, p_idempotency_key);
  v_rev := public._e10_inv_blob_write(p_id, false, v_actor);
  v_mid := public.e10_emit_inventory_movement(p_id, 'sale', -p_qty, 0, p_idempotency_key,
             'sale', 'marked sold', 'inventory', p_id, 'mark_sold', null,
             jsonb_build_object('proceeds', coalesce(p_proceeds,0)));
  perform public._e10_inv_receipt_write(p_idempotency_key, 'mark_sold', p_id, v_fp, v_mid);
  return jsonb_build_object('ok',true,'msg','sold','item',public._e10_inv_item_json(p_id),'rev',v_rev,'movement_id',v_mid);
end;
$$;

-- 5. reserve ─────────────────────────────────────────────────────────────────
--    reserved <= qty is a HARD invariant (blocker 6): reserving beyond available is rejected for
--    EVERYONE (admin override removed here — the batch set-reservations RPC owns target-setting).
create or replace function public.e10_inv_reserve(p_id text, p_show_ref text, p_show_label text,
    p_qty numeric, p_idempotency_key text)
  returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_actor text := auth.jwt()->>'email'; v_qty numeric; v_res numeric; v_avail numeric;
        v_mid uuid; v_rev bigint; v_fp text; v_rc jsonb;
begin
  perform public._e10_inv_guard();
  if p_idempotency_key is null or btrim(p_idempotency_key) = '' then
    return jsonb_build_object('ok',false,'msg','idempotency_key required'); end if;
  v_fp := md5(coalesce(p_id,'')||'|'||coalesce(p_show_ref,'')||'|'||coalesce(p_qty::text,''));
  v_rc := public._e10_inv_receipt_check(p_idempotency_key, 'reserve', p_id, v_fp);
  if v_rc ? '_mismatch' then return jsonb_build_object('ok',false,'msg','idempotency key reused with different arguments'); end if;
  if v_rc is not null then return public._e10_inv_replay_json(p_id, v_rc); end if;
  if p_qty is null or p_qty <= 0 then return jsonb_build_object('ok',false,'msg','reserve qty must be positive'); end if;
  select qty into v_qty from public.e10_inventory_items where id = p_id for update;
  if not found then return jsonb_build_object('ok',false,'msg','item not found'); end if;
  select coalesce(sum(qty),0) into v_res from public.e10_inventory_reservations where item_id = p_id and status = 'active';
  v_avail := coalesce(v_qty,0) - v_res;
  if p_qty > v_avail then return jsonb_build_object('ok',false,'msg','only '||v_avail||' available'); end if;  -- reserved<=qty, everyone
  insert into public.e10_inventory_reservations (item_id, show_ref, show_label, streamer_uid, qty, status, created_by)
    values (p_id, p_show_ref, p_show_label, auth.uid()::text, p_qty, 'active', auth.uid());
  v_rev := public._e10_inv_blob_write(p_id, false, v_actor);
  v_mid := public.e10_emit_inventory_movement(p_id, 'reservation', 0, p_qty, p_idempotency_key,
             'reserve', 'reserved to show', 'show', p_show_ref, 'reserve', null, '{}'::jsonb);
  perform public._e10_inv_receipt_write(p_idempotency_key, 'reserve', p_id, v_fp, v_mid);
  return jsonb_build_object('ok',true,'msg','reserved','item',public._e10_inv_item_json(p_id),'rev',v_rev,'movement_id',v_mid);
end;
$$;

-- 6. release ─────────────────────────────────────────────────────────────────
--    Blocker 2: non-admin may release ONLY their own rows; admin any. Legacy created_by=null rows are
--    owned via streamer_uid = auth.uid()::text.
create or replace function public.e10_inv_release(p_id text, p_show_ref text, p_idempotency_key text)
  returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_actor text := auth.jwt()->>'email'; v_rel numeric; v_mid uuid; v_rev bigint;
        v_fp text; v_rc jsonb; v_admin boolean := (select public.e10_is_admin());
begin
  perform public._e10_inv_guard();
  if p_idempotency_key is null or btrim(p_idempotency_key) = '' then
    return jsonb_build_object('ok',false,'msg','idempotency_key required'); end if;
  v_fp := md5(coalesce(p_id,'')||'|'||coalesce(p_show_ref,''));
  v_rc := public._e10_inv_receipt_check(p_idempotency_key, 'release', p_id, v_fp);
  if v_rc ? '_mismatch' then return jsonb_build_object('ok',false,'msg','idempotency key reused with different arguments'); end if;
  if v_rc is not null then return public._e10_inv_replay_json(p_id, v_rc); end if;
  perform 1 from public.e10_inventory_items where id = p_id for update;
  if not found then return jsonb_build_object('ok',false,'msg','item not found'); end if;
  -- only the caller's own rows for a non-admin (blocker 2)
  select coalesce(sum(qty),0) into v_rel from public.e10_inventory_reservations
    where item_id = p_id and show_ref is not distinct from p_show_ref and status = 'active'
      and (v_admin or created_by = auth.uid() or (created_by is null and streamer_uid = auth.uid()::text));
  if v_rel = 0 then return jsonb_build_object('ok',false,'msg','no active reservation of yours for that show'); end if;
  update public.e10_inventory_reservations set status = 'released'
    where item_id = p_id and show_ref is not distinct from p_show_ref and status = 'active'
      and (v_admin or created_by = auth.uid() or (created_by is null and streamer_uid = auth.uid()::text));
  v_rev := public._e10_inv_blob_write(p_id, false, v_actor);
  v_mid := public.e10_emit_inventory_movement(p_id, 'reservation_release', 0, -v_rel, p_idempotency_key,
             'release', 'reservation released', 'show', p_show_ref, 'release', null, '{}'::jsonb);
  perform public._e10_inv_receipt_write(p_idempotency_key, 'release', p_id, v_fp, v_mid);
  return jsonb_build_object('ok',true,'msg','released','item',public._e10_inv_item_json(p_id),'rev',v_rev,'movement_id',v_mid);
end;
$$;

-- 7. consume ─────────────────────────────────────────────────────────────────
--    Blocker 5: signature is (p_id, p_break_session_id, p_source_show_ref, p_qty, key) — NO caller
--    p_reserved_qty. The SERVER derives the reserved portion from active reservations MATCHED BY
--    p_source_show_ref (never the session id), scoped to the caller (non-admin) or all (admin), draws
--    them down FIFO, and records the exact allocation in meta so reversal can reconstruct it.
--    Blocker 6: qty may never go negative (rejected for everyone).
create or replace function public.e10_inv_consume(p_id text, p_break_session_id text, p_source_show_ref text,
    p_qty numeric, p_idempotency_key text)
  returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_actor text := auth.jwt()->>'email'; v_qty numeric; v_mid uuid; v_rev bigint;
        v_fp text; v_rc jsonb; v_admin boolean := (select public.e10_is_admin());
        v_draw numeric := 0; v_remaining numeric; v_cut numeric; r record; v_alloc jsonb := '[]'::jsonb;
begin
  perform public._e10_inv_guard();
  if p_idempotency_key is null or btrim(p_idempotency_key) = '' then
    return jsonb_build_object('ok',false,'msg','idempotency_key required'); end if;
  v_fp := md5(coalesce(p_id,'')||'|'||coalesce(p_break_session_id,'')||'|'||coalesce(p_source_show_ref,'')||'|'||coalesce(p_qty::text,''));
  v_rc := public._e10_inv_receipt_check(p_idempotency_key, 'consume', p_id, v_fp);
  if v_rc ? '_mismatch' then return jsonb_build_object('ok',false,'msg','idempotency key reused with different arguments'); end if;
  if v_rc is not null then return public._e10_inv_replay_json(p_id, v_rc); end if;
  if p_qty is null or p_qty <= 0 then return jsonb_build_object('ok',false,'msg','consume qty must be positive'); end if;
  select qty into v_qty from public.e10_inventory_items where id = p_id for update;
  if not found then return jsonb_build_object('ok',false,'msg','item not found'); end if;
  if p_qty > coalesce(v_qty,0) then return jsonb_build_object('ok',false,'msg','cannot consume more than '||coalesce(v_qty,0)||' on hand'); end if;  -- no negative
  -- derive the reserved drawdown from matching active reservations (by SOURCE SHOW REF), FIFO.
  if p_source_show_ref is not null and btrim(p_source_show_ref) <> '' then
    v_remaining := p_qty;
    for r in select id, qty, show_ref, show_label, streamer_uid, created_by
               from public.e10_inventory_reservations
              where item_id = p_id and show_ref is not distinct from p_source_show_ref and status = 'active'
                and (v_admin or created_by = auth.uid() or (created_by is null and streamer_uid = auth.uid()::text))
              order by created_at asc
              for update loop
      exit when v_remaining <= 0;
      v_cut := least(r.qty, v_remaining);
      if v_cut >= r.qty then
        update public.e10_inventory_reservations set status = 'consumed' where id = r.id;
      else
        update public.e10_inventory_reservations set qty = qty - v_cut where id = r.id;
      end if;
      v_alloc := v_alloc || jsonb_build_object('qty', v_cut, 'show_ref', r.show_ref, 'show_label', r.show_label,
                   'streamer_uid', r.streamer_uid, 'created_by', r.created_by);
      v_draw := v_draw + v_cut; v_remaining := v_remaining - v_cut;
    end loop;
  end if;
  update public.e10_inventory_items set qty = coalesce(qty,0) - p_qty, updated_by = auth.uid(), updated_at = now()
    where id = p_id;
  perform public._e10_inv_clamp_res(p_id, p_idempotency_key);
  v_rev := public._e10_inv_blob_write(p_id, false, v_actor);
  v_mid := public.e10_emit_inventory_movement(p_id, 'break_consumption', -p_qty, -v_draw, p_idempotency_key,
             'break', 'consumed by break', 'break_session', p_break_session_id, 'consume', null,
             jsonb_build_object('consumed_qty', p_qty, 'source_show_ref', p_source_show_ref, 'reserved_drawn', v_draw, 'allocation', v_alloc));
  perform public._e10_inv_receipt_write(p_idempotency_key, 'consume', p_id, v_fp, v_mid);
  return jsonb_build_object('ok',true,'msg','consumed','item',public._e10_inv_item_json(p_id),'rev',v_rev,'movement_id',v_mid);
end;
$$;

-- 8. reverse_consumption ─────────────────────────────────────────────────────
--    Blocker 5: signature is (p_id, p_reverses_movement_id, key) — server RECONSTRUCTS the pre-consume
--    state from the original consumption movement's meta: restores the consumed on-hand AND recreates
--    the reservation rows as they were; reserved_delta equals the quantity actually re-reserved.
create or replace function public.e10_inv_reverse_consumption(p_id text, p_reverses_movement_id uuid, p_idempotency_key text)
  returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_actor text := auth.jwt()->>'email'; v_mid uuid; v_rev bigint; v_fp text; v_rc jsonb;
        v_src record; v_meta jsonb; v_cq numeric; v_draw numeric; a jsonb; v_sess text;
begin
  perform public._e10_inv_guard();
  if p_idempotency_key is null or btrim(p_idempotency_key) = '' then
    return jsonb_build_object('ok',false,'msg','idempotency_key required'); end if;
  v_fp := md5(coalesce(p_id,'')||'|'||coalesce(p_reverses_movement_id::text,''));
  v_rc := public._e10_inv_receipt_check(p_idempotency_key, 'reverse_consumption', p_id, v_fp);
  if v_rc ? '_mismatch' then return jsonb_build_object('ok',false,'msg','idempotency key reused with different arguments'); end if;
  if v_rc is not null then return public._e10_inv_replay_json(p_id, v_rc); end if;
  select item_id, movement_type, on_hand_delta, meta, source_entity_id
    into v_src from public.e10_inventory_movements where id = p_reverses_movement_id;
  if not found then return jsonb_build_object('ok',false,'msg','movement to reverse not found'); end if;
  if v_src.movement_type <> 'break_consumption' then return jsonb_build_object('ok',false,'msg','not a break consumption movement'); end if;
  if v_src.item_id is distinct from p_id then return jsonb_build_object('ok',false,'msg','movement item mismatch'); end if;
  perform 1 from public.e10_inventory_items where id = p_id for update;
  if not found then return jsonb_build_object('ok',false,'msg','item not found'); end if;
  v_meta := coalesce(v_src.meta, '{}'::jsonb);
  v_cq   := coalesce(nullif(v_meta->>'consumed_qty','')::numeric, -coalesce(v_src.on_hand_delta,0));  -- restore this on-hand
  v_draw := coalesce(nullif(v_meta->>'reserved_drawn','')::numeric, 0);
  v_sess := v_src.source_entity_id;
  begin
    update public.e10_inventory_items set qty = coalesce(qty,0) + v_cq, updated_by = auth.uid(), updated_at = now()
      where id = p_id;
    -- recreate the reservation rows exactly as they were at consume time (blocker 5)
    for a in select * from jsonb_array_elements(coalesce(v_meta->'allocation','[]'::jsonb)) loop
      insert into public.e10_inventory_reservations (item_id, show_ref, show_label, streamer_uid, qty, status, created_by)
        values (p_id, a->>'show_ref', a->>'show_label', a->>'streamer_uid', (a->>'qty')::numeric, 'active',
                nullif(a->>'created_by','')::uuid);
    end loop;
    v_rev := public._e10_inv_blob_write(p_id, false, v_actor);
    v_mid := public.e10_emit_inventory_movement(p_id, 'break_reversal', v_cq, v_draw, p_idempotency_key,
               'break', 'break consumption reversed', 'break_session', v_sess, 'reverse',
               p_reverses_movement_id, jsonb_build_object('restored_qty', v_cq, 'reserved_restored', v_draw));
  exception when others then
    return jsonb_build_object('ok',false,'msg','reversal rejected: '||sqlerrm);
  end;
  perform public._e10_inv_receipt_write(p_idempotency_key, 'reverse_consumption', p_id, v_fp, v_mid);
  return jsonb_build_object('ok',true,'msg','reversed','item',public._e10_inv_item_json(p_id),'rev',v_rev,'movement_id',v_mid);
end;
$$;

-- 9. set_reservations (NEW, batch, atomic) ───────────────────────────────────
--    Blocker 4: SET the caller's reservation for each (item, show) to a target, ALL-or-NOTHING in one
--    transaction. Locks all target items in deterministic id order (deadlock avoidance), validates
--    every target on fresh data FIRST, then mutates + emits net movements only if all pass. One receipt
--    for the batch. Blocker 2 per-caller scoping: a non-admin's target applies only to their own rows
--    and can never absorb another user's reservation; an admin sets the full (item, show) target.
create or replace function public.e10_inv_set_reservations(p_show_ref text, p_show_label text, p_targets jsonb, p_idempotency_key text)
  returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_actor text := auth.jwt()->>'email'; v_admin boolean := (select public.e10_is_admin());
        v_fp text; v_rc jsonb; t jsonb; v_ids text[]; v_id text; v_tq numeric; v_item_qty numeric;
        v_caller numeric; v_total numeric; v_other numeric; v_net numeric; v_rev bigint;
        v_items jsonb := '[]'::jsonb; r record; v_cut numeric; v_reduce numeric; v_mid uuid;
begin
  perform public._e10_inv_guard();
  if p_idempotency_key is null or btrim(p_idempotency_key) = '' then
    return jsonb_build_object('ok',false,'msg','idempotency_key required'); end if;
  if p_targets is null or jsonb_typeof(p_targets) <> 'array' then
    return jsonb_build_object('ok',false,'msg','targets must be an array'); end if;
  v_fp := md5(coalesce(p_show_ref,'')||'|'||coalesce(p_targets::text,''));
  v_rc := public._e10_inv_receipt_check(p_idempotency_key, 'set_reservations', null, v_fp);
  if v_rc ? '_mismatch' then return jsonb_build_object('ok',false,'msg','idempotency key reused with different arguments'); end if;
  if v_rc is not null then return jsonb_build_object('ok',true,'replay',true,'msg','replay','item',null,
    'rev',(select rev from public.e10_workspace where id='shared'),'movement_id',null,'idempotency_key',v_rc->'idempotency_key'); end if;
  -- deterministic id order lock (deadlock avoidance)
  select array_agg(distinct (e->>'item_id') order by (e->>'item_id')) into v_ids
    from jsonb_array_elements(p_targets) e where coalesce(e->>'item_id','') <> '';
  if v_ids is null then return jsonb_build_object('ok',false,'msg','no targets'); end if;
  perform 1 from public.e10_inventory_items where id = any(v_ids) order by id for update;
  -- VALIDATE ALL FIRST (fresh data), zero mutation on any failure
  for t in select * from jsonb_array_elements(p_targets) loop
    v_id := t->>'item_id'; v_tq := coalesce(nullif(t->>'qty','')::numeric, 0);
    select qty into v_item_qty from public.e10_inventory_items where id = v_id;
    if not found then return jsonb_build_object('ok',false,'msg','item not found: '||coalesce(v_id,'?')); end if;
    if v_tq < 0 then return jsonb_build_object('ok',false,'msg','target qty cannot be negative for '||v_id); end if;
    -- caller's current reservation for this (item, show); other = everything else active on the item
    select coalesce(sum(qty),0) into v_caller from public.e10_inventory_reservations
      where item_id = v_id and show_ref is not distinct from p_show_ref and status = 'active'
        and (v_admin or created_by = auth.uid() or (created_by is null and streamer_uid = auth.uid()::text));
    select coalesce(sum(qty),0) into v_total from public.e10_inventory_reservations
      where item_id = v_id and status = 'active';
    v_other := v_total - v_caller;
    if v_tq + v_other > coalesce(v_item_qty,0) then
      return jsonb_build_object('ok',false,'msg','item '||v_id||': target '||v_tq||' exceeds available '||(coalesce(v_item_qty,0)-v_other)); end if;
  end loop;
  -- APPLY (all validated)
  for t in select * from jsonb_array_elements(p_targets) loop
    v_id := t->>'item_id'; v_tq := coalesce(nullif(t->>'qty','')::numeric, 0);
    select coalesce(sum(qty),0) into v_caller from public.e10_inventory_reservations
      where item_id = v_id and show_ref is not distinct from p_show_ref and status = 'active'
        and (v_admin or created_by = auth.uid() or (created_by is null and streamer_uid = auth.uid()::text));
    v_net := v_tq - v_caller;
    if v_net > 0 then
      insert into public.e10_inventory_reservations (item_id, show_ref, show_label, streamer_uid, qty, status, created_by)
        values (v_id, p_show_ref, p_show_label, auth.uid()::text, v_net, 'active', auth.uid());
      v_mid := public.e10_emit_inventory_movement(v_id, 'reservation', 0, v_net, p_idempotency_key||':'||v_id,
                 'set_reservations', 'reservation set', 'show', p_show_ref, 'set_reservations', null, '{}'::jsonb);
    elsif v_net < 0 then
      v_reduce := -v_net;
      for r in select id, qty from public.e10_inventory_reservations
                 where item_id = v_id and show_ref is not distinct from p_show_ref and status = 'active'
                   and (v_admin or created_by = auth.uid() or (created_by is null and streamer_uid = auth.uid()::text))
                 order by created_at desc for update loop
        exit when v_reduce <= 0;
        v_cut := least(r.qty, v_reduce);
        if v_cut >= r.qty then update public.e10_inventory_reservations set status = 'released' where id = r.id;
        else update public.e10_inventory_reservations set qty = qty - v_cut where id = r.id; end if;
        v_reduce := v_reduce - v_cut;
      end loop;
      v_mid := public.e10_emit_inventory_movement(v_id, 'reservation_release', 0, v_net, p_idempotency_key||':'||v_id,
                 'set_reservations', 'reservation set', 'show', p_show_ref, 'set_reservations', null, '{}'::jsonb);
    end if;
    perform public._e10_inv_blob_write(v_id, false, v_actor);
    v_items := v_items || jsonb_build_object('item_id', v_id, 'target', v_tq, 'net', v_net, 'item', public._e10_inv_item_json(v_id));
  end loop;
  v_rev := (select rev from public.e10_workspace where id = 'shared');
  perform public._e10_inv_receipt_write(p_idempotency_key, 'set_reservations', null, v_fp, null);
  return jsonb_build_object('ok',true,'msg','reservations set','items',v_items,'rev',v_rev,'movement_id',null);
end;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Blocker 2 legacy backfill: stamp created_by from streamer_uid where it parses as a valid member uuid,
-- so members are not locked out of their own legacy (created_by=null) reservations.
update public.e10_inventory_reservations r
   set created_by = r.streamer_uid::uuid
 where r.created_by is null
   and r.streamer_uid ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
   and exists (select 1 from public.e10_members m where m.user_id = r.streamer_uid::uuid);

-- ─────────────────────────────────────────────────────────────────────────────
-- Execution grants (members call; anon cannot; RPCs re-check membership internally).
do $$
declare fn text;
begin
  foreach fn in array array[
    'e10_inv_add_item(jsonb,text)', 'e10_inv_edit_item(text,jsonb,text,text[])', 'e10_inv_delete_item(text,text)',
    'e10_inv_reserve(text,text,text,numeric,text)', 'e10_inv_release(text,text,text)',
    'e10_inv_mark_sold(text,numeric,numeric,text)',
    'e10_inv_consume(text,text,text,numeric,text)',
    'e10_inv_reverse_consumption(text,uuid,text)',
    'e10_inv_set_reservations(text,text,jsonb,text)'
  ] loop
    execute format('revoke all on function public.%s from public, anon', fn);
    execute format('grant execute on function public.%s to authenticated', fn);
  end loop;
end $$;

-- ═══════════════════════════════════════════════════════════════════════════════
-- ROLLBACK (down-block, DO NOT run unless reverting M3.1a). Restores the M3 baseline bodies (imperfect
-- but known-good) and drops the M3.1 additions. Touches NO rows except dropping receipts (committed
-- mutations only). The M3 baseline for consume/reverse used p_reserved_qty; restore those signatures.
--   drop function if exists public.e10_inv_set_reservations(text,text,jsonb,text);
--   drop function if exists public.e10_inv_consume(text,text,text,numeric,text);
--   drop function if exists public.e10_inv_reverse_consumption(text,uuid,text);
--   drop function if exists public.e10_inv_edit_item(text,jsonb,text,text[]);
--   drop table if exists public.e10_mutation_receipts;
--   drop function if exists public._e10_inv_receipt_check(text,text,text,text);
--   drop function if exists public._e10_inv_receipt_write(text,text,text,text,uuid);
--   drop function if exists public._e10_inv_replay_json(text,jsonb);
--   drop function if exists public._e10_inv_bad_num(jsonb,text[]);
--   -- then re-apply migrations ..124500 (edit_item/reserve/release/consume/reverse_consumption bodies),
--   -- ..130000 (add_item/edit_item extra passthrough), ..131500 (clamp + mark_sold/consume/edit_item).
--   -- created_by backfill is data-safe to leave (it only filled nulls from streamer_uid); no revert needed.
-- ═══════════════════════════════════════════════════════════════════════════════
