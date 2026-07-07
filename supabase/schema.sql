-- Element 10 — Supabase schema (already applied to project ddhkkumiyidorzmajwde)
-- Shared workspace: one JSONB row the whole team reads/writes; realtime broadcasts changes.

create table if not exists public.e10_workspace (
  id text primary key default 'main',
  data jsonb not null default '{}'::jsonb,
  rev bigint not null default 0,
  updated_at timestamptz not null default now(),
  updated_by text
);

alter table public.e10_workspace enable row level security;

-- NOTE: the original permissive policies below granted every authenticated user
-- read/write on EVERY row. They are intentionally NOT recreated here — the
-- granular multi-tenant policies (ws_sel/ws_ins/ws_upd/ws_del, further down) are
-- the real access control. We only DROP the legacy names so re-running this file
-- can never reopen cross-tenant access by OR-combining a permissive policy with
-- the granular ones. (The live DB already has only the granular policies.)
drop policy if exists "e10 authed read" on public.e10_workspace;
drop policy if exists "e10 authed write" on public.e10_workspace;

insert into public.e10_workspace (id, data) values ('main', '{}'::jsonb) on conflict (id) do nothing;

-- realtime
alter publication supabase_realtime add table public.e10_workspace;

-- ─────────────────────────────────────────────────────────────
-- FUTURE (not applied): per-entity tables for field-level merge sync.
-- When the team outgrows last-write-wins, split the JSONB blob into:
--   e10_todos(id, text, done, desc, position, created_by, ...)
--   e10_notes(id, kind, text, author, created_at)
--   e10_todo_comments(id, todo_id, author, text, created_at)
--   e10_shows(id, day, daypart, name, format, duration, streamer)
--   e10_inventory(id, name, cat, set, qty, cost, value, cond, img)
--   e10_kv(key, value)   -- lists, dashCfg, streamers, breaks, sales
-- Enable RLS (authenticated) + realtime on each. Migrate the current
-- workspace JSON into rows once, then point the app at the tables.

-- ─────────────────────────────────────────────────────────────
-- APPLIED: multi-tenant (personal vs universal) + roles + RLS
-- Rows: 'shared' (team: notes, todos, streamers, lists, checklists, attachments,
--   inventory) all-read/write; 'universal' (admin-curated baselines) all-read/admin-write;
--   'user:<uid>' (personal shows/breaks/dashCfg/sales) owner+admin only.
alter table public.e10_workspace add column if not exists owner uuid;
create table if not exists public.e10_members(
  user_id uuid primary key references auth.users(id) on delete cascade,
  email text, display_name text, role text not null default 'member',
  created_at timestamptz not null default now());
alter table public.e10_members enable row level security;
create or replace function public.e10_is_admin() returns boolean
  language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.e10_members m where m.user_id=auth.uid() and m.role='admin'); $$;
-- members policies: read self (or admin all), self-insert as member, admin updates roles
create policy m_sel on public.e10_members for select to authenticated using (user_id=auth.uid() or public.e10_is_admin());
create policy m_ins on public.e10_members for insert to authenticated with check (user_id=auth.uid() and role='member');
create policy m_upd on public.e10_members for update to authenticated using (public.e10_is_admin()) with check (public.e10_is_admin());
-- workspace policies: shared/universal readable by all; personal by owner/admin; universal writable by admin
create policy ws_sel on public.e10_workspace for select to authenticated using (id in ('shared','universal') or owner=auth.uid() or public.e10_is_admin());
create policy ws_ins on public.e10_workspace for insert to authenticated with check (id='shared' or (id='universal' and public.e10_is_admin()) or owner=auth.uid() or public.e10_is_admin());
create policy ws_upd on public.e10_workspace for update to authenticated using (id='shared' or (id='universal' and public.e10_is_admin()) or owner=auth.uid() or public.e10_is_admin()) with check (id='shared' or (id='universal' and public.e10_is_admin()) or owner=auth.uid() or public.e10_is_admin());
create policy ws_del on public.e10_workspace for delete to authenticated using (owner=auth.uid() or public.e10_is_admin());

-- ─────────────────────────────────────────────────────────────
-- APPLIED (migration e10_live_break_sessions): Live Break Session primitive
-- One session + slots + append-only event log; four surfaces read the same object.
--   e10_break_sessions  (id, name, streamer_uid, status, stash_or_pass, case_hit, share_code, ...)
--   e10_break_slots     (id, session_id, label, tier, price, state, case_hit, buyer_handle, buyer_uid, position)
--   e10_break_events    (id bigint identity, session_id, slot_id, type, payload jsonb, actor_uid, created_at)  -- Tier-2 analytics substrate; indexed on (session_id, created_at), (type), (session_id, type, created_at)
--   e10_viewers         (user_id, whatnot_handle)              -- viewer identity/handle link (viewers are NOT e10_members)
--   e10_session_viewers (session_id, user_id)                  -- share_code redemptions / explicit viewer grants
-- Helper fns (security definer): e10_is_member(), e10_my_handle(), e10_owns_session(uuid),
--   e10_can_read_session(uuid), e10_redeem_code(text) [links caller to a session by unguessable code].
-- RLS: streamer/admin CRUD their own sessions/slots/events; a viewer may READ a session (+slots/events)
--   only if linked (a slot's buyer_uid=them or buyer_handle=their handle) OR they redeemed the share_code.
--   Overlay authenticates as the streamer (no public/anon read path). Realtime on sessions/slots/events.
-- SECURITY NOTE — two existing policies were TIGHTENED so viewers get ZERO e10_workspace access
--   (member/admin access is unchanged, verified by simulation):
--     ws_sel/ws_ins/ws_upd  — the shared/universal branches now require e10_is_member()
--     m_ins                 — e10_members self-insert is now admin-only (members provisioned by admin;
--                             this closes viewer->member self-escalation). Default role stays 'member'.
