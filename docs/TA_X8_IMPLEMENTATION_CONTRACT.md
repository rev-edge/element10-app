# TA-X8 implementation contract

Status: revision 3 proposed for independent review. No X8 migration is authorized by this
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
p_args jsonb)` is `VOLATILE SECURITY DEFINER`, anon-closed, and available only to
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

The dispatcher does not claim that volatility is a security boundary. Its exact
nested call graph is reviewed below. Query-control metadata is the only permitted
write. Before/after tests assert that no commercial, inventory, purchasing,
customer, identity, evidence, draft, outbox payload or idempotency state changes.

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
- Separate prepare and approval capabilities are enforced. The same actor may
  exercise both when they currently hold both; X8 adds no distinct-actor rule.
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

`e10_outbox_claim_commands` stores claim-request idempotency key, request
fingerprint and the historical bounded result. `e10_outbox_acknowledgements` is
append-only and records organization, outbox
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
- rejects limits outside 1..100 and leases outside 5..300 seconds;
- selects only pending/failed rows whose retry time is due (`NULL` means due), destination is
  allowed and prior lease is absent/expired;
- orders by next-attempt/created/id and locks with `FOR UPDATE SKIP LOCKED`;
- assigns one random token and incremented generation per row and increments
  `attempt_count` exactly once when ownership is granted;
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
- `delivered` sets the existing delivered state and timestamp and clears all
  active claim fields;
- `retry` sets failed, clears the claim and schedules a bounded next attempt;
- `dead` sets terminal dead and clears the claim;
- appends one acknowledgement record and returns a stable result;
- exact retry returns the original result; changed reuse fails.

Wrong owner, disabled consumer, foreign org, expired token, replaced generation
and malformed outcome fail without changing the row. Acknowledgement does not
contact a provider. Future delivery must use the immutable
`organization_id/commercial_event_id/destination_key` effect identity and prove
provider-side replay safety separately.

## X8a exact target and schema map

### Nested side effects

The implementation must verify these identities from `pg_proc` at build time and
pin them in tests. A function's volatility label is descriptive, not authority.

- `inventory.page` calls `public.e10_org_inv_page(uuid,text,integer,jsonb)` and
  `_e10_inv_item_json`. It reads inventory only and writes nothing.
- `inventory.history` calls
  `public.e10_org_inv_history(uuid,timestamptz,uuid,integer,text)`. It reads the
  retained movement ledger only and writes nothing.
- `supplier.workspace` calls
  `public.e10_org_supplier_workspace(uuid,uuid,integer,text)`. It reads
  purchasing documents/comments and writes nothing.
- `supplier.actual_cost_history` calls
  `public.e10_org_supplier_actual_cost_history(uuid,uuid,uuid,text,timestamptz,integer,text)`.
  It reads accepted receipt/cost evidence and writes nothing.
- `customer.spend_summary`, `customer.spend_contributions` and
  `customer.provisional_activity` call their exact X7b public functions. Those
  functions are `VOLATILE` because they take `FOR SHARE` locks on
  `e10_reporting_dataset_revisions`; they perform no insert, update or delete.
- `attendance.weekly` calls the exact X7a public function. It takes `FOR SHARE`
  on the same dataset revision and performs no insert, update or delete.
- `inventory.lifecycle`, `inventory.unique_item_evidence` and
  `inventory.valuation_coverage` call their exact X7e public readers and perform
  no write.
- `market.screener` and `market.observation_drilldown` call their exact X7d
  public readers. They write only actor/org-bound rows through
  `e10.save_market_query_context` and `e10.save_market_query_cursor`. This is an
  explicit query-control metadata exception needed for snapshot/cursor
  integrity. It is not a business-state mutation or shared result cache.

The X8 query context itself is also query-control metadata. Thus X8 is
business-read-only, not transaction-level `READ ONLY`. The allowed write set is
exactly `e10_query_contexts`, `e10_query_context_commands`,
`e10_market_query_contexts`, and `e10_market_query_cursors`. Tests compare all
other user tables before/after every operation. A future target with any other
nested write fails the call-graph gate and is not added to the allowlist.

### Common validation and envelope

Every `p_args` must be an object, at most 64 KiB, with no recursively unknown
keys. Strings are at most 2,000 bytes unless an existing target has a narrower
limit. Arrays are at most 100 elements. Numeric values must be finite. Times
must be finite timestamps. `limit` is required where shown and bounded to the
target's existing maximum; the dispatcher rejects rather than silently expands
it. Paired cursor components must both be null or both present.

Every response is:

```text
{version, operation, organization_id, context_id, query_fingerprint,
 as_of, cutoff, grain, units, metric_definition, coverage, sources,
 unknowns, result}
```

Fields unavailable from the target are literal JSON `null` plus a named entry
in `unknowns`; the dispatcher does not invent them. `sources` contains stable
database entity/event/observation identities already returned by the target,
never a fabricated external URL.

### Per-operation arguments

The dispatcher delegates to these exact existing signatures. Defaults shown are
the target defaults, but X8 still requires and narrows arguments as specified
below:

```text
e10_org_inv_page(p_org uuid,p_after text,p_limit int,p_filters jsonb)
e10_org_inv_history(p_org uuid,p_after_created timestamptz,p_after_id uuid,p_limit int,p_item_id text)
e10_org_supplier_workspace(p_org uuid,p_supplier_id uuid,p_limit integer,p_cursor text)
e10_org_supplier_actual_cost_history(p_org uuid,p_supplier_id uuid,p_configuration_version_id uuid,p_currency text,p_as_of timestamptz,p_limit integer,p_cursor text)
e10_org_customer_spend_summary(p_org uuid,p_from timestamptz,p_to timestamptz,p_observation_cutoff timestamptz,p_currency text,p_timezone text,p_week_start integer,p_customer uuid,p_purchase_kind text,p_location uuid,p_channel text,p_product uuid,p_configuration uuid,p_copy uuid,p_session uuid,p_capture_source text,p_limit integer,p_after_customer_id uuid,p_expected_dataset_revision bigint,p_expected_query_fingerprint text)
e10_org_customer_spend_contributions(p_org uuid,p_from timestamptz,p_to timestamptz,p_observation_cutoff timestamptz,p_currency text,p_customer uuid,p_purchase_kind text,p_location uuid,p_channel text,p_product uuid,p_configuration uuid,p_copy uuid,p_session uuid,p_capture_source text,p_limit integer,p_after_occurred_at timestamptz,p_after_transaction_id uuid,p_after_line_id uuid,p_expected_dataset_revision bigint,p_expected_query_fingerprint text)
e10_org_customer_provisional_activity(p_org uuid,p_from timestamptz,p_to timestamptz,p_observation_cutoff timestamptz,p_currency text,p_customer uuid,p_limit integer,p_after_occurred_at timestamptz,p_after_activity_id uuid,p_expected_dataset_revision bigint,p_expected_query_fingerprint text)
e10_org_weekly_attendance(p_org uuid,p_from timestamptz,p_to timestamptz,p_observation_cutoff timestamptz,p_timezone text,p_week_start integer,p_customer uuid,p_source_class text,p_provider_key text,p_limit integer,p_after_week_start date,p_expected_dataset_revision bigint,p_expected_query_fingerprint text)
e10_org_inventory_lifecycle(p_org uuid,p_as_of timestamptz,p_unique_item_id uuid,p_limit integer,p_cursor text)
e10_org_unique_item_evidence(p_org uuid,p_unique_item_id uuid,p_as_of timestamptz,p_limit integer,p_cursor text)
e10_org_inventory_valuation_coverage(p_org uuid,p_method text,p_method_version text,p_currency text,p_closing_cutoff timestamptz,p_opening_cutoff timestamptz,p_freshness_days integer,p_limit integer,p_cursor text)
e10_org_market_screener(p_org uuid,p_scope text,p_grouping text,p_metric text,p_observation_kind text,p_observed_from timestamptz,p_observed_to timestamptz,p_as_of timestamptz,p_currency text,p_source_mode text,p_source_kind text,p_source_connections jsonb,p_filters jsonb,p_sort text,p_limit integer,p_cursor uuid)
e10_org_market_observation_drilldown(p_org uuid,p_parent_query_fingerprint text,p_cohort_key text,p_observation_kind text,p_observed_from timestamptz,p_observed_to timestamptz,p_as_of timestamptz,p_currency text,p_source_mode text,p_source_kind text,p_source_connections jsonb,p_limit integer,p_cursor uuid)
```

- `inventory.page`: optional `after`; required `limit` 1..500; optional
  `filters` with only `cat,set,year,grade,q`. Result grain `inventory_item`, units
  `stored_item_quantity`; coverage/revision/cutoff are unavailable. X8 uses a
  permitted projection helper that excludes `note`, raw `meta`, private cost and
  contact fields from `_e10_inv_item_json` output.
- `inventory.history`: optional paired `after_created,after_id`; required
  `limit` 1..500; optional `item_id`. Result grain `inventory_movement`, units
  from `on_hand_delta/reserved_delta`; coverage unavailable. X8 projects a
  fixed allowlist and excludes free-form `note` plus raw `meta` unless a later
  reviewed field-level contract authorizes them.
- `supplier.workspace`: required `supplier_id`, `limit` 1..100; optional
  opaque `cursor`. Existing financial authorization controls the financial
  projection. Result sources are document IDs/revisions; grain is
  `purchasing_document`; cutoff is request time.
- `supplier.actual_cost_history`: required `supplier_id`,
  `configuration_version_id`, ISO currency, finite `as_of`, `limit` 1..100;
  optional opaque `cursor`. Grain `accepted_receipt_cost_evidence`, units named
  by currency and configuration base unit. Missing cost remains unavailable.
- `customer.spend_summary`: required finite `from,to,observation_cutoff`, ISO
  currency, timezone, ISO `week_start` 1..7 and `limit` 1..100; optional customer,
  purchase-kind, location, channel, product, configuration, copy, session,
  capture-source, cursor customer ID, expected dataset revision and query
  fingerprint. Existing exact signature and paired expected revision/fingerprint
  rules apply. Grain `effective_customer`; metric definition is the X7b
  net-merchandise contract; contact fields are never returned.
- `customer.spend_contributions`: required finite
  `from,to,observation_cutoff`, ISO currency and `limit` 1..100; optional
  customer, purchase-kind, location, channel, product, configuration, copy,
  session and capture-source; paired expected revision/fingerprint;
  cursor is the all-or-none triple `after_occurred_at,after_transaction_id,
  after_line_id`. Grain `posted_transaction_line_contribution`.
- `customer.provisional_activity`: required finite range/cutoff, ISO currency and
  `limit` 1..100; optional customer; all-or-none cursor
  `after_occurred_at,after_activity_id`; paired expected dataset revision/query
  fingerprint. Grain `provisional_activity`; it is labeled non-posted and never
  added to spend.
- `attendance.weekly`: required finite range/cutoff, timezone, ISO `week_start`
  1..7 and `limit` 1..54; optional customer/source class/provider key/week
  cursor; paired revision/fingerprint. Each row is one local calendar week for
  the selected organization scope, optionally filtered to one effective
  customer. It is not labeled `customer_week` when no customer filter exists.
  The target's `session_count_grain` and `duration_grain` fields are
  authoritative; durations are observed presence seconds with coverage and gap
  disclosure, never video watch time.
- `inventory.lifecycle`: required finite `as_of`, `limit` 1..100; optional unique
  item and opaque cursor. Each item is one unique-item ownership episode keyed
  by `unique_item_id,episode_key,origin_event_id`, with episode-level age,
  exposure and disposition metrics. It is not labeled as one lifecycle event.
  Contributing event identities, truncation, finality, precision and ambiguity
  come from X7e.
- `inventory.unique_item_evidence`: required unique item, finite `as_of`, `limit`
  1..50; optional cursor. Grain `evidence_observation`.
- `inventory.valuation_coverage`: required method, method version, ISO currency,
  finite closing cutoff, freshness days 1..3650 and `limit` 1..100; optional
  finite opening cutoff and cursor. Grain and units are returned by X7e; missing
  valuation/cost remains unknown.
- `market.screener`: required scope, grouping, metric, observation kind,
  finite `observed_from,observed_to,as_of`, ISO currency, source mode and
  `limit` 1..100; optional
  source kind/connections, typed filters, sort and cursor. Only the X7d filter
  schema is accepted recursively. Grain, cohort, units, rights/coverage,
  revisions and query fingerprint are passed through unchanged.
- `market.observation_drilldown`: required parent fingerprint, cohort key,
  observation kind, finite `observed_from,observed_to,as_of`, ISO currency,
  source mode and `limit`
  1..50; optional source kind/connections and cursor. Parent snapshot and source
  rights must still be valid for the same actor/org.

The envelope never declares a grain or unit finer than the target result. For
heterogeneous supplier workspace rows it uses `supplier_document` with the
target's `kind`; for customer summary it uses `effective_customer`; for spend
contributions it uses `posted_transaction_line_contribution`; for provisional
activity it uses `provisional_activity`; for unique-item evidence it uses
`evidence_record`; for valuation it uses `unique_item_holding`; and market
operations pass through the target's cohort/observation grain and units. Numeric
units are copied from target fields or stated as unavailable, never inferred.

On every call, before target-specific work and again after any blocking target
lock, the dispatcher/context guard checks active organization, `auth.uid()`,
context actor/org equality, expiry/revocation and current membership. Context ID
is an identifier, never bearer authority. Context tables are RLS-enabled,
client-closed and service-role-only. The creator may revoke their own context;
an org admin may revoke any context in that org. Revocation checks are repeated
after the context row lock. Expired contexts are retained as bounded audit
metadata for 30 days; no query results are cached by X8.

## X8b exact RPC and transition map

Public RPCs are:

- `e10_org_create_action_draft(p_org,p_operation,p_values,p_field_provenance,p_source_references,p_idempotency_key)`
- `e10_org_amend_action_draft(p_org,p_draft_id,p_expected_revision,p_values,p_field_provenance,p_source_references,p_idempotency_key)`
- `e10_org_preview_action_draft(p_org,p_draft_id,p_revision)`
- `e10_org_approve_action_draft(p_org,p_draft_id,p_expected_revision,p_idempotency_key)`
- `e10_org_cancel_action_draft(p_org,p_draft_id,p_expected_revision,p_reason,p_idempotency_key)`
- `e10_org_commit_action_draft(p_org,p_draft_id,p_expected_revision,p_idempotency_key)`

All are anon-closed. Tables remain client-closed. Creator or org admin may read,
preview, amend or cancel; amend also requires the operation's prepare capability.
Any current member with the operation's approval capability may preview and
approve an eligible proposal, with the same financial/contact redaction applied
to both calls. This does not grant amend, cancel or commit. The same actor may
prepare and approve because existing policy does not impose a universal
distinct-person rule; no new blanket maker/checker rule is invented. Commit
requires the operation's prepare capability and may be performed by the creator
or an org admin. The ordinary delegated writer rechecks its own authority.

Allowed transitions are exact: create produces `draft`; amend is allowed from
`draft` or `approved`, appends a new revision and returns to `draft` with approval
cleared; approval requires `status='draft'` and
`current_revision=p_expected_revision`, then records that revision as approved;
commit requires `status='approved'` and
`current_revision=approved_revision=p_expected_revision`; cancellation is
allowed from `draft` or `approved`; `committed` and `cancelled` are terminal.
Cancellation and commit serialize on the same draft row, so exactly one terminal
transition can win.

Values and provenance are operation-specific objects, each at most 256 KiB;
source references are at most 100 entries and 64 KiB total. Recursive unknown
keys, nonfinite numbers and oversized strings fail. Missing and ambiguous fields
are derived by server validators from typed values and current referenced rows;
the caller cannot declare a required field resolved. Preview projects only the
operation allowlist and redacts financial/contact values unless the caller has
the same current permission required by the underlying read contract.

Create operations have no target revision. Instead, every referenced supplier,
location, product/configuration, customer, activity and source row contributes a
server-derived identity/status/revision fingerprint stored on the draft revision.
Approval and commit recompute it. A change yields a stale-reference conflict and
requires an amended revision and new approval. Amend always clears approved
revision/status and appends a new complete revision; old approval history remains.

Commit locks the X8 command and draft first, then pre-acquires the ordinary
writer's existing advisory idempotency lock using the server-derived downstream
key and the writer's exact namespace (`purchase-order-command` or
`customer-commercial`). Advisory acquisition is reentrant in the same
transaction, so the delegated writer later observes the same lock. Only after
that potentially blocking lock returns does X8 lock every referenced mutable row
in a canonical order by relation and primary key, recompute the complete
fingerprint, and invoke the writer. Reference locks are held through the ordinary
write and X8 result recording. Any mismatch raises and rolls back the whole
transaction. The implementation test must hold that delegated-writer advisory
lock in one connection, start commit in another, mutate and commit a referenced
row while X8 waits, release the advisory lock, and prove X8's post-wait
fingerprint check fails with no ordinary row, command, event or partial X8
transition.

Every mutation uses X8-command-lock then draft-lock ordering. Commit continues
with the downstream advisory lock and canonical reference-row locks described
above. Authorization is
checked before target inspection and repeated after each blocking lock. Approval
requires the current draft revision; commit requires that same current revision
to be the recorded approved revision, exactly as specified above. Commit derives
an operation-namespaced ordinary idempotency key:
`x8:<operation>:<draft UUID>:<revision>:<SHA-256 of X8 commit key>`. The caller
cannot supply the downstream key. X8 stores that key and the exact ordinary
result. Exact retry first rechecks current authority, then returns the stored
result; changed operation/revision/payload under the same X8 key fails.

Current writer verification is mandatory at implementation: PO creation must
still create status `draft`, require active org/member `act.purchasing_prepare`,
validate supplier/destination/`can_receive_at`/active configurations, lock its
idempotency key and append one revision/event. Customer draft creation must
still create only status `draft`, require member
`act.prepare_customer_transactions`, validate every typed line and source/entity
link, lock its idempotency key and append one complete revision. X8 adds no bypass.

## X8c exact lease and idempotency ordering

Claim command fingerprint includes version, org, consumer, requested limit and
lease seconds. One command row stores the immutable returned row IDs, tokens,
generations and lease expiries. Exact replay first rechecks active org and enabled
consumer. It returns the historical result with `authoritative=false` unless
every recorded token is still the current unexpired claim. It never renews a
lease or implies current ownership. Changed reuse fails.

Consumer authorization is checked before selecting outbox rows and again after
each selected row lock. Destination entitlement is checked both times. The
fresh `clock_timestamp()` after lock acquisition determines lease eligibility
and expiry. Claiming increments `attempt_count` once. `next_attempt_at IS NULL`
means immediately due. Claim limit is 1..100, lease 5..300 seconds, destination
and consumer keys are 1..160 bytes, and counters may not overflow `integer`.

Acknowledgement command fingerprint includes version, org, consumer, outbox row,
token, generation, outcome, bounded retry interval and bounded error digest.
Error text is at most 2,000 bytes. Retry delay is 5..86,400 seconds. Exact replay
first rechecks active org and enabled consumer, then returns the stored historical
result even though the original token was cleared; it performs no second state
change. Without an existing acknowledgement receipt, expired/cleared/replaced
tokens fail. Changed reuse fails.

Ack and reclaim serialize on the outbox row. Ack uses fresh wall-clock time after
the row lock and succeeds only before lease expiry. Reclaim is eligible only at
or after expiry and writes a new generation/token. Therefore whichever obtains
the row under its valid time condition wins; a stale ack can never acknowledge
the new generation. Consumer disablement or destination removal is checked after
the lock and denies both claim and ack, including exact replay, without mutation.

`delivered`, `retry` and `dead` all clear owner/token/claimed/lease fields.
`delivered` sets `delivered_at`; other states keep it null. `retry` sets status
failed and `next_attempt_at=clock_timestamp()+retry interval`; `dead` sets dead
with no retry time. Every outcome sets bounded `last_error` consistently and
updates `updated_at`. The immutable effect identity remains
`organization_id/commercial_event_id/destination_key`; acknowledgement proves
only the database protocol transition, not external exactly-once delivery.

No consumer, destination entitlement, credential, dispatcher, job or schedule
is seeded by X8c.

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
