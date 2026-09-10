-- TA-X3b immutable document-revision gate. Self-failing and rolled back.
begin;
do $$
declare
  o uuid:='e1000000-0000-4000-8000-0000000000a6'; ob uuid:='e1000000-0000-4000-8000-00000000e3c0';
  supplier uuid:=gen_random_uuid(); location uuid:=gen_random_uuid(); po uuid:=gen_random_uuid(); inv uuid:=gen_random_uuid(); receipt uuid:=gen_random_uuid(); credit uuid:=gen_random_uuid();
  t text; c bigint;
begin
  insert into public.e10_organizations(id,name,slug) values(ob,'X3b Org B','x3b-org-b');
  insert into public.e10_suppliers(id,organization_id,name) values(supplier,o,'X3b Supplier');
  insert into public.e10_locations(id,organization_id,name) values(location,o,'X3b Location');
  insert into public.e10_purchase_orders(id,organization_id,supplier_id,destination_location_id,currency) values(po,o,supplier,location,'CAD');
  insert into public.e10_supplier_invoices(id,organization_id,supplier_id,currency) values(inv,o,supplier,'CAD');
  insert into public.e10_stock_receipts(id,organization_id,supplier_id,destination_location_id) values(receipt,o,supplier,location);
  insert into public.e10_supplier_credits(id,organization_id,supplier_id,currency,total_amount) values(credit,o,supplier,'CAD',1);
  insert into public.e10_purchase_order_revisions(organization_id,purchase_order_id,revision,status,snapshot,payload_fingerprint) values(o,po,1,'draft','{"lines":[]}','po-1');
  insert into public.e10_supplier_invoice_revisions(organization_id,supplier_invoice_id,revision,status,snapshot,payload_fingerprint) values(o,inv,1,'draft','{"lines":[]}','inv-1');
  insert into public.e10_stock_receipt_revisions(organization_id,stock_receipt_id,revision,status,snapshot,payload_fingerprint) values(o,receipt,1,'draft','{"lines":[]}','receipt-1');
  insert into public.e10_supplier_credit_revisions(organization_id,supplier_credit_id,revision,status,snapshot,payload_fingerprint) values(o,credit,1,'draft','{"lines":[]}','credit-1');
  foreach t in array array['e10_purchase_order_revisions','e10_supplier_invoice_revisions','e10_stock_receipt_revisions','e10_supplier_credit_revisions'] loop
    execute format('select count(*) from public.%I',t) into c; if c<>1 then raise exception 'missing revision row in %',t; end if;
    begin execute format('update public.%I set change_reason=%L',t,'rewrite'); raise exception 'revision update allowed on %',t; exception when sqlstate '55000' then null; end;
    begin execute format('delete from public.%I',t); raise exception 'revision delete allowed on %',t; exception when sqlstate '55000' then null; end;
  end loop;
  begin insert into public.e10_purchase_order_revisions(organization_id,purchase_order_id,revision,status,snapshot,payload_fingerprint) values(o,po,1,'draft','{}','duplicate'); raise exception 'duplicate revision allowed'; exception when unique_violation then null; end;
  begin insert into public.e10_purchase_order_revisions(organization_id,purchase_order_id,revision,status,snapshot,payload_fingerprint) values(ob,po,2,'draft','{}','cross-org'); raise exception 'cross-org revision allowed'; exception when foreign_key_violation then null; end;
  raise notice 'TA-X3b immutable document revisions: PASS (4/4, duplicate and cross-org denied)';
end $$;

set local role authenticated;
do $$ declare t text; begin
  foreach t in array array['e10_purchase_order_revisions','e10_supplier_invoice_revisions','e10_stock_receipt_revisions','e10_supplier_credit_revisions'] loop
    begin execute format('select 1 from public.%I',t); raise exception 'authenticated can read %',t; exception when insufficient_privilege then null; end;
  end loop;
  raise notice 'TA-X3b revision privacy: PASS';
end $$;
reset role;
rollback;
