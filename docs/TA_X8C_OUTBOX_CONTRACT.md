# TA-X8c dormant outbox claim and acknowledgement contract

Status: local implementation candidate conforming to the approved
`TA_X8_IMPLEMENTATION_CONTRACT.md`. It starts no worker, scheduler,
notification, provider connection or external dispatch.

## Storage and authority

`e10_outbox_consumers` is a service-managed organization allowlist. A consumer
has a stable UUID and key, enabled status, and exact destination keys.
Consumer and destination keys are 1 through 160 bytes. The migration seeds no
consumer or entitlement.

The existing `e10_integration_outbox` retains its immutable effect identity of
`organization_id/commercial_event_id/destination_key` and gains nullable claim
owner, random token, integer generation, claimed time and lease expiry.
`e10_outbox_claim_commands` immutably stores idempotent claim requests and their
historical bounded results. `e10_outbox_acknowledgements` immutably stores
delivered, retry or dead database-protocol outcomes and their request receipts.

All three new relations have RLS enabled, zero client policies, and no `anon` or
`authenticated` grants. The two public functions are callable only by
`service_role`. This is a database protocol, not a client or model endpoint.

## Claim contract

`e10_claim_outbox(org, consumer, limit, lease_seconds, idempotency_key)` accepts
limits 1 through 100 and leases 5 through 300 seconds. It requires an active
organization and enabled consumer before target inspection and again after
blocking command work. Each selected row's exact destination entitlement is
rechecked after its row lock.

Eligible rows are pending or failed, due now when `next_attempt_at` is null or
reached, and unclaimed or expired. Deterministic ordering uses effective due
time, creation time and UUID. `FOR UPDATE SKIP LOCKED` permits disjoint bounded
batches while preventing two consumers from owning one live generation. A fresh
wall clock after each selected row lock determines eligibility and expiry.
Claiming assigns a new token and generation and increments `attempt_count` once,
with explicit integer-overflow refusal.

The command fingerprint covers contract version, organization, consumer, limit
and lease. Changed reuse fails. Exact replay rechecks active organization,
consumer and every recorded destination, returns the immutable historical IDs,
tokens, generations and expiries, and never renews a lease. It reports
`authoritative=true` only while every recorded token is still the current
unexpired claim; an empty or stale historical result is non-authoritative.

## Acknowledgement contract

`e10_ack_outbox(org, consumer, outbox, token, generation, outcome,
retry_after_seconds, error, idempotency_key)` accepts these exact outcomes:

- `delivered`: no retry or error, sets `delivered_at`;
- `retry`: a 5 through 86,400 second delay and nonempty error, sets failed and
  the next-attempt time; or
- `dead`: no retry time and a nonempty error, sets terminal dead.

Error text is at most 2,000 bytes. The immutable fingerprint includes contract
version, scope, row, token, generation, outcome, retry interval and SHA-256 error
digest. Ack and reclaim serialize on the outbox row. After the row lock, a fresh
wall clock and fresh active-organization, consumer and destination checks apply.
Only the current owner, token and generation may acknowledge before expiry.

Every outcome clears owner, token, claimed and expiry fields. Delivered clears
error/retry and sets delivery time. Retry and dead keep delivery time null and
set bounded error state consistently. Exact idempotency replay rechecks current
authority and returns its immutable acknowledgement receipt even though the
token was cleared. It performs no second state transition. Without that receipt,
expired, cleared or replaced tokens fail.

Database acknowledgement does not prove provider-side delivery or external
exactly-once behavior. Any future dispatcher must use the immutable
organization/event/destination identity as its provider-side replay key and pass
a separate credential, network, retry and operational review.

## Deliberate exclusions

TA-X8c includes no daemon, cron entry, queue poller, Edge Function, webhook,
provider credential, network request, notification, automatic retry schedule,
dead-letter automation or UI. Local and staging tests use isolated fixtures and
remove them after execution.
