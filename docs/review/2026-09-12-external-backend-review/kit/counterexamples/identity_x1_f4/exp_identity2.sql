\set ON_ERROR_STOP 0
\pset format aligned
begin;
-- fixtures
insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at) values
 ('a7000000-0000-4000-8000-00000000f001','00000000-0000-0000-0000-000000000000','authenticated','authenticated','dual@x.invalid',now(),now()),
 ('a7000000-0000-4000-8000-00000000f002','00000000-0000-0000-0000-000000000000','authenticated','authenticated','single@x.invalid',now(),now()),
 ('a7000000-0000-4000-8000-00000000f003','00000000-0000-0000-0000-000000000000','authenticated','authenticated','padmin@x.invalid',now(),now()) on conflict do nothing;
insert into public.e10_organizations(id,name,slug) values ('e1000000-0000-4000-8000-00000000f0b0','EXP Org B','exp-org-b') on conflict do nothing;
insert into public.e10_organization_roles(id,organization_id,key,name) values ('e1000000-0000-4000-8000-00000000f0b1','e1000000-0000-4000-8000-00000000f0b0','member','Member');
insert into public.e10_organization_memberships(organization_id,user_id,role_id,status) values
 ('e1000000-0000-4000-8000-0000000000a6','a7000000-0000-4000-8000-00000000f001','e1000000-0000-4000-8000-000000000004','active'),
 ('e1000000-0000-4000-8000-00000000f0b0','a7000000-0000-4000-8000-00000000f001','e1000000-0000-4000-8000-00000000f0b1','active'),
 ('e1000000-0000-4000-8000-0000000000a6','a7000000-0000-4000-8000-00000000f002','e1000000-0000-4000-8000-000000000004','active');
insert into public.e10_platform_admins(user_id) values ('a7000000-0000-4000-8000-00000000f003');
insert into public.e10_catalog_releases(id,release_name,release_year) values ('a7000000-0000-4000-8000-00000000f100','EXP Release',2026);
insert into public.e10_catalog_variants(id,release_id,card_number) values ('a7000000-0000-4000-8000-00000000f101','a7000000-0000-4000-8000-00000000f100','1');
insert into public.e10_product_masters(id,organization_id,name) values ('a7000000-0000-4000-8000-00000000f200','e1000000-0000-4000-8000-0000000000a6','EXP Product');
savepoint sp;
insert into public.e10_product_configurations(id,organization_id,product_master_id,name) values ('a7000000-0000-4000-8000-00000000f201','e1000000-0000-4000-8000-0000000000a6','a7000000-0000-4000-8000-00000000f200','Box');
rollback to sp;
savepoint sp;
insert into public.e10_product_configuration_versions(id,organization_id,configuration_id,version_no,state,packaging_kind,base_unit,base_units_per_package) values ('a7000000-0000-4000-8000-00000000f202','e1000000-0000-4000-8000-0000000000a6','a7000000-0000-4000-8000-00000000f201',1,'active','box','pack',24);
rollback to sp;
savepoint sp;
insert into public.e10_inventory_items(id,name,qty,organization_id,configuration_version_id) values ('__exp_item','EXP Item',1,'e1000000-0000-4000-8000-0000000000a6','a7000000-0000-4000-8000-00000000f202');
rollback to sp;

\echo === E1: mutate an ACTIVE configuration version already referenced by an inventory item, as service_role (no immutability trigger expected)
set role service_role;
savepoint sp;
update public.e10_product_configuration_versions set base_units_per_package=1, packaging_kind='case', barcode='CHANGED' where id='a7000000-0000-4000-8000-00000000f202' returning id, version_no, state, base_units_per_package, packaging_kind, barcode;
rollback to sp;
savepoint sp;
delete from public.e10_product_configuration_versions where id='a7000000-0000-4000-8000-00000000f202';
rollback to sp;
reset role;
select 'E1 version still referenced by inventory item -> '||(select count(*) from public.e10_inventory_items where configuration_version_id='a7000000-0000-4000-8000-00000000f202') as e1;

\echo === E2: serial numerator stored on a VARIANT via attrs / print_run fields (no check keeps copy-level data off the variant)
set role service_role;
savepoint sp;
update public.e10_catalog_variants set attrs=jsonb_build_object('serial_numerator',7,'grade','PSA 10') where id='a7000000-0000-4000-8000-00000000f101' returning id, attrs;
rollback to sp;
reset role;

\echo === E3: provider mapping rows are NOT append-only for service_role (update/delete accepted; is_current flip requires update of prior row)
set role service_role;
savepoint sp;
insert into public.e10_catalog_identity_mappings(id,provider,entity_kind,external_id,mapping_revision,variant_id,match_status,is_current) values ('a7000000-0000-4000-8000-00000000f300','exp','variant','ext-1',1,'a7000000-0000-4000-8000-00000000f101','candidate',true);
rollback to sp;
-- append revision 2 while revision 1 is current -> blocked by partial unique index, so a revision can only be appended after mutating revision 1
savepoint sp;
insert into public.e10_catalog_identity_mappings(provider,entity_kind,external_id,mapping_revision,variant_id,match_status,is_current) values ('exp','variant','ext-1',2,'a7000000-0000-4000-8000-00000000f101','rejected',true);
rollback to sp;
savepoint sp;
update public.e10_catalog_identity_mappings set match_status='rejected', variant_id='a7000000-0000-4000-8000-00000000f101', source_payload='{"rewritten":true}' where id='a7000000-0000-4000-8000-00000000f300' returning id, mapping_revision, match_status, source_payload;
rollback to sp;
savepoint sp;
delete from public.e10_catalog_identity_mappings where id='a7000000-0000-4000-8000-00000000f300' returning id;
rollback to sp;
reset role;

\echo === E4: cross-org composite FK: configuration in org B referencing org A product master (expect FK violation)
savepoint sp;
insert into public.e10_product_configurations(organization_id,product_master_id,name) values ('e1000000-0000-4000-8000-00000000f0b0','a7000000-0000-4000-8000-00000000f200','Cross');
rollback to sp;
\echo === E4b: unique item in org B referencing org A configuration version (expect FK violation)
savepoint sp;
insert into public.e10_unique_items(organization_id,item_kind,product_master_id,configuration_version_id) values ('e1000000-0000-4000-8000-00000000f0b0','card','a7000000-0000-4000-8000-00000000f200','a7000000-0000-4000-8000-00000000f202');
rollback to sp;
\echo === E4c: unique item in org B linked to any platform variant (allowed by design; variant is platform-level)
savepoint sp;
insert into public.e10_unique_items(organization_id,item_kind,catalog_variant_id,serial_numerator) values ('e1000000-0000-4000-8000-00000000f0b0','card','a7000000-0000-4000-8000-00000000f101',3) returning organization_id, catalog_variant_id, serial_numerator;
rollback to sp;
\echo === E4d: two copies in one org with the same serial numerator on the same variant (no uniqueness on (variant, serial))
savepoint sp;
insert into public.e10_unique_items(organization_id,item_kind,catalog_variant_id,serial_numerator) values ('e1000000-0000-4000-8000-0000000000a6','card','a7000000-0000-4000-8000-00000000f101',3),('e1000000-0000-4000-8000-0000000000a6','card','a7000000-0000-4000-8000-00000000f101',3) returning id, serial_numerator;
rollback to sp;
\echo === E4e: unique item with a catalog_variant but item_kind non-card, and serial_numerator larger than print_run (no check)
savepoint sp;
update public.e10_catalog_variants set print_run_denominator=10 where id='a7000000-0000-4000-8000-00000000f101';
release sp;
savepoint sp;
insert into public.e10_unique_items(organization_id,item_kind,catalog_variant_id,serial_numerator) values ('e1000000-0000-4000-8000-0000000000a6','apparel','a7000000-0000-4000-8000-00000000f101',999) returning item_kind, serial_numerator;
rollback to sp;

\echo === E5: same-name players distinct (expect two rows)
savepoint sp;
insert into public.e10_players(id,name) values ('a7000000-0000-4000-8000-00000000f401','Exp Same'),('a7000000-0000-4000-8000-00000000f402','Exp Same') returning id,name_norm;
release sp;

\echo === E6: shared catalog RLS for a DUAL-membership user (current_org() is null) vs single-membership user
set role authenticated;
select set_config('request.jwt.claims','{"sub":"a7000000-0000-4000-8000-00000000f002","role":"authenticated"}',true);
savepoint sp;
select 'single-membership sees variants='||count(*) from public.e10_catalog_variants where id='a7000000-0000-4000-8000-00000000f101';
release sp;
select set_config('request.jwt.claims','{"sub":"a7000000-0000-4000-8000-00000000f001","role":"authenticated"}',true);
savepoint sp;
select 'dual-membership sees variants='||count(*)||' releases='||(select count(*) from public.e10_catalog_releases where id='a7000000-0000-4000-8000-00000000f100')||' players='||(select count(*) from public.e10_players where id='a7000000-0000-4000-8000-00000000f401')||' mappings='||(select count(*) from public.e10_catalog_identity_mappings) from public.e10_catalog_variants where id='a7000000-0000-4000-8000-00000000f101';
release sp;
savepoint sp;
select 'dual-membership own product masters (org A)='||count(*) from public.e10_product_masters where organization_id='e1000000-0000-4000-8000-0000000000a6';
release sp;
savepoint sp;
select 'dual-membership RPC affiliations ok? '||(public.e10_catalog_player_affiliations('a7000000-0000-4000-8000-00000000f401',null,null,10)->>'player_id');
release sp;
reset role;

\echo === E7: F4 candidate player_id that is not a uuid string -> which SQLSTATE?
set role authenticated;
select set_config('request.jwt.claims','{"sub":"a7000000-0000-4000-8000-00000000f003","role":"authenticated"}',true);
savepoint sp;
select public.e10_platform_propose_player_identity_review('manual:exp','k1','Exp Same','manual','op',null,'{}',jsonb_build_array(jsonb_build_object('player_id','not-a-uuid','confidence_status','unknown','confidence',null,'evidence','{}'::jsonb),jsonb_build_object('player_id','a7000000-0000-4000-8000-00000000f402','confidence_status','unknown','confidence',null,'evidence','{}'::jsonb)),'r','{}','exp-k1');
release sp;
\echo === E7b: F4 candidate with 'confidence' number for unknown  / confidence numeric but as string
savepoint sp;
select public.e10_platform_propose_player_identity_review('manual:exp','k2','Exp Same','manual','op',null,'{}',jsonb_build_array(jsonb_build_object('player_id','a7000000-0000-4000-8000-00000000f401','confidence_status','known','confidence','0.5','evidence','{}'::jsonb),jsonb_build_object('player_id','a7000000-0000-4000-8000-00000000f402','confidence_status','unknown','confidence',null,'evidence','{}'::jsonb)),'r','{}','exp-k2');
release sp;
\echo === E7c: F4 reject with a case id that does not exist and revision 1
savepoint sp;
select public.e10_platform_reject_player_identity_review('a7000000-0000-4000-8000-00000000ffff',1,'r','{}','exp-rej');
release sp;
\echo === E8: X1b affiliation where team sport differs from p_sport (no cross-check)
savepoint sp;
insert into public.e10_teams(id,name,sport,league) values ('a7000000-0000-4000-8000-00000000f500','Exp Team','basketball','nba');
release sp;
savepoint sp;
select public.e10_platform_review_player_affiliation(null,'a7000000-0000-4000-8000-00000000f401','a7000000-0000-4000-8000-00000000f500','soccer','league-x','2020-01-01',null,0,'assert','manual_review','ref','reason','{}','exp-aff-1')->>'ok';
release sp;
\echo === E8b: X1b revoke root chain then start a NEW chain (null key) for same player/team/from -> ?
savepoint sp;
select public.e10_platform_review_player_affiliation((select decision_key from public.e10_player_affiliation_decisions where idempotency_key='exp-aff-1'),'a7000000-0000-4000-8000-00000000f401','a7000000-0000-4000-8000-00000000f500','soccer','league-x','2020-01-01',null,1,'revoke','manual_review','ref','reason','{}','exp-aff-2')->>'ok';
release sp;
savepoint sp;
select public.e10_platform_review_player_affiliation(null,'a7000000-0000-4000-8000-00000000f401','a7000000-0000-4000-8000-00000000f500','soccer','league-x','2020-01-01',null,0,'assert','manual_review','ref','reason','{}','exp-aff-3')->>'ok';
release sp;
\echo === E8c: X1b assert with decision_key of a chain but different sport/league than prior (allowed? fields not in identity)
savepoint sp;
select public.e10_platform_review_player_affiliation((select decision_key from public.e10_player_affiliation_decisions where idempotency_key='exp-aff-1'),'a7000000-0000-4000-8000-00000000f401','a7000000-0000-4000-8000-00000000f500','hockey','nhl','2020-01-01',null,2,'assert','manual_review','ref','reason','{}','exp-aff-4')->>'ok';
release sp;
select decision_key,revision,action,sport,league from public.e10_player_affiliation_decisions where idempotency_key like 'exp-aff-%' order by revision;
reset role;
rollback;
