# 0005 — The tenant spine (Foundation Gate, Track A step 6 — design)

**Status:** PROPOSED — **revision 3** (2026-07-17). rev2 = the reviewers' 8 revisions + 4 rulings; **rev3 adds:** a
zero-downtime write bridge + corrected backfill/cutover order (§12); RPC scope derivation classified by
member/entity/invitation/viewer context (§4); an explicit grants/RLS/index matrix per org-core table (§1.2); exact
module-capability + entitlement semantics with no undefined wildcard (§1.1); verified-only + expiring handle-claim
uniqueness (§6); removal of the ambiguous `can_read_session` (§5); and the buyback/repack future invariants (§13).
Awaiting the A6-0 human gate ("A6 design approved") from BOTH reviewers. No build checkpoint (A6a–d) runs until
approved. **The largest schema change in the project's history.**
**`docs/DOMAIN_MAP.md` reconciled (v1.2, 2026-07-17)** with Trent's current content — the checklist/role
corrections, the A–D rulings, the prototype ①–⑥ concepts, and the repack/store-credit invariants are folded in; no
decided item dropped.
**Hard constraint:** ZERO production changes in all of A6. Designed, built, backfilled, tested in LOCAL + STAGING
only. Tenant-zero migrates to prod at A10, after A7's isolation proof. (Read-only prod gate under
`E10_ALLOW_PROD=1` stays fine.)
**Binding inputs:** ADR 0004 (identity + two-tier viewer contract + capacity), `docs/DOMAIN_MAP.md` (four-layer
classification, four roles, shared-catalog decision), the A5.1 expand/contract discipline.

---

## 0. Identity model — one account, multiple authorization CONTEXTS (revision 7)
**Correction to the earlier "a viewer is never a member" framing (and to ADR 0004's phrasing):** membership and
viewer-ness are **authorization *contexts* on a single account**, not mutually exclusive account types. One
`auth.users` account may simultaneously be a **member** of one or more orgs (via `e10_organization_memberships`)
**and** a **platform-global viewer/buyer** (via `e10_viewers` + session participation). The person on Trent's team
who buys spots in a competitor's break is both — a member of org A and a viewer in org B.

- **Member context** authorizes org-scoped access, isolated by `organization_id`.
- **Viewer context** authorizes session-participation-scoped access, spans orgs, and **never grants org-scoped RLS
  for an org the account is not a member of.**
- **Isolation still holds and gets its own test:** a member of org A who buys as a viewer in org B — that org-B
  purchase is invisible to their org-A colleagues (org A's member RLS only matches org-A rows; the org-B slot
  carrying their `buyer_uid` is org-B-scoped). See §10 + the A6d test.

## 0.1 Layer classification (`docs/DOMAIN_MAP.md`)
- **COMPANY-OWNED → `organization_id NOT NULL` + org-scoped RLS/RPCs/idempotency:** `e10_inventory_items`,
  `_reservations`, `_movements`, `e10_mutation_receipts`, `e10_workspace`, `e10_break_sessions`, `e10_break_slots`,
  `e10_break_events`, and the `e10_obs_*` competitive-intel subsystem (Ruling B).
- **SHARED REFERENCE (platform-level, NO `organization_id`, READ-ONLY to tenants):** `e10_cards`, `e10_players`,
  `e10_sets`, `e10_teams`, `e10_checklists` (Rulings A). **No tenant writes to the platform catalog** (Ruling A).
- **IDENTITY:** `e10_members` → org memberships; `e10_viewers` stays platform-global; `e10_role_permissions` →
  org-scoped role permission sets (allow-list, revision 2).
- **PARTICIPATION:** `e10_session_viewers` gains `organization_id` (from its session) but authorizes viewers.
- **OPS/BACKUP unchanged** (RLS deny-all, service-role only).

---

## 1. Org-core schema (new — A6a)

**Authorization helpers live in a non-REST-exposed internal schema `e10` (revision 8)** — PostgREST exposes only
`public`, so nothing in `e10` is reachable via `/rest/v1/rpc`. `public` holds ONLY intentional client RPCs.
`authenticated` gets `USAGE` on `e10` + `EXECUTE` on its predicates (needed for RLS evaluation), but they are off
the API surface entirely (this structurally retires the residual advisor-0029 concern for predicate helpers).

```sql
create schema if not exists e10;   -- internal; NOT in PostgREST's exposed schema list

create table public.e10_organizations (
  id uuid primary key default gen_random_uuid(),
  slug text unique not null, name text not null,
  status text not null default 'active', settings jsonb not null default '{}'::jsonb,
  created_by uuid, created_at timestamptz not null default now()
);

-- org-DEFINED roles: composite PK so all references are (organization_id, role_id) (revision 1)
create table public.e10_organization_roles (
  organization_id uuid not null references public.e10_organizations(id) on delete cascade,
  id uuid not null default gen_random_uuid(),
  key text not null,                 -- system keys: admin|manager|streamer|ops (+ custom)
  name text not null, is_system boolean not null default false,
  created_at timestamptz not null default now(),
  primary key (organization_id, id),
  unique (organization_id, key)
);

-- permission SETS — ALLOW-LIST: a row PRESENT-and-allowed grants; ABSENT = DENY (revision 2, inverts the old deny-list)
create table public.e10_organization_role_permissions (
  organization_id uuid not null,
  role_id uuid not null,
  capability text not null,          -- act.inventory_edit | act.lists_edit | act.live_run |
                                     -- act.permissions_config | act.reporting_export | act.team_manage | mod.<key>
  allowed boolean not null default true,
  updated_by uuid, updated_at timestamptz not null default now(),
  primary key (organization_id, role_id, capability),
  foreign key (organization_id, role_id) references public.e10_organization_roles(organization_id, id) on delete cascade
);

create table public.e10_organization_memberships (
  organization_id uuid not null references public.e10_organizations(id) on delete cascade,
  user_id uuid not null,
  role_id uuid not null,
  display_name text, status text not null default 'active',
  created_at timestamptz not null default now(),
  primary key (organization_id, user_id),
  foreign key (organization_id, role_id) references public.e10_organization_roles(organization_id, id)
);

create table public.e10_organization_invitations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.e10_organizations(id) on delete cascade,
  email text not null,
  role_id uuid not null,
  token_hash text not null,          -- HASH of the token, never the token (revision 5)
  invited_by uuid,
  status text not null default 'pending',
  expires_at timestamptz not null,   -- expiry REQUIRED (revision 5)
  created_at timestamptz not null default now(),
  foreign key (organization_id, role_id) references public.e10_organization_roles(organization_id, id),
  unique (organization_id, token_hash)
);

create table public.e10_organization_modules (   -- entitlements
  organization_id uuid not null references public.e10_organizations(id) on delete cascade,
  module_key text not null, enabled boolean not null default true,
  settings jsonb not null default '{}'::jsonb,
  primary key (organization_id, module_key)
);

-- PLATFORM ADMIN — above orgs, never org membership; RLS DENY-ALL (service-role/definer only)
create table public.e10_platform_admins (
  user_id uuid primary key, created_by uuid, created_at timestamptz not null default now()
);
-- alter table … enable row level security;  -- and NO policy → deny-all to anon/authenticated
```

**Allow-list model + parity seed (revision 2 — the subtle correctness point):**
- `e10.has_org_cap(org, cap)` := platform-admin **OR** (active member of `org` **AND EXISTS** a
  `role_permissions` row for their role+cap with `allowed=true`). **Empty ⇒ denied** (opposite of the current
  deny-list `e10_has_cap`).
- A6a seeds explicit grants for the four **system** roles (sensible defaults): e.g. Admin = all six `act.*` +
  `mod.*`; Manager = inventory/lists/reporting/live; Streamer = live_run + lists; Ops = fulfillment/reporting.
- **Tenant-zero parity seed (A6b acceptance):** because today's model is deny-list (every member has EVERY cap),
  the tenant-zero backfill MUST grant, to the roles its current members map to, **every currently-exercised
  capability** — the enumerated set `act.inventory_edit, act.lists_edit, act.live_run, act.permissions_config,
  act.reporting_export, act.team_manage` + the active `mod.*` — so the deny-list→allow-list flip is **behaviorally
  invisible at cutover.** A6b **proves parity per user:** for every current member, every `hasCap(x)` that returns
  true today returns true after the flip. (A6a enumerates the full cap set by grepping `has_cap`/`hasCap` call
  sites; this list is the floor.)
- **Clone RPC** `e10_org_role_clone(p_org, p_src_role, p_dst_role)` copies the source role's permission-set rows
  (the allow grants) as a starting point; admin-cap gated.

### 1.1 Module-capability + entitlement semantics — NO undefined wildcard (rev3)
Two orthogonal, both-required gates; there is **no stored or honored `mod.*` wildcard** — every capability is a
concrete string.
- **Entitlement** (`e10_organization_modules.module_key`) = the coarse bundle an **org HAS** (billing/provisioning
  level). Enumerated set: **`core`, `cards`** (future verticals add siblings). Written by platform admin.
- **Module capability** (`role_permissions.capability = 'mod.<key>'`) = whether a **role** may use a nav module.
  The `<key>` set is **exactly enumerated** from the client's nav groups: `mod.home, mod.schedule, mod.inventory,
  mod.checklists, mod.modeler, mod.teams, mod.live, mod.fulfill, mod.reports, mod.team, mod.lists` (+ the literals
  `mod.settings, mod.toolkit`). A6a pins this list from the code; new modules add concrete keys, never a wildcard.
- **Action capabilities** (`act.*`) are the six enumerated in §1 (`inventory_edit, lists_edit, live_run,
  permissions_config, reporting_export, team_manage`).
- **Effective access to a nav module** = (org entitled: `e10_organization_modules` has `module_key` of the owning
  bundle, enabled) **AND** (role granted: `e10.has_org_cap(org, 'mod.<key>')`). Bundle ownership: `checklists,
  modeler, teams` → `cards`; the rest → `core`. `e10.has_org_cap` matches a concrete row only — a missing
  `mod.<key>` row is a deny (allow-list), and a disabled entitlement denies regardless of the role grant.

### 1.2 Grants / RLS / index matrix — org-core tables (rev3)
All writes flow through `SECURITY DEFINER` RPCs in `public` that call `e10.*` predicates; `authenticated` gets only
the SELECT reach below via RLS (no direct table INSERT/UPDATE/DELETE grants). `anon` gets nothing new.

| Table | SELECT (RLS `using`) | Writes | Key indexes |
|---|---|---|---|
| `e10_organizations` | `e10.is_org_member(id)` OR platform-admin | platform-admin (self-serve create later) | PK`(id)`, `unique(slug)` |
| `e10_organization_roles` | `e10.is_org_member(organization_id)` | `e10.is_org_admin(org)` ∧ `has_org_cap(org,'act.permissions_config')`; system roles undeletable | PK`(org,id)`, `unique(org,key)` |
| `e10_organization_role_permissions` | `e10.is_org_member(org)` | admin ∧ `act.permissions_config` | PK`(org,role_id,capability)`, `(org,capability)` |
| `e10_organization_memberships` | `e10.is_org_member(org)` OR `user_id=(select auth.uid())` | admin ∧ `act.team_manage` | PK`(org,user_id)`, **`(user_id)`** (the `current_org()` reverse lookup — load-bearing) |
| `e10_organization_invitations` | `e10.is_org_admin(org)` (invitee redeems by token, never reads the table) | admin ∧ `act.team_manage` | PK`(id)`, `unique(org,token_hash)`, `(token_hash)`, `(org,email)` |
| `e10_organization_modules` | `e10.is_org_member(org)` | **platform-admin** (entitlement = billing) | PK`(org,module_key)` |
| `e10_platform_admins` | **DENY-ALL** (RLS on, no policy → service-role/definer only) | service-role/definer | PK`(user_id)` |
| `e10_viewer_handle_claims` | `user_id=(select auth.uid())` OR platform-admin | INSERT own; verify = platform-admin | PK`(id)`, `(user_id)`, verified-unique `(lower(handle))` (§6) |
| `e10_live_sessions` | `e10.is_org_member(org)` (public surface via projection only) | member ∧ `act.live_run` | PK`(org,id)`, `(org,source_show_ref)`, `(org,status)` |

**Internal predicate helpers (schema `e10`, fully qualified, InitPlan-safe):** `e10.is_platform_admin()`,
`e10.is_org_member(org)`, `e10.is_org_admin(org)`, `e10.has_org_cap(org, cap)`, `e10.current_org()` (single-
membership fast path → the sole active membership, else null), `e10.can_spectate_session(sess)`,
`e10.owns_slot(slot)`. **`can_read_session` is REMOVED (rev3, §5)** — it conflated the three tiers; nothing
generic replaces it. The existing `public.e10_is_admin/is_member/is_org/has_cap/owns_session/can_read_session` are
**superseded by** the `e10.*` predicates during A6c and dropped at the contract migration (§12).

---

## 2. PK strategy — composite `(organization_id, id)` (Ruling C, corrected rationale)
**Decision:** `organization_id` leads the PK on every company-owned table; existing `id` **values are never
regenerated**; child links become composite. **Corrected rationale — apply composite CONSISTENTLY, including the
new org tables** (revision 1): `e10_organization_roles` is itself org-scoped with PK `(organization_id, id)`, so
memberships / invitations / role_permissions reference `(organization_id, role_id)` — no single-column-FK exception
anywhere in the tenant spine. The isolation guarantee is uniform: a composite FK makes a cross-org reference
structurally impossible, at every level.

- **`item_id text` linkage stays load-bearing + un-regenerated:** movements/receipts/reservations reference items
  by `(organization_id, item_id) → items(organization_id, id)`. The append-only ledger's *content* (deltas, times,
  actors) is untouched; the FK re-point is a constraint change, not a data change.
- **Org-leading member index family is free** (the PK btree leads with `organization_id`).
- **Tenant-zero is semantically a no-op** (one org ⇒ `(org0, id)` behaves as `id`).
- **Cost/mitigation:** composite joins are verbose; mitigated because RPCs derive org server-side and write the
  joins (§4), not the client.

| Table | New PK | Composite FK(s) |
|---|---|---|
| `e10_inventory_items` | `(organization_id, id)` | — |
| `e10_inventory_movements` | `(organization_id, id)` | `(organization_id, item_id) → items` |
| `e10_inventory_reservations` | `(organization_id, id)` | `(organization_id, item_id) → items` |
| `e10_mutation_receipts` | `(organization_id, idempotency_key)` | idempotency re-scoped `(org, key)` |
| `e10_workspace` | `(organization_id, id)` | — (each org owns its own `'shared'`/`'universal'` rows) |
| `e10_live_sessions` (new, §7) | `(organization_id, id)` | — |
| `e10_break_sessions` | `(organization_id, id)` | `(org, live_session_id) → live_sessions` |
| `e10_break_slots` | `(organization_id, id)` | `(org, session_id) → break_sessions` |
| `e10_break_events` | `(organization_id, id)` | `(org, session_id)→sessions`, `(org, slot_id)→slots` |
| `e10_session_viewers` | `(organization_id, session_id, user_id)` | `(org, session_id) → break_sessions` |
| `e10_obs_*` | `(organization_id, id/key)` | intra-subsystem composite FKs |

---

## 3. Two index families (per table)
**Member family (leads `organization_id`)** — mostly the PK, plus: items `(organization_id, cat)`,
`(organization_id, updated_at)`; movements `(organization_id, item_id, created_at)`, `(organization_id,
created_at)`; reservations `(organization_id, item_id) where status='active'`; break_sessions `(organization_id,
status)`, `(organization_id, source_show_ref)`; break_slots `(organization_id, session_id, position)`;
break_events `(organization_id, session_id, created_at)`; receipts `(organization_id, idempotency_key)` (PK).
**Viewer family (leads `buyer_uid`/`user_id`)** — break_slots `(buyer_uid, sold_at)`, `(buyer_uid, created_at)`;
session_viewers `(user_id, created_at)`; handle claims `(lower(whatnot_handle))` partial (§6).

---

## 4. RPC strategy — compatibility WRAPPERS, no overloads (revision 3)
**Not** optional params on existing signatures (that creates overloads PostgREST resolves ambiguously). Instead:
- **Keep every old signature byte-identical, as a thin WRAPPER** that derives the sole org and delegates:
  `e10_inv_add_item(p_item, p_key)` body → `select e10_org_inv_add_item(e10.current_org(), p_item, p_key)`.
  The deployed single-org client keeps calling the old names, unchanged, forever until contract.
- **New, DISTINCTLY-NAMED org-aware RPCs with a REQUIRED org argument:** `e10_org_inv_add_item(p_organization_id,
  p_item, p_key)`, `e10_org_inv_list(p_organization_id)`, etc. — each validates `e10.is_org_member(org)` +
  `e10.has_org_cap(org, <cap>)` and scopes all reads/writes to `org` (item/session lookups keyed `(org, id)`).
  The new-shell client (Track B) calls these with an explicit org.
- **Contract migration drops the wrappers** once old-client traffic drains (§12). No overloads at any point.

Covers: `e10_inv_*` (add/edit/delete/get/list/reserve/release/set_reservations/consume/reverse_consumption/
mark_sold), `e10_emit_inventory_movement`, and onboarding/role RPCs (`e10_add_member → invitations`,
`e10_assign_role/set_role → org roles`, `e10_buyer_suggest`, `e10_redeem_code`) — each old name a wrapper over an
`e10_org_*` counterpart. All are `public` client RPCs; predicates they call live in `e10` (revision 8).

### 4.1 Scope derivation classified by context (rev3)
How `org` is resolved + validated depends on the RPC's context. **Every class validates capability AND, where an
org is both supplied and derivable, asserts they MATCH** (an explicit `p_organization_id` may never override the
entity's/invitation's true org — that is the cross-org attack surface).

| Class | Which RPCs | Org source | Validation |
|---|---|---|---|
| **Member** (creates within the caller's org) | `e10_org_inv_add_item`, `e10_org_inv_list`, `e10_org_role_clone`, role/permission edits | `coalesce(p_organization_id, e10.current_org())` | `e10.is_org_member(org)` ∧ `has_org_cap(org, <cap>)`; if both `p_org` and a single membership exist they must match |
| **Entity** (operates on an existing row) | `e10_org_inv_edit_item/delete/get/reserve/release/consume/mark_sold/reverse_consumption`, `e10_emit_inventory_movement` | the **entity's** `organization_id` (looked up by `(?, id)`) | caller `is_org_member(entity.org)` ∧ cap; **`p_org`, if supplied, must equal `entity.org`** (else `cross_org_denied`) — the item/session's org is authoritative, not the caller's claim |
| **Invitation** (caller is NOT yet a member) | `e10_redeem_code` / accept-invitation | the **invitation's** `organization_id` (looked up by `token_hash`) | token exists, `status='pending'`, `expires_at > now()`; then create the membership. No membership precondition |
| **Viewer** (no org membership; session-scoped) | `e10_buyer_suggest(session)`, `e10_session_public(session)`, own-purchase reads | the **session's** `organization_id` (the authorization boundary) | authorize as **viewer** — `e10.can_spectate_session` / `e10.owns_slot` / session-participant — **never** as member; no org-membership check |

The wrappers (old names) are all **Member** or **Entity** class and resolve org via `e10.current_org()`
(single-membership). The `e10_org_*` names take the org explicitly and follow the class above.

---

## 5. Viewer authorization — three FULLY SEPARATED tiers (revision 4)
Add an explicit **session visibility field**: `e10_break_sessions.visibility text not null default 'private'`
(`private` | `published`) — only a `published` (live/on-stream) session is spectatable.

1. **Spectator** — any authenticated account may read a **published** session's public surface **only via the
   allowlisted projection** `e10_session_public(sess)` (RPC/view exposing ONLY public columns: `label, tier, price,
   state, team_id, player_id, position, case_hit, sold_at, method, band_*`). **No direct SELECT on `e10_break_slots`
   for spectators.** Predicate `e10.can_spectate_session(sess)` = authenticated ∧ session.visibility='published'.
2. **Owning buyer** — the private slot fields (`buyer_uid, buyer_handle, ship_state, ship_note, incentives`) are
   readable by direct SELECT **only** by the owner (`buyer_uid = auth.uid()`, or a **verified** handle match, §6).
3. **Org member** — full read/write of the session's slots within their org.

**Raw `e10_break_slots` SELECT policy = org member (of the row's org) OR owning buyer. Nothing else** — spectators
never touch the raw table. Broadcast (A9 hook): the public topic authorizes via `can_spectate_session`;
participant-private payloads via `owns_slot`; never mixed (§9).

**Replacing `can_read_session` (rev3).** The existing session-read policies that call `public.e10_can_read_session`
(`e10_break_sessions.bs_sel`, `e10_break_slots.sl_sel`, `e10_break_events.ev_sel`, `e10_session_viewers.sv_sel`) are
rewritten in A6c to the explicit tiers — **member:** `e10.is_org_member(organization_id)`; **spectator:** the
public projection RPC only (gated `e10.can_spectate_session`), not direct table SELECT; **owning buyer:**
`e10.owns_slot(...)` / `buyer_uid=(select auth.uid())` for the participant rows. No single predicate spans tiers.
The old `e10_can_read_session` is dropped at the contract migration.

---

## 6. Handle-to-account verification — one canonical source (revision 5)
Single source of truth = `e10_viewer_handle_claims`; **no duplicate boolean on `e10_viewers`** (any UI flag is a
derived read of this table).
```sql
create table public.e10_viewer_handle_claims (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null, whatnot_handle text not null,
  status text not null default 'pending',            -- pending | verified | rejected
  evidence jsonb, verified_at timestamptz,
  expires_at timestamptz not null,                   -- PENDING claims expire (rev3)
  created_at timestamptz not null default now()
);
-- canonical uniqueness = at most ONE VERIFIED owner per handle (verified-only, rev3). A partial index cannot
-- reference now(), so pending claims are deliberately NOT index-unique: they carry expires_at and are cleaned up,
-- and the verify RPC re-checks "no live verified claim + no unexpired pending by another user" at verification
-- time. This refines revision 5's `status in ('pending','verified')` index (which could wedge on a stale pending).
create unique index e10_vhc_verified_handle on public.e10_viewer_handle_claims (lower(whatnot_handle))
  where status = 'verified';
```
A **verified** claim is the single canonical fact that lets a slot's `buyer_handle` attribute to a global
`buyer_uid` across streamers; the participant predicate trusts verified matches only. Pending claims expire so a
handle is never permanently blocked by an abandoned claim. Verification UX ships post-A6.

---

## 7. Session ⊃ breaks (1–n) — provision + strict-1:1 backfill (Ruling D)
`e10_live_sessions` (org-scoped, §2) is the "go-live" parent; `e10_break_sessions` (the BREAK unit) gains nullable
`live_session_id`. **Backfill = ONE parent per EXISTING break_session (strict 1:1) — do NOT group by
`source_show_ref`** (Ruling D): a retried show start produces two live events on one show (observed in practice),
so grouping by `source_show_ref` would wrongly merge distinct go-live events. Per-break rollups aggregate to the
live-session later; A6 ships the parent table + nullable link only. This keeps `session≈break` from being baked
into the org columns or Broadcast naming.

---

## 8. Storage — private tenant bucket (revision 6) + catalog overlay hook (Ruling A)
- **Two buckets.** Tenant-private uploads go to a **new PRIVATE bucket** (`tenant-uploads`, `public=false`),
  reached via `storage.objects` RLS on an org path (`{organization_id}/…`) + **signed URLs**. **Only the platform
  catalog images stay in the public `cards` bucket.** (Retires the "org-path inside the public bucket" idea from
  rev 1.)
- **No tenant writes to the platform catalog (Ruling A):** `e10_cards/players/sets/teams/checklists` become
  **read-only to org members** (org-read via `e10.is_org_member`-of-any / `is_org`); INSERT/UPDATE/DELETE only by
  platform admin / curation. Org "uploads" land in an org-private staging/overlay table (the hook, NOT built),
  promoted to canonical by **platform curation only** (Phase-6 flywheel).
- **Org upload path is a prerequisite before the first external org** (standing condition) — the private bucket +
  org staging must exist before onboarding org #2.

## 8b. SMTP / onboarding
Member = invite (`e10_organization_invitations`, hashed token + required expiry, admin-gated redeem RPC) — low
volume. Viewer = self-serve signup — **high volume, the custom-SMTP driver.** Custom SMTP provisioned before the
first external org, not in A6.

---

## 9. Realtime / Broadcast naming (A9 hook — documented, not implemented)
- **Member surfaces:** org-filtered Postgres Changes; channel `org:{org_id}`.
- **Session public topic** (spectator Broadcast): `session:{session_id}:public`, authorized `can_spectate_session`,
  public projection fields only.
- **Participant-private:** per-recipient (per-viewer channel / ownership-filtered), authorized `owns_slot`. Never
  mixed onto the public topic. Broadcast emitted from the DB (`realtime.send` in the mutation RPC); channel derives
  from `(organization_id, session_id)` — the composite keys guarantee it.

---

## 10. Cross-org privacy invariants (input 5 + revision 7) — their own tests
1. **Viewer cross-org:** a member of org A cannot see a viewer's org-B activity (rows carry `organization_id`;
   member RLS filters to their org; the viewer's own view is `buyer_uid = auth.uid()` across orgs).
2. **Principal-overlap (revision 7):** a member of org A who *buys as a viewer* in org B — their org-A colleagues
   see NOTHING of that org-B purchase (the org-B slot with their `buyer_uid` is org-B-scoped; org-A member RLS
   never matches it). A6d asserts both.
3. **Legacy workspace CAS (standing condition):** A6c proves the current `e10_workspace` compare-and-swap write
   path (a member committing `'shared'`) touches **only the caller's org's** `(org, 'shared')` row — never another
   org's, never the singular global row.

---

## 11. Tenant-zero backfill (A6b — STAGING only)
1. **Restore** a production snapshot into a **staging copy** (never touch prod).
2. Create `org0` + four system roles + **seeded allow-grants** + `core`/`cards` modules; map current `e10_members`
   → `(org0, user, role_id)`; seed `e10_platform_admins` for Trent's platform identity (separate from membership).
3. **Backfill** `organization_id = org0` on every company-owned row; then `NOT NULL` + swap composite PKs/FKs;
   `e10_workspace` → `(org0, …)`; receipts idempotency → `(org0, key)`; strict-1:1 `live_sessions` (§7).
4. **Verify (A6b acceptance):** every row owned (no null org); counts reconcile (35 items / 41 movements / 6
   receipts / …); recon views drift 0; ledger content byte-intact (checksum before/after); **allow-list PARITY
   proven per user** (§1); the read-only gate passes against the backfilled **staging** DB. Paste every query.

---

## 12. Zero-downtime rollout — WRITE BRIDGE + corrected order (rev3)
**The write bridge (the correction rev2 lacked).** With no maintenance window (ADR 0004), a company-owned table is
written throughout the migration, so `organization_id` must be stamped on EVERY new row from the instant the column
exists — **before** the backfill — or a row inserted mid-backfill stays null and the later `NOT NULL` fails. The
bridge = a `BEFORE INSERT` trigger `e10.stamp_org()` installed in the **same** migration that adds the column:
`NEW.organization_id := coalesce(NEW.organization_id, e10.current_org())` (→ org0 while single-org). The `e10_org_*`
RPCs pass org explicitly; the wrappers + trigger cover the old client. The bridge is dropped at contract.

**Corrected per-table online order (each step non-blocking to writes):**
1. `ADD COLUMN organization_id uuid` (nullable, metadata-only, instant) **+ install `e10.stamp_org()` BEFORE INSERT
   trigger in the same migration** — new rows are owned from t0.
2. `CREATE UNIQUE INDEX CONCURRENTLY (organization_id, id)` (online, no write lock).
3. Composite FKs `NOT VALID` (instant) → `VALIDATE CONSTRAINT` (online; does not block writes).
4. **Backfill** existing NULL rows → `org0` in batches (the bridge already owns anything inserted meanwhile).
5. `CHECK (organization_id IS NOT NULL) NOT VALID` → `VALIDATE` → `SET NOT NULL` (uses the validated check —
   avoids a long full-table lock).
6. **Promote PK** via `ADD PRIMARY KEY USING INDEX` on the pre-built unique index (fast). Old `id` PK + old
   single-column FKs are dropped **at contract**, not here.

**Sequence (staging → prod):**
- **EXPAND (A6a–c, staging):** `e10` schema + predicates; new org tables; per-table steps 1–3; `e10_org_*` RPCs;
  old RPCs → wrappers; policies switched to `e10.*`. Supports client N (single-org) AND N+1 (org-aware).
- **BACKFILL (A6b, staging):** step 4 + allow-list parity seed + strict-1:1 live_sessions; verify (§11).
- **PROMOTE (staging):** steps 5–6.
- **A10 PROD cutover (after A7):** same EXPAND → bridge → BACKFILL → PROMOTE on prod → deploy the org-aware
  new-shell client → **observe** old-client drain (the deployed single-org client keeps working via wrappers +
  bridge throughout — zero downtime).
- **CONTRACT (separate later migration, after drain):** drop the wrappers, the `e10.stamp_org()` bridge, the old
  `id` PKs + single-column FKs, and the superseded `public.e10_is_admin/has_cap/can_read_session/…` helpers; remove
  the `e10.current_org()` single-membership *requirement*; retire singular-`'shared'`. Only here is anything
  removed/renamed/contracted.

The **standing release rule** (no rename/removal/policy-contraction/incompatible-RPC-change in the same release as
its replacement) lands in `docs/OPERATIONS.md`.

---

## 13. Future company-owned operations — recorded invariants (NOT built in A6)
Buyback and repack (pack-opener) are later cards-vertical operations; their invariants are fixed now so the spine
never has to be reopened for them (per Trent — record, don't build):
- **Org-scoped like all company-owned data:** `organization_id NOT NULL`, composite `(organization_id, id)` PK,
  org derived by the Entity/Member class (§4.1), never cross-org.
- **Ledger-integrated, no out-of-band inventory:** a **repack** consumes source inventory and produces new sellable
  items ONLY through the append-only movement ledger (consumption on the source, acquisition on the outputs), and
  **cost basis is conserved** — output cost derives from the consumed source via ledger movements, never hand-set.
  A **buyback** acquires product as new items + an acquisition movement (cost = buyback price), same discipline.
- **Reconcilable + idempotent:** transactional RPCs writing receipts scoped `(organization_id, idempotency_key)`;
  their effects reconcile in the recon views (drift 0) exactly like reserve/consume.
- **Repack = a TRANSFORMATION, not a transfer:** linked `transformation_consume` (sources leave) +
  `transformation_output` (the pack appears) movements; output cost basis conserved from the consumed components.
  **"Provably fair" needs MORE than the ledger** — a frozen versioned batch manifest (component ids, quantities,
  assigned-value + cost-basis snapshots, bucket definitions, exact integer hit counts) + an immutable allocation
  method / algorithm version / pack numbering (possibly commit-reveal). Recorded as the standard; not built.
- **Store credit is a SEPARATE ledger, not inventory:** its own append-only ledger (issue/redeem/adjust) keyed
  `(organization, viewer, currency)`, **never cross-org spendable**; outstanding credit is a customer **LIABILITY
  tracked separately from inventory cost basis** (different accounting number). A bought-back card re-enters
  inventory as an intake movement (cost = credit paid). Depends on verified handles (§6). Tax/legal (closed-loop /
  escheatment) review before any external org carries balances.
- **Deferred:** no `e10_repacks`/`e10_buybacks`/store-credit schema in A6; this fixes the rules those tables must
  obey. See `docs/DOMAIN_MAP.md` (reconciled 2026-07-17) for the full product detail (concepts ①–⑥, repack RP1).

---

## Rulings adopted (were the open decisions)
- **A — checklists:** platform-level, **read-only to tenants; no tenant writes to the platform catalog**; org
  uploads via the private-bucket + staging/overlay hook, promoted by platform curation only.
- **B — `e10_obs_*`:** org-scoped company-owned, stored as **derived records carrying provenance** (source,
  capture time/method) **and a consent/lawful-basis marker** — observing other streamers' public activity is a
  derived-data-about-others concern; provenance + consent columns are required, the legal review is flagged.
- **C — PK:** composite `(organization_id, id)`, applied consistently incl. composite role FKs (§2).
- **D — session⊃breaks:** add `e10_live_sessions`; backfill **strict 1:1** (one parent per existing break_session,
  no `source_show_ref` grouping).

## Out of scope (this doc / all of A6)
Any production change (A10). A7 hostile campaign. A8 bounded reads / A9 Broadcast impl beyond the named hooks.
Catalog overlay + promotion flywheel (Phase 6). All UI (Track B). Billing.

---
**⏸ STOP. This design requires "A6 design approved" (both reviewers) before A6a runs. Production untouched.**
