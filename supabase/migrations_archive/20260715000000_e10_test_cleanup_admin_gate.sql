-- Migration: e10_test_cleanup_admin_gate  (Chain P — P0)
-- e10_test_cleanup deletes append-only LEDGER rows + receipts for a caller-supplied 'zz' prefix (and
-- caller-supplied item ids). Member-callable, that is a side door through the append-only invariant.
-- Gate it to admins only. ADDITIVE (CREATE OR REPLACE of one function); ZERO rows; no signature change.
create or replace function public.e10_test_cleanup(p_prefix text, p_session_ids uuid[] default null)
  returns jsonb language plpgsql security definer set search_path to 'public' as $$
begin
  if not (select public.e10_is_admin()) then
    raise exception 'e10_test_cleanup: admin only' using errcode = '42501';
  end if;
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

-- Rollback: CREATE OR REPLACE the prior body (the leading admin check replaced by `perform
-- public._e10_inv_guard();`). No table touch, no data change.
