-- Foundation Gate A4a, item 4 tail — pin the one mutable search_path + tighten anon EXECUTE.
-- Advisor 0011 flags e10_obs_apply_repack_cost: SECURITY INVOKER, proconfig=null (no pinned search_path),
-- and executable by anon via PUBLIC. Pin search_path=public (every other e10_* function is already pinned)
-- and revoke anon/PUBLIC EXECUTE (an obs cost-writer that anon has no business calling).
-- Also revoke anon/PUBLIC EXECUTE on the two other invoker obs/slot helpers that read org data
-- (e10_slot_pred, e10_checklist_facet) — they already pin search_path; this is grant-posture consistency.
-- All keep authenticated + service_role EXECUTE (their legitimate callers). Touches zero data.

begin;

alter function public.e10_obs_apply_repack_cost() set search_path = public;

revoke execute on function public.e10_obs_apply_repack_cost()            from anon, public;
revoke execute on function public.e10_slot_pred(jsonb)                   from anon, public;
revoke execute on function public.e10_checklist_facet(uuid, text)       from anon, public;

commit;

-- ============================================================================
-- DOWN (restore prior posture — no pinned search_path, PUBLIC/anon EXECUTE):
-- begin;
-- alter function public.e10_obs_apply_repack_cost() reset search_path;
-- grant execute on function public.e10_obs_apply_repack_cost()      to anon, public;
-- grant execute on function public.e10_slot_pred(jsonb)             to anon, public;
-- grant execute on function public.e10_checklist_facet(uuid, text)  to anon, public;
-- commit;
