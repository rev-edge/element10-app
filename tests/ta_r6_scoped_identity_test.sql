\set ON_ERROR_STOP on
begin;
do $$
declare o1 uuid:=gen_random_uuid();o2 uuid:=gen_random_uuid();line_id uuid:=gen_random_uuid();sanitized jsonb;random_id uuid:=gen_random_uuid();
begin
 insert into public.e10_organizations(id,slug,name)values(o1,'r6-a-'||left(o1::text,8),'R6 A'),(o2,'r6-b-'||left(o2::text,8),'R6 B');
 insert into public.e10_suppliers(id,organization_id,name)values(gen_random_uuid(),o1,'R6'),(gen_random_uuid(),o2,'R6');
 insert into public.e10_locations(id,organization_id,name)values(gen_random_uuid(),o1,'R6'),(gen_random_uuid(),o2,'R6');
 insert into public.e10_purchase_orders(id,organization_id,supplier_id,destination_location_id,currency,status,revision,created_by)
 select gen_random_uuid(),s.organization_id,s.id,l.id,'USD','draft',1,null from public.e10_suppliers s join public.e10_locations l using(organization_id) where s.organization_id in(o1,o2);
 insert into public.e10_product_masters(id,organization_id,name)values(gen_random_uuid(),o2,'R6');
 insert into public.e10_product_configurations(id,organization_id,product_master_id,name)
 select gen_random_uuid(),o2,id,'R6' from public.e10_product_masters where organization_id=o2;
 insert into public.e10_product_configuration_versions(id,organization_id,configuration_id,version_no,state,packaging_kind,base_unit,base_units_per_package)
 select gen_random_uuid(),o2,id,1,'active','each','each',1 from public.e10_product_configurations where organization_id=o2;
 insert into public.e10_purchase_order_lines(id,organization_id,purchase_order_id,configuration_version_id,line_no,ordered_quantity,state)
 select line_id,o2,p.id,v.id,1,1,'active' from public.e10_purchase_orders p cross join public.e10_product_configuration_versions v where p.organization_id=o2 and v.organization_id=o2;
 sanitized:=e10.sanitize_scoped_line_ids(o1,jsonb_build_array(jsonb_build_object('id',line_id)), 'public.e10_purchase_order_lines'::regclass);
 if sanitized#>>'{0,id}'=line_id::text then raise exception'foreign line identity was not remapped';end if;
 sanitized:=e10.sanitize_scoped_line_ids(o1,jsonb_build_array(jsonb_build_object('id',random_id)), 'public.e10_purchase_order_lines'::regclass);
 if sanitized#>>'{0,id}'<>random_id::text then raise exception'available line identity was changed';end if;
 if position('sanitize_scoped_line_ids' in pg_get_functiondef('public.e10_org_create_purchase_order(uuid,uuid,uuid,text,text,timestamptz,jsonb,text)'::regprocedure))=0
   or position('sanitize_scoped_line_ids' in pg_get_functiondef('public._e10_org_amend_financial_document_x3d1b(uuid,text,uuid,integer,text,date,numeric,jsonb,text,text)'::regprocedure))=0 then raise exception'writer sanitizer wiring missing';end if;
end $$;
rollback;
select 'TA-R6 scoped line identity: PASS' result;
