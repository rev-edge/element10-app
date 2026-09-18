\set ON_ERROR_STOP on
begin;
do $$
declare
  admin_id uuid:=gen_random_uuid();ordinary_id uuid:=gen_random_uuid();
  player_one uuid:=gen_random_uuid();player_two uuid:=gen_random_uuid();
  proposed jsonb;replay jsonb;rejected jsonb;read_result jsonb;second_read jsonb;case_id uuid;second_case_id uuid;page_cursor uuid;seen uuid[];
begin
  insert into auth.users(id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
  values(admin_id,'authenticated','authenticated','f4-admin@example.invalid','',now(),'{}','{}',now(),now()),
    (ordinary_id,'authenticated','authenticated','f4-member@example.invalid','',now(),'{}','{}',now(),now());
  insert into public.e10_platform_admins(user_id,created_by)values(admin_id,admin_id);
  insert into public.e10_players(id,name)values(player_one,'Same Name'),(player_two,'Same Name');
  perform set_config('request.jwt.claims',jsonb_build_object('sub',admin_id,'role','authenticated')::text,true);
  execute'set local role authenticated';
  proposed:=public.e10_platform_propose_player_identity_review('manual:operator','case-001','Same Name','manual','Operator review',null,'{"source":"operator supplied"}',jsonb_build_array(jsonb_build_object('player_id',player_one,'confidence_status','known','confidence',0.8,'evidence',jsonb_build_object('basis','candidate one')),jsonb_build_object('player_id',player_two,'confidence_status','unknown','confidence',null,'evidence',jsonb_build_object('basis','candidate two'))),'Ambiguous same-name identity','{"review":"required"}','f4-propose');
  case_id:=(proposed->>'case_id')::uuid;
  if proposed->>'status'is distinct from'pending'or(proposed->>'revision')::bigint is distinct from 1 or(proposed->>'replay')::boolean then raise exception'F4 proposal result invalid: %',proposed;end if;
  replay:=public.e10_platform_propose_player_identity_review('manual:operator','case-001','Same Name','manual','Operator review',null,'{"source":"operator supplied"}',jsonb_build_array(jsonb_build_object('player_id',player_one,'confidence_status','known','confidence',0.8,'evidence',jsonb_build_object('basis','candidate one')),jsonb_build_object('player_id',player_two,'confidence_status','unknown','confidence',null,'evidence',jsonb_build_object('basis','candidate two'))),'Ambiguous same-name identity','{"review":"required"}','f4-propose');
  if not(replay->>'replay')::boolean or(replay->>'case_id')::uuid is distinct from case_id then raise exception'F4 proposal replay invalid';end if;
  begin
    perform public.e10_platform_propose_player_identity_review('manual:operator','case-001','Changed Name','manual','Operator review',null,'{"source":"changed"}',jsonb_build_array(jsonb_build_object('player_id',player_one,'confidence_status','known','confidence',0.8,'evidence','{}'::jsonb),jsonb_build_object('player_id',player_two,'confidence_status','unknown','confidence',null,'evidence','{}'::jsonb)),'Changed payload','{}','f4-propose');
    raise exception'F4 changed idempotent proposal accepted';exception when invalid_parameter_value then if sqlerrm<>'idempotency_key_mismatch'then raise;end if;end;
  read_result:=public.e10_platform_player_identity_review_cases('pending',1,null);
  if jsonb_array_length(read_result->'rows')is distinct from 1 or read_result#>>'{rows,0,case_id}'is distinct from case_id::text
    or jsonb_array_length(read_result#>'{rows,0,candidates}')is distinct from 2 or jsonb_array_length(read_result#>'{rows,0,decision_history}')is distinct from 1
    or(read_result#>>'{rows,0,candidates,0,display_name}')is distinct from'Same Name'or(read_result#>>'{rows,0,candidates,1,display_name}')is distinct from'Same Name'
    or not(read_result->'limitations')@>'["no_approval","no_canonical_link","no_merge_or_split","no_automatic_candidate_generation"]'::jsonb then raise exception'F4 pending review read invalid: %',read_result;end if;
  if not exists(select 1 from jsonb_array_elements(read_result#>'{rows,0,candidates}')c where c->>'confidence_status'='known'and(c->>'confidence')::numeric=0.8)
    or not exists(select 1 from jsonb_array_elements(read_result#>'{rows,0,candidates}')c where c->>'confidence_status'='unknown'and c->'confidence'='null'::jsonb)then raise exception'F4 confidence semantics invalid: %',read_result;end if;
  if array(select(c->>'player_id')::uuid from jsonb_array_elements(read_result#>'{rows,0,candidates}')c order by(c->>'player_id')::uuid)
     is distinct from array(select x from unnest(array[player_one,player_two])x order by x)
     or(select count(*)from public.e10_players where name_norm='same name')is distinct from 2 then raise exception'F4 deterministic same-name candidates invalid';end if;
  replay:=public.e10_platform_propose_player_identity_review('model:identity-matcher','case-002','Same Name','model','identity-matcher','v1.2.3','{"source":"model proposal","trace":"retained"}',jsonb_build_array(jsonb_build_object('player_id',player_one,'confidence_status','unknown','confidence',null,'evidence','{}'::jsonb),jsonb_build_object('player_id',player_two,'confidence_status','unknown','confidence',null,'evidence','{}'::jsonb)),'Second ambiguity','{}','f4-propose-2');second_case_id:=(replay->>'case_id')::uuid;
  read_result:=public.e10_platform_player_identity_review_cases('pending',1,null);page_cursor:=(read_result->>'next_after_case_id')::uuid;second_read:=public.e10_platform_player_identity_review_cases('pending',1,page_cursor);seen:=array[(read_result#>>'{rows,0,case_id}')::uuid,(second_read#>>'{rows,0,case_id}')::uuid];
  if page_cursor is null or jsonb_array_length(read_result->'rows')<>1 or jsonb_array_length(second_read->'rows')<>1 or second_read->'next_after_case_id'<>'null'::jsonb or cardinality(array(select distinct x from unnest(seen)x))<>2 or not seen@>array[case_id,second_case_id]then raise exception'F4 bounded reader continuation invalid: %, %',read_result,second_read;end if;
  if not exists(select 1 from jsonb_array_elements((read_result->'rows')||(second_read->'rows'))r where r->>'proposer_kind'='model'and r->>'proposer_name'='identity-matcher'and r->>'proposer_version'='v1.2.3'and r#>>'{source_evidence,trace}'='retained')then raise exception'F4 model provenance not preserved';end if;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',ordinary_id,'role','authenticated')::text,true);
  begin perform public.e10_platform_player_identity_review_cases(null,10,null);raise exception'F4 ordinary reader allowed';exception when insufficient_privilege then null;end;
  begin perform public.e10_platform_reject_player_identity_review(case_id,1,'Denied','{}','f4-denied');raise exception'F4 ordinary reject allowed';exception when insufficient_privilege then null;end;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',admin_id,'role','authenticated')::text,true);
  rejected:=public.e10_platform_reject_player_identity_review(case_id,1,'Not enough evidence','{"outcome":"retain both"}','f4-reject');
  replay:=public.e10_platform_reject_player_identity_review(case_id,1,'Not enough evidence','{"outcome":"retain both"}','f4-reject');
  if rejected->>'status'is distinct from'rejected'or(rejected->>'revision')::bigint is distinct from 2 or not(replay->>'replay')::boolean then raise exception'F4 rejection or replay invalid';end if;
  begin perform public.e10_platform_reject_player_identity_review(case_id,1,'Stale','{}','f4-reject-stale');raise exception'F4 stale reject accepted';exception when serialization_failure then null;end;
  read_result:=public.e10_platform_player_identity_review_cases('rejected',10,null);
  if read_result#>>'{rows,0,status}'is distinct from'rejected'or jsonb_array_length(read_result#>'{rows,0,candidates}')is distinct from 2
    or jsonb_array_length(read_result#>'{rows,0,decision_history}')is distinct from 2 or(select count(*)from public.e10_players where id in(player_one,player_two))is distinct from 2
    or exists(select 1 from public.e10_catalog_identity_mappings where entity_kind='player'and player_id in(player_one,player_two))then raise exception'F4 rejection did not preserve ambiguity: %',read_result;end if;
  if has_function_privilege('anon','public.e10_platform_propose_player_identity_review(text,text,text,text,text,text,jsonb,jsonb,text,jsonb,text)','execute')or has_function_privilege('anon','public.e10_platform_reject_player_identity_review(uuid,bigint,text,jsonb,text)','execute')or has_function_privilege('anon','public.e10_platform_player_identity_review_cases(text,integer,uuid)','execute')then raise exception'F4 anon function access';end if;
  execute'reset role';
end $$;
rollback;
select'TA-F4 identity ambiguity review PASS'result;
