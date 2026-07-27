# Element 10 UX Workflow Contract

Status: proposed binding design and review contract. Read with
`OPERATOR_LIFECYCLE.md`.

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

The implementation plan follows this artifact. A corrective ticket does not waive it.

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

## 7. Evidence

Required workflow scenarios:

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

## 8. Agent directive

For every UI planning or implementation task:

1. Read `OPERATOR_LIFECYCLE.md` and this contract.
2. Inspect the existing implementation and nearest equivalent pattern.
3. Produce the workflow preflight before code.
4. Identify adjacent gaps proactively.
5. Separate observations from authorized implementation.
6. Implement only the reviewed plan.
7. Run the workflow scenarios before packaging.
8. Report unresolved lifecycle gaps without self-authorizing them.

The agent is expected to challenge an incomplete task loop even when every named
control in the prompt can be implemented literally.
