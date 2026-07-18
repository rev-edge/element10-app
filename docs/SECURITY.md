# Element 10 — Security register (Foundation Gate A4)

**Acceptance artifact for the A4 security & performance sweep.** After A4, production advisors show
**zero ERRORs and zero UNDISPOSITIONED warnings** — every remaining WARN/INFO is justified below.
Regenerate the raw findings with MCP `get_advisors` (security + performance) on `ddhkkumiyidorzmajwde`,
or the dashboard's Advisors tab. Re-run before/after every schema change (OPERATIONS.md).

## Standing rule — functions are born non-executable (A5.1a)
The default-function-privileges **factory is closed** (migration `20260716110000`): PostgreSQL's built-in
database-level `EXECUTE TO PUBLIC` default **and** Supabase's schema-level anon/authenticated grants are both
revoked for the `postgres` grantor (the migration role), so **every new public function is born executable only
by `service_role` (and its owner) — not anon, not authenticated.** Therefore, from A6 on, **any RPC that
signed-in users must call has to `GRANT EXECUTE … TO authenticated` explicitly** in its own migration; forgetting
to grant fails safe (the function is simply not callable) instead of leaking. (Schema-scoped revokes do **not**
reach the built-in PUBLIC default — it must be revoked at the database level; see the migration header. The
second grantor, `supabase_admin`, is Supabase-managed, unalterable by `postgres`, and governs only
supabase_admin-created objects we never author.) **CI enforces this every push** via `tests/probe_defpriv.sql`
(create fn as postgres → anon denied, authenticated denied, service_role allowed → explicit grant works → plus a
whole-surface scan that fails if any public function is anon/PUBLIC-executable — the safeguard against the
unalterable `supabase_admin` grantor path).

## What A4 fixed (advisor before → after, prod)
| Advisor | Level | Before | After | Fix |
|---|---|---|---|---|
| `auth_rls_initplan` (0003) | WARN | 14 | **0** | `20260716100000` wrap bare `auth.uid()`/no-arg helpers in `(select …)` |
| `unindexed_foreign_keys` (0001) | INFO | 8 | **0** | `20260716100100` covering index per FK |
| `security_definer_view` (0010) | **ERROR** | 4 | **0** | `20260716100200` `security_invoker=true` + revoke anon on the 4 `e10_obs_*` views |
| `function_search_path_mutable` (0011) | WARN | 1 | **0** | `20260716100300` pin `search_path=public` on `e10_obs_apply_repack_cost` |
| `public_bucket_allows_listing` (0025) | WARN | 1 | **0** | `20260716100400`+`100500` drop the `cards` list policy (public bucket serves URLs; app never lists) |
| `anon_security_definer_function_executable` (0029) | WARN | 0¹ | **0** | `20260716100500` revoke anon/PUBLIC EXECUTE (parity — see note) |

¹ Prod already had anon revoked; the gap was on reproduced environments (staging/local/CI), which the A1
baseline left anon-executable. `20260716100500` is a **no-op on prod** and closes the parity gap everywhere
else. Staging confirmed 33 `anon_security_definer` findings → 0 after the fixup.

### The obs-view leak (context)
The 4 `e10_obs_*` analytics views (`slot_economics`, `break_economics`, `product_premium`,
`format_product_perf`) were `SECURITY DEFINER` **and** granted `anon:SELECT` — an active unauthenticated
internet read of competitive-intel data via the public anon key. Identical class to the P0 recon-view
incident (`docs/incidents/2026-07-15-m4-blob-clobber.md`, migration `20260715130126`). Now invoker-scoped:
the underlying `e10_obs_*` tables are `is_org`-gated on SELECT, so org members read normally and anon reads
nothing. This was the only ERROR-level finding and is **not** one of the prompt's six items — acceptance
("zero errors") forced it; it is a behavior change for anon only (leak closed).

---

## Privileged-function register (SECURITY DEFINER)
Every `SECURITY DEFINER` function in `public`. All confirmed `search_path=public` (pinned). Grant posture after
A4 matches production. "authenticated?" = whether signed-in users may call it via `/rest/v1/rpc/…`.
Advisor 0029 (`authenticated_security_definer_function_executable`) fires for every row marked authenticated=✓ —
**all such rows are intentional and dispositioned here** (26 on prod).

### Group A — inventory API gateway (authenticated ✓, anon ✗)
`e10_inv_add_item`, `e10_inv_edit_item`, `e10_inv_delete_item`, `e10_inv_get`, `e10_inv_list`,
`e10_inv_reserve`, `e10_inv_release`, `e10_inv_set_reservations`, `e10_inv_consume`,
`e10_inv_reverse_consumption`, `e10_inv_mark_sold`, `e10_emit_inventory_movement`.
- **Why definer:** they write the append-only movement ledger + idempotency receipts and mutate
  `e10_inventory_items`/`_reservations` atomically, which requires bypassing the callers' per-row RLS on those
  tables. This is the *only* sanctioned write path (M4: the relational store is the system of record).
- **Internal guard re-checked:** `_e10_inv_guard()` (membership/role), `e10_has_cap('act.inventory_edit')` where
  applicable, and per-key idempotency via `_e10_inv_receipt_check`/`_write`. Direct-RPC abuse is rejected —
  proven by `tests/m31_test.js`, `m32_test.js`, `rls_test.js`.
- **Grant:** `authenticated` (the app's signed-in operators) + `service_role`; anon/PUBLIC revoked.

### Group B — onboarding / roles (authenticated ✓, anon ✗)
`e10_add_member`, `e10_add_viewer`, `e10_assign_role`, `e10_set_role`, `e10_redeem_code`, `e10_buyer_suggest`.
- **Why definer:** manage `e10_members`/`e10_viewers`/`e10_role_permissions`, which are admin-gated tables.
- **Internal guard:** `e10_is_admin()` re-check inside the body — a non-admin caller is rejected even though
  `authenticated` can invoke the function (proven: `rls_test.js` "non-admin call … REJECTED",
  "viewer call to e10_set_role REJECTED"). `e10_redeem_code`/`e10_buyer_suggest` self-scope to the caller.
- **Grant:** `authenticated` + `service_role`; anon/PUBLIC revoked.

### Group C — RLS predicate helpers (authenticated ✓ — REQUIRED, anon ✗)
`e10_is_admin`, `e10_is_member`, `e10_is_org`, `e10_has_cap`, `e10_can_read_session`, `e10_owns_session`,
`e10_my_handle`.
- **Why definer + why authenticated cannot be revoked:** these are called *inside RLS policy expressions*
  (e.g. `card_sel USING ((select e10_is_org()))`). PostgreSQL checks EXECUTE against the **invoking** role, so
  revoking `authenticated` would break RLS for every signed-in user. They are `STABLE`, read only membership/
  ownership, and return a boolean/handle **about the caller** — no data disclosure. The 0029 WARN on these is
  therefore *inherent and intended*.
- **Grant:** `authenticated` + `service_role`; anon/PUBLIC revoked. `e10_schema_version` (constant; used by the
  client load-time handshake) has the same posture.

### Group D — internal helpers (authenticated ✗, anon ✗ — definer chain only)
`_e10_inv_blob_write`, `_e10_inv_clamp_res`, `_e10_inv_guard`, `_e10_inv_item_json`, `_e10_inv_receipt`,
`_e10_inv_receipt_check`, `_e10_inv_receipt_write`, `_e10_inv_replay`, `_e10_inv_replay_json`.
- Called only from Group A within the definer chain. Grant: `postgres` + `service_role` only (no anon,
  authenticated, or PUBLIC). Not on the REST surface; not flagged by 0029.

### Non-definer helpers (SECURITY INVOKER — RLS applies to the caller)
`e10_slot_pred`, `e10_slot_cards`, `e10_slot_partition`, `e10_checklist_facet`, `e10_obs_apply_repack_cost`,
`_e10_inv_bad_num`. Invoker semantics mean the caller's own RLS governs any data touched. A4 pinned
`e10_obs_apply_repack_cost`'s `search_path` and revoked anon/PUBLIC EXECUTE on the three that read org data
(`e10_slot_pred`, `e10_checklist_facet`, `e10_obs_apply_repack_cost`).

---

## Storage — `cards` bucket
`public=true`. Policies on `storage.objects`: `cards authed upload/update/delete` (authenticated, `bucket_id='cards'`).
The `cards public read` SELECT policy was **dropped** — a public bucket serves object URLs (`getPublicUrl`)
without any SELECT policy, and the app never lists the bucket (only `.upload()` + `.getPublicUrl()`), so the
policy only enabled anon enumeration. Card images continue to load by URL; listing is fully closed.

---

## Dispositioned residual findings (no code fix)
| Finding | Level | Count (prod) | Disposition |
|---|---|---|---|
| `authenticated_security_definer_function_executable` (0029) | WARN | 26 | Intended — the inventory API (A), onboarding/roles (B), and RLS predicate helpers (C) above. Each self-guards or discloses nothing; anon revoked; authenticated required (revoking C breaks RLS). |
| `rls_enabled_no_policy` (0008) | INFO | 3 | `e10_mutation_receipts` (append-only idempotency ledger, written only by the Group-A definer chain), `e10_seed_backup`, `e10_bigimport_backup` (cold backups). RLS-enabled + no policy = deny-all to anon/authenticated; only `service_role`/definer reach them. Intended lockdown, not a gap. |
| `unused_index` (0005) | INFO | ~24 | The 8 new FK indexes read "unused" only because they are new / prod has low FK-join traffic; they exist to prevent seq-scans on FK cascades + `organization_id` joins at scale (A6). The pre-existing ~16 are drop candidates, but dropping indexes is a behavior/perf change **out of A4 scope** — deferred to a dedicated perf pass. |
| `auth_db_connections_absolute` (perf) | INFO | 1 | Auth uses a fixed 10-connection allocation. Fine at the current (single small) instance size and low Auth concurrency. Switch to percentage-based **only** when the instance is resized — revisit then. No change now. |

`auth_leaked_password_protection` is **RESOLVED** (enabled on prod 2026-07-16 — HaveIBeenPwned checking on; a GoTrue dashboard toggle, see `docs/OPERATIONS.md`), so it no longer appears in the advisor output.

## Auth pooler / connections decision
Auth connection strategy left at absolute (10) — see the disposition above. Pooler configuration unchanged
(the tests reach prod read-only via the IPv4 session pooler `aws-0-us-east-1.pooler.supabase.com`). No change
warranted at current scale; both are instance-size-dependent and revisited on resize.

---

## A6a — org-core security surface (STAGING/LOCAL only; not on prod until A10)
The tenant spine's org-core (ADR 0005; migration `20260717120000`). Advisors on staging: **zero errors** (security + performance). New surface + dispositions:

- **Authorization predicates live in the non-REST-exposed `e10` schema** (`e10.is_platform_admin / is_org_member / is_org_admin / has_org_cap / current_org / owns_slot / can_spectate_session`). Because `e10` is not in PostgREST's exposed schemas, these are **not reachable via `/rest/v1/rpc`** and do **not** appear in advisor 0029 — the structural fix for the predicate-helper exposure. `authenticated` holds `USAGE` on `e10` + `EXECUTE` on the predicates (needed for RLS evaluation) only.
- **Four new client RPCs** in `public` are `SECURITY DEFINER`, born private, granted `authenticated` only, and self-guard internally: `e10_org_role_clone` (admin ∧ `act.permissions_config`), `e10_claim_handle` (self), `e10_verify_handle_claim` / `e10_reject_handle_claim` (platform-admin, advisory-lock serialized). They appear in advisor 0029 (`authenticated_security_definer_function_executable`) — **intended**, same disposition as the inventory RPCs (the exposed API surface, anon revoked, capability-gated).
- **`e10_platform_admins` = RLS on + zero policies (deny-all)** → advisor `rls_enabled_no_policy` INFO. **Intended** (only `service_role`/definer reach it), same class as the receipts/backups.
- **Unindexed FKs (INFO, 4):** the audit columns `organizations.created_by`, `platform_admins.created_by`, `invitations.invited_by`, `role_permissions.updated_by` reference `auth.users` without a covering index. **Dispositioned** — audit/attribution columns, never a query predicate on the FK column; low-value to index. The hot-path FKs (role FKs, `memberships(user_id)`) are indexed. Add later only if an audit query needs it.
- **Module→bundle ownership (Trent's ruling 2026-07-17, CONFIRMED; encoded in A6a.1 `e10.module_bundle(text)`, IMMUTABLE):** **ALL SIX legacy keys — `home`, `inventory`, `reporting`, `schedule`, `settings`, `toolkit` — map to bundle `core`**; an unknown key returns `null`. **Rationale on record:** the client's Live **Toolkit** contains Ship/fulfillment, which is `core` in `docs/DOMAIN_MAP.md`; a `cards` mapping would strip fulfillment from future non-cards orgs. Cards-specific gating arrives with the new frontend's own concrete keys, not by reclassifying a legacy one. Effective module access = org entitled to `e10.module_bundle(key)` (currently always `core`) AND the role granted the concrete `mod.<key>` capability.
- **Effective module access (A6a.2):** `e10.has_module_access(org, key)` is a non-REST-exposed, authenticated-only predicate that requires both an existing enabled entitlement for `e10.module_bundle(key)` and an exact allow-list grant from `e10.has_org_cap(org, 'mod.' || key)`. CI proves disabled-entitlement/granted-capability = deny, enabled-entitlement/missing-capability = deny, and both present = allow.
- **Handle-verify race fix (A6a.1 → hardened A6a.3):** `e10_verify_handle_claim` is race-free. **A6a.3** makes the post-lock recheck explicit (migration `20260717180000` added the reread; `20260718132644` completed it). After `pg_advisory_xact_lock(hashtext(handle_norm))`, the function **rereads the claim under the lock and requires it still exists, still carries the same locked `handle_norm` (else `claim_handle_changed`), is still `status='pending'`, and is not expired** before the verified-owner recheck; the final `UPDATE` stays conditional on **`status='pending' AND expires_at > now()`** (0 rows → `claim_not_pending_or_expired`) as a backstop. `e10_reject_handle_claim` takes **no** advisory lock, so a reject can commit while a verify is blocked on the lock — the reread catches it at the pending check, and the conditional update catches a reject that lands between the reread and the update. A rejected or expired claim can never become verified under any interleaving. Covered by `tests/a6a1_verify_bundle_test.sql` (sequential: reject-then-verify, expired, two-pending-race) **and** `tests/a6a3_verify_concurrent_test.js` — a genuine **two-connection** proof (A holds the lock, B's verify blocks, A commits a reject, B unblocks and must fail with `claim_not_pending_or_expired`, claim stays `rejected`) — both in CI, the latter also run against staging.
