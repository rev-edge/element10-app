# Element 10 project agent instructions

These project instructions supplement the global engineering brief.

## Session boot

1. Confirm the canonical repository and current gate.
2. Read `BOARD.md`.
3. For any product, workflow, frontend, prototype, or UX task, read:
   - `docs/OPERATOR_LIFECYCLE.md`
   - `docs/UX_WORKFLOW_CONTRACT.md`
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

## Design gate

For a new or materially changed workflow:

1. Plan the complete task loop.
2. Have the plan reviewed.
3. Implement the reviewed plan.
4. Verify with the required behavioral scenarios and render evidence.
5. Report unresolved adjacent gaps without self-authorizing them.

Do not combine an unreviewed workflow plan and its implementation in one pass.

## Documentation

- `docs/OPERATOR_LIFECYCLE.md` is the operator-job authority.
- `docs/UX_WORKFLOW_CONTRACT.md` is the workflow Definition of Done.
- `BOARD.md` remains the gate and approval authority.
- Domain, security, capability, and database documents remain authoritative for their
  respective boundaries.
- A pass is not complete until current documents describe the resulting task loop and
  known deferred seams.
