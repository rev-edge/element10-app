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
