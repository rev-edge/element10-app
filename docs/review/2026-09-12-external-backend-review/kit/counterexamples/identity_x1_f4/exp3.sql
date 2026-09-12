\set ON_ERROR_STOP 0
begin;
insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at) values
 ('a7000000-0000-4000-8000-00000000f003','00000000-0000-0000-0000-000000000000','authenticated','authenticated','padmin@x.invalid',now(),now()) on conflict do nothing;
insert into public.e10_platform_admins(user_id) values ('a7000000-0000-4000-8000-00000000f003');
insert into public.e10_catalog_releases(id,release_name,release_year) values ('a7000000-0000-4000-8000-00000000f100','EXP Release',2026);
insert into public.e10_catalog_variants(id,release_id,card_number) values ('a7000000-0000-4000-8000-00000000f101','a7000000-0000-4000-8000-00000000f100','1');
insert into public.e10_product_masters(id,organization_id,name) values ('a7000000-0000-4000-8000-00000000f200','e1000000-0000-4000-8000-0000000000a6','EXP Product');
insert into public.e10_product_configurations(id,organization_id,product_master_id,name) values ('a7000000-0000-4000-8000-00000000f201','e1000000-0000-4000-8000-0000000000a6','a7000000-0000-4000-8000-00000000f200','Box');
insert into public.e10_product_configuration_versions(id,organization_id,configuration_id,version_no,state,packaging_kind,base_unit,base_units_per_package) values ('a7000000-0000-4000-8000-00000000f202','e1000000-0000-4000-8000-0000000000a6','a7000000-0000-4000-8000-00000000f201',1,'active','box','pack',24);
insert into public.e10_inventory_items(id,name,qty,organization_id,configuration_version_id) values ('__exp_item','EXP Item',1,'e1000000-0000-4000-8000-0000000000a6','a7000000-0000-4000-8000-00000000f202');
insert into public.e10_players(id,name) values ('a7000000-0000-4000-8000-00000000f401','Exp Same'),('a7000000-0000-4000-8000-00000000f402','Exp Same');
insert into public.e10_teams(id,name,sport,league) values ('a7000000-0000-4000-8000-00000000f500','Exp Team','basketball','nba');
\echo === E1: as service_role, mutate ACTIVE configuration version referenced by inventory item
set role service_role;
update public.e10_product_configuration_versions set base_units_per_package=1, packaging_kind='case', barcode='CHANGED', state='retired' where id='a7000000-0000-4000-8000-00000000f202' returning version_no,state,base_units_per_package,packaging_kind,barcode;
reset role;
\echo === E3: as service_role, mapping revision rows updatable/deletable
set role service_role;
insert into public.e10_catalog_identity_mappings(id,provider,entity_kind,external_id,mapping_revision,variant_id,match_status,is_current) values ('a7000000-0000-4000-8000-00000000f300','exp','variant','ext-1',1,'a7000000-0000-4000-8000-00000000f101','candidate',true);
savepoint a;
insert into public.e10_catalog_identity_mappings(provider,entity_kind,external_id,mapping_revision,variant_id,match_status,is_current) values ('exp','variant','ext-1',2,'a7000000-0000-4000-8000-00000000f101','rejected',true);
rollback to a;
update public.e10_catalog_identity_mappings set match_status='rejected', source_payload='{"rewritten":true}', mapping_revision=5 where id='a7000000-0000-4000-8000-00000000f300' returning mapping_revision, match_status, source_payload;
delete from public.e10_catalog_identity_mappings where id='a7000000-0000-4000-8000-00000000f300' returning id;
reset role;
\echo === E7: F4 non-uuid candidate id -> SQLSTATE
set role authenticated;
select set_config('request.jwt.claims','{"sub":"a7000000-0000-4000-8000-00000000f003","role":"authenticated"}',true);
savepoint b;
select public.e10_platform_propose_player_identity_review('manual:exp','k1','Exp Same','manual','op',null,'{}',jsonb_build_array(jsonb_build_object('player_id','not-a-uuid','confidence_status','unknown','confidence',null,'evidence','{}'::jsonb),jsonb_build_object('player_id','a7000000-0000-4000-8000-00000000f402','confidence_status','unknown','confidence',null,'evidence','{}'::jsonb)),'r','{}','exp-k1');
rollback to b;
\echo === E7b: confidence numeric-as-string for known
savepoint c;
select public.e10_platform_propose_player_identity_review('manual:exp','k2','Exp Same','manual','op',null,'{}',jsonb_build_array(jsonb_build_object('player_id','a7000000-0000-4000-8000-00000000f401','confidence_status','known','confidence','0.5','evidence','{}'::jsonb),jsonb_build_object('player_id','a7000000-0000-4000-8000-00000000f402','confidence_status','unknown','confidence',null,'evidence','{}'::jsonb)),'r','{}','exp-k2');
rollback to c;
\echo === E7c: reject unknown case
savepoint d;
select public.e10_platform_reject_player_identity_review('a7000000-0000-4000-8000-00000000ffff',1,'r','{}','exp-rej');
rollback to d;
\echo === E7d: propose with 2 same candidates? (dup) and valid propose then reject twice (reject a rejected)
select public.e10_platform_propose_player_identity_review('manual:exp','k3','Exp Same','manual','op',null,'{}',jsonb_build_array(jsonb_build_object('player_id','a7000000-0000-4000-8000-00000000f401','confidence_status','unknown','confidence',null,'evidence','{}'::jsonb),jsonb_build_object('player_id','a7000000-0000-4000-8000-00000000f402','confidence_status','unknown','confidence',null,'evidence','{}'::jsonb)),'r','{}','exp-k3') \gset r_
select public.e10_platform_reject_player_identity_review((:'r_e10_platform_propose_player_identity_review'::jsonb->>'case_id')::uuid,1,'r','{}','exp-rej-1')->>'revision';
savepoint e;
select public.e10_platform_reject_player_identity_review((:'r_e10_platform_propose_player_identity_review'::jsonb->>'case_id')::uuid,2,'r','{}','exp-rej-2');
rollback to e;
\echo === E7e: replay of proposal after rejection returns historical 'pending'
select public.e10_platform_propose_player_identity_review('manual:exp','k3','Exp Same','manual','op',null,'{}',jsonb_build_array(jsonb_build_object('player_id','a7000000-0000-4000-8000-00000000f401','confidence_status','unknown','confidence',null,'evidence','{}'::jsonb),jsonb_build_object('player_id','a7000000-0000-4000-8000-00000000f402','confidence_status','unknown','confidence',null,'evidence','{}'::jsonb)),'r','{}','exp-k3')->>'status';
\echo === E7f: same idempotency key reused across propose and reject namespaces (shared decisions table)
savepoint f;
select public.e10_platform_reject_player_identity_review((:'r_e10_platform_propose_player_identity_review'::jsonb->>'case_id')::uuid,2,'r','{}','exp-k3');
rollback to f;
\echo === E8: affiliation with sport mismatching the team
select public.e10_platform_review_player_affiliation(null,'a7000000-0000-4000-8000-00000000f401','a7000000-0000-4000-8000-00000000f500','soccer','league-x','2020-01-01',null,0,'assert','manual_review','ref','reason','{}','exp-aff-1')->>'ok';
\echo === E8b: revoke then null-key new chain for same identity
select public.e10_platform_review_player_affiliation((select decision_key from public.e10_player_affiliation_decisions where idempotency_key='exp-aff-1'),'a7000000-0000-4000-8000-00000000f401','a7000000-0000-4000-8000-00000000f500','soccer','league-x','2020-01-01',null,1,'revoke','manual_review','ref','reason','{}','exp-aff-2')->>'ok';
savepoint g;
select public.e10_platform_review_player_affiliation(null,'a7000000-0000-4000-8000-00000000f401','a7000000-0000-4000-8000-00000000f500','soccer','league-x','2020-01-01',null,0,'assert','manual_review','ref','reason','{}','exp-aff-3')->>'ok';
rollback to g;
\echo === E8c: continue chain with different sport/league
select public.e10_platform_review_player_affiliation((select decision_key from public.e10_player_affiliation_decisions where idempotency_key='exp-aff-1'),'a7000000-0000-4000-8000-00000000f401','a7000000-0000-4000-8000-00000000f500','hockey','nhl','2020-01-01',null,2,'assert','manual_review','ref','reason','{}','exp-aff-4')->>'ok';
\echo === E8d: overlapping affiliation same player/team different effective_from (allowed - separate chain)
select public.e10_platform_review_player_affiliation(null,'a7000000-0000-4000-8000-00000000f401','a7000000-0000-4000-8000-00000000f500','hockey','nhl','2020-06-01',null,0,'assert','manual_review','ref','reason','{}','exp-aff-5')->>'ok';
select jsonb_array_length(public.e10_catalog_player_affiliations('a7000000-0000-4000-8000-00000000f401','2021-01-01','2021-02-01',10)->'rows') as overlapping_rows_same_team;
\echo === E8e: subject-context for a (variant,player) pair that is not a subject -> FK error code?
savepoint h;
select public.e10_platform_review_variant_subject_context(null,'a7000000-0000-4000-8000-00000000f101','a7000000-0000-4000-8000-00000000f401',0,'assert','known','a7000000-0000-4000-8000-00000000f500','manual_review','ref','reason','{}','exp-ctx-1');
rollback to h;
reset role;
rollback;
