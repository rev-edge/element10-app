-- Migration: e10_inventory_items_extra_passthrough  (Chain M — M3 support)
-- Discovered during the M3 client cutover: the Pass-2.5 inventory form writes STRUCTURED fields
-- (inventory_type, domain, sport, game, franchise, category_detail, manufacturer, configuration,
-- package_type, product_line, product_year, certification_number, description, item_count,
-- cost_basis_mode, units_per_case, …) that the M1 relational schema has no typed columns for. The 35
-- backfilled items are all unclassified, so M1 lost nothing; but a new/edited classified item would
-- lose those fields on the RPC round-trip. Fix: ONE additive nullable jsonb passthrough column that
-- captures every item key not already mapped to a typed column. ADDITIVE ONLY.
alter table public.e10_inventory_items add column if not exists extra jsonb;

-- The set of item keys that ARE mapped to typed columns (plus id + reservations). Everything else in
-- an item object flows into `extra` verbatim and is merged back out by _e10_inv_item_json.
-- (kept inline in each function below so the definitions stay self-contained)

-- Rebuild the canonical row->blob JSON builder to merge `extra` (structured fields) back in.
create or replace function public._e10_inv_item_json(p_id text)
  returns jsonb language sql security definer set search_path to 'public' stable as $$
  select case when it.id is null then null else
    ( jsonb_strip_nulls(jsonb_build_object(
        'id', it.id, 'name', it.name, 'cat', it.cat, 'set', it.card_set, 'setId', it.set_id,
        'cond', it.cond, 'year', it.year, 'parallel', it.parallel, 'cardNumber', it.card_number,
        'rarity', it.rarity, 'grade', it.grade, 'gradingCompany', it.grading_company, 'img', it.img,
        'qty', it.qty, 'cost', it.cost, 'value', it.value, 'perBoxCost', it.per_box_cost,
        'boxesPerCase', it.boxes_per_case, 'soldQty', it.sold_qty, 'soldProceeds', it.sold_proceeds,
        'soldAt', it.sold_at, 'cardId', it.card_id, 'playerId', it.player_id, 'owner', it.owner,
        'addedAt', it.added_at, 'seed', it.seed))
      || coalesce(it.extra, '{}'::jsonb)
      || jsonb_build_object('reservations', coalesce((
           select jsonb_agg(jsonb_build_object('qty', rr.qty, 'showId', rr.show_ref,
                    'showLabel', rr.show_label, 'streamerUid', rr.streamer_uid))
           from public.e10_inventory_reservations rr
           where rr.item_id = it.id and rr.status = 'active'), '[]'::jsonb)) )
  end
  from public.e10_inventory_items it where it.id = p_id;
$$;

-- add_item: route non-legacy keys into `extra`.
create or replace function public.e10_inv_add_item(p_item jsonb, p_idempotency_key text)
  returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_actor text := auth.jwt()->>'email'; v_id text := p_item->>'id';
        v_qty numeric := nullif(p_item->>'qty','')::numeric; v_mid uuid; v_rev bigint; v_extra jsonb;
begin
  perform public._e10_inv_guard();
  if v_id is null or btrim(v_id) = '' then return jsonb_build_object('ok',false,'msg','item id required'); end if;
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
  return jsonb_build_object('ok',true,'msg','added','item',public._e10_inv_item_json(v_id),'rev',v_rev,'movement_id',v_mid);
end;
$$;

-- edit_item: merge non-legacy patch keys into `extra` (present keys win; absent keys unchanged).
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
