-- Recovery / down path for migration 20260716100500_e10_grant_parity_fixups.sql (A4a).
-- Immutable-migration convention: the applied migration is never edited; its full reversal lives here
-- (the migration's in-file down-block was elided with "…"; this is the complete, tested version).
--
-- ⚠ Running this REVERSES the A4 grant-parity hardening: it re-grants anon EXECUTE on the SECURITY DEFINER
-- surface (and anon+authenticated on the internal helpers), and recreates the cards-bucket list policy.
-- Only run to unwind A4a's parity fixup deliberately. Run as the migration role (postgres).

begin;

-- (1a) internal helpers: restore anon + authenticated EXECUTE (pre-fixup baseline state)
grant execute on function public._e10_inv_blob_write(text, boolean, text)                     to anon, authenticated;
grant execute on function public._e10_inv_clamp_res(text, text)                               to anon, authenticated;
grant execute on function public._e10_inv_guard()                                             to anon, authenticated;
grant execute on function public._e10_inv_item_json(text)                                     to anon, authenticated;
grant execute on function public._e10_inv_receipt(text, text, text, jsonb)                    to anon, authenticated;
grant execute on function public._e10_inv_receipt_check(text, text, text, text)               to anon, authenticated;
grant execute on function public._e10_inv_receipt_write(text, text, text, text, uuid)         to anon, authenticated;
grant execute on function public._e10_inv_replay(text)                                        to anon, authenticated;
grant execute on function public._e10_inv_replay_json(text, jsonb)                            to anon, authenticated;

-- (1b) public API + RLS-predicate helpers: restore anon EXECUTE (authenticated was retained by the fixup)
grant execute on function public.e10_add_member(text)                                         to anon;
grant execute on function public.e10_add_viewer(text)                                         to anon;
grant execute on function public.e10_assign_role(uuid, text)                                  to anon;
grant execute on function public.e10_buyer_suggest(uuid, text)                                to anon;
grant execute on function public.e10_can_read_session(uuid)                                   to anon;
grant execute on function public.e10_emit_inventory_movement(text, text, numeric, numeric, text, text, text, text, text, text, uuid, jsonb) to anon;
grant execute on function public.e10_has_cap(text)                                            to anon;
grant execute on function public.e10_inv_add_item(jsonb, text)                                to anon;
grant execute on function public.e10_inv_consume(text, text, text, numeric, text)             to anon;
grant execute on function public.e10_inv_delete_item(text, text)                              to anon;
grant execute on function public.e10_inv_edit_item(text, jsonb, text, text[])                 to anon;
grant execute on function public.e10_inv_get(text)                                            to anon;
grant execute on function public.e10_inv_list()                                               to anon;
grant execute on function public.e10_inv_mark_sold(text, numeric, numeric, text)              to anon;
grant execute on function public.e10_inv_release(text, text, text)                            to anon;
grant execute on function public.e10_inv_reserve(text, text, text, numeric, text)             to anon;
grant execute on function public.e10_inv_reverse_consumption(text, uuid, text)                to anon;
grant execute on function public.e10_inv_set_reservations(text, text, jsonb, text)            to anon;
grant execute on function public.e10_is_admin()                                               to anon;
grant execute on function public.e10_is_member()                                              to anon;
grant execute on function public.e10_is_org()                                                 to anon;
grant execute on function public.e10_my_handle()                                              to anon;
grant execute on function public.e10_owns_session(uuid)                                        to anon;
grant execute on function public.e10_redeem_code(text)                                        to anon;
grant execute on function public.e10_set_role(uuid, text)                                     to anon;

-- (2) recreate the cards-bucket SELECT policy (authenticated-scoped, as 20260716100400 left it before 100500 dropped it)
drop policy if exists "cards public read" on storage.objects;
create policy "cards public read" on storage.objects for select to authenticated using (bucket_id = 'cards');

commit;
