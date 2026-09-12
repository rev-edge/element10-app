\set ON_ERROR_STOP on
begin;
do $$
declare
  o uuid:=gen_random_uuid();foreign_org uuid:=gen_random_uuid();
  actor uuid:=gen_random_uuid();hostile uuid:=gen_random_uuid();
  role_id uuid:=gen_random_uuid();hostile_role uuid:=gen_random_uuid();
  subject_id uuid:=gen_random_uuid();wrong_subject uuid:=gen_random_uuid();
  release_one uuid:=gen_random_uuid();release_two uuid:=gen_random_uuid();release_three uuid:=gen_random_uuid();
  variant_one uuid:=gen_random_uuid();variant_two uuid:=gen_random_uuid();variant_unknown uuid:=gen_random_uuid();variant_wrong_grade uuid:=gen_random_uuid();
  observation_one uuid:=gen_random_uuid();observation_two uuid:=gen_random_uuid();observation_unknown uuid:=gen_random_uuid();observation_wrong_grade uuid:=gen_random_uuid();
  filters jsonb;first_page jsonb;second_page jsonb;negative jsonb;cursor_id uuid;
  seen uuid[];first_fp text;first_org_revision bigint;first_catalog_revision bigint;
begin
  insert into auth.users(id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
  values(actor,'authenticated','authenticated','x7d-f3@example.invalid','',now(),'{}','{}',now(),now()),
    (hostile,'authenticated','authenticated','x7d-f3-hostile@example.invalid','',now(),'{}','{}',now(),now());
  insert into public.e10_organizations(id,slug,name)
  values(o,'x7d-f3-'||substr(o::text,1,8),'F3 cross-product'),
    (foreign_org,'x7d-f3h-'||substr(foreign_org::text,1,8),'F3 hostile');
  insert into public.e10_organization_roles(id,organization_id,key,name)
  values(role_id,o,'analyst','Analyst'),(hostile_role,foreign_org,'analyst','Analyst');
  insert into public.e10_organization_memberships(organization_id,user_id,role_id,status)
  values(o,actor,role_id,'active'),(foreign_org,hostile,hostile_role,'active');
  insert into public.e10_organization_role_permissions(organization_id,role_id,capability,allowed)
  values(o,role_id,'act.view_market_analytics',true),(foreign_org,hostile_role,'act.view_market_analytics',true);

  insert into public.e10_players(id,name)
  values(subject_id,'Shared Cross-Product Subject'),(wrong_subject,'Different Subject');
  insert into public.e10_catalog_releases(id,release_name,release_year,sport,league,manufacturer,brand_line)
  values(release_one,'F3 Product One',2024,'baseball','MLB','Maker One','Line One'),
    (release_two,'F3 Product Two',2025,'baseball','MLB','Maker Two','Line Two'),
    (release_three,'F3 Product Three',2026,'baseball','MLB','Maker Three','Line Three');
  insert into public.e10_catalog_variants(id,release_id,card_number)
  values(variant_one,release_one,'1'),(variant_two,release_two,'2'),
    (variant_unknown,release_three,'3'),(variant_wrong_grade,release_three,'4');
  insert into public.e10_catalog_variant_subjects(variant_id,player_id,position)
  values(variant_one,subject_id,1),(variant_two,subject_id,1),
    (variant_unknown,subject_id,1),(variant_wrong_grade,subject_id,1);

  set local session_replication_role=replica;
  insert into public.e10_market_observations(id,organization_id,observation_kind,catalog_variant_id,occurred_at,currency,amount,quantity,source_kind,source_connection_id,raw_payload_snapshot)
  values(observation_one,o,'completed_sale',variant_one,'2026-01-10','USD',100,1,'manual','f3-one','{}'),
    (observation_two,o,'completed_sale',variant_two,'2026-01-11','USD',200,1,'manual','f3-two','{}'),
    (observation_unknown,o,'completed_sale',variant_unknown,'2026-01-12','USD',300,1,'manual','f3-unknown','{}'),
    (observation_wrong_grade,o,'completed_sale',variant_wrong_grade,'2026-01-13','USD',400,1,'manual','f3-wrong-grade','{}');
  set local session_replication_role=origin;
  insert into public.e10_market_observation_fact_decisions(organization_id,decision_key,observation_id,revision,action,condition_state,grader_code,grade_label,transaction_quantity,amount_basis,reviewed_unit_amount,reason,evidence,idempotency_key,request_fingerprint)
  values(o,gen_random_uuid(),observation_one,1,'assert','graded','PSA','9',1,'unit_price',100,'F3','{}','f3-fact-one','f3-fact-one'),
    (o,gen_random_uuid(),observation_two,1,'assert','graded','PSA','9',1,'unit_price',200,'F3','{}','f3-fact-two','f3-fact-two'),
    (o,gen_random_uuid(),observation_unknown,1,'assert','graded','PSA','9',1,'unit_price',300,'F3','{}','f3-fact-unknown','f3-fact-unknown'),
    (o,gen_random_uuid(),observation_wrong_grade,1,'assert','graded','PSA','8',1,'unit_price',400,'F3','{}','f3-fact-wrong','f3-fact-wrong');
  insert into public.e10_catalog_variant_facet_decisions(decision_key,variant_id,subject_id,facet_key,revision,action,boolean_value,reason,evidence,idempotency_key,request_fingerprint)
  values(gen_random_uuid(),variant_one,subject_id,'rookie_designation',1,'assert',true,'F3','{}','f3-rookie-one','f3-rookie-one'),
    (gen_random_uuid(),variant_two,subject_id,'rookie_designation',1,'assert',true,'F3','{}','f3-rookie-two','f3-rookie-two'),
    (gen_random_uuid(),variant_wrong_grade,subject_id,'rookie_designation',1,'assert',true,'F3','{}','f3-rookie-wrong','f3-rookie-wrong');

  perform set_config('request.jwt.claims',jsonb_build_object('sub',actor,'role','authenticated')::text,true);
  filters:=jsonb_build_object('subject_id',subject_id,'rookie_designation',true,'condition_state','graded','grader_code','PSA','grade_label','9');
  first_page:=public.e10_org_market_screener(o,'catalog','variant','count','completed_sale','2026-01-01','2026-02-01','2026-02-01','USD','none',null,null,filters,'cohort_asc',1,null);
  cursor_id:=(first_page->>'next_cursor')::uuid;
  if jsonb_array_length(first_page->'rows')is distinct from 1 or cursor_id is null then
    raise exception'F3 first page or continuation missing: %',first_page;
  end if;
  first_fp:=first_page->>'query_fingerprint';
  first_org_revision:=(first_page->>'organization_revision')::bigint;
  first_catalog_revision:=(first_page->>'catalog_revision')::bigint;
  second_page:=public.e10_org_market_screener(o,'catalog','variant','count','completed_sale','2026-01-01','2026-02-01','2026-02-01','USD','none',null,null,filters,'cohort_asc',1,cursor_id);
  if jsonb_array_length(second_page->'rows')is distinct from 1 or second_page->'next_cursor'is distinct from'null'::jsonb
     or second_page->>'query_fingerprint'is distinct from first_fp
     or(second_page->>'organization_revision')::bigint is distinct from first_org_revision
     or(second_page->>'catalog_revision')::bigint is distinct from first_catalog_revision then
    raise exception'F3 stable continuation failed: %',second_page;
  end if;
  seen:=array[(first_page#>>'{rows,0,catalog_variant_id}')::uuid,(second_page#>>'{rows,0,catalog_variant_id}')::uuid];
  if cardinality(array(select distinct x from unnest(seen)x))is distinct from 2
     or not seen@>array[variant_one,variant_two] or seen&&array[variant_unknown,variant_wrong_grade] then
    raise exception'F3 combined query membership failed: %',seen;
  end if;

  negative:=public.e10_org_market_screener(o,'catalog','variant','count','completed_sale','2026-01-01','2026-02-01','2026-02-01','USD','none',null,null,filters||'{"grade_label":"10"}'::jsonb,'cohort_asc',10,null);
  if jsonb_array_length(negative->'rows')is distinct from 0 then raise exception'F3 wrong grade matched';end if;
  negative:=public.e10_org_market_screener(o,'catalog','variant','count','completed_sale','2026-01-01','2026-02-01','2026-02-01','USD','none',null,null,filters||jsonb_build_object('subject_id',wrong_subject),'cohort_asc',10,null);
  if jsonb_array_length(negative->'rows')is distinct from 0 then raise exception'F3 wrong subject matched';end if;
  begin
    perform public.e10_org_market_screener(o,'catalog','variant','count','completed_sale','2026-01-01','2026-02-01','2026-02-01','USD','none',null,null,filters||'{"grade_label":"8"}'::jsonb,'cohort_asc',1,cursor_id);
    raise exception'F3 changed-filter cursor accepted';
  exception when invalid_parameter_value then null;end;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',hostile,'role','authenticated')::text,true);
  begin
    perform public.e10_org_market_screener(o,'catalog','variant','count','completed_sale','2026-01-01','2026-02-01','2026-02-01','USD','none',null,null,filters,'cohort_asc',1,null);
    raise exception'F3 hostile organization reader allowed';
  exception when insufficient_privilege then null;end;
end $$;
rollback;
select'TA-X7d.2 F3 cross-product rookie PSA 9 public pagination PASS'result;
