# A7 — Hostile Two-Organization Scenario Matrix

Status: durable authorization-verification matrix. **Authored once; consumed twice** — by **A7** (engine RLS/delegate proofs, `tests/a7_hostile_matrix_test.sql`) and later by **PF-C20** (product-prototype verification). A scenario here is an *attempt to breach the tenant boundary*; the matrix records who attacks, what they target, the exact refusal, and the layer that must produce it. It is not a happy-path demo.

Baseline: accepted code head `1a87bad` (A6c.0–A6c.4 GRANTED; the 97-policy census fully consumed; zero legacy org-blind predicates anywhere). Two organizations throughout: **orgA = org0** (`e1000000-0000-4000-8000-0000000000a6`, the tenant-zero data set) and **orgB** (a second, adversarial org). Production is out of scope (read-only until A10; it still carries the pre-A6c policies — that gap is A8–A10's motivation, not A7's).

## 1. Identity classes

Each is exercised with a **real authenticated JWT** (`set role authenticated` + `request.jwt.claims.sub`), never a definer/superuser shortcut. `anonymous` uses `role anon` / no `sub`.

| # | Class | How represented | Key predicate signal |
|---|---|---|---|
| I1 | Org member (has cap) | active membership in the org, role holding `act.inventory_edit` | `is_org_member(org)=t`, `has_org_cap(org,cap)=t`, `is_org_admin=f` |
| I2 | Org member (no cap) | active membership, role lacking the cap (ops) | `is_org_member=t`, `has_org_cap=f` |
| I3 | Org admin | active membership, role key `admin` | `is_org_admin(org)=t` |
| I4 | Platform admin | row in `e10_platform_admins` | `is_platform_admin()=t` |
| I5 | Multi-membership user | active membership in **both** orgs | `current_org()=NULL` (fail-closed) |
| I6 | Session owner | `streamer_uid` of the target session | `owns_session(sess)=t` |
| I7 | Session participant | row in `e10_session_viewers` for the session, **non-member** | `can_read_session` via participant; `is_org_member=f` |
| I8 | Viewer / redeem-code | authenticated, redeems a `share_code` | derives org from session; never `current_org()` |
| I9 | buyer_uid holder | `buyer_uid` on a slot, non-member | slot-ownership predicate only |
| I10 | verified-handle holder | verified `e10_viewer_handle_claims` matching a slot handle, non-member | handle predicate only |
| I11 | Anonymous | `role anon`, no `sub` | no membership, no delegate grant |

## 2. Target families (every census family + delegates)

| Family | Tables / objects | Governing layer |
|---|---|---|
| F1 Inventory | `e10_inventory_items` / `e10_inventory_reservations` (SELECT RLS); writes are RPC-only | `is_org_member(organization_id)` SELECT; delegates for writes |
| F2 Ledger | `e10_inventory_movements` (SELECT `is_org_member`), `e10_mutation_receipts` (deny-all) | ledger outlives items (no movement→item FK); receipts server-only |
| F3 Sessions | `e10_break_sessions`/`_slots`/`_events`/`e10_session_viewers` | member OR owner OR participant OR buyer_uid OR handle; published-vs-private spectate |
| F4 OBS | 17 `e10_obs_*` tables (40 policies) | `is_org_member(organization_id)` |
| F5 Workspace | `e10_workspace` (shared/universal/owner) | member+cap / admin / owner; WITH CHECK pins `current_org()`; global PK |
| F6 Catalog (read-only) | `e10_cards/checklists/players/sets/teams` | SELECT = `is_platform_admin() OR current_org() IS NOT NULL`; mutations deny-by-default |
| F7 Identity | `e10_members`, `e10_role_permissions`, `e10_viewers` | own-row read OR `is_org_admin(current_org())`; writes admin-only |
| F8 Delegates | the 14 `e10_org_*` SECURITY DEFINER RPCs | internal guards: member/cap/entity-org/owns_session; `cross_org_denied` 42501 |

## 3. The matrix — hostile crossings, expected refusal, and layer

Notation: **ALLOW** = the legitimate positive; **DENY(sqlstate)** = a raised refusal with that SQLSTATE; **DENY(0 rows)** = RLS USING/visibility filters the row out (unshadowable — a read or USING-excluded write raises nothing); **DENY(ok:false «msg»)** = a delegate business refusal. "Proof" cites the gate that establishes the cell (A7 = `a7_hostile_matrix_test.sql`; prior gates reused where already exhaustive).

### F1 Inventory (orgA target)
| Attacker | Outcome | Layer | Proof |
|---|---|---|---|
| I1 orgB member reads orgA items | DENY(0 rows) | RLS `imov`/`item_sel` `is_org_member(orgA)=f` | A7 §F1, A6c.1 |
| I1 orgA member reads orgA items | ALLOW | RLS member | A7 §F1 |
| I5 multi reads orgA items | DENY(0 rows) | `is_org_member(orgA)` still true but reads via RLS; write path fails on `current_org()` null | A7 §F1 note |
| I11 anon reads orgA items | DENY(42501) | anon holds NO table grant on `e10_inventory_items` → "permission denied for table" | A7 anon block |

### F2 Ledger (orgA; outlives items)
| Attacker | Outcome | Layer | Proof |
|---|---|---|---|
| I1 orgB member reads orgA correction movement | DENY(0 rows) | `imov_sel is_org_member(orgA)=f` | A7 §F2 |
| I1 orgA member reads the correction movement of a **hard-deleted** item | ALLOW | ledger org-scoped, no movement→item FK | A7 §F2, A6c.1 axis-8 |
| any authenticated reads `e10_mutation_receipts` | DENY(0 rows) | receipts deny-all (server-only) | A7 §F2 |

### F3 Sessions / slots / events / viewers (orgA)
| Attacker | Outcome | Layer | Proof |
|---|---|---|---|
| I1 orgB member reads orgA private session | DENY(0 rows) | `bs_sel`: not member/owner/participant of orgA | A7 §F3 |
| I7 participant reads the joined published session | ALLOW | participant predicate | A7 §F3, A6c.1 axis-3 |
| non-participant (orgB member) `can_spectate_session(published)` | ALLOW(true) but raw table DENY(0 rows) | published projection only; raw rows never served | A7 §F3, A6c.1 axis-7 |
| non-participant reads private session | DENY(0 rows) | `can_spectate_session(private)=false`; not participant | A7 §F3 |
| I9 buyer_uid reads own slot; a different non-member does not | ALLOW / DENY(0 rows) | slot buyer_uid predicate | A7 §F3, A6c.1 axis-5 |
| I10 handle holder reads handle slot; a different non-member does not | ALLOW / DENY(0 rows) | verified-handle predicate | A7 §F3, A6c.1 axis-6 |
| cross-org slot INSERT (orgB slot into orgA-member session) | DENY(42501) | `sl_ins` WITH CHECK (FK made valid first) | A6c.1.1 |

### F4 OBS (orgA)
| Attacker | Outcome | Layer | Proof |
|---|---|---|---|
| I1 orgB member reads orgA obs row | DENY(0 rows) | `is_org_member(orgA)=f` | A7 §F4 |
| I1 orgA member reads own obs row | ALLOW | member | A7 §F4 |

### F5 Workspace (orgA)
| Attacker | Outcome | Layer | Proof |
|---|---|---|---|
| I1 orgB member reads/writes orgA `shared` | DENY(0 rows) | `ws_sel`/`ws_upd` not member of orgA | A7 §F5, A6c.3 |
| I2 no-cap orgA member writes `shared` | DENY(0 rows) | `ws_upd` shared branch needs cap | A6c.4 disc. |
| I5 multi writes orgA `shared` | DENY(42501) | `ws_upd` WITH CHECK `current_org()` null + `ws_sel` new-row visibility | A6c.4 disc. |
| I1 orgA member re-stamps `shared` to orgB | DENY(42501) | WITH CHECK current_org pin (+ ws_sel) | A6c.3 |
| orgB `shared` INSERT | DENY(23505) | global PRIMARY KEY(id) | A6c.3 |

### F6 Catalog (read-only, global)
| Attacker | Outcome | Layer | Proof |
|---|---|---|---|
| no-org **authenticated** caller reads catalog | DENY(0 rows) | `card_sel`: executes the policy fn, `current_org() IS NULL` and not platform admin → filtered | A7 §F6, A6c.4 |
| I11 **anonymous** reads catalog | DENY(42501) | anon HOLDS 7 table grants on `e10_cards`, but has NO EXECUTE on `e10.is_platform_admin()` called by `card_sel` → "permission denied for function is_platform_admin" (policy-function-execute layer, **not** a table grant) | A7 anon block |
| I1 any-org member reads catalog | ALLOW | belongs to an org | A7 §F6 |
| I3 org admin INSERTs a card | DENY(42501) | deny-by-default (mutation policies dropped) | A7 §F6, A6c.4 |
| I4 platform admin reads catalog | ALLOW | `is_platform_admin()` | A7 §F6 |

### F7 Identity (members / role_permissions / viewers)
| Attacker | Outcome | Layer | Proof |
|---|---|---|---|
| I1 non-admin reads another member row | DENY(0 rows) | `m_sel` own-row-or-admin | A7 §F7, A6c.4 |
| I1 non-admin INSERTs a member / role_permission | DENY(42501) | `m_ins`/`rp_ins` WITH CHECK `is_org_admin(current_org())` | A7 §F7, A6c.4 |
| I11 no-org caller reads role_permissions | DENY(0 rows) | `rp_sel` current_org null | A7 §F7, A6c.4 |

### F8 Delegates (14 `e10_org_*`)
| Attacker | Outcome | Layer | Proof |
|---|---|---|---|
| I1 orgB member calls Entity delegate on an orgA item (`e10_org_inv_edit_item(orgB,…)` where item∈orgA) | DENY(42501 `cross_org_denied`) | delegate item-org guard | A7 §F8, A6c.2 |
| I2 no-cap member calls a Member delegate | DENY(42501 missing cap) | `has_org_cap` guard | A6c.2 |
| I5 multi calls a legacy wrapper (`current_org()` null) | DENY(42501) | `is_org_member(null)=f` | A6c.2 |
| I1 non-owner calls `e10_org_buyer_suggest(sess)` | DENY(42501) | `owns_session` guard | A6c.2 |
| legacy-global-admin (ordinary orgB member) exercises admin behavior in orgB | ordinary-member behavior (ok:false) | `is_org_admin(p_org)` | A6c.2.1 |
| I8 `e10_org_redeem_code(bad)` | returns NULL (no viewer) | derive org from share_code | A6c.2 |
| I11 anon calls any `e10_org_*` | DENY(no EXECUTE) | born-locked ACL: authenticated+service_role only | A7 §F8, A6c.0/probe_defpriv |

## 4. Invariants re-proven under hostile identities (A7)
- **Ledger outlives items**: an orgA member still reads the correction movement of a hard-deleted item; an orgB member cannot (§F2).
- **Delegate authority census = 0**: no `e10_is_admin/e10_is_member/e10_is_org/e10_can_read_session/legacy e10_owns_session` in any `e10_org_*` body or org-aware helper.
- **Multi-membership fail-closed**: `current_org()` NULL denies every membership-bound write path.
- **Born-locked ACL**: anonymous has zero EXECUTE on the delegates.
- **Anonymous read denials have two distinct layers, both surfacing as 42501 `insufficient_privilege`**: a *table-grant* refusal where anon holds no SELECT (e.g. `e10_inventory_items`), and a *policy-function-execute* refusal where anon holds table grants but cannot execute an `e10.*` predicate the policy calls (e.g. `e10.is_platform_admin()` in `card_sel`). Neither is a silent 0-row filter; the attribution matters when reasoning about which lock actually holds.

## 5. Red/green (per family)
For at least one scenario per family, the denial is falsified by permissive-replace (a session exercise, before/after in the report): the guarding predicate/policy is relaxed to a permissive form, the attacker succeeds (RED), and the real predicate restores the refusal (GREEN). Families whose denial is a **dropped policy** (F6 mutation deny-by-default) are falsified by *adding* a permissive policy; families whose denial is a **constraint** (F5 global PK) are proven by the specific SQLSTATE + layer note (not permissive-replace-able) and noted as such.

## 6. Findings
A7 is **proofs only**. If a scenario reveals a policy/authorization gap, it is recorded here as a **FINDING** (id, family, identity, observed vs expected, hypothesized layer) and reported to the CPI **unfixed** — no policy change is made inside A7. (Section populated by the gate run; empty ⇒ no gap found.)

_Findings: none at authoring; the gate run confirms or amends this._
