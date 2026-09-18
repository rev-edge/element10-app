# Modular product scope: Inventory and Cards

Status: owner-confirmed product requirements, September 14, 2026. This confirms intended behavior, not implementation, deployment or acceptance. Track A must reconcile current code and environments before claiming support. Existing inventory, cost, tenancy, authorization and audit invariants remain binding.

## Module boundaries

- Inventory is the shared source of owned stock, including sealed products, singles, slabs and other inventory. Preserve a specialized Cards view inside Inventory.
- Provide a separate dedicated Cards workspace/module for card catalog and checklists, owned singles/slabs, card-specific sorting/filtering, price analysis and preparation/management of individual-card channel listings. It is not merely the Cards filter inside Inventory.
- Cards reads and operates on the same owned-item records as Inventory. Acquisition, quantity, location, cost, reservation and disposition must not acquire a second ledger or duplicate records. An authorized change through either workspace is reflected in both.
- Catalog/checklist identities can exist without shop ownership. Multiple physical copies link to the same identity while retaining separate condition, grading/certification, acquisition and cost lineage. Incomplete catalog matching must not block basic intake or invent an exact identity.
- Per-channel listings are separate linked records for the same owned item. Website/eBay publishing is intended scope, subject to supported integration contracts and explicit authorized actions. It is not a claim that a connector is implemented. A confirmed sale must reconcile shared availability and other channel listings with visible retry/failure handling; displaying the same item twice must never double stock or valuation.
- Keep acquisition cost, asking price, completed sale evidence and estimated market value distinct. Internal/manual data remains useful without an external feed.

## Independent adoption and progressive complexity

A customer may use basic Inventory and supplier invoices without adopting advanced purchasing, breaking, catalog analysis or publishing. Inventory alone must still support basic owned cards. The dedicated Cards workspace adds specialization without requiring data migration or re-entry. A Cards-focused package may reuse shared inventory services without exposing every Inventory workflow. Shared service dependency does not by itself decide commercial packaging.

Treat these as separate controls:
1. Organization module entitlements: which product capabilities are enabled.
2. Workflow configuration: which supported operational paths apply, such as direct purchase without a PO.
3. User/workspace presentation: Everyday versus Advanced information and controls, separately from row density. Same records and business rules; progressive disclosure must retain important exceptions and next actions.
4. Role/capability authorization: which actions and fields a person may access. Hiding a control is not enforcement; Advanced is not a permission upgrade.

Basic intake should require only facts needed for the selected action and its existing invariants. Offer understandable defaults and optional enrichment instead of requiring checklists, multi-location setup, supplier-code mapping or break preparation. A sole permitted location can be preselected. Missing cost is unknown, never silently zero. Invoice entry without a PO is valid; invoice approval alone never receives stock or proves payment.

Enabling richer modules or presentation preserves stable IDs and all history. Disabling a module preserves records and must explicitly handle active commitments; it cannot silently delete history or strand shared Inventory. Preserve access to authorized basic card inventory when specialized Cards functionality is disabled. Exact commercial bundles and downgrade policy remain decisions to reconcile.

## Required acceptance scenarios

| ID | Scenario | Required result |
|---|---|---|
| MOD-01 | Basic Inventory plus invoices; Cards, breaks and advanced purchasing unused | Add a basic item, record a supplier invoice without a PO, receive actual stock through the authorized receipt action, and find both records. No fabricated PO or checklist prerequisite. |
| MOD-02 | Add a single/slab through Inventory, then open Cards | Same owned-item ID and cost/quantity/history; no second acquisition. |
| MOD-03 | Authorized edit through Cards, then revisit Inventory | Both surfaces show the same underlying update and audit history. |
| MOD-04 | Browse an unowned checklist card; acquire two copies | Browsing creates no stock; acquisition creates distinct copies linked to one identity, with separate cert/condition/cost where applicable. |
| MOD-05 | Switch Everyday/Advanced and change density | Same records, permissions and totals; presentation changes independently; critical exceptions stay apparent. |
| MOD-06 | Enable Cards after basic Inventory use | Existing owned cards become available without duplication, migration or re-entry. Unresolved identity stays explicit. |
| MOD-07 | Disable Cards with owned cards and an active listing | Basic inventory remains available; history preserved; active listing handling is explicit, not silently abandoned. |
| MOD-08 | List one copy on two supported channels; simultaneous sale attempts | One stock unit and one successful disposition; concurrent/replayed events cannot double-sell. Other-channel reconciliation and failure state are visible. |
| MOD-09 | Role or entitlement revoked while a task is open | Commit rechecks current authority; neither presentation mode nor stale UI bypasses it. |
| MOD-10 | Solo owner uses basic invoices | Report compatibility with current reviewer/approver separation. Do not silently remove the guard; identify the precise owner policy decision if this path is blocked. |

## Track A reconciliation deliverable

Produce an evidence-backed matrix for MOD-01 through MOD-10: implemented locally, staging-verified, production-verified, partial, missing or conflicting. Cite exact code/contracts/tests and commit/environment. Separate UI requirements from backend gaps, existing generic core from card-specific legacy seams, entitlements from presentation preferences, and catalog identity from owned copies. Identify required changes, migration/backfill implications, dependencies and unresolved business decisions. Reconcile active domain, roadmap, board and handoff documents without rewriting historical acceptance. This scope capture authorizes reconciliation and documentation, not new production rollout or unreviewed changes to financial/approval rules.
