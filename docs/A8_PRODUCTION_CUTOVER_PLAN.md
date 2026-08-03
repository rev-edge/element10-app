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

**Downtime:** none of consequence — brief metadata-only ACCESS EXCLUSIVE flips per table. On 35/41/6 the VALIDATE scans are trivial.

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
Every migration is idempotent by construction (`create … if not exists`, `add column if not exists`, `where organization_id is null`, `on conflict do nothing`, `if not exists (select 1 from pg_constraint …)`). The CONCURRENTLY index steps are the only non-transactional ones; their INVALID-index recovery is documented in each migration and drilled in P0. A partial failure at any step is resumed by re-running from that step.

---

## 11. Open dependencies carried into the execution gate
1. **Curation path for the catalog (P5 blocker)** — a Track B / model decision (platform-admin curation RPC or org-owned checklist table). P5 cannot run for prod until this ships and the client uses it. (Flagged since A6c.4.)
2. **Money is integer cents** (F4 ruling) — a physical-schema note for whatever P-phase first introduces money columns; no money columns exist in this cutover, so it does not gate A8, but it is recorded so the execution plan does not silently introduce floats.
3. **Client release coordination** — P4/P5 require a client build + `SCHEMA_VERSION` bump released through the `schema-gate` pipeline; the execution gate must schedule the migration and the deploy together.
4. **Maintenance window** — the ADR records a 24/7 SLO with no maintenance windows; this plan achieves **zero-downtime** (all phases online), which is why the expand→backfill→promote→contract shape is mandatory rather than a stop-the-world dump/restore.

---

## 12. What A8 is NOT
A8 is the plan. It is not the migration set (that exists and is staging-proven), not authorization to touch production, and not a schedule. Execution — the backup, the rehearsal transcript review, the coordinated migration+deploy, and the observe/abort decisions — is a **separate gate** requiring CPI acceptance of this plan, outside review, and an explicit go. Until then, production stays exactly where it is: `20260716110000`, read-only, 35/41/6.
