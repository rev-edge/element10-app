# TA-X7c provider-time normalization plan

Status: implementation-ready plan for independent review. No migration or
environment change is authorized by this document alone.

## Authority and boundary

This sub-batch implements X7c from `TA_X7_REPORTING_PLAN.md` and the attendance
cases in `EXPANSION_ACCEPTANCE_CASES.md`. It consumes only dormant, typed
`authorized_platform` fixture/import evidence already accepted in X6h. It does
not enable a connector, collector, feed, scheduled process, client telemetry or
production write. Companion and provider evidence remain separate sources.

## Interpretation contract

The authoritative ordering key is
`(provider_occurred_at, provider_event_id, event_id)` within the exact
`(organization_id, provider_key, session_id, subject_key, connection_id)`
stream. `server_received_at` is provenance and a late-arrival input only. It is
never substituted for missing provider occurrence time.

Before transition interpretation, follow append-only `corrects_event_id`
lineage to the single current leaf, with a hard traversal-depth and row-count
bound. A corrected event is retained in drill-down but excluded from the
effective sequence. Cycles, branching leaves, a target in another stream, or an
effective row that lacks a finite provider occurrence time are quarantined.
The X6h writer checks cross-stream correction targets, but no FK encodes that
rule, so the normalizer independently validates it. Existing indexes prevent
duplicate provider event identities.

The normalized state machine is:

- `join` while closed opens an interval;
- before each next provider-time event, an open interval expires at the last
  qualifying heartbeat plus the reviewed expiry; a later heartbeat or leave
  cannot bridge the expired gap;
- `heartbeat` while open extends evidence but does not create another interval;
- `leave` while open closes at provider occurrence time;
- events sharing the same provider timestamp with conflicting kinds are
  `same_time_conflict`; lexical UUID order is never treated as semantic proof;
- an exact duplicate semantic event is quarantined rather than counted twice;
- `heartbeat` or `leave` while closed is `missing_join`;
- `join` while open is `duplicate_join` unless a reviewed correction removes
  the conflicting predecessor;
- a leave earlier than its opening join is `negative_interval`;
- a join with no later heartbeat/leave expires from the join time itself;
- an open interval is bounded by the earliest of the last qualifying event plus
  the policy heartbeat expiry, session end, policy effective bound, retention
  expiry and observation cutoff;
- an ended session without a trustworthy bound is quarantined, not stretched
  to ingest time.

Provider times after `server_received_at`, after the observation cutoff, or
outside the session/policy/retention window are quarantined as
`future_provider_time` or the corresponding bounded-window reason. Negative
receipt lag never becomes duration evidence. Every emitted half-open interval
is clipped to all applicable session, policy, retention and observation bounds.

Late arrival is explicit: `server_received_at - provider_occurred_at` is
returned, and rows beyond the selected policy's finite late-arrival bound are
`late_beyond_policy`. This plan does not invent that bound from the existing
heartbeat setting. The approved normalization policy below carries it.

## Additive structures

### Reviewed normalization policies

Add immutable `e10_provider_presence_normalization_policy_decisions`, keyed by
organization, provider and monotonic revision. Each decision records `enable`,
`supersede` or `revoke`, finite effective interval, heartbeat expiry, maximum
late-arrival interval, review reason, reviewer, review time, predecessor,
idempotency key and fingerprint. A service-only current-state view selects the
latest valid decision for a requested historical instant. No mutable enabled
flag or partial unique index is used. Revocation and supersession preserve all
prior policy rows and their historical effective windows.

Configuration uses a public authenticated capability writer with advisory
serialization, expected-current-revision CAS, bounded inputs, idempotency and
post-wait authority rechecks. Add
`act.configure_attendance_normalization` to the allow-list but seed no grants;
organizations grant it explicitly through the existing role-permission model.
Reading normalized attendance continues to use `act.view_customer_engagement`
and does not imply configuration authority.

Every normalization run must also select current reviewed X7a
`e10_current_attendance_coverage_assertions` for the exact organization,
`source_class='authorized_platform'`, provider and interval. Only asserted
covered instants can produce reportable intervals. `partial` and `unavailable`
gaps, collection-disabled policy periods, and expired-retention spans are
excluded and counted. A coverage label or normalization policy never implies a
complete denominator; X7a complete-window rules remain authoritative.

### Immutable normalization runs

Add `e10_provider_presence_normalization_runs` and
`e10_provider_presence_normalized_intervals`. A run binds organization,
provider, policy version, finite observation cutoff, input reporting revision,
algorithm version, creator, idempotency key/fingerprint and completion counts.
Intervals retain session, stream, subject, connection, original/effective
customer identity, half-open provider-time range, source event IDs, expiry
reason and policy/version provenance. Runs and intervals are append-only and
service-only. They are rebuildable projections, never replacements for raw
events.

Add `e10_provider_presence_quarantine_rows` to the run output with exact event
and stream identity, bounded reason code and bounded evidence IDs. Quarantine is
visible through reporting but cannot be promoted by editing the row. A later
corrected input, coverage assertion, attribution or policy creates a new run.

## Writers and bounded reads

Add a service-role-only normalization runner for one explicit organization,
provider, policy version and observation cutoff. It takes a hard maximum event
count and refuses an input set above the bound rather than silently truncating.
It serializes per organization/provider/cutoff, captures the presentation
reporting revision, rechecks the current policy and coverage, and materializes
one immutable run atomically. Each run stores a deterministic dependency
fingerprint over only its provider, selected cutoff/window, effective raw-event
and correction leaves, policy decision, coverage assertions, relevant
attribution/effective-customer decisions, session bounds and retention inputs.
The service-only current-run view recomputes and matches that dependency
fingerprint. A correction invalidates only runs whose dependencies changed;
normalizing provider B or another cutoff does not invalidate an otherwise-current
provider-A run. Multiple providers and cutoffs can therefore coexist.

The ordinary org reporting revision remains the presentation/pagination
watermark and advances when a completed run becomes available. That bump makes
old client cursors restart but is not itself a run-freshness dependency. A read
requires both a matching run dependency fingerprint and a current presentation
revision captured under one snapshot. If no run exists or its fingerprint is
stale, the RPC returns an explicit `unavailable_rebuild_required` status with no
zero-valued attendance claim. Identical idempotent runner replay returns the same
run; same key with a different fingerprint fails. Input event and lineage scans,
intervals and evidence arrays all have explicit hard bounds and fail rather than
truncate.

Add authenticated bounded reads:

- provider normalized interval detail, with explicit org, provider, session,
  customer, finite window/cutoff, limit and server-resolved cursor;
- provider quarantine detail with reason filter, limit and server-resolved
  cursor; and
- source-separated attendance summary that labels provider and companion rows
  independently and never unions their seconds into one unlabeled number.

Reads require active membership and `act.view_customer_engagement`, resolve
current effective-customer attribution without exposing raw attendee keys, bind
cursors to org/query/revision/cutoff, and reject a stale revision. Service-only
drill-down may include the raw provider attendee key for reviewed operations.
No RPC returns contact fields or customer financials.

## Reporting revision and concurrency

The existing reporting revision must advance for normalization policy changes
and completed normalization runs. A read locks the revision and rechecks
authority after every possible wait before returning. A runner rechecks service
authority/policy after advisory and revision locks. Exact-backend tests cover:

- policy authority revoked while its writer is blocked;
- reader authority revoked while blocked on the reporting revision;
- raw provider correction arriving while a run waits, causing stale-input
  rejection or inclusion only under the new revision; and
- two identical runner retries producing one run; and
- provider A and B runs and two distinct cutoffs coexist as current; a relevant
  correction, coverage, policy, attribution or session change invalidates only
  the affected dependency fingerprint and yields
  `unavailable_rebuild_required`, never silent empty/zero output.

## Required fixtures and acceptance

The focused test uses two organizations and no live provider:

1. Events arrive out of order but normalize by provider time. Because the X6h
   public ingest deliberately rejects a first non-join, arbitrary-order cases
   use a service-only test fixture/import loader; no broader public intake is
   claimed or added.
2. A correction replaces an earlier event without deleting either raw row.
3. A delayed leave closes at provider time, not receipt time.
4. Duplicate join, duplicate provider identity, missing join, same-time conflict
   and invalid transition remain quarantined with exact reason codes. The
   normalizer repeats the cross-stream correction defense.
5. Two connections overlap and remain distinct in provider drill-down; any
   customer-level union uses multirange union and counts overlap once.
6. Provider and companion summaries remain separately labeled.
7. No enabled reviewed policy means zero reportable intervals.
8. A row outside the policy late-arrival bound, a future/negative-lag row, a
   join-only expiry and a heartbeat/leave after expiry are handled without
   bridging silence. Session, policy, retention and cutoff clipping are exact.
9. A foreign-org member, missing-cap member and `anon` caller learn nothing.
10. Pagination uses the full stable tuple and rejects arbitrary, foreign and
    stale cursors.
11. Every run-owned fixture is removed and org0 sentinel/baseline remains.
12. Coverage gaps, unavailable assertions and collection-disabled periods do
    not emit reportable intervals or manufacture a complete denominator.
13. Per-dependency current-run freshness, multi-provider/multi-cutoff coexistence,
    explicit rebuild-required status and bounded lineage/input failure are
    proven.

## Delivery and stop boundary

Implementation is one additive schema/policy migration plus focused functional
and exact-lock concurrency tests wired into CI. Verification requires clean
local replay, X6h/X7a/X7b regressions, A7, default privileges, independent
review, exact-head CI, explicit staging apply, staging tests, advisor/lint delta,
zero run-owned residue and read-only production proof. Stop at the X7c boundary
before X7d.
