-- TA-X3a purchasing document model gate. Self-failing and rolled back.
begin;
do $$
declare o uuid:='e1000000-0000-4000-8000-0000000000a6'; l uuid:=gen_random_uuid(); s uuid:=gen_random_uuid(); p uuid:=gen_random_uuid(); c uuid:=gen_random_uuid(); v uuid:=gen_random_uuid(); po uuid:=gen_random_uuid(); pol uuid:=gen_random_uuid(); inv uuid:=gen_random_uuid(); il uuid:=gen_random_uuid(); r uuid:=gen_random_uuid(); rl uuid:=gen_random_uuid(); cr uuid:=gen_random_uuid(); cl uuid:=gen_random_uuid(); ci uuid:=gen_random_uuid(); cv uuid:=gen_random_uuid(); before_items bigint;
begin
 insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at) values
 ('a7000000-0000-4000-8000-00000000e3a1','00000000-0000-0000-0000-000000000000','authenticated','authenticated','x3low@x.invalid',now(),now()),
 ('a7000000-0000-4000-8000-00000000e3a2','00000000-0000-0000-0000-000000000000','authenticated','authenticated','x3admin@x.invalid',now(),now());
 insert into public.e10_organization_memberships(organization_id,user_id,role_id,status) values
 (o,'a7000000-0000-4000-8000-00000000e3a1','e1000000-0000-4000-8000-000000000003','active'),
 (o,'a7000000-0000-4000-8000-00000000e3a2','e1000000-0000-4000-8000-000000000001','active');
 insert into public.e10_locations(id,organization_id,name) values(l,o,'X3 Receiving');
 insert into public.e10_suppliers(id,organization_id,name) values(s,o,'X3 Supplier');
 insert into public.e10_product_masters(id,organization_id,name) values(p,o,'X3 Product');
 insert into public.e10_product_configurations(id,organization_id,product_master_id,name) values(c,o,p,'X3 Box');
 insert into public.e10_product_configuration_versions(id,organization_id,configuration_id,version_no,state,packaging_kind,base_unit,base_units_per_package) values(v,o,c,1,'active','box','unit',1);
 select count(*) into before_items from public.e10_inventory_items;
 insert into public.e10_purchase_orders(id,organization_id,supplier_id,destination_location_id,order_number,currency,status) values(po,o,s,l,'X3-PO','CAD','approved');
 insert into public.e10_purchase_order_lines(id,organization_id,purchase_order_id,configuration_version_id,line_no,ordered_quantity,estimated_unit_cost) values(pol,o,po,v,1,10,12);
 insert into public.e10_supplier_invoices(id,organization_id,supplier_id,status,currency,total_amount,source_connection,external_document_id,payload_fingerprint) values(inv,o,s,'approved','CAD',120,'x3','invoice-1','fp1');
 insert into public.e10_supplier_invoice_lines(id,organization_id,supplier_invoice_id,configuration_version_id,line_no,invoiced_quantity,unit_cost,line_amount) values(il,o,inv,v,1,10,12,120);
 insert into public.e10_invoice_po_allocations values(o,il,pol,10,now());
 if (select count(*) from public.e10_inventory_items)<>before_items then raise exception 'invoice created stock'; end if;
 insert into public.e10_stock_receipts(id,organization_id,supplier_id,destination_location_id,status,received_at) values(r,o,s,l,'posted',now());
 insert into public.e10_stock_receipt_lines(id,organization_id,stock_receipt_id,configuration_version_id,line_no,received_quantity,accepted_quantity,damaged_quantity,quarantined_quantity,actual_unit_cost,currency) values(rl,o,r,v,1,10,8,1,1,12,'CAD');
 insert into public.e10_receipt_po_allocations values(o,rl,pol,10,now());
 insert into public.e10_receipt_invoice_allocations values(o,rl,il,10,now());
 insert into public.e10_supplier_credits(id,organization_id,supplier_id,status,currency,total_amount) values(cr,o,s,'approved','CAD',12);
 insert into public.e10_supplier_credit_lines(id,organization_id,supplier_credit_id,line_no,line_amount) values(cl,o,cr,1,12);
 insert into public.e10_credit_invoice_allocations values(o,cl,il,12,now());
 insert into public.e10_commercial_comments(id,organization_id,audience,body,purchase_order_id,created_by) values(ci,o,'internal','private note',po,'a7000000-0000-4000-8000-00000000e3a2');
 insert into public.e10_commercial_comments(organization_id,audience,body,purchase_order_id,supersedes_comment_id,created_by) values(o,'vendor','vendor-safe amendment',po,ci,'a7000000-0000-4000-8000-00000000e3a2');
 if (select count(*) from public.e10_commercial_comments where purchase_order_id=po and audience='internal')<>1 or (select count(*) from public.e10_commercial_comments where purchase_order_id=po and audience='vendor')<>1 then raise exception 'comment audiences collapsed'; end if;
 begin update public.e10_commercial_comments set body='mutated' where id=ci; raise exception 'comment update allowed'; exception when object_not_in_prerequisite_state then null; end;
 begin insert into public.e10_supplier_invoices(organization_id,supplier_id,status,currency,source_connection,external_document_id,payload_fingerprint) values(o,s,'draft','CAD','x3','invoice-1','different'); raise exception 'duplicate source accepted'; exception when unique_violation then null; end;
 raise notice 'TA-X3a purchasing documents: PASS (distinct PO/invoice/receipt/credit, explicit allocations, no invoice stock effect, audience split, append-only, source dedup)';
end $$;

set local role authenticated;
do $$ declare c int; begin
 perform set_config('request.jwt.claims',json_build_object('sub','a7000000-0000-4000-8000-00000000e3a1','role','authenticated')::text,true);
 select count(*) into c from public.e10_purchase_orders where order_number='X3-PO'; if c<>1 then raise exception 'low role cannot read operational header'; end if;
 select count(*) into c from public.e10_purchase_order_lines; if c<>0 then raise exception 'low role can read estimated costs'; end if;
 select count(*) into c from public.e10_supplier_invoices; if c<>0 then raise exception 'low role can read invoices'; end if;
 begin perform 1 from public.e10_commercial_comments; raise exception 'low role can read comments'; exception when insufficient_privilege then null; end;
 perform set_config('request.jwt.claims',json_build_object('sub','a7000000-0000-4000-8000-00000000e3a2','role','authenticated')::text,true);
 select count(*) into c from public.e10_supplier_invoices; if c<>1 then raise exception 'financial admin cannot read invoice'; end if;
 raise notice 'TA-X3a same-org financial privacy: PASS';
end $$;
reset role;
rollback;
