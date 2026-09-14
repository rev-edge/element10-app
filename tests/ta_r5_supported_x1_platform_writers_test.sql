\set ON_ERROR_STOP on
begin;
do $$
declare admin_user uuid:=gen_random_uuid();ordinary uuid:=gen_random_uuid();player uuid:=gen_random_uuid();
  release_result jsonb;variant_result jsonb;map1 jsonb;map2 jsonb;map3 jsonb;release_id uuid;variant_id uuid;
begin
  insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at)values
    (admin_user,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',admin_user||'@r5.invalid',now(),now()),
    (ordinary,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',ordinary||'@r5.invalid',now(),now());
  insert into public.e10_platform_admins(user_id)values(admin_user);
  insert into public.e10_players(id,name)values(player,'R5 player');
  perform set_config('request.jwt.claims',jsonb_build_object('sub',admin_user,'role','authenticated')::text,true);set local role authenticated;
  release_result:=public.e10_platform_create_catalog_release('Maker','Line','R5 Release',2026,'2026','baseball','en','US','base','{}','r5-release');
  release_id:=(release_result->>'catalog_release_id')::uuid;
  if not(public.e10_platform_create_catalog_release('Maker','Line','R5 Release',2026,'2026','baseball','en','US','base','{}',' r5-release ')->>'replay')::boolean then raise exception'release replay failed';end if;
  variant_result:=public.e10_platform_create_catalog_variant(release_id,'1','Gold','gold','shimmer','en','base',true,50,'{}',jsonb_build_array(jsonb_build_object('player_id',player,'position',1,'subject_role','featured')),'r5-variant');
  variant_id:=(variant_result->>'catalog_variant_id')::uuid;
  map1:=public.e10_platform_review_catalog_identity_mapping('provider','variant','external-1',null,null,variant_id,'candidate',0.8,'{"source":"feed"}','r5-map-1');
  map2:=public.e10_platform_review_catalog_identity_mapping('provider','variant','external-1',null,null,variant_id,'verified',1,'{"source":"review"}','r5-map-2');
  map3:=public.e10_platform_review_catalog_identity_mapping('provider','variant','external-1',null,null,variant_id,'rejected',0,'{"source":"third"}','r5-map-3');
  if (map1->>'mapping_revision')::integer<>1 or(map2->>'mapping_revision')::integer<>2 or(map3->>'mapping_revision')::integer<>3
    or(select count(*)from public.e10_catalog_identity_mappings where provider='provider'and external_id='external-1'and is_current)<>1
    or not exists(select 1 from public.e10_catalog_identity_mappings where id=(map1->>'mapping_id')::uuid and not is_current)
    or not exists(select 1 from public.e10_catalog_identity_mappings where id=(map3->>'mapping_id')::uuid and is_current) then raise exception'mapping revision chain invalid';end if;
  reset role;begin update public.e10_catalog_identity_mappings set is_current=true where id=(map1->>'mapping_id')::uuid;raise exception'historical mapping resurrection accepted';exception when sqlstate'55000'then null;end;set local role authenticated;
  begin perform public.e10_platform_create_catalog_variant(release_id,'2',null,null,null,null,null,false,null,'{}','[{"player_id":"bad","position":1}]','r5-bad-subject');raise exception'malformed subject accepted';exception when sqlstate'22023'then null;end;
  begin perform public.e10_platform_create_catalog_variant(release_id,'2',null,null,null,null,null,false,null,'{"serial_numerator":1}','[]','r5-copy-attr');raise exception'copy-level variant attribute accepted';exception when sqlstate'22023'then null;end;
  begin perform public.e10_platform_review_catalog_identity_mapping(null,'variant','x',null,null,variant_id,'candidate',null,'{}','r5-null-provider');raise exception'null provider accepted';exception when sqlstate'22023'then null;end;
  begin perform public.e10_platform_review_catalog_identity_mapping('provider','variant','null-status',null,null,variant_id,null,null,'{}','r5-null-status');raise exception'null mapping status accepted';exception when sqlstate'22023'then null;end;
  begin insert into public.e10_catalog_releases(release_name)values('direct');raise exception'direct platform table write accepted';exception when insufficient_privilege then null;end;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',ordinary,'role','authenticated')::text,true);
  begin perform public.e10_platform_create_catalog_release(null,null,'denied',null,null,null,null,null,null,'{}','r5-denied');raise exception'non-admin platform write accepted';exception when sqlstate'42501'then null;end;
  if has_function_privilege('anon','public.e10_platform_create_catalog_release(text,text,text,integer,text,text,text,text,text,jsonb,text)','execute')then raise exception'platform writer exposed to anon';end if;
end $$;
rollback;
select 'TA-R5 supported platform X1 writers: PASS' result;
