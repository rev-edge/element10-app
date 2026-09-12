-- Foundation Gate A6c.0 (PREREQUISITES) — STAGING/LOCAL only; production read-only. ADDITIVE + idempotent.
-- Authorization: BOARD.md Approvals Ledger row "A6c authorization plan rev 6 | GRANTED | CPI | 2026-07-20 |
-- Element10_A6c_PLAN.md SHA-256 2d1710bfdb0653271960f021c12efacb4c83f1be22067d6e064e6724ed33ce70".
-- Scope: additive predicates + session visibility + the org-aware e10_org_* delegates and _e10_inv_* helpers, created
-- ALONGSIDE the legacy functions and born-locked per plan §5.d. NOTHING is switched over: no wrapper cutover, no policy
-- cutover; existing sessions remain private; legacy RPCs/policies/helpers are untouched. Stops before A6c.1.
-- Function arithmetic (plan §5, docs-only): 14 public inventory RPCs -> 14 delegates; 13 client-callable; the 14th,
-- e10_org_emit_inventory_movement, is internal-only per §5.d; with §5.b's 10 helpers that is the 24-function inventory.
-- The "19 RPC wrappers" figure in the handoff is stale.

-- ================= STAGE 1: predicates + session visibility =================

-- e10.owns_session: write-owner predicate (session streamer OR org-admin). RLS-usable; grant authenticated only.
create or replace function e10.owns_session(sess uuid) returns boolean
  language sql stable security definer set search_path to 'public' as $fn$
    select exists(select 1 from public.e10_break_sessions s
                  where s.id = sess and (s.streamer_uid = auth.uid() or e10.is_org_admin(s.organization_id)));
$fn$;
revoke execute on function e10.owns_session(uuid) from public;
revoke execute on function e10.owns_session(uuid) from anon;
grant execute on function e10.owns_session(uuid) to authenticated;

-- session visibility: A6b never added it. Deliberate backfill leaves existing sessions 'private' (NO silent publish).
alter table public.e10_break_sessions add column if not exists visibility text not null default 'private';
do $$ begin
  if not exists (select 1 from pg_constraint where conname='e10_break_sessions_visibility_chk'
                 and conrelid='public.e10_break_sessions'::regclass) then
    alter table public.e10_break_sessions
      add constraint e10_break_sessions_visibility_chk check (visibility in ('private','published'));
  end if;
end $$;

-- ADR-final published-session spectator predicate (replaces the A6a interim `share_code IS NOT NULL`).
-- CREATE OR REPLACE preserves the existing ACL (postgres + authenticated); global UNIQUE(share_code) is untouched.
create or replace function e10.can_spectate_session(sess uuid) returns boolean
  language sql stable security definer set search_path to 'public' as $fn$
    select auth.uid() is not null
       and exists(select 1 from public.e10_break_sessions s where s.id = sess and s.visibility = 'published');
$fn$;

-- ================= STAGE 2: org-aware helpers + emit (born-locked; service_role only) =================
-- Created ALONGSIDE the legacy zero-org helpers (which remain untouched and in use by the legacy wrappers).
-- Each threads a leading p_org and org-scopes its reads/writes. Grants: revoke PUBLIC/anon/authenticated; service_role.

-- guard(p_org): org-scoped membership + capability
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

-- item_json(p_org, p_id): org-scoped item projection (item + its active reservations, both org-filtered)
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

-- receipt_check(p_org,...): org-scoped idempotency lookup
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

-- receipt_write(p_org,...): org-scoped receipt write
create or replace function public._e10_inv_receipt_write(p_org uuid, p_key text, p_rpc text, p_item_id text, p_fp text, p_mid uuid) returns void
  language sql security definer set search_path to 'public' as $fn$
  insert into public.e10_mutation_receipts (idempotency_key, rpc, item_id, actor_uid, movement_id, input_fingerprint, organization_id)
  values (p_key, p_rpc, p_item_id, auth.uid(), p_mid, p_fp, p_org);
$fn$;

-- NOTE: the legacy public._e10_inv_receipt(...) and public._e10_inv_replay(...) reference a `response` column that no
-- longer exists on e10_mutation_receipts (columns: idempotency_key, rpc, item_id, actor_uid, movement_id,
-- input_fingerprint, created_at, organization_id). They are dead legacy code — the live receipt path is
-- _e10_inv_receipt_check + _e10_inv_receipt_write + _e10_inv_replay_json. A6c.0 does NOT recreate the dead helpers.

-- replay_json(p_org, p_item_id, p_rec): org-scoped replay envelope
create or replace function public._e10_inv_replay_json(p_org uuid, p_item_id text, p_rec jsonb) returns jsonb
  language sql stable security definer set search_path to 'public' as $fn$
  select jsonb_build_object('ok', true, 'replay', true, 'msg', 'replay',
    'item', case when p_item_id is null then null else public._e10_inv_item_json(p_org, p_item_id) end,
    'rev', (select rev from public.e10_workspace where id = 'shared' and organization_id = p_org),
    'movement_id', p_rec->'movement_id', 'idempotency_key', p_rec->'idempotency_key');
$fn$;

-- blob_write(p_org,...): org-scoped shared-workspace rev read-back
create or replace function public._e10_inv_blob_write(p_org uuid, p_id text, p_remove boolean, p_actor text) returns bigint
  language sql security definer set search_path to 'public' as $fn$
  select coalesce((select rev from public.e10_workspace where id = 'shared' and organization_id = p_org), 0::bigint);
$fn$;

-- emit(p_org,...): org-scoped movement writer (org idempotency dedup; explicit organization_id on the row)
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

-- clamp_res(p_org,...): org-scoped reservation clamp (uses the org emit)
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

-- born-locked grants for STAGE 2 (internal-only: revoke PUBLIC/anon/authenticated; service_role only)
do $$ declare f text; begin
  foreach f in array array[
    'public._e10_inv_guard(uuid)','public._e10_inv_item_json(uuid,text)','public._e10_inv_receipt_check(uuid,text,text,text,text)',
    'public._e10_inv_receipt_write(uuid,text,text,text,text,uuid)',
    'public._e10_inv_replay_json(uuid,text,jsonb)','public._e10_inv_blob_write(uuid,text,boolean,text)',
    'public._e10_inv_clamp_res(uuid,text,text)','public.e10_org_emit_inventory_movement(uuid,text,text,numeric,numeric,text,text,text,text,text,text,uuid,jsonb)'
  ] loop
    execute format('revoke execute on function %s from public', f);
    execute format('revoke execute on function %s from anon', f);
    execute format('revoke execute on function %s from authenticated', f);
    execute format('grant execute on function %s to service_role', f);
  end loop;
end $$;

-- ================= STAGE 3: the 13 client delegates (authorized internally; born-locked authenticated+service_role) =================
-- A6c.0 delegates establish the ORG-AUTHORIZATION BOUNDARY over the existing (single-org-correct) legacy mechanics:
--   Member  -> is_org_member(p_org) + has_org_cap(p_org,'act.inventory_edit'); operate in p_org.
--   Entity  -> same guard + derive the item's org and reject a mismatched p_org with cross_org_denied.
--   Viewer/session-owner -> derive org from the session; NEVER call e10.current_org().
-- get/list are FULLY org-scoped here (they must be, since the legacy read path is org-blind and DEFINER bypasses RLS).
-- redeem_code carries its own body (the legacy insert omits organization_id, which is NOT NULL post-Step-5). The other
-- write delegates reuse the proven legacy mechanics for now; the A6c.2 wrapper cutover relocates those mechanics into
-- the delegates (using the Stage-2 org-aware helpers) and makes the legacy signatures thin. NOTHING is switched here.

-- Member: add_item
create or replace function public.e10_org_inv_add_item(p_org uuid, p_item jsonb, p_idempotency_key text) returns jsonb
  language plpgsql security definer set search_path to 'public' as $fn$
begin
  if not e10.is_org_member(p_org) then raise exception 'cross_org_denied: not a member of organization %', p_org using errcode='42501'; end if;
  if not e10.has_org_cap(p_org,'act.inventory_edit') then raise exception 'e10_org_inv_add_item: missing act.inventory_edit' using errcode='42501'; end if;
  return public.e10_inv_add_item(p_item, p_idempotency_key);
end; $fn$;

-- Member: set_reservations
create or replace function public.e10_org_inv_set_reservations(p_org uuid, p_show_ref text, p_show_label text, p_targets jsonb, p_idempotency_key text) returns jsonb
  language plpgsql security definer set search_path to 'public' as $fn$
begin
  if not e10.is_org_member(p_org) then raise exception 'cross_org_denied: not a member of organization %', p_org using errcode='42501'; end if;
  if not e10.has_org_cap(p_org,'act.inventory_edit') then raise exception 'e10_org_inv_set_reservations: missing act.inventory_edit' using errcode='42501'; end if;
  return public.e10_inv_set_reservations(p_show_ref, p_show_label, p_targets, p_idempotency_key);
end; $fn$;

-- Entity delegates: guard(p_org) + derive item.org + reject cross-org, then legacy mechanics
create or replace function public.e10_org_inv_edit_item(p_org uuid, p_id text, p_patch jsonb, p_idempotency_key text, p_remove_keys text[] default null::text[]) returns jsonb
  language plpgsql security definer set search_path to 'public' as $fn$
declare v_item_org uuid;
begin
  if not e10.is_org_member(p_org) then raise exception 'cross_org_denied: not a member of organization %', p_org using errcode='42501'; end if;
  if not e10.has_org_cap(p_org,'act.inventory_edit') then raise exception 'e10_org_inv_edit_item: missing act.inventory_edit' using errcode='42501'; end if;
  select organization_id into v_item_org from public.e10_inventory_items where id=p_id;
  if v_item_org is not null and v_item_org<>p_org then raise exception 'cross_org_denied: item % is in a different organization', p_id using errcode='42501'; end if;
  return public.e10_inv_edit_item(p_id, p_patch, p_idempotency_key, p_remove_keys);
end; $fn$;

create or replace function public.e10_org_inv_delete_item(p_org uuid, p_id text, p_idempotency_key text) returns jsonb
  language plpgsql security definer set search_path to 'public' as $fn$
declare v_item_org uuid;
begin
  if not e10.is_org_member(p_org) then raise exception 'cross_org_denied: not a member of organization %', p_org using errcode='42501'; end if;
  if not e10.has_org_cap(p_org,'act.inventory_edit') then raise exception 'e10_org_inv_delete_item: missing act.inventory_edit' using errcode='42501'; end if;
  select organization_id into v_item_org from public.e10_inventory_items where id=p_id;
  if v_item_org is not null and v_item_org<>p_org then raise exception 'cross_org_denied: item % is in a different organization', p_id using errcode='42501'; end if;
  return public.e10_inv_delete_item(p_id, p_idempotency_key);
end; $fn$;

create or replace function public.e10_org_inv_reserve(p_org uuid, p_id text, p_show_ref text, p_show_label text, p_qty numeric, p_idempotency_key text) returns jsonb
  language plpgsql security definer set search_path to 'public' as $fn$
declare v_item_org uuid;
begin
  if not e10.is_org_member(p_org) then raise exception 'cross_org_denied: not a member of organization %', p_org using errcode='42501'; end if;
  if not e10.has_org_cap(p_org,'act.inventory_edit') then raise exception 'e10_org_inv_reserve: missing act.inventory_edit' using errcode='42501'; end if;
  select organization_id into v_item_org from public.e10_inventory_items where id=p_id;
  if v_item_org is not null and v_item_org<>p_org then raise exception 'cross_org_denied: item % is in a different organization', p_id using errcode='42501'; end if;
  return public.e10_inv_reserve(p_id, p_show_ref, p_show_label, p_qty, p_idempotency_key);
end; $fn$;

create or replace function public.e10_org_inv_release(p_org uuid, p_id text, p_show_ref text, p_idempotency_key text) returns jsonb
  language plpgsql security definer set search_path to 'public' as $fn$
declare v_item_org uuid;
begin
  if not e10.is_org_member(p_org) then raise exception 'cross_org_denied: not a member of organization %', p_org using errcode='42501'; end if;
  if not e10.has_org_cap(p_org,'act.inventory_edit') then raise exception 'e10_org_inv_release: missing act.inventory_edit' using errcode='42501'; end if;
  select organization_id into v_item_org from public.e10_inventory_items where id=p_id;
  if v_item_org is not null and v_item_org<>p_org then raise exception 'cross_org_denied: item % is in a different organization', p_id using errcode='42501'; end if;
  return public.e10_inv_release(p_id, p_show_ref, p_idempotency_key);
end; $fn$;

create or replace function public.e10_org_inv_consume(p_org uuid, p_id text, p_break_session_id text, p_source_show_ref text, p_qty numeric, p_idempotency_key text) returns jsonb
  language plpgsql security definer set search_path to 'public' as $fn$
declare v_item_org uuid;
begin
  if not e10.is_org_member(p_org) then raise exception 'cross_org_denied: not a member of organization %', p_org using errcode='42501'; end if;
  if not e10.has_org_cap(p_org,'act.inventory_edit') then raise exception 'e10_org_inv_consume: missing act.inventory_edit' using errcode='42501'; end if;
  select organization_id into v_item_org from public.e10_inventory_items where id=p_id;
  if v_item_org is not null and v_item_org<>p_org then raise exception 'cross_org_denied: item % is in a different organization', p_id using errcode='42501'; end if;
  return public.e10_inv_consume(p_id, p_break_session_id, p_source_show_ref, p_qty, p_idempotency_key);
end; $fn$;

create or replace function public.e10_org_inv_mark_sold(p_org uuid, p_id text, p_qty numeric, p_proceeds numeric, p_idempotency_key text) returns jsonb
  language plpgsql security definer set search_path to 'public' as $fn$
declare v_item_org uuid;
begin
  if not e10.is_org_member(p_org) then raise exception 'cross_org_denied: not a member of organization %', p_org using errcode='42501'; end if;
  if not e10.has_org_cap(p_org,'act.inventory_edit') then raise exception 'e10_org_inv_mark_sold: missing act.inventory_edit' using errcode='42501'; end if;
  select organization_id into v_item_org from public.e10_inventory_items where id=p_id;
  if v_item_org is not null and v_item_org<>p_org then raise exception 'cross_org_denied: item % is in a different organization', p_id using errcode='42501'; end if;
  return public.e10_inv_mark_sold(p_id, p_qty, p_proceeds, p_idempotency_key);
end; $fn$;

create or replace function public.e10_org_inv_reverse_consumption(p_org uuid, p_id text, p_reverses_movement_id uuid, p_idempotency_key text) returns jsonb
  language plpgsql security definer set search_path to 'public' as $fn$
declare v_item_org uuid;
begin
  if not e10.is_org_member(p_org) then raise exception 'cross_org_denied: not a member of organization %', p_org using errcode='42501'; end if;
  if not e10.has_org_cap(p_org,'act.inventory_edit') then raise exception 'e10_org_inv_reverse_consumption: missing act.inventory_edit' using errcode='42501'; end if;
  select organization_id into v_item_org from public.e10_inventory_items where id=p_id;
  if v_item_org is not null and v_item_org<>p_org then raise exception 'cross_org_denied: item % is in a different organization', p_id using errcode='42501'; end if;
  return public.e10_inv_reverse_consumption(p_id, p_reverses_movement_id, p_idempotency_key);
end; $fn$;

-- Entity read: fully org-scoped (org-blind legacy read + DEFINER bypass would leak cross-org)
create or replace function public.e10_org_inv_get(p_org uuid, p_id text) returns jsonb
  language plpgsql stable security definer set search_path to 'public' as $fn$
begin
  if not e10.is_org_member(p_org) then raise exception 'cross_org_denied: not a member of organization %', p_org using errcode='42501'; end if;
  return public._e10_inv_item_json(p_org, p_id);
end; $fn$;

-- Member read: fully org-scoped list
create or replace function public.e10_org_inv_list(p_org uuid) returns jsonb
  language plpgsql stable security definer set search_path to 'public' as $fn$
begin
  if not e10.is_org_member(p_org) then raise exception 'cross_org_denied: not a member of organization %', p_org using errcode='42501'; end if;
  return (select coalesce(jsonb_agg(public._e10_inv_item_json(p_org, it.id) order by it.id),'[]'::jsonb)
            from public.e10_inventory_items it where it.organization_id = p_org);
end; $fn$;

-- Entity (session-owner): org from session via owns_session; NEVER current_org
create or replace function public.e10_org_buyer_suggest(p_session uuid, p_q text) returns jsonb
  language plpgsql stable security definer set search_path to 'public' as $fn$
begin
  if not e10.owns_session(p_session) then raise exception 'cross_org_denied: not the session owner' using errcode='42501'; end if;
  return public.e10_buyer_suggest(p_session, p_q);
end; $fn$;

-- Viewer: org derived from the globally-unique share_code; explicit organization_id on the viewer row; NEVER current_org
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

-- born-locked grants: the 13 client delegates get authenticated + service_role; revoke PUBLIC/anon
do $$ declare f text; begin
  foreach f in array array[
    'public.e10_org_inv_add_item(uuid,jsonb,text)',
    'public.e10_org_inv_edit_item(uuid,text,jsonb,text,text[])',
    'public.e10_org_inv_delete_item(uuid,text,text)',
    'public.e10_org_inv_reserve(uuid,text,text,text,numeric,text)',
    'public.e10_org_inv_release(uuid,text,text,text)',
    'public.e10_org_inv_consume(uuid,text,text,text,numeric,text)',
    'public.e10_org_inv_mark_sold(uuid,text,numeric,numeric,text)',
    'public.e10_org_inv_set_reservations(uuid,text,text,jsonb,text)',
    'public.e10_org_inv_reverse_consumption(uuid,text,uuid,text)',
    'public.e10_org_inv_get(uuid,text)',
    'public.e10_org_inv_list(uuid)',
    'public.e10_org_buyer_suggest(uuid,text)',
    'public.e10_org_redeem_code(text)'
  ] loop
    execute format('revoke execute on function %s from public', f);
    execute format('revoke execute on function %s from anon', f);
    execute format('grant execute on function %s to authenticated', f);
    execute format('grant execute on function %s to service_role', f);
  end loop;
end $$;
