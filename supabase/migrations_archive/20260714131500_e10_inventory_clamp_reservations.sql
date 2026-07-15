-- Migration: e10_inventory_clamp_reservations  (Chain M — M3 support)
-- Preserve the invClampRes invariant server-side: when a mutation drops on-hand below the reserved
-- total, trim the newest active reservations so reserved never exceeds qty (the gate's HARD check),
-- and record ONE reservation_release movement for the trimmed amount so blob==rows==ledger stay
-- reconciled. Wired into edit_item, mark_sold, and consume (the qty-reducers). ADDITIVE.
create or replace function public._e10_inv_clamp_res(p_id text, p_key text)
  returns void language plpgsql security definer set search_path to 'public' as $$
declare v_qty numeric; v_res numeric; v_excess numeric; v_cut numeric; r record; v_trimmed numeric := 0;
begin
  select coalesce(qty,0) into v_qty from public.e10_inventory_items where id = p_id;
  select coalesce(sum(qty),0) into v_res from public.e10_inventory_reservations where item_id = p_id and status = 'active';
  v_excess := v_res - greatest(v_qty, 0);
  if v_excess <= 0 then return; end if;
  for r in select id, qty from public.e10_inventory_reservations
             where item_id = p_id and status = 'active' order by created_at desc loop
    exit when v_excess <= 0;
    v_cut := least(r.qty, v_excess);
    if v_cut >= r.qty then
      update public.e10_inventory_reservations set status = 'released' where id = r.id;
    else
      update public.e10_inventory_reservations set qty = qty - v_cut where id = r.id;
    end if;
    v_excess := v_excess - v_cut; v_trimmed := v_trimmed + v_cut;
  end loop;
  if v_trimmed > 0 then
    perform public.e10_emit_inventory_movement(p_id, 'reservation_release', 0, -v_trimmed,
      coalesce(p_key,'auto')||':clamp', 'clamp', 'reservations trimmed to on-hand', 'inventory', p_id,
      'clamp', null, '{}'::jsonb);
  end if;
end;
$$;
revoke all on function public._e10_inv_clamp_res(text, text) from public, anon, authenticated;

-- mark_sold: clamp after the qty drop.
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
  perform public._e10_inv_clamp_res(p_id, p_idempotency_key);
  v_rev := public._e10_inv_blob_write(p_id, false, v_actor);
  v_mid := public.e10_emit_inventory_movement(p_id, 'sale', -p_qty, 0, p_idempotency_key,
             'sale', 'marked sold', 'inventory', p_id, 'mark_sold', null,
             jsonb_build_object('proceeds', coalesce(p_proceeds,0)));
  return jsonb_build_object('ok',true,'msg','sold','item',public._e10_inv_item_json(p_id),'rev',v_rev,'movement_id',v_mid);
end;
$$;

-- consume: clamp after the qty drop (and after any session-reservation release).
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
  update public.e10_inventory_items set qty = coalesce(qty,0) - p_qty, updated_by = auth.uid(), updated_at = now()
    where id = p_id;
  if v_rq > 0 then
    update public.e10_inventory_reservations set status = 'released'
      where item_id = p_id and show_ref is not distinct from p_session_ref and status = 'active';
  end if;
  perform public._e10_inv_clamp_res(p_id, p_idempotency_key);
  v_rev := public._e10_inv_blob_write(p_id, false, v_actor);
  v_mid := public.e10_emit_inventory_movement(p_id, 'break_consumption', -p_qty, -v_rq, p_idempotency_key,
             'break', 'consumed by break', 'break_session', p_session_ref, 'consume', null, '{}'::jsonb);
  return jsonb_build_object('ok',true,'msg','consumed','item',public._e10_inv_item_json(p_id),'rev',v_rev,'movement_id',v_mid);
end;
$$;

-- edit_item: extra passthrough (from the prior migration) + clamp after the qty change.
create or replace function public.e10_inv_edit_item(p_id text, p_patch jsonb, p_idempotency_key text)
  returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_actor text := auth.jwt()->>'email'; v_old numeric; v_new numeric; v_d numeric;
        v_mid uuid; v_rev bigint; v_item public.e10_inventory_items; v_pextra jsonb;
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
  v_pextra := p_patch - array['id','name','cat','set','setId','cond','year','parallel','cardNumber',
    'rarity','grade','gradingCompany','img','qty','cost','value','perBoxCost','boxesPerCase','soldQty',
    'soldProceeds','soldAt','cardId','playerId','owner','addedAt','seed','reservations'];
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
    extra           = case when v_pextra = '{}'::jsonb then extra else coalesce(extra,'{}'::jsonb) || v_pextra end,
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
  return jsonb_build_object('ok',true,'msg','saved','item',public._e10_inv_item_json(p_id),'rev',v_rev,'movement_id',v_mid);
end;
$$;
