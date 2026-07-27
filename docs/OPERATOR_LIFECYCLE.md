# Element 10 Operator Lifecycle

Status: binding coordination authority for operator-experience planning and review.

This document defines how an organization member gets work done across Element 10. It
does not grant database authority, approve a schema, create a capability, or replace
the product and supply contracts. When a UI checkpoint touches an operator job, its
plan, implementation, evidence, and review must use this lifecycle.

The governing distinction is:

> Scope controls what a checkpoint may build. Scope never limits what the designer
> must notice, analyze, and report.

## 1. Product promise

Element 10 is an operator system for a card business that acquires inventory through
multiple channels, prepares and sells it through multiple sales channels, fulfills
the resulting orders, and reconciles operating and financial outcomes.

The system must preserve continuity across:

- acquisition source, seller, purchase, and received inventory;
- product and physical-card identity;
- landed cost, allocation, adjustments, and cost provenance;
- listing, channel publication, reservation, and double-sale prevention;
- live selling, direct selling, marketplace selling, and show selling;
- fulfillment, returns, corrections, fees, payouts, and reconciliation;
- planning and restocking decisions informed by prior outcomes.

A screen is not a completed design. The meaningful unit is an operator task that
starts in context, commits a business outcome, and ends with an intentional next
action or a truthful stopping point.

## 2. Actors and operating cadences

Roles are permission bundles, not separate applications. The same lifecycle appears
with different entry points and authority.

| Actor | Primary cadence | Typical entry | Primary handoffs |
|---|---|---|---|
| Admin / owner | daily and weekly | Home, Money, Acquisition, Schedule | approves exceptions, reviews margin and reconciliation |
| Manager | weekly and exception-driven | Schedule, Inventory, Attention | hands prepared work to Streamer and Operations |
| Streamer | day-of and live | My show today, Prepared handoff | hands completed execution to Operations |
| Operations team member | continuous queue | Intake, Fulfill, Recovery | hands closed fulfillment and corrections to reconciliation |

The buyer companion, public pages, and OBS are separate surfaces. They receive
allowlisted or participant-owned projections. They do not become alternate operator
roles.

## 3. End-to-end operating lifecycle

### 3.1 Lifecycle spine

```text
Plan demand
  -> source or acquire
  -> receive or intake
  -> identify and enrich
  -> establish and review cost
  -> choose destination
  -> list, allocate, or prepare
  -> reserve and commit
  -> sell or run live
  -> fulfill
  -> reconcile
  -> learn and restock
```

Every organization may enter this spine at different points. Directly purchased
singles, collection purchases, sealed-product purchasing, trades, and existing-stock
corrections use different intake paths but converge on authoritative inventory and
cost provenance. Whatnot, eBay, Shopify, direct, and show sales use different adapters
but converge on listing, commitment, disposition, fulfillment, and reconciliation.

### 3.2 Stage contract

| Stage | Operator outcome | Completion object or evidence | Natural next actions | Common recovery |
|---|---|---|---|---|
| Plan demand | Decide what the business needs and when | planned show, requirement, buy need, or intake intention | acquire, allocate existing stock, schedule | revise demand, substitute, cancel |
| Source or acquire | Record where inventory came from and what was paid | PO or Acquisition with source, date, seller/vendor, total | receive sealed supply, intake cards | correct seller, amount, channel, or duplicate |
| Receive or intake | Turn expected or purchased supply into identified records | receipt/lot or guarded CardInstance records | enrich identity, review intake | partial receipt, unidentified queue, resume later |
| Identify and enrich | Establish durable product or card identity | Product/Configuration, checklist link, CardInstance | review cost, archive duplicate, add another | resolve conflict, restore archived, manual entry |
| Establish cost | Tie inventory to real spend without destroying evidence | lot landed cost or acquisition cost assignment | mark ready, list, allocate, prepare | adjustment event, over-assignment gate, unresolved remainder |
| Choose destination | Decide how inventory will earn or serve the business | listing intent, repack input, show requirement, hold | publish, allocate, reserve | return to stock, substitute, abandon intent |
| List, allocate, or prepare | Create a sellable or executable commitment | Listing, PlannedAllocation, ConfirmedReservation, Prepared vN | publish, approve, Start Live | resolve readiness, supersede and reprepare |
| Reserve and commit | Prevent conflicting consumption or sale | active reservation or channel commitment | sell, consume, fulfill | release, conflict resolution, expiry |
| Sell or run live | Record authoritative disposition or execution | sale/disposition or LiveSession events | fulfill, correct, close | reopen where allowed, additive reversal |
| Fulfill | Deliver the sold outcome | pulled, packed, shipped, delivered, exception states | reconcile | address correction, return, reship |
| Reconcile | Compare recorded economics to channel statements and payouts | fees, payout match, margin, discrepancy closure | close period, investigate, adjust | import correction, unmatched transaction |
| Learn and restock | Feed outcomes into the next operating cycle | performance insight and replenishment decision | plan demand | correct categorization or incomplete evidence |

## 4. Acquisition and singles lifecycle

This lifecycle governs direct card purchases, collection purchases, show-table
purchases, trades, marketplace acquisitions, and other acquisition channels.

### 4.1 Acquisition creation

The operator records:

- acquisition shape: single card or collection;
- acquisition channel, such as distributor, eBay, show, collection, or trade;
- optional Vendor link or free-text seller;
- purchase date and amount paid;
- expected card count for a collection, advisory only;
- landed-cost components when that checkpoint exists.

Saving an Acquisition creates no blank CardInstances. The success state must show what
was saved and provide an immediate route into intake or back to acquisition review.

### 4.2 Card intake loop

Each card is created through one guarded CardInstance path.

```text
Open Acquisition
  -> Add card
  -> identify or enter manually
  -> review warnings and provenance
  -> Save card
  -> continue based on Acquisition state
```

State-aware continuation:

| Condition | Primary continuation | Secondary continuation |
|---|---|---|
| Collection below expected count | Add another card | Review acquisition |
| Collection at or above expected count | Review acquisition | Add another card |
| Expected count absent | Add another card | Review acquisition |
| Single-card acquisition after first card | Review acquisition | View saved card |
| Editing an existing card | Return to invoking grid/detail context | View saved card |

The continuation shows progress, for example `3 of ~5 entered`. Expected count never
blocks completion and never creates records. “Add another” opens an empty form with
the same Acquisition selected and creates nothing until save succeeds.

### 4.3 Acquisition review

Acquisition detail is the durable resume and review surface. It shows:

- cards entered and advisory expected count;
- purchase total and landed total when available;
- assigned cost versus amount paid when assignment exists;
- unassigned or zero-basis cards;
- acquisition-level margin inputs and later realized outcomes;
- Add card, Edit acquisition, and available next-stage actions;
- truthful unavailable states for deferred stages.

The operator may leave incomplete intake and resume it from this surface. Leaving is
not an error. No text may call cost assignment “next” unless it provides a reachable
action. Before S2 exists, the surface states that assignment is planned and currently
unavailable.

### 4.4 Cost assignment

Single-card acquisitions derive the card basis from the acquisition total. Collection
cards begin at zero and are assigned cost through additive assignment or adjustment
events. The workspace shows assigned total against amount paid and the remaining
amount. Non-admin over-assignment fails closed. Completion returns to Acquisition
review with the resulting state visible.

### 4.5 Destination and sale

A CardInstance can remain available, be held, enter a repack, or receive one or more
channel Listings. Listing is a separate entity from the physical card. Each Listing
has a sales channel, external identifier, asking terms, status, timestamps, fees,
reservation, and synchronization state.

One physical card may be advertised on multiple channels, but only one active
commitment may consume it. A reservation or sale on one channel must make conflicts
visible on every other channel. A sales-channel adapter never owns physical inventory
truth.

### 4.6 Fulfillment, return, and reconciliation

Sale or disposition hands the CardInstance and buyer/order context to Fulfillment.
Fulfillment completion hands actual fees, shipping outcome, payout evidence, and any
return or correction to reconciliation. Corrections are additive. A return never
silently deletes the sale, shipment, or financial history.

## 5. Sealed product and live-commerce lifecycle

The canonical product-first supply sequence remains:

```text
Product Master
  -> Product Configuration
  -> Vendor and PO
  -> Receipt and Inventory Lot
  -> ChecklistForUse where applicable
  -> Product Format Recipe
  -> Program or Planned Show
  -> ProductRequirement
  -> PlannedAllocation or direct ConfirmedReservation
  -> readiness
  -> Prepared vN
  -> maker-checker approval
  -> Start Live
  -> consumption and completion
  -> fulfillment
  -> reconciliation
```

The warm path begins from Schedule or Program and skips already-green setup pages.
Resolver detours return to the invoking Show, Break, Product, filter, and focused
control. Completion hands the execution to Operations. Streamers do not become the
shipping workflow by implication.

## 6. Channel model

The word “channel” always has a qualifier.

| Concept | Examples | Owned by |
|---|---|---|
| Distribution class | Hobby, Retail | Product Configuration |
| Acquisition channel | distributor, eBay, show, collection, trade | Acquisition |
| Sales channel | Whatnot, eBay, Shopify, direct, show | Listing or Disposition |
| Fulfillment route | shipped, pickup, break shipment | Fulfillment |

Adapters translate external channel records into canonical Element 10 objects. They
do not redefine Product, CardInstance, cost, reservation, sale, or fulfillment
semantics. Whatnot may be implemented first without designing the core as though it
is the only acquisition or sales channel.

## 7. Task-loop contract

Every mutating workflow must define all of the following before implementation:

1. Operator job and intended business outcome.
2. Entry points and invoking context.
3. Preconditions and permission conditions.
4. Steps and business commit point.
5. Immediate success state.
6. Primary and secondary continuations.
7. Review, edit, undo, archive, or additive correction path.
8. Back, Cancel, close, and unsaved-work behavior.
9. Repetitive or batch behavior.
10. Incomplete exit and later resume behavior.
11. Empty, loading, denied, conflict, stale, and failure recovery.
12. Handoff to the next lifecycle object, queue, actor, or deferred checkpoint.

A task is not complete when code returns successfully. It is complete when the
operator can understand the result and deliberately continue, review, correct, or
leave.

## 8. Navigation and context

- Every full-page working surface has a visible return or breadcrumb path.
- Modal Cancel abandons only the uncommitted modal task.
- Saving from a detour returns to its invoking context with filters, selection,
  object identity, and focus preserved.
- “Back” follows operator history or an explicit origin, not a hardcoded module home.
- Successful create and update actions show the saved object, not only a toast.
- The next primary action changes with lifecycle state and permission.
- A disabled or deferred action explains why and who or what unlocks it.
- No visible control is decorative unless it is explicitly marked unavailable.
- An interrupted workflow has a durable resume surface or queue.

## 9. Required design preflight

Before building a new or materially changed workflow, the design agent produces:

- a journey statement;
- a state and transition map;
- an action inventory for each touched surface;
- the task-loop fields from section 7;
- cases for first item, repeated item, incomplete exit, final item, edit, Cancel,
  denied authority, and recovery;
- adjacent lifecycle gaps, split into “must close now” and “reported for a later
  checkpoint”;
- any model, capability, tenancy, or channel contract that requires CPI or Track A.

The agent may not silently implement a new domain contract. It must still identify
the need and show how the current checkpoint ends honestly without it.

## 10. Workflow evidence and acceptance

Static screenshots prove paint, not workflow completeness. A workflow package must
cover these operator outcomes:

1. First-time happy path.
2. Repetitive or bulk path.
3. Incomplete exit and resume.
4. Final-item or completion path.
5. Edit and return-to-origin path.
6. Cancel with no unintended creation.
7. One denied or conflicted path and its recovery.
8. One multi-organization or cards-off case where applicable.

These outcomes are not a complete walkthrough method.
`OPERATOR_WALKTHROUGH_PROTOCOL.md` requires separate lifecycle, interruption,
boundary-transition, mutation/invariant, and temporal/input tours; at least two
materially different passes; defect-family expansion; and independent acceptance.

For each scenario, evidence records:

- starting state;
- action taken;
- business state committed;
- immediate rendered result;
- next action offered;
- ending destination and retained context.

A gate fails workflow acceptance if:

- a successful save ends only in a toast;
- a user must use global navigation to discover the next step;
- the UI promises a “next” stage that cannot be reached;
- repeated work loses parent context;
- Cancel, Back, or close produces a phantom record;
- a future checkpoint is used as justification for a present dead end;
- the report proves controls individually but not the complete task loop;
- only one walkthrough pass was run;
- static starting-state coverage stands in for mid-operation transitions;
- a finding was not expanded across its sibling mutators and transitions;
- any finding remains undispositioned;
- the builder reports its own work accepted.

## 11. Relationship to other authorities

- `PRODUCT_FIRST_WORKFLOW.md` owns the canonical sealed-product operating sequence.
- `PRODUCT_SUPPLY_MODEL.md` owns product demand, supply, reservation, and cost lineage.
- Product-first model rulings on CardInstance, Acquisition, Listing, and Disposition
  own their domain semantics when approved.
- `CAPABILITY_CROSSWALK.md` and Track A security contracts own authority.
- `UX_WORKFLOW_CONTRACT.md` turns this lifecycle into repeatable design and review
  requirements.
- `OPERATOR_WALKTHROUGH_PROTOCOL.md` owns walkthrough tours, evidence classes,
  defect-family expansion, and acceptance separation.
- `BOARD.md` selects the current gate and records acceptance.

Where another approved contract conflicts with this document on schema, arithmetic,
or authority, that contract wins and the conflict is escalated. Where a screen-level
instruction omits navigation, continuation, review, interruption, or recovery, this
document supplies the missing workflow requirement.
