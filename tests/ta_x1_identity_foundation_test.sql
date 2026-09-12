-- TA-X1 identity foundation gate. Self-failing and transactionally rolled back.
begin;

do $$
declare
  org_a uuid := 'e1000000-0000-4000-8000-0000000000a6';
  org_b uuid := 'e1000000-0000-4000-8000-00000000e1b0';
  role_b uuid;
  user_a uuid := 'a7000000-0000-4000-8000-00000000e1a0';
  user_b uuid := 'a7000000-0000-4000-8000-00000000e1b0';
  no_org uuid := 'a7000000-0000-4000-8000-00000000e1c0';
  player_a uuid := 'a7000000-0000-4000-8000-00000000e101';
  player_b uuid := 'a7000000-0000-4000-8000-00000000e102';
  release_a uuid := 'a7000000-0000-4000-8000-00000000e103';
  variant_a uuid := 'a7000000-0000-4000-8000-00000000e104';
  release_b uuid := 'a7000000-0000-4000-8000-00000000e107';
  variant_b uuid := 'a7000000-0000-4000-8000-00000000e108';
  product_a uuid := 'a7000000-0000-4000-8000-00000000e105';
  config_a uuid := 'a7000000-0000-4000-8000-00000000e106';
begin
  insert into public.e10_organizations(id,name,slug)
    values (org_b,'TA-X1 Org B','ta-x1-org-b') on conflict do nothing;
  insert into public.e10_organization_roles(organization_id,key,name)
    values (org_b,'member','Member') returning id into role_b;
  insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at)
    select u,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',
           replace(u::text,'-','')||'@ta-x1.invalid',now(),now()
    from unnest(array[user_a,user_b,no_org]) u on conflict (id) do nothing;
  insert into public.e10_organization_memberships(organization_id,user_id,role_id,status)
    values
      (org_a,user_a,'e1000000-0000-4000-8000-000000000003','active'),
      (org_b,user_b,role_b,'active')
    on conflict (organization_id,user_id) do update set role_id=excluded.role_id,status='active';

  insert into public.e10_players(id,name) values
    (player_a,'TA-X1 Subject A'),(player_b,'TA-X1 Subject B');
  insert into public.e10_catalog_releases(id,release_name,release_year,season,sport,language,edition)
    values
      (release_a,'TA-X1 Release',2026,'2026','soccer','en','base'),
      (release_b,'TA-X1 Release',2026,'2026','soccer','es','international');
  insert into public.e10_catalog_variants(
    id,release_id,card_number,exact_parallel,color_family,rookie_designation,print_run_denominator
  ) values (variant_a,release_a,'10','Gold Refractor','gold',true,50);
  insert into public.e10_catalog_variants(
    id,release_id,card_number,exact_parallel,color_family,rookie_designation,print_run_denominator
  ) values (variant_b,release_b,'10','Gold Refractor','gold',true,50);
  insert into public.e10_catalog_variant_subjects(variant_id,player_id,position) values
    (variant_a,player_a,1),(variant_a,player_b,2);

  insert into public.e10_product_masters(id,organization_id,name,internal_code)
    values (product_a,org_a,'TA-X1 Product','TA-X1-P');
  insert into public.e10_product_configurations(id,organization_id,product_master_id,name,internal_code)
    values (config_a,org_a,product_a,'Hobby Box','TA-X1-C');
  insert into public.e10_product_configuration_versions(
    organization_id,configuration_id,version_no,state,packaging_kind,base_unit,base_units_per_package,barcode
  ) values (org_a,config_a,1,'active','box','card',24,'TA-X1-BC');
  insert into public.e10_product_configuration_versions(
    organization_id,configuration_id,version_no,state,packaging_kind,base_unit,base_units_per_package,barcode
  ) values (org_a,config_a,2,'draft','box','card',24,'TA-X1-BC');

  insert into public.e10_catalog_identity_mappings(
    provider,entity_kind,external_id,mapping_revision,variant_id,match_status,is_current
  ) values ('ta-x1','variant','external-1',1,variant_a,'candidate',false);
  insert into public.e10_catalog_identity_mappings(
    provider,entity_kind,external_id,mapping_revision,variant_id,match_status,is_current
  ) values ('ta-x1','variant','external-1',2,variant_a,'rejected',true);

  insert into public.e10_inventory_items(id,name,qty,organization_id)
    values ('__ta_x1_card','TA-X1 Card',1,org_a),('__ta_x1_noncard','TA-X1 Non-card',1,org_a);
  insert into public.e10_unique_items(
    organization_id,inventory_item_id,catalog_variant_id,item_kind,serial_numerator,condition
  ) values
    (org_a,'__ta_x1_card',variant_a,'card',3,'near_mint'),
    (org_a,'__ta_x1_noncard',null,'collectible',null,'new');
end $$;

set local role authenticated;
do $$
declare
  org_a uuid := 'e1000000-0000-4000-8000-0000000000a6';
  user_a uuid := 'a7000000-0000-4000-8000-00000000e1a0';
  user_b uuid := 'a7000000-0000-4000-8000-00000000e1b0';
  no_org uuid := 'a7000000-0000-4000-8000-00000000e1c0';
  variant_a uuid := 'a7000000-0000-4000-8000-00000000e104';
  c integer;
  ok integer := 0;
  bad text := '';
begin
  perform set_config('request.jwt.claims',json_build_object('sub',user_a::text,'role','authenticated')::text,true);
  select count(*) into c from public.e10_product_masters where organization_id=org_a;
  if c=1 then ok:=ok+1; else bad:=bad||' own_product='||c; end if;
  select count(*) into c from public.e10_unique_items where organization_id=org_a;
  if c=2 then ok:=ok+1; else bad:=bad||' own_items='||c; end if;
  select count(*) into c from public.e10_unique_items where organization_id=org_a and catalog_variant_id is null;
  if c=1 then ok:=ok+1; else bad:=bad||' cards_off='||c; end if;
  select count(*) into c from public.e10_catalog_variant_subjects where variant_id=variant_a;
  if c=2 then ok:=ok+1; else bad:=bad||' multi_subject='||c; end if;
  select count(*) into c from public.e10_catalog_variants
    where id=variant_a and print_run_denominator=50
      and not exists (select 1 from public.e10_catalog_variants v where v.id=variant_a and v.attrs ? 'serial_numerator');
  if c=1 then ok:=ok+1; else bad:=bad||' variant_copy_split='||c; end if;
  select count(*) into c from public.e10_unique_items
    where organization_id=org_a and catalog_variant_id=variant_a and serial_numerator=3;
  if c=1 then ok:=ok+1; else bad:=bad||' copy_serial='||c; end if;
  select count(*) into c from public.e10_product_configuration_versions
    where organization_id=org_a and configuration_id='a7000000-0000-4000-8000-00000000e106' and barcode='TA-X1-BC';
  if c=2 then ok:=ok+1; else bad:=bad||' version_barcode_history='||c; end if;
  select count(*) into c from public.e10_catalog_identity_mappings
    where provider='ta-x1' and entity_kind='variant' and external_id='external-1';
  if c=2 then ok:=ok+1; else bad:=bad||' mapping_history='||c; end if;
  select count(*) into c from public.e10_catalog_variants v
    join public.e10_catalog_releases r on r.id=v.release_id
    where v.card_number='10' and v.exact_parallel='Gold Refractor'
      and r.release_name='TA-X1 Release'
      and (r.language,r.edition) in (('en','base'),('es','international'));
  if c=2 then ok:=ok+1; else bad:=bad||' language_edition_identity='||c; end if;

  perform set_config('request.jwt.claims',json_build_object('sub',user_b::text,'role','authenticated')::text,true);
  select count(*) into c from public.e10_product_masters where organization_id=org_a;
  if c=0 then ok:=ok+1; else bad:=bad||' cross_org_product='||c; end if;
  select count(*) into c from public.e10_unique_items where organization_id=org_a;
  if c=0 then ok:=ok+1; else bad:=bad||' cross_org_item='||c; end if;
  select count(*) into c from public.e10_catalog_variants where id=variant_a;
  if c=1 then ok:=ok+1; else bad:=bad||' member_catalog='||c; end if;

  perform set_config('request.jwt.claims',json_build_object('sub',no_org::text,'role','authenticated')::text,true);
  select count(*) into c from public.e10_catalog_variants where id=variant_a;
  if c=0 then ok:=ok+1; else bad:=bad||' no_org_catalog='||c; end if;

  begin
    insert into public.e10_product_masters(organization_id,name) values (org_a,'forbidden');
    bad:=bad||' authenticated_write_allowed';
  exception when insufficient_privilege then ok:=ok+1;
  when others then bad:=bad||' authenticated_write_wrong='||sqlstate; end;

  if ok=14 then
    raise notice 'TA-X1 identity foundation: PASS (14/14)';
  else
    raise exception 'TA-X1 identity foundation: FAIL passed=%/14 failures=[%]',ok,bad;
  end if;
end $$;
reset role;

do $$
begin
  begin
    insert into public.e10_catalog_identity_mappings(
      provider,entity_kind,external_id,variant_id,match_status
    ) values ('ta-x1','variant','bad-target','a7000000-0000-4000-8000-00000000efff','candidate');
    raise exception 'TA-X1 invalid provider target was accepted';
  exception when foreign_key_violation then
    raise notice 'TA-X1 provider target FK: PASS';
  end;
end $$;

delete from public.e10_inventory_items where id='__ta_x1_card';
do $$
declare c integer;
begin
  select count(*) into c from public.e10_unique_items
    where organization_id='e1000000-0000-4000-8000-0000000000a6'
      and item_kind='card' and inventory_item_id is null;
  if c<>1 then raise exception 'TA-X1 inventory unlink failed: expected 1, got %',c; end if;
  raise notice 'TA-X1 inventory unlink: PASS (physical identity survives inventory deletion)';
end $$;

rollback;
