-- Migration: drop e10_test_cleanup  (Chain P — P0R)
-- The prior migration (20260715000000) admin-gated e10_test_cleanup, but a production RPC that can
-- DELETE append-only ledger rows + mutation receipts is a standing liability even behind an admin check.
-- Reviewer standard adopted: production application roles get NO RPC capable of deleting movement or
-- receipt history. Test teardown moves entirely to a service-role script (tests/cleanup.js), off the
-- app's RLS surface. This migration REVOKES every grant then DROPS the exact signature.
--
-- Grants observed live before this migration: postgres, authenticated, service_role (EXECUTE).
-- `revoke ... from public` does NOT strip anon (Supabase default privileges grant anon directly),
-- so anon is revoked explicitly even though it was not listed — DROP removes any remainder regardless.
--
-- ONE-WAY: there is no down migration. Do not recreate this function. Recovery of the *secure* inventory
-- RPCs (if they are ever accidentally replaced) lives in supabase/recovery/m322_safe_function_restore.sql,
-- which restores e10_inv_consume / e10_inv_reverse_consumption only — never this cleanup RPC.

revoke all on function public.e10_test_cleanup(text, uuid[]) from public;
revoke all on function public.e10_test_cleanup(text, uuid[]) from anon;
revoke all on function public.e10_test_cleanup(text, uuid[]) from authenticated;
revoke all on function public.e10_test_cleanup(text, uuid[]) from service_role;

drop function public.e10_test_cleanup(text, uuid[]);

-- Proof (run after apply; expect zero rows):
--   select p.oid::regprocedure::text
--     from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--    where n.nspname = 'public' and p.proname = 'e10_test_cleanup';
