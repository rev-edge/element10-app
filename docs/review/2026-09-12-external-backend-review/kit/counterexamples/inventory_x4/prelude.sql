-- Fixture prelude (run as postgres inside begin;). Deterministic IDs.
do $$
declare
 o uuid:='e1000000-0000-4000-8000-0000000000a6';
 actor uuid:='a4000000-0000-4000-8000-000000000001'; role_id uuid:='a4000000-0000-4000-8000-000000000002';
 supplier uuid:='a4000000-0000-4000-8000-000000000003'; location_id uuid:='a4000000-0000-4000-8000-000000000004';
 product_id uuid:='a4000000-0000-4000-8000-000000000005'; config_id uuid:='a4000000-0000-4000-8000-000000000006';
 po_id uuid:='a4000000-0000-4000-8000-000000000007'; po_line uuid:='a4000000-0000-4000-8000-000000000008';
 invoice_id uuid:='a4000000-0000-4000-8000-000000000009'; invoice_line uuid:='a4000000-0000-4000-8000-00000000000a';
 session_id uuid:='a4000000-0000-4000-8000-00000000000b';
 forg uuid:='a4000000-0000-4000-8000-00000000000c'; factor uuid:='a4000000-0000-4000-8000-00000000000d'; frole uuid:='a4000000-0000-4000-8000-00000000000e';
 fsupplier uuid:='a4000000-0000-4000-8000-00000000000f'; flocation uuid:='a4000000-0000-4000-8000-000000000010';
 fproduct uuid:='a4000000-0000-4000-8000-000000000011'; fconfig uuid:='a4000000-0000-4000-8000-000000000012';
 fpo uuid:='a4000000-0000-4000-8000-000000000013'; fpol uuid:='a4000000-0000-4000-8000-000000000014';
begin
 insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at)
 values(actor,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','rv-'||actor||'@example.invalid',now(),now()),
       (factor,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','rv-'||factor||'@example.invalid',now(),now());
 insert into public.e10_organizations(id,slug,name) values(forg,'rv-foreign','RV foreign org');
 insert into public.e10_organization_modules(organization_id,module_key,enabled) values(forg,'core',true);
 insert into public.e10_organization_roles(id,organization_id,key,name,is_system) values(role_id,o,'rv-role','RV reviewer',false),(frole,forg,'rv-frole','RV foreign',false);
 insert into public.e10_organization_role_permissions(organization_id,role_id,capability,allowed)
 values(o,role_id,'act.create_receiving',true),(o,role_id,'act.resolve_recovery',true),(o,role_id,'financial.actual_cost.read',true),
       (o,role_id,'act.reserve_inventory',true),(o,role_id,'act.inventory_edit',true),
       (forg,frole,'act.create_receiving',true),(forg,frole,'act.resolve_recovery',true),(forg,frole,'financial.actual_cost.read',true),
       (forg,frole,'act.reserve_inventory',true),(forg,frole,'act.inventory_edit',true);
 insert into public.e10_organization_memberships(organization_id,user_id,role_id,status) values(o,actor,role_id,'active'),(forg,factor,frole,'active');
 insert into public.e10_suppliers(id,organization_id,code,name,status) values(supplier,o,'RVS','RV supplier','active'),(fsupplier,forg,'RVF','RV foreign supplier','active');
 insert into public.e10_locations(id,organization_id,code,name,status) values(location_id,o,'RVL','RV location','active'),(flocation,forg,'RVFL','RV foreign location','active');
 insert into public.e10_location_role_permissions(organization_id,location_id,role_id,can_receive) values(o,location_id,role_id,true),(forg,flocation,frole,true);
 insert into public.e10_product_masters(id,organization_id,name,status) values(product_id,o,'RV product','active'),(fproduct,forg,'RV fproduct','active');
 insert into public.e10_product_configurations(id,organization_id,product_master_id,name,status) values(config_id,o,product_id,'Each','active'),(fconfig,forg,fproduct,'Each','active');
 insert into public.e10_product_configuration_versions(id,organization_id,configuration_id,version_no,state,packaging_kind,base_unit,base_units_per_package)
 values(config_id,o,config_id,1,'active','each','each',1),(fconfig,forg,fconfig,1,'active','each','each',1);
 insert into public.e10_inventory_items(id,name,qty,organization_id) values('rv-item-1','RV item 1',0,o),('rv-item-2','RV item 2',0,o),('rv-fitem','RV foreign item',0,forg);
 insert into public.e10_break_sessions(id,name,streamer_uid,organization_id,source_show_ref) values(session_id,'RV session',actor,o,'rv-show');
 insert into public.e10_purchase_orders(id,organization_id,supplier_id,destination_location_id,status,currency,created_by)
 values(po_id,o,supplier,location_id,'approved','CAD',actor),(fpo,forg,fsupplier,flocation,'approved','CAD',factor);
 insert into public.e10_purchase_order_lines(id,organization_id,purchase_order_id,configuration_version_id,line_no,ordered_quantity,estimated_unit_cost)
 values(po_line,o,po_id,config_id,1,10,99),(fpol,forg,fpo,fconfig,1,10,null);
 insert into public.e10_supplier_invoices(id,organization_id,supplier_id,supplier_document_number,status,currency,created_by)
 values(invoice_id,o,supplier,'RV-INV','draft','CAD',actor);
 insert into public.e10_supplier_invoice_lines(id,organization_id,supplier_invoice_id,configuration_version_id,line_no,invoiced_quantity,line_amount,state)
 values(invoice_line,o,invoice_id,config_id,1,10,100,'active');
end $$;
