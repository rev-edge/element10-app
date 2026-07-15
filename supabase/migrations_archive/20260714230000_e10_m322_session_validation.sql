-- Migration: e10_m322_session_validation  (M3.2.2a — narrow closure)
-- Item 1: e10_inv_consume — a well-formed UUID p_break_session_id that matches NO e10_break_sessions row
--   is REJECTED ('unknown break session'), not silently treated as an unreserved draw. Only an explicitly
--   supported bypass — null/empty, or a legacy NON-UUID literal (e.g. 'break') — skips the session lookup.
-- Item 2: e10_inv_reverse_consumption — same session-ownership rule as consume. The session is derived from
--   the reversed movement's source_entity_id; the caller must be the session owner (streamer_uid=auth.uid())
--   or admin. A movement with no session linkage falls back to the original actor (actor_uid) or admin.
-- ADDITIVE (CREATE OR REPLACE of two functions only); ZERO rows; no signature/grant/RLS/table change.
--
-- ROADMAP FACTUAL CORRECTION (carried per the M3.2.2 prompt): M3.1 ALREADY serialized same-key mutations —
-- the advisory lock lived in _e10_inv_receipt_check, which every RPC called before mutating. M3.2.1 made
-- the lock directly auditable per-body and added different-key unique_violation handling; it did NOT
-- introduce serialization. The prior audit's grep excluded underscore-prefixed helpers (false negative).
-- ─────────────────────────────────────────────────────────────────────────────

create or replace function public.e10_inv_consume(p_id text, p_break_session_id text, p_source_show_ref text,
    p_qty numeric, p_idempotency_key text)
  returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_actor text := auth.jwt()->>'email'; v_qty numeric; v_mid uuid; v_rev bigint;
        v_fp text; v_rc jsonb; v_admin boolean := (select public.e10_is_admin());
        v_draw numeric := 0; v_remaining numeric; v_cut numeric; r record; v_alloc jsonb := '[]'::jsonb;
        v_show_ref text; v_uuid_ok boolean := false; v_sess_show text; v_sess_owner uuid;
begin
  perform public._e10_inv_guard();
  if p_idempotency_key is null or btrim(p_idempotency_key) = '' then
    return jsonb_build_object('ok',false,'msg','idempotency_key required'); end if;
  perform pg_advisory_xact_lock(hashtext(p_idempotency_key));
  v_fp := md5(coalesce(p_id,'')||'|'||coalesce(p_break_session_id,'')||'|'||coalesce(p_source_show_ref,'')||'|'||coalesce(p_qty::text,''));
  v_rc := public._e10_inv_receipt_check(p_idempotency_key, 'consume', p_id, v_fp);
  if v_rc ? '_mismatch' then return jsonb_build_object('ok',false,'msg','idempotency key reused with different arguments'); end if;
  if v_rc is not null then return public._e10_inv_replay_json(p_id, v_rc); end if;
  if p_qty is null or p_qty <= 0 then return jsonb_build_object('ok',false,'msg','consume qty must be positive'); end if;
  select qty into v_qty from public.e10_inventory_items where id = p_id for update;
  if not found then return jsonb_build_object('ok',false,'msg','item not found'); end if;
  if p_qty > coalesce(v_qty,0) then return jsonb_build_object('ok',false,'msg','cannot consume more than '||coalesce(v_qty,0)||' on hand'); end if;
  -- ITEM 1/4: resolve the source show ref from the SESSION (never trust the client's p_source_show_ref).
  -- null/empty OR a legacy non-UUID literal → explicit bypass (unreserved draw). A well-formed UUID that
  -- finds no session → hard reject (existence validation must not fall through to an unreserved draw).
  if p_break_session_id is null or btrim(p_break_session_id) = '' then
    v_show_ref := null;
  else
    begin
      perform p_break_session_id::uuid; v_uuid_ok := true;
    exception when invalid_text_representation then
      v_uuid_ok := false;                                   -- legacy non-uuid literal (e.g. 'break')
    end;
    if not v_uuid_ok then
      v_show_ref := null;                                    -- legacy bypass → unreserved draw
    else
      select source_show_ref, streamer_uid into v_sess_show, v_sess_owner
        from public.e10_break_sessions where id = p_break_session_id::uuid;
      if not found then
        return jsonb_build_object('ok',false,'msg','unknown break session');   -- ITEM 1
      end if;
      if not (v_sess_owner = auth.uid() or v_admin) then
        return jsonb_build_object('ok',false,'msg','not your break session');
      end if;
      if p_source_show_ref is not null and p_source_show_ref is distinct from v_sess_show then
        return jsonb_build_object('ok',false,'msg','source_show_ref does not match the session');
      end if;
      v_show_ref := v_sess_show;
    end if;
  end if;
  -- derive the reserved drawdown from matching active reservations (by the SERVER show ref), FIFO.
  if v_show_ref is not null and btrim(v_show_ref) <> '' then
    v_remaining := p_qty;
    for r in select id, qty, show_ref, show_label, streamer_uid, created_by
               from public.e10_inventory_reservations
              where item_id = p_id and show_ref is not distinct from v_show_ref and status = 'active'
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
             jsonb_build_object('consumed_qty', p_qty, 'source_show_ref', v_show_ref, 'reserved_drawn', v_draw, 'allocation', v_alloc));
  perform public._e10_inv_receipt_write(p_idempotency_key, 'consume', p_id, v_fp, v_mid);
  return jsonb_build_object('ok',true,'msg','consumed','item',public._e10_inv_item_json(p_id),'rev',v_rev,'movement_id',v_mid);
end;
$$;

create or replace function public.e10_inv_reverse_consumption(p_id text, p_reverses_movement_id uuid, p_idempotency_key text)
  returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_actor text := auth.jwt()->>'email'; v_mid uuid; v_rev bigint; v_fp text; v_rc jsonb;
        v_src record; v_meta jsonb; v_cq numeric; v_draw numeric; a jsonb; v_sess text;
        v_admin boolean := (select public.e10_is_admin()); v_sess_owner uuid; v_sess_found boolean := false;
begin
  perform public._e10_inv_guard();
  if p_idempotency_key is null or btrim(p_idempotency_key) = '' then
    return jsonb_build_object('ok',false,'msg','idempotency_key required'); end if;
  perform pg_advisory_xact_lock(hashtext(p_idempotency_key));
  v_fp := md5(coalesce(p_id,'')||'|'||coalesce(p_reverses_movement_id::text,''));
  v_rc := public._e10_inv_receipt_check(p_idempotency_key, 'reverse_consumption', p_id, v_fp);
  if v_rc ? '_mismatch' then return jsonb_build_object('ok',false,'msg','idempotency key reused with different arguments'); end if;
  if v_rc is not null then return public._e10_inv_replay_json(p_id, v_rc); end if;
  select item_id, movement_type, on_hand_delta, meta, source_entity_id, actor_uid
    into v_src from public.e10_inventory_movements where id = p_reverses_movement_id;
  if not found then return jsonb_build_object('ok',false,'msg','movement to reverse not found'); end if;
  if v_src.movement_type <> 'break_consumption' then return jsonb_build_object('ok',false,'msg','not a break consumption movement'); end if;
  if v_src.item_id is distinct from p_id then return jsonb_build_object('ok',false,'msg','movement item mismatch'); end if;
  perform 1 from public.e10_inventory_items where id = p_id for update;
  if not found then return jsonb_build_object('ok',false,'msg','item not found'); end if;
  -- ITEM 2: same ownership rule as consume, derived from the reversed movement. Session owner or admin;
  -- if the movement has no (resolvable) session linkage, fall back to the original actor or admin.
  if v_src.source_entity_id is not null and btrim(v_src.source_entity_id) <> '' then
    begin
      select streamer_uid into v_sess_owner from public.e10_break_sessions where id = v_src.source_entity_id::uuid;
      v_sess_found := found;
    exception when invalid_text_representation then
      v_sess_found := false;
    end;
  end if;
  if v_sess_found then
    if not (v_sess_owner = auth.uid() or v_admin) then
      return jsonb_build_object('ok',false,'msg','not your break session');
    end if;
  else
    if not (v_src.actor_uid is not distinct from auth.uid() or v_admin) then
      return jsonb_build_object('ok',false,'msg','not your consumption to reverse');
    end if;
  end if;
  v_meta := coalesce(v_src.meta, '{}'::jsonb);
  v_cq   := coalesce(nullif(v_meta->>'consumed_qty','')::numeric, -coalesce(v_src.on_hand_delta,0));
  v_draw := coalesce(nullif(v_meta->>'reserved_drawn','')::numeric, 0);
  v_sess := v_src.source_entity_id;
  begin
    update public.e10_inventory_items set qty = coalesce(qty,0) + v_cq, updated_by = auth.uid(), updated_at = now()
      where id = p_id;
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

-- ITEM 4 — dedicated test-fixture cleanup helper. TEST NAMESPACE ONLY: the prefix must start with 'zz'
-- (real inventory ids are iS../i17.., real sessions aren't 'zz'-tagged), so it can never touch real data.
-- Member-gated; session deletion by id is restricted to the caller's own sessions (or admin). Lets the
-- anon-key test harness remove its own LEDGER rows + RECEIPTS (otherwise append-only / client-undeletable),
-- so teardown is self-contained with no external SQL sweep. Not used by any app code path.
create or replace function public.e10_test_cleanup(p_prefix text, p_session_ids uuid[] default null)
  returns jsonb language plpgsql security definer set search_path to 'public' as $$
begin
  perform public._e10_inv_guard();
  if p_prefix is null or p_prefix !~ '^zz' or length(p_prefix) < 4 then
    raise exception 'e10_test_cleanup: prefix must start with ''zz'' and be >= 4 chars (test namespace only)' using errcode = '22023';
  end if;
  delete from public.e10_inventory_movements   where item_id like p_prefix||'%' or idempotency_key like p_prefix||'%';
  delete from public.e10_mutation_receipts      where idempotency_key like p_prefix||'%' or item_id like p_prefix||'%';
  delete from public.e10_inventory_reservations where item_id like p_prefix||'%';
  delete from public.e10_inventory_items        where id like p_prefix||'%';
  delete from public.e10_break_sessions
   where source_show_ref like p_prefix||'%'
      or (p_session_ids is not null and id = any(p_session_ids)
          and (streamer_uid = auth.uid() or (select public.e10_is_admin())));
  update public.e10_workspace set data = jsonb_set(coalesce(data,'{}'::jsonb),'{inventory}',
    (select coalesce(jsonb_agg(e),'[]'::jsonb) from jsonb_array_elements(data->'inventory') e where e->>'id' not like p_prefix||'%'))
   where id = 'shared';
  return jsonb_build_object('ok', true, 'prefix', p_prefix);
end;
$$;
revoke all on function public.e10_test_cleanup(text, uuid[]) from public, anon;
grant execute on function public.e10_test_cleanup(text, uuid[]) to authenticated;

-- ═════════════════════════════════════════════════════════════════════════════
-- ROLLBACK (M3.2.2a) — ITEM 3: a REAL, receipts-preserving down-block. Re-run the two CREATE OR REPLACE
-- statements below to restore the pre-M3.2.2 (M3.2.1) bodies. This touches NO table and NEVER drops or
-- recreates e10_mutation_receipts, so accumulated idempotency history is preserved.
-- ⚠ Re-running migration 20260714150000_e10_m31_mutation_hardening.sql is NOT a rollback path: it DROPs
--   and recreates e10_mutation_receipts (DESTROYING receipt history). Do not use it to revert.
--
-- -- Pre-M3.2.2 e10_inv_consume (M3.2.1 body): well-formed-UUID-with-no-session falls through to unreserved.
-- create or replace function public.e10_inv_consume(p_id text, p_break_session_id text, p_source_show_ref text,
--     p_qty numeric, p_idempotency_key text) returns jsonb language plpgsql security definer set search_path to 'public' as $$
-- declare v_actor text := auth.jwt()->>'email'; v_qty numeric; v_mid uuid; v_rev bigint;
--         v_fp text; v_rc jsonb; v_admin boolean := (select public.e10_is_admin());
--         v_draw numeric := 0; v_remaining numeric; v_cut numeric; r record; v_alloc jsonb := '[]'::jsonb;
--         v_show_ref text; v_sess_found boolean := false; v_sess_show text; v_sess_owner uuid;
-- begin
--   perform public._e10_inv_guard();
--   if p_idempotency_key is null or btrim(p_idempotency_key) = '' then return jsonb_build_object('ok',false,'msg','idempotency_key required'); end if;
--   perform pg_advisory_xact_lock(hashtext(p_idempotency_key));
--   v_fp := md5(coalesce(p_id,'')||'|'||coalesce(p_break_session_id,'')||'|'||coalesce(p_source_show_ref,'')||'|'||coalesce(p_qty::text,''));
--   v_rc := public._e10_inv_receipt_check(p_idempotency_key, 'consume', p_id, v_fp);
--   if v_rc ? '_mismatch' then return jsonb_build_object('ok',false,'msg','idempotency key reused with different arguments'); end if;
--   if v_rc is not null then return public._e10_inv_replay_json(p_id, v_rc); end if;
--   if p_qty is null or p_qty <= 0 then return jsonb_build_object('ok',false,'msg','consume qty must be positive'); end if;
--   select qty into v_qty from public.e10_inventory_items where id = p_id for update;
--   if not found then return jsonb_build_object('ok',false,'msg','item not found'); end if;
--   if p_qty > coalesce(v_qty,0) then return jsonb_build_object('ok',false,'msg','cannot consume more than '||coalesce(v_qty,0)||' on hand'); end if;
--   if p_break_session_id is not null and btrim(p_break_session_id) <> '' then
--     begin select source_show_ref, streamer_uid into v_sess_show, v_sess_owner from public.e10_break_sessions where id = p_break_session_id::uuid; v_sess_found := found;
--     exception when invalid_text_representation then v_sess_found := false; end;
--   end if;
--   if v_sess_found then
--     if not (v_sess_owner = auth.uid() or v_admin) then return jsonb_build_object('ok',false,'msg','not your break session'); end if;
--     if p_source_show_ref is not null and p_source_show_ref is distinct from v_sess_show then return jsonb_build_object('ok',false,'msg','source_show_ref does not match the session'); end if;
--     v_show_ref := v_sess_show;
--   else v_show_ref := null; end if;
--   -- (drawdown / mutate / clamp / blob / emit / receipt identical to current body) …
-- end; $$;
-- -- Pre-M3.2.2 e10_inv_reverse_consumption (M3.2.1 body): NO ownership check (drop the item-2 block above).
-- ═════════════════════════════════════════════════════════════════════════════
