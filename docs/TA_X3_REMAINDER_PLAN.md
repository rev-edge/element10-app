# TA-X3 purchasing workflow remainder plan

Status: plan for review. No migration or environment change is authorized by this file.

Authorities: `EXPANSION_FRAMEWORK.md` PUR-01 through PUR-06,
`EXPANSION_ACCEPTANCE_CASES.md`, `TRACK_A_EXPANSION_PLAN_2026-09-10.md`, and
the existing TA-X2, TA-X3a/X3b, and TA-X4 migrations. Existing approval,
tenant-isolation, immutable-history, bounded-read, and idempotency rules remain
binding.

## Existing foundation

TA-X3a already separates purchase orders, supplier invoices, stock receipts,
supplier credits, their lines, explicit allocation relations, and audience-typed
comments. TA-X3b supplies immutable revision tables. These tables are
client-closed except for existing direct organization-scoped SELECT policies.
Those policies are not bounded read APIs. The tables do
not yet provide authoritative workflow writers, allocation conservation, or a
vendor-safe comment projection.

TA-X4 already owns receipt posting, lot creation, receipt reversal, and expected
or received supply commitments. X3 must call or coexist with those contracts. It
must not create inventory from invoice approval, fabricate a PO for invoice-only
intake, or introduce a second inventory writer.

## Authority and common writer rules

- Install additive capabilities `act.purchasing_prepare`,
  `act.purchasing_approve`, and `act.purchasing_cancel`. They receive no default
  role grants. Prepare authorizes document creation, amendment, submission,
  matching, and comments; approve authorizes approval; cancel authorizes
  cancellation or void. This preserves the approved separation between
  purchasing and `act.create_receiving` and keeps authority configurable. If the
  owner requires a different split or names, that is a stop condition before
  implementation rather than permission to reuse receiving authority.
- Financial document and cost reads continue to require the existing settled
  financial-read contract. A mutation capability does not imply financial read.
- Every public writer is `SECURITY DEFINER`, explicitly organization-scoped,
  self-authorizing, `anon`/`PUBLIC` closed, and bounded. Internal helpers remain
  client-closed.
- Every command takes an idempotency key. The server derives the fingerprint
  from canonical typed operation, organization, and payload. A supplied digest,
  if accepted for compatibility, is verified against the server digest and is
  never authoritative. An existing same-key/same-fingerprint result is returned
  after rechecking current caller authority, even if the document later changed;
  stale-CAS validation occurs only for a new command. Same-key/different-payload
  fails. Authority is repeated after the logical lock.
- Every amendment or status change uses an expected revision. The header/lines,
  incremented revision, immutable full snapshot, status, reason, and command
  receipt commit atomically. A stale expected revision fails without residue.
- Each successful document mutation also appends a guarded native commercial
  event in the same transaction. Event schema, subject link, correction lineage,
  request fingerprint, and lifecycle payload are validated by the accepted X5
  envelope. The command does not call a separately authorized public event RPC.
- All numeric input must be finite as well as positive/nonnegative. `NaN` and
  infinities fail before writes. Arrays and text fields have explicit bounds.
- Supplier, destination, configuration, currency, source identity, and all
  allocated documents are revalidated in the explicit organization at commit.
  `current_org()` is not used to infer tenant identity.
- All X3 and X4 operations touching a purchasing document use one common ordered
  protocol: logical operation key, document header row, document lines ordered by
  ID, allocation rows ordered by their full key, then receipt/expected-supply
  rows ordered by ID. Existing X4 writers must be wrapped or corrected to follow
  the same ordering before X3 reduction/cancel or allocation release is exposed.
  Stable referenced line IDs are never rebuilt or deleted.

## Implementation checkpoints

### TA-X3c: purchase-order lifecycle

Add idempotent create, amend, submit, approve, and cancel commands. Create and
amend accept bounded typed lines. They require an active supplier, an active
authorized destination, active configuration versions in the same organization,
finite quantities/cost estimates, unique positive line numbers, and one currency
for the document. Zero eligible destinations blocks creation. If exactly one is
eligible it may be returned by a separate bounded suggestion query, but commit
still receives and rechecks the explicit location ID.

PO transitions are exact: `draft -> submitted -> approved`; `draft`, `submitted`,
or `approved` may become `cancelled`; an approved PO may become `closed` only
when the existing receipt/commitment contract proves no remaining expected work.
Draft is editable. Submitted amendment returns the same command atomically to
`draft`. Approved amendment creates a new revision and returns to `submitted`,
invalidating the prior approval. Existing X4 receiving remains legal from
`submitted` or `approved`; X3 does not imply that receipt requires PO approval.

Each command appends a complete PO revision and native lifecycle event.
Amendment never mutates a revision. Cancellation/reduction uses the shared X4
lock protocol. It is blocked below net received or where active allocations
would be stranded; this checkpoint does not invent automatic release.
Supplier/configuration/destination/currency changes after matching or receipt
are rejected. It changes no received inventory and retains ordered/received
history. More permissive over-receipt behavior is not inferred.

### TA-X3d: invoice, credit, and allocation workflows

Add separate idempotent create/amend/review/approve/void commands for supplier
invoices and credits. Invoice-only creation is legal and carries no PO ID.
Invoice and credit transitions are exact: `draft -> reviewed -> approved`, and
any of `draft`, `reviewed`, or `approved` may become `void` only when allocation
effects have been explicitly and atomically released or corrected. Draft is
editable. Amending reviewed or approved content creates a new revision and
returns it to `reviewed`, invalidating prior approval; there is no `submitted`
invoice/credit state. Approval appends a revision and event but creates no
receipt, lot, movement, inventory, payment, or PO. Credits remain separate
additive commercial documents; a shortage does not create one automatically.

Add atomic allocation commands for invoice-line to PO-line and credit-line to
invoice-line matching. Under ordered logical locks, validate same organization,
supplier, exact configuration where applicable, compatible currency, mutable
document states, and finite positive quantities/amounts. Enforce aggregate
conservation across existing plus proposed allocations so concurrent commands
cannot allocate more than the source line or target eligible amount/quantity.
Partial and split allocations are legal. Release/correction is additive and
auditable, not an in-place silent re-point. If the existing allocation tables
cannot represent that history, add decision/event rows rather than deleting
prior evidence. Allocation/comment operations state whether they affect the
document revision and approval: financial matching changes append a new document
revision and invalidate approved status; comments do not change financial
revision or approval but append their own event.

Connected-document identity remains organization + source connection + external
document ID, with server fingerprint reconciliation. Manual invoice/credit
identity is organization + supplier + normalized supplier document number;
missing manual document numbers require an explicit duplicate-review outcome,
not silent uniqueness. Existing identity with changed content enters a reviewed
reconciliation failure and is not overwritten.

Amounts preserve PostgreSQL `numeric` precision and are never implicitly rounded
by these commands. `NaN` and infinities are rejected. Any future currency-scale
or rounding rule requires owner direction before quantization is introduced.
Unknown optional amounts remain NULL, distinct from zero. Allocation conservation
applies only to known eligible amounts/quantities and fails closed when a
required basis is unknown.

Do not implement payment, accounting recognition, currency conversion,
unapproved tolerance, or automatic invoice-to-receipt behavior.

### TA-X3e: comment workflow and projections

Add an append-only comment command requiring `act.purchasing_prepare`, explicit
organization, exactly one supported document reference, and `internal` or
`vendor` audience. A superseding comment must be in the same organization, on
the same document, and in the same audience chain. Bound body length and reject
blank content. A partial unique current-leaf constraint plus the document/chain
lock prevents concurrent successors from forking one comment chain.

Add bounded member-authorized internal history and a separate vendor-output
projection. Vendor output selects only allowlisted document fields and effective
`audience='vendor'` comments. It must not expose internal bodies, supersession
metadata that reveals internal rows, actor/audit fields, hidden costs, raw
  snapshots, or unallowlisted JSON metadata. No vendor delivery channel is built.

### TA-X3f: supplier purchasing workspace reads

Add cursor-bounded, explicit-organization reads for supplier-linked purchase
orders, invoices, receipts, credits, and exact underlying IDs. Operational PO
and receipt headers follow their existing member-read contract; amounts, costs,
allocations, invoice/credit details, and derived measures require the settled
financial-read authority. Return separately labeled open commitments, approved
invoiced amounts net of approved credits, and unused approved credit. Payment is
returned as unavailable/not modeled, never inferred from invoice approval.
Ordered value is never labeled spend or lifetime spend.

Reuse the exact accepted actual-cost query for PUR-02: exact supplier,
configuration version, accepted non-reversed receipt evidence, currency, source,
and date, with deterministic validated conversion only. X3 adds no client-side
autofill behavior. Manual values remain explicit and are never overwritten.

## Required proof packet

Map tests explicitly to PUR-01 through PUR-06 and include:

- allowed creator, org admin, ordinary member, suspended member, no-membership,
  multi-membership, and foreign-organization cases;
- exact-backend concurrent idempotency and post-lock authority-revocation tests;
- stale revision, changed fingerprint, invalid transition, and zero-residue
  failures;
- authorized destination recheck, sole destination, zero destination, active
  supplier/configuration, non-card core configuration, and tenant isolation;
- finite numeric rejection and bounded input/read behavior;
- invoice-only intake without a fabricated PO or stock effect;
- identical duplicate import replay and changed-payload reconciliation failure;
- one invoice across two POs and two invoices against one PO, with aggregate
  conservation under concurrency;
- amend versus receive, cancel versus expected allocation, and reallocate versus
  void races using the shared X3/X4 lock order, with net reversals/releases and
  no stranded allocation;
- PO estimate versus accepted-receipt actual-cost separation and manual-value
  preservation;
- immutable snapshots for every mutation, invalidated stale approval, and full
  retained history;
- vendor projection containing the vendor instruction and proving the internal
  secret absent from every returned field;
- supplier workspace pagination, permission-filtered financial fields, exact
  source links, separately labeled commitments/net credits/unused credits, and
  explicit unavailable payment data;
- local clean replay, focused regressions, default-privilege probe, exact-head
  CI, explicit staging apply and rollback/cleanup proofs, advisor delta, and
  production read-only proof.

## Explicit stop conditions

Stop for owner direction before capability migration if the proposed
prepare/approve/cancel split or names are not accepted. Also stop rather than
inventing accounting recognition, payment
rules, landed-cost allocation method, over-receipt authority or tolerance,
automatic vendor credits, currency conversion, cross-shop pooling, capability
namespace replacement, or production deployment. Direct/no-PO receiving and
multi-line receipt/reversal remain TA-X4 work, not a reason to fabricate PO state
inside X3.
