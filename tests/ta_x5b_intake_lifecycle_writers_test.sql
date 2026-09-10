\set ON_ERROR_STOP on
begin;
do $$
declare o uuid:='e1000000-0000-4000-8000-0000000000a6'; u uuid:=gen_random_uuid(); rid uuid:=gen_random_uuid();
  product uuid:=gen_random_uuid(); batch uuid; row_id uuid; decision uuid; event_id uuid; r jsonb; c bigint;
begin
  insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at)
    values(u,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','x5b@x.invalid',now(),now());
  insert into public.e10_organization_roles(id,organization_id,key,name,is_system) values(rid,o,'x5b','X5b',false);
  insert into public.e10_organization_role_permissions(organization_id,role_id,capability,allowed)
    values(o,rid,'act.manage_intake',true),(o,rid,'act.record_commercial_events',true);
  insert into public.e10_organization_memberships(organization_id,user_id,role_id,status) values(o,u,rid,'active');
  insert into public.e10_product_masters(id,organization_id,name) values(product,o,'X5b Product');
  insert into public.e10_inventory_items(id,name,qty,organization_id) values('x5b-item','X5b Item',0,o);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated')::text,true);
  perform set_config('role','authenticated',true);
  r:=public.e10_org_stage_intake(o,'csv','source-a','doc-1','storage://x5b.csv','payload-a',jsonb_build_array(
    jsonb_build_object('raw_payload',jsonb_build_object('kind','ask'),'observation_kind','asking_price','occurred_at','2026-09-10T20:00:00Z','currency','CAD','amount',25),
    jsonb_build_object('raw_payload',jsonb_build_object('kind','unknown')),
    jsonb_build_object('raw_payload',jsonb_build_object('kind','broken'),'observation_kind','completed_sale','occurred_at','not-a-date','currency','','amount','not-a-number'),
    jsonb_build_object('raw_payload',jsonb_build_object('kind','nonfinite'),'observation_kind','bogus','occurred_at','today','currency','CAD','amount','NaN','quantity',0)),'x5b-stage-1');
  perform set_config('role','postgres',true);
  batch:=(r->>'batch_id')::uuid;
  if (r->>'row_count')::int<>4 or (r->>'invalid_row_count')::int<>3 or r->>'status'<>'staged' then raise exception 'stage result wrong: %',r; end if;
  select count(*) into c from public.e10_intake_rows where organization_id=o and batch_id=batch and source_row_number=4
    and observation_kind is null and occurred_at is null and amount is null and quantity is null and jsonb_array_length(validation_errors)>=3;
  if c<>1 then raise exception 'invalid typed values were not retained safely'; end if;
  r:=public.e10_org_stage_intake(o,'csv','source-a','doc-1','storage://x5b.csv','payload-a',jsonb_build_array(
    jsonb_build_object('raw_payload',jsonb_build_object('kind','ask'),'observation_kind','asking_price','occurred_at','2026-09-10T20:00:00Z','currency','CAD','amount',25),
    jsonb_build_object('raw_payload',jsonb_build_object('kind','unknown')),
    jsonb_build_object('raw_payload',jsonb_build_object('kind','broken'),'observation_kind','completed_sale','occurred_at','not-a-date','currency','','amount','not-a-number'),
    jsonb_build_object('raw_payload',jsonb_build_object('kind','nonfinite'),'observation_kind','bogus','occurred_at','today','currency','CAD','amount','NaN','quantity',0)),'x5b-stage-1');
  if not (r->>'replay')::boolean then raise exception 'stage replay missing'; end if;
  begin perform public.e10_org_stage_intake(o,'manual',null,null,null,'different','[{"raw_payload":{}}]','x5b-stage-1'); raise exception 'stage mismatch accepted';
  exception when sqlstate '22023' then null; end;
  begin perform public.e10_org_stage_intake(o,'manual',null,null,null,'x',null,'x5b-null'); raise exception 'null rows accepted';
  exception when sqlstate '22023' then null; end;
  select id into row_id from public.e10_intake_rows where organization_id=o and batch_id=batch and source_row_number=1;
  r:=public.e10_org_resolve_intake_row(o,row_id,'match_product',product,'reviewed exact product',null,'x5b-resolve-1');
  decision:=(r->>'decision_id')::uuid;
  r:=public.e10_org_resolve_intake_row(o,row_id,'match_product',product,'reviewed exact product',null,'x5b-resolve-1');
  if not (r->>'replay')::boolean then raise exception 'resolve replay missing'; end if;
  r:=public.e10_org_resolve_intake_row(o,row_id,'clear_match',null,'correction',decision,'x5b-resolve-2');
  if r->>'match_status'<>'unresolved' then raise exception 'clear match failed: %',r; end if;
  r:=public.e10_org_record_commercial_event(o,'listing_created','inventory_item','x5b-item','2026-09-10T21:00:00Z',
    'manual','operator-entry','{"ask":25}',null,array['dormant-ledger'],'x5b-event-1');
  event_id:=(r->>'event_id')::uuid;
  if (r->>'outbox_count')::int<>1 then raise exception 'outbox not atomic: %',r; end if;
  r:=public.e10_org_record_commercial_event(o,'listing_created','inventory_item','x5b-item','2026-09-10T21:00:00Z',
    'manual','operator-entry','{"ask":25}',null,array['dormant-ledger'],'x5b-event-1');
  if not (r->>'replay')::boolean then raise exception 'event replay missing'; end if;
  r:=public.e10_org_record_commercial_event(o,'correction','inventory_item','x5b-item','2026-09-10T22:00:00Z',
    'manual','operator-correction','{"reason":"wrong ask"}',event_id,'{}','x5b-event-2');
  begin perform public.e10_org_record_commercial_event(o,'listing_created','inventory_item','x5b-item',now(),'manual',null,'{}',null,array['same','same'],'x5b-dup-dest');
  exception when sqlstate '22023' then null; end;
  begin perform public.e10_org_record_commercial_event(o,'sale_committed','sale',gen_random_uuid()::text,now(),'manual',null,'{}',null,'{}','x5b-unsupported');
  exception when sqlstate '22023' then null; end;
  begin perform public.e10_org_record_commercial_event('e4000000-0000-4000-8000-00000000e5ff','listing_created','inventory_item','x5b-item',now(),'manual',null,'{}',null,'{}','x5b-cross');
  exception when insufficient_privilege then null; end;
  select count(*) into c from public.e10_integration_outbox where organization_id=o and commercial_event_id=event_id;
  if c<>1 then raise exception 'outbox duplicate count %',c; end if;
  if has_function_privilege('anon','public.e10_org_stage_intake(uuid,text,text,text,text,text,jsonb,text)','execute') then raise exception 'stage exposed to anon'; end if;
  raise notice 'TA-X5b writers: PASS (bounded stage, reviewed resolve, typed event+outbox, idempotency, corrections, tenant denial)';
end $$;
rollback;
