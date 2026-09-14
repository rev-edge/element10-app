-- TA-R5 corrective: bounded X1 rows, copy-level attribute separation and
-- transaction-bound provider-mapping current-revision promotion.

create function e10.guard_x1_payload_bounds() returns trigger
language plpgsql security definer set search_path=public as $$
begin
  if tg_table_name='e10_product_masters' then
    if new.name is null or length(btrim(new.name))not between 1 and 200 or length(new.internal_code)>200 or octet_length(new.attrs::text)>65536 then raise exception using errcode='22023',message='product_master_payload_invalid';end if;
  elsif tg_table_name='e10_product_configurations' then
    if new.name is null or length(btrim(new.name))not between 1 and 200 or length(new.internal_code)>200 or octet_length(new.attrs::text)>65536 then raise exception using errcode='22023',message='product_configuration_payload_invalid';end if;
  elsif tg_table_name='e10_product_configuration_versions' then
    if new.state is null or new.state not in('draft','active','retired') or new.packaging_kind is null or length(btrim(new.packaging_kind))not between 1 and 100
      or new.base_unit is null or length(btrim(new.base_unit))not between 1 and 50 or new.base_units_per_package is null
      or new.base_units_per_package::text in('NaN','Infinity','-Infinity') or new.base_units_per_package<=0
      or length(new.barcode)>300 or octet_length(new.attrs::text)>65536 then raise exception using errcode='22023',message='configuration_version_payload_invalid';end if;
  elsif tg_table_name='e10_unique_items' then
    if new.item_kind is null or length(btrim(new.item_kind))not between 1 and 100 or length(new.condition)>100 or length(new.grading_company)>100
      or length(new.grade)>100 or length(new.certification_number)>300 or octet_length(new.observed_markings::text)>65536 or octet_length(new.attrs::text)>65536 then raise exception using errcode='22023',message='unique_item_payload_invalid';end if;
  elsif tg_table_name='e10_catalog_releases' then
    if new.release_name is null or length(btrim(new.release_name))not between 1 and 300 or length(new.manufacturer)>200 or length(new.brand_line)>200
      or length(new.season)>100 or length(new.sport)>100 or length(new.language)>50 or length(new.region)>100 or length(new.edition)>100
      or octet_length(new.attrs::text)>65536 then raise exception using errcode='22023',message='catalog_release_payload_invalid';end if;
  elsif tg_table_name='e10_catalog_variants' then
    if length(new.card_number)>200 or length(new.exact_parallel)>200 or length(new.color_family)>100 or length(new.finish_pattern)>100
      or length(new.language)>50 or length(new.edition)>100 or octet_length(new.attrs::text)>65536
      or new.attrs ?|array['serial_numerator','serial_number','certification_number','grading_company','grade','condition','observed_markings'] then raise exception using errcode='22023',message='catalog_variant_payload_invalid';end if;
  elsif tg_table_name='e10_catalog_identity_mappings' then
    if new.provider is null or length(btrim(new.provider))not between 1 and 100 or new.external_id is null or length(btrim(new.external_id))not between 1 and 300
      or octet_length(new.source_payload::text)>65536 then raise exception using errcode='22023',message='catalog_identity_mapping_payload_invalid';end if;
  end if;
  return new;
end $$;
create trigger e10_product_master_bounds_trg before insert or update on public.e10_product_masters for each row execute function e10.guard_x1_payload_bounds();
create trigger e10_product_configuration_bounds_trg before insert or update on public.e10_product_configurations for each row execute function e10.guard_x1_payload_bounds();
create trigger e10_configuration_version_bounds_trg before insert or update on public.e10_product_configuration_versions for each row execute function e10.guard_x1_payload_bounds();
create trigger e10_unique_item_bounds_trg before insert or update on public.e10_unique_items for each row execute function e10.guard_x1_payload_bounds();
create trigger e10_catalog_release_bounds_trg before insert or update on public.e10_catalog_releases for each row execute function e10.guard_x1_payload_bounds();
create trigger e10_catalog_variant_bounds_trg before insert or update on public.e10_catalog_variants for each row execute function e10.guard_x1_payload_bounds();
create trigger e10_catalog_mapping_bounds_trg before insert or update on public.e10_catalog_identity_mappings for each row execute function e10.guard_x1_payload_bounds();
revoke all on function e10.guard_x1_payload_bounds() from public,anon,authenticated;
grant execute on function e10.guard_x1_payload_bounds() to service_role;

create table e10.x1_mapping_promotion_authorizations(
  transaction_id bigint not null,backend_pid integer not null,old_mapping_id uuid not null,new_mapping_id uuid not null,
  primary key(transaction_id,backend_pid,old_mapping_id,new_mapping_id)
);
alter table e10.x1_mapping_promotion_authorizations enable row level security;
revoke all on e10.x1_mapping_promotion_authorizations from public,anon,authenticated,service_role;

create or replace function e10.guard_catalog_identity_mapping_history() returns trigger
language plpgsql security definer set search_path=public as $$
begin
  if tg_op='DELETE' then raise exception using errcode='55000',message='catalog_identity_mapping_history_immutable';end if;
  if row(new.id,new.provider,new.entity_kind,new.external_id,new.mapping_revision,new.player_id,new.release_id,new.variant_id,new.match_status,new.confidence,new.source_payload,new.reviewed_by,new.reviewed_at,new.created_at)
    is distinct from row(old.id,old.provider,old.entity_kind,old.external_id,old.mapping_revision,old.player_id,old.release_id,old.variant_id,old.match_status,old.confidence,old.source_payload,old.reviewed_by,old.reviewed_at,old.created_at) then
    raise exception using errcode='55000',message='catalog_identity_mapping_history_immutable';end if;
  if new.is_current is distinct from old.is_current and not exists(
    select 1 from e10.x1_mapping_promotion_authorizations a
    where a.transaction_id=txid_current()and a.backend_pid=pg_backend_pid()
      and((a.old_mapping_id=old.id and old.is_current and not new.is_current)
        or(a.new_mapping_id=old.id and not old.is_current and new.is_current))) then
    raise exception using errcode='55000',message='catalog_identity_mapping_current_transition_denied';end if;
  return new;
end $$;

create function e10.promote_catalog_identity_mapping(p_old uuid,p_new uuid) returns void
language plpgsql security definer set search_path=public as $$
begin
  insert into e10.x1_mapping_promotion_authorizations values(txid_current(),pg_backend_pid(),p_old,p_new);
  update public.e10_catalog_identity_mappings set is_current=false where id=p_old;
  if not found then raise exception using errcode='40001',message='catalog_identity_mapping_stale';end if;
  update public.e10_catalog_identity_mappings set is_current=true where id=p_new;
  if not found then raise exception using errcode='40001',message='catalog_identity_mapping_stale';end if;
  delete from e10.x1_mapping_promotion_authorizations where transaction_id=txid_current()and backend_pid=pg_backend_pid()and old_mapping_id=p_old and new_mapping_id=p_new;
end $$;
revoke all on function e10.promote_catalog_identity_mapping(uuid,uuid) from public,anon,authenticated,service_role;

create or replace function public.e10_platform_review_catalog_identity_mapping(
  p_provider text,p_entity_kind text,p_external_id text,p_player_id uuid,p_release_id uuid,p_variant_id uuid,
  p_match_status text,p_confidence numeric,p_source_payload jsonb,p_idempotency_key text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare actor uuid:=auth.uid();scope_id constant uuid:='00000000-0000-0000-0000-000000000000';
  k text:=btrim(p_idempotency_key);provider_key text:=btrim(p_provider);external_key text:=btrim(p_external_id);
  fp text;new_id uuid:=gen_random_uuid();result jsonb;prior record;next_revision integer;
begin
  if actor is null or not e10.is_platform_admin()then raise exception using errcode='42501',message='platform_catalog_write_denied';end if;
  if provider_key is null or length(provider_key)not between 1 and 100 or p_entity_kind not in('player','release','variant') or external_key is null or length(external_key)not between 1 and 300
    or p_match_status not in('verified','candidate','rejected','superseded') or p_confidence is not null and(p_confidence::text in('NaN','Infinity','-Infinity')or p_confidence<0 or p_confidence>1)
    or p_source_payload is null or jsonb_typeof(p_source_payload)<>'object' or octet_length(p_source_payload::text)>65536 or k is null or length(k)not between 1 and 200
    or(p_entity_kind='player')is distinct from(p_player_id is not null and p_release_id is null and p_variant_id is null)
    or(p_entity_kind='release')is distinct from(p_player_id is null and p_release_id is not null and p_variant_id is null)
    or(p_entity_kind='variant')is distinct from(p_player_id is null and p_release_id is null and p_variant_id is not null) then raise exception using errcode='22023',message='catalog_identity_mapping_payload_invalid';end if;
  fp:=md5(jsonb_build_array('catalog-identity-mapping-v1',provider_key,p_entity_kind,external_key,p_player_id,p_release_id,p_variant_id,p_match_status,p_confidence,p_source_payload)::text);
  perform pg_advisory_xact_lock(hashtextextended('platform|x1-mapping-command|'||k,0));result:=e10.x1_replay(scope_id,'catalog_identity_mapping.review',k,fp);
  if result is not null then if not e10.is_platform_admin()then raise exception using errcode='42501',message='platform_catalog_write_denied';end if;return result;end if;
  perform pg_advisory_xact_lock(hashtextextended('platform|x1-mapping|'||provider_key||'|'||p_entity_kind||'|'||external_key,0));
  select * into prior from public.e10_catalog_identity_mappings m where m.provider=provider_key and m.entity_kind=p_entity_kind and m.external_id=external_key and m.is_current for update;
  next_revision:=coalesce(prior.mapping_revision,0)+1;
  if p_player_id is not null then perform 1 from public.e10_players p where p.id=p_player_id for key share;
  elsif p_release_id is not null then perform 1 from public.e10_catalog_releases r where r.id=p_release_id for key share;
  else perform 1 from public.e10_catalog_variants v where v.id=p_variant_id for key share;end if;
  if not found then raise exception using errcode='22023',message='catalog_identity_mapping_target_invalid';end if;
  if not e10.is_platform_admin()then raise exception using errcode='42501',message='platform_catalog_write_denied';end if;
  insert into public.e10_catalog_identity_mappings(id,provider,entity_kind,external_id,mapping_revision,player_id,release_id,variant_id,match_status,is_current,confidence,source_payload,reviewed_by,reviewed_at)
    values(new_id,provider_key,p_entity_kind,external_key,next_revision,p_player_id,p_release_id,p_variant_id,p_match_status,prior.id is null,p_confidence,p_source_payload,case when p_match_status='verified'then actor end,case when p_match_status='verified'then clock_timestamp()end);
  if prior.id is not null then perform e10.promote_catalog_identity_mapping(prior.id,new_id);end if;
  result:=jsonb_build_object('ok',true,'replay',false,'mapping_id',new_id,'mapping_revision',next_revision,'supersedes_mapping_id',prior.id);
  insert into public.e10_x1_creation_commands values(scope_id,'catalog_identity_mapping.review',k,fp,result,actor,clock_timestamp());return result;
end $$;
