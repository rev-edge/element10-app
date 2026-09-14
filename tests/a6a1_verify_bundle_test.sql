-- Element 10 — A6a.1 tests (handle-verify race + module_bundle). Self-failing: any assertion RAISEs, so
-- `psql -v ON_ERROR_STOP=1` exits non-zero and CI fails. Run against the local/staging stack AS THE MIGRATION
-- ROLE (postgres). The verify block runs inside a transaction that ROLLS BACK — no side effects.
--   Run: psql "<db url>" -v ON_ERROR_STOP=1 -f tests/a6a1_verify_bundle_test.sql

-- (d) module_bundle: all six legacy keys → 'core'; unknown → null
do $$ begin
  if not (e10.module_bundle('home')='core' and e10.module_bundle('inventory')='core'
      and e10.module_bundle('reporting')='core' and e10.module_bundle('schedule')='core'
      and e10.module_bundle('settings')='core' and e10.module_bundle('toolkit')='core'
      and e10.module_bundle('not-a-key') is null) then
    raise exception 'A6a.1 module_bundle FAIL';
  end if;
  raise notice 'A6a.1 module_bundle: PASS (6 keys -> core, unknown -> null)';
end $$;

-- (a,b,c) verify race — inside a rolled-back transaction (seeds a platform admin from a member, sets its jwt,
-- exercises the RPC, asserts). No committed changes.
begin;
do $$
declare v_padmin uuid; id1 uuid; id2 uuid; id3 uuid; id4 uuid; v_ok boolean;
begin
  select user_id into v_padmin from public.e10_members order by created_at limit 1;
  if v_padmin is null then raise notice 'A6a.1 verify: SKIP (bare env, no members to act as platform admin)'; return; end if;
  insert into public.e10_platform_admins(user_id) values (v_padmin) on conflict do nothing;
  perform set_config('request.jwt.claims', json_build_object('sub', v_padmin::text, 'role','authenticated')::text, true);

  -- (c) two pending claims on one handle → first verify wins, second → handle_already_verified
  insert into public.e10_viewer_handle_claims(user_id,whatnot_handle,status,expires_at) values (v_padmin,'a6a1race','pending',now()+interval '7 days') returning id into id1;
  insert into public.e10_viewer_handle_claims(user_id,whatnot_handle,status,expires_at) values (v_padmin,'a6a1race','pending',now()+interval '7 days') returning id into id2;
  perform public.e10_verify_handle_claim(id1);   -- first must succeed
  v_ok := false; begin perform public.e10_verify_handle_claim(id2); exception when others then v_ok := sqlerrm like '%handle_already_verified%'; end;
  if not v_ok then raise exception 'A6a.1 FAIL(c): second verify did not raise handle_already_verified'; end if;

  -- (a) reject-then-verify → claim_not_pending_or_expired (the race's deterministic equivalent)
  insert into public.e10_viewer_handle_claims(user_id,whatnot_handle,status,expires_at) values (v_padmin,'a6a1rej','pending',now()+interval '7 days') returning id into id3;
  perform public.e10_reject_handle_claim(id3);
  v_ok := false; begin perform public.e10_verify_handle_claim(id3); exception when others then v_ok := sqlerrm like '%claim_not_pending_or_expired%'; end;
  if not v_ok then raise exception 'A6a.1 FAIL(a): verify of a rejected claim did not raise claim_not_pending_or_expired'; end if;

  -- (b) expired pending claim → verify → claim_not_pending_or_expired
  insert into public.e10_viewer_handle_claims(user_id,whatnot_handle,status,created_at,expires_at) values (v_padmin,'a6a1exp','pending',now()-interval '8 days',now()-interval '1 day') returning id into id4;
  v_ok := false; begin perform public.e10_verify_handle_claim(id4); exception when others then v_ok := sqlerrm like '%claim_not_pending_or_expired%'; end;
  if not v_ok then raise exception 'A6a.1 FAIL(b): verify of an expired claim did not raise claim_not_pending_or_expired'; end if;

  raise notice 'A6a.1 verify race: PASS (a reject->not_pending, b expired->not_pending, c second->already_verified)';
end $$;
rollback;
