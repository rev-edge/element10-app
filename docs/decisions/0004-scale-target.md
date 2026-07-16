# 0004 — Scale Target (Foundation Gate, Track A step 5)

**Status:** Accepted (v1.1, 2026-07-16). Supersedes the v1.0 draft; all v1.0 open confirmations resolved by Trent.
**Context:** Architecture is designed for the CEILING; load tests validate the nearest MILESTONE with measured
headroom. This record fixes the numbers so A6 (tenancy), A8 (bounded reads), A9 (realtime), and A10 (load test)
optimize against one target instead of guessing.

## The ceiling (~18-month ambition)

| Dimension | Target |
|---|---|
| Organizations | 2,000-3,000 max |
| Members per org | 12-15 (streamer + staff) → ≈ 24k-45k member accounts |
| Viewers | Separate, larger, platform-global pool (scales with audience, not orgs) |
| Simultaneous live shows | 1,000-1,500 peak (Friday night) |
| Concurrent viewers per show | 30-100 |
| Selling pace | 5-10 spots/min PER SHOW at peak (confirmed per-show) |
| Inventory items per org | thousands (≈ 10M rows platform-wide) |
| Orders per org per week | 1 major + ~a dozen smaller |
| Live-action latency | "Instant" → two budgets, below |
| Availability | 99.9% during live hours (M1/M2); revisit 99.95% at ceiling |

## Derived loads at ceiling
- **Write rate:** 1,250 shows × ~7 spot-sales/min ≈ **146 mutations/sec** platform peak (each = a transactional
  RPC: slot + movement + receipt). This is an aggregate throughput number, NOT a contention number: 7/min per
  show is 0.12/sec per show, so no single row is ever hot (contention is sharded by slot and item). Postgres
  handles 146/sec comfortably with the A4 indexes and org-leading composite keys. The number has built-in
  conservatism: it assumes all 1,250 shows peaking simultaneously, which never happens.
- **Realtime fanout (the A9 decider):** operator/overlay surfaces ≈ 2-3 conns/show ≈ 4k. If viewers use
  companion pages: +30-100/show → **40k-150k concurrent subscribers.** Postgres Changes is single-threaded and
  Supabase advises Broadcast beyond ~3k subscribers on a change stream, so audience-facing realtime is
  Broadcast-only at ceiling. Companion adoption (the 40k-vs-150k swing) is instrumented from day one.
- **Data volume:** ~10M inventory rows, movements a multiple. Fine for Postgres; load-bearing for A8 (cursor
  pagination + org-leading indexes) and for viewer-scoped reads (buyer-leading indexes, see below).
- **Connections:** 100k+ concurrent realtime is beyond Pro defaults → a Supabase Team/Enterprise + quota
  conversation at genuine ceiling. A known invoice on the road to 3,000 orgs, not a today problem.

## Milestones (what actually gets load-tested)

| | M1 (beta) | M2 (growth) | Ceiling |
|---|---|---|---|
| Orgs | 10 | 100 | 3,000 |
| Concurrent shows | 5 | 50 | 1,500 |
| Concurrent realtime subs | ~500 | ~5,000 | 150,000 |
| Peak mutations/sec | ~1 | ~6 | ~145 |

A10's stress test runs at **2× M2 on the mutation path** (100 shows, ~12 mut/sec) with headroom projected toward
ceiling. **The fanout path is tested to a HIGHER multiple** than the mutation path, because subscribers-per-channel
has discontinuities (Postgres Changes → Broadcast → connection-tier quota) where the mutation path scales smoothly.

## Decision: the two-principal identity model
Two principal types, two isolation models. **A6 builds to this; it is not org-uniform.**

- **Members** (streamer + staff, 12-15/org): org-scoped. RLS isolates every member read/write by
  `organization_id`. Onboarded by admin invite.
- **Viewers/buyers:** a **platform-global identity** — one self-serve signup, then read-only companion access to
  ANY streamer on the platform. Never an `e10_member`. Access to a given org's live data is granted **by session
  participation, not membership** (`e10_session_viewers` link or slot buyer match), via `e10_can_read_session`.
  A viewer has no home org and never receives org-scoped RLS.

The current schema (`e10_viewers`, `e10_session_viewers`, `e10_can_read_session` with buyer_uid/handle matching)
already encodes this split; A6 formalizes it.

## Binding consequences
1. **A9 is Broadcast-first** for anything a viewer touches. Broadcast is emitted **from the database** (a
   `realtime.send` inside the mutation RPC, not from the operator's browser), so the fanout reflects committed
   state and stays correct with multiple operators or a flaky client. The session model (A6) must make the
   channel name derivable inside the RPC. Broadcast channel authorization reuses `e10_can_read_session`, so a
   viewer's access is uniformly session-scoped across both Postgres reads and Broadcast.
2. **A6 indexes: two families.** Member hot paths lead with `organization_id`; idempotency keys scoped
   `(org, key)`. **Exception:** viewer-facing cross-streamer reads (a viewer's own history) lead with
   `buyer_uid` / `(buyer_uid, created_at)` — a global viewer has no org to lead with.
3. **Cross-org privacy is an explicit invariant.** The same viewer appears in many orgs' `session_viewers`/`slots`
   rows; org A must never see that viewer's org-B activity. Holds iff those rows carry `organization_id` and
   member RLS filters on it, while the viewer's aggregate view is a viewer-authenticated query keyed by their own
   uid. Add an `rls_test` case: a member of org A cannot read a viewer's org-B participation.
4. **"Instant" = two latency budgets, measured separately in A10.**
   - Operator mark-sold / consume / reserve round-trip: **≤150 ms perceived, ≤300 ms P95** server round-trip.
   - Audience-perceived update (commit + Broadcast fanout + client render, up to 150k subs): its own budget,
     and the one that actually defines "instant" for viewers. CI gains a latency assertion at A10 for both.
5. **Whatnot-handle linking is the attribution join** and a first-class, verified A6 step (how a global viewer's
   purchases attribute to one account across streamers).
6. **Custom SMTP** is driven primarily by high-volume viewer self-serve signup (not member invites) — folded
   into A6 onboarding. Availability SLO needs "live hours" defined concretely, with the error budget weighted
   toward protecting peak windows rather than spread evenly (a Friday-night outage is the expensive failure).

## Out of scope for this record
No A6/A8/A9/A10 implementation. This fixes the target and the identity model those steps build against.
