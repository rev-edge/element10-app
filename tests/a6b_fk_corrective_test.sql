-- Element 10 — A6b composite-FK ON DELETE corrective proof. Self-failing, transactionally rolled back.
-- Proves (Trent's 4 requirements) that dropping the movements/receipts->items composite FKs is safe:
--   1. e10_inv_delete_item succeeds on an org0 item that has a reservation + movement + receipt;
--   2. its correction movement AND receipt SURVIVE the item deletion (no cascade of ledger history);
--   3. no cross-org item mutation can create ledger rows (the org-scoped ledger-insert trigger rejects it);
--   4. the surviving ledger rows retain organization_id AND the historical item_id.
-- The reservation IS expected to cascade away (its composite FK is now CASCADE, matching the legacy FK).
-- Run as postgres (local/CI). Uses set_config('request.jwt.claims',...) to drive the real SECURITY DEFINER RPCs.
begin;
do $$
declare
  v_org  uuid := 'e1000000-0000-4000-8000-0000000000a6'::uuid;      -- org0 (tenant-zero)
  v_orgb uuid := 'e1000000-0000-4000-8000-0000000000b7'::uuid;      -- a throwaway second org (cross-org fixture)
  v_user uuid := 'a6bfc000-0000-4000-8000-000000000001'::uuid;      -- throwaway org0 admin
  v_admin_role uuid := 'e1000000-0000-4000-8000-000000000001'::uuid;
  v_item text := '__a6bfc_item';
  v_mv int; v_rc int; v_res int;
begin
  -- provision a throwaway org0 admin member (e10_members for the legacy guard + org0 membership for current_org())
  insert into auth.users (id, instance_id, aud, role, email, created_at, updated_at)
    values (v_user, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'a6bfc@x.invalid', now(), now())
    on conflict (id) do nothing;
  insert into public.e10_members (user_id, email, role) values (v_user, 'a6bfc@x.invalid', 'admin')
    on conflict (user_id) do update set role = 'admin';
  insert into public.e10_organization_memberships (organization_id, user_id, role_id, status)
    values (v_org, v_user, v_admin_role, 'active')
    on conflict (organization_id, user_id) do update set role_id = excluded.role_id, status = 'active';
  perform set_config('request.jwt.claims', json_build_object('sub', v_user::text, 'role', 'authenticated')::text, true);

  -- (1) the real RPC flow: add -> reserve (emits movement + receipt) -> delete (emits correction movement + receipt)
  perform public.e10_inv_add_item(jsonb_build_object('id', v_item, 'name', 'A6b FK reg', 'qty', 5, 'cat', 'Box'), v_item || ':add');
  perform public.e10_inv_reserve(v_item, '__a6bfc_show', 'A6b FK Show', 2, v_item || ':res');
  perform public.e10_inv_delete_item(v_item, v_item || ':del');   -- must NOT raise

  -- (1) delete succeeded
  if exists (select 1 from public.e10_inventory_items where id = v_item) then
    raise exception 'FAIL(1): e10_inv_delete_item did not delete the item';
  end if;
  -- reservation cascaded away (composite FK now CASCADE)
  select count(*) into v_res from public.e10_inventory_reservations where item_id = v_item;
  if v_res <> 0 then raise exception 'FAIL: reservation did not cascade (got %)', v_res; end if;
  -- (2)+(4) correction movement + receipt survive, retaining organization_id AND the historical item_id
  select count(*) into v_mv from public.e10_inventory_movements where item_id = v_item and organization_id = v_org;
  select count(*) into v_rc from public.e10_mutation_receipts   where item_id = v_item and organization_id = v_org;
  if v_mv < 1 then raise exception 'FAIL(2/4): no surviving movement with org+item_id (got %)', v_mv; end if;
  if v_rc < 1 then raise exception 'FAIL(2/4): no surviving receipt with org+item_id (got %)', v_rc; end if;

  -- (3) cross-org: as the org0 member, a movement referencing an OrgB item must be rejected by the ledger trigger.
  insert into public.e10_organizations (id, name, slug) values (v_orgb, 'A6b FK OrgB', 'a6bfc-orgb') on conflict do nothing;
  insert into public.e10_inventory_items (id, name, qty, organization_id) values ('__a6bfc_bitem', 'OrgB item', 1, v_orgb);
  begin
    -- no explicit organization_id: the bridge stamps org0 (the caller's org); the item is OrgB => must be rejected
    insert into public.e10_inventory_movements (workspace_id, item_id, movement_type, on_hand_delta, idempotency_key)
      values ('shared', '__a6bfc_bitem', 'correction', -1, '__a6bfc_xorg');
    raise exception 'FAIL(3): cross-org ledger insert was NOT rejected';
  exception when sqlstate '42501' then
    null; -- expected: e10.assert_ledger_item_org() raised 42501
  end;
  if exists (select 1 from public.e10_inventory_movements where item_id = '__a6bfc_bitem') then
    raise exception 'FAIL(3): a cross-org movement row exists';
  end if;

  raise notice 'A6b FK corrective proof: PASS (delete ok; % movement(s) + % receipt(s) survived with org+item_id; reservation cascaded; cross-org insert rejected)', v_mv, v_rc;
end $$;
rollback;
