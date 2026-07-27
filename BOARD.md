# Element 10 Project Board

_Last reconciled: 2026-07-21 by Chief Project Inspector_

**CANONICAL LOCATION:** `/Users/tsconnely/dev/element10-app/BOARD.md`.
That file is the only authoritative copy. Any other copy of this document,
anywhere, is a non-authoritative snapshot and must not be used to decide a gate.
If a snapshot disagrees with the repository copy, the repository wins and the
snapshot is stale.

## CURRENT SYSTEM MOMENT

- [x] Product-first workflow approved
- [x] PF-0 provenance and hub gate accepted
- [x] A6c authorization plan rev 6 approved
- [x] A6c.0 additive prerequisites accepted
- [x] A6c.1 + A6c.1.1 RLS policy rewrite ACCEPTED (two independent audits; falsifiable denial proof)
- [x] A6c.2 implemented (0a7da40) — outside review: NOT ACCEPTED (buyer_suggest unscoped `seen`; global-admin authority in 6 delegate bodies; compact staging body)
- [ ] **A6c.2.1 authority corrective - CURRENT TRACK A GATE**
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
- [ ] **PF-C-S1.7 - CURRENT TRACK B GATE, READY TO DISPATCH** (state-not-render defaults + audit, compact provenance, no-native-popover, player-aware no-match + cold-start hint)
- [ ] ~~PF-C-S1.5 walkthrough findings:~~ superseded line — see above: dropdown dismissal (universal), filter affordance (universal), required brand/line/year, print-run affordance, acq→first-card flow, images/links/asking, cert sanity - CURRENT TRACK B GATE**
- [ ] PF-C-S2 cost-basis assignment (zero-basis → assign to total) - next after S1.2
- [ ] PF-C-S2 cost assignment · S3 disposition · S4 repack · S5 margin reporting - sequenced after S1
- [ ] PF-C4 onward (sealed-product purchasing) - independent of the singles sequence, either order
- [ ] PF-C4 onward (purchasing) - unaffected by the PF-M2 gap, sealed product only (a product must complete setup before it can be ordered)

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
| Product-first workflow | GRANTED | CPI | 2026-07-20 | `Element10_PRODUCT_FIRST_CANONICAL.zip` SHA-256 `874b8f40a519ddbb22c79bfd4e8180746e5c0a13e8eba2fd18a96d0951ed82fb` — **VERIFIED** against the original archive 2026-07-20; extracted content 12/12, content anchor `2ae67f8c...` |
| PF-0 provenance and hub gate | GRANTED | CPI | 2026-07-20 | PF-0.2 archives — see `PF0_2_ARCHIVE_HASHES.txt` |
| A6c authorization plan rev 6 | GRANTED | CPI | 2026-07-20 | `Element10_A6c_PLAN.md` SHA-256 `2d1710bfdb0653271960f021c12efacb4c83f1be22067d6e064e6724ed33ce70` |
| A6c.2 wrapper cutover + mechanic relocation | NOT ACCEPTED | CPI | 2026-07-26 | Commit `0a7da40eb7d3249266cd19914b8abf3b68967895`, migration `20260726140000_e10_a6c2_cutover.sql`, CI `30211865339`. Structure verified clean (delegates are the mechanism, wrappers thin one-line forwards, 0 recursion, 7 legacy helpers retired with refcount proof, 55 A6c.1 policies untouched, prod untouched). **Rejected on outside review, both findings CPI-confirmed on live staging: (1) `buyer_suggest`'s `seen` query has no session or org filter — `streamer_uid=auth.uid() OR e10_is_admin()` exposes buyer identities across sessions and, for a legacy global admin, across organizations; (2) SIX delegates (reviewer's five + buyer_suggest) retain legacy GLOBAL `e10_is_admin()` authority inside org-aware bodies — a legacy global admin could exercise admin behavior in an org where they hold ordinary membership; no test covers that identity combination.** Root cause: "preserve legacy behavior verbatim" (m31/m32 oracle) preserved legacy AUTHORITY verbatim; no census ever covered delegate-body predicates. Also: compact staging body + reconciled ledger makes staging appear identical to clean replay when it is not — insufficient for a security-definer migration. CPI's own audit missed both (checked structure, not authority semantics) and the CPI's stale board sections violated its own 2026-07-21 maintenance rule a second time. |
| A6c.1 RLS policy rewrite (55 policies) + A6c.1.1 test corrective | GRANTED | CPI | 2026-07-26 | Commits `7138716743250d47e3cf90da9196fd471f18a322` (migration `20260726120000_e10_a6c1_rls_rewrite.sql`, CI `30206547507`) + `d2ad844` (test-only, CI `30207551465`). CPI-verified against live staging: 97-policy census reconciles exactly (55 rewritten = 41 USING + 14 WITH CHECK; 100 live minus 3 storage = 97); `imov_sel` now `e10.is_org_member(organization_id)` closing the A6c.0 finding; every WITH CHECK pins `organization_id = e10.current_org()`; correlated refs table-qualified with the `owned_slot` alias (rev-4 shadowing not reintroduced); 11 delegates intact, wrapper still legacy (no A6c.2 creep); prod untouched (12 migrations, head `20260716110000`, zero e10 policies). Outside review found the cross-org write denial was a false positive (FK shadowed RLS behind `exception when others` — standing rule 5); A6c.1.1 rebuilt it FK-valid requiring SQLSTATE 42501, audited the other 7 denials (SELECT-count/predicate, unshadowable), and proved falsifiability by permissive-replace after finding a bare DROP yields default-deny — a stronger construction than the corrective specified. Agent's ADR flag was correct; board's stale rev3.2.2 note fixed. |
| A6c.0 additive prerequisites | GRANTED | CPI | 2026-07-20 | commit `7f0d38385e05682da5bc51879a1ac04683d27afd`; migration `20260720120000_e10_a6c0_prereqs.sql`; CI green run `29768281886`; staging head `20260720120000`. CPI-verified against live prod + staging: 13-delegate allowlist exact, internals `authenticated=false`, zero anon/PUBLIC, no wrapper or policy cutover, 0 published sessions, prod untouched. |
| PF-C2 Product Configuration | GRANTED | CPI | 2026-07-20 | `Element10_PFC2_REVIEW.zip` SHA-256 `c001a8bb169b50e94103277f205d0290023513786da431233d1ef521166ca7d3`; screen 08 `a7d056e881f89c0fc19748e9...`. CPI-verified in source: `saveConfig` fails closed; conversions append-only with `cur` pointer; forbidden list and scan hosts unshortened; unit arithmetic independently recomputed (360 / 4320 / 48); cards-off handled via per-org seed data. Passed on first attempt. |
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

---

### TRACK A — Claude Code — READY TO DISPATCH

## A6c.2 NOT ACCEPTED — implement A6c.2.1 (authority corrective)

The relocation's structure passed two audits: delegates are the mechanism,
wrappers are one-line forwards, zero recursion, seven helpers retired with
refcount proofs, the 55 A6c.1 policies untouched, prod untouched. None of that
is being redone. The defects are in the AUTHORITY SEMANTICS of the relocated
bodies — "preserve legacy behavior verbatim" preserved legacy authority
verbatim, and legacy authority embedded global-admin power that is wrong in a
multi-tenant world. Where behavior-preservation and org-scoping conflict,
**org-scoping wins**; note each divergence from m31/m32 explicitly instead of
preserving it.

Authorization: ledger rows `A6c.1 + A6c.1.1 | GRANTED | CPI | 2026-07-26` and
`A6c authorization plan rev 6 | GRANTED`. Baseline: accepted code head
`d2ad844`; A6c.2's `0a7da40` is the corrective's parent. STAGING and LOCAL only.

## 1 — BLOCKING: scope `buyer_suggest`'s `seen` query

Confirmed on staging: `seen` collects from `e10_break_slots` joined to sessions
`where (s.streamer_uid=auth.uid() or public.e10_is_admin())` — no session
filter, no org filter. Every buyer the caller ever hosted (or, for a legacy
global admin, EVERY buyer in EVERY organization) leaks into suggestions.

Required: `seen` scopes to **the requested session** (`sl.session_id =
p_session`), consistent with the roster CTE; the entry already verifies
`e10.owns_session(p_session)`. Remove `e10_is_admin()` here entirely.
This changes suggestion breadth vs legacy — that is the point; record it as an
approved behavioral divergence.

## 2 — BLOCKING: purge legacy global-admin authority from delegate bodies

Six delegates carry `public.e10_is_admin()` (the reviewer's five —
`inv_release`, `inv_consume`, `inv_mark_sold`, `inv_set_reservations`,
`inv_reverse_consumption` — plus `buyer_suggest` per item 1). Replace the five
inventory uses with **organization-scoped authority**:
`e10.is_org_admin(p_org)` (or the capability check the plan's ACL matrix
assigns, if stricter). A legacy global admin with ordinary membership in org B
gets ordinary-member treatment in org B, nothing more.

**Then census, don't spot-fix:** enumerate EVERY legacy authority predicate
(`e10_is_admin`, `e10_is_member`, `e10_is_org`, `e10_can_read_session`, legacy
`e10_owns_session`) across ALL `e10_org_*` bodies and org-aware `_e10_inv_*`
helpers. Report the census table: function, predicate found, replacement or
justified retention. Zero unexplained legacy predicates remain. The A6c.1
census covered policies; nothing ever covered delegate bodies — this closes
that gap permanently.

## 3 — Regression tests for the uncovered identity combination

Per the raised proof standard (specific SQLSTATE, no `when others` except as a
`*_wrongerr` recorder, layer-exclusion notes):
- Legacy global admin + ordinary member of org B → each of the five admin-privileged
  operations in org B refuses with its specific SQLSTATE (and the org-B admin
  positive case succeeds).
- `buyer_suggest` for session X returns no buyer whose only appearance is in
  session Y (same owner) and none from another organization (adversarial two-org
  fixture).
- Falsify once each via permissive-replace (session exercise, described with
  before/after in the report — not committed to CI).

## 4 — Staging artifact discipline (reviewer concern, adopted)

The compact-body practice ends for authorization objects. Required here:
- Re-apply the EXACT committed migration text to staging (reset the A6c.2 +
  A6c.2.1 state as needed), or prove object-level identity: `pg_get_functiondef`
  of every touched object diffed against a local clean replay of the committed
  files, zero diffs, the diff transcript in the report.
- **Standing rule going forward: staging receives the byte-exact committed
  artifact for any migration touching authorization objects.** The A6b-era
  compact-body contract notes stand for their own accepted gates; they are not
  precedent for future ones.

## 5 — Housekeeping (fold in)

Drop `_e10_inv_receipt` and `_e10_inv_replay` — dead since A6c.0 (reference the
dropped `response` column), refcount 0, locked; carry the same refcount-proof
pattern as the seven already retired.

## Report

Changed files vs `0a7da40`; the authority census table; per-test red/green;
staging identity proof; full suite green; prod re-proven untouched. Propose the
delta; do not self-accept. Stop before A6c.3 and request "A6c.2.1 accepted."

### TRACK B — Claude Design — READY TO DISPATCH (PF-C-S1.7)

Claude Design cannot read this file. The CPI must paste this subsection to it.
Ignore any `BOARD.md` copy in your own workspace. This relayed text is authority.

## PF-C-S1.7 — operator findings from the S1.5.1 walkthrough (four items)

## 0. Fail-closed input

Start from accepted PF-C-S1.6:
  `Element10_PFCS1_6_REVIEW.zip`
  SHA-256 `fd47e4610058fad2ba7bd1af14b972a5293c23cd59f5406c43c378c119069b41`
  `08-product-workspace.html` `d2065b29e3d72a556e004610b80987f1718b85b047ccdd43df26c5fa7c183eb6`
FROZEN: screens 01-07; `e10.css` `cd37cd43...`.

## 1 — Rendered defaults must live in state (the "Cards to create" bug)

`value="${esc(f.count||5)}"` renders 5 while state holds '' — the operator sees
5, saves, and is told "must be at least 1"; deleting and retyping commits it.

- Fix: defaults are set in state (`blankAcq` gives `count:5`); render only ever
  echoes state, never invents a fallback value.
- **Audit every input in the file for the render-fallback pattern**
  (`value="${...||...}"` and equivalents). List each hit; fix all. This is the
  third display-vs-state divergence family (caret, click target, now value);
  record the rule in evidence: what the operator sees must be what state holds.

## 2 — Provenance marks: keep the signal, cut the repetition (CPI spec correction)

Nine autofilled fields currently repeat the same full basis sentence nine times.
The per-field basis-line spec was the CPI's; at this density it violates the
project's strip-noisy-copy instruction.

- Per field: a compact glyph/chip only (⚙ or similar), title/tooltip carrying the
  full basis, individually dismissible as today.
- One summary line for the batch, once, under the name field: "9 fields filled
  from checklist — 2026 Panini Prizm FIFA World Cup Soccer, Base #1 · clear all".
- "Clear all" drops every provenance mark (values stay); manual edit still drops
  that field's mark.
- Same rule anywhere else multiple fields share one basis (setup wizard step 3
  is fine as-is — different bases per field).

## 3 — No native popovers, extended (universal)

The brand field's `<datalist>` summons the OS-native dropdown. Standing rule
extension: **no `<datalist>` and no native select popovers on suggest/typeahead
fields** — same class as the banned `alert`/`confirm`/`prompt`: OS-rendered,
outside the scan hosts, off-theme.
- Replace the brand datalist with the in-app suggest pattern (the picker's
  stable-host dropdown, reused — pattern-reuse rule; it already obeys dismissal
  and repaint discipline).
- Plain `<select>` elements for short enum choices remain allowed; the ban is on
  native *suggest* popovers over free-text fields.
- Audit for other `<datalist>` uses; replace them too.

## 4 — No-match flow: player-aware, affirmative wording

"Close — enter by hand" is passive and odd. When the typed name has no checklist
match:
- If it matches a **known player** — the union of names across this org's
  checklists AND its existing card instances — offer "Use player 'X'" (fills
  name, and team where all sources agree; provenance-marked).
- Otherwise offer **"New player: 'X'"** — affirmative, closes the picker, keeps
  what was typed, focus moves to the next field.
- **Cold-start hint** (CPI behavioral-run finding): when the organization has NO
  persisted checklists at all, the no-match state additionally explains why and
  what to do — "No checklists in this organization yet — set up a product from
  documents to enable autofill." One line; renders only in the truly-empty case.
- Still NO persisted Player entity (model boundary from S1.3 stands; derivation
  only). If a durable player record is wanted later, that is a model gate —
  flagged for the CPI, not built here.

## Standing rules — all, plus the repaint/focus/state disciplines

Item 1's audit is the deliverable as much as the fix. Screenshots per rule 7:
the count field defaulting AND saving first try; the compact provenance with its
summary; the in-app brand suggest; both no-match actions.

## Package and report

`Element10_PFCS1_7_REVIEW.zip` + full 64-char hashes, manifest clean, chain
rooted at accepted S1.6. Do not mark accepted yourself.

Needs the operator walkthrough. Stop and request "PF-C-S1.7 accepted."

---

### TRACK B — Claude Design — READY TO DISPATCH (PF-C-S1.6)

Claude Design cannot read this file. The CPI must paste this subsection to it.
Ignore any `BOARD.md` copy in your own workspace. This relayed text is authority.

## PF-C-S1.6 — financial and identity discipline on the card record

Source: outside UI/UX review of accepted PF-C-S1.4, dispositioned by the CPI.
Five items. One of them corrects the build contradicting the approved model.

## 0. Fail-closed input

Start from accepted PF-C-S1.5.1:
  `Element10_PFCS1_5_1_REVIEW.zip`
  SHA-256 `37d72670c657224d5515d68ea2cfd815778a39447b62943478113d0ae1103ea5`
  `08-product-workspace.html` `a492aa29818164f670dbf9ccbd4baee59205ffe879b4d0e92a7f002019418f17`
FROZEN: screens 01-07. `e10.css` frozen unless S1.5 unfroze it with CPI
sign-off; if so, the S1.5-accepted css hash is the new baseline.

## 1 — Cost basis is never a free-typed field (BLOCKING; build contradicts PF-M2.1 §4.2)

The card form exposes `cost_basis` as an ordinary input. The approved model says
basis changes are additive adjustment events; a typed edit also silently moves
the owning acquisition's assigned total with no acquisition-level visibility.

Required:
- **Single-card acquisition** instances: basis is DERIVED (= the acquisition's
  total paid), displayed read-only with its source stated. Changing it means
  editing the acquisition, and the display says so.
- **Collection-import** instances: basis displays as locked at zero — "assigned
  in cost assignment (next checkpoint)". No input.
- No mutator path may write `cost_basis` directly from the form. Probe it:
  attempting to set basis via the harness refuses. S2 will build assignment and
  adjustment events on top of this lock; do not build them here.

## 2 — Identity guards

- **Name becomes required** at save (alongside S1.5's brand/line/year). A card
  with no name refuses.
- **Org-wide uniqueness of grading company + cert number**: two records with the
  same company+cert are the same physical slab. Refuse the duplicate, name the
  existing card, offer to view it. Applies against archived cards too (restore,
  don't duplicate).
- **Likely-duplicate raw warning** (warn, never block): same brand/line/set/
  number/parallel/print-run/serial (or both unnumbered) in the org → an inline
  "you may already own this — view existing" note at save, dismissible, because
  owning two equivalent unnumbered copies is legitimate. The warning names the
  match; saving proceeds normally.

## 1b — Collection import creates ZERO cards up front (unguarded-path fix)

Operator finding (2026-07-26): choosing "5 cards" then entering one left four
blank records. Worse than UX: `saveAcq` manufactures blank instances directly,
**bypassing `saveInstance` and every identity guard this gate adds** — a second,
unguarded creation path (standing rule 1).

- A collection acquisition creates **no card instances at save**. Cards come into
  existence only through the one guarded Add-card path.
- Remove the "Cards to create" count as a creator. Optionally keep it as
  **"Expected cards"** — advisory metadata shown on the acquisition as progress
  ("3 of ~5 entered"); it creates nothing and blocks nothing.
- The acquisition-save → Add-card flow (S1.5) stays; the operator enters cards
  one by one. True bulk entry is S2.5's intake workspace, not this.
- Migration of prototype seed/state: any existing blank instances (no name, no
  brand) may be dropped from seeds — they are unreachable states once this lands.
- Prove per rule 6: save a collection acquisition with expected=5, enter one
  card, show the grid holds exactly one row and the acquisition shows 1 of ~5.

## 2b — The player field is labelled for what it holds; the card title is composed

Operator ruling (2026-07-26): "Name as a field serves no purpose on a card. The
card should be a combination of the player/character name, brand, line, year at
its core."

- Relabel the field **"Player / Character"** (key stays `name` internally; this is
  a label, column-header and picker-placeholder change).
- **Card display identity is GENERATED, never typed**: wherever a card renders as
  a thing — detail header, breadcrumb, grid primary column, picker rows,
  duplicate-warning references — show the composed title:
  `{year} {brand} {line} {player}` + ` · {parallel}` when present + ` · #{number}`
  when present + ` · {serial}/{print_run}` when numbered. Skip empty parts
  cleanly; never render a dangling separator.
- The composed title is display-only — no stored title field, nothing new to
  keep in sync.
- This matches the deployed app's existing generated-naming rule
  (Year·Brand·Line·…, per the build log), so production already validates the
  pattern.

## 3 — Rename the configuration field "Channel" → "Distribution"

Ruling: channel is four separate concepts (distribution class / acquisition
channel / sales channel / fulfillment route) and no surface may reuse one for
another. The Hobby/Retail field on configurations, in the setup wizard's
extract step, and anywhere else it renders is **Distribution** from now on.
Values unchanged. Update every label, column header, exception card and basis
line that says "channel" about Hobby/Retail. The word "channel" is reserved for
sales channels (S3/PF-M3) and acquisition channels (S2).

## 3b — Start the document-driven setup from the Checklists page too

Operator ruling (2026-07-26): the product/checklist journey must also start from
the Checklists page, not only from Products — checklists are where the operator
actually begins.

- Add **"Set up from documents"** to the Checklists page (alongside its list of
  persisted checklists, including when the list is empty — the empty state should
  invite it).
- It opens **the SAME wizard** (`openImport`), same steps, same gates, same
  approve path. Do NOT fork a second flow or a second mutator; this is an entry
  point, nothing else (pattern-reuse rule).
- **Origin-aware landing only**: launched from Checklists → after approval land
  on the created product's checklist view; launched from Products → land on the
  product detail as today. Track the origin in wizard state; clear it on
  cancel/close.
- Cards-off unaffected: core organizations cannot reach the Checklists page at
  all (existing behavior — verify unchanged).

## 4 — Mark the global search inert

The chrome search box ("Search sessions, inventory, people… ⌘K") does nothing
and is a false affordance. Do not implement it and do not remove it: disable it
visibly (non-focusable, muted, tooltip/label "coming later — entity search").
The roadmap builds it as an entity launcher post-S5.

## 5 — Scope discipline

Nothing else. No acquisition-channel field, no landed-cost components, no
adjustment events, no batch import — those are S2/S2.5 and are specified there.
If S1.5's delivery already altered a surface this gate touches, reconcile to
S1.5's accepted state and say so in the report.

## Standing rules — all seven, plus caption, pattern-reuse, and dismissal

The two refusals (missing name, duplicate cert) and the raw warning are rule-6
territory: demonstrate each condition occurring, screenshot per rule 7,
including the warn-and-save-anyway path for the raw duplicate. The basis lock
is probed at the mutator, not the UI (rule 5).

## Acceptance

- No input can set cost basis anywhere; derived display for single-card,
  locked-zero display for collection cards; harness probe refuses.
- Nameless card refuses; duplicate company+cert refuses naming the existing
  card (including archived); raw duplicate warns, names the match, saves on
  confirm.
- No rendered surface says "Channel" about Hobby/Retail; all say "Distribution".
- Global search visibly inert with explanatory affordance.
- All S1.x + S1.5 behaviour passes; cards-off scan clean; org isolation intact.

## Package and report

`Element10_PFCS1_6_REVIEW.zip` + full 64-char hashes, manifest `shasum -c`
clean, chain rooted at the accepted S1.5 zip hash. Lead with the basis-lock
probe refusing, then the three identity screenshots. Do not mark accepted
yourself.

Needs the operator walkthrough. Stop and request "PF-C-S1.6 accepted."

---

### TRACK B — Claude Design — READY TO DISPATCH (relay this whole subsection)

Claude Design cannot read this file. The CPI must paste this subsection to it.
Ignore any `BOARD.md` copy in your own workspace. This relayed text is authority.

## PF-C-S1.5 NOT ACCEPTED — build PF-C-S1.5.1

Package `5e3cc57f224fe5e61ef8e1fa38721a75ebbe002d91e726d83316b26e0a067933`
audited; seven of eight items pass in source and the dismissal architecture
(delegated capture-phase trio, Escape swallowed) is right. **Operator walkthrough:
no card can be selected from the picker.**

### The defect — one clause

`dismissAllPopovers` line 388: `if(changed==='picker'||S.ciform){...cifDrawPicker();}`

The `|| S.ciform` repaints `#cifPicker` on EVERY mousedown while the card form is
open — including a mousedown on a suggestion row. The row is destroyed between
mousedown and click, so `cifPickCard` never fires. The picker renders and cannot
be used.

This is the S1.3/S1.4 defect family again — a repaint destroying the in-flight
interaction target; there the caret, here the click.

### Required

1. Repaint only what actually closed: `if(changed==='picker')cifDrawPicker();`
   (and the grid line already does this correctly). Remove the `||S.ciform`.
2. **Standing rule for this file, record it in the evidence: a host is never
   repainted during an in-flight interaction with it.** Mousedown on a target
   inside a host must not trigger that host's repaint before the click completes.
   Audit the other two dismissal branches (cols, opmenu) for the same premature-
   repaint shape and state the result.
3. Prove per rule 6/7: screenshot the picker open, then the form AFTER a
   suggestion row was clicked, with the autofilled provenance-marked fields —
   i.e. the S1.3 acceptance evidence re-demonstrated on this build. Also prove
   outside-click and Escape dismissal still work (the feature must survive its
   own fix).

### Scope

That clause, the audit of the other branches, nothing else. Every S1.5 item
stays as delivered.

### Package and report

`Element10_PFCS1_5_1_REVIEW.zip` + full 64-char hashes, manifest clean, chain
rooted at S1.5 `5e3cc57f...`. Do not mark accepted yourself.

Needs the operator walkthrough. Stop and request "PF-C-S1.5.1 accepted."

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
- Accepted repository **code** head: `7f0d38385e05682da5bc51879a1ac04683d27afd`
  (moved from `53501928...` when A6c.0 was accepted — A6c.0 is accepted code, so
  it becomes the new baseline. `53501928...` remains the A6a/A6b historical
  baseline. Diff future work against `7f0d383...`.)
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

- A6c.0, A6c.1 + A6c.1.1 ACCEPTED. Accepted code head `d2ad844`.
- **A6c.2 implemented (commit `0a7da40`) and NOT ACCEPTED** on outside review —
  two tenant-boundary defects in relocated delegate bodies plus the compact
  staging-body concern. **A6c.2.1 is the active gate** (see NEXT PROMPT TO SEND).
- A6c.3 (workspace) and A6c.4 (platform/identity) remain out of scope until
  A6c.2.1 is accepted. The two dead orphans `_e10_inv_receipt`/`_e10_inv_replay`
  (refcount 0, locked, reference a dropped column) fold into A6c.2.1.


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

**Rewritten 2026-07-26 in the same reconciliation as the A6c.2 ledger row, per the
standing maintenance rule (which the CPI violated twice before this).**

1. Implement **A6c.2.1 ONLY** — the authority corrective. Full instructions in
   `## NEXT PROMPT TO SEND` → TRACK A; that subsection is authoritative.
2. STAGING and LOCAL only. Production read-only until A10.
3. Stop before A6c.3. Propose the delta; do not self-accept.


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

- **PF-C1 Product Master ACCEPTED 2026-07-20** against `f522cf4f...` (screen 08
  `1fec0346...`), after independent CPI audit of the full gate scope rather than
  the delivery report. PF-C1.1 was rejected; PF-C1.3 passed.
- **PF-C2.1 DELIVERED 2026-07-20 and CPI-AUDITED: PASS.** Package `d9352dcf...`;
  screen 08 `e3d392f7...`; manifest clean; `e10.css` STILL byte-identical — the
  entire editor rework used existing CSS.
  Verified in source: zero base-unit input fields (derived); live breakdown;
  channel present and `null` for core organizations; nested references via
  `kind:'ref'` + `refConfigId` + `count`; `removeConfig` refuses while dependents
  exist and names them; dependent old/new preview before commit.
  **Cycle protection is stronger than specified — two independent layers.**
  `wouldCycle()` filters the reference dropdown so a cycling option cannot even
  be selected, AND refuses at save; `resolveTotal()` separately carries a `seen`
  set and returns `cycle:true` at render time. Prevented at selection, refused at
  save, survivable at render.
  The self-reported leak is properly gated: `${cardsOn()?' (Hobby Box, Hobby
  Case…)':''}` — card examples render only for cards organizations.
  Guardrails unshortened: 20 forbidden terms, 3 scan hosts. All PF-C1/PF-C2
  behaviour intact.
  **Standing rule 4 worked unprompted for the first time:** the agent found the
  leak itself, reported the FAILING scan, fixed it, re-scanned, and reported both
  results rather than only the passing one.

- **PF-C2 DELIVERED 2026-07-20 and CPI-AUDITED: PASS. Acceptance recommended;
  awaiting the CPI's literal ruling and ledger row.**
  Package `c001a8bb...`; screen 08 `a7d056e8...`; internal manifest clean;
  `e10.css` STILL byte-identical at `cd37cd43...` — a configuration editor was
  built without touching CSS.
  Verified in source, not from the report: `saveConfig` fails closed on
  authority, form presence, target existence, organization, and archived-parent;
  conversion versions are APPENDED (`versions.push`, `cur` pointer) so a factor
  change never rewrites the meaning of quantities recorded under the old version;
  no-change duplicates refused by version number; the 20-term forbidden list and
  the three scan hosts are unchanged, neither shortened nor narrowed; every
  PF-C1 behaviour still present (four `canWrite` refusals, archived-not-editable,
  `applyPendingFocus`, `archiveState`, the ARCHIVED-conflict message, the
  identity guards).
  Unit normalization independently recomputed from the seed data: 24x15=360,
  12x24x15=4320, 6x8=48. All three match.
  Cards-off is handled better than specified: packaging names are per-organization
  SEED DATA (cards org holds "Hobby Box"/"Hobby Case"; core org holds "Master
  carton"), so card vocabulary cannot leak through a missed conditional branch.
- **First checkpoint in this sequence to pass on its first attempt.** PF-C1 took
  three. The five standing rules are doing the work they were written for.
- Carried forward from the PF-C1 audit, non-blocking: `archiveP` on an already
  archived record and `restoreP` on an already active one are idempotent rather
  than refusing. No harmful mutation. Fold into PF-C2 if convenient.
- Frozen for PF-C2: screens 01-07 and `e10.css` (`cd37cd43...`). Screen 08 is the
  working surface and may change; its accepted baseline is `1fec0346...`.

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