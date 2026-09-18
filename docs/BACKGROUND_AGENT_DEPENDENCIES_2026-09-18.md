# Background agent dependencies and owner decisions

Status: dependency and decision register, 2026-09-18.

## Established decisions

- Two predefined agents only: supplier invoice reconciliation and card inventory hygiene/enrichment.
- Both start in observe-and-propose mode.
- No unrestricted agent builder.
- Receiving remains physical truth; invoice and supplier credit remain separate financial evidence.
- Agent calculations do not create actual credits, payments, inventory, or catalog publication.
- AI is optional and uses the shared managed/org-funded/connector/manual architecture.
- External communication and executable automation are separate later grants.

## Reusable implemented foundations

- Tenant spine, capabilities, module entitlement, final-lock authority checks, and organization isolation.
- X8a closed typed read contexts and dispatcher.
- X8b immutable proposal revisions and guarded delegation for its two allowed operations.
- X8c dormant bounded claim/ack protocol.
- PO, invoice, receipt, credit, allocation, revision, receipt-correction, lot, cost-evidence, and vendor-document contracts.
- Platform catalog releases/variants/subject links, identity mappings, and governed reporting readers.
- Inventory evidence, lifecycle, valuation, and complete authorized-dataset reader patterns.
- Shared provider-independent AI job/configuration/usage contract, currently planned only.

## Blocking dependencies for BA-1/BA-2

- dedicated runtime principal and agent-specific authorization pattern;
- predefined definition registry and organization policy/grant capability names;
- trigger source contract and event-to-run deduplication key;
- retention/visibility policy for findings, evidence, failures, and costs;
- Home task projection ownership and stable link contract;
- approved supplier comparison tolerance and delivery-timing policy;
- packaging conversion ambiguity handling;
- decision whether BA-2 may only recommend review or may create a pre-credit request draft.

## Blocking dependencies for supplier recovery

- lifecycle and ownership for proposed recovery, approved submission, submitted claim, supplier acknowledgement, rejection/acceptance, and eventual actual credit;
- whether maker-checker is required before supplier submission;
- external communication channel, destination verification, templates, receipts, and replay safety;
- invoice arithmetic policy for tax, freight, discounts, rounding, and non-merchandise charges;
- authoritative payment/balance system if recovery reporting ever claims outstanding money.

Recommendation: BA-2 should stop at a durable finding and suggested next action.
Add the pre-credit request only after the lifecycle is approved. Do not delay
deterministic quantity reconciliation on payment/accounting decisions.

## Blocking dependencies for card hygiene confirmation

- organization-private subject mentions/candidates and enrichment overlay;
- reviewed alias/external-identifier history;
- exact authority for private link confirmation versus platform submission;
- duplicate/merge preview and downstream-impact reader;
- approved protected-field list and reversible normalization operations;
- platform catalog proposal/review/publish capability mapping.

Recommendation: the first card slice creates findings and private candidates
only. Platform catalog mutation and identity merge remain separate.

## Owner decisions for later automation

1. Capability names and default role grants for agent administration, run, review, cost view, approval, each executable action, and communication.
2. Who may grant unattended authority, whether grants expire, and maximum scope/quantity/amount/tolerance limits.
3. Schedule frequency, backfill window, concurrency, retry, dead-letter, and organization budget defaults.
4. Whether automated reversible formatting may ever be enabled and its exact allowed fields/operations.
5. Whether a distinct actor must approve agent proposals and whether the agent/runtime may ever approve anything.
6. Provider disclosure/retention policy and first supported unattended API connection after launch-time provider verification.
7. Customer pricing/allowance treatment for background runs, including deterministic runs versus provider-backed attempts.
8. Incident kill-switch ownership and notification/escalation behavior.

## Design constraints

- New public-schema tables are private by default: RLS, explicit grants, and closed bounded functions. RLS does not replace object privileges.
- `SECURITY DEFINER` is never authority by itself and must be born locked.
- Service-role access is infrastructure access, not organization permission.
- Human JWT/session state is not durable unattended authority.
- Provider/model text, imported content, and generated explanations are untrusted data.
- No production activation before threat model, local replay, hostile/concurrency tests, exact-head CI, guarded staging evidence, security review, and independent acceptance.
