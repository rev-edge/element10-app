# 0005 — The tenant spine (Foundation Gate, Track A step 6 — design)

**Status:** PROPOSED — **revision 3.2.1** (2026-07-17). rev2 = the reviewers' 8 revisions + 4 rulings; **rev3 adds:** a
zero-downtime write bridge + corrected backfill/cutover order (§12); RPC scope derivation classified by
member/entity/invitation/viewer context (§4); an explicit grants/RLS/index matrix per org-core table (§1.2); exact
module-capability + entitlement semantics with no undefined wildcard (§1.1); verified-only + expiring handle-claim
uniqueness (§6); removal of the ambiguous `can_read_session` (§5); and the buyback/repack future invariants (§13).
**rev3.1 closure edit:** bootstrap org0 memberships + parity grants BEFORE the current_org-based bridge/wrappers/
policies (blocker 1); composite key ships as a UNIQUE candidate until contract — PostgreSQL forbids a second PK
(blocker 2); globally-unique invitation token + session id/share_code so token/viewer/session org-derivation is
unambiguous (blocker 3); the six concrete `mod` keys incl. `mod.reporting`, no wildcard (blocker 4); plus role-FK
indexes, `auth.users` FKs, CHECK constraints, handle normalization + verify-concurrency rule, and the exact A6
table list (§0.2).
**rev3.2 (2026-07-17) residuals:** §12 step 6 no longer promotes the PK — it formalizes the composite as a UNIQUE
constraint (`ADD CONSTRAINT … UNIQUE USING INDEX`); `ADD PRIMARY KEY USING INDEX` moved to CONTRACT, after the old
`id` PK is dropped (blocker-2 residual); §4.1 wrapper closing corrected — `e10_redeem_code` = Invitation-class,
`e10_buyer_suggest` = Viewer-class, neither may call `current_org()` (blocker-3 residual); §6 states one account may
hold multiple verified handles, one owner per normalized handle, no `user_id` uniqueness; §1.2 handle-claims write
path resolved to an RPC (`e10_claim_handle`) consistent with the preamble; §12 step 2 notes `CREATE INDEX
CONCURRENTLY` is non-transactional + the INVALID-index recovery rule; `docs/DOMAIN_MAP.md` company-owned section
points to §0.2 and drops the non-table items from the A6 org_id claim.
**rev3.2.1 (2026-07-17) micro-edit:** §12 CONTRACT now uses a second standalone composite unique index for legal
PK promotion, recreates child composite FKs against the new PK before removing the candidate UNIQUE constraint,
and permanently preserves the §4.1 global session `UNIQUE(id)` / `UNIQUE(share_code)` lookup keys.
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

### 0.2 Exact A6 table list (the migration scope — currently-existing tables only)
**Gets `organization_id` in A6 (19 existing + 1 new):** `e10_inventory_items`, `e10_inventory_movements`,
`e10_inventory_reservations`, `e10_mutation_receipts`, `e10_workspace`, `e10_break_sessions`, `e10_break_slots`,
`e10_break_events`, `e10_session_viewers`, and the ten obs tables — `e10_obs_breaks`, `e10_obs_captures`,
`e10_obs_channels`, `e10_obs_config`, `e10_obs_products`, `e10_obs_product_prices`, `e10_obs_slots`,
`e10_obs_streams`, `e10_obs_upcoming_shows`, `e10_obs_viewer_snapshots`; plus the **new** `e10_live_sessions`
(org-scoped from birth, §7).
**Does NOT get `organization_id`:** `e10_cards`, `e10_players`, `e10_sets`, `e10_teams`, `e10_checklists` (platform
catalog); `e10_members` → memberships, `e10_viewers` (global), `e10_role_permissions` → org role permissions;
`e10_bigimport_backup`, `e10_seed_backup` (ops/backup). *(Not tables today, so out of A6's migration: orders,
fulfillment, customers [Phase 8/9]; repacks, buybacks, store credit [§13]; break-models/cost-model/notes, which
live in `e10_workspace` JSONB.)*

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
  slug text unique not null check (slug ~ '^[a-z0-9-]{2,40}$'),   -- normalized handle
  name text not null,
  status text not null default 'active' check (status in ('active','suspended')),
  settings jsonb not null default '{}'::jsonb,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

-- org-DEFINED roles: composite PK so all references are (organization_id, role_id) (rev1)
create table public.e10_organization_roles (
  organization_id uuid not null references public.e10_organizations(id) on delete cascade,
  id uuid not null default gen_random_uuid(),
  key text not null,                 -- system keys: admin|manager|streamer|ops (+ custom)
  name text not null, is_system boolean not null default false,
  created_at timestamptz not null default now(),
  primary key (organization_id, id),
  unique (organization_id, key)
);

-- permission SETS — ALLOW-LIST: a row PRESENT-and-allowed grants; ABSENT = DENY (rev2, inverts the old deny-list)
create table public.e10_organization_role_permissions (
  organization_id uuid not null,
  role_id uuid not null,
  capability text not null,          -- one of the enumerated act.* / mod keys in §1.1 (concrete strings only)
  allowed boolean not null default true,
  updated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now(),
  primary key (organization_id, role_id, capability),
  foreign key (organization_id, role_id) references public.e10_organization_roles(organization_id, id) on delete cascade
);

create table public.e10_organization_memberships (
  organization_id uuid not null references public.e10_organizations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role_id uuid not null,
  display_name text,
  status text not null default 'active' check (status in ('active','invited','suspended')),
  created_at timestamptz not null default now(),
  primary key (organization_id, user_id),
  foreign key (organization_id, role_id) references public.e10_organization_roles(organization_id, id)
);
create index e10_memberships_user_idx on public.e10_organization_memberships (user_id);            -- current_org() reverse lookup
create index e10_memberships_role_idx on public.e10_organization_memberships (organization_id, role_id); -- role FK

create table public.e10_organization_invitations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.e10_organizations(id) on delete cascade,
  email text not null,
  role_id uuid not null,
  token_hash text not null unique,   -- HASH of the token, GLOBALLY unique so redeem-by-token is unambiguous (blocker 3)
  invited_by uuid references auth.users(id) on delete set null,
  status text not null default 'pending' check (status in ('pending','accepted','revoked','expired')),
  expires_at timestamptz not null check (expires_at > created_at),   -- expiry REQUIRED (rev5)
  created_at timestamptz not null default now(),
  foreign key (organization_id, role_id) references public.e10_organization_roles(organization_id, id)
);
create index e10_invitations_role_idx on public.e10_organization_invitations (organization_id, role_id); -- role FK
create index e10_invitations_org_email_idx on public.e10_organization_invitations (organization_id, lower(email));

create table public.e10_organization_modules (   -- entitlements
  organization_id uuid not null references public.e10_organizations(id) on delete cascade,
  module_key text not null check (module_key in ('core','cards')),   -- enumerated bundle set (§1.1)
  enabled boolean not null default true,
  settings jsonb not null default '{}'::jsonb,
  primary key (organization_id, module_key)
);

-- PLATFORM ADMIN — above orgs, never org membership; RLS DENY-ALL (service-role/definer only)
create table public.e10_platform_admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);
-- alter table … enable row level security;  -- and NO policy → deny-all to anon/authenticated
```

**Allow-list model + parity seed (revision 2 — the subtle correctness point):**
- `e10.has_org_cap(org, cap)` := platform-admin **OR** (active member of `org` **AND EXISTS** a
  `role_permissions` row for their role+cap with `allowed=true`). **Empty ⇒ denied** (opposite of the current
  deny-list `e10_has_cap`).
- A6a seeds explicit grants for the four **system** roles (sensible defaults): e.g. Admin = all six `act.*` + all
  six module keys; Manager = inventory/lists/reporting/live + the matching modules; Streamer = live_run + lists;
  Ops = fulfillment/reporting (`mod.toolkit` + `mod.reporting`). All grants are concrete capability strings.
- **Tenant-zero parity seed (A6b acceptance):** because today's model is deny-list (every member has EVERY cap),
  the tenant-zero backfill MUST grant, to the roles its current members map to, **every currently-exercised
  capability** — the six `act.*` (§1.1) + the six module keys (`mod.home, mod.inventory, mod.reporting,
  mod.schedule, mod.settings, mod.toolkit`) that the org currently uses — so the deny-list→allow-list flip is
  **behaviorally invisible at cutover.** A6b **proves parity per user:** for every current member, every `hasCap(x)`
  that returns true today returns true after the flip. (A6a pins the full concrete cap set from the `has_cap`/
  `hasCap` call sites; this list is the floor — no wildcard.)
- **Clone RPC** `e10_org_role_clone(p_org, p_src_role, p_dst_role)` copies the source role's permission-set rows
  (the allow grants) as a starting point; admin-cap gated.

### 1.1 Module-capability + entitlement semantics — concrete enumerated keys, NO wildcard (rev3.1)
Two orthogonal, both-required gates. Every capability is one of a fixed enumerated set of concrete strings — there
is **no pattern/wildcard capability** anywhere (no `mod.` prefix-match, none stored, none honored).
- **Entitlement** (`e10_organization_modules.module_key`) = the coarse bundle an **org HAS** (billing/provisioning).
  Enumerated: **`core`, `cards`** (a future vertical adds a concrete sibling key). Written by platform admin.
- **Module capabilities** = the **SIX** concrete keys the current client actually checks (pinned from the code):
  **`mod.home`, `mod.inventory`, `mod.reporting`, `mod.schedule`, `mod.settings`, `mod.toolkit`.** These are the
  exact strings stored in `role_permissions.capability`. A new module adds one new concrete key — never a pattern.
- **Action capabilities** = the **SIX**: `act.inventory_edit`, `act.lists_edit`, `act.live_run`,
  `act.permissions_config`, `act.reporting_export`, `act.team_manage`.
- **Effective access to a module** = (org entitled to the module's owning bundle, `enabled=true`) **AND**
  (`e10.has_org_cap(org, '<that concrete key>')` finds an `allowed=true` row). **Bundle ownership (confirmed ruling
  2026-07-17, encoded in A6a.1 `e10.module_bundle(text)` IMMUTABLE): ALL SIX legacy keys → `core`** — the Live
  Toolkit contains Ship/fulfillment which is `core` in DOMAIN_MAP, and a `cards` mapping would strip fulfillment
  from future non-cards orgs; a future vertical supplies its own concrete keys mapping to `cards`. A missing
  permission row is a **deny** (allow-list); a disabled entitlement denies regardless of the role grant.
  `e10.has_org_cap` only ever matches an exact capability string from the twelve above. A6a.2 encodes the combined
  rule as `e10.has_module_access(org, key)`: the mapped entitlement must exist and be enabled, and
  `e10.has_org_cap(org, 'mod.' || key)` must grant the exact module capability.

### 1.2 Grants / RLS / index matrix — org-core tables (rev3)
All writes flow through `SECURITY DEFINER` RPCs in `public` that call `e10.*` predicates; `authenticated` gets only
the SELECT reach below via RLS (no direct table INSERT/UPDATE/DELETE grants). `anon` gets nothing new.

| Table | SELECT (RLS `using`) | Writes | Key indexes |
|---|---|---|---|
| `e10_organizations` | `e10.is_org_member(id)` OR platform-admin | platform-admin (self-serve create later) | PK`(id)`, `unique(slug)` |
| `e10_organization_roles` | `e10.is_org_member(organization_id)` | `e10.is_org_admin(org)` ∧ `has_org_cap(org,'act.permissions_config')`; system roles undeletable | PK`(org,id)`, `unique(org,key)` |
| `e10_organization_role_permissions` | `e10.is_org_member(org)` | admin ∧ `act.permissions_config` | PK`(org,role_id,capability)`, `(org,capability)` |
| `e10_organization_memberships` | `e10.is_org_member(org)` OR `user_id=(select auth.uid())` | admin ∧ `act.team_manage` | PK`(org,user_id)`, **`(user_id)`** (`current_org()` reverse lookup — load-bearing), `(org,role_id)` (role FK), `user_id→auth.users` |
| `e10_organization_invitations` | `e10.is_org_admin(org)` (invitee redeems by token, never reads the table) | admin ∧ `act.team_manage` | PK`(id)`, **`unique(token_hash)` global** (blocker 3), `(org,role_id)` (role FK), `(org,lower(email))` |
| `e10_organization_modules` | `e10.is_org_member(org)` | **platform-admin** (entitlement = billing) | PK`(org,module_key)` |
| `e10_platform_admins` | **DENY-ALL** (RLS on, no policy → service-role/definer only) | service-role/definer | PK`(user_id)` |
| `e10_viewer_handle_claims` | `user_id=(select auth.uid())` OR platform-admin | **via RPC** (consistent with the preamble): `e10_claim_handle` (self — sets `user_id = auth.uid()`); verify/reject via a platform-admin RPC. No direct table grant. | PK`(id)`, `(user_id)`, verified-unique `(handle_norm)` (§6) |
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
- **Staged as a UNIQUE candidate, not a second PK (blocker 2):** PostgreSQL allows only ONE primary key per table,
  and the existing `id` PK must stay live through EXPAND (the old client still keys on it). So on the retrofitted
  existing tables the composite ships as a **`UNIQUE (organization_id, id)` constraint/candidate key**; the child
  composite FKs reference that UNIQUE (a FK may target any unique constraint, not only a PK). The composite becomes
  the actual PRIMARY KEY **only at the CONTRACT migration**, once the old `id` PK + its single-column FKs are
  dropped. (New org-core tables in §1 are created fresh with their composite PK directly — no staging needed.) The
  "New PK" column below is the **end-state** key; read it as "UNIQUE until contract, PK after."

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

**Wrappers keep their old name's class — they are NOT all Member/Entity (blocker 3):** most `e10_inv_*` wrappers are
Member/Entity and resolve org via `e10.current_org()` (single-membership), but **`e10_redeem_code` wraps as
Invitation-class** (org derived from the globally-unique `token_hash`; **no `current_org()`, no membership
precondition**) and **`e10_buyer_suggest` wraps as Viewer-class** (org derived from the session's global `id`;
authorize as viewer). **No Invitation- or Viewer-class wrapper may call `e10.current_org()`** — the caller has no
membership to derive from; org comes from the token or the session. The `e10_org_*` names take org explicitly and
follow the same class.

**Globally-unambiguous identities the Invitation + Viewer classes depend on (blocker 3):** these classes resolve
`org` from a token or a session that the caller references *without already knowing the org*, so those identifiers
must be **globally unique**, not per-org:
- **Invitation:** `e10_organization_invitations.token_hash` is `UNIQUE` **globally** (not `(org, token_hash)`) — the
  invitee redeems by token alone.
- **Session/viewer:** `e10_break_sessions.id` (uuid) keeps a **global `UNIQUE (id)`** and `share_code` a global
  `UNIQUE (share_code)` **in addition to** the composite `(organization_id, id)` — so the spectator/participant path
  can look up a session by its global id / share code and derive `org` from it. `e10_live_sessions.id` likewise
  keeps a global `UNIQUE (id)`. (Uuids are already collision-free; the explicit global unique is what makes the
  org-derivation lookup a single-column key that survives the composite-PK swap at contract.)

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
  user_id uuid not null references auth.users(id) on delete cascade,
  whatnot_handle text not null,                      -- as entered
  -- CANONICAL normalization (rev3.1): lowercase + trim + strip a leading '@'. Stored/generated so EVERY compare +
  -- the uniqueness use the same form. buyer_handle attribution (§5) matches on this normalized value.
  handle_norm text generated always as (lower(btrim(regexp_replace(whatnot_handle, '^@', '')))) stored,
  status text not null default 'pending' check (status in ('pending','verified','rejected')),
  evidence jsonb, verified_at timestamptz,
  expires_at timestamptz not null check (expires_at > created_at),   -- PENDING claims expire (rev3)
  created_at timestamptz not null default now()
);
-- canonical uniqueness = at most ONE VERIFIED owner per NORMALIZED handle (verified-only, rev3). A partial index
-- cannot reference now(), so pending claims are deliberately NOT index-unique: they carry expires_at + are cleaned
-- up. Refines rev5's `status in ('pending','verified')` index (which could wedge on a stale pending).
create unique index e10_vhc_verified_handle on public.e10_viewer_handle_claims (handle_norm) where status = 'verified';
create index e10_vhc_user_idx on public.e10_viewer_handle_claims (user_id);
```
**Concurrency rule (rev3.1; hardened A6a.3):** verification is serialized per handle — the verify RPC takes a
transaction-scoped advisory lock `pg_advisory_xact_lock(hashtext(handle_norm))`, then (A6a.3) **rereads the claim
under the lock and requires it still exists, still carries the locked `handle_norm` (else `claim_handle_changed`),
is still `status='pending'`, and is not expired**, re-checks "no existing verified claim on this `handle_norm`", and
flips exactly one claim to `verified` via an `UPDATE … WHERE status='pending' AND expires_at > now()` (0 rows → clean
error). Two racers cannot both win: the advisory lock serializes two verifiers and the verified-only unique index is
the backstop, so the loser gets a clean `handle_already_verified`. A reject takes **no** lock, so it can commit while
a verify is blocked — the post-lock reread and the conditional update both prevent a rejected/expired claim from
being verified, never a partial state. Proven by a two-connection concurrent test (`tests/a6a3_verify_concurrent_test.js`)
run against both local and staging. (Migration `20260717180000` introduced the reread; `20260718132644` added the
handle-unchanged recheck and `expires_at > now()` in the update predicate.)

**Cardinality (Trent's ruling, 2026-07-17):** one `auth.users` account MAY hold **multiple** verified handles (a
person legitimately buys under more than one Whatnot handle); each **normalized** handle has **at most one** verified
owner (the `e10_vhc_verified_handle` index enforces exactly that). There is deliberately **NO uniqueness on
`user_id`** — the constraint is one-owner-per-handle, not one-handle-per-user.

A **verified** claim is the single canonical fact that lets a slot's `buyer_handle` attribute to a global
`buyer_uid` across streamers; the participant predicate trusts verified matches only (comparing on `handle_norm`).
Pending claims expire so a handle is never permanently blocked by an abandoned claim. Verification UX ships post-A6.

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
2. **(Done in A6a bootstrap — blocker 1, listed here for the full picture)** `org0` + four system roles + **parity
   allow-grants** + `core`/`cards` modules exist; current `e10_members` are mapped to `(org0, user, role_id)`;
   `e10_platform_admins` seeded for Trent's platform identity (separate from membership). This precedes any
   `current_org`-based bridge/wrapper/policy.
3. **Backfill** `organization_id = org0` on every company-owned row; `e10_workspace` → `(org0, …)`; receipts
   idempotency → `(org0, key)`; strict-1:1 `live_sessions` (§7). Then `NOT NULL`; the composite ships as **`UNIQUE
   (organization_id, id)`** (the `id` PK stays — blocker 2; composite becomes PK only at contract).
4. **Verify (A6b acceptance):** every row owned (no null org); counts reconcile (35 items / 41 movements / 6
   receipts / …); recon views drift 0; ledger content byte-intact (checksum before/after); **allow-list PARITY
   proven per user** (§1 — every `hasCap` true today is true after); the read-only gate passes against the
   backfilled **staging** DB. Paste every query.

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
2. `CREATE UNIQUE INDEX CONCURRENTLY (organization_id, id)` (online, no write lock). **`CONCURRENTLY` cannot run
   inside a transaction block** — it ships as its **own non-transactional migration step** (one such index per
   step, not wrapped in `begin/commit`). **Recovery rule:** a failed `CONCURRENTLY` leaves an **INVALID** index
   behind; the step is idempotent-guarded — detect a leftover (`pg_index.indisvalid = false`), `DROP INDEX` it, and
   re-run the step. (Same applies to any other `CONCURRENTLY` index in the migration set.)
3. Composite FKs `NOT VALID` (instant) → `VALIDATE CONSTRAINT` (online; does not block writes).
4. **Backfill** existing NULL rows → `org0` in batches (the bridge already owns anything inserted meanwhile).
5. `CHECK (organization_id IS NOT NULL) NOT VALID` → `VALIDATE` → `SET NOT NULL` (uses the validated check —
   avoids a long full-table lock).
6. **Formalize the candidate key — NOT a PK change (blocker 2).** `ALTER TABLE … ADD CONSTRAINT
   <t>_org_id_key UNIQUE USING INDEX <the step-2 index>`, so `(organization_id, id)` is a **named UNIQUE
   constraint** that the child composite FKs reference. **The old `id` PRIMARY KEY stays** — PostgreSQL forbids a
   second PK, and the old client still keys on `id`. **No `ADD PRIMARY KEY` here.** PK promotion happens only at
   CONTRACT (below), after the old `id` PK is dropped.

**Sequence (staging → prod):**
- **BOOTSTRAP FIRST (A6a, blocker 1):** create the `e10` schema, the predicates, and the org-core tables, then
  **seed org0 + its system roles + map current `e10_members` → org0 memberships + the parity allow-grants +
  modules — BEFORE installing anything that calls `e10.current_org()`/`is_org_member`/`has_org_cap`.** Rationale:
  the write bridge, the wrappers, and the switched policies all resolve the caller's org through membership; if any
  were installed against an empty membership table, `current_org()` returns null and every write would stamp-null
  and every read would deny. With org0's memberships + grants in place first, every current user resolves to org0
  the instant the bridge/wrappers/policies go live (each has exactly one membership → the single-membership fast
  path is deterministic).
- **EXPAND (A6a–c, staging — AFTER bootstrap):** per-table steps 1–3 incl. the `e10.stamp_org()` bridge (now safe —
  memberships exist); add the `e10_org_*` RPCs; convert old RPCs → wrappers; switch policies to `e10.*`. Supports
  client N (single-org) AND N+1 (org-aware).
- **BACKFILL (A6b, staging):** step 4 (backfill existing company rows → org0) + strict-1:1 live_sessions; verify
  incl. allow-list parity per user (§11).
- **PROMOTE (staging):** steps 5–6 — enforce `NOT NULL` and formalize the `(organization_id, id)` **UNIQUE
  constraint**. Still **no PK change**; the old `id` PK remains and both clients keep working.
- **A10 PROD cutover (after A7):** same EXPAND → bridge → BACKFILL → PROMOTE on prod → deploy the org-aware
  new-shell client → **observe** old-client drain (the deployed single-org client keeps working via wrappers +
  bridge throughout — zero downtime).
- **CONTRACT (separate later migration, post-drain):** drop the compatibility wrappers, the `e10.stamp_org()`
  bridge, and the superseded `public.e10_is_admin/has_cap/can_read_session/…` helpers; remove the
  `e10.current_org()` single-membership *requirement*; retire singular-`'shared'`. Then promote each retrofitted
  table's composite candidate key to its literal primary key in this exact order: **(1)** `CREATE UNIQUE INDEX
  CONCURRENTLY` a SECOND standalone index on `(organization_id, id)`, not attached to any constraint; the step-2
  rules apply, so each build is its own non-transactional migration step and a failed build's INVALID index is
  detected, dropped, and retried; **(2)** drop the old `id` PK's inbound single-column FKs, then drop the old `id`
  PRIMARY KEY, while permanently preserving the §4.1 global `UNIQUE(id)` and `UNIQUE(share_code)` indexes on
  `e10_break_sessions` / `e10_live_sessions`; **(3)** `ALTER TABLE … ADD PRIMARY KEY USING INDEX` the step-1
  standalone index, which is legal because that index is unowned and the old PK is gone; **(4)** recreate each
  child composite FK against the new PK via `ADD CONSTRAINT … NOT VALID` → `VALIDATE CONSTRAINT`, and only after
  each replacement validates drop its corresponding old composite FK; **(5)** drop the superseded step-6
  candidate UNIQUE constraint after nothing references it. This runs only at CONTRACT, post-drain, and the
  contract migration receives its own runbook and review before execution. Only here is anything removed,
  renamed, or contracted.

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
