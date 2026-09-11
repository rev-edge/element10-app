-- TA-X3d.1a supplier invoice/credit create gate. Self-failing and rolled back.
begin;

do $$
declare
  o constant uuid:='e1000000-0000-4000-8000-0000000000a6';
  ob uuid:='d3100000-0000-4000-8000-0000000000b0';
  role_id uuid:=gen_random_uuid(); low_role uuid:=gen_random_uuid();
begin
  insert into public.e10_organizations(id,name,slug) values(ob,'X3d1a foreign','x3d1a-foreign');
  insert into public.e10_organization_roles(id,organization_id,key,name) values
    (role_id,o,'x3d1a-preparer','X3d1a preparer'),
    (low_role,o,'x3d1a-low','X3d1a low');
  insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at) values
    ('d3100000-0000-4000-8000-000000000001','00000000-0000-0000-0000-000000000000',
      'authenticated','authenticated','x3d1a-prep@example.invalid',now(),now()),
    ('d3100000-0000-4000-8000-000000000002','00000000-0000-0000-0000-000000000000',
      'authenticated','authenticated','x3d1a-low@example.invalid',now(),now());
  insert into public.e10_organization_memberships(organization_id,user_id,role_id,status) values
    (o,'d3100000-0000-4000-8000-000000000001',role_id,'active'),
    (o,'d3100000-0000-4000-8000-000000000002',low_role,'active');
  insert into public.e10_organization_role_permissions(organization_id,role_id,capability,allowed)
    values(o,role_id,'act.purchasing_prepare',true);
  insert into public.e10_suppliers(id,organization_id,name,status) values
    ('d3100000-0000-4000-8000-000000000010',o,'X3d1a supplier','active'),
    ('d3100000-0000-4000-8000-000000000011',ob,'X3d1a foreign supplier','active');
  insert into public.e10_product_masters(id,organization_id,name)
    values('d3100000-0000-4000-8000-000000000020',o,'X3d1a product');
  insert into public.e10_product_configurations(id,organization_id,product_master_id,name)
    values('d3100000-0000-4000-8000-000000000021',o,'d3100000-0000-4000-8000-000000000020','X3d1a unit');
  insert into public.e10_product_configuration_versions
    (id,organization_id,configuration_id,version_no,state,packaging_kind,base_unit,base_units_per_package)
    values('d3100000-0000-4000-8000-000000000022',o,'d3100000-0000-4000-8000-000000000021',
      1,'active','unit','unit',1);
  set local session_replication_role='replica';
  insert into public.e10_supplier_invoices(organization_id,supplier_id,supplier_document_number,currency,total_amount)
    values(o,'d3100000-0000-4000-8000-000000000010','LEGACY-AMB','CAD',1),
      (o,'d3100000-0000-4000-8000-000000000010',' legacy-amb ','CAD',2);
  set local session_replication_role='origin';
end $$;

create temp table x3d1a_results(key text primary key,value jsonb);
grant select,insert on x3d1a_results to authenticated;
insert into x3d1a_results values('baseline',jsonb_build_object(
  'purchase_orders',(select count(*) from public.e10_purchase_orders),
  'stock_receipts',(select count(*) from public.e10_stock_receipts),
  'inventory_movements',(select count(*) from public.e10_inventory_movements)));

set local role authenticated;
do $$
declare
  o constant uuid:='e1000000-0000-4000-8000-0000000000a6';
  invoice_result jsonb; replay_result jsonb; identity_result jsonb; conflict_result jsonb; conflict_replay jsonb;
  credit_result jsonb; connected_result jsonb; connected_conflict jsonb; connected_conflict_replay jsonb;
  invoice_id uuid; credit_id uuid; precise numeric:=123.45678901234567890123456789;
  invoice_lines jsonb:=jsonb_build_array(jsonb_build_object(
    'id','d3100000-0000-4000-8000-000000000031','line_no',1,
    'configuration_version_id','d3100000-0000-4000-8000-000000000022',
    'description','precision line','invoiced_quantity',2.5,'unit_cost',precise,'line_amount',precise));
  credit_lines jsonb:=jsonb_build_array(jsonb_build_object(
    'id','d3100000-0000-4000-8000-000000000032','line_no',1,
    'configuration_version_id','d3100000-0000-4000-8000-000000000022',
    'description','explicit reviewed no-number credit','line_amount',10.00000000000000000001));
begin
  perform set_config('request.jwt.claims',jsonb_build_object(
    'sub','d3100000-0000-4000-8000-000000000001','role','authenticated')::text,true);
  invoice_result:=public.e10_org_create_supplier_invoice(o,
    'd3100000-0000-4000-8000-000000000010',' INV-X3D1A ','CAD','2026-09-11',precise,
    null,null,null,null,null,invoice_lines,'x3d1a-invoice-create');
  invoice_id:=(invoice_result->>'supplier_invoice_id')::uuid;
  if invoice_result->>'status'<>'draft' or invoice_result->>'revision'<>'1'
    or invoice_result->>'replay'<>'false' then raise exception 'invoice create result invalid: %',invoice_result; end if;
  replay_result:=public.e10_org_create_supplier_invoice(o,
    'd3100000-0000-4000-8000-000000000010',' INV-X3D1A ','CAD','2026-09-11',precise,
    null,null,null,null,null,invoice_lines,'x3d1a-invoice-create');
  if replay_result->>'replay'<>'true' or replay_result->>'supplier_invoice_id'<>invoice_id::text then
    raise exception 'idempotent invoice replay failed: %',replay_result; end if;

  identity_result:=public.e10_org_create_supplier_invoice(o,
    'd3100000-0000-4000-8000-000000000010',' INV-X3D1A ','CAD','2026-09-11',precise,
    null,null,null,null,null,invoice_lines,'x3d1a-invoice-identity-replay');
  if identity_result->>'identity_replay'<>'true' or identity_result->>'supplier_invoice_id'<>invoice_id::text then
    raise exception 'manual identity replay failed: %',identity_result; end if;

  conflict_result:=public.e10_org_create_supplier_invoice(o,
    'd3100000-0000-4000-8000-000000000010','inv-x3d1a','CAD','2026-09-11',precise+1,
    null,null,null,null,null,invoice_lines,'x3d1a-invoice-conflict');
  if conflict_result->>'status'<>'requires_review' or conflict_result->>'ok'<>'false' then
    raise exception 'changed manual identity was not preserved for review: %',conflict_result;
  end if;
  conflict_replay:=public.e10_org_create_supplier_invoice(o,
    'd3100000-0000-4000-8000-000000000010','inv-x3d1a','CAD','2026-09-11',precise+1,
    null,null,null,null,null,invoice_lines,'x3d1a-invoice-conflict-replay');
  if conflict_replay->>'reconciliation_replay'<>'true'
    or conflict_replay->>'reconciliation_case_id'<>conflict_result->>'reconciliation_case_id' then
    raise exception 'manual reconciliation replay did not converge: %',conflict_replay;
  end if;

  credit_result:=public.e10_org_create_supplier_credit(o,
    'd3100000-0000-4000-8000-000000000010',null,'CAD','2026-09-11',10.00000000000000000001,
    null,null,null,'confirmed_distinct','Supplier issued no document number',credit_lines,'x3d1a-credit-create');
  credit_id:=(credit_result->>'supplier_credit_id')::uuid;
  if credit_result->>'status'<>'draft' then
    raise exception 'explicit no-number credit create failed: %',credit_result;
  end if;

  connected_result:=public.e10_org_create_supplier_invoice(o,
    'd3100000-0000-4000-8000-000000000010',null,'CAD','2026-09-11',20,
    'provider-x','external-1','upstream-fp-1',null,null,
    jsonb_build_array(jsonb_build_object('id','d3100000-0000-4000-8000-000000000033',
      'line_no',1,'line_amount',20)),'x3d1a-connected-create');
  connected_conflict:=public.e10_org_create_supplier_invoice(o,
    'd3100000-0000-4000-8000-000000000010',null,'CAD','2026-09-11',21,
    'provider-x','external-1','upstream-fp-2',null,null,
    jsonb_build_array(jsonb_build_object('id','d3100000-0000-4000-8000-000000000033',
      'line_no',1,'line_amount',21)),'x3d1a-connected-conflict');
  if connected_conflict->>'status'<>'requires_review' then
    raise exception 'changed connected identity did not enter reconciliation';
  end if;
  connected_conflict_replay:=public.e10_org_create_supplier_invoice(o,
    'd3100000-0000-4000-8000-000000000010',null,'CAD','2026-09-11',21,
    'provider-x','external-1','upstream-fp-2',null,null,
    jsonb_build_array(jsonb_build_object('id','d3100000-0000-4000-8000-000000000033',
      'line_no',1,'line_amount',21)),'x3d1a-connected-conflict-replay');
  if connected_conflict_replay->>'reconciliation_replay'<>'true'
    or connected_conflict_replay->>'reconciliation_case_id'<>connected_conflict->>'reconciliation_case_id' then
    raise exception 'connected reconciliation replay did not converge';
  end if;

  begin
    perform public.e10_org_create_supplier_invoice(o,'d3100000-0000-4000-8000-000000000010',
      'BAD-LINES','CAD',null,1,null,null,null,null,null,
      jsonb_build_array(jsonb_build_object('line_no',1,'line_amount',1)),'x3d1a-bad-line-id');
    raise exception 'line without stable UUID accepted'; exception when sqlstate '22023' then null; end;
  begin
    perform public.e10_org_create_supplier_invoice(o,'d3100000-0000-4000-8000-000000000010',
      null,'CAD',null,1,null,null,null,null,null,invoice_lines,'x3d1a-missing-identity');
    raise exception 'missing identity review accepted'; exception when sqlstate '22023' then null; end;
  begin
    perform public.e10_org_create_supplier_invoice(o,'d3100000-0000-4000-8000-000000000010',
      'INV-X3D1A','CAD','2026-09-11',precise+2,null,null,null,null,null,
      jsonb_build_array(jsonb_build_object('id','d3100000-0000-4000-8000-000000000031',
        'line_no',1,'invoiced_quantity','2.5','unit_cost','12.50','line_amount',precise)),
      'x3d1a-invalid-existing-lines');
    raise exception 'invalid string numerics reached existing-identity reconciliation';
  exception when sqlstate '22023' then null; end;
  begin
    perform public.e10_org_create_supplier_invoice(o,'d3100000-0000-4000-8000-000000000010',
      'legacy-amb','CAD',null,3,null,null,null,null,null,
      jsonb_build_array(jsonb_build_object('id','d3100000-0000-4000-8000-000000000040',
        'line_no',1,'line_amount',3)),'x3d1a-ambiguous-legacy');
    raise exception 'ambiguous legacy manual identity silently selected a target';
  exception when check_violation then null; end;
  begin
    perform public.e10_org_create_supplier_invoice(o,'d3100000-0000-4000-8000-000000000011',
      'FOREIGN','CAD',null,1,null,null,null,null,null,invoice_lines,'x3d1a-foreign-supplier');
    raise exception 'foreign supplier accepted'; exception when insufficient_privilege then null; end;

  perform set_config('request.jwt.claims',jsonb_build_object(
    'sub','d3100000-0000-4000-8000-000000000002','role','authenticated')::text,true);
  begin
    perform public.e10_org_create_supplier_invoice(o,'d3100000-0000-4000-8000-000000000010',
      'DENIED','CAD',null,1,null,null,null,null,null,invoice_lines,'x3d1a-low-denied');
    raise exception 'member without purchasing_prepare allowed'; exception when insufficient_privilege then null; end;

  insert into x3d1a_results values
    ('invoice',invoice_result),('credit',credit_result),('connected',connected_result);
  raise notice 'TA-X3d.1a authenticated API behavior: PASS';
end $$;
reset role;

do $$
declare
  o constant uuid:='e1000000-0000-4000-8000-0000000000a6';
  invoice_id uuid:=((select value from x3d1a_results where key='invoice')->>'supplier_invoice_id')::uuid;
  credit_id uuid:=((select value from x3d1a_results where key='credit')->>'supplier_credit_id')::uuid;
  connected_id uuid:=((select value from x3d1a_results where key='connected')->>'supplier_invoice_id')::uuid;
  baseline jsonb:=(select value from x3d1a_results where key='baseline');
begin
  if (select id from public.e10_supplier_invoice_lines where supplier_invoice_id=invoice_id)
      <>'d3100000-0000-4000-8000-000000000031'
    or (select line_amount from public.e10_supplier_invoice_lines where supplier_invoice_id=invoice_id)
      <>123.45678901234567890123456789 then
    raise exception 'invoice stable line identity or numeric precision lost';
  end if;
  if (select total_amount from public.e10_supplier_invoices where id=invoice_id)
      <>123.45678901234567890123456789
    or (select count(*) from public.e10_financial_document_reconciliation_cases
      where existing_document_id=invoice_id and identity_kind='manual')<>1
    or (select count(*) from public.e10_financial_document_reconciliation_cases
      where existing_document_id=connected_id and identity_kind='connected')<>1 then
    raise exception 'identity conflict persistence or original preservation failed';
  end if;
  if (select (received_snapshot->>'total_amount')::numeric
      from public.e10_financial_document_reconciliation_cases
      where existing_document_id=invoice_id and identity_kind='manual')
      <>124.45678901234567890123456789
    or (select received_snapshot->'lines'->0->>'id'
      from public.e10_financial_document_reconciliation_cases
      where existing_document_id=invoice_id and identity_kind='manual')
      <>'d3100000-0000-4000-8000-000000000031'
    or exists(select 1 from public.e10_financial_document_commands
      where idempotency_key='x3d1a-invalid-existing-lines') then
    raise exception 'bounded incoming snapshot missing or invalid-line request wrote evidence';
  end if;
  if (select count(*) from public.e10_supplier_credit_lines
      where supplier_credit_id=credit_id and id='d3100000-0000-4000-8000-000000000032')<>1 then
    raise exception 'credit stable line identity lost';
  end if;
  if (select count(*) from public.e10_purchase_orders)<>(baseline->>'purchase_orders')::bigint
    or (select count(*) from public.e10_stock_receipts)<>(baseline->>'stock_receipts')::bigint
    or (select count(*) from public.e10_inventory_movements)<>(baseline->>'inventory_movements')::bigint then
    raise exception 'financial document create fabricated PO, receipt or inventory movement';
  end if;
  if (select count(*) from public.e10_financial_document_events where organization_id=o)<>3
    or (select count(*) from public.e10_supplier_invoice_revisions where organization_id=o
      and supplier_invoice_id in (invoice_id,connected_id))<>2
    or (select count(*) from public.e10_supplier_credit_revisions where organization_id=o
      and supplier_credit_id=credit_id)<>1 then
    raise exception 'create revision/event evidence mismatch';
  end if;
  raise notice 'TA-X3d.1a durable evidence: PASS (reconciliation, stable lines, precision, no operational side effects)';
end $$;

do $$
begin
  if has_table_privilege('anon','public.e10_financial_document_events','select')
    or has_table_privilege('authenticated','public.e10_financial_document_events','select')
    or has_function_privilege('anon','public.e10_org_create_supplier_invoice(uuid,uuid,text,text,date,numeric,text,text,text,text,text,jsonb,text)','execute')
    or has_function_privilege('anon','public.e10_org_create_supplier_credit(uuid,uuid,text,text,date,numeric,text,text,text,text,text,jsonb,text)','execute')
    or has_function_privilege('authenticated','public._e10_org_create_financial_document_x3d1a(uuid,text,uuid,text,text,date,numeric,text,text,text,text,text,jsonb,text)','execute') then
    raise exception 'X3d.1a ACL closure failed';
  end if;
  raise notice 'TA-X3d.1a ACL: PASS';
end $$;

rollback;
