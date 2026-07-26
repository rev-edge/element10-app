-- Element 10 — A6c.1 RLS rewrite gate. Self-failing; transactionally rolled back.
-- Fixtures are created as the migration role (RLS bypassed), then all authorization assertions run under
-- `set role authenticated` with a per-user JWT claim, so RLS is genuinely enforced (authenticated is not a superuser,
-- not the table owner, no BYPASSRLS). Proves every axis positive + denial, published-vs-private spectate, and that a
-- deleted item's ledger row stays readable (organization-scoped, no item dependency).
begin;

-- ---------- fixtures (as the privileged migration role) ----------
do $$
declare
  v_orgA uuid := 'e1000000-0000-4000-8000-0000000000a6';         -- org0
  v_orgB uuid := 'e1000000-0000-4000-8000-0000000000e5';         -- second org
  v_adminrole uuid := 'e1000000-0000-4000-8000-000000000001';
  v_amem uuid := 'a6c11111-0000-4000-8000-00000000000a';         -- org A member
  v_bmem uuid := 'a6c11111-0000-4000-8000-00000000000b';         -- org B member
  v_none uuid := 'a6c11111-0000-4000-8000-00000000000c';         -- no membership
  v_viewer uuid := 'a6c11111-0000-4000-8000-00000000000d';       -- session_viewer, non-member
  v_buyer uuid := 'a6c11111-0000-4000-8000-00000000000e';        -- buyer_uid on a slot, non-member
  v_handle uuid := 'a6c11111-0000-4000-8000-00000000000f';       -- verified-handle buyer, non-member
  v_broleA uuid; v_broleB uuid;
begin
  insert into public.e10_organizations(id,name,slug) values (v_orgB,'A6c1 OrgB','a6c1-orgb') on conflict do nothing;
  -- org B needs its own admin role for a membership
  select id into v_broleB from public.e10_organization_roles where organization_id=v_orgB and key='admin';
  if v_broleB is null then insert into public.e10_organization_roles(organization_id,key,name) values (v_orgB,'admin','Admin') returning id into v_broleB; end if;
  insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at)
    select u,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',replace(u::text,'-','')||'@a6c1.invalid',now(),now()
    from unnest(array[v_amem,v_bmem,v_none,v_viewer,v_buyer,v_handle]) u on conflict (id) do nothing;
  insert into public.e10_members(user_id,email,role) values (v_amem,'am@x','admin'),(v_bmem,'bm@x','admin') on conflict (user_id) do update set role=excluded.role;
  insert into public.e10_organization_memberships(organization_id,user_id,role_id,status) values
    (v_orgA,v_amem,v_adminrole,'active'),(v_orgB,v_bmem,v_broleB,'active') on conflict (organization_id,user_id) do update set role_id=excluded.role_id,status='active';
  -- items in each org
  insert into public.e10_inventory_items(id,name,qty,organization_id) values ('__a6c1_itemA','A',5,v_orgA),('__a6c1_itemB','B',5,v_orgB);
  -- a deleted item's ledger row (org A): create item + movement, then hard-delete the item
  insert into public.e10_inventory_items(id,name,qty,organization_id) values ('__a6c1_del','D',1,v_orgA);
  insert into public.e10_inventory_movements(workspace_id,item_id,movement_type,on_hand_delta,idempotency_key,organization_id)
    values ('shared','__a6c1_del','correction',-1,'__a6c1_delmv',v_orgA);
  delete from public.e10_inventory_items where id='__a6c1_del';
  -- sessions in org A: published + private, streamer = v_amem
  insert into public.e10_break_sessions(id,organization_id,streamer_uid,share_code,visibility) values
    ('11111111-0000-4000-8000-0000000000a1'::uuid,v_orgA,v_amem,'__a6c1_pub','published'),
    ('11111111-0000-4000-8000-0000000000a2'::uuid,v_orgA,v_amem,'__a6c1_priv','private');
  -- slots in org A on the published session: one owned by buyer_uid, one by handle
  insert into public.e10_break_slots(id,organization_id,session_id,buyer_uid) values
    ('22222222-0000-4000-8000-0000000000b1'::uuid,v_orgA,'11111111-0000-4000-8000-0000000000a1'::uuid,v_buyer);
  insert into public.e10_break_slots(id,organization_id,session_id,buyer_handle) values
    ('22222222-0000-4000-8000-0000000000b2'::uuid,v_orgA,'11111111-0000-4000-8000-0000000000a1'::uuid,'@Fanatic');
  -- session_viewer (v_viewer joined the published session)
  insert into public.e10_session_viewers(session_id,user_id,organization_id) values ('11111111-0000-4000-8000-0000000000a1'::uuid,v_viewer,v_orgA);
  -- verified handle claim for v_handle -> whatnot_handle '@Fanatic' (handle_norm generates to 'fanatic')
  insert into public.e10_viewer_handle_claims(user_id,whatnot_handle,status,expires_at)
    values (v_handle,'@Fanatic','verified',now()+interval '1 year') on conflict do nothing;
end $$;

-- ---------- authorization assertions under a real authenticated role (RLS enforced) ----------
set local role authenticated;
do $$
declare
  v_orgA uuid := 'e1000000-0000-4000-8000-0000000000a6'; v_orgB uuid := 'e1000000-0000-4000-8000-0000000000e5';
  v_amem uuid := 'a6c11111-0000-4000-8000-00000000000a'; v_bmem uuid := 'a6c11111-0000-4000-8000-00000000000b';
  v_none uuid := 'a6c11111-0000-4000-8000-00000000000c'; v_viewer uuid := 'a6c11111-0000-4000-8000-00000000000d';
  v_buyer uuid := 'a6c11111-0000-4000-8000-00000000000e'; v_handle uuid := 'a6c11111-0000-4000-8000-00000000000f';
  v_pub uuid := '11111111-0000-4000-8000-0000000000a1'; v_priv uuid := '11111111-0000-4000-8000-0000000000a2';
  ok int:=0; bad text:='';
  procedure_noop int;
begin
  -- helper: set the acting user
  -- AXIS 1 cross-org read: org-A member sees org-A items (positive) but not org-B items (denial)
  perform set_config('request.jwt.claims', json_build_object('sub',v_amem::text,'role','authenticated')::text, true);
  if (select count(*) from public.e10_inventory_items where id='__a6c1_itemA')=1 then ok:=ok+1; else bad:=bad||' xorg_pos'; end if;
  if (select count(*) from public.e10_inventory_items where id='__a6c1_itemB')=0 then ok:=ok+1; else bad:=bad||' xorg_deny'; end if;
  -- AXIS 2 non-member read denied
  perform set_config('request.jwt.claims', json_build_object('sub',v_none::text,'role','authenticated')::text, true);
  if (select count(*) from public.e10_inventory_items where id in ('__a6c1_itemA','__a6c1_itemB'))=0 then ok:=ok+1; else bad:=bad||' nonmember'; end if;
  -- AXIS 3 session participant vs non: viewer (participant) sees the session; non-member non-participant does not
  perform set_config('request.jwt.claims', json_build_object('sub',v_viewer::text,'role','authenticated')::text, true);
  if (select count(*) from public.e10_break_sessions where id=v_pub)=1 then ok:=ok+1; else bad:=bad||' participant_pos'; end if;
  perform set_config('request.jwt.claims', json_build_object('sub',v_none::text,'role','authenticated')::text, true);
  if (select count(*) from public.e10_break_sessions where id=v_pub)=0 then ok:=ok+1; else bad:=bad||' participant_deny'; end if;
  -- AXIS 4 viewer vs member: viewer sees the session it joined but NOT the org's inventory (not a member)
  perform set_config('request.jwt.claims', json_build_object('sub',v_viewer::text,'role','authenticated')::text, true);
  if (select count(*) from public.e10_inventory_items where id='__a6c1_itemA')=0 then ok:=ok+1; else bad:=bad||' viewer_not_member'; end if;
  -- AXIS 5 buyer_uid boundary: buyer sees their own slot; non-member non-buyer does not
  perform set_config('request.jwt.claims', json_build_object('sub',v_buyer::text,'role','authenticated')::text, true);
  if (select count(*) from public.e10_break_slots where id='22222222-0000-4000-8000-0000000000b1')=1 then ok:=ok+1; else bad:=bad||' buyer_pos'; end if;
  perform set_config('request.jwt.claims', json_build_object('sub',v_none::text,'role','authenticated')::text, true);
  if (select count(*) from public.e10_break_slots where id='22222222-0000-4000-8000-0000000000b1')=0 then ok:=ok+1; else bad:=bad||' buyer_deny'; end if;
  -- AXIS 6 handle boundary: verified-handle buyer sees the handle slot; a different non-member does not
  perform set_config('request.jwt.claims', json_build_object('sub',v_handle::text,'role','authenticated')::text, true);
  if (select count(*) from public.e10_break_slots where id='22222222-0000-4000-8000-0000000000b2')=1 then ok:=ok+1; else bad:=bad||' handle_pos'; end if;
  perform set_config('request.jwt.claims', json_build_object('sub',v_buyer::text,'role','authenticated')::text, true);
  if (select count(*) from public.e10_break_slots where id='22222222-0000-4000-8000-0000000000b2')=0 then ok:=ok+1; else bad:=bad||' handle_deny'; end if;
  -- AXIS 7 published vs private (predicate): published->true, private->false; and raw tables serve NO spectator
  perform set_config('request.jwt.claims', json_build_object('sub',v_none::text,'role','authenticated')::text, true);
  if e10.can_spectate_session(v_pub) is true then ok:=ok+1; else bad:=bad||' spectate_pub'; end if;
  if e10.can_spectate_session(v_priv) is false then ok:=ok+1; else bad:=bad||' spectate_priv'; end if;
  if (select count(*) from public.e10_break_sessions where id=v_pub)=0 then ok:=ok+1; else bad:=bad||' spectator_no_raw'; end if;  -- non-participant sees no raw row even for a published session
  -- AXIS 8 deleted-item ledger visibility: org-A member reads the correction movement for the hard-deleted item
  perform set_config('request.jwt.claims', json_build_object('sub',v_amem::text,'role','authenticated')::text, true);
  if (select count(*) from public.e10_inventory_movements where item_id='__a6c1_del')=1
     and (select count(*) from public.e10_inventory_items where id='__a6c1_del')=0 then ok:=ok+1; else bad:=bad||' deleted_ledger'; end if;
  -- write-side WITH CHECK: org-A member cannot INSERT a break_slot into org B (cross-org write denied)
  begin
    insert into public.e10_break_slots(id,organization_id,session_id) values (gen_random_uuid(),v_orgB,v_pub);
    bad:=bad||' xorg_write_not_denied';
  exception when others then ok:=ok+1; end;

  if ok = 15 then raise notice 'A6c.1 RLS gate: PASS (8 axes, positive+denial, under authenticated JWT; deleted-item ledger visible; cross-org write denied)';
  else raise exception 'A6c.1 RLS gate: FAIL passed=%/15 failures=[%]', ok, bad; end if;
end $$;
reset role;
rollback;
