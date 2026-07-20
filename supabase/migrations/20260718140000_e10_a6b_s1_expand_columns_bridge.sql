-- Foundation Gate A6b Step 1 (EXPAND) — nullable organization_id + write bridge (STAGING/LOCAL only; prod untouched).
-- ADDITIVE. Per ADR 0005 §12: add the column and install e10.stamp_org() BEFORE INSERT in the SAME migration so
-- every new row is org-owned from t0 (memberships exist since A6a bootstrap / Step 0, so current_org() -> org0).
-- Also adds e10_break_sessions.live_session_id (§7 link; backfilled strict-1:1 in Step 2).

create or replace function e10.stamp_org() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.organization_id is null then new.organization_id := e10.current_org(); end if;
  return new;
end $$;
revoke all on function e10.stamp_org() from anon, public;

alter table public.e10_inventory_items add column if not exists organization_id uuid references public.e10_organizations(id);
alter table public.e10_inventory_movements add column if not exists organization_id uuid references public.e10_organizations(id);
alter table public.e10_inventory_reservations add column if not exists organization_id uuid references public.e10_organizations(id);
alter table public.e10_mutation_receipts add column if not exists organization_id uuid references public.e10_organizations(id);
alter table public.e10_workspace add column if not exists organization_id uuid references public.e10_organizations(id);
alter table public.e10_break_sessions add column if not exists organization_id uuid references public.e10_organizations(id);
alter table public.e10_break_slots add column if not exists organization_id uuid references public.e10_organizations(id);
alter table public.e10_break_events add column if not exists organization_id uuid references public.e10_organizations(id);
alter table public.e10_session_viewers add column if not exists organization_id uuid references public.e10_organizations(id);
alter table public.e10_obs_breaks add column if not exists organization_id uuid references public.e10_organizations(id);
alter table public.e10_obs_captures add column if not exists organization_id uuid references public.e10_organizations(id);
alter table public.e10_obs_channels add column if not exists organization_id uuid references public.e10_organizations(id);
alter table public.e10_obs_config add column if not exists organization_id uuid references public.e10_organizations(id);
alter table public.e10_obs_products add column if not exists organization_id uuid references public.e10_organizations(id);
alter table public.e10_obs_product_prices add column if not exists organization_id uuid references public.e10_organizations(id);
alter table public.e10_obs_slots add column if not exists organization_id uuid references public.e10_organizations(id);
alter table public.e10_obs_streams add column if not exists organization_id uuid references public.e10_organizations(id);
alter table public.e10_obs_upcoming_shows add column if not exists organization_id uuid references public.e10_organizations(id);
alter table public.e10_obs_viewer_snapshots add column if not exists organization_id uuid references public.e10_organizations(id);
alter table public.e10_break_sessions add column if not exists live_session_id uuid;

drop trigger if exists e10_stamp_org_trg on public.e10_inventory_items;
create trigger e10_stamp_org_trg before insert on public.e10_inventory_items for each row execute function e10.stamp_org();
drop trigger if exists e10_stamp_org_trg on public.e10_inventory_movements;
create trigger e10_stamp_org_trg before insert on public.e10_inventory_movements for each row execute function e10.stamp_org();
drop trigger if exists e10_stamp_org_trg on public.e10_inventory_reservations;
create trigger e10_stamp_org_trg before insert on public.e10_inventory_reservations for each row execute function e10.stamp_org();
drop trigger if exists e10_stamp_org_trg on public.e10_mutation_receipts;
create trigger e10_stamp_org_trg before insert on public.e10_mutation_receipts for each row execute function e10.stamp_org();
drop trigger if exists e10_stamp_org_trg on public.e10_workspace;
create trigger e10_stamp_org_trg before insert on public.e10_workspace for each row execute function e10.stamp_org();
drop trigger if exists e10_stamp_org_trg on public.e10_break_sessions;
create trigger e10_stamp_org_trg before insert on public.e10_break_sessions for each row execute function e10.stamp_org();
drop trigger if exists e10_stamp_org_trg on public.e10_break_slots;
create trigger e10_stamp_org_trg before insert on public.e10_break_slots for each row execute function e10.stamp_org();
drop trigger if exists e10_stamp_org_trg on public.e10_break_events;
create trigger e10_stamp_org_trg before insert on public.e10_break_events for each row execute function e10.stamp_org();
drop trigger if exists e10_stamp_org_trg on public.e10_session_viewers;
create trigger e10_stamp_org_trg before insert on public.e10_session_viewers for each row execute function e10.stamp_org();
drop trigger if exists e10_stamp_org_trg on public.e10_obs_breaks;
create trigger e10_stamp_org_trg before insert on public.e10_obs_breaks for each row execute function e10.stamp_org();
drop trigger if exists e10_stamp_org_trg on public.e10_obs_captures;
create trigger e10_stamp_org_trg before insert on public.e10_obs_captures for each row execute function e10.stamp_org();
drop trigger if exists e10_stamp_org_trg on public.e10_obs_channels;
create trigger e10_stamp_org_trg before insert on public.e10_obs_channels for each row execute function e10.stamp_org();
drop trigger if exists e10_stamp_org_trg on public.e10_obs_config;
create trigger e10_stamp_org_trg before insert on public.e10_obs_config for each row execute function e10.stamp_org();
drop trigger if exists e10_stamp_org_trg on public.e10_obs_products;
create trigger e10_stamp_org_trg before insert on public.e10_obs_products for each row execute function e10.stamp_org();
drop trigger if exists e10_stamp_org_trg on public.e10_obs_product_prices;
create trigger e10_stamp_org_trg before insert on public.e10_obs_product_prices for each row execute function e10.stamp_org();
drop trigger if exists e10_stamp_org_trg on public.e10_obs_slots;
create trigger e10_stamp_org_trg before insert on public.e10_obs_slots for each row execute function e10.stamp_org();
drop trigger if exists e10_stamp_org_trg on public.e10_obs_streams;
create trigger e10_stamp_org_trg before insert on public.e10_obs_streams for each row execute function e10.stamp_org();
drop trigger if exists e10_stamp_org_trg on public.e10_obs_upcoming_shows;
create trigger e10_stamp_org_trg before insert on public.e10_obs_upcoming_shows for each row execute function e10.stamp_org();
drop trigger if exists e10_stamp_org_trg on public.e10_obs_viewer_snapshots;
create trigger e10_stamp_org_trg before insert on public.e10_obs_viewer_snapshots for each row execute function e10.stamp_org();
