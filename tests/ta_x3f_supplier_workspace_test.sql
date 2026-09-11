\set ON_ERROR_STOP on
begin;
do $$
declare o uuid:=gen_random_uuid();o2 uuid:=gen_random_uuid();actor uuid:=gen_random_uuid();ordinary uuid:=gen_random_uuid();admin_user uuid:=gen_random_uuid();suspended uuid:=gen_random_uuid();no_member uuid:=gen_random_uuid();multi uuid:=gen_random_uuid();foreign_user uuid:=gen_random_uuid();
 role_fin uuid:=gen_random_uuid();role_plain uuid:=gen_random_uuid();role_admin uuid:=gen_random_uuid();role_foreign uuid:=gen_random_uuid();supplier uuid:=gen_random_uuid();supplier2 uuid:=gen_random_uuid();loc uuid:=gen_random_uuid();
 product uuid:=gen_random_uuid();config uuid:=gen_random_uuid();version_id uuid:=gen_random_uuid();po uuid:=gen_random_uuid();pol uuid:=gen_random_uuid();receipt uuid:=gen_random_uuid();rl uuid:=gen_random_uuid();
 invoice_id uuid:=gen_random_uuid();il uuid:=gen_random_uuid();credit_id uuid:=gen_random_uuid();cl uuid:=gen_random_uuid();j jsonb;j2 jsonb;s jsonb;cursor_value text;
begin
 insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at)select u,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',u||'@x3f.invalid',now(),now()from unnest(array[actor,ordinary,admin_user,suspended,no_member,multi,foreign_user])u;
 insert into public.e10_organizations(id,slug,name)values(o,'x3f-'||substr(o::text,1,8),'X3f'),(o2,'x3g-'||substr(o2::text,1,8),'X3f foreign');
 insert into public.e10_organization_roles(id,organization_id,key,name,is_system)values(role_fin,o,'fin','Financial',false),(role_plain,o,'plain','Plain',false),(role_admin,o,'admin','Admin',false),(role_foreign,o2,'foreign','Foreign',false);
 insert into public.e10_organization_memberships(organization_id,user_id,role_id,status)values(o,actor,role_fin,'active'),(o,ordinary,role_plain,'active'),(o,admin_user,role_admin,'active'),(o,suspended,role_fin,'suspended'),(o,multi,role_fin,'active'),(o2,multi,role_foreign,'active'),(o2,foreign_user,role_foreign,'active');
 insert into public.e10_organization_role_permissions(organization_id,role_id,capability,allowed)values(o,role_fin,'financial.actual_cost.read',true);
 insert into public.e10_locations(id,organization_id,code,name,status)values(loc,o,'X3F','X3f','active');
 insert into public.e10_suppliers(id,organization_id,code,name,status)values(supplier,o,'X3F-S','Supplier','active'),(supplier2,o2,'X3F-F','Foreign','active');
 insert into public.e10_product_masters(id,organization_id,name,status)values(product,o,'X3f product','active');
 insert into public.e10_product_configurations(id,organization_id,product_master_id,name,status)values(config,o,product,'X3f config','active');
 insert into public.e10_product_configuration_versions(id,organization_id,configuration_id,version_no,state,packaging_kind,base_unit,base_units_per_package)values(version_id,o,config,1,'active','unit','unit',1);
 insert into public.e10_purchase_orders(id,organization_id,supplier_id,destination_location_id,order_number,status,currency,created_by,created_at,approved_revision,approved_by,approved_at)
 values(po,o,supplier,loc,'X3F-PO','approved','CAD',actor,'2026-01-01',1,actor,'2026-01-01');
 insert into public.e10_purchase_order_lines(id,organization_id,purchase_order_id,configuration_version_id,line_no,ordered_quantity,estimated_unit_cost)values(pol,o,po,version_id,1,10,5);
 insert into public.e10_stock_receipts(id,organization_id,supplier_id,destination_location_id,receipt_number,status,received_at,created_by,created_at)
 values(receipt,o,supplier,loc,'X3F-R','posted','2026-01-03',actor,'2026-01-03');
 insert into public.e10_stock_receipt_lines(id,organization_id,stock_receipt_id,configuration_version_id,line_no,received_quantity,accepted_quantity,actual_unit_cost,currency)
 values(rl,o,receipt,version_id,1,4,4,6,'CAD');
 insert into public.e10_receipt_po_allocations(organization_id,receipt_line_id,purchase_order_line_id,allocated_quantity)values(o,rl,pol,4);
 insert into public.e10_supplier_invoices(id,organization_id,supplier_id,supplier_document_number,status,currency,total_amount,created_by,created_at,approved_revision,approved_by,approved_at)
 values(invoice_id,o,supplier,'X3F-I','approved','CAD',50,actor,'2026-01-04',1,actor,'2026-01-04');
 insert into public.e10_supplier_invoice_lines(id,organization_id,supplier_invoice_id,configuration_version_id,line_no,invoiced_quantity,unit_cost,line_amount)values(il,o,invoice_id,version_id,1,10,5,50);
 insert into public.e10_supplier_credits(id,organization_id,supplier_id,supplier_document_number,status,currency,total_amount,created_by,created_at,approved_revision,approved_by,approved_at)
 values(credit_id,o,supplier,'X3F-C','approved','CAD',10,actor,'2026-01-05',1,actor,'2026-01-05');
 insert into public.e10_supplier_credit_lines(id,organization_id,supplier_credit_id,configuration_version_id,line_no,line_amount)values(cl,o,credit_id,version_id,1,10);
 insert into public.e10_credit_invoice_allocations(organization_id,credit_line_id,invoice_line_id,allocated_amount)values(o,cl,il,4);

 perform set_config('request.jwt.claims',jsonb_build_object('sub',ordinary,'role','authenticated')::text,true);set local role authenticated;
 j:=public.e10_org_supplier_workspace(o,supplier,100,null);
 if j->>'financial_access'<>'not_authorized'or j->'financial_summary'<>'null'::jsonb or jsonb_array_length(j->'items')<>2
  or exists(select 1 from jsonb_array_elements(j->'items')x where x->>'kind'in('supplier_invoice','supplier_credit'))
  or exists(select 1 from jsonb_array_elements(j->'items')x where x->>'estimated_total'is not null or x->>'accepted_quantity'is not null)
  then raise exception'ordinary member financial leak %',j;end if;
 begin perform public.e10_org_supplier_actual_cost_history(o,supplier,version_id,'CAD','2026-02-01',10,null);raise exception'ordinary actual cost allowed';exception when insufficient_privilege then null;end;
 reset role;

 perform set_config('request.jwt.claims',jsonb_build_object('sub',admin_user,'role','authenticated')::text,true);set local role authenticated;
 j:=public.e10_org_supplier_workspace(o,supplier,10,null);if jsonb_array_length(j->'items')<>2 or j->>'financial_access'<>'not_authorized'then raise exception'admin operational boundary invalid %',j;end if;
 reset role;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',suspended,'role','authenticated')::text,true);set local role authenticated;
 begin perform public.e10_org_supplier_workspace(o,supplier,10,null);raise exception'suspended member allowed';exception when insufficient_privilege then null;end;
 reset role;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',no_member,'role','authenticated')::text,true);set local role authenticated;
 begin perform public.e10_org_supplier_workspace(o,supplier,10,null);raise exception'no-membership user allowed';exception when insufficient_privilege then null;end;
 reset role;

 perform set_config('request.jwt.claims',jsonb_build_object('sub',actor,'role','authenticated')::text,true);set local role authenticated;
 j:=public.e10_org_supplier_workspace(o,supplier,100,null);s:=(j->'financial_summary')->0;
 if j->>'financial_access'<>'authorized'or jsonb_array_length(j->'items')<>4 or s->>'currency'<>'CAD'
  or(s->>'open_commitment_estimate')::numeric<>30 or(s->>'approved_invoice_amount')::numeric<>50
  or(s->>'approved_credit_amount')::numeric<>10 or(s->>'allocated_approved_credit_amount')::numeric<>4 or(s->>'net_approved_invoice_amount')::numeric<>46
  or(s->>'unused_approved_credit_amount')::numeric<>6 or j->>'payment_status'<>'unavailable_not_modeled'
  or exists(select 1 from jsonb_array_elements(j->'items')x where x->>'payment_status'<>'unavailable_not_modeled')
  then raise exception'financial workspace invalid %',j;end if;
 if not exists(select 1 from jsonb_array_elements(j->'items')x where x->>'kind'='purchase_order'and(x->'line_ids')@>jsonb_build_array(pol))
  or not exists(select 1 from jsonb_array_elements(j->'items')x where x->>'kind'='stock_receipt'and(x->'line_ids')@>jsonb_build_array(rl))
  then raise exception'exact source ids absent %',j;end if;
 j:=public.e10_org_supplier_workspace(o,supplier,1,null);cursor_value:=j->>'next_cursor';
 if jsonb_array_length(j->'items')<>1 or cursor_value is null then raise exception'page one missing %',j;end if;
 j2:=public.e10_org_supplier_workspace(o,supplier,1,cursor_value);
 if jsonb_array_length(j2->'items')<>1 or j2#>>'{items,0,id}'=j#>>'{items,0,id}'then raise exception'page two invalid % %',j,j2;end if;
 j:=public.e10_org_supplier_actual_cost_history(o,supplier,version_id,'CAD','2026-02-01',10,null);
 if jsonb_array_length(j->'items')<>1 or j#>>'{items,0,receipt_id}'<>receipt::text or j#>>'{items,0,receipt_line_id}'<>rl::text
  or(j#>>'{items,0,actual_unit_cost}')::numeric<>6 or j->>'conversion'<>'none_exact_currency_only'then raise exception'actual cost evidence invalid %',j;end if;
 begin perform public.e10_org_supplier_workspace(o,supplier,101,null);raise exception'unbounded workspace accepted';exception when invalid_parameter_value then null;end;
 begin perform public.e10_org_supplier_workspace(o,supplier,10,'forged');raise exception'forged cursor accepted';exception when invalid_parameter_value then null;end;
 reset role;

 perform set_config('request.jwt.claims',jsonb_build_object('sub',multi,'role','authenticated')::text,true);set local role authenticated;
 j:=public.e10_org_supplier_workspace(o,supplier,10,null);if j->>'financial_access'<>'authorized'then raise exception'multi-member explicit org denied';end if;
 begin perform public.e10_org_supplier_workspace(o2,supplier2,1,cursor_value);raise exception'cursor survived organization switch';exception when invalid_parameter_value then null;end;
 begin perform public.e10_org_supplier_workspace(o2,supplier,10,null);raise exception'foreign supplier accepted';exception when invalid_parameter_value then null;end;
 reset role;delete from public.e10_organization_role_permissions where organization_id=o and role_id=role_fin and capability='financial.actual_cost.read';set local role authenticated;
 j:=public.e10_org_supplier_workspace(o,supplier,10,null);if j->>'financial_access'<>'not_authorized'then raise exception'revoked financial access remained';end if;
 begin perform public.e10_org_supplier_actual_cost_history(o,supplier,version_id,'CAD','2026-02-01',10,null);raise exception'revoked actual cost allowed';exception when insufficient_privilege then null;end;
 reset role;

 perform set_config('request.jwt.claims',jsonb_build_object('sub',foreign_user,'role','authenticated')::text,true);set local role authenticated;
 begin perform public.e10_org_supplier_workspace(o,supplier,10,null);raise exception'hostile org read allowed';exception when insufficient_privilege then null;end;
 reset role;
 if has_function_privilege('anon','public.e10_org_supplier_workspace(uuid,uuid,integer,text)','execute')or has_function_privilege('public','public.e10_org_supplier_workspace(uuid,uuid,integer,text)','execute')
  or has_function_privilege('anon','public.e10_org_supplier_actual_cost_history(uuid,uuid,uuid,text,timestamptz,integer,text)','execute')then raise exception'X3f anonymous ACL open';end if;
end $$;
rollback;
select 'TA-X3f supplier workspace PASS' result;
