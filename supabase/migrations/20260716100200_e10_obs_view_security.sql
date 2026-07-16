-- Foundation Gate A4a — obs analytics views SECURITY DEFINER fix (advisor 0010, the only ERROR-level lints).
-- These 4 e10_obs_* views were created WITHOUT security_invoker (so SECURITY DEFINER, bypassing RLS) AND
-- granted SELECT to anon — an active UNAUTHENTICATED internet leak of competitive-intel data via the public
-- anon key. This is the IDENTICAL bug the P0 hotfix (20260715130126_e10_p0_recon_view_security.sql) fixed for
-- the recon views. Same remedy: invoker semantics (the caller's RLS applies) + revoke anon entirely.
-- The underlying e10_obs_* tables are is_org-gated on SELECT, so org members still see everything and anon
-- sees nothing. Not in the prompt's six items, but acceptance = "zero errors" forces it; flagged as a
-- behavior change for anon (closing access they should never have had). Touches zero data.

begin;

alter view public.e10_obs_slot_economics     set (security_invoker = true);
alter view public.e10_obs_break_economics     set (security_invoker = true);
alter view public.e10_obs_product_premium     set (security_invoker = true);
alter view public.e10_obs_format_product_perf set (security_invoker = true);

revoke all on public.e10_obs_slot_economics     from anon;
revoke all on public.e10_obs_break_economics     from anon;
revoke all on public.e10_obs_product_premium     from anon;
revoke all on public.e10_obs_format_product_perf from anon;

commit;

-- ============================================================================
-- DOWN (restores the prior, insecure posture — definer semantics + anon SELECT):
-- begin;
-- alter view public.e10_obs_slot_economics     set (security_invoker = false);
-- alter view public.e10_obs_break_economics     set (security_invoker = false);
-- alter view public.e10_obs_product_premium     set (security_invoker = false);
-- alter view public.e10_obs_format_product_perf set (security_invoker = false);
-- grant select on public.e10_obs_slot_economics     to anon;
-- grant select on public.e10_obs_break_economics     to anon;
-- grant select on public.e10_obs_product_premium     to anon;
-- grant select on public.e10_obs_format_product_perf to anon;
-- commit;
