# TA-X4 receiving remainder implementation contract

Status: proposed for independent review before implementation

Date: 2026-09-11

## Existing accepted baseline

TA-X4a through TA-X4d already provide lot-backed reservations, expected-supply allocations, a strict single-PO-line receipt writer, accepted/damaged/quarantined quantities, one lot and one inventory movement per receipt line, and single-line full reversal. The accepted writer rejects over-receipt. Invoice approval, receipt posting, and payment remain separate.

The remaining work must extend this baseline without rewriting applied migrations or weakening its locking, idempotency, tenant, reservation, or ledger-history guarantees.

## Proposed checkpoints

### TA-X4e: source-neutral multi-line receipt model and writer

Add an organization-owned, client-closed receipt command relation and an organization-owned explicit `receipt_line -> supplier_invoice_line` quantity-allocation relation. The allocation relation records evidence linkage only. It does not approve an invoice, recognize a charge, infer payment, copy invoice cost into inventory, or allocate landed cost.

Add one bounded, idempotent `e10_org_receive_batch` API. One receipt contains 1 through 100 lines. Each line names an exact configuration version, inventory item, accepted/damaged/quarantined quantities, and optional lot code, actual-cost observation, expected-allocation fulfillments, PO-line allocation, and invoice-line allocation. The server derives and validates supplier and destination coherence across every referenced source.

Rules:

- A receipt may be PO-first, invoice-linked without a PO, or direct supplier purchase without either source.
- No path fabricates a purchase order, invoice, approval, payment, or accounting event.
- Every line must have positive total received quantity. Accepted, damaged, and quarantined quantities remain separate and nonnegative.
- The destination is a required location ID and is rechecked with `e10.can_receive_at`; advisory text cannot replace or override it.
- PO allocation is optional, explicit, quantity-conserving, and retains the current non-over-receipt rule.
- Invoice allocation is optional, explicit, same-supplier/same-currency/same-configuration, and cannot exceed the invoice line quantity after prior non-reversed allocations. Invoice status may be draft, reviewed, or approved because physical receipt is independent of charge approval; void invoices are ineligible.
- A direct line without PO or invoice remains attributable to the exact supplier, destination, configuration, and receipt. It is not labeled invoice-backed or ordered supply.
- Actual unit cost remains optional receipt evidence with its own source and currency. Missing cost remains unknown. An invoice amount is not silently promoted to actual unit cost.
- All line/source/item/expected-allocation locks are acquired in deterministic UUID order. Authorization and active-organization state are reread after command lock acquisition.
- Exact retry returns the original receipt and exact line/lot/movement IDs. Same key with changed normalized payload is denied. The entire batch commits or rolls back atomically.

### TA-X4f: atomic multi-line reversal

Add one bounded, idempotent `e10_org_reverse_receipt_batch` API. It reverses every line of one posted receipt atomically, appends one reversal row and any inventory correction movement per line, reverses expected-allocation fulfillment events, and marks every affected lot and the receipt reversed.

Rules:

- A receipt cannot be partly reversed by this checkpoint.
- Reversal is denied if any affected accepted quantity has been consumed, actively lot-reserved, or cannot be removed without violating the legacy item reservation floor.
- PO and invoice allocation rows remain immutable evidence; reversed receipt status removes them from effective received/allocation calculations.
- Replay is stable after later mutable eligibility changes. Changed reason or target under the same key is denied.
- Locks cover the receipt, every line, every lot/item, source allocation, expected allocation, and reservation dependency in deterministic order.

### TA-X4g: reviewed inspection and quarantine disposition

Add an immutable, revisioned inspection/disposition decision relation plus a bounded, idempotent writer for quarantined quantity only. Initial actions are deliberately limited to `accept` and `damage`.

Rules:

- Decisions transfer a positive quantity from the line/lot's unresolved quarantined balance to accepted or damaged disposition. They never exceed the remaining quarantined balance.
- `accept` increases lot accepted quantity and item on-hand through one linked inventory movement in the same transaction.
- `damage` records non-sellable disposition and does not increase on-hand.
- Original receipt quantities are immutable evidence. Effective quantities are derived from the receipt plus disposition decisions, not by rewriting receipt rows.
- Correction is additive through an explicit superseding decision chain. It does not delete history or silently change cost evidence.
- Authorization requires the existing recovery/receiving authority, active organization, permitted destination, and same-organization objects, with post-lock rereads.
- Return-to-vendor, vendor credit, write-off accounting, salvage value, and landed-cost consequences are not asserted by these two actions.

## Acceptance mapping

| Authority or case | Required executable proof |
|---|---|
| PUR-04; Invoice-only intake | Invoice line quantity 12, direct receipt accepted 10 with no PO row created; explicit invoice/receipt allocation 10; visible remaining discrepancy 2; invoice status and approval history unchanged. |
| PUR-04; Split matching | Two receipt lines may link to one invoice line and one receipt may link across eligible PO/invoice lines; effective quantities conserve every source and target without fanout or double counting. Existing X3d invoice-to-PO allocation conservation remains green. |
| PUR-05; partial and multi-line receipt | One atomic receipt posts at least two lines with accepted, damaged, and quarantined quantities; exact items/lots/movements are returned; one invalid line rolls back the whole receipt. |
| PUR-05; inspection/quarantine | Quarantined stock is unavailable; reviewed accept makes only the decided quantity available and appends a movement; reviewed damage remains unavailable; excess and concurrent disposition lose safely. |
| PUR-05; reversal | Multi-line full reversal restores item, lot, expected-allocation, and effective PO/invoice receipt state atomically; any consumed/reserved line blocks the whole reversal; retry is stable. |
| Duplicate document | Exact batch retry creates no duplicate receipt, line, lot, movement, allocation, or event; changed payload under the same key fails with no residue. |
| Location restriction | Foreign or unauthorized destination ID is denied; advisory delivery text cannot override the location; permission or organization suspension after a real lock wait is reread and denied. |
| Historical cost | Direct and PO receipts retain exact configuration version, cost source/date/currency, and unknown cost. Invoice linkage alone does not create actual-cost evidence. |
| Manual price | Explicit receipt cost observation is retained. A later vendor or invoice suggestion cannot silently replace it. |
| Notes audience | Existing X3e vendor projection remains green and contains no new inspection, internal, cost, or allocation metadata. |
| Multi-membership and hostile tenant | Explicit `p_org` succeeds for the selected membership only; foreign supplier, location, PO, invoice, configuration, item, allocation, receipt, lot, and command IDs are denied. |
| Non-card core | One apparel/carton fixture completes direct multi-line receipt, quarantine acceptance, reservation, and reversal without a card/catalog/player dependency. |
| Concurrency | Exact backend wait proofs cover same command key, competing PO/invoice capacity, batch reversal versus reservation/consume, disposition versus disposition, and authority/org suspension after lock wait. |
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
