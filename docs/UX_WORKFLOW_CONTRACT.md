# Element 10 UX Workflow Contract

Status: binding design and review contract. Read with
`OPERATOR_LIFECYCLE.md` and `OPERATOR_WALKTHROUGH_PROTOCOL.md`.

## 1. Definition of done

A UI change is not complete because the requested component exists or a mutation
returns successfully. It is complete when the operator can:

- understand what happened;
- continue to the next natural action;
- review or correct the result;
- safely cancel or leave;
- resume incomplete work;
- recover from denial, conflict, stale state, or failure;
- retain the object and navigation context that motivated the task.

No successful task ends in only a toast, an unexplained blank state, or a global-nav
search for the next step.

## 2. Required planning artifact

Before implementation, produce a workflow preflight with:

| Field | Required content |
|---|---|
| Operator job | outcome in the operator’s language |
| Start | entry points, origin, parent object, preconditions |
| Commit | exact business mutation or handoff |
| Success | immediate state and saved evidence |
| Continue | primary and secondary next actions |
| Review | detail, summary, edit, archive, undo, or additive correction |
| Leave | Back, Cancel, close, unsaved-work behavior |
| Repeat | add another, bulk, keyboard/focus, progress |
| Resume | durable surface or queue for incomplete work |
| Recover | empty, loading, denied, duplicate, conflict, stale, failed |
| Boundary | deferred model/capability and the honest present-day seam |
| Return context | route, filters, selection, object, focus |

The implementation plan follows this artifact. A corrective that creates or
materially changes workflow does not waive it. A narrow corrective inside an
already reviewed task loop may cite the approved preflight and use the targeted
walkthrough matrix defined by `OPERATOR_WALKTHROUGH_PROTOCOL.md`.

## 3. Surface action inventory

Every touched surface must identify:

- one state-aware primary action;
- relevant secondary actions;
- Save or commit behavior;
- review or detail destination;
- Back or origin-aware return;
- Cancel/close behavior;
- unavailable and permission-denied behavior;
- empty and interrupted-work behavior.

Not every surface needs every button. Every operator task needs every responsibility
addressed.

## 4. Adjacent-flow responsibility

The designer inspects the step immediately before and after the requested change.

- In-scope, low-risk continuity defects are included in the workflow plan.
- A larger data, security, or lifecycle contract is reported to the CPI and not
  silently implemented.
- The present checkpoint must still end in a usable, truthful state.
- “Out of scope” means “do not build it,” not “do not think about it.”

## 5. State-aware actions

Action priority follows lifecycle state, not a universal static layout.

Examples:

- collection intake below expected count: Add another is primary;
- expected count reached: Review acquisition is primary;
- single-card acquisition after its card exists: review, not Add another;
- editing an existing record: return to the invoking context;
- unavailable future stage: explain that it is not available and do not call it the
  immediate next step.

## 6. Navigation rules

- Preserve origin, parent object, filters, selection, and focus.
- Use explicit origin-aware return for detours.
- Provide visible Back or breadcrumb on full working surfaces.
- Guard unsaved work before destructive navigation.
- Cancel never commits.
- Success never strands the operator.
- Parent detail is the durable resume surface for child-entry workflows.

## 7. Evidence and walkthrough coverage

**Floor first: the self-debug sweep.** Before any scenario evidence, run
`tests/harness/selfdebug.js` on every touched surface and report it green, or
every failure explained (walkthrough protocol §6a). Scenario evidence over a
surface whose basic controls are broken proves nothing — unclickable controls,
reversed typing, dead buttons, dead-end saves and undismissable dropdowns are
the builder's to find, never the operator's.

Evidence classes are independently satisfiable: four of the five need no
renderer. A renderer outage degrades the render class ONLY, disclosed by
scenario id, and never blocks a gate (§8a). Deliver the build where others can
reach it — a build only the builder can open cannot be independently verified.


The following lifecycle scenarios are the minimum outcome coverage:

1. First-time completion.
2. Repeated or bulk action.
3. Incomplete exit and resume.
4. Final-item completion.
5. Edit and return.
6. Cancel with no phantom record.
7. Denial/conflict and recovery.

Evidence states the start, action, committed outcome, immediate UI, continuation, and
ending context. Screenshots remain required for render claims, but screenshots alone
cannot satisfy workflow acceptance.

`OPERATOR_WALKTHROUGH_PROTOCOL.md` supplies the execution method. It requires:

- lifecycle, interruption, boundary-transition, mutation/invariant, and
  temporal/input tours;
- baseline and materially different adversarial passes;
- a risk-based state and transition matrix;
- separate interaction, mutator, persisted-state, render, and boundary evidence;
- defect-family expansion and regression for every finding;
- bounded claims, explicit untested conditions, and independent acceptance.

One end-to-end click-through cannot establish workflow acceptance. Static
organization, role, or entitlement checks do not prove transitions made while work
is open.

## 8. Agent directive

For every UI planning or implementation task:

1. Read `OPERATOR_LIFECYCLE.md`, this contract, and
   `OPERATOR_WALKTHROUGH_PROTOCOL.md`.
2. Inspect the existing implementation and nearest equivalent pattern.
3. Produce the workflow preflight before code.
4. Identify adjacent gaps proactively.
5. Separate observations from authorized implementation.
6. Implement only the reviewed plan.
7. Declare the walkthrough coverage matrix and scenario IDs before testing.
8. Run the required tours and separate evidence classes before packaging.
9. Expand every finding into its invariant and sibling paths.
10. Report unresolved lifecycle gaps and untested conditions without
    self-authorizing them.

The agent is expected to challenge an incomplete task loop even when every named
control in the prompt can be implemented literally.
