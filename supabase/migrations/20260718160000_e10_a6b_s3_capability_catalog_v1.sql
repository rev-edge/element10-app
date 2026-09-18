-- Foundation Gate A6b Step 3 — install the A6b v1 finer capability catalog (STAGING/LOCAL only; prod untouched).
-- ADDITIVE + idempotent. Seeds the 15 authoritative v1 `act.*` capabilities (Trent's ruling 2026-07-18) into org0's
-- system roles, joined by ROLE KEY. Legacy capability + module rows are untouched (this only INSERTs new rows).
--
-- v1 catalog (exact strings) — 11 WRITE + 4 READ:
--   WRITE: act.create_session, act.scheduling, act.assign_operators, act.configure_breaks, act.reserve_inventory,
--          act.submit_checklist_sources, act.approve_checklists, act.approve_preparation, act.create_receiving,
--          act.resolve_recovery, act.reopen_preparation
--   READ:  act.view_schedule, act.view_inventory, act.view_prepared_handoff, act.view_financial_estimates
-- Role mapping (new-cap counts): admin=15 (all), manager=13 (all except act.approve_checklists +
--   act.approve_preparation), streamer=2 (act.view_schedule, act.view_prepared_handoff), ops=1 (act.view_inventory).
-- act.live_run stays the existing legacy Start-Live gate and is NOT one of these 15. The alternate 11-leaf
-- `session.read/write/...` vocabulary is NOT authoritative and is not used. Future orgs inherit this mapping when the
-- organization-creation workflow is built (not built in A6b).

insert into public.e10_organization_role_permissions (organization_id, role_id, capability, allowed)
select r.organization_id, r.id, c.capability, true
from public.e10_organization_roles r
join (values
  -- admin: all 15
  ('admin','act.create_session'), ('admin','act.scheduling'), ('admin','act.assign_operators'),
  ('admin','act.configure_breaks'), ('admin','act.reserve_inventory'), ('admin','act.submit_checklist_sources'),
  ('admin','act.approve_checklists'), ('admin','act.approve_preparation'), ('admin','act.create_receiving'),
  ('admin','act.resolve_recovery'), ('admin','act.reopen_preparation'), ('admin','act.view_schedule'),
  ('admin','act.view_inventory'), ('admin','act.view_prepared_handoff'), ('admin','act.view_financial_estimates'),
  -- manager: 13 (all except act.approve_checklists, act.approve_preparation)
  ('manager','act.create_session'), ('manager','act.scheduling'), ('manager','act.assign_operators'),
  ('manager','act.configure_breaks'), ('manager','act.reserve_inventory'), ('manager','act.submit_checklist_sources'),
  ('manager','act.create_receiving'), ('manager','act.resolve_recovery'), ('manager','act.reopen_preparation'),
  ('manager','act.view_schedule'), ('manager','act.view_inventory'), ('manager','act.view_prepared_handoff'),
  ('manager','act.view_financial_estimates'),
  -- streamer: 2
  ('streamer','act.view_schedule'), ('streamer','act.view_prepared_handoff'),
  -- ops: 1
  ('ops','act.view_inventory')
) as c(role_key, capability) on c.role_key = r.key
where r.organization_id = 'e1000000-0000-4000-8000-0000000000a6'
on conflict (organization_id, role_id, capability) do nothing;
