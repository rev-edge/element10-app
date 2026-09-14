# TA-X6g native break sale capture plan

Status: focused plan for coordinator review. No implementation or environment change is authorized by this file.

## Authority and observed baseline

This slice implements the native-live-operation contract in `docs/EXPANSION_FRAMEWORK.md` lines 154-174 and the hold-versus-sale, refund/resale, native-then-imported and posting-permission acceptance cases. A board sale is provisional customer activity, never official spend, payment, settlement or accounting recognition. Holds, bids, assignment, slot creation and viewer/companion activity create no commercial activity.

The current client directly updates `e10_break_slots` and then separately inserts `e10_break_events`, so a sold slot and its event are not atomic. It also reuses the slot row for reopen/resell, which cannot be a durable sale identity. There is no current database sale writer to preserve. Existing slot/session RLS and `act.live_run` authority remain compatible; this slice adds explicit transactional RPCs without changing client code or widening viewer writes. The current client emits `spot_reopened`, but the database event constraint allows `spot_released`, not `spot_reopened`; the new contract uses the existing legal `spot_released` value and does not edit UI in this batch.

## Additive storage

Add immutable, organization-owned `e10_native_break_sales`. Each row has a generated sale UUID distinct from the slot UUID; organization, session and slot composite foreign keys; a monotonically increasing slot sale sequence; buyer user/handle snapshots; nullable resolved customer; identity status; quantity, gross price, currency, sale method, occurred time, incentives/raw evidence; the slot's prior price so release can restore rather than destroy a planned reference value; linked provisional activity, commercial event and legal `spot_sold` operational event; idempotency fingerprint; actor and recorded time. Unique constraints cover `(organization_id,id)`, `(organization_id,slot_id,sale_sequence)`, the linked activity/event IDs, and the idempotency key. A slot may therefore produce sale 1, be released, then produce sale 2 without overwriting sale 1.

Add immutable `e10_native_break_sale_transitions` for `committed` and `released` lifecycle facts. One root commit belongs to each sale and at most one release supersedes it. The current projection derives whether a sale remains active; neither sale nor provisional activity rows are rewritten on release. Both new public tables have RLS enabled, no client table policies, revoked `PUBLIC`/`anon`/`authenticated` access and service-role table grants. Append-only triggers reject update/delete.

Add `native_sale_revision bigint NOT NULL DEFAULT 0` to `e10_break_slots`. RPC calls use this monotonic revision for CAS rather than transaction-start timestamps. Each managed commit and release increments it and returns the new value. A security-invoker trigger protects every slot with native-sale history, active or released: authenticated direct updates to organization/session association, managed revision, state, buyer, price, sold time or incentives, and direct deletion are rejected. Legacy slots with no native-sale history keep their current direct-write behavior. This deliberately exposes the temporary client split: after a slot first uses the RPC, its sale lifecycle must continue through the RPCs. Full UI cutover is required before relying on universal native capture.

## Customer resolution and source identity

At commit time, resolve only evidence already authoritative:

- If `buyer_uid` maps through a current verified-handle identity decision and still-verified canonical handle claim to one active terminal customer, and a supplied handle identifies that same user/customer when present, snapshot that customer and `verified_auth`.
- Otherwise, if the supplied handle maps through one current reviewed channel identity to one active terminal customer, snapshot that customer and `reviewed_attributed`.
- Ambiguous, missing, stale, archived, nonterminal or buyer-user/handle-conflicting mappings remain `customer_id=NULL`, `buyer_identity_status='unresolved'`; the sale is retained for later reviewed attribution. Conflicting evidence never falls back to another person's reviewed handle.

No fuzzy name/price/time matching occurs. The native provisional activity uses `source_kind='native'`, `source_connection_id='live-break:' || session_id`, and `source_event_id='sale:' || native_sale_id`. Its commercial event uses the same source identity and `sale_committed` with `provisional_only=true`. An imported/manual observation retains its own source identity. Later review links the native activity to the posted line through the existing draft activity snapshot/posting path; an import reconciliation then links to that same posted line. Unique activity/source claims and one posted line per activity ensure the sale contributes once. Similarity alone never auto-links sources.

## Transactional writers

Add `e10_org_commit_native_break_sale` with explicit organization, session, slot, expected monotonic slot revision, buyer evidence, quantity, sale amount, currency, method, occurrence, bounded incentives/evidence and idempotency key. The sale amount is the known net hammer amount captured by the board; the provisional activity stores it as merchandise gross with an explicit known-zero discount. It is not an inference that an omitted imported discount was zero.

The function:

1. Authorizes active membership and `act.live_run` before locks.
2. Checks an organization-scoped native-sale receipt under its idempotency lock before mutable slot or identity checks, so an exact retry remains stable.
3. Acquires the organization customer-topology lock first, then locks the session and slot in deterministic organization/UUID order, rechecks authority, organization and session ownership, requires the session to be active, and requires the supplied monotonic slot revision plus a nonsold state. Session-end updates serialize on the same session row.
4. Resolves the buyer under the existing customer-topology/identity authority and snapshots the result.
5. Allocates the next per-slot sale sequence while holding the slot lock.
6. In one transaction updates the slot to sold and inserts the immutable sale, commit transition, provisional `e10_customer_activity_observations`, trusted native `sale_committed` event, legal `spot_sold` operational event, and receipt.

The result returns sale/activity/event IDs, sale sequence, identity status, resolved customer, updated monotonic slot revision, `posted=false`, `paid=false`, and replay state.

Add `e10_org_release_native_break_sale` with organization, session, slot, active sale ID, expected slot revision, reason/evidence and idempotency key. It uses the same authorization and lock order, requires the named sale to be the active sale for the currently sold slot, appends one release transition and legal `spot_released` operational event, then clears buyer, sold time and incentives, changes state to available and restores the pre-sale slot price. It preserves label, tier, method, band/configuration, team/player, plan, shipping and all other reference fields. It never deletes or negates the provisional activity and creates no refund or posted adjustment. A subsequent commit receives a new sale UUID and sequence. Exact retry returns the original release result; competing release/commit calls serialize.

Both RPCs are `SECURITY DEFINER` with pinned search paths, explicit self-authorization, revoked `PUBLIC`/anon and authenticated plus service-role execute grants. No default role receives a new capability. Existing direct slot policies, RPC signatures and capability flexibility remain unchanged; adopting the atomic RPC in the client is a later UI cutover, not part of this backend slice.

## Verification

The focused two-connection test will prove:

- hold/assignment/direct unsold setup creates zero sales and zero customer activities;
- one commit atomically changes the slot and creates exactly one sale, transition, activity and commercial event;
- exact retry is stable and changed-key reuse fails;
- simultaneous commits for one slot produce one winner and one CAS/state refusal;
- release followed by resale creates a second sale UUID/sequence while preserving the first;
- simultaneous release/resale cannot deadlock or create two active sales;
- commit versus identity detach/whole-record merge observes topology-first serialization and never snapshots stale customer authority;
- session end versus commit serializes, and an ended session cannot accept a sale;
- buyer user and verified handle map only through current verified evidence; reviewed handle mapping is exact; ambiguous/unresolved buyers are retained;
- archived, merged/nonterminal, revoked-claim and cross-organization customer evidence never becomes an authoritative resolved customer;
- foreign session/slot IDs, nonowner ordinary member, missing `act.live_run`, stale slot revision and malformed/nonfinite monetary inputs fail closed;
- viewer/participant identities cannot call either RPC and direct access to the new tables remains denied;
- no sale is marked posted/paid/settled and no customer transaction/line/adjustment is created;
- source tuple is exact and can be carried into the existing draft/post/reconciliation path without a second contribution;
- a real native activity is approved and posted through the existing draft workflow, then a later imported source is reconciled to that exact posted line without creating a second transaction contribution;
- generic activity and commercial-event writers cannot forge native provenance;
- full cleanup residue is zero, followed by clean replay, X6a-X6f regressions, A7, default privileges, exact-head CI and explicitly targeted staging evidence.

## Remainder after X6g

X6g closes atomic native sale capture only. Attendance remains separate evidence with bounded presence intervals, reconnect/device deduplication, heartbeat expiry, session bounds, source/coverage labels and no viewer commercial writes. TA-X7 still owns reportable eligibility, provisional-versus-posted separation, customer/session/product drill-down and the full native-plus-import double-count acceptance proof. No UI, live feed, scheduled monitor, chatbot, production or main-branch work is included.
