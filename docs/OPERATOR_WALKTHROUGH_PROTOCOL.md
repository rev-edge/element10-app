# Element 10 Operator Walkthrough Protocol

Status: binding workflow verification and acceptance protocol. Read with
`OPERATOR_LIFECYCLE.md` and `UX_WORKFLOW_CONTRACT.md`.

## 1. Purpose

An operator walkthrough is a structured attempt to disprove that a workflow is
complete. It is not a demonstration of the intended happy path and it is not an
acceptance ruling.

This protocol prevents four recurring failures:

- one linear click-through being reported as complete coverage;
- static role or organization checks standing in for mid-operation transitions;
- a discovered defect being treated as isolated instead of expanding its full
  defect family;
- the builder accepting its own implementation.

The protocol applies to new workflows, materially changed workflows, corrective
gates, and regression reviews. A narrow corrective may reduce the matrix, but it
does not waive the relevant tours or acceptance separation.

## 2. Authority and roles

- `OPERATOR_LIFECYCLE.md` owns the operator jobs and handoffs.
- `UX_WORKFLOW_CONTRACT.md` owns workflow planning and Definition of Done.
- This document owns walkthrough execution, evidence, claim discipline, and
  acceptance separation.
- `BOARD.md` owns the active gate and records the acceptance ruling.

Roles are distinct:

| Role | Responsibility | May accept the gate? |
|---|---|---|
| Builder | implement, self-test, disclose findings, package a candidate | No |
| Independent reviewer | challenge the candidate, run or verify the required tours, audit evidence | No |
| Operator | exercise the workflow for business fit and identify real-world gaps | Recommends approval or rejection |
| CPI | reconcile evidence, findings, operator ruling, and Board authority | Yes, through the Approvals Ledger |

A builder's walkthrough is useful pre-submission evidence. It never counts as
independent acceptance. The builder reports `ready for independent review`, not
`accepted`, `complete`, or an equivalent gate ruling.

## 3. Walkthrough entry conditions

Before the first click, record:

- current gate and authorized phase;
- accepted baseline package and hashes;
- reviewed workflow-preflight identifier, when required;
- in-scope surfaces and business mutations;
- explicit out-of-scope boundaries;
- fixture organizations, roles, entitlements, and object states;
- the expected business invariants;
- every exposed mutator that can commit the affected state;
- the coverage matrix and scenario identifiers.

If the agent cannot identify the committing mutators or expected invariants, the
walkthrough is not ready to begin.

## 4. Coverage matrix

The walkthrough matrix varies the dimensions below. Full Cartesian coverage is
not required. Use risk-based pairwise coverage, then cover every combination
that crosses a load-bearing authority, money, inventory, tenant, lifecycle, or
destructive-action boundary.

| Dimension | Minimum states to consider |
|---|---|
| Lifecycle | first item, repeated item, incomplete, final item, edit, archived/restored where applicable |
| Business state | empty, draft, committed, approved, stale, conflicted, terminal |
| Authority | allowed role, denied role, direct mutator attempt |
| Tenant and entitlement | organization A, organization B, cards-on, cards-off, switch while work is open |
| Mutation | create, update, archive, restore, delete, reparent, related-object change |
| Navigation | Back, Cancel, close, Escape, outside click, refresh, origin-aware return |
| Input and timing | empty, zero, negative, maximum, malformed, rapid repeat, double-submit, stale form |
| Related objects | parent changed, child added or removed, approval invalidated, reservation or cost affected |

The matrix distinguishes initial-state coverage from transition coverage. Opening
a page as a cards-off organization does not prove safety when the Cards module is
disabled while a card form is already open.

## 5. Mandatory tours

Every materially changed workflow runs all five tours. A corrective gate runs
the tours relevant to the corrected invariant plus regression tours for the
surrounding task loop.

### Tour A: lifecycle completion

Exercise:

- first-time completion;
- repeated or bulk work;
- incomplete exit and durable resume;
- final-item completion;
- review and correction;
- edit and return to origin.

Confirm the committed object, immediate result, state-aware continuation, review
path, and ending context.

### Tour B: interruption and navigation

Interrupt work using:

- Back, Cancel, close, Escape, and outside click;
- refresh or route change where supported;
- dirty-state exit;
- nested picker, dialog, or popover dismissal;
- abandonment before the first child exists.

Confirm that unsaved work is guarded consistently, Cancel creates nothing,
transient UI closes in the correct order, and the durable resume surface remains
reachable.

### Tour C: boundary transitions

While a form, dialog, or draft is open, change the relevant:

- organization;
- role or authority;
- module entitlement;
- parent object;
- visibility or archived state.

Then attempt the commit through both the visible UI and the committing mutator.
Confirm fail-closed enforcement, vocabulary isolation, dirty-state handling, and
no cross-organization persistence or rendering.

### Tour D: mutation and invariant

Identify every mutation that can affect the workflow's business invariant. Test
the relevant create, edit, archive, restore, delete, reparent, and related-object
changes before and after approval or other terminal states.

Examples include:

- adding, removing, or moving a card after cost assignment approval;
- changing a reserved lot after preparation;
- editing a parent after a child workflow commits;
- archiving an object still referenced by active work.

Verify both sides of any relationship. Moving a child must reconcile the source
and destination parents, not merely update the child.

### Tour E: temporal and input

Exercise:

- double-submit and rapid repeated clicks;
- repeated Escape or outside-click sequences;
- saving with a nested decision unresolved;
- stale form submission;
- empty, zero, negative, malformed, fractional, and upper-bound inputs;
- retries with the same idempotency key where applicable.

Confirm one intended mutation, deterministic recovery, normalized values, and no
phantom or duplicate records.

## 6. Pass structure

At least two materially different passes are required:

1. **Baseline pass:** execute the planned lifecycle and contract scenarios from
   known fixtures.
2. **Adversarial pass:** reset to known fixtures, vary click order and boundary
   transitions, and target assumptions exposed by the baseline pass.

The adversarial pass may not simply repeat the baseline with different sample
data. It must include different transitions and failure hypotheses.

A finding in either pass triggers defect-family expansion and a focused rerun.
There is no acceptance after the first pass, even when it reports zero findings.

## 7. Defect-family expansion

For every finding:

1. State the violated invariant.
2. Identify every sibling surface, mutator, object transition, and role that can
   reach the invariant.
3. Search the implementation for all enforcement and rendering entry points.
4. Test the sibling paths before proposing scope.
5. Classify each result as:
   - must close in the current gate;
   - requires an operator ruling;
   - requires a model, capability, tenancy, or Track A decision;
   - documented later-checkpoint work that leaves the current task usable.
6. Add a regression scenario for the original path and the defect family.

Example: if adding a card makes an approved cost assignment stale, do not stop at
the Add path. Test edit, archive, restore, delete, and move-between-acquisitions,
then verify both source and destination acquisition state.

## 8. Evidence classes

No evidence class substitutes for another:

| Evidence class | What it proves |
|---|---|
| Interaction evidence | the real click, focus, keyboard, dismissal, and navigation sequence |
| Mutator evidence | the committing function independently enforces authority and invariants |
| Persisted-state evidence | the intended business state was committed exactly once |
| Render evidence | the settled interface displays the claimed state and actions |
| Boundary evidence | tenant, role, entitlement, and context transitions fail closed |

Screenshots prove settled pixels. They do not prove that a mutator refused, that
the correct row persisted, or that a workflow can resume.

## 9. Scenario record

Every scenario receives a stable identifier and records:

| Field | Required evidence |
|---|---|
| Scenario ID | stable identifier reused by regression evidence |
| Tour and pass | A-E and baseline/adversarial/focused rerun |
| Hypothesis | behavior or invariant being challenged |
| Starting state | organization, role, entitlement, route, objects, approvals |
| Exact sequence | clicks, keys, context changes, and direct probes in order |
| Expected result | mutation, refusal, navigation, and retained context |
| Actual result | observed behavior without interpretation |
| Persisted result | rows, totals, statuses, or event evidence |
| Ending context | route, parent, filters, selection, focus, open work |
| Evidence | screenshot, test, query, source census, or recording identifier |
| Result | pass, fail, blocked, or not run |
| Follow-up | finding ID, regression ID, ruling, or later checkpoint |

## 10. Claim discipline

- Report `scenario IDs X, Y, and Z passed`, not `org isolation held everywhere`.
- Separate static starting-state tests from mid-operation transition tests.
- State every relevant condition that was not run.
- `Nothing crashed`, a clean console, and a successful happy path are observations,
  not acceptance evidence.
- A source census may support `all mutators contain the guard`; one UI refusal may
  not.
- A test constructed differently from the failing operator path does not replace
  that path.
- Evidence captions describe what the artifact actually shows.

## 11. Findings and disposition

The walkthrough report maintains a findings ledger:

| Field | Meaning |
|---|---|
| Finding ID | stable identifier |
| Severity | blocker, major, moderate, improvement |
| Invariant | rule or business fact violated |
| Defect family | sibling paths and entry points inspected |
| Disposition | current-gate fix, operator ruling, model escalation, later checkpoint |
| Regression | scenario proving the closure |
| Status | open, fixed-unverified, verified, accepted-risk |

An undispositioned finding blocks gate acceptance. A finding marked fixed remains
open until its original path, defect family, and regression scenario pass.

## 12. Completion and stopping rule

A candidate is ready for independent review only when:

- the coverage matrix is complete or explicitly bounded;
- all five required tours, or the approved corrective subset, have run;
- baseline and materially different adversarial passes have run;
- every finding has a disposition;
- every current-gate fix has verified regression evidence;
- untested conditions and later-checkpoint gaps are explicit;
- package hashes and render evidence are complete;
- current documentation describes the resulting task loop.

The builder then stops and requests independent review. Only the CPI may record a
gate as accepted after independent evidence and the operator ruling required by
`BOARD.md`.

## 13. Walkthrough report template

```text
Candidate:
Gate and phase:
Accepted baseline:
Reviewed preflight:
Builder:
Independent reviewer:
Operator:

Coverage matrix:
- lifecycle:
- business states:
- authority:
- tenant and entitlement:
- mutations:
- navigation:
- input and timing:
- related objects:

Pass 1, baseline:
- scenario IDs:
- findings:

Pass 2, adversarial:
- materially different transitions:
- scenario IDs:
- findings:

Defect-family expansions:
- finding -> invariant -> sibling paths -> results:

Evidence-class reconciliation:
- interaction:
- mutator:
- persisted state:
- render:
- boundary:

Untested conditions:
Findings ledger:
Regression results:
Operator ruling:
CPI disposition:
```
