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

-- ─────────────────────────────────────────────────────────────
-- APPLIED (migration e10_overlay_session_state):
-- Vertical Whatnot OBS overlays (overlay.html, 1080x1920, two layouts ?layout=oncam|graphics).
-- No new tables. Four nullable/defaulted columns on e10_break_sessions drive the overlay live:
--   active_slot_id uuid  — the spot on the block now (streamer sets it with ● Now in the Live panel;
--                          overlay renders it as the current-spot bar).
--   trade_open boolean   — Trade-block state (Live panel toggle → overlay "TRADE BLOCK OPEN" badge).
--   checklist_id uuid    — set at format-start (liveStartFromFormat); lets the overlay read the
--                          chase-flagged cards for the chase list/board via e10_cards (chase=true).
--   overlay_cfg jsonb    — {showTitle, ticker, handleLeft, handleRight} branding, edited from the
--                          Live panel "OBS overlays" section; overlay reads it live.
-- RLS UNCHANGED / not weakened: these inherit the existing e10_break_sessions policies (owner/admin
--   write via streamer_uid=auth.uid()/e10_is_admin(); read via e10_can_read_session). The overlay
--   signs in as the streamer, so it reads its own session + slots (existing realtime subscription
--   reused) and the checklist's chase cards under the existing member-read e10_cards RLS. No new
--   functions or policies; get_advisors shows no new findings. Stash-or-pass has no server-side vote
--   store (companion is display-of-state), so the overlay shows the prompt/state, not fabricated tallies.

-- ─────────────────────────────────────────────────────────────
-- APPLIED (migration e10_chases_hit_case_open):
-- On-cam break board — status placard cards + live cross-off chase board.
-- Two nullable/defaulted columns on e10_break_sessions (no new tables):
--   chases_hit    jsonb   default '[]'  — array of e10_cards.id marked hit this session; the on-cam
--                          chase board (and the graphics chase board) dim + strike + tag "HIT" any
--                          chase whose id is in this set, and the "N LEFT" count = total − hit.
--   case_hit_open boolean default false — persistent "case-hit box in play" flag so the CASE HIT
--                          placard stays up; the existing momentary case_hit still drives the
--                          celebratory top-banner flash.
-- Panel writes: liveToggleChaseHit (per-chase mark/un-mark, one tap, logs a chase_hit/chase_unhit
--   e10_break_event), liveToggleCaseOpen. Overlay reads session.chases_hit + the checklist's
--   chase=true e10_cards live via the existing realtime subscription; crosses off + drops the count
--   in real time. RLS UNCHANGED / not weakened: both columns inherit the existing e10_break_sessions
--   policies (write owner/admin via streamer_uid=auth.uid() OR e10_is_admin(); read via
--   e10_can_read_session). No new policy → no new membership check to InitPlan-wrap. Placards bind to
--   session.stash_or_pass / (case_hit_open||case_hit) / trade_open; each shows only when its state is on.

-- ─────────────────────────────────────────────────────────────
-- APPLIED (migration e10_session_products_participants):
-- Live Break Phase A — box/case inventory + pre-flight format review + break cost.
-- Two nullable/defaulted jsonb columns on e10_break_sessions (no new tables); break_type, cost,
-- name(title) already exist:
--   products     jsonb default '[]' — the included sealed products:
--                  [{itemId,name,cat,slice('case'|'half'|'boxes'),n,boxes,perBoxCost,boxesPerCase,consumed}].
--                  break cost = Σ boxes×perBoxCost (persisted to session.cost = the invested basis for ROI).
--   participants jsonb default '[]' — hosts on the break (from the streamer picker).
-- Box/case model lives in the JSONB workspace inventory (S.inventory): items gain boxesPerCase (default 1)
--   and perBoxCost (default = unit cost); on-hand qty is counted in boxes. Slicing full case / half /
--   N boxes → a box count via boxesPerCase. AUTOMATIC decrement is idempotent: each session product row
--   carries `consumed` (boxes this break has taken); breakConsume() only ever applies delta = boxes −
--   consumed to it.qty (decrement when >0, return when <0) via cloudCommitShared, then sets consumed =
--   applied so repeated edits never double-count. Review defers the decrement to Confirm; mid-show
--   add/remove/re-slice decrements/returns immediately. On break end, consumed boxes stay consumed
--   (opened). available = qty − reserved is unchanged, so reservations/rollup stay correct.
-- RLS UNCHANGED / not weakened: both columns inherit the existing e10_break_sessions owner/admin write
--   + can_read_session read; no new policy, nothing new to InitPlan-wrap. Inventory writes go through the
--   existing member-writable shared workspace row via cloudCommitShared (read-modify-write).

-- ─────────────────────────────────────────────────────────────
-- APPLIED (migration e10_roles_permissions_engine):
-- Roles & permissions engine. ENFORCEMENT IS ADDITIVE — capabilities only RESTRICT; they never loosen
-- an existing policy, and admin is a hard-wired superuser that cannot be locked out.
--   e10_role_permissions(role, capability, allowed, updated_at, updated_by) PK(role,capability).
--     RLS: select = (select e10_is_member()); insert/update/delete = (select e10_is_admin()). InitPlan.
--   Capabilities (enumerated): MODULES mod.home/mod.schedule/mod.inventory/mod.toolkit/mod.reporting/
--     mod.settings; ACTIONS act.inventory_edit/act.live_run/act.team_manage/act.lists_edit/
--     act.reporting_export/act.permissions_config.
--   e10_has_cap(cap text) — SECURITY DEFINER, search_path=public. Returns (select e10_is_admin()) OR
--     NOT EXISTS(an explicit allowed=false row for the caller's role+cap). Default-ALLOW: existing
--     members (no rows) are unaffected; admin ALWAYS true (a deny row for 'admin' is ignored). Row-
--     independent → wrapped as (select e10_has_cap(...)) in policies = InitPlan (once per statement).
--   e10_is_member() is UNCHANGED (role in ('member','admin')) so every existing WRITE policy that uses
--     it (e10_workspace + e10_cards/players/sets/checklists ins/upd/del) keeps its exact original
--     behavior — capability gates only add AND has_cap, never loosen. e10_is_org() (NEW, = exists any
--     e10_members row) is used ONLY on READ (SELECT) policies so custom roles (manager/streamer/viewer)
--     can VIEW; they still cannot WRITE (strict e10_is_member) unless assigned member/admin. [This split
--     is the applied fix for the security review's finding #1 — see migration e10_permissions_secfix.]
--   e10_assign_role(p_user,p_role) — admin-only RPC to assign any role string; protects the last admin
--     with a row-lock on the admin rows before the count (closes a TOCTOU race — review finding #3).
--   ADDITIVE gates (each = ORIGINAL predicate AND (select e10_has_cap(...)); base branch preserved):
--     e10_workspace ws_ins/ws_upd — the 'shared' (inventory) branch AND act.inventory_edit.
--     e10_break_sessions bs_ins/bs_upd — owner/admin AND act.live_run.
--     e10_break_slots sl_ins/sl_upd/sl_del — e10_owns_session AND act.live_run.
--   Two-layer enforcement: client hides nav/controls by capability; RLS is the real gate. Verified a
--   restricted 'viewer' is blocked SERVER-SIDE — inventory write and break-session insert both fail with
--   "new row violates row-level security policy" — while admin retains full access and members are
--   unaffected. Team writes stay admin-only RPCs; exports are client-side (act.reporting_export).

-- ─────────────────────────────────────────────────────────────
-- APPLIED (migration e10_teams_logo_url):
-- Graphics overlay v2 — team-board-forward layout. One nullable column, no pipeline this pass:
--   e10_teams.logo_url text — the live team board renders it as a tile logo when set, else a monogram
--     derived from the slot label. RLS UNCHANGED (already InitPlan-wrapped: read=(select e10_is_member()),
--     write=(select e10_is_admin())); a nullable column inherits those policies — nothing weakened.
-- Everything else is client-only: overlay.html ?layout=graphics rebuilt into a live team tile board
--   (one tile per session slot; bright/volt when available, dimmed when sold; "N LEFT"; logo via team_id
--   → e10_teams.logo_url, else monogram; 6-wide, scales to 30+), format side rails + top banner from a
--   configurable tagline (overlay_cfg.tagline, default from break_type), a LIVE pill (+ e10_session_viewers
--   count when available), an Element-10 giveaway chip (overlay_cfg.giveaway {on,label,endsAt,entries} —
--   started/stopped/entry-controlled from the Live panel, local countdown tick, hidden when off), a socials
--   bar (overlay_cfg.socials), and brand chevrons framing the cam zone. The bottom ~15% is kept clear for
--   Whatnot's native bid bar — the ON THE BLOCK spot/price bar and sold flash are suppressed on graphics
--   (Whatnot shows spot/price/winner; the tiles show sold via dimming). The on-cam layout is untouched.

-- ─────────────────────────────────────────────────────────────
-- APPLIED (migration e10_teams_league_and_starter_rosters):
-- Complete the break setup — load the spot list (format / team roster / player / on-the-fly).
--   e10_teams.league text (nullable) — tags each team's league so "sport → league → load roster" works.
--     RLS UNCHANGED (already InitPlan-wrapped: read=(select e10_is_org()), insert/update/delete=(select
--     e10_is_admin())); a nullable column inherits those policies — nothing weakened.
--   Idempotent starter-roster seed into e10_teams (insert ... where not exists on lower(name), so re-running
--     is a no-op and never duplicates): 176 teams tagged sport + league — NBA(30), MLB(30), NFL(32),
--     NHL(32), Premier League(20), Soccer Nations(32). Full city+nickname names keep the unique lower(name)
--     index collision-free across leagues (e.g. Los Angeles Lakers vs Los Angeles Kings). Logos deferred
--     (the overlay's monogram fallback renders now). This is permanent product data, not throwaway.
-- Everything else is client-only (index.html): a shared "Load the spot list" panel on BOTH the pre-flight
--   REVIEW and the live-board WORKLIST — attach a saved format (seeds slots+tiers+projection), generate by
--   TEAM (sport→league→e10_teams roster, one slot per team, team_id-linked so the graphics overlay renders
--   logos/monograms), generate by PLAYER (e10_checklist_facet), or build on the fly (N blank spots; the
--   free-text one-off add stays). Live-board loaders insert straight into e10_break_slots (default plan={}
--   on every batch row so a mixed batch can't null-out the NOT-NULL plan column); review loaders populate
--   the BK slot builder (now renders roster/on-the-fly slots even with no checklist — per-card counts just
--   stay blank). Once slots exist, the AVERAGE SLOT TARGET (break cost ÷ slot count, break-even) shows on
--   both surfaces and attaching a format populates proj_low/expected/high. Box-slicing fix (Phase A):
--   the inventory form captures a Cost basis (per box / per case) + Boxes/case and stores `cost` PER BOX
--   (case price ÷ boxes/case), so a case-priced product models correctly and the product editor slices to
--   full case / half / N boxes against the right per-box cost.

-- ─────────────────────────────────────────────────────────────
-- CLIENT-ONLY FIX (no schema change): live-break PRODUCTS/COST reactivity.
--   Root cause: breakConsume() ended with `p.boxes = p.consumed`, conflating the DESIRED committed box
--   count (set by the slice) with how many boxes were actually pulled from stock. When on-hand was 0 (or
--   short), applied=0 so consumed didn't move and this line overwrote the slice-driven p.boxes back to its
--   old value — freezing the product line, the Break-cost total, the Avg-slot-target and the ROI header.
--   Fix: cost is now DECOUPLED from stock — breakConsume only reconciles inventory and tracks p.consumed
--   (actual movement); it never touches p.boxes. A shortage warns ("cost still committed for N") instead of
--   freezing. Swept the same "mutate state but don't re-render" pattern: afterProdChange() now re-renders
--   the whole surface in the REVIEW context too (its avg-slot-target header lives outside #prodBox), so a
--   product change updates every cost-derived field, not just the product box.

-- ─────────────────────────────────────────────────────────────
-- CLIENT-ONLY (no schema change): Teams management page under Inventory (dTeams).
--   Reuses e10_teams as-is (name, sport, league, logo_url) and its existing RLS — read=(select
--   e10_is_org()), insert/update/delete=(select e10_is_admin()). Members browse; only admins see the
--   edit/add/remove/logo controls, and the DB enforces it (a member UPDATE matches 0 rows via the
--   admin-only USING clause; a member INSERT is 403).
--   • Hierarchy: Sport → League → team tiles, plus an open name search across all teams. Each tile shows
--     the logo thumbnail when logo_url is set, else the SAME monogram the graphics overlay uses
--     (teamMonogram mirrors overlay.html monogram) so the page and the on-air board match.
--   • Edit / add / remove a team; add a new league/set (sport + league); free-text sport & league inputs
--     support custom non-sports sets (anime, characters). Duplicate names are caught before insert with a
--     suggest-and-confirm (offer to open the existing team) — never a hard 409 against unique lower(name).
--   • Logo population: per team, upload an image (reuses pickImage → e10Upload → resize → Storage `cards`
--     bucket → public URL) OR paste a URL; both write e10_teams.logo_url. Bulk-friendly: every tile in a
--     league view has an inline paste field + ⬆ upload so a whole league can be knocked out in one sitting.
--     No web auto-fetch (licensing / external dependency — out of scope). The graphics overlay team board
--     already renders logo_url, so a set logo shows on-air immediately (verified).

-- ─────────────────────────────────────────────────────────────
-- CLIENT-ONLY (no schema change): inventory in-place edit + bounded UX polish sweep.
--   Inventory edit: invEdit/invEditSave — an Edit action on every item opens the same cost-basis-aware
--     fields as the add form (name, category, set, cost basis per box/per case + boxes/case + per-box hint,
--     qty, market, grading-co/grade/card#/year/parallel/condition, owner, image upload/URL). Saves in place
--     (no delete-and-re-add), recomputes rollups, and lets legacy items (e.g. a $12,000/box case) be
--     corrected to the right per-box cost — which then flows into live-break slices. Inline validation
--     (name required; cost/qty/market ≥ 0; boxes/case ≥ 1) with a visible error line; delete now confirms.
--   Polish sweep (small/additive/reversible): destructive confirms added to delInv, liveDelSlot (warns if
--     the spot is SOLD), delShow/delShowById, delBreak/delBreakById, delCopy, prodRemove; success/error
--     toasts on those + addInv + addTodo; liveDelSlot now surfaces DB errors instead of an empty catch.
--     Enter-to-submit on the inventory add name, reserve-units, show-reserve qty, and the break planner
--     product/chase/auction add-rows. Empty-state "None yet." fallbacks on the break planner
--     product/chase/auction/inventory panels. Currency stays money()-formatted app-wide (audited).

-- ─────────────────────────────────────────────────────────────
-- CLIENT-ONLY (no schema change): Live Break Phase B — live ROI% + per-slot target vs actual.
--   Streamer-facing only (liveProgressHTML / liveSpotCard in index.html) — the public overlay is untouched.
--   Everything is computed from existing columns: e10_break_sessions.cost / proj_* and e10_break_slots
--   hammer price / band_expected / tier. Re-renders on every sale, reopen, and cost change via renderLive
--   (product edits) and the realtime e10_break_sessions subscription — no new wiring.
--   • Header: ROI% = (Σ sold hammer − cost) / cost, red→green at break-even, beside Net/vs-cost. A remaining
--     line: "To break even: $A more · avg $B/remaining slot" and (when proj_expected > cost) "To margin goal
--     ($exp): $C more" — proj_expected is the phase-2 margin-goal revenue target (no targetMargin column
--     needed). A pacing line: sold Σhammer vs Σ(their targets), beating/trailing.
--   • Per-slot: slotTarget(sl) = band_expected (phase-2 tier) if the format is tiered, else the break-even
--     share cost ÷ slot count. OPEN slots show the target; SOLD slots show hammer vs target with a signed
--     delta + ▲ over / ▼ under (and a green/red left border).

-- ─────────────────────────────────────────────────────────────
-- APPLIED (migration e10_phase_c_incentive_attribution): Live Break Phase C — incentive attribution.
--   e10_break_slots.incentives jsonb NOT NULL default '[]'  — the incentive keys that were active when the
--     slot sold (Phase D can split slot performance by incentive: `where incentives ? 'stash_or_pass'`).
--   e10_break_sessions.see_2_pick_1 boolean (nullable) — the new "see 2 pick 1" incentive state; the
--     existing stash_or_pass / case_hit(_open) / trade_open booleans are untouched (backward compatible).
--   RLS UNCHANGED — both tables keep their InitPlan-wrapped policies (slots: owner + (select
--     e10_has_cap('act.live_run')) for ins/upd/del, e10_can_read_session for select; sessions likewise).
--     New columns inherit those policies — no policy loosened.
-- Client (index.html): an INCENTIVE REGISTRY is the single source of truth —
--   INCENTIVES = [{key,label,active(session)}] for stash_or_pass, case_hit (case_hit_open||case_hit),
--   trade_block (trade_open), see_2_pick_1. activeIncentives(session) resolves the live-active set;
--   liveConfirmSold stamps it onto slot.incentives, liveReopen clears it (a re-sell re-stamps). Sold slots
--   render their incentive tags. TO ADD A NEW INCENTIVE: append one INCENTIVES row + one toggle button in
--   liveActiveHTML + one placard branch in overlay.html placardsHTML. A new "See 2 pick 1" toggle sits with
--   stash/case/trade. overlay.html: a compression-safe SEE 2 PICK 1 placard (pl-see) shows on the on-cam
--   layout only when see_2_pick_1 is on; the other three placards are unchanged.

-- ─────────────────────────────────────────────────────────────
-- CLIENT-ONLY (no schema / no RLS change): player-driven chase lists + bulk chase assignment.
--   Chase stays a card-level flag (e10_cards.chase) — the source of truth the break chase board
--   (liveLoadChases) + planner (dbPreloadCards) already read. Applying a list just sets that flag in bulk,
--   so it carries to breaks with no new wiring (verified: applied chases appear in the planner pool).
--   • Chase list = { id, name, sport, league, players:[{id,name}] } stored in the SCOPED workspace JSONB
--     (added 'chaseLists' to SCOPED_KEYS / blankScoped / normScoped / rebuildS / pushFromS / doCloudWrite —
--     persisted exactly like breaks/copySets, no new table). Manager on the Checklists page: create / rename
--     (inline) / delete (confirm) / add-remove players via the existing player picker (dbPlayerSearch).
--   • APPLY (chaseApply): id-match first — update chase=true where checklist_id=CL and player_id in the
--     list's linked player ids; then name-match — for cards with null player_id, ilike the list player names
--     (case-insensitive). Additive, or "clear other chases first" (replace). Reports matched (+cleared).
--     All writes go through the existing e10_cards UPDATE policy (same one the per-row chase checkbox uses).
--   • Bulk in the grid (scBulkChase): Mark / Unmark chase across the CURRENT filter/search (one UPDATE
--     scoped by the same dbCardFilters the grid uses), reversible, count toasted; whole-checklist needs a
--     confirm. "Save chases as list" collects the checklist's distinct chase players into a new list.
--   • Import review offers a matching chase list (auto-selected when its sport/league appears in the
--     checklist name/set) and flags matching-name cards on the pending import — suggest, never forced.
--   Standing UX pass in scope: destructive confirms (delete list) + toasts on every mutation + Enter-to-
--   submit (list name) + async button-disable while applying + terse empty states; shared grid untouched.

-- ─────────────────────────────────────────────────────────────
-- CLIENT-ONLY (no schema/RLS change): end-to-end workflow QA fix pass. The pricing engine math was
-- hand-verified sound (margin resolves to exactly targetMargin, all divisors guarded); fixes below are
-- integrity / stale-render / silent-failure bugs found auditing all 7 workflows.
--   SILENT DB FAILURES surfaced (were empty catch → false success): liveEnd (kept session on failed end),
--     livePatchSession (kept local proj/checklist diverging from DB), liveConfirmReview + liveStart per-slot
--     inserts (now count + warn "N spot(s) failed"), commitImport card_count, dbEnsureSet (unlinked set),
--     resolveTeams (warns N teams unlinked), writeRow cloud upsert (was console.warn-only → toast).
--   STALE / CARRY-OVER: overlay.html slot-realtime now re-runs loadTeams() so team spots added after the
--     overlay loaded show their logos (were stuck on monogram until reload); show builder product edit now
--     re-renders the builder so the hero break-cost updates (was #prodBox only).
--   CORRECTNESS: bkPreRankTiers (+ computePlan label) tier quantile assigned the wrong band when slots <
--     tiers (n=2 gave S then B, skipping A) → now top-tiers-first; genSchedule pushed shows with NO id so
--     showById(undefined) always resolved the LAST generated show → now unique id + products/needs; scEdit
--     rejects NaN/negative card values and reverts the row on a failed write; liveNextPos() bases new slot
--     position/label on max(position)+1 (was array length → collisions after a delete); liveReopen now also
--     nulls buyer_handle/uid/price (stale winner no longer resurfaces in the sold modal); addInv stamps
--     addedAt (aging was measured from last reload); liveProgressHTML no longer says "On track" when there
--     is no LOW band. Plus: scAddCard success toast.
-- FLAGGED FOR FOLLOW-UP (bigger / design calls, not done): case-insensitive player/team import dedup +
--   atomic batch (lower(name) expression index blocks a clean upsert-onConflict — needs a normalized column);
--   chaseApply name-match should use the same chaseNorm as the import preview (normalized column);
--   reservation-vs-qty reconciliation (markSold/breakConsume reduce qty but leave reservations → phantom
--   available); reserveModelToShow SET-vs-+= under-reserves on duplicate invItems; on-cam overlay chaseboard
--   (bottom 1728) + now-bar (1740) intrude into the bottom-15% keep-clear zone; liveStart-from-show seeds
--   only projection rows, dropping ruleSlots' team_id/bands (route show-start through liveLoadFormat);
--   bkTierField/bkSlotOverride stale per-slot band spans (targeted span update to avoid focus loss).

-- ─────────────────────────────────────────────────────────────
-- APPLIED (migration e10_name_norm_dedup) — the ONE migration for the flagged follow-up fixes.
--   e10_players.name_norm + e10_teams.name_norm: text GENERATED ALWAYS AS (lower(btrim(name))) STORED,
--     each with a UNIQUE index (e10_players_name_norm_uidx / e10_teams_name_norm_uidx). Generated → existing
--     rows untouched, stays in sync automatically; verified 0 pre-existing collisions so the unique index
--     built cleanly. RLS UNCHANGED (columns inherit each table's InitPlan-wrapped policies; nothing loosened).
--   Used by the client for: (a) IMPORT DEDUP — resolveTeams / planResolution / commitImport now look up
--     existing rows by name_norm and insert new ones via upsert(onConflict:'name_norm',ignoreDuplicates)
--     so a single case/whitespace-variant collision skips just that row instead of rolling back the whole
--     batch (the old atomic insert + case-sensitive .in() dropped up to 200 rows silently); and (b)
--     chaseApply name-match — the import preview (clApplyChaseListToImport) now normalizes the same way
--     (trim+lower) as the server apply, so preview and apply flag the same cards.
-- Client-only companions (no schema): A1 show→live seeding now carries the format's ruleSlots (team_id +
--   tiers + bands + projection), not just projection rows (liveStart rich-seed branch); A2 invClampRes()
--   trims reservations to on-hand qty on every qty drop (invEditSave / markSold / breakConsume) so
--   available never lies; A3 reserveModelToShow aggregates invItems by itemId (SUM, not SET-overwrite) so a
--   duplicate-item model reserves the total while re-attach stays idempotent; C5 on-cam #chaseboard height
--   556 (bottom = 1632, off the keep-clear line); C6 bkBandSpanHTML/bkRefreshBands update per-slot band
--   spans in place on a tier/override edit (no full re-render, focus retained).
-- Verified live (UI drive + SQL/DOM read): B teams 'argentina'/'ARGENTINA' → same existing id + new team
--   created, no rollback; A3 reserved=2; A2 qty 1 → reserved clamped to 1, available 0; A1 3 rich slots
--   (Argentina:A:120 …) + proj 140/300/660; C5 chaseboard bottom 1632; C6 span $80→$999 in place, focus kept.

-- ─────────────────────────────────────────────────────────────
-- CLIENT-ONLY (no schema/RLS change): Excel-style per-column filtering in the shared grid engine.
--   Built once into the engine (gRenderList now emits thead[header + a .gfilt filter row] / tbody, plus a
--   focus-preserving gRenderBody that refreshes only the data rows). Each column declares filter via
--   `filter`: 'text' | 'num' | 'enum' | false (default text; num when type==='num'); values read via
--   filterGet||sortVal, enum distinct via enumGet||sortVal or a fixed enumVals. Text ops: contains
--   (default) / not-contains / equals / starts / ends / is-empty / not-empty. Num ops: = ≠ ≥ ≤ between.
--   Enum: multi-select checkboxes + All/Clear. AND across columns, coexists with header-click SORT;
--   per-column ✕ clear + global Reset; saved views capture colFilters. Push-down: client grids filter the
--   in-memory array (gApplyColFilters); the server-backed 55k card grid translates each filter into the
--   Supabase query (dbCardColFilters: ilike / not.ilike / in / eq/neq/gte/lte/range / is-null) so it
--   filters the FULL dataset across all pages, keeping the trigram path.
--   Wired + verified: INVENTORY (folded its Category/Set/Grading/Grade≥/Year/Status top-band into column
--   filters; top bar slimmed to Search + Owner + Columns/Views/Reset) — text contains/not-contains, num ≥
--   and between, enum multi-select, combined all pass. CARD GRID — Type=insert → 431 (SQL-matched), name
--   contains "Messi" on 55,677 cards → 204 (SQL-matched) in ~250ms; top-band folded into column filters.
-- COVERAGE MAP (every list/table surface → status):
--   already-on-shared-grid (get filtering now): Inventory, Checklist cards (e10_cards grid), Import-review
--     grid (opt-in pending — flagged). Migrate-recommended (FLAGGED, engine ready): Buy list, Reporting
--     tables (by-category etc.), Players list, Teams list, Whatnot export, Ship/fulfillment detail,
--     Break/Format chase-pool & product/auction lists, Copy sets, Break-models, Checklists list,
--     Attachments. Intentionally bespoke (leave): Schedule calendar (day/week/month), Live-break mobile
--     worklist (touch cockpit), Home cockpit cards, buyer-GROUPED fulfillment (grouping is the point),
--     Break tier-band editor & spot-plan (form/derived, not a record list), To-dos (checklist UI).
