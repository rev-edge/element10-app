# Modular scope reconciliation: Inventory and Cards

Status: documentation-only Track A reconciliation, September 14, 2026. This
document does not implement, deploy, or accept any behavior. It reconciles the
owner-confirmed scope in `MODULAR_SCOPE_2026-09-14.md` against canonical source
at `71864682262b03e9a723583e66eff939c2996f09`, the latest vendor-bill work, and
the environment evidence recorded for that head.

September 16 correction: release checklist creation and maintenance belongs to
the permanent Products workspace. Cards retains specialist catalog browsing,
owned-copy analysis, valuation, and listing workflows. Cards navigation or
entitlement does not automatically control Product/checklist authority. See
`PRODUCT_CHECKLIST_SCOPE_RECONCILIATION_2026-09-16.md` for the staged import,
publication, readiness, and grid delta.

## Evidence boundary

- Local source contains the A6 module/authorization spine, shared product and
  owned-item identity, source-neutral receipts, lot reservation, inventory
  lifecycle, market evidence, native break sale, and vendor-bill series.
- Current-head CI run `34872991640` passed at `7186468`.
- Staging project `csmbjfmoxkexcyssntbg` was explicitly targeted for the five
  vendor-bill migrations. Recorded evidence shows the new quantity increment,
  nine vendor-document tables, and ten functions, with no anonymous execution.
- Production project `ddhkkumiyidorzmajwde` was read-only during the recorded
  check. It still had no `e10` schema and no vendor-document objects. Therefore
  no MOD scenario is production-verified.
- UI behavior is not inferred from tables, functions, tests, or prototypes.

## MOD-01 through MOD-10 matrix

| ID | Result | Exact evidence | Backend and UI remainder |
| --- | --- | --- | --- |
| MOD-01 | Backend implemented locally and staging-supported; UI unproved | `20260912000335_e10_ta_x4e_source_neutral_receipt_batch.sql`; `tests/ta_x4e_receipt_batch_test.sql` proves invoice-only receipt and asserts that no PO allocation was fabricated. `20260914165613_vendor_bill_register_matching.sql`, `20260914170435_vendor_bill_detail_inbound.sql`, and `docs/VENDOR_BILL_BACKEND_CONTRACT_2026-09-14.md` add the current invoice path. | No evidence proves a basic user-facing item, invoice, receipt, and retrieval journey. Basic mode must not introduce a PO, checklist, break, or Cards entitlement prerequisite. |
| MOD-02 | Backend partial; UI missing | `20260910171106_e10_ta_x1_identity_foundation.sql` makes `e10_unique_items` organization-owned and links each copy to the shared inventory item and optionally to `e10_catalog_variants`. `tests/ta_x1_identity_foundation_test.sql` covers card and non-card instances. | There is no verified Inventory-to-Cards navigation proving the same stable owned-item ID, cost, quantity, and history on both surfaces. No duplicate Cards-owned store may be added. |
| MOD-03 | Backend architecture supports one record; end-to-end missing | Both surfaces are required to write the same `e10_inventory_items` / `e10_unique_items` identity and existing append-only histories. The identity migration explicitly describes Cards as optional through `catalog_variant_id`. | No dedicated Cards edit command or dual-surface UI test proves that a permitted change appears in Inventory with the same audit event. Writers must remain governed commands, not direct client table mutation. |
| MOD-04 | Backend identity split implemented; acquisition journey partial | `e10_catalog_variants` can exist without ownership. `e10_unique_items.catalog_variant_id` is optional and non-unique. `tests/ta_x1_identity_foundation_test.sql` proves an unlinked generic copy and catalog-linked physical instances; the index `(organization_id, catalog_variant_id, id)` supports many copies per identity. | Add an acceptance proof that browsing creates zero owned rows, then acquiring two copies creates two stable owned IDs linked to one catalog identity with independent cert/condition/cost. UI is missing. |
| MOD-05 | Missing product behavior | Authorization is independently enforced by backend roles/capabilities; no database evidence makes presentation mode an authority source. | Everyday/Advanced mode and density are UI preferences with no verified implementation. They must preserve query identity, totals, permissions, errors, warnings, and next actions. They must not become entitlements or capability shortcuts. |
| MOD-06 | Backend structurally compatible; lifecycle proof missing | Existing owned items survive independently of `catalog_variant_id`. A6 provides `e10_organization_modules` and `e10.has_module_access`; `tests/a6a2_module_access_test.sql` proves entitlement plus capability is required. `tests/ta_x4h_noncard_core_test.sql` proves Cards disabled while generic inventory receipt, cost, reservation, and history work. | No enable-Cards command/test proves zero row migration, zero duplicate acquisition, stable IDs, and explicit unresolved identity. Cards readers must discover existing eligible owned rows, not copy them. |
| MOD-07 | Missing/contract conflict until policy is chosen | Shared owned inventory and history are not physically dependent on a Cards table, so disabling presentation need not delete them. | No downgrade state machine handles active listings. Disabling Cards must preserve Inventory access and history, block or restrict new card-specialized actions, and explicitly retain, withdraw, or hand off each active listing. Owner must choose commercial downgrade behavior before implementation. |
| MOD-08 | Partial primitives; required channel contract missing | `20260910210000_e10_ta_x5a_typed_intake_lifecycle.sql` recognizes `listing_created`, `listing_published`, and `sale_committed`; `20260911014500_e10_ta_x6g_native_break_sales.sql` and its adversarial test cover a governed native break sale. | There is no first-class per-channel listing relation, connector command, shared availability claim across channels, or durable retry/failure reconciliation. A generic lifecycle event is evidence, not a listing state machine. Add linked listings, idempotent channel events, one final disposition under lock, and an outbox/reconciliation status before claiming multi-channel safety. |
| MOD-09 | Backend substantially implemented; module-specific test still required | A6 `e10.has_module_access` is fail-closed for disabled entitlement or missing capability. `20260912200500_e10_ta_r4_post_lock_authority.sql` and R2 final-lock authority race tests establish the current commit-time recheck pattern. | Every future Cards/listing writer must recheck organization status, entitlement, membership, and exact capability after acquiring its final lock. Add a revocation-mid-command test for each new writer. UI hiding remains non-authoritative. |
| MOD-10 | Conflicting for a sole final approver; safe partial path remains | `20260914164617_vendor_bill_contract_guards.sql` requires non-null reviewer and approver, different identities, and approval of the current revision. `tests/vendor_bill_contract_guards_test.sql` covers this contract. | A solo owner can create/amend the invoice, receive stock, and retain provisional/unknown cost, but cannot alone make invoice evidence approved. Do not weaken the guard implicitly. Owner decision required as described below. |

## Required additive changes and dependencies

1. **Dedicated Cards workspace contract.** Build Cards as a specialized reader
   and governed-command layer over shared owned inventory. It may add card
   catalog, checklist, analysis, and listing records. It must not add another
   stock balance, acquisition, cost, reservation, or disposition ledger.
2. **Stable module transitions.** Add explicit enable/disable commands and tests.
   Enablement discovers existing rows by stable ID. Disablement preserves all
   shared records and produces a disposition for active module-specific
   commitments. No data-copy or backfill should be needed merely to enable the
   workspace.
3. **Channel listing state.** Add an organization-owned listing record linked to
   one owned copy, channel account, remote identity, desired/published state,
   version, and last synchronization result. Add append-only attempts/events and
   an outbox. A sale command must lock the shared owned unit or availability
   claim before committing one disposition, then reconcile all other listings.
   Replays return the same outcome; losing concurrent attempts write no second
   sale or cost fact.
4. **Catalog versus owned aggregation.** Keep platform catalog identity separate
   from organization-owned copies. Readers may aggregate owned count,
   availability, cost, asking price, sale evidence, and market evidence by
   catalog identity only after organization and field-level authorization.
   Unmatched copies remain visible as unresolved; no guessed exact identity.
5. **Presentation independence.** Everyday/Advanced and density belong to user
   or workspace presentation preferences. They do not grant authority or change
   records, totals, required invariants, or exception visibility.
6. **Shared-core extraction.** Reuse identity, owned inventory, location,
   receipt, lot, cost-evidence, reservation, lifecycle, authorization, audit,
   and idempotency services. Vendor document capture is currently vendor-bill
   specific. If generalized later, extract only source, attachment, processing,
   provenance, and review primitives behind typed domain adapters. Do not make
   OCR output, checklist interpretation, or card catalog matching an automatic
   stock/cost write.

## Cards-off behavior

Cards-off must still allow authorized basic Inventory users to create and manage
owned singles, slabs, sealed products, and non-card goods. A catalog match is
optional. Specialized card catalog/checklist/analysis/listing operations may be
hidden and denied when the Cards entitlement is off, but shared Inventory rows,
cost, location, reservations, history, and authorized basic edits remain. The
existing `tests/ta_x4h_noncard_core_test.sql` is useful core evidence, but an
equivalent card-shaped Cards-off test and UI journey are still required.

## Invoice reviewer/approver separation for a solo owner

The technical consequence of the current maker-checker rule is precise: one
identity cannot both review and approve the same current invoice revision. A
sole owner is not blocked from recording an invoice or receiving physical
stock. The invoice remains unapproved, and quantities without approved evidence
remain provisional or unknown for actual cost.

Trent must choose one commercial policy:

1. Require a second qualified human or external accounting approver. This fits
   the existing guard and is the recommended safe default.
2. Permit a narrowly scoped solo-organization exception. This requires a new,
   explicit policy and capability, strong re-authentication, immutable reason
   and evidence, revision binding, conspicuous audit labeling, and tests. It
   must not be inferred from `admin`, and it must not overwrite the ordinary
   reviewer/approver rule.
3. Keep solo invoices permanently unapproved while still permitting receipt
   and provisional-cost workflows.

Until that ruling, fail closed at approval. Do not silently let the same user
fill both identities.

## Migration order if the missing scope is approved

1. Contract-only decision for Cards downgrade and solo invoice approval.
2. Add first-class channel listing, attempt/event, and reconciliation outbox
   structures. No copy of shared stock or cost data.
3. Add service-only, idempotent listing and sale commands with final-lock
   authority and availability rechecks.
4. Add module transition commands and stable-ID/card-off regression tests.
5. Add authorized catalog-to-owned aggregation readers.
6. Implement Inventory and Cards UI surfaces, Everyday/Advanced presentation,
   density, failure handling, and full MOD-01 through MOD-10 browser acceptance.
7. Apply only through the standing local, exact-head CI, explicit staging, and
   independent-review gates. Production requires a separate go/no-go.

No existing applied migration should be rewritten. Any implementation is an
additive, separately reviewed series.

## Authority decisions still required from Trent

- Cards commercial packaging and exact entitlement keys.
- Downgrade behavior for active listings and in-flight publishing attempts.
- Supported v1 sales channels and which system is authoritative for remote
  listing/sale acknowledgement.
- Solo-owner invoice policy from the three choices above.
- Field-level visibility for actual cost versus asking price, completed sale,
  and market estimate in Cards and Inventory.
- Whether catalog aggregation may expose organization-owned counts outside the
  owning organization. Default is no.

## Tests required before implementation can claim the scope

- One acceptance test for every MOD-01 through MOD-10 row, with backend and UI
  evidence reported separately.
- Cards-off basic card and non-card intake, receipt, reservation, cost/history,
  and retrieval.
- Cards enable/disable with stable IDs, unresolved catalog identity, history,
  and an active listing.
- Two copies linked to one catalog variant with independent cert, condition,
  acquisition, and cost.
- Same-row edit visibility and audit identity across Inventory and Cards.
- Everyday/Advanced/density equality for IDs, totals, permissions, exceptions,
  and next actions.
- Concurrent two-channel sale with one disposition, one inventory decrement,
  idempotent replay, loser no-write proof, and visible reconciliation failure.
- Entitlement, membership, role, and organization revocation after command
  start but before final lock/commit.
- Solo invoice tests for the selected policy, including a proof that ordinary
  maker-checker separation remains enforced.

This reconciliation does not self-accept the modular scope and authorizes no
schema or production change.
