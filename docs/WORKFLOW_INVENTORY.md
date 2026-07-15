# Element 10 — Workflow Inventory (Track B, step 0 → 1)

_v0.1 — 2026-07-15. Built from Trent's role narratives. This document is the input to the domain map, the navigation prototype, and the five journey prototypes. It describes how work ACTUALLY flows, not how the current app models it._

## The operating spine

One loop, every role enters at a different point:

```
PLAN the week → STOCK inventory → DESIGN breaks → SCHEDULE & assign
     → PREPARE the show → GO LIVE → COMPLETE → FULFILL & SHIP → RECONCILE money
                                                      ↘ ANALYZE → feeds next PLAN
```

Roles are not separate workflows — they are **entry points, cadences, and permissions on this spine**. The product's connective tissue is the **handoff objects**: a *prepared show* (manager → streamer), an *approved break* (design → live), a *completed session* (streamer → fulfillment/reporting). These become first-class concepts in the domain map, and "readiness" (checklist ✓, inventory reserved ✓, format ✓, streamer assigned ✓) is a computable state of the prepared show, not a vibe.

## Journey format (binding for all prototypes)

Actor · Trigger · Frequency · Steps (every module-hop marked **[→]**) · Context that must travel · Detours · Done-state · Next natural action.

**The detour rule:** every "realize they need to…" is a nested task. A detour must return the user to exactly where they were, with all entered state intact. This is the single highest-leverage fix over the current app.

---

## Journey S1 — Streamer: run my show (daily, day-of)

- **Trigger:** shift starts / showtime approaching.
- **Steps:** log in → **my show today** surfaces immediately (no hunting) → review the prepared show: break format, inventory, slots **[→ show detail]** → approve, or adjust inventory/format (bounded edits) **[→ picker/planner detour]** → launch **[→ live board]** → run live tools: mark sold, assign winners, incentives, chase board → complete the show → review show summary + shipping list **[→ fulfillment view]** → done.
- **Context that must travel:** the show and everything attached (reservations, format, participants) flows into the live session without re-selection; the completed session flows into the summary/ship view without lookup.
- **Detours:** add/substitute inventory pre-launch (must return to the pre-flight with everything held).
- **Done-state:** session ended, summary seen, shipping known.
- **Next action handoff:** completed session → fulfillment queue + reporting.
- **Current-app friction (observed):** the show → live → summary chain exists but context is carried by module-level globals (the LIVE_SEED class of bugs); the summary/ship handoff is a manual navigation.

## Journey M1 — Manager: Monday programming (weekly)

- **Trigger:** Monday morning; next week is unscheduled.
- **Steps:** log in → review this week's programming (what ran, what's coming) **[→ schedule]** → schedule next week's shows → assign streamers to each show/shift → select products + formats for next week's new releases **[→ inventory / break planner]** → done when next week is fully staffed and stocked.
- **Context:** the week is the working object — the manager thinks in a week grid with gaps, not in individual show modals.
- **Detours (from the narrative, both first-class):**
  - **M1a — Intake:** cases arrive → add to inventory (intake movements) → return to planning.
  - **M1b — Checklists:** products breaking next week need 2–3 new checklists → source/upload them → return to planning.
- **Done-state:** next week staffed, stocked, checklisted.
- **Next action handoff:** prepared shows → streamers' "my show today."

## Journey O1 — Owner: same-night show from fresh product (occasional, high-intensity)

- **Trigger:** product arrived this evening; wants it live tonight/soon.
- **Steps:** log in → create show **[→ show creation]** → **detour: checklist missing** → download it, upload it **[→ checklist import]** → **return with the show intact** → run 2–3 break format ideas through the formatting assistant **[→ break planner]** → finalize slot makeup + break size → reserve inventory → save for go-live later.
- **Context:** the in-progress show must survive the checklist detour and the format experiments — this is the exact journey the current app handles worst.
- **Done-state:** a prepared show, ready for S1.
- **Also owner-only:** reporting/analytics review and go-to format design (separate journeys, lower frequency — mapped later; they consume the spine's outputs).

## Frequency × role matrix (drives navigation weight)

| Activity | Streamer | Manager | Owner |
|---|---|---|---|
| My show today / go live | **daily** | rare | sometimes |
| Week programming + assignment | — | **weekly** | sometimes |
| Inventory intake | — | weekly | weekly |
| Checklist upload | — | weekly | weekly |
| Break format design | bounded edits | weekly | **whenever** |
| Fulfillment / shipping | end of show | oversight | oversight |
| Reporting / analytics | own shows | weekly | **whenever** |

Daily → home-screen queue. Weekly → a planning workspace. Occasional → one click deeper. Nothing important lives in a hamburger menu.

## Handoffs (the SaaS value seams)

1. **Manager → Streamer:** the prepared show. Needs a readiness state (checklist ✓ / inventory reserved ✓ / format ✓ / assigned ✓) and a "what's mine today" queue.
2. **Streamer → Fulfillment:** the completed session. Auto-materializes the ship list; no navigation hunting.
3. **Everything → Owner:** completed sessions + movements → reporting; format performance → the format designer's inputs.

## Tenancy note

Streamer / Manager / Owner map directly to the organization role model for Track A step 6. Design the journeys assuming those roles exist; the current app's admin/member flattening is a known gap, not a spec.

## Design decisions (from prototyping — binding on later prototypes)

- **2026-07-15 · Navigation = left rail**, grouped Daily / Weekly / Occasional with the full pipeline visible. Top-tab continuity with the old app is a non-goal (replatform).
- **2026-07-15 · Context strip** (persistent bar under the top bar) is the context-follows-you mechanism: current show + four readiness chips. Compact/collapsible variant on live-operation screens; when a session is live it carries the SESSION (show + live state + ROI), not just the show.
- **2026-07-15 · Readiness chips are actionable** — a failing chip is the button that starts its fix (opens the detour, which returns).
- **2026-07-15 · Current-app screens are reference only** — no new kit screens recreated from the old app; new surfaces come exclusively from journey prototypes.

## Journey R1 — Reconciliation (weekly/monthly; owner) — FROM TRENT 2026-07-15

- **The cost model (all knowable, all configurable — nothing here is a guess):** Whatnot fee % (known constant) · breaking/packing labor benchmark **set per employee** · shipping paid by customer · packing-supplies cost (settable) · product cost driven by inventory. **Net per session is computable**: hammer − fee% − labor − supplies − product cost.
- **The check:** session → daily → weekly → monthly recorded totals vs Whatnot payouts/deposits. Cadence: weekly or monthly. Today it's done **mentally at high level** ("here's my revenue minus cost; here's what Whatnot deposited").
- **Design implication (prototype ⑤ is now unblocked):** a session P&L using the configured cost model; rollup views at day/week/month; a reconciliation surface that puts recorded totals beside Whatnot deposits and flags the gap. Labor-benchmark-per-employee is a NEW concept (tenant-owned configuration) that exists nowhere in the current app — it enters the domain map.
- **Roadmap tie:** this IS the Phase 10 metric contract, seeded from reality: gross (hammer) / fees / labor / supplies / product cost / net, at session grain with rollups; Phase 8's payout import feeds the deposits side.

## Journey F1 — Fulfillment reality (post-show; actor: **Operations Team Member**) — FROM TRENT 2026-07-15

_Roles finalized 2026-07-15: **Admin · Manager · Streamer · Operations Team Member**, with customizable, role-to-role-copyable permission sets. The Ops Team Member's home is the fulfillment queue — their day starts at "what needs pulling/packing/shipping," not at shows or inventory._

- **Physical system:** base cards + rookies go into **cubbies assigned by SPOT NUMBER** during/after the stream. Chases/SSPs/parallels are **documented digitally on-stream, set aside for extra care, and attributed to buyers POST-stream** — a distinct "hits attribution" workstep.
- **Whatnot generates packing slips and labels** — the app never needs label generation; it needs **pull lists that match the cubby/spot organization** and a hits-attribution queue.
- **Slot detail shown today:** spot name (e.g. New York Mets) · attributes (break title) · ship-to autofilled from the platform (name, username, address).
- **Design implication:** ship view is TWO-phase — (1) spot-ordered pull matching the cubby wall + the hits queue awaiting buyer attribution, then (2) buyer-consolidated packing against Whatnot's slips. Sorting must match the physical wall, not an abstract order list.

## Complaints list — FROM TRENT 2026-07-15 (the new design is graded against these)

1. No obvious back button in many spots → navigation history/breadcrumbs are a shell requirement.
2. Text/formatting bleeds over borders → QA class; the new component system must make this structurally hard.
3. Dropdowns without search → EVERY picker is searchable, no bare `<select>` for data lists.
4. No seamless cross-module updates (checklist mid-break = leave the whole workflow) → the detour rule, confirmed as the top fix. Trent: "the prototyped workflow Claude design developed was much much better."
5. Can't click away to dismiss popups/fields → universal dismissal affordances (click-outside closes, with the dirty-guard when needed).
6. Dynamic field visibility by type everywhere (Case selected → grading hidden, box-count shown) → the 2.5 form logic generalized to all forms.
7. **Cascading structured pickers for naming/data conventions: Brand → Year → Product line** (Panini/Topps → 2026 → Chrome/Prizm/Dynasty) → validates the structured-field model the backend already stores; the new UI feeds these from reference data as dependent dropdowns.
8. Enrichment (non-required) fields hidden by default → progressive disclosure pattern.
9. Grid flexibility everywhere — sort/filter/resize/saved views/**dashlets** → the grid engine's capabilities become universal, plus configurable dashboard widgets (feeds Phase 4 Home).

## Lose-your-place — FROM TRENT 2026-07-15

Confirmed as the single pattern: any dependency mid-workflow (show setup, inventory add, break formatting) forces leaving the workflow entirely. The detour rule is the fix; the shell prototype's approach is endorsed by the operator.

## Step 0: ✅ COMPLETE (2026-07-15). Next: step 1 — the domain map.
