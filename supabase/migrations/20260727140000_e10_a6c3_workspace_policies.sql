-- Element 10 — A6c.3 workspace policy family + byte-exact A6c.0 re-align.
-- Part 1 rewrites the 4 deferred e10_workspace RLS policies (census rows 94-97) from legacy org-blind predicates
-- (e10_is_member/e10_has_cap/e10_is_admin/e10_is_org) to org-scoped e10.* predicates, mirroring the A6c.1 standing:
-- USING carries the org-scoped access predicate; every WITH CHECK additionally pins organization_id = e10.current_org().
-- The global PRIMARY KEY(id) is intentionally retained until CONTRACT, so exactly one 'shared' row (org0) exists during
-- A6c and an org-B 'shared' INSERT fails the global PK (proved in the gate). Part 2 re-applies the byte-exact committed
-- A6c.0 bodies of the 8 objects whose staging definitions cosmetically diverged from the committed file (A6c.2.1 identity
-- sweep) — semantically identical (7 whitespace-only + redeem_code's dropped comment), re-aligned so staging and a clean
-- replay are byte-identical everywhere per the standing rule. Locally these CREATE OR REPLACE statements are no-ops
-- (the bodies already match the A6c.0 file). No delegate authority changes; the 55 A6c.1 policies are untouched.

-- =====================================================================================================================
-- PART 1 — the 4 e10_workspace policies (rows 94-97) org-scoped
-- =====================================================================================================================

-- 94 | ws_ins | INSERT | public
drop policy if exists ws_ins on public.e10_workspace;
create policy ws_ins on public.e10_workspace for insert to public
  with check (
    (
      ((e10_workspace.id = 'shared') AND e10.is_org_member(e10_workspace.organization_id) AND e10.has_org_cap(e10_workspace.organization_id,'act.inventory_edit'))
      OR ((e10_workspace.id = 'universal') AND e10.is_org_admin(e10_workspace.organization_id))
      OR (e10_workspace.owner = auth.uid())
      OR e10.is_org_admin(e10_workspace.organization_id)
    )
    AND (e10_workspace.organization_id = e10.current_org())
  );

-- 95 | ws_del | DELETE | authenticated
drop policy if exists ws_del on public.e10_workspace;
create policy ws_del on public.e10_workspace for delete to authenticated
  using ((e10_workspace.owner = auth.uid()) OR e10.is_org_admin(e10_workspace.organization_id));

-- 96 | ws_sel | SELECT | public
drop policy if exists ws_sel on public.e10_workspace;
create policy ws_sel on public.e10_workspace for select to public
  using (
    ((e10_workspace.id = ANY (ARRAY['shared'::text,'universal'::text])) AND e10.is_org_member(e10_workspace.organization_id))
    OR (e10_workspace.owner = auth.uid())
    OR e10.is_org_admin(e10_workspace.organization_id)
  );

-- 97 | ws_upd | UPDATE | public
drop policy if exists ws_upd on public.e10_workspace;
create policy ws_upd on public.e10_workspace for update to public
  using (
    ((e10_workspace.id = 'shared') AND e10.is_org_member(e10_workspace.organization_id) AND e10.has_org_cap(e10_workspace.organization_id,'act.inventory_edit'))
    OR ((e10_workspace.id = 'universal') AND e10.is_org_admin(e10_workspace.organization_id))
    OR (e10_workspace.owner = auth.uid())
    OR e10.is_org_admin(e10_workspace.organization_id)
  )
  with check (
    (
      ((e10_workspace.id = 'shared') AND e10.is_org_member(e10_workspace.organization_id) AND e10.has_org_cap(e10_workspace.organization_id,'act.inventory_edit'))
      OR ((e10_workspace.id = 'universal') AND e10.is_org_admin(e10_workspace.organization_id))
      OR (e10_workspace.owner = auth.uid())
      OR e10.is_org_admin(e10_workspace.organization_id)
    )
    AND (e10_workspace.organization_id = e10.current_org())
  );

-- =====================================================================================================================
-- PART 2 — byte-exact re-align of the 8 A6c.0 objects (verbatim committed bodies from 20260720120000_e10_a6c0_prereqs.sql)
-- =====================================================================================================================

create or replace function public._e10_inv_guard(p_org uuid) returns void
  language plpgsql security definer set search_path to 'public' as $fn$
begin
  if not e10.is_org_member(p_org) then
    raise exception 'inventory RPC: caller is not a member of organization %', p_org using errcode = '42501';
  end if;
  if not e10.has_org_cap(p_org, 'act.inventory_edit') then
    raise exception 'inventory RPC: missing capability act.inventory_edit in organization %', p_org using errcode = '42501';
  end if;
end; $fn$;

create or replace function public._e10_inv_item_json(p_org uuid, p_id text) returns jsonb
  language sql stable security definer set search_path to 'public' as $fn$
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
           where rr.item_id = it.id and rr.status = 'active' and rr.organization_id = p_org), '[]'::jsonb)) )
  end
  from public.e10_inventory_items it where it.id = p_id and it.organization_id = p_org;
$fn$;

create or replace function public._e10_inv_receipt_check(p_org uuid, p_key text, p_rpc text, p_item_id text, p_fp text) returns jsonb
  language plpgsql security definer set search_path to 'public' as $fn$
declare v public.e10_mutation_receipts;
begin
  select * into v from public.e10_mutation_receipts where idempotency_key = p_key and organization_id = p_org;
  if not found then return null; end if;
  if v.rpc is distinct from p_rpc or v.item_id is distinct from p_item_id
     or v.actor_uid is distinct from auth.uid() or v.input_fingerprint is distinct from p_fp then
    return jsonb_build_object('_mismatch', true);
  end if;
  return jsonb_build_object('replay', true, 'movement_id', v.movement_id, 'idempotency_key', v.idempotency_key);
end; $fn$;

create or replace function public.e10_org_emit_inventory_movement(
  p_org uuid, p_item_id text, p_movement_type text, p_on_hand_delta numeric DEFAULT 0, p_reserved_delta numeric DEFAULT 0,
  p_idempotency_key text DEFAULT NULL, p_reason_code text DEFAULT NULL, p_note text DEFAULT NULL,
  p_source_entity_type text DEFAULT NULL, p_source_entity_id text DEFAULT NULL, p_source_action text DEFAULT NULL,
  p_reverses_movement_id uuid DEFAULT NULL, p_meta jsonb DEFAULT '{}'::jsonb) returns uuid
  language plpgsql security definer set search_path to 'public' as $fn$
declare v_oh numeric := coalesce(p_on_hand_delta,0); v_rd numeric := coalesce(p_reserved_delta,0);
        v_existing uuid; v_owner text; v_new uuid; v_rev record;
begin
  if not e10.is_org_member(p_org) then raise exception 'e10_org_emit_inventory_movement: not a member of %', p_org using errcode='42501'; end if;
  if not e10.has_org_cap(p_org,'act.inventory_edit') then raise exception 'e10_org_emit_inventory_movement: missing act.inventory_edit' using errcode='42501'; end if;
  if p_idempotency_key is null or btrim(p_idempotency_key)='' then raise exception 'idempotency_key is required' using errcode='22004'; end if;
  select id into v_existing from public.e10_inventory_movements where idempotency_key=p_idempotency_key and organization_id=p_org;
  if found then return v_existing; end if;
  if p_item_id is null or btrim(p_item_id)='' then raise exception 'p_item_id is required' using errcode='22004'; end if;
  if p_movement_type='opening_balance' then raise exception 'opening_balance is migration-only' using errcode='22023'; end if;
  if p_movement_type is null or p_movement_type not in ('intake','manual_increase','manual_decrease','correction','reservation','reservation_release','break_consumption','break_reversal','sale','return','transfer','loss_damage') then
    raise exception 'invalid movement_type %', coalesce(p_movement_type,'<null>') using errcode='22023'; end if;
  if v_oh=0 and v_rd=0 then return null; end if;
  case p_movement_type
    when 'intake' then if not (v_oh>0 and v_rd=0) then raise exception 'intake requires on_hand_delta>0 and reserved_delta=0' using errcode='22023'; end if;
    when 'manual_increase' then if not (v_oh>0 and v_rd=0) then raise exception 'manual_increase requires on_hand_delta>0 and reserved_delta=0' using errcode='22023'; end if;
    when 'return' then if not (v_oh>0 and v_rd=0) then raise exception 'return requires on_hand_delta>0 and reserved_delta=0' using errcode='22023'; end if;
    when 'manual_decrease' then if not (v_oh<0 and v_rd=0) then raise exception 'manual_decrease requires on_hand_delta<0 and reserved_delta=0' using errcode='22023'; end if;
    when 'sale' then if not (v_oh<0 and v_rd<=0) then raise exception 'sale requires on_hand_delta<0 and reserved_delta<=0' using errcode='22023'; end if;
    when 'loss_damage' then if not (v_oh<0 and v_rd<=0) then raise exception 'loss_damage requires on_hand_delta<0 and reserved_delta<=0' using errcode='22023'; end if;
    when 'break_consumption' then if not (v_oh<0 and v_rd<=0) then raise exception 'break_consumption requires on_hand_delta<0 and reserved_delta<=0' using errcode='22023'; end if;
    when 'reservation' then if not (v_oh=0 and v_rd>0) then raise exception 'reservation requires on_hand_delta=0 and reserved_delta>0' using errcode='22023'; end if;
    when 'reservation_release' then if not (v_oh=0 and v_rd<0) then raise exception 'reservation_release requires on_hand_delta=0 and reserved_delta<0' using errcode='22023'; end if;
    when 'break_reversal' then
      if p_reverses_movement_id is null then raise exception 'break_reversal requires reverses_movement_id' using errcode='22023'; end if;
      if not (v_oh>0 and v_rd>=0) then raise exception 'break_reversal requires on_hand_delta>0 and reserved_delta>=0' using errcode='22023'; end if;
    else null;
  end case;
  if p_reverses_movement_id is not null then
    select id, workspace_id, movement_type into v_rev from public.e10_inventory_movements where id=p_reverses_movement_id and organization_id=p_org;
    if not found then raise exception 'reverses_movement_id % does not exist in organization', p_reverses_movement_id using errcode='23503'; end if;
    if v_rev.movement_type='opening_balance' then raise exception 'an opening_balance cannot be reversed' using errcode='22023'; end if;
    if exists (select 1 from public.e10_inventory_movements where reverses_movement_id=p_reverses_movement_id and organization_id=p_org) then
      raise exception 'movement % has already been reversed', p_reverses_movement_id using errcode='23505'; end if;
  end if;
  select (i->>'owner') into v_owner from public.e10_workspace w, lateral jsonb_array_elements(w.data->'inventory') i
    where w.id='shared' and w.organization_id=p_org and i->>'id'=p_item_id limit 1;
  perform set_config('e10.emit','on',true);
  insert into public.e10_inventory_movements (workspace_id,item_id,owner_ref,movement_type,on_hand_delta,reserved_delta,cost_basis,
    source_entity_type,source_entity_id,source_action,actor_uid,reason_code,note,idempotency_key,reverses_movement_id,migration_version,meta,organization_id)
  values ('shared',p_item_id,v_owner,p_movement_type,v_oh,v_rd,null,p_source_entity_type,p_source_entity_id,p_source_action,
    auth.uid(),p_reason_code,p_note,p_idempotency_key,p_reverses_movement_id,null,coalesce(p_meta,'{}'::jsonb),p_org)
  on conflict (idempotency_key) do nothing returning id into v_new;
  if v_new is null then select id into v_new from public.e10_inventory_movements where idempotency_key=p_idempotency_key and organization_id=p_org; end if;
  return v_new;
end; $fn$;

create or replace function public._e10_inv_clamp_res(p_org uuid, p_id text, p_key text) returns void
  language plpgsql security definer set search_path to 'public' as $fn$
declare v_qty numeric; v_res numeric; v_excess numeric; v_cut numeric; r record; v_trimmed numeric := 0;
begin
  select coalesce(qty,0) into v_qty from public.e10_inventory_items where id=p_id and organization_id=p_org;
  select coalesce(sum(qty),0) into v_res from public.e10_inventory_reservations where item_id=p_id and status='active' and organization_id=p_org;
  v_excess := v_res - greatest(v_qty,0);
  if v_excess<=0 then return; end if;
  for r in select id,qty from public.e10_inventory_reservations where item_id=p_id and status='active' and organization_id=p_org order by created_at desc loop
    exit when v_excess<=0;
    v_cut := least(r.qty,v_excess);
    if v_cut>=r.qty then update public.e10_inventory_reservations set status='released' where id=r.id;
    else update public.e10_inventory_reservations set qty=qty-v_cut where id=r.id; end if;
    v_excess := v_excess-v_cut; v_trimmed := v_trimmed+v_cut;
  end loop;
  if v_trimmed>0 then
    perform public.e10_org_emit_inventory_movement(p_org, p_id, 'reservation_release', 0, -v_trimmed,
      coalesce(p_key,'auto')||':clamp','clamp','reservations trimmed to on-hand','inventory',p_id,'clamp',null,'{}'::jsonb);
  end if;
end; $fn$;

create or replace function public.e10_org_inv_get(p_org uuid, p_id text) returns jsonb
  language plpgsql stable security definer set search_path to 'public' as $fn$
begin
  if not e10.is_org_member(p_org) then raise exception 'cross_org_denied: not a member of organization %', p_org using errcode='42501'; end if;
  return public._e10_inv_item_json(p_org, p_id);
end; $fn$;

create or replace function public.e10_org_inv_list(p_org uuid) returns jsonb
  language plpgsql stable security definer set search_path to 'public' as $fn$
begin
  if not e10.is_org_member(p_org) then raise exception 'cross_org_denied: not a member of organization %', p_org using errcode='42501'; end if;
  return (select coalesce(jsonb_agg(public._e10_inv_item_json(p_org, it.id) order by it.id),'[]'::jsonb)
            from public.e10_inventory_items it where it.organization_id = p_org);
end; $fn$;

create or replace function public.e10_org_redeem_code(p_code text) returns uuid
  language plpgsql security definer set search_path to 'public' as $fn$
declare v_sid uuid; v_org uuid;
begin
  if auth.uid() is null then raise exception 'redeem_code: not authenticated' using errcode='42501'; end if;
  select id, organization_id into v_sid, v_org from public.e10_break_sessions where share_code = p_code;
  if v_sid is null then return null; end if;  -- invalid code: no session, no viewer created (rejected, behavior-preserving)
  insert into public.e10_session_viewers(session_id, user_id, organization_id)
    values (v_sid, auth.uid(), v_org) on conflict (session_id, user_id) do nothing;
  return v_sid;
end; $fn$;
