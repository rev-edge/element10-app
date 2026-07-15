-- P0 hotfix (2026-07-15, applied by reviewer with Trent's knowledge):
-- M4's read-source migration recreated the recon views WITHOUT security_invoker,
-- making them SECURITY DEFINER (bypassing RLS) AND leaving SELECT granted to anon —
-- unauthenticated internet access via the public anon key. Supabase advisor 0010.
-- Fix: invoker semantics (caller's RLS applies) + revoke anon entirely.
-- NOTE FOR REPO: this migration must be committed to supabase/migrations/ verbatim
-- as part of the Foundation Gate's reproducibility work. Do not rewrite it.
alter view public.e10_inventory_recon set (security_invoker = true);
alter view public.e10_inventory_reserved_recon set (security_invoker = true);
revoke select on public.e10_inventory_recon from anon;
revoke select on public.e10_inventory_reserved_recon from anon;
