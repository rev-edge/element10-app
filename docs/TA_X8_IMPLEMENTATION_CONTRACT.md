# TA-X8 implementation contract

Status: proposed for independent review. No X8 migration is authorized by this
document alone.

Authorities:

- `docs/EXPANSION_FRAMEWORK.md` sections 8 and 9
- `docs/EXPANSION_ACCEPTANCE_CASES.md`
- `docs/TA_X8_REVIEW_CHECKLIST.md`
- `docs/TRACK_A_EXPANSION_PLAN_2026-09-10.md`

## Boundary

X8 supplies three backend integration seams. It does not build a chatbot, UI,
external dispatcher, live feed, scheduler, notification service, autonomous
agent, or arbitrary SQL/function endpoint. It does not introduce accounting,
payment, landed-cost, pricing-publication, cross-shop sharing, or provider-rights
rules.

Implementation is split into independently reviewable increments:

1. X8a: explicit query context and closed typed query allowlist.
2. X8b: inert revisioned action proposals delegating to ordinary writers.
3. X8c: dormant service-only outbox claim and acknowledgement protocol.

Each increment stops after local replay, tests, exact-head CI, independent
implementation review, explicit staging apply, staging evidence, and independent
staging acceptance.

## X8a: read-only query boundary

### Context

`e10_query_contexts` records only:

- context UUID;
- organization UUID;
- actor UUID;
- purpose string from a closed allowlist (`workspace`, `export`, `assistant`);
- creation and bounded expiry timestamps;
- revocation timestamp and actor, when revoked.

It stores no query result or private tenant data. Context creation is an explicit
metadata mutation through `e10_org_create_query_context`. Creation requires an
active organization and current membership. Lifetime is bounded to 24 hours.
Exact idempotent retry returns the same context; changed input under one key
fails. Context revocation is append-only evidence plus a terminal timestamp.

Every query call requires both `p_org` and `p_context_id`. The server checks that
the context belongs to `auth.uid()`, names exactly `p_org`, is unexpired and not
revoked, and that the actor still has an active membership. A multi-membership
user therefore selects explicitly; no call uses `current_org()` or first-org
fallback. Switching organizations makes the prior context unusable for the new
organization without deleting the original context.

### Dispatcher

`e10_org_typed_query(p_org uuid, p_context_id uuid, p_operation text,
p_args jsonb)` is `STABLE SECURITY DEFINER`, anon-closed, and available only to
`authenticated` and `service_role`. It uses a literal `CASE` allowlist. It never
accepts SQL, relation names, function names, operators, projection strings, or
unbounded export flags. Unknown operations and unknown argument keys fail.

Supported v1 operations and existing authoritative targets:

- `inventory.page` -> `e10_org_inv_page`
- `inventory.history` -> `e10_org_inv_history`
- `supplier.workspace` -> `e10_org_supplier_workspace`
- `supplier.actual_cost_history` -> `e10_org_supplier_actual_cost_history`
- `customer.spend_summary` -> `e10_org_customer_spend_summary`
- `customer.spend_contributions` -> `e10_org_customer_spend_contributions`
- `customer.provisional_activity` -> `e10_org_customer_provisional_activity`
- `attendance.weekly` -> `e10_org_weekly_attendance`
- `inventory.lifecycle` -> `e10_org_inventory_lifecycle`
- `inventory.unique_item_evidence` -> `e10_org_unique_item_evidence`
- `inventory.valuation_coverage` -> `e10_org_inventory_valuation_coverage`
- `market.screener` -> `e10_org_market_screener`
- `market.observation_drilldown` -> `e10_org_market_observation_drilldown`

The dispatcher passes explicit bounded parameters to those functions and does
not reimplement their business rules. Existing per-operation authorization,
financial/contact projection, stable cursor, dataset revision, source scope,
coverage, ambiguity, and metric semantics remain authoritative. Limits may be
narrowed but never widened. A dispatcher response adds a stable envelope with
operation, context, organization, result, query fingerprint, as-of/cutoff,
metric/grain/unit definition where applicable, source references, coverage, and
explicit unknowns returned by the underlying contract.

The dispatcher is declared `STABLE` so a supported query cannot perform a
commercial or inventory mutation. Operations whose current implementation
cannot execute inside that read-only function contract remain unsupported until
corrected; they are not silently routed through a volatile escape.

Explicitly unsupported in v1:

- arbitrary SQL, RPC or table access;
- bulk mutation, record merge, identity decision or curation;
- unbounded list/export;
- cross-shop/private-data aggregation;
- pricing, accounting, payment or publication decisions;
- wishlist monitoring, external feeds and notification delivery.

### X8a acceptance

- Every operation has positive, malformed-input, unknown-key, limit, cursor,
  source/metric and hostile-tenant cases.
- A two-membership actor succeeds only with the matching explicit context.
- Foreign, expired, revoked, wrong-actor and scope-switched contexts fail before
  target inspection.
- A matching result beyond page one is returned through the same semantics used
  for totals and export-sized pages.
- Missing cost remains unknown/unavailable, provisional activity remains
  separate from posted spend, and line/copy/source grains do not multiply.
- Transaction-local before/after checks prove no commercial, inventory, draft,
  event, outbox or idempotency-table mutation from query execution.
- Representative-volume plans are captured before making latency claims.

## X8b: reviewable action proposals

### Storage

`e10_action_drafts` contains organization, creator, operation, current revision,
status (`draft`, `approved`, `committed`, `cancelled`), approved revision and the
ordinary result reference. `e10_action_draft_revisions` is append-only and
contains typed proposed values, missing fields, field provenance, source
references, target revision, request fingerprint, author and timestamp.
`e10_action_draft_decisions` is append-only approval/cancellation history.
`e10_action_draft_commands` provides operation-scoped idempotency.

All tables are org-owned, RLS-enabled, client-closed and service-role-only.
Public RPCs are the only client path. Imported text, user text and model output
are stored strictly as untrusted proposal provenance and never interpreted as
authority, SQL, capability, organization, approval or execution instructions.

### Supported operations

Only two v1 proposal types are supported because both have complete ordinary
draft writers:

#### `purchase_order.create`

Required proposal fields mirror
`e10_org_create_purchase_order(p_org, p_supplier_id,
p_destination_location_id, p_order_number, p_currency, p_expected_at, p_lines,
p_idempotency_key)`. Missing or ambiguous supplier, destination, configuration,
quantity or currency remains in `missing_fields`; it is not guessed. Proposal
creation/amendment requires `act.purchasing_prepare`. Approval requires
`act.purchasing_approve`. Commit delegates to the ordinary writer, which creates
an ordinary purchase order in `draft` status and rechecks active organization,
membership, prepare capability, destination permission, supplier/configuration,
payload, revision and idempotency. X8 commit does not approve or transmit the PO.

#### `customer_transaction.create_draft`

Required proposal fields mirror
`e10_org_create_customer_transaction_draft(p_org, p_customer, p_currency,
p_occurred_at, p_precision, p_note, p_lines, p_idempotency_key)`. Unresolved
customer or product identity remains explicit. Proposal preparation requires
`act.prepare_customer_transactions`; approval requires
`act.approve_customer_transactions`. Commit delegates to the ordinary writer,
which creates only an ordinary customer transaction draft. X8 commit does not
approve or post customer spend.

All other actions are explicitly unsupported in v1, including receiving stock,
posting customer transactions, approving a PO, merging identities, resolving
catalog mappings, reversing inventory, acknowledging money, dispatching an
external action, or applying a model suggestion.

### State and authorization

- Create/amend never calls an ordinary business writer.
- Amend uses current-revision CAS and appends a complete new revision.
- Approval names the exact current revision and requires `missing_fields=[]`.
- Commit names the exact approved revision and uses a distinct idempotency key.
- Commit locks the action draft, then rechecks active organization, actor,
  membership, operation-specific capability and approved/current revision.
- The delegated ordinary writer performs its own current authorization,
  location/entity/revision/idempotency checks in the same transaction.
- A changed proposal or target revision cannot reuse approval.
- Exact retry returns the same ordinary draft reference. Changed operation,
  revision or payload under one key fails.
- Scope switching cannot read, approve or commit the other organization's
  proposal. The original proposal remains retained under its original org.

### X8b acceptance

- Ambiguous PO and customer proposal fixtures remain uncommittable with exact
  missing fields and provenance.
- Prompt-injection text is retained as data and cannot alter organization,
  operation, approval, capability or delegated arguments.
- Preview is an exact rendering of one immutable revision.
- Changed revision invalidates approval.
- Maker/checker capability separation is enforced.
- Capability, membership, organization, destination permission and referenced
  entity changes between approval and commit fail closed.
- Competing commits and exact retries yield one action-draft command and one
  ordinary PO/customer draft, with real lock-wait proof and no partial residue.
- No proposal path receives stock, posts spend, changes inventory, merges an
  identity, dispatches an event externally, or mutates source evidence.

## X8c: dormant outbox claim and acknowledgement

### Storage additions

`e10_outbox_consumers` is an org-scoped, service-managed allowlist with stable
consumer ID, key, enabled status and allowed destination keys. No consumer is
seeded or enabled by the migration.

The existing `e10_integration_outbox` gains nullable claim owner, random claim
token, claim generation, claimed timestamp and lease expiry. Its existing event,
destination, payload and unique effect identity remain unchanged.

`e10_outbox_acknowledgements` is append-only and records organization, outbox
row, consumer, claim generation/token, success/failure disposition, retry time,
idempotency fingerprint and recorded time. It records database protocol state,
not proof that an external provider performed an effect.

All relations remain RLS-enabled and client-closed. Claim and acknowledgement
functions are executable only by `service_role`; there is no authenticated,
anon or `PUBLIC` path.

### Claim contract

`e10_claim_outbox(p_org, p_consumer_id, p_limit, p_lease_seconds,
p_idempotency_key)`:

- validates active org and enabled registered consumer before target inspection;
- clamps limit to 1..100 and lease to 5..300 seconds;
- selects only pending/failed rows whose retry time is due, destination is
  allowed and prior lease is absent/expired;
- orders by next-attempt/created/id and locks with `FOR UPDATE SKIP LOCKED`;
- assigns one random token and incremented generation per row;
- returns only bounded event identity, destination, payload, token, generation
  and lease expiry;
- makes exact request replay stable and changed-key reuse fail.

Concurrent consumers cannot own one live generation. Crash before ack leaves the
outbox event durable; after lease expiry a new claim gets a new token and higher
generation. The old token can never acknowledge the replacement.

### Acknowledgement contract

`e10_ack_outbox(p_org, p_consumer_id, p_outbox_id, p_claim_token,
p_claim_generation, p_outcome, p_retry_after_seconds, p_error,
p_idempotency_key)`:

- accepts only `delivered`, `retry` or `dead`;
- locks the outbox row and rechecks active org, enabled consumer, owner, token,
  generation and unexpired lease;
- `delivered` sets the existing delivered state and timestamp;
- `retry` sets failed, clears the claim and schedules a bounded next attempt;
- `dead` sets terminal dead and clears the claim;
- appends one acknowledgement record and returns a stable result;
- exact retry returns the original result; changed reuse fails.

Wrong owner, disabled consumer, foreign org, expired token, replaced generation
and malformed outcome fail without changing the row. Acknowledgement does not
contact a provider. Future delivery must use the immutable
`organization_id/commercial_event_id/destination_key` effect identity and prove
provider-side replay safety separately.

### X8c acceptance

- Migration seeds no consumer and enables no dispatch path.
- Two real connections racing to claim one row produce one owner.
- Disjoint bounded batches can be claimed concurrently without duplication.
- Crash-before-ack, lease expiry and replacement preserve one durable outbox
  row and reject the stale token.
- Exact acknowledgement retry creates one acknowledgement and one state change.
- Wrong owner, foreign org, disabled consumer and revocation during lock wait
  fail after fresh authorization checks with no residue.
- No network call, secret, scheduler, Edge Function, webhook or notification is
  created or invoked.

## Evidence packet

Each increment returns its migration and tests, operation/response schemas,
function ACLs, table RLS/grants, local clean replay, focused regressions,
exact-head CI, explicit staging apply/ledger, definition hashes, fixture cleanup,
advisor counts/deltas and the standing production `BEGIN READ ONLY` baseline.
The final X8 handoff maps every checklist item to executable evidence and labels
all unsupported/deferred operations rather than implying broader integration.
