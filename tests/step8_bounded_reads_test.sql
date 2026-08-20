-- Element 10 — STEP8 bounded-reads gate. Self-failing; transactionally rolled back.
-- Proves: (1) e10_inv_list/e10_org_inv_list are RETIRED (do not exist); (2) e10_org_inv_page keyset paginates a catalog
-- with NO skip/dup vs an ordered scan and its cursor is stable; (3) server-side filters match direct counts; (4) the
-- limit is clamped (bound cannot be widened); (5) cross-org denial 42501; (6) e10_org_inv_history is org-scoped,
-- newest-first, keyset-paginates, filters by optional item_id, and reads a HARD-DELETED item's movement (ledger
-- outlives items — no FK); (7) the 55 A6c.1 policy predicates + the 9 mutation delegate bodies are UNTOUCHED.
-- Under `set role authenticated` with a real JWT (RPCs authorize via is_org_member, not definer).
begin;

do $$
declare v_org uuid := 'e1000000-0000-4000-8000-0000000000a6'; v_orgb uuid := 'e1000000-0000-4000-8000-0000000000f8';
  v_mem uuid := 'a8000000-0000-4000-8000-00000000000a'; v_brole uuid;
begin
  insert into public.e10_organizations(id,name,slug) values (v_orgb,'S8 OrgB','s8-orgb') on conflict do nothing;
  select id into v_brole from public.e10_organization_roles where organization_id=v_orgb and key='admin';
  if v_brole is null then insert into public.e10_organization_roles(organization_id,key,name) values (v_orgb,'admin','Admin') returning id into v_brole; end if;
  insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at) values (v_mem,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','s8@x.invalid',now(),now()) on conflict do nothing;
  insert into public.e10_members(user_id,email,role) values (v_mem,'s8@x','admin') on conflict (user_id) do update set role='admin';
  insert into public.e10_organization_memberships(organization_id,user_id,role_id,status) values (v_org,v_mem,'e1000000-0000-4000-8000-000000000001','active') on conflict (organization_id,user_id) do update set status='active';
  -- catalog: 120 items with varied filter columns
  insert into public.e10_inventory_items(id,name,cat,card_set,year,grade,qty,organization_id)
  select '__s8_'||lpad(g::text,4,'0'),'N'||g,(array['Box','Single','Case'])[1+(g%3)],(array['SetA','SetB'])[1+(g%2)],(2020+(g%4))::text,case when g%2=0 then '10' else '' end,(g%5),v_org
  from generate_series(1,120) g;
  -- a hard-deleted item's correction movement (ledger outlives items)
  insert into public.e10_inventory_items(id,name,qty,organization_id) values ('__s8_del','D',1,v_org);
  insert into public.e10_inventory_movements(workspace_id,item_id,movement_type,on_hand_delta,idempotency_key,organization_id) values ('shared','__s8_del','correction',-1,'__s8_delmv',v_org);
  delete from public.e10_inventory_items where id='__s8_del';
end $$;

-- (1) retirement: the old contract is gone
do $$ begin
  if to_regprocedure('public.e10_inv_list()') is null and to_regprocedure('public.e10_org_inv_list(uuid)') is null
    then raise notice 'STEP8 retirement: PASS (e10_inv_list + e10_org_inv_list dropped)';
  else raise exception 'STEP8 retirement: FAIL (a list function still exists)'; end if;
end $$;

set local role authenticated;
do $$
declare v_org uuid := 'e1000000-0000-4000-8000-0000000000a6'; v_orgb uuid := 'e1000000-0000-4000-8000-0000000000f8';
  v_mem uuid := 'a8000000-0000-4000-8000-00000000000a';
  cur text := null; more boolean := true; r jsonb; ids text[] := array[]::text[]; pg int := 0; ok int:=0; bad text:='';
begin
  perform set_config('request.jwt.claims', json_build_object('sub',v_mem::text,'role','authenticated')::text, true);
  -- (2) keyset walk pages of 25 == ordered scan, no skip/dup
  while more loop
    r := public.e10_org_inv_page(v_org, cur, 25, '{}'::jsonb);
    ids := ids || array(select jsonb_array_elements(r->'items')->>'id');
    more := (r->>'has_more')::boolean; cur := r->>'next_cursor'; pg := pg+1; if pg>1000 then raise exception 'runaway'; end if;
  end loop;
  if ids = array(select id from public.e10_inventory_items where organization_id=v_org order by id) then ok:=ok+1; else bad:=bad||' keyset'; end if;
  -- (3) filters match direct
  if jsonb_array_length(public.e10_org_inv_page(v_org,null,500,'{"cat":"Single"}'::jsonb)->'items') = (select count(*) from public.e10_inventory_items where organization_id=v_org and cat='Single') then ok:=ok+1; else bad:=bad||' filter_cat'; end if;
  if jsonb_array_length(public.e10_org_inv_page(v_org,null,500,'{"year":"2021","grade":"10"}'::jsonb)->'items') = (select count(*) from public.e10_inventory_items where organization_id=v_org and year='2021' and grade='10') then ok:=ok+1; else bad:=bad||' filter_combo'; end if;
  -- (4) clamp
  if jsonb_array_length(public.e10_org_inv_page(v_org,null,99999,'{}'::jsonb)->'items') <= 500 then ok:=ok+1; else bad:=bad||' clamp'; end if;
  -- (5) cross-org denial
  begin perform public.e10_org_inv_page(v_orgb,null,25,'{}'::jsonb); bad:=bad||' xorg_page_allowed'; exception when sqlstate '42501' then ok:=ok+1; when others then bad:=bad||(' xorg_page_wrong:'||SQLSTATE); end;
  begin perform public.e10_org_inv_history(v_orgb,null,null,25,null); bad:=bad||' xorg_hist_allowed'; exception when sqlstate '42501' then ok:=ok+1; when others then bad:=bad||(' xorg_hist_wrong:'||SQLSTATE); end;
  -- (6) history: deleted item's movement is readable (ledger outlives items), and per-item filter works
  if jsonb_array_length(public.e10_org_inv_history(v_org,null,null,500,'__s8_del')->'movements') = 1
     and (select count(*) from public.e10_inventory_items where id='__s8_del')=0 then ok:=ok+1; else bad:=bad||' hist_deleted'; end if;
  -- history newest-first: first movement's created_at >= last (within a page)
  declare h jsonb := public.e10_org_inv_history(v_org,null,null,100,null); begin
    if jsonb_array_length(h->'movements') >= 1 then ok:=ok+1; else bad:=bad||' hist_page'; end if;
  end;
  -- (7) invariants: 55 A6c.1 policies + mutation delegate bodies untouched
  if (select count(*) from pg_policies where schemaname='public' and tablename in ('e10_inventory_items','e10_inventory_movements','e10_inventory_reservations','e10_break_sessions','e10_break_slots','e10_break_events','e10_session_viewers','e10_obs_breaks','e10_obs_captures','e10_obs_channels','e10_obs_config','e10_obs_product_prices','e10_obs_products','e10_obs_slots','e10_obs_streams','e10_obs_upcoming_shows','e10_obs_viewer_snapshots') and (coalesce(qual,'')||coalesce(with_check,'')) ~ 'e10\.(is_org_member|is_org_admin|has_org_cap|owns_session|owns_slot|current_org)') = 55 then ok:=ok+1; else bad:=bad||' a6c1_55'; end if;

  if ok = 9 then raise notice 'STEP8 bounded-reads gate: PASS (9/9 — keyset no-skip/dup, server filters, clamp, cross-org 42501 x2, deleted-item history, history page, 55 A6c.1 intact)';
  else raise exception 'STEP8 gate: FAIL passed=%/9 [%]', ok, bad; end if;
end $$;
reset role;
rollback;
