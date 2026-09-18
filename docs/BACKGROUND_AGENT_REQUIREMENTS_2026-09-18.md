# Background agent requirements

Status: owner-directed scope recorded 2026-09-18. Requirements only. See
`BACKGROUND_AGENT_ARCHITECTURE_2026-09-18.md` for reconciliation.

| ID | Requirement |
| --- | --- |
| BA-01 | Only reviewed predefined agent definitions may run; no unrestricted builder, arbitrary SQL, generic RPC, or generic mutation. |
| BA-02 | Every run pins organization, definition/version, policy revision, trigger, source revision/fingerprint, accountable runtime principal, and rule version. |
| BA-03 | Organization enablement is revisioned, disabled by default, scope-bounded, pausable, and revocable. |
| BA-04 | Event, schedule, and manual triggers are typed, bounded, idempotent, and causally traceable. |
| BA-05 | Runs, attempts, leases, checkpoints, retries, timeouts, cancellation, and dead-letter state are durable and auditable. |
| BA-06 | Repeated or concurrent delivery produces one effective run, finding, proposal, and business effect. |
| BA-07 | Read, AI use, propose, approve, execute per action type, and external communication permissions remain separate. |
| BA-08 | Unattended execution uses a dedicated runtime principal and explicit agent grant, never an expired browser session, forged human identity, or blanket administrative authority. |
| BA-09 | Current organization, policy, grant, scope, source revision, target revision, budget, and domain invariants are reread before proposal publication or action. |
| BA-10 | Findings retain exact evidence, deterministic calculations, unknowns, source links, agent/rule version, and resolution history. |
| BA-11 | Imported documents and model output are untrusted data and cannot alter authority, organization, provider, funding, destination, or action. |
| BA-12 | Completed effects are corrected through domain reversal, supersession, or compensation, never deletion or audit rewriting. |
| BA-13 | Supplier reconciliation independently compares ordered, physically received, and billed facts using approved unit/conversion/currency rules and timing state. |
| BA-14 | Supplier findings cannot change receipt, inventory, invoice approval, actual credit, payment, or supplier communication in the first slice. |
| BA-15 | Proposed recovery, submitted claim, supplier acknowledgement, and actual credit remain distinct states and records. |
| BA-16 | Card hygiene preserves product/release, checklist/variant, subject, and owned inventory identity boundaries. |
| BA-17 | Original card text/evidence and human-reviewed values are preserved; candidates and unresolved identities remain non-authoritative. |
| BA-18 | Organization-private enrichment cannot mutate platform catalog data or another organization. |
| BA-19 | Optional AI uses the shared provider/funding/job/usage contracts; deterministic/manual operation remains complete without AI. |
| BA-20 | Provider/funding selection never changes silently, and spending/connection revocation stops new provider attempts without erasing findings. |
| BA-21 | Findings feed existing Home tasks and record workspaces through stable links rather than creating a separate task ledger. |
| BA-22 | UI and APIs disclose exactly what each agent may read, propose, execute, and communicate. |
| BA-23 | Pause/kill controls prevent queued work and proposal/action publication; in-flight cancellation is recorded separately from provider completion. |
| BA-24 | No agent run creates a financial, inventory, catalog, or external effect outside its explicitly granted domain writer and action type. |
