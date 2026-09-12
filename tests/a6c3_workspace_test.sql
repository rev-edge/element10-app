-- Element 10 — A6c.3 workspace policy + CAS gate. Self-failing; transactionally rolled back.
-- Proves the 4 rewritten e10_workspace policies enforce the org boundary and that optimistic-concurrency CAS still works,
-- per plan §6: (1) an org0 member reads and CAS-bumps (org0,'shared'); (2) a stale-rev CAS matches 0 rows (the signal to
-- re-read and merge); (3) an org-B-only member is denied read AND write of org0's 'shared' row; (4) an org-B 'shared'
-- INSERT fails the retained GLOBAL PRIMARY KEY(id); (5) an org0 member cannot re-stamp the row to a foreign org (the
-- WITH CHECK organization_id = current_org() pin). Fixtures built as the migration role (RLS bypassed); assertions run
-- under per-user JWT claims with `set role authenticated`, so RLS is genuinely enforced. Proof standard: exact row-count
-- or specific SQLSTATE per assertion; `exception when others` only as a *_wrongerr recorder; per-assertion layer notes.
begin;

-- ---------- fixtures ----------
do $$
declare
  v_org0 uuid := 'e1000000-0000-4000-8000-0000000000a6';                 -- org0 (owns the single 'shared' row)
  v_orgB uuid := 'e1000000-0000-4000-8000-0000000000d2';                 -- a second org
  v_mgrrole0 uuid := 'e1000000-0000-4000-8000-000000000002';             -- org0 manager role (has act.inventory_edit, key<>'admin')
  v_bmemrole uuid;
  v_m0 uuid := 'a6c31111-0000-4000-8000-00000000000a';                   -- org0 member WITH cap, NOT admin (CAS actor)
  v_mb uuid := 'a6c31111-0000-4000-8000-00000000000b';                   -- org-B-only member WITH cap in org B (denial + PK actor)
begin
  insert into public.e10_organizations(id,name,slug) values (v_orgB,'A6c3 OrgB','a6c3-orgb') on conflict do nothing;
  insert into public.e10_organization_roles(organization_id,key,name) values (v_orgB,'member','Member') returning id into v_bmemrole;
  insert into public.e10_organization_role_permissions(organization_id,role_id,capability,allowed) values
    (v_orgB,v_bmemrole,'act.inventory_edit',true);
  insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at)
    select u,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',replace(u::text,'-','')||'@a6c3.invalid',now(),now()
    from unnest(array[v_m0,v_mb]) u on conflict (id) do nothing;
  insert into public.e10_members(user_id,email,role) values (v_m0,'m0@x','member'),(v_mb,'mb@x','member')
    on conflict (user_id) do update set role=excluded.role;
  insert into public.e10_organization_memberships(organization_id,user_id,role_id,status) values
    (v_org0,v_m0,v_mgrrole0,'active'),                                   -- single org0 membership => current_org()=org0
    (v_orgB,v_mb,v_bmemrole,'active')                                    -- single org-B membership => current_org()=orgB
    on conflict (organization_id,user_id) do update set role_id=excluded.role_id,status='active';
  -- ensure the single org0 'shared' row exists (seed already has it; make idempotent)
  insert into public.e10_workspace(id,organization_id,rev,data) values ('shared',v_org0,1,'{}'::jsonb)
    on conflict (id) do nothing;
end $$;

-- ---------- assertions ----------
set local role authenticated;
do $$
declare
  v_org0 uuid := 'e1000000-0000-4000-8000-0000000000a6';
  v_orgB uuid := 'e1000000-0000-4000-8000-0000000000d2';
  v_m0 uuid := 'a6c31111-0000-4000-8000-00000000000a';
  v_mb uuid := 'a6c31111-0000-4000-8000-00000000000b';
  v_rev0 bigint; v_rev1 bigint; v_cnt int; v_seen int; ok int:=0; bad text:='';
begin
  -- identity sanity: v_m0 is a plain org0 member WITH the cap (not admin); v_mb is org-B-only.
  perform set_config('request.jwt.claims', json_build_object('sub',v_m0::text,'role','authenticated')::text, true);
  if e10.has_org_cap(v_org0,'act.inventory_edit') and not e10.is_org_admin(v_org0) and e10.current_org()=v_org0
    then ok:=ok+1; else bad:=bad||' m0_identity'; end if;
  perform set_config('request.jwt.claims', json_build_object('sub',v_mb::text,'role','authenticated')::text, true);
  if e10.current_org()=v_orgB and not e10.is_org_member(v_org0) then ok:=ok+1; else bad:=bad||' mb_identity'; end if;

  -- (1) org0 member reads + CAS bump. ws_sel makes the row visible; ws_upd 'shared' branch (member + cap) allows the
  -- update; the WITH CHECK current_org pin passes (org unchanged). Row-count outcome, not an exception.
  perform set_config('request.jwt.claims', json_build_object('sub',v_m0::text,'role','authenticated')::text, true);
  select rev into v_rev0 from public.e10_workspace where id='shared' and organization_id=v_org0;
  if v_rev0 is not null then ok:=ok+1; else bad:=bad||' cas_read'; end if;
  update public.e10_workspace set rev=rev+1, updated_at=now()
    where id='shared' and organization_id=v_org0 and rev=v_rev0;
  get diagnostics v_cnt = row_count;
  if v_cnt=1 then ok:=ok+1; else bad:=bad||' cas_bump_rows:'||v_cnt; end if;
  select rev into v_rev1 from public.e10_workspace where id='shared' and organization_id=v_org0;
  if v_rev1 = v_rev0 + 1 then ok:=ok+1; else bad:=bad||' cas_rev_notbumped'; end if;

  -- (2) stale-rev CAS -> 0 rows (rev is now v_rev0+1; matching on v_rev0 hits nothing) -> caller re-reads and merges.
  -- Layer note: the 0 is the rev= CAS predicate, not RLS (RLS still admits the row for this member).
  update public.e10_workspace set rev=rev+1
    where id='shared' and organization_id=v_org0 and rev=v_rev0;
  get diagnostics v_cnt = row_count;
  if v_cnt=0 then ok:=ok+1; else bad:=bad||' stale_cas_rows:'||v_cnt; end if;

  -- (3) org-B-only member denied read AND write of org0's 'shared' row (RLS: not a member of org0, not owner, not
  -- org0-admin). SELECT-count/row-count denial — unshadowable (a read/USING-filtered update raises no exception).
  perform set_config('request.jwt.claims', json_build_object('sub',v_mb::text,'role','authenticated')::text, true);
  select count(*) into v_seen from public.e10_workspace where id='shared' and organization_id=v_org0;
  if v_seen=0 then ok:=ok+1; else bad:=bad||' orgb_read_visible:'||v_seen; end if;
  update public.e10_workspace set data=data where id='shared' and organization_id=v_org0;
  get diagnostics v_cnt = row_count;
  if v_cnt=0 then ok:=ok+1; else bad:=bad||' orgb_write_rows:'||v_cnt; end if;

  -- (4) org-B 'shared' INSERT fails the retained GLOBAL PRIMARY KEY(id). v_mb passes ws_ins WITH CHECK (org-B member +
  -- cap + organization_id=current_org()=orgB), so the ONLY thing that can refuse is the global PK on id='shared'.
  -- Require SQLSTATE 23505 exactly; a 42501 would mean RLS blocked it (different layer) and is a defect for this case.
  begin
    insert into public.e10_workspace(id,organization_id,owner,rev,data) values ('shared',v_orgB,v_mb,0,'{}'::jsonb);
    bad:=bad||' orgb_insert_allowed';
  exception
    when unique_violation then ok:=ok+1;                              -- 23505 = global PRIMARY KEY(id)
    when others then bad:=bad||(' orgb_insert_wrongerr:'||SQLSTATE);
  end;

  -- (5) org0 member cannot re-stamp the row to a foreign org: ws_upd USING passes (org0 member updates the org0 row),
  -- then the org-scoped workspace RLS rejects the org-B-stamped NEW row with 42501. Defense in depth, both org-scoped
  -- and either alone sufficing: (a) the ws_upd WITH CHECK organization_id = current_org() pin (org0 <> current_org),
  -- and (b) the ws_sel SELECT policy, which PostgreSQL applies as a new-row visibility check on UPDATE (the org-B row is
  -- invisible to an org0 member). No FK/unique/trigger fires (orgB exists; (orgB,'shared') composite is free; stamp_org
  -- is BEFORE INSERT only). Require SQLSTATE 42501 exactly; the red/green below removes BOTH org-scoped predicates.
  perform set_config('request.jwt.claims', json_build_object('sub',v_m0::text,'role','authenticated')::text, true);
  begin
    update public.e10_workspace set organization_id=v_orgB where id='shared' and organization_id=v_org0;
    bad:=bad||' xorg_write_allowed';
  exception
    when sqlstate '42501' then ok:=ok+1;                              -- the RLS WITH CHECK refusal
    when others then bad:=bad||(' xorg_write_wrongerr:'||SQLSTATE);
  end;

  if ok = 10 then raise notice 'A6c.3 workspace gate: PASS (CAS bump + stale-merge; org-B read/write denied; global-PK insert refusal 23505; cross-org write refusal 42501 — org-scoped policies enforced)';
  else raise exception 'A6c.3 workspace gate: FAIL passed=%/10 failures=[%]', ok, bad; end if;
end $$;
reset role;
rollback;
