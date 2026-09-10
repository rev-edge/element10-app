\set ON_ERROR_STOP on
begin;
do $$
declare
  o uuid := 'e1000000-0000-4000-8000-0000000000a6';
  u uuid := 'e4000000-0000-4000-8000-00000000e4c0';
  u_denied uuid := 'e4000000-0000-4000-8000-00000000e4d0';
  role_id uuid := 'e4000000-0000-4000-8000-00000000e4c1';
  denied_role uuid := 'e4000000-0000-4000-8000-00000000e4d1';
  ob uuid := 'e4000000-0000-4000-8000-00000000e4d2';
  ob_role uuid := 'e4000000-0000-4000-8000-00000000e4d3';
  supplier uuid := 'e4000000-0000-4000-8000-00000000e4c2';
  location uuid := 'e4000000-0000-4000-8000-00000000e4c3';
  product uuid := 'e4000000-0000-4000-8000-00000000e4c4';
  config uuid := 'e4000000-0000-4000-8000-00000000e4c5';
  lot uuid := 'e4000000-0000-4000-8000-00000000e4c6';
  lot2 uuid := 'e4000000-0000-4000-8000-00000000e4c8';
  session uuid := 'e4000000-0000-4000-8000-00000000e4c7';
  reservation uuid; reservation2 uuid; r jsonb; c bigint; q numeric; consumed numeric; st text;
begin
  insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at)
    values(u,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','x4c-transition@x.invalid',now(),now());
  insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at)
    values(u_denied,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','x4c-denied@x.invalid',now(),now());
  insert into public.e10_organization_roles(id,organization_id,key,name,is_system)
    values(role_id,o,'x4c-transition','X4c Transition',false);
  insert into public.e10_organization_role_permissions(organization_id,role_id,capability,allowed)
    values(o,role_id,'act.reserve_inventory',true),(o,role_id,'act.inventory_edit',true);
  insert into public.e10_organization_memberships(organization_id,user_id,role_id,status)
    values(o,u,role_id,'active');
  insert into public.e10_organization_roles(id,organization_id,key,name,is_system)
    values(denied_role,o,'x4c-denied','X4c Denied',false);
  insert into public.e10_organization_memberships(organization_id,user_id,role_id,status)
    values(o,u_denied,denied_role,'active');
  insert into public.e10_suppliers(id,organization_id,name) values(supplier,o,'X4c Supplier');
  insert into public.e10_locations(id,organization_id,name) values(location,o,'X4c Location');
  insert into public.e10_product_masters(id,organization_id,name) values(product,o,'X4c Product');
  insert into public.e10_product_configurations(id,organization_id,product_master_id,name)
    values(config,o,product,'Each');
  insert into public.e10_product_configuration_versions(id,organization_id,configuration_id,version_no,state,packaging_kind,base_unit,base_units_per_package)
    values(config,o,config,1,'active','each','each',1);
  insert into public.e10_inventory_items(id,name,qty,organization_id) values('x4c-transition-item','X4c Item',10,o);
  insert into public.e10_inventory_lots(id,organization_id,configuration_version_id,location_id,supplier_id,inventory_item_id,status,accepted_quantity)
    values(lot,o,config,location,supplier,'x4c-transition-item','available',10);
  insert into public.e10_inventory_lots(id,organization_id,configuration_version_id,location_id,supplier_id,inventory_item_id,status,accepted_quantity)
    values(lot2,o,config,location,supplier,'x4c-transition-item','available',10);
  insert into public.e10_break_sessions(id,name,streamer_uid,organization_id,source_show_ref)
    values(session,'X4c Session',u,o,'x4c-transition-show');
  perform set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated')::text,true);

  r:=public.e10_org_lot_reserve(o,lot,10,session,'x4c-reserve');
  reservation:=(r->>'reservation_id')::uuid;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',u_denied,'role','authenticated')::text,true);
  begin perform public.e10_org_lot_consume(o,reservation,1,'x4c-denied'); raise exception 'missing capability allowed';
  exception when insufficient_privilege then null; end;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated')::text,true);
  perform set_config('role','authenticated',true);
  begin
    insert into e10.lot_transition_guards(backend_pid,transaction_id) values(pg_backend_pid(),txid_current());
    raise exception 'authenticated caller wrote private transition guard';
  exception when insufficient_privilege then null; end;
  r:=public.e10_org_lot_consume(o,reservation,3,'x4c-consume');
  perform set_config('role','postgres',true);
  if not (r->>'ok')::boolean or (r->>'consumed_quantity')::numeric<>3 or (r->>'remaining_quantity')::numeric<>7 then
    raise exception 'partial consume result wrong: %',r;
  end if;
  r:=public.e10_org_lot_consume(o,reservation,3,'x4c-consume');
  if not (r->>'replay')::boolean then raise exception 'consume replay not recognized'; end if;
  begin
    perform public.e10_org_lot_consume(o,reservation,4,'x4c-consume');
    raise exception 'consume idempotency mismatch accepted';
  exception when sqlstate '22023' then null; end;

  select consumed_quantity,status into consumed,st from public.e10_lot_reservations where id=reservation;
  select qty into q from public.e10_inventory_items where organization_id=o and id='x4c-transition-item';
  if consumed<>3 or st<>'active' or q<>7 then raise exception 'partial consume state wrong consumed=% status=% onhand=%',consumed,st,q; end if;
  select qty into q from public.e10_inventory_reservations where id=(select legacy_reservation_id from public.e10_lot_reservations where id=reservation);
  if q<>7 then raise exception 'legacy active remainder wrong: %',q; end if;

  r:=public.e10_org_lot_release(o,reservation,'x4c-release');
  if (r->>'released_quantity')::numeric<>7 or (r->>'consumed_quantity')::numeric<>3 then raise exception 'release result wrong: %',r; end if;
  r:=public.e10_org_lot_release(o,reservation,'x4c-release');
  if not (r->>'replay')::boolean then raise exception 'release replay not recognized'; end if;
  select consumed_quantity,status into consumed,st from public.e10_lot_reservations where id=reservation;
  select qty into q from public.e10_inventory_items where organization_id=o and id='x4c-transition-item';
  if consumed<>3 or st<>'released' or q<>7 then raise exception 'release re-exposed consumed stock consumed=% status=% onhand=%',consumed,st,q; end if;
  select count(*) into c from public.e10_lot_reservation_transitions where lot_reservation_id=reservation;
  if c<>2 then raise exception 'transition audit count wrong: %',c; end if;
  select coalesce(sum(on_hand_delta),0),coalesce(sum(reserved_delta),0) into q,consumed
    from public.e10_inventory_movements where organization_id=o and item_id='x4c-transition-item';
  if q<>-3 or consumed<>0 then raise exception 'movement ledger not reconciled on_hand=% reserved=%',q,consumed; end if;

  -- The seven released units can be reserved again; the three consumed units cannot.
  r:=public.e10_org_lot_reserve(o,lot,7,session,'x4c-reserve-2');
  reservation2:=(r->>'reservation_id')::uuid;
  begin perform public.e10_org_lot_reserve(o,lot,1,session,'x4c-reserve-over'); raise exception 'consumed stock was re-exposed';
  exception when check_violation then null; end;
  begin perform public.e10_org_lot_reserve(o,lot2,8,session,'x4c-second-lot-over'); raise exception 'shared item re-exposed consumed stock';
  exception when check_violation then null; end;
  begin perform public.e10_org_lot_consume(o,reservation2,8,'x4c-overconsume'); raise exception 'overconsume accepted';
  exception when check_violation then null; end;
  begin perform public.e10_org_lot_release(o,reservation2,'x4c-consume'); raise exception 'cross-action idempotency reuse accepted';
  exception when sqlstate '22023' then null; end;
  r:=public.e10_org_lot_consume(o,reservation2,7,'x4c-consume-full');
  if (r->>'status')<>'consumed' or (r->>'remaining_quantity')::numeric<>0 then raise exception 'full consume wrong: %',r; end if;
  begin perform public.e10_org_lot_consume(o,reservation2,1,'x4c-after-consumed'); raise exception 'terminal consume accepted';
  exception when sqlstate '55000' then null; end;
  begin perform public.e10_org_lot_release(o,reservation2,'x4c-after-consumed-release'); raise exception 'terminal release accepted';
  exception when sqlstate '55000' then null; end;

  insert into public.e10_organizations(id,name,slug) values(ob,'X4c Other','x4c-other');
  insert into public.e10_organization_roles(id,organization_id,key,name,is_system) values(ob_role,ob,'x4c','X4c',false);
  insert into public.e10_organization_role_permissions(organization_id,role_id,capability,allowed)
    values(ob,ob_role,'act.inventory_edit',true);
  insert into public.e10_organization_memberships(organization_id,user_id,role_id,status) values(ob,u,ob_role,'active');
  begin perform public.e10_org_lot_consume(ob,reservation,1,'x4c-cross-org'); raise exception 'cross-org transition accepted';
  exception when insufficient_privilege then null; end;
  perform set_config('e10.lot_transition','on',true);
  begin
    update public.e10_inventory_reservations set status='active'
      where id=(select legacy_reservation_id from public.e10_lot_reservations where id=reservation);
    raise exception 'legacy linked mutation bypassed guard';
  exception when sqlstate '55000' then null; end;
  select count(*) into c from e10.lot_transition_guards;
  if c<>0 then raise exception 'transition guard residue: %',c; end if;
  raise notice 'TA-X4c partial consume/release: PASS (10 reserve, 3 consume, 7 release, no consumed re-exposure)';
end $$;
rollback;

set role anon;
do $$ begin
  if has_function_privilege('anon','public.e10_org_lot_consume(uuid,uuid,numeric,text)','execute')
     or has_function_privilege('anon','public.e10_org_lot_release(uuid,uuid,text)','execute') then
    raise exception 'TA-X4c functions exposed to anon';
  end if;
  raise notice 'TA-X4c fail-closed ACL: PASS';
end $$;
reset role;
