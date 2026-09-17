# Shared import, export, and AI architecture

Date: 2026-09-17

Status: investigation, requirements reconciliation, and implementation planning
only. No migration, service activation, credential connection, paid API call,
deployment, or production change is authorized. This document does not accept
the proposed architecture as implemented.

Evidence baseline: canonical `foundation-a6` source at
`c585da739bc14d4f6ceaac0d550d0f4f92e6e5e4`. Current local source was inspected.
No local database, staging, or production environment was contacted in this
pass. Historical staging evidence remains bounded to its recorded runtime head.

## 1. Executive contract

Element 10 supports four independent execution choices over one governed
application workflow:

1. Element 10-managed AI, funded and commercially packaged by Element 10.
2. Organization-owned provider connections, administered once for the
   organization and usable by authorized employees without employee API keys.
3. External assistant connectors, where ChatGPT, Claude, or another supported
   assistant calls Element 10 tools under the user's Element 10 authority.
4. Manual import and export, which remains complete without AI.

These choices do not create four business workflows. All produce or inspect the
same organization-scoped source, import draft, mapping revision, prepared rows,
approval, export specification, and ordinary application command records.

The following dimensions remain separate:

- product/module entitlement;
- user capability and data scope;
- Everyday or Advanced presentation;
- AI execution provider;
- funding source;
- approval and publication authority.

Changing presentation cannot change authority, provider routing, data scope, or
billing. AI proposes. Deterministic application rules validate. Existing
ordinary commands commit. No model, connector, or export generator gains an
independent publication, inventory, receiving, financial-posting, or external-
transmission path.

## 2. Current-status matrix

| Area | Local implementation | Deployed evidence | Prototype only | Documented or newly clarified | Disposition |
| --- | --- | --- | --- | --- | --- |
| Checklist AI mapper | `supabase/functions/normalize-checklist/index.ts`, commit `2aeee9a`, sends at most 30 rows and 24,000 characters to hard-coded Anthropic model `claude-haiku-4-5`; returns mapping plus provider usage. No focused test found. | No current deployment, secret, invocation, cost, or environment proof was found. | `index.html` invokes the function and falls back to Direct import. | Owner now requires managed AI, organization-owned AI, connectors, and manual operation. | **Conflicting legacy seam**. Preserve as a prototype reference, replace with provider-independent job/configuration contracts before production use. |
| Checklist manual import | Prototype reads CSV/XLS/XLSX, picks one sheet, maps headers, stages rows in browser, and allows review. | No deployed acceptance at current head. | `index.html` browser workflow. | `CHECKLIST_INGESTION_DESIGN_2026-09-16.md` defines the durable lifecycle. | **Prototype only**. It lacks immutable source, draft revision, save/resume, full provenance, stale review, and governed commit. |
| Checklist commit | `clApproveReview` ultimately inserts legacy `e10_checklists` and `e10_cards` directly after client-side resolution. | Historical application behavior is not current production acceptance. | The prototype labels the action “Approve & commit.” | Active checklist design separates organization approval from platform publication. | **Conflicting**. Direct legacy writes must not become the new contract. |
| Generic typed intake | X5 tables and writers implement immutable raw payload, typed rows, tenant scope, resolver decisions, idempotent stage, revision-bound commit, correction lineage, and dormant outbox. Tests cover replay, corrected imports, concurrency, and cross-org denial. Commits begin `fe02c49`, `aecbf17`. | Historical staging packet records X5/R3 coverage at runtime `481ea1a`, not current-head verification. | None. | Newly clarified as a reusable pattern, not a checklist-ready schema. | **Implemented pattern, domain-limited**. Reuse invariants, not the current fixed observation kinds. |
| Assistant read interface | X8a provides actor/org-bound revocable query contexts and a closed typed query dispatcher. Tests include `ta_x8a_query_context_test.sql`, `ta_x8a_typed_dispatcher_test.sql`, and concurrency. | Historical staging evidence only. | No assistant UI or remote connector. | External assistants must use the same typed reads. | **Backend pattern implemented**. Connector authentication, tool manifests, and checklist/export operations are missing. |
| Assistant mutation interface | X8b has immutable action-draft revisions, provenance, missing fields, preview, revision-bound approval, stale rejection, delegated commit, and replay protection for only PO creation and customer transaction draft creation. | Historical staging evidence only. | No general assistant product. | Checklist mapping/correction must follow this pattern. | **Implemented pattern, operation allowlist too narrow**. Extend additively, never expose arbitrary mutation. |
| External dispatch | X8c implements a dormant service-only claim/ack protocol. No consumers are enabled. Tests prove leases, replay, and concurrency. | Historical staging evidence only; no delivery proof. | None. | File generation is distinct from sending or publication. | **Dormant protocol only**. It is not an active integration or proof of external effect. |
| Export authorization | `act.reporting_export` exists. X8 query context accepts purpose `export`; bounded domain readers exist. | No shared export-job deployment proof. | Browser helpers generate selected local CSV/XLSX artifacts. | Full authorized cohort and selected-ID versus all-filtered scope are required. | **Partial**. No shared export specification, snapshot, artifact, retention, expiry, or reproducibility contract. |
| AI configuration | One server environment key, `ANTHROPIC_API_KEY`, is referenced by the checklist function. | No credential/environment proof. | One global provider route. | Organization-managed and Element 10-managed modes are owner-confirmed. | **Missing**. No org connection, policy, model allowlist, limit, rotation, revocation, routing, or secret reference. |
| AI usage and billing | Mapper returns raw provider usage to its caller. | No durable usage or cost evidence. | None. | Managed allowances, credits, metering, organization funding, and connector attribution are newly clarified. | **Missing**. No job, attempt, provider usage, cost reconciliation, pricing policy, allowance, billable event, or spend limit. |
| Entitlements and capabilities | Organization entitlements, `e10.has_module_access`, capability registry, role grants, and final-lock rereads exist. | Historical staging verification exists for the tenant spine and later corrective series. | Presentation gates also exist in prototype code. | AI execution/funding must not be inferred from presentation. | **Reusable foundation**. New AI administration/use/export/import capabilities and module ownership need owner approval. |
| Checklist-led product creation | Product/configuration/catalog foundations exist. The complete versioned organization checklist import and applicability lifecycle remains unimplemented. | No environment claim for the proposed lifecycle. | Prototype imports cards/checklists. | Three September 16 reconciliation documents define product, checklist, subject, and applicability contracts. | **First slice planned, not implemented**. |

No production capability is inferred from a table name, browser prototype, or
historical test. The current-status matrix is intentionally conservative.

## 3. Provider facts and limitations

### OpenAI

Official OpenAI documentation says ChatGPT and API Platform use separate billing
systems. A ChatGPT subscription does not fund API usage initiated by Element 10.
The Responses API supports MCP tools and custom MCP servers. OpenAI exposes
organization usage and cost endpoints with project, user, API-key, and model
dimensions, but provider usage and provider cost still need independent
reconciliation to Element 10 billable usage.

Sources:

- <https://help.openai.com/en/articles/9039756-managing-your-work-in-the-api-platform-with-projects>
- <https://developers.openai.com/api/reference/resources/admin/subresources/organization/subresources/usage>
- <https://developers.openai.com/api/reference/cli/resources/responses/methods/create>
- <https://developers.openai.com/api/docs/guides/your-data>

### Anthropic and Claude

Official Anthropic documentation says Claude paid plans and Claude Console/API
are separate products. A paid Claude subscription does not fund API calls made
by Element 10. Anthropic documents prepaid or invoiced API billing, and notes
that failed requests are generally not charged while a client timeout may still
be charged if the request was on track to succeed. MCP is supported across
Claude products, but that support does not authorize an Element 10 connector or
define the user's Element 10 permissions.

Sources:

- <https://support.claude.com/en/articles/9876003-i-have-a-paid-claude-subscription-pro-max-team-or-enterprise-plans-why-do-i-have-to-pay-separately-to-use-the-claude-api-and-console>
- <https://support.claude.com/en/articles/8977456-how-do-i-pay-for-my-claude-api-usage>
- <https://modelcontextprotocol.io/docs/2026-07-28/getting-started/intro>

Provider availability, models, rate limits, data controls, usage fields, and
commercial terms can change. Element 10 must keep provider capability metadata
versioned and must not encode a model name as a permanent product entitlement.

## 4. Organization AI configuration model

The proposed additive model has six layers.

### 4.1 Provider catalog

`ai_provider_definitions` is platform-governed metadata, not a credential table.
It records provider key, supported execution modes, capability classes, current
status, documented usage dimensions, data-control profile version, and model
catalog refresh metadata. Provider-specific options live in validated typed
configuration, not arbitrary executable JSON.

### 4.2 Organization connection

`organization_ai_connections` is organization-owned and records provider,
display label, status, validation status/time, credential reference, credential
version, created/revoked actor and time, and provider account/workspace metadata
that is safe to display. It never stores a plaintext secret in a client-readable
table. Secret material belongs in a server-side secret manager. The database
stores only an opaque secret reference and version.

Connection ownership is the organization, not an employee. Employees never
receive the provider secret. Administration and use are separate capabilities.
Revocation prevents new attempts immediately and prevents queued attempts from
starting. In-flight provider cancellation is best effort and the attempt remains
auditable.

### 4.3 Organization AI policy

`organization_ai_policies` is revisioned and selects, by task class:

- permitted execution modes: managed, organization connection, or no AI;
- allowed provider connections and model families;
- explicit default route;
- allowed data classes and minimization profile;
- per-job input/output limits;
- organization and user concurrency limits;
- daily/monthly usage or spend controls;
- fallback policy, defaulting to none;
- retention and logging policy references.

Changing a policy does not rewrite an existing job. Every job pins the policy
revision used for authorization and routing.

### 4.4 Capabilities and entitlement

Proposed capability families, names pending owner approval:

- administer AI connections and policies;
- use AI assistance for a permitted task;
- view organization AI usage;
- view provider cost and customer-billable usage;
- prepare imports and mapping revisions;
- approve domain imports;
- configure and generate exports;
- administer connector access.

Entitlement determines whether the organization has the product feature.
Capability determines what the actor may do. The task policy determines which
provider/mode may run. Presentation determines only how controls are shown.

### 4.5 Jobs and attempts

`ai_jobs` records organization, actor, task class, target draft/revision,
selected execution mode, funding source, provider connection or managed route,
model policy, data-minimization profile, input fingerprint, idempotency key,
status, and timestamps. Mode and funding source are immutable after creation.

`ai_job_attempts` records each provider request, retry reason, provider request
identity, selected model, start/completion, outcome, partial output reference,
and provider usage status. Model output is an untrusted proposal linked to the
import or action-draft revision. It cannot commit business records.

No silent fallback is allowed. A managed attempt cannot replace a failed
organization-funded attempt unless the organization policy permits fallback and
the actor explicitly confirms the chargeable route. That consent creates a new
attempt with its own mode and funding source. Draft work already created remains
available if AI fails, is revoked, or reaches a limit.

### 4.6 Data minimization

Task-specific input builders select only necessary fields. Checklist mapping may
send headers and representative source cells, but should omit customer/contact,
cost, and unrelated organization data. Exports never send restricted fields to
AI merely because the actor may export them. Provider-bound payload fingerprints
and field-class manifests are auditable without storing secrets.

## 5. Execution and funding decision table

| Workflow | Inference location | Credential/funding | Required Element 10 record | Failure and fallback |
| --- | --- | --- | --- | --- |
| Native UI, Element 10-managed | Element 10 calls approved provider API | Element 10 account; customer treatment determined by pinned pricing policy | AI job and attempt with `managed` mode and Element 10 funding; allowance/billable event evaluation | Preserve draft; retry under policy; never switch to org-funded silently. |
| Native UI, organization-owned API | Element 10 server calls provider using org connection | Organization provider account | AI job/attempt with connection ID/version and `organization_provider` funding | Fail closed if revoked/invalid/limited; preserve draft; managed fallback requires prior policy plus explicit consent. |
| External assistant connector | Assistant performs its own inference and calls Element 10 MCP/tools | Assistant host/account funds its inference | Connector session/tool audit and ordinary Element 10 query/draft records | Tool failure does not trigger Element 10 AI. Any extra Element 10 inference is a separately disclosed and consented AI job. |
| Manual import/export | No inference | None | Import source/draft or export specification/artifact records | Fully operable without provider configuration. |

Consumer ChatGPT or Claude subscriptions may fund inference inside their own
assistant products according to those products' terms. They do not fund API
requests made by Element 10.

## 6. Usage and commercial accounting

Keep four ledgers distinct:

1. Provider-reported usage and provider cost.
2. Element 10 request-time usage estimates.
3. Reconciled provider cost, which may arrive later.
4. Customer-billable usage under an Element 10 pricing-policy revision.

Proposed records:

- immutable `ai_usage_observations` per provider request and report revision;
- `ai_provider_cost_reconciliations` linking estimates to provider reports;
- versioned `ai_pricing_policies` with effective intervals and unit definitions;
- organization allowance/credit grants and consumption events;
- immutable `ai_billable_events`, unique by organization and logical job effect;
- adjustments/corrections that supersede or offset, never rewrite, earlier
  observations or billable events.

Retry rules:

- an exact replay returns the same job or attempt result;
- transport retry may produce another provider attempt but not another logical
  customer charge unless the pricing policy explicitly prices successful
  attempts rather than jobs;
- provider-reported charge after timeout remains provider cost even when no
  usable output exists;
- cancellation records requested and effective times separately;
- partial output is not billable as completed output unless the pinned policy
  defines that result and the UI disclosed it;
- delayed provider reports append reconciliation evidence;
- organization-funded API usage is attributed but is not Element 10-funded
  consumption. Any Element 10 feature fee is a separate explicit policy.

Organization reports show job, task, initiating actor, execution mode, funding
source, provider/model class, estimates, reported usage, reconciled cost where
authorized, billable units, allowances/credits, and corrections. Provider cost
and customer price need separate permissions.

## 7. External connector contract

The first MCP/tool surface is deliberately narrow:

- search authorized product, release, configuration, checklist, source, and
  evidence records through X8-style typed queries;
- start or resume an organization import draft;
- propose mapping, transformation, match, exclusion, or correction revisions;
- preview full-dataset validation summaries and unresolved issues;
- create an export specification and request a generated file;
- return a native review link containing an opaque draft/context reference.

Every connector session authenticates an Element 10 user, selects one explicit
organization, creates a revocable assistant query context, and rechecks current
membership, entitlement, capabilities, data scope, revision, and idempotency on
every call. Assistant output and uploaded content are untrusted data.

Connectors may create or amend drafts when authorized. They do not approve
their own drafts by implication. Checklist organization approval, platform
publication, receipt posting, inventory movement, invoice approval, customer
transaction posting, external transmission, and marketplace publication remain
separate ordinary commands with their existing authority.

Tool schemas are closed, typed, bounded, versioned, and free of arbitrary SQL,
table names, RPC names, projection strings, or generic mutation payloads.

## 8. Shared import contract

All domains share these stages:

`source -> parse revision -> mapping revision -> prepared-result revision ->
review decisions -> revision-bound approval -> ordinary domain commit`

Shared records retain immutable file/object identity, digest, source metadata,
sheet/page/row identity, raw values, parser version, mapping/template version,
AI proposal provenance when used, deterministic validation, duplicate and match
candidates, row disposition, review actor/time, dependency fingerprint, and
commit receipts.

Every source column receives one explicit disposition: mapped, organization
custom field, or excluded with reason. Identical bytes and identical settings
replay the same draft. Corrected input creates a new source/parse revision linked
to its predecessor. Mapping changes invalidate only dependent reviews. Approval
names an exact prepared revision. Stale approval cannot authorize changed rows.

### Domain matrix

| Domain | Initial formats | Matching keys | Review and commit effect | Current status |
| --- | --- | --- | --- | --- |
| Products, releases, configurations, packaging | CSV/XLSX first; reviewed supported documents later | Organization product/config IDs, canonical release external IDs, publisher/year/name context, SKU/barcode with scope | Create/amend organization product and immutable configuration/packaging drafts; platform catalog publication remains separate | Foundations exist; shared import missing |
| Checklists, cards, subjects, applicability | CSV/XLS/XLSX first; PDF and structured JSON through explicit parser profiles | Release-scoped card identity, exact variant facets, source IDs, optional reviewed subject identity; configuration-version applicability many-to-many | Approve immutable organization checklist version and applicability evidence; zero inventory/financial effects | First complete slice planned |
| Suppliers and offers | CSV/XLSX | Supplier code within organization, product/configuration, currency, effective date | Supplier/offer drafts only | Supplier foundation exists; import profile missing |
| Customers and permitted contact/preferences | CSV/XLSX with privacy profile | Channel/account scoped external IDs and reviewed customer IDs; never name/address auto-merge | Customer/contact/preference proposals under independent permissions | Customer identity exists; contacts/preferences/import missing |
| Inventory opening balances and intake | CSV/XLSX | Location, product/config/copy, source row, quantity/cost evidence | Delegate to authorized inventory/receipt writers; never direct ledger inserts | Typed intake pattern exists; opening-balance contract incomplete |
| Purchase orders and supplier invoices | CSV/XLSX plus supported vendor documents | Organization supplier/document/line IDs, config, currency, source identity | Create reviewed PO/invoice drafts; invoice import does not receive stock | Ordinary writers and bill intake exist; shared mapping layer missing |
| Marketplace sales/orders/fulfillment | Validated provider CSV first | Seller/account, import batch/row, order ID, line ID, refund/adjustment/shipment IDs | Reconcile evidence to customer activity/transaction/fulfillment; no automatic posting | Customer reconciliation exists; provider adapter/fulfillment missing |

Organization mapping templates are versioned and private by default. Approved
corrections may improve that organization's future template. They do not train a
shared model or alter another organization without a separate platform-governed,
privacy-reviewed process.

## 9. Checklist-led first implementation slice

The smallest complete slice is manual-first and provider-optional:

1. Upload CSV/XLS/XLSX and preserve immutable bytes/digest, workbook, sheet, and
   row identities.
2. Confirm or propose product/release details.
3. Prepare organization product, configuration, SKU/barcode/date, packaging,
   checklist entry, exact variant, typed attribute, optional subject mention,
   and applicability candidates.
4. Require explicit column dispositions and deterministic type/identity checks.
5. Save/resume immutable mapping and prepared-result revisions.
6. Review the complete prepared result, including duplicates, contradictions,
   missing evidence, and before/after effects.
7. Approve one organization checklist version. Platform publication remains a
   later separate action. No inventory or commercial records are created.
8. Generate a bounded export of the approved organization version using the
   same authorized cohort as its grid.

AI is an optional mapping/proposal step. The first launch needs manual mode and
one Element 10-managed provider route only if commercial and privacy decisions
are approved. Organization-funded routing and external connectors can follow
without changing the draft or approval model.

Packaging composition and card applicability remain separate. Applicability
uses the existing versioned many-to-many proposal. Missing evidence is unknown.
Potential pulls, guaranteed components, and exclusions are distinct. No odds are
inferred. Missing checklist/applicability does not block sealed ordering or
receiving.

## 10. Shared export contract

An export starts as an immutable, reviewable specification containing dataset,
authorization scope, selection mode, filters, columns, grouping, sorting,
units, currency/metric definitions, output format, destination template,
dataset revision, query fingerprint, and as-of boundary.

Selection mode is one of explicit selected IDs or all matching the reviewed
filter. “Current page” is never silently interpreted as the full dataset. The
preview reports total authorized rows, excluded restricted fields, estimated
size, and reproducibility metadata before generation.

Large exports run as bounded asynchronous jobs. Artifacts have organization and
actor scope, checksum, source specification/revision, expiry, retention class,
download audit, and deletion status. Reproduction either pins the original
dataset snapshot/revision or clearly reports that a new current-data artifact
was generated.

Generating/downloading a file is not external transmission. Emailing, supplier
delivery, marketplace upload, or publication requires a distinct destination
configuration, authority, preview, and auditable command. X8c may later carry
such effects, but a database acknowledgement is not provider delivery proof.

## 11. Staged implementation sequence

1. **IEA-0 decisions and threat model**: approve capability names/defaults,
   secret manager, privacy/data classes, retention, pricing-policy ownership,
   provider routes, and checklist approval/publication rules.
2. **IEA-1 shared source and draft core**: immutable sources/rows, parser and
   mapping revisions, column dispositions, prepared revisions, save/resume,
   dependency invalidation, replay, and correction lineage.
3. **IEA-2 checklist-led manual slice**: product/release/configuration/packaging,
   checklist/variant/optional subject/applicability preparation, full preview,
   organization approval, readiness reader, and zero-side-effect proof.
4. **IEA-3 export specification and artifact jobs**: full-cohort export, selected
   versus all-filtered scope, preview, checksum, expiry, retention, and audit.
5. **IEA-4 AI job and managed route**: provider-independent jobs/attempts,
   minimization, one approved managed provider adapter, usage observations,
   explicit failure, and no paid fallback.
6. **IEA-5 organization connections**: secure secret references, validation,
   rotation/revocation, policy/model allowlists, limits, organization funding,
   and usage attribution.
7. **IEA-6 connectors**: authenticated MCP/tool surface over X8 typed queries
   and draft commands, native review links, revocation, and approval parity.
8. **IEA-7 domain adapters and commercial accounting**: suppliers, customers,
   inventory, PO/invoice, marketplace profiles plus pricing policies,
   allowances, credits, cost reconciliation, and organization reporting.

Every stage requires reviewed migrations, local replay, focused adversarial and
concurrency tests, exact-head CI, explicit staging apply/evidence, and an
independent verdict. Production remains a separate gate.

## 12. Owner decisions

1. Capability names and default roles for AI administration/use, import
   preparation/approval, exports, usage/cost viewing, and connectors.
2. Secret manager and whether organization connections initially support API
   keys only, OAuth only, or provider-specific combinations.
3. First managed provider and permitted model families per task. Model names are
   operational configuration, not permanent entitlements.
4. Whether managed AI ships in the first slice and what allowance/spend control
   applies. No final prices are selected here.
5. Whether organization-funded usage may carry a separate Element 10 feature fee.
6. Fallback policy. Recommended default: no cross-funding fallback; require
   explicit consent per failed job if enabled.
7. Data classes permitted for each provider/task, retention expectations, and
   whether prompts/outputs may be retained for support or improvement.
8. Checklist completeness, maker-checker policy, organization overlay scope,
   and platform review/publication separation already identified in the active
   checklist documents.
9. Which import formats and domain adapters are committed for v1 after the
   checklist slice.
10. Export retention/expiry, maximum size, saved specification ownership, and
    which external destinations are ever permitted.
11. Connector launch targets and authentication model. ChatGPT and Claude
    support MCP concepts, but each product's distribution, review, workspace,
    and commercial terms require launch-time verification.

## 13. Constraints for the design agent

- Design one shared lifecycle, not separate “AI import” and “manual import”
  databases.
- Do not expose provider keys to clients, employees, prompts, exports, or logs.
- Do not use presentation mode as authorization or billing input.
- Do not let provider/model output select organization, capability, execution
  mode, funding source, approval, or destination.
- Do not silently switch funding source or provider.
- Do not call assistant-hosted inference an Element 10 API cost, or vice versa.
- Do not make AI required for save/resume, validation, review, commit, or export.
- Do not create a second catalog, customer ledger, inventory ledger, purchasing
  workflow, or action-draft system.
- Do not flatten packaging composition into card applicability.
- Do not infer unknown SKUs, pack counts, exclusivity, subject identity, or odds.
- Do not mutate prior approved versions while a correction draft is reviewed.
- Do not treat file generation as transmission or publication.
- Keep new client surfaces private by default with RLS, explicit grants, and
  bounded permission-aware functions. Supabase public-schema auto-exposure is
  no longer a safe assumption.
