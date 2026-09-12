-- TA-X3a.1 authority corrective.
-- act.view_financial_estimates does not imply permission to read actual
-- invoice, receipt-cost, credit, or allocation records. Keep these server-only
-- until an explicit actual-cost/financial-read authority is approved.

do $$
declare t text;
begin
  foreach t in array array[
    'e10_supplier_invoices',
    'e10_supplier_invoice_lines',
    'e10_stock_receipt_lines',
    'e10_supplier_credits',
    'e10_supplier_credit_lines',
    'e10_invoice_po_allocations',
    'e10_receipt_po_allocations',
    'e10_receipt_invoice_allocations',
    'e10_credit_invoice_allocations'
  ] loop
    execute format('drop policy if exists %I on public.%I',t||'_financial_sel',t);
    execute format('revoke select on table public.%I from authenticated',t);
  end loop;
end $$;

comment on table public.e10_supplier_invoices is
  'Actual commercial document. Authenticated reads fail closed pending explicit actual-cost/financial-read authority.';
comment on table public.e10_stock_receipt_lines is
  'Receipt quantities and actual cost remain server-only pending separately reviewed redacted operational reads and actual-cost authority.';
