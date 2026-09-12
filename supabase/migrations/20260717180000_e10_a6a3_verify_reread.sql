-- Foundation Gate A6a.3 — verify-race closure (STAGING/LOCAL only; production untouched). ADDITIVE + idempotent
-- (create-or-replace). Does NOT edit applied migrations 120000 / 130000 / 164942. Per the outside reviewer's A6a.3
-- closure item.
--
-- After acquiring the normalized-handle advisory lock, REREAD the claim and REQUIRE status='pending' (and not
-- expired) BEFORE the conditional update — an explicit, spec-literal post-lock recheck. e10_reject_handle_claim takes
-- NO advisory lock, so a concurrent reject can commit (pending->rejected) while verify is blocked on the lock; the
-- reread now catches that at the pending check, and the conditional `UPDATE ... WHERE status='pending'` remains the
-- backstop for a reject that commits between the reread and the update. Net invariant: a rejected (or expired) claim
-- can never become verified, under any interleaving. Proven concurrently by tests/a6a3_verify_concurrent_test.js.

create or replace function public.e10_verify_handle_claim(p_claim_id uuid)
  returns void language plpgsql security definer set search_path = public as $$
declare v_norm text; v_status text; v_exp timestamptz; v_n integer;
begin
  if not e10.is_platform_admin() then raise exception 'forbidden'; end if;
  -- derive the lock key (handle_norm) from the claim id; ANY status, so the key exists even mid-race
  select handle_norm into v_norm from e10_viewer_handle_claims where id = p_claim_id;
  if v_norm is null then raise exception 'claim_not_found'; end if;
  -- acquire the advisory lock for the normalized handle, THEN reread the claim UNDER the lock
  perform pg_advisory_xact_lock(hashtext(v_norm));
  select status, expires_at into v_status, v_exp from e10_viewer_handle_claims where id = p_claim_id;
  if v_status is null then raise exception 'claim_not_found'; end if;
  if v_status <> 'pending' or v_exp <= now() then raise exception 'claim_not_pending_or_expired'; end if;
  -- recheck: at most one verified owner per handle_norm
  if exists(select 1 from e10_viewer_handle_claims where handle_norm = v_norm and status = 'verified') then
    raise exception 'handle_already_verified';
  end if;
  -- conditional-update backstop: a reject that commits between the reread and here still matches zero rows
  update e10_viewer_handle_claims set status = 'verified', verified_at = now()
   where id = p_claim_id and status = 'pending';
  get diagnostics v_n = row_count;
  if v_n = 0 then raise exception 'claim_not_pending_or_expired'; end if;
end $$;
-- (create-or-replace preserves grants; re-assert posture for safety)
revoke all on function public.e10_verify_handle_claim(uuid) from anon, public;
grant execute on function public.e10_verify_handle_claim(uuid) to authenticated;
