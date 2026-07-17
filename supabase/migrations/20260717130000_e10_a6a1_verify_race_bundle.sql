-- Foundation Gate A6a.1 — corrective (STAGING/LOCAL only; production untouched). Narrow: does NOT rewrite the
-- applied A6a migration. Idempotent (create-or-replace). Per the A6a.1 build prompt + ADR 0005.
--
-- (1) Race-free e10_verify_handle_claim: the status/expiry condition ON THE UPDATE is the fix — a concurrent
--     rejection or an expiry can never be overwritten, regardless of interleaving.
-- (2) e10.module_bundle(): encodes the confirmed ruling (2026-07-17) that ALL SIX legacy module keys map to the
--     'core' bundle (the client's Live Toolkit contains Ship/fulfillment, which is core in DOMAIN_MAP; a 'cards'
--     mapping would strip fulfillment from future non-cards orgs; cards gating arrives with the new frontend's
--     own concrete keys).

-- (1) --------------------------------------------------------------------------------------------------------
create or replace function public.e10_verify_handle_claim(p_claim_id uuid)
  returns void language plpgsql security definer set search_path = public as $$
declare v_norm text; v_n integer;
begin
  -- a) platform-admin check
  if not e10.is_platform_admin() then raise exception 'forbidden'; end if;
  -- b) read the claim's handle_norm by id (any status) — just to derive the lock key
  select handle_norm into v_norm from e10_viewer_handle_claims where id = p_claim_id;
  if v_norm is null then raise exception 'claim_not_found'; end if;
  -- c) serialize per handle
  perform pg_advisory_xact_lock(hashtext(v_norm));
  -- d) under the lock: at most one verified owner per handle_norm
  if exists(select 1 from e10_viewer_handle_claims where handle_norm = v_norm and status = 'verified') then
    raise exception 'handle_already_verified';
  end if;
  -- e) conditional update — a concurrent reject/expiry can never be overwritten
  update e10_viewer_handle_claims
     set status = 'verified', verified_at = now()
   where id = p_claim_id and status = 'pending' and expires_at > now();
  get diagnostics v_n = row_count;
  if v_n = 0 then raise exception 'claim_not_pending_or_expired'; end if;
end $$;
-- (create-or-replace preserves the A6a authenticated grant; re-assert posture for safety)
revoke all on function public.e10_verify_handle_claim(uuid) from anon, public;
grant execute on function public.e10_verify_handle_claim(uuid) to authenticated;

-- (2) --------------------------------------------------------------------------------------------------------
-- module → bundle ownership. IMMUTABLE (pure CASE, no table access). Private-by-default like the other e10
-- predicates. ALL SIX legacy keys → 'core'; unknown key → null.
create or replace function e10.module_bundle(p_key text) returns text
  language sql immutable set search_path = '' as $$   -- pure CASE; references nothing (pins search_path per house rule)
  select case p_key
    when 'home'      then 'core'
    when 'inventory' then 'core'
    when 'reporting' then 'core'
    when 'schedule'  then 'core'
    when 'settings'  then 'core'
    when 'toolkit'   then 'core'
    else null
  end;
$$;
revoke all on function e10.module_bundle(text) from anon, public;
grant execute on function e10.module_bundle(text) to authenticated;
