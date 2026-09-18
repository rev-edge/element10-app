-- Element 10 — A7 hostile two-organization matrix gate. Self-failing; transactionally rolled back.
-- Proves docs/A7_HOSTILE_MATRIX.md: hostile identity classes are refused across every census family, and the legitimate
-- identity is allowed, under REAL authenticated JWTs (set role authenticated + request.jwt.claims.sub) — never definer.
-- Consolidates the cross-org / special-identity crossings A7 owns; the intra-family axes proven exhaustively by prior
-- gates are cited in the matrix doc. Proof standard: specific SQLSTATE (42501/23505) or exact ok:false msg for raised
-- refusals; exact count / row-count for RLS USING/visibility denials (unshadowable); per-assertion layer notes; no
-- `when others` except as a *_wrongerr recorder. A7 is PROOFS ONLY — a gap is a FINDING (raised at the end), not a fix.
begin;

-- ---------- fixtures (migration role; RLS bypassed) ----------
do $$
declare
  v_orgA uuid := 'e1000000-0000-4000-8000-0000000000a6';         -- org0
  v_orgB uuid := 'e1000000-0000-4000-8000-0000000000b7';         -- adversary org
  v_admrole_A uuid := 'e1000000-0000-4000-8000-000000000001';    -- orgA admin
  v_mgrrole_A uuid := 'e1000000-0000-4000-8000-000000000002';    -- orgA manager (has act.inventory_edit, not admin)
  v_opsrole_A uuid := 'e1000000-0000-4000-8000-000000000004';    -- orgA ops (no cap)
  v_brole uuid; v_bmemrole uuid;
  A_mem  uuid := 'a7000000-0000-4000-8000-00000000000a';         -- orgA member+cap; streamer
  A_nocap uuid := 'a7000000-0000-4000-8000-00000000000b';        -- orgA member, no cap
  A_admin uuid := 'a7000000-0000-4000-8000-00000000000c';        -- orgA admin
  B_mem  uuid := 'a7000000-0000-4000-8000-00000000000d';         -- orgB member+cap (attacker)
  v_multi uuid := 'a7000000-0000-4000-8000-00000000000e';        -- member of BOTH => current_org() null
  v_padmin uuid := 'a7000000-0000-4000-8000-00000000000f';       -- platform admin
  V_part uuid := 'a7000000-0000-4000-8000-000000000010';         -- participant, non-member
  BU     uuid := 'a7000000-0000-4000-8000-000000000011';         -- buyer_uid, non-member
  H      uuid := 'a7000000-0000-4000-8000-000000000012';         -- verified-handle, non-member
  v_noorg uuid := 'a7000000-0000-4000-8000-000000000013';        -- no membership
begin
  insert into public.e10_organizations(id,name,slug) values (v_orgB,'A7 OrgB','a7-orgb') on conflict do nothing;
  select id into v_brole from public.e10_organization_roles where organization_id=v_orgB and key='admin';
  if v_brole is null then insert into public.e10_organization_roles(organization_id,key,name) values (v_orgB,'admin','Admin') returning id into v_brole; end if;
  insert into public.e10_organization_roles(organization_id,key,name) values (v_orgB,'member','Member') returning id into v_bmemrole;
  insert into public.e10_organization_role_permissions(organization_id,role_id,capability,allowed) values (v_orgB,v_bmemrole,'act.inventory_edit',true);
  insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at)
    select u,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',replace(u::text,'-','')||'@a7.invalid',now(),now()
    from unnest(array[A_mem,A_nocap,A_admin,B_mem,v_multi,v_padmin,V_part,BU,H,v_noorg]) u on conflict (id) do nothing;
  insert into public.e10_members(user_id,email,role) values
    (A_mem,'am@x','member'),(A_nocap,'an@x','member'),(A_admin,'aa@x','admin'),(B_mem,'bm@x','member'),(v_multi,'mu@x','admin')
    on conflict (user_id) do update set role=excluded.role;
  insert into public.e10_organization_memberships(organization_id,user_id,role_id,status) values
    (v_orgA,A_mem,v_mgrrole_A,'active'),(v_orgA,A_nocap,v_opsrole_A,'active'),(v_orgA,A_admin,v_admrole_A,'active'),
    (v_orgB,B_mem,v_bmemrole,'active'),
    (v_orgA,v_multi,v_admrole_A,'active'),(v_orgB,v_multi,v_brole,'active')
    on conflict (organization_id,user_id) do update set role_id=excluded.role_id,status='active';
  insert into public.e10_platform_admins(user_id) values (v_padmin) on conflict do nothing;

  -- F1/F2 inventory + ledger-outlives-items (orgA)
  insert into public.e10_inventory_items(id,name,qty,organization_id) values ('__a7_itemA','A',5,v_orgA);
  insert into public.e10_inventory_items(id,name,qty,organization_id) values ('__a7_del','D',1,v_orgA);
  insert into public.e10_inventory_movements(workspace_id,item_id,movement_type,on_hand_delta,idempotency_key,organization_id)
    values ('shared','__a7_del','correction',-1,'__a7_delmv',v_orgA);
  delete from public.e10_inventory_items where id='__a7_del';       -- item gone; correction movement survives (no FK)

  -- F3 sessions/slots/viewers (orgA): published + private, streamer = A_mem
  insert into public.e10_break_sessions(id,organization_id,streamer_uid,share_code,visibility) values
    ('a7000000-0000-4000-8000-0000000000a1'::uuid,v_orgA,A_mem,'__a7_pub','published'),
    ('a7000000-0000-4000-8000-0000000000a2'::uuid,v_orgA,A_mem,'__a7_priv','private');
  insert into public.e10_break_slots(id,organization_id,session_id,buyer_uid) values
    ('a7000000-0000-4000-8000-0000000000b1'::uuid,v_orgA,'a7000000-0000-4000-8000-0000000000a1'::uuid,BU);
  insert into public.e10_break_slots(id,organization_id,session_id,buyer_handle) values
    ('a7000000-0000-4000-8000-0000000000b2'::uuid,v_orgA,'a7000000-0000-4000-8000-0000000000a1'::uuid,'@A7Fan');
  insert into public.e10_session_viewers(session_id,user_id,organization_id) values ('a7000000-0000-4000-8000-0000000000a1'::uuid,V_part,v_orgA);
  insert into public.e10_viewer_handle_claims(user_id,whatnot_handle,status,expires_at) values (H,'@A7Fan','verified',now()+interval '1 year') on conflict do nothing;

  -- F4 obs (orgA)
  insert into public.e10_obs_config(key,organization_id,txt_value) values ('__a7_obsA',v_orgA,'x') on conflict do nothing;

  -- F6 catalog (global)
  insert into public.e10_checklists(id,name,card_count,attrs) values ('a7000000-0000-4000-8000-0000000000c1','CL',0,'{}'::jsonb) on conflict (id) do nothing;
  insert into public.e10_cards(id,checklist_id,chase,attrs) values ('a7000000-0000-4000-8000-000000000ca1','a7000000-0000-4000-8000-0000000000c1',false,'{}'::jsonb) on conflict (id) do nothing;
  -- F7 identity: a legacy role_permissions row
  insert into public.e10_role_permissions(role,capability,allowed) values (v_admrole_A,'act.inventory_edit',true) on conflict do nothing;
  -- F5 workspace shared (orgA) exists
  insert into public.e10_workspace(id,organization_id,rev,data) values ('shared',v_orgA,1,'{}'::jsonb) on conflict (id) do nothing;
end $$;

-- ---------- assertions ----------
set local role authenticated;
do $$
declare
  v_orgA uuid := 'e1000000-0000-4000-8000-0000000000a6'; v_orgB uuid := 'e1000000-0000-4000-8000-0000000000b7';
  A_mem uuid := 'a7000000-0000-4000-8000-00000000000a'; A_nocap uuid := 'a7000000-0000-4000-8000-00000000000b';
  A_admin uuid := 'a7000000-0000-4000-8000-00000000000c'; B_mem uuid := 'a7000000-0000-4000-8000-00000000000d';
  v_multi uuid := 'a7000000-0000-4000-8000-00000000000e'; v_padmin uuid := 'a7000000-0000-4000-8000-00000000000f';
  V_part uuid := 'a7000000-0000-4000-8000-000000000010'; BU uuid := 'a7000000-0000-4000-8000-000000000011';
  H uuid := 'a7000000-0000-4000-8000-000000000012'; v_noorg uuid := 'a7000000-0000-4000-8000-000000000013';
  S_pub uuid := 'a7000000-0000-4000-8000-0000000000a1'; S_priv uuid := 'a7000000-0000-4000-8000-0000000000a2';
  slot_bu uuid := 'a7000000-0000-4000-8000-0000000000b1'; slot_h uuid := 'a7000000-0000-4000-8000-0000000000b2';
  c int; r jsonb; ok int:=0; bad text:='';
  procedure_setclaim text;
begin
  -- helper via inline set_config
  -- ============ F1 Inventory ============
  perform set_config('request.jwt.claims', json_build_object('sub',B_mem::text,'role','authenticated')::text, true);
  select count(*) into c from public.e10_inventory_items where id='__a7_itemA'; if c=0 then ok:=ok+1; else bad:=bad||' F1_orgB_read:'||c; end if;    -- RLS is_org_member(orgA)=f
  perform set_config('request.jwt.claims', json_build_object('sub',A_mem::text,'role','authenticated')::text, true);
  select count(*) into c from public.e10_inventory_items where id='__a7_itemA'; if c=1 then ok:=ok+1; else bad:=bad||' F1_orgA_read:'||c; end if;

  -- ============ F2 Ledger (outlives items) ============
  perform set_config('request.jwt.claims', json_build_object('sub',B_mem::text,'role','authenticated')::text, true);
  select count(*) into c from public.e10_inventory_movements where item_id='__a7_del'; if c=0 then ok:=ok+1; else bad:=bad||' F2_orgB_ledger:'||c; end if;
  perform set_config('request.jwt.claims', json_build_object('sub',A_mem::text,'role','authenticated')::text, true);
  select count(*) into c from public.e10_inventory_movements where item_id='__a7_del';                    -- ledger outlives the hard-deleted item
  if c=1 and (select count(*) from public.e10_inventory_items where id='__a7_del')=0 then ok:=ok+1; else bad:=bad||' F2_orgA_ledger:'||c; end if;
  -- receipts are server-only: authenticated holds NO table grant (stronger than RLS deny-all) -> insufficient_privilege 42501
  begin perform 1 from public.e10_mutation_receipts limit 1; bad:=bad||' F2_receipts_readable';
  exception when insufficient_privilege then ok:=ok+1; when others then bad:=bad||(' F2_receipts_wrong:'||SQLSTATE); end;

  -- ============ F3 Sessions ============
  perform set_config('request.jwt.claims', json_build_object('sub',B_mem::text,'role','authenticated')::text, true);
  select count(*) into c from public.e10_break_sessions where id=S_priv; if c=0 then ok:=ok+1; else bad:=bad||' F3_orgB_priv:'||c; end if;
  perform set_config('request.jwt.claims', json_build_object('sub',V_part::text,'role','authenticated')::text, true);
  select count(*) into c from public.e10_break_sessions where id=S_pub; if c=1 then ok:=ok+1; else bad:=bad||' F3_part_pub:'||c; end if;
  -- published projection: a non-participant (orgB member) may spectate a PUBLISHED session (predicate true) but reads NO raw row.
  perform set_config('request.jwt.claims', json_build_object('sub',B_mem::text,'role','authenticated')::text, true);
  if e10.can_spectate_session(S_pub) is true and e10.can_spectate_session(S_priv) is false then ok:=ok+1; else bad:=bad||' F3_spectate_pred'; end if;
  select count(*) into c from public.e10_break_sessions where id=S_pub; if c=0 then ok:=ok+1; else bad:=bad||' F3_orgB_pub_raw:'||c; end if;
  -- buyer_uid slot: owner sees it, a cross-org member does not
  perform set_config('request.jwt.claims', json_build_object('sub',BU::text,'role','authenticated')::text, true);
  select count(*) into c from public.e10_break_slots where id=slot_bu; if c=1 then ok:=ok+1; else bad:=bad||' F3_bu_own:'||c; end if;
  perform set_config('request.jwt.claims', json_build_object('sub',B_mem::text,'role','authenticated')::text, true);
  select count(*) into c from public.e10_break_slots where id=slot_bu; if c=0 then ok:=ok+1; else bad:=bad||' F3_bu_xorg:'||c; end if;
  -- verified-handle slot: handle holder sees it, the buyer_uid holder (different non-member) does not
  perform set_config('request.jwt.claims', json_build_object('sub',H::text,'role','authenticated')::text, true);
  select count(*) into c from public.e10_break_slots where id=slot_h; if c=1 then ok:=ok+1; else bad:=bad||' F3_h_own:'||c; end if;
  perform set_config('request.jwt.claims', json_build_object('sub',BU::text,'role','authenticated')::text, true);
  select count(*) into c from public.e10_break_slots where id=slot_h; if c=0 then ok:=ok+1; else bad:=bad||' F3_h_other:'||c; end if;

  -- ============ F4 OBS ============
  perform set_config('request.jwt.claims', json_build_object('sub',B_mem::text,'role','authenticated')::text, true);
  select count(*) into c from public.e10_obs_config where key='__a7_obsA'; if c=0 then ok:=ok+1; else bad:=bad||' F4_orgB_obs:'||c; end if;
  perform set_config('request.jwt.claims', json_build_object('sub',A_mem::text,'role','authenticated')::text, true);
  select count(*) into c from public.e10_obs_config where key='__a7_obsA'; if c=1 then ok:=ok+1; else bad:=bad||' F4_orgA_obs:'||c; end if;

  -- ============ F5 Workspace ============
  perform set_config('request.jwt.claims', json_build_object('sub',B_mem::text,'role','authenticated')::text, true);
  select count(*) into c from public.e10_workspace where id='shared' and organization_id=v_orgA; if c=0 then ok:=ok+1; else bad:=bad||' F5_orgB_read:'||c; end if;
  update public.e10_workspace set updated_at=now() where id='shared' and organization_id=v_orgA; get diagnostics c=row_count; if c=0 then ok:=ok+1; else bad:=bad||' F5_orgB_write:'||c; end if;

  -- ============ F6 Catalog (read-only, global) ============
  perform set_config('request.jwt.claims', json_build_object('sub',v_noorg::text,'role','authenticated')::text, true);
  select count(*) into c from public.e10_cards where id='a7000000-0000-4000-8000-000000000ca1'; if c=0 then ok:=ok+1; else bad:=bad||' F6_noorg_read:'||c; end if;
  perform set_config('request.jwt.claims', json_build_object('sub',A_mem::text,'role','authenticated')::text, true);
  select count(*) into c from public.e10_cards where id='a7000000-0000-4000-8000-000000000ca1'; if c=1 then ok:=ok+1; else bad:=bad||' F6_member_read:'||c; end if;
  perform set_config('request.jwt.claims', json_build_object('sub',A_admin::text,'role','authenticated')::text, true);
  begin insert into public.e10_cards(id,checklist_id,chase,attrs) values ('a7000000-0000-4000-8000-000000000ca2','a7000000-0000-4000-8000-0000000000c1',false,'{}'::jsonb); bad:=bad||' F6_admin_ins_allowed';
  exception when sqlstate '42501' then ok:=ok+1; when others then bad:=bad||(' F6_admin_ins_wrong:'||SQLSTATE); end;
  perform set_config('request.jwt.claims', json_build_object('sub',v_padmin::text,'role','authenticated')::text, true);
  select count(*) into c from public.e10_cards where id='a7000000-0000-4000-8000-000000000ca1'; if c=1 then ok:=ok+1; else bad:=bad||' F6_padmin_read:'||c; end if;

  -- ============ F7 Identity ============
  perform set_config('request.jwt.claims', json_build_object('sub',A_mem::text,'role','authenticated')::text, true);
  select count(*) into c from public.e10_members where user_id=A_admin; if c=0 then ok:=ok+1; else bad:=bad||' F7_nonadmin_other:'||c; end if;
  begin insert into public.e10_members(user_id,email,role) values (v_noorg,'x@x','member'); bad:=bad||' F7_member_ins_allowed';
  exception when sqlstate '42501' then ok:=ok+1; when others then bad:=bad||(' F7_member_ins_wrong:'||SQLSTATE); end;
  perform set_config('request.jwt.claims', json_build_object('sub',v_noorg::text,'role','authenticated')::text, true);
  select count(*) into c from public.e10_role_permissions; if c=0 then ok:=ok+1; else bad:=bad||' F7_noorg_rp:'||c; end if;

  -- ============ F8 Delegates ============
  -- H1 cross-org Entity: orgB member calls edit_item(p_org=orgB) on an item that lives in orgA -> cross_org_denied 42501
  perform set_config('request.jwt.claims', json_build_object('sub',B_mem::text,'role','authenticated')::text, true);
  begin perform public.e10_org_inv_edit_item(v_orgB,'__a7_itemA',jsonb_build_object('name','x'),'__a7_h1',null); bad:=bad||' F8_xorg_allowed';
  exception when sqlstate '42501' then ok:=ok+1; when others then bad:=bad||(' F8_xorg_wrong:'||SQLSTATE); end;
  -- H2 non-owner buyer_suggest -> 42501 (owns_session false)
  begin perform public.e10_org_buyer_suggest(S_pub,''); bad:=bad||' F8_suggest_allowed';
  exception when sqlstate '42501' then ok:=ok+1; when others then bad:=bad||(' F8_suggest_wrong:'||SQLSTATE); end;
  -- H3 multi-membership legacy wrapper -> current_org() null -> 42501
  perform set_config('request.jwt.claims', json_build_object('sub',v_multi::text,'role','authenticated')::text, true);
  begin perform public.e10_inv_add_item(jsonb_build_object('id','__a7_m','name','M','qty',1,'cat','Box'),'__a7_h3'); bad:=bad||' F8_multi_allowed';
  exception when sqlstate '42501' then ok:=ok+1; when others then bad:=bad||(' F8_multi_wrong:'||SQLSTATE); end;

  -- ============ Invariants ============
  -- INV1 delegate authority census = 0 legacy predicates in any e10_org_* body or org-aware helper
  select count(*) into c from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and (p.proname like 'e10_org_%' or p.proname in ('_e10_inv_guard','_e10_inv_blob_write','_e10_inv_clamp_res','_e10_inv_receipt_check','_e10_inv_receipt_write','_e10_inv_replay_json','_e10_inv_item_json','_e10_inv_bad_num'))
      and (pg_get_functiondef(p.oid) ~ '\me10_is_admin\s*\(' or pg_get_functiondef(p.oid) ~ '\me10_is_member\s*\(' or pg_get_functiondef(p.oid) ~ '\me10_is_org\s*\(' or pg_get_functiondef(p.oid) ~ '\me10_can_read_session\s*\(' or pg_get_functiondef(p.oid) ~ 'public\.e10_owns_session\s*\(');
  if c=0 then ok:=ok+1; else bad:=bad||' INV1_census:'||c; end if;
  -- INV2 born-locked ACL: anonymous has ZERO EXECUTE on the client delegates
  select count(*) into c from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname like 'e10_org_%' and has_function_privilege('anon', p.oid, 'EXECUTE');
  if c=0 then ok:=ok+1; else bad:=bad||' INV2_anon_exec:'||c; end if;

  if ok = 29 then raise notice 'A7 hostile matrix gate: PASS (29/29 — F1-F8 cross-org denials + legitimate positives under real JWTs; ledger outlives items under hostile identity; delegate census 0; anon ACL 0)';
  else raise exception 'A7 hostile matrix gate: FAIL passed=%/29 failures=[%]', ok, bad; end if;
end $$;
reset role;

-- ============ Anonymous (role anon) — F1/F6 read denials, DIFFERENT layers, both 42501 insufficient_privilege ============
-- Inventory: anon holds NO table grant on e10_inventory_items -> "permission denied for table" (grant layer).
-- Catalog:  anon DOES hold table grants on e10_cards, but the card_sel policy calls e10.is_platform_admin(), on which
--           anon has NO EXECUTE -> "permission denied for function is_platform_admin" (policy-function-execute layer).
-- (An authenticated no-org caller, by contrast, executes the policy fn and is filtered to 0 rows — see F6 in the gate.)
do $$
declare c int; ok int:=0;
begin
  set local role anon;
  begin select count(*) into c from public.e10_inventory_items where id='__a7_itemA'; if c=0 then ok:=ok+1; end if;
  exception when insufficient_privilege then ok:=ok+1; end;                 -- table grant absent
  begin select count(*) into c from public.e10_cards where id='a7000000-0000-4000-8000-000000000ca1'; if c=0 then ok:=ok+1; end if;
  exception when insufficient_privilege then ok:=ok+1; end;                 -- is_platform_admin EXECUTE absent
  reset role;
  if ok=2 then raise notice 'A7 anon (role anon): PASS (no inventory access [table grant absent] + no catalog access [is_platform_admin EXECUTE absent] — both 42501)';
  else raise exception 'A7 anon: FAIL ok=%/2', ok; end if;
end $$;
reset role;
rollback;
