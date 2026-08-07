# A8 — Production Cutover Plan (multi-tenant spine + authorization engine)

Status: **PLAN ONLY — not authorization to execute.** Production is READ-ONLY. Nothing in this document is applied to production. Execution is a separate gate after CPI review + outside review; rehearsal happens only on staging or a scratch restore. Baseline: accepted code head `6eab46a`; A6a→A7 GRANTED and proven on staging.

This is the single irreversible sequence in the project: it moves the **live** production database from pre-tenant head `20260716110000` to the staging-proven multi-tenant head `20260731120000` — against real inventory, real append-only ledger history, and paying operations. It gets the A6c-rev-6 treatment or better: reviewed in full before a line runs.

---

## 0. Ground truth

| | Production (`ddhkkumiyidorzmajwde`) | Staging-proven (`csmbjfmoxkexcyssntbg`) |
|---|---|---|
| Migration head | `20260716110000` (12 migrations) | `20260731120000` (48 migrations) |
| `e10` predicate schema | **absent** | present |
| Org tables (`e10_organizations`/`_roles`/`_memberships`/`_role_permissions`) | **absent** | present |
| `organization_id` columns | **absent** on all 19 retrofit tables | present, NOT NULL |
| RLS policies | legacy org-blind (`e10_is_member`/`e10_is_admin`/`e10_is_org`) | org-scoped `e10.*` (97-policy census consumed) |
| Inventory RPCs | legacy monolithic bodies | relocated delegates + thin wrappers |
| Catalog mutation policies | **15 present** (tenant-writable — the hole) | 0 (deny-by-default) |
| Real data | **35 items / 41 movements / 6 receipts** + sessions/obs/workspace, all org-less | tenant-zero clone, org0-stamped |

**The cutover = replay the 36 migrations `20260717120000 … 20260731120000` on production, in order.** They were authored expand-first and are already lock-minimizing (see §5); this plan validates that claim against production-shaped data, sequences it, and wraps it in backup/rehearsal/verify/abort.

### The 36 migrations, grouped
- **A6a org core (5):** `a6a_org_core` (+ verify-race bundle, module-access, verify-reread, handle-recheck). Creates the `e10` schema, predicates, org tables, and **bootstraps org0 + enrolls existing `e10_members`** (admin→admin role, else→manager role which carries the cap).
- **A6b Step 1 EXPAND (21):** `s1_expand_columns_bridge` (nullable `organization_id` + `e10.stamp_org()` BEFORE INSERT + `live_session_id`); 19 × `CREATE UNIQUE INDEX CONCURRENTLY <t>_org_uq`; `s1_composite_fks` (ADD NOT VALID → VALIDATE).
- **A6b Step 2 BACKFILL (1):** `s2_backfill` — stamp org0, create strict-1:1 `live_sessions` parents, link.
- **A6b Step 3 (1):** `s3_capability_catalog_v1` — seed the capability catalog.
- **A6b FK corrective (1):** `fk_ondelete_corrective` — ledger FKs dropped (ledger outlives items) + org-boundary trigger.
- **A6b Step 5 PROMOTE (1):** `s5_promote` — CHECK NOT VALID → VALIDATE → SET NOT NULL → drop check → `UNIQUE USING INDEX`, ×19.
- **A6c.0–A6c.4 authorization engine (6):** delegates → 55-policy RLS rewrite → wrapper cutover → authority corrective → workspace policies → **catalog/identity + the hole closure**.

---

## 1. Hard boundaries (restated, binding)
1. **No production writes of any kind** until this plan AND its execution gate are approved. Reading prod for verification is allowed.
2. Every prod step must have been **rehearsed against production-shaped data** (a restore of a real prod backup) and passed, before it is proposed for prod.
3. **Idempotent + re-runnable:** every step is safe to re-run after a partial failure (all use `if not exists` / `where … is null` / `on conflict do nothing`).
4. **Abort is defined per phase** (§8) — including what "abort" means once a step has committed (most steps are additive and forward-only; the true point of no return is P4-contract).
5. This plan is authored once; **execution is a separate CPI + outside-review gate.**

---

## 2. Phase P0 — Backup and restore rehearsal (FIRST, gating everything)

No prod step is proposed until the entire sequence has run green against a restore of production-shaped data.

**P0.1 Capture a production-shaped dataset.** Take a fresh logical backup of prod (`pg_dump` of the `public` schema + data, or a PITR/branch snapshot) into a **scratch environment** (a throwaway Supabase project or a local restore). The scratch DB must contain prod's real row shapes and counts (35/41/6 + sessions/obs/workspace), not synthetic fixtures.

**P0.2 Prove the restore.** Verify the scratch restore matches prod byte-for-byte on the cutover-relevant surface:
- row counts per table == prod;
- `e10_inventory_movements` content checksum == prod (the ledger is the crown jewels): `select md5(string_agg(id::text||on_hand_delta::text||coalesce(item_id,''), ',' order by id)) from e10_inventory_movements;`
- no `e10` schema, no org columns (i.e., it is a true pre-cutover clone).

**P0.3 Rehearse the ENTIRE 36-migration sequence on the scratch restore**, in order, capturing per step: duration, lock waits, row counts touched, and the §7 verification queries. A step that is not green on the rehearsal is not eligible for prod.

**P0.4 Rehearse the rollback boundaries** (§6) on the scratch restore: for each phase, exercise its documented recovery and confirm it returns to the phase's start state.

**P0.5 Rehearse re-runnability:** re-run each step a second time on the scratch DB; confirm it is a no-op (idempotency proof).

Gate out of P0: a rehearsal transcript (durations, locks, verifications, rollback drills) reviewed by CPI. **Only then may P1 be proposed for prod.**

---

## 3. Phase P1 — EXPAND (additive, online, reversible)

**Contents:** A6a (5) + A6b Step 1 (21). All additive; production keeps serving reads/writes throughout.

**Ordering + lock character:**
| Step group | DDL | Lock | Notes |
|---|---|---|---|
| A6a org core | CREATE SCHEMA/TABLE/FUNCTION; INSERT bootstrap | brief per new object; new tables uncontended | **Enrollment is load-bearing** — see P1-verify |
| `s1_expand_columns_bridge` | `ADD COLUMN organization_id uuid REFERENCES …` (nullable, no default) ×18 + trigger | metadata-only ACCESS EXCLUSIVE per table (milliseconds on any size) | column is all-NULL → FK validates trivially; `stamp_org` starts org-owning NEW rows immediately |
| 19 × `CREATE UNIQUE INDEX CONCURRENTLY` | index build | **no ACCESS EXCLUSIVE** (SHARE UPDATE EXCLUSIVE) — writes continue | **non-transactional**; a failed one leaves an INVALID index → detect (`indisvalid=false`), `DROP INDEX`, re-run that one step (per each migration's own recovery note) |
| `s1_composite_fks` | ADD … NOT VALID (instant) then VALIDATE | NOT VALID = instant; VALIDATE = SHARE UPDATE EXCLUSIVE (online) | org is NULL pre-backfill so MATCH SIMPLE validates trivially and begins enforcing as P2 populates |

**Downtime:** none. All steps are online. The only ACCESS EXCLUSIVE locks are the metadata-only column/trigger adds (sub-second).

**Critical P1 verification (org enrollment — the correctness lynchpin):** `stamp_org()` stamps NEW rows via `e10.current_org()`, which returns org0 **only for a user with exactly one active org0 membership.** After A6a bootstrap, assert **every distinct writer is enrolled**:
- `select count(*) from e10_members m left join e10_organization_memberships om on om.user_id=m.user_id where om.user_id is null;` must be **0**.
- Additionally enumerate any `auth.uid()` that appears as `updated_by`/`created_by`/`streamer_uid`/`buyer_uid` on the 19 tables but is **not** in `e10_organization_memberships` → each such identity would stamp `organization_id=NULL` on a live write during the P1→P3 window and fail P3 promote. **This set must be empty, or those users are enrolled before P1 completes.** (Abort criterion A-P1.)

**Rollback boundary (P1):** fully reversible. `DROP` the new indexes/constraints/columns/trigger/functions/org tables (down path `supabase/recovery/a8_p1_expand_down.sql`, authored + drilled in P0). No data mutated (columns are NULL); dropping them restores the pre-cutover shape exactly.

---

## 4. Phase P2 — BACKFILL (data, online, forward-recoverable)

**Contents:** `s2_backfill` + `s3_capability_catalog_v1` + `fk_ondelete_corrective`.

- `s2_backfill`: `UPDATE … SET organization_id = org0 WHERE organization_id IS NULL` across the 19 tables (parents before children so the P1 composite FKs hold), then strict-1:1 `live_sessions` parents (deterministic id = `md5('a6b_live_session:'||session_id)`) + link. On 35/41/6 + sessions/obs, this is **a few hundred row-locked UPDATEs — sub-second**, no table lock. Idempotent (`where … is null` / `on conflict do nothing`).
- `s3_capability_catalog_v1`: seed rows (INSERT … on conflict do nothing). Additive.
- `fk_ondelete_corrective`: drops `movements→items` + `receipts→items` composite FKs (ledger intentionally outlives hard-deleted items), recreates the other 12 to mirror legacy ON DELETE, installs `e10.assert_ledger_item_org` boundary trigger. DDL on constraints (brief locks); no data rewrite.

**Downtime:** none.

**Backfill correctness + irreversible-safety (the tenant-zero data):**
- The ledger is append-only and is the business's financial truth. The backfill **only sets a previously-NULL `organization_id`**; it never touches `id`, `on_hand_delta`, `item_id`, `idempotency_key`, or any ledger content. Prove it: capture the movements content checksum (§0) **before and after** P2 — it must be **identical** (org is not in the checksum). Receipts idempotency re-scopes to `(org0, idempotency_key)`; the global idempotency key is untouched until CONTRACT, so no replay key changes meaning.
- **Verify zero residual NULLs** after P2 on all 19 tables (Abort A-P2 if any remain — it means a live write landed org-less; the writer must be enrolled and the backfill re-run before proceeding).
- Because the org value is deterministic (org0) and the backfill is idempotent, P2 is **forward-recoverable**: a re-run converges; there is no lossy transformation to undo.

**Rollback boundary (P2):** still reversible in principle (set the backfilled `organization_id` back to NULL, drop the `live_sessions` parents) but **P2 is where reversibility starts to cost** — it created `live_sessions` rows and re-scoped receipts. Recovery `supabase/recovery/a8_p2_backfill_down.sql` restores NULLs + removes the parents; drilled in P0. Prefer forward-fix over rollback once P2 has run.

---

## 5. Phase P3 — PROMOTE / CONTRACT-of-the-columns (the first hardening)

**Contents:** `s5_promote` — for each of the 19 tables: `CHECK(org IS NOT NULL) NOT VALID → VALIDATE → SET NOT NULL → DROP check → ADD CONSTRAINT <t>_org_uq UNIQUE USING INDEX <t>_org_uq`.

**Lock character (why this is safe even on the ledger):**
- `ADD CHECK … NOT VALID` — instant (no scan).
- `VALIDATE CONSTRAINT` — **SHARE UPDATE EXCLUSIVE** (online; reads + writes continue), one scan.
- `SET NOT NULL` — normally an ACCESS EXCLUSIVE full scan, but PG 12+ **skips the scan** because the just-validated CHECK proves non-null. So the ACCESS EXCLUSIVE window is the catalog flip only (milliseconds).
- `UNIQUE USING INDEX <t>_org_uq` — converts the **already-built CONCURRENTLY index** in place (same name); ACCESS EXCLUSIVE but instant (no build).

**Downtime:** none of consequence — brief metadata-only ACCESS EXCLUSIVE flips per table. On the real data the retrofit tables total ~6.5k rows (largest: `e10_obs_slots` 5,870; `e10_cards` 57,288 is NOT retrofit — global catalog, A6c.4 policy DDL only), and every VALIDATE/backfill/promote step measured <125 ms (total 1.8 s for all 36).

**Abort A-P3:** if any `VALIDATE` fails, a NULL `organization_id` survived P2 (a live org-less write slipped in) → **abort P3, do not SET NOT NULL**, return to P2 (enroll the writer, re-backfill), re-verify zero NULLs, retry. Aborting P3 mid-table is safe: the CHECK-NOT-VALID and VALIDATE are reversible (`DROP CONSTRAINT`); nothing is lost.

**Rollback boundary (P3):** the `<t>_org_uq` UNIQUE constraints and NOT NULL can be dropped (recovery `a8_p3_promote_down.sql`), reverting to nullable org columns. This is the **last cleanly-reversible phase**. After P4 the RLS/RPC contract changes and the client is redeployed — rollback then means a coordinated client+DB revert (see §6).

---

## 6. Phase P4 — Authorization engine (RLS + RPC cutover) + client coordination

**Contents:** A6c.0 (delegates, additive) → A6c.1 (55-policy RLS rewrite) → A6c.2 (wrapper cutover) → A6c.2.1 (authority corrective) → A6c.3 (workspace policies). **A6c.4 [the catalog hole] is P5, deliberately last — see §7.**

**Character:** these are function + policy replacements (no data rewrite, no long locks; policy swaps are catalog-only). The risk here is **contract**, not locks: the RPC bodies and RLS predicates change, and the **deployed client must match**.

**Client / SCHEMA_VERSION / deploy coupling (this is the real production hazard):**
- The client carries a `SCHEMA_VERSION`; CI's `schema-gate` job blocks the Pages deploy unless the live DB's `e10_schema_version()` equals the client's `SCHEMA_VERSION`, and the client's `_schemaHandshake()` fails closed at runtime on mismatch.
- Therefore P4 is a **coordinated deploy**, not a bare migration:
  1. Apply A6c.0–A6c.3 to prod (delegates + policies + wrappers). The **legacy wrappers keep their exact signatures**, so the currently-deployed client keeps working through the cutover (it calls `e10_inv_*`, now thin delegators) — this is why A6c.2 preserved signatures verbatim.
  2. Bump `e10_schema_version()` in the migration to the new contract value; bump the client `SCHEMA_VERSION` to match in the same release.
  3. Deploy the client; `schema-gate` passes only on exact match; `_schemaHandshake()` confirms at runtime.
- **Observe window:** after P4, watch error rates, RPC failures, and RLS-denial logs before P5. The org-scoped policies now govern every read; a mis-enrolled user surfaces here as zero-rows rather than data loss.

**Rollback boundary (P4):** this is the **coordinated point of no return**. Rolling back P4 means restoring the legacy RPC bodies (recovery `a8_p4_authz_down.sql`, which re-creates every legacy body/signature and re-installs the legacy policies) **and** redeploying the prior client build **and** reverting `e10_schema_version()`. Rehearse this coordinated revert in P0. Beyond P4, forward-fix is strongly preferred; a true rollback is a business-visible event.

---

## 7. Phase P5 — The catalog write hole (A6c.4) — closed last, with client coordination

**The hole:** production's `e10_cards/checklists/players/sets/teams` carry **15 tenant-writable mutation policies**. These tables have **no `organization_id`** (global reference data), so today any member can write shared catalog data visible to every future tenant. A6c.4 drops the 15 policies → deny-by-default (curation via service_role / a future platform-admin RPC).

**Where it closes:** **last** (P5), after the authorization engine (P4) is live and observed. Closing it is a pure policy drop (catalog-only lock, instant).

**What breaks if it closes early — and the required precondition:**
- The **currently deployed production client creates checklists and cards by direct table INSERT** (the document-driven setup writes `e10_checklists`/`e10_cards` from the client under RLS). The moment the 15 policies drop, those INSERTs fail `42501`. So closing P5 **before** the client no longer needs direct catalog writes **breaks operator checklist/card creation** in production.
- **Precondition for P5 (a hard dependency on Track B / a model decision, flagged since A6c.4):** a **curation path must exist first** — either (a) a reviewed `SECURITY DEFINER` platform-admin curation RPC that performs catalog writes with proper authority, or (b) an **org-owned checklist table** (checklists become tenant data with `organization_id`, org-scoped like inventory) so operators write their own, and the *global* catalog stays platform-curated. Until (a) or (b) ships and the client is redeployed to use it, **P5 does not run** — the hole stays open on prod as a known, bounded risk (single-tenant today, so no cross-tenant exposure yet), exactly as recorded on the board.
- If P5 must precede the curation path for security reasons, the explicit tradeoff is: **catalog creation is disabled** for operators until the curation path deploys. That is a CPI/operator business call, not an engineering default. This plan does **not** choose it silently.

**Abort A-P5:** if catalog-write errors spike post-P5 without the curation path deployed, re-add the 15 policies (recovery `a8_p5_catalog_down.sql`, instant) — the hole reopens but operations continue — and hold P5 until the curation path is live.

---

## 8. Lock / downtime / abort summary

| Phase | Longest lock | Online? | Abort trigger | Abort action | Reversible? |
|---|---|---|---|---|---|
| P0 rehearsal | n/a (scratch) | — | any step red on scratch | fix before prod | n/a |
| P1 expand | metadata-only ACCESS EXCL (ms) | yes | un-enrolled writer set non-empty (A-P1) | enroll, or drop columns and stop | fully |
| P2 backfill | row locks (sub-second) | yes | residual NULL org after run (A-P2); ledger checksum changed | re-enroll+re-backfill; **hard stop if checksum drift** | forward-recoverable |
| P3 promote | ACCESS EXCL catalog flip (ms) | yes | VALIDATE fails on a NULL (A-P3) | drop check, return to P2 | last clean rollback |
| P4 authz+deploy | catalog-only (policy/fn swap) | yes | RPC error / RLS-denial spike; schema-gate fail | coordinated revert (fn+client+schema_version) | coordinated only |
| P5 catalog close | catalog-only (ms) | yes | catalog-write error spike w/o curation path | re-add 15 policies (reopen hole) | instant |

"Abort once a step has committed" means, for the additive phases (P1–P3), **stop and forward-fix or run the phase's down-recovery**; the true irreversible commitment is **P4** (contract + client), which is why P4 is gated on a rehearsed coordinated revert and P5 is held behind the curation-path dependency.

**Measured contention (A8-DRILL2, D2 — replaces the earlier estimate):** under 3 concurrent writers committing continuously against the retrofit tables (1,017 commits during P1; 729 during P2+P3; 0 errors), the **maximum observed stall of a live writer was 12 ms**, and no migration step escalated beyond its predicted lock or blocked a writer materially. P1 ran 2.63 s under load (1.8 s idle); P2+P3 0.52 s. The ACCESS-EXCLUSIVE steps (ADD COLUMN, SET NOT NULL) are metadata-only so their lock window does not grow with row count. **Caveat / required mitigation:** the rehearsal used only short (autocommit) writer transactions. A *long-running* writer transaction held across a P1/P3 ACCESS-EXCLUSIVE step would make that step queue behind it and, in turn, queue every subsequent writer behind the step (the classic "ALTER TABLE behind a long query stalls the table" foot-gun). **Therefore each ACCESS-EXCLUSIVE migration step must set a short `lock_timeout` (e.g. 3 s) and be retry-wrapped**, so it fails fast and releases rather than head-of-line-blocking live traffic. This is a new execution-gate requirement (D2 finding).

---

## 9. Verification queries (per phase, run on scratch in P0 and on prod at execution)
- **P1:** every writer enrolled (§3); each `<t>_org_uq` index `indisvalid=true`; each composite FK `convalidated=true`; `e10` schema + org tables present.
- **P2:** zero residual NULL `organization_id` on all 19 tables; movements content checksum **unchanged** vs pre-P2; `live_sessions` count == `break_sessions` count (strict 1:1); capability catalog seeded (admin/manager/streamer/ops row counts match staging).
- **P3:** all 19 `organization_id` NOT NULL; 19 named `<t>_org_uq` UNIQUE constraints (`contype='u'`, valid, non-partial); no PK promotion; all triggers attached.
- **P4:** delegate ACL exactly the 13 client delegates authenticated (probe_defpriv green); 55 A6c.1 policies org-scoped; wrappers thin; `e10_schema_version()` == deployed client `SCHEMA_VERSION`; the A7 hostile matrix gate green against a two-org fixture on prod-restored scratch.
- **P5:** 0 catalog mutation policies; RLS enabled on the 5 catalog tables; deny-by-default INSERT refused 42501; curation path callable by its intended role.
- **Global (every phase):** migration count `+N exactly`; `get_advisors` 0 errors; the baseline **35 items / 41 movements / 6 receipts** byte-identical throughout (the cutover adds `organization_id`, never touches business content).

---

## 10. Idempotency & re-runnability
Every migration is idempotent by construction — **verified per-file in A8-PREP** (see the 36-row audit below), after fixing `s1_composite_fks` (its 16 bare `ADD CONSTRAINT` are now guarded by `if not exists (select 1 from pg_constraint …)`; the plan's earlier blanket claim was false for that one file until fixed). The CONCURRENTLY index steps are the only non-transactional ones; their INVALID-index recovery is documented in each migration and drilled in P0. A partial failure at any step is resumed by re-running from that step.

---

## 11. Open dependencies carried into the execution gate
1. **Curation path for the catalog (P5 blocker)** — a Track B / model decision (platform-admin curation RPC or org-owned checklist table). P5 cannot run for prod until this ships and the client uses it. (Flagged since A6c.4.)
2. **Money is integer cents** (F4 ruling) — a physical-schema note for whatever P-phase first introduces money columns; no money columns exist in this cutover, so it does not gate A8, but it is recorded so the execution plan does not silently introduce floats.
3. **Client release coordination** — P4/P5 require a client build + `SCHEMA_VERSION` bump released through the `schema-gate` pipeline; the execution gate must schedule the migration and the deploy together.
4. **Maintenance window** — the ADR records a 24/7 SLO with no maintenance windows; this plan achieves **zero-downtime** (all phases online), which is why the expand→backfill→promote→contract shape is mandatory rather than a stop-the-world dump/restore.

---

## 12. What A8 is NOT
A8 is the plan. It is not the migration set (that exists and is staging-proven), not authorization to touch production, and not a schedule. Execution — the backup, the rehearsal transcript review, the coordinated migration+deploy, and the observe/abort decisions — is a **separate gate** requiring CPI acceptance of this plan, outside review, and an explicit go. Until then, production stays exactly where it is: `20260716110000`, read-only, 35/41/6.

---

## 13. A8-PREP — rehearsal findings closed (2026-08-04)

Rehearsed on a byte-faithful local scratch restore of real prod data (24.9 MB dump; ledger + 29-table count fingerprints matched prod). Production untouched.

### F5 — canonical ledger-integrity check (reproducible by any auditor)
The one canonical crown-jewels query. Run it on prod today and it returns the stated value; run it after any cutover step and it MUST be unchanged (organization_id is not in it — the cutover is additive to the ledger).
```sql
select md5(string_agg(
  id::text||'|'||coalesce(on_hand_delta::text,'~')||'|'||coalesce(reserved_delta::text,'~')||'|'
  ||coalesce(item_id,'~')||'|'||coalesce(movement_type,'~')||'|'||coalesce(idempotency_key,'~'),
  chr(10) order by id)) as canonical_ledger_md5
from public.e10_inventory_movements;
```
**Production value (2026-08-04): `f54a1fe978614e21cf2ffb8c63afb475`.** (The plan's earlier §2 formula `md5(string_agg(id::text||on_hand_delta::text||coalesce(item_id,''),',' order by id))` = `0df7a705c70a69120047c7adf35c9186`; it is fragile — a single null `on_hand_delta` would silently drop a row from the aggregate — so it is retired in favour of the null-safe delimited query above. The transcript's `e4cfa76d…` was yet a third variant; there is now ONE.)

### F1 — idempotency fixed + full audit
`s1_composite_fks` fixed (16 guarded `ADD` + 16 guarded `VALIDATE`; behaviour + resulting schema identical to the accepted A6b migration, only re-runnability added). The **re-run drill now passes: forward 0 failures, re-run 0 failures across all 36.** A deeper hazard was found and closed: on a full re-run, s1 would resurrect the movements/receipts composite FKs that `fk_ondelete_corrective` deliberately drops (ledger outlives items) — the guarded form + fk_corrective's own idempotent re-drop leave the end state correct (movements/receipts composite FKs absent; reservations kept; 14 org FKs validated; ledger md5 unchanged). Per-file audit: all 36 carry an idempotency mechanism (create-or-replace / if-not-exists / on-conflict / where-null / guarded-DO); **0 residual risk**.

### F2 — committed, drilled recovery scripts (`supabase/recovery/a8_p*_down.sql`)
- **P1/P2/P3 down: authored (enumerated from the migrations), committed, and DRILLED in sequence** — P3-down (drop NOT NULL only; the org_uq UNIQUE is left because the composite FKs depend on it and it is FK-equivalent to the Step-1 index), P2-down (bulk org-null with `session_replication_role=replica` because the backfill went parents-first so the reversal must go children-first), P1-down (full CASCADE teardown of the 9 added tables + org columns + e10 schema). The chain returns to the **exact pre-cutover fingerprint** (29 tables, e10 schema 0, org cols 0, ledger `f54a1fe9`). Authoring these surfaced real dependency traps (constraint-depends-on, FK ordering) — evidence that recovery scripts must be drilled, not assumed.
- **P4/P5 down: `restore-from-backup`, not a forward script** (see F6). The committed `a8_p4_authz_down.sql` performs the DB-side functions-only revert (proven) and documents that the policy surface is restored from the pre-P4 backup; `a8_p5_catalog_down.sql` re-adds the 15 catalog mutation policies (the documented P5 abort) + notes the identity/SELECT reverts come from the backup.

### F6 — the P4 rollback: **P4 is effectively irreversible in live operation.** (drilled, stated plainly)
- **DB-side RPC bodies ARE restorable:** dropping the A6c delegates and re-applying the legacy `CREATE OR REPLACE` bodies (with `check_function_bodies=off`) returned `pg_get_functiondef` fingerprint **exactly** to post-P3 (`b9e6a467…`) on the scratch.
- **DB-side POLICIES are NOT reliably restorable by forward script:** the 55 org-table + 4 workspace policies are not isolated named `CREATE POLICY` statements (they originate in `20260716100000_rls_initplan`); a reconstructed DROP+CREATE from `pg_policies` decompiled text failed on a complex predicate. The authoritative recovery is **restore from the pre-P4 backup**.
- **The live reversal also requires reverting the deployed client + `e10_schema_version()` in lockstep** through the schema-gate Pages deploy.
- **Conclusion:** P4 is the point of no return. Operationally, **forward-fix is the default; a true P4 rollback = restore the pre-P4 backup + coordinated client/SCHEMA_VERSION revert, as an incident-level, operator-authorized event.** This must be understood before the execution go, not discovered during an incident.

### F4 — lock-contention gap (scope limitation; proposed, not run)
The rehearsal is single-connection: it measures per-step DURATION (<125 ms each), not lock waits under concurrent live traffic. The lock *types* are fixed by the DDL and are the lock-minimizing forms (`CONCURRENTLY`, `NOT VALID`→`VALIDATE`, CHECK-validated `SET NOT NULL`, `UNIQUE USING INDEX` on a pre-built index), so contention risk is low but untested. **Proposed (do not run without authorization):** during the execution rehearsal, drive a background writer against the retrofit tables (the m31/m32 RPC workload at a modest rate) while P1–P3 apply, and record `pg_stat_activity` lock waits + any statement-timeout events per step; abort if any P1–P3 step blocks a writer beyond a set threshold.

---

## 14. A8-DRILL2 — the last two rehearsals (2026-08-07)

Drilled on the byte-faithful scratch restore (real prod data). Production untouched (`20260716110000`, 35/41/6, canonical ledger `f54a1fe9…`).

### D1 — P4/P5 recovery drilled end-to-end as restore-from-backup (with wall-clock)
Sequence: capture pre-P4 backup → apply P4 (A6c.0–A6c.3) + P5 (A6c.4) → recover from the backup → prove exact return to the post-P3 fingerprint.

**Result: exact return proven** — all five fingerprints match post-P3 after recovery: ledger `f54a1fe9…`, counts `af98b7cb…`, **fn_bodies `b9e6a467…`**, **policy_defs `77a3e5d0…`**, 97 policies. So the P4 authorization surface (RPC bodies AND policies — the part F6 flagged as not forward-scriptable) *is* recoverable via backup restore.

**Wall-clock (this data size, local):** backup **0.35 s** (4.9 MB custom-format); faithful recovery **~1.4 s**. These are the data/schema-restore floor; **production recovery is Supabase PITR / backup-restore to a target endpoint, which is provisioning-bound (minutes), not ~1.4 s** — the number the operator needs at incident time is "minutes to a restored endpoint," dominated by provisioning, not data volume at this scale.

**D1 findings (method matters — three ways to get recovery subtly wrong, all found by doing it):**
1. **Version-matched dump/restore is mandatory.** `pg_dump` 16 against the PG 17 server produced a **0-byte dump** (then a broken restore). Use the platform/server-matched binary (here: the container's 17.6). A version mismatch is a silent recovery failure.
2. **`pg_restore --clean` is the WRONG method** into a live cluster: it only drops objects *present in the dump*, so the **14 A6c delegates created during P4 survived** the "recovery" (49 functions vs the 35 target). Recovery must be **clean-slate** (drop schemas / restore to a fresh target), not `--clean`.
3. **Recovery is full-cluster / multi-schema and privilege-sensitive.** A `-n public`-scoped restore dropped the `e10` predicate schema's functions, cascading 8 policy failures; and `pg_restore` replays ownership / `ALTER DEFAULT PRIVILEGES` / cross-schema (`auth`) statements that require the cluster superuser. A faithful restore is the **full multi-schema dump restored as superuser** — which is exactly what a platform-native PITR does, and why hand-rolled `pg_restore` into a live DB is not the recovery path.

**Client-side revert (stated in the same terms):** a P4 recovery is not complete at the database. The deployed client's `SCHEMA_VERSION` and the live `e10_schema_version()` must be reverted in lockstep through the `schema-gate` Pages deploy (the client fails closed on mismatch). So the true recovery wall-clock = **PITR-to-restored-endpoint (minutes) + a client redeploy of the prior build (minutes)**, coordinated — an incident-level, operator-authorized event, not a script.

### D2 — lock contention under a live writer
3 concurrent writers committing continuously (short autocommit UPDATEs on the retrofit tables) while each phase applied; `pg_stat_activity` sampled ~every 15 ms for `wait_event_type='Lock'`.

**Result: the phases hold under contention.** Max live-writer stall **12 ms** (P1) / **10 ms** (P2+P3); **0 writer errors** across 1,746 commits; no step escalated beyond its predicted lock. Most observed waits were writer-vs-writer (multiple writers on one hot row), not migration-induced; with distinct-row writers the migration-vs-writer waits were ≤10 ms (a writer briefly queued behind the backfill UPDATE-all). The ACCESS-EXCLUSIVE steps are metadata-only, so this does not worsen at prod row counts. See §8 for the numbers folded into the plan.

**D2 finding (folded into §8): short `lock_timeout` + retry on the ACCESS-EXCLUSIVE steps.** The rehearsal used only short writer transactions. A long-running writer transaction across a P1/P3 ACCESS-EXCLUSIVE step would head-of-line-block the table. Each such step must set a short `lock_timeout` (~3 s) and retry, failing fast rather than stalling live traffic. New execution-gate requirement.

**Honest bottom line:** zero-downtime is supported by the measured numbers at this load and data scale; the two conditions that keep it true in production are (a) the `lock_timeout`+retry guard on ACCESS-EXCLUSIVE steps, and (b) no long-running writer transaction deliberately held across the promote — both are execution-gate items, not code changes to the migrations.
