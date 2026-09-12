# Track A final independent review

## Current disposition after external review

The final acceptance recorded later in this historical ledger is superseded.
The external review of f93aaa7 reports reproduced inventory, authorization,
customer-spend, provenance and evidence-coverage defects. Those counterexamples
have not yet been independently reproduced by this coordinator. Unconditional
acceptance is withdrawn pending reproduction, corrective regression tests and
renewed staging verification. Prior PASS records remain historical evidence,
not proof against the newly reported counterexamples.

The owner authorized correction of the review findings first, followed by
multilingual backend foundations. Track A is preparing a full finding matrix
and dependency-ordered plan. Production, main, cutover and Track B screen work
remain outside this execution. The external counterexample kit was not supplied;
the detailed report is available and can be used to reconstruct failing tests.

## Historical review record

Review baseline: `2b1f31fca4198c14d35953214e469af286d6c999`.
Date: 2026-09-12. Status: acceptance remains open.

This record supplements, rather than replaces, the owner-edited scope and
builder acceptance artifacts. Findings below were sent to Track A for a
consolidated response. No production change is authorized by this review.

## Open acceptance findings

| ID | Required behavior | Current evidence | Next acceptance evidence |
| --- | --- | --- | --- |
| F1 | Customer spend-range and channel filtering across the full authorized dataset, before paging, with consistent totals/export | `EXPANSION_ACCEPTANCE_CASES.md:40`. `20260911031500_e10_ta_x7b_spend_reporting.sql:238` has no aggregate spend-range or sort input. X8 dispatcher lines 119–122 forwards none. X7b test lines 37–45 tests 201 transaction lines; line 68 tests two customers, not spend filtering. The trace's 205-row example is inventory valuation. | Supported bounded customer-grid contract with optional aggregate filters and stable sorting, consistent full-cohort totals and export traversal, query-bound cursors, typed-query coverage, and a matching customer beyond page one. |
| F2 | Official lifetime spend over known history with coverage disclosed | Framework sections defining lifetime spend and acceptance customer coverage/privacy. Customer summary rejects windows longer than 366 days; X7b test line 73 expressly verifies that limit. No alternate lifetime contract verified. | Known-history computation at a stable cutoff with explicit coverage and unknowns, correct deduplication/refunds, bounded resources, and multi-year fixtures. Do not sum averages or overlapping distinct counts. |
| F3 | One cross-product subject + rookie designation + PSA 9 query, including later-page matches | Acceptance case is backend query behavior, not merely a named demo. `ta_x7d2_screener_cohorts_test.sql` proves useful grade and rookie predicates separately, within one release; cited evidence does not prove their combined cross-product public pagination. | Representative multi-release fixture through the public reader, combined predicates, stable continuation and unknown-rookie exclusion. Real player data is unnecessary. |
| F4 | Same-name identity ambiguity remains a reviewable candidate; rejection preserves identities | Trace cites inert PO/customer drafts, which do not prove identity review. X1 mapping table supports candidate/rejected statuses and confidence, but current evidence only directly inserts variant mappings. | Correct identity-specific contract and test, or explicit remaining gap. No chatbot or automatic merge is required. |
| F5 | Accurate completion and integration handoff | Matrix header says staging complete but its X4h row says pending. CI `34672627839` predates X4h. Handoff substitutes `p_document_id` for invoice/credit lifecycle named parameters and leaves purchasing approval capability vague. | Updated stage-specific status, exact-head CI/staging packet, actual `p_supplier_invoice_id` / `p_supplier_credit_id` signatures, and explicit operation/capability mapping. |

## Evidence corrections, not new feature requirements

### F4 follow-up source inspection

At `6a31c2d`, repository-wide references to
`e10_catalog_identity_mappings` occur only in its X1 migration and X1 SQL test.
The test directly inserts variant candidate/rejected revisions and checks their
count. It does not exercise two same-name players, proposal evidence/confidence,
or an authorized rejection operation. The table supports player targets and
review metadata, but authenticated clients have SELECT only and no mapped
decision writer was found. X8's contract explicitly excludes identity decision
and curation from its operation allowlist. Therefore the trace's X8 inert-draft
citation is not proof of this identity-specific acceptance case. Resolve with
an explicit governed backend contract and test, or identify a genuine existing
path before marking F4 complete. Do not introduce automatic merges or a chatbot.

- Identity across copies: X1 fixture includes only one card copy with serial 3.
  X7d2 cohort fixture is stronger: two owned copies with serials 7 and 9 and a
  serial-7 filter. Cite the correct evidence and verify denominator composition
  rather than treating one copy as a two-copy proof.
- Customer source reconciliation: `.github/workflows/ci.yml:119` runs
  `tests/ta_x6d_customer_transaction_adjustments_test.js`. The trace's
  `tests/ta_x6d3_source_reconciliation` is not an actual file path.
- Customer transaction prepare/approve/post and market analytics capability
  strings in the handoff were verified against migrations and need no rename.

## Accepted checkpoints retained

- X8c staging accepted against evidence commit
  `f438f5e79de556e7c07d32fefe521a1ef70edb3c`; this does not close final scope review.
- X4h local implementation accepted at
  `b5d4b9f8ac5ce83a8fb5fdd9377e0e7bca91b00d`.
- Assertion-only follow-up `e881197245322b553f4e84ece6431d3ad7b1fedb`
  reviewed: JSON comparisons now reject missing/null values explicitly.
  X4h staging acceptance is still pending.
- CI `34673940960` independently confirmed completed/success at
  `f0d70693e5789e215f9318d4db5e714daa83724a`. This includes committed X4h and
  the approved X7f plan, but not the uncommitted X7f runtime implementation.

## Review discipline

### X7f plan review checkpoint

Reviewed proposed plan at `ca3f5f3`. Direction supports F1/F2, but not approved
pending four contract clarifications sent to Track A:

1. Full-history attendance/ratio fields must not silently reuse a bounded-window
   path or sum overlapping annual distinct counts. Test engagement-enabled users.
2. Display-name sorting needs explicit authority, deterministic collation/null
   ordering and cursor invalidation when names change.
3. Coverage must expose unknown occurrence, attribution and missing-history
   limitations. Test aggregate known-subtotal filtering on incomplete and
   unknown-only customer totals without presenting them as complete spend.
4. Bound full-history execution without silent truncation; define v2 dispatch
   selection and reject mixed legacy/new cursor inputs.

Revised plan `f0d7069` approved for implementation. It specifies unavailable
known-history attendance ratios, deterministic name sorting and rename revision
invalidation, explicit unknown-history coverage, a fail-closed 100,000 eligible
contribution ceiling, and exact legacy/v2 dispatch selection. This is plan
approval only. Runtime and staging acceptance remain open. Review must verify
selected-customer/location diagnostic privacy and prevent names leaking through
the X8 result or cursor.

### X7f implementation review checkpoint

Implementation `a14c2e558ab0b1d52e119001d8c3bbe87ee9c7cc` not approved yet:

- Name-sort cursor tuples are trusted when supplied instead of checked against
  the actual authorized anchor. A selected-customer query also needs to reject
  another customer's anchor.
- X8 passes JSON `null` cursor as a non-SQL-null value, incorrectly rejecting a
  conventional first-page request. Normalize and validate cursor shape.
- `purchasing_ratio_status` is missing from the promised compatible fields.
- Required 100,000/100,001 resource boundary is not exercised. Sort tests assert
  counts rather than ordering; the name-redaction fixture returns only one row,
  so it does not prove a redacted continuation works.
- V2-specific unknown/empty/currency/correction/authorization and cursor-binding
  cases remain insufficient. Prior v1 regression success does not prove the new
  aggregate projection.

The posted-transactions relation is posted-only by design. The review does not
require an invented draft-status predicate or change established restated-current
reporting semantics. Earlier provisional concern about that predicate is closed.

Follow-up `9e35153` reviewed: server-resolved anchor tuples, selected-customer
guard, JSON-null normalization and restored ratio status address the reported
runtime defects. Local approval is still withheld for the acknowledged missing
resource-boundary and v2 semantic/security tests. Requested one consolidated
complete gate rather than repeated partial approval requests.

Reconcile each finding against actual supported behavior before changing code.

Test-only packet `6a31c2d` reviewed in full, together with the X7f runtime.
Actual 100,001-row refusal / 100,000-row success and a proven lock wait followed
by capability revocation are now exercised. No new runtime defect established.
Three remaining test weaknesses were returned as one bounded follow-up:

- Location-only fixture contains no unauthorized location, so it does not prove
  exclusion from rows, totals or selected-customer unknown-occurrence diagnostics.
- Distinct names and a forged tuple under UUID sorting do not prove duplicate /
  case-colliding name continuation or forged name-sort anchor behavior.
- Spend-sort oracle uses unadjusted line net; its refund does not change rank.
  Require an adjustment that changes ordering and page-invariant monetary totals
  and line counts, not only customer counts.

Follow-up `5abc905` changes only `tests/ta_x7f_customer_spend_grid_test.js`.
Syntax and commit-diff checks pass. The independent adjustment oracle, changing
refund rank, monetary/line-count page invariance, duplicate-name traversal and
forged name-sort cursor now have meaningful assertions. Two precise fixture
corrections remain before local acceptance:

- Selected-customer restricted-location diagnostics must be tested without an
  explicit location filter, which currently masks a missing authorization check.
- Guarantee an eligible NULL-name customer; the current random UUID selection
  can exclude the sole NULL-name row as old history or overwrite it as a tie row.

### X7f local acceptance

`754a7ef` APPROVED LOCAL. The three-line test-only follow-up removes the explicit
location filter from the restricted selected-customer assertion and requires
subtotal 949, one visible line, and one unknown-occurrence line. It also restores
the random NULL name, selects a guaranteed eligible non-colliding NULL-name
customer, and asserts that customer is last in complete one-row name traversal.
The prior runtime, adjustment-oracle, page-total, resource and lock-wait reviews
stand. Syntax and commit-diff checks pass; builder reports both local suites pass.
Exact-head CI and explicitly targeted staging evidence remain required. This
closes the local gate only, not F1/F2 staging acceptance or overall completion.

Independent follow-up: GitHub run `34676324253` completed SUCCESS at exact head
`754a7ef6b37534d7606611c448f0498e55f4db0c`. The test job and both named X7f/X4h
steps passed; production deploy was skipped. Read-only staging ledger inspection
confirms migrations `20260912043132` and `20260912044807` are present. Presence
alone is not staging acceptance: runtime identity, staging behavior, privilege
and cleanup evidence still await the consolidated packet.

### X7f staging performance correction

Builder reports exact-definition staging execution reaches statement timeout
`57014` at 100,001 eligible rows before the intended `54000` resource refusal.
Staging acceptance remains open. Approved a narrow additive corrective plan:
private bounded count-only eligibility helper, replacing only the known-history
preflight. Source inspection confirms the original enrichment lateral joins do
not determine eligibility. Require exact predicate/parity guards, unchanged
authority and fixed ceiling, and actual staging timing for BOTH 100,001 refusal
and 100,000 full-report success. Raising timeouts/caps or silently truncating is
not acceptance. If full aggregation still times out, isolate that bottleneck
before proposing another correction. Original applied migration stays intact.

Corrective `54c7338` reviewed. Independent mechanical comparison proves the
public grid body differs only at the preflight line and the normalized eligibility
WHERE block matches the original contribution helper. Local catalog confirms
SECURITY DEFINER, pinned public search path and owner/service-only execution.
Fixed LIMIT 100001 precedes COUNT. Syntax and diff checks pass. Runtime is
approved in substance; local gate awaits the promised maintained source/parity
guard, because product/configuration/copy/session behavioral cases currently use
only impossible identifiers and can pass vacuously. No runtime change requested.

Follow-up `018876715071d84ba0f8c5e2a77c4600eb22a749` is LOCAL APPROVED.
Its single test-only addition compares catalog definitions for the base joins and
complete eligibility predicate. Independently executing the exact committed SQL
against the local catalog returned `matches=true`; Node syntax check passed.
Builder reports the full X7f matrix passed after clean reset. No runtime changes
since the reviewed correction. Authorized progression: non-production push,
exact-head CI, then explicitly targeted staging. Both boundary performance cases
above remain required; this is not staging acceptance or overall completion.

Exact-head CI `34678245472` independently verified SUCCESS at `018876715071d84ba0f8c5e2a77c4600eb22a749`.
The full test job, named X7f reporting gate and X4h non-card gate passed;
schema-gate and deploy jobs were skipped. Targeted staging performance and
consolidated evidence remain the next acceptance gate.

Staging follow-up reported failure: 100001 preflight still returned `57014`
after its ordinary 300-second timeout (452.27 seconds total test elapsed).
Builder identified effective attribution being recomputed per line after the
planner joined 100001 lines. A new additive private-helper correction plan is
approved: materialize eligible transaction attribution before line joins, retain
every eligibility and permission predicate and the fixed contribution cap.
Replace the shape-specific source guard with positive/nonmatching behavioral
parity fixtures, including multi-line transactions and restricted scope. Require
query-plan loop evidence and both staging boundary outcomes; materialization is
not proof of acceptable performance. Earlier applied migrations remain intact.

Revision `2ee3df80470aba1c61404f614b9270dcfbff33a1` LOCAL APPROVED after full
47-line additive migration and test-delta review. Transaction and line predicates
are preserved; materialization precedes the org-scoped line join and fixed cap.
New tests assert exact positive-one/nonmatching-zero dimension counts, two lines
for one transaction, and three after merge attribution. Independently checked
syntax, diff hygiene, and local catalog stable/SECURITY DEFINER/search path/ACL.
Builder reports clean replay, full X7f in 213.05 seconds, concurrency and default
privilege passes. Exact-head CI and both timed staging public-grid boundary
outcomes remain pending, together with plan/loop evidence and fixture shape.

CI `34679521130` independently verified SUCCESS at exact `2ee3df80470aba1c61404f614b9270dcfbff33a1`.
Named X7f and X4h steps passed; deploy and schema-gate jobs skipped. This clears
the CI gate only. Staging timing, query-plan and consolidated evidence are pending.

Staging after `2ee3df8`: builder reports preflight now advances, but 100000
full-grid raw aggregation still times out at 300 seconds (518.74 seconds total).
Private grid-only contribution projection and diagnostics optimization proposed,
leaving canonical official/X7b functions unchanged. Review requires one plan
amendment: cursor-anchor aggregation cannot retain the slow canonical path just
because it selects one customer; that customer may have 100000 lines. Use the
parity-proven grid projection there too, or empirically prove that path's timing.
Required parity covers independent finalizations, signed adjustments, unknown
components, complete totals, diagnostics, all filters and authority. Require
high-volume continuation and many-distinct-transaction performance evidence.

Batch `0236c9271e1d91186e659d1318db2f174e30f1ab` review in progress; local gate
WITHHELD for test coverage. Existing `parity()` still tests the preflight count
helper, not the new monetary grid projection. The latter has only one selected
customer parity after all finalizations/adjustments. Requested reuse of the
positive/nonmatching, multiline, merge and restricted-scope fixtures for full
new-helper projected-row parity, staged independent component finalization and
signed-adjustment expected values, and explicit diagnostics parity. No runtime
change requested. Builder reports local 100001 refusal 12.135s, 100000 full report
35.971s, heavy cursor pages 36.407s/42.875s; staging performance remains unproven.

Completed runtime source comparison for `0236c92`: original canonical monetary
expressions use the same component MAX finalizations, signed SUM adjustments,
base-value precedence and explicit unknown propagation as the new projection.
The new grouped joins remain confined to authorized org/line identities.
Mechanical comparison proves the public grid body is unchanged outside the two
contribution-helper substitutions and diagnostics replacement. No unrelated
cursor, fingerprint, scope, grouping or output changes found. Local approval
still awaits the requested maintained behavioral tests.

Local gate APPROVED at `bb0719dcdf9b37276e030f62c3f37310669578b5` after
test-only follow-up review. The reusable 16-field projection comparison now uses
NULL-safe empty arrays and covers positive/nonmatching dimensions, multiline,
merged attribution and restricted scope. Independent expected values cover
unknown merchandise before finalization and finalized amounts plus both signed
adjustments afterward (base 8, delta 2, net 10, shipping 2.5, tax 2.5).
Diagnostics compare canonical behavior for selected/unselected cohorts and
explicitly assert authorized unattributed and unknown-occurrence counts while
excluding hidden-location evidence. Full-cap and heavy cursor tests retained.
Coordinator independently passed syntax and commit diff checks. Builder reports
full test PASS in 309.10s, concurrency PASS and default-privileges PASS; timings
are 12.081s refusal, 36.071s full report, 37.345s/42.551s cursor pages.
Exact-head CI and staging acceptance remain pending. Staging must prove ordinary
timeout success/refusal, cursor continuation, many-distinct-transaction plan and
timing, matching hashes/ACLs/ledger and cleanup before closing F1/F2.

Exact-head CI independently verified: run `34681330302` completed SUCCESS at
`bb0719dcdf9b37276e030f62c3f37310669578b5`. Named X7f full-dataset spend and
X4h generic non-card gates both completed SUCCESS; overall test job SUCCESS.
Schema-gate and deploy were SKIPPED. This clears CI, not staging acceptance.

Staging follow-up at bb0719d remains NOT ACCEPTED: builder reports intended
100001 refusal in 111.590s, then 100000 request timed out at ordinary 300s in
count helper -> per-line financial permission -> org capability. Cleanup reports
zero X7f orgs/users. Approved additive set-wise authorization plan for the three
private helpers, preserving existing member/org-cap helpers and per-request
materialization. Canonical source review clarified inactive same-org locations:
org-wide financial readers ARE allowed; only location-scoped grants require
active locations. Missing/foreign locations remain denied and null location
requires org-wide permission. Builder instructed to test those distinctions,
platform-admin preservation, no join multiplication, concurrent revocation and
many-distinct-transaction volume before new exact CI/staging gates.

Reviewed `91fdc1e288e783e7bc97ec84760274aaee72e278`: three private replacements
only, canonical permissions preserved in source, DISTINCT allowed locations plus
EXISTS prevent row multiplication; org-safe location joins and ACLs retained.
Syntax and commit diff checks pass. Local gate WITHHELD for two test weaknesses:
inactive location has no explicit grant, so denial does not prove active-status
enforcement; missing/foreign p_location filters mismatch the actual line, so
zero rows do not prove same-org existence checks. Requested test-only follow-up
with granted inactive location and actual missing/foreign line locations, both
permission scopes, projection and diagnostics parity, restoration/cleanup.
Builder reports new local full reports at 412ms (one transaction) and 620ms
(2000 transactions), refusals 72ms/97ms, cursor 487ms/591ms. These are not staging
performance acceptance. Runtime review found no additional defect.

Local APPROVE at test-only `1dbd2ec888fd1437f9f604160cd035eebc8544a0`, paired
with runtime 91fdc1e. Actual target-line locations now cover inactive/null/missing/
foreign cases without conflicting filters. Explicit restricted grants isolate
active-status and same-org existence checks; canonical count/projection and
diagnostic comparisons run, and fixtures restore locations/grants. Existing
active scoped positive remains. Coordinator syntax/diff checks pass. Builder
reports full local PASS 1:52.72 and concurrent-auth/default-privilege PASS.
Exact-head CI and ordinary-timeout staging remain required before F1/F2 close.

Independent exact-head CI check cleared `34682691228` at
`1dbd2ec888fd1437f9f604160cd035eebc8544a0`: overall SUCCESS, test job SUCCESS,
named X7f/X4h steps SUCCESS; schema-gate/deploy SKIPPED. Staging remains pending.

Staging behavioral packet received for 1dbd2ec: full suite PASS at ordinary
300s timeout, total 2:59.70; one-transaction overcap 825ms, full 3031ms,
cursor 3279/4202ms; 2000-transaction full 4582ms and overcap 917ms. Builder
reports post-lock concurrency and default-privileges PASS. Coordinator directly
verified local/staging equality of all four X7f function hashes and X4h hash,
pinned SECURITY DEFINER definitions and exact private/public ACLs. Direct staging
cleanup query found zero X7f orgs/users/bulk lines. Requested committed durable
X7f/X4h packet with command/log provenance and specific X4h staging execution
evidence. Timing plus fixture shape is behavioral performance evidence, not a
captured EXPLAIN plan; packet must distinguish these. Final closure awaits packet.

STAGING ACCEPT X4h/X7f and close F1/F2 at evidence commit
`26442b8f32d016f9b64e89029a5a33362fe246f9`, exact implementation/test head
`1dbd2ec888fd1437f9f604160cd035eebc8544a0`. Entire durable packet
`docs/TA_X4H_X7F_STAGING_EVIDENCE.md` reviewed, including X4h core/concurrency
execution. Independent checks confirm both migration file hashes, all five
local/staging function identities and ACL/search paths, six migration ledgers,
zero X7f residue and zero X4h users/orgs. Exact-head CI already verified SUCCESS.
F3 combined card-query proof, F4 same-name identity governance, and F5 final
trace/matrix/handoff reconciliation remain open. Overall goal is NOT complete.

F3 test-only plan approved using supported catalog subject filter, not forbidden
catalog exact_subject=true. Reviewed `56c1182941c16ccc6ba077efb3617a2c0d4b2863`:
two rookie PSA9 variants across releases/manufacturers, unknown rookie and PSA8
controls, limit-one two-page exact membership, hostile and cursor mismatch cases.
Local approval withheld for actual SQL authenticated role (claims alone leave
postgres role) and non-null initial fingerprint/revision assertions. Requested
focused test-only follow-up; no new runtime change or scope expansion.

F3 LOCAL APPROVE `d0d097f2398eb7339f6ecd212c7d70d4a3733c6a`: actual
authenticated SQL role now wraps public reads, hostile JWT switch retained,
role reset and non-null snapshot fields asserted. Combined cross-release
membership/negative/pagination tests preserved. Builder focused PASS; independent
diff check PASS. Exact-head CI and focused staging rollback evidence pending.

F4 additive plan approved: platform-admin propose/reject plus required bounded
reader for immutable identity cases, alternative player candidates, append-only
decisions. Preserve manual/model source namespace+key, explicit tool/version,
confidence/evidence; distinct player IDs not constrained to same names. No
automatic or manual merge/link approval implemented by this narrow contract.
Canonical mapping/player rows unchanged on rejection. Exact retry/mismatch,
revision CAS, post-lock actor authority, hostile access and concurrent rejection
tests required before CI/staging. Do not describe this as a full resolver or AI.

F3 exact-head CI independently verified SUCCESS: run `34683432065` at
`d0d097f2398eb7339f6ecd212c7d70d4a3733c6a`, test SUCCESS and schema-gate/deploy
SKIPPED. Focused staging rollback proof and durable evidence remain pending.

F3 STAGING ACCEPT: durable `65751b6` packet reviewed against tested `d0d097f`.
Explicit staging command and rollback PASS recorded; coordinator directly
confirmed zero F3 org/user residue. F3 closed. Wrong-subject control is a query
against a different subject with no variants, not an additional variant fixture.
F4 identity ambiguity governance and F5 final reconciliation remain open.

F4 name-index correction APPROVED within existing acceptance scope. Independent
local pg_indexes confirms unique name_norm and lower(name) indexes; all nine
player foreign keys reference UUID id. Same-display-name acceptance cannot pass
with those uniqueness rules. Builder authorized to drop both name-only unique
indexes without CASCADE in the new F4 migration and add nonunique (name_norm,id),
preserving UUID PK, trigram search, rows and relationships. Require deterministic
same-name retrieval and rejection preservation, identity/catalog regressions and
predecessor replay. No applied baseline edits, production, or automatic merging.

F4 exact candidate cd15b119dae9600ed673df5bb135a2ebbeb11de7 reviewed in full
(migration, functional/concurrency tests and CI registration). Runtime shape is
aligned; local acceptance withheld pending focused coverage of ordinary propose
denial, invalid candidate/provenance bounds with no residue, reject key mismatch,
duplicate source, append-only enforcement, concurrent proposals and propose
post-lock revocation. Existing tests prove same-name identity, read/reject denial,
reject race and rejection case-lock revocation, but do not prove those additional
claims. Requested removal of redundant case-id index already covered by PK and
documentation of historical replay status. No redesign or production authority.

F4 LOCAL APPROVE exact bf99230063bd81c14b215254b7fd257fda14f399.
Reviewed guards suite and concurrency follow-up: requested denial, bounds,
duplicate-source, reject mismatch, append-only and proposal-race/revocation
closures are directly exercised. Redundant index removed. Independent local
catalog confirms three pinned SECURITY DEFINER RPCs with only postgres/service/
authenticated EXECUTE and three RLS tables with postgres/service-only grants.
Player UUID PK, trigram and nonunique normalized-name index retained. Node
syntax and diff checks pass. Exact-head CI and explicit staging with durable
evidence remain required; F4 not staging accepted and F5 still open.

F4 exact CI34684368998 independently SUCCESS at bf99230; test SUCCESS,
schema-gate/deploy SKIPPED. Evidence983c2e8 read fully. Independent direct
staging checks confirm all three function hashes match local and packet, pinned
search paths/allowlisted ACLs, three RLS service-only tables, expected player
indexes, exact 20260912093000 ledger and zero cases/candidates/decisions/test
users. Requested evidence-only command and captured output provenance for
functional/guards/concurrency/defaultpriv runs before final staging acceptance;
reuse existing logs, no unnecessary rerun. F5 remains open.

F4 STAGING ACCEPT at evidence f359fb0da66c206b79647977ba63bd5b698a939f,
runtime/test bf99230063bd81c14b215254b7fd257fda14f399. Added explicit
staging-target commands and captured functional/guards/concurrency/defaultpriv
outputs reviewed. Together with independently verified exact CI, local/staging
function parity, ACL/RLS/index/ledger and cleanup checks, this closes F4.
F5 final requirement trace, completion matrix and exact integration handoff
reconciliation remain open. Builder directed to reconcile these, preserving
owner edits and all original scope/non-production boundaries.

F5 e80df72 review started. Read complete expanded acceptance cases, acceptance
trace and integration handoff. Two current doc contradictions sent for correction:
handoff universal explicit-org/member rule contradicts shared catalog/platform
F4/service outbox families; referenced normative X8 implementation contract still
maps spend_summary to v1 and old argument rules at lines71/341/370 despite X7f
v2 runtime. Require accurate family-specific authority and current normative v2
override, preserving history. Full remaining authoritative-source/evidence audit
is still underway; no overall final acceptance.

F5 full framework and X7e/X8 checklists reviewed. Requested explicit evidence or
approved deferral for section11 customer contact/consent/preferences/tags/notes
storage and permission contracts (X6a basic table does not show these), and
section1 typed-extension scope classification. These are reconciliation questions,
not authorization to invent a general engine or widen the goal. Requested final
advisor disclosure/F4 delta disposition required by the security register. No
new runtime defect established by those documentation questions yet.

F5 ledger audit exposed genuinely absent staging X6d3 corrective20260911164840.
Builder applied exact already-CI-tested file and reports targeted staging suite
PASS. Independent MCP now confirms ledger and wrapper hash75d23f22b0ef1c308ff7e9bc0127f1700de5e2d0aa3b4e15c5207bde037d17f9
matches clean local, with expected comment/ACL/searchpath. New packet read;
requested fixture cleanup evidence and compact full application schema parity
manifest/diff because migration-name counts alone missed real runtime drift.
CRM/extension classification must distinguish broader unimplemented framework
from enumerated X1-X8 implementation outcome; a slice's non-claim is not proof
of an owner-approved global deferral. No new generic engine authorized.

F5 ac79c58 read: family authority and dual v1/v2 contract corrections align.
Parity evidence coverage contradicted by independent local pg_proc census:
public192 plus e10 144 functions, but packet claims whole-app function manifest
with count192. Requested reproducible exact manifest queries for BOTH schemas,
definitions/signatures/ACL/searchpaths plus triggers/policy expressions and
existing structural categories; explicit review of comment-only differences.
Also X8v2 implementation unconditionally strips display_name, so conditional
contact-visibility wording must be corrected. No runtime change requested.

F5 parity correction161a029 independently verified via direct staging MCP and
local psql using the committed manifest CTE. All 336 function metadata rows,
170 tables, 2042 columns, 1671 constraints, 649 indexes, 228 triggers and 97
policies have equal aggregate hashes across targets. All 334 nonexception
function definitions match exactly. Both exception definitions fetched from
each target and read directly: module_bundle differs in comments, formatting
and optional terminal SQL semicolon; verify_handle_claim differs only in the
nine numbered comments. No behavioral difference identified. This closes the
specific whole-application parity evidence blocker, not overall F5 acceptance.
Read 4fd7a88 handoff diff: full customer/credit/allocation signatures and
operation-specific capabilities now explicit. Final integration contract and
requirements closure remains pending the final packet.

F5 handoff 4fd7a88 full current read complete. Independently extracted all 66
explicit public RPC signatures and compared names/argument order/types against
local pg_proc identity arguments, normalizing only type spelling and documented
defaults: zero mismatches. Latest origin/foundation-a6 matches4fd7a88; its
exact-head CI34685754343 is currently in progress. Re-read complete acceptance
trace and remaining classifications. No new in-scope implementation gap found
in this pass. Final CI and completion packet still pending.

Final deliverable link check: 109 unique exact .md/.sql/.js tokens across
acceptance trace, final matrix and handoff; all 108 file references resolve.
The remaining token arbitrary.sql is intentionally an invalid dispatcher
operation in the negative-test description, not a missing file. CI34685754343
still active, observed at TA-X7c provider-normalization gate; no restart needed.

## Final independent acceptance

FINAL ACCEPT: approved Track A X1-X8 backend foundation through explicitly
targeted staging, at published origin/foundation-a6 head
4fd7a88c21861921774647cdc4812ec18d9a2c9f. CI34685754343 independently read
as SUCCESS at that exact SHA, test job SUCCESS, schema-gate and deploy SKIPPED.
F1-F4 accepted above; F5 closes with full requirements trace, exact integration
handoff, staged correction and independently reproduced schema parity. No
remaining in-scope blocker identified by the requirement-by-requirement audit.

Completion applies to the approved backend goal, not the entire product vision.
Track B/live board/companion/OBS UI adoption, production cutover, chatbot,
feeds, trackers and collector showcase remain outside this goal. Broader
generic typed extensions and privacy-reviewed CRM contact/consent/tags/notes
are explicitly unimplemented framework seams, not hidden implemented claims.

Latest independent production read confirms no e10 schema, 12 migrations with
maximum20260716110000, and no action-draft table. Latest staging advisors have
zero ERROR and match the disclosed baseline; this is not a claim of zero
warnings. All prior dirty owner files remain preserved. This final section
supersedes earlier pending labels in this chronological review ledger.

Do not broaden to UI, live feeds, chat, scheduled work or production. Use targeted
tests for evidence corrections, then the registered release gates for changed
runtime batches. Preserve user changes. All findings in this review are closed
by the final acceptance above; future work requires its own scope and evidence.
