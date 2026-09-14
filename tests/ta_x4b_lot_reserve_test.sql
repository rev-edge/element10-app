-- TA-X4b lot reservation writer gate. Self-failing and rolled back.
begin;
do $$
declare o uuid:='e1000000-0000-4000-8000-0000000000a6'; ob uuid:='e1000000-0000-4000-8000-00000000e4b0';
 u uuid:='a7000000-0000-4000-8000-00000000e4b1'; ub uuid:='a7000000-0000-4000-8000-00000000e4b2';
 supplier uuid:=gen_random_uuid(); location uuid:=gen_random_uuid(); inactive_location uuid:='e4000000-0000-4000-8000-00000000e4b4'; product uuid:=gen_random_uuid(); config uuid:=gen_random_uuid(); lot uuid:='e4000000-0000-4000-8000-00000000e4b1'; session uuid:='e4000000-0000-4000-8000-00000000e4b2'; foreign_session uuid:='e4000000-0000-4000-8000-00000000e4b3'; ended_session uuid:='e4000000-0000-4000-8000-00000000e4b5'; inactive_lot uuid:='e4000000-0000-4000-8000-00000000e4b6';
begin
 insert into public.e10_organizations(id,name,slug) values(ob,'X4b Org B','x4b-org-b');
 insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at) values
 (u,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','x4b@x.invalid',now(),now()),
 (ub,'00000000-0000-0000-8000-000000000000','authenticated','authenticated','x4bforeign@x.invalid',now(),now());
 insert into public.e10_organization_memberships(organization_id,user_id,role_id,status) values(o,u,'e1000000-0000-4000-8000-000000000002','active');
 insert into public.e10_organization_role_permissions(organization_id,role_id,capability,allowed) values(o,'e1000000-0000-4000-8000-000000000002','act.reserve_inventory',true) on conflict do nothing;
 insert into public.e10_suppliers(id,organization_id,name) values(supplier,o,'X4b Supplier');
 insert into public.e10_locations(id,organization_id,name) values(location,o,'X4b Location');
 insert into public.e10_locations(id,organization_id,name,status) values(inactive_location,o,'X4b Inactive Location','inactive');
 insert into public.e10_product_masters(id,organization_id,name) values(product,o,'X4b Product');
 insert into public.e10_product_configurations(id,organization_id,product_master_id,name) values(config,o,product,'Each');
 insert into public.e10_product_configuration_versions(id,organization_id,configuration_id,version_no,state,packaging_kind,base_unit,base_units_per_package) values(config,o,config,1,'active','each','each',1);
 insert into public.e10_inventory_items(id,name,qty,organization_id) values('x4b-item','X4b Item',5,o);
 insert into public.e10_inventory_lots(id,organization_id,configuration_version_id,location_id,supplier_id,inventory_item_id,status,accepted_quantity) values(lot,o,config,location,supplier,'x4b-item','available',5);
 insert into public.e10_inventory_lots(id,organization_id,configuration_version_id,location_id,supplier_id,inventory_item_id,status,accepted_quantity) values(inactive_lot,o,config,inactive_location,supplier,'x4b-item','available',5);
 insert into public.e10_break_sessions(id,name,streamer_uid,organization_id,source_show_ref) values(session,'X4b Session',u,o,'x4b-show');
 insert into public.e10_break_sessions(id,name,streamer_uid,organization_id,status) values(ended_session,'X4b Ended Session',u,o,'ended');
 insert into public.e10_break_sessions(id,name,streamer_uid,organization_id) values(foreign_session,'X4b Foreign Session',ub,ob);
end $$;

set local role authenticated;
do $$ declare a jsonb; b jsonb; after_consume jsonb; c bigint; begin
 perform set_config('request.jwt.claims',json_build_object('sub','a7000000-0000-4000-8000-00000000e4b1','role','authenticated')::text,true);
 select public.e10_org_lot_reserve('e1000000-0000-4000-8000-0000000000a6','e4000000-0000-4000-8000-00000000e4b1',2,'e4000000-0000-4000-8000-00000000e4b2','x4b-idem-1') into a;
 select public.e10_org_lot_reserve('e1000000-0000-4000-8000-0000000000a6','e4000000-0000-4000-8000-00000000e4b1',2,'e4000000-0000-4000-8000-00000000e4b2','x4b-idem-1') into b;
 if a->>'replay'<>'false' or b->>'replay'<>'true' or a->>'reservation_id'<>b->>'reservation_id' then raise exception 'idempotent replay failed'; end if;
 select count(*) into c from public.e10_inventory_reservations where item_id='x4b-item' and status='active'; if c<>1 then raise exception 'legacy reservation not synchronized'; end if;
 select count(*) into c from public.e10_inventory_movements where item_id='x4b-item' and idempotency_key='e1000000-0000-4000-8000-0000000000a6:lot-reserve:x4b-idem-1'; if c<>1 then raise exception 'movement not synchronized'; end if;
 begin perform public.e10_org_lot_reserve('e1000000-0000-4000-8000-0000000000a6','e4000000-0000-4000-8000-00000000e4b1',3,'e4000000-0000-4000-8000-00000000e4b2','x4b-idem-1'); raise exception 'idempotency mismatch allowed'; exception when sqlstate '22023' then null; end;
 begin perform public.e10_org_lot_reserve('e1000000-0000-4000-8000-0000000000a6','e4000000-0000-4000-8000-00000000e4b1',4,'e4000000-0000-4000-8000-00000000e4b2','x4b-idem-over'); raise exception 'overcommit allowed'; exception when check_violation then null; end;
 begin perform public.e10_org_lot_reserve('e1000000-0000-4000-8000-0000000000a6','e4000000-0000-4000-8000-00000000e4b1',1,'e4000000-0000-4000-8000-00000000e4b3','x4b-idem-foreign'); raise exception 'foreign session allowed'; exception when insufficient_privilege then null; end;
 begin perform public.e10_org_lot_reserve('e1000000-0000-4000-8000-0000000000a6','e4000000-0000-4000-8000-00000000e4b1',1,'e4000000-0000-4000-8000-00000000e4b5','x4b-idem-ended'); raise exception 'ended session allowed'; exception when sqlstate '55000' then null; end;
 begin perform public.e10_org_lot_reserve('e1000000-0000-4000-8000-0000000000a6','e4000000-0000-4000-8000-00000000e4b6',1,'e4000000-0000-4000-8000-00000000e4b2','x4b-idem-inactive'); raise exception 'inactive location allowed'; exception when sqlstate '55000' then null; end;
 begin perform public.e10_org_inv_consume('e1000000-0000-4000-8000-0000000000a6','x4b-item','e4000000-0000-4000-8000-00000000e4b2',null,2,'x4b-consume-1'); raise exception 'legacy consume altered a lot-linked reservation'; exception when sqlstate '55000' then null; end;
 select public.e10_org_lot_reserve('e1000000-0000-4000-8000-0000000000a6','e4000000-0000-4000-8000-00000000e4b1',2,'e4000000-0000-4000-8000-00000000e4b2','x4b-idem-1') into after_consume;
 if after_consume->>'status'<>'active' or (after_consume->>'consumed_quantity')::numeric<>0 then raise exception 'denied legacy consume changed lot state'; end if;
 raise notice 'TA-X4b atomic lot reserve: PASS';
end $$;
reset role;
rollback;
