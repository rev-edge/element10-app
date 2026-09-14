\set ON_ERROR_STOP on
begin;
do $$
declare o uuid:=gen_random_uuid();release_id uuid:=gen_random_uuid();variant_id uuid:=gen_random_uuid();copy3 uuid:=gen_random_uuid();copy4 uuid:=gen_random_uuid();
begin
 insert into public.e10_organizations(id,slug,name)values(o,'r8-'||left(o::text,8),'R8');
 insert into public.e10_catalog_releases(id,release_name)values(release_id,'R8');
 insert into public.e10_catalog_variants(id,release_id,print_run_denominator)values(variant_id,release_id,50);
 insert into public.e10_unique_items(id,organization_id,catalog_variant_id,item_kind,serial_numerator)values(copy3,o,variant_id,'card',3),(copy4,o,variant_id,'card',4);
 if(select count(*)from public.e10_unique_items where organization_id=o and catalog_variant_id=variant_id)<>2
   or(select id from public.e10_unique_items where organization_id=o and catalog_variant_id=variant_id and serial_numerator=3)is distinct from copy3
   or(select id from public.e10_unique_items where organization_id=o and catalog_variant_id=variant_id and serial_numerator=4)is distinct from copy4 then raise exception'two physical copies did not remain distinct';end if;
 -- Storage-only truth taxonomy fixture. Supported ingestion and its no-side-effect
 -- contract are proved through public writers in ta_x5d_intake_commit_test.sql.
 set local session_replication_role=replica;
 insert into public.e10_market_observations(organization_id,observation_kind,catalog_variant_id,occurred_at,currency,amount,source_kind,raw_payload_snapshot)values
  (o,'asking_price',variant_id,now(),'USD',100,'manual','{}'),(o,'estimated_value',variant_id,now(),'USD',90,'manual','{}'),(o,'completed_sale',variant_id,now(),'USD',80,'manual','{}');
 set local session_replication_role=origin;
 if(select count(distinct observation_kind)from public.e10_market_observations where organization_id=o and catalog_variant_id=variant_id)<>3 then raise exception'ask/estimate/sale evidence collapsed';end if;
end $$;
rollback;
select 'TA-R8 focused evidence: PASS' result;
