-- TA-X3d.1c review/approve/void transition gate. Self-failing and rolled back.
begin;

do $$
declare
  o constant uuid:='d31d0000-0000-4000-8000-000000000001';
  other_org constant uuid:='d31d0000-0000-4000-8000-000000000002';
  actor constant uuid:='d31d0000-0000-4000-8000-000000000003';
  prepare_only constant uuid:='d31d0000-0000-4000-8000-000000000004';
  suspended_actor constant uuid:='d31d0000-0000-4000-8000-000000000024';
  no_member_actor constant uuid:='d31d0000-0000-4000-8000-000000000025';
  all_role uuid:='d31d0000-0000-4000-8000-000000000005';
  prepare_role uuid:='d31d0000-0000-4000-8000-000000000006';
  suspended_role uuid:='d31d0000-0000-4000-8000-000000000026';
  other_role uuid:='d31d0000-0000-4000-8000-000000000027';
  supplier uuid:='d31d0000-0000-4000-8000-000000000007';
  product_id uuid:='d31d0000-0000-4000-8000-000000000008';
  config_id uuid:='d31d0000-0000-4000-8000-000000000009';
  version_id uuid:='d31d0000-0000-4000-8000-000000000010';
  invoice_id uuid:='d31d0000-0000-4000-8000-000000000011';
  invoice_line uuid:='d31d0000-0000-4000-8000-000000000012';
  void_invoice uuid:='d31d0000-0000-4000-8000-000000000013';
  void_invoice_line uuid:='d31d0000-0000-4000-8000-000000000014';
  credit_id uuid:='d31d0000-0000-4000-8000-000000000015';
  credit_line uuid:='d31d0000-0000-4000-8000-000000000016';
  void_credit uuid:='d31d0000-0000-4000-8000-000000000017';
  void_credit_line uuid:='d31d0000-0000-4000-8000-000000000018';
  result jsonb; replay jsonb; baseline jsonb;
begin
  insert into public.e10_organizations(id,name,slug) values
    (o,'X3d1c org','x3d1c-org'),(other_org,'X3d1c other','x3d1c-other');
  insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at) values
    (actor,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','x3d1c@example.invalid',now(),now()),
    (prepare_only,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','x3d1c-prepare@example.invalid',now(),now()),
    (suspended_actor,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','x3d1c-suspended@example.invalid',now(),now()),
    (no_member_actor,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','x3d1c-none@example.invalid',now(),now());
  insert into public.e10_organization_roles(id,organization_id,key,name) values
    (all_role,o,'x3d1c-all','X3d1c all'),(prepare_role,o,'x3d1c-prepare','X3d1c prepare'),
    (suspended_role,o,'x3d1c-suspended','X3d1c suspended'),
    (other_role,other_org,'x3d1c-other','X3d1c other');
  insert into public.e10_organization_memberships(organization_id,user_id,role_id,status) values
    (o,actor,all_role,'active'),(other_org,actor,other_role,'active'),
    (o,prepare_only,prepare_role,'active'),(o,suspended_actor,suspended_role,'suspended');
  insert into public.e10_organization_role_permissions(organization_id,role_id,capability,allowed) values
    (o,all_role,'act.purchasing_prepare',true),(o,all_role,'act.purchasing_approve',true),
    (o,all_role,'act.purchasing_cancel',true),(o,prepare_role,'act.purchasing_prepare',true),
    (o,suspended_role,'act.purchasing_prepare',true),
    (other_org,other_role,'act.purchasing_prepare',true);
  insert into public.e10_suppliers(id,organization_id,name,status) values(supplier,o,'X3d1c supplier','active');
  insert into public.e10_product_masters(id,organization_id,name) values(product_id,o,'X3d1c product');
  insert into public.e10_product_configurations(id,organization_id,product_master_id,name)
    values(config_id,o,product_id,'X3d1c config');
  insert into public.e10_product_configuration_versions
    (id,organization_id,configuration_id,version_no,state,packaging_kind,base_unit,base_units_per_package)
    values(version_id,o,config_id,1,'active','unit','unit',1);
  insert into public.e10_supplier_invoices
    (id,organization_id,supplier_id,supplier_document_number,currency,total_amount,created_by)
    values(invoice_id,o,supplier,'X3D1C-INV','CAD',10,actor),
      (void_invoice,o,supplier,'X3D1C-VOID-INV','CAD',5,actor);
  insert into public.e10_supplier_invoice_lines
    (id,organization_id,supplier_invoice_id,configuration_version_id,line_no,invoiced_quantity,unit_cost,line_amount)
    values(invoice_line,o,invoice_id,version_id,1,1,10,10),
      (void_invoice_line,o,void_invoice,version_id,1,1,5,5);
  insert into public.e10_supplier_credits
    (id,organization_id,supplier_id,supplier_document_number,currency,total_amount,created_by)
    values(credit_id,o,supplier,'X3D1C-CR','CAD',3,actor),
      (void_credit,o,supplier,'X3D1C-VOID-CR','CAD',2,actor);
  insert into public.e10_supplier_credit_lines
    (id,organization_id,supplier_credit_id,configuration_version_id,line_no,line_amount)
    values(credit_line,o,credit_id,version_id,1,3),
      (void_credit_line,o,void_credit,version_id,1,2);
  baseline:=jsonb_build_object(
    'po',(select count(*) from public.e10_purchase_orders),
    'receipt',(select count(*) from public.e10_stock_receipts),
    'movement',(select count(*) from public.e10_inventory_movements),
    'lot',(select count(*) from public.e10_inventory_lots));

  perform set_config('request.jwt.claims',jsonb_build_object('sub',actor,'role','authenticated')::text,true);
  set local role authenticated;
  result:=public.e10_org_review_supplier_invoice(o,invoice_id,1,'invoice reviewed','x3d1c-invoice-review');
  if result->>'status'<>'reviewed' or result->>'revision'<>'2' then raise exception 'invoice review failed: %',result; end if;
  replay:=public.e10_org_review_supplier_invoice(o,invoice_id,1,'invoice reviewed','x3d1c-invoice-review');
  if replay->>'replay'<>'true' or replay->>'revision'<>'2' then raise exception 'review replay failed: %',replay; end if;
  result:=public.e10_org_approve_supplier_invoice(o,invoice_id,2,'invoice approved','x3d1c-invoice-approve');
  if result->>'status'<>'approved' or result->>'revision'<>'3' then raise exception 'invoice approve failed: %',result; end if;
  replay:=public.e10_org_review_supplier_invoice(o,invoice_id,1,'invoice reviewed','x3d1c-invoice-review');
  if replay->>'replay'<>'true' or replay->>'revision'<>'2' then
    raise exception 'historical review replay failed after approval: %',replay;
  end if;
  begin
    perform public.e10_org_approve_supplier_invoice(o,invoice_id,2,'stale','x3d1c-invoice-stale');
    raise exception 'stale approval accepted'; exception when sqlstate '40001' then null; end;
  begin
    perform public.e10_org_review_supplier_invoice(o,invoice_id,3,'invalid','x3d1c-invoice-invalid');
    raise exception 'approved invoice reviewed again'; exception when sqlstate '55000' then null; end;
  begin
    perform public.e10_org_review_supplier_invoice(o,invoice_id,1,'changed replay','x3d1c-invoice-review');
    raise exception 'changed idempotency payload accepted'; exception when sqlstate '22023' then null; end;

  result:=public.e10_org_review_supplier_credit(o,credit_id,1,'credit reviewed','x3d1c-credit-review');
  if result->>'status'<>'reviewed' or result->>'revision'<>'2' then raise exception 'credit review failed'; end if;
  result:=public.e10_org_approve_supplier_credit(o,credit_id,2,'credit approved','x3d1c-credit-approve');
  if result->>'status'<>'approved' or result->>'revision'<>'3' then raise exception 'credit approve failed'; end if;
  result:=public.e10_org_review_supplier_invoice(o,void_invoice,1,'invoice reviewed before void','x3d1c-void-invoice-review');
  if result->>'status'<>'reviewed' or result->>'revision'<>'2' then raise exception 'void-invoice review failed'; end if;
  result:=public.e10_org_void_supplier_invoice(o,void_invoice,2,'reviewed invoice void','x3d1c-invoice-void');
  if result->>'status'<>'void' or result->>'revision'<>'3' then raise exception 'reviewed invoice void failed'; end if;
  begin
    perform public.e10_org_approve_supplier_credit(o,void_credit,1,'draft cannot approve','x3d1c-draft-approve');
    raise exception 'draft credit approved'; exception when sqlstate '55000' then null; end;
  result:=public.e10_org_void_supplier_credit(o,void_credit,1,'unused credit void','x3d1c-credit-void');
  if result->>'status'<>'void' or result->>'revision'<>'2' then raise exception 'credit void failed'; end if;
  begin
    perform public.e10_org_void_supplier_credit(o,void_credit,2,'repeat void','x3d1c-repeat-void');
    raise exception 'void credit voided again'; exception when sqlstate '55000' then null; end;

  perform set_config('request.jwt.claims',jsonb_build_object('sub',prepare_only,'role','authenticated')::text,true);
  begin
    perform public.e10_org_approve_supplier_invoice(o,invoice_id,3,'not approver','x3d1c-prepare-approve');
    raise exception 'prepare-only actor approved'; exception when insufficient_privilege then null; end;
  begin
    perform public.e10_org_void_supplier_invoice(o,invoice_id,3,'not canceller','x3d1c-prepare-void');
    raise exception 'prepare-only actor voided'; exception when insufficient_privilege then null; end;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',suspended_actor,'role','authenticated')::text,true);
  begin
    perform public.e10_org_review_supplier_invoice(o,invoice_id,3,'suspended','x3d1c-suspended');
    raise exception 'suspended member transitioned document'; exception when insufficient_privilege then null; end;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',no_member_actor,'role','authenticated')::text,true);
  begin
    perform public.e10_org_review_supplier_invoice(o,invoice_id,3,'no membership','x3d1c-no-membership');
    raise exception 'membership-less caller transitioned document'; exception when insufficient_privilege then null; end;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',actor,'role','authenticated')::text,true);
  begin
    perform public.e10_org_review_supplier_invoice(other_org,invoice_id,1,'cross org','x3d1c-cross-org');
    raise exception 'cross-org transition accepted'; exception when insufficient_privilege then null; end;
  reset role;

  if (select approved_revision from public.e10_supplier_invoices where id=invoice_id) is distinct from 3
    or (select approved_by from public.e10_supplier_invoices where id=invoice_id) is distinct from actor
    or (select approved_at from public.e10_supplier_invoices where id=invoice_id) is null
    or (select voided_by from public.e10_supplier_invoices where id=void_invoice) is distinct from actor
    or (select voided_at from public.e10_supplier_invoices where id=void_invoice) is null
    or (select approved_revision from public.e10_supplier_credits where id=credit_id) is distinct from 3
    or (select approved_by from public.e10_supplier_credits where id=credit_id) is distinct from actor
    or (select approved_at from public.e10_supplier_credits where id=credit_id) is null
    or (select voided_by from public.e10_supplier_credits where id=void_credit) is distinct from actor
    or (select voided_at from public.e10_supplier_credits where id=void_credit) is null
    or (select count(*) from public.e10_supplier_invoice_revisions
      where organization_id=o and supplier_invoice_id in (invoice_id,void_invoice))<>4
    or (select count(*) from public.e10_supplier_credit_revisions
      where organization_id=o and supplier_credit_id in (credit_id,void_credit))<>3
    or (select count(*) from public.e10_financial_document_events where organization_id=o)<>7
    or exists(select 1 from public.e10_financial_document_commands where organization_id=o
      and idempotency_key in ('x3d1c-invoice-stale','x3d1c-invoice-invalid','x3d1c-prepare-approve',
        'x3d1c-draft-approve','x3d1c-repeat-void','x3d1c-prepare-void','x3d1c-suspended',
        'x3d1c-no-membership','x3d1c-cross-org')) then
    raise exception 'transition evidence or failure residue invalid';
  end if;
  set constraints all immediate;
  set constraints all deferred;
  if (select count(*) from public.e10_purchase_orders)<>(baseline->>'po')::bigint
    or (select count(*) from public.e10_stock_receipts)<>(baseline->>'receipt')::bigint
    or (select count(*) from public.e10_inventory_movements)<>(baseline->>'movement')::bigint
    or (select count(*) from public.e10_inventory_lots)<>(baseline->>'lot')::bigint then
    raise exception 'financial approval or void created an operational side effect';
  end if;
  if has_function_privilege('anon','public.e10_org_review_supplier_invoice(uuid,uuid,integer,text,text)','execute')
    or has_function_privilege('authenticated','public._e10_org_transition_financial_document_x3d1c(uuid,text,uuid,integer,text,text,text)','execute') then
    raise exception 'X3d.1c ACL closure failed';
  end if;
  raise notice 'TA-X3d.1c review/approve/void, capabilities, CAS, history, no-side-effects: PASS';
end $$;

-- Each current allocation family independently blocks void until explicitly released.
insert into public.e10_credit_invoice_allocations(organization_id,credit_line_id,invoice_line_id,allocated_amount)
values('d31d0000-0000-4000-8000-000000000001','d31d0000-0000-4000-8000-000000000016',
  'd31d0000-0000-4000-8000-000000000012',1);
set local role authenticated;
select set_config('request.jwt.claims',jsonb_build_object(
  'sub','d31d0000-0000-4000-8000-000000000003','role','authenticated')::text,true);
do $$ begin
  begin perform public.e10_org_void_supplier_invoice(
    'd31d0000-0000-4000-8000-000000000001','d31d0000-0000-4000-8000-000000000011',3,
    'credit allocation blocks invoice','x3d1c-credit-block-invoice');
    raise exception 'credit allocation did not block invoice void'; exception when sqlstate '55000' then null; end;
  begin perform public.e10_org_void_supplier_credit(
    'd31d0000-0000-4000-8000-000000000001','d31d0000-0000-4000-8000-000000000015',3,
    'credit allocation blocks credit','x3d1c-credit-block-credit');
    raise exception 'credit allocation did not block credit void'; exception when sqlstate '55000' then null; end;
end $$;
reset role;
delete from public.e10_credit_invoice_allocations
  where organization_id='d31d0000-0000-4000-8000-000000000001';

insert into public.e10_locations(id,organization_id,name,status)
values('d31d0000-0000-4000-8000-000000000019','d31d0000-0000-4000-8000-000000000001','X3d1c location','active');
insert into public.e10_purchase_orders
  (id,organization_id,supplier_id,destination_location_id,order_number,status,currency,created_by)
values('d31d0000-0000-4000-8000-000000000020','d31d0000-0000-4000-8000-000000000001',
  'd31d0000-0000-4000-8000-000000000007','d31d0000-0000-4000-8000-000000000019',
  'X3D1C-PO','approved','CAD','d31d0000-0000-4000-8000-000000000003');
insert into public.e10_purchase_order_lines
  (id,organization_id,purchase_order_id,configuration_version_id,line_no,ordered_quantity)
values('d31d0000-0000-4000-8000-000000000021','d31d0000-0000-4000-8000-000000000001',
  'd31d0000-0000-4000-8000-000000000020','d31d0000-0000-4000-8000-000000000010',1,1);
insert into public.e10_invoice_po_allocations
  (organization_id,invoice_line_id,purchase_order_line_id,allocated_quantity)
values('d31d0000-0000-4000-8000-000000000001','d31d0000-0000-4000-8000-000000000012',
  'd31d0000-0000-4000-8000-000000000021',1);
set local role authenticated;
select set_config('request.jwt.claims',jsonb_build_object(
  'sub','d31d0000-0000-4000-8000-000000000003','role','authenticated')::text,true);
do $$ begin
  begin perform public.e10_org_void_supplier_invoice(
    'd31d0000-0000-4000-8000-000000000001','d31d0000-0000-4000-8000-000000000011',3,
    'PO allocation blocks invoice','x3d1c-po-block');
    raise exception 'PO allocation did not block invoice void'; exception when sqlstate '55000' then null; end;
end $$;
reset role;
delete from public.e10_invoice_po_allocations
  where organization_id='d31d0000-0000-4000-8000-000000000001';

insert into public.e10_stock_receipts
  (id,organization_id,supplier_id,destination_location_id,receipt_number,status,received_at,created_by)
values('d31d0000-0000-4000-8000-000000000022','d31d0000-0000-4000-8000-000000000001',
  'd31d0000-0000-4000-8000-000000000007','d31d0000-0000-4000-8000-000000000019',
  'X3D1C-REC','posted',now(),'d31d0000-0000-4000-8000-000000000003');
insert into public.e10_stock_receipt_lines
  (id,organization_id,stock_receipt_id,configuration_version_id,line_no,received_quantity,accepted_quantity,currency)
values('d31d0000-0000-4000-8000-000000000023','d31d0000-0000-4000-8000-000000000001',
  'd31d0000-0000-4000-8000-000000000022','d31d0000-0000-4000-8000-000000000010',1,1,1,'CAD');
insert into public.e10_receipt_invoice_allocations
  (organization_id,receipt_line_id,invoice_line_id,allocated_quantity)
values('d31d0000-0000-4000-8000-000000000001','d31d0000-0000-4000-8000-000000000023',
  'd31d0000-0000-4000-8000-000000000012',1);
set local role authenticated;
select set_config('request.jwt.claims',jsonb_build_object(
  'sub','d31d0000-0000-4000-8000-000000000003','role','authenticated')::text,true);
do $$ begin
  begin perform public.e10_org_void_supplier_invoice(
    'd31d0000-0000-4000-8000-000000000001','d31d0000-0000-4000-8000-000000000011',3,
    'receipt allocation blocks invoice','x3d1c-receipt-block');
    raise exception 'receipt allocation did not block invoice void'; exception when sqlstate '55000' then null; end;
end $$;
reset role;
delete from public.e10_receipt_invoice_allocations
  where organization_id='d31d0000-0000-4000-8000-000000000001';

-- Approved documents can be voided only after every current allocation is gone.
set local role authenticated;
select set_config('request.jwt.claims',jsonb_build_object(
  'sub','d31d0000-0000-4000-8000-000000000003','role','authenticated')::text,true);
do $$
declare invoice_result jsonb; credit_result jsonb;
begin
  invoice_result:=public.e10_org_void_supplier_invoice(
    'd31d0000-0000-4000-8000-000000000001','d31d0000-0000-4000-8000-000000000011',3,
    'all invoice allocations released','x3d1c-approved-invoice-void');
  credit_result:=public.e10_org_void_supplier_credit(
    'd31d0000-0000-4000-8000-000000000001','d31d0000-0000-4000-8000-000000000015',3,
    'all credit allocations released','x3d1c-approved-credit-void');
  if invoice_result->>'revision'<>'4' or invoice_result->>'status'<>'void'
    or credit_result->>'revision'<>'4' or credit_result->>'status'<>'void' then
    raise exception 'post-release approved void failed';
  end if;
end $$;
reset role;
do $$ begin
  if (select approved_revision from public.e10_supplier_invoices
      where id='d31d0000-0000-4000-8000-000000000011') is not null
    or (select approved_revision from public.e10_supplier_credits
      where id='d31d0000-0000-4000-8000-000000000015') is not null
    or exists(select 1 from public.e10_financial_document_commands
      where idempotency_key in ('x3d1c-credit-block-invoice','x3d1c-credit-block-credit',
        'x3d1c-po-block','x3d1c-receipt-block'))
    or not exists(select 1 from public.e10_supplier_invoice_revisions
      where organization_id='d31d0000-0000-4000-8000-000000000001'
        and supplier_invoice_id='d31d0000-0000-4000-8000-000000000011'
        and revision=3 and status='approved'
        and snapshot->>'revision'='3' and snapshot->>'status'='approved')
    or not exists(select 1 from public.e10_supplier_credit_revisions
      where organization_id='d31d0000-0000-4000-8000-000000000001'
        and supplier_credit_id='d31d0000-0000-4000-8000-000000000015'
        and revision=3 and status='approved'
        and snapshot->>'revision'='3' and snapshot->>'status'='approved') then
    raise exception 'void allocation barrier residue or approval invalidation failed';
  end if;
  set constraints all immediate;
end $$;

rollback;
