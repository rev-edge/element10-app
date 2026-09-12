\set ON_ERROR_STOP on
begin;
do $$
declare o uuid:=gen_random_uuid();u uuid:=gen_random_uuid();role_id uuid:=gen_random_uuid();loc uuid:=gen_random_uuid();supplier uuid:=gen_random_uuid();product uuid:=gen_random_uuid();config uuid:=gen_random_uuid();version uuid:=gen_random_uuid();customer uuid:=gen_random_uuid();j jsonb;j2 jsonb;d uuid;po uuid;cd uuid;po_values jsonb;customer_values jsonb;
begin
 insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at)values(u,'00000000-0000-0000-8000-000000000000','authenticated','authenticated','x8bc-'||u||'@x.invalid',now(),now());
 insert into public.e10_organizations(id,slug,name)values(o,'x8bc-'||substr(o::text,1,8),'X8b commit');
 insert into public.e10_organization_roles(id,organization_id,key,name,is_system)values(role_id,o,'x8bc','X8b commit',false);
 insert into public.e10_organization_memberships(organization_id,user_id,role_id,status)values(o,u,role_id,'active');
 insert into public.e10_organization_role_permissions values(o,role_id,'act.purchasing_prepare',true),(o,role_id,'act.purchasing_approve',true),(o,role_id,'act.prepare_customer_transactions',true),(o,role_id,'act.approve_customer_transactions',true);
 insert into public.e10_locations(id,organization_id,code,name,status)values(loc,o,'X8BC','X8b receiving','active');
 insert into public.e10_location_role_permissions(organization_id,location_id,role_id,can_receive)values(o,loc,role_id,true);
 insert into public.e10_suppliers(id,organization_id,code,name,status)values(supplier,o,'X8BC','X8b supplier','active');
 insert into public.e10_product_masters(id,organization_id,name)values(product,o,'X8b product');
 insert into public.e10_product_configurations(id,organization_id,product_master_id,name)values(config,o,product,'X8b configuration');
 insert into public.e10_product_configuration_versions(id,organization_id,configuration_id,version_no,state,packaging_kind,base_unit,base_units_per_package)values(version,o,config,1,'active','unit','unit',1);
 insert into public.e10_customers(id,organization_id,display_name,status)values(customer,o,'X8b customer','active');
 perform set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated')::text,true);set local role authenticated;

 po_values:=jsonb_build_object('supplier_id',supplier,'destination_location_id',loc,'order_number','X8B-PO','currency','CAD','expected_at',null,'lines',jsonb_build_array(jsonb_build_object('line_no',1,'configuration_version_id',version,'ordered_quantity',2,'estimated_unit_cost',12.50)));
 j:=public.e10_org_create_action_draft(o,'purchase_order.create',po_values,'{"supplier_id":{"source":"operator"}}','[]','po-propose');d:=(j->>'draft_id')::uuid;
 if jsonb_array_length(j->'missing_fields')<>0 then raise exception'valid PO reported missing %',j;end if;
 perform public.e10_org_approve_action_draft(o,d,1,'po-approve');
 j:=public.e10_org_commit_action_draft(o,d,1,'po-commit');po:=(j#>>'{ordinary_result,purchase_order_id}')::uuid;
 reset role;
 if j->>'status'<>'committed'or po is null or not exists(select 1 from public.e10_purchase_orders where organization_id=o and id=po and status='draft'and revision=1)then raise exception'PO delegation failed %',j;end if;
 set local role authenticated;
 j2:=public.e10_org_commit_action_draft(o,d,1,'po-commit');if not(j2->>'replay')::boolean or j2#>>'{ordinary_result,purchase_order_id}'<>po::text then raise exception'PO commit replay failed %',j2;end if;
 reset role;
 if exists(select 1 from public.e10_stock_receipts where organization_id=o)then raise exception'PO proposal received stock';end if;

 set local role authenticated;
 customer_values:=jsonb_build_object('customer_id',customer,'currency','CAD','occurred_at',null,'precision','unknown','note','proposed only','lines',jsonb_build_array(jsonb_build_object('purchase_kind','unclassified','capture_source','manual','source_line_id','x8b-line-1','product_master_id',product,'configuration_version_id',version,'quantity',1,'merchandise_gross',20)));
 j:=public.e10_org_create_action_draft(o,'customer_transaction.create_draft',customer_values,'{"note":{"source":"operator"}}','[]','customer-propose');d:=(j->>'draft_id')::uuid;
 if jsonb_array_length(j->'missing_fields')<>0 then raise exception'valid customer proposal reported missing %',j;end if;
 perform public.e10_org_approve_action_draft(o,d,1,'customer-approve');
 j:=public.e10_org_commit_action_draft(o,d,1,'customer-commit');cd:=(j#>>'{ordinary_result,draft_id}')::uuid;
 reset role;
 if j->>'status'<>'committed'or cd is null or not exists(select 1 from public.e10_customer_transaction_drafts where organization_id=o and id=cd and status='draft'and current_revision=1)then raise exception'customer draft delegation failed %',j;end if;
 set local role authenticated;
 j2:=public.e10_org_commit_action_draft(o,d,1,'customer-commit');if not(j2->>'replay')::boolean or j2#>>'{ordinary_result,draft_id}'<>cd::text then raise exception'customer commit replay failed %',j2;end if;
 reset role;
 if exists(select 1 from public.e10_customer_transactions where organization_id=o)or exists(select 1 from public.e10_commercial_events where organization_id=o and event_type='customer_transaction_posted')then raise exception'customer proposal posted spend';end if;
 if(select count(*)from public.e10_action_draft_commands where organization_id=o and command_type='commit')<>2 then raise exception'commit command count invalid';end if;
end $$;
rollback;
select'TA-X8b ordinary-writer delegation PASS'as result;
