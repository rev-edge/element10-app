-- Element 10 — STEP8: bounded inventory reads (filtered, keyset-paginated) + bounded movement history.
-- Replaces the unbounded e10_org_inv_list / e10_inv_list (whole-catalog jsonb_agg) with a keyset-paginated, server-side-
-- filtered page RPC, and adds a keyset-paginated org-scoped movement-history RPC (built bounded from t0; there was no
-- prior history RPC). Follows the A6c.2 pattern exactly: an org-aware SECURITY DEFINER delegate that authorizes
-- internally (is_org_member -> 42501), plus a thin wrapper that forwards e10.current_org(). The 9 mutation delegates,
-- the 55 A6c.1 RLS policy predicates, and the ledger FK contract (no ledger->items FK) are UNTOUCHED.
--
-- Keyset keys (proven stable+unique on staging): items = id (UNIQUE (organization_id,id)); movements =
-- (created_at desc, id desc) with id the globally-unique PK breaking ties. No OFFSET anywhere. History filters by
-- organization_id (authorization) with an OPTIONAL item_id column filter (plain retained column, no FK, valid for
-- hard-deleted items — the A6b/A7 frozen behavior). p_limit is clamped so the bound cannot be widened by the caller.

-- =====================================================================================================================
-- 1) Catalog page — delegate
-- =====================================================================================================================
create or replace function public.e10_org_inv_page(
  p_org uuid, p_after text default null, p_limit int default 100, p_filters jsonb default '{}'::jsonb)
  returns jsonb language plpgsql stable security definer set search_path to 'public' as $fn$
declare v_lim int := least(greatest(coalesce(p_limit,100), 1), 500);   -- clamp [1,500]; the bound cannot be widened
        v_ids text[]; v_items jsonb; v_next text; v_more boolean;
begin
  if not e10.is_org_member(p_org) then raise exception 'cross_org_denied: not a member of organization %', p_org using errcode='42501'; end if;
  -- keyset page over ids (order by id; id > cursor); fetch v_lim+1 to detect has_more. Filters are server-side.
  select array_agg(id order by id) into v_ids from (
    select it.id from public.e10_inventory_items it
    where it.organization_id = p_org
      and (p_after is null or it.id > p_after)
      and (p_filters->>'cat'   is null or it.cat       = p_filters->>'cat')
      and (p_filters->>'set'   is null or it.card_set  = p_filters->>'set')
      and (p_filters->>'year'  is null or it.year      = p_filters->>'year')
      and (p_filters->>'grade' is null or it.grade     = p_filters->>'grade')
      and (p_filters->>'q'     is null or it.name ilike '%'||(p_filters->>'q')||'%')
    order by it.id
    limit v_lim + 1
  ) k;
  v_ids := coalesce(v_ids, array[]::text[]);
  v_more := array_length(v_ids,1) > v_lim;
  if v_more then v_ids := v_ids[1:v_lim]; end if;
  v_next := case when array_length(v_ids,1) > 0 then v_ids[array_length(v_ids,1)] else null end;
  select coalesce(jsonb_agg(public._e10_inv_item_json(p_org, id) order by id), '[]'::jsonb)
    into v_items from unnest(v_ids) as id;
  return jsonb_build_object('items', v_items, 'next_cursor', case when v_more then v_next else null end, 'has_more', coalesce(v_more,false));
end; $fn$;

-- Catalog page — thin wrapper (forwards current_org())
create or replace function public.e10_inv_page(
  p_after text default null, p_limit int default 100, p_filters jsonb default '{}'::jsonb)
  returns jsonb language sql stable security definer set search_path to 'public'
as $fn$ select public.e10_org_inv_page(e10.current_org(), p_after, p_limit, p_filters); $fn$;

-- =====================================================================================================================
-- 2) Movement history — delegate (org-scoped; optional item_id; keyset newest-first)
-- =====================================================================================================================
create or replace function public.e10_org_inv_history(
  p_org uuid, p_after_created timestamptz default null, p_after_id uuid default null,
  p_limit int default 100, p_item_id text default null)
  returns jsonb language plpgsql stable security definer set search_path to 'public' as $fn$
declare v_lim int := least(greatest(coalesce(p_limit,100), 1), 500);
        r record; v_arr jsonb := '[]'::jsonb; v_n int := 0; v_more boolean := false;
        v_next_created timestamptz := null; v_next_id uuid := null;
begin
  if not e10.is_org_member(p_org) then raise exception 'cross_org_denied: not a member of organization %', p_org using errcode='42501'; end if;
  -- fetch one extra row to detect has_more; keyset newest-first on (created_at desc, id desc).
  for r in
    select m.id, m.item_id, m.movement_type, m.on_hand_delta, m.reserved_delta, m.reason_code, m.note,
           m.source_entity_type, m.source_entity_id, m.source_action, m.actor_uid, m.created_at, m.meta
    from public.e10_inventory_movements m
    where m.organization_id = p_org
      and (p_item_id is null or m.item_id = p_item_id)
      and (p_after_created is null or (m.created_at, m.id) < (p_after_created, p_after_id))
    order by m.created_at desc, m.id desc
    limit v_lim + 1
  loop
    if v_n = v_lim then v_more := true; exit; end if;              -- the (v_lim+1)th row only signals has_more
    v_arr := v_arr || to_jsonb(r);
    v_next_created := r.created_at; v_next_id := r.id;             -- last kept row = the cursor for the next page
    v_n := v_n + 1;
  end loop;
  return jsonb_build_object(
    'movements', v_arr,
    'next_created', case when v_more then v_next_created else null end,
    'next_id',      case when v_more then v_next_id      else null end,
    'has_more', v_more);
end; $fn$;

-- Movement history — thin wrapper
create or replace function public.e10_inv_history(
  p_after_created timestamptz default null, p_after_id uuid default null,
  p_limit int default 100, p_item_id text default null)
  returns jsonb language sql stable security definer set search_path to 'public'
as $fn$ select public.e10_org_inv_history(e10.current_org(), p_after_created, p_after_id, p_limit, p_item_id); $fn$;

-- =====================================================================================================================
-- 3) ACL — born-locked, mirroring the A6c.0 delegate matrix: authenticated + service_role on the client delegates+
--    wrappers; nothing else. (default privileges already revoke PUBLIC/anon.)
-- =====================================================================================================================
revoke all on function public.e10_org_inv_page(uuid,text,int,jsonb)              from public;
revoke all on function public.e10_inv_page(text,int,jsonb)                       from public;
revoke all on function public.e10_org_inv_history(uuid,timestamptz,uuid,int,text) from public;
revoke all on function public.e10_inv_history(timestamptz,uuid,int,text)          from public;
grant execute on function public.e10_org_inv_page(uuid,text,int,jsonb)               to authenticated, service_role;
grant execute on function public.e10_inv_page(text,int,jsonb)                        to authenticated, service_role;
grant execute on function public.e10_org_inv_history(uuid,timestamptz,uuid,int,text) to authenticated, service_role;
grant execute on function public.e10_inv_history(timestamptz,uuid,int,text)          to authenticated, service_role;

-- =====================================================================================================================
-- 4) RETIRE the unbounded contract (§3.5 — no quiet fallback). The client is updated to e10_inv_page in the same
--    change; any other deployed client MUST switch to e10_inv_page before this reaches its database.
-- =====================================================================================================================
drop function if exists public.e10_inv_list();
drop function if exists public.e10_org_inv_list(uuid);
