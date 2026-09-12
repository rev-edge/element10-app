\set ON_ERROR_STOP on
begin;
\ir ta_x8_business_state_helper.sql
do $$
declare o uuid:=gen_random_uuid();o2 uuid:=gen_random_uuid();actor uuid:=gen_random_uuid();ordinary uuid:=gen_random_uuid();admin_user uuid:=gen_random_uuid();suspended uuid:=gen_random_uuid();no_member uuid:=gen_random_uuid();multi uuid:=gen_random_uuid();foreign_user uuid:=gen_random_uuid();bs jsonb;
 role_fin uuid:=gen_random_uuid();role_plain uuid:=gen_random_uuid();role_admin uuid:=gen_random_uuid();role_foreign uuid:=gen_random_uuid();supplier uuid:=gen_random_uuid();supplier2 uuid:=gen_random_uuid();supplier_unknown uuid:=gen_random_uuid();supplier_full uuid:=gen_random_uuid();supplier_other uuid:=gen_random_uuid();supplier_states uuid:=gen_random_uuid();loc uuid:=gen_random_uuid();
 product uuid:=gen_random_uuid();config uuid:=gen_random_uuid();version_id uuid:=gen_random_uuid();version2 uuid:=gen_random_uuid();po uuid:=gen_random_uuid();pol uuid:=gen_random_uuid();pol_unknown uuid:=gen_random_uuid();receipt uuid:=gen_random_uuid();rl uuid:=gen_random_uuid();
 po_u uuid:=gen_random_uuid();pol_u uuid:=gen_random_uuid();po_f uuid:=gen_random_uuid();pol_f uuid:=gen_random_uuid();receipt_f uuid:=gen_random_uuid();rl_f uuid:=gen_random_uuid();
 po_draft uuid:=gen_random_uuid();po_submitted uuid:=gen_random_uuid();po_approved uuid:=gen_random_uuid();po_cancelled uuid:=gen_random_uuid();po_closed uuid:=gen_random_uuid();
 pol_draft uuid:=gen_random_uuid();pol_submitted uuid:=gen_random_uuid();pol_approved uuid:=gen_random_uuid();pol_cancelled uuid:=gen_random_uuid();pol_closed uuid:=gen_random_uuid();receipt_state uuid:=gen_random_uuid();rl_state uuid:=gen_random_uuid();
 invoice_id uuid:=gen_random_uuid();invoice_usd uuid:=gen_random_uuid();il uuid:=gen_random_uuid();credit_id uuid:=gen_random_uuid();cl uuid:=gen_random_uuid();
 r2 uuid:=gen_random_uuid();rl2 uuid:=gen_random_uuid();rrev uuid:=gen_random_uuid();rlrev uuid:=gen_random_uuid();rzero uuid:=gen_random_uuid();rlzero uuid:=gen_random_uuid();rnone uuid:=gen_random_uuid();rlnone uuid:=gen_random_uuid();rfuture uuid:=gen_random_uuid();rlfuture uuid:=gen_random_uuid();rusd uuid:=gen_random_uuid();rlusd uuid:=gen_random_uuid();rconfig uuid:=gen_random_uuid();rlconfig uuid:=gen_random_uuid();rother uuid:=gen_random_uuid();rlother uuid:=gen_random_uuid();
 j jsonb;j2 jsonb;s jsonb;s_usd jsonb;po_body jsonb;summary_full jsonb;cursor_value text;x8ctx uuid;
begin
 insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at)select u,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',u||'@x3f.invalid',now(),now()from unnest(array[actor,ordinary,admin_user,suspended,no_member,multi,foreign_user])u;
 insert into public.e10_organizations(id,slug,name)values(o,'x3f-'||substr(o::text,1,8),'X3f'),(o2,'x3g-'||substr(o2::text,1,8),'X3f foreign');
 insert into public.e10_organization_roles(id,organization_id,key,name,is_system)values(role_fin,o,'fin','Financial',false),(role_plain,o,'plain','Plain',false),(role_admin,o,'admin','Admin',false),(role_foreign,o2,'foreign','Foreign',false);
 insert into public.e10_organization_memberships(organization_id,user_id,role_id,status)values(o,actor,role_fin,'active'),(o,ordinary,role_plain,'active'),(o,admin_user,role_admin,'active'),(o,suspended,role_fin,'suspended'),(o,multi,role_fin,'active'),(o2,multi,role_foreign,'active'),(o2,foreign_user,role_foreign,'active');
 insert into public.e10_organization_role_permissions(organization_id,role_id,capability,allowed)values(o,role_fin,'financial.actual_cost.read',true);
 insert into public.e10_locations(id,organization_id,code,name,status)values(loc,o,'X3F','X3f','active');
 insert into public.e10_suppliers(id,organization_id,code,name,status)values(supplier,o,'X3F-S','Supplier','active'),(supplier_unknown,o,'X3F-U','Unknown supplier','active'),(supplier_full,o,'X3F-C','Complete supplier','active'),(supplier_other,o,'X3F-O','Other supplier','active'),(supplier_states,o,'X3F-ST','State supplier','active'),(supplier2,o2,'X3F-F','Foreign','active');
 insert into public.e10_product_masters(id,organization_id,name,status)values(product,o,'X3f product','active');
 insert into public.e10_product_configurations(id,organization_id,product_master_id,name,status)values(config,o,product,'X3f config','active');
 insert into public.e10_product_configuration_versions(id,organization_id,configuration_id,version_no,state,packaging_kind,base_unit,base_units_per_package)values(version_id,o,config,1,'active','unit','unit',1),(version2,o,config,2,'retired','unit','unit',1);
 insert into public.e10_purchase_orders(id,organization_id,supplier_id,destination_location_id,order_number,status,currency,created_by,created_at,approved_revision,approved_by,approved_at)
 values(po,o,supplier,loc,'X3F-PO','approved','CAD',actor,'2026-01-01',1,actor,'2026-01-01');
 insert into public.e10_purchase_order_lines(id,organization_id,purchase_order_id,configuration_version_id,line_no,ordered_quantity,estimated_unit_cost)values(pol,o,po,version_id,1,10,5),(pol_unknown,o,po,version_id,2,2,null);
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
 insert into public.e10_supplier_invoices(id,organization_id,supplier_id,supplier_document_number,status,currency,total_amount,created_by,created_at,approved_revision,approved_by,approved_at)
 values(invoice_usd,o,supplier,'X3F-USD','approved','USD',20,actor,'2026-01-06',1,actor,'2026-01-06');

 insert into public.e10_purchase_orders(id,organization_id,supplier_id,destination_location_id,order_number,status,currency,created_by,created_at)values
  (po_u,o,supplier_unknown,loc,'X3F-U','approved','CAD',actor,'2026-01-01'),(po_f,o,supplier_full,loc,'X3F-FULL','approved','CAD',actor,'2026-01-01');
 insert into public.e10_purchase_order_lines(id,organization_id,purchase_order_id,configuration_version_id,line_no,ordered_quantity,estimated_unit_cost)values(pol_u,o,po_u,version_id,1,2,null),(pol_f,o,po_f,version_id,1,3,null);
 insert into public.e10_stock_receipts(id,organization_id,supplier_id,destination_location_id,receipt_number,status,received_at,created_by,created_at)values(receipt_f,o,supplier_full,loc,'X3F-FULL-R','posted','2026-01-02',actor,'2026-01-02');
 insert into public.e10_stock_receipt_lines(id,organization_id,stock_receipt_id,configuration_version_id,line_no,received_quantity,accepted_quantity)values(rl_f,o,receipt_f,version_id,1,3,3);
 insert into public.e10_receipt_po_allocations(organization_id,receipt_line_id,purchase_order_line_id,allocated_quantity)values(o,rl_f,pol_f,3);

 insert into public.e10_purchase_orders(id,organization_id,supplier_id,destination_location_id,order_number,status,currency,created_by,created_at)values
  (po_draft,o,supplier_states,loc,'X3F-DRAFT','draft','CAD',actor,'2026-01-01'),
  (po_submitted,o,supplier_states,loc,'X3F-SUBMITTED','submitted','CAD',actor,'2026-01-02'),
  (po_approved,o,supplier_states,loc,'X3F-APPROVED','approved','CAD',actor,'2026-01-03'),
  (po_cancelled,o,supplier_states,loc,'X3F-CANCELLED','cancelled','CAD',actor,'2026-01-04'),
  (po_closed,o,supplier_states,loc,'X3F-CLOSED','closed','CAD',actor,'2026-01-05');
 insert into public.e10_purchase_order_lines(id,organization_id,purchase_order_id,configuration_version_id,line_no,ordered_quantity,estimated_unit_cost)values
  (pol_draft,o,po_draft,version_id,1,2,10),(pol_submitted,o,po_submitted,version_id,1,3,10),(pol_approved,o,po_approved,version_id,1,4,10),
  (pol_cancelled,o,po_cancelled,version_id,1,5,10),(pol_closed,o,po_closed,version_id,1,6,10);
 insert into public.e10_stock_receipts(id,organization_id,supplier_id,destination_location_id,receipt_number,status,received_at,created_by,created_at)
  values(receipt_state,o,supplier_states,loc,'X3F-ST-R','posted','2026-01-06',actor,'2026-01-06');
 insert into public.e10_stock_receipt_lines(id,organization_id,stock_receipt_id,configuration_version_id,line_no,received_quantity,accepted_quantity,actual_unit_cost,currency)
  values(rl_state,o,receipt_state,version_id,1,1,1,10,'CAD');
 insert into public.e10_receipt_po_allocations(organization_id,receipt_line_id,purchase_order_line_id,allocated_quantity)values(o,rl_state,pol_approved,1);

 perform set_config('request.jwt.claims',jsonb_build_object('sub',ordinary,'role','authenticated')::text,true);set local role authenticated;
 j:=public.e10_org_supplier_workspace(o,supplier,100,null);
 if j->>'financial_access'is distinct from'not_authorized'or j->'financial_summary'is distinct from'null'::jsonb or jsonb_array_length(j->'items')is distinct from 2
  or exists(select 1 from jsonb_array_elements(j->'items')x where x->>'kind'in('supplier_invoice','supplier_credit'))
  or exists(select 1 from jsonb_array_elements(j->'items')x where x->>'ordered_estimate_total'is not null or x->>'ordered_estimate_known_subtotal'is not null
   or x->>'open_commitment_estimate'is not null or x->>'open_commitment_known_subtotal'is not null
   or x->>'open_commitment_unknown_line_count'is not null or x->>'open_commitment_unknown_quantity'is not null or x->>'accepted_quantity'is not null)
  then raise exception'ordinary member financial leak %',j;end if;
 begin perform public.e10_org_supplier_actual_cost_history(o,supplier,version_id,'CAD','2026-02-01',10,null);raise exception'ordinary actual cost allowed';exception when insufficient_privilege then null;end;
 reset role;

 perform set_config('request.jwt.claims',jsonb_build_object('sub',admin_user,'role','authenticated')::text,true);set local role authenticated;
 j:=public.e10_org_supplier_workspace(o,supplier,10,null);if jsonb_array_length(j->'items')is distinct from 2 or j->>'financial_access'is distinct from'not_authorized'then raise exception'admin operational boundary invalid %',j;end if;
 reset role;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',suspended,'role','authenticated')::text,true);set local role authenticated;
 begin perform public.e10_org_supplier_workspace(o,supplier,10,null);raise exception'suspended member allowed';exception when insufficient_privilege then null;end;
 reset role;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',no_member,'role','authenticated')::text,true);set local role authenticated;
 begin perform public.e10_org_supplier_workspace(o,supplier,10,null);raise exception'no-membership user allowed';exception when insufficient_privilege then null;end;
 reset role;

 perform set_config('request.jwt.claims',jsonb_build_object('sub',actor,'role','authenticated')::text,true);set local role authenticated;
 x8ctx:=(public.e10_org_create_query_context(o,'workspace',600,'x8-x3f')->>'context_id')::uuid;
 bs:=pg_temp.x8_business_state();j:=public.e10_org_typed_query(o,x8ctx,'supplier.workspace',jsonb_build_object('supplier_id',supplier,'limit',100));if pg_temp.x8_business_state()is distinct from bs then raise exception'X8 supplier workspace changed business data';end if;perform pg_temp.x8_assert_envelope(j,'supplier.workspace','supplier_document');if jsonb_array_length(j#>'{result,items}')<>5 then raise exception'X8 supplier workspace dispatch %',j;end if;
 bs:=pg_temp.x8_business_state();j:=public.e10_org_typed_query(o,x8ctx,'supplier.actual_cost_history',jsonb_build_object('supplier_id',supplier,'configuration_version_id',version_id,'currency','CAD','as_of','2026-02-01T00:00:00Z','limit',10));if pg_temp.x8_business_state()is distinct from bs then raise exception'X8 supplier cost changed business data';end if;perform pg_temp.x8_assert_envelope(j,'supplier.actual_cost_history','accepted_receipt_cost_evidence');if jsonb_array_length(j#>'{result,items}')<1 then raise exception'X8 supplier cost dispatch %',j;end if;
 j:=public.e10_org_supplier_workspace(o,supplier,100,null);summary_full:=j->'financial_summary';select value into s from jsonb_array_elements(summary_full)where value->>'currency'='CAD';select value into s_usd from jsonb_array_elements(summary_full)where value->>'currency'='USD';select value into po_body from jsonb_array_elements(j->'items')where value->>'kind'='purchase_order';
 if j->>'financial_access'is distinct from'authorized'or jsonb_array_length(j->'items')is distinct from 5 or s is null or s_usd is null
  or s->>'open_commitment_status'is distinct from'incomplete'or(s->>'open_commitment_known_subtotal')::numeric is distinct from 30
  or(s->>'open_commitment_unknown_line_count')::integer is distinct from 1 or(s->>'open_commitment_unknown_quantity')::numeric is distinct from 2
  or s->'open_commitment_estimate'is distinct from'null'::jsonb or(s->>'approved_invoice_amount')::numeric is distinct from 50
  or(s->>'approved_credit_amount')::numeric is distinct from 10 or(s->>'allocated_approved_credit_amount')::numeric is distinct from 4 or(s->>'net_approved_invoice_amount')::numeric is distinct from 46
  or(s->>'unused_approved_credit_amount')::numeric is distinct from 6 or(s_usd->>'approved_invoice_amount')::numeric is distinct from 20
  or(s_usd->>'approved_credit_amount')::numeric is distinct from 0 or j->>'payment_status'is distinct from'unavailable_not_modeled'
  or po_body->>'ordered_estimate_status'is distinct from'incomplete'or(po_body->>'ordered_estimate_known_subtotal')::numeric is distinct from 50
  or(po_body->>'ordered_estimate_unknown_line_count')::integer is distinct from 1 or po_body->'ordered_estimate_total'is distinct from'null'::jsonb
  or po_body->>'open_commitment_status'is distinct from'incomplete'or(po_body->>'open_commitment_known_subtotal')::numeric is distinct from 30
  or(po_body->>'open_commitment_unknown_line_count')::integer is distinct from 1 or(po_body->>'open_commitment_unknown_quantity')::numeric is distinct from 2
  or po_body->'open_commitment_estimate'is distinct from'null'::jsonb
  or exists(select 1 from jsonb_array_elements(j->'items')x where x->>'payment_status'is distinct from'unavailable_not_modeled')
  then raise exception'financial workspace invalid %',j;end if;
 if not exists(select 1 from jsonb_array_elements(j->'items')x where x->>'kind'='purchase_order'and(x->'line_ids')@>jsonb_build_array(pol))
  or not exists(select 1 from jsonb_array_elements(j->'items')x where x->>'kind'='stock_receipt'and(x->'line_ids')@>jsonb_build_array(rl))
  then raise exception'exact source ids absent %',j;end if;
 j:=public.e10_org_supplier_workspace(o,supplier,1,null);cursor_value:=j->>'next_cursor';
 if jsonb_array_length(j->'items')is distinct from 1 or cursor_value is null then raise exception'page one missing %',j;end if;
 if j->'financial_summary'is distinct from summary_full then raise exception'page one summary changed %',j;end if;
 j2:=public.e10_org_supplier_workspace(o,supplier,1,cursor_value);
 if jsonb_array_length(j2->'items')is distinct from 1 or j2#>>'{items,0,id}'is not distinct from j#>>'{items,0,id}'or j2->'financial_summary'is distinct from summary_full then raise exception'page two invalid % %',j,j2;end if;
 j:=public.e10_org_supplier_workspace(o,supplier_unknown,10,null);select value into s from jsonb_array_elements(j->'financial_summary')where value->>'currency'='CAD';select value into po_body from jsonb_array_elements(j->'items')where value->>'kind'='purchase_order';
 if s->>'open_commitment_status'is distinct from'incomplete'or(s->>'open_commitment_known_subtotal')::numeric is distinct from 0 or(s->>'open_commitment_unknown_line_count')::integer is distinct from 1 or s->'open_commitment_estimate'is distinct from'null'::jsonb
  or po_body->>'ordered_estimate_status'is distinct from'incomplete'or(po_body->>'ordered_estimate_unknown_line_count')::integer is distinct from 1 or po_body->'ordered_estimate_total'is distinct from'null'::jsonb
  or po_body->>'open_commitment_status'is distinct from'incomplete'or(po_body->>'open_commitment_unknown_line_count')::integer is distinct from 1 or po_body->'open_commitment_estimate'is distinct from'null'::jsonb then raise exception'all-unknown commitment not fail-closed %',j;end if;
 j:=public.e10_org_supplier_workspace(o,supplier_full,10,null);select value into s from jsonb_array_elements(j->'financial_summary')where value->>'currency'='CAD';select value into po_body from jsonb_array_elements(j->'items')where value->>'kind'='purchase_order';
 if s->>'open_commitment_status'is distinct from'complete'or(s->>'open_commitment_unknown_line_count')::integer is distinct from 0 or(s->>'open_commitment_estimate')::numeric is distinct from 0
  or po_body->>'ordered_estimate_status'is distinct from'incomplete'or(po_body->>'ordered_estimate_unknown_line_count')::integer is distinct from 1 or po_body->'ordered_estimate_total'is distinct from'null'::jsonb
  or po_body->>'open_commitment_status'is distinct from'complete'or(po_body->>'open_commitment_unknown_line_count')::integer is distinct from 0 or(po_body->>'open_commitment_estimate')::numeric is distinct from 0 then raise exception'fully received unknown commitment not zero %',j;end if;

 j:=public.e10_org_supplier_workspace(o,supplier_states,20,null);select value into s from jsonb_array_elements(j->'financial_summary')where value->>'currency'='CAD';
 if(s->>'open_commitment_estimate')::numeric is distinct from 60 then raise exception'header-state supplier open commitment invalid %',j;end if;
 select value into po_body from jsonb_array_elements(j->'items')where value->>'id'=po_draft::text;
 if(po_body->>'ordered_estimate_total')::numeric is distinct from 20 or(po_body->>'open_commitment_estimate')::numeric is distinct from 0 then raise exception'draft PO estimate split invalid %',po_body;end if;
 select value into po_body from jsonb_array_elements(j->'items')where value->>'id'=po_submitted::text;
 if(po_body->>'ordered_estimate_total')::numeric is distinct from 30 or(po_body->>'open_commitment_estimate')::numeric is distinct from 30 then raise exception'submitted PO estimate split invalid %',po_body;end if;
 select value into po_body from jsonb_array_elements(j->'items')where value->>'id'=po_approved::text;
 if(po_body->>'ordered_estimate_total')::numeric is distinct from 40 or(po_body->>'open_commitment_estimate')::numeric is distinct from 30 then raise exception'approved partial PO estimate split invalid %',po_body;end if;
 select value into po_body from jsonb_array_elements(j->'items')where value->>'id'=po_cancelled::text;
 if(po_body->>'ordered_estimate_total')::numeric is distinct from 50 or(po_body->>'open_commitment_estimate')::numeric is distinct from 0 then raise exception'cancelled PO estimate split invalid %',po_body;end if;
 select value into po_body from jsonb_array_elements(j->'items')where value->>'id'=po_closed::text;
 if(po_body->>'ordered_estimate_total')::numeric is distinct from 60 or(po_body->>'open_commitment_estimate')::numeric is distinct from 0 then raise exception'closed PO estimate split invalid %',po_body;end if;

 reset role;
 insert into public.e10_stock_receipts(id,organization_id,supplier_id,destination_location_id,status,received_at,created_by,created_at)values
  (r2,o,supplier,loc,'posted','2026-01-02',actor,'2026-01-02'),
  (rrev,o,supplier,loc,'reversed','2026-01-04',actor,'2026-01-04'),
  (rzero,o,supplier,loc,'posted','2026-01-05',actor,'2026-01-05'),
  (rnone,o,supplier,loc,'posted','2026-01-06',actor,'2026-01-06'),
  (rfuture,o,supplier,loc,'posted','2026-03-01',actor,'2026-03-01'),
  (rusd,o,supplier,loc,'posted','2026-01-07',actor,'2026-01-07'),
  (rconfig,o,supplier,loc,'posted','2026-01-08',actor,'2026-01-08'),
  (rother,o,supplier_other,loc,'posted','2026-01-09',actor,'2026-01-09');
 insert into public.e10_stock_receipt_lines(id,organization_id,stock_receipt_id,configuration_version_id,line_no,received_quantity,accepted_quantity,damaged_quantity,actual_unit_cost,currency)values
  (rl2,o,r2,version_id,1,2,2,0,5,'CAD'),
  (rlrev,o,rrev,version_id,1,1,1,0,7,'CAD'),
  (rlzero,o,rzero,version_id,1,1,0,1,7,'CAD'),
  (rlnone,o,rnone,version_id,1,1,1,0,null,'CAD'),
  (rlfuture,o,rfuture,version_id,1,1,1,0,8,'CAD'),
  (rlusd,o,rusd,version_id,1,1,1,0,9,'USD'),
  (rlconfig,o,rconfig,version2,1,1,1,0,10,'CAD'),
  (rlother,o,rother,version_id,1,1,1,0,11,'CAD');
 set local role authenticated;
 j:=public.e10_org_supplier_actual_cost_history(o,supplier,version_id,'CAD','2026-02-01',10,null);
 if jsonb_array_length(j->'items')is distinct from 2 or not exists(select 1 from jsonb_array_elements(j->'items')x where x->>'receipt_line_id'=rl::text and(x->>'actual_unit_cost')::numeric=6)
  or not exists(select 1 from jsonb_array_elements(j->'items')x where x->>'receipt_line_id'=rl2::text and(x->>'actual_unit_cost')::numeric=5)
  or exists(select 1 from jsonb_array_elements(j->'items')x where(x->>'receipt_line_id')::uuid=any(array[rlrev,rlzero,rlnone,rlfuture,rlusd,rlconfig,rlother]))
  or j->>'conversion'is distinct from'none_exact_currency_only'then raise exception'actual cost eligibility invalid %',j;end if;
 j:=public.e10_org_supplier_actual_cost_history(o,supplier,version_id,'CAD','2026-02-01',1,null);cursor_value:=j->>'next_cursor';
 if jsonb_array_length(j->'items')is distinct from 1 or cursor_value is null then raise exception'actual cost page one invalid %',j;end if;
 j2:=public.e10_org_supplier_actual_cost_history(o,supplier,version_id,'CAD','2026-02-01',1,cursor_value);
 if jsonb_array_length(j2->'items')is distinct from 1 or j2#>>'{items,0,receipt_line_id}'is not distinct from j#>>'{items,0,receipt_line_id}'then raise exception'actual cost page two invalid % %',j,j2;end if;
 begin perform public.e10_org_supplier_workspace(o,supplier,101,null);raise exception'unbounded workspace accepted';exception when invalid_parameter_value then null;end;
 begin perform public.e10_org_supplier_workspace(o,supplier,10,'forged');raise exception'forged cursor accepted';exception when invalid_parameter_value then null;end;
 reset role;

 update public.e10_organizations set status='suspended'where id=o;
 set local role authenticated;
 begin perform public.e10_org_supplier_workspace(o,supplier,10,null);raise exception'suspended organization workspace allowed';exception when insufficient_privilege then null;end;
 begin perform public.e10_org_supplier_actual_cost_history(o,supplier,version_id,'CAD','2026-02-01',10,null);raise exception'suspended organization actual cost allowed';exception when insufficient_privilege then null;end;
 reset role;
 update public.e10_organizations set status='active'where id=o;

 perform set_config('request.jwt.claims',jsonb_build_object('sub',multi,'role','authenticated')::text,true);set local role authenticated;
 j:=public.e10_org_supplier_workspace(o,supplier,10,null);if j->>'financial_access'is distinct from'authorized'then raise exception'multi-member explicit org denied';end if;
 begin perform public.e10_org_supplier_workspace(o2,supplier2,1,cursor_value);raise exception'cursor survived organization switch';exception when invalid_parameter_value then null;end;
 begin perform public.e10_org_supplier_workspace(o2,supplier,10,null);raise exception'foreign supplier accepted';exception when invalid_parameter_value then null;end;
 reset role;delete from public.e10_organization_role_permissions where organization_id=o and role_id=role_fin and capability='financial.actual_cost.read';set local role authenticated;
 j:=public.e10_org_supplier_workspace(o,supplier,10,null);if j->>'financial_access'is distinct from'not_authorized'then raise exception'revoked financial access remained';end if;
 begin perform public.e10_org_supplier_actual_cost_history(o,supplier,version_id,'CAD','2026-02-01',10,null);raise exception'revoked actual cost allowed';exception when insufficient_privilege then null;end;
 reset role;

 perform set_config('request.jwt.claims',jsonb_build_object('sub',foreign_user,'role','authenticated')::text,true);set local role authenticated;
 begin perform public.e10_org_supplier_workspace(o,supplier,10,null);raise exception'hostile org read allowed';exception when insufficient_privilege then null;end;
 reset role;
 if has_function_privilege('anon','public.e10_org_supplier_workspace(uuid,uuid,integer,text)','execute')or has_function_privilege('public','public.e10_org_supplier_workspace(uuid,uuid,integer,text)','execute')
  or has_function_privilege('anon','public.e10_org_supplier_actual_cost_history(uuid,uuid,uuid,text,timestamptz,integer,text)','execute')
  or has_function_privilege('authenticated','e10.purchase_order_open_commitment_summary(uuid,uuid)','execute')
  or has_function_privilege('public','e10.supplier_open_commitment_summary(uuid,uuid,text)','execute')then raise exception'X3f anonymous or helper ACL open';end if;
end $$;
rollback;
select 'TA-X3f supplier workspace PASS' result;
