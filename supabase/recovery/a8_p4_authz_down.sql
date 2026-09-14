-- A8 P4 (AUTHORIZATION ENGINE: A6c.0-A6c.3) down-recovery.
--
-- HONEST BOUNDARY (drilled, A8-PREP F6): P4 IS EFFECTIVELY IRREVERSIBLE IN LIVE OPERATION.
--   * DB-side RPC bodies CAN be restored: dropping the A6c-added e10_org_* delegates and re-applying the legacy
--     CREATE OR REPLACE function bodies returned pg_get_functiondef exactly to the post-P3 fingerprint (b9e6a467...)
--     on the scratch rehearsal — PROVEN. (Do this with `set check_function_bodies = off;` so cross-references restore
--     regardless of order.)
--   * DB-side POLICIES are NOT reliably restorable from decompiled pg_policies text (a reconstructed DROP+CREATE
--     hit a syntax error on a complex predicate). The legacy 55 org-table policies + 4 workspace policies are not
--     isolated as named CREATE POLICY statements in the baseline (they originate in 20260716100000_rls_initplan), so
--     the AUTHORITATIVE policy recovery is RESTORE-FROM-BACKUP, not a forward script.
--   * The LIVE reversal additionally requires reverting the deployed client build and e10_schema_version() in lockstep
--     through the schema-gate Pages deploy — a multi-system, business-visible event.
--
-- THEREFORE the recovery from P4 is: **restore the pre-P4 backup (the P0 snapshot taken before P4) + coordinated client
-- + SCHEMA_VERSION revert**, treated as an incident-level, operator-authorized action. Forward-fix is the operational
-- default. The DB-side fragment below (drop delegates; restore legacy function bodies) is provided for a
-- functions-only quick revert and is NOT a substitute for the backup restore of the policy surface.
set client_min_messages = warning;
set check_function_bodies = off;
-- drop the A6c-added client delegates + org-aware helpers (everything under e10_org_* + the p_org helper variants)
do $$ declare r record; begin
  for r in select p.oid::regprocedure sig from pg_proc p join pg_namespace n on n.oid=p.pronamespace
           where n.nspname='public' and (p.proname like 'e10_org_%'
             or p.proname in ('_e10_inv_guard','_e10_inv_blob_write','_e10_inv_clamp_res','_e10_inv_receipt_check','_e10_inv_receipt_write','_e10_inv_replay_json','_e10_inv_item_json'))
             and pg_get_function_identity_arguments(p.oid) like 'p_org%' loop
    execute 'drop function if exists '||r.sig||' cascade'; end loop; end $$;
-- (legacy RPC bodies) — re-apply the pre-P4 legacy function definitions here from the pre-P4 backup / migration set.
-- The rehearsal proved that restoring the captured post-P3 CREATE OR REPLACE bodies returns fn_bodies_md5 to b9e6a467.
-- Policy surface: RESTORE FROM THE PRE-P4 BACKUP (see header). Do not attempt reconstructed-DDL policy recovery.
