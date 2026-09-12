\set ON_ERROR_STOP on
begin;
do $$
declare
  o uuid:='e1000000-0000-4000-8000-0000000000a6';
  product uuid:=gen_random_uuid();config uuid:=gen_random_uuid();version uuid:=gen_random_uuid();
  release_id uuid:=gen_random_uuid();mapping1 uuid:=gen_random_uuid();mapping2 uuid:=gen_random_uuid();
begin
  insert into public.e10_product_masters(id,organization_id,name)values(product,o,'R5 product');
  insert into public.e10_product_configurations(id,organization_id,product_master_id,name)values(config,o,product,'R5 config');
  insert into public.e10_product_configuration_versions(id,organization_id,configuration_id,version_no,state,packaging_kind,base_unit,base_units_per_package,attrs)
    values(version,o,config,1,'draft','box','each',1,'{"proof":"original"}');
  begin update public.e10_product_configuration_versions set attrs='{"proof":"changed"}' where id=version;
    raise exception 'configuration content update accepted';exception when sqlstate'55000'then null;end;
  begin delete from public.e10_product_configuration_versions where id=version;
    raise exception 'configuration history delete accepted';exception when sqlstate'55000'then null;end;
  update public.e10_product_configuration_versions set state='active' where id=version;
  begin update public.e10_product_configuration_versions set state='draft' where id=version;
    raise exception 'active configuration returned to draft';exception when sqlstate'55000'then null;end;
  update public.e10_product_configuration_versions set state='retired' where id=version;
  begin update public.e10_product_configuration_versions set state='active' where id=version;
    raise exception 'retired configuration reactivated';exception when sqlstate'55000'then null;end;
  if (select state from public.e10_product_configuration_versions where id=version)<>'retired' then raise exception 'valid configuration retirement lost';end if;

  insert into public.e10_catalog_releases(id,release_name)values(release_id,'R5 release');
  insert into public.e10_catalog_identity_mappings(id,provider,entity_kind,external_id,mapping_revision,release_id,match_status,is_current)
    values(mapping1,'r5-provider','release','r5-external',1,release_id,'candidate',true);
  begin update public.e10_catalog_identity_mappings set source_payload='{"changed":true}' where id=mapping1;
    raise exception 'mapping content update accepted';exception when sqlstate'55000'then null;end;
  begin delete from public.e10_catalog_identity_mappings where id=mapping1;
    raise exception 'mapping history delete accepted';exception when sqlstate'55000'then null;end;
  begin update public.e10_catalog_identity_mappings set is_current=false where id=mapping1;
    raise exception 'mapping retired without successor';exception when sqlstate'55000'then null;end;
  insert into public.e10_catalog_identity_mappings(id,provider,entity_kind,external_id,mapping_revision,release_id,match_status,is_current)
    values(mapping2,'r5-provider','release','r5-external',2,release_id,'candidate',false);
  update public.e10_catalog_identity_mappings set is_current=false where id=mapping1;
  update public.e10_catalog_identity_mappings set is_current=true where id=mapping2;
  if (select count(*) from public.e10_catalog_identity_mappings where provider='r5-provider'and external_id='r5-external'and is_current)<>1
    or not exists(select 1 from public.e10_catalog_identity_mappings where id=mapping1 and not is_current)
    or not exists(select 1 from public.e10_catalog_identity_mappings where id=mapping2 and is_current) then
    raise exception 'mapping successor promotion invalid';end if;
end $$;
rollback;
select 'TA-R5 immutable identity history: PASS' result;
