\set ON_ERROR_STOP on
begin;
do $$
declare o uuid:='e1000000-0000-4000-8000-0000000000a6'; u uuid:=gen_random_uuid(); role_id uuid:=gen_random_uuid(); product uuid:=gen_random_uuid(); b1 uuid; b2 uuid; r1 uuid; r2 uuid; r3 uuid; old_obs uuid; new_obs uuid; extra_obs uuid; revision bigint; result jsonb; classes jsonb;
begin
 insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at) values(u,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','x5f@x.invalid',now(),now());
 insert into public.e10_organization_roles(id,organization_id,key,name,is_system) values(role_id,o,'x5f','X5f',false);
 insert into public.e10_organization_role_permissions values(o,role_id,'act.manage_intake',true);
 insert into public.e10_organization_memberships(organization_id,user_id,role_id,status) values(o,u,role_id,'active');
 insert into public.e10_product_masters(id,organization_id,name) values(product,o,'X5f Product');
 perform set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated')::text,true);
 result:=public.e10_org_stage_intake(o,'csv','vendor','daily.csv','storage://v1','sha-v1',jsonb_build_array(jsonb_build_object('raw_payload','{"ask":10,"source_event_id":"sale-1"}'::jsonb,'observation_kind','asking_price','occurred_at','2025-01-01T00:00:00Z','currency','CAD','amount',10)),'x5f-stage-1'); b1:=(result->>'batch_id')::uuid;
 result:=public.e10_org_stage_intake(o,'csv','vendor','daily.csv','storage://v1','sha-v1',jsonb_build_array(jsonb_build_object('raw_payload','{"ask":10,"source_event_id":"sale-1"}'::jsonb,'observation_kind','asking_price','occurred_at','2025-01-01T00:00:00Z','currency','CAD','amount',10)),'x5f-stage-copy'); if not (result->>'replay')::boolean or (result->>'batch_id')::uuid<>b1 then raise exception 'exact source replay failed'; end if;
 begin perform public.e10_org_stage_intake(o,'csv','vendor','other.csv','storage://other','sha-other',jsonb_build_array(jsonb_build_object('raw_payload','{}'::jsonb,'observation_kind','asking_price','occurred_at','2025-01-01T00:00:00Z','currency','CAD','amount',10)),'x5f-stage-copy'); raise exception 'source replay key mismatch accepted'; exception when sqlstate '22023' then null; end;
 begin perform public.e10_org_stage_intake(o,'csv','vendor','daily.csv','storage://v1','sha-v1',jsonb_build_array(jsonb_build_object('raw_payload','{}'::jsonb,'observation_kind','asking_price','occurred_at','2025-01-01T00:00:00Z','currency','CAD','amount',99)),'x5f-stage-copy-2'); raise exception 'lying payload fingerprint accepted'; exception when sqlstate '22023' then null; end;
 select id into r1 from public.e10_intake_rows where batch_id=b1; perform public.e10_org_resolve_intake_row(o,r1,'match_product',product,'reviewed',null,'x5f-resolve-1'); revision:=(public.e10_org_intake_review_state(o,b1)->>'review_revision')::bigint; perform public.e10_org_commit_intake(o,b1,revision,'x5f-commit-1'); select id into old_obs from public.e10_market_observations where intake_row_id=r1;
 result:=public.e10_org_stage_intake(o,'csv','vendor','daily.csv','storage://v2','sha-v2',jsonb_build_array(
  jsonb_build_object('raw_payload','{"ask":99,"source_event_id":"sale-new"}'::jsonb,'observation_kind','asking_price','occurred_at','2025-01-03T00:00:00Z','currency','CAD','amount',99),
  jsonb_build_object('raw_payload','{"ask":12,"source_event_id":"sale-1"}'::jsonb,'observation_kind','asking_price','occurred_at','2025-01-02T00:00:00Z','currency','CAD','amount',12)),'x5f-stage-2'); b2:=(result->>'batch_id')::uuid; if (result->>'supersedes_batch_id')::uuid<>b1 then raise exception 'changed source lineage missing'; end if;
 select id into r3 from public.e10_intake_rows where batch_id=b2 and source_row_number=1; select id into r2 from public.e10_intake_rows where batch_id=b2 and source_row_number=2;
 perform public.e10_org_resolve_intake_row(o,r3,'match_product',product,'reviewed inserted row',null,'x5f-resolve-3'); perform public.e10_org_resolve_intake_row(o,r2,'match_product',product,'reviewed moved correction',null,'x5f-resolve-2'); revision:=(public.e10_org_intake_review_state(o,b2)->>'review_revision')::bigint;
 begin perform public.e10_org_commit_intake(o,b2,revision,'x5f-wrong-commit'); raise exception 'changed source committed without classification'; exception when sqlstate '55000' then null; end;
 begin perform public.e10_org_commit_corrected_intake(o,b2,revision,'[]','x5f-missing-class'); raise exception 'missing classification accepted'; exception when sqlstate '22023' then null; end;
 begin perform public.e10_org_commit_corrected_intake(o,b2,revision,'[{"source_row_number":1},{"source_row_number":2,"classification":"replacement"}]','x5f-null-class'); raise exception 'null classification accepted'; exception when sqlstate '22023' then null; end;
 begin perform public.e10_org_commit_corrected_intake(o,b2,revision,jsonb_build_array(jsonb_build_object('source_row_number',1,'classification','new','reason','inserted'),jsonb_build_object('source_row_number',2,'classification','replacement','superseded_observation_id',old_obs,'reason','moved')),'x5f-unreviewed-new'); raise exception 'new row without duplicate review accepted'; exception when sqlstate '22023' then null; end;
 classes:=jsonb_build_array(jsonb_build_object('source_row_number',1,'classification','new','reason','reviewed inserted source event','duplicate_reviewed',true),jsonb_build_object('source_row_number',2,'classification','replacement','superseded_observation_id',old_obs,'reason','corrected vendor row moved during reorder'));
 result:=public.e10_org_commit_corrected_intake(o,b2,revision,classes,'x5f-corrected'); select id into new_obs from public.e10_market_observations where intake_row_id=r2; select id into extra_obs from public.e10_market_observations where intake_row_id=r3;
 if (select count(*) from public.e10_current_market_observations where id in(old_obs,new_obs,extra_obs))<>2 or exists(select 1 from public.e10_current_market_observations where id=old_obs) then raise exception 'eligible interpretation wrong'; end if;
 result:=public.e10_org_commit_corrected_intake(o,b2,revision,classes,'x5f-corrected'); if not (result->>'replay')::boolean then raise exception 'corrected commit replay failed'; end if;
 begin perform public.e10_org_commit_corrected_intake(o,b2,revision,classes||jsonb_build_array(jsonb_build_object('source_row_number',2,'classification','new')),'x5f-corrected'); raise exception 'corrected commit mismatch accepted'; exception when sqlstate '22023' then null; end;
 if (select count(*) from public.e10_market_observations where id in(old_obs,new_obs,extra_obs))<>3 then raise exception 'immutable source evidence lost'; end if;
 raise notice 'TA-X5f atomic corrected-file import: PASS';
end $$;
rollback;
