-- Element 10 — SAFE RECOVERY artifact (Chain P — P0R)
--
-- This is a RECOVERY script, NOT a rollback. It reinstalls the LAST-KNOWN-SECURE bodies of
-- e10_inv_consume and e10_inv_reverse_consumption (the M3.2.2 definitions, captured verbatim from the
-- live catalog via pg_get_functiondef). Run it only if those functions are ever accidentally replaced
-- or drift from the secure definitions. It restores the authorization guarantees; it never reintroduces
-- the pre-M3.2.2 defects (unknown-session fall-through to unreserved consume; unenforced reversal
-- ownership). Those states are not valid recovery targets and appear nowhere below.
--
-- Preserves by construction:
--   * unknown-session rejection            (consume: 'unknown break session')
--   * consume ownership check              (consume: 'not your break session' + source_show_ref match)
--   * reversal ownership check             (reverse: session-owner else original-actor, else reject)
--   * idempotency receipts + movement ledger (advisory lock + _e10_inv_receipt_check/_write, emit)
--   * NO stateful table is dropped or recreated — only CREATE OR REPLACE of two function bodies.
--
-- Safe to execute inside a transaction and roll back (see the proof harness in the P0R report), and
-- safe to run for real after accidental function replacement or drift. Idempotent: re-running installs
-- the same bytes.

CREATE OR REPLACE FUNCTION public.e10_inv_consume(p_id text, p_break_session_id text, p_source_show_ref text, p_qty numeric, p_idempotency_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
  if p_break_session_id is null or btrim(p_break_session_id) = '' then
    v_show_ref := null;
  else
    begin
      perform p_break_session_id::uuid; v_uuid_ok := true;
    exception when invalid_text_representation then
      v_uuid_ok := false;
    end;
    if not v_uuid_ok then
      v_show_ref := null;
    else
      select source_show_ref, streamer_uid into v_sess_show, v_sess_owner
        from public.e10_break_sessions where id = p_break_session_id::uuid;
      if not found then
        return jsonb_build_object('ok',false,'msg','unknown break session');
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
$function$;

CREATE OR REPLACE FUNCTION public.e10_inv_reverse_consumption(p_id text, p_reverses_movement_id uuid, p_idempotency_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
$function$;
