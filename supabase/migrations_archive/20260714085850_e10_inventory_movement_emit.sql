-- Migration: e10_inventory_movement_emit  (Pass 2.6 — movement-emitter RPC)
-- Server foundation for Passes 2.7 (intake/adjustment), 2.8 (reservation/release),
-- and 2.9 (break consumption/reversal). ADDITIVE ONLY. Inserts ZERO rows.
--
-- Builds:
--   1. public.e10_emit_inventory_movement(...)  — the single idempotent, RLS-gated,
--      append-only emit RPC every future UI pass calls.
--   2. imov_ins                                 — one additive INSERT policy (emit-context gated).
--   3. e10_invmov_reverses_uk                   — unique partial index: a movement is reversed at most once.
--   4. public.e10_inventory_reserved_recon      — Pass 2.8 reconciliation view (report-only).
--
-- The JSONB workspace (e10_workspace 'shared') remains the production source of truth.
-- This RPC RECORDS movements; it does not drive inventory, reservations, cost, or availability.

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. The emit RPC.
--    SECURITY DEFINER (runs as owner `postgres`, which BYPASSRLS) — therefore the
--    RPC CANNOT lean on RLS to keep non-members out; it re-checks membership and the
--    act.inventory_edit capability itself. actor_uid and owner_ref are stamped
--    server-side and are NOT accepted from the caller.
create or replace function public.e10_emit_inventory_movement(
  p_item_id              text,
  p_movement_type        text,
  p_on_hand_delta        numeric default 0,
  p_reserved_delta       numeric default 0,
  p_idempotency_key      text    default null,
  p_reason_code          text    default null,
  p_note                 text    default null,
  p_source_entity_type   text    default null,
  p_source_entity_id     text    default null,
  p_source_action        text    default null,
  p_reverses_movement_id uuid    default null,
  p_meta                 jsonb   default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path to 'public'
as $$
declare
  v_oh       numeric := coalesce(p_on_hand_delta, 0);
  v_rd       numeric := coalesce(p_reserved_delta, 0);
  v_existing uuid;
  v_owner    text;
  v_new      uuid;
  v_rev      record;
begin
  -- (1) Membership gate. SECURITY DEFINER bypasses RLS, so this is THE gate, not the policy.
  if not (select public.e10_is_member()) then
    raise exception 'e10_emit_inventory_movement: caller is not a member'
      using errcode = '42501';
  end if;

  -- (2) Capability gate, mirroring the INSERT policy predicate. Default-allow (0 permission rows).
  if not (select public.e10_has_cap('act.inventory_edit')) then
    raise exception 'e10_emit_inventory_movement: missing capability act.inventory_edit'
      using errcode = '42501';
  end if;

  -- (3) Idempotency key is the contract, not the caller's problem to reconcile later.
  if p_idempotency_key is null or btrim(p_idempotency_key) = '' then
    raise exception 'e10_emit_inventory_movement: idempotency_key is required'
      using errcode = '22004';
  end if;

  -- (4) Replay fast-path. A key already on the ledger returns its id and re-runs NO
  --     validation — critically, it does NOT re-run the double-reversal guard against
  --     the row this very key already wrote. N retries -> one row, one stable id.
  select id into v_existing
    from public.e10_inventory_movements
   where idempotency_key = p_idempotency_key;
  if found then
    return v_existing;
  end if;

  -- (5) Item id required (the JSONB item id; the item is not relational, so no FK).
  if p_item_id is null or btrim(p_item_id) = '' then
    raise exception 'e10_emit_inventory_movement: p_item_id is required'
      using errcode = '22004';
  end if;

  -- (6) Movement-type validity. opening_balance is migration-only.
  if p_movement_type = 'opening_balance' then
    raise exception 'e10_emit_inventory_movement: opening_balance is migration-only'
      using errcode = '22023';
  end if;
  if p_movement_type is null or p_movement_type not in (
       'intake','manual_increase','manual_decrease','correction','reservation',
       'reservation_release','break_consumption','break_reversal','sale','return',
       'transfer','loss_damage') then
    raise exception 'e10_emit_inventory_movement: invalid movement_type %',
      coalesce(p_movement_type, '<null>') using errcode = '22023';
  end if;

  -- (7) No-op guard. A zero/zero delta records nothing (no row, null id).
  if v_oh = 0 and v_rd = 0 then
    return null;
  end if;

  -- (8) Structural sign/type coherence. Deltas are INDEPENDENT and signed; never
  --     collapsed into an available figure, never inferred one from the other.
  case p_movement_type
    when 'intake' then
      if not (v_oh > 0 and v_rd = 0) then
        raise exception 'intake requires on_hand_delta>0 and reserved_delta=0' using errcode = '22023';
      end if;
    when 'manual_increase' then
      if not (v_oh > 0 and v_rd = 0) then
        raise exception 'manual_increase requires on_hand_delta>0 and reserved_delta=0' using errcode = '22023';
      end if;
    when 'return' then
      if not (v_oh > 0 and v_rd = 0) then
        raise exception 'return requires on_hand_delta>0 and reserved_delta=0' using errcode = '22023';
      end if;
    when 'manual_decrease' then
      if not (v_oh < 0 and v_rd = 0) then
        raise exception 'manual_decrease requires on_hand_delta<0 and reserved_delta=0' using errcode = '22023';
      end if;
    when 'sale' then
      if not (v_oh < 0 and v_rd <= 0) then
        raise exception 'sale requires on_hand_delta<0 and reserved_delta<=0' using errcode = '22023';
      end if;
    when 'loss_damage' then
      if not (v_oh < 0 and v_rd <= 0) then
        raise exception 'loss_damage requires on_hand_delta<0 and reserved_delta<=0' using errcode = '22023';
      end if;
    when 'break_consumption' then
      if not (v_oh < 0 and v_rd <= 0) then
        raise exception 'break_consumption requires on_hand_delta<0 and reserved_delta<=0' using errcode = '22023';
      end if;
    when 'reservation' then
      if not (v_oh = 0 and v_rd > 0) then
        raise exception 'reservation requires on_hand_delta=0 and reserved_delta>0' using errcode = '22023';
      end if;
    when 'reservation_release' then
      if not (v_oh = 0 and v_rd < 0) then
        raise exception 'reservation_release requires on_hand_delta=0 and reserved_delta<0' using errcode = '22023';
      end if;
    when 'break_reversal' then
      if p_reverses_movement_id is null then
        raise exception 'break_reversal requires reverses_movement_id' using errcode = '22023';
      end if;
      if not (v_oh > 0 and v_rd >= 0) then
        raise exception 'break_reversal requires on_hand_delta>0 and reserved_delta>=0' using errcode = '22023';
      end if;
    else
      -- correction, transfer: any non-zero delta combination is legitimate.
      null;
  end case;

  -- (9) Reversal guard for ANY movement carrying a reverses pointer.
  if p_reverses_movement_id is not null then
    select id, workspace_id, movement_type
      into v_rev
      from public.e10_inventory_movements
     where id = p_reverses_movement_id;
    if not found then
      raise exception 'reverses_movement_id % does not exist', p_reverses_movement_id using errcode = '23503';
    end if;
    if v_rev.workspace_id <> 'shared' then
      raise exception 'reverses_movement_id % is in a different workspace', p_reverses_movement_id using errcode = '22023';
    end if;
    if v_rev.movement_type = 'opening_balance' then
      raise exception 'an opening_balance cannot be reversed' using errcode = '22023';
    end if;
    -- App-level double-reversal guard (the unique partial index below is the DB-level backstop).
    if exists (select 1 from public.e10_inventory_movements where reverses_movement_id = p_reverses_movement_id) then
      raise exception 'movement % has already been reversed', p_reverses_movement_id using errcode = '23505';
    end if;
  end if;

  -- (10) owner_ref is DERIVED from the item, never from client input. Null for a
  --      throwaway/unknown id is fine (owner_ref is nullable).
  select (i->>'owner')
    into v_owner
    from public.e10_workspace w,
         lateral jsonb_array_elements(w.data->'inventory') i
   where w.id = 'shared' and i->>'id' = p_item_id
   limit 1;

  -- (11) Mark emit context so the INSERT policy admits this write even if the RPC ever
  --      stops bypassing RLS (e.g. ownership change). Transaction-local; a direct client
  --      insert never sets it, so a raw insert is denied by imov_ins.
  perform set_config('e10.emit', 'on', true);

  -- (12) Idempotent append. Concurrent same-key callers collapse to a single row.
  insert into public.e10_inventory_movements (
    workspace_id, item_id, owner_ref, movement_type,
    on_hand_delta, reserved_delta, cost_basis,
    source_entity_type, source_entity_id, source_action,
    actor_uid, reason_code, note, idempotency_key,
    reverses_movement_id, migration_version, meta
  )
  values (
    'shared', p_item_id, v_owner, p_movement_type,
    v_oh, v_rd, null,
    p_source_entity_type, p_source_entity_id, p_source_action,
    auth.uid(), p_reason_code, p_note, p_idempotency_key,
    p_reverses_movement_id, null, coalesce(p_meta, '{}'::jsonb)
  )
  on conflict (idempotency_key) do nothing
  returning id into v_new;

  if v_new is null then
    -- Lost a race to a concurrent identical-key insert; return the row it committed.
    select id into v_new
      from public.e10_inventory_movements
     where idempotency_key = p_idempotency_key;
  end if;

  return v_new;
end;
$$;

-- Lock down execution: revoke from public AND anon explicitly (Supabase ALTER DEFAULT
-- PRIVILEGES grants EXECUTE to anon directly, so REVOKE ... FROM public does not remove it).
revoke all on function public.e10_emit_inventory_movement(
  text, text, numeric, numeric, text, text, text, text, text, text, uuid, jsonb
) from public, anon;
grant execute on function public.e10_emit_inventory_movement(
  text, text, numeric, numeric, text, text, text, text, text, text, uuid, jsonb
) to authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Additive INSERT policy. imov_sel (member read) is untouched; no UPDATE, no
--    DELETE policy is added — the table stays append-only. Predicates InitPlan-wrapped.
--    The emit-context clause means only the RPC path may write; a direct client insert
--    (which never sets e10.emit) is rejected with 42501.
create policy imov_ins on public.e10_inventory_movements
  for insert to authenticated
  with check (
        (select public.e10_is_member())
    and (select public.e10_has_cap('act.inventory_edit'))
    and coalesce(current_setting('e10.emit', true), '') = 'on'
  );

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. DB-level single-reversal guarantee: a given movement can be reversed at most once.
--    Additive; no existing row carries reverses_movement_id, so this cannot conflict.
create unique index if not exists e10_invmov_reverses_uk
  on public.e10_inventory_movements (reverses_movement_id)
  where reverses_movement_id is not null;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. Pass 2.8 reconciliation view — ledger-derived reserved totals per item vs. the
--    JSONB reservations array. REPORT ONLY: it writes, corrects, reconciles nothing.
--    security_invoker => runs under the querying member's RLS (member-read on both the
--    ledger and the workspace), matching the e10_checklist_facet SECURITY INVOKER precedent.
create or replace view public.e10_inventory_reserved_recon
  with (security_invoker = true) as
  with jsonb_res as (
    select i->>'id'                                    as item_id,
           max(i->>'name')                             as item_name,
           coalesce(sum((r->>'qty')::numeric), 0)      as reserved_jsonb
      from public.e10_workspace w,
           jsonb_array_elements(w.data->'inventory') i
      left join lateral jsonb_array_elements(coalesce(i->'reservations', '[]'::jsonb)) r on true
     where w.id = 'shared'
     group by i->>'id'
  ),
  ledger_res as (
    select item_id, sum(reserved_delta) as reserved_ledger
      from public.e10_inventory_movements
     where workspace_id = 'shared'
     group by item_id
  )
  select coalesce(j.item_id, l.item_id)                              as item_id,
         j.item_name,
         coalesce(j.reserved_jsonb, 0)                               as reserved_jsonb,
         coalesce(l.reserved_ledger, 0)                              as reserved_ledger,
         coalesce(l.reserved_ledger, 0) - coalesce(j.reserved_jsonb, 0) as drift
    from jsonb_res j
    full outer join ledger_res l on l.item_id = j.item_id;

revoke all on public.e10_inventory_reserved_recon from anon;
grant select on public.e10_inventory_reserved_recon to authenticated;
