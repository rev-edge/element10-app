\set ON_ERROR_STOP 0
begin;
insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at) values
 ('a7000000-0000-4000-8000-00000000f003','00000000-0000-0000-0000-000000000000','authenticated','authenticated','padmin@x.invalid',now(),now()) on conflict do nothing;
insert into public.e10_platform_admins(user_id) values ('a7000000-0000-4000-8000-00000000f003');
insert into public.e10_catalog_releases(id,release_name,release_year) values ('a7000000-0000-4000-8000-00000000f100','EXP Release',2026);
insert into public.e10_catalog_variants(id,release_id,card_number) values ('a7000000-0000-4000-8000-00000000f101','a7000000-0000-4000-8000-00000000f100','1');
insert into public.e10_players(id,name) values ('a7000000-0000-4000-8000-00000000f401','Exp Same'),('a7000000-0000-4000-8000-00000000f402','Exp Same');
insert into public.e10_teams(id,name,sport,league) values ('a7000000-0000-4000-8000-00000000f500','Exp Team','basketball','nba');
set role authenticated;
select set_config('request.jwt.claims','{"sub":"a7000000-0000-4000-8000-00000000f003","role":"authenticated"}',true);
\echo === E8: affiliation with sport mismatching the team (basketball team, soccer affiliation)
select public.e10_platform_review_player_affiliation(null,'a7000000-0000-4000-8000-00000000f401','a7000000-0000-4000-8000-00000000f500','soccer','league-x','2020-01-01',null,0,'assert','manual_review','ref','reason','{}','exp-aff-1')->>'decision_key' as k \gset
\echo === E8b: revoke then null-key new chain for same identity
select public.e10_platform_review_player_affiliation(:'k','a7000000-0000-4000-8000-00000000f401','a7000000-0000-4000-8000-00000000f500','soccer','league-x','2020-01-01',null,1,'revoke','manual_review','ref','reason','{}','exp-aff-2')->>'revision';
savepoint g;
select public.e10_platform_review_player_affiliation(null,'a7000000-0000-4000-8000-00000000f401','a7000000-0000-4000-8000-00000000f500','soccer','league-x','2020-01-01',null,0,'assert','manual_review','ref','reason','{}','exp-aff-3')->>'ok';
rollback to g;
\echo === E8c: continue chain with different sport/league than the chain root
select public.e10_platform_review_player_affiliation(:'k','a7000000-0000-4000-8000-00000000f401','a7000000-0000-4000-8000-00000000f500','hockey','nhl','2020-01-01',null,2,'assert','manual_review','ref','reason','{}','exp-aff-4')->>'revision';
\echo === E8d: second chain same player/team, different effective_from, overlapping
select public.e10_platform_review_player_affiliation(null,'a7000000-0000-4000-8000-00000000f401','a7000000-0000-4000-8000-00000000f500','hockey','nhl','2020-06-01',null,0,'assert','manual_review','ref','reason','{}','exp-aff-5')->>'revision';
select jsonb_array_length(public.e10_catalog_player_affiliations('a7000000-0000-4000-8000-00000000f401','2021-01-01','2021-02-01',10)->'rows') as overlapping_rows_same_team;
\echo === E8e: subject-context for non-subject pair
savepoint h;
select public.e10_platform_review_variant_subject_context(null,'a7000000-0000-4000-8000-00000000f101','a7000000-0000-4000-8000-00000000f401',0,'assert','known','a7000000-0000-4000-8000-00000000f500','manual_review','ref','reason','{}','exp-ctx-1');
rollback to h;
\echo === E8f: affiliations reader with limit and no window, default args
select jsonb_array_length(public.e10_catalog_player_affiliations('a7000000-0000-4000-8000-00000000f401')->'rows');
reset role;
select decision_key,revision,action,sport,league,effective_from from public.e10_player_affiliation_decisions where idempotency_key like 'exp-aff-%' order by effective_from,revision;
rollback;
