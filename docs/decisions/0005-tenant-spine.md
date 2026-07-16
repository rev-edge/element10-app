# 0005 — The tenant spine (Foundation Gate, Track A step 6 — design)

**Status:** PROPOSED — awaiting the A6-0 human gate ("A6 design approved"). No build checkpoint (A6a–d) runs until
this is approved. **The largest schema change in the project's history.**
**Hard constraint:** ZERO production changes in all of A6. Designed, built, backfilled, and tested in LOCAL +
STAGING only. Tenant-zero migrates to prod at A10, after A7's isolation proof.
**Binding inputs:** ADR 0004 (two-principal identity, two-tier viewer contract, capacity), `docs/DOMAIN_MAP.md`
(the four-layer classification + the four roles + shared-catalog decision), the A5.1 expand/contract discipline.

This doc gives concrete DDL sketches, the PK strategy, the per-RPC org-derivation contract, the viewer predicates,
the two index families, the tenant-zero backfill, realtime/storage scoping, and the expand→contract sequence that
keeps prod untouched until A10. It ends with the **open decisions for the gate**.

---

## 0. Layer classification (what gets `organization_id`, what does not)
From `docs/DOMAIN_MAP.md`:

- **COMPANY-OWNED → `organization_id NOT NULL` + org-scoped RLS/RPCs/idempotency:** `e10_inventory_items`,
  `e10_inventory_reservations`, `e10_inventory_movements`, `e10_mutation_receipts`, `e10_workspace`
  (shows/schedules/notes/todos JSONB), `e10_break_sessions`, `e10_break_slots`, `e10_break_events`, and the
  `e10_obs_*` competitive-intel subsystem (an org's private analytics — see **Open decision B**).
- **SHARED REFERENCE (platform-level, NO `organization_id`):** `e10_cards`, `e10_players`, `e10_sets`,
  `e10_teams` — the canonical catalog (ADR-domain decision #1: shared canonical + org overlays). `e10_checklists`
  is proposed to stay platform too (see **Open decision A**). Overlay = a *hook*, not built (§8).
- **IDENTITY:** `e10_members` → re-keyed to org memberships; `e10_viewers` stays **platform-global** (never
  org-scoped); `e10_role_permissions` → org-scoped role permission sets.
- **PARTICIPATION:** `e10_session_viewers` gains `organization_id` (inherited from its session) but authorizes
  *viewers* (global) — the bridge between the two principals.
- **OPS/BACKUP (unchanged):** `e10_bigimport_backup`, `e10_seed_backup` (RLS deny-all, service-role only).

---

## 1. Org-core schema (new tables — A6a)

```sql
create table e10_organizations (
  id           uuid primary key default gen_random_uuid(),
  slug         text unique not null,
  name         text not null,
  status       text not null default 'active',        -- active | suspended
  settings     jsonb not null default '{}'::jsonb,
  created_by   uuid,
  created_at   timestamptz not null default now()
);

-- org-DEFINED roles (evolve the 4-role enum into per-org rows so they are customizable + cloneable)
create table e10_organization_roles (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null references e10_organizations(id) on delete cascade,
  key             text not null,        -- default keys: admin | manager | streamer | ops  (+ custom)
  name            text not null,
  is_system       boolean not null default false,  -- the 4 shipped defaults (undeletable), customs = false
  created_at      timestamptz not null default now(),
  unique (organization_id, key)
);

-- permission SETS: org × role × capability, deny-list preserved (empty = all allowed), evolves e10_role_permissions
create table e10_organization_role_permissions (
  organization_id uuid not null references e10_organizations(id) on delete cascade,
  role_id         uuid not null references e10_organization_roles(id) on delete cascade,
  capability      text not null,        -- 'act.inventory_edit', 'act.live_run', 'act.fulfillment', ...
  allowed         boolean not null default true,
  updated_by      uuid,
  updated_at      timestamptz not null default now(),
  primary key (organization_id, role_id, capability)
);

create table e10_organization_memberships (
  organization_id uuid not null references e10_organizations(id) on delete cascade,
  user_id         uuid not null,        -- auth.users.id
  role_id         uuid not null references e10_organization_roles(id),
  display_name    text,
  status          text not null default 'active',      -- active | invited | suspended
  created_at      timestamptz not null default now(),
  primary key (organization_id, user_id)
);

create table e10_organization_invitations (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null references e10_organizations(id) on delete cascade,
  email           text not null,
  role_id         uuid not null references e10_organization_roles(id),
  token           text not null unique,
  invited_by      uuid,
  status          text not null default 'pending',     -- pending | accepted | revoked | expired
  expires_at      timestamptz,
  created_at      timestamptz not null default now()
);

create table e10_organization_modules (          -- entitlements: which verticals/features an org has
  organization_id uuid not null references e10_organizations(id) on delete cascade,
  module_key      text not null,                  -- 'core' | 'cards' | (future verticals)
  enabled         boolean not null default true,
  settings        jsonb not null default '{}'::jsonb,
  primary key (organization_id, module_key)
);

-- PLATFORM ADMINISTRATOR — a concept ABOVE orgs, NEVER modeled as org membership
create table e10_platform_admins (
  user_id    uuid primary key,
  created_by uuid,
  created_at timestamptz not null default now()
);
```

**Role clone RPC (customizable + copyable, per domain decision #2):**
`e10_org_role_clone(p_org uuid, p_src_role uuid, p_dst_role uuid)` — copies the source role's permission-set rows
into the destination role as a starting point (admin-capability gated). Default permission sets for the four
system roles ship as A6a seeds.

**Helpers (evolve `e10_is_admin/is_member/is_org/has_cap`), all `SECURITY DEFINER`, `search_path=public`, born
locked → explicit `grant execute to authenticated`:**
- `e10_is_platform_admin()` → `exists(select 1 from e10_platform_admins where user_id = auth.uid())`.
- `e10_is_org_member(org uuid)` → active membership `(org, auth.uid())`, OR platform admin.
- `e10_is_org_admin(org uuid)` → member whose role is the org's `admin` system role (or holds the admin cap).
- `e10_has_org_cap(org uuid, cap text)` → **deny-list preserved:** platform-admin OR (member of org AND NOT
  exists a `role_permissions` row for their role+cap with `allowed=false`).
- `e10_current_org()` → **single-membership fast path (input 8):** if `auth.uid()` has exactly ONE active
  membership, return its org; else `null` (the multi-org caller must pass `p_organization_id`).
- **InitPlan discipline:** no-arg helpers wrapped `(select …)` in policies; org-argument helpers are row-correlated
  (left bare, like `e10_owns_session`).

---

## 2. PK strategy for existing tables — **RECOMMENDATION: composite `(organization_id, id)`**

**Decision:** add `organization_id` and make it the **leading PK column** on every company-owned table, keeping the
existing `id` **values unchanged** (never regenerated). Child links become composite:
`e10_inventory_movements(organization_id, item_id) → e10_inventory_items(organization_id, id)`.

**Why (vs the alternative "keep single-column `id` PK + `organization_id` column + `UNIQUE(org,id)` + RLS/trigger"):**
1. **The `item_id text` linkage stays load-bearing and un-regenerated.** `id` values (`'iS02'`, uuids) are never
   touched; the key merely gains a leading `organization_id`. Movements/receipts/reservations reference items by
   `(organization_id, item_id)` — the append-only ledger's *content* (deltas, timestamps, actors) is untouched; a
   composite FK is a constraint change, not a data change.
2. **Physical cross-org integrity.** A composite FK makes it structurally impossible for org A's movement to
   reference org B's item. Option B relies on RLS + a trigger to catch what the key would otherwise allow — weaker,
   and the whole point of the spine is isolation.
3. **The org-leading member index family comes FREE** — the PK btree already leads with `organization_id`.
4. **Tenant-zero is a no-op semantically:** with one org, `(org0, id)` behaves exactly like `id` — no collision,
   no behavior change for the current single-org client.

**Cost + mitigation:** composite joins are more verbose. Mitigated because **RPCs derive org server-side and write
the joins** (§4) — the client never hand-writes them. `e10_workspace` keeps its text ids (`'shared'`,`'universal'`,
`'user:<uuid>'`) but per-org: PK `(organization_id, id)`, so each org owns its own `'shared'` row (retires the
singular-`'shared'` assumption).

**Per-table PK / FK plan:**
| Table | New PK | Composite FK(s) added |
|---|---|---|
| `e10_inventory_items` | `(organization_id, id)` | — |
| `e10_inventory_movements` | `(organization_id, id)` | `(organization_id, item_id) → items` |
| `e10_inventory_reservations` | `(organization_id, id)` | `(organization_id, item_id) → items` |
| `e10_mutation_receipts` | `(organization_id, idempotency_key)` | idempotency re-scoped to `(org, key)` |
| `e10_workspace` | `(organization_id, id)` | — |
| `e10_break_sessions` | `(organization_id, id)` | `(organization_id, live_session_id) → live_sessions` (§7) |
| `e10_break_slots` | `(organization_id, id)` | `(organization_id, session_id) → break_sessions` |
| `e10_break_events` | `(organization_id, id)` | `(org, session_id)→sessions`, `(org, slot_id)→slots` |
| `e10_session_viewers` | `(organization_id, session_id, user_id)` | `(org, session_id) → break_sessions` |
| `e10_obs_*` | `(organization_id, id/key)` | intra-subsystem composite FKs |

---

## 3. Two index families (enumerated per table)
**Member family — leads with `organization_id`** (mostly the PK, plus):
- items: `(organization_id, cat)`, `(organization_id, updated_at)`
- movements: `(organization_id, item_id, created_at)`, `(organization_id, created_at)`
- reservations: `(organization_id, item_id) where status='active'`
- break_sessions: `(organization_id, status)`, `(organization_id, source_show_ref)`
- break_slots: `(organization_id, session_id, position)`
- break_events: `(organization_id, session_id, created_at)`
- receipts idempotency: `(organization_id, idempotency_key)` (PK)

**Viewer family — leads with `buyer_uid` / `user_id`** (a global viewer's cross-streamer reads have no org to lead
with):
- break_slots: `(buyer_uid, sold_at)`, `(buyer_uid, created_at)` — "my purchases across every streamer"
- session_viewers: `(user_id, created_at)` — "sessions I've joined across orgs"
- viewer handle claims: `(user_id)`, `(lower(whatnot_handle))`

---

## 4. Org-derivation contract for existing RPCs (input 8 — backward compatible)
Every mutation/read RPC gains an **optional** `p_organization_id uuid default null`, never sent by the current
single-org client, and resolves:
```
org := coalesce(p_organization_id, e10_current_org());
if org is null then raise 'organization_required';   -- only trips a multi-org caller who omitted it
if not e10_is_org_member(org) then raise 'not_a_member';
if not e10_has_org_cap(org, '<the RPC's capability>') then raise 'forbidden';
-- ... all reads/writes scoped to `org`; item/session lookups keyed (org, id) ...
```
Applies to: `e10_inv_add_item / edit_item / delete_item / get / list / reserve / release / set_reservations /
consume / reverse_consumption / mark_sold`, `e10_emit_inventory_movement`, and the onboarding/role RPCs
(`e10_add_member → invitations`, `e10_assign_role / set_role → org roles`, `e10_buyer_suggest`, `e10_redeem_code`).
`e10_inv_list()` returns only the caller's org rows. **The deployed single-org client keeps working**: it calls
these with no org param → resolves to the sole membership. `e10_schema_version()` and the viewer/spectator reads
are unaffected. (No client changes in A6 — this is server-side only.)

---

## 5. Viewer principal — spectator vs participant predicates
Per ADR 0004's two-tier contract + the `e10_break_slots` field reality (public: `label,tier,price,state,team_id,
player_id,position,case_hit,sold_at,method,band_*`; **private:** `buyer_uid,buyer_handle,ship_state,ship_note,
incentives`).

- **Spectator surface = an allowlisted PROJECTION only.** A new `e10_session_public(sess)` RPC / view returns
  **only the public columns**, readable by any authenticated user when the session is live/shared. Spectators get
  **no direct SELECT** on `e10_break_slots`. Predicate `e10_can_spectate_session(sess)` (authenticated + session
  status live/shared).
- **Participant-private = ownership.** Direct reads of a slot's private fields require `buyer_uid = auth.uid()`
  (or a **verified** handle match, §6) — *not* mere session participation. Predicate `e10_owns_slot(slot)`.
- **`e10_can_read_session(sess)`** is refactored to name the tiers explicitly: org-member (full) · spectator
  (public projection) · participant (own private rows). It is **necessary but not sufficient** for private data.
- **Broadcast (A9 hook, not built):** the **public session topic** authorizes via `e10_can_spectate_session`;
  **participant-private payloads** authorize via `e10_owns_slot` — never one channel with mixed payloads, never a
  single broadened predicate (§9 naming).

---

## 6. Handle-to-account verification (first-class in the schema; UX later)
`e10_viewers` gains `handle_verified boolean not null default false`, `handle_verified_at timestamptz`,
`verification_method text`. Plus a claim table:
```sql
create table e10_viewer_handle_claims (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null,                 -- the global viewer account
  whatnot_handle text not null,
  status       text not null default 'pending',   -- pending | verified | rejected
  evidence     jsonb, verified_at timestamptz, created_at timestamptz not null default now(),
  unique (lower(whatnot_handle))               -- a handle attributes to one account
);
```
A **verified** handle is what lets a slot's `buyer_handle` attribute to a global `buyer_uid` across streamers
(the participant predicate trusts verified matches only). Verification UX ships post-A6.

---

## 7. Session ⊃ breaks (1–n) — structural provision (domain map v1.1)
The current `e10_break_sessions` ≈ one break; the corrected model is a **go-live session containing 1–n breaks
with per-break rollups.** A6 must not preclude it. **Provision (additive, cheap):**
```sql
create table e10_live_sessions (            -- the "go live" event; org-scoped; maps to a show
  organization_id uuid not null,
  id uuid default gen_random_uuid(),
  source_show_ref text, name text, status text, created_at timestamptz not null default now(),
  primary key (organization_id, id)
);
-- e10_break_sessions (the BREAK unit) gains a nullable parent link:
alter table e10_break_sessions add column live_session_id uuid;   -- FK (organization_id, live_session_id)
```
Backfill groups existing break-sessions under per-`source_show_ref` live-sessions (1:1 where no show ref). Per-break
rollups aggregate to the live-session later. A6 ships the parent table + nullable link only; the full hierarchy/UX
is a later pass. This keeps `session≈break` from being baked into the org columns or the Broadcast naming.

---

## 8. Storage + catalog overlay hooks (hooks only)
- **Storage:** company-owned uploads move under an org-scoped path `org/{organization_id}/card/…`; `storage.objects`
  policies gain an org-path predicate. Platform catalog images stay platform-pathed. A6 implements org-pathing for
  new company uploads; existing tenant-zero images are re-pointed during backfill (staging).
- **Catalog overlay hook (NOT built):** the shared catalog (`e10_cards/players/sets/teams`) stays platform-level;
  org corrections/custom entries land later in an org-scoped overlay table, e.g.
  `e10_card_overlays(organization_id, card_id, patch jsonb, provenance …)` referencing platform card ids. A6
  documents the seam; the promotion flywheel (private upload → platform review → shared) is Phase 6.

## 8b. SMTP / onboarding
Two onboarding flows: **member** = invite (`e10_organization_invitations` + a redeem RPC, admin-gated) — low
volume; **viewer** = self-serve signup — **high volume, the custom-SMTP driver.** Custom SMTP is a known
dependency for the multi-org/public future (Supabase's built-in SMTP is rate-limited); recorded here, provisioned
before the first external org, not in A6.

---

## 9. Realtime / Broadcast naming (A9 hook — documented, not implemented)
- **Member operational surfaces** (inventory grid, schedule): org-filtered Postgres Changes; channel `org:{org_id}`.
- **Session public topic** (spectator, A9 Broadcast): `session:{session_id}:public` — authorized by
  `e10_can_spectate_session`; carries only public projection fields.
- **Participant-private**: delivered per-recipient (a per-viewer private channel or ownership-filtered payloads),
  authorized by `e10_owns_slot`. Never mixed onto the public topic.
- Broadcast is **emitted from the DB** (a `realtime.send` inside the mutation RPC), so the channel name must be
  derivable from `(organization_id, session_id)` inside the RPC — which the composite keys guarantee.

---

## 10. Cross-org privacy invariant (input 5 — its own test)
The same global viewer appears in org A's and org B's `session_viewers`/`break_slots` rows. **A member of org A must
never see that viewer's org-B activity.** Holds because those rows carry `organization_id` and member RLS filters
`organization_id = <the member's org>`; the viewer's own cross-org view is a *viewer-authenticated* query keyed by
`buyer_uid = auth.uid()`. A6d's `rls_test` adds the explicit case: an org-A member's SELECT on slots/session_viewers
returns **zero** org-B rows even for a viewer present in both.

---

## 11. Tenant-zero backfill plan (A6b — staging only)
1. **Restore** a production snapshot into a **staging copy** (never touch prod; the read-only prod gate stays fine).
2. Create the tenant-zero org (`org0`) + its four system roles + default permission sets + `core`/`cards` modules;
   map the current `e10_members` rows to `(org0, user, role_id)`; seed `e10_platform_admins` for Trent's platform
   identity (separate from org membership).
3. **Backfill** `organization_id = org0` on every company-owned row (one UPDATE per table — all current data is one
   org), then promote `organization_id` to `NOT NULL` and swap in the composite PKs/FKs.
4. `e10_workspace` → `(org0, 'shared'|'universal'|'user:*')`; idempotency receipts → `(org0, key)`.
5. **Verify (A6b acceptance):** every row owned (no null `organization_id`); counts reconcile (35 items / 41
   movements / 6 receipts / …); recon views drift 0; ledger history content byte-intact (checksum before/after);
   the read-only gate passes against the backfilled **staging** DB. Paste every query.

---

## 12. Migration sequencing — explicit EXPAND → BACKFILL → DEPLOY → OBSERVE → CONTRACT (input 9)
The schema-version gate protects only the client being deployed; an already-open old client writes through a
migration. So **nothing renames/removes/contracts in the same release as its replacement.** The A6→A10 rollout:

1. **EXPAND (A6a–c, staging):** additive only — new org tables; `organization_id` added **nullable**; a
   `UNIQUE(organization_id, id)` index + composite FKs added **alongside** the existing `id` PK; RPCs gain the
   optional `p_organization_id` and derive org. Supports client N (single-org, no org param) AND N+1 (org-aware).
2. **BACKFILL (A6b, staging):** `org0` on all rows; verify.
3. **PROMOTE (staging, still expand-safe):** `organization_id NOT NULL`; swap PK to `(organization_id, id)`. The old
   client still works (server derives org).
4. **A7 isolation proof → A10 PROD cutover:** the SAME expand migration to prod → backfill prod → **deploy the
   org-aware new-shell client** → **observe** old-client traffic drain (the deployed single-org client keeps working
   via server-side derivation throughout).
5. **CONTRACT (separate, later migration, after drain):** remove the single-org shims — retire the
   `e10_current_org()` fallback as a *requirement*, drop any legacy singular-`'shared'` assumptions, tighten
   policies. Only here does anything get removed.

The **standing release discipline** (this rule) lands in `docs/OPERATIONS.md`.

---

## Open decisions for the gate (Trent + reviewer)
- **A — `e10_checklists` layer.** Input 3 lists "org-uploaded checklists" as company-owned, but `e10_cards`
  (platform) reference `checklist_id`, so making checklists org-scoped creates a platform→org FK (inverts the
  layering). **Recommendation:** keep `e10_checklists` **platform-level** (tenant-zero's existing 4 are canonical
  seed); serve "org-uploaded checklist" via the **org-scoped upload/overlay hook** (§8, future), promoted to
  canonical by the Phase-6 flywheel. Approve, or scope checklists to orgs and duplicate the catalog per tenant.
- **B — `e10_obs_*` competitive intel.** **Recommendation:** org-scoped (company-owned — an org's private watch
  list + captures), with a future path to promote raw market observations to shared reference (like the checklist
  flywheel). Approve, or classify some obs data as platform-shared market reference now.
- **C — PK strategy.** Composite `(organization_id, id)` (§2). Approve, or take the lighter single-column-id +
  `UNIQUE(org,id)` + RLS/trigger option (weaker isolation).
- **D — session⊃breaks provision.** Add the `e10_live_sessions` parent hook now (§7). Approve, or defer entirely
  (risk: A6 bakes session≈break into org columns/naming).

## Out of scope (this doc / all of A6)
Any production change (A10). The hostile adversarial campaign (A7). Bounded reads (A8) + Broadcast implementation
(A9) beyond the hooks named here. The catalog overlay + promotion flywheel (Phase 6). All UI (Track B). Billing.

---
**⏸ STOP. This design requires "A6 design approved" (Trent + reviewer) before A6a runs.**
