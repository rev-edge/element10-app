-- Migration: e10_break_session_source_show_ref  (M3.2)
-- Carry the source show's reference on a live break session so break consumption can draw down THAT
-- show's reservations (M3.1 blocker-5 wired end-to-end). ADDITIVE: one nullable text column, no data
-- change, RLS/policies untouched (inherits the existing e10_break_sessions owner/admin policies).
-- The value stored equals the show id (== e10_inventory_reservations.show_ref, the value
-- e10_inv_set_reservations / e10_inv_reserve persist). Null for ad-hoc sessions (no source show) →
-- consume draws only unreserved stock, exactly the server's documented behavior.
alter table public.e10_break_sessions add column if not exists source_show_ref text;

-- Rollback: alter table public.e10_break_sessions drop column source_show_ref;
