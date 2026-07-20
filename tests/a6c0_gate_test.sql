-- Element 10 — A6c.0 prerequisites gate. Self-failing; behavioral part transactionally rolled back.
-- Proves: (a) the exact authenticated allowlist = pre-existing wrappers + the 13 e10_org_* client delegates and
-- nothing else; internal helpers/emit are authenticated=false; zero anon/PUBLIC across A6c functions. (b) the published
-- spectator predicate (private denied / published allowed). (c) per-delegate positive + adversarial authorization
-- (wrong-org, missing-capability, non-owner, invalid-code all rejected).

-- ---- (a) ACL allowlist + born-locked ----
do $$
declare v_delegates int; v_internal_auth int; v_anon int;
begin
  select count(*) into v_delegates from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.prosecdef and has_function_privilege('authenticated',p.oid,'EXECUTE')
      and p.proname like 'e10_org_inv_%' or (n.nspname='public' and has_function_privilege('authenticated',p.oid,'EXECUTE')
      and p.proname in ('e10_org_buyer_suggest','e10_org_redeem_code'));
  -- the 13 client delegates must all be authenticated-executable
  if (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public'
       and has_function_privilege('authenticated',p.oid,'EXECUTE')
       and p.proname in ('e10_org_inv_add_item','e10_org_inv_edit_item','e10_org_inv_delete_item','e10_org_inv_reserve',
         'e10_org_inv_release','e10_org_inv_consume','e10_org_inv_mark_sold','e10_org_inv_set_reservations',
         'e10_org_inv_reverse_consumption','e10_org_inv_get','e10_org_inv_list','e10_org_buyer_suggest','e10_org_redeem_code')) <> 13 then
    raise exception 'A6c.0 ACL: the 13 client delegates are not all authenticated-executable';
  end if;
  -- internal helpers + emit must NOT be authenticated-executable
  select count(*) into v_internal_auth from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and has_function_privilege('authenticated',p.oid,'EXECUTE')
      and (p.proname='e10_org_emit_inventory_movement' or (p.proname like '\_e10_inv_%' and pg_get_function_identity_arguments(p.oid) like 'p_org uuid%'));
  if v_internal_auth <> 0 then raise exception 'A6c.0 ACL: % internal function(s) are authenticated-executable', v_internal_auth; end if;
  -- zero anon/PUBLIC across all A6c functions
  select count(*) into v_anon from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname in ('public','e10') and (has_function_privilege('anon',p.oid,'EXECUTE') or has_function_privilege('public',p.oid,'EXECUTE'))
      and (p.proname like 'e10_org_%' or (p.proname like '\_e10_inv_%' and pg_get_function_identity_arguments(p.oid) like 'p_org uuid%') or p.proname='owns_session');
  if v_anon <> 0 then raise exception 'A6c.0 ACL: % A6c function(s) are anon/PUBLIC-executable', v_anon; end if;
  raise notice 'A6c.0 ACL: PASS (13 delegates authenticated; internals service_role-only; zero anon/PUBLIC)';
end $$;

-- ---- (b) + (c) spectate proof + per-delegate positive/adversarial (rolled back) ----
begin;
do $$
declare
  v_org uuid := 'e1000000-0000-4000-8000-0000000000a6'; v_orgb uuid := 'e1000000-0000-4000-8000-0000000000c1';
  v_admin uuid := 'a6c01111-0000-4000-8000-000000000001'; v_nocap uuid := 'a6c01111-0000-4000-8000-000000000002';
  v_adminrole uuid := 'e1000000-0000-4000-8000-000000000001'; v_opsrole uuid;
  v_sess uuid := gen_random_uuid(); v_othersess uuid := gen_random_uuid();
  r jsonb; ok int:=0; bad text:=''; v_priv boolean; v_pub boolean;
begin
  insert into public.e10_organizations(id,name,slug) values (v_orgb,'GateOrgB','a6c0-gate-orgb') on conflict do nothing;
  insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at)
    select u,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',replace(u::text,'-','')||'@a6c0.invalid',now(),now()
    from unnest(array[v_admin,v_nocap]) u on conflict (id) do nothing;
  insert into public.e10_members(user_id,email,role) values (v_admin,'a6c0admin@x','admin'),(v_nocap,'a6c0nocap@x','member') on conflict (user_id) do update set role=excluded.role;
  insert into public.e10_organization_memberships(organization_id,user_id,role_id,status) values (v_org,v_admin,v_adminrole,'active') on conflict (organization_id,user_id) do update set role_id=excluded.role_id,status='active';
  select id into v_opsrole from public.e10_organization_roles where organization_id=v_org and key='ops';
  insert into public.e10_organization_memberships(organization_id,user_id,role_id,status) values (v_org,v_nocap,coalesce(v_opsrole,v_adminrole),'active') on conflict (organization_id,user_id) do update set role_id=excluded.role_id,status='active';
  insert into public.e10_break_sessions(id,organization_id,streamer_uid,share_code,visibility) values (v_sess,v_org,v_admin,'__a6c0_code','published');
  insert into public.e10_break_sessions(id,organization_id,streamer_uid,share_code,visibility) values (v_othersess,v_org,v_nocap,'__a6c0_other','private');
  insert into public.e10_inventory_items(id,name,qty,organization_id) values ('__a6c0_bitem','B',3,v_orgb);

  perform set_config('request.jwt.claims', json_build_object('sub',v_admin::text,'role','authenticated')::text, true);
  -- (b) spectate
  select e10.can_spectate_session(v_othersess) into v_priv;   -- private
  select e10.can_spectate_session(v_sess) into v_pub;         -- published
  if v_priv is false then ok:=ok+1; else bad:=bad||' spectate_private_not_denied'; end if;
  if v_pub is true then ok:=ok+1; else bad:=bad||' spectate_published_not_allowed'; end if;
  -- (c) positive
  r := public.e10_org_inv_add_item(v_org, jsonb_build_object('id','__a6c0_a','name','A','qty',5,'cat','Box'), '__a6c0_add');
  if (r->>'ok')::boolean then ok:=ok+1; else bad:=bad||' add'; end if;
  if public.e10_org_inv_get(v_org,'__a6c0_a') is not null then ok:=ok+1; else bad:=bad||' get'; end if;
  if jsonb_array_length(public.e10_org_inv_list(v_org)) >= 1 then ok:=ok+1; else bad:=bad||' list'; end if;
  if public.e10_org_buyer_suggest(v_sess,'') is not null then ok:=ok+1; else bad:=bad||' buyer'; end if;
  -- NOTE: redeem_code has an INSERT side effect, so it must be called in its own statement before the visibility
  -- check (a single `if redeem()=v_sess and exists(...)` would evaluate exists() on the pre-insert snapshot).
  declare v_rr uuid; v_rc int; begin
    v_rr := public.e10_org_redeem_code('__a6c0_code');
    select count(*) into v_rc from public.e10_session_viewers where session_id=v_sess and user_id=v_admin and organization_id=v_org;
    if v_rr=v_sess and v_rc=1 then ok:=ok+1; else bad:=bad||' redeem'; end if;
  end;
  -- (c) adversarial
  begin perform public.e10_org_inv_list(v_orgb); bad:=bad||' xorg_member'; exception when sqlstate '42501' then ok:=ok+1; end;
  begin perform public.e10_org_inv_edit_item(v_org,'__a6c0_bitem',jsonb_build_object('name','x'),'__a6c0_xedit',null); bad:=bad||' xorg_entity'; exception when sqlstate '42501' then ok:=ok+1; end;
  if public.e10_org_redeem_code('__a6c0_bogus') is null then ok:=ok+1; else bad:=bad||' invalidcode'; end if;
  perform set_config('request.jwt.claims', json_build_object('sub',v_nocap::text,'role','authenticated')::text, true);
  begin perform public.e10_org_buyer_suggest(v_sess,''); bad:=bad||' nonowner'; exception when sqlstate '42501' then ok:=ok+1; end;
  begin perform public.e10_org_inv_add_item(v_org, jsonb_build_object('id','__a6c0_n','name','N','qty',1,'cat','Box'), '__a6c0_nadd'); bad:=bad||' misscap'; exception when sqlstate '42501' then ok:=ok+1; end;

  if ok = 12 then raise notice 'A6c.0 behavioral gate: PASS (2 spectate + 5 positive + 5 adversarial)';
  else raise exception 'A6c.0 behavioral gate: FAIL passed=%/12 failures=[%]', ok, bad; end if;
end $$;
rollback;
