-- TA-X3d.0 financial workflow storage gate. Self-failing and rolled back.
begin;

do $$
declare
  o uuid:='e1000000-0000-4000-8000-0000000000a6';
  ob uuid:=gen_random_uuid(); supplier uuid:=gen_random_uuid(); supplier_b uuid:=gen_random_uuid(); location uuid:=gen_random_uuid();
  product uuid:=gen_random_uuid(); config uuid:=gen_random_uuid(); version uuid:=gen_random_uuid();
  po uuid:=gen_random_uuid(); po_line uuid:=gen_random_uuid();
  invoice uuid:=gen_random_uuid(); invoice_line uuid:=gen_random_uuid(); invoice_b uuid:=gen_random_uuid();
  credit uuid:=gen_random_uuid(); credit_line uuid:=gen_random_uuid();
  invoice_event uuid:=gen_random_uuid(); credit_event uuid:=gen_random_uuid(); actor uuid:=gen_random_uuid();
  invoice_release uuid:=gen_random_uuid(); credit_release uuid:=gen_random_uuid();
begin
  insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at)
    values(actor,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',actor||'@x3d.invalid',now(),now());
  insert into public.e10_organizations(id,name,slug) values(ob,'X3d foreign','x3d-foreign');
  insert into public.e10_suppliers(id,organization_id,name,status) values
    (supplier,o,'X3d supplier','active'),(supplier_b,ob,'X3d foreign supplier','active');
  insert into public.e10_locations(id,organization_id,name,status) values(location,o,'X3d location','active');
  insert into public.e10_product_masters(id,organization_id,name) values(product,o,'X3d product');
  insert into public.e10_product_configurations(id,organization_id,product_master_id,name)
    values(config,o,product,'X3d unit');
  insert into public.e10_product_configuration_versions
    (id,organization_id,configuration_id,version_no,state,packaging_kind,base_unit,base_units_per_package)
    values(version,o,config,1,'active','unit','unit',1);
  insert into public.e10_purchase_orders
    (id,organization_id,supplier_id,destination_location_id,order_number,status,currency)
    values(po,o,supplier,location,'X3D-PO','approved','CAD');
  insert into public.e10_purchase_order_lines
    (id,organization_id,purchase_order_id,configuration_version_id,line_no,ordered_quantity,state)
    values(po_line,o,po,version,1,5,'active');

  begin
    insert into public.e10_supplier_invoices(organization_id,supplier_id,currency,total_amount)
      values(o,supplier,'CAD',10);
    raise exception 'manual invoice without identity review accepted';
  exception when foreign_key_violation or check_violation then null; end;

  insert into public.e10_supplier_invoices
    (id,organization_id,supplier_id,supplier_document_number,currency,total_amount)
    values(invoice,o,supplier,' Inv-01 ','CAD',50);
  insert into public.e10_supplier_invoices
    (id,organization_id,supplier_id,supplier_document_number,currency,total_amount)
    values(invoice_b,ob,supplier_b,'INV-FOREIGN','CAD',50);
  begin
    insert into public.e10_supplier_invoices
      (organization_id,supplier_id,supplier_document_number,currency,total_amount)
      values(o,supplier,'inv-01','CAD',50);
    raise exception 'normalized manual invoice duplicate accepted';
  exception when unique_violation then null; end;
  insert into public.e10_supplier_invoice_lines
    (id,organization_id,supplier_invoice_id,configuration_version_id,line_no,invoiced_quantity,unit_cost,line_amount)
    values(invoice_line,o,invoice,version,1,5,10,50);
  begin
    update public.e10_supplier_invoices set approved_by=actor where id=invoice;
    raise exception 'mixed-null invoice approval metadata accepted';
  exception when check_violation then null; end;
  update public.e10_supplier_invoices set status='reviewed',reviewed_by=actor,reviewed_at=now() where id=invoice;
  update public.e10_supplier_invoices set status='draft' where id=invoice;

  insert into public.e10_supplier_credits
    (id,organization_id,supplier_id,currency,total_amount,duplicate_review_outcome,duplicate_review_reason)
    values(credit,o,supplier,'CAD',10,'confirmed_distinct','No supplier document number was issued.');
  insert into public.e10_supplier_credit_lines
    (id,organization_id,supplier_credit_id,configuration_version_id,line_no,description,line_amount)
    values(credit_line,o,credit,version,1,'X3d credit',10);
  begin
    update public.e10_supplier_credits set voided_at=now() where id=credit;
    raise exception 'mixed-null credit void metadata accepted';
  exception when check_violation then null; end;

  insert into public.e10_supplier_invoices
    (organization_id,supplier_id,currency,total_amount,identity_legacy_unresolved_at)
    values(o,supplier,'CAD',1,transaction_timestamp());
  set local session_replication_role=replica;
  insert into public.e10_supplier_credits
    (organization_id,supplier_id,supplier_document_number,currency,total_amount)
    values(o,supplier,'LEGACY-DUP','CAD',1),(o,supplier,'legacy-dup','CAD',2);
  set local session_replication_role=origin;
  update public.e10_supplier_credits set total_amount=3
    where organization_id=o and lower(btrim(supplier_document_number))='legacy-dup';

  insert into public.e10_invoice_po_allocation_events
    (id,organization_id,invoice_line_id,purchase_order_line_id,operation,quantity_delta,reason,command_idempotency_key)
    values(invoice_event,o,invoice_line,po_line,'allocate',2,'initial match','x3d-invoice-allocate');
  insert into public.e10_financial_allocation_commands
    (organization_id,idempotency_key,allocation_kind,operation,allocation_event_id,request_fingerprint,result)
    values(o,'x3d-invoice-allocate','invoice_to_po','allocate',invoice_event,'fp',
      jsonb_build_object('allocation_event_id',invoice_event::text));

  insert into public.e10_credit_invoice_allocation_events
    (id,organization_id,credit_line_id,invoice_line_id,operation,amount_delta,reason,command_idempotency_key)
    values(credit_event,o,credit_line,invoice_line,'allocate',10,'initial credit match','x3d-credit-allocate');
  insert into public.e10_financial_allocation_commands
    (organization_id,idempotency_key,allocation_kind,operation,allocation_event_id,request_fingerprint,result)
    values(o,'x3d-credit-allocate','credit_to_invoice','allocate',credit_event,'fp',
      jsonb_build_object('allocation_event_id',credit_event::text));
  set constraints all immediate;

  insert into public.e10_financial_document_commands
    (organization_id,idempotency_key,document_kind,operation,document_id,request_fingerprint,result)
    values
      (o,'x3d-invoice-create','supplier_invoice','create',invoice,'fp-invoice',
        jsonb_build_object('supplier_invoice_id',invoice::text)),
      (o,'x3d-credit-create','supplier_credit','create',credit,'fp-credit',
        jsonb_build_object('supplier_credit_id',credit::text));

  set constraints all deferred;
  insert into public.e10_invoice_po_allocation_events
    (id,organization_id,invoice_line_id,purchase_order_line_id,operation,quantity_delta,reason,command_idempotency_key)
    values(invoice_release,o,invoice_line,po_line,'release',-1,'partial release','x3d-invoice-release');
  insert into public.e10_financial_allocation_commands
    (organization_id,idempotency_key,allocation_kind,operation,allocation_event_id,request_fingerprint,result)
    values(o,'x3d-invoice-release','invoice_to_po','release',invoice_release,'fp-release',
      jsonb_build_object('allocation_event_id',invoice_release::text));
  insert into public.e10_credit_invoice_allocation_events
    (id,organization_id,credit_line_id,invoice_line_id,operation,amount_delta,reason,command_idempotency_key)
    values(credit_release,o,credit_line,invoice_line,'release',-5,'partial release','x3d-credit-release');
  insert into public.e10_financial_allocation_commands
    (organization_id,idempotency_key,allocation_kind,operation,allocation_event_id,request_fingerprint,result)
    values(o,'x3d-credit-release','credit_to_invoice','release',credit_release,'fp-release',
      jsonb_build_object('allocation_event_id',credit_release::text));
  set constraints all immediate;

  begin
    insert into public.e10_financial_document_commands
      (organization_id,idempotency_key,document_kind,operation,document_id,request_fingerprint,result)
      values(o,'x3d-missing-result','supplier_invoice','create',invoice,'fp','{}');
    raise exception 'financial document command without required result ID accepted';
  exception when check_violation then null; end;
  begin
    insert into public.e10_financial_document_commands
      (organization_id,idempotency_key,document_kind,operation,document_id,request_fingerprint,result)
      values(o,'x3d-foreign-target','supplier_invoice','create',invoice_b,'fp',
        jsonb_build_object('supplier_invoice_id',invoice_b::text));
    raise exception 'financial document command accepted foreign-organization real target';
  exception when check_violation then null; end;
  begin
    insert into public.e10_financial_document_commands
      (organization_id,idempotency_key,document_kind,operation,document_id,request_fingerprint,result)
      values(o,'x3d-wrong-kind','supplier_credit','create',invoice,'fp',
        jsonb_build_object('supplier_credit_id',invoice::text));
    raise exception 'financial document command accepted wrong-kind real target';
  exception when check_violation then null; end;
  begin
    insert into public.e10_financial_document_reconciliation_cases
      (organization_id,document_kind,identity_kind,source_connection,external_document_id,
       existing_document_id,existing_fingerprint,received_fingerprint)
      values(o,'supplier_invoice','connected','provider','missing',gen_random_uuid(),'old','new');
    raise exception 'reconciliation case accepted nonexistent target';
  exception when check_violation then null; end;
  insert into public.e10_financial_document_reconciliation_cases
    (organization_id,document_kind,identity_kind,supplier_id,normalized_document_number,
     existing_document_id,existing_fingerprint,received_fingerprint)
    values(o,'supplier_invoice','manual',supplier,'inv-01',invoice,'old','new');
  begin
    insert into public.e10_credit_invoice_allocation_events
      (organization_id,credit_line_id,invoice_line_id,operation,amount_delta,reason,command_idempotency_key)
      values(o,credit_line,invoice_line,'release',-1,'extra wrong-kind event','x3d-invoice-allocate');
    raise exception 'extra wrong-kind event accepted for invoice allocation command';
  exception when check_violation then null; end;
  begin
    insert into public.e10_invoice_po_allocation_events
      (organization_id,invoice_line_id,purchase_order_line_id,operation,quantity_delta,reason,command_idempotency_key)
      values(o,invoice_line,po_line,'allocate',1,'missing command','x3d-missing-command');
    raise exception 'allocation event without command accepted';
  exception when foreign_key_violation or check_violation then null; end;

  begin
    update public.e10_invoice_po_allocation_events set reason='rewritten' where id=invoice_event;
    raise exception 'allocation evidence mutated';
  exception when sqlstate '55000' then null; end;
  begin
    insert into public.e10_invoice_po_allocation_events
      (organization_id,invoice_line_id,purchase_order_line_id,operation,quantity_delta,reason,command_idempotency_key)
      values(ob,invoice_line,po_line,'allocate',1,'cross org','x3d-cross-org');
    raise exception 'cross-organization allocation evidence accepted';
  exception when foreign_key_violation then null; end;

  if (select count(*) from public.e10_financial_allocation_commands where organization_id=o)<>4
    or (select count(*) from public.e10_invoice_po_allocation_events where organization_id=o)<>2
    or (select count(*) from public.e10_credit_invoice_allocation_events where organization_id=o)<>2 then
    raise exception 'financial allocation evidence reconciliation failed';
  end if;
  raise notice 'TA-X3d.0 financial workflow foundation: PASS (identity, stable lines, append-only allocation/release evidence, tenant FKs)';
end $$;

set local role authenticated;
do $$
declare t text; n bigint;
begin
  perform set_config('request.jwt.claims',jsonb_build_object('sub','00000000-0000-0000-0000-000000000001','role','authenticated')::text,true);
  foreach t in array array[
    'e10_financial_document_commands','e10_financial_document_reconciliation_cases',
    'e10_financial_allocation_commands','e10_invoice_po_allocation_events',
    'e10_credit_invoice_allocation_events'
  ] loop
    begin
      execute format('select count(*) from public.%I',t) into n;
      raise exception 'client-closed table % unexpectedly selectable (% rows)',t,n;
    exception when insufficient_privilege then null; end;
  end loop;
  begin
    insert into public.e10_financial_document_commands
      (organization_id,idempotency_key,document_kind,operation,document_id,request_fingerprint,result)
      values(gen_random_uuid(),'x','supplier_invoice','create',gen_random_uuid(),'x','{}');
    raise exception 'direct financial command insert allowed';
  exception when insufficient_privilege then null; end;
end $$;
reset role;

do $$
declare t text;
begin
  foreach t in array array[
    'e10_financial_document_commands','e10_financial_document_reconciliation_cases',
    'e10_financial_allocation_commands','e10_invoice_po_allocation_events',
    'e10_credit_invoice_allocation_events'
  ] loop
    if not (select c.relrowsecurity from pg_class c where c.oid=('public.'||t)::regclass)
      or has_table_privilege('anon','public.'||t,'select')
      or has_table_privilege('authenticated','public.'||t,'select') then
      raise exception 'RLS/ACL closure failed for %',t;
    end if;
  end loop;
  if has_function_privilege('anon','e10.guard_financial_allocation_command()','execute')
    or has_function_privilege('authenticated','e10.guard_financial_allocation_command()','execute') then
    raise exception 'allocation command guard exposed';
  end if;
  raise notice 'TA-X3d.0 fail-closed ACL: PASS';
end $$;

rollback;
