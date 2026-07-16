-- Foundation Gate A4a — grant/policy PARITY FIXUPS surfaced by the staging advisor run.
-- (Append-only: this does NOT rewrite the already-applied A4a migrations; it layers the corrections on top,
--  same pattern as 00000000000002_e10_baseline_grant_fixups.sql for table grants.)
--
-- Two gaps the staging (reproduced-from-migrations) environment revealed that LOCAL could not:
--
-- (1) anon EXECUTE on SECURITY DEFINER functions. Production has anon revoked on every e10_*/_e10_* secdef
--     function (verified: their ACLs carry authenticated + service_role only, no anon/PUBLIC). The A1 squashed
--     baseline, however, re-grants anon EXECUTE — so staging/local/CI ended up LESS locked down than prod
--     (advisor 0029 anon_security_definer_function_executable, 33 fns). Revoke anon + PUBLIC to match prod.
--     Idempotent NO-OP on prod (revoking an absent grant does nothing). The internal _e10_inv_* helpers get
--     authenticated revoked too (prod = postgres + service_role only). e10_schema_version is already correct.
--
-- (2) The 'cards' bucket "cards public read" SELECT policy. 20260716100400 scoped it to authenticated, but
--     advisor 0025 still fires for ANY broad SELECT policy on a public bucket, and the app NEVER lists the
--     bucket (only .upload() + .getPublicUrl(); public buckets serve object URLs with no SELECT policy).
--     So drop it entirely — image URLs keep working, listing is fully closed. Supersedes the 100400 scope.
--
-- Touches zero data.

begin;

-- ── (1a) internal helpers: match prod (postgres + service_role only) ──
revoke execute on function public._e10_inv_blob_write(text, boolean, text)                     from anon, authenticated, public;
revoke execute on function public._e10_inv_clamp_res(text, text)                               from anon, authenticated, public;
revoke execute on function public._e10_inv_guard()                                             from anon, authenticated, public;
revoke execute on function public._e10_inv_item_json(text)                                     from anon, authenticated, public;
revoke execute on function public._e10_inv_receipt(text, text, text, jsonb)                    from anon, authenticated, public;
revoke execute on function public._e10_inv_receipt_check(text, text, text, text)               from anon, authenticated, public;
revoke execute on function public._e10_inv_receipt_write(text, text, text, text, uuid)         from anon, authenticated, public;
revoke execute on function public._e10_inv_replay(text)                                        from anon, authenticated, public;
revoke execute on function public._e10_inv_replay_json(text, jsonb)                            from anon, authenticated, public;

-- ── (1b) public API + RLS-predicate helpers: revoke anon/PUBLIC, keep authenticated (match prod) ──
revoke execute on function public.e10_add_member(text)                                         from anon, public;
revoke execute on function public.e10_add_viewer(text)                                         from anon, public;
revoke execute on function public.e10_assign_role(uuid, text)                                  from anon, public;
revoke execute on function public.e10_buyer_suggest(uuid, text)                                from anon, public;
revoke execute on function public.e10_can_read_session(uuid)                                   from anon, public;
revoke execute on function public.e10_emit_inventory_movement(text, text, numeric, numeric, text, text, text, text, text, text, uuid, jsonb) from anon, public;
revoke execute on function public.e10_has_cap(text)                                            from anon, public;
revoke execute on function public.e10_inv_add_item(jsonb, text)                                from anon, public;
revoke execute on function public.e10_inv_consume(text, text, text, numeric, text)             from anon, public;
revoke execute on function public.e10_inv_delete_item(text, text)                              from anon, public;
revoke execute on function public.e10_inv_edit_item(text, jsonb, text, text[])                 from anon, public;
revoke execute on function public.e10_inv_get(text)                                            from anon, public;
revoke execute on function public.e10_inv_list()                                               from anon, public;
revoke execute on function public.e10_inv_mark_sold(text, numeric, numeric, text)              from anon, public;
revoke execute on function public.e10_inv_release(text, text, text)                            from anon, public;
revoke execute on function public.e10_inv_reserve(text, text, text, numeric, text)             from anon, public;
revoke execute on function public.e10_inv_reverse_consumption(text, uuid, text)                from anon, public;
revoke execute on function public.e10_inv_set_reservations(text, text, jsonb, text)            from anon, public;
revoke execute on function public.e10_is_admin()                                               from anon, public;
revoke execute on function public.e10_is_member()                                              from anon, public;
revoke execute on function public.e10_is_org()                                                 from anon, public;
revoke execute on function public.e10_my_handle()                                              from anon, public;
revoke execute on function public.e10_owns_session(uuid)                                        from anon, public;
revoke execute on function public.e10_redeem_code(text)                                        from anon, public;
revoke execute on function public.e10_set_role(uuid, text)                                     from anon, public;

-- ── (2) drop the unneeded cards-bucket SELECT policy (app never lists; public bucket serves URLs) ──
drop policy if exists "cards public read" on storage.objects;

commit;

-- ============================================================================
-- DOWN (restore the pre-fixup, less-locked posture):
-- begin;
-- -- re-grant anon EXECUTE (public API + helpers) and anon+authenticated (internal), matching the baseline:
-- grant execute on function public._e10_inv_blob_write(text, boolean, text)             to anon, authenticated;
-- -- (…the other 8 _e10_inv_* to anon, authenticated…)
-- grant execute on function public.e10_inv_list()                                       to anon;
-- -- (…the other public API + helper fns to anon…)
-- -- restore the authenticated-scoped list policy (as 20260716100400 left it):
-- create policy "cards public read" on storage.objects for select to authenticated using (bucket_id = 'cards');
-- commit;
