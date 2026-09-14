\set ON_ERROR_STOP on
begin;
do $$
declare o uuid:='e1000000-0000-4000-8000-0000000000a6'; other_org uuid:=gen_random_uuid(); u uuid:=gen_random_uuid(); role_id uuid:=gen_random_uuid();
  product uuid:=gen_random_uuid(); batch uuid; row1 uuid; row2 uuid; row3 uuid; row4 uuid; result jsonb; c bigint; occurred timestamptz; revision bigint; before_inventory bigint;before_customer bigint;
begin
  insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at) values(u,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','x5d@x.invalid',now(),now());
  insert into public.e10_organization_roles(id,organization_id,key,name,is_system) values(role_id,o,'x5d','X5d',false);
  insert into public.e10_organization_role_permissions(organization_id,role_id,capability,allowed) values(o,role_id,'act.manage_intake',true);
  insert into public.e10_organization_memberships(organization_id,user_id,role_id,status) values(o,u,role_id,'active');
  insert into public.e10_product_masters(id,organization_id,name) values(product,o,'X5d Product');
  select count(*)into before_inventory from public.e10_inventory_movements;select count(*)into before_customer from public.e10_customer_transactions;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated')::text,true);
  result:=public.e10_org_stage_intake(o,'csv','x5d-source','x5d-doc','storage://x5d.csv','x5d-fp',jsonb_build_array(
    jsonb_build_object('raw_payload',jsonb_build_object('title','ask'),'observation_kind','asking_price','occurred_at','2025-01-02T03:04:05Z','currency','CAD','amount',25),
    jsonb_build_object('raw_payload',jsonb_build_object('title','estimate'),'observation_kind','estimated_value','occurred_at','2025-01-03T03:04:05Z','currency','CAD','amount',30),
    jsonb_build_object('raw_payload',jsonb_build_object('title','sale'),'observation_kind','completed_sale','occurred_at','2025-01-04T03:04:05Z','currency','CAD','amount',20),
    jsonb_build_object('raw_payload',jsonb_build_object('title','excluded'),'observation_kind','asking_price','occurred_at','2025-01-05T03:04:05Z','currency','CAD','amount',99)),'x5d-stage');
  batch:=(result->>'batch_id')::uuid;
  select id into row1 from public.e10_intake_rows where batch_id=batch and source_row_number=1;
  select id into row2 from public.e10_intake_rows where batch_id=batch and source_row_number=2;
  select id into row3 from public.e10_intake_rows where batch_id=batch and source_row_number=3;
  select id into row4 from public.e10_intake_rows where batch_id=batch and source_row_number=4;
  perform public.e10_org_resolve_intake_row(o,row1,'match_product',product,'reviewed',null,'x5d-resolve-1');
  perform public.e10_org_resolve_intake_row(o,row2,'match_product',product,'reviewed estimate',null,'x5d-resolve-2');
  perform public.e10_org_resolve_intake_row(o,row3,'match_product',product,'reviewed sale',null,'x5d-resolve-3');
  perform public.e10_org_resolve_intake_row(o,row4,'reject',null,'not reliable',null,'x5d-resolve-4');
  revision:=(public.e10_org_intake_review_state(o,batch)->>'review_revision')::bigint;
  begin perform public.e10_org_commit_intake(o,batch,revision-1,'x5d-stale'); raise exception 'stale review committed'; exception when sqlstate '40001' then null; end;
  result:=public.e10_org_commit_intake(o,batch,revision,'x5d-commit');
  if (result->>'observation_count')::int<>3 or (result->>'rejected_row_count')::int<>1 or (result->>'replay')::boolean then raise exception 'commit result wrong %',result; end if;
  select count(*),min(occurred_at) into c,occurred from public.e10_market_observations where organization_id=o and intake_commit_id=(result->>'commit_id')::uuid;
  if c<>3 or occurred<>'2025-01-02T03:04:05Z' or(select count(distinct observation_kind)from public.e10_market_observations where organization_id=o and intake_commit_id=(result->>'commit_id')::uuid)<>3 then raise exception 'observation evidence separation wrong count=% occurred=%',c,occurred; end if;
  if(select count(*)from public.e10_inventory_movements)<>before_inventory or(select count(*)from public.e10_customer_transactions)<>before_customer then raise exception'supported market intake changed inventory or customer truth';end if;
  result:=public.e10_org_commit_intake(o,batch,revision,'x5d-commit');
  if not (result->>'replay')::boolean then raise exception 'commit replay missing'; end if;
  begin perform public.e10_org_commit_intake(o,batch,revision+1,'x5d-commit'); raise exception 'commit key mismatch accepted'; exception when sqlstate '22023' then null; end;
  result:=public.e10_org_resolve_intake_row(o,row1,'match_product',product,'reviewed',null,'x5d-resolve-1');
  if not (result->>'replay')::boolean then raise exception 'post-commit exact resolution replay missing'; end if;
  begin perform public.e10_org_resolve_intake_row(o,row1,'match_product',product,'changed reason',null,'x5d-resolve-1'); raise exception 'post-commit mismatched replay accepted'; exception when sqlstate '22023' then null; end;
  begin perform public.e10_org_commit_intake(o,batch,revision,'x5d-other-key'); raise exception 'second commit accepted'; exception when unique_violation then null; end;
  begin perform public.e10_org_resolve_intake_row(o,row1,'clear_match',null,'late edit',null,'x5d-late'); raise exception 'committed row changed'; exception when sqlstate '55000' then null; end;
  begin perform public.e10_org_commit_intake(other_org,batch,revision,'x5d-cross'); raise exception 'cross-org commit accepted'; exception when insufficient_privilege then null; end;
  result:=public.e10_org_stage_intake(o,'manual',null,'actionable',null,'x5d-actionable-fp',jsonb_build_array(
    jsonb_build_object('raw_payload',jsonb_build_object('receipt','untrusted'),'observation_kind','inventory_receipt','occurred_at','2025-01-04T03:04:05Z','quantity',1)),'x5d-actionable-stage');
  select id into row1 from public.e10_intake_rows where batch_id=(result->>'batch_id')::uuid;
  perform public.e10_org_resolve_intake_row(o,row1,'match_product',product,'identity only',null,'x5d-actionable-resolve');
  revision:=(public.e10_org_intake_review_state(o,(result->>'batch_id')::uuid)->>'review_revision')::bigint;
  begin perform public.e10_org_commit_intake(o,(result->>'batch_id')::uuid,revision,'x5d-actionable-commit'); raise exception 'receipt intake bypassed domain writer'; exception when sqlstate '55000' then null; end;
  select count(*) into c from public.e10_inventory_movements where organization_id=o and item_id like 'x5d%';
  if c<>0 then raise exception 'intake commit created inventory movement'; end if;
  if has_function_privilege('anon','public.e10_org_commit_intake(uuid,uuid,bigint,text)','execute') then raise exception 'commit exposed to anon'; end if;
  raise notice 'TA-X5d intake commit: PASS (reviewed observation, rejected exclusion, replay, immutable, cross-org denied)';
end $$;
rollback;
