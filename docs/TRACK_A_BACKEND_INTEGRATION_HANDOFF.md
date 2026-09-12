# Track A backend integration handoff

Date: 2026-09-12

Audience: Track B and future backend consumers. This is the discoverable index
for the staging-complete X1-X8 foundation. Exact behavior remains defined by the
cited migration and contract, not by client assumptions.

## Rules shared by integration calls

- Organization-scoped client RPCs require the explicitly selected organization,
  a real authenticated JWT, an active organization and membership, and their
  named capability or object authority. Never infer the first membership.
  Supplying an ID is never authority.
- Shared reviewed-catalog readers use their catalog-specific authority and do
  not accept an organization merely to imitate tenant scope.
- The F4 identity-review APIs are platform-admin APIs with no organization
  argument. The X8c outbox claim/ack APIs are service-role-only and are not
  browser APIs. Their sections below are authoritative over the org-client rule.
- Mutating client RPCs use an explicit idempotency key. Exact replay returns the prior
  result; changed reuse fails. Revisioned resources also require the current
  expected revision and return a conflict when stale.
- Treat SQLSTATE `42501` as authorization/scope refusal, `22023` as invalid or
  mismatched input, `23514` as a capacity/conservation refusal, `40001` as a
  stale revision/serialization conflict, and `55000` as a closed lifecycle
  state. Clients must display the returned server message without inventing a
  successful fallback.
- Limits and cursors are mandatory where specified. Cursors are opaque and
  bound to actor, organization, filters, revisions and cutoffs.
- Null or `unavailable` means unknown. It is never zero. Provisional activity
  is never official spend. Asking price, completed sale, acquisition cost and
  valuation estimate are different evidence kinds.
- Direct table writes are not an integration contract. Use public RPCs only.

## Identity and location foundation

X1 identity tables are read through RLS-backed catalog/product relations. The
reviewed public history surfaces are:

- `e10_catalog_player_affiliations(p_player_id uuid,p_window_from date,p_window_to date,p_limit integer) -> jsonb`
- `e10_catalog_variant_subject_context(p_variant_id uuid,p_limit integer) -> jsonb`
- `e10_org_purchase_destinations(p_org uuid,p_after_name text,p_after_id uuid,p_limit integer) -> table(id,code,name,eligible_count,sole_eligible)`

Player history is shared reviewed catalog evidence. Products, configurations,
versions, copies, locations, suppliers and offerings remain organization-owned.
Destination selection must use returned IDs; advisory text cannot override an
ineligible location. Contracts: migrations `20260910171106`, `20260910173520`,
`20260910174555`, `20260911190000`.

## Purchasing, financial documents and comments

Ordinary purchasing writers, all returning `jsonb`:

- `e10_org_create_purchase_order(p_org uuid,p_supplier_id uuid,p_destination_location_id uuid,p_order_number text,p_currency text,p_expected_at timestamptz,p_lines jsonb,p_idempotency_key text)`
- `e10_org_amend_purchase_order(p_org uuid,p_purchase_order_id uuid,p_expected_revision integer,p_supplier_id uuid,p_destination_location_id uuid,p_order_number text,p_currency text,p_expected_at timestamptz,p_lines jsonb,p_reason text,p_idempotency_key text)`
- `e10_org_transition_purchase_order(p_org uuid,p_purchase_order_id uuid,p_expected_revision integer,p_action text,p_reason text,p_idempotency_key text)`
- `e10_org_create_supplier_invoice(p_org uuid,p_supplier_id uuid,p_supplier_document_number text,p_currency text,p_document_date date,p_total_amount numeric,p_source_connection text,p_external_document_id text,p_payload_fingerprint text,p_duplicate_review_outcome text,p_duplicate_review_reason text,p_lines jsonb,p_idempotency_key text)`
- `e10_org_create_supplier_credit(...)`, with the same header arguments as invoice creation
- `e10_org_amend_supplier_invoice(p_org uuid,p_supplier_invoice_id uuid,p_expected_revision integer,p_currency text,p_document_date date,p_total_amount numeric,p_lines jsonb,p_reason text,p_idempotency_key text)`
- `e10_org_amend_supplier_credit(...)`, with the corresponding credit ID
- `e10_org_review_supplier_invoice`, `e10_org_approve_supplier_invoice`, and `e10_org_void_supplier_invoice`, each `(p_org uuid,p_supplier_invoice_id uuid,p_expected_revision integer,p_reason text,p_idempotency_key text)`
- `e10_org_review_supplier_credit`, `e10_org_approve_supplier_credit`, and `e10_org_void_supplier_credit`, each `(p_org uuid,p_supplier_credit_id uuid,p_expected_revision integer,p_reason text,p_idempotency_key text)`
- `e10_org_allocate_invoice_to_po(p_org uuid,p_invoice_line_id uuid,p_purchase_order_line_id uuid,p_expected_invoice_revision integer,p_expected_purchase_order_revision integer,p_quantity numeric,p_reason text,p_idempotency_key text)`
- `e10_org_release_invoice_from_po(...)`, same identities/revisions and release quantity
- `e10_org_allocate_credit_to_invoice(p_org uuid,p_credit_line_id uuid,p_invoice_line_id uuid,p_expected_credit_revision integer,p_expected_invoice_revision integer,p_amount numeric,p_reason text,p_idempotency_key text)`
- `e10_org_release_credit_from_invoice(...)`, same identities/revisions and release amount

Capabilities are operation-specific:

| Operation | Required capability |
| --- | --- |
| Create or amend PO, invoice or credit | `act.purchasing_prepare` |
| Submit PO or review invoice/credit | `act.purchasing_prepare` |
| Approve PO, invoice or credit | `act.purchasing_approve` |
| Cancel/close PO or void invoice/credit | `act.purchasing_cancel` |
| Create receipt batch | `act.create_receiving` |
| Reverse receipt or correct disposition | `act.resolve_recovery` |
| Allocate or release invoice/credit relationships | `act.purchasing_prepare` |

Location authority is rechecked inside the applicable writer. Invoice approval
does not receive stock or assert payment.

Comment and bounded workspace APIs:

- `e10_org_add_commercial_comment(p_org uuid,p_document_kind text,p_document_id uuid,p_audience text,p_body text,p_supersedes_comment_id uuid,p_idempotency_key text) -> jsonb`
- `e10_org_list_commercial_comments(p_org uuid,p_document_kind text,p_document_id uuid,p_limit integer,p_before_created_at timestamptz,p_before_id uuid) -> jsonb`
- `e10_org_vendor_comment_projection(p_org uuid,p_document_kind text,p_document_id uuid,p_limit integer) -> jsonb`
- `e10_org_supplier_workspace(p_org uuid,p_supplier_id uuid,p_limit integer,p_cursor text) -> jsonb`
- `e10_org_supplier_actual_cost_history(p_org uuid,p_supplier_id uuid,p_configuration_version_id uuid,p_currency text,p_as_of timestamptz,p_limit integer,p_cursor text) -> jsonb`

Vendor projection is an allowlist and never contains internal comments. Actual
cost requires `financial.actual_cost.read`, is exact supplier/configuration/
currency evidence, and never treats an unreceived order as last paid.

## Receiving, lots and reservations

- `e10_org_receive_batch(p_org uuid,p_supplier_id uuid,p_destination_location_id uuid,p_received_at timestamptz,p_lines jsonb,p_idempotency_key text) -> jsonb`
- `e10_org_reverse_receipt_batch(p_org uuid,p_receipt_id uuid,p_reason text,p_idempotency_key text) -> jsonb`
- `e10_org_review_receipt_disposition(p_org uuid,p_receipt_line_id uuid,p_action text,p_quantity numeric,p_predecessor_decision_id uuid,p_expected_revision integer,p_reason text,p_idempotency_key text) -> jsonb`
- `e10_org_lot_reserve(p_org uuid,p_lot_id uuid,p_quantity numeric,p_break_session_id uuid,p_idempotency_key text) -> jsonb`
- `e10_org_lot_reserve_for_demand(p_org uuid,p_lot_id uuid,p_quantity numeric,p_demand_type text,p_demand_reference text,p_demand_label text,p_idempotency_key text) -> jsonb`
- `e10_org_lot_consume(p_org uuid,p_reservation_id uuid,p_quantity numeric,p_idempotency_key text) -> jsonb`
- `e10_org_lot_release(p_org uuid,p_reservation_id uuid,p_idempotency_key text) -> jsonb`

Receiving requires `act.create_receiving` and destination authority. Reservation
requires `act.reserve_inventory`; consume/release require
`act.inventory_edit`. Generic demand type is only `manual` or `sale_order`.
Its reference is opaque caller provenance, not proof that an authorized order
exists. The break-specific API remains the only session-linked contract. Both
paths share lot/item locks, no-overcommit checks, receipt projection, legacy
reservation compatibility and movement evidence.

## Intake and commercial evidence

- `e10_org_stage_intake(p_org uuid,p_source_kind text,p_source_connection_id text,p_source_reference text,p_original_file_reference text,p_payload_fingerprint text,p_rows jsonb,p_idempotency_key text) -> jsonb`
- `e10_org_stage_corrected_intake(p_org uuid,p_supersedes_batch_id uuid,p_source_kind text,p_source_connection_id text,p_source_reference text,p_original_file_reference text,p_payload_fingerprint text,p_rows jsonb,p_idempotency_key text) -> jsonb`
- `e10_org_resolve_intake_row(p_org uuid,p_intake_row_id uuid,p_decision text,p_target_id uuid,p_reason text,p_corrects_decision_id uuid,p_idempotency_key text) -> jsonb`
- `e10_org_commit_intake(p_org uuid,p_batch_id uuid,p_expected_review_revision bigint,p_idempotency_key text) -> jsonb`
- `e10_org_commit_corrected_intake(p_org uuid,p_batch_id uuid,p_expected_review_revision bigint,p_classifications jsonb,p_idempotency_key text) -> jsonb`
- `e10_org_record_commercial_event_v2(p_org uuid,p_event_type text,p_event_schema_version integer,p_subject_type text,p_subject_id text,p_occurred_at timestamptz,p_occurred_at_precision text,p_source_kind text,p_source_connection_id text,p_source_reference text,p_source_event_id text,p_correlation_id text,p_causation_event_id uuid,p_evidence_quality text,p_payload jsonb,p_corrects_event_id uuid,p_outbox_destinations text[],p_idempotency_key text) -> jsonb`

Intake uses `act.manage_intake`; ordinary event recording uses
`act.record_commercial_events`. Imported payloads remain untrusted. Typed
resolution, review, correction and eligible-current interpretation are server
decisions. Native-system provenance is reserved for trusted native writers.

## Customer and attendance lifecycle

Customer identity and transaction entry points are indexed in migrations
`20260910234500` through `20260911021500`. Primary client APIs include:

- `e10_org_create_customer(p_org uuid,p_display_name text,p_idempotency_key text)`
- `e10_org_update_customer(p_org uuid,p_customer_id uuid,p_expected_revision bigint,p_display_name text,p_status text,p_idempotency_key text)`
- `e10_org_decide_customer_identity(p_org uuid,p_customer_id uuid,p_identity_kind text,p_channel text,p_external_account_id text,p_alias_text text,p_identity_action text,p_viewer_handle_claim_id uuid,p_reason text,p_evidence jsonb,p_idempotency_key text)`
- `e10_org_create_customer_transaction_draft(p_org uuid,p_customer uuid,p_currency text,p_occurred_at timestamptz,p_precision text,p_note text,p_lines jsonb,p_idempotency_key text)`
- `e10_org_amend_customer_transaction_draft(p_org uuid,p_draft uuid,p_expected_revision integer,p_customer uuid,p_currency text,p_occurred_at timestamptz,p_precision text,p_note text,p_lines jsonb,p_idempotency_key text)`
- `e10_org_approve_customer_transaction_draft(p_org uuid,p_draft uuid,p_expected_revision integer,p_idempotency_key text)`
- `e10_org_post_customer_transaction_draft(p_org uuid,p_draft uuid,p_expected_revision integer,p_idempotency_key text)`
- `e10_org_adjust_customer_transaction(...)`, exact 19-argument adjustment signature in migration `20260911003000`
- `e10_org_finalize_customer_transaction_component(...)`, exact 13-argument finalization signature in migration `20260911004500`
- `e10_org_decide_customer_transaction_reconciliation(...)`, exact reviewed case signature in migration `20260911010000`
- `e10_org_decide_customer_resolution(...)` and `e10_org_decide_customer_transaction_attribution(...)`, exact immutable correction signatures in migrations `20260911011500` and `20260911013000`
- `e10_org_commit_native_break_sale(...)` and `e10_org_release_native_break_sale(...)`, exact slot-revision signatures in migration `20260911014500`

Capabilities remain distinct: `act.manage_customers`,
`act.prepare_customer_transactions`, `act.approve_customer_transactions`,
`act.post_customer_transactions`, and reconciliation authority. No default
role grant is implied. Provisional activity and native board sales do not post
official spend. Posting does not assert settlement.

This completed X6 slice is transaction and identity reconciliation, not a full
CRM. It does not store customer contact records, communication preferences,
consent provenance, visibility-controlled organization tags, private customer
notes or fulfillment addresses. Clients must not place those values in generic
evidence JSON or infer that `act.manage_customers` exposes a nonexistent contact
projection. Those fields require a later privacy-reviewed schema and independent
permissions. Likewise, no generic versioned typed-extension registry exists;
the framework's namespace/type/units/validation/cardinality/permission/index
rules remain mandatory for any later extension implementation.

## Reporting contracts

These are bounded reads. Their exact long signatures and response fields are
defined in their migrations and wrapped without broadening by X8a:

- Attendance: `e10_org_weekly_attendance`,
  `e10_org_attendance_contributions`,
  `e10_org_attendance_contribution_segments`,
  `e10_org_provider_attendance_intervals`, and
  `e10_org_provider_attendance_quarantine`. Capability:
  `act.view_customer_engagement`.
- Customer: `e10_org_customer_spend_summary`,
  `e10_org_customer_spend_contributions`,
  `e10_org_customer_spend_lineage`, and
  `e10_org_customer_provisional_activity`. The final full-dataset grid is
  `e10_org_customer_spend_grid_v2(p_org uuid,p_window_mode text,p_from timestamptz,p_to timestamptz,p_observation_cutoff timestamptz,p_currency text,p_timezone text,p_week_start integer,p_customer uuid DEFAULT NULL,p_purchase_kind text DEFAULT NULL,p_location uuid DEFAULT NULL,p_channel text DEFAULT NULL,p_product uuid DEFAULT NULL,p_configuration uuid DEFAULT NULL,p_copy uuid DEFAULT NULL,p_session uuid DEFAULT NULL,p_capture_source text DEFAULT NULL,p_min_known_official_subtotal numeric DEFAULT NULL,p_max_known_official_subtotal numeric DEFAULT NULL,p_sort text DEFAULT 'customer_id_asc',p_limit integer DEFAULT 100,p_cursor jsonb DEFAULT NULL,p_expected_dataset_revision bigint DEFAULT NULL,p_expected_query_fingerprint text DEFAULT NULL) -> jsonb`.
  Capabilities:
  `act.view_customer_financials`, engagement and location financial access as
  applicable.
- Market: `e10_org_market_screener(p_org uuid,p_scope text,p_grouping text,p_metric text,p_observation_kind text,p_observed_from timestamptz,p_observed_to timestamptz,p_as_of timestamptz,p_currency text,p_source_mode text,p_source_kind text,p_source_connections jsonb,p_filters jsonb,p_sort text,p_limit integer,p_cursor uuid) -> jsonb` and
  `e10_org_market_observation_drilldown(p_org uuid,p_parent_query_fingerprint text,p_cohort_key text,p_observation_kind text,p_observed_from timestamptz,p_observed_to timestamptz,p_as_of timestamptz,p_currency text,p_source_mode text,p_source_kind text,p_source_connections jsonb,p_limit integer,p_cursor uuid) -> jsonb`. Capability: `act.view_market_analytics`.
- Inventory: `e10_org_inventory_lifecycle(p_org uuid,p_as_of timestamptz,p_unique_item_id uuid,p_limit integer,p_cursor text) -> jsonb`, `e10_org_unique_item_evidence(p_org uuid,p_unique_item_id uuid,p_as_of timestamptz,p_limit integer,p_cursor text) -> jsonb`, and `e10_org_inventory_valuation_coverage(p_org uuid,p_method text,p_method_version text,p_currency text,p_closing_cutoff timestamptz,p_opening_cutoff timestamptz,p_freshness_days integer,p_limit integer,p_cursor text) -> jsonb`.

Every report returns or preserves scope, grain, metric definition, units,
cutoff/revision, coverage and sources. Contact and actual-cost fields require
their separate permissions. Totals are computed before pagination.

## X8 integration seam

### Typed query context

- `e10_org_create_query_context(p_org uuid,p_purpose text,p_lifetime_seconds integer,p_idempotency_key text) -> jsonb`
- `e10_org_revoke_query_context(p_org uuid,p_context_id uuid,p_idempotency_key text) -> jsonb`
- `e10_org_typed_query(p_org uuid,p_context_id uuid,p_operation text,p_args jsonb) -> jsonb`

Supported operation strings are exactly:

`inventory.page`, `inventory.history`, `supplier.workspace`,
`supplier.actual_cost_history`, `customer.spend_summary`,
`customer.spend_contributions`, `customer.provisional_activity`,
`attendance.weekly`, `inventory.lifecycle`,
`inventory.unique_item_evidence`, `inventory.valuation_coverage`,
`market.screener`, and `market.observation_drilldown`.

Their arguments, limits, target signatures and common response envelope are
normative in `TA_X8_IMPLEMENTATION_CONTRACT.md` sections "X8a exact target and
schema map" and "Common validation and envelope". Unknown operation, argument,
table or function names fail. Query-control context/cursor metadata is the only
allowed write; business state is unchanged.

`customer.spend_summary` dispatches to the X7f v2 full-dataset grid when
`window_mode` is present, while retaining the same operation string and the
reviewed legacy delegate when it is absent. The v2 route accepts aggregate
bounds, stable sort, JSON cursor, expected dataset revision and expected query
fingerprint. It rejects mixed v1/v2 cursor arguments and redacts customer names
when contact visibility is absent.

## Player identity ambiguity review

These are platform-admin review APIs, not organization-member catalog writers:

- `e10_platform_propose_player_identity_review(p_source_namespace text,p_source_key text,p_source_display_name text,p_proposer_kind text,p_proposer_name text,p_proposer_version text,p_source_evidence jsonb,p_candidates jsonb,p_reason text,p_evidence jsonb,p_idempotency_key text) -> jsonb`
- `e10_platform_reject_player_identity_review(p_case_id uuid,p_expected_revision bigint,p_reason text,p_evidence jsonb,p_idempotency_key text) -> jsonb`
- `e10_platform_player_identity_review_cases(p_status text DEFAULT NULL,p_limit integer DEFAULT 50,p_after_case_id uuid DEFAULT NULL) -> jsonb`

They require current platform-admin authority and preserve distinct UUID player
identities when display names match. Candidate confidence is explicitly known
with a numeric value in `[0,1]`, or unknown with null confidence. Model proposals
require a model version. Tables and decision history are append-only.

This contract deliberately has no approve, canonical-link, merge, split or
automatic-candidate-generation operation. Rejection does not mutate players or
provider mappings. An exact proposal replay returns the original proposal
operation result, so its returned status is historical and must not be treated
as a current case-status read after a later rejection. Use the bounded reader
for current state.

### Reviewable action drafts

- `e10_org_create_action_draft(p_org uuid,p_operation text,p_values jsonb,p_field_provenance jsonb,p_source_references jsonb,p_idempotency_key text)`
- `e10_org_amend_action_draft(p_org uuid,p_draft_id uuid,p_expected_revision integer,p_values jsonb,p_field_provenance jsonb,p_source_references jsonb,p_idempotency_key text)`
- `e10_org_preview_action_draft(p_org uuid,p_draft_id uuid,p_revision integer)`
- `e10_org_approve_action_draft(p_org uuid,p_draft_id uuid,p_expected_revision integer,p_idempotency_key text)`
- `e10_org_cancel_action_draft(p_org uuid,p_draft_id uuid,p_expected_revision integer,p_reason text,p_idempotency_key text)`
- `e10_org_commit_action_draft(p_org uuid,p_draft_id uuid,p_expected_revision integer,p_idempotency_key text)`

All return `jsonb`. Supported operations are only `purchase_order.create` and
`customer_transaction.create_draft`. Commit delegates to their ordinary writer
and rechecks its authority. Drafting, preview and approval are inert. There is
no arbitrary RPC, identity merge, receipt, posting, dispatch, or silent action.

### Dormant outbox protocol

- `e10_claim_outbox(p_org uuid,p_consumer_id uuid,p_limit integer,p_lease_seconds integer,p_idempotency_key text) -> jsonb`
- `e10_ack_outbox(p_org uuid,p_consumer_id uuid,p_outbox_id uuid,p_claim_token uuid,p_claim_generation integer,p_outcome text,p_retry_after_seconds integer,p_error text,p_idempotency_key text) -> jsonb`

These are `service_role` only, not browser APIs. Claim limit is 1..100 and lease
5..300 seconds. Ack outcome is `delivered`, `retry`, or `dead`; retry is
5..86,400 seconds and error text at most 2,000 bytes. No consumer is seeded.
Database acknowledgement is not proof of provider delivery.

## Fixtures and evidence

- Case-by-case trace: `TA_X1_X8_ACCEPTANCE_TRACE.md`
- Batch/evidence matrix: `TA_X1_X8_FINAL_ACCEPTANCE_MATRIX.md`
- X7e contract and evidence: `TA_X7E_REVIEW_CHECKLIST.md`,
  `TA_X7E_STAGING_EVIDENCE.md`
- X8 normative contract: `TA_X8_IMPLEMENTATION_CONTRACT.md`
- X8 evidence: `TA_X8A_STAGING_EVIDENCE.md`,
  `TA_X8B_STAGING_EVIDENCE.md`, `TA_X8C_STAGING_EVIDENCE.md`
- Final closures: `TA_X4H_X7F_STAGING_EVIDENCE.md`,
  `TA_F3_STAGING_EVIDENCE.md`, `TA_F4_STAGING_EVIDENCE.md`
- SQL and two-connection fixtures: `tests/ta_x1_*` through `tests/ta_x8_*`

## Unsupported and deferred behavior

Not supported by these APIs: arbitrary SQL/function execution, automatic
canonical identity merge, cross-shop pooling, live provider feeds, scheduled
monitoring, notifications, chatbot behavior, external dispatch, automatic
financial or price publication, payment/accounting recognition, or production
deployment. Wishlist storage is independent and not supplied by this handoff.
No client should infer these capabilities from a generic JSON field or a
service-role-only helper.
