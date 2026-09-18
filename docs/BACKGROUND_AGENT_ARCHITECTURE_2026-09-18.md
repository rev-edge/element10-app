# Background agent architecture

Date: 2026-09-18

Status: investigation, requirements reconciliation, and implementation planning
only. No migration, provider activation, credential connection, scheduler,
worker, deployment, or production change is authorized. This document does not
accept a background-agent runtime as implemented.

Evidence baseline: canonical `foundation-a6` source at
`7ad4bc8cd1046fb3bba33b0af7f99043d0695bee`. Repository source, tests, and
recorded staging evidence were inspected. No database environment was contacted.

## 1. Established product direction

Element 10 will initially offer two predefined organization-controlled agents:

1. supplier invoice reconciliation;
2. card inventory data hygiene and enrichment.

Both begin in observe-and-propose mode. There is no unrestricted agent builder,
arbitrary SQL, generic mutation tool, implicit approval, external communication,
or automatic financial/inventory effect. Selective automation is a later,
action-specific policy choice and not an implication of enabling an agent.

The background layer extends the shared import/export and AI architecture. It
does not create a second permission system, proposal system, task system,
commercial ledger, catalog, or inventory ledger.

## 2. Current-state and gap matrix

| Capability | State | Exact evidence | Agent-layer consequence |
| --- | --- | --- | --- |
| Explicit organization read context | Implemented and staging-verified | X8a migrations `20260912000380` and `20260912000381`; `e10_query_contexts`; `e10_org_typed_query`; `tests/ta_x8a_query_context_test.sql`, `tests/ta_x8a_typed_dispatcher_test.sql`, and concurrency test; staging acceptance at `e5a387c` | Reuse the closed typed-reader pattern. Current contexts are user/`auth.uid()` bound and expire within 24 hours, so they are not unattended-agent credentials. |
| Reviewable action proposals | Implemented and staging-verified, narrowly scoped | X8b migrations `20260912000390` through `20260912000397`; action drafts/revisions/decisions/commands; staging acceptance at `c989ff7` | Reuse immutable revisions, preview, stale rejection, and delegated commit. Only `purchase_order.create` and `customer_transaction.create_draft` exist. Agent findings are not action drafts, and no invoice/card operation is currently supported. |
| External work leasing | Implemented and staging-verified but dormant | X8c migration `20260912035932`; outbox consumers, claim commands, acknowledgements; claim/ack tests; staging acceptance at `87e3e67` | Reuse bounded leases, generation tokens, retry/dead outcomes, and service-only ACLs. No consumer is seeded, no scheduler/worker exists, and acknowledgement is not delivery proof. |
| Scheduler and worker service | Missing | X8 contract explicitly excludes scheduler and autonomous agent; X8c tests assert no cron or dispatch function consumes the outbox | Must be designed and deployed separately. A database queue is not a running agent. |
| Agent definition/version and org enablement | Missing | No agent-definition, org-agent-policy, trigger, run, finding, or agent-grant relation exists | Add predefined, versioned definitions and revisioned organization policies, disabled by default. |
| Durable runs, attempts, checkpoints, cancellation | Missing | X8 has query contexts, action drafts, and outbox leases, not agent runs | Add run and attempt lifecycle with cancellation, heartbeat/checkpoint, timeout, and source snapshot. |
| Findings and evidence | Missing | Financial reconciliation cases/decisions and identity candidates are domain-specific; there is no reusable agent finding/proposal relation | Add durable findings linked to exact source revisions and optional domain proposals. Do not flatten domain decisions into generic JSON. |
| Unattended execution authority | Missing | Existing authenticated writers derive a current human actor from `auth.uid()`; X8c is `service_role` only but authorizes consumers, not domain action | Never reuse a browser session or forge a human JWT. Add an agent runtime principal and narrow, revocable organization grant before any unattended action. |
| Organization AI configuration and usage accounting | Contracted only | `SHARED_IMPORT_EXPORT_AI_ARCHITECTURE_2026-09-17.md` sections 4 through 6 | Provider connection, policy, jobs/attempts, cost reconciliation, and billable events must exist before provider-backed unattended runs. Deterministic/manual runs do not require AI. |
| PO/invoice/receipt independent facts | Implemented locally; older purchasing/receipt slices have staging evidence | `e10_purchase_orders*`, `e10_supplier_invoices*`, `e10_stock_receipts*`, allocation/event tables, immutable revisions, receipt writers and reversals; X3/X4 tests | Strong foundation for deterministic three-way comparison. Current-head vendor-bill additions are not claimed deployed by this pass. |
| Vendor-document capture and extraction seam | Implemented and locally tested; no live provider claimed | migrations `20260914170127` and `20260914170435`; immutable documents, attachments, attempts, reviews, inbound messages; vendor-document tests | Can supply untrusted evidence to reconciliation. It is not a live OCR/vendor connector or an agent runtime. |
| Supplier invoice and credit lifecycle | Partial | Invoice and supplier-credit review/approve/void writers, revisions, allocation events, cost evidence, register/detail readers | Actual credit documents exist. Proposed credit request, submitted claim, supplier acknowledgement, and expected-credit lifecycle are absent. Payment/balance/aging remain unavailable. |
| Commercial arithmetic | Conflicting dependency, fail-closed | Vendor-bill contract defers charge components, tax inclusivity, discount signs, freight treatment, and rounding tolerance | Agent may calculate only approved quantity/unit/currency comparisons. It cannot assert a payable discrepancy that depends on undecided arithmetic. |
| Canonical cards and subjects | Implemented/partial | X1 catalog releases/variants, `e10_catalog_variant_subjects`, `e10_catalog_identity_mappings`; X1 tests prove multi-subject variants; X7d readers expose subject cohorts | Reuse stable catalog identities and subject links. Generic subject vocabulary, reviewed alias history, and org-private unresolved mentions remain partial/planned. |
| Inventory evidence and lifecycle readers | Implemented and staging-verified | X7e governed evidence/lifecycle/valuation migrations and tests | Suitable read foundation for card hygiene, but no hygiene finding engine or correction writer exists. |
| Organization-private catalog enrichment | Contracted only | `SUBJECT_IDENTITY_RECONCILIATION_2026-09-16.md` and checklist designs | Required before tenant-private suggestions can be confirmed without mutating platform catalog data. |
| Home tasks/workspace links | Missing for agents | No stable agent-finding-to-Home-task adapter exists | Findings must feed the existing task/workspace model through stable links, not create a disconnected task product. |

Historical staging evidence is bounded to the commits named in the evidence
packets. It is not current-head deployment evidence. Production is not inspected
or changed by this pass.

## 3. Minimum reusable runtime contracts

### 3.1 Predefined definition and organization policy

`agent_definition_versions` is platform-governed and immutable. It contains a
stable definition key, version, supported trigger classes, typed input contract,
typed finding kinds, allowed read operations, allowed proposal types, optional
executable action types, calculation/rule version, and data-disclosure profile.
Only reviewed predefined definitions are registered.

`organization_agent_policies` is organization-owned and revisioned. It pins one
definition version and records enabled/paused status, record scope, event and
schedule settings, connection route, budget/usage limits, finding severity
thresholds, proposal permissions, optional automation grants, and the approving
actor. New policies are disabled. A policy change never rewrites an existing
run.

### 3.2 Trigger and duplicate suppression

Triggers are typed envelopes from three sources:

- domain events tied to an exact source record and revision;
- bounded schedules with an explicit coverage window and watermark;
- manual requests by an authenticated organization user.

An effective trigger is unique by organization, definition version, policy
revision, trigger class, source identity/revision or schedule window, and rule
version. Repeated delivery converges on the same effective run. A material
source revision creates a new run and makes dependent proposals stale.

The runtime records causal ancestry. Events produced by an agent action are not
ignored globally, but an identical causal effect cannot recursively create the
same finding/run. Bounded chain depth and repeated-fingerprint detection stop
self-trigger loops.

### 3.3 Runs, attempts, checkpoints, and cancellation

`agent_runs` records organization, definition/version, policy revision, trigger,
source snapshot/fingerprint, accountable runtime principal, initiating user when
manual, status, cancellation request, checkpoint, coverage, and timestamps.

`agent_run_attempts` records leases, worker identity, heartbeat, provider/AI job
when used, retry reason, start/end, outcome, and error category. Only one live
attempt generation owns a run. Attempts are bounded by timeout, backoff,
concurrency, and maximum-attempt policy. Exhaustion enters dead-letter review.

Cancellation prevents a queued attempt from starting. In-flight cancellation is
best effort, records request and effective time separately, and prevents later
proposal or action publication unless the attempt reacquires current authority.

### 3.4 Findings, evidence, proposals, and resolution

An `agent_finding` is durable, organization-scoped, and unique by definition,
finding kind, affected business grain, source revision fingerprint, and rule
version. It records severity, deterministic facts, unknowns, calculation basis,
status, and stable record/workspace links.

Finding evidence is append-only and references authoritative records, revisions,
source documents, raw text, normalized values, and calculation inputs. Imported
or model-generated text is data, never instruction.

A finding may create zero or more typed proposed actions. Proposals retain the
finding/evidence snapshot and target revision. They use an existing domain
proposal/writer where one exists. A finding is not itself approval, a supplier
claim, a credit, an inventory movement, or a canonical catalog decision.

Resolution records `accepted`, `rejected`, `deferred`, `superseded`,
`no_action_required`, or a domain-specific linked outcome with actor, reason,
and timestamp. Re-evaluation updates effective status by appending evidence and
resolution history, not by erasing the prior conclusion.

### 3.5 Authority model

The unattended runtime uses a dedicated service principal, not a human session.
Every read or proposal call supplies organization, agent definition/version,
policy revision, run, and attempt identities. Server-side code verifies:

1. organization active;
2. definition/version registered and allowed;
3. organization policy enabled and not paused;
4. current trigger, scope, connection, budget, and data-disclosure limits;
5. action class present in the grant;
6. source and target revisions still current;
7. current domain invariants and idempotency.

Permissions remain separate for reading, using AI, proposing, human approving,
executing each action class, and communicating externally. Observe-and-propose
grants contain no execute or communicate permission.

Later automation requires an explicit, revisioned `organization_agent_grant`
for one action type, bounded record scope, amount/quantity/tolerance limits,
expiry, and revocation. The ordinary guarded domain writer remains authoritative.
It must expose a reviewed agent-specific delegate or command path rather than
trust `service_role` or impersonate the approving user. Authority and source
state are reread immediately before the effect.

Revocation prevents queued work and proposal/action publication immediately.
Completed actions are never deleted. Corrections use the existing reversal,
supersession, or compensating-action contract of the domain.

### 3.6 AI execution and commercial accounting

AI is optional. Deterministic comparison, finding review, and manual resolution
remain available with AI disabled or over budget. When AI is used, each attempt
links to the provider-independent AI job/attempt contract and pins provider,
connection, funding source, policy, disclosed fields, and usage/billing records.

Element 10-managed and organization-owned API connections can support unattended
server execution only after secure server credentials, data policy, limits, and
commercial terms are approved. External ChatGPT/Claude connector sessions are
interactive tool clients, not a dependable background scheduler. Their consumer
subscriptions must not be treated as server credentials or funding for Element
10 API calls.

Current official provider facts support the boundary:

- OpenAI exposes project service accounts/API keys and separate API billing:
  <https://developers.openai.com/api/reference/cli/resources/admin/subresources/organization/subresources/projects/subresources/service_accounts/subresources/api_keys/methods/create>
  and
  <https://help.openai.com/en/articles/9039756-managing-billing-for-chatgpt-and-the-api-platform>.
- Anthropic states that shared production automation should use Claude Platform
  with an API key, and Claude paid subscriptions and API/Console access remain
  separate products:
  <https://support.claude.com/en/articles/15036540-use-the-claude-agent-sdk-with-your-claude-plan>
  and
  <https://support.claude.com/en/articles/9876003-i-have-a-paid-claude-subscription-pro-max-team-or-enterprise-plans-why-do-i-have-to-pay-separately-to-use-the-claude-api-and-console>.

Provider features and terms require launch-time revalidation. No provider is
selected or activated here.

## 4. Agent A: supplier invoice reconciliation

### 4.1 Facts and calculation

The agent compares three independent, revision-pinned fact sets:

- ordered: PO line configuration, ordered quantity, unit/currency, cancellation
  and expected-delivery state;
- received: receipt allocation, accepted/quarantined/damaged/disposition and
  reversal/correction history;
- billed: invoice line quantity/amount/currency, invoice status, allocation and
  approved credit evidence.

All quantity comparison first converts through approved configuration packaging
and `quantity_increment` contracts. Missing or conflicting conversion blocks a
conclusion. Currency must agree. No silent conversion is allowed. Amount/tax/
freight/discount conclusions remain blocked where the commercial arithmetic
policy is undecided.

Timing is part of the conclusion. A partial receipt before a still-open expected
delivery is `awaiting_delivery`, not an unsupported supplier shortage. Cancelled
or void documents, released allocations, receipt reversals, and already approved
supplier credits are included in the effective facts.

### 4.2 Finding and proposal

One effective finding exists per organization, supplier, comparison grain,
discrepancy kind, source-revision set, and calculation-rule version. It contains
the three fact summaries, conversion/currency basis, tolerance, unknowns, links,
and recommended next step.

First-slice recommendations are limited to:

- no action or await later delivery;
- request human review of allocation/conversion;
- prepare a proposed supplier recovery/credit request;
- note that an actual credit already resolves all or part of the discrepancy.

The agent never changes receipt quantity, stock, invoice approval, cost evidence,
credit, payment, or external communication. Existing `e10_supplier_credits` are
actual credit documents with review/approval/void and allocation history. They
must not be created merely because the agent calculated an expectation.

The repository lacks the pre-credit lifecycle needed for a recovery proposal:
`proposed`, `approved_for_submission`, `submitted`, `supplier_acknowledged`,
`accepted`, `rejected`, `withdrawn`, and links to any eventual actual supplier
credit. That is an additive domain dependency. No accounting balance or payment
state is inferred from it.

### 4.3 Triggers

Material PO line/revision, receipt/allocation/reversal/disposition, invoice line/
revision/allocation, credit/allocation, packaging conversion, and reviewed vendor
document changes enqueue a typed trigger. Scheduled backfill uses a bounded
window/watermark. Manual runs name scope explicitly.

## 5. Agent B: card inventory hygiene and enrichment

### 5.1 Assessment boundary

The agent reads organization-owned inventory/raw-lot/unique-item evidence and
platform catalog/checklist/subject data through separate authorized readers. It
may identify:

- missing or inconsistent catalog attributes;
- candidate release, checklist entry, and exact variant matches;
- candidate zero/one/many subject links and unresolved names;
- duplicate candidates;
- controlled-vocabulary/formatting inconsistencies;
- missing provenance or unresolved identity.

Product/release, checklist/variant, subject, and owned item remain distinct.
Candidates do not become confirmed links. Organization-private evidence cannot
publish or overwrite platform catalog data.

### 5.2 Evidence and protection

Every finding preserves original text, source identity, extraction/mapping
revision, current human-reviewed values, candidate evidence, confidence class,
ambiguities, affected records, and downstream impact. Similar names alone never
merge subjects or variants. Multiple subjects and unresolved text are valid.

Any merge, canonical identity replacement, or platform publication requires the
separate catalog proposal/review authority. The first slice never changes stock,
reservations, location, acquisition cost, asking price, grade, certificate, or
canonical catalog facts.

### 5.3 Reversible future formatting operations

Potential later automation is restricted to organization-private derived
normalization fields while preserving raw text: Unicode NFC normalization,
outer-whitespace trim, repeated-whitespace collapse, and mapping a value to an
already reviewed controlled-vocabulary synonym. It may not change identity,
numbers, serials, grades, certificates, prices, or human-reviewed canonical
display values. Exact operations and fields require owner approval before an
execute grant exists.

## 6. Operator-facing contract

The future management/review surface must show:

- predefined agent name and version;
- exact read, propose, execute, and communicate permissions;
- enabled/paused state, scope, trigger, connection, budget, and limits;
- current and historical runs, attempts, findings, evidence, costs, and errors;
- proposal preview with source and target revisions;
- approve, reject, defer, supersede, or open linked workspace actions;
- kill switch and impact on queued/in-flight work.

Findings project into existing Home tasks and record workspaces using stable
finding/record links. Home is a view and triage surface, not a second finding or
task ledger.

## 7. Staged implementation plan

1. **BA-0 decisions and threat model**: approve capability names, runtime
   principal, retention, schedule limits, provider disclosure, action grant
   shape, Home-task projection, and supplier recovery lifecycle.
2. **BA-1 observe-only runtime foundation**: predefined definitions, org policy,
   triggers, runs/attempts/checkpoints, findings/evidence/resolution, cancellation,
   leases, duplicate suppression, loop prevention, pause/kill, and audit. No AI
   or executable proposal is required.
3. **BA-2 first vertical slice, supplier reconciliation**: deterministic bounded
   reads, event/schedule/manual triggers, ordered/received/billed calculation,
   one durable finding, existing-credit suppression, and Home/workspace links.
   It proposes review only until the recovery-request lifecycle is approved.
4. **BA-3 supplier recovery proposal**: add the reviewed pre-credit request
   lifecycle. Still no external send, invoice approval, credit posting, stock
   mutation, or payment.
5. **BA-4 card hygiene observe/propose**: add private evidence/candidates,
   confirmed-versus-suggested separation, human-reviewed-value protection, and
   platform-catalog boundary tests.
6. **BA-5 optional AI execution**: connect jobs/attempts, minimization, budgets,
   usage and cost after shared AI architecture decisions. Manual/deterministic
   behavior remains complete.
7. **BA-6 selective automation**: only individually approved reversible action
   types with explicit grants, final authority/source rereads, compensation,
   and independent acceptance. External communication is a separate later gate.

Each stage stops for local replay, focused hostile/concurrency tests, exact-head
CI, guarded staging apply/evidence, security/advisor review, and independent
verdict. Production is a separate gate.

## 8. Verification and rollback approach

BA-1 and BA-2 are additive and disabled by default. Verification must prove
tenant isolation, no arbitrary relation/function access, one effective run and
finding under repeated/concurrent delivery, bounded scheduling, stale rejection,
post-wait revocation, cancellation, dead-letter behavior, loop prevention,
prompt-injection resistance, and zero financial/inventory/catalog effects.

Operational rollback is pause/disable policy, revoke worker/connection, stop
claiming new work, let or cancel in-flight leases, and retain immutable audit and
findings. It must not delete accepted history. Code/schema rollback uses a
reviewed forward corrective migration if data exists. A provider failure cannot
erase draft/findings or force a different funding route.

## 9. Design-agent handoff

The design agent may prototype now:

- enable/pause configuration for two predefined agents;
- clear read/propose/execute/communicate permission summaries;
- run history and cost placeholders labeled unavailable where not implemented;
- supplier discrepancy and card-hygiene finding/evidence review;
- approve/reject/defer controls that remain simulated;
- stable links to Home and relevant record workspaces.

The prototype must explicitly simulate scheduling, provider calls, costs,
background completion, recovery requests, approvals, external communication,
catalog correction, and all execution. It must not claim a running worker,
deployed provider, actual supplier contact, automatic correction, or production
agent.
