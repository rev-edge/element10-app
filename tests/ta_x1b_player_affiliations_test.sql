-- TA-X1b governed dated affiliations and depicted-team context. Transactional.
begin;

do $$
declare
  org uuid := 'e1000000-0000-4000-8000-0000000000a6';
  admin_user uuid := 'a7000000-0000-4000-8000-00000000e210';
  member_user uuid := 'a7000000-0000-4000-8000-00000000e211';
  outsider uuid := 'a7000000-0000-4000-8000-00000000e212';
  player uuid := 'a7000000-0000-4000-8000-00000000e213';
  old_team uuid := 'a7000000-0000-4000-8000-00000000e214';
  new_team uuid := 'a7000000-0000-4000-8000-00000000e215';
  release_id uuid := 'a7000000-0000-4000-8000-00000000e216';
  variant uuid := 'a7000000-0000-4000-8000-00000000e217';
begin
  insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at)
  select u,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',replace(u::text,'-','')||'@ta-x1b.invalid',now(),now()
  from unnest(array[admin_user,member_user,outsider])u on conflict(id)do nothing;
  insert into public.e10_platform_admins(user_id)values(admin_user)on conflict do nothing;
  insert into public.e10_organization_memberships(organization_id,user_id,role_id,status) values(org,member_user,'e1000000-0000-4000-8000-000000000004','active') on conflict(organization_id,user_id)do update set status='active';
  insert into public.e10_players(id,name,sport)values(player,'TA-X1B Stable Player','soccer');
  insert into public.e10_teams(id,name,sport,league)values(old_team,'TA-X1B Former Club','soccer','league-a'),(new_team,'TA-X1B Current Club','soccer','league-a');
  insert into public.e10_catalog_releases(id,release_name,release_year,sport)values(release_id,'TA-X1B Historical Release',2021,'soccer');
  insert into public.e10_catalog_variants(id,release_id,card_number)values(variant,release_id,'21');
  insert into public.e10_catalog_variant_subjects(variant_id,player_id)values(variant,player);
end $$;

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"a7000000-0000-4000-8000-00000000e210","role":"authenticated"}',true);

do $$
declare player uuid:='a7000000-0000-4000-8000-00000000e213';old_team uuid:='a7000000-0000-4000-8000-00000000e214';new_team uuid:='a7000000-0000-4000-8000-00000000e215';variant uuid:='a7000000-0000-4000-8000-00000000e217';r jsonb;k uuid;
begin
  r:=public.e10_platform_review_player_affiliation(null,player,old_team,'soccer','league-a','2020-01-01','2022-01-01',0,'assert','official_source','official:test:former','Historical affiliation',jsonb_build_object('verified',true),'ta-x1b-aff-old');
  if r->>'replay'<>'false' then raise exception 'first affiliation write was replay';end if;
  r:=public.e10_platform_review_player_affiliation(null,player,old_team,'soccer','league-a','2020-01-01','2022-01-01',0,'assert','official_source','official:test:former','Historical affiliation',jsonb_build_object('verified',true),'ta-x1b-aff-old');
  if r->>'replay'<>'true' then raise exception 'exact affiliation replay was not stable';end if;
  perform public.e10_platform_review_player_affiliation(null,player,new_team,'soccer','league-a','2022-01-01',null,0,'assert','official_source','official:test:current','Current affiliation',jsonb_build_object('verified',true),'ta-x1b-aff-new');
  r:=public.e10_platform_review_variant_subject_context(null,variant,player,0,'assert','known',old_team,'documentary_source','card-image:test:21','Card depicts former club',jsonb_build_object('front_image_reviewed',true),'ta-x1b-context');
  if r->>'replay'<>'false' then raise exception 'first context write was replay';end if;
  k:=(r->>'decision_key')::uuid;
  begin
    perform public.e10_platform_review_variant_subject_context(k,variant,player,0,'assert','known',new_team,'documentary_source','card-image:test:21','Illicit relabel',jsonb_build_object('front_image_reviewed',true),'ta-x1b-context-mismatch');
    raise exception 'stale context revision accepted';
  exception when serialization_failure then null;end;
end $$;

select set_config('request.jwt.claims','{"sub":"a7000000-0000-4000-8000-00000000e211","role":"authenticated"}',true);
do $$
declare player uuid:='a7000000-0000-4000-8000-00000000e213';old_team uuid:='a7000000-0000-4000-8000-00000000e214';new_team uuid:='a7000000-0000-4000-8000-00000000e215';variant uuid:='a7000000-0000-4000-8000-00000000e217';r jsonb;bad text:='';ok integer:=0;
begin
  r:=public.e10_catalog_player_affiliations(player,'2021-01-01','2021-12-31',100);
  if jsonb_array_length(r->'rows')=1 and r#>>'{rows,0,team_id}'=old_team::text then ok:=ok+1;else bad:=bad||' historical_window';end if;
  r:=public.e10_catalog_player_affiliations(player,'2024-01-01','2025-01-01',100);
  if jsonb_array_length(r->'rows')=1 and r#>>'{rows,0,team_id}'=new_team::text then ok:=ok+1;else bad:=bad||' current_window';end if;
  r:=public.e10_catalog_variant_subject_context(variant,50);
  if jsonb_array_length(r->'rows')=1 and r#>>'{rows,0,depicted_team_id}'=old_team::text then ok:=ok+1;else bad:=bad||' historical_card_relabelled';end if;
  begin perform public.e10_catalog_player_affiliations(player,null,null,201);bad:=bad||' unbounded_limit';exception when invalid_parameter_value then ok:=ok+1;end;
  begin perform public.e10_platform_review_player_affiliation(null,player,new_team,'soccer','league-a','2025-01-01',null,0,'assert','manual_review','test','denied',jsonb_build_object(),'ta-x1b-denied');bad:=bad||' member_write';exception when insufficient_privilege then ok:=ok+1;end;
  begin perform 1 from public.e10_player_affiliation_decisions;bad:=bad||' direct_table_read';exception when insufficient_privilege then ok:=ok+1;end;
  if ok<>6 then raise exception 'TA-X1b member proofs failed %/6:%',ok,bad;end if;
end $$;

select set_config('request.jwt.claims','{"sub":"a7000000-0000-4000-8000-00000000e212","role":"authenticated"}',true);
do $$begin
  begin perform public.e10_catalog_player_affiliations('a7000000-0000-4000-8000-00000000e213',null,null,100);raise exception 'membership-less read allowed';exception when insufficient_privilege then null;end;
end $$;

reset role;
do $$
declare n integer;
begin
  select count(*)into n from information_schema.routine_privileges where specific_schema='public' and routine_name in('e10_platform_review_player_affiliation','e10_platform_review_variant_subject_context','e10_catalog_player_affiliations','e10_catalog_variant_subject_context')and grantee in('PUBLIC','anon');
  if n<>0 then raise exception 'TA-X1b born-locked ACL failure: %',n;end if;
  begin
    update public.e10_player_affiliation_decisions set reason='tamper';raise exception 'affiliation mutation accepted';
  exception when others then
    if sqlerrm not like '%is_append_only' then raise;end if;
  end;
  raise notice 'TA-X1b affiliations/context: PASS';
end $$;

rollback;
