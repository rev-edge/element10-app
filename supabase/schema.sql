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

-- ─────────────────────────────────────────────────────────────
-- APPLIED (migrations e10_admin_onboarding_rpcs + e10_onboarding_rpcs_revoke_anon):
-- Admin-gated onboarding so teammates are added from the UI, not hand-run SQL. Each fn is
-- SECURITY DEFINER, checks public.e10_is_admin() internally (auth.uid() from JWT resolves
-- inside a definer fn), pins search_path=public, and has EXECUTE revoked from anon (the
-- internal admin check is the real gate; the revoke is defense-in-depth + advisor hygiene).
-- NOTE: Supabase's ALTER DEFAULT PRIVILEGES grants EXECUTE to anon directly, so `revoke from
-- public` does NOT remove anon — you must `revoke ... from anon` explicitly.
--   e10_add_member(p_email text) returns text   -- 'added' | 'already_member' | 'no_auth_user'
--   e10_set_role(p_user uuid, p_role text)       -- member|admin; refuses to demote the last admin
--   e10_add_viewer(p_email text) returns text    -- 'added' | 'no_auth_user'
-- The client calls these via sb.rpc(...) from the admin-only Team tab in Data & Lists.
--
-- create or replace function public.e10_add_member(p_email text)
--   returns text language plpgsql security definer set search_path=public as $$
--   declare v_uid uuid; v_email text;
--   begin
--     if not public.e10_is_admin() then raise exception 'Admin only' using errcode='42501'; end if;
--     select id, email into v_uid, v_email from auth.users where lower(email)=lower(btrim(p_email)) limit 1;
--     if v_uid is null then return 'no_auth_user'; end if;
--     if exists(select 1 from public.e10_members where user_id=v_uid) then return 'already_member'; end if;
--     insert into public.e10_members(user_id, email, role) values (v_uid, v_email, 'member');
--     return 'added';
--   end; $$;
-- (e10_set_role / e10_add_viewer follow the same guard pattern; see the two migrations.)
-- revoke execute on function public.e10_add_member(text)/e10_set_role(uuid,text)/e10_add_viewer(text) from public, anon;
-- grant  execute on function ... to authenticated;
--
-- Verified by tests/rls_test.js against the LIVE project with real member+viewer accounts:
-- functionality (owner .insert().select() = INSERT ... RETURNING returns the row), isolation
-- (member cannot read another member's user:<uid> row; viewer gets zero e10_workspace rows and
-- cannot read unlinked sessions/slots/events), and RPC gating (non-admin calls are rejected).

-- ─────────────────────────────────────────────────────────────
-- APPLIED (migrations e10_card_tables, e10_cards_pagination_indexes, e10_cards_filter_trgm):
-- Card/checklist/player/set data moved OUT of the shared JSONB blob into real tables so it
-- scales to millions of rows, queried a page at a time (never loaded whole into the browser).
--   e10_sets(id, name, year, sport, brand, attrs jsonb, created_by, ts)          -- unique(lower(name),coalesce(year,0))
--   e10_players(id, name, aliases text[], sport, team, position, nationality,     -- master record; unique(lower(name))
--               attrs jsonb, created_by, ts)                                       --   trigram GIN on name
--   e10_checklists(id, name, set_id→e10_sets, source, card_count, attrs, ...)     -- the named uploads/collections
--   e10_cards(id, checklist_id→e10_checklists ON DELETE CASCADE, set_id, player_id,-- HIGH VOLUME
--             num, name, set_name (denormalized), rarity, value numeric, parallel,
--             card_type, serial, color, rookie bool, chase bool, attrs jsonb,
--             card_id_ref uuid (future: inventory→card link), created_by, ts,
--             search text GENERATED (lower name|num|set|rarity|parallel|type|color|serial|value))
-- Indexes on e10_cards: (checklist_id), (set_id), (player_id); btree (checklist_id,name,id),
--   (checklist_id,value,id), (player_id,name,id) for indexed ordered pagination; trigram GIN on
--   search, name, set_name, parallel, rarity for open-ended ILIKE search in single-digit ms.
-- Query approach: .eq(scope) + server ILIKE filters + .range(off,off+99); unfiltered browse
--   orders by an indexed column (no sort), filtered/search streams straight from the trigram
--   index with NO order (materializing every match to sort is what made it slow); the row count
--   is fetched separately (count exact, head) so the grid opens without waiting on it.
-- RLS: ALL FOUR tables are SHARED TEAM DATA — authenticated members read + write, viewers none.
--   Each policy uses public.e10_is_member() (checks e10_members, a DIFFERENT table, so the
--   INSERT ... RETURNING self-read works; NOT a self-referential subquery). Schema-qualified.
--     <t>_sel  for select using ((select public.e10_is_member()))
--     <t>_ins  for insert with check ((select public.e10_is_member()))
--     <t>_upd  for update using/with check ((select public.e10_is_member()))
--     <t>_del  for delete using ((select public.e10_is_member()))
--   PERF (migrations e10_cards_rls_initplan_sel + e10_card_tables_rls_initplan_all): the check is
--   wrapped as (select public.e10_is_member()) so Postgres evaluates it ONCE per statement as an
--   InitPlan constant instead of once PER ROW. Semantically identical. Before the wrap, an
--   authenticated search scanned all rows of a checklist and ran e10_is_member() per row (55k
--   times) => 2.4–5.7s per request; after, ~30ms server-side. (The trigram index still isn't used
--   under RLS because LIKE isn't leakproof, so the search filter can't be pushed below the security
--   qual — a full scan of the checklist's rows, fine at 55k; a SECURITY DEFINER search RPC would
--   restore trigram usage if a single checklist ever reaches millions of rows.)
-- Bulk import = chunked client-side inserts (batches of 500 under RLS) with progress; the
--   one-time 55,677-row Prizm backfill was done server-side (data already lived in Postgres).
-- Also enabled RLS (no policies = server-only) on e10_seed_backup + e10_bigimport_backup,
--   which were public/anon-readable (migration e10_secure_backup_tables). Backup DATA untouched.
-- Verified in tests/rls_test.js: member reads shared cards/players, member INSERT...RETURNING
--   works, a non-member gets ZERO cards and is denied inserts.

-- ─────────────────────────────────────────────────────────────
-- APPLIED (migrations e10_teams_and_card_team, e10_slot_partition_rpc, e10_slot_partition_remainder):
-- Break-format rebuild phase 1 — team entity + team field + the rule-based slot slicing primitive.
--   e10_teams(id, name, aliases text[], sport, nationality, attrs, created_by, ts)
--     - unique lower(name); trigram GIN on name (mirrors e10_players' search path -> dbTeamSearch,
--       a copy of dbPlayerSearch pointed at e10_teams via the existing entityPicker).
--     - RLS (InitPlan-wrapped, no per-row call): read = (select public.e10_is_member());
--       insert/update/delete = (select public.e10_is_admin())  [member read, admin write].
--   e10_cards += team_id uuid (FK e10_teams on delete set null, indexed) + team text. No backfill —
--     cards without a team are valid (Pokémon has no team). The generated `search` column was
--     dropped+recreated to include team (its trigram GIN rebuilt) so open search matches team.
-- Slot rule shape (persisted on the break model in the workspace as ruleSlots, NOT materialized
--   card lists): [{ id, name, include:[{field,value,valueId?}], exclude:[{...}], remainder? }].
--   field ∈ team|player|set|parallel|type; include conditions are AND'd, exclude carves them out;
--   team/player prefer the linked id, others match text. A {remainder:true} slot is the Field
--   catch-all (claims cards no other slot took).
-- Partition check is server-side: public.e10_slot_partition(p_checklist uuid, p_slots jsonb) (SECURITY
--   INVOKER so RLS applies; EXECUTE authenticated, revoked anon). e10_slot_pred builds an index-
--   friendly WHERE per slot (team_id/player_id use the indexes; set_name/parallel/card_type ILIKE),
--   inserts matches into a temp map, then returns per-slot matched count + summed value, COVER
--   (unassigned count + sample) and DISJOINT (double-claimed count + colliding slot names + sample).
--   Only counts + bounded samples leave the DB — no pulling the whole checklist to the client
--   (measured ~150ms over the 55k Prizm checklist). Phase 2 (pricing/tiers/method/projection) will
--   build on these slot definitions; not built here.

-- ─────────────────────────────────────────────────────────────
-- APPLIED (migration e10_checklist_facet_rpc):
-- Break-format rebuild phase 2 — break formatter (sale method + tier bands + viability projection).
--   ONE new DB object (no new tables): public.e10_checklist_facet(p_checklist uuid, p_dim text) jsonb.
--     - SECURITY INVOKER (default) + STABLE, so RLS on e10_cards applies (member read); adds no new
--       RLS surface. Index-friendly: filtered by checklist_id (indexed), grouped server-side.
--     - Returns the distinct team (or player) values of a checklist as
--       [{label,id,cards,value}] ranked by summed value desc — the input to one-click "Generate
--       spots" and the tier pre-rank. The client never pulls the row set to enumerate teams/players.
--   Everything else in phase 2 persists on the break model in the workspace store (no DDL):
--     - format model  += breakType ('team'|'player'|'hybrid'), tierBands:[{id,name,low,expected,high}].
--     - each ruleSlot += method ('$1auction'|'auction'|'fixed'), start?/price?, tierId?,
--       bandOverride?{low,expected,high}, order?  (all optional → old models load unchanged).
--   ONE band resolver seam (client bkResolveBand): auction slots read {low,expected,high} through it;
--     phase 2 returns the manual tier band or per-slot override; a future hammer-history source (phase
--     3) adds a branch returning the SAME shape — the projection math never changes. Fixed slots use
--     their price at low=expected=high. Projection = Σ slot takes at LOW/EXPECTED/HIGH vs the
--     cost/(1-marginGoal) clear line, a top-N concentration share + a top-spots-at-LOW downside, and a
--     fixed-price nudge to close the margin gap. Reuses e10_slot_partition as-is; RLS not weakened.

-- ─────────────────────────────────────────────────────────────
-- APPLIED (migration e10_break_phase3_live_fulfillment):
-- Break-format rebuild phase 3 — live break board + buyer assignment + fulfillment.
-- Built ON the EXISTING live-break tables (e10_break_sessions / e10_break_slots / e10_break_events /
-- e10_viewers / e10_session_viewers) — no parallel system, no new tables. All new columns nullable /
-- defaulted so pre-phase-3 ad-hoc sessions/slots keep working.
--   e10_break_slots += method, band_low/band_expected/band_high (phase-2 band snapshot), team_id,
--     player_id (history seam), sold_at, plan jsonb (formatSlotId + card pull-list + cardCount +
--     tierName + remainder flag), ship_state ('open'|'packed'|'shipped'), ship_note. The formatted
--     spot maps 1:1 onto a slot: label←name, tier←tierName, price(fixed), band_*←resolved band,
--     team_id/player_id←the include rule's linked valueId (so each hammer is queryable by entity).
--     buyer_handle (text) + buyer_uid (optional viewer link) already existed — the buyer identity.
--   e10_break_sessions += format_id (saved-model id), break_type, cost, proj_low/proj_expected/
--     proj_high — the projection snapshot that powers the live header and modeled-vs-actual.
--   Indexes: e10_break_slots(team_id), (player_id) [history seam]; (lower(buyer_handle)) where
--     state='sold' [buyer-grouped ship list].
--   RLS UNCHANGED and not weakened: slot INSERT/UPDATE/DELETE stay e10_owns_session (only the session
--     owner or admin assigns — a member's UPDATE affects 0 rows), SELECT stays e10_can_read_session.
--     New columns inherit these existing owner/admin policies. Membership checks are the STABLE
--     SECURITY DEFINER helpers e10_owns_session / e10_can_read_session (single subquery, evaluated once).
--   e10_buyer_suggest(p_session,p_q) — SECURITY DEFINER, gated by e10_owns_session (returns [] otherwise),
--     anon revoked. Owner-only read path for the assign typeahead: session roster (e10_viewers, which is
--     self/admin-read only) UNION this streamer's prior buyers — WITHOUT weakening e10_viewers' RLS.
--   e10_slot_cards(p_checklist,p_slots,p_limit) — SECURITY INVOKER (RLS applies), reuses e10_slot_pred;
--     returns the bounded matched card pull-list per formatted slot to seed the board (Field is capped).
--   Buyer-grouped fulfillment query: read sold e10_break_slots across the owner's sessions
--     (RLS-scoped) and group by buyer_uid else lower(buyer_handle) → cross-session ship list.
--   Modeled-vs-actual reads the session's proj_* + cost snapshot vs summed hammer (real margin).
