# Backend schema expert-feedback review

Date: 2026-09-12

Status: approved by Trent on 2026-09-12. Implementation remains checkpointed,
additive and subject to the per-item approval boundaries below.

## Evidence basis

This review inspected the realized local Supabase schema at migration
`20260912154500`, 169 public base tables, their columns, primary/unique/check
constraints, indexes, foreign keys, policies and application references. The
local database is fixture-light: the reviewed catalog and product `attrs`
columns were empty, and `e10_inventory_items.extra` had three empty objects.
Consequently, statements about production JSON contents are grounded in writer
code and contracts, not an unavailable production sample. No staging or
production database was contacted.

## 1. JSON attributes and custom fields

### Current state: Partially handled

The schema has 109 JSON/JSONB columns on base tables. They fall into distinct
classes that should not be treated alike:

1. Source/evidence snapshots: `raw_payload`, `raw_payload_snapshot`,
   `source_payload`, `evidence`, `source_evidence`, `raw_evidence`,
   `input_evidence`, `received_snapshot`, `observed_markings` and OBS `raw`.
   These preserve provenance and are safe as JSON when reports use reviewed
   relational facts rather than parsing the source document.
2. Immutable command/result envelopes: columns named `result`, `snapshot`,
   `classifications`, `normalized_request`, `resolved_source_universe`,
   `sort_position` and outbox `payload`. These are bounded API, replay, revision
   or delivery envelopes. They are safe as JSON when their lookup keys remain
   relational.
3. Typed event/config payloads: `e10_break_events.payload`,
   `e10_commercial_events.payload`, `e10_financial_document_events.payload`,
   `overlay_cfg`, `plan`, `incentives`, `products`, `participants`,
   `chases_hit`, module/org `settings`, and location `address`. These are
   acceptable only behind a schema/version or validation contract. Any member
   promoted to a regular filter, join, conservation rule or permission boundary
   must become relational.
4. Extension bags: `attrs` on cards, checklists, catalog releases/variants,
   players, sets, teams, products/configurations, unique items, locations,
   suppliers/offerings and OBS products, plus `e10_inventory_items.extra`.
   These are the risky class for reporting.
5. Legacy workspace/backup blobs: `e10_workspace.data`, `e10_seed_backup.data`
   and `e10_bigimport_backup.data`. These are compatibility/recovery objects,
   not a reporting design.

The expert's claim that JSON has no indexing and must be filtered after SQL
returns rows is incorrect. PostgreSQL JSONB supports GIN and expression indexes,
and SQL filters execute in the database. The real concerns are uncontrolled key
names, inconsistent types/values, weak referential integrity and indexes that
must be designed per query. An EAV custom-field table does not provide "no query
performance penalty"; it adds joins and can be worse for multi-field filters.

The current client does use extension bags. Checklist import preserves every
unmapped column in `e10_cards.attrs`. It also writes player league into
`e10_players.attrs`. Inventory RPCs preserve whitelisted and unknown item input
in `e10_inventory_items.extra`. This disproves the requested blanket confirmation
that the application never reads or writes attributes. Current primary card
search filters use dedicated columns (`parallel`, `color`, etc.), not `attrs`,
which is the correct pattern.

### Proposed additive change

Do not use one untyped `(field_name, field_value)` table. Use definitions plus
typed values:

```sql
create table e10_custom_field_definitions (
  id uuid primary key,
  organization_id uuid not null,
  object_type text not null,
  field_key text not null,
  display_label text not null,
  data_type text not null,
  unit text,
  allowed_values jsonb,
  cardinality text not null,
  index_mode text not null,
  status text not null,
  created_by uuid,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  unique (organization_id, object_type, field_key)
);

create table e10_custom_field_values (
  id uuid primary key,
  organization_id uuid not null,
  field_definition_id uuid not null,
  object_type text not null,
  object_id text not null,
  value_text text,
  value_numeric numeric,
  value_boolean boolean,
  value_date date,
  value_timestamp timestamptz,
  created_by uuid,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  unique (organization_id, field_definition_id, object_type, object_id)
);

create index on e10_custom_field_values
  (organization_id, object_type, object_id, field_definition_id);
create index on e10_custom_field_values
  (organization_id, field_definition_id, value_text, object_id);
```

Only one typed value may be populated, enforced by a check/trigger. Indexes are
created only for definitions approved as reportable. Keep raw source payloads
unchanged. Promote existing JSON keys only after a key/type/value census and a
reconciling backfill.

### Questions for Trent

- Which object families may receive custom reporting fields in v1?
- May definitions be multi-valued, and which values require controlled terms?
- Which existing production JSON keys are promised as searchable today?

## 2. Parallel, color, finish and governed catalog fields

### Current state: Partially handled

`e10_catalog_variants` has `id`, `release_id`, `legacy_card_id`, `card_number`,
`exact_parallel`, legacy text `color_family`, legacy text `finish_pattern`,
`language`, `edition`, `rookie_designation`, `print_run_denominator`, `attrs`,
`created_at` and `updated_at`. Its indexes are:

- PK `(id)`;
- `(release_id, card_number, exact_parallel, id)`;
- `(rookie_designation, color_family, finish_pattern, id)`.

The governed color/finish IDs are not physical columns on that table. They are
effective projections derived from append-only
`e10_catalog_variant_facet_decisions.term_key`, with optional org overrides.
`e10_catalog_facet_term_keys.id` is the stable term identity and carries a
namespace check of `color_family` or `finish_family`. Versioned term and alias
tables validate namespace, current asserted term, revision and supersession.
Platform-admin review RPCs govern term, alias and global facet decisions; org
facet overrides are separate and permission checked.

The legacy checklist importer writes `e10_cards.parallel`, `color` and `attrs`.
It does not create `e10_catalog_variants` or governed facet decisions and does
not map a new exact parallel through the term aliases. Unmapped checklist
columns are intentionally retained in `e10_cards.attrs`. Therefore the desired
new-parallel mapping path is not complete. The governed reader correctly emits
null term IDs with an explicit `unknown` status when no current decision exists.

No persistent label/localization table exists for these field labels. Current
labels are frontend strings. Renaming a display label must not rename database
columns or term namespaces.

Queries against the effective schema are:

```sql
-- All shimmer-family variants for player X
select v.*
from e10.market_catalog_entities(:organization_id) v
join e10_catalog_variant_subjects s
  on s.variant_id = v.catalog_variant_id
where s.player_id = :player_id
  and v.finish_family_term_id = :shimmer_term_id;

-- All purple shimmer-family variants for player X
select v.*
from e10.market_catalog_entities(:organization_id) v
join e10_catalog_variant_subjects s
  on s.variant_id = v.catalog_variant_id
where s.player_id = :player_id
  and v.color_family_term_id = :purple_term_id
  and v.finish_family_term_id = :shimmer_term_id;
```

The player join uses `e10_catalog_variant_subjects_player_idx(player_id,
variant_id)`. Variant identity uses the release lookup index. The claim that
both complete queries are optimally indexed is not yet proven: effective term
IDs are computed through current-decision views, and the decision indexes lead
with variant/logical identity, not `(facet_key, term_key, variant_id)`. Add such
a partial index only after `EXPLAIN (ANALYZE, BUFFERS)` at representative volume.

### Proposed additive change

Create a reviewed catalog-import promotion command that preserves the exact
source parallel, resolves aliases by namespace, records either governed
decisions or explicit unresolved review cases, and never guesses. Add measured
term-to-variant indexes if plans prove them necessary. Do not duplicate effective
term IDs as mutable columns unless a refresh/invalidation contract is approved.

### Questions for Trent

- May an exact parallel be published while color or finish remains unresolved?
- Is org-private aliasing allowed to affect private reports without changing the
  platform taxonomy?

## 3. Players and the variant-subject pivot

### Current state: Already handled, with one rejected recommendation

`e10_catalog_variant_subjects` is:

```text
variant_id uuid not null FK -> e10_catalog_variants(id) ON DELETE CASCADE
player_id uuid not null FK -> e10_players(id)
subject_role text not null default 'featured'
position integer not null default 1 check (position > 0)
PK (variant_id, player_id)
UNIQUE (variant_id, position)
INDEX (player_id, variant_id)
```

There is no `player_id` on `e10_catalog_variants`. The legacy `e10_cards` table
does have one, but that is the old catalog, not duplication inside the new
variant table.

`subject_role` describes the subject's role on the card, currently defaulting to
`featured`. `position` is display/order position among subjects, not the
athlete's playing position. The projections aggregate subjects ordered by this
column. Tests exercise two subjects at positions 1 and 2. No richer role values
are currently governed or demonstrated in local rows.

Adding a surrogate ID is not beneficial here. This is a true junction whose
identity is the pair. A surrogate would still require the current pair unique
constraint and would weaken foreign keys that correctly reference
`(variant_id, player_id)`. Keep the composite PK.

### Proposed change

No key migration. If subject roles acquire semantics, add a check/catalog and
tests. Rename `position` to `display_order` only through a compatibility plan if
operator confusion justifies the churn.

### Question for Trent

- Do we need governed subject roles beyond `featured` before the next catalog
  intake implementation?

## 4. Checklists

### Current state: Partially handled

`e10_checklists` has `id` UUID PK, `name`, nullable `set_id` FK to `e10_sets`,
`source`, `card_count default 0`, `attrs`, `created_by`, `created_at` and
`updated_at`. Index `e10_checklists_set_id_idx(set_id)` supports set lookup.

Legacy `e10_cards.checklist_id` is non-null and cascades from the checklist.
Indexes include `e10_cards_checklist_id_idx(checklist_id)` and compound paging
indexes beginning with `checklist_id`.

`card_count` is denormalized and can drift. The client inserts card batches and
then performs a separate direct checklist update. The code explicitly tolerates
that update failing and asks the operator to reopen. No database trigger or
transactional import writer maintains the count.

Checklist `attrs` is empty locally. The current client does not populate it in
the reviewed import path, but it remains an uncontrolled platform-reference
extension bag. Checklist reportable metadata should use dedicated release/source
relations or governed custom fields, not ad hoc keys.

### Proposed additive change

Make the canonical import command transactional and derive the count from rows,
or maintain it in the same server transaction. Prefer a derived count for truth;
retain a cached count only with a reconciliation guard. The future checklist
must point to canonical variants rather than making `e10_cards` the permanent
identity model.

### Questions for Trent

- Is `card_count` required as a cached performance value, or may reads derive it?
- Which checklist-level metadata is actually reportable?

## 5. Viewers, customers, identities and platforms

### Current state: Partially handled

The expert's diagnosis of `e10_viewers` is incorrect. It is a global registered
viewer profile with PK `user_id -> auth.users(id)`, nullable `whatnot_handle` and
`created_at`. It is not a stream-membership row. A registered user can already
join multiple sessions through `e10_session_viewers`, whose PK is
`(session_id, user_id)` and which has `created_at` and `organization_id`.

The richer attendance model already exists:

- `e10_session_presence_streams`: session, source class, provider key, subject
  key, connection, optional auth user, platform attendee key, optional customer,
  identity status, coverage/retention and creation metadata.
- `e10_session_presence_segments`: stream segment, sequence, heartbeat expiry,
  retention and coverage policy.
- `e10_session_presence_events`: connected/heartbeat/disconnected/correction
  evidence with server, client and provider timestamps.
- derived interval readers calculate observed presence. They intentionally do
  not claim platform watch time unless licensed provider evidence supplies it.

Customer identity is also present:

```text
auth.users(id) <- optional e10_customers.auth_user_id
e10_customers(id, organization_id)
  <- e10_customer_identity_decisions(customer_id, channel,
       external_account_id, optional verified_user_id/handle_claim)
  <- customer activity and posted transaction attribution
e10_session_presence_streams.original_customer_id -> e10_customers
```

Duplication/gaps remain. `e10_viewers.whatnot_handle`, slot `buyer_handle`, OBS
slot `buyer_handle`, `e10_obs_channels(handle,family,whatnot_seller_id)`, viewer
handle claims, and customer channel identities can all carry handle-like data.
`e10_obs_channels.family` acts like a provider/platform string. There is no
governed platform registry. `e10_obs_*` means observed capture data in practice,
but readers can reasonably mistake it for Open Broadcaster Software.

### Proposed additive change

Create a platform/provider registry with stable identity, while keeping names
versionable rather than overwriting history:

```sql
create table e10_platforms (
  id uuid primary key,
  slug text not null unique,
  current_name text not null,
  status text not null,
  created_at timestamptz not null,
  updated_at timestamptz not null
);
```

Add `platform_id` to customer channel-identity decisions and provider attendance
records. Keep the external account ID/handle on the identity decision, because
the same handle string may identify different accounts on different platforms.
Do not add a second generic `stream_viewers` table: the presence stream/segment/
event model already covers this requirement more honestly than mutable
`joined_at`, `left_at`, `watch_time_seconds` columns. Add provider-reported watch
duration as separately labeled evidence, never as a silent overwrite of observed
companion time.

Retire `e10_viewers.whatnot_handle` only after compatibility readers/writers move
to verified handle claims/customer identities. Renaming is not currently safe:
legacy policies and client code reference it. Rename the `e10_obs_*` family in a
separate compatibility release to `e10_observed_*` or document the prefix as
`observed`, while reserving an explicit `e10_presentation_*` namespace for OBS
visual delivery.

### Questions for Trent

- Is the platform registry shared platform reference, with platform-admin-only
  curation?
- Is one platform account allowed to map to different org-owned customer
  profiles, as current tenant-private identity design implies?

## 6. Organizations

### Current state: Partially handled

`e10_organizations.status` is non-null text, defaults to `active`, and is checked
to `active|suspended`. The table has `created_at` but no `updated_at` or
`suspended_at`.

A nullable `suspended_at` records when the current suspension began, but it does
not provide history "for free": resuspension overwrites or loses prior periods.
Do not drop `status`; many authorization functions currently test
`status='active'`, and a timestamp alone becomes awkward if more lifecycle states
arrive.

### Proposed additive change

Add `updated_at`, `suspended_at`, a consistency check tying it to status, and an
append-only organization-status transition table with actor, reason and time.
Backfill suspended organizations with an explicitly unknown effective time
rather than inventing one. A reviewed status-change command must update the
current projection and insert its transition atomically.

### Questions for Trent

- Is suspension reversible, and must prior suspension intervals be reported?
- Should billing delinquency remain a separate state machine? Recommended: yes.

## 7. Audit trail and history

### Current state: Partially handled

There is no generic `audit_change_batches`/`audit_change_records` facility.
There is, however, extensive stronger domain history: immutable revisions,
commands/receipts, decisions with supersession, commercial events, allocation
events, receipt reversals, sale transitions, outbox acknowledgements and many
append-only guards. A generic audit table must not replace these authoritative
domain histories.

### Proposed additive change

Add a central audit index for mutable administrative/master-data changes:

```sql
create table e10_audit_change_batches (
  id uuid primary key,
  organization_id uuid,
  actor_user_id uuid,
  request_id text,
  operation text not null,
  occurred_at timestamptz not null,
  reason text
);

create table e10_audit_change_records (
  id uuid primary key,
  batch_id uuid not null,
  organization_id uuid,
  object_type text not null,
  object_id text not null,
  field_name text not null,
  old_value jsonb,
  new_value jsonb,
  classification text not null,
  created_at timestamptz not null
);
create index on e10_audit_change_records
  (organization_id, object_type, object_id, id);
```

For this stack, reviewed RPCs should create the batch and records in the same
transaction. This captures business operation, reason and actor accurately.
Database triggers are useful as a temporary coverage net for unavoidable legacy
direct writes, but they lack business intent and can leak secrets into old/new
JSON. Trigger capture must redact classified fields and use transaction-local
context set by the RPC. Append-only event/decision tables should be excluded to
avoid duplicating their own history.

### Questions for Trent

- Which mutable objects require field-level history first?
- What retention/export rules apply, especially for contact and financial data?

## 8. Organization role permissions

### Current state: Partially handled

`e10_organization_role_permissions` has organization, role, capability text,
`allowed boolean default true`, updater and update time. Its PK is
`(organization_id, role_id, capability)`; its FK is the composite role identity;
and `(organization_id, capability)` supports capability lookup.
`e10.has_org_cap(org, cap)` grants platform admins or finds an active membership
whose single role has the requested capability with `allowed=true`. Missing and
false rows both deny. Current local defaults contain 64 rows, 27 distinct
capabilities and zero false rows: admin 27, manager 25, streamer 7, ops 5.

Persisted default strings are:

```text
act.approve_checklists, act.approve_preparation, act.assign_operators,
act.configure_breaks, act.create_receiving, act.create_session,
act.inventory_edit, act.lists_edit, act.live_run, act.permissions_config,
act.reopen_preparation, act.reporting_export, act.reserve_inventory,
act.resolve_recovery, act.scheduling, act.submit_checklist_sources,
act.team_manage, act.view_financial_estimates, act.view_inventory,
act.view_prepared_handoff, act.view_schedule, mod.home, mod.inventory,
mod.reporting, mod.schedule, mod.settings, mod.toolkit
```

Newer writers also check additional strings such as
`act.manage_customers`, `act.prepare_customer_transactions`,
`act.approve_customer_transactions`, `act.post_customer_transactions`,
`act.adjust_customer_transactions`, `act.reconcile_customer_transactions`,
`act.merge_customers`, `act.correct_customer_attribution`,
`act.view_customer_financials`, `act.view_customer_engagement`,
`act.manage_intake`, `act.record_commercial_events`,
`act.curate_market_analytics`, `act.view_market_analytics`,
`act.configure_attendance_normalization`, `act.manage_attendance_coverage`,
`act.purchasing_prepare` and `financial.actual_cost.read`. Some are deliberately
ungranted/reserved. This confirms the known capability-catalog reconciliation
gap. None is field-level, although the `mod.*` navigation/entitlement keys do not
belong in the action-capability table long term.

The expert's numeric `level` proposal should not replace operation capabilities.
Create, approve, post, reconcile, publish and view sensitive costs are not a safe
read/write/admin hierarchy. A manager may prepare but not approve; a financial
reader may view costs but not edit inventory. Collapsing these into resource
levels would undermine maker-checker separation. It would reduce rows only by
coarsening authority, not by lossless normalization. For the current 27 default
capabilities, a four-resource level guess might reduce 64 rows to roughly 16,
but it would erase the distinctions the backend currently enforces. The safe
lossless reduction is effectively zero.

A surrogate ID is also unnecessary for this relationship table. The natural
composite prevents duplicate grants and is what callers address. Adding an ID
would still require the same unique constraint. Do add a governed capability
catalog and reference a stable capability ID or key:

```sql
create table e10_capabilities (
  id uuid primary key,
  capability_key text not null unique,
  owning_module text not null,
  operation_group text not null,
  sensitivity text not null,
  status text not null,
  replacement_capability_id uuid,
  created_at timestamptz not null,
  updated_at timestamptz not null
);
```

Keep `(organization_id, role_id, capability_id)` as the permission PK. Either
remove `allowed` and represent grants by row presence, or keep false only as a
disabled/tombstoned administrative state. It is not an override today because a
user has one role. If future users have multiple roles, deny precedence must be
explicitly designed rather than inferred.

Role templates should remain operation-based:

- Admin: all ordinary tenant capabilities, excluding platform curation and
  service-only operations.
- Manager: operational create/amend/receive/live capabilities, but not
  maker-checker approvals, permission administration or restricted actual cost
  unless explicitly granted.
- Streamer: live-session operation and required safe reads, with no purchasing,
  customer-financial or catalog-publication authority.

Templates are copied into org roles and then customizable; future template
changes must not silently rewrite an organization's customized role.

### Questions for Trent

- Approve operation capabilities over numeric resource levels?
- Should false rows be retained for audit/UI toggling or replaced by append-only
  role revision history?
- Which currently reserved capabilities receive v1 default grants?

## 9. General table patterns

### Current state: Partially handled, with broad disagreement

The rule "every table needs a surrogate id first" is not a PostgreSQL best
practice. Junctions, idempotency ledgers, singleton revisions and scoped natural
identities often benefit from composite keys. Column order also has no semantic
effect. Add surrogate keys only when rows need independent identity outside
their natural relationship.

Tables without a single-column `id` PK are:

```text
e10_action_draft_commands, e10_action_draft_revisions,
e10_catalog_identity_review_candidates, e10_catalog_variant_subjects,
e10_commercial_comment_commands, e10_commercial_event_schemas,
e10_credit_invoice_allocations, e10_customer_activity_source_components,
e10_customer_commercial_receipts, e10_customer_mutation_receipts,
e10_customer_transaction_approval_activity_snapshots,
e10_customer_transaction_draft_lines,
e10_customer_transaction_draft_revisions, e10_financial_allocation_commands,
e10_financial_document_commands, e10_intake_stage_replays,
e10_inventory_cursor_secrets, e10_inventory_reporting_revisions,
e10_invoice_po_allocations, e10_live_sessions,
e10_location_role_permissions, e10_market_catalog_revision,
e10_market_org_revisions, e10_members, e10_mutation_receipts,
e10_native_break_sale_receipts, e10_obs_config,
e10_organization_memberships, e10_organization_modules,
e10_organization_role_permissions, e10_organization_roles,
e10_platform_admins, e10_presence_collection_policies,
e10_purchase_order_commands, e10_query_context_commands,
e10_receipt_commands, e10_receipt_disposition_commands,
e10_receipt_invoice_allocations, e10_receipt_po_allocations,
e10_receipt_reversal_commands, e10_reporting_dataset_revisions,
e10_role_permissions, e10_seed_backup, e10_session_presence_receipts,
e10_session_viewers, e10_viewers
```

Most are correctly relationship, receipt/command, revision, singleton or
compatibility tables. `e10_viewers` is correctly keyed by its one auth user.
Review independently only where a row must be externally referenced and its
natural key is mutable or excessively wide.

The literal missing-timestamp inventory is large because append-only rows use
domain timestamps such as `decided_at`, `recorded_at`, `reviewed_at` or
`occurred_at`, and relationship/singleton tables often have no meaningful
update. Requiring both generic timestamps everywhere would add misleading data.

Missing `created_at`:

```text
e10_attendance_coverage_assertions, e10_bigimport_backup,
e10_catalog_facet_taxonomy_aliases, e10_catalog_facet_taxonomy_terms,
e10_catalog_facet_term_keys, e10_catalog_identity_review_decisions,
e10_catalog_population_snapshots, e10_catalog_variant_facet_decisions,
e10_catalog_variant_subject_context_decisions, e10_catalog_variant_subjects,
e10_commercial_event_schemas, e10_corrected_intake_commits,
e10_customer_activity_attribution_decisions,
e10_customer_activity_observations, e10_customer_activity_source_components,
e10_customer_identity_decisions, e10_customer_resolution_decisions,
e10_customer_transaction_approval_activity_snapshots,
e10_customer_transaction_attribution_decisions,
e10_customer_transaction_draft_decisions,
e10_customer_transaction_draft_lines,
e10_customer_transaction_evidence_links, e10_customer_transaction_lines,
e10_customer_transaction_reconciliation_decisions, e10_customer_transactions,
e10_intake_commits, e10_intake_resolver_decisions,
e10_inventory_cursor_secrets, e10_inventory_disposition_links,
e10_inventory_items, e10_inventory_reporting_revisions,
e10_location_financial_permission_decisions, e10_location_role_permissions,
e10_market_catalog_revision, e10_market_observation_coverage_decisions,
e10_market_observation_equivalence_decisions,
e10_market_observation_fact_decisions, e10_market_observations,
e10_market_org_revisions, e10_obs_breaks, e10_obs_captures, e10_obs_config,
e10_obs_product_prices, e10_obs_slots, e10_obs_streams,
e10_obs_upcoming_shows, e10_obs_viewer_snapshots,
e10_org_catalog_variant_facet_overrides, e10_organization_modules,
e10_organization_role_permissions, e10_outbox_acknowledgements,
e10_player_affiliation_decisions, e10_presence_policy_state_history,
e10_provider_presence_normalization_policy_decisions,
e10_provider_presence_normalized_intervals,
e10_provider_presence_quarantine_rows, e10_receipt_disposition_decisions,
e10_reporting_dataset_revisions, e10_role_permissions, e10_seed_backup,
e10_session_presence_attribution_decisions, e10_session_presence_events,
e10_stock_receipt_reversals, e10_unique_item_facet_decisions,
e10_unique_item_grade_assessments, e10_valuation_evidence, e10_workspace
```

For `updated_at`, 137 tables lack that literal name. The exact inventory is:

```text
e10_action_draft_commands, e10_action_draft_decisions,
e10_action_draft_revisions, e10_attendance_coverage_assertions,
e10_bigimport_backup, e10_break_events, e10_break_sessions, e10_cards,
e10_catalog_facet_taxonomy_aliases, e10_catalog_facet_taxonomy_terms,
e10_catalog_facet_term_keys, e10_catalog_identity_mappings,
e10_catalog_identity_review_candidates, e10_catalog_identity_review_cases,
e10_catalog_identity_review_decisions, e10_catalog_population_snapshots,
e10_catalog_variant_facet_decisions,
e10_catalog_variant_subject_context_decisions, e10_catalog_variant_subjects,
e10_commercial_comment_commands, e10_commercial_comments,
e10_commercial_event_schemas, e10_commercial_events,
e10_corrected_intake_commits, e10_credit_invoice_allocation_events,
e10_credit_invoice_allocations, e10_customer_activity_attribution_decisions,
e10_customer_activity_observations, e10_customer_activity_source_components,
e10_customer_commercial_receipts, e10_customer_identity_decisions,
e10_customer_mutation_receipts, e10_customer_resolution_decisions,
e10_customer_transaction_adjustments,
e10_customer_transaction_approval_activity_snapshots,
e10_customer_transaction_attribution_decisions,
e10_customer_transaction_component_finalizations,
e10_customer_transaction_draft_decisions,
e10_customer_transaction_draft_lines,
e10_customer_transaction_draft_revisions,
e10_customer_transaction_evidence_links, e10_customer_transaction_lines,
e10_customer_transaction_reconciliation_cases,
e10_customer_transaction_reconciliation_decisions,
e10_customer_transaction_source_claims, e10_customer_transactions,
e10_expected_allocation_events, e10_financial_allocation_commands,
e10_financial_document_commands, e10_financial_document_events,
e10_financial_document_reconciliation_cases, e10_intake_commits,
e10_intake_resolver_decisions, e10_intake_rows, e10_intake_stage_replays,
e10_inventory_cursor_secrets, e10_inventory_disposition_links,
e10_inventory_movements, e10_inventory_reporting_revisions,
e10_inventory_reservations, e10_invoice_po_allocation_events,
e10_invoice_po_allocations, e10_live_sessions,
e10_location_financial_permission_decisions, e10_lot_cost_evidence,
e10_lot_reservation_transitions, e10_market_catalog_revision,
e10_market_observation_coverage_decisions,
e10_market_observation_equivalence_decisions,
e10_market_observation_fact_decisions, e10_market_observation_supersessions,
e10_market_observations, e10_market_org_revisions,
e10_market_query_contexts, e10_market_query_cursors, e10_members,
e10_mutation_receipts, e10_native_break_sale_receipts,
e10_native_break_sale_transitions, e10_native_break_sales, e10_obs_breaks,
e10_obs_captures, e10_obs_channels, e10_obs_product_prices,
e10_obs_products, e10_obs_slots, e10_obs_streams,
e10_obs_upcoming_shows, e10_obs_viewer_snapshots,
e10_org_catalog_variant_facet_overrides, e10_organization_invitations,
e10_organization_memberships, e10_organization_modules,
e10_organization_roles, e10_organizations, e10_outbox_acknowledgements,
e10_outbox_claim_commands, e10_platform_admins,
e10_player_affiliation_decisions, e10_presence_collection_policies,
e10_presence_policy_state_history, e10_product_configuration_versions,
e10_provider_presence_normalization_policy_decisions,
e10_provider_presence_normalization_runs,
e10_provider_presence_normalized_intervals,
e10_provider_presence_quarantine_rows, e10_purchase_order_commands,
e10_purchase_order_lines, e10_purchase_order_revisions,
e10_query_context_commands, e10_query_contexts, e10_receipt_commands,
e10_receipt_disposition_commands, e10_receipt_disposition_decisions,
e10_receipt_invoice_allocations, e10_receipt_po_allocations,
e10_receipt_reversal_commands, e10_reporting_dataset_revisions,
e10_seed_backup, e10_session_presence_attribution_decisions,
e10_session_presence_events, e10_session_presence_receipts,
e10_session_presence_segments, e10_session_presence_streams,
e10_session_viewers, e10_stock_receipt_lines, e10_stock_receipt_reversals,
e10_stock_receipt_revisions, e10_supplier_credit_lines,
e10_supplier_credit_revisions, e10_supplier_invoice_lines,
e10_supplier_invoice_revisions, e10_unique_item_facet_decisions,
e10_unique_item_grade_assessments, e10_valuation_evidence,
e10_viewer_handle_claims, e10_viewers
```

The actionable review
should be limited to mutable current-state tables. Append-only events, decisions,
revisions, command receipts, junctions and immutable observations should not get
an `updated_at` they can never update. Clear mutable gaps include
`e10_organizations`, legacy `e10_viewers`, `e10_members`,
`e10_organization_roles`, `e10_organization_memberships`,
`e10_organization_invitations`, `e10_organization_modules`,
`e10_break_sessions`, `e10_cards` and several OBS current-state tables. A
follow-up migration plan must classify each table as mutable, append-only,
relationship, revision or singleton before adding anything.

Lifecycle text columns were inventoried across organization, membership,
invitation, product/configuration, customer, purchasing, receiving, inventory,
session, intake, outbox, identity-review and evidence tables. Do not replace them
mechanically with timestamps. State and transition time answer different
questions. Mutable lifecycles need current status plus transition history;
append-only decision/event models already carry history.

Renameable external names currently represented as text include catalog
manufacturer, customer identity channel, OBS channel family, provider keys and
source kinds. Platform/provider/channel should use a governed registry where
identity and integrations depend on them. Manufacturer is a canonical catalog
entity candidate, but converting it requires alias/matching governance because
source spellings are evidence. `source_kind` is usually a controlled event
classification, not an external entity and should remain a checked value.

### Questions for Trent

- Approve semantic classification before any bulk ID/timestamp migration?
- Which mutable legacy tables are scheduled for retirement rather than retrofit?
- Should manufacturer governance be part of catalog identity or product supply?

## Prioritized plan

1. Build the transactional canonical checklist promotion path, preserving exact
   parallel and creating reviewed or unresolved color/finish mappings. This has
   the highest immediate catalog/reporting impact.
2. Approve and implement governed custom-field definitions plus typed values.
   First census production JSON keys and promote only demonstrated reportable
   fields. Do not delete provenance JSON.
3. Reconcile the capability catalog and add catalog propose/review/publish
   operations. Preserve maker-checker separation; reject numeric rwx collapse.
4. Unify platform/channel identity around a stable platform registry, then bridge
   live buyer entry to customer identity and privacy-safe presentation delivery.
5. Fix checklist `card_count` transactional consistency.
6. Add organization suspension transition history, `suspended_at` current-state
   convenience and `updated_at`.
7. Add the central audit index for mutable administrative/master data, while
   retaining domain-specific append-only histories as authority.
8. Measure player/color/finish report plans at representative volume and add
   term-led indexes only where query plans justify them.
9. Classify all tables by lifecycle before selectively adding missing timestamps
   or surrogate IDs. Do not run a blanket retrofit.

## Execution checkpoints

### C1: canonical checklist promotion

Status: completed and locally verified 2026-09-12.

Migration `20260912171106_e10_schema_review_c1_checklist_promotion.sql` adds a
platform-admin-only, idempotent transaction that promotes one legacy checklist
into canonical variants and subject links. It preserves the source exact
parallel, resolves color and finish only through current reviewed aliases, and
records unresolved or absent values explicitly. Promotion is canonicalization,
not a claim that unresolved facets are approved for public publication.

The checkpoint also adds append-only checklist-entry, promotion-row and command
evidence. The database prevents duplicate promotion, wrong-namespace facet
keys, deletion of referenced source history and anonymous execution. The
checklist cached count is reconciled in the same locked transaction.

Local evidence: clean replay from migration zero passed; the focused promotion
suite passed; catalog entity projection and screener cohort regression suites
passed; the default-privilege probe passed with zero anonymous or PUBLIC
executable functions. Database lint reported only pre-existing findings in
older functions and no finding in this checkpoint's objects.

### C2: governed typed custom fields

Status: completed and locally verified 2026-09-12.

Migration `20260912171646_e10_schema_review_c2_governed_custom_fields.sql`
adds organization-owned definitions, controlled terms and exactly-one-type
values. Supported object families are catalog variants, checklists, inventory
items, unique items, product masters, product configurations and versions,
customers, suppliers and locations. Platform references may receive an
organization overlay, while organization-owned targets are verified against
the same organization before a value can be written.

Definitions govern data type, unit, cardinality, indexing mode and optional
field-level read/write capabilities. A missing write capability is fail-closed
to organization admins; a declared capability must be held. Direct client
writes remain closed and the authenticated RPC validates each typed value.
Raw JSON is not rewritten.

The clean local census found no populated keys in card, player or inventory
extension bags, so this checkpoint performs no speculative backfill. A future
environment-authorized census may nominate keys, but promotion still requires
an explicit definition, type and reconciliation proof.

### C3: governed capability catalog

Status: completed and locally verified 2026-09-12.

Migration `20260912172059_e10_schema_review_c3_capability_catalog.sql` adds a
stable capability registry and validates every persisted role grant against its
key. The existing `(organization_id, role_id, capability)` permission identity
and all client-facing capability checks remain compatible. False rows remain a
disabled administrative state; missing and false both deny, and neither is
treated as cross-role deny precedence.

Every currently persisted or backend-enforced capability is cataloged. Reserved
operations remain ungranted. The catalog now distinguishes organization and
platform authority and introduces separate `catalog.propose`, `catalog.review`
and `catalog.publish` operations. Tenant roles can never receive the platform
review or publication operations. Numeric read/write/admin levels are rejected
because they cannot preserve maker-checker and sensitive-read boundaries.

The custom-field capability hooks from C2 now reference the same registry.
Local tests prove validated foreign keys, no uncataloged grants, fail-closed
reserved defaults, false-row denial, platform-operation isolation, registry
read visibility and client mutation denial.

### C4: platform identity and live presentation bridge

Status: completed and locally verified 2026-09-12.

Migration `20260912172412_e10_schema_review_c4_platform_buyer_presentation_bridge.sql`
adds a shared stable platform registry, append-only reviewed name history and
explicit legacy channel/provider keys. Whatnot is the initial governed platform.
Platform IDs are added to customer channel identities, authorized-platform
presence streams, observed channels, operational break-slot buyers and native
sales. New unknown platform strings fail closed; recognizable legacy rows are
backfilled without changing their external account evidence.

The same external account may map to different organization-owned customers
because customer identity remains scoped by organization and platform. A
bounded live-buyer lookup returns recognized, ambiguous or unrecognized status
to the session owner without creating an Element 10 login or a duplicate buyer
record.

Native sale assignment and release now enqueue service-only presentation events
from the operational transaction. They do not write `e10_obs_*`; those tables
remain observed capture evidence rather than the system of record. Tests prove
platform-admin-only naming, append-only name revisions, optimistic concurrency,
known/unknown platform stamping, live customer lookup, buyer platform stamping,
presentation enqueue, release enqueue and zero observed-table side effects.

### C5: checklist count consistency

Status: completed and locally verified 2026-09-12.

Migration `20260912172924_e10_schema_review_c5_checklist_count_consistency.sql`
reconciles the legacy cache once, validates it as nonnegative and installs
statement-level transition-table triggers for card insertion, deletion and
checklist reassignment. The triggers apply deltas while locking the checklist
row, so concurrent card batches cannot overwrite each other's count.

Direct attempts to assign a count that differs from the current card rows fail;
the platform promotion command remains compatible because it writes the exact
derived count. Tests prove batch insert, unrelated card update, reassignment,
deletion, direct-drift denial, two-connection concurrency and the existing
catalog authorization gates.

### C6: organization suspension lifecycle

Status: completed and locally verified 2026-09-12.

Migration `20260912173214_e10_schema_review_c6_organization_status_history.sql`
adds `updated_at`, `suspended_at` and an explicit
`suspension_time_known` discriminator. Existing suspended rows retain an
unknown effective time instead of receiving an invented timestamp. New status
changes maintain a consistent current projection.

Every organization receives an append-only baseline, and a platform-admin-only
command records suspend and resume transitions atomically with reason, evidence,
actor, idempotency and optimistic concurrency. Suspension is reversible and
prior intervals remain reportable. Billing delinquency is not folded into this
state and remains a separate future state machine.

Tests prove baseline creation, ordinary-member denial, suspension, replay,
stale-revision rejection, resumption, transition semantics and compatibility
with existing race tests that suspend organizations while writers are blocked.

### C7: central mutable-data audit index

Status: completed and locally verified 2026-09-12.

Migration `20260912173502_e10_schema_review_c7_central_audit_index.sql`
adds append-only audit batches and field-level records for mutable organization,
role, permission, module, location, supplier, offering, product and custom-field
master data. Existing domain events, decisions, revisions and receipts remain
the authority and are deliberately excluded from generic capture.

Triggers act as a coverage net and accept transaction-local request/reason
context from reviewed RPCs. Contact, address, extension JSON and custom values
are never copied into audit records; salted-independent SHA-256 change digests
show whether protected content changed without exposing it. Audit reads require
platform administration or organization administration plus
`act.permissions_config`.

Retention is classified as standard, restricted or legal hold, but no deletion
period is invented. Tests prove contextual batches, exact ordinary deltas,
restricted redaction, absence of plaintext secrets, append-only protection,
authorized/unauthorized reads and exclusion of authoritative domain histories.

### C8: measured catalog term query index

Status: completed and locally verified 2026-09-12.

Migration `20260912173830_e10_schema_review_c8_catalog_term_index.sql` adds one
generic, term-led partial index over asserted catalog facet decisions. A
rollback-only local measurement used 50,000 variants and 100,000 facet
decisions. Before the index, the color-term report scanned all 100,000
decisions, removed 75,000 rows, touched 3,125 buffers and completed in 8.715 ms.
With the index, PostgreSQL selected `e10_variant_facet_term_assert_idx`, touched
1,827 buffers and completed in 7.888 ms. Timing is supporting evidence; the
stable acceptance signal is the index-backed predicate replacing a full scan.

The index is namespace-generic `(facet_key, term_key, variant_id, id)` and
limited to `action = 'assert'`. It supports color, finish and later governed
facets without inventing one index per vocabulary. The existing successor index
continues to serve the current-decision anti-join. No player-specific index was
added because the subject relation already has `(player_id, variant_id)`. No
JSON expression index was added.

### C9: semantic lifecycle classification

Status: completed and locally verified 2026-09-12.

No schema migration is justified by this checkpoint. The classification test
inventories every current public `e10_*` table and assigns exactly one lifecycle:

- `mutable_current_state`: present state may change; generic `updated_at` is
  useful only when no domain transition history already supplies authority.
- `append_only`: events, decisions, revisions, commands, receipts and evidence;
  occurrence/review/domain time is authoritative and `updated_at` is misleading.
- `relationship`: identity is the participating keys; a surrogate ID is not
  added unless another row must address the relationship independently.
- `singleton_or_compatibility`: naturally scoped state or a retirement bridge;
  preserve its natural key pending explicit replacement.
- `snapshot`: immutable backup or captured state, with capture/domain time.

`schema_review_c9_lifecycle_classification_test.sql` derives the complete live
inventory from PostgreSQL metadata, asserts one classification for every table
and anchors representative semantics for break events, organization
memberships, organizations and OBS config. On this checkpoint's schema it
classifies all 182 tables.

Selective conclusions: C6 already added justified organization current-state
timestamps plus authoritative transition history. C5 fixed checklist derived
state transactionally. No remaining table has evidence strong enough to add a
generic timestamp or surrogate identifier without an owner lifecycle or
retirement ruling. Therefore C9 deliberately adds no blanket DDL and preserves
all natural/composite identities.

### Completion audit

Status: all nine approved checkpoints completed locally on 2026-09-12.

A clean migration replay through C8 succeeded. The focused C1 through C9 suites
all passed from that replay, including the C5 concurrency test and the
default-function-privilege born-locked probe. Catalog projection and promotion
regressions also passed. Database lint found no issue in the checkpoint work;
its two errors remain the pre-existing temporary-table references in
`e10_slot_partition` and `e10_service_run_provider_presence_normalization`.

No staging or production database was contacted. Environment rollout remains a
separate, explicitly authorized operation and is not implied by completion of
this local architecture correction plan.

## Appendix: exact base-table JSON inventory

```text
e10_action_draft_commands(result)
e10_action_draft_revisions(proposed_values, field_provenance, source_references)
e10_action_drafts(ordinary_result)
e10_attendance_coverage_assertions(evidence)
e10_bigimport_backup(data)
e10_break_events(payload)
e10_break_sessions(overlay_cfg, chases_hit, products, participants)
e10_break_slots(plan, incentives)
e10_cards(attrs)
e10_catalog_facet_taxonomy_aliases(evidence)
e10_catalog_facet_taxonomy_terms(evidence)
e10_catalog_identity_mappings(source_payload)
e10_catalog_identity_review_candidates(evidence)
e10_catalog_identity_review_cases(source_evidence)
e10_catalog_identity_review_decisions(evidence)
e10_catalog_population_snapshots(evidence)
e10_catalog_releases(attrs)
e10_catalog_variant_facet_decisions(evidence)
e10_catalog_variant_subject_context_decisions(evidence)
e10_catalog_variants(attrs)
e10_checklists(attrs)
e10_commercial_comment_commands(result)
e10_commercial_events(payload)
e10_corrected_intake_commits(classifications)
e10_customer_activity_attribution_decisions(evidence)
e10_customer_activity_observations(raw_payload)
e10_customer_commercial_receipts(result)
e10_customer_identity_decisions(evidence)
e10_customer_mutation_receipts(result)
e10_customer_resolution_decisions(evidence)
e10_customer_transaction_adjustments(evidence)
e10_customer_transaction_attribution_decisions(evidence)
e10_customer_transaction_component_finalizations(evidence)
e10_customer_transaction_draft_lines(raw_evidence)
e10_customer_transaction_lines(raw_evidence)
e10_customer_transaction_reconciliation_cases(evidence)
e10_customer_transaction_reconciliation_decisions(evidence)
e10_financial_allocation_commands(result)
e10_financial_document_commands(result)
e10_financial_document_events(payload)
e10_financial_document_reconciliation_cases(received_snapshot)
e10_intake_rows(raw_payload, validation_errors)
e10_integration_outbox(payload)
e10_inventory_disposition_links(evidence)
e10_inventory_items(extra)
e10_inventory_movements(cost_basis, meta)
e10_location_financial_permission_decisions(evidence, result)
e10_locations(address, attrs)
e10_market_observation_coverage_decisions(evidence)
e10_market_observation_equivalence_decisions(evidence)
e10_market_observation_fact_decisions(evidence)
e10_market_observations(raw_payload_snapshot)
e10_market_query_contexts(normalized_request, resolved_source_universe)
e10_market_query_cursors(sort_position)
e10_native_break_sale_receipts(result)
e10_native_break_sale_transitions(evidence)
e10_native_break_sales(incentives, raw_evidence)
e10_obs_breaks(incentives)
e10_obs_captures(raw)
e10_obs_products(attrs)
e10_org_catalog_variant_facet_overrides(evidence)
e10_organization_modules(settings)
e10_organizations(settings)
e10_outbox_acknowledgements(result)
e10_outbox_claim_commands(result)
e10_player_affiliation_decisions(evidence)
e10_players(attrs)
e10_product_configuration_versions(attrs)
e10_product_configurations(attrs)
e10_product_masters(attrs)
e10_provider_presence_normalization_policy_decisions(evidence)
e10_provider_presence_quarantine_rows(details)
e10_purchase_order_commands(result)
e10_purchase_order_revisions(snapshot)
e10_query_context_commands(result)
e10_receipt_commands(result)
e10_receipt_disposition_commands(result)
e10_receipt_reversal_commands(result)
e10_seed_backup(data)
e10_session_presence_attribution_decisions(evidence)
e10_session_presence_events(evidence)
e10_session_presence_receipts(result)
e10_sets(attrs)
e10_stock_receipt_revisions(snapshot)
e10_supplier_credit_revisions(snapshot)
e10_supplier_invoice_revisions(snapshot)
e10_supplier_offerings(attrs)
e10_suppliers(contact, attrs)
e10_teams(attrs)
e10_unique_item_facet_decisions(evidence)
e10_unique_item_grade_assessments(evidence)
e10_unique_items(observed_markings, attrs)
e10_valuation_evidence(input_evidence)
e10_viewer_handle_claims(evidence)
e10_workspace(data)
```

## Approval boundary

This document does not approve DDL, backfill, renaming, capability grants,
environment application or production work. Each prioritized item needs a
separate additive migration plan, recovery plan, evidence matrix and owner
decisions listed above before implementation.
