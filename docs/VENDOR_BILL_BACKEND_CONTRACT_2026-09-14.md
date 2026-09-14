# Vendor bill backend contract

Date: 2026-09-14  
Baseline: `c5fa261bd1ff3d74d104c7cb8eb04c7467b75bdf`  
Scope: backend only; no production or frontend change

## Implemented capability matrix

| Capability | State | Contract |
|---|---|---|
| Reviewer/approver separation | Implemented | Invoice and credit approval requires an actor different from the actor who reviewed the same current revision. |
| Quantity grain | Implemented | Each configuration version has immutable `quantity_increment`; purchasing, allocation, receipt, lot, reservation and disposition writers reject off-grain quantities. Legacy discrete configurations map explicitly to `1`. |
| Receipt cost provenance | Implemented | Operator-entered receipt cost is provisional. Approved invoice support is a separate append-only evidence record. Neither implies payment. Zero-accepted damaged lines retain their receipt value but do not create positive-quantity cost evidence. |
| Global bill register | Implemented | Financially scoped, cursor-paginated invoice headers with stable null-date handling, filters and full filtered-dataset totals by currency. Payment remains `unavailable_not_modeled`. |
| Bill detail | Implemented | Bounded lines plus product/configuration, PO, receipt, credit, revision and source-document links. |
| Invoice after receipt | Implemented | Governed quantity link/release command changes matching evidence only and cannot receive stock again. |
| Duplicate/conflict decision | Implemented | One immutable reviewed disposition per financial reconciliation case with safe replay. |
| Document capture | Implemented | Tenant-scoped immutable document, attachment, source hash, processing attempt, raw/normalized extraction, event and review records. |
| Provider-neutral extraction | Implemented boundary | Service-only result recorder supports deterministic fixtures, retries and failures. Extracted content is untrusted draft data and performs no domain write. No live provider is claimed. |
| Operator corrections | Implemented | Reviewed payload and corrections are immutable; reviewed results must be passed to an existing invoice, credit, receipt or PO writer and then linked. |
| Typed vendor inbound | Implemented boundary | Stable connection, kind, external identity, revision and fingerprint. Exact replay converges; changed content becomes a review conflict. Order confirmations never create a payable. |
| Header/line/tax/freight reconciliation | Deferred, fail-closed | The repository lacks an approved commercial arithmetic policy for whether charges live as lines or components, tax inclusivity, rounding tolerance and discount sign rules. No automatic reconciliation or approval claim is made until that policy is confirmed. |
| Payment, due, balance and aging | Deferred, unavailable | Requires an authoritative accounting/settlement owner. Approved invoices minus credits is not treated as amount due. |
| Live OCR or vendor integration | Deferred | Requires a selected provider/vendor source, credentials, supported document contract and end-to-end verification. |

## Migrations

- `20260914164617_vendor_bill_contract_guards.sql`
- `20260914165408_vendor_bill_cost_evidence.sql`
- `20260914165613_vendor_bill_register_matching.sql`
- `20260914170127_vendor_document_capture.sql`
- `20260914170435_vendor_bill_detail_inbound.sql`

All are additive. No previously applied migration is rewritten.

## Track B APIs

| Function | Caller | Purpose |
|---|---|---|
| `e10_org_bill_register` | authenticated with active membership and `financial.actual_cost.read` | Global filtered, paginated bill list and totals. |
| `e10_org_bill_detail` | authenticated with active membership and `financial.actual_cost.read` | Bounded invoice detail and linked evidence. |
| `e10_org_link_receipt_to_invoice` | authenticated with active membership, `act.purchasing_prepare` and `financial.actual_cost.read` | Link or release existing receipt quantity without stock effects. |
| `e10_org_decide_financial_document_reconciliation` | authenticated with active membership and `act.purchasing_approve` | Immutable same/different/cannot-determine decision. |
| `e10_org_record_approved_invoice_receipt_cost` | authenticated with active membership, `act.purchasing_approve` and `financial.actual_cost.read` | Add approved-invoice-supported cost evidence. |
| `e10_org_capture_vendor_document` | authenticated with active membership and `act.purchasing_prepare` | Capture an immutable tenant document and attachment. |
| `e10_org_review_vendor_document` | authenticated with active membership and `act.purchasing_prepare` | Preserve operator-reviewed draft and correction evidence. |
| `e10_org_link_vendor_document` | authenticated with active membership and `act.purchasing_prepare` | Link a reviewed document to an object created by an ordinary domain writer. |
| `e10_org_record_vendor_extraction` | service role only | Record one provider-neutral extraction attempt. |
| `e10_org_record_vendor_inbound` | service role only | Record typed external messages and changed-payload conflicts. |

All public functions deny `anon`. Definer functions recheck authority after advisory locks where a user-authorized commit occurs. Raw documents, extraction text and internal evidence tables have no direct authenticated table grants.

## State boundaries

- Invoice workflow status, physical receipt status, matching/dispute state and payment state remain independent.
- Extraction success does not approve a bill, create inventory, mark payment or invoke a domain writer.
- An order confirmation is an expectation document, not a payable.
- Linking an invoice to an earlier receipt changes matching evidence only.
- Currency is matched exactly. No conversion occurs.
- Existing invoice and credit revision writers remain the only financial-document mutation path.
- Existing receipt writers remain the only stock-receipt path.

## Remaining owner decisions

1. Choose the accounting system that owns posting, payments and balances, or explicitly choose a separate Element 10 operational payment register.
2. Approve the invoice arithmetic model: component versus line representation, tax-inclusion semantics, discount signs, freight treatment and permitted rounding tolerance.
3. Select the first real vendor/document source and extraction provider, including retention and attachment-storage policy.
4. Decide treatment of already-paid retail receipts and non-inventory expenses.

Until those decisions are recorded, the backend reports payment as unavailable, performs no automatic arithmetic approval, and claims no live vendor integration.

## Verification contract

The focused tests are:

- `tests/vendor_bill_contract_guards_test.sql`
- `tests/vendor_bill_cost_evidence_test.sql`
- `tests/vendor_bill_register_matching_test.sql`
- `tests/vendor_document_capture_test.sql`

They run in CI with existing X3/X4 SQL and concurrency suites. Passing backend evidence is not self-acceptance and does not imply that a frontend workflow exists.
