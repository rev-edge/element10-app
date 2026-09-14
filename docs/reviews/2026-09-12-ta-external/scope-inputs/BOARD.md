# Element 10 Project Board

_Last reconciled: 2026-07-27 by Chief Project Inspector (operator-lifecycle and
walkthrough protocols applied; S1.7 restructured two-phase)._

**CANONICAL LOCATION:** `/Users/tsconnely/dev/element10-app/BOARD.md`.
That file is the only authoritative copy. Any other copy of this document,
anywhere, is a non-authoritative snapshot and must not be used to decide a gate.
If a snapshot disagrees with the repository copy, the repository wins and the
snapshot is stale.

## ACCEPTANCE AUTHORITY (Trent, 2026-08-03)

**Trent accepts:** anything operator-facing — UI, UX, workflow shape, new
surfaces, and every walkthrough. If it changes what the operator sees or does,
it is his.

**CPI accepts, with the outside reviewer:** engine gates, model documents,
correctives with no operator-visible change, infrastructure, evidence and
process discipline. These are batched and never queued for Trent.

**Trent RULES (not accepts) on genuine commercial judgment** — costing method,
authority policy, catalog strategy, anything about how the business actually
operates. The CPI decides technical and consistency questions itself, including
inside model documents; their workflow consequences surface at Trent's
walkthrough, where he can still veto. Nothing operator-visible is locked in
without him seeing it work.

**Standing carve-out — production cutover (A8-A10) requires Trent's explicit
go before EXECUTION.** The plan is CPI-accepted; pulling the trigger on
production is a business-risk decision against a live operation with real
inventory and ledger history, not a review formality.

## WORKING MODEL: CONTINUOUS AUTHORIZED WORK (2026-09-07)

`docs/CONTINUOUS_WORK.md` supersedes routine sprint/checkpoint stops and
redispatch clauses throughout this board and its historical charters. Preserve
substantive dependencies, freezes, independent acceptance and production go.
Agents record execution evidence directly; acceptance ledger authority is unchanged.

## TRACK B RELAY PROTOCOL (Trent, 2026-07-27 — binding on every Design dispatch)

September 11 execution policy: `docs/AGENT_EXECUTION_EFFICIENCY.md` governs
builder-owned routine verification, milestone-based independent review,
consolidated findings and compact evidence. Continuous heavyweight supervisor
polling is discontinued. Acceptance authority, substantive gates, production
restrictions and the full Track A objective remain unchanged. This records a
process decision, not acceptance of a pending implementation batch.

Every Design relay is one self-contained, gate-specific document copied from this
board. Never instruct Design to read repository paths. Every relay carries five
blocks: (1) AUTHORITY — relay revision/date/hash, current gate, exact authorized
phase (preflight | implementation | corrective | review), accepted baseline
hashes, the ledger row relied on, explicit out-of-scope; (2) OPERATOR CONTEXT —
job, lifecycle stage, the workflow immediately before and after, entry points,
parent object, durable resume surface, relevant authority boundaries;
(3) REQUIRED WORKFLOW PLAN for new/changed workflows — journey statement,
state/transition map, per-surface action inventory, the 12 task-loop fields, the
8 case types, adjacent findings split must-close-now / later-checkpoint,
escalations; (4) EXACT IMPLEMENTATION SCOPE — enumerated changes, state-aware
actions, honest unavailable-stage handling, context preservation, forbidden
changes, standing rules written out in full (no shorthand ever);
(5) EVIDENCE AND COMPLETION — behavioral scenarios, the five walkthrough tours,
baseline + materially different adversarial passes, defect-family expansion,
separate interaction/mutator/persisted/render/boundary evidence,
screenshot/caption standards, regression + cards-off + isolation checks,
package/manifest/chain root, operator-walkthrough requirement, genuine escalation
conditions, and "Record execution progress without self-accepting." Workflow
work produces a preflight, self-reviews it, and proceeds to authorized
implementation in the same run under `docs/CONTINUOUS_WORK.md`. Relays are always regenerated whole — never incremental
amendments that depend on chat context. The test: Design could delete its
history and still execute correctly.

## OPERATOR WORKFLOW AUTHORITIES

- `docs/OPERATOR_LIFECYCLE.md` defines the end-to-end operator jobs and handoffs.
- `docs/UX_WORKFLOW_CONTRACT.md` defines workflow planning, navigation, and
  behavioral acceptance.
- `docs/OPERATOR_WALKTHROUGH_PROTOCOL.md` defines multi-pass walkthrough tours,
  evidence classes, defect-family expansion, claim discipline, and acceptance
  separation.
- These documents do not alter schema, security, capability, or gate authority.
- Every Track B relay must include the relevant lifecycle, workflow-contract, and
  walkthrough-protocol requirements verbatim when the receiving agent cannot read
  these files.

## Execution progress: September 10 expanded-vision audit

### September 10 owner authorization: expanded Track A goal

**Standing execution/publication approval, September 10:** The owner approved the pending CI-registration commit and requested no repeated routine approvals for this Track A goal. Within its defined backend scope, local edits, tests, scoped commits, pushes to `origin/foundation-a6` in `rev-edge/element10-app`, exact-head CI, explicitly targeted staging migrations/verification, and progress reporting between the coordinating and Track A Codex tasks are authorized. This includes the public visibility of those scoped code changes. Do not include unrelated dirty work or secrets. Routine checkpoint or per-commit approval requests are unnecessary. Production writes, main-branch pushes/deployments, UI work, unrelated publication, destructive operations and unresolved commercial decisions remain outside this standing approval. This does not override platform-enforced permissions.

The owner explicitly approved starting the expanded Track A backend goal via Codex after reviewing its staging-only completion boundary. The existing `Track A: Data Layer` task has received the implementation request. This reopens expanded backend implementation and isolated/staging verification, not the historical production cutover. The older parked decision below continues to govern production.

Authorized outcome: reconcile existing capabilities, then implement and empirically verify dependency-ordered backend batches for canonical identities, purchasing/inventory contracts, validated idempotent intake and lifecycle history, provisional versus posted customer/break transactions, permission-scoped reporting, and future query/action integration seams. Deliver contracts and a requirement/evidence matrix ready for UI integration. Preserve dirty work and tenant isolation; verify the target environment before remote writes. Existing tests may default to production and must not be run against that default.

Excluded: Track B/UI implementation, production migrations/writes/deployments/cutover, chatbot, live market feeds, scheduled trackers, and collector-showcase implementation. Material commercial decisions and unresolved substantive safety gates still require escalation. No independent acceptance or new implementation verification is recorded by this authorization.

### Prior audit and alignment progress

Cross-agent entry point: `docs/CROSS_AGENT_ALIGNMENT_2026-09-10.md` now defines the common source set and self-contained Track B relay. Local AGENTS.md and CLAUDE.md point to it. Cloud delivery and recipient acknowledgment remain unverified; no UI implementation or new gate acceptance is implied.

Owner authorized the audit/document/prototype sequence in voice. This entry records execution, **not gate acceptance**; existing grants, freezes and production-cutover rules are unchanged. The NEXT PROMPT section and historical acceptance rows were not rewritten.

- Read-only production/staging schema inventory completed; maturity differences recorded in `docs/EXPANSION_AUDIT_2026-09-10.md` and its database snapshot.
- Canonical Markdown source identities inventoried. Framework/roadmap/domain/lifecycle/workflow links updated additively for shared core, invoice-first receiving, source-to-sale history, card identity/screening, market evidence, wishlist/optional monitors and AI-ready queries/drafts.
- **New model risk:** PF-M5's provisional promotion composition key borrows a physical-copy duplicate heuristic that excludes year and includes serial numerator. Browser probe confirms different years collide and two copies separate. Refine catalog identity before promotion implementation; current duplicate warnings were not silently changed.
- Separate purchasing candidate under `Streaming/element10-app/review/vision-2026-09-10/` adds audience-separated comments to create/amend/detail and additive replay. R1 baseline and e10.css remain untouched. Browser evidence and delivery report are in that candidate's folder. This is memory-only prototype behavior, not cloud persistence.
- Receiving, destination authority, actual historical-cost lookup, new catalog/lifecycle schema, external feeds, chat and monitoring remain dependency-bound work in `docs/EXPANSION_FRAMEWORK.md`. No production write, migration, push, deployment or live monitoring was performed.
- Later owner clarifications are captured in framework sections 5/6/11/12 and roadmap phases 9/11/13: relational cross-catalog BI is primary; local/imported data works without feeds; board activity stays provisional with optional reviewed posting; attendance is source-labeled; grading/population/valuation provenance is explicit; collector showcase is the final deferred phase. `docs/CARD_DATA_COMPARATIVE_REVIEW_2026-09-10.md` records representative competitor inspection, not an exhaustive absence claim.
- `docs/TRACK_A_EXPANSION_HANDOFF_2026-09-10.md` is prepared and linked from the Claude entry point and docs index. Direct delivery to Claude is NOT confirmed. Track A plan reconciliation remains outstanding; this documentation capture does not unpark production cutover or claim the wider prototype work is built.

## CURRENT SYSTEM MOMENT

- [x] Product-first workflow approved
- [x] PF-0 provenance and hub gate accepted
- [x] A6c authorization plan rev 6 approved
- [x] A6c.0 additive prerequisites accepted
- [x] A6c.1 + A6c.1.1 RLS policy rewrite ACCEPTED (two independent audits; falsifiable denial proof)
- [x] A6c.2 + A6c.2.1 wrapper cutover + authority corrective ACCEPTED (outside review + CPI independent census)
- [x] A6c.3 workspace family + CAS + A6c.0 re-align ACCEPTED 2026-07-27
- [x] A6c.4 platform/identity ACCEPTED 2026-07-31 — **97-policy census CLOSED; cross-org catalog write hole shut on staging**
- [x] A7 hostile two-org matrix ACCEPTED 2026-08-03 — zero findings; matrix doc authored once, consumed again at PF-C20
- [x] **ENGINE AUTHORIZATION SERIES COMPLETE (A6a → A7).** Multi-tenant isolation designed, built, rewritten, cut over, and proven hostile-resistant on staging.
- [x] A8 production cutover plan ACCEPTED 2026-08-03 (plan only; execution needs Trent's go)
- [x] C-REHEARSE ACCEPTED 2026-08-04 — rehearsal sound, prod untouched; **6 findings carry to execution (F1/F2 material, F5/F6 added by CPI)**
- [x] A8-PREP ACCEPTED 2026-08-04 — F1/F2/F5 closed and CPI-verified (checksum reproduced independently); **F6: P4 is EFFECTIVELY IRREVERSIBLE — recovery is backup-restore + coordinated client revert, incident-level**
- [ ] **A8-DRILL2 - CURRENT TRACK A WORK** (rehearse P4/P5 recovery AS a backup-restore drill; exercise lock contention with concurrent writers) — the last two things standing between the plan and an execution proposal
- [ ] **THEN: execution go/no-go — Trent's explicit decision, with P4 irreversibility on the table**
- [ ] ~~superseded~~ CHECKPOINT C-REHEARSE (full P0 rehearsal on a scratch restore: capture, prove, all 36 migrations, rollback drills, idempotency; production untouched throughout)
- [ ] **CROSS-TRACK: PF-M5 curation path blocks A8-P5** — the catalog hole cannot close in production until it ships
- [x] PF-C1 Product Master accepted
- [x] PF-C2 Product Configuration accepted
- [x] Human walkthrough of the combined PF-C1 + PF-C2 Product workflow — DONE, feedback captured
- [x] PF-C2.1 configuration model corrections accepted
- [x] PF-C2.3 + PF-C2.4 document-driven setup accepted
- [x] Operator review of the setup flow — exceptions confirmed correct, three additions requested
- [x] PF-C2.5 NOT ACCEPTED (3 defects)
- [x] PF-C2.6 ACCEPTED
- [x] PF-C2.7 NOT ACCEPTED (grid prefs crossed the org boundary)
- [x] PF-C2.8 ACCEPTED
- [x] PF-C2.9 NOT ACCEPTED (marking did not paint)
- [x] PF-C2.10 NOT ACCEPTED (a no-op discharged a blocking decision)
- [x] PF-C2.11 ACCEPTED
- [x] PF-C2.12 NOT ACCEPTED (stale DOM on return; miscaptioned evidence)
- [x] PF-C2.13 ACCEPTED with finding (evidence captions)
- [x] **Operator approval of the product setup flow — GRANTED. "That screen flows well."**
- [x] D1/D2 retro-audit of screens 00-07 — DONE. Findings retargeted as PF-C21 regeneration requirements, NOT a work queue. See `Element10_D1D2_RETRO_AUDIT.md`.
- [x] ~~PF-R1..PF-R7 retro-review sequence~~ **WITHDRAWN 2026-07-21, CPI error.** The approved `PRODUCT_FIRST_WORKFLOW.md` §11 already rules that screens 01-07 are "accepted pre-pivot evidence", implement no PF-C checkpoint, remain frozen, and are replaced by PF-C21's global regeneration. The CPI created a seven-gate sequence duplicating PF-C21 and contradicting an approved document it had already read, and put a scheduling question to the operator that the plan had already answered. Operator confirms screens 01-07 are artifacts only with no interim reliance. They stay frozen and untouched.
- [x] PF-C3 + PF-C3.1 Vendor identity ACCEPTED (source audit + operator walkthrough)
- [x] PF-M2 singles model DELIVERED + CPI-audited: substance sound. NOT approved — one dead state, two operator rulings to fold in.
- [x] PF-M2 + PF-M2.1 singles / graded / repack model APPROVED
- [x] PF-C-S1 + PF-C-S1.1 CardInstance + Acquisition ACCEPTED (source audit + walkthrough)
- [x] PF-C-S1.2 serial split ACCEPTED (walkthrough; incl. self-caught cross-org `#ovhost` leak fix, CPI-verified against prior build)
- [x] PF-C-S1.3 NOT ACCEPTED (typing rendered backwards)
- [x] PF-C-S1.4 caret fix ACCEPTED (proven in operator use — in-order text in the walkthrough screenshot)
- [x] PF-C-S1.5 NOT ACCEPTED (picker rows unclickable) · PF-C-S1.5.1 fix ACCEPTED — both GRANTED as a pair
- [x] PF-C-S1.6 ACCEPTED (source audit + CPI behavioral run 18/18 at operator direction)
- [x] ~~PF-C-S1.7 CURRENT TRACK B GATE~~ **ACCEPTED 2026-07-27** — stale line corrected 2026-08-11 (5th instance of the CPI stale-board defect)
- [x] ~~PF-C-S1.5 walkthrough findings~~ superseded and closed in the S1.5.1 pair
- [x] PF-C-S2 cost assignment ACCEPTED · S2.1 / S2.2 / S2.3 ACCEPTED · PF-M3 Listings ACCEPTED · S3 disposition ACCEPTED as C-SELL.1
- [ ] **C-POLISH — CPI audit passed 2026-08-11, awaiting OPERATOR acceptance** (walkthrough script delivered)
- [ ] **THEN Track B singles: S4 repack → S5 margin reporting** — closes the singles arc
- [ ] Carried into the next Track B charter: **F1 bulk-selection scope disclosure** + Escape-on-dirty-form no-op
- [ ] PF-C4 onward (sealed-product purchasing) - independent of the singles sequence, either order
- [ ] PF-C4 onward (purchasing) - unaffected by the PF-M2 gap, sealed product only (a product must complete setup before it can be ordered)

## TRACK A PARKED — and the plan's core premise is now in question (2026-08-24)

**Trent: "I am not even using the tool for breaks for another two months. Why
would I do it now?"** He was right and the CPI was wrong to push toward
execution. Track A is stood down deliberately. Nothing is blocked; there is
simply no reason to cross an irreversible boundary for a benefit that does not
arrive until there is a second tenant.

**Three reasons execution is not scheduled:**

1. **No urgency.** Nothing in the build queue needs production migrated. Track B
   is entirely prototype; B5–B7 (the real app) has not started. The catalog write
   hole is real but bounded — single-tenant means no cross-tenant exposure today.
2. **P5 cannot run anyway.** It stays blocked until PF-M5's curation path ships
   and the client uses it, which is unbuilt Track B work. Executing now would
   take the irreversible P4 step and still leave the hole open — the irreversible
   cost for a partial result.
3. **The plan is engineered for a constraint that does not currently hold.**

**PREMISE FINDING (CPI, must be resolved BEFORE any future execution):** plan §12
states "the ADR records a 24/7 SLO with no maintenance windows; this plan
achieves zero-downtime (all phases online), which is why the
expand→backfill→promote→contract discipline" exists. **That SLO is false during a
dark window.** The four-phase discipline, the `lock_timeout`+retry guards, the
coordinated client deploy, the observation windows, and much of why P4 is
irreversible at all are there to avoid taking the system down. **If a maintenance
window is available, a materially simpler and safer migration is possible than
the one we rehearsed.** A8 must therefore be RE-EXAMINED against the actual
downtime tolerance at execution time, not simply executed as written. The
rehearsals (C-REHEARSE, A8-PREP, A8-DRILL2) remain valid evidence and are not
wasted — they prove the hard path works, which bounds the risk of the easy one.

**Carried into whenever execution is scheduled:**
- Cut over against the backup clock (~04:00 ET, just after the daily physical
  backup) — reduces the exposure window from ~19.5 h to minutes at zero cost.
- Supabase backups EXCLUDE Storage objects; a restore does not return images.
- PITR is OFF; the standing trigger to enable it is the **first paying tenant**,
  not affordability (Trent, 2026-08-24).
- Re-examine the premise above before adopting the rehearsed phase structure.

**Best use of the dark window is NOT the cutover.** It is B5–B7 — turning the
prototype into software running against the database. Largest unscoped item on
the board, needs zero production contact, and a quiet period is exactly when it
should happen.

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
| REVIEW-2026-09-07-APPROVAL-IDENTITY corrective | **CORRECTED — candidate delivered, NOT self-accepted** | CPI | 2026-09-07 | Dispatch package `element10-review-handoff-2026-09-07-v1` verified two ways: its own `verify_package.py` (89 entries) and an independent `shasum -c MANIFEST.sha256` (**89/89 OK, zero failures**). Pinned source confirmed byte-identical to the granted B6 build `abbb3c1f…` (386,386 B) and the frozen CSS `cd37cd43…`. **Fix:** actor **identity** is now a stable id (`ACTORS` registry, `poActorId()`), with role and display name recorded as **snapshots taken at the time of the act** (`actor_ref`/`proposer_ref` = `{actor_id,name,role}`). All **four** comparison sites converted from string equality to id equality — the two mutators (`approvePO`, `approvePoAmend`) and **the two display warnings**, which the review correctly flagged and which a mutator-only fix would have left lying to the operator before the click. `poActor()` survives as display-only and is explicitly commented as never compared. **Legacy handled honestly:** an event with no `proposer_ref` yields `self_approved: null` with `identity_known: false` and copy stating independence is NOT established — it never fabricates a false independent approval, which was the original defect's whole harm. **Required matrix, 8/8 across BOTH approval paths:** same person unchanged role → true · **same person Manager→Admin → true (the reported defect, now correct)** · same person renamed mid-flight → true · different people with distinct ids in the SAME org → false · different people different roles → false · legacy unknown → null. Two-actor cases use genuinely distinct ids in one organization (a `Sam` fixture added to org A), not an org switch or a label change, exactly as the package required. **The supplied probe behaves as the package predicted and warned:** its REPRO assertion PASSES on the baseline and now **FAILS on the candidate** — the package was explicit that its pass must never be cited as a post-fix regression, and it is not. **Regression, all green:** canonical sweep 162 records with the same 5 known org-A false positives as baseline · threshold family 5/5 · status gate 5/5 (proposed/rejected/cancelled zero, open and pending-last-approved contributing) · capability separation still refused at the mutator · stale revision refused · double approval refused · cross-org refused · `poAuditReplay` still matches · **`e10.css` byte-unchanged**. Candidate `Streaming/element10-f3-candidate/08-product-workspace.html` `8f3080626995afe59074df1d6e32a99431d54d69b1acb16c342b34fee6af97ce` (389,906 B); regression `identity_regression.js` `c55c096e…` (4,610 B). **NOT self-accepted and NOT B7 acceptance** — approval-integrity claims for B4/B5/B6 are now supportable where they were not, but operator visual/business-fit review of the UI phase remains outstanding. |
| **F3 approval identity — CPI AUDIT MISS, reopens B4/B5/B6 correctness** | **DEFECT CONFIRMED — outside review, CPI-reproduced** | CPI | 2026-09-07 | Outside review artifacts (`element10-review.md`, `element10-approval-probe.log`, `element10-approval-review-probe.js`, `element10-claude-handoff.md`, `element10-uiux-plan.md`, `element10-review-evidence.json`, `element10-workflow-draft.patch`). **The defect: `poActor()` returns `cur().user+' ('+cap().role+')'` — actor identity FUSED WITH ROLE — and both approval paths compare that string (`const self=proposer===poActor()`).** CPI reproduced independently against the granted B6 build: Maya proposes as `Maya (Manager)`, the same person approves after a role change as `Maya (Admin)`, and the approval event records **`self_approved: false`**. **The record therefore reads as INDEPENDENT two-person approval when one person did both.** That is verbatim the failure the B2.1 charter declared unacceptable — "an unmarked approval that reads like two-person control but was one person… A record that lies about a control is worse than an absent control." The converse also follows from the same root cause: two distinct people whose display string collides would be falsely marked self-approved. **CPI SELF-ASSESSMENT — this is an audit miss, not a builder failure.** At B4 I verified `self_approved:true` when proposer and approver matched and treated the stamp as proven. I never tested the same person under a changed role, never tested a genuinely different approver, and never read `poActor()` to see identity and role were fused. **I tested the positive case and called the control verified — the same method error as the C-SELL audit, where I checked the claims made rather than attacking what the model required.** The builder's implementation followed the charter as written; the charter said "stamp self-approval" and it does, for the one case anyone tested. **Severity, stated honestly:** authority is unaffected (capability checks are separate and verified sound); expected supply, conservation and the ledger are unaffected; a single operator who never changes role sees correct stamping today. It is an **audit-record integrity** defect, which matters precisely when someone is inspecting controls. **Consequence: B4/B5/B6 remain GRANTED for their capability and arithmetic claims, but no claim of approval-integrity or full PF-C4 correctness may be made until F3 is corrected.** Corrective: separate a stable actor identity from role/display snapshots; role change must not alter self-approval detection; a distinct actor must not be matched. Preserve the permitted single-operator self-approval policy. **Note on the supplied probe:** its "REPRO" assertion expects the BAD behavior, so its passing must never be cited as a regression pass after the fix — it has to be inverted to assert correct identity handling with positive and negative actors. |
| B6 PF-C4 — expected supply + cost surfaced (sprint) | **GRANTED** | CPI | 2026-08-31 | Build `abbb3c1fde17bf342449f8853e59611d9298c4a1cdbabeb1bce824d63b81d358` (386,386 B); `PF_C4_B6_EVIDENCE.md` `9429d5367f2e2612caa727d8930cf83f5dfea8ea93963d231e0ccaaef905ddec` (7,059 B). Hashes in-message. `e10.css` re-verified frozen. **The charter named the mixed-status rollup as the single highest risk — a summary view is where an excluded row sneaks back in — so the CPI built the five-state org independently rather than reading their number.** One org holding open + proposed + rejected + cancelled + open-with-pending-increase simultaneously: **rollup = 7**, being the open PO's 4 plus the pending PO's last-approved 3, with **its proposed 27-unit increase correctly excluded**. Under transitions: approving the proposed PO added exactly its 5 → 12; approving the amendment added exactly the increase → 39; the excluded states never contributed at any point. The gate is a single point (`poExpectedOpen` keying on status) rather than duplicated per surface, which is why it holds. Excluded work renders as "Not counted" rather than being silently dropped — the operator can see what is not in the number. **Expected cost is labelled "never cost basis" on the surface itself** (I14 preserved). **Their Attention claim was source-checked before being made** — they grepped, found the build has no Attention surface, quoted DOMAIN_MAP's "derived, never manually curated", and shipped a Needs-attention strip plus a live nav badge while honestly marking the full queue a later checkpoint. That is the B2 lesson applied without being told again. B6-F1 self-found and fixed (nav badge staleness on mid-session mutations, verified across ⏳2→⏳1→0). **CPI incidental verification: the duplicate guard works as designed** — same vendor plus same order date warns and links rather than blocking (the cert-dup pattern), which is what broke my first probe until I answered it. **B6-F2 (CPI, harness, third gap this arc and all three mine): the canonical sweep visited only list surfaces, never detail pages** — which is exactly where the org-authored PF-C2 unit names they disclosed ("360 cards", "Base unit: card") render. Extended with a **core-org detail-page scan**; a genuine core org (Cascade Supply Co) is clean across product, vendor and PO detail. Their disclosure is therefore confirmed as the accepted false-positive class, not a leak. **Method note worth recording: my first version of that guard passed VACUOUSLY** — it tested `pf.cardsOn()`, which is not exported, so `!(undefined)` was true and the premise "cards are off in the core org" passed while proving nothing. Same failure shape as the innerText bug. Rewritten to read the value `scanCardsOff()` actually returns, and the premise is now asserted (`cardsOn=false`) before the scan is trusted. **A guard that cannot fail is not a guard.** Sweep now 162 records; the 5 failures remain the known org-A entitlement-off class. `selfdebug.js` → `4566cb42138db22b59cf6c0c86192f98f55a2b32694f142c49ecd3ab940446fc` (12,550 B); `e10_harness.js` unchanged. **PF-C4 build work is COMPLETE — B7 is evidence plus the operator's first purchasing walkthrough.** |
| B5 PF-C4 — PO detail + amendments (sprint) | **GRANTED** — with a scope-and-verifiability flag on out-of-charter activity | CPI | 2026-08-31 | Build `8e42b9f95133febee0d8f218a60074eae178aa789e352890429c579674635c21` (380,285 B); `PF_C4_B5_EVIDENCE.md` `aec0de9d220e0a3b65c22bbdc5dfdf7cfc84b120608bd51439ad26a0b114c19e` (7,018 B). Hashes in-message. `e10.css` independently re-verified frozen at `cd37cd43…`. **CPI re-ran the fixed canonical harness (158 records; the 5 failures are the known org-A false-positive class, verified) and confirmed a genuine core org is clean across all six routes with the live term scan.** **The §3.6 amendment design is the strongest part and every claim held under attack.** A money-increasing amendment on a committed PO enters `open_pending_amendment`; **the PO is held at last-approved content and the increase contributes ZERO expected supply until approved** — CPI verified expected supply stayed at 4 while pending and rose to 10 only on approval. The pending amendment carries **its own revision**, and `po.revision` advances only when an amendment is approved, so the PO's revision always reflects approved content rather than a proposal — a cleaner separation than the charter asked for. A decision drawn on a stale amendment revision is refused. Amendment approval is guarded by `purchasing.approve` **at the mutator** (the `manager` scenario is refused), not merely in the UI. `poAuditReplay` re-derives the PO from its event stream and matched the maintained fields after every scenario cluster including cancellation — that is a genuinely strong self-check to have built unprompted. Cancellation is events, never deletion: the row survives, ordered history is retained on the line (`qty=4, cancelled=4`), expected supply goes to zero, a second cancel is refused as terminal, and the event records `dropped_pending` ops when cancelling over a pending amendment. Cancel is correctly treated as money-decreasing and takes no approval, matching the ruling. **The §4 bounded claim was honored exactly as required:** reduction-below-net-received is enforced in the writer but proven only against `net_received = 0`, and the evidence says so rather than overclaiming. **CPI method note: three of my probe failures were my own** — I used `po.revision` where the amendment carries `po.pending.revision`, and I set `unit_price` where the form field is `price`. The second error incidentally exercised the unknown-cost path through the live form and it correctly failed toward control. Verified before claiming, per standing rule. **FLAG B5-F1 — NOT a defect in the deliverable, but recorded because it is a governance and reachability problem.** The delivery closed with a paragraph describing a design-system toolchain: `check_design_system` passing, "bundle compiles, 19 components, 23 cards, 88 tokens, manifest in sync", node harness scripts moved from `build/harness/` to `_scratch/harness/`, and 8 legacy `@startingPoint` tags proposed for conversion to `templates/<slug>/`. **CPI searched the repo and the shared folder: `startingPoint`, `check_design_system`, `_scratch`, and `build/harness` do not exist in either, and there is no `build/`, `_scratch/` or `templates/` directory.** The canonical harness at `tests/harness/` is intact and hash-correct, so nothing the CPI depends on was disturbed. This may be a builder-side environment the CPI cannot see — that is plausible and no accusation is made — but **it is outside the B5 charter's scope, it moved files, and it is unauditable from here**, which is the same class of problem standing rule 15 exists to prevent. The charter's hard stops include "you are about to touch anything frozen or out of scope." **The `@startingPoint` conversion is DECLINED pending grounding**; the builder correctly asked rather than self-authorizing, which is the right conduct and is credited. **B5-F1 RESOLVED same day.** The builder grounded it plainly: a builder-side design-tool environment with its own asset compiler, which was wrongly ingesting the node harness scripts; only its **local working copies** moved, `build/harness/` → `_scratch/harness/`, bytes unchanged, and it reported post-move hashes **exactly matching the canonical values** — `f2a1729a…` (3,946 B) and `2b525e25…` (10,407 B) — which the CPI had already verified independently at `tests/harness/`. Nothing in the repo or shared folder was involved; the `@startingPoint` conversion is dropped. **The grounding produced something more valuable than the flag: the relay topology (standing rule 15) — the builders cannot write to the repo or the shared folder at all.** That is the real root cause of the PF-M5 "delivered but not reachable" cycle, and it was never misreporting. Rule 15 updated accordingly. No fault recorded against the builder for B5-F1. |
| B4 PF-C4 — PO create + commit loop (sprint) | **GRANTED** | CPI | 2026-08-31 | Build `5eb5c10fc444829848558094465d15aae3ad2f7bcb892769726c32976fa72bca` (357,183 B); `PF_C4_B4_EVIDENCE.md` `348345702d27adceeee6b2de8d8e1a5e48cfef62aeb95ad193a5cf255842396c` (5,688 B). Hashes supplied in-message. **`e10.css` independently re-verified at `cd37cd43…` — still frozen; twenty-one accepted editors now.** First implementation sprint of the inventory arc. **CPI re-ran the CANONICAL node harness rather than accepting the disclosed in-browser equivalent, then attacked every claim with its own scenarios.** Threshold family, 6/6: zero cost, unknown cost, and exactly-at-threshold all require approval; one cent below commits; unset threshold requires approval on everything. Every branch fails toward control, and the refusal strings explain *why* rather than just refusing. **B4-F1, which the builder self-found and fixed (zero-cost PO committing on save), is genuinely closed and the family was expanded — CPI verified the `≥` boundary and the one-cent-below case independently.** **B3-F1 honored:** a `proposed` PO contributes 0 expected supply, a `rejected` PO contributes 0, a committed PO contributes — the status filter is in the derivation as required. **Authority separation proven AT THE MUTATOR, not the UI**, using the `manager` scenario (purchasingWrite true, purchasingApprove false): `approvePO` refuses with "no approval authority (purchasing.approve)", `rejectPO` refuses identically, and the PO remains `proposed` after both denied attempts. `readonly` holds neither. Stale-revision approval refused with the revisions named; a committed PO cannot be approved twice; cross-org approval from org B refused. Self-approval is stamped, not silent: the event carries actor, proposer, revision and `self_approved:true`. **TWO TOOLING FINDINGS, BOTH THE CPI's OWN FAULT, both fixed here.** **B4-F2 (material, and it invalidates prior evidence): the canonical node harness's cards-off TERM scan has been VACUOUS since inception.** `scanCardsOff()` reads `el.innerText||''`, and **jsdom does not implement `innerText`** — it returns `undefined`, so every host read as an empty string and the scan could never produce a hit. Every "[cards-off @ X] scan clean" PASS the CPI has reported from the node harness — across S2.2, C-SELL.1, C-POLISH and this sprint — proved nothing. Fixed by polyfilling `innerText`→`textContent` in the harness `beforeParse`. **Re-run with a live scan: a genuine core org (Cascade Supply Co) is clean across all six routes with zero hits — the tenancy invariant is now actually proven rather than vacuously passed.** The five failures that appear on org A with entitlement toggled off are the accepted S2.2 false-positive class and are now *visible and explicable*: `breaks` is the organization's own name ("Rip City Breaks") in the chrome, `baseball` is a product sport-category chip. The cards-off **DATA** checks were never vacuous, so the stronger invariant (no vertical rows in a core org) always held. **Credit where it is due: the builder's disclosed deviation to an in-browser sweep was, for this specific check, BETTER than the canonical tool** — a real browser has `innerText`, which is the only reason their F0 (`chase` matching inside `Purchase`) was findable at all. That deviation earns credit, not a ding. **B4-F3: the canonical `selfdebug.js` surface list did not include the new PO surface** (`#pos`), so the CPI's first green 134 never rendered the screen under audit. Extended; the sweep is now 158 records with the PO surface covered — typing forward, caret surviving self-rerender, dialogs dismissing on Escape, status filters live. **CPI self-assessment: I reported 134 green and came close to treating it as meaningful before checking either whether the sweep reached the new surface or whether its scan could read text at all. A green sweep that visits nothing and reads nothing is not evidence.** Harness fixes propagated to `tests/harness/` — `e10_harness.js` `f2a1729a…` (3,946 B), `selfdebug.js` `2b525e25…` (10,407 B). |
| B3 PF-C4 preflight — purchasing (sprint) | **GRANTED** — planning only, one condition carried to B4 | CPI | 2026-08-31 | `PF_C4_PREFLIGHT.md` `9adc58ca207124766b27adbeb858cc315ac822779a59ebf6f696623287141944` (14,847 B) — **hash computed by the CPI; the delivery message omitted it. Second rule-15 lapse in three deliveries, after B2.1 got it right.** Files were reachable and correct so no harm resulted, but the reviewer should never have to guess which bytes were reviewed. All twelve contract fields present and verified individually; surface action inventory covers PO list/create/detail plus two additive entry points; seven lifecycle scenarios planned. **CPI attacked the citation, because citing an existing source as support is the shape that failed at B2. It held.** The claim that a PO stays location-free with the receipt choosing the location cites PF-M4 §A2, and §A2 genuinely supports it: whole-lot-only was argued down partly because it "would need per-destination PO lines" and would require "guessing the split before it happens." A location-bearing PO is precisely what the GRANTED position model rejects. **Substance is sound.** I3: a PO line binds the **configuration version id** at creation so a later conversion change cannot restate what was ordered, with explicit re-binding visible as an amendment event. I4: `expected_open = ordered − received − cancelled`, derived at read time, never stored editable; cancellation zeroes the remaining expectation while ordered/received history stands — which is exactly what PF-C5's fixed downstream rules require, and reduction below net received is refused at the amendment writer. I14: expected cost is a labelled expectation that never becomes basis and never shares a field with COGS, preserving the lot-level actual costing ruling. `purchasing.write` is distinct from every inventory capability with seeds stated, so a person who may edit inventory cannot thereby commit the business's money. Amendments are additive events with I8 discipline applied by choice. **§4.8 is exactly the conduct the corrective was meant to produce:** the PO-approval question is raised and explicitly NOT decided, with the sentence "The B7 mechanism existing is not the ruling, and this preflight does not treat it as one." A recommendation is given with consequences stated both ways. **CPI FINDING B3-F1 (condition on B4, not a defect here): the "no rework" claim is slightly overstated.** §4.8 says the seam is contained because the status field and event stream carry either answer, but §4.4's derivation `ordered − received − cancelled` has **no PO-status filter**, while §4.8 says that under an approval ruling "expected supply exists only from approval." Those are inconsistent: adding approval later would change the derivation's input set. **Binding on B4: write the expected-supply derivation to filter on PO status from the outset** — then the claim becomes true and an approval ruling costs nothing. **PO-approval ruling is now with Trent; B4 does not begin until it is answered.** |
| B2.1 PF-M4 approval mechanism (sprint) — **PF-M4 COMPLETE** | **GRANTED** | CPI | 2026-08-31 | `PF_M4_LOCATIONS.md` `d576aa31330fbeefd981ffd25549ff6bf5d4004e098423fb61610db970d911c9` (29,410 B); `PF_M4_COVER_NOTE_B2_1.md` `ffb7843f4f66d627d7580f48a06418ffbdb2215170a58939e0aee53f1843d52d` (3,969 B). **Hashes supplied in-message — the rule-15 lapse from B2 is corrected.** The false §B4 paragraph is replaced, correctly attributed to the 2026-08-31 ruling, and now states plainly that the approval dimension is absent today (citing `DOMAIN_MAP.md` line 44 `✗ missing`) and is a required build. **CPI attacked three things; all three held.** (1) **Two pending transfers against the same stock, both approved → over-transfer.** Handled, and handled honestly rather than by pretending pending stock is locked: a `proposed` transfer is intent only with zero ledger effect, so "pending stock can be reserved or transferred away in the meantime; approval therefore does not guarantee execution" — on approval the writer re-runs the full §B1 validation including the free-stock check, and a now-failing transfer moves to a **blocked state with a Recovery item, never a partial posting.** That is better than reserving at proposal, which would have created a fourth position and complicated conservation. (2) **Conservation under pending.** Holds trivially by construction — a pending transfer touches no term of the equation because positions only change when the writer posts movements and it posts none before approval. (3) **The cited precedent, which is the exact claim-shape that failed at B2.** `approve_checklists` and `approve_preparation` verified present in `DOMAIN_MAP.md`, `SECURITY.md` and `decisions/0005-tenant-spine.md`; `approve_inventory` and `transfer_inventory` are correctly declared new rather than smuggled in as existing. **Single-operator resolution is exactly right and slightly better than the CPI asked for:** self-approval permitted, `proposer = approver` derivable AND stamped `self_approved` at write time, audit and Attention surfaces reporting self-approvals distinctly — "the record never reads as two-person control when it was one person… excluded by construction, not by policy." `require_distinct_approver` defaults off so a one-person org works out of the box, and receiving is never blocked. **Everything fails closed:** threshold trigger is `≥` so the boundary falls on the controlled side; unknown or zero cost basis is treated as above threshold; **unset threshold means every transfer requires approval** — an org opts into a threshold, never out of the mechanism. Revision binding genuinely generalizes the preparation states rather than flattening them: approval binds to a revision of the proposal's content, and editing anything material marks a prior approval `stale`. Correct scoping on what needs sign-off: late arrival and return-to-source need none because they destroy no value. Ledger gains no FK to approvals — refs are values. **Residual, non-blocking:** a write-off left pending indefinitely leaves the missing unit counted in-transit and inventory value overstated; the model surfaces it as an open transfer remainder with a Recovery item rather than hiding it, which is adequate, but aging or escalation of stale Recovery items is unaddressed and should be picked up at PF-C6. **PF-M4 IS COMPLETE. PF-C4 IS UNBLOCKED.** |
| B2 PF-M4 part B — movement between locations (sprint) | **NOT ACCEPTED** — superseded by B2.1 | CPI | 2026-08-31 | `PF_M4_LOCATIONS.md` `0f564fb336634996781c03b4d3ba95b8a9e78765991fb9567b545ea8df653a49` (23,553 B) — **hash and byte size computed by the CPI, not supplied: the delivery message omitted them, a standing-rule-15 lapse (minor; files were reachable and correct).** **Most of part B is strong and is NOT what fails.** B1-F1 applied correctly with the S2.3 precedent cited and ledger primacy made explicit. **§B3 in-transit is the best section:** it takes the third-position question head-on and names why each alternative fails — counting at source "would let it be re-reserved at a facility that cannot pull it," counting at destination "would let Store B confirm against a truck," neither breaks conservation. It uses DOMAIN_MAP's **custody** axis for `in-transit` while correctly reserving `pending-transfer` for actual ownership change (consignment), inventing no parallel vocabulary, and restates conservation as **Σ facility + Σ in-transit = ledger-derived `lot_on_hand`**. **CPI attacked the in-transit reservability race and it was already closed** — dispatched units sit in no facility's free pool. The CardInstance union counts custody first so nothing double-counts. Capability vocabulary verified real: `reserve_inventory`, `create_receiving`, `resolve_recovery` all present in DOMAIN_MAP; naming a new `transfer_inventory` inside that scheme is legitimate. **REJECTED ON ONE CLAIM, and it is a dodged hard stop.** §B4 closes: "DOMAIN_MAP's approval dimension is already org-configurable and risk-based (`Not-required / Proposed / Approved / Rejected / Stale`)… **This is why no commercial ruling was needed:** the existing framework makes sign-off an org setting, not a model constant." **CPI checked DOMAIN_MAP.md line 44 directly. The Approval-state row's "what exists today" column reads `✗ missing`.** It is a recorded GAP, not an existing framework — every other row in that table names a real store (`JSONB workspace`, `relational (e10_live_sessions…)`). **Second defect in the same sentence:** the real states are `Not-required / Proposed-vs-vN / Approved-for-vN / Rejected / Stale`. The delivery dropped the `-vs-vN` and `-for-vN` suffixes, and that version-binding is precisely what makes it a *preparation-snapshot* approval mechanism rather than a general-purpose one for transfers and write-offs. **Charter §5 named this exact case a HARD STOP** ("a commercial ruling is needed — e.g. whether a transfer needs approval, whether shrinkage needs sign-off"). The agent declined the stop by deferring to a framework that does not exist. **Consequence if inherited:** PF-C4 and PF-C5 would be planned against a non-existent approval mechanism, and whether a shrinkage write-off needs sign-off — a genuine internal-controls question — would be silently answered as "org-configurable, later." **Corrective B2.1 issued, and it cannot be closed without an operator ruling; the question is with Trent.** Everything else in part B stands and is not to be relitigated. |
| B1 PF-M4 part A — inventory positions (sprint) | **GRANTED** | CPI | 2026-08-24 | `PF_M4_LOCATIONS.md` `f64cf8d2daa1eeaea54c9bb85475faa56f106d19e8c679e8d5a2e7c9c206e4fe` (11,401 B); `PF_M4_COVER_NOTE_B1.md` `9063677d5de367886d1c4e3b20a56d9bbfdb4c9b2267d479167def5a6a0499ce` (3,171 B). Both verified exact before reading. **Position ruling: per-location balances on a shared lot** — a `LotPosition` row per (organization, lot, location), lot identity intact, maintained in the same transaction by the same single guarded writer that appends the movement, with a new conservation invariant **Σ LotPosition.on_hand over a lot = ledger-derived `lot_on_hand`**, the writer refusing on mismatch. **Both alternatives were argued down with named costs rather than assumed away, which is what the charter demanded.** Child-lot splitting: additive cost events would fan out pro-rata across children and re-prorate on every re-split, making cost basis path-dependent — fatal, since splitting is the common operation. Whole-lot-only: cheapest model, but forces either artificial per-destination lots guessed at the dock or a ban on partial transfers, and 12 boxes received centrally then sent 6/6 to two stores is the operator's stated reality. Cost of the chosen model stated honestly: one new table, one new invariant, a location argument on every mutator. **Nonfungible case resolved cleanly:** CardInstance keeps a single `current_location` rather than a quantity-1 position row, argued on the grounds that the apportioning dimension positions exist for does not exist for an instance; the two mechanisms unify at the reporting boundary as a union, not by special-casing either. **Ledger discipline verified intact** — location is a plain recorded value on the movement, no FKs to items OR locations, history still filters by `organization_id` only, and a renamed or archived location never rewrites history. **Migration seam sound:** default location never a null state (null would break the "every unit in exactly one place" summation and leave a null branch in every mutator forever), backfill posts an additive zero-net attribution movement per lot so as-of replay has a defined start, and a single-location org's arithmetic degenerates to PF-M1 exactly. Pre-migration history is resolved to the default location and **labelled** rather than rewritten. **CPI FINDING B1-F1 (minor, classification not behavior, carried into B2):** the document calls `LotPosition` a *stored fact* in §A5 and §A4 while §A6 correctly calls it "a maintained current-state component, never the historical source," and §A5 itself states `lot_on_hand = Σ positions = Σ movements` — which makes positions **reconstructible from location-attributed movements, i.e. a maintained projection with a conservation audit, not an irreducible fact.** The behavior described is correct either way (ledger is historical truth; the writer enforces conservation), but the S2.3 precedent demoted `total_paid` from fact to cache with a single writer precisely so no future reader would trust the maintained row over the ledger. Same treatment applies here: name it a cache/projection. **Relay finding, credited to the builder and FIXED by the CPI:** the shared folder held a 2026-07-27 `BOARD.md` snapshot lacking the sprint-model section the dispatch cited. The agent noticed, proceeded on the self-contained charter, and reported it rather than following a superseded working model. Second stale-copy trap in the shared folder after the pre-relational clone; renamed `STALE_docs_snapshot_jul27__DO_NOT_READ` with a warning file. **Charter boundary respected** — reservation locality, transfers, in-transit and permissions all correctly deferred to B2 with fields prepared but no semantics asserted. |
| A1 recovery measurement (sprint) | **GRANTED as chartered — objective Q2 remains open on an OPERATOR COST DECISION** | CPI | 2026-08-24 | First sprint under the time-boxed model. Ran ~4 minutes and ended at the §4 cost boundary. **Conduct was correct and is the point of the row:** the agent refused to provision a paid restore target, did not rationalize the spend as small or temporary, and delivered a partial answer honestly rather than an unauthorized charge. Production re-proven untouched (12 migrations, head `20260716110000`, canonical ledger `f54a1fe9…`); nothing provisioned, so nothing to tear down. **Q1 answered, and it is the finding that matters.** Org is on Pro: daily backups, 7-day retention. PITR is a separately-priced add-on. Prod shows `archive_mode=on` with WAL-G `wal-push` and `wal_level=logical`, but the agent correctly refused to read continuous WAL archiving as proof the add-on is purchased — that machinery is platform-standard. The `pitr_enabled` flag lives behind a dashboard/API endpoint neither the agent nor the CPI can reach, reproducing the CPI's original inability to confirm it. **CPI verified the pricing the agent lacked: PITR is $100/month per 7 days of retention and additionally requires at least a Small compute add-on; enabling it STOPS daily backups because it supersedes them.** Q2 blocked: `restore_project` restores in place, which is a production write and forbidden; a branch carries no production data and is unfit for a restore measurement at any price; a new project is ~$10/month. Q4's client-revert half WAS measured — full CI pipeline ~200 s plus Pages propagation, so **4–6 minutes for the client and `SCHEMA_VERSION` revert to go live**, dominated by the test suite. **CPI RE-FRAMES THE DECISION, because the agent conflated two costs an order of magnitude apart.** It presented a $10/month measurement question. The real question is whether to run an irreversible migration on a 24/7 live-commerce business with **an RPO of up to 24 hours** (daily-backup-only) or spend $100/month to reduce it to minutes. Timing is how long the business is down; RPO is how much is permanently lost. The second dominates. Free next step: the operator confirms PITR status in the dashboard in ~30 seconds, which decides whether the $10 timing measurement is even worth authorizing. **CPI FAULT, recorded: the charter sequenced the expensive question (Q2, measured timing) ahead of the free one (Q1, RPO), when the free one carried the larger risk.** The agent effectively resequenced and salvaged the sprint. Standing correction: charter gates cheapest-first, so a cost boundary cannot strand the cheap finding behind the expensive one. **RESOLVED 2026-08-24 — CPI confirmed Q1 directly in the dashboard with the operator signed in. PITR IS NOT ENABLED.** The Point-in-time tab reads "Point in Time Recovery is available as an add-on" with an Enable button. Production runs on **daily physical backups only**, 8 retained, observed timestamps `07:2x UTC` daily (≈**03:25 ET**). **Therefore the real RPO is not an abstract "up to 24 hours" — it is time-since-03:25-ET.** A failure at 23:00 ET on a Saturday loses ~19.5 hours, which for this business is an entire streaming day of sales, movements and inventory state. **SECOND FINDING, previously unflagged by anyone: the backup page states "Database backups do not include objects stored via the Storage API"** and that restoring does not restore objects deleted since. Element 10 stores **card images and team logos in Storage** (`pickImage` → Storage upload → public URL). A database restore therefore returns rows referencing image objects that were never in the backup — the two stores can diverge, and any image deleted post-backup is unrecoverable. This belongs in the execution-gate requirements alongside the RPO number. **CPI RECOMMENDATION (free, and it dominates the $100/month option for a one-time cutover): schedule P4 immediately AFTER the daily backup lands, ~04:00 ET.** Continuous PITR buys protection against arbitrary-time failure; a planned one-time migration does not need it. Cutting over ~35 minutes after a fresh physical backup, at an hour with essentially zero live activity, reduces the exposure window from ~19.5 hours to minutes at zero cost. The $100/month add-on remains the right answer for ongoing operational risk, but it is a separate decision from this cutover. |
| A8-DRILL2 P4/P5 recovery + lock contention | **GRANTED** | CPI | 2026-08-24 | Commit `2a268d6`; transcript `Streaming/Element10_A8_DRILL2.md` `8b3e560889274813d035945c86337cc1cfaa4d8a5c6440d6438bed16f7d1e378` (4,472 B). **Evidence shipped this time** — the C-SELL failure class (claims without reproducible artifacts) did not recur. **CPI independently verified production untouched via direct query, not by reading their claim: 12 migrations, head `20260716110000`, no `e10` schema, 15 catalog mutation policies still present** (the hole is still open, exactly as expected pre-P5), 31 public `e10_*` functions. **D1 is the important result: exact return from P4+P5 is PROVEN** — all five post-P3 fingerprints match after restore, including `fn_bodies b9e6a467` and `policy_defs 77a3e5d0` and 97 policies. That is the surface F6 flagged as not forward-scriptable, and it is recoverable by backup restore. **Three findings, each found by DOING rather than reasoning, which is what the charter asked for:** (1) version-matched `pg_dump` is mandatory — 16-against-17 produced a **0-byte dump**, a silent recovery failure; (2) `pg_restore --clean` is the wrong method, leaving the 14 A6c delegates created during P4 orphaned (49 functions vs 35 target) — recovery must be clean-slate to a fresh target; (3) faithful restore is full-cluster, multi-schema and superuser, since `-n public` dropped the `e10` predicate schema and cascaded 8 policy failures. D2: 3 concurrent writers, 1,746 commits, **0 errors, max writer stall 12 ms (P1) / 10 ms (P2+P3)**, no step escalating beyond its predicted lock, with the honest caveat that only short autocommit transactions were used and a long-running writer txn across an ACCESS-EXCLUSIVE step would head-of-line-block the table — yielding a new execution-gate requirement (`lock_timeout` ~3s + retry on those steps). **CPI FINDING G1 — carried to the go/no-go, NOT a DRILL2 defect: the two numbers that actually decide the go are still unmeasured.** The drill measured the local restore floor (backup 0.35 s, recovery ~1.4 s) and correctly disclosed that production recovery is provisioning-bound "minutes." But "minutes" spans 5 to 60, and for a 24/7 live-commerce business deciding on an irreversible phase, that range IS the decision. Worse, the stated production recovery path assumes **Supabase PITR**, and CPI could not confirm from project metadata that PITR is enabled on `ddhkkumiyidorzmajwde`. If it is not, recovery falls back to daily backups and the **RPO is up to 24 hours of live transactions**, which is a materially different risk than the drill implies. Both are answerable without touching production — a timed PITR restore to a throwaway target endpoint settles time-to-endpoint and confirms the mechanism exists. **Required before the execution go.** G2 (minor): D2's load — 3 writers over ~3 seconds — is well below a live break's peak, so zero-downtime is proven at this load, not at target workload; FG8's "≥2× defined target" remains unmet and should be stated plainly at the go rather than implied by the 12 ms number. |
| STEP8 bounded inventory reads | **GRANTED** — with a scope correction to the record | CPI | 2026-08-24 | Commit `50d34cd`; migrations `20260820120000_e10_step8_bounded_reads.sql` + two index migrations; `tests/step8_bounded_reads_test.sql`. Production independently verified untouched (same query as the DRILL2 row). **Construction is sound and follows the A6c.2 pattern exactly:** `e10_org_inv_page` is a `SECURITY DEFINER` delegate authorizing internally (`e10.is_org_member` → 42501) with a thin `e10_inv_page` wrapper forwarding `e10.current_org()`; `p_limit` is clamped to [1,500] so **the caller cannot widen the bound**; keyset throughout with **no OFFSET anywhere**; keys stated and justified (items by `id` under `UNIQUE(organization_id,id)`, movements by `(created_at desc, id desc)` with the PK breaking ties). **The frozen contracts are intact — CPI checked the one that matters most: movement history filters by `organization_id` for authorization with `item_id` as an OPTIONAL plain retained column, explicitly no FK, explicitly valid for hard-deleted items.** The ledger-outlives-items invariant frozen since A6b and re-proven hostile at A7 survives this change. The 9 mutation delegates and the 55 A6c.1 policy predicates are untouched. **SCOPE CORRECTION so the record is not read too generously:** this bounds the SERVER, not the client. The unbounded whole-catalog `jsonb_agg` is genuinely retired, which was the CPU/memory blast-radius defect. But `loadInventoryRows` still **walks every page** into an in-memory grid, so the client continues to materialize the entire org catalog — the builder discloses this inline ("this loader keeps the existing in-memory grid by walking every page"; server-side filters are available for "follow-on client work"). At **35 production inventory rows** this is operationally irrelevant today and the work is correctly pre-emptive; at the scale that motivated Track A step 8 it is the half that matters. **Step 8 is therefore NOT closed** — on-demand grid pagination consuming the `{q,cat,set,year,grade}` filters remains open and must not be inherited as done. |
| PF-M5.1 P5 write census + dispositions | **GRANTED** | CPI | 2026-08-24 | `PF_M5_CHECKLIST_CATALOG.md` `71b8af8fe71a260d04b37f5d6b66c32fb29c86ce68d7f3c45e215892832dc17d` (21,994 B); `PF_M5_COVER_NOTE.md` `f75cd3fab72d6b0047a72e9c081fb6c95ae0feb2262bb3f1df6aaaed7f2f4b57` (6,312 B). Both hashes and byte sizes verified exact before reading. **CPI ran an independent census rather than checking theirs: 19 write sites against the five catalog tables in `index.html`, zero in `companion.html`/`overlay.html`/`open.html` — matching their claim exactly, and all 19 line numbers matching row-for-row.** Every row dispositioned into covered / new-delegate / scoped-out with no implied withdrawals. **CPI attacked three things and all three held.** (1) "Logos org-owned" on `e10_teams`, a table with NO `organization_id` — resolved by a new org-scoped `e10_org_team_branding` with the overlay composing org branding first and canonical `logo_url` as fallback. (2) CPI hypothesis that the overlay board is anonymous and therefore could not read an org-scoped branding table, which would have made "keeps working mid-show" false — **disproven by inspection**: `overlay.html` gates on `sb.auth.getSession()` and shows an auth pane without one, and `team_sel` requires `current_org() IS NOT NULL`, so the authenticated overlay session reads org branding correctly. (3) The branding composition is a **read** change in `overlay.html`, a file with zero writes, so a write-only implementation list would have missed it and logos would silently stop updating — cover-note item 5 explicitly carries "overlay board reads org branding with canonical logo fallback." **Integrity check on the "§§1/2/4/5/6 untouched" claim: CPI compared §4 against the rejected revision and it is byte-identical** — the corrective is genuinely additive. Rulings recorded: canonical hard-delete abolished for everyone (`withdrawn_at`/`superseded_by` supersede; nothing referenced by a ChecklistForUse version or card instance can disappear); `e10_teams` identity platform-curated with a submission path while logos are org-owned presentation; import is link-only against canonical reference tables with unmatched names riding as free text and canonical rows created at promotion. Three scope-outs, each with a same-day operator equivalent. **Minor, non-blocking:** row 6 (`tmEditSave`) is labelled "covered" in the census table while also appearing as scope-out 3 — not a contradiction (the org-visible rename is covered; the canonical edit is withdrawn) but the label does double duty. **PF-M5 is now UNBLOCKED as A8-P5's precondition** — the model names what Track A implements and what the client must call. **Carried to the operator, not as a blocker: the destruction ruling is a product decision made inside a model gate.** Canonical hard-delete is abolished permanently for everyone including platform curation. It is well-argued and the operator keeps a reversible hide with the same visible outcome, so it did not trip a commercial hard stop — but "no one can ever delete a card from the catalog" is the kind of decision Trent may want a view on. Recorded here so it is not silently inherited. |
| PF-M5 checklist catalog + curation model | **NOT ACCEPTED** — superseded by PF-M5.1 | CPI | 2026-08-20 | `PF_M5_CHECKLIST_CATALOG.md` `364c0c7e81e650418d0593f46b4773234046fbebf0c5a9db505bbf7295237e6d` (13,701 B); `PF_M5_COVER_NOTE.md` `6a604d82027d432626fc5e48bb96f43564db324ab82b60696d4fe10d89d6f30e` (3,894 B). **The model's substance is sound and is NOT what fails.** Org-local-creation-that-is-promotable is the right mechanism and is correctly argued against both alternatives (a blocking queue strands an operator mid-setup; a definer RPC writing canonical makes tenants de-facto catalog writers, violating the A6c.4 reality). Composition-key identity generalizing `cardDupKey()` is sound, `cardTitle()` surviving promotion by construction is correct and consistent with PF-C-S1.6, the ledger invariant is respected (no FKs to items; catalog rows were never referenced), and the additive re-point via Attention rather than rewrite is the right call. **Rejected on the one claim the gate exists to support.** Model §3 closes: "remove every direct INSERT/UPDATE/DELETE against the five catalog tables; call the four `e10_org_*` delegates above... **This is the complete list of client-side changes P5 depends on**," and cover note item 5 repeats it. **It is not complete.** CPI ran an independent census of `index.html`, the deployed client, against the 5 catalog tables P5 governs (15 policies = ins/upd/del × 5 tables): **~10 write paths have no delegate.** (1) **The Team Manager is a full admin CRUD surface** with no checklist involvement whatsoever — `tmAddSave` INSERT, `tmEditSave` UPDATE, `tmSetLogo` UPDATE, `tmRemove` DELETE on `e10_teams`. Team logos feed the live overlay board ("live on the overlay board"), so P5 on this model breaks a **stream-facing** feature mid-show. `e10_org_overlay_patch` governs checklist overlays and chase tags; it does not reach a global team directory. (2) **Single-card operations on canonical rows:** `scEdit` (any card field), `scSetTeam`, `scDel` (deletes a canonical catalog row). (3) **`delChecklist`** deletes a checklist and all its cards — no delegate covers canonical deletion at all; the four delegates are create/stage/patch/approve with no destructive path. (4) **Import side effects** `dbEnsureSet` INSERT `e10_sets`, players upsert, teams upsert may be internal to `_submit(jsonb)`, but the model never says so while claiming completeness. **Consequence if implemented as written:** Track A removes the client's direct writes per cover-note item 5, finds no delegate for team management, card editing, or deletion, and either stalls or ships a client that loses those features. P5's abort (re-add the 15 policies) is instant and recoverable, so this is not catastrophic — but it is discovered by an operator mid-stream rather than by the model. **CPI RULING ON Q3 (asked and answered, does not reopen the gate):** confirmed as modeled — the tenant-side delegates are required at P5; the platform curation RPCs may follow. P5 needs only that the client stop writing canonical rows; an unpromoted catalog simply does not grow, which is acceptable. **Q1/Q2 are commercial and go to Trent, not to me.** Corrective **PF-M5.1** issued: census-first, then close or explicitly scope out every uncovered path with a ruling. |
| C-POLISH checkpoint (5 gates) | CPI AUDIT PASSED — recommended, awaiting OPERATOR acceptance | CPI | 2026-08-11 | `Element10_CPOLISH_REVIEW.zip` `48b4316e7079882a…`, drop `fa35af87138cf490…`; build `d3a18d53f58653b2e7d34787…`; `e10.css` frozen `cd37cd43…`. Package integrity: **manifest mismatches 0**. CPI-run self-debug sweep on the delivered build: **130 records, 0 failing**. **The four failures the report dismissed as "an accepted org-A ent-off scan false positive" did not reproduce for me at all** — I did not accept the inline explanation, I superseded it: org-A cards-off scan returns `hits=[]` and the invariant that actually matters, a CORE org holding no vertical vocabulary or data, is proven clean directly. Gates verified by CPI-authored adversarial scenarios, not by re-reading their claims. **Gate 3 duplicate (4/4):** carries identity (name/parallel/print run/acquisition) and CLEARS serial plus all three grading fields, so a duplicate can never inherit another card's cert — the raw-or-graded invariant holds through the new path; creates nothing until saved. **Gate 3 archive-acquisition (3/3):** refuses while active cards reference it and the refusal names the invariant ("archive or move those cards first; refusing keeps every card on exactly one live acquisition"), then allows once clear. **Gate 4 bulk (source + behavior):** archive is a bulk action, delete is not, cost basis is not bulk-editable, two-step confirm restates the true count, spec-owned `exec` returns its own undo closure that snapshots and restores listing side effects incl. the delist obligation. **Gate 5 pagination (8/8) at 261 real rows:** page 1 renders exactly GRID_CAP 200; pager appears only past the cap with Prev correctly disabled; the header checkbox selects the VISIBLE PAGE only (200 of 261) while the disclosed escalation reaches all matching; selection survives paging without page-2 rows being falsely painted checked; any filter/search/sort change resets to page 1. **Enter semantics:** invalid form creates no phantom record and states every problem; an open picker owns Enter and fills rather than submits; textarea keeps its newline; `#gedit` and a pending `#confirmscrim` are both explicitly excluded from the primary-button path. **Dirty-work guard:** Cancel raises the confirm; routing away does not destroy the form. **FINDING F1 (operator-facing, minor, folded forward — not a re-cut):** a selection can outlive the filter that produced it. Select all 261 matching, then narrow to 111, and the bar reads "261 selected · all 111 matching" while the button reads "Archive 261" — every number literally true, read together misleading, with 150 selected rows the operator cannot see on any page. Recoverable (confirm restates 261, undo exists) so it is disclosure, not data loss. **Two conditions NOT tested and stated as such:** the bulk-undo listing restore is source-verified only, since no listing-creation function is exported for me to seed one; and Escape on a dirty form is a silent no-op — it neither closes nor raises the confirm, giving the operator no feedback. **Acceptance is Trent's** under the operator-facing split; this row records the CPI audit, not the gate. |
| A6a organization core / tenant spine | GRANTED | CPI | 2026-07-20 | head `53501928a6ef928ad5a5ec4401e4e12073e6527a` |
| A6b tenant-zero backfill + capability catalog | GRANTED | CPI | 2026-07-20 | head `53501928...`, CI run `29688509320` |
| Product-first workflow | GRANTED | CPI | 2026-07-20 | `Element10_PRODUCT_FIRST_CANONICAL.zip` SHA-256 `874b8f40a519ddbb22c79bfd4e8180746e5c0a13e8eba2fd18a96d0951ed82fb` — **VERIFIED** against the original archive 2026-07-20; extracted content 12/12, content anchor `2ae67f8c...` |
| PF-0 provenance and hub gate | GRANTED | CPI | 2026-07-20 | PF-0.2 archives — see `PF0_2_ARCHIVE_HASHES.txt` |
| A6c authorization plan rev 6 | GRANTED | CPI | 2026-07-20 | `Element10_A6c_PLAN.md` SHA-256 `2d1710bfdb0653271960f021c12efacb4c83f1be22067d6e064e6724ed33ce70` |
| A6c.3 workspace policy family + CAS + A6c.0 re-align | GRANTED | CPI | 2026-07-27 | Commit `1e94544` (exactly 3 files, +329), migration `20260727140000_e10_a6c3_workspace_policies.sql`, CI `30285456119`. CPI-verified on live staging: 4 workspace policies org-scoped / 0 legacy / WITH CHECK pinned on both write paths, matching census rows 94-97; total new-style 66 with the 55 A6c.1 policies untouched; independent census — zero legacy predicates in any delegate body; the 8 A6c.0 objects re-aligned (staging `redeem_code` functiondef md5 matches the reported AFTER; whole inventory surface now byte-exact); CAS proof incl. stale-rev 0-rows and cross-org 42501; gate test's only `when others` are `*_wrongerr` recorders; red/green by permissive-replace at two strengths; prod untouched (12, `20260716110000`, 0 org-scoped ws policies). Layer-honesty disclosure (UPDATE refusal defended by ws_upd WITH CHECK AND ws_sel visibility; falsification removed both) exceeded the standard. Carried disclosures → A6c.4/A7 scope: missing-cap on the shared write branch unexercised; live two-connection CAS race; universal/owner branches with no extant rows. |
| A6c.2 + A6c.2.1 wrapper cutover + authority corrective | GRANTED | CPI | 2026-07-27 | Commits `0a7da40` (cutover, CI `30211865339`) + `8152f2d` (authority corrective, migration `20260727120000`, CI `30260835702`). CPI-verified on live staging with an independent census query: ZERO legacy authority predicates remain in any org-aware body; `buyer_suggest.seen` scoped to `p_session` with `e10_is_admin` removed (approved behavioral divergence from the m31/m32 oracle — org-scoping wins over verbatim legacy authority); five inventory delegates on `e10.is_org_admin(p_org)`; both dead orphans retired; wrappers thin, zero recursion; 55 A6c.1 policies untouched; prod untouched (12, `20260716110000`, 0 delegates). Byte-exact staging artifact applied per the new standing rule; 6 touched delegates proven byte-identical via `pg_get_functiondef` hashes. Gate test 15/15 with zero `when others`; admin denials pinned by exact ok/msg (business-capability refusals, not exceptions) — justified, hard 42501s still covered by the A6c.2 gate. Identity-combination regression covered: legacy global admin with ordinary org-B membership receives ordinary-member treatment. Reviewer's bonus finding recorded: 8 A6c.0 objects cosmetically differ on staging (token-identical) — re-align folded into A6c.3. |
| A6c.2 wrapper cutover (superseded history) | NOT ACCEPTED | CPI | 2026-07-26 | Commit `0a7da40eb7d3249266cd19914b8abf3b68967895`, migration `20260726140000_e10_a6c2_cutover.sql`, CI `30211865339`. Structure verified clean (delegates are the mechanism, wrappers thin one-line forwards, 0 recursion, 7 legacy helpers retired with refcount proof, 55 A6c.1 policies untouched, prod untouched). **Rejected on outside review, both findings CPI-confirmed on live staging: (1) `buyer_suggest`'s `seen` query has no session or org filter — `streamer_uid=auth.uid() OR e10_is_admin()` exposes buyer identities across sessions and, for a legacy global admin, across organizations; (2) SIX delegates (reviewer's five + buyer_suggest) retain legacy GLOBAL `e10_is_admin()` authority inside org-aware bodies — a legacy global admin could exercise admin behavior in an org where they hold ordinary membership; no test covers that identity combination.** Root cause: "preserve legacy behavior verbatim" (m31/m32 oracle) preserved legacy AUTHORITY verbatim; no census ever covered delegate-body predicates. Also: compact staging body + reconciled ledger makes staging appear identical to clean replay when it is not — insufficient for a security-definer migration. CPI's own audit missed both (checked structure, not authority semantics) and the CPI's stale board sections violated its own 2026-07-21 maintenance rule a second time. |
| A6c.1 RLS policy rewrite (55 policies) + A6c.1.1 test corrective | GRANTED | CPI | 2026-07-26 | Commits `7138716743250d47e3cf90da9196fd471f18a322` (migration `20260726120000_e10_a6c1_rls_rewrite.sql`, CI `30206547507`) + `d2ad844` (test-only, CI `30207551465`). CPI-verified against live staging: 97-policy census reconciles exactly (55 rewritten = 41 USING + 14 WITH CHECK; 100 live minus 3 storage = 97); `imov_sel` now `e10.is_org_member(organization_id)` closing the A6c.0 finding; every WITH CHECK pins `organization_id = e10.current_org()`; correlated refs table-qualified with the `owned_slot` alias (rev-4 shadowing not reintroduced); 11 delegates intact, wrapper still legacy (no A6c.2 creep); prod untouched (12 migrations, head `20260716110000`, zero e10 policies). Outside review found the cross-org write denial was a false positive (FK shadowed RLS behind `exception when others` — standing rule 5); A6c.1.1 rebuilt it FK-valid requiring SQLSTATE 42501, audited the other 7 denials (SELECT-count/predicate, unshadowable), and proved falsifiability by permissive-replace after finding a bare DROP yields default-deny — a stronger construction than the corrective specified. Agent's ADR flag was correct; board's stale rev3.2.2 note fixed. |
| A6c.0 additive prerequisites | GRANTED | CPI | 2026-07-20 | commit `7f0d38385e05682da5bc51879a1ac04683d27afd`; migration `20260720120000_e10_a6c0_prereqs.sql`; CI green run `29768281886`; staging head `20260720120000`. CPI-verified against live prod + staging: 13-delegate allowlist exact, internals `authenticated=false`, zero anon/PUBLIC, no wrapper or policy cutover, 0 published sessions, prod untouched. |
| PF-C2 Product Configuration | GRANTED | CPI | 2026-07-20 | `Element10_PFC2_REVIEW.zip` SHA-256 `c001a8bb169b50e94103277f205d0290023513786da431233d1ef521166ca7d3`; screen 08 `a7d056e881f89c0fc19748e9...`. CPI-verified in source: `saveConfig` fails closed; conversions append-only with `cur` pointer; forbidden list and scan hosts unshortened; unit arithmetic independently recomputed (360 / 4320 / 48); cards-off handled via per-org seed data. Passed on first attempt. |
| A8-PREP (close the rehearsal findings) | GRANTED — execution still NOT authorized | CPI | 2026-08-04 | Commit `faab6f4`, CI `30941477566`. **CPI-verified independently: production untouched** (12 migrations, `20260716110000`, no `e10` schema, 35/41/6) and — the point of F5 — **I reproduced their canonical ledger checksum exactly: `f54a1fe978614e21cf2ffb8c63afb475`** by running the one query now stated in the plan. F1 closed: the composite-FK migration carries 33 guards against 16 constraints, re-run drill 0/0 across all 36, plus a deeper hazard they found unprompted (a full re-run would resurrect the movements/receipts composite FKs that the ondelete corrective drops — the ledger-outlives-items invariant — end state verified correct). F2 closed: `a8_p1..p5_down.sql` authored, COMMITTED and drilled; P1/P2/P3 return to the exact pre-cutover fingerprint, and authoring them surfaced real dependency traps (org_uq is FK-depended-on; the backfill went parents-first so reversal must go children-first) — evidence that recovery scripts must be drilled, not assumed. F5 also caught a latent hole in the OLD formula: a single null `on_hand_delta` would have silently dropped a row from the aggregate, so the crown-jewels check could have missed a ledger change. **F6 — THE MATERIAL FINDING, stated plainly as asked: P4 IS EFFECTIVELY IRREVERSIBLE IN PRODUCTION.** DB-side RPC bodies restore, but RLS policies are not reliably restorable by forward script (they originate in an init-plan; reconstructed policy DDL failed on a complex predicate). Recovery from P4 = restore pre-P4 backup + coordinated client/SCHEMA_VERSION revert = incident-level, operator-authorized; forward-fix is the default. F3/F4: row volumes corrected (~6.5k retrofit; cards 57288 is policy DDL only, row-independent); lock contention stated as a single-connection scope limitation with a concurrent-writer exercise proposed but NOT run. **CPI-carried, open before any go: (a) lock contention still unexercised — duration is not contention; (b) P4/P5 recovery is now understood but never rehearsed AS a backup-restore drill, and it is the point of no return.** |
| C-REHEARSE (A8 §2 P0 rehearsal) | GRANTED — rehearsal accepted, execution NOT unblocked | CPI | 2026-08-04 | Transcript `Element10_A8_P0_REHEARSAL.md`. Executed against a local scratch restore of REAL production data; **production never touched — CPI re-verified independently: 12 migrations, head `20260716110000`, no `e10` schema, 35/41/6, all 15 catalog-mutation policies still present.** Proved on real data: all 36 migrations apply clean (~1.8s total, every step <125ms); the **enrollment lynchpin holds (0/0)** — every real writer already enrolled, which is the failure mode that would stamp NULLs and fail the P3 promote; the **backfill leaves ledger content untouched**; a complete reversal returns the DB exactly to pre-cutover. Did what the charter asked — FOUND rather than confirmed. **Findings, all carried to the execution gate: F1 (MATERIAL) `s1_composite_fks` is NOT idempotent — CPI verified 16 bare `ADD CONSTRAINT` with zero existence guards, so the plan's §10 "idempotent by construction" claim is FALSE for it and a resume dies on "already exists". F2 (MATERIAL) no committed down-recovery scripts exist; correct rollback enumeration is error-prone — the agent proved it by getting it wrong itself, missing 4 of 9 added tables on its first attempt; a post-P4 restore additionally needs 55 legacy policies + RPC bodies + a coordinated client revert. F3/F4 (MINOR) understated retrofit row volumes; lock CONTENTION unexercised in a single-connection rehearsal.** CPI adds two: **F5 the ledger checksum is not independently reproducible** — the plan's §2 formula yields `0df7a705…` while the transcript reports `e4cfa76d…`; a crown-jewels verification only its author can run is half a verification, so ONE canonical formula must be fixed in the plan. **F6 the rollback that matters was never rehearsed** — the drill exercised a naive early-phase reversal, not recovery from P4, the actual point of no return where RLS, RPC contracts and the deployed client move together. |
| A8 production cutover plan | GRANTED (plan only — NOT execution authority) | CPI | 2026-08-03 | Commit `1c49f99`, `docs/A8_PRODUCTION_CUTOVER_PLAN.md` (196 lines). Accepted under the CPI acceptance authority for non-operator-facing work. Plan gates everything on a P0 restore-rehearsal against production-shaped data; uses the ledger content checksum as the crown-jewels verification; expand→backfill→promote→contract for zero downtime against the 24/7 SLO; per-phase rollback boundaries, abort criteria, verification queries, and idempotency proofs. **Key finding, credited: P5 (closing the catalog write hole) is BLOCKED by a real dependency — the deployed production client creates checklists and cards by direct table INSERT, so dropping the 15 policies breaks operator checklist creation.** The plan refuses to silently choose "disable catalog creation," naming it as a business call. **This puts Track B's PF-M5 (curation path, per the shared-canonical + org-overlays ruling) on the critical path for the final cutover phase.** Execution against production remains gated on Trent's explicit go. |
| A7 hostile two-organization matrix | GRANTED | CPI | 2026-08-03 | Commits `00e808d` + `6eab46a` (CPI layer-attribution correction), CI green `30657187213`. **Proofs only — CPI-verified zero migrations across both commits; staging head unchanged at `20260731120000`.** `docs/A7_HOSTILE_MATRIX.md` authored ONCE for A7 now and PF-C20 later (11 identity classes × both orgs × 8 census families, each naming attacker / target / expected refusal / layer) — closing a board parallel-queue item open since 2026-07-20. Gate 29/29 + anon under real authenticated JWTs, never definer: cross-org denial + legitimate positive per family; **ledger-outlives-items re-proven under a hostile identity** (org-A member reads the correction movement of a hard-deleted item; org-B member cannot) — the invariant frozen since A6b holding under attack; receipts server-only; published-vs-private spectate; buyer_uid and verified-handle boundaries; multi-membership fail-closed; catalog and identity write denials. Red/green falsification one scenario per family (F1-F7 permissive policy, F8 delegate stub). **FINDINGS: NONE — every hostile denial held.** CPI independently confirmed on live staging: zero legacy policy predicates, zero legacy delegate bodies, zero anon-executable delegates, zero `authenticated` grants on receipts. Prod untouched (12 migrations, `20260716110000`, no `e10` schema). Agent resumed correctly from a crashed session whose recap was wrong, trusting artifacts over narrative. **Track A engine authorization series A6c.0–A6c.4 + A7 COMPLETE.** |
| A6c.4 platform-catalog + identity family + disclosures | GRANTED | CPI | 2026-07-31 | Commit `1a87bad`, migration `20260731120000_e10_a6c4_platform_identity.sql`, CI `30654018116`. CPI-verified on live staging: 5 catalog SELECTs scoped (platform-admin OR in-an-org), ZERO catalog mutation policies with RLS enabled on all 5 — **closing a live cross-org write hole** (global reference tables were member-writable; the old rls_test assertions had encoded the hole and were corrected); 8 identity policies org-scoped; zero legacy predicates anywhere — **the 97-policy census is fully consumed (A6c.0–A6c.4)**. Carried A6c.3 disclosures all exercised (ws_del branches, missing-cap, multi-membership 42501, universal/owner fixtures, genuine two-connection CAS race). Gates 20/20 + 12/12; red/green three ways; byte-exact staging artifact; prod untouched (and prod still carries the hole until A8-A10 — noted as cutover motivation). Agent correctly proceeded past the CPI's stale NEXT-PROMPT subsection (4th instance of that CPI defect) on the unambiguous authorization sections and flagged it. FLAG carried to roadmap: tenant-read-only catalog forces the checklist-curation decision before checklist physicalization. |
| C-SELL checkpoint (5 gates) | NOT ACCEPTED | CPI | 2026-08-04 | `Element10_C_SELL_REVIEW.zip` `4269fa40857cc7ca9830a3526f6f17dc0685e41ab9db6bb7ebbd3738eb5ca483`; build `516bd6b4...`. Package/manifest/frozen-css all valid, and the **Gate 1.1 decision is APPROVED and stands** — nullable `listing_id` with ONE commitment boundary for listed and direct sales; sibling-ending and delist obligations sound; margin preserved under additive basis correction. **Rejected on an outside adversarial audit: 8 of 8 targeted checks failed.** (1) `commitSale` stores the caller's `p.channel` instead of deriving it from the listing, and accepts ENDED listings — no eligible-state rule. (2) Idempotency returns any prior disposition on key match before checking the request refers to the same instance/listing/channel/price/date — a reused key returns a false replay for a different card. (3) ChannelSaleReport has only a random internal id, no external reference: duplicate deliveries unrecognisable, a duplicate against the winner becomes a FALSE SaleConflict. (4) `publishListing` does not reread archived state; `openAttestForm`/`openConflictRes` lack `cardsOn()` — the S2.1 F2 family RECURRING. (5) SalesChannel is strings not a registry, and five card-sales venues are SEEDED IN THE CARDS-OFF ORG. (6) All four proposed capabilities collapse to `canWrite()`. Gate 5 incomplete (two "total paid" strings remain). "Live" vocabulary contradicts the model, and the listings count treats drafts as live. Evidence: scenario files not shipped (claims unreproducible), sweep never extended to Listings, three screenshots do not show what their captions claim, every caption ends `undefined`. **CPI SELF-ASSESSMENT: my audit passed this build.** I verified the claims the report made rather than attacking what the model required — tested `listingId:null` but never a listed sale with a mismatched channel; tested replay with the same payload rather than a different one. My self-debug sweep did not reach dialogs (so the missing `cardsOn()` walked past it) and my cards-off scan reported clean because "Whatnot"/"eBay" are not forbidden WORDS while being forbidden DATA. Both tool gaps are now fixed (sweep: dialogs + opener entitlement + cards-off data; 130 records). **CHARTER PROVENANCE, CPI fault:** the package cites rev 2 `27f46945`; rev 3 `5e9fbdcd` (adding the mandatory sweep) was authored AFTER the agent began. I amended a charter mid-flight, which the relay protocol I wrote forbids. Not a baseline failure by the builder. |
| PF-C-S2.3 acquisition channel + landed cost | GRANTED | CPI | 2026-08-03 | `Element10_PFCS2_3_REVIEW.zip` SHA-256 `548b465359c476eddaab85a20050a630587e77d415b5b88dcf26c4d5ab085fce`; build `9075d0736d4d2824f2a32946...` (identical in package and drop zip); `e10.css` frozen. Two-phase gate: preflight `PFCS2_3-PREFLIGHT-1` approved, then implementation, then a blocked-evidence recovery. Components are the stored facts, landed total derived, `total_paid` demoted to a cache with `saveAcq` its sole writer (7 remaining occurrences all designed, censused); channel an org-scoped suggest vocabulary, required on create; MIGRATED legacy records never auto-decomposed. **CPI ran the canonical headless harness against the delivered build and independently verified the substance**: components `[300,12,9,45]` stored, landed = 366, cache agrees, and the `C2r` claim confirmed — single-card basis derives from the LANDED total (366), not the purchase line (300); card-form basis lock still refuses. Three CPI fixture stumbles were accepted guards refusing bad input, incl. the new required-channel guard. Baseline 8 cases + adversarial pass (dirty-guard races, mutator-level floor and authority attacks with crafted drafts, MIGRATED fabrication attack, cross-org vocabulary probes, double-save, CPI-correction-1 continuation regression) + 6 render captures once the environment recovered. One baseline FAIL left in the log UNEDITED and correctly diagnosed as a probe artifact, re-proven as `C2r` — standing rule 4 honored, not gamed. **Finding W1 escalated not fixed** (3 user-facing strings still say "total paid"; values correct) — cosmetic, folded into the next Track B gate. |
| PF-C-S2.2 entitlement + truth + context corrective | GRANTED | CPI | 2026-07-31 | `Element10_PFCS2_2_REVIEW.zip` SHA-256 `71e9ffbdb9b6124da725af01aaf1299c88e0e74e6a519c24b6e331031d211eff`; screen 08 `09c21696...`. CPI audit + CPI-executed delegate walkthrough at operator direction — 16/16 across two materially different passes (core lifecycle/mutator; adversarial context-switch/temporal). F2: `ent.cards` fails closed in every vertical mutator and opener, probed directly. F3: held totals derived from actual bases with explicit discrepancy states on both sides of a moved-basis card, move-back resolving — proven end-to-end. F1: `guardContextChange` census (5 draft families × 3 context changes, Stay/Discard holds, no resurrection, scan clean post-switch). Three CPI fixture stumbles were accepted guards refusing bad fixtures (raw-dup pause, zero-cards refusal, single-mode derivation) — incidental adversarial confirmation. Operator accepted on the delegate run. |
| PF-C-S2.1 admin-only over-assignment | GRANTED | CPI | 2026-07-27 | `Element10_PFCS2_1_REVIEW.zip` SHA-256 `60700f84e3060f2a43acf64a208c0b3a55bd02aa0f3b365f4979a2a81f584b31`; screen 08 `b7567fa46b05c7ab5f2e1c30e4215f5d2c1a9fd94afdd5f8683c7c964a1e09c3`. First Track B gate under the adversarial walkthrough protocol, and the first relay delivered by verified file-reference after the agent correctly REFUSED a hash-mismatched truncated paste. Change verified conformant (review gate + independent mutator `isAdmin()` re-check + admin-override statement + flag derived from recorded totals; non-admin verbatim-unchanged). Adversarial pass surfaced four pre-existing family findings, all CPI-dispositioned: F1 stale dialog on scenario switch, F2 mutators ignore module entitlement (CPI-reproduced: zero `cardsOn()` in `saveCostAssignment`/`saveInstance`), F3 between-acquisitions basis move leaves untruthful held totals (CPI-reproduced: acquisition selector on edit form) — all three must-close → PF-C-S2.2; F4 float precision at 10^15 → binding Track A note: money is integer cents in the physical schema. Operator walkthrough approved. |
| PF-C-S1.7 (preflight + implementation) + PF-C-S2 cost assignment | GRANTED | CPI | 2026-07-27 | `Element10_PFCS1_7_REVIEW.zip` SHA-256 `88c9b8c5629f148d36608d3de2de39c7d868731fa8ad4725b2641c164a2bbec5`; screen 08 `875422ab71204c257ec75c93cf2e5ca9850d1282dc515c505375a980fff71bc8`. First gate under the full protocol: relay → preflight `PFCS1_7-PREFLIGHT-1` → CPI review (one correction: team-choice reuse) → E1 baseline ruling (revert to S1.6; divergent file preserved as labelled no-authority reference) → phase-2 implementation → audit → walkthrough. CPI audit: manifest clean; rebuild provably not the reference (carries the team-choice correction the reference lacks); state-aware continuation panel proven behaviorally (below→Add another, at→Review); zero blanks/datalist/"next"-copy/render-fallbacks; zero-acq seam present. S2 (opened mid-flight by direct operator authorization, agent flagged correctly): assign→review→approve with single guarded writer, dirty-guarded draft, card-form basis lock re-proven post-approval, 60/40-of-100 arithmetic verified, approval recorded on the acquisition. 12/12 CPI behavioral checks. Operator: "i reviewed it and it works - approved." Outstanding conformance corrective → S2.1 (admin-only over-assignment per the standing 2026-07-21 ruling; current build flat-caps everyone). |
| PF-C-S1.6 financial + identity discipline | GRANTED | CPI | 2026-07-26 | `Element10_PFCS1_6_REVIEW.zip` SHA-256 `fd47e4610058fad2ba7bd1af14b972a5293c23cd59f5406c43c378c119069b41`; screen 08 `d2065b29e3d72a556e004610b80987f1718b85b047ccdd43df26c5fa7c183eb6`. Eight items: cost basis unwritable (input removed; mutator refuses a direct write naming attempted vs derived — closed the build-contradicts-PF-M2.1-§4.2 inconsistency); collection import creates ZERO instances (the unguarded blank-creation path is dead, `saveAcq` has no pushes; "Expected cards" is advisory progress); Name required; org-wide duplicate company+cert refused naming the existing card via composed title (archived included); raw-duplicate warn-then-save; `cardTitle()` composed identity, load-bearing in 7 places, no dangling separators; Channel→Distribution rename complete; Checklists entry point into the same wizard with origin-aware landing; search visibly inert. Acceptance evidence: CPI source audit + **CPI-executed behavioral run at operator direction — 18/18 checks via real DOM events** (mousedown→click picker rows, native input events), covering the full sequence: checklists-first wizard → zero-blank collection → picker autofill → basis probe refusal → duplicate-cert refusal → origin landing. Finding from the run: a fresh org has an empty picker index until a product import runs — correct per spec; a why-and-what-next line added to S1.7's no-match item. |
| PF-C-S1.5 + PF-C-S1.5.1 walkthrough batch + picker-click fix | GRANTED | CPI | 2026-07-26 | S1.5 `Element10_PFCS1_5_REVIEW.zip` SHA-256 `5e3cc57f224fe5e61ef8e1fa38721a75ebbe002d91e726d83316b26e0a067933` (7/8 verified: delegated dismissal with Escape swallow, quiet filter row + contains/not/equals/empty ops, required brand/line/year, "/" print-run adornment + serial redirect, acq→first-card flow, images/links/asking outside money math, advisory cert warning; 3 self-found defects disclosed pre-package) was NOT ACCEPTED on the operator finding that picker rows were unclickable — `||S.ciform` repainted the picker on every mousedown, destroying the row between mousedown and click. S1.5.1 `Element10_PFCS1_5_1_REVIEW.zip` SHA-256 `37d72670c657224d5515d68ea2cfd815778a39447b62943478113d0ae1103ea5`; screen 08 `a492aa29818164f670dbf9ccbd4baee59205ffe879b4d0e92a7f002019418f17`. Repaint-only-what-closed; while proving it the agent found and fixed the focus-reopen defect (programmatic focus is not a user focus, `S._noFocusOpen` at three sites) rather than shipping a fix that visibly broke the feature a new way; proof used the full native mousedown→click sequence. Operator confirmed selection and autofill working. |
| PF-C-S1.3 + PF-C-S1.4 checklist autofill + caret fix | GRANTED | CPI | 2026-07-26 | S1.3 `Element10_PFCS1_3_REVIEW.zip` `274e85b6...` (substance: org-scoped picker, variant→parallel translation at the boundary, provenance marks, subject→name) was NOT ACCEPTED on the operator finding that typing rendered backwards — `cifNameInput` redrew the form per keystroke with no caret restore, fifth pattern-reuse failure. S1.4 `Element10_PFCS1_4_REVIEW.zip` SHA-256 `67c2da4c859074c25c688d55d4bf82ccfc2f152596045b93659b519cb5146714`; screen 08 `a0e3de7be87989e675a05ffe2ad08a054c30e06ab1e5460b5128ea60c0f645ca`. Fix is structural: the input is never rebuilt while typing (stable `#cifPicker` host repaints alone); the four legitimate redraw paths share `ciCaptureCaret`/`ciRestoreCaret`; live-DOM input audit. Accepted on the operator's own walkthrough screenshot showing in-order text. |
| PF-C-S1.2 print run + serial split | GRANTED | CPI | 2026-07-21 | `Element10_PFCS1_2_REVIEW.zip` SHA-256 `50807b79c89baef9f045762cf3eb7bf137a9a4e96802afb9b9ad259b72948592`; screen 08 `d45f7726d113e206b0f6f3ddd4c07b9ada707adb11d605d6f37d50d41ae2612b`. `serial_number` → `print_run` + `serial`, display rule covers 14/149, 1/1, /149 and unnumbered; print-run filter proven narrowing. **Included a self-caught, self-disclosed tenant-boundary fix:** `setOrg`/`setEnt` never cleared `#ovhost`, so a dialog open across an org switch left card vocabulary in the other org's DOM — reproduced failing (`hits:["card","player","parallel"]`), fixed, reproduced clean; CPI verified the prior build lacked the clear. Rules 4 and 6 applied unprompted. |
| PF-C-S1 + PF-C-S1.1 CardInstance + Acquisition (create/read/archive) | GRANTED | CPI | 2026-07-21 | `Element10_PFCS1_1_REVIEW.zip` SHA-256 `dacb78c714c20db503d65384cb6e674070735bca58aa61d982fd5009b86d2582`; screen 08 `e22aeaac2f5dcb79057a3fd2c7595ee07713e41fe3c3132e188a249dd3597a48`. Source audit + operator walkthrough. First pixels of the singles model. CPI-verified: raw-or-graded invariant refuses at save (and refuses graded+raw-note); orphan instance refused; only `active`/`archived` states in code; `singlesSpec` fourth grid consumer; cross-org isolation with route redirect before render. PF-C-S1 walkthrough found two model-meets-reality gaps → S1.1: vendor now optional with free-text seller + inline quick-create (reuses `saveVendor`, no forked path, verified vendor list 2→3); field taxonomy corrected (variant+parallel→parallel, `serial_number` added as filterable column, name→subject) — scoped to CardInstance extras, checklist grid untouched, verified all 12 remaining `variant` refs are checklist-side. Model amendments to PF-M2.1 §3.1/§4.1 recorded on board. Operator: "walkthrough approved." |
| PF-M2 + PF-M2.1 singles / graded / repack model | APPROVED | CPI | 2026-07-21 | `PRODUCT_SINGLES_MODEL.md` SHA-256 `1c41ca64027f37e972264bbc203d8b7df047f2bcbec9fb77f0525f580bb2c757` (zip `568d5c753a236b74941631b9df63c7386998b4d2a143f5dcde1f619fd3130bed`). Design/model only, no prototype. CPI-verified against the document, then against the v1→v2 diff (13 lines, all in §3.4/§3.5/§4.2/§7/§10; repack math, basis-independence proof and ledger discipline provably untouched). Substance sound on first pass: repack cost aggregation and break-up preserve each instance's original basis and never manufacture cost; acquisition margin routed only through `total_paid` and proceeds, independent of per-card basis; append-only ledger invariant survives the manufacturing verb; re-grade as new instance; closed-sale margin preserved under later basis correction. PF-M2.1 folded two operator rulings: `reserved` given a real hold-before-sale event (no dead state), over-assignment admin-gated via `singles.cost_assign_over`. Proposes a 5-checkpoint singles sequence, non-binding, parallel to PF-C4+. |
| PF-C3 + PF-C3.1 Vendor identity | GRANTED | CPI | 2026-07-21 | `Element10_PFC3_1_REVIEW.zip` SHA-256 `4830cf1498fff88e5290659d4d38c19caa656551fecef80a5bfd6024de614f0a`; screen 08 `b8c354b1c1a04b937c316103fb5a495af3d7cc452694792dcce950a4eaf7d319`. **First gate accepted under the operator-walkthrough rule, which earned itself immediately:** the CPI source audit of PF-C3 passed, and the walkthrough found the vendor edit form could not be closed — `closeVendorForm` called `route()` while the hash was still `#vendor/:id/edit`, so the form reopened in the same tick. Every individual function was correct; the trap existed only in their interaction and was invisible to source review. PF-C3.1 fixed it against `closeForm`'s pattern, audited every other close path (CPI independently confirmed only product/vendor new+edit have hash routes, so the rest conform by construction), and added identity fields: repeatable addresses with role (mailing / billing / ship-from), website, account number, vendor type, secondary contact, notes. Zero purchasing, zero cost. Operator: "The vendor pages look good - approve." |
| PF-C2.13 clean repaint on focused-surface return | GRANTED (with finding) | CPI | 2026-07-21 | `Element10_PFC2_13_REVIEW.zip` SHA-256 `f08104bb3527a42be402c8b60a7269e27a474f1f2d90e610b02f3949086e019f`; screen 08 `62eb09613d973ff0a40332999a3f3e352ae1b8455e779d3eb04b8680e0b78837`. CPI-verified: `excFocusDone` and `excFocusCancel` both call `route();drawImport();`, matching `closeReview`. Confirmed by pixels — `pfc213-03` and `pfc213-04` show the dialog at step 5 with a clean products list behind it, no leftover grid, "Save and review" disabled, exception cards still unresolved. **FINDING (not blocking):** `pfc213-02-cancel-pressed.png` and `pfc213-05-done-clean-return.png` both show the wizard at step 2 with steps 3-5 unvisited, a state that cannot follow a focused-surface return; the toast in `-05` outlived the state that fired it. Third consecutive gate with a caption not matching its image. The Done-path clean return therefore has no valid screenshot. Granted because the fix is verified in source, the substantive claims are evidenced by `-03`/`-04`, and the operator approved the flow in use. |
| PF-C2.12 focused exception-resolution step | NOT ACCEPTED | CPI | 2026-07-21 | `Element10_PFC2_12_REVIEW.zip` SHA-256 `191c85f843eb057001663701e71ee93a377e8d5376f9ac0473c11175886f8535`; screen 08 `92ff97ee...`. The redesign itself is correct and confirmed by pixels — the focused surface (scoped to 160 rows, matching reason stated, remaining count) and the strengthened marking (tint + edge + per-row badge + tagged-only toggle) close three rounds of "no focal point". Rejected on: `excFocusDone`/`excFocusCancel` call `drawImport()` without repainting `#main`, leaving the focused surface behind the dialog (visible in the reviewer's own screenshot; `closeReview` does it correctly four lines away); and the rule-6/7 unhappy-path screenshot shows a resolved exception with no refusal and no blocked approval, not the cancelled path it claims. |
| PF-C2.11 resolution-must-be-earned + column sizing | GRANTED | CPI | 2026-07-21 | `Element10_PFC2_11_REVIEW.zip` SHA-256 `1dd413ff32bd5ee44c0dc5e57ab955a219f4faede412ed0ac94a5f0b25b629b1`; screen 08 `df957ff2fe9b084a3616a8a61a8146ac4dd5a8dcce195806ac6fad4bdb828b1c`. CPI-verified: Edit inline renders only where `e.parallel` exists; `impResolve` refuses without mutation otherwise; zero-match leaves `resolved` false and the exception in `impBlockers`; no `undefined` in operator text; `autoColWidth` content-aware with operator resize still winning. The remaining operator complaint is an interaction-design gap, not a defect in this code — carried to PF-C2.12. |
| PF-C2.10 paint marking + component alignment | NOT ACCEPTED | CPI | 2026-07-21 | `Element10_PFC2_10_REVIEW.zip` SHA-256 `157da5d64b6652ee0954ac3156ae1e329b6b25d3d0ab746e44218651dbedb202`; screen 08 `2fa42e7e...`. The PF-C2.9 marking defect IS fixed and confirmed by pixels — CPI opened `pfc210-marked-rows.png` and verified `tr.edited-row td` tint plus `td:first-child` amber edge painting. Rejected on a defect found in operator testing that the screenshots could not catch because all five captured working paths: `impResolve` marks an exception `resolved` unconditionally, so Edit inline on `e5` "Exclusivity resolves to nothing" performs nothing, prints `undefined`, and clears itself from `impBlockers` — a no-op discharging a blocking decision. Same class as `gApprove`. Also `table-layout:fixed` with even widths truncates every column. |
| PF-C2.9 bulk-bar safety + column catalog | NOT ACCEPTED | CPI | 2026-07-21 | `Element10_PFC2_9_REVIEW.zip` SHA-256 `22b3e7db3559f8a10b09abca132b9daff8d2fa3329f180d0217ba77cd501a6e2`; screen 08 `b05a76e2...`. Findings 1, 2, 4, 5 verified in source (no-preselect bulk bar, confirm-in-place, per-surface column catalog with admin-only minting, zero native dialogs). Rejected: the edited-row marking was `box-shadow:inset` on a `<tr>` under `border-collapse:separate`, which generates no paintable box — correct markup, zero pixels, reported by the operator twice. Evidence asserted "amber-edge rows render" from DOM presence. Standing rule 7 was created here. |
| PF-C2.8 grid preferences scoped per organization | GRANTED | CPI | 2026-07-21 | `Element10_PFC2_8_REVIEW.zip` SHA-256 `239caa62ca9923966b96f87b61d73a3fd097f6c086028960558e04733c4caab4`; screen 08 `a53e0c14eb2863cc50618ce7ee766c8624f2e05a0a7df750f397c4d57cd43465`. CPI-verified: all preference access routes through `gridPrefsRoot()` → `S.gridPrefs[S.org]`, zero unscoped `S.gridPrefs[` reads remain; `gridSavePrefs` prunes to current `spec.cols`; `grRemoveCol` drops from prefs, spec and order together. Cards-off scan re-run with the condition created first. Full regression sweep clean. |
| PF-C2.7 shared grid component | NOT ACCEPTED | CPI | 2026-07-21 | `Element10_PFC2_7_REVIEW.zip` SHA-256 `166f7d2dc684d02f131b1f4fad166b127e25adf902a9ef026170d0ae78104856`; screen 08 `419e72dd...`. The component itself was correct — single `S.grid`, spec-driven `gridEnsure`, both consumers migrated, old `gridFiltered`/`g*` stack genuinely removed, resize and reorder real, per-action `can()` enforced in both entry points. Rejected on a tenant boundary defect: `S.gridPrefs` never cleared or scoped, Products spec id literal `'products'` for every organization, so an operator-added column and its typed label crossed from one organization to another — and could carry card vocabulary into a cards-off organization. The scan reported clean because it ran before the condition was created (standing rule 6). Superseded by PF-C2.8. |
| PF-C2.6 corrective + eight operator findings | GRANTED | CPI | 2026-07-21 | `Element10_PFC2_6_REVIEW.zip` SHA-256 `1498f138a1a99b63d31b196955fb1d97b964db315d35a627efbe37292a22fae6`; screen 08 `9b1bf0761908ab2aba9641e9ef8ffef39a606741db0fc947b6fe6c4003605cea`. CPI-verified: `gApprove` reads `_seenReview` and refuses; select-all page-scoped with disclosed escalation to all matching; bulk actions confirm with exact counts and `gConfirmBulk` snapshots for undo; channel confirmed once at step 4 and still blocking if untouched; exclusivity fixtured across configuration / channel / route / unresolvable; scroll preserved in `drawImport`; column union via `buildGridCols`; cost seam text-only; forbidden list 20 → 28. Granted against its brief as dispatched — the shared-grid obligation was appended by the CPI after drafting and was carved out into PF-C2.7. |
| PF-C2.5 identity step + checklist grid | NOT ACCEPTED | CPI | 2026-07-21 | `Element10_PFC2_5_REVIEW.zip` SHA-256 `c4f94ffc010bf193ba05cc676dd096100923b6f1d97ab5eda1e5e4ddaffa1cd4` — hashes verified clean, `e10.css` frozen. Rejected on three defects: `gApprove` sets `reviewed=true` without verifying a review occurred (`_seenReview` set but never read — dead guard, PF-C2.3 defect inverted); `gSelAll` selects all matches while the grid renders 200, scope undisclosed; no undo and `gBulkRemove` is immediate and irreversible. Reviewer's own evidence bullet 2 exhibited defect 1 and reported it as a pass (standing rule 5). |
| PF-C2.3 + PF-C2.4 document-driven setup | GRANTED | CPI | 2026-07-20 | `Element10_PFC2_4_REVIEW.zip` SHA-256 `7d4eefe32df5bd90198af8206d3dc28f021c0321f1582893f45bf8cd17254983`; screen 08 `1826b15f...`. CPI-verified: `in_setup` assigned in `saveForm` (reachable, not dead UI); `markReady` refuses at zero configs; channel raised as inferred decision blocking approval with basis shown. |
| PF-C2.1 configuration model corrections | GRANTED | CPI | 2026-07-20 | `Element10_PFC2_1_REVIEW.zip` SHA-256 `d9352dcfa3548699797f8850a6190e08af8c72d139765c3c259fa4dd34092f78`; screen 08 `e3d392f7...`. Nested references, dual cycle guards, dependent warnings, append-only versioning — banked; the importer writes into this model. |
| PF-C1 Product Master | GRANTED | CPI | 2026-07-20 | `Element10_PFC1_3_REVIEW.zip` SHA-256 `f522cf4fbbb1495ae81ab56613343a061bd2ae514d816e06572d9e2c83036b24`; screen 08 `1fec03464f614c75a2e1582de1acd85d260c8fb9cd69e0eff8642771787cb29e` |

## NEXT PROMPT TO SEND

This section is written and replaced only by the Chief Project Inspector at each
reconciliation. Each agent executes ONLY its own subsection and ignores the other.
If your subsection says ALREADY DISPATCHED, do not re-run it.

**STATUS 2026-08-20 — both charters below are SPENT. Do not re-run either.**

| Track | Live charter | Hash / bytes | State |
|---|---|---|---|
| B | **SPRINT B3** (PF-C4 preflight) | see `Streaming/SPRINT_PLAN_INVENTORY.md` | **READY. PF-M4 is COMPLETE (B1 + B2.1 granted) and PF-C4 is UNBLOCKED** — the model gate that stood in front of purchasing and receiving is cleared. B3 is the workflow preflight; no implementation until the CPI reviews it. Then B4–B7 build purchasing, ending in the first operator walkthrough. |
| A | — none — | — | **TRACK A IS PARKED (Trent, 2026-08-24).** Not blocked, not waiting on anyone — deliberately stood down. See "TRACK A PARKED" below. Only A2 (step 8's client-side pagination) remains dispatchable, and it is optional. Do not queue execution work. |

**Census source for PF-M5.1**, relayed by the CPI, repo HEAD `50d34cd`
(one unaudited/undeployed commit ahead of prod; STEP8's `index.html` diff touches
only the inventory read path and changes ZERO catalog writes, CPI-verified):

| file | SHA-256 | bytes |
|---|---|---|
| `index.html` | `68243547d07149943ebe1ebad742338d1d4bd805715cc215db9f113683fefba0` | 445,295 |
| `companion.html` | `6a587465f3af369744a4235733f0c26a949416d0c9e88f73a8522653e6a35efe` | 10,404 |
| `overlay.html` | `294a87fa1aae5e5b9761e6e95ee9ded31879428763e4c5e6d7b5ea8fda5f5119` | 28,195 |
| `open.html` | `f24d000a4e9e004976c41cde4b6e871971258ddea71969b16b67ab068f663509` | 26,671 |

**Never census** `Streaming/archive/DO_NOT_CENSUS__prerelational_blob_app_jul3__NOT_THE_CLIENT/`
(renamed 2026-08-20). It is the pre-relational blob app; it holds zero catalog
writes and returns a clean-but-false result.

---

### SPENT — TRACK A — Claude Code — CHARTER (A8-DRILL2 · the last two rehearsals)

## 1. AUTHORITY
- Charter: **A8DRILL2 rev 1**, 2026-08-04. Verify SHA-256 against the dispatch
  message; execute only on exact match. Not amended mid-flight — reissued whole
  if it changes.
- A8-PREP is ACCEPTED (CPI reproduced the canonical checksum
  `f54a1fe978614e21cf2ffb8c63afb475` independently; production verified
  untouched). Baseline: accepted code head `faab6f4`.
- **PRODUCTION IS NOT TOUCHED.** Reads for verification only. This charter does
  not and cannot grant execution authority.

## 2. WHY THESE TWO REMAIN
A8-PREP closed idempotency, recovery scripts and the checksum. Two gaps stand
between the plan and an execution proposal, and both are the kind that only
show up under real conditions:

**D1 — P4/P5 recovery has never been rehearsed as what it actually is.**
F6 established that P4 is effectively irreversible by forward script and that
recovery means restore-from-backup plus a coordinated client revert. That is
now *understood* but never *drilled*. Rehearse it end to end on the scratch
restore: take the pre-P4 backup, run P4 (and P5), then recover from that backup
and prove the database returns to the exact post-P3 state (canonical ledger
`f54a1fe9…`, fingerprints, policy/RPC inventory). Report the **wall-clock time
to recover**, because during an incident that number is the decision. State
what the client-side revert requires in the same terms.

**D2 — lock contention is unexercised.** A single-connection rehearsal measures
duration, not what a live writer experiences. Run the concurrent-writer exercise
A8-PREP proposed: hold realistic write traffic against the scratch restore
(inserts/updates on the retrofit tables and the ledger) while each phase runs,
and report actual lock waits, blocked-query durations, and whether any step
escalates beyond its predicted lock. The zero-downtime claim rests on this.

## 3. WHAT AN HONEST OUTCOME LOOKS LIKE
Either is acceptable and both must be reported plainly:
- the phases hold under contention and recovery is fast → the execution proposal
  carries real numbers;
- something blocks, escalates, or recovery is slow → **that is the finding**, and
  it changes the plan or the window rather than being smoothed over.
Do not tune the exercise until it passes. If a phase cannot be made
contention-safe, say so.

## 4. HARD STOPS
Production would be written · a drill reveals a plan defect needing re-planning
rather than patching · a contract question arises · the charter boundary.

## 5. DELIVERY
The D1 recovery drill transcript (including wall-clock recovery time and the
client-revert requirement), the D2 contention transcript (lock waits per phase
under load), any findings, and an updated plan §8 with real contention numbers
replacing estimates. Re-prove production untouched. Propose the BOARD.md delta;
do not self-accept. Report "A8-DRILL2 ready for independent review."

### SPENT — TRACK B — Claude Design — CHARTER (C-POLISH · friction fixes + connective features)

## 1. AUTHORITY
- Charter: **C-POLISH rev 1**, 2026-08-05. Verify this file's SHA-256 against
  the dispatch message; execute only on exact match. Self-contained, sole
  authority. **Not amended mid-flight** — reissued whole with a new hash if it
  changes.
- Working model: CHECKPOINT. Work the gates continuously, self-review and record
  each, continue without waiting. External review once, at the end.
- Baseline: accepted C-SELL.1 — build
  `d1463b000661964f90fbf564cc741a6726f1499dec78edd6537a06a395abf9ab`;
  package `cb19953facfc9abd9cf98c1b4f678f978368d376a8a5060a2dab338aeda84440`.
  Verify before editing. FROZEN: screens 01-07, `e10.css` `cd37cd43...`.
- Source: a CPI-driven exploratory session across product, checklist, inventory
  and acquisition workflows. **Zero behavioural bugs were found** — everything
  below is friction or absence, not brokenness. Do not "fix" working behaviour.

## 2. GATE 1 — interaction friction (four items)

**1a. The setup wizard's step 2 has no Back.** Steps 3, 4 and 5 all do. Choose
the wrong publisher and the only exit is Cancel and start over. Add Back to
step 2 (→ step 1), matching the other steps' placement and label exactly.

**1b. Unlabeled buttons in the review/checklist grid.** The per-column filter
controls render as blank slivers — invisible unless you already know they exist.
Give them a visible affordance and an accessible name (`aria-label`/title).
Audit every grid for other zero-text buttons and report the list.

**1c. Checklists empty state renders "Set up from documents" TWICE** — two
identical adjacent buttons. One button; make the empty state say what a
checklist is for and how one arrives.

**1d. Enter does not submit anything.** In a data-entry app this is real
friction. Implement precisely:
- Enter in a **single-line input** inside a dialog triggers that dialog's
  primary action (the same function the primary button calls — never a
  duplicate code path).
- Enter in a **textarea** inserts a newline; never submits.
- **Enter while a suggest/picker is open selects the highlighted item and does
  NOT submit** — the picker owns the key while it is open. This is the one that
  will break if implemented carelessly.
- Enter never bypasses a validation, a dirty-guard, or a confirmation step.
- Escape's existing behaviour is unchanged.

**1e. OPTIONAL, operator's call:** unbuilt nav items (Home, Live, Fulfill,
Schedule, Money, Breaks, Repacks, Settings) are inert — clicking does nothing
with no feedback. The operator has ruled this acceptable (not built yet). If
implementing costs little, give them the same treatment already accepted for
global search ("— coming later"): visibly non-interactive rather than silently
dead. **Skip this if it is not trivial; it is explicitly not required.**

## 3. GATE 2 — connective links (the data is siloed)
Three one-way links, each on a detail surface, each excluded from the nav rail:
- **Card → the checklist/product it was autofilled from.** A card enriched from
  a checklist currently has no route back to it.
- **Product → the singles owned from it.** Today you must go to Card inventory
  and filter by hand. A link into a pre-filtered card inventory is sufficient;
  do not build a new surface.
- **Acquisition → its vendor record**, when a Vendor (not a free-text seller) is
  attached.
Where a link cannot be honest — a hand-entered card that matched no checklist —
render nothing rather than a dead or guessing link.

## 4. GATE 3 — two missing lifecycle actions

**3a. Duplicate a card** ("I bought three of the same"). From the card detail.
Specified, do not improvise:
- **Carries:** acquisition, name, brand, line, set, card number, parallel,
  print run, year, team, and asking price.
- **Clears:** serial (copy-specific), and **all three grading fields**
  (company, grade, cert) — cert is unique per slab, and carrying only two of the
  three would violate the accepted raw-or-graded invariant.
- Opens the new card in the normal Add-card form, pre-filled, **creating
  nothing until saved through the single guarded path.**

**3b. Archive an acquisition.** Products, vendors and cards can all be archived;
acquisitions cannot, so a mis-entered one is permanent. Archive-not-delete, same
discipline as elsewhere. **Decide and state:** what archiving an acquisition
means for the cards referencing it (they must not become orphans — the accepted
model requires exactly one acquisition per instance). Refusing to archive while
active cards reference it is an acceptable answer if you say so plainly.

## 5. GATE 4 — bulk management on card inventory
The singles grid has no selection column, so there is no multi-archive and no
multi-edit; every correction is a round trip through the detail page. **Reuse
the ACCEPTED checklist-grid bulk pattern** — no new mechanism, no preflight
needed, because that workflow is already accepted: page-scoped select with the
disclosed "select all N matching" escalation, confirm-in-place naming the exact
count, and undo of the last bulk action.
- Actions: **archive** (never delete), and set-a-field for the safe identity
  fields. **Cost basis is never bulk-editable** — it is not form-writable at all.
- Every bulk action fails closed on its own `can()` per standing rule 1.

## 6. GATE 5 — beyond 200 rows (shared component — most care)
The grid caps at `GRID_CAP=200` with "first 200 shown" and no way to reach the
rest but filtering. This touches EVERY grid, so:
- **Produce a short preflight for this gate specifically** (the task-loop fields
  plus the state/transition map) and ship it in the package for CPI review
  alongside the implementation. If the preflight reveals a conflict with
  accepted behaviour, STOP and report rather than proceeding.
- **The accepted select-all semantics must survive exactly**: header checkbox =
  the visible page, with an explicit disclosed escalation to all matching. If
  pagination makes "page" ambiguous, that is a finding, not something to
  smooth over.
- Preferences (columns, widths, order, sort) keep persisting per org per grid.

## 7. STANDING RULES — in full, unchanged
1. Every mutator/opener fails closed independently on capability, organization,
   archived state, and module entitlement. 2. Cost basis is never form-writable
   or bulk-writable. 3. Cards are never created as blanks; one guarded creation
   path. 4. Rendered defaults live in state. 5. No native dialogs or suggest
   popovers. 6. Dropdowns dismiss on outside click, Escape, focus departure;
   no-result states offer an affirmative close. 7. A host is never repainted
   during an in-flight interaction; programmatic focus is not user focus.
8. Compact provenance: glyphs plus one summary line. 9. Forbidden list 28+
minimum (36 live), scan `#app`+`#ovhost`+`#toast` with dialogs open.
10. Cross-org isolation on everything including preferences and vocabularies.
11. Evidence classes stay separate. 12. Render claims need correctly-captioned
screenshots showing what they claim. 13. A failing test is never replaced by a
differently-constructed passing one. 14. Never call an unbuilt stage "next".
15. **Every artifact a charter names as input or output lands in the shared
folder with its SHA-256 and byte size — the charter author supplies the inputs,
the builder relays the outputs, and neither cites a path the other cannot
reach.** **RELAY TOPOLOGY, established 2026-08-31 and the root cause of the
earlier "delivered but not reachable" incidents: the builder agents CANNOT write
to the repo or the shared folder at all.** They produce files in their own
workspace; the operator places them; the CPI verifies. So a delivery naming
`docs/product-first/…` was never a false claim — it was the builder naming a
path in ITS OWN environment, which the CPI then searched for in the repo and
did not find. Consequences, binding: a builder states the filename and its
**SHA-256 + byte size**, never a destination path it does not control; the CPI
verifies bytes on arrival and never infers non-delivery from a path miss; and a
builder's environment may legitimately contain tooling and vocabulary that does
not exist in Element 10 — that is not a finding, but work done there is out of
charter scope and unauditable, so it is never evidence. Earned twice in one day, 2026-08-20: PF-M5 reported a
`docs/product-first/` path for files that were not there, and PF-M5.1 then
charter-directed a census of a deployed `index.html` the builder had no copy of.
A stale clone sat in the shared folder under a repo-like name and would have
returned a clean-but-false census; the builder stopped instead, correctly. **A
census, audit, or build against a source whose identity is not hash-pinned is
not evidence.** When an agent cannot reach a named input, that is a hard stop
and the charter author's defect to fix, never the builder's to work around.

## 8. EVIDENCE
- **Mandatory self-debug sweep first, every gate** (`tests/harness/selfdebug.js`
  — it now walks dialogs, tests opener entitlement, and checks cards-off DATA).
  Green or every failure explained before scenario evidence.
- Two materially different passes; ship the **executable scenario files**, not
  only logs.
- Enter-key behaviour needs its own adversarial scenarios: Enter in a textarea,
  Enter with the picker open, Enter on an invalid form, Enter with a dirty guard
  pending. Prove each does the right thing.
- Full S1.x/S2.x/C-SELL regression. Cards-off and org-isolation sweeps.
- Screenshots must visibly contain what their captions claim.

## 9. DELIVERY
`Element10_CPOLISH_REVIEW.zip` + a DROP zip the CPI can unpack for the canonical
harness, full 64-char hashes, manifest `shasum -c` clean, checkpoint log with
each gate's provisional result, chain rooted at `d1463b00...`. **Do not update
BOARD.md and do not self-accept.** Report "C-POLISH ready for independent
review."

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
- A6c.0 additive prerequisites (accepted 2026-07-20)
- A6c.1 + A6c.1.1 RLS rewrite (accepted 2026-07-26; commits `7138716`/`d2ad844`,
  CI `30206547507`/`30207551465`)
- A6c.2 + A6c.2.1 wrapper cutover + authority corrective (accepted 2026-07-27;
  commits `0a7da40`/`8152f2d`, CI `30211865339`/`30260835702`)
- Accepted repository **code** head: **`8152f2d`**. Baseline history:
  `53501928...` (A6a/A6b) → `7f0d383` (A6c.0) → `d2ad844` (A6c.1.1) →
  `8152f2d` (A6c.2.1). Diff future work against `8152f2d`.
- CI green: run `29768281886` (A6c.0); prior `29688509320` (A6b)
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

- **A6c.0–A6c.4 + A7 ALL GRANTED. The engine authorization series is COMPLETE.**
  Accepted code head `6eab46a`. Staging carries the full multi-tenant model,
  proven against 11 hostile identity classes with zero findings.
- **A8 is the active gate — the production path begins.** Everything to date has
  been staging-only by design. A8-A10 carries the model to production, including
  the cross-org catalog write hole that A6c.4 closed on staging and that remains
  OPEN in production today. Production is read-only until A10.
- Before A8 builds: it needs its own authorization plan reviewed the way A6c rev 6
  was — this is the only irreversible sequence in the project.


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

**Rewritten 2026-08-11 (maintenance rule). The prior text still said "A8
PLANNING ONLY — author the plan"; the plan was ACCEPTED 2026-08-03, C-REHEARSE
and A8-PREP are both accepted, and A8-DRILL2 is in flight. 6th instance of the
CPI stale-board defect.**

1. **A8-DRILL2 IS THE CURRENT WORK — in flight.** Rehearse P4/P5 recovery AS a
   backup-restore drill with real wall-clock recovery time; exercise lock
   contention with concurrent writers. Production remains READ-ONLY.
2. **THEN: the execution go/no-go — Trent's explicit decision**, with F6 on the
   table (P4 is effectively irreversible; recovery is backup-restore plus a
   coordinated client revert, incident-level).
3. **A8-P5 stays BLOCKED on Track B's PF-M5 curation path** — the production
   catalog write hole cannot close until operators have another way to create
   checklists and cards.
4. Still unbuilt on the Track A order: **step 8 bounded reads** (cursor
   pagination, server-side filtering, retire `e10_inv_list`), **step 9 realtime
   scale strategy** (org-filtered operational subscriptions; Broadcast for
   high-fanout audiences), and **step 10's load proof** at 2x defined workload.
5. Propose the BOARD.md delta; do not self-accept.


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

- **PF-C-S1.6 ACCEPTED 2026-07-26** (`fd47e461...`, screen 08 `d2065b29...`) —
  the singles surface carries: guarded-only creation (zero blanks), unwritable
  cost basis, required name/brand/line/year, duplicate-cert refusal via composed
  titles, raw-duplicate warn-then-save, Distribution rename, Checklists entry
  point with origin-aware landing, inert search. Full S1 arc S1..S1.6 GRANTED in
  the ledger.
- [x] **PF-C-S1.7 + PF-C-S2 ACCEPTED 2026-07-27** (full protocol run: preflight → review → ruled baseline → implementation → audit 12/12 → operator walkthrough)

- **PF-C-S2 OPENED MID-FLIGHT BY DIRECT OPERATOR AUTHORIZATION** (Trent,
  2026-07-27, hands-on): the assignment workflow (assign → review → approve,
  single writer, dirty-guarded draft, under-assignment shown as explicit
  remainder, adjust-anytime) was built into the same working file and the
  package rebuilt (zip `88c9b8c5...`, screen `875422ab...`, supersedes the
  Phase-2-only hashes `e5c4e1ca...`/`99dd7a3f...`). The agent exceeded the
  relay scope on operator instruction and FLAGGED it — correct conduct under
  the protocol; operator authority outranks the relay.
- **S2 conformance ruling (Trent, 2026-07-27): the July-21 admin-only
  over-assignment ruling STANDS.** The delivered flat cap is a conformance
  defect: ordinary operators are refused past total paid; an admin may exceed
  it with the over-assigned state recorded and visibly flagged
  (`singles.cost_assign_over`, PROPOSED). Corrective required in the S1.7+S2
  audit round.
- S2 remaining scope, unchanged: acquisition channel + landed-cost components;
  the assignment "Adjust" flow may overwrite freely ONLY until S3 dispositions
  exist — from S3 on, corrections to sold cards' basis are additive events per
  PF-M2.1 §4.2 (seam recorded). Per-acquisition margin reporting stays S5. per
  `docs/UX_WORKFLOW_CONTRACT.md` + `docs/OPERATOR_LIFECYCLE.md` §9 — no
  implementation until the CPI reviews the preflights. See NEXT PROMPT TO SEND.
- Then: S2 cost assignment (expanded scope: acquisition channel, landed-cost
  components, assignment workspace, admin-only over-assign) → S2.5 intake
  workspace → PF-M3 Listings (blocks S3) → S3 disposition → S4 repack →
  S5 reporting. PF-C4+ sealed purchasing runs independently.
- Frozen: screens 01-07; `e10.css` at `cd37cd43...` (twenty accepted editors).

### Superseded gate history (July 20) — retained for provenance

### PF-C1 closure history (accepted — retained for provenance)

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

### Standing UI contract (Trent, 2026-07-21) — binding on every screen

- **The operator task is the unit of design.** Read
  `docs/OPERATOR_LIFECYCLE.md` and `docs/UX_WORKFLOW_CONTRACT.md` before planning
  or building a workflow. A component-complete screen with an incomplete task
  loop is not accepted.
- **No dead-end success states.** Every successful mutation shows its committed
  result and offers a state-aware continuation, review/correction path, and safe
  exit. A toast is feedback, never navigation.
- **Scope does not suppress observation.** An agent may not implement an
  unapproved adjacent model or authority contract, but it must identify the gap,
  preserve an honest seam, and report it to the CPI.
- **Navigation preserves origin and work context.** Detours and edits return with
  the parent object, route, filters, selection, unsaved state, and focus intact.
  Parent detail is the durable resume surface for interrupted child-entry flows.
- **Workflow preflight precedes implementation.** Every new or materially changed
  workflow defines its entry, commit, success, continuation, review, Back/Cancel,
  repeat, resume, recovery, and lifecycle handoff before code.
- **Workflow evidence is behavioral.** In addition to render screenshots, prove
  first-time, repeat, incomplete/resume, final-item, edit/return, Cancel, and one
  denial/conflict recovery path.
- **One walkthrough is never acceptance.** Follow
  `docs/OPERATOR_WALKTHROUGH_PROTOCOL.md`: run baseline and materially different
  adversarial passes across the lifecycle, interruption, boundary-transition,
  mutation/invariant, and temporal/input tours. Every finding expands to its
  invariant and sibling paths. Builders report ready for independent review;
  only the CPI records acceptance after the required operator ruling.
- **A resolution must be earned.** No action may mark an exception, gate or
  decision resolved unless it actually performed the resolution. An action that
  changed nothing leaves the blocker standing. Same class as `gApprove` asserting
  a review it never had.
- **Every screen requires an operator walkthrough gate** (Trent, 2026-07-21).
  Applies to screens built or regenerated under the product-first pivot, including
  everything PF-C21 produces. It does NOT apply retroactively to frozen pre-pivot
  evidence. A screen is not accepted on a CPI source audit alone. The operator works it
  hands-on and the walkthrough is its own checkbox on this board, recorded like
  any other gate. This formalises what happened by accident on the product setup
  flow, where three of the four rejections in that sequence came from operator
  use rather than source review — including the two the CPI could not have found
  by reading code.
- **A new surface must follow the patterns already in the file.** Three
  consecutive gates reinvented an existing correct pattern slightly wrong:
  duplicated grid logic (PF-C2.7), `drawImport()` without repaint when
  `closeReview` did it right (PF-C2.12), `route()` without leaving the edit route
  when `closeForm` did it right (PF-C3). Before adding a surface, find the nearest
  existing equivalent and match it, or state why it should differ.
- **Screenshot captions are part of the evidence.** A screenshot must be captioned
  with the state it actually shows, and its filename must match. Three consecutive
  gates submitted images captioned as states they did not depict. A miscaptioned
  screenshot is worse than no screenshot: it reads as proof while proving nothing,
  and it hid a real defect once (the PF-C2.12 overlap was found in one by accident).
  Where a claim is about a transition, capture the state immediately after it and
  say what was pressed.
- **Standing rule 7 — a render claim needs a screenshot.** Any assertion that
  something renders, displays, appears, is visible or is marked must be evidenced
  by a screenshot of it rendered. Source inspection and DOM queries do not
  establish paint. Added after `box-shadow` on a `<tr>` under
  `border-collapse:separate` produced correct-looking markup that painted nothing,
  through two gates.
- **Polish inside the shared component is structural, not cosmetic.** A spacing or
  alignment defect in the grid reproduces on every surface using it. Cosmetic
  tolerance applies to one-off screens only.
- **A rendered default must exist in state** (2026-07-26, from the "Cards to
  create" field rendering 5 while state held '' — what the operator sees must be
  what state holds; render echoes state, never invents fallbacks).
- **No native suggest popovers** (`<datalist>`, OS-rendered autocomplete) on any
  field — extension of the no-native-dialogs rule, same reasons: outside the scan
  hosts, off-theme, un-auditable. Plain `<select>` for short enums stays allowed.
- **One basis, one line**: when several fields share a single provenance basis,
  show compact per-field glyphs plus one summary line — never the same sentence
  repeated per field.
- **A host is never repainted during an in-flight interaction with it** (2026-07-26,
  from the S1.5 picker: a capture-phase mousedown repaint destroyed the suggestion
  row before its click completed — same family as the S1.3 caret loss). Repaint
  only what actually changed, after the interaction settles.
- **The operator is not the debugger** (2026-08-03). Before any evidence pass,
  the builder runs the mandatory self-debug sweep (`tests/harness/selfdebug.js`)
  on every touched surface: every input typed into with the live node
  re-acquired per keystroke, every button clicked and checked for errors and for
  changing something, every dialog proven dismissible, native popovers checked,
  cards-off scanned per surface. Green or every failure explained BEFORE
  scenarios begin. Basic brokenness — unclickable controls, reversed typing,
  dead buttons, dead-end saves, undismissable dropdowns — is the builder's to
  find, never the operator's. Protocol §6a.
- **Evidence production is never single-homed** (2026-08-01, after a wedged
  preview blocked a whole track). The five evidence classes are independently
  satisfiable; only render needs a renderer. Canonical tool:
  `tests/harness/e10_harness.js` (node + jsdom, real DOM events, exit 0/1,
  CI-usable) — any agent runs the same tool on the same build. A renderer
  outage degrades the render class only, disclosed by scenario id; it never
  blocks a gate. See protocol §8a.
- **Canonical harness delivery pattern** (proven 2026-08-03): a builder whose
  sandbox lacks node, or lacks write access to the shared folder, delivers a
  DROP ZIP (build + frozen css + BUILD.txt) alongside its package; the CPI
  unpacks it and runs `tests/harness/e10_harness.js` — the canonical tool —
  against the delivered build. A ported harness is acceptable for the builder's
  own passes IF the port is disclosed, but only the canonical run counts as
  independent verification. This closed the loop on S2.3 and is the standing
  pattern.
- **A build must be reachable before it can be evidenced** (2026-08-01). Any
  agent delivers its compiled build to the shared folder as soon as it
  compiles — before evidence, before packaging. A build living only inside one
  workspace is unverifiable and unauditable by anyone else.
- **Every mutator on a vertical surface fails closed on the module entitlement
  itself** (2026-07-27, from S2.1 adversarial F2): `cardsOn()`-class checks live
  in the mutator, independent of the UI being unreachable — alongside
  capability, organization, and archived-state checks.
- **Every dropdown, picker and transient panel dismisses on outside click,
  Escape, and focus departure** (Trent, 2026-07-26: they "consistently don't go
  away"). A no-result state is still a dropdown and additionally offers an
  affirmative close action. Every new overlay states its dismissal paths in
  evidence.
- **No browser-native dialogs.** `alert` / `confirm` / `prompt` render outside
  `#app`, `#ovhost` and `#toast`, so the cards-off scan cannot see them. Any
  affordance that renders outside the scan hosts is invisible to the control that
  proves the tenant vocabulary invariant. All dialogs render in-app.
- **One shared data grid component** across all tabular surfaces. Per-column
  filter, sort, show/hide from the data's own fields, resize, reorder, inline
  edit, selection. Select-all discloses scope; bulk actions confirm with counts
  and are undoable. Which bulk actions exist is per-surface; the mechanics are
  shared. Grid preferences (columns, widths, order, sort) persist per user per
  grid, carry no authority, and never widen visibility. Read-only users keep
  every non-editing capability.

### Product domain rulings (Trent, 2026-07-20 walkthrough) — binding on schema

- **Channel is four separate concepts, never one field** (outside review,
  ratified 2026-07-26). Distribution class (Hobby/Retail, on a configuration —
  field renamed "Distribution"); acquisition channel (distributor / eBay / show /
  collection / trade, on an Acquisition); sales channel (Whatnot / eBay / Shopify
  / direct / show, on a Listing/Disposition); fulfillment route (shipped / pickup
  / break shipment). No surface may reuse one for another.
- **Cost basis is never a free-typed field** (outside review caught the build
  contradicting approved PF-M2.1 §4.2). Single-purchase cards derive basis from
  the acquisition; collection cards stay locked at zero until S2 assignment;
  every later change is an additive adjustment event with reason and old/new.
- **A Listing is its own entity and must be modelled (PF-M3) BEFORE S3
  disposition.** Listing references a CardInstance and carries channel, external
  id, SKU/title, asking, status, timestamps, fees, reservation, sync state. This
  is the double-sale guard. S3 does not build until PF-M3 is approved.
- **Multi-location ruling (Trent + outside review, 2026-07-27 — REPLACES the
  CPI's earlier over-specified version, which asserted physical design without
  reading the mechanisms):** Locations operated by one tenant are
  organization-owned facilities, not separate tenant boundaries. Inventory and
  operational facts must be designed for location-level AND
  organization-consolidated reporting. **PF-M4 must settle — and be approved
  BEFORE PF-C4 physical-schema implementation, and certainly before PF-C5
  receiving:** inventory positions (per-location balances vs child-lot splitting
  vs whole-lot-only — a lot CAN be split between stores; CardInstance's single
  current location is the natural nonfungible case), transfer postings (the
  current movement writer has NO transfer semantics: zero-net returns null, a
  single nonzero delta shifts org-wide on-hand — transfers need paired postings
  or a transfer event with derived postings proving source≠destination, same
  org, sufficient free stock, -q/+q, org-net zero, atomicity, idempotency, and
  no stranded or silently moved reservations), reservation locality (lot_free
  is lot-level today; a show at Store B cannot treat Store A stock as
  fulfillable — confirmed reservations likely bind to a location position),
  in-transit behavior (NOT automatically additive later: needs transfer
  identity, stateful postings, partial receipt and discrepancy handling —
  reconcile with DOMAIN_MAP's existing five-axis custody model incl.
  `in-transit` and `pending-transfer`), permissions, and historical reporting
  (events retain the location applicable AT EVENT TIME; a current-location
  pointer alone distorts yesterday's reports). Default location per org and
  location-UI-only-when-plural stand as UX decisions. "Never a second
  organization" is scoped: franchisees, separate legal entities, currencies, or
  independently administered businesses may still be separate organizations,
  with a future reporting-group concept for cross-org rollup — not designed
  now.
- **Sale-commit is its own authority, separate from inventory editing** (Trent,
  2026-08-04, commercial ruling). Committing a sale writes a financial record
  (disposition + margin), so `singles.sale_commit` is granted apart from
  `act.inventory_edit`: a team member may enter, identify and cost cards without
  being able to close a sale or set the recorded price. `singles.listing_write`
  and `singles.listing_publish` likewise sit below it (advertising is not
  selling); `singles.conflict_resolve` accompanies sale authority. In the
  prototype these may be simulated, but the simulation must be LABELLED as such
  and must model the separation — never collapse them to `canWrite()` while
  claiming distinct enforcement. Persistence is Track A's, later-additive.
- **The double-sale guard lives at the sale commitment, never at publication**
  (PF-M3, approved 2026-08-03). Listings are advertisements, not holds — an
  instance listed on N channels stays active and on-hand. At most one sale
  commitment per CardInstance ever, serialized at the instance boundary with a
  post-guard reread and an idempotency key; siblings auto-end `superseded`
  inside the same atomic commit and carry delist obligations. Concurrent channel
  sale claims are ordered by ARRIVAL AT THE AUTHORITATIVE BOUNDARY, never by
  channel clocks; the loser is refused with zero mutation and produces a
  SaleConflict for evidenced operator resolution — never an auto-refund, never a
  second Disposition.
- **Two writable numbers describing one truth will diverge; a derived total
  cannot disagree with its parts** (ratified from `PFCS2_3-PREFLIGHT-1`,
  2026-07-31). Where a total and its breakdown both exist, the components are
  the stored facts and the total is derived, with exactly one writer of any
  cache. Track A design input: `cost_components` + org-scoped
  `acquisition_channel` vocabulary persistence (org-scoped RLS, CAS on
  component writes, money as integer cents).
- **Purchase-order approval (Trent, 2026-08-31, answering PF-C4 preflight
  §4.8):** **a PO requires approval above an org-set threshold**, mirroring the
  transfer ruling. Small reorders commit on save; large commitments need a
  second person. Threshold is an org setting, not a model constant. Uses the
  §B7 mechanism (revision-bound states, self-approval recorded, fail-closed when
  unset) with a **distinct `purchasing.approve` capability** — a
  `purchasing.write` holder must not self-authorize by capability collision.
  Money-increasing amendments are in scope for approval; money-neutral and
  money-decreasing ones are not.
- **Transfer and write-off approval (Trent, 2026-08-31 — the ruling B2's hard
  stop should have asked for):** **Inter-location transfers need approval above
  a threshold** — small moves post immediately, larger ones require a second
  person. The threshold is an **org setting**, not a model constant; the model
  defines the mechanism and the comparison, the org sets the number.
  **Shrinkage write-offs ALWAYS need sign-off**, unconditionally — this is the
  path where inventory value can quietly disappear, and it is the one place
  Trent chose the tightest control available.
  **Consequence the model must handle, raised by the CPI at ruling time:** a
  single-operator organization (Trent today) has no second person. Mandatory
  sign-off then either blocks receiving entirely or degenerates into
  self-approval, which is not a control and must never be silently recorded as
  one. The model must state the single-authorized-approver behavior explicitly —
  self-approval permitted but **recorded as self-approved**, or an org-level
  setting that names the situation — never an unmarked approval that looks like
  maker–checker but is not. **This also means the approval dimension DOMAIN_MAP
  records as `✗ missing` is now a REQUIRED build, not an optional future.**
- **No financial or evidentiary fact may depend on a Storage object** (CPI,
  2026-08-24, from the A1 backup investigation). Supabase database backups
  **exclude** objects stored via the Storage API, and a restore does not return
  objects deleted since — so anything living only in Storage is outside the
  backup and outside the recovery guarantee. **Verified true today:** Storage
  holds team logos, inventory photos, repack images and card images — all
  presentation. Money is integer cents in the database with the append-only
  ledger as the record, so a restore costs photos, not records. **Binding
  forward:** a receipt, invoice, cost document, attestation, or any artifact
  that *proves* a financial fact may not be stored only as a Storage object. If
  a future gate wants receipt attachment (a natural request on acquisitions and
  PF-C5 receiving), the authoritative fact stays in the database and the image
  is a non-load-bearing convenience. This is the cheap version of a problem that
  is expensive once discovered during a restore.
- **Costing method is lot-level actual cost** (Trent, 2026-07-21). A received
  case or box becomes a lot carrying what was actually paid. Consuming the lot
  charges that lot's cost. Cost is never derived through the nesting chain: if no
  purchase exists for that exact configuration, show nothing rather than a
  computed stand-in. "Last price paid" and COGS are separate figures and may not
  share a field. Binding on PO / receipt / lot design.
- **Exclusivity resolves to a scope, never to a new configuration.** An
  exclusivity string on a checklist row resolves against a configuration
  (`Mega Exclusive`), a channel (`Hobby SKU Exclusive` = every hobby-channel
  configuration), or a distribution route (`Breaker Exclusive`, which may match no
  configuration). An exception is raised only when it resolves to none of the
  three. The checklist is universal; availability is not.
- **The checklist is a persisted child of the product release**, not an import
  artifact. It survives creation, stays editable, carries its own edit history and
  is organization-scoped. Track A owns the physical design.
- **Non-sports is in scope, Pokemon first.** A checklist row has a stable core
  (set, number as text, name, variant, sequence) plus category-specific
  attributes on an `extra` pattern. `athlete` and `team` are SPORTS EXTRAS, not
  core fields. Rarity and artist are TCG extras. Category drives which extras
  appear. The publisher/source selector is an extensible list, never a two-value
  enum. The packaging ladder is already category-neutral and unchanged.

- A Blaster Box or Mega Box is a **Product Configuration** of the same Product
  Master, not a separate product. **Test: if it shares a checklist, it is the
  same Product Master.** A different year or brand is a different product.
- The **checklist belongs to the Product release**; every configuration of that
  release shares it. Already consistent with the approved PRODUCT_SUPPLY_MODEL.
- The checklist is universal but **availability is not** — configuration-exclusive
  parallels exist (Blaster-only, Mega-only). PF-C7 will need per-configuration
  applicability. Not built yet; do not design as though it will never exist.
- **Channel (Hobby / Retail) is a first-class property of a Configuration**, not
  part of its name. Extensible; sub-channels deliberately deferred.
- A Configuration may be defined by **referencing another Configuration plus a
  count** ("a Case holds 12 of these") rather than restating the full chain.
  Duplicated chains can silently diverge; references cannot. Propagation must be
  visible, circular references refused, and referenced configurations may not be
  orphaned.
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

- **W1 (carried from S2.3, cosmetic):** three user-facing strings still read
  "total paid" where the vocabulary is now "landed total"; values are correct.
  Fold into the next Track B implementation gate — do not spawn a gate for it.

- **ROADMAP (outside UI/UX review, 2026-07-26, dispositioned by CPI):**
  S1.6 (immediate): lock cost basis on the card form; require Name; refuse
  duplicate grading-company+cert org-wide; warn on likely duplicate raw identity;
  rename configuration Channel → Distribution; mark global search inert.
  S2 (extended scope): acquisition channel + landed-cost components (shipping,
  tax, fees, premium → computed landed total); basis adjustments as events.
  Currency deferred deliberately. S2.5 (new): collection intake workspace — CSV
  import, batch defaults, unidentified queue, save-and-resume. PF-M3 (model gate,
  blocks S3): Listings. Post-S5: cross-channel exception queue built on the
  approved workflow §6 Attention/Recovery vocabulary. Pre-production: mobile/
  responsive gate (nav vanishes <760px; card-show intake is the driving mobile
  case); nav split Catalog/Stock/Cards at PF-C4; accessibility sweep (aria-live
  toasts, dialog semantics, keyboard resize/reorder, aria-pressed) + these become
  standing-contract requirements for all new builds now.
  Reviewer error in the CPI's brief corrected: Vendors are CORE (PF-C3 required
  core-org reachability), not cards-only as the brief stated.

- **PF-M2 operator rulings (Trent, 2026-07-21)** — binding inputs to the model:
  - **Break-origin cards are OUT OF SCOPE ENTIRELY.** Operator ruling: no card
    business breaks product in order to stock singles. Cards are never created in
    inventory from a break, by any path, automatic or manual. This supersedes the
    earlier cost-toggle discussion and removes it: no cost derivation, no
    capitalize-vs-memo toggle, no card-to-break link, no double-count risk.
    **Every card instance was purchased, so its cost is always real spend.**
    **CLOSED — the unsold-spot edge does not exist.** Operator ruling: a break
    must fill to start, so unsold spots never occur. Nothing reopens this.
  - **Bulk is an import method, not an entity.** Every card is its own record. No
    bulk-lot entity, no promote operation.
  - **DECIDED — collection-import cost spreading: zero-basis with assignment to
    total** (Trent, 2026-07-21). Import every card at zero cost basis, then assign
    cost to specific cards until the assigned total reaches what was actually paid.
    The remainder stays at zero. Books tie out against real spend, the import fast
    path stays fast, and basis lands where the value is. Rejected: even split
    (gives commons the same basis as the cards worth having) and selective
    assignment (a review pass on every import).
  - **Acquisition record is required** (Trent, 2026-07-21). Every card purchase —
    a collection or a single card — creates an identified acquisition carrying who
    it was bought from, when, and the total paid. Every card instance references
    its acquisition. This makes **per-acquisition margin** reportable: proceeds
    from cards out of that purchase versus what was paid, with sold-versus-held
    counts. CPI note: this neutralises the zero-basis weakness for the question
    that matters — collection-level margin is exact regardless of how basis was
    spread internally, and basis assignment becomes relevant only to per-card
    margin and to inventory valuation, not to "did this buy work out".
    **Required consequence:** zero-basis cards must be FLAGGED so reporting can
    separate them. Across a collection the arithmetic nets out — assigned cards
    show thin or negative margin, offsetting commons showing 100% — but a margin
    percentage mixing the two is meaningless. Assigned-total must be visible
    against amount paid during assignment, so the operator can see the remainder.
  - **Acquisition vendor is optional + inline-create** (Trent, 2026-07-21,
    walkthrough). Amends PF-M2.1 §4.1: an Acquisition carries an optional Vendor
    link OR a free-text `seller` (one-off personal sellers at shows) OR neither.
    Inline vendor quick-create reuses the guarded PF-C3 vendor path, never a second
    one. Per-acquisition margin unaffected (never depended on vendor).
  - **Cards are never created as blanks** (Trent, 2026-07-26). A collection
    acquisition creates zero instances at save; "expected cards" is advisory
    progress metadata only. Every instance passes the single guarded creation
    path. (The prior pre-create-N-blanks import bypassed all identity guards.)
  - **The document-driven setup starts from Checklists as well as Products**
    (Trent, 2026-07-26). Same wizard, same gates — an entry point, never a second
    flow. Landing follows origin (Checklists → checklist view; Products →
    product detail).
  - **A card's display identity is composed, never typed** (Trent, 2026-07-26).
    The `name` field holds the player/character and is labelled "Player /
    Character"; everywhere a card renders as a thing it shows the generated
    title Year Brand Line Player · Parallel · #Number · serial/print-run.
    Matches the deployed app's generated-naming rule.
  - **Brand, line and year are required on every CardInstance** (Trent,
    2026-07-26, non-negotiable). Extras become name, brand, line, set, number,
    parallel, print_run, serial, year. CardInstance additionally gains images[],
    links[], and advisory `asking_price` — which never participates in cost or
    margin math; Disposition records actual sale price separately.
  - **CardInstance field taxonomy corrected** (Trent, 2026-07-21, walkthrough).
    Amends PF-M2.1 §3.1 enumerated `extra` keys to: subject, set, card number
    (text), parallel, serial number, year. `variant` and `parallel` collapse to
    one `parallel` (they are the same axis; the walkthrough proved the redundancy).
    `serial_number` split (PF-C-S1.2) into `print_run` (numbered-to denominator,
    e.g. /149) and `serial` (the specific copy held, e.g. 14), both filterable
    columns, displayed together as `14/149`. `name` renamed `subject`; then per operator ruling at S1.2 walkthrough, `subject` renamed to `name` (PF-C-S1.3) — a player or character name field; vertical-neutrality does not require vagueness. The `extra`-pattern
    mechanism is unchanged; the checklist grid model is untouched.
  - **`reserved` hold state is specified, not dropped** (Trent, 2026-07-21). A
    card may be held for a pending sale (invoice sent, unpaid) or staged for a
    repack, advisory like PlannedAllocation; only the posted event moves it
    terminal. It must be entered by an actual event, never left as dead enum state.
  - **Over-assigning cost basis beyond amount paid is admin-only** (Trent,
    2026-07-21). Not a soft warning — gated on admin authority, fails closed for
    non-admins, permitted for admins with the over-assigned state recorded.
  - **Singles need a disposition event.** Recording margin on sale requires
    sold / price / date / channel on the instance. The product-first workflow has
    breaks and fulfillment but **no path for selling a single card outside a
    break**. Scope item for PF-M2 alongside instances and repack transformation.
- **MODEL GAP: instance-level inventory is unmodelled.** Raised by the operator
  2026-07-21. `DOMAIN_MAP` anticipates the seam — "grading attributes
  (company/grade/cert), card-specific item attributes ... repacks + pack opener"
  riding inventory-item `extra` — but `PRODUCT_FIRST_WORKFLOW.md` contains **zero**
  mention of singles, slabs, grading or certs, and the word "repack" appears
  nowhere in it. No checkpoint in PF-C1..PF-C21 creates instance-level inventory.
  Three distinct problems, not one:
  1. **Non-fungibility.** A Lot is a quantity with a cost basis. A graded slab is
     one specific item with grade, grader, cert and condition. The second cannot
     be expressed as a quantity of a Product Configuration.
  2. **Derived cost collides with the accepted lot-cost ruling.** Lot-level actual
     costing assumes cost arrives at receipt. A card pulled from a case was never
     purchased individually; its cost must be *allocated* from the case cost, and
     that allocation is a real accounting choice the ruling does not cover.
  3. **No transformation concept.** A repack consumes N singles and produces one
     new sellable unit with cost flowing through. The model can receive inventory
     (purchase) and consume it (reservation). It cannot manufacture.
  Singles also arrive by direct purchase, so both an acquisition path and a
  derivation path are needed. Recommend a model gate (PF-M2) authored in parallel;
  it does not block PF-C4-PF-C6, which are purchasing and sealed-product only.

- **PF-C21 regeneration requirements** captured from the D1/D2 retro-audit. Not
  work for now; the regeneration must deliver: ONE entitlement mechanism (screen
  08's `cardsOn()` and `07-planning-schedule`'s `setEnt` are two mechanisms for
  one invariant); capability guards on the 23 currently unguarded mutators across
  screens 02/03/04/06/07; the cards-off forbidden-list scan extended beyond screen
  08, which is the only screen that has one; and `05-close-reconcile` rebuilt
  neutral — its seed data is entirely card vocabulary with no gating.
- **SOURCE and LIVE MIRROR diverge on every screen 00-07** (e.g. `02`: 60,744 vs
  66,331 bytes; `05`: 23,209 vs 36,125). PF-0 covered provenance for both
  archives, but whether this divergence is intended or drift is recorded nowhere.
  It determines which artifact a retro-review gate is audited against. Resolve
  before PF-R1.
- **Two entitlement mechanisms exist for one invariant.** Screen 08 uses
  `cardsOn()`; `07-planning-schedule` uses its own `setEnt` / "Cards on" control.
  Same shape as the two-grids problem PF-C2.7 consolidated. Reconcile to one.

- Track A handoff records "19 RPC wrappers". The A6c plan rev 6 inventory is 14
  public inventory RPCs, 13 client delegates, 1 internal delegate, 10 internal
  helpers. Correct the handoff; the plan is right.
- ~~Canonical anchor `874b8f40...` unverified.~~ **CLOSED 2026-07-20 — VERIFIED.**
  Recomputed against the original `Element10_PRODUCT_FIRST_CANONICAL.zip` from
  `prototypes/exports/`. Actual SHA-256 =
  `874b8f40a519ddbb22c79bfd4e8180746e5c0a13e8eba2fd18a96d0951ed82fb`, matching
  the recorded anchor exactly. The anchor was correct all along and may be cited
  as a verified root of trust.
  Extracted content additionally verified: 12/12 members match their own
  `HASHES.txt`; content anchor
  `2ae67f8c4efd3a74e0fe6dd12bdea1ee8d94e76eab3df7f1555cc91ac6453f0d`.
  (An earlier revision of this item wrongly asserted the archive did not exist
  and was unrecomputable. That was inferred from a search scoped to the CPI's
  own mounts. Retained here as the reason the coordination rule below exists.)
- **OVERDUE / CPI SLIP.** `CAPABILITY_CROSSWALK.md` describes a twelve-key
  persisted catalog. Staging holds the legacy twelve plus fifteen A6b additive
  capabilities. This item said "reconcile before PF-C2". PF-C2, PF-C2.1, PF-C2.3
  and PF-C2.4 were all accepted without it being done. The CPI wrote a gate
  condition and then did not enforce it. Reconcile now, before any further
  product-first capability is proposed. Track A parallel work item 2 below.
- The A7 hostile two-organization scenario matrix should be authored once and
  consumed by both A7 and PF-C20, not written twice in two vocabularies.
- `money.read` / `cost.read` sub-organization privacy (a streamer sees only their
  own commission) cannot be expressed by organization-membership RLS. It needs
  its own design, post-A6. A capability leaf will not solve it.

## COORDINATION RULE

`BOARD.md` is the coordinating authority for both tracks. Agents read it at the
start of every run and act only within their track's Next authorized action.

- Agents update execution progress and evidence directly; formal acceptance rows remain CPI-owned.
- Agents do not mark their own gates accepted.
- Execution instructions live in `## NEXT PROMPT TO SEND`. Historical dispatch subsections do not require a new prompt for each sprint;
  use the current authorized objective and dependency-ready queue. That section is authored and replaced solely by the
  Chief Project Inspector; an agent never edits it, including to record that it
  has finished.
- Only the Chief Project Inspector reconciles state and applies gate changes,
  after independent review.
- If a required approval is not recorded in the Approvals Ledger, it does not
  exist.
- Where any other document disagrees with this board on current state, this board
  wins and the other document is corrected.
- Never record a limitation of one participant's access as a fact about the
  world. "Not reachable from here" is not "does not exist." State the scope of
  any search that produces a negative finding.

### Board access is asymmetric — know which side you are on

- **Track A (Claude Code)** runs on the local machine and reads this file
  DIRECTLY. It is the live authority for that track.
- **Track B (Claude Design)** runs in a separate cloud filesystem and CANNOT
  reach this file. Its subsection of `NEXT PROMPT TO SEND` is relayed by the
  Chief Project Inspector at dispatch time.
- Therefore: **Track B must not maintain, consult, or trust any local copy of
  `BOARD.md`.** Any such copy is stale by construction. For a Track B run, the
  relayed instruction IS the authority for that run, and the ledger state quoted
  inside it is current as of dispatch.
- A Track B agent that finds a board file in its own workspace should ignore it
  and say so, rather than reasoning from it.
- The CPI relays the ledger rows a Track B run depends on, inside the
  instruction, so the agent never has to look them up.
