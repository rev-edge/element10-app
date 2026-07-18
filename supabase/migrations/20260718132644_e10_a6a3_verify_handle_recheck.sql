-- Foundation Gate A6a.3 — verify-race closure, completion pass (STAGING/LOCAL only; production untouched).
-- ADDITIVE + idempotent (create-or-replace). Does NOT edit any applied migration (120000/130000/164942/180000).
--
-- Completes the outside-review A6a.3 spec on top of 20260717180000 (which added the post-lock reread). Two
-- refinements this migration adds to e10_verify_handle_claim:
--   (6) the post-lock reread now also REQUIRES the claim still carries the SAME normalized handle we locked
--       (raise claim_handle_changed otherwise), and
--   (8) the conditional UPDATE predicate now includes expires_at > now() in addition to status='pending'.
-- The conditional update is retained even with the reread: it is the backstop against a rejection (or expiry) that
-- commits AFTER the reread but BEFORE the update. e10_reject_handle_claim takes no advisory lock, so that window is
-- real; both the reread and the conditional update together guarantee a rejected/expired claim can never become
-- verified, under any interleaving. Proven concurrently by tests/a6a3_verify_concurrent_test.js.

create or replace function public.e10_verify_handle_claim(p_claim_id uuid)
  returns void language plpgsql security definer set search_path = public as $$
declare v_norm text; v_reread_norm text; v_status text; v_exp timestamptz; v_n integer;
begin
  -- (1) caller must be a platform admin
  if not e10.is_platform_admin() then raise exception 'forbidden'; end if;
  -- (2)(3) read the claim ONLY to obtain its normalized handle (the advisory-lock key)
  select handle_norm into v_norm from e10_viewer_handle_claims where id = p_claim_id;
  if v_norm is null then raise exception 'claim_not_found'; end if;
  -- (4) acquire the transaction advisory lock for that normalized handle
  perform pg_advisory_xact_lock(hashtext(v_norm));
  -- (5) reread the target claim by id UNDER the lock
  select handle_norm, status, expires_at into v_reread_norm, v_status, v_exp
    from e10_viewer_handle_claims where id = p_claim_id;
  -- (6) require: still exists, still carries the locked normalized handle, still pending, not expired
  if v_reread_norm is null then raise exception 'claim_not_found'; end if;
  if v_reread_norm <> v_norm then raise exception 'claim_handle_changed'; end if;
  if v_status <> 'pending' or v_exp <= now() then raise exception 'claim_not_pending_or_expired'; end if;
  -- (7) recheck under the lock: no verified owner already exists for this normalized handle
  if exists(select 1 from e10_viewer_handle_claims where handle_norm = v_norm and status = 'verified') then
    raise exception 'handle_already_verified';
  end if;
  -- (8) conditional-update backstop: id + still pending + not expired
  update e10_viewer_handle_claims set status = 'verified', verified_at = now()
   where id = p_claim_id and status = 'pending' and expires_at > now();
  -- (9) zero rows updated -> clean, stable error
  get diagnostics v_n = row_count;
  if v_n = 0 then raise exception 'claim_not_pending_or_expired'; end if;
end $$;
-- (10) preserve the authenticated-only execution posture; anon/PUBLIC explicitly revoked
revoke all on function public.e10_verify_handle_claim(uuid) from anon, public;
grant execute on function public.e10_verify_handle_claim(uuid) to authenticated;
