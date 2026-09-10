\set ON_ERROR_STOP on
begin;
do $$
declare o uuid:='e1000000-0000-4000-8000-0000000000a6'; u uuid:=gen_random_uuid(); role_id uuid:=gen_random_uuid(); p1 uuid:=gen_random_uuid(); p2 uuid:=gen_random_uuid(); b1 uuid; b2 uuid; r1 uuid; r2 uuid; old_obs uuid; imported_obs uuid; manual_obs uuid; result jsonb;
begin
 insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at) values(u,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','x5e@x.invalid',now(),now());
 insert into public.e10_organization_roles(id,organization_id,key,name,is_system) values(role_id,o,'x5e','X5e',false);
 insert into public.e10_organization_role_permissions(organization_id,role_id,capability,allowed) values(o,role_id,'act.manage_intake',true);
 insert into public.e10_organization_memberships(organization_id,user_id,role_id,status) values(o,u,role_id,'active');
 insert into public.e10_product_masters(id,organization_id,name) values(p1,o,'X5e Product A'),(p2,o,'X5e Product B');
 perform set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated')::text,true);
 result:=public.e10_org_stage_intake(o,'csv','x5e-source','import-1','storage://x5e-1','x5e-fp-1',jsonb_build_array(jsonb_build_object('raw_payload','{"sold":100}'::jsonb,'observation_kind','completed_sale','occurred_at','2025-01-01T00:00:00Z','currency','USD','amount',100)),'x5e-stage-1');
 b1:=(result->>'batch_id')::uuid; select id into r1 from public.e10_intake_rows where batch_id=b1;
 perform public.e10_org_resolve_intake_row(o,r1,'match_product',p1,'reviewed',null,'x5e-resolve-1');
 perform public.e10_org_commit_intake(o,b1,(public.e10_org_intake_review_state(o,b1)->>'review_revision')::bigint,'x5e-commit-1');
 select id into old_obs from public.e10_market_observations where intake_row_id=r1;
 result:=public.e10_org_correct_market_observation(o,old_obs,'asking_price','product',p2,'2025-01-02T00:00:00Z','CAD',140,1,'manual','{"ask":140}','wrong type and identity','x5e-manual'); manual_obs:=(result->>'observation_id')::uuid;
 if not exists(select 1 from public.e10_market_observations where id=manual_obs and observation_kind='asking_price' and product_master_id=p2 and intake_row_id is null) then raise exception 'corrected kind/identity wrong'; end if;
 result:=public.e10_org_correct_market_observation(o,old_obs,'asking_price','product',p2,'2025-01-01T19:00:00-05','CAD',140,1,'manual','{"ask":140}','wrong type and identity','x5e-manual'); if not (result->>'replay')::boolean then raise exception 'timezone-stable replay failed'; end if;
 begin perform public.e10_org_correct_market_observation(o,old_obs,'asking_price','product',p2,'infinity','CAD',1,1,'x','{}','x','inf-time'); raise exception 'infinite time accepted'; exception when sqlstate '22023' then null; end;
 begin perform public.e10_org_correct_market_observation(o,old_obs,'asking_price','product',p2,now(),'CAD','NaN',1,'x','{}','x','nan'); raise exception 'NaN accepted'; exception when sqlstate '22023' then null; end;
 result:=public.e10_org_stage_intake(o,'api','x5e-source','import-2','api://x5e-2','x5e-fp-2',jsonb_build_array(jsonb_build_object('raw_payload','{"value":150}'::jsonb,'observation_kind','estimated_value','occurred_at','2025-02-01T00:00:00Z','currency','CAD','amount',150)),'x5e-stage-2');
 b2:=(result->>'batch_id')::uuid; select id into r2 from public.e10_intake_rows where batch_id=b2;
 perform public.e10_org_resolve_intake_row(o,r2,'match_product',p2,'reviewed reimport',null,'x5e-resolve-2'); perform public.e10_org_commit_intake(o,b2,(public.e10_org_intake_review_state(o,b2)->>'review_revision')::bigint,'x5e-commit-2');
 select id into imported_obs from public.e10_market_observations where intake_row_id=r2;
 result:=public.e10_org_reconcile_market_observation_reimport(o,manual_obs,imported_obs,'reviewed replacement','x5e-reimport'); result:=public.e10_org_reconcile_market_observation_reimport(o,manual_obs,imported_obs,'reviewed replacement','x5e-reimport'); if not (result->>'replay')::boolean then raise exception 'reimport replay failed'; end if;
 if not exists(select 1 from public.e10_market_observation_supersessions s join public.e10_market_observations n on n.id=s.replacement_observation_id where s.superseded_observation_id=manual_obs and s.lineage_kind='reviewed_reimport' and n.intake_row_id=r2 and n.intake_commit_id is not null) then raise exception 'reimport provenance absent'; end if;
 if (select amount from public.e10_market_observations where id=old_obs)<>100 then raise exception 'prior evidence mutated'; end if;
 begin
  perform public.e10_org_reconcile_market_observation_reimport(o,imported_obs,old_obs,'must reject multi-hop cycle','x5e-cycle');
  raise exception 'multi-hop lineage cycle accepted';
 exception when sqlstate '22023' then
  if sqlerrm<>'observation_lineage_cycle' then raise; end if;
 end;
 begin perform public.e10_org_reconcile_market_observation_reimport(o,old_obs,imported_obs,'branch','x5e-branch'); raise exception 'branch accepted'; exception when sqlstate '55000' then null; end;
 raise notice 'TA-X5e observation lineage: PASS';
end $$;
rollback;
