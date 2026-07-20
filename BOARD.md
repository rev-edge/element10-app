# Element 10 Project Board

_Last reconciled: 2026-07-20 by Chief Project Inspector_

**CANONICAL LOCATION:** `/Users/tsconnely/dev/element10-app/BOARD.md`.
That file is the only authoritative copy. Any other copy of this document,
anywhere, is a non-authoritative snapshot and must not be used to decide a gate.
If a snapshot disagrees with the repository copy, the repository wins and the
snapshot is stale.

## CURRENT SYSTEM MOMENT

- [x] Product-first workflow approved
- [x] PF-0 provenance and hub gate accepted
- [x] A6c authorization plan rev 6 approved
- [ ] A6c.0 additive prerequisites implemented and accepted - CURRENT TRACK A GATE
- [ ] PF-C1 Product Master accepted - CURRENT TRACK B GATE
- [ ] PF-C2 Product Configuration accepted
- [ ] Human walkthrough of the combined PF-C1 + PF-C2 Product workflow

## APPROVALS LEDGER

Only the Chief Project Inspector records rows here. An agent may cite a row; no
agent may add one. If a gate is not listed as GRANTED, it is not approved — stop
and report rather than infer it. Every approval names the artifact it was granted
against, so an approval cannot be silently carried forward to a later revision.

Rows carry only GRANTED or NOT ACCEPTED. A gate that has not been reviewed has no
row at all. Authorization to *begin* work is never a ledger row; it lives in the
track's Next authorized action. A row is added for a gate only when its completed
work has been independently accepted.

| Gate | Status | Approved by | Date | Artifact |
|---|---|---|---|---|
| A6a organization core / tenant spine | GRANTED | CPI | 2026-07-20 | head `53501928a6ef928ad5a5ec4401e4e12073e6527a` |
| A6b tenant-zero backfill + capability catalog | GRANTED | CPI | 2026-07-20 | head `53501928...`, CI run `29688509320` |
| Product-first workflow | GRANTED | CPI | 2026-07-20 | `874b8f40a519ddbb22c79bfd4e8180746e5c0a13e8eba2fd18a96d0951ed82fb` (see Open Items — unverified) |
| PF-0 provenance and hub gate | GRANTED | CPI | 2026-07-20 | PF-0.2 archives — see `PF0_2_ARCHIVE_HASHES.txt` |
| A6c authorization plan rev 6 | GRANTED | CPI | 2026-07-20 | `Element10_A6c_PLAN.md` SHA-256 `2d1710bfdb0653271960f021c12efacb4c83f1be22067d6e064e6724ed33ce70` |
| PF-C1 Product Master | NOT ACCEPTED — PF-C1.2 corrective active | - | - | - |

## NEXT PROMPT TO SEND

This section is written and replaced only by the Chief Project Inspector at each
reconciliation. Each agent executes ONLY its own subsection and ignores the other.
If your subsection says ALREADY DISPATCHED, do not re-run it.

---

### TRACK A — Claude Code — READY TO DISPATCH

Implement A6c.0 only.

Authorization: the Approvals Ledger above records
`A6c authorization plan rev 6 | GRANTED | CPI | 2026-07-20 |
Element10_A6c_PLAN.md SHA-256 2d1710bfdb0653271960f021c12efacb4c83f1be22067d6e064e6724ed33ce70`.
Cite that row. Do not infer authorization from anything else.

Repository verification before editing:
- Canonical repo `/Users/tsconnely/dev/element10-app`, branch `foundation-a6`.
- Accepted **code** head is `53501928a6ef928ad5a5ec4401e4e12073e6527a`. HEAD is
  currently `51667c0`, a documentation-only commit adding this board on top of it.
  Verify **ancestry** against the accepted code head. Do not require equality
  with HEAD.
- Read `AGENTS.md`, ADR 0005 rev 3.2.2, `Element10_A6c_PLAN.md` (rev 6), and the
  97-policy census before writing anything.
- Report any uncommitted user changes and preserve them.
- All diffs are taken against `53501928...`, never a range you select. Where you
  describe deployed behavior, pull the function body from staging rather than
  characterizing it from a diff.

Scope — A6c.0 ONLY:
- Additive prerequisites, predicates, visibility, and constraints.
- All `e10_org_*` delegates and `_e10_inv_*` helpers created born-locked per the
  section 5.d ACL matrix: 13 client delegates granted `authenticated` +
  `service_role`; `e10_org_emit_inventory_movement`, `_e10_inv_guard(p_org)` and
  every org-aware helper revoked from `authenticated` and granted `service_role`
  only; PUBLIC and anon revoked throughout.
- Nothing is switched over. No wrapper cutover. No policy cutover.
- Existing sessions remain private.
- STAGING and LOCAL only. Production stays read-only.
- Stop before A6c.1.

Fold in while you work — documentation only, no behavior change, no re-review:
1. State the function arithmetic explicitly so it is not re-derived: 14 public
   inventory RPCs in section 5.a map to 14 delegates; 13 are client-callable; the
   14th, `e10_org_emit_inventory_movement`, is internal-only per section 5.d;
   with section 5.b's 10 helpers that is the 24-function inventory. The
   "19 RPC wrappers" figure in the Track A handoff is stale.
2. Membership-bound inventory wrappers that pass `e10.current_org()` fail closed
   for users with multiple active memberships. `e10_buyer_suggest` and
   `e10_redeem_code` are exceptions: both derive organization from session context
   and never call `e10.current_org()`. Buyer Suggest remains Entity
   (session-owner); Redeem Code remains Viewer.

Do not: add product-first physical tables; rename or remove persisted capability
rows; persist `product.write` or `session.approve`; modify accepted A6a/A6b
migrations; promote composite candidate keys to primary keys; touch production;
begin A6c.1.

Run the A6c.0 gate tests to completion. Report, leading with:
1. Changed files with before/after hashes, diffed against `53501928...`.
2. The exact authenticated-executable allowlist, proving it is the pre-existing
   public wrappers plus exactly the 13 client delegates and nothing else.
3. `has_function_privilege('authenticated', oid, 'EXECUTE')` = false for every
   internal helper, and zero anon/PUBLIC execution across all A6c functions.
4. Confirmation that no wrapper or policy was cut over and existing sessions
   remain private.
5. Confirmation that A6a/A6b migrations and production are untouched, and that
   A6c.1 has not begun.
6. A proposed `BOARD.md` delta. Do not mark the gate accepted yourself.

Stop and request "A6c.0 accepted."

---

### TRACK B — Claude Design — ALREADY DISPATCHED

PF-C1.2 is in flight. Do not re-run it and do not start PF-C2.

Its required closure items are listed under TRACK B → "PF-C1.2 required closure"
below. On return, package as `Element10_PFC1_2_REVIEW.zip` plus
`PFC1_2_ARCHIVE_HASHES.txt`, attach both, lead the report with changed-file
hashes and the completed verifier result, propose a `BOARD.md` delta, and stop
requesting "PF-C1 accepted." Do not mark the gate accepted yourself.

---

## TRACK A: ENGINE AND AUTHORIZATION

### Accepted

- A1-A5 foundation
- Relational inventory engine, ledger, receipts, idempotency, reservations
- A6a organization core and tenant spine
- A6a.1-A6a.3 corrective closures
- A6b tenant-zero backfill and 19-table organization retrofit
- A6b capability catalog
- A6c authorization plan rev 6
- Accepted repository **code** head: `53501928a6ef928ad5a5ec4401e4e12073e6527a`
- CI green: run `29688509320`
- Documentation-only commits (BOARD.md, docs/) may sit on top of the accepted
  code head without moving it. The accepted code head changes only when new
  code or migrations are accepted. Verify ancestry against it, not equality
  with HEAD.

### Frozen

- A6a and A6b migrations
- Existing global primary keys until CONTRACT
- Legacy twelve permissions and A6b fifteen additive capabilities
- Production remains read-only until A10

### Current gate

- A6c plan rev 6 APPROVED 2026-07-20 against `2d1710bf...`. The ACL correction
  (authenticated client delegates vs service-role-only internal helpers) is
  accepted as written in section 5.d.
- A6c.0 is now the active implementation gate. Nothing beyond A6c.0 is authorized.

### Approved-with-amendment (documentation only, no re-review required)

Two items to fold into the plan text. Neither changes behavior.

1. State the function arithmetic explicitly so it is not re-derived: 14 public
   inventory RPCs in section 5.a map to 14 delegates. 13 are client-callable; the
   14th, `e10_org_emit_inventory_movement`, is internal-only per section 5.d. With
   section 5.b's 10 internal helpers this is the 24-function inventory. The
   "19 RPC wrappers" figure in the Track A handoff is stale and matches none of
   these.
2. Record the multi-membership consequence, not just the invariant.
   Membership-bound inventory wrappers that pass `e10.current_org()` fail closed
   for users with multiple active memberships. `e10_buyer_suggest` and
   `e10_redeem_code` are exceptions: both derive organization from session context
   and never call `e10.current_org()`. Buyer Suggest remains Entity
   (session-owner); Redeem Code remains Viewer.

### Next authorized action

1. Implement A6c.0 ONLY: additive prerequisites, predicates, visibility,
   constraints, and all `e10_org_*` delegates and helpers, born-locked per the
   section 5.d ACL matrix. Nothing switched over. No wrapper or policy cutover.
2. STAGING and LOCAL only. Production remains read-only.
3. Stop before A6c.1. Run the A6c.0 gate tests, log results, and propose a
   BOARD.md delta. Do not mark the gate accepted.

## TRACK B: PRODUCT AND OPERATOR INTERFACE

### Accepted foundation

- D1 shell and visual language
- D2 planning foundation
- D2 C1 Schedule
- D2 C2 preparation/readiness
- D2 C3 Planned Break management
- Product-first model, D3 contract, governance, workflow, and PF-C1-PF-C21 sequence
- PF-0 provenance and hub gate

### Current gate

- PF-C1 Product Master is implemented but not accepted.
- PF-C1.1 was rejected.
- PF-C1.2 is the active corrective closure.
- PF-C2 has not started.

### PF-C1.2 required closure

- Add active/archived state, Archive, and Restore.
- Archived identity continues blocking normalized duplicates.
- Refusal caused by an archived conflict must say so and offer view/restore.
- Repair settled focus return after hashchange rendering.
- Scan every rendered product host, including overlays.
- Reconcile every status-bearing statement by search.
- Attach the external archive manifest.
- Finish all verification before requesting acceptance.

## CROSS-TRACK CONTRACTS

- Track B prototypes do not define authoritative database schemas.
- Product Master, Product Configuration, PO, receipt, lot, allocation,
  reservation, and preparation-version schemas remain unresolved.
- Track A must not implement product-first physical tables during A6c.
- Track A must not rename or remove persisted capability rows during A6c.
- PF-C1 mutation uses `act.inventory_edit` as the interim persisted authority.
- `product.write` remains proposed and unpersisted.
- `mod.*` controls entitlement/navigation visibility, not database authorization.
- `session.approve` remains a future human-ruling gate.
- Reservation and allocation production work requires atomic database operations,
  idempotency, concurrency protection, and explicit overcommit behavior.
- Platform Card Catalog remains shared and read-only to tenants.
- Organization Product Master remains tenant-owned.
- No production mutation is authorized before A10.

## ENGINE INVARIANTS

These survive every future pass. Any change that violates one is rejected on sight.

- `e10.current_org()` is fail-closed: null on zero OR multiple memberships.
- Entity-class RPCs derive organization from the entity. A supplied organization
  that mismatches returns `cross_org_denied`.
- Invitation and Viewer class functions never call `e10.current_org()`.
- The append-only ledger outlives its items. No ledger-to-items foreign keys,
  ever. History reads filter by `organization_id` only.
- Idempotency receipts are scoped `(organization_id, idempotency_key)`.
- Catalog tables are platform-level and never carry an organization column.
- The `'shared'` workspace row is globally unique until CONTRACT. Per-organization
  shared rows are impossible before then.

## OPEN ITEMS

- Track A handoff records "19 RPC wrappers". The A6c plan rev 6 inventory is 14
  public inventory RPCs, 13 client delegates, 1 internal delegate, 10 internal
  helpers. Correct the handoff; the plan is right.
- Canonical anchor `874b8f40...` was recomputed only against the extracted
  directory, never the original archive. Recompute, or record as
  accepted-unverified. Every Track B chain of custody cites it as root of trust.
- `CAPABILITY_CROSSWALK.md` describes a twelve-key persisted catalog. Staging
  holds the legacy twelve plus fifteen A6b additive capabilities. Reconcile
  before PF-C2 so no new leaf is proposed for an authority that already ships.
- The A7 hostile two-organization scenario matrix should be authored once and
  consumed by both A7 and PF-C20, not written twice in two vocabularies.
- `money.read` / `cost.read` sub-organization privacy (a streamer sees only their
  own commission) cannot be expressed by organization-membership RLS. It needs
  its own design, post-A6. A capability leaf will not solve it.

## COORDINATION RULE

`BOARD.md` is the coordinating authority for both tracks. Agents read it at the
start of every run and act only within their track's Next authorized action.

- Agents propose a `BOARD.md` delta in their reports. They do not apply it.
- Agents do not mark their own gates accepted.
- Execution instructions live in `## NEXT PROMPT TO SEND`. Each agent runs only
  its own subsection there. That section is authored and replaced solely by the
  Chief Project Inspector; an agent never edits it, including to record that it
  has finished.
- Only the Chief Project Inspector reconciles state and applies gate changes,
  after independent review.
- If a required approval is not recorded in the Approvals Ledger, it does not
  exist.
- Where any other document disagrees with this board on current state, this board
  wins and the other document is corrected.