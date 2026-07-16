# 0004 — Scale Target (Foundation Gate, Track A step 5)

**Status:** Accepted (v1.2, 2026-07-16). Supersedes v1.0/v1.1. **All A5 confirmations resolved by Trent.**
v1.2 (A5.1 correction pass): capacity claims restated as hypotheses with a real test method; realtime tiers
corrected; the two-tier viewer contract hardened; live-hours defined; audience latency budget + optimistic UI adopted.
**Context:** Architecture is designed for the CEILING; load tests validate the nearest MILESTONE with measured
headroom. This record fixes the numbers + the identity/authorization model so A6 (tenancy), A8 (bounded reads),
A9 (realtime), and A10 (load test) optimize against one target instead of guessing.

## The ceiling (~18-month ambition)

| Dimension | Target |
|---|---|
| Organizations | 2,000-3,000 max |
| Members per org | 12-15 (streamer + staff) → ≈ 24k-45k member accounts |
| Viewers | Separate, larger, platform-global pool (scales with audience, not orgs) |
| Simultaneous live shows | 1,000-1,500 peak |
| Concurrent viewers per show | 30-100 |
| Selling pace | 5-10 spots/min PER SHOW at peak (confirmed per-show) |
| Inventory items per org | thousands (≈ 10M rows platform-wide) |
| Orders per org per week | 1 major + ~a dozen smaller |
| Live-action latency | "Instant" → two budgets (operator ≤300 ms P95; audience ≤1 s P95), below |
| Availability | **99.9% (M1/M2), revisit 99.95% at ceiling — measured 24/7 (see Live hours)** |

## Derived loads at ceiling — HYPOTHESES until proven
Capacity numbers below are **projections, not measurements.** Two load-bearing caveats: (a) the org-leading
composite indexes these assume **do not exist until A6**; (b) the mutation ceiling is **unproven until A10**.
- **Write rate (hypothesis):** 1,250 shows × ~7 spot-sales/min ≈ **146 mutations/sec** platform peak (each = a
  transactional RPC: slot + movement + receipt). This is an aggregate-throughput number, NOT a contention number:
  7/min per show is 0.12/sec per show, so no single row is hot (contention is sharded by slot + item). Expected to
  be comfortable for Postgres *once A6's org-leading indexes exist*; 146/sec also bakes in conservatism (assumes
  all 1,250 shows peaking at once, which never happens).
- **Realtime fanout (the A9 decider):** operator/overlay surfaces ≈ 2-3 conns/show ≈ 4k. If viewers use companion
  pages: +30-100/show → **40k-150k concurrent subscribers.** Postgres Changes is single-threaded (Supabase advises
  Broadcast beyond ~3k subscribers on a change stream), so audience-facing realtime is Broadcast-only at ceiling.
  Companion adoption (the 40k-vs-150k swing) is instrumented from day one.
- **Realtime connection tiers (corrected; quotas change — verify against current Supabase docs at each milestone):**
  Pro defaults to **~500** concurrent realtime connections; Pro-without-spend-cap / Team list **~10,000**. So
  **M2's ~5,000 subs already requires a config bump or higher tier** (bites at M2), and **150k at ceiling requires
  an Enterprise / custom-capacity agreement** (bites approaching ceiling). Both recorded as known dependencies.
- **Data volume:** ~10M inventory rows, movements a multiple. Fine for Postgres; load-bearing for A8 (cursor
  pagination + org-leading indexes) and for viewer-scoped reads (buyer-leading indexes, below).

## Milestones (what actually gets load-tested)

| | M1 (beta) | M2 (growth) | Ceiling |
|---|---|---|---|
| Orgs | 10 | 100 | 3,000 |
| Concurrent shows | 5 | 50 | 1,500 |
| Concurrent realtime subs | ~500 | ~5,000 | 150,000 |
| Peak mutations/sec | ~1 | ~6 | ~145 |

**A10 method = a stepped load curve, not extrapolation.** Drive mutations at **12 → 25 → 50 → 100 → 145 /sec**,
stopping at the first SLO or resource breach; at each step record **p95/p99 latency, error rate, lock waits,
connection-pool utilization, DB CPU, and reconciliation drift.** Passing 12/sec certifies **M2 acceptance only** —
it says nothing about the ceiling. The **fanout path is load-tested to a higher multiple than the mutation path**,
because subscribers-per-channel has discontinuities (Postgres Changes → Broadcast → connection-tier quota) where
the mutation path scales smoothly.

## Decision: the two-principal identity model
Two principal types, two isolation models. **A6 builds to this; it is not org-uniform.**
- **Members** (streamer + staff, 12-15/org): org-scoped. RLS isolates every member read/write by `organization_id`.
  Onboarded by admin invite.
- **Viewers/buyers:** a **platform-global identity** — one self-serve signup, then read-only companion access to
  ANY streamer. Never an `e10_member`. Access to an org's live data is by **session participation, not membership**.
  A viewer has no home org and never receives org-scoped RLS.

The current schema (`e10_viewers`, `e10_session_viewers`, `e10_can_read_session` with buyer_uid/handle matching)
already encodes this split; A6 formalizes it.

## Decision: the two-TIER viewer authorization contract (hardened)
`e10_can_read_session` is **necessary but not sufficient** — it authorizes *shared* participation, never private
data. Two tiers, named so A9 implements them literally:
- **Spectator surface:** any authenticated viewer may read a live session's **public** state, but **only through
  an explicitly allowlisted projection** (a safe RPC / view / dedicated public-state table). Spectators get **no
  direct SELECT** on mixed-sensitivity tables — `e10_break_slots` carries `buyer_uid`, buyer handles, pricing, and
  shipping state/notes. **Every field on the spectator surface is individually classified public;** buyer handles
  are exposed only if explicitly classified public.
- **Participant-private data:** a viewer's own rows (their purchases, fulfillment) require **direct ownership** —
  `buyer_uid = auth.uid()` (or an equally strong verified-account predicate), never merely session participation.
- **Broadcast (A9) consequence:** a **public session topic** (spectator-authorized) **and** **participant-private
  payloads** (ownership-authorized) — **never one channel carrying mixed payloads, never a single broadened
  predicate.** (This supersedes v1.1's "Broadcast reuses `e10_can_read_session`", which was too broad.)

## Binding consequences
1. **A9 Broadcast is emitted from the database** (a `realtime.send` inside the mutation RPC, not the operator's
   browser), so fanout reflects committed state and stays correct with multiple operators / flaky clients. The A6
   session model must make the channel name derivable inside the RPC. Channel authorization follows the two-tier
   contract above (spectator topic vs ownership-gated private payloads).
2. **A6 indexes: two families.** Member hot paths lead with `organization_id`; idempotency keys scoped `(org, key)`.
   **Exception:** viewer-facing cross-streamer reads (a viewer's own history) lead with `buyer_uid` /
   `(buyer_uid, created_at)` — a global viewer has no org to lead with.
3. **Cross-org privacy is an explicit invariant.** The same viewer appears in many orgs' `session_viewers`/`slots`
   rows; org A must never see that viewer's org-B activity. Holds iff those rows carry `organization_id` and member
   RLS filters on it, while the viewer's aggregate view is a viewer-authenticated query keyed by their own uid.
   Add an `rls_test` case: a member of org A cannot read a viewer's org-B participation.
4. **"Instant" = two latency budgets, measured separately in A10.**
   - **Operator** mark-sold / consume / reserve round-trip: **≤300 ms P95** server round-trip.
   - **Audience-perceived** update (commit + Broadcast fanout + client render, up to 150k subs): **≤1 s P95**
     (event → viewer's companion/overlay render) for M1/M2, revisited at A9. This is the budget that actually
     defines "instant" for viewers.
   - **Optimistic UI is an explicit new-shell requirement:** the "150 ms perceived" operator feel is
     **client-rendered optimism reconciled against the ≤300 ms server P95**, not a server budget.
5. **Whatnot-handle linking is the attribution join** and a first-class, **verified** A6 step (how a global viewer's
   purchases attribute to one account across streamers).
6. **Custom SMTP** is driven primarily by high-volume viewer self-serve signup (not member invites) — folded into
   A6 onboarding.

## Live hours + availability (Trent-supplied)
The platform is **live 24/7 — the SLO window is all day, every day** (not "during live hours"). **Peak windows:**
weekday evenings (~6 PM–1 AM ET) and weekends broadly; the error budget is **weighted to protect peaks hardest**
(a Friday-night failure is the expensive one). **Consequence: there are no maintenance windows.** **Zero-downtime
deploys are therefore a standing requirement, enforced by the release gate** (CI `schema-gate` + the client's
fail-closed handshake; see `docs/OPERATIONS.md`).

## Out of scope for this record
No A6/A8/A9/A10 implementation. This fixes the target, the identity model, and the authorization contract those
steps build against.
