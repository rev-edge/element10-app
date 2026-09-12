-- Element 10 — A6c.2.1 authority-corrective gate. Self-failing; transactionally rolled back.
-- Proves the relocated delegates now scope admin authority to the ORGANIZATION, closing the A6c.2 defect where six
-- bodies carried the legacy GLOBAL public.e10_is_admin(). The uncovered identity is a legacy global admin
-- (e10_members.role='admin') who is only an ORDINARY member of org B: pre-fix they exercised admin behavior in org B;
-- post-fix e10.is_org_admin(p_org) gives them ordinary-member behavior there, while a genuine org-B admin still gets it.
--
-- Proof-standard note: for the five inventory delegates, admin authority is a CAPABILITY (reservation-ownership scope,
-- over-sell bypass, break-session ownership), expressed as an `ok:false` business denial with a specific message — NOT a
-- SQLSTATE exception. So each admin-behavior assertion pins the EXACT (ok,msg) pair (stronger than a generic SQLSTATE
-- check) rather than manufacturing an exception the code never raises. The hard 42501 denials (cross-org / missing-cap /
-- buyer non-owner) are unchanged by A6c.2.1 and remain covered by tests/a6c2_cutover_test.sql. buyer_suggest is proven by
-- result-set membership (cross-session + cross-org exclusion). Fixtures built as the migration role (RLS bypassed);
-- assertions run under per-user JWT claims so auth.uid()/e10.is_org_admin resolve to the acting identity.
begin;

-- ---------- fixtures ----------
do $$
declare
  v_orgB uuid := 'e1000000-0000-4000-8000-0000000000d1';         -- a fresh org
  v_orgA uuid := 'e1000000-0000-4000-8000-0000000000a6';         -- org0 (for the cross-org buyer_suggest leak)
  v_badminrole uuid; v_bmemrole uuid;
  v_gadmin uuid := 'a6c21111-0000-4000-8000-00000000000a';       -- LEGACY GLOBAL admin + ORDINARY org-B member (the uncovered identity)
  v_bother uuid := 'a6c21111-0000-4000-8000-00000000000b';       -- ordinary org-B member; owns the reservations/session/consumption
  v_badmin uuid := 'a6c21111-0000-4000-8000-00000000000c';       -- genuine org-B ADMIN
  v_aowner uuid := 'a6c21111-0000-4000-8000-00000000000d';       -- an org-A session owner (cross-org slot)
begin
  insert into public.e10_organizations(id,name,slug) values (v_orgB,'A6c21 OrgB','a6c21-orgb') on conflict do nothing;
  -- org-B roles: admin (key='admin' -> is_org_admin true) and member (non-admin key). BOTH granted act.inventory_edit,
  -- so has_org_cap passes for the member too and the ONLY separator is is_org_admin.
  insert into public.e10_organization_roles(organization_id,key,name) values (v_orgB,'admin','Admin') returning id into v_badminrole;
  insert into public.e10_organization_roles(organization_id,key,name) values (v_orgB,'member','Member') returning id into v_bmemrole;
  insert into public.e10_organization_role_permissions(organization_id,role_id,capability,allowed) values
    (v_orgB,v_badminrole,'act.inventory_edit',true),
    (v_orgB,v_bmemrole,'act.inventory_edit',true);

  insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at)
    select u,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',replace(u::text,'-','')||'@a6c21.invalid',now(),now()
    from unnest(array[v_gadmin,v_bother,v_badmin,v_aowner]) u on conflict (id) do nothing;
  -- v_gadmin carries the LEGACY GLOBAL admin flag; v_bother/v_badmin do not (isolates that org-admin power now comes from
  -- is_org_admin, not the legacy flag).
  insert into public.e10_members(user_id,email,role) values
    (v_gadmin,'gadm@x','admin'),(v_bother,'both@x','member'),(v_badmin,'badm@x','member'),(v_aowner,'aown@x','member')
    on conflict (user_id) do update set role=excluded.role;
  insert into public.e10_organization_memberships(organization_id,user_id,role_id,status) values
    (v_orgB,v_gadmin,v_bmemrole,'active'),            -- legacy global admin, ORDINARY org-B role
    (v_orgB,v_bother,v_bmemrole,'active'),
    (v_orgB,v_badmin,v_badminrole,'active')
    on conflict (organization_id,user_id) do update set role_id=excluded.role_id,status='active';

  -- items in org B, one per operation to avoid cross-assertion interference
  insert into public.e10_inventory_items(id,name,qty,organization_id) values
    ('__a6c21_rel','R',5,v_orgB), ('__a6c21_sold','X',5,v_orgB),
    ('__a6c21_con','C',10,v_orgB), ('__a6c21_set','T',5,v_orgB), ('__a6c21_rev','V',10,v_orgB);
  -- v_bother's active reservations: release + set_reservations targets (5 on rel/S1, 5 on set/S3), and mark_sold avail=0 (5 on sold)
  insert into public.e10_inventory_reservations(item_id,show_ref,show_label,streamer_uid,qty,status,created_by,organization_id) values
    ('__a6c21_rel','S1','Show1',v_bother::text,5,'active',v_bother,v_orgB),
    ('__a6c21_sold','S2','Show2',v_bother::text,5,'active',v_bother,v_orgB),
    ('__a6c21_set','S3','Show3',v_bother::text,5,'active',v_bother,v_orgB);
  -- v_bother's break session (consume "not your break session")
  insert into public.e10_break_sessions(id,organization_id,streamer_uid,share_code,visibility,source_show_ref) values
    ('a6c21000-0000-4000-8000-0000000000c1'::uuid,v_orgB,v_bother,'__a6c21_bs','private','SC');
  -- v_bother's break_consumption movement to reverse (actor branch: source_entity_id blank)
  insert into public.e10_inventory_movements(workspace_id,item_id,movement_type,on_hand_delta,reserved_delta,idempotency_key,organization_id,actor_uid,meta) values
    ('shared','__a6c21_rev','break_consumption',-2,0,'__a6c21_revsrc',v_orgB,v_bother,
     jsonb_build_object('consumed_qty',2,'reserved_drawn',0,'allocation','[]'::jsonb));

  -- buyer_suggest fixtures: v_gadmin owns sessions X and Y in org B; org-A session Z owned by v_aowner.
  insert into public.e10_break_sessions(id,organization_id,streamer_uid,share_code,visibility) values
    ('a6c21000-0000-4000-8000-0000000000f1'::uuid,v_orgB,v_gadmin,'__a6c21_X','private'),  -- session X (queried)
    ('a6c21000-0000-4000-8000-0000000000f2'::uuid,v_orgB,v_gadmin,'__a6c21_Y','private'),  -- session Y (same owner)
    ('a6c21000-0000-4000-8000-0000000000f3'::uuid,v_orgA,v_aowner,'__a6c21_Z','private');  -- session Z (other org)
  insert into public.e10_break_slots(id,organization_id,session_id,buyer_handle) values
    ('a6c21000-0000-4000-8000-000000000101'::uuid,v_orgB,'a6c21000-0000-4000-8000-0000000000f1'::uuid,'@inX'),
    ('a6c21000-0000-4000-8000-000000000102'::uuid,v_orgB,'a6c21000-0000-4000-8000-0000000000f2'::uuid,'@onlyY'),
    ('a6c21000-0000-4000-8000-000000000103'::uuid,v_orgA,'a6c21000-0000-4000-8000-0000000000f3'::uuid,'@orgA');
end $$;

-- ---------- assertions ----------
do $$
declare
  v_orgB uuid := 'e1000000-0000-4000-8000-0000000000d1';
  v_gadmin uuid := 'a6c21111-0000-4000-8000-00000000000a';
  v_bother uuid := 'a6c21111-0000-4000-8000-00000000000b';
  v_badmin uuid := 'a6c21111-0000-4000-8000-00000000000c';
  v_sessX uuid := 'a6c21000-0000-4000-8000-0000000000f1';
  v_revmv uuid;
  r jsonb; sug jsonb; ok int:=0; bad text:='';
begin
  select id into v_revmv from public.e10_inventory_movements where idempotency_key='__a6c21_revsrc';

  -- sanity: the legacy global flag really is set on v_gadmin, and org-scoping really differs.
  perform set_config('request.jwt.claims', json_build_object('sub',v_gadmin::text,'role','authenticated')::text, true);
  if public.e10_is_admin() and not e10.is_org_admin(v_orgB) then ok:=ok+1; else bad:=bad||' gadmin_identity'; end if;
  perform set_config('request.jwt.claims', json_build_object('sub',v_badmin::text,'role','authenticated')::text, true);
  if e10.is_org_admin(v_orgB) then ok:=ok+1; else bad:=bad||' badmin_isadmin'; end if;

  -- ============ RELEASE ============ legacy global admin canNOT release another member's reservation; org-B admin can.
  perform set_config('request.jwt.claims', json_build_object('sub',v_gadmin::text,'role','authenticated')::text, true);
  r := public.e10_org_inv_release(v_orgB,'__a6c21_rel','S1','__a6c21_rel_g');
  if (r->>'ok')='false' and r->>'msg'='no active reservation of yours for that show' then ok:=ok+1; else bad:=bad||' rel_gadmin:'||coalesce(r->>'msg','?'); end if;
  perform set_config('request.jwt.claims', json_build_object('sub',v_badmin::text,'role','authenticated')::text, true);
  r := public.e10_org_inv_release(v_orgB,'__a6c21_rel','S1','__a6c21_rel_a');
  if (r->>'ok')='true' and r->>'msg'='released' then ok:=ok+1; else bad:=bad||' rel_badmin:'||coalesce(r->>'msg','?'); end if;

  -- ============ MARK_SOLD ============ over-availability (avail=0): legacy global admin refused; org-B admin bypasses.
  perform set_config('request.jwt.claims', json_build_object('sub',v_gadmin::text,'role','authenticated')::text, true);
  r := public.e10_org_inv_mark_sold(v_orgB,'__a6c21_sold',3,0,'__a6c21_sold_g');
  if (r->>'ok')='false' and r->>'msg'='only 0 available' then ok:=ok+1; else bad:=bad||' sold_gadmin:'||coalesce(r->>'msg','?'); end if;
  perform set_config('request.jwt.claims', json_build_object('sub',v_badmin::text,'role','authenticated')::text, true);
  r := public.e10_org_inv_mark_sold(v_orgB,'__a6c21_sold',3,0,'__a6c21_sold_a');
  if (r->>'ok')='true' and r->>'msg'='sold' then ok:=ok+1; else bad:=bad||' sold_badmin:'||coalesce(r->>'msg','?'); end if;

  -- ============ CONSUME ============ another member's break session: legacy global admin refused; org-B admin proceeds.
  perform set_config('request.jwt.claims', json_build_object('sub',v_gadmin::text,'role','authenticated')::text, true);
  r := public.e10_org_inv_consume(v_orgB,'__a6c21_con','a6c21000-0000-4000-8000-0000000000c1',null,2,'__a6c21_con_g');
  if (r->>'ok')='false' and r->>'msg'='not your break session' then ok:=ok+1; else bad:=bad||' con_gadmin:'||coalesce(r->>'msg','?'); end if;
  perform set_config('request.jwt.claims', json_build_object('sub',v_badmin::text,'role','authenticated')::text, true);
  r := public.e10_org_inv_consume(v_orgB,'__a6c21_con','a6c21000-0000-4000-8000-0000000000c1',null,2,'__a6c21_con_a');
  if (r->>'ok')='true' and r->>'msg'='consumed' then ok:=ok+1; else bad:=bad||' con_badmin:'||coalesce(r->>'msg','?'); end if;

  -- ============ SET_RESERVATIONS ============ manage another member's reservations: legacy global admin canNOT; org-B admin can.
  perform set_config('request.jwt.claims', json_build_object('sub',v_gadmin::text,'role','authenticated')::text, true);
  r := public.e10_org_inv_set_reservations(v_orgB,'S3','Show3',jsonb_build_array(jsonb_build_object('item_id','__a6c21_set','qty',3)),'__a6c21_set_g');
  if (r->>'ok')='false' and r->>'msg' like 'item __a6c21_set: target 3 exceeds available%' then ok:=ok+1; else bad:=bad||' set_gadmin:'||coalesce(r->>'msg','?'); end if;
  perform set_config('request.jwt.claims', json_build_object('sub',v_badmin::text,'role','authenticated')::text, true);
  r := public.e10_org_inv_set_reservations(v_orgB,'S3','Show3',jsonb_build_array(jsonb_build_object('item_id','__a6c21_set','qty',3)),'__a6c21_set_a');
  if (r->>'ok')='true' and r->>'msg'='reservations set' then ok:=ok+1; else bad:=bad||' set_badmin:'||coalesce(r->>'msg','?'); end if;

  -- ============ REVERSE_CONSUMPTION ============ another member's consumption: legacy global admin refused; org-B admin proceeds.
  perform set_config('request.jwt.claims', json_build_object('sub',v_gadmin::text,'role','authenticated')::text, true);
  r := public.e10_org_inv_reverse_consumption(v_orgB,'__a6c21_rev',v_revmv,'__a6c21_rev_g');
  if (r->>'ok')='false' and r->>'msg'='not your consumption to reverse' then ok:=ok+1; else bad:=bad||' rev_gadmin:'||coalesce(r->>'msg','?'); end if;
  perform set_config('request.jwt.claims', json_build_object('sub',v_badmin::text,'role','authenticated')::text, true);
  r := public.e10_org_inv_reverse_consumption(v_orgB,'__a6c21_rev',v_revmv,'__a6c21_rev_a');
  if (r->>'ok')='true' and r->>'msg'='reversed' then ok:=ok+1; else bad:=bad||' rev_badmin:'||coalesce(r->>'msg','?'); end if;

  -- ============ BUYER_SUGGEST ============ scoped to the requested session: no same-owner-other-session, no other-org.
  perform set_config('request.jwt.claims', json_build_object('sub',v_gadmin::text,'role','authenticated')::text, true);
  sug := public.e10_org_buyer_suggest(v_sessX,'');
  if exists(select 1 from jsonb_array_elements(sug) e where e->>'label'='@inX') then ok:=ok+1; else bad:=bad||' sug_missing_inX'; end if;
  if not exists(select 1 from jsonb_array_elements(sug) e where e->>'label'='@onlyY') then ok:=ok+1; else bad:=bad||' sug_leaked_onlyY'; end if;
  if not exists(select 1 from jsonb_array_elements(sug) e where e->>'label'='@orgA') then ok:=ok+1; else bad:=bad||' sug_leaked_orgA'; end if;

  if ok = 15 then raise notice 'A6c.2.1 authority gate: PASS (legacy-global-admin gets ordinary-member behavior in org B across release/mark_sold/consume/set_reservations/reverse; org-B admin retains it; buyer_suggest scoped to the requested session, no cross-session/cross-org leak)';
  else raise exception 'A6c.2.1 authority gate: FAIL passed=%/15 failures=[%]', ok, bad; end if;
end $$;
rollback;
