\set ON_ERROR_STOP on
begin;
do $$
declare
  org_a uuid:='e1000000-0000-4000-8000-0000000000a6'; org_b uuid:=gen_random_uuid();
  user_a uuid:=gen_random_uuid(); user_b uuid:=gen_random_uuid(); role_a uuid:=gen_random_uuid(); role_b uuid:=gen_random_uuid();
  release_id uuid:=gen_random_uuid(); variant_id uuid:=gen_random_uuid(); batch_a uuid; batch_b uuid; row_a uuid; row_b uuid; old_a uuid; replacement_a uuid; result jsonb;
begin
  insert into public.e10_organizations(id,name,slug) values(org_b,'X5h Org B','x5h-'||replace(org_b::text,'-',''));
  insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at) values
    (user_a,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',user_a||'@x.invalid',now(),now()),
    (user_b,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',user_b||'@x.invalid',now(),now());
  insert into public.e10_organization_roles(id,organization_id,key,name,is_system) values
    (role_a,org_a,'x5h-'||user_a,'X5h A',false),(role_b,org_b,'x5h-'||user_b,'X5h B',false);
  insert into public.e10_organization_role_permissions(organization_id,role_id,capability,allowed) values
    (org_a,role_a,'act.manage_intake',true),(org_b,role_b,'act.manage_intake',true);
  insert into public.e10_organization_memberships(organization_id,user_id,role_id,status) values
    (org_a,user_a,role_a,'active'),(org_b,user_b,role_b,'active');
  insert into public.e10_catalog_releases(id,release_name,release_year,sport) values(release_id,'X5h Shared Release',2026,'soccer');
  insert into public.e10_catalog_variants(id,release_id,card_number,exact_parallel) values(variant_id,release_id,'10','Gold');

  perform set_config('request.jwt.claims',jsonb_build_object('sub',user_a,'role','authenticated')::text,true);
  result:=public.e10_org_stage_intake(org_a,'api','x5h-source-a','variant evidence',null,'x5h-a',jsonb_build_array(jsonb_build_object('raw_payload','{}'::jsonb,'observation_kind','completed_sale','occurred_at','2026-01-01T00:00:00Z','currency','CAD','amount',100)),'x5h-stage-a');
  batch_a:=(result->>'batch_id')::uuid; select id into row_a from public.e10_intake_rows where batch_id=batch_a;
  perform public.e10_org_resolve_intake_row(org_a,row_a,'match_catalog_variant',variant_id,'catalog evidence without owned copy',null,'x5h-resolve-a');
  perform public.e10_org_commit_intake(org_a,batch_a,(public.e10_org_intake_review_state(org_a,batch_a)->>'review_revision')::bigint,'x5h-commit-a');
  select id into old_a from public.e10_market_observations where organization_id=org_a and intake_row_id=row_a;
  result:=public.e10_org_correct_market_observation(org_a,old_a,'completed_sale','catalog_variant',variant_id,'2026-01-01T00:00:00Z','CAD',105,1,'reviewed-correction','{}','corrected amount','x5h-correct-a');
  replacement_a:=(result->>'observation_id')::uuid;

  perform set_config('request.jwt.claims',jsonb_build_object('sub',user_b,'role','authenticated')::text,true);
  result:=public.e10_org_stage_intake(org_b,'api','x5h-source-b','same shared variant',null,'x5h-b',jsonb_build_array(jsonb_build_object('raw_payload','{}'::jsonb,'observation_kind','asking_price','occurred_at','2026-01-02T00:00:00Z','currency','CAD','amount',120)),'x5h-stage-b');
  batch_b:=(result->>'batch_id')::uuid; select id into row_b from public.e10_intake_rows where batch_id=batch_b;
  perform public.e10_org_resolve_intake_row(org_b,row_b,'match_catalog_variant',variant_id,'shared catalog target',null,'x5h-resolve-b');
  perform public.e10_org_commit_intake(org_b,batch_b,(public.e10_org_intake_review_state(org_b,batch_b)->>'review_revision')::bigint,'x5h-commit-b');

  if (select count(*) from public.e10_market_observations where catalog_variant_id=variant_id)<>3 then raise exception 'shared variant evidence history missing'; end if;
  if (select count(distinct organization_id) from public.e10_market_observations where catalog_variant_id=variant_id)<>2 then raise exception 'variant evidence lost tenant scope'; end if;
  if exists(select 1 from public.e10_unique_items where catalog_variant_id=variant_id) then raise exception 'catalog evidence fabricated ownership'; end if;
  if exists(select 1 from public.e10_market_observations where catalog_variant_id=variant_id and num_nonnulls(product_master_id,configuration_version_id,unique_item_id)<>0) then raise exception 'variant observation has mixed grain'; end if;
  if (select count(*) from public.e10_current_market_observations where catalog_variant_id=variant_id)<>2
    or exists(select 1 from public.e10_current_market_observations where id=old_a)
    or not exists(select 1 from public.e10_current_market_observations where id=replacement_a and catalog_variant_id=variant_id and amount=105)
  then raise exception 'eligible-current variant projection wrong'; end if;
  raise notice 'TA-X5h catalog-variant observations: PASS (shared target, tenant evidence, corrected current view, no ownership)';
end $$;
rollback;
