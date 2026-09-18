-- Element 10 — A6c.4: carried A6c.3 workspace disclosures. Self-failing; transactionally rolled back.
-- Closes the untested workspace-policy conditions disclosed at A6c.3 (the A6c.3 migration is accepted/frozen and NOT
-- modified — this is added coverage only): ws_del; the missing-capability 'shared' write branch; multi-membership
-- fail-closed on a workspace write; and the previously data-less 'universal' and owner branches (fixtures created here).
-- Under `set role authenticated` (RLS enforced). Proof standard: specific 42501 or exact row-count per case; layer notes.
begin;

-- ---------- fixtures ----------
do $$
declare
  v_org0 uuid := 'e1000000-0000-4000-8000-0000000000a6';
  v_orgB uuid := 'e1000000-0000-4000-8000-0000000000e5';
  v_adminrole0 uuid := 'e1000000-0000-4000-8000-000000000001';   -- org0 admin (has act.inventory_edit)
  v_opsrole0 uuid := 'e1000000-0000-4000-8000-000000000004';     -- org0 ops (LACKS act.inventory_edit)
  v_brole uuid;
  v_admin0 uuid := 'a6c42222-0000-4000-8000-00000000000a';       -- org0 admin
  v_nocap0 uuid := 'a6c42222-0000-4000-8000-00000000000b';       -- org0 member WITHOUT the cap (ops), not admin
  v_owner  uuid := 'a6c42222-0000-4000-8000-00000000000c';       -- owns personal workspace rows; single org0 membership
  v_multi  uuid := 'a6c42222-0000-4000-8000-00000000000d';       -- member of BOTH org0 and orgB => current_org() null
begin
  insert into public.e10_organizations(id,name,slug) values (v_orgB,'A6c4 OrgB','a6c4-orgb') on conflict do nothing;
  select id into v_brole from public.e10_organization_roles where organization_id=v_orgB and key='admin';
  if v_brole is null then insert into public.e10_organization_roles(organization_id,key,name) values (v_orgB,'admin','Admin') returning id into v_brole; end if;
  insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at)
    select u,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',replace(u::text,'-','')||'@a6c4d.invalid',now(),now()
    from unnest(array[v_admin0,v_nocap0,v_owner,v_multi]) u on conflict (id) do nothing;
  insert into public.e10_members(user_id,email,role) values
    (v_admin0,'a@x','admin'),(v_nocap0,'n@x','member'),(v_owner,'o@x','member'),(v_multi,'m@x','admin')
    on conflict (user_id) do update set role=excluded.role;
  insert into public.e10_organization_memberships(organization_id,user_id,role_id,status) values
    (v_org0,v_admin0,v_adminrole0,'active'),
    (v_org0,v_nocap0,v_opsrole0,'active'),
    (v_org0,v_owner,v_opsrole0,'active'),
    (v_org0,v_multi,v_adminrole0,'active'),
    (v_orgB,v_multi,v_brole,'active')                              -- second active membership => current_org() null
    on conflict (organization_id,user_id) do update set role_id=excluded.role_id,status='active';
  -- ensure the single org0 'shared' row exists; add a 'universal' row (org0, no owner); add personal rows owned by v_owner.
  insert into public.e10_workspace(id,organization_id,rev,data) values ('shared',v_org0,1,'{}'::jsonb) on conflict (id) do nothing;
  insert into public.e10_workspace(id,organization_id,owner,rev,data) values
    ('universal',v_org0,null,1,'{}'::jsonb),
    ('a6c4_pown',v_org0,v_owner,1,'{}'::jsonb),      -- owner read/update
    ('a6c4_pdel1',v_org0,v_owner,1,'{}'::jsonb),     -- D1 owner deletes
    ('a6c4_pdel2',v_org0,v_owner,1,'{}'::jsonb),     -- D3 org-admin deletes (owner is someone else)
    ('a6c4_pdel3',v_org0,v_owner,1,'{}'::jsonb)      -- D2 non-owner non-admin cannot delete
    on conflict (id) do nothing;
end $$;

-- ---------- assertions ----------
set local role authenticated;
do $$
declare
  v_org0 uuid := 'e1000000-0000-4000-8000-0000000000a6'; v_orgB uuid := 'e1000000-0000-4000-8000-0000000000e5';
  v_admin0 uuid := 'a6c42222-0000-4000-8000-00000000000a'; v_nocap0 uuid := 'a6c42222-0000-4000-8000-00000000000b';
  v_owner uuid := 'a6c42222-0000-4000-8000-00000000000c'; v_multi uuid := 'a6c42222-0000-4000-8000-00000000000d';
  c int; ok int:=0; bad text:='';
begin
  -- sanity: identities
  perform set_config('request.jwt.claims', json_build_object('sub',v_nocap0::text,'role','authenticated')::text, true);
  if e10.is_org_member(v_org0) and not e10.has_org_cap(v_org0,'act.inventory_edit') and not e10.is_org_admin(v_org0) then ok:=ok+1; else bad:=bad||' nocap_identity'; end if;
  perform set_config('request.jwt.claims', json_build_object('sub',v_multi::text,'role','authenticated')::text, true);
  if e10.current_org() is null then ok:=ok+1; else bad:=bad||' multi_current_org_not_null'; end if;

  -- D1 ws_del: owner deletes its own personal row (USING owner=auth.uid()).
  perform set_config('request.jwt.claims', json_build_object('sub',v_owner::text,'role','authenticated')::text, true);
  delete from public.e10_workspace where id='a6c4_pdel1'; get diagnostics c=row_count;
  if c=1 then ok:=ok+1; else bad:=bad||' D1_owner_del_rows:'||c; end if;
  -- D2 ws_del: a non-owner non-admin member cannot delete another's row (USING excludes => 0 rows).
  perform set_config('request.jwt.claims', json_build_object('sub',v_nocap0::text,'role','authenticated')::text, true);
  delete from public.e10_workspace where id='a6c4_pdel3'; get diagnostics c=row_count;
  if c=0 then ok:=ok+1; else bad:=bad||' D2_nonowner_del_rows:'||c; end if;
  -- D3 ws_del: an org admin deletes an org row via is_org_admin(org).
  perform set_config('request.jwt.claims', json_build_object('sub',v_admin0::text,'role','authenticated')::text, true);
  delete from public.e10_workspace where id='a6c4_pdel2'; get diagnostics c=row_count;
  if c=1 then ok:=ok+1; else bad:=bad||' D3_admin_del_rows:'||c; end if;

  -- D4 missing-cap 'shared' write: a member WITHOUT act.inventory_edit cannot UPDATE the shared row. The 'shared' branch
  -- requires the cap; owner is null (owner branch fails); not admin => ws_upd USING excludes => 0 rows (unshadowable).
  perform set_config('request.jwt.claims', json_build_object('sub',v_nocap0::text,'role','authenticated')::text, true);
  update public.e10_workspace set updated_at=now() where id='shared' and organization_id=v_org0; get diagnostics c=row_count;
  if c=0 then ok:=ok+1; else bad:=bad||' D4_nocap_shared_upd_rows:'||c; end if;

  -- D5 multi-membership fail-closed: v_multi (current_org null) is an org0 admin so ws_upd USING passes on 'shared', but
  -- the WITH CHECK organization_id = current_org() (null) refuses the write. Layer: ws_upd WITH CHECK current_org pin
  -- (and ws_sel new-row visibility) — require SQLSTATE 42501.
  perform set_config('request.jwt.claims', json_build_object('sub',v_multi::text,'role','authenticated')::text, true);
  begin
    update public.e10_workspace set updated_at=now() where id='shared' and organization_id=v_org0;
    bad:=bad||' D5_multi_shared_upd_allowed';   -- USING passed (org0 admin); a successful write means the pin failed to refuse
  exception when sqlstate '42501' then ok:=ok+1; when others then bad:=bad||(' D5_multi_wrongerr:'||SQLSTATE); end;

  -- D6 universal branch: any org member READS 'universal' (ws_sel id-in-set AND is_org_member); a non-admin member cannot
  -- UPDATE it (universal write needs is_org_admin) => 0 rows; an org admin UPDATEs it => 1 row.
  perform set_config('request.jwt.claims', json_build_object('sub',v_nocap0::text,'role','authenticated')::text, true);
  select count(*) into c from public.e10_workspace where id='universal'; if c=1 then ok:=ok+1; else bad:=bad||' D6_member_read_universal:'||c; end if;
  update public.e10_workspace set updated_at=now() where id='universal'; get diagnostics c=row_count;
  if c=0 then ok:=ok+1; else bad:=bad||' D6_nonadmin_universal_upd_rows:'||c; end if;
  perform set_config('request.jwt.claims', json_build_object('sub',v_admin0::text,'role','authenticated')::text, true);
  update public.e10_workspace set updated_at=now() where id='universal'; get diagnostics c=row_count;
  if c=1 then ok:=ok+1; else bad:=bad||' D6_admin_universal_upd_rows:'||c; end if;

  -- D7 owner branch: the owner READS and UPDATEs its own personal row (owner=auth.uid(); WITH CHECK owner=self AND
  -- org=current_org, both true for a single-org owner).
  perform set_config('request.jwt.claims', json_build_object('sub',v_owner::text,'role','authenticated')::text, true);
  select count(*) into c from public.e10_workspace where id='a6c4_pown'; if c=1 then ok:=ok+1; else bad:=bad||' D7_owner_read:'||c; end if;
  update public.e10_workspace set updated_at=now() where id='a6c4_pown'; get diagnostics c=row_count;
  if c=1 then ok:=ok+1; else bad:=bad||' D7_owner_upd_rows:'||c; end if;

  if ok = 12 then raise notice 'A6c.4 workspace disclosures: PASS (12/12 — ws_del owner/admin/non-owner; missing-cap shared write denied; multi-membership fail-closed; universal read-by-member/write-by-admin; owner read+write)';
  else raise exception 'A6c.4 workspace disclosures: FAIL passed=%/12 failures=[%]', ok, bad; end if;
end $$;
reset role;
rollback;
