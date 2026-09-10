\set ON_ERROR_STOP on
begin;
do $$
declare o uuid:='e1000000-0000-4000-8000-0000000000a6'; u uuid:=gen_random_uuid(); rid uuid:=gen_random_uuid();
  r jsonb; c bigint; linked bigint;
begin
  insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at)
    values(u,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','x5c@x.invalid',now(),now());
  insert into public.e10_organization_roles(id,organization_id,key,name,is_system) values(rid,o,'x5c','X5c',false);
  insert into public.e10_organization_role_permissions(organization_id,role_id,capability,allowed)
    values(o,rid,'act.inventory_edit',true);
  insert into public.e10_organization_memberships(organization_id,user_id,role_id,status) values(o,u,rid,'active');
  insert into public.e10_inventory_items(id,name,qty,organization_id) values('x5c-item','X5c Item',5,o);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated')::text,true);
  r:=public.e10_org_inv_reserve(o,'x5c-item','show-1','Show 1',2,'x5c-reserve-1');
  if not (r->>'ok')::boolean then raise exception 'native reserve failed: %',r; end if;
  begin
    perform public.e10_org_inv_reserve(o,'x5c-item','show-rollback','Rollback',1,'x5c-reserve-rollback');
    raise exception 'force action rollback';
  exception when raise_exception then null; end;
  select count(*) into c from public.e10_inventory_movements where organization_id=o and idempotency_key='x5c-reserve-rollback';
  if c<>0 then raise exception 'rolled-back action retained movement'; end if;
  select count(*) into c from public.e10_commercial_events where organization_id=o and subject_id='x5c-item';
  if c<>1 then raise exception 'rolled-back action retained event; count=%',c; end if;
  r:=public.e10_org_inv_release(o,'x5c-item','show-1','x5c-release-1');
  if not (r->>'ok')::boolean then raise exception 'native release failed: %',r; end if;
  perform public.e10_org_emit_inventory_movement(o,'x5c-item','correction',1,0,'x5c-unclassified','test','unclassified',
    'test','x','other',null,'{}');
  select count(*),count(inventory_movement_id) into c,linked from public.e10_commercial_events
    where organization_id=o and subject_type='inventory_item' and subject_id='x5c-item';
  if c<>2 or linked<>2 then raise exception 'native event linkage wrong events=% linked=%',c,linked; end if;
  if (select count(*) from public.e10_commercial_events where organization_id=o and subject_id='x5c-item' and event_type='hold')<>1
     or (select count(*) from public.e10_commercial_events where organization_id=o and subject_id='x5c-item' and event_type='release')<>1 then
    raise exception 'native event types wrong';
  end if;
  raise notice 'TA-X5c native action linkage: PASS (reserve/release atomic events, rollback atomicity, unknown correction not guessed)';
end $$;
rollback;
