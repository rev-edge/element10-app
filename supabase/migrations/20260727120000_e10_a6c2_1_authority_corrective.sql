-- Element 10 — A6c.2.1 authority corrective.
-- A6c.2 relocated the legacy inventory mechanics into the e10_org_* delegates but "preserve legacy behavior verbatim"
-- also preserved legacy AUTHORITY verbatim: six relocated bodies carried the legacy GLOBAL predicate public.e10_is_admin()
-- (= exists in e10_members where role='admin', org-blind) inside org-aware bodies. In a multi-tenant world a legacy global
-- admin holding only ordinary membership in org B would exercise admin behavior in org B. Where behavior-preservation and
-- org-scoping conflict, ORG-SCOPING WINS. This migration:
--   (1) buyer_suggest: scopes the `seen` query to the REQUESTED session (sl.session_id = p_session, consistent with the
--       roster CTE; the entry already verifies e10.owns_session(p_session)) and removes e10_is_admin() entirely. This
--       narrows suggestion breadth vs legacy — an APPROVED behavioral divergence (a non-owner previously leaked every
--       buyer they ever hosted, and a legacy global admin leaked buyers across every organization).
--   (2) five inventory delegates: replace the global public.e10_is_admin() with the org-scoped e10.is_org_admin(p_org)
--       (platform-admin OR admin-role membership of p_org). A legacy global admin with ordinary membership in org B now
--       gets ordinary-member treatment in org B.
--   (3) retires the two dead legacy orphans _e10_inv_receipt/_e10_inv_replay (reference the dropped `response` column since
--       A6c.0), each guarded by an in-migration reference-count=0 proof — same pattern as the seven retired in A6c.2.
-- Every other line of each body is reproduced verbatim from 20260726140000 (return shapes/messages unchanged). Wrappers,
-- other delegates, org-aware _e10_inv_* helpers, and the 55 A6c.1 policies are NOT touched.

-- =====================================================================================================================
-- (1) buyer_suggest — org/session-scoped `seen`; no global admin
-- =====================================================================================================================
CREATE OR REPLACE FUNCTION public.e10_org_buyer_suggest(p_session uuid, p_q text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare q text := lower(btrim(coalesce(p_q,''))); out jsonb;
begin
  if not e10.owns_session(p_session) then raise exception 'cross_org_denied: not the session owner' using errcode='42501'; end if;
  with roster as (
    select v.whatnot_handle as handle, max(v.user_id::text) as viewer_uid, 'roster' as src
      from public.e10_session_viewers sv join public.e10_viewers v on v.user_id=sv.user_id
     where sv.session_id=p_session and coalesce(btrim(v.whatnot_handle),'')<>''
     group by v.whatnot_handle
  ), seen as (
    -- A6c.2.1: scoped to the requested session (owns_session already verified) and stripped of the global admin path.
    select distinct on (lower(sl.buyer_handle)) sl.buyer_handle as handle, sl.buyer_uid::text as viewer_uid, 'seen' as src
      from public.e10_break_slots sl
     where sl.session_id = p_session
       and coalesce(btrim(sl.buyer_handle),'')<>''
     order by lower(sl.buyer_handle), sl.updated_at desc
  ), merged as (select handle,viewer_uid,src from roster union all select handle,viewer_uid,src from seen),
  dedup as (
    select distinct on (lower(handle)) handle, viewer_uid, src from merged
     where q='' or lower(handle) like '%'||q||'%'
     order by lower(handle), (src='roster') desc
  )
  select coalesce(jsonb_agg(jsonb_build_object('label',handle,'id',viewer_uid,'sub',src) order by handle),'[]'::jsonb)
    into out from (select * from dedup limit 20) x;
  return out;
end $function$;

-- =====================================================================================================================
-- (2) five inventory delegates — global e10_is_admin() -> org-scoped e10.is_org_admin(p_org)
-- =====================================================================================================================

-- ---- Entity: release ----
CREATE OR REPLACE FUNCTION public.e10_org_inv_release(p_org uuid, p_id text, p_show_ref text, p_idempotency_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_actor text := auth.jwt()->>'email'; v_rel numeric; v_mid uuid; v_rev bigint;
        v_fp text; v_rc jsonb; v_admin boolean := e10.is_org_admin(p_org); v_item_org uuid;
begin
  if not e10.is_org_member(p_org) then raise exception 'cross_org_denied: not a member of organization %', p_org using errcode='42501'; end if;
  if not e10.has_org_cap(p_org,'act.inventory_edit') then raise exception 'e10_org_inv_release: missing act.inventory_edit' using errcode='42501'; end if;
  select organization_id into v_item_org from public.e10_inventory_items where id=p_id;
  if v_item_org is not null and v_item_org<>p_org then raise exception 'cross_org_denied: item % is in a different organization', p_id using errcode='42501'; end if;
  perform public._e10_inv_guard(p_org);
  if p_idempotency_key is null or btrim(p_idempotency_key) = '' then
    return jsonb_build_object('ok',false,'msg','idempotency_key required'); end if;
  perform pg_advisory_xact_lock(hashtext(p_idempotency_key));
  v_fp := md5(coalesce(p_id,'')||'|'||coalesce(p_show_ref,''));
  v_rc := public._e10_inv_receipt_check(p_org, p_idempotency_key, 'release', p_id, v_fp);
  if v_rc ? '_mismatch' then return jsonb_build_object('ok',false,'msg','idempotency key reused with different arguments'); end if;
  if v_rc is not null then return public._e10_inv_replay_json(p_org, p_id, v_rc); end if;
  perform 1 from public.e10_inventory_items where id = p_id and organization_id = p_org for update;
  if not found then return jsonb_build_object('ok',false,'msg','item not found'); end if;
  select coalesce(sum(qty),0) into v_rel from public.e10_inventory_reservations
    where item_id = p_id and show_ref is not distinct from p_show_ref and status = 'active' and organization_id = p_org
      and (v_admin or created_by = auth.uid() or (created_by is null and streamer_uid = auth.uid()::text));
  if v_rel = 0 then return jsonb_build_object('ok',false,'msg','no active reservation of yours for that show'); end if;
  update public.e10_inventory_reservations set status = 'released'
    where item_id = p_id and show_ref is not distinct from p_show_ref and status = 'active' and organization_id = p_org
      and (v_admin or created_by = auth.uid() or (created_by is null and streamer_uid = auth.uid()::text));
  v_rev := public._e10_inv_blob_write(p_org, p_id, false, v_actor);
  v_mid := public.e10_org_emit_inventory_movement(p_org, p_id, 'reservation_release', 0, -v_rel, p_idempotency_key,
             'release', 'reservation released', 'show', p_show_ref, 'release', null, '{}'::jsonb);
  perform public._e10_inv_receipt_write(p_org, p_idempotency_key, 'release', p_id, v_fp, v_mid);
  return jsonb_build_object('ok',true,'msg','released','item',public._e10_inv_item_json(p_org, p_id),'rev',v_rev,'movement_id',v_mid);
end; $function$;

-- ---- Entity: consume ----
CREATE OR REPLACE FUNCTION public.e10_org_inv_consume(p_org uuid, p_id text, p_break_session_id text, p_source_show_ref text, p_qty numeric, p_idempotency_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_actor text := auth.jwt()->>'email'; v_qty numeric; v_mid uuid; v_rev bigint;
        v_fp text; v_rc jsonb; v_admin boolean := e10.is_org_admin(p_org);
        v_draw numeric := 0; v_remaining numeric; v_cut numeric; r record; v_alloc jsonb := '[]'::jsonb;
        v_show_ref text; v_uuid_ok boolean := false; v_sess_show text; v_sess_owner uuid; v_item_org uuid;
begin
  if not e10.is_org_member(p_org) then raise exception 'cross_org_denied: not a member of organization %', p_org using errcode='42501'; end if;
  if not e10.has_org_cap(p_org,'act.inventory_edit') then raise exception 'e10_org_inv_consume: missing act.inventory_edit' using errcode='42501'; end if;
  select organization_id into v_item_org from public.e10_inventory_items where id=p_id;
  if v_item_org is not null and v_item_org<>p_org then raise exception 'cross_org_denied: item % is in a different organization', p_id using errcode='42501'; end if;
  perform public._e10_inv_guard(p_org);
  if p_idempotency_key is null or btrim(p_idempotency_key) = '' then
    return jsonb_build_object('ok',false,'msg','idempotency_key required'); end if;
  perform pg_advisory_xact_lock(hashtext(p_idempotency_key));
  v_fp := md5(coalesce(p_id,'')||'|'||coalesce(p_break_session_id,'')||'|'||coalesce(p_source_show_ref,'')||'|'||coalesce(p_qty::text,''));
  v_rc := public._e10_inv_receipt_check(p_org, p_idempotency_key, 'consume', p_id, v_fp);
  if v_rc ? '_mismatch' then return jsonb_build_object('ok',false,'msg','idempotency key reused with different arguments'); end if;
  if v_rc is not null then return public._e10_inv_replay_json(p_org, p_id, v_rc); end if;
  if p_qty is null or p_qty <= 0 then return jsonb_build_object('ok',false,'msg','consume qty must be positive'); end if;
  select qty into v_qty from public.e10_inventory_items where id = p_id and organization_id = p_org for update;
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
        from public.e10_break_sessions where id = p_break_session_id::uuid and organization_id = p_org;
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
              where item_id = p_id and show_ref is not distinct from v_show_ref and status = 'active' and organization_id = p_org
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
    where id = p_id and organization_id = p_org;
  perform public._e10_inv_clamp_res(p_org, p_id, p_idempotency_key);
  v_rev := public._e10_inv_blob_write(p_org, p_id, false, v_actor);
  v_mid := public.e10_org_emit_inventory_movement(p_org, p_id, 'break_consumption', -p_qty, -v_draw, p_idempotency_key,
             'break', 'consumed by break', 'break_session', p_break_session_id, 'consume', null,
             jsonb_build_object('consumed_qty', p_qty, 'source_show_ref', v_show_ref, 'reserved_drawn', v_draw, 'allocation', v_alloc));
  perform public._e10_inv_receipt_write(p_org, p_idempotency_key, 'consume', p_id, v_fp, v_mid);
  return jsonb_build_object('ok',true,'msg','consumed','item',public._e10_inv_item_json(p_org, p_id),'rev',v_rev,'movement_id',v_mid);
end; $function$;

-- ---- Entity: mark_sold ----
CREATE OR REPLACE FUNCTION public.e10_org_inv_mark_sold(p_org uuid, p_id text, p_qty numeric, p_proceeds numeric, p_idempotency_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_actor text := auth.jwt()->>'email'; v_qty numeric; v_res numeric; v_avail numeric;
        v_mid uuid; v_rev bigint; v_fp text; v_rc jsonb; v_item_org uuid;
begin
  if not e10.is_org_member(p_org) then raise exception 'cross_org_denied: not a member of organization %', p_org using errcode='42501'; end if;
  if not e10.has_org_cap(p_org,'act.inventory_edit') then raise exception 'e10_org_inv_mark_sold: missing act.inventory_edit' using errcode='42501'; end if;
  select organization_id into v_item_org from public.e10_inventory_items where id=p_id;
  if v_item_org is not null and v_item_org<>p_org then raise exception 'cross_org_denied: item % is in a different organization', p_id using errcode='42501'; end if;
  perform public._e10_inv_guard(p_org);
  if p_idempotency_key is null or btrim(p_idempotency_key) = '' then
    return jsonb_build_object('ok',false,'msg','idempotency_key required'); end if;
  perform pg_advisory_xact_lock(hashtext(p_idempotency_key));
  v_fp := md5(coalesce(p_id,'')||'|'||coalesce(p_qty::text,'')||'|'||coalesce(p_proceeds::text,''));
  v_rc := public._e10_inv_receipt_check(p_org, p_idempotency_key, 'mark_sold', p_id, v_fp);
  if v_rc ? '_mismatch' then return jsonb_build_object('ok',false,'msg','idempotency key reused with different arguments'); end if;
  if v_rc is not null then return public._e10_inv_replay_json(p_org, p_id, v_rc); end if;
  if p_qty is null or p_qty <= 0 then return jsonb_build_object('ok',false,'msg','sell qty must be positive'); end if;
  if p_proceeds is not null and p_proceeds < 0 then return jsonb_build_object('ok',false,'msg','proceeds cannot be negative'); end if;
  select qty into v_qty from public.e10_inventory_items where id = p_id and organization_id = p_org for update;
  if not found then return jsonb_build_object('ok',false,'msg','item not found'); end if;
  select coalesce(sum(qty),0) into v_res from public.e10_inventory_reservations where item_id = p_id and status = 'active' and organization_id = p_org;
  v_avail := coalesce(v_qty,0) - v_res;
  if p_qty > coalesce(v_qty,0) then return jsonb_build_object('ok',false,'msg','cannot sell more than '||coalesce(v_qty,0)||' on hand'); end if;
  if p_qty > v_avail and not e10.is_org_admin(p_org) then
    return jsonb_build_object('ok',false,'msg','only '||v_avail||' available'); end if;
  update public.e10_inventory_items set
    qty = coalesce(qty,0) - p_qty,
    sold_qty = coalesce(sold_qty,0) + p_qty,
    sold_proceeds = coalesce(sold_proceeds,0) + coalesce(p_proceeds,0),
    sold_at = (extract(epoch from now())*1000)::numeric,
    updated_by = auth.uid(), updated_at = now()
  where id = p_id and organization_id = p_org;
  perform public._e10_inv_clamp_res(p_org, p_id, p_idempotency_key);
  v_rev := public._e10_inv_blob_write(p_org, p_id, false, v_actor);
  v_mid := public.e10_org_emit_inventory_movement(p_org, p_id, 'sale', -p_qty, 0, p_idempotency_key,
             'sale', 'marked sold', 'inventory', p_id, 'mark_sold', null,
             jsonb_build_object('proceeds', coalesce(p_proceeds,0)));
  perform public._e10_inv_receipt_write(p_org, p_idempotency_key, 'mark_sold', p_id, v_fp, v_mid);
  return jsonb_build_object('ok',true,'msg','sold','item',public._e10_inv_item_json(p_org, p_id),'rev',v_rev,'movement_id',v_mid);
end; $function$;

-- ---- Member: set_reservations ----
CREATE OR REPLACE FUNCTION public.e10_org_inv_set_reservations(p_org uuid, p_show_ref text, p_show_label text, p_targets jsonb, p_idempotency_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_actor text := auth.jwt()->>'email'; v_admin boolean := e10.is_org_admin(p_org);
        v_fp text; v_rc jsonb; t jsonb; v_ids text[]; v_id text; v_tq numeric; v_item_qty numeric;
        v_caller numeric; v_total numeric; v_other numeric; v_net numeric; v_rev bigint;
        v_items jsonb := '[]'::jsonb; r record; v_cut numeric; v_reduce numeric; v_mid uuid;
begin
  if not e10.is_org_member(p_org) then raise exception 'cross_org_denied: not a member of organization %', p_org using errcode='42501'; end if;
  if not e10.has_org_cap(p_org,'act.inventory_edit') then raise exception 'e10_org_inv_set_reservations: missing act.inventory_edit' using errcode='42501'; end if;
  perform public._e10_inv_guard(p_org);
  if p_idempotency_key is null or btrim(p_idempotency_key) = '' then
    return jsonb_build_object('ok',false,'msg','idempotency_key required'); end if;
  perform pg_advisory_xact_lock(hashtext(p_idempotency_key));
  if p_targets is null or jsonb_typeof(p_targets) <> 'array' then
    return jsonb_build_object('ok',false,'msg','targets must be an array'); end if;
  v_fp := md5(coalesce(p_show_ref,'')||'|'||coalesce(p_targets::text,''));
  v_rc := public._e10_inv_receipt_check(p_org, p_idempotency_key, 'set_reservations', null, v_fp);
  if v_rc ? '_mismatch' then return jsonb_build_object('ok',false,'msg','idempotency key reused with different arguments'); end if;
  if v_rc is not null then return jsonb_build_object('ok',true,'replay',true,'msg','replay','item',null,
    'rev',(select rev from public.e10_workspace where id='shared' and organization_id=p_org),'movement_id',null,'idempotency_key',v_rc->'idempotency_key'); end if;
  select array_agg(distinct (e->>'item_id') order by (e->>'item_id')) into v_ids
    from jsonb_array_elements(p_targets) e where coalesce(e->>'item_id','') <> '';
  if v_ids is null then return jsonb_build_object('ok',false,'msg','no targets'); end if;
  perform 1 from public.e10_inventory_items where id = any(v_ids) and organization_id = p_org order by id for update;
  for t in select * from jsonb_array_elements(p_targets) loop
    v_id := t->>'item_id'; v_tq := coalesce(nullif(t->>'qty','')::numeric, 0);
    select qty into v_item_qty from public.e10_inventory_items where id = v_id and organization_id = p_org;
    if not found then return jsonb_build_object('ok',false,'msg','item not found: '||coalesce(v_id,'?')); end if;
    if v_tq < 0 then return jsonb_build_object('ok',false,'msg','target qty cannot be negative for '||v_id); end if;
    select coalesce(sum(qty),0) into v_caller from public.e10_inventory_reservations
      where item_id = v_id and show_ref is not distinct from p_show_ref and status = 'active' and organization_id = p_org
        and (v_admin or created_by = auth.uid() or (created_by is null and streamer_uid = auth.uid()::text));
    select coalesce(sum(qty),0) into v_total from public.e10_inventory_reservations
      where item_id = v_id and status = 'active' and organization_id = p_org;
    v_other := v_total - v_caller;
    if v_tq + v_other > coalesce(v_item_qty,0) then
      return jsonb_build_object('ok',false,'msg','item '||v_id||': target '||v_tq||' exceeds available '||(coalesce(v_item_qty,0)-v_other)); end if;
  end loop;
  for t in select * from jsonb_array_elements(p_targets) loop
    v_id := t->>'item_id'; v_tq := coalesce(nullif(t->>'qty','')::numeric, 0);
    select coalesce(sum(qty),0) into v_caller from public.e10_inventory_reservations
      where item_id = v_id and show_ref is not distinct from p_show_ref and status = 'active' and organization_id = p_org
        and (v_admin or created_by = auth.uid() or (created_by is null and streamer_uid = auth.uid()::text));
    v_net := v_tq - v_caller;
    if v_net > 0 then
      insert into public.e10_inventory_reservations (item_id, show_ref, show_label, streamer_uid, qty, status, created_by, organization_id)
        values (v_id, p_show_ref, p_show_label, auth.uid()::text, v_net, 'active', auth.uid(), p_org);
      v_mid := public.e10_org_emit_inventory_movement(p_org, v_id, 'reservation', 0, v_net, p_idempotency_key||':'||v_id,
                 'set_reservations', 'reservation set', 'show', p_show_ref, 'set_reservations', null, '{}'::jsonb);
    elsif v_net < 0 then
      v_reduce := -v_net;
      for r in select id, qty from public.e10_inventory_reservations
                 where item_id = v_id and show_ref is not distinct from p_show_ref and status = 'active' and organization_id = p_org
                   and (v_admin or created_by = auth.uid() or (created_by is null and streamer_uid = auth.uid()::text))
                 order by created_at desc for update loop
        exit when v_reduce <= 0;
        v_cut := least(r.qty, v_reduce);
        if v_cut >= r.qty then update public.e10_inventory_reservations set status = 'released' where id = r.id;
        else update public.e10_inventory_reservations set qty = qty - v_cut where id = r.id; end if;
        v_reduce := v_reduce - v_cut;
      end loop;
      v_mid := public.e10_org_emit_inventory_movement(p_org, v_id, 'reservation_release', 0, v_net, p_idempotency_key||':'||v_id,
                 'set_reservations', 'reservation set', 'show', p_show_ref, 'set_reservations', null, '{}'::jsonb);
    end if;
    perform public._e10_inv_blob_write(p_org, v_id, false, v_actor);
    v_items := v_items || jsonb_build_object('item_id', v_id, 'target', v_tq, 'net', v_net, 'item', public._e10_inv_item_json(p_org, v_id));
  end loop;
  v_rev := (select rev from public.e10_workspace where id = 'shared' and organization_id = p_org);
  perform public._e10_inv_receipt_write(p_org, p_idempotency_key, 'set_reservations', null, v_fp, null);
  return jsonb_build_object('ok',true,'msg','reservations set','items',v_items,'rev',v_rev,'movement_id',null);
end; $function$;

-- ---- Entity: reverse_consumption ----
CREATE OR REPLACE FUNCTION public.e10_org_inv_reverse_consumption(p_org uuid, p_id text, p_reverses_movement_id uuid, p_idempotency_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_actor text := auth.jwt()->>'email'; v_mid uuid; v_rev bigint; v_fp text; v_rc jsonb;
        v_src record; v_meta jsonb; v_cq numeric; v_draw numeric; a jsonb; v_sess text;
        v_admin boolean := e10.is_org_admin(p_org); v_sess_owner uuid; v_sess_found boolean := false; v_item_org uuid;
begin
  if not e10.is_org_member(p_org) then raise exception 'cross_org_denied: not a member of organization %', p_org using errcode='42501'; end if;
  if not e10.has_org_cap(p_org,'act.inventory_edit') then raise exception 'e10_org_inv_reverse_consumption: missing act.inventory_edit' using errcode='42501'; end if;
  select organization_id into v_item_org from public.e10_inventory_items where id=p_id;
  if v_item_org is not null and v_item_org<>p_org then raise exception 'cross_org_denied: item % is in a different organization', p_id using errcode='42501'; end if;
  perform public._e10_inv_guard(p_org);
  if p_idempotency_key is null or btrim(p_idempotency_key) = '' then
    return jsonb_build_object('ok',false,'msg','idempotency_key required'); end if;
  perform pg_advisory_xact_lock(hashtext(p_idempotency_key));
  v_fp := md5(coalesce(p_id,'')||'|'||coalesce(p_reverses_movement_id::text,''));
  v_rc := public._e10_inv_receipt_check(p_org, p_idempotency_key, 'reverse_consumption', p_id, v_fp);
  if v_rc ? '_mismatch' then return jsonb_build_object('ok',false,'msg','idempotency key reused with different arguments'); end if;
  if v_rc is not null then return public._e10_inv_replay_json(p_org, p_id, v_rc); end if;
  select item_id, movement_type, on_hand_delta, meta, source_entity_id, actor_uid
    into v_src from public.e10_inventory_movements where id = p_reverses_movement_id and organization_id = p_org;
  if not found then return jsonb_build_object('ok',false,'msg','movement to reverse not found'); end if;
  if v_src.movement_type <> 'break_consumption' then return jsonb_build_object('ok',false,'msg','not a break consumption movement'); end if;
  if v_src.item_id is distinct from p_id then return jsonb_build_object('ok',false,'msg','movement item mismatch'); end if;
  perform 1 from public.e10_inventory_items where id = p_id and organization_id = p_org for update;
  if not found then return jsonb_build_object('ok',false,'msg','item not found'); end if;
  if v_src.source_entity_id is not null and btrim(v_src.source_entity_id) <> '' then
    begin
      select streamer_uid into v_sess_owner from public.e10_break_sessions where id = v_src.source_entity_id::uuid and organization_id = p_org;
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
      where id = p_id and organization_id = p_org;
    for a in select * from jsonb_array_elements(coalesce(v_meta->'allocation','[]'::jsonb)) loop
      insert into public.e10_inventory_reservations (item_id, show_ref, show_label, streamer_uid, qty, status, created_by, organization_id)
        values (p_id, a->>'show_ref', a->>'show_label', a->>'streamer_uid', (a->>'qty')::numeric, 'active',
                nullif(a->>'created_by','')::uuid, p_org);
    end loop;
    v_rev := public._e10_inv_blob_write(p_org, p_id, false, v_actor);
    v_mid := public.e10_org_emit_inventory_movement(p_org, p_id, 'break_reversal', v_cq, v_draw, p_idempotency_key,
               'break', 'break consumption reversed', 'break_session', v_sess, 'reverse',
               p_reverses_movement_id, jsonb_build_object('restored_qty', v_cq, 'reserved_restored', v_draw));
  exception when others then
    return jsonb_build_object('ok',false,'msg','reversal rejected: '||sqlerrm);
  end;
  perform public._e10_inv_receipt_write(p_org, p_idempotency_key, 'reverse_consumption', p_id, v_fp, v_mid);
  return jsonb_build_object('ok',true,'msg','reversed','item',public._e10_inv_item_json(p_org, p_id),'rev',v_rev,'movement_id',v_mid);
end; $function$;

-- =====================================================================================================================
-- (3) Retire the two dead legacy orphans _e10_inv_receipt / _e10_inv_replay (reference the dropped `response` column
-- since A6c.0; refcount 0). Same in-migration zero-reference proof as the seven retired in A6c.2.
-- =====================================================================================================================
do $$
declare cand record; n int;
begin
  for cand in select * from (values
      (1, 'public._e10_inv_receipt(text, text, text, jsonb)', '_e10_inv_receipt'),
      (2, 'public._e10_inv_replay(text)',                     '_e10_inv_replay')
    ) as c(ord, sig, nm) order by c.ord
  loop
    -- count references to this helper across every function body in public+e10, excluding the candidate itself.
    -- _e10_inv_replay must not match _e10_inv_replay_json (an org-aware helper we KEEP): the \( boundary after the
    -- exact name excludes the _json suffix.
    select count(*) into n
    from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
    where ns.nspname in ('public','e10') and p.prokind = 'f'
      and p.oid <> to_regprocedure(cand.sig)
      and pg_get_functiondef(p.oid) ~ ('\m'||cand.nm||'\s*\(');
    raise notice 'A6c.2.1 retire: legacy % — reference count = %', cand.sig, n;
    if n = 0 then
      execute 'drop function if exists '||cand.sig;
      raise notice 'A6c.2.1 retire: DROPPED %', cand.sig;
    else
      raise notice 'A6c.2.1 retire: KEPT % (still referenced)', cand.sig;
    end if;
  end loop;
end $$;
