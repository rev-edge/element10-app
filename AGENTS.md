# Element 10 project agent instructions

These project instructions supplement the global engineering brief.

## Session boot

1. Confirm the canonical repository and current gate.
2. Read `BOARD.md`.
3. For any product, workflow, frontend, prototype, or UX task, read:
   - `docs/OPERATOR_LIFECYCLE.md`
   - `docs/UX_WORKFLOW_CONTRACT.md`
   - `docs/OPERATOR_WALKTHROUGH_PROTOCOL.md`
   - the relevant domain and authority documents linked by the current gate.
4. Inspect the current implementation and nearest equivalent pattern.
5. Separate planning from implementation.

## Working model (2026-08-24 — time-boxed sprints, supersedes checkpoints)

- Work runs in **SPRINTS**: one dispatch, one delivery, scoped to roughly an
  hour. Sprints are numbered in `SPRINT_PLAN_INVENTORY.md`; your charter names
  which sprint you are running.
- **Scope is the control, not the clock.** You cannot measure an hour and must
  not try. Finish the sprint's named deliverable and evidence it. **Never stop
  mid-feature to respect a time budget** — a half-built surface is worse than a
  long sprint. If the scope turns out to be materially larger than the sprint
  describes, say so in the delivery and let the CPI resize the remaining plan.
- **Every sprint ends in a truthful, usable state.** Leaving a capability
  unbuilt is fine. Leaving one half-built, or shipping a control that implies a
  capability that is not there, is not.
- **Self-recorded sprint results are PROVISIONAL.** Only the CPI writes ledger
  rows. The CPI audits every sprint return; the operator accepts at feature
  boundaries (end of a PF-C), not at every sprint.
- **HARD STOPS halt the batch immediately**: a schema/capability/tenancy/
  financial/channel/lifecycle contract is needed · a commercial ruling is
  needed (how the business operates) · a finding you cannot disposition ·
  baseline verification or a regression fails · the charter boundary is reached
  · you are about to touch anything frozen or out of scope. A CPI ruling
  (technical, consistency, or modelling) is asked and answered without ending
  the batch.
- **Acceptance authority:** the operator accepts anything operator-facing (UI,
  UX, workflow, walkthroughs) and rules on commercial judgment; the CPI accepts
  engine gates, model documents, non-operator-visible correctives, and process.
  Production cutover execution needs the operator's explicit go.

## Debug your own work — the operator is not the debugger

**Before any evidence pass, on every touched surface:**

    cd tests/harness && npm install        # once
    node e10_harness.js <build.html> selfdebug.js

Green — or every failure explained — BEFORE scenario evidence begins. The sweep
types into every input (re-acquiring the live node per keystroke so a
self-rerendering field's caret is genuinely tested), clicks every enabled button
checking for thrown errors and for actually changing something, proves dialogs
dismiss on Escape, checks the native-popover ban, and scans cards-off per
surface. Extend it when a gate adds a surface or control class it does not
reach. A sweep finding is a finding: defect-family expansion applies and it is
reported even when self-fixed.

Unclickable controls, reversed typing, dead buttons, dead-end saves and
undismissable dropdowns are **yours to find**. See protocol §6a.

**Evidence is never single-homed** (§8a): four of five evidence classes need no
browser. A renderer outage degrades the render class only — disclosed by
scenario id — and never blocks a gate. Deliver your build to the shared folder
(or a drop zip) as soon as it compiles: a build only you can reach cannot be
independently verified.

## Artifact reachability — inputs and outputs both (standing rule 15)

Every artifact a charter names as an input or an output lands in the **shared
folder** with its **SHA-256 and byte size**. The charter author supplies the
inputs; you relay the outputs. Neither side cites a path the other cannot reach.

- Report the path you actually wrote to, not the path you intend it to live at
  eventually. "Delivered to `docs/…`" when the file is in your workspace costs a
  review cycle.
- **If a charter names an input you cannot reach, STOP and hand it up.** That is
  the charter author's defect, not yours to work around, and not yours to
  substitute a plausible-looking file for.
- **Never census, audit, or build against a source whose identity is not
  hash-pinned.** A stale clone under a repo-like name returns a clean result that
  is entirely false. This happened on 2026-08-20; the agent stopped, which was
  right, and the stale copy is now renamed `DO_NOT_CENSUS__…`.

## Workflow responsibility

- Own the operator task, not only the named component or screen.
- Before implementation, produce the workflow preflight required by
  `docs/UX_WORKFLOW_CONTRACT.md`.
- Inspect the steps immediately before and after the requested change.
- Scope limits implementation. It does not limit analysis or gap reporting.
- Never silently create a schema, lifecycle, capability, tenancy, or financial rule.
- End the current checkpoint in a truthful usable state when a later rule is deferred.
- A successful save may not end with only a toast or no visible continuation.
- Preserve origin, parent object, filters, selection, unsaved state, and focus across
  detours and return.
- Cover first-time, repeat, incomplete, final-item, edit, Cancel, denial, and recovery
  cases.
- Verify workflows through the separate tours and evidence classes required by
  `docs/OPERATOR_WALKTHROUGH_PROTOCOL.md`.

## Design gate

For a new or materially changed workflow:

1. Plan the complete task loop.
2. Have the plan reviewed.
3. Implement the reviewed plan.
4. Verify with the required walkthrough tours, behavioral scenarios, mutator
   probes, persisted-state evidence, and render evidence.
5. Report unresolved adjacent gaps without self-authorizing them.

Do not combine an unreviewed workflow plan and its implementation in one pass.

## Walkthrough and acceptance

- A first walkthrough pass never establishes completion.
- Run a baseline pass and a materially different adversarial pass.
- Distinguish static starting-state checks from organization, role, entitlement,
  parent, and approval changes made while work is open.
- Every finding triggers defect-family expansion: state the invariant, inspect all
  sibling mutators and transitions, and add regression coverage.
- Tie broad claims to enumerated scenario IDs, source censuses, or queries. State
  relevant conditions that were not tested.
- An undispositioned finding blocks gate acceptance.
- The builder reports `ready for independent review` and never accepts its own
  implementation. Only the CPI records acceptance in `BOARD.md` after the required
  independent and operator review.

## Documentation

- `docs/OPERATOR_LIFECYCLE.md` is the operator-job authority.
- `docs/UX_WORKFLOW_CONTRACT.md` is the workflow Definition of Done.
- `docs/OPERATOR_WALKTHROUGH_PROTOCOL.md` is the workflow verification and
  acceptance-evidence authority.
- `BOARD.md` remains the gate and approval authority.
- Domain, security, capability, and database documents remain authoritative for their
  respective boundaries.
- A pass is not complete until current documents describe the resulting task loop and
  known deferred seams.
