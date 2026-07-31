-- Element 10 — A6c.4 platform-catalog + identity policy gate. Self-failing; transactionally rolled back.
-- Proves the 28 rewritten/dropped census rows enforce the intended boundaries under `set role authenticated` (RLS on):
--   S1 catalog SELECT (cards/checklists/players/sets/teams): a caller who belongs to an org OR is a platform admin reads
--      the shared catalog; a caller with no org and no platform-admin grant does not. (One table exercised end to end;
--      a source census asserts all 5 SELECT policies share the identical predicate — claim discipline.)
--   S2 catalog mutation deny-by-default: with the 15 mutation policies dropped and RLS enabled, even an org admin's
--      INSERT is refused 42501 and UPDATE affects 0 rows; only service_role/platform maintenance (RLS bypass) may write.
--   S3 identity family: e10_members / e10_role_permissions / e10_viewers — a member reads its own row; writes require
--      e10.is_org_admin(e10.current_org()); role_permissions reads like the catalog; a no-org caller cannot read it.
-- Proof standard: specific SQLSTATE (42501) for write refusals; exact count/row-count for read/USING-filtered denials
-- (unshadowable — a read or USING-excluded update raises no exception); per-assertion layer notes; no `when others`
-- except as a *_wrongerr recorder. Fixtures built as the migration role (RLS bypassed).
begin;

-- ---------- fixtures ----------
do $$
declare
  v_org0 uuid := 'e1000000-0000-4000-8000-0000000000a6';
  v_adminrole0 uuid := 'e1000000-0000-4000-8000-000000000001';   -- org0 admin role
  v_streamrole0 uuid := 'e1000000-0000-4000-8000-000000000003';  -- org0 streamer role (key<>'admin' => is_org_admin false)
  v_admin0 uuid := 'a6c41111-0000-4000-8000-00000000000a';       -- org0 admin
  v_mem0   uuid := 'a6c41111-0000-4000-8000-00000000000b';       -- org0 member, NOT admin
  v_noorg  uuid := 'a6c41111-0000-4000-8000-00000000000c';       -- no membership, not platform admin
  v_padmin uuid := 'a6c41111-0000-4000-8000-00000000000d';       -- platform admin
  v_newmem uuid := 'a6c41111-0000-4000-8000-00000000000e';       -- target of the admin-only member INSERT
begin
  insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at)
    select u,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',replace(u::text,'-','')||'@a6c4.invalid',now(),now()
    from unnest(array[v_admin0,v_mem0,v_noorg,v_padmin,v_newmem]) u on conflict (id) do nothing;
  insert into public.e10_members(user_id,email,role) values
    (v_admin0,'adm0@x','admin'),(v_mem0,'mem0@x','member') on conflict (user_id) do update set role=excluded.role;
  insert into public.e10_organization_memberships(organization_id,user_id,role_id,status) values
    (v_org0,v_admin0,v_adminrole0,'active'),(v_org0,v_mem0,v_streamrole0,'active')
    on conflict (organization_id,user_id) do update set role_id=excluded.role_id,status='active';
  insert into public.e10_platform_admins(user_id) values (v_padmin) on conflict do nothing;
  insert into public.e10_viewers(user_id,whatnot_handle) values (v_mem0,'@mem0'),(v_admin0,'@adm0') on conflict (user_id) do nothing;
  -- a catalog card (via a checklist) so SELECT visibility is observable
  insert into public.e10_checklists(id,name,card_count,attrs) values ('a6c40000-0000-4000-8000-0000000000c1','CL',1,'{}'::jsonb) on conflict (id) do nothing;
  insert into public.e10_cards(id,checklist_id,chase,attrs) values ('a6c40000-0000-4000-8000-000000000ca1','a6c40000-0000-4000-8000-0000000000c1',false,'{}'::jsonb) on conflict (id) do nothing;
  -- a legacy role-permissions row so rp_sel has something to read
  insert into public.e10_role_permissions(role,capability,allowed) values (v_adminrole0,'act.inventory_edit',true) on conflict do nothing;
end $$;

-- ---------- assertions ----------
set local role authenticated;
do $$
declare
  v_org0 uuid := 'e1000000-0000-4000-8000-0000000000a6';
  v_admin0 uuid := 'a6c41111-0000-4000-8000-00000000000a'; v_mem0 uuid := 'a6c41111-0000-4000-8000-00000000000b';
  v_noorg uuid := 'a6c41111-0000-4000-8000-00000000000c'; v_padmin uuid := 'a6c41111-0000-4000-8000-00000000000d';
  v_newmem uuid := 'a6c41111-0000-4000-8000-00000000000e';
  c int; ok int:=0; bad text:='';
begin
  -- =========================== S1  platform catalog SELECT scoping (e10_cards) ===========================
  -- S1.1 org member reads the catalog; S1.2 no-org non-padmin cannot; S1.3 platform admin reads.
  perform set_config('request.jwt.claims', json_build_object('sub',v_mem0::text,'role','authenticated')::text, true);
  select count(*) into c from public.e10_cards where id='a6c40000-0000-4000-8000-000000000ca1'; if c=1 then ok:=ok+1; else bad:=bad||' S1.1_member_read:'||c; end if;
  perform set_config('request.jwt.claims', json_build_object('sub',v_noorg::text,'role','authenticated')::text, true);
  select count(*) into c from public.e10_cards where id='a6c40000-0000-4000-8000-000000000ca1'; if c=0 then ok:=ok+1; else bad:=bad||' S1.2_noorg_visible:'||c; end if;
  perform set_config('request.jwt.claims', json_build_object('sub',v_padmin::text,'role','authenticated')::text, true);
  select count(*) into c from public.e10_cards where id='a6c40000-0000-4000-8000-000000000ca1'; if c=1 then ok:=ok+1; else bad:=bad||' S1.3_padmin_read:'||c; end if;
  -- S1.4 source census: all 5 catalog SELECT policies share ONE identical predicate (backs the "all 5" claim).
  select count(distinct qual) into c from pg_policies where schemaname='public'
    and tablename in ('e10_cards','e10_checklists','e10_players','e10_sets','e10_teams') and cmd='SELECT';
  if c=1 then ok:=ok+1; else bad:=bad||' S1.4_catalog_sel_variants:'||c; end if;

  -- =========================== S2  catalog mutation deny-by-default ===========================
  -- S2.1 INSERT refused 42501 even for an org admin (RLS enabled, 0 INSERT policy => no WITH CHECK passes; the checklist
  -- FK is satisfied, so ONLY RLS default-deny can refuse). S2.2 UPDATE affects 0 rows (no UPDATE policy => USING excludes
  -- every row). S2.3 absence: 0 mutation policies remain on the 5 catalog tables.
  perform set_config('request.jwt.claims', json_build_object('sub',v_admin0::text,'role','authenticated')::text, true);
  begin
    insert into public.e10_cards(id,checklist_id,chase,attrs) values ('a6c40000-0000-4000-8000-000000000ca2','a6c40000-0000-4000-8000-0000000000c1',false,'{}'::jsonb);
    bad:=bad||' S2.1_insert_allowed';
  exception when sqlstate '42501' then ok:=ok+1; when others then bad:=bad||(' S2.1_insert_wrongerr:'||SQLSTATE); end;
  update public.e10_cards set name='x' where id='a6c40000-0000-4000-8000-000000000ca1';
  get diagnostics c = row_count; if c=0 then ok:=ok+1; else bad:=bad||' S2.2_update_rows:'||c; end if;
  select count(*) into c from pg_policies where schemaname='public'
    and tablename in ('e10_cards','e10_checklists','e10_players','e10_sets','e10_teams') and cmd<>'SELECT';
  if c=0 then ok:=ok+1; else bad:=bad||' S2.3_mutation_policies:'||c; end if;

  -- =========================== S3  identity family ===========================
  -- S3.1 m_sel: a member sees its OWN e10_members row; S3.2 does NOT see another member's row; S3.3 an org admin sees it.
  perform set_config('request.jwt.claims', json_build_object('sub',v_mem0::text,'role','authenticated')::text, true);
  select count(*) into c from public.e10_members where user_id=v_mem0; if c=1 then ok:=ok+1; else bad:=bad||' S3.1_own_member:'||c; end if;
  select count(*) into c from public.e10_members where user_id=v_admin0; if c=0 then ok:=ok+1; else bad:=bad||' S3.2_other_member_visible:'||c; end if;
  perform set_config('request.jwt.claims', json_build_object('sub',v_admin0::text,'role','authenticated')::text, true);
  select count(*) into c from public.e10_members where user_id=v_mem0; if c=1 then ok:=ok+1; else bad:=bad||' S3.3_admin_sees_member:'||c; end if;
  -- S3.4 m_ins: non-admin refused 42501; S3.5 org admin allowed.
  perform set_config('request.jwt.claims', json_build_object('sub',v_mem0::text,'role','authenticated')::text, true);
  begin insert into public.e10_members(user_id,email,role) values (v_newmem,'nm@x','member'); bad:=bad||' S3.4_member_ins_allowed';
  exception when sqlstate '42501' then ok:=ok+1; when others then bad:=bad||(' S3.4_member_ins_wrongerr:'||SQLSTATE); end;
  perform set_config('request.jwt.claims', json_build_object('sub',v_admin0::text,'role','authenticated')::text, true);
  begin insert into public.e10_members(user_id,email,role) values (v_newmem,'nm@x','member'); ok:=ok+1;
  exception when others then bad:=bad||(' S3.5_admin_ins_err:'||SQLSTATE); end;
  -- S3.6 m_upd: non-admin => 0 rows (USING is_org_admin false); S3.7 org admin => 1 row.
  perform set_config('request.jwt.claims', json_build_object('sub',v_mem0::text,'role','authenticated')::text, true);
  update public.e10_members set display_name='z' where user_id=v_mem0;
  get diagnostics c = row_count; if c=0 then ok:=ok+1; else bad:=bad||' S3.6_nonadmin_upd_rows:'||c; end if;
  perform set_config('request.jwt.claims', json_build_object('sub',v_admin0::text,'role','authenticated')::text, true);
  update public.e10_members set display_name='z' where user_id=v_mem0;
  get diagnostics c = row_count; if c=1 then ok:=ok+1; else bad:=bad||' S3.7_admin_upd_rows:'||c; end if;
  -- S3.8 rp_sel: org member reads legacy role_permissions; S3.9 no-org caller cannot.
  perform set_config('request.jwt.claims', json_build_object('sub',v_mem0::text,'role','authenticated')::text, true);
  select count(*) into c from public.e10_role_permissions; if c>=1 then ok:=ok+1; else bad:=bad||' S3.8_member_rp_read:'||c; end if;
  perform set_config('request.jwt.claims', json_build_object('sub',v_noorg::text,'role','authenticated')::text, true);
  select count(*) into c from public.e10_role_permissions; if c=0 then ok:=ok+1; else bad:=bad||' S3.9_noorg_rp_visible:'||c; end if;
  -- S3.10 rp_ins: non-admin refused 42501; S3.11 org admin allowed.
  perform set_config('request.jwt.claims', json_build_object('sub',v_mem0::text,'role','authenticated')::text, true);
  begin insert into public.e10_role_permissions(role,capability,allowed) values (v_org0,'act.x',true); bad:=bad||' S3.10_rp_ins_allowed';
  exception when sqlstate '42501' then ok:=ok+1; when others then bad:=bad||(' S3.10_rp_ins_wrongerr:'||SQLSTATE); end;
  perform set_config('request.jwt.claims', json_build_object('sub',v_admin0::text,'role','authenticated')::text, true);
  begin insert into public.e10_role_permissions(role,capability,allowed) values (v_org0,'act.x',true); ok:=ok+1;
  exception when others then bad:=bad||(' S3.11_rp_ins_err:'||SQLSTATE); end;
  -- S3.12 vw_sel: a viewer sees its OWN row; S3.13 not another's (non-admin).
  perform set_config('request.jwt.claims', json_build_object('sub',v_mem0::text,'role','authenticated')::text, true);
  select count(*) into c from public.e10_viewers where user_id=v_mem0; if c=1 then ok:=ok+1; else bad:=bad||' S3.12_own_viewer:'||c; end if;
  select count(*) into c from public.e10_viewers where user_id=v_admin0; if c=0 then ok:=ok+1; else bad:=bad||' S3.13_other_viewer_visible:'||c; end if;

  if ok = 20 then raise notice 'A6c.4 platform/identity gate: PASS (20/20 — catalog SELECT platform/org-scoped; 15 mutations deny-by-default incl. 42501 INSERT refusal; members/role_permissions/viewers org-scoped with is_org_admin(current_org()) writes)';
  else raise exception 'A6c.4 platform/identity gate: FAIL passed=%/20 failures=[%]', ok, bad; end if;
end $$;
reset role;
rollback;
