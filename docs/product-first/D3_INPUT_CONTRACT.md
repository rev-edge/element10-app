# Element 10 — D3_INPUT_CONTRACT.md
## What D3 (live operator journey) receives from D2, and the live-board contracts

**Status:** APPROVED base contract **+ one explicit governance extension** (this pass): Start Live is bound to a valid maker-checker approval of the exact Prepared version (§1a / §10a below), recorded openly in the canonical merge manifest — **not** an unnoticed cleanup. All other approved D3 behavior is preserved unchanged. Design-only; D3 is not built in this pass. Aligned to the approved PF-M1.1 product/supply model (ConfirmedReservation-against-lots, requirement conservation, additive lineage). Capability names below are **behavioral design labels**; the persisted set stays the legacy keys, and finer leaves are a **later additive migration**. **Program Templates use `session.write`; preparation issuance uses `session.write`; production maker-checker approval requires the distinct later-additive `session.approve` leaf** (a prototype may only *simulate* the checker; `session.write` must never be the production checker authority).

**Operator-lifecycle relationship:** this contract occupies the Prepare → approve
→ Start Live → execute → complete → fulfillment handoff in
`../OPERATOR_LIFECYCLE.md`. D3 UI work must satisfy
`../UX_WORKFLOW_CONTRACT.md` without weakening any atomic, privacy, capability,
or immutable-snapshot boundary below.

---

## 1. Prepared vN inputs handed to D3

D3 consumes an **immutable Prepared vN** and, on Start Live, creates a distinct `e10_live_sessions` execution carrying `source_show_ref`; runtime `e10_break_sessions` attach via `live_session_id`. Prepared vN carries:

- Planned Show identity + operator assignment + valid date/time.
- The **Planned Break configuration** (cards): format recipe/template version, slot structure, tiers/pricing per break.
- **Every ProductRequirement** — Show-level and Break-attributed. Cardinality lives on the ProductRequirement, not the Break:
  - each relevant ProductRequirement **independently pins its applicable ChecklistForUse version** (with chase annotations);
  - **ConfirmedReservations and captured lot/effective-cost evidence attach through ProductRequirements** (not a generic "inventory per break");
  - a **mixer Break** therefore carries **multiple checklist pins and reservation groups** (one set per its ProductRequirements);
  - a **core zero-Break Show** carries **Show-level ProductRequirements** with no Break.
- Requirement state at issue satisfies `req_confirmed = req_required` and `req_planned = 0` for every ProductRequirement (PF-M1.1 §5).
- Green readiness rollup at issue time.

D3 **revalidates atomically at Start Live** (§1a) and refuses a stale/invalidated prep (must be re-prepared in D2). D3 never mutates the Prepared vN.

### 1a. Start Live boundary (atomic + idempotent)

"Revalidate on entry" alone is insufficient — a prep can go stale between check and execution creation. Start Live is **one authoritative boundary** that atomically:
- **locks / guards** the source Planned Show and the selected Prepared vN (serialize or compare-and-set);
- **rereads** and verifies the Prepared vN is still **current + valid** (not superseded/invalidated);
- **[governance extension]** verifies a **valid maker-checker approval bound to that exact `prepared_version_id` and content digest** exists, that **maker ≠ checker**, and that the approval is **not for a superseded version** (a superseded version's approval cannot authorize Start Live);
- verifies `req_confirmed = req_required` and `req_planned = 0` across all ProductRequirements;
- verifies all required **checklist pins**, **operator assignment**, **entitlements**, capability conditions, and readiness evidence;
- verifies **no unresolved current-version blocking Recovery** remains;
- creates the **LiveSession + runtime Break** rows;
- records the **exact Prepared version** and **`source_show_ref`**;
- returns the **same LiveSession for the same idempotency key**.

Two concurrent attempts must not create two active executions. Multiple **intentional** LiveSession executions from one Planned Show remain supported, but each subsequent execution requires a **distinct explicit start intent** and a valid lifecycle state (not an accidental double-submit). Build acceptance: same-key retry returns the same LiveSession; concurrent starts yield exactly one active execution (§9).

---

## 2. Resolver registry (single source of routing)

One registry keyed by readiness item; **every presentation of the same blocker calls the same resolver** (fixes the legacy Streamer bug where all Resolve actions routed to Inventory).

| Readiness key | Resolver destination | Capability to act |
|---|---|---|
| `checklist` | Checklist resolution / staging detour | `checklist.stage` / `checklist.approve` |
| `inventory` (reservation) | Inventory reservation | `inventory.reserve` |
| `format` | Break plan / Format Builder | `break.configure` / `format.manage` (deferred leaf; interim `act.lists_edit`) |
| `operator` | Operator assignment (only where member has permission) | `session.write` |
| `product` | Product assignment (Schedule-first exception) | `product.write` (deferred leaf; interim `session.write`) |

Rules: top primary action and the readiness row for the same key resolve identically. Return to the Prepared Show with **context + focus intact**. If the member lacks the resolving capability, show who can (never a dead control).

---

## 3. Editing behavior by object & phase

Edits are scoped by which object and lifecycle phase they touch — mutable plan vs immutable snapshot vs execution-scoped:

- **Planned Show / Planned Break: mutable** (D2). Normal planning edits.
- **Prepared vN: immutable.** Never edited in place.
- **Editing the plan after preparation** supersedes the current Prepared version, returns the plan to **Created / Preparing**, and requires **re-preparation** (retains prior version as history).
- **LiveSession / runtime Break: execution-scoped additive adjustments** — never mutations of the Planned Break or Prepared vN.
- **Sold / assigned / consumed / completed / locked** slot history **cannot be retroactively rewritten** (corrections are additive events).
- **Pricing/tier/team/format changes after Live begins** require explicit **eligibility rules + capability checks + audit events**, and **deterministic refusal when locked**.
- **"Save as new template"** snapshots the eligible working configuration into a **new template/version**; it never alters historical executions or the templates bound to prior Prepared versions.

For a member with the required capabilities, D3 still offers **quick inline** format/slot/tier adjustments *within these boundaries* (execution-scoped on the runtime break; plan edits route back through supersede+re-prepare) plus an obvious route to the full **Format Builder** preserving Show/Break/Product/return context. Build acceptance proves all three object boundaries (plan mutable, Prepared immutable, execution additive) in §9.

### 3a. Template versioning

- **"Update template" creates a new template version.** The active Planned/Live Break retains its own captured configuration (captured at prepare/start; edits don't retro-alter history).
- **Never silently overwrite** the reusable template used by historical Prepared versions or executions.

---

## 4. Live controls panel (functional contract)

Controls split into **configuration toggles** (enable/disable a capability) and **operational actions** (a step that changes state and may emit alerts). Each entry below defines: default + its source · allowed states/transitions · operator interaction · capability/entitlement · companion effect · OBS/public effect · audit event · unavailable reason · post-lock/completion behavior.

### 4a. Configuration toggles

**Significant-Pull alerts enabled** — default OFF (from org/show config). States: `off ↔ on`. Operator toggles. Cap `live_run`/cards. Companion: none until an action fires. OBS: none. Audit `config.pull_alerts`. Unavailable: no checklist tags / not cards / no cap. After lock: toggle frozen; existing alerts retained.

**Case-Hit alerts enabled** — default from **explicit org/show configuration** (not automatically from tag presence). Checklist `case_hit` tags are an **eligibility prerequisite**, not an auto-enable. States `off ↔ on`. Same pattern; audit `config.casehit_alerts`.

**Companion interaction visibility** — default from show config; requires companion linked. States `hidden ↔ visible`. Toggles participant view. OBS none. Audit `config.companion_visibility`.

**OBS overlay visibility** — default from OBS config. States `hidden ↔ visible`. Toggles **public** overlay only. Audit `config.obs_visibility`.

**Buyback / store-credit offers enabled** — default OFF; requires **entitlement + legal enablement**. States `off ↔ on`, force-OFF when not legally enabled. Audit `config.buyback_enabled`. Companion/OBS: none from the toggle itself (offers surface via the action). Unavailable reason names the missing entitlement/legal gate.

### 4b. Operational actions

**Log significant pull** — prereq alerts enabled + `case_hit`/significant checklist tag. Interaction: operator selects the pulled card → confirm. Companion: notify owning buyer + show hit (participant-private). OBS: overlay alert **if** overlay visible. Audit `pull.significant`. Post-lock: still loggable during active break; refused after completion.

**Log case hit** — as above for `case_hit`-tagged cards. Audit `pull.case_hit`.

**Stash or Pass** — **multi-step mode**, not a boolean: `offered → (stash | pass)`; stash routes the slot to a defined stash pool, pass continues. Prereq: format allows. Companion reflects stash state. OBS none. Audit `spot.stash` / `spot.pass`. Refused when break locked.

**See 2, Pick 1** — **multi-step mode**: `presented(2) → picked(1) → remainder-disposed`. Companion shows the choice window. OBS optional. Audit `promo.see2pick1`. Refused when locked.

**Trade window** — explicit states `closed → open → locked`; opens only with ≥2 verified buyers; auto-locks at break lock. Companion surfaces trade offers/confirm (participant-private). OBS none. Audit `trade.window_open` / `trade.window_locked`. Drives the §6 trade state machines.

**Make buyback / store-credit offer** — prereq toggle on + entitled + legally enabled. Interaction: operator issues an offer to a buyer. Companion: **eligible offer + that buyer's own status enters participant-private** (see §5). OBS: never. Audit `offer.buyback`. Refused when not legally enabled or locked.

Every unavailable control renders an explicit reason (prerequisite / capability / entitlement / legal / locked), never a decorative dead toggle. **Every live-control mutation requires current `act.live_run`**, plus any control-specific entitlement, capability, prerequisite, or legal gate named above. Build acceptance (§10) proves each control produces a **visible state change + audit event**, not mere rendering.

---

## 5. Channel separation (hard boundary)

Three distinct payload channels — never combined:
- **Operator-only state** — internal controls, cost basis, margins, approval policy, org liability totals, reservations, resolver state.
- **Participant-private** — a buyer's **own** spots/assignments/offers/trade payloads (only rows they own or are entitled to). **A legally-enabled buyback/store-credit offer and the buyer's own offer status may enter this channel**; **store-credit balance/liability detail is visible only to its verified owner** where the product permits.
- **Public / Broadcast (OBS)** — allowlisted projections only; never participant-private or operator-private data; **buyback/store-credit never enters OBS**.

**Operator-private evidence** — internal cost basis, margin, approval policy, organization liability totals — **never** enters companion or OBS. Build acceptance (§10): hostile isolation proving **Buyer A cannot read Buyer B's** offers, balances, spots, or trade payloads.

---

## 6. Buyer lookup + trade state machines

**Corrected interaction:**
1. Selecting a buyer from lookup **immediately filters** the left spot grid (no separate "Filter grid to buyer" button).
2. Operator selects eligible owned slots directly from the filtered grid.
3. Primary action appears **only after ≥1 eligible slot is selected**.
4. That primary action initiates the trade-in/trade workflow.
5. **Clear filter** and **Clear selection** have visible text + WCAG-compliant contrast.
6. Clearing selection does **not** clear the buyer filter unless the user explicitly clears the filter.

**Distinct workflows (not aliases) — explicit state machines:**

**Trade-in / re-spin:** `owned → selected → confirmed → returned-to-pool`.
- Cancel path from `selected`/`confirmed` → `owned` (no change committed).
- Conflict path: slot already changed → fail safe to `owned`, surface conflict.
- Atomic slot release; **idempotent** (same key → same result); eligibility reread at commit; **no double return**.
- Audit `slot.tradein`.

**Buyer-to-buyer trade:** `draft → offered → counterparty-confirmed → mutually-confirmed → operator-committed`.
- Terminal paths: `withdrawn` (either party before mutual confirm) · `expired` (at break lock) · `conflicted` · `rejected`.
- Requires: **verified identity ownership on both sides**; participant-private payload isolation; **slot eligibility reread at commit**; authoritative **lock/compare-and-set** guard; **atomic dual ownership transfer**; **idempotent commit**; competing proposals **cannot both succeed**; **expiration at break lock**; **no partial ownership transfer**.
- Audit `trade.buyer_to_buyer` (offer / confirm / commit / terminal each discrete).

**Stash or Pass** and **See 2, Pick 1** — separate promotion mechanics (§4b), **not** trading aliases.

Buyer selection remains an **immediate grid filter**; the primary button initiates the selected workflow **only after eligible slots are selected**. **Clear Filter** and **Clear Selection** stay separate visible actions.

---

## 7. Consumption & reversal transaction contract

D3 preserves the PF-M1.1 inventory behavior with authoritative, atomic, idempotent operations.

**Consume:**
- validate active LiveSession / runtime Break and an eligible ProductRequirement + ConfirmedReservation;
- **reread** current lot/reservation state under the concurrency guard;
- transition the applicable **confirmed → consumed** quantity;
- post the inventory movement (lot on-hand decrement per PF-M1.1 §5);
- preserve **ProductRequirement → reservation → lot → receipt/PO → Prepared vN → LiveSession / runtime Break** lineage;
- **prevent negative stock and double consumption** (idempotency key).

**Reverse:**
- reference exactly **one prior consumption**;
- post an **additive reversal** (never delete/rewrite history);
- restore the exact lot + eligible reservation state per execution policy;
- **prevent duplicate reversal**;
- preserve actor, reason, timestamps, full lineage.

Deterministic conflict behavior on contention (same guard as reservation). Build acceptance (§10): consume → retry (idempotent) → reverse → retry (idempotent) → two competing consumes yield exactly one success.

---

## 8. Audit requirements

Every live control action and ownership/assignment change emits a discrete, timestamped audit event (keys in §4/§6/§7), attributed to the **acting principal** — an **organization member** or a **verified participant/buyer** — sufficient for D6 reconciliation lineage. Each event records: **actor type** (member | participant), **actor id**, **organization**, **timestamp**, **operation**, **idempotency/request identity**, **LiveSession**, **runtime Break**, and **affected object references** (slot / ProductRequirement / reservation / lot where applicable) — plus consumed Product Configuration, source lot, cost basis, and PO/receipt / Planned Show / Prepared vN provenance for consumption events. Corrections are additive events — history is never rewritten.

---

## 9. Journeys 03–06 input contracts (no redesign now)

- **03 same-night Admin** → revise to product-first fast path (Product → checklist → format recipe → create/schedule Show → allocate/reserve → Prepare); same objects, faster velocity.
- **04 Manager weekly** → weekly grid based on Program Templates; Product readiness + incoming supply feed the week.
- **05 close/reconcile (D6)** → input contract only: consumed Product Configuration, source lot, actual cost basis, PO/receipt provenance, full lineage, additive correction events.
- **06 repack (D7)** → input contract only: select eligible lots/cards, preserve source cost basis, reference Product + checklist metadata, create separate transformed output Product, retain consume/output lineage, preserve fairness + compliance gates.

---

## 10. D3 build-pass acceptance criteria (for the later D3 build, not this pass)

When D3 is built, it must demonstrate:
1. Start Live from a green Prepared vN creates a **distinct `e10_live_sessions`** execution carrying `source_show_ref`; runtime breaks attach via `live_session_id`; **Prepared vN is never mutated**.
2. Start Live is **refused** on a stale/invalidated Prepared vN with a route back to D2 re-preparation.
3. **Atomic Start Live revalidation** — lock/reread/verify/create in one boundary; a prep going stale mid-start is caught before execution creation.
3a. **[governance extension] Approval-bound Start Live** — Start Live is **refused** unless a valid approval is bound to the **exact current `prepared_version_id` + content digest**, with **maker ≠ checker**; an approval for a **superseded** Prepared version **cannot** authorize Start Live; re-preparation requires a new approval before Start Live is eligible.
4. **Same-key Start Live retry** returns the same LiveSession (idempotent); **concurrent Start Live attempts** yield exactly one active execution.
5. One LiveSession contains **multiple breaks** with explicit per-break lock + completion states.
6. **Editing boundaries** — plan mutable; Prepared vN immutable (plan edit supersedes + re-prepares); LiveSession/runtime edits execution-scoped additive; locked/sold/consumed history not rewritable.
7. Every resolver row and its top primary action route through the **single registry** to the same destination, returning with context + focus intact.
8. Live controls each show functional/unavailable states with explicit reasons and produce a **visible state change + audit event** (toggles vs actions distinguished).
9. **Consumption + additive reversal**; **duplicate consume/reverse refused**; two competing consumes yield one success.
10. Buyer lookup filters the grid; primary action appears only after ≥1 eligible slot selected; **trade-in vs buyer-to-buyer trade** are distinct workflows with explicit state machines + distinct audit contracts; competing trade proposals cannot both succeed.
11. **Buyer-private channel isolation** — Buyer A cannot read Buyer B's offers, balances, spots, or trade payloads; operator cost/margin never in companion/OBS; buyback never in OBS.
12. **Cards checklist/reservation cardinality** for a multi-product mixer — multiple checklist pins + reservation groups per Break via ProductRequirements.
13. Completion hands off to **Operations** (fulfillment, D5) — streamer does not ship.
14. Consumption emits additive lineage sufficient for D6 (consumed Configuration, source lot, cost basis, PO/receipt, Show/Prepared vN/LiveSession/break).
15. The complete operator task loop is proven: Start Live preserves the Prepared
    origin and context; resolver detours return intact; completion shows what was
    committed and hands the execution to Operations with an explicit next action;
    interrupted and denied paths provide a durable resume or recovery route. A
    toast or route to a module home does not satisfy this requirement.

**Out of scope for the D3 contract pass:** no C1–C3 prototype changes, no checkpoint governance, no product-first doc merge, no HTML implementation. Those follow the approved sequence (D3 contract → governance → merge → product-first approval).
