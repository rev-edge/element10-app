\set ON_ERROR_STOP on
begin;
do $$
declare target_org uuid:=gen_random_uuid();caller_org uuid:=gen_random_uuid();u uuid:=gen_random_uuid();role_id uuid:=gen_random_uuid();supplier_id uuid:=gen_random_uuid();location_id uuid:=gen_random_uuid();receipt_id uuid:=gen_random_uuid();denials integer:=0;
begin
 insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at)values(u,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',u||'@r6.invalid',now(),now());
 insert into public.e10_organizations(id,slug,name)values(target_org,'r6-target-'||left(target_org::text,8),'R6 target'),(caller_org,'r6-caller-'||left(caller_org::text,8),'R6 caller');
 insert into public.e10_organization_roles(id,organization_id,key,name)values(role_id,caller_org,'r6','R6');
 insert into public.e10_organization_memberships(organization_id,user_id,role_id,status)values(caller_org,u,role_id,'active');
 insert into public.e10_organization_role_permissions values(caller_org,role_id,'act.create_receiving',true);
 insert into public.e10_suppliers(id,organization_id,name)values(supplier_id,target_org,'R6');
 insert into public.e10_locations(id,organization_id,name)values(location_id,target_org,'R6');
 insert into public.e10_stock_receipts(id,organization_id,supplier_id,destination_location_id,status,idempotency_key,created_by)values(receipt_id,target_org,supplier_id,location_id,'posted','occupied',u);
 insert into public.e10_receipt_commands(organization_id,idempotency_key,request_fingerprint,stock_receipt_id,result,created_by)values(target_org,'command-occupied','fp',receipt_id,'{}',u);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated')::text,true);set local role authenticated;
 begin perform public.e10_org_receive_batch(target_org,null,null,null,'[]','occupied');exception when sqlstate'42501'then denials:=denials+1;end;
 begin perform public.e10_org_receive_batch(target_org,null,null,null,'[]','unused');exception when sqlstate'42501'then denials:=denials+1;end;
 begin perform public.e10_org_receive_po_line(target_org,null,null,1,0,0,null,null,'[]','command-occupied');exception when sqlstate'42501'then denials:=denials+1;end;
 begin perform public.e10_org_receive_po_line(target_org,null,null,1,0,0,null,null,'[]','unused');exception when sqlstate'42501'then denials:=denials+1;end;
 if denials<>4 then raise exception'occupied/unused receipt keys did not share denial path: %',denials;end if;
end $$;
rollback;
select 'TA-R6 X4 oracle closure: PASS' result;
