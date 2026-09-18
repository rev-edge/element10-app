\set ON_ERROR_STOP on
begin;

do $$
declare
 actor uuid:='c4000000-0000-4000-8000-000000000010';
 outsider uuid:='c4000000-0000-4000-8000-000000000011';
 platform uuid:='c4000000-0000-4000-8000-000000000001';
 expected timestamptz;result jsonb;
begin
 insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at)values
 (actor,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','c4-admin@example.invalid',now(),now()),
 (outsider,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','c4-outsider@example.invalid',now(),now());
 insert into public.e10_platform_admins(user_id)values(actor);
 select updated_at into expected from public.e10_platforms where id=platform;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',outsider,'role','authenticated')::text,true);
 begin
  perform public.e10_platform_review_name(platform,expected,'Whatnot Marketplace','review','c4-name');
  raise exception 'ordinary user changed platform name';
 exception when insufficient_privilege then if sqlerrm<>'platform_registry_curation_denied'then raise;end if;end;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',actor,'role','authenticated')::text,true);
 result:=public.e10_platform_review_name(platform,expected,'Whatnot Marketplace','review','c4-name');
 if result->>'replay'<>'false'or(select current_name from public.e10_platforms where id=platform)<>'Whatnot Marketplace'
  or(select count(*) from public.e10_platform_name_decisions where platform_id=platform)<>2 then raise exception 'platform name history mismatch';end if;
 result:=public.e10_platform_review_name(platform,expected,'Whatnot Marketplace','review','c4-name');
 if result->>'replay'<>'true'then raise exception 'platform name replay mismatch';end if;
 begin
  perform public.e10_platform_review_name(platform,expected,'Stale','stale','c4-stale');
  raise exception 'stale platform name update accepted';
 exception when serialization_failure then if sqlerrm<>'platform_revision_conflict'then raise;end if;end;
end$$;

do $$
declare org uuid:='e1000000-0000-4000-8000-0000000000a6';channel uuid:='c4000000-0000-4000-8000-000000000020';
begin
 insert into public.e10_obs_channels(id,organization_id,handle,family)values(channel,org,'c4-channel','whatnot');
 if(select platform_id from public.e10_obs_channels where id=channel)is distinct from'c4000000-0000-4000-8000-000000000001'::uuid then raise exception 'known legacy family not stamped';end if;
 begin
  insert into public.e10_obs_channels(id,organization_id,handle,family)values('c4000000-0000-4000-8000-000000000021',org,'c4-unknown','invented');
  raise exception 'unknown platform family accepted';
 exception when check_violation then if sqlerrm<>'platform_identity_unknown'then raise;end if;end;
end$$;

do $$begin
 if has_function_privilege('anon','public.e10_platform_review_name(uuid,timestamptz,text,text,text)','execute')
  or has_function_privilege('anon','public.e10_org_lookup_live_buyer(uuid,uuid,text,text)','execute')then raise exception 'anonymous platform RPC leak';end if;
 if not has_function_privilege('authenticated','public.e10_org_lookup_live_buyer(uuid,uuid,text,text)','execute')then raise exception 'authenticated live lookup missing';end if;
end$$;

rollback;
select 'schema review C4 platform bridge PASS' result;
