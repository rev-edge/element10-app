-- Element 10 — A6c.2 wrapper-cutover + mechanic-relocation gate. Self-failing; transactionally rolled back.
-- Proves the RELOCATED delegates are the mechanism and enforce org boundaries, and that the legacy wrappers now
-- forward through e10.current_org() (the cutover path). Raised proof standard:
--   * every denial asserts its SPECIFIC SQLSTATE (42501); `exception when others` is NEVER used to swallow a denial —
--     any non-42501 error is recorded as a distinct *_wrongerr failure (a different layer firing first is a defect).
--   * each denial notes which other layer (FK / trigger / constraint / RLS) could plausibly fire first and why it can't.
-- Fixtures are built as the privileged migration role (RLS bypassed); assertions run under per-user JWT claims so
-- auth.uid()/e10.current_org()/e10.is_org_member/e10.has_org_cap resolve to the acting identity. The delegates are
-- SECURITY DEFINER, so authorization here is enforced by the delegates' explicit guards, not by RLS.
begin;

-- ---------- fixtures ----------
do $$
declare
  v_orgA uuid := 'e1000000-0000-4000-8000-0000000000a6';          -- org0
  v_orgB uuid := 'e1000000-0000-4000-8000-0000000000c2';          -- a second org
  v_adminrole uuid := 'e1000000-0000-4000-8000-000000000001';     -- org0 admin role (has act.inventory_edit)
  v_opsrole uuid;                                                  -- org0 ops role (lacks act.inventory_edit)
  v_brole uuid;                                                    -- orgB admin role
  v_admin uuid := 'a6c22222-0000-4000-8000-00000000000a';         -- orgA admin (full inventory cap)
  v_ops   uuid := 'a6c22222-0000-4000-8000-00000000000b';         -- orgA member WITHOUT act.inventory_edit
  v_multi uuid := 'a6c22222-0000-4000-8000-00000000000c';         -- member of BOTH orgA and orgB (current_org -> null)
begin
  insert into public.e10_organizations(id,name,slug) values (v_orgB,'A6c2 OrgB','a6c2-orgb') on conflict do nothing;
  select id into v_brole from public.e10_organization_roles where organization_id=v_orgB and key='admin';
  if v_brole is null then insert into public.e10_organization_roles(organization_id,key,name) values (v_orgB,'admin','Admin') returning id into v_brole; end if;
  select id into v_opsrole from public.e10_organization_roles where organization_id=v_orgA and key='ops';

  insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at)
    select u,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',replace(u::text,'-','')||'@a6c2.invalid',now(),now()
    from unnest(array[v_admin,v_ops,v_multi]) u on conflict (id) do nothing;
  insert into public.e10_members(user_id,email,role) values
    (v_admin,'a6c2adm@x','admin'),(v_ops,'a6c2ops@x','member'),(v_multi,'a6c2multi@x','admin')
    on conflict (user_id) do update set role=excluded.role;
  insert into public.e10_organization_memberships(organization_id,user_id,role_id,status) values
    (v_orgA,v_admin,v_adminrole,'active'),
    (v_orgA,v_ops,coalesce(v_opsrole,v_adminrole),'active'),
    (v_orgA,v_multi,v_adminrole,'active'),
    (v_orgB,v_multi,v_brole,'active')                             -- second active membership => current_org() null
    on conflict (organization_id,user_id) do update set role_id=excluded.role_id,status='active';

  -- a REAL, FK-valid item in orgB. The cross-org Entity assertion targets it, so the row genuinely exists (no
  -- not-found path) and only the delegate's item-org check can refuse the orgA caller.
  insert into public.e10_inventory_items(id,name,qty,organization_id) values ('__a6c2_bitem','B',5,v_orgB);
  -- an orgA session owned by v_admin; v_ops is a member but NOT the owner (buyer_suggest non-owner case).
  insert into public.e10_break_sessions(id,organization_id,streamer_uid,share_code,visibility) values
    ('a6c20000-0000-4000-8000-0000000000f1'::uuid,v_orgA,v_admin,'__a6c2_sess','private');
end $$;

-- ---------- assertions ----------
do $$
declare
  v_orgA uuid := 'e1000000-0000-4000-8000-0000000000a6'; v_orgB uuid := 'e1000000-0000-4000-8000-0000000000c2';
  v_admin uuid := 'a6c22222-0000-4000-8000-00000000000a'; v_ops uuid := 'a6c22222-0000-4000-8000-00000000000b';
  v_multi uuid := 'a6c22222-0000-4000-8000-00000000000c';
  v_sess uuid := 'a6c20000-0000-4000-8000-0000000000f1';
  r jsonb; ok int:=0; bad text:='';
begin
  -- ============ 1) cross-org ENTITY mutation denied (relocated delegate guard) ============
  -- v_admin is a member of orgA; __a6c2_bitem lives in orgB. e10_org_inv_edit_item(orgA, itemB,...) derives the item's
  -- org (orgB) and rejects the mismatch with 42501. Layer analysis: SECURITY DEFINER bypasses RLS; no FK/constraint is
  -- touched (a pure edit of an existing row); the movement/receipt inserts are never reached. => ONLY the delegate's
  -- explicit `cross_org_denied: item ... is in a different organization` guard can fire. Require 42501 exactly.
  perform set_config('request.jwt.claims', json_build_object('sub',v_admin::text,'role','authenticated')::text, true);
  begin
    perform public.e10_org_inv_edit_item(v_orgA,'__a6c2_bitem',jsonb_build_object('name','x'),'__a6c2_xedit',null);
    bad:=bad||' xorg_entity_allowed';
  exception
    when sqlstate '42501' then ok:=ok+1;
    when others then bad:=bad||(' xorg_entity_wrongerr:'||SQLSTATE);
  end;

  -- ============ 2) missing-capability denied (relocated delegate guard) ============
  -- v_ops is a member of orgA but the ops role lacks act.inventory_edit. e10_org_inv_add_item passes is_org_member but
  -- fails has_org_cap and raises 42501 BEFORE any row is written. Layer analysis: no unique/NOT-NULL/FK can fire because
  -- no INSERT is reached; RLS bypassed (SECDEF). => ONLY the has_org_cap guard fires. Require 42501 exactly.
  perform set_config('request.jwt.claims', json_build_object('sub',v_ops::text,'role','authenticated')::text, true);
  begin
    perform public.e10_org_inv_add_item(v_orgA, jsonb_build_object('id','__a6c2_ncap','name','N','qty',1,'cat','Box'), '__a6c2_ncap');
    bad:=bad||' misscap_allowed';
  exception
    when sqlstate '42501' then ok:=ok+1;
    when others then bad:=bad||(' misscap_wrongerr:'||SQLSTATE);
  end;

  -- ============ 3) multi-membership FAILS CLOSED on a cutover path ============
  -- v_multi has two active memberships => e10.current_org() returns null. The LEGACY wrapper e10_inv_add_item (now a thin
  -- delegator) forwards e10_org_inv_add_item(null, ...); e10.is_org_member(null) is false => 42501. This exercises the
  -- cutover wiring end to end. Layer analysis: the null org can never satisfy is_org_member, and no INSERT is reached, so
  -- no FK/constraint precedes it. Require 42501 exactly.
  perform set_config('request.jwt.claims', json_build_object('sub',v_multi::text,'role','authenticated')::text, true);
  if e10.current_org() is null then ok:=ok+1; else bad:=bad||' multi_current_org_not_null'; end if;
  begin
    perform public.e10_inv_add_item(jsonb_build_object('id','__a6c2_multi','name','M','qty',1,'cat','Box'), '__a6c2_multi');
    bad:=bad||' multi_allowed';
  exception
    when sqlstate '42501' then ok:=ok+1;
    when others then bad:=bad||(' multi_wrongerr:'||SQLSTATE);
  end;

  -- ============ 4) deleted-item ledger read SUCCEEDS on the relocated delete path (ledger has no item dependency) ============
  -- As v_admin (full cap in orgA): add an item (intake movement), then delete it (correction movement + item row gone).
  -- The correction movement must remain readable, org-scoped, with the item row deleted. Proves the relocated
  -- delete_item emits e10_org_emit_inventory_movement(orgA,...) and the movements ledger keeps no FK to items.
  perform set_config('request.jwt.claims', json_build_object('sub',v_admin::text,'role','authenticated')::text, true);
  r := public.e10_org_inv_add_item(v_orgA, jsonb_build_object('id','__a6c2_del','name','D','qty',3,'cat','Box'), '__a6c2_del_add');
  if (r->>'ok')::boolean then ok:=ok+1; else bad:=bad||' del_add_failed'; end if;
  r := public.e10_org_inv_delete_item(v_orgA,'__a6c2_del','__a6c2_del_rm');
  if (r->>'ok')::boolean then ok:=ok+1; else bad:=bad||' del_failed'; end if;
  if (select count(*) from public.e10_inventory_movements
        where item_id='__a6c2_del' and organization_id=v_orgA and movement_type='correction')=1
     and (select count(*) from public.e10_inventory_items where id='__a6c2_del')=0
    then ok:=ok+1; else bad:=bad||' deleted_ledger'; end if;

  -- ============ 5) buyer_suggest NON-OWNER denied (relocated behind owns_session) ============
  -- v_ops is an orgA member but NOT the owner of v_sess (streamer_uid = v_admin). The relocated e10_org_buyer_suggest
  -- raises 42501 rather than the legacy silent '[]'. Layer analysis: STABLE SECURITY DEFINER; the CTE is never executed
  -- because the owns_session guard raises first; no table constraint is involved. Require 42501 exactly.
  perform set_config('request.jwt.claims', json_build_object('sub',v_ops::text,'role','authenticated')::text, true);
  begin
    perform public.e10_org_buyer_suggest(v_sess,'');
    bad:=bad||' buyer_nonowner_allowed';
  exception
    when sqlstate '42501' then ok:=ok+1;
    when others then bad:=bad||(' buyer_nonowner_wrongerr:'||SQLSTATE);
  end;

  -- ============ 6) redeem_code invalid-code returns NULL (behavior-preserving; no viewer created) ============
  -- Not a denial (no exception): an unknown share_code yields null and inserts no session_viewer. Layer analysis: none —
  -- the function returns null before any INSERT.
  perform set_config('request.jwt.claims', json_build_object('sub',v_admin::text,'role','authenticated')::text, true);
  if public.e10_org_redeem_code('__a6c2_bogus_code') is null then ok:=ok+1; else bad:=bad||' redeem_invalid_not_null'; end if;

  if ok = 9 then raise notice 'A6c.2 cutover gate: PASS (cross-org entity, missing-cap, multi-membership fail-closed, deleted-item ledger, buyer non-owner, redeem-null — all with specific SQLSTATEs)';
  else raise exception 'A6c.2 cutover gate: FAIL passed=%/9 failures=[%]', ok, bad; end if;
end $$;
rollback;
