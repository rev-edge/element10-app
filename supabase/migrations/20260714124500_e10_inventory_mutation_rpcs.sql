-- Migration: e10_inventory_mutation_rpcs  (Chain M — M2: transactional mutation RPCs)
-- The authoritative inventory mutation surface. Each RPC, in ONE transaction: locks the item row,
-- checks the idempotency key BEFORE mutating (replay -> zero mutation, returns the committed result),
-- validates on fresh data, mutates the relational rows, updates the blob's inventory section (the
-- dual-write that keeps rollback open through M3), and appends the ledger movement via the INTERNAL
-- e10_emit_inventory_movement. ADDITIVE (functions + helpers); also DROPS imov_ins (emission is now
-- exclusively internal to these SECURITY DEFINER RPCs).
--
-- Idempotency-key convention (schema.sql, emit block): '<scope>:shared:<source_entity_id>:<item_id>'.
-- Movement mapping: add->intake; qty +/- ->manual_increase/manual_decrease; reserve/release->
-- reservation/reservation_release (reserved_delta only); sold->sale; delete->correction (zeroes
-- on_hand+reserved); consume/reverse->break_consumption/break_reversal.

-- ─────────────────────────────────────────────────────────────────────────────
-- Helper A: canonical item -> JSONB builder (camelCase, matches the blob shape). Reservations are
-- rebuilt from active child rows. jsonb_strip_nulls drops null optional keys (matches normShared's
-- absent=null). This is also exactly what M4's blob reprojection reuses.
create or replace function public._e10_inv_item_json(p_id text)
  returns jsonb language sql security definer set search_path to 'public' stable as $$
  select case when it.id is null then null else
    jsonb_strip_nulls(jsonb_build_object(
      'id', it.id, 'name', it.name, 'cat', it.cat, 'set', it.card_set, 'setId', it.set_id,
      'cond', it.cond, 'year', it.year, 'parallel', it.parallel, 'cardNumber', it.card_number,
      'rarity', it.rarity, 'grade', it.grade, 'gradingCompany', it.grading_company, 'img', it.img,
      'qty', it.qty, 'cost', it.cost, 'value', it.value, 'perBoxCost', it.per_box_cost,
      'boxesPerCase', it.boxes_per_case, 'soldQty', it.sold_qty, 'soldProceeds', it.sold_proceeds,
      'soldAt', it.sold_at, 'cardId', it.card_id, 'playerId', it.player_id, 'owner', it.owner,
      'addedAt', it.added_at, 'seed', it.seed))
    || jsonb_build_object('reservations', coalesce((
         select jsonb_agg(jsonb_build_object('qty', rr.qty, 'showId', rr.show_ref,
                  'showLabel', rr.show_label, 'streamerUid', rr.streamer_uid))
         from public.e10_inventory_reservations rr
         where rr.item_id = it.id and rr.status = 'active'), '[]'::jsonb))
  end
  from public.e10_inventory_items it where it.id = p_id;
$$;
revoke all on function public._e10_inv_item_json(text) from public, anon, authenticated;

-- Helper B: write the blob's inventory section for one item (add/replace, or remove) and bump rev.
-- Locks the shared workspace row. Called only from the RPCs (owner). Returns the new rev.
create or replace function public._e10_inv_blob_write(p_id text, p_remove boolean, p_actor text)
  returns bigint language plpgsql security definer set search_path to 'public' as $$
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
$$;
revoke all on function public._e10_inv_blob_write(text, boolean, text) from public, anon, authenticated;

-- Helper C: shared preamble result carrier is inlined per-RPC (plpgsql has no easy shared block).
-- Each RPC calls _e10_inv_guard() to enforce membership + capability (mirrors the emit gates).
create or replace function public._e10_inv_guard()
  returns void language plpgsql security definer set search_path to 'public' as $$
begin
  if not (select public.e10_is_member()) then
    raise exception 'inventory RPC: caller is not a member' using errcode = '42501';
  end if;
  if not (select public.e10_has_cap('act.inventory_edit')) then
    raise exception 'inventory RPC: missing capability act.inventory_edit' using errcode = '42501';
  end if;
end;
$$;
revoke all on function public._e10_inv_guard() from public, anon, authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. add_item — create a new item (row + blob) and an intake movement (if qty>0).
create or replace function public.e10_inv_add_item(p_item jsonb, p_idempotency_key text)
  returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_actor text := auth.jwt()->>'email'; v_id text := p_item->>'id';
        v_qty numeric := nullif(p_item->>'qty','')::numeric; v_mid uuid; v_rev bigint;
begin
  perform public._e10_inv_guard();
  if v_id is null or btrim(v_id) = '' then return jsonb_build_object('ok',false,'msg','item id required'); end if;
  -- replay
  if p_idempotency_key is not null and btrim(p_idempotency_key) <> '' then
    select id into v_mid from public.e10_inventory_movements where idempotency_key = p_idempotency_key;
    if found then
      return jsonb_build_object('ok',true,'msg','replay','item',public._e10_inv_item_json(v_id),
        'rev',(select rev from public.e10_workspace where id='shared'),'movement_id',v_mid);
    end if;
  end if;
  if exists (select 1 from public.e10_inventory_items where id = v_id) then
    return jsonb_build_object('ok',false,'msg','item already exists');
  end if;
  v_qty := coalesce(v_qty, 0);
  insert into public.e10_inventory_items (
    id,name,cat,card_set,set_id,cond,year,parallel,card_number,rarity,grade,grading_company,img,
    qty,cost,value,per_box_cost,boxes_per_case,sold_qty,sold_proceeds,sold_at,card_id,player_id,
    owner,added_at,seed,updated_by,updated_at)
  values (
    v_id, p_item->>'name', p_item->>'cat', p_item->>'set', p_item->>'setId', p_item->>'cond',
    p_item->>'year', p_item->>'parallel', p_item->>'cardNumber', p_item->>'rarity', p_item->>'grade',
    p_item->>'gradingCompany', p_item->>'img', v_qty, nullif(p_item->>'cost','')::numeric,
    nullif(p_item->>'value','')::numeric, nullif(p_item->>'perBoxCost','')::numeric,
    nullif(p_item->>'boxesPerCase','')::numeric, nullif(p_item->>'soldQty','')::numeric,
    nullif(p_item->>'soldProceeds','')::numeric, nullif(p_item->>'soldAt','')::numeric,
    p_item->>'cardId', p_item->>'playerId', coalesce(p_item->>'owner', v_actor),
    coalesce(nullif(p_item->>'addedAt','')::numeric, (extract(epoch from now())*1000)::numeric),
    (p_item->>'seed')::boolean, auth.uid(), now());
  v_rev := public._e10_inv_blob_write(v_id, false, v_actor);
  v_mid := public.e10_emit_inventory_movement(v_id, 'intake', v_qty, 0, p_idempotency_key,
             'add', 'new item', 'inventory', v_id, 'add_item', null, '{}'::jsonb);
  return jsonb_build_object('ok',true,'msg','added','item',public._e10_inv_item_json(v_id),'rev',v_rev,'movement_id',v_mid);
end;
$$;

-- 2. edit_item — patch display/economic fields; emit an adjustment movement only if qty changed.
create or replace function public.e10_inv_edit_item(p_id text, p_patch jsonb, p_idempotency_key text)
  returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_actor text := auth.jwt()->>'email'; v_old numeric; v_new numeric; v_d numeric;
        v_mid uuid; v_rev bigint; v_item public.e10_inventory_items;
begin
  perform public._e10_inv_guard();
  select * into v_item from public.e10_inventory_items where id = p_id for update;
  if not found then return jsonb_build_object('ok',false,'msg','item not found'); end if;
  if p_idempotency_key is not null and btrim(p_idempotency_key) <> '' then
    select id into v_mid from public.e10_inventory_movements where idempotency_key = p_idempotency_key;
    if found then
      return jsonb_build_object('ok',true,'msg','replay','item',public._e10_inv_item_json(p_id),
        'rev',(select rev from public.e10_workspace where id='shared'),'movement_id',v_mid);
    end if;
  end if;
  v_old := coalesce(v_item.qty, 0);
  update public.e10_inventory_items set
    name            = case when p_patch ? 'name' then p_patch->>'name' else name end,
    cat             = case when p_patch ? 'cat' then p_patch->>'cat' else cat end,
    card_set        = case when p_patch ? 'set' then p_patch->>'set' else card_set end,
    set_id          = case when p_patch ? 'setId' then p_patch->>'setId' else set_id end,
    cond            = case when p_patch ? 'cond' then p_patch->>'cond' else cond end,
    year            = case when p_patch ? 'year' then p_patch->>'year' else year end,
    parallel        = case when p_patch ? 'parallel' then p_patch->>'parallel' else parallel end,
    card_number     = case when p_patch ? 'cardNumber' then p_patch->>'cardNumber' else card_number end,
    rarity          = case when p_patch ? 'rarity' then p_patch->>'rarity' else rarity end,
    grade           = case when p_patch ? 'grade' then p_patch->>'grade' else grade end,
    grading_company = case when p_patch ? 'gradingCompany' then p_patch->>'gradingCompany' else grading_company end,
    img             = case when p_patch ? 'img' then p_patch->>'img' else img end,
    qty             = case when p_patch ? 'qty' then nullif(p_patch->>'qty','')::numeric else qty end,
    cost            = case when p_patch ? 'cost' then nullif(p_patch->>'cost','')::numeric else cost end,
    value           = case when p_patch ? 'value' then nullif(p_patch->>'value','')::numeric else value end,
    per_box_cost    = case when p_patch ? 'perBoxCost' then nullif(p_patch->>'perBoxCost','')::numeric else per_box_cost end,
    boxes_per_case  = case when p_patch ? 'boxesPerCase' then nullif(p_patch->>'boxesPerCase','')::numeric else boxes_per_case end,
    card_id         = case when p_patch ? 'cardId' then p_patch->>'cardId' else card_id end,
    player_id       = case when p_patch ? 'playerId' then p_patch->>'playerId' else player_id end,
    owner           = case when p_patch ? 'owner' then p_patch->>'owner' else owner end,
    updated_by = auth.uid(), updated_at = now()
  where id = p_id;
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
  return jsonb_build_object('ok',true,'msg','saved','item',public._e10_inv_item_json(p_id),'rev',v_rev,'movement_id',v_mid);
end;
$$;

-- 3. delete_item — remove the item; a single 'correction' movement zeroes remaining on_hand+reserved
--    so the ledger reconciles. Emitted while the item is still in the blob (owner_ref resolves).
create or replace function public.e10_inv_delete_item(p_id text, p_idempotency_key text)
  returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_actor text := auth.jwt()->>'email'; v_qty numeric; v_res numeric; v_mid uuid; v_rev bigint;
begin
  perform public._e10_inv_guard();
  select qty into v_qty from public.e10_inventory_items where id = p_id for update;
  if not found then return jsonb_build_object('ok',false,'msg','item not found'); end if;
  if p_idempotency_key is not null and btrim(p_idempotency_key) <> '' then
    select id into v_mid from public.e10_inventory_movements where idempotency_key = p_idempotency_key;
    if found then
      return jsonb_build_object('ok',true,'msg','replay','item',null,
        'rev',(select rev from public.e10_workspace where id='shared'),'movement_id',v_mid);
    end if;
  end if;
  v_qty := coalesce(v_qty, 0);
  select coalesce(sum(qty),0) into v_res from public.e10_inventory_reservations
    where item_id = p_id and status = 'active';
  if v_qty <> 0 or v_res <> 0 then
    v_mid := public.e10_emit_inventory_movement(p_id, 'correction', -v_qty, -v_res, p_idempotency_key,
               'item_deleted', 'item removed from inventory', 'inventory', p_id, 'delete_item', null, '{}'::jsonb);
  end if;
  delete from public.e10_inventory_items where id = p_id;  -- cascades reservations
  v_rev := public._e10_inv_blob_write(p_id, true, v_actor);
  return jsonb_build_object('ok',true,'msg','deleted','item',null,'rev',v_rev,'movement_id',v_mid);
end;
$$;

-- 4. reserve — hard-lock units to a show. available = qty − Σ active reserved; non-admin cannot exceed.
create or replace function public.e10_inv_reserve(p_id text, p_show_ref text, p_show_label text,
    p_qty numeric, p_idempotency_key text)
  returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_actor text := auth.jwt()->>'email'; v_qty numeric; v_res numeric; v_avail numeric;
        v_mid uuid; v_rev bigint;
begin
  perform public._e10_inv_guard();
  select qty into v_qty from public.e10_inventory_items where id = p_id for update;
  if not found then return jsonb_build_object('ok',false,'msg','item not found'); end if;
  if p_idempotency_key is not null and btrim(p_idempotency_key) <> '' then
    select id into v_mid from public.e10_inventory_movements where idempotency_key = p_idempotency_key;
    if found then
      return jsonb_build_object('ok',true,'msg','replay','item',public._e10_inv_item_json(p_id),
        'rev',(select rev from public.e10_workspace where id='shared'),'movement_id',v_mid);
    end if;
  end if;
  if p_qty is null or p_qty <= 0 then return jsonb_build_object('ok',false,'msg','reserve qty must be positive'); end if;
  select coalesce(sum(qty),0) into v_res from public.e10_inventory_reservations where item_id = p_id and status = 'active';
  v_avail := coalesce(v_qty,0) - v_res;
  if p_qty > v_avail and not (select public.e10_is_admin()) then
    return jsonb_build_object('ok',false,'msg','only '||v_avail||' available');
  end if;
  insert into public.e10_inventory_reservations (item_id, show_ref, show_label, streamer_uid, qty, status, created_by)
    values (p_id, p_show_ref, p_show_label, auth.uid()::text, p_qty, 'active', auth.uid());
  v_rev := public._e10_inv_blob_write(p_id, false, v_actor);
  v_mid := public.e10_emit_inventory_movement(p_id, 'reservation', 0, p_qty, p_idempotency_key,
             'reserve', 'reserved to show', 'show', p_show_ref, 'reserve', null, '{}'::jsonb);
  return jsonb_build_object('ok',true,'msg','reserved','item',public._e10_inv_item_json(p_id),'rev',v_rev,'movement_id',v_mid);
end;
$$;

-- 5. release — release the active reservation(s) for (item, show); reserved_delta only.
create or replace function public.e10_inv_release(p_id text, p_show_ref text, p_idempotency_key text)
  returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_actor text := auth.jwt()->>'email'; v_rel numeric; v_mid uuid; v_rev bigint;
begin
  perform public._e10_inv_guard();
  perform 1 from public.e10_inventory_items where id = p_id for update;
  if not found then return jsonb_build_object('ok',false,'msg','item not found'); end if;
  if p_idempotency_key is not null and btrim(p_idempotency_key) <> '' then
    select id into v_mid from public.e10_inventory_movements where idempotency_key = p_idempotency_key;
    if found then
      return jsonb_build_object('ok',true,'msg','replay','item',public._e10_inv_item_json(p_id),
        'rev',(select rev from public.e10_workspace where id='shared'),'movement_id',v_mid);
    end if;
  end if;
  select coalesce(sum(qty),0) into v_rel from public.e10_inventory_reservations
    where item_id = p_id and show_ref is not distinct from p_show_ref and status = 'active';
  if v_rel = 0 then return jsonb_build_object('ok',false,'msg','no active reservation for that show'); end if;
  update public.e10_inventory_reservations set status = 'released'
    where item_id = p_id and show_ref is not distinct from p_show_ref and status = 'active';
  v_rev := public._e10_inv_blob_write(p_id, false, v_actor);
  v_mid := public.e10_emit_inventory_movement(p_id, 'reservation_release', 0, -v_rel, p_idempotency_key,
             'release', 'reservation released', 'show', p_show_ref, 'release', null, '{}'::jsonb);
  return jsonb_build_object('ok',true,'msg','released','item',public._e10_inv_item_json(p_id),'rev',v_rev,'movement_id',v_mid);
end;
$$;

-- 6. mark_sold — sell from available; non-admin capped to available, admin may oversell.
create or replace function public.e10_inv_mark_sold(p_id text, p_qty numeric, p_proceeds numeric, p_idempotency_key text)
  returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_actor text := auth.jwt()->>'email'; v_qty numeric; v_res numeric; v_avail numeric;
        v_mid uuid; v_rev bigint;
begin
  perform public._e10_inv_guard();
  select qty into v_qty from public.e10_inventory_items where id = p_id for update;
  if not found then return jsonb_build_object('ok',false,'msg','item not found'); end if;
  if p_idempotency_key is not null and btrim(p_idempotency_key) <> '' then
    select id into v_mid from public.e10_inventory_movements where idempotency_key = p_idempotency_key;
    if found then
      return jsonb_build_object('ok',true,'msg','replay','item',public._e10_inv_item_json(p_id),
        'rev',(select rev from public.e10_workspace where id='shared'),'movement_id',v_mid);
    end if;
  end if;
  if p_qty is null or p_qty <= 0 then return jsonb_build_object('ok',false,'msg','sell qty must be positive'); end if;
  select coalesce(sum(qty),0) into v_res from public.e10_inventory_reservations where item_id = p_id and status = 'active';
  v_avail := coalesce(v_qty,0) - v_res;
  if p_qty > v_avail and not (select public.e10_is_admin()) then
    return jsonb_build_object('ok',false,'msg','only '||v_avail||' available');
  end if;
  update public.e10_inventory_items set
    qty = coalesce(qty,0) - p_qty,
    sold_qty = coalesce(sold_qty,0) + p_qty,
    sold_proceeds = coalesce(sold_proceeds,0) + coalesce(p_proceeds,0),
    sold_at = (extract(epoch from now())*1000)::numeric,
    updated_by = auth.uid(), updated_at = now()
  where id = p_id;
  v_rev := public._e10_inv_blob_write(p_id, false, v_actor);
  v_mid := public.e10_emit_inventory_movement(p_id, 'sale', -p_qty, 0, p_idempotency_key,
             'sale', 'marked sold', 'inventory', p_id, 'mark_sold', null,
             jsonb_build_object('proceeds', coalesce(p_proceeds,0)));
  return jsonb_build_object('ok',true,'msg','sold','item',public._e10_inv_item_json(p_id),'rev',v_rev,'movement_id',v_mid);
end;
$$;

-- 7. consume — break consumption: decrement on_hand (and optionally reserved), stamp the session.
create or replace function public.e10_inv_consume(p_id text, p_session_ref text, p_qty numeric,
    p_reserved_qty numeric, p_idempotency_key text)
  returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_actor text := auth.jwt()->>'email'; v_rq numeric := coalesce(p_reserved_qty,0);
        v_mid uuid; v_rev bigint;
begin
  perform public._e10_inv_guard();
  perform 1 from public.e10_inventory_items where id = p_id for update;
  if not found then return jsonb_build_object('ok',false,'msg','item not found'); end if;
  if p_idempotency_key is not null and btrim(p_idempotency_key) <> '' then
    select id into v_mid from public.e10_inventory_movements where idempotency_key = p_idempotency_key;
    if found then
      return jsonb_build_object('ok',true,'msg','replay','item',public._e10_inv_item_json(p_id),
        'rev',(select rev from public.e10_workspace where id='shared'),'movement_id',v_mid);
    end if;
  end if;
  if p_qty is null or p_qty <= 0 then return jsonb_build_object('ok',false,'msg','consume qty must be positive'); end if;
  update public.e10_inventory_items set qty = coalesce(qty,0) - p_qty, updated_by = v_actor, updated_at = now()
    where id = p_id;
  if v_rq > 0 then
    -- draw down reserved for this session's reservation(s) if present
    update public.e10_inventory_reservations set status = 'released'
      where item_id = p_id and show_ref is not distinct from p_session_ref and status = 'active';
  end if;
  v_rev := public._e10_inv_blob_write(p_id, false, v_actor);
  v_mid := public.e10_emit_inventory_movement(p_id, 'break_consumption', -p_qty, -v_rq, p_idempotency_key,
             'break', 'consumed by break', 'break_session', p_session_ref, 'consume', null, '{}'::jsonb);
  return jsonb_build_object('ok',true,'msg','consumed','item',public._e10_inv_item_json(p_id),'rev',v_rev,'movement_id',v_mid);
end;
$$;

-- 8. reverse_consumption — restore stock a break consumed; emit references the consumption movement.
--    The emit reversal guard (exists / not opening / at-most-once) is enforced; a double-reversal is
--    caught and returned as ok:false with the whole transaction rolled back.
create or replace function public.e10_inv_reverse_consumption(p_id text, p_session_ref text, p_qty numeric,
    p_reserved_qty numeric, p_reverses_movement_id uuid, p_idempotency_key text)
  returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_actor text := auth.jwt()->>'email'; v_rq numeric := coalesce(p_reserved_qty,0);
        v_mid uuid; v_rev bigint;
begin
  perform public._e10_inv_guard();
  perform 1 from public.e10_inventory_items where id = p_id for update;
  if not found then return jsonb_build_object('ok',false,'msg','item not found'); end if;
  if p_idempotency_key is not null and btrim(p_idempotency_key) <> '' then
    select id into v_mid from public.e10_inventory_movements where idempotency_key = p_idempotency_key;
    if found then
      return jsonb_build_object('ok',true,'msg','replay','item',public._e10_inv_item_json(p_id),
        'rev',(select rev from public.e10_workspace where id='shared'),'movement_id',v_mid);
    end if;
  end if;
  if p_qty is null or p_qty <= 0 then return jsonb_build_object('ok',false,'msg','reverse qty must be positive'); end if;
  begin
    update public.e10_inventory_items set qty = coalesce(qty,0) + p_qty, updated_by = v_actor, updated_at = now()
      where id = p_id;
    v_rev := public._e10_inv_blob_write(p_id, false, v_actor);
    v_mid := public.e10_emit_inventory_movement(p_id, 'break_reversal', p_qty, v_rq, p_idempotency_key,
               'break', 'break consumption reversed', 'break_session', p_session_ref, 'reverse',
               p_reverses_movement_id, '{}'::jsonb);
  exception when others then
    return jsonb_build_object('ok',false,'msg','reversal rejected: '||sqlerrm);
  end;
  return jsonb_build_object('ok',true,'msg','reversed','item',public._e10_inv_item_json(p_id),'rev',v_rev,'movement_id',v_mid);
end;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Execution grants: members call the RPCs; anon cannot. (The functions re-check membership internally.)
do $$
declare fn text;
begin
  foreach fn in array array[
    'e10_inv_add_item(jsonb,text)', 'e10_inv_edit_item(text,jsonb,text)', 'e10_inv_delete_item(text,text)',
    'e10_inv_reserve(text,text,text,numeric,text)', 'e10_inv_release(text,text,text)',
    'e10_inv_mark_sold(text,numeric,numeric,text)', 'e10_inv_consume(text,text,numeric,numeric,text)',
    'e10_inv_reverse_consumption(text,text,numeric,numeric,uuid,text)'
  ] loop
    execute format('revoke all on function public.%s from public, anon', fn);
    execute format('grant execute on function public.%s to authenticated', fn);
  end loop;
end $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Retire the client emit path: emission is now exclusively internal to the RPCs above. Members can no
-- longer INSERT the ledger directly. imov_sel (member read) stays; still NO update/delete policy.
drop policy if exists imov_ins on public.e10_inventory_movements;
