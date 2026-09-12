-- TA-R5: bounded, permission-scoped, idempotent tenant X1 creation paths.

create table public.e10_x1_creation_commands(
  authority_scope uuid not null,
  operation text not null,
  idempotency_key text not null,
  request_fingerprint text not null,
  result jsonb not null,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default clock_timestamp(),
  primary key(authority_scope,operation,idempotency_key)
);
alter table public.e10_x1_creation_commands enable row level security;
revoke all on public.e10_x1_creation_commands from public,anon,authenticated;
grant all on public.e10_x1_creation_commands to service_role;
create function e10.guard_x1_creation_command() returns trigger language plpgsql
security definer set search_path=public as $$begin
  raise exception using errcode='55000',message='x1_creation_command_immutable';
end $$;
revoke all on function e10.guard_x1_creation_command() from public,anon,authenticated;
grant execute on function e10.guard_x1_creation_command() to service_role;
create trigger e10_x1_creation_commands_append_only_trg before update or delete
on public.e10_x1_creation_commands for each row execute function e10.guard_x1_creation_command();

create function e10.x1_replay(p_scope uuid,p_operation text,p_key text,p_fingerprint text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare c record;
begin
  select request_fingerprint,result into c from public.e10_x1_creation_commands
  where authority_scope=p_scope and operation=p_operation and idempotency_key=p_key;
  if not found then return null;end if;
  if c.request_fingerprint<>p_fingerprint then raise exception using errcode='22023',message='idempotency_key_mismatch';end if;
  return c.result||jsonb_build_object('replay',true);
end $$;
revoke all on function e10.x1_replay(uuid,text,text,text) from public,anon,authenticated;
grant execute on function e10.x1_replay(uuid,text,text,text) to service_role;

create function public.e10_org_create_product_master(p_org uuid,p_name text,p_internal_code text,p_attrs jsonb,p_idempotency_key text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare actor uuid:=auth.uid();k text:=btrim(p_idempotency_key);fp text;id uuid:=gen_random_uuid();r jsonb;
begin
  if actor is null or not e10.has_org_cap(p_org,'catalog.propose')then raise exception using errcode='42501',message='catalog_propose_denied';end if;
  if p_name is null or length(btrim(p_name))not between 1 and 200 or k is null or length(k)not between 1 and 200
    or p_attrs is null or jsonb_typeof(p_attrs)<>'object' then raise exception using errcode='22023',message='product_master_payload_invalid';end if;
  fp:=md5(jsonb_build_array('product-master-v1',p_org,btrim(p_name),nullif(btrim(p_internal_code),''),p_attrs)::text);
  perform pg_advisory_xact_lock(hashtextextended(p_org||'|x1-product-master|'||k,0));r:=e10.x1_replay(p_org,'product_master.create',k,fp);
  if r is not null then if not e10.has_org_cap(p_org,'catalog.propose')then raise exception using errcode='42501',message='catalog_propose_denied';end if;return r;end if;
  if not e10.has_org_cap(p_org,'catalog.propose')then raise exception using errcode='42501',message='catalog_propose_denied';end if;
  insert into public.e10_product_masters(id,organization_id,name,internal_code,attrs,created_by)values(id,p_org,btrim(p_name),nullif(btrim(p_internal_code),''),p_attrs,actor);
  r:=jsonb_build_object('ok',true,'replay',false,'product_master_id',id);
  insert into public.e10_x1_creation_commands values(p_org,'product_master.create',k,fp,r,actor,clock_timestamp());return r;
end $$;

create function public.e10_org_create_product_configuration(p_org uuid,p_product_master_id uuid,p_name text,p_internal_code text,p_attrs jsonb,p_idempotency_key text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare actor uuid:=auth.uid();k text:=btrim(p_idempotency_key);fp text;id uuid:=gen_random_uuid();r jsonb;
begin
  if actor is null or not e10.has_org_cap(p_org,'catalog.propose')then raise exception using errcode='42501',message='catalog_propose_denied';end if;
  if p_product_master_id is null or p_name is null or length(btrim(p_name))not between 1 and 200 or k is null or length(k)not between 1 and 200
    or p_attrs is null or jsonb_typeof(p_attrs)<>'object' then raise exception using errcode='22023',message='product_configuration_payload_invalid';end if;
  fp:=md5(jsonb_build_array('product-configuration-v1',p_org,p_product_master_id,btrim(p_name),nullif(btrim(p_internal_code),''),p_attrs)::text);
  perform pg_advisory_xact_lock(hashtextextended(p_org||'|x1-product-configuration|'||k,0));r:=e10.x1_replay(p_org,'product_configuration.create',k,fp);
  if r is not null then if not e10.has_org_cap(p_org,'catalog.propose')then raise exception using errcode='42501',message='catalog_propose_denied';end if;return r;end if;
  perform 1 from public.e10_product_masters pm where pm.organization_id=p_org and pm.id=p_product_master_id for key share;
  if not found then raise exception using errcode='42501',message='product_master_access_denied';end if;
  if not e10.has_org_cap(p_org,'catalog.propose')then raise exception using errcode='42501',message='catalog_propose_denied';end if;
  insert into public.e10_product_configurations(id,organization_id,product_master_id,name,internal_code,attrs,created_by)values(id,p_org,p_product_master_id,btrim(p_name),nullif(btrim(p_internal_code),''),p_attrs,actor);
  r:=jsonb_build_object('ok',true,'replay',false,'configuration_id',id);
  insert into public.e10_x1_creation_commands values(p_org,'product_configuration.create',k,fp,r,actor,clock_timestamp());return r;
end $$;

create function public.e10_org_create_configuration_version(p_org uuid,p_configuration_id uuid,p_expected_latest_version integer,p_state text,p_packaging_kind text,p_base_unit text,p_base_units_per_package numeric,p_barcode text,p_attrs jsonb,p_idempotency_key text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare actor uuid:=auth.uid();k text:=btrim(p_idempotency_key);fp text;id uuid:=gen_random_uuid();r jsonb;latest integer;
begin
  if actor is null or not e10.has_org_cap(p_org,'catalog.propose')then raise exception using errcode='42501',message='catalog_propose_denied';end if;
  if p_configuration_id is null or p_expected_latest_version is null or p_expected_latest_version<0 or p_state not in('draft','active')
    or p_packaging_kind is null or length(btrim(p_packaging_kind))not between 1 and 100 or p_base_unit is null or length(btrim(p_base_unit))not between 1 and 50
    or p_base_units_per_package is null or p_base_units_per_package<=0 or p_attrs is null or jsonb_typeof(p_attrs)<>'object'
    or k is null or length(k)not between 1 and 200 then raise exception using errcode='22023',message='configuration_version_payload_invalid';end if;
  fp:=md5(jsonb_build_array('configuration-version-v1',p_org,p_configuration_id,p_expected_latest_version,p_state,btrim(p_packaging_kind),btrim(p_base_unit),p_base_units_per_package,nullif(btrim(p_barcode),''),p_attrs)::text);
  perform pg_advisory_xact_lock(hashtextextended(p_org||'|x1-configuration-version|'||k,0));r:=e10.x1_replay(p_org,'configuration_version.create',k,fp);
  if r is not null then if not e10.has_org_cap(p_org,'catalog.propose')then raise exception using errcode='42501',message='catalog_propose_denied';end if;return r;end if;
  perform 1 from public.e10_product_configurations pc where pc.organization_id=p_org and pc.id=p_configuration_id for update;
  if not found then raise exception using errcode='42501',message='product_configuration_access_denied';end if;
  select coalesce(max(version_no),0)into latest from public.e10_product_configuration_versions where organization_id=p_org and configuration_id=p_configuration_id;
  if latest<>p_expected_latest_version then raise exception using errcode='40001',message='configuration_version_stale';end if;
  if not e10.has_org_cap(p_org,'catalog.propose')then raise exception using errcode='42501',message='catalog_propose_denied';end if;
  insert into public.e10_product_configuration_versions(id,organization_id,configuration_id,version_no,state,packaging_kind,base_unit,base_units_per_package,barcode,attrs,created_by)
    values(id,p_org,p_configuration_id,latest+1,p_state,btrim(p_packaging_kind),btrim(p_base_unit),p_base_units_per_package,nullif(btrim(p_barcode),''),p_attrs,actor);
  r:=jsonb_build_object('ok',true,'replay',false,'configuration_version_id',id,'version_no',latest+1);
  insert into public.e10_x1_creation_commands values(p_org,'configuration_version.create',k,fp,r,actor,clock_timestamp());return r;
end $$;

create function public.e10_org_create_unique_item(p_org uuid,p_inventory_item_id text,p_catalog_variant_id uuid,p_item_kind text,p_condition text,p_grading_company text,p_grade text,p_certification_number text,p_serial_numerator integer,p_observed_markings jsonb,p_attrs jsonb,p_idempotency_key text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare actor uuid:=auth.uid();k text:=btrim(p_idempotency_key);fp text;id uuid:=gen_random_uuid();r jsonb;
begin
  if actor is null or not e10.has_org_cap(p_org,'catalog.propose')then raise exception using errcode='42501',message='catalog_propose_denied';end if;
  if p_item_kind is null or length(btrim(p_item_kind))not between 1 and 100 or p_serial_numerator is not null and p_serial_numerator<=0
    or p_observed_markings is null or jsonb_typeof(p_observed_markings)<>'object' or p_attrs is null or jsonb_typeof(p_attrs)<>'object'
    or k is null or length(k)not between 1 and 200 then raise exception using errcode='22023',message='unique_item_payload_invalid';end if;
  fp:=md5(jsonb_build_array('unique-item-v1',p_org,p_inventory_item_id,p_catalog_variant_id,btrim(p_item_kind),p_condition,p_grading_company,p_grade,p_certification_number,p_serial_numerator,p_observed_markings,p_attrs)::text);
  perform pg_advisory_xact_lock(hashtextextended(p_org||'|x1-unique-item|'||k,0));r:=e10.x1_replay(p_org,'unique_item.create',k,fp);
  if r is not null then if not e10.has_org_cap(p_org,'catalog.propose')then raise exception using errcode='42501',message='catalog_propose_denied';end if;return r;end if;
  if p_inventory_item_id is not null then perform 1 from public.e10_inventory_items ii where ii.organization_id=p_org and ii.id=p_inventory_item_id for key share;if not found then raise exception using errcode='42501',message='inventory_item_access_denied';end if;end if;
  if p_catalog_variant_id is not null and not exists(select 1 from public.e10_catalog_variants cv where cv.id=p_catalog_variant_id)then raise exception using errcode='22023',message='catalog_variant_invalid';end if;
  if not e10.has_org_cap(p_org,'catalog.propose')then raise exception using errcode='42501',message='catalog_propose_denied';end if;
  insert into public.e10_unique_items(id,organization_id,inventory_item_id,catalog_variant_id,item_kind,condition,grading_company,grade,certification_number,serial_numerator,observed_markings,attrs,created_by)
    values(id,p_org,p_inventory_item_id,p_catalog_variant_id,btrim(p_item_kind),p_condition,p_grading_company,p_grade,p_certification_number,p_serial_numerator,p_observed_markings,p_attrs,actor);
  r:=jsonb_build_object('ok',true,'replay',false,'unique_item_id',id);
  insert into public.e10_x1_creation_commands values(p_org,'unique_item.create',k,fp,r,actor,clock_timestamp());return r;
end $$;

revoke all on function public.e10_org_create_product_master(uuid,text,text,jsonb,text),public.e10_org_create_product_configuration(uuid,uuid,text,text,jsonb,text),public.e10_org_create_configuration_version(uuid,uuid,integer,text,text,text,numeric,text,jsonb,text),public.e10_org_create_unique_item(uuid,text,uuid,text,text,text,text,text,integer,jsonb,jsonb,text) from public,anon;
grant execute on function public.e10_org_create_product_master(uuid,text,text,jsonb,text),public.e10_org_create_product_configuration(uuid,uuid,text,text,jsonb,text),public.e10_org_create_configuration_version(uuid,uuid,integer,text,text,text,numeric,text,jsonb,text),public.e10_org_create_unique_item(uuid,text,uuid,text,text,text,text,text,integer,jsonb,jsonb,text) to authenticated,service_role;
