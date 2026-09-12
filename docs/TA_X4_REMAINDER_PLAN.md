# TA-X4 receiving remainder implementation contract

Status: proposed for independent review before implementation

Date: 2026-09-11

## Existing accepted baseline

TA-X4a through TA-X4d already provide lot-backed reservations, expected-supply allocations, a strict single-PO-line receipt writer, accepted/damaged/quarantined quantities, one lot and one inventory movement per receipt line, and single-line full reversal. The accepted writer rejects over-receipt. Invoice approval, receipt posting, and payment remain separate.

The remaining work must extend this baseline without rewriting applied migrations or weakening its locking, idempotency, tenant, reservation, or ledger-history guarantees.

## Proposed checkpoints

### TA-X4e: source-neutral multi-line receipt model and writer

Add an organization-owned, client-closed receipt command relation and an organization-owned explicit `receipt_line -> supplier_invoice_line` quantity-allocation relation. The allocation relation records evidence linkage only. It does not approve an invoice, recognize a charge, infer payment, copy invoice cost into inventory, or allocate landed cost.

Every PO or invoice source allocation records **physical received quantity**. It never means accepted/sellable quantity. Each newly written receipt line may name at most one PO line and at most one invoice line; callers split a physical line when distinct source allocations are required. The line's effective accepted quantity is shared by its PO and invoice evidence links without inserting another physical allocation when quarantined units are later accepted. Reads expose physical allocated, effective accepted, damaged, quarantined, reversed, and remaining quantities separately.

Add one bounded, idempotent `e10_org_receive_batch` API. One receipt contains 1 through 100 lines. Each line names an exact configuration version, inventory item, accepted/damaged/quarantined quantities, and optional lot code, actual-cost observation, expected-allocation fulfillments, PO-line allocation, and invoice-line allocation. The server derives and validates supplier and destination coherence across every referenced source.

Rules:

- A receipt may be PO-first, invoice-linked without a PO, or direct supplier purchase without either source.
- No path fabricates a purchase order, invoice, approval, payment, or accounting event.
- Every line must have positive total received quantity. Accepted, damaged, and quarantined quantities remain separate and nonnegative.
- The destination is a required location ID and is rechecked with `e10.can_receive_at`; advisory text cannot replace or override it.
- PO allocation is optional, explicit, physical-quantity-conserving, and retains the current non-over-receipt rule. Open commitment uses effective accepted quantity, never damaged or unresolved quarantined quantity.
- Invoice allocation is optional, explicit, same-supplier/same-currency/same-configuration, and cannot exceed the invoice line quantity after prior non-reversed physical allocations. Invoice status may be draft, reviewed, or approved because physical receipt is independent of charge approval; void invoices are ineligible.
- A direct line without PO or invoice remains attributable to the exact supplier, destination, configuration, and receipt. It is not labeled invoice-backed or ordered supply.
- Actual unit cost remains optional receipt evidence with its own source and currency. Missing cost remains unknown. An invoice amount is not silently promoted to actual unit cost.
- Lock acquisition extends the existing X3/X4 hierarchy: normalized command advisory lock, organization, supplier/location, financial document and PO headers, source lines, receipt, receipt lines, lots/items, allocations, expected allocations, and reservations. IDs are sorted within each class. It does not introduce an independent generic UUID lock order. Authorization and active-organization state are reread after command lock acquisition.
- Exact retry returns the original receipt and exact line/lot/movement IDs. Same key with changed normalized payload is denied. The entire batch commits or rolls back atomically.
- Each physical receipt appends canonical typed X5 `receipt` evidence atomically. Evidence retains exact receipt, line, lot, movement, PO-line, invoice-line, command, event-time, and source correlation. Retry preserves one-event-per-logical-action cardinality, including lines with zero initially accepted quantity.
- Existing invoice amend, transition, and allocation writers are tightened under the same financial-document/source-line locks. They cannot change supplier, currency, configuration, quantity, void state, or allocation below a non-reversed linked physical receipt. Such incompatibility is denied rather than orphaned or silently reconciled.

Add one service-only effective-receipt interpretation shared by X3f supplier/open-commitment reads, X3f actual-cost history, source allocation availability, lot availability, reservation checks, disposition, and reversal. It derives effective accepted/damaged/quarantined quantities from immutable receipt evidence plus eligible disposition decisions and excludes fully reversed receipts. No consumer may independently reinterpret these quantities.

### TA-X4f: atomic multi-line reversal

Add one bounded, idempotent `e10_org_reverse_receipt_batch` API. It reverses every line of one posted receipt atomically, appends one reversal row and any inventory correction movement per line, reverses expected-allocation fulfillment events, and marks every affected lot and the receipt reversed.

Rules:

- A receipt cannot be partly reversed by this checkpoint. Reversal closes the disposition chain and makes every later disposition command ineligible while preserving all prior decisions.
- Reversal removes each line's effective accepted quantity, including quantity accepted by later quarantine decisions, and is denied if any resulting accepted units have been consumed, actively lot-reserved, or cannot be removed without violating the legacy item reservation floor.
- PO and invoice allocation rows remain immutable evidence; reversed receipt status removes them from effective received/allocation calculations.
- Replay is stable after later mutable eligibility changes. Changed reason or target under the same key is denied.
- Locks cover the receipt, every line, every lot/item, source allocation, expected allocation, and reservation dependency in deterministic order.
- Reversal appends typed X5 `correction` evidence atomically for the receipt and every affected line/lot/movement correlation. Retry adds no event.

### TA-X4g: reviewed inspection and quarantine disposition

Add an immutable, revisioned inspection/disposition decision relation plus a bounded, idempotent writer for quarantined quantity only. Initial actions are deliberately limited to `accept` and `damage`.

Rules:

- Decisions transfer a positive quantity from the line/lot's unresolved quarantined balance to accepted or damaged disposition. They never exceed the remaining quarantined balance.
- `accept` increases lot accepted quantity and item on-hand through one linked inventory movement in the same transaction.
- `damage` records non-sellable disposition and does not increase on-hand.
- Original receipt quantities are immutable evidence. Effective quantities are derived from the receipt plus disposition decisions, not by rewriting receipt rows.
- Correction is additive through an explicit superseding decision chain. Superseding a prior decision applies the prior decision's inverse inventory effect and the successor's forward effect atomically, with revision CAS, on-hand/reservation floors, deterministic dependency locks, and command idempotency. It does not delete history or silently change cost evidence.
- Authorization requires the existing recovery/receiving authority, active organization, permitted destination, and same-organization objects, with post-lock rereads.
- Return-to-vendor, vendor credit, write-off accounting, salvage value, and landed-cost consequences are not asserted by these two actions.
- Every accept, damage, or correction appends typed X5 `correction` evidence atomically with exact receipt, line, lot, movement, predecessor/successor decision, command, and source correlation. Retry adds no event.
- Disposition and full reversal share the receipt/line/lot/item lock hierarchy. Exactly one concurrent outcome wins; the loser rereads terminal/revision state and leaves no partial movement, decision, or event.

## Acceptance mapping

| Authority or case | Required executable proof |
|---|---|
| PUR-04; Invoice-only intake | Invoice line quantity 12, direct receipt accepted 10 with no PO row created; explicit physical invoice/receipt allocation 10; effective accepted 10; visible physical and accepted discrepancy 2; invoice status and approval history unchanged. |
| PUR-04; Split matching | Two receipt lines may link to one invoice line and one receipt may link across eligible PO/invoice lines; effective quantities conserve every source and target without fanout or double counting. Existing X3d invoice-to-PO allocation conservation remains green. |
| PUR-05; partial and multi-line receipt | One atomic receipt posts at least two lines with accepted, damaged, and quarantined quantities; exact items/lots/movements are returned; one invalid line rolls back the whole receipt. |
| PUR-05; inspection/quarantine | Quarantined stock is unavailable; reviewed accept makes only the decided quantity available and appends a movement; reviewed damage remains unavailable; excess and concurrent disposition lose safely. Accept, then correction, then reversal applies exact inverse/forward effects while preserving history. |
| PUR-05; reversal | Multi-line full reversal removes initial plus disposition-accepted quantity and restores item, lot, expected-allocation, and effective PO/invoice receipt state atomically; any consumed/reserved line blocks the whole reversal; later disposition is denied; retry is stable. Reversal racing disposition yields one coherent winner. |
| Duplicate document | Exact batch retry creates no duplicate receipt, line, lot, movement, allocation, or event; changed payload under the same key fails with no residue. |
| Location restriction | Foreign or unauthorized destination ID is denied; advisory delivery text cannot override the location; permission or organization suspension after a real lock wait is reread and denied. |
| Historical cost | Direct and PO receipts retain exact configuration version, cost source/date/currency, and unknown cost. Invoice linkage alone does not create actual-cost evidence. An all-quarantined known-cost line is initially absent from eligible actual cost, enters after reviewed acceptance, and leaves after reversal. |
| Manual price | Explicit receipt cost observation is retained. A later vendor or invoice suggestion cannot silently replace it. |
| Notes audience | Existing X3e vendor projection remains green and contains no new inspection, internal, cost, or allocation metadata. |
| Multi-membership and hostile tenant | Explicit `p_org` succeeds for the selected membership only; foreign supplier, location, PO, invoice, configuration, item, allocation, receipt, lot, and command IDs are denied. |
| Non-card core | One apparel/carton fixture completes direct multi-line receipt, quarantine acceptance, reservation, and reversal without a card/catalog/player dependency. |
| Source/effective reconciliation | Physical source allocation never changes when quarantine becomes accepted. The shared interpretation changes effective accepted/open commitment/lot availability/actual-cost eligibility once, and reversal removes it once, without duplicate units. |
| Invoice mutation races | Amend, void, reallocation, and receipt operations share the X3/X4 lock hierarchy. Incompatible invoice mutation below linked non-reversed physical receipt is denied after the wait; no orphan link, over-allocation, or partial side effect remains. |
| Typed lifecycle evidence | Receipt, disposition, disposition correction, and reversal each create the allowlisted typed X5 event(s) in the state transaction with exact source IDs. Exact retry preserves event cardinality. |
| Concurrency | Exact backend wait proofs cover same command key, competing PO/invoice capacity, invoice amend/void/reallocation versus receipt, batch reversal versus reservation/consume, disposition versus disposition, reversal versus disposition, and authority/org suspension after lock wait. |
| Security and delivery | New public tables have RLS and no client grants; public APIs self-authorize and deny anon/PUBLIC; internal helpers are service-role-only; clean local replay, predecessor regressions, A7, default privileges, exact-head CI, explicit staging, advisors, cleanup, and production read-only evidence pass. |

## Owner-decision boundaries held closed

- Over-receipt remains rejected. No exception capability or tolerance is invented.
- Landed-cost allocation method remains unresolved. No freight, duty, tax, fee, or blended-cost allocation writer is added.
- Receipt posting does not approve invoices or recognize charges.
- Invoice approval does not create stock.
- Payment and settlement remain unavailable/not modeled.
- Shortage, damage, quarantine, or rejection does not automatically create a supplier credit.
- Return-to-vendor and accounting write-off workflows remain outside this technical checkpoint until explicitly ruled.

## Review boundary

No migration or implementation begins until this contract and acceptance mapping are independently accepted. Implementation will use new additive migrations only and stop at each X4e, X4f, and X4g checkpoint for local review before staging.
