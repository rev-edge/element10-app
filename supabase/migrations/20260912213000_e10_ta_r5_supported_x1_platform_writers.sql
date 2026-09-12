-- TA-R5: bounded, idempotent platform-curated X1 creation and revision paths.

create function public.e10_platform_create_catalog_release(
  p_manufacturer text,p_brand_line text,p_release_name text,p_release_year integer,
  p_season text,p_sport text,p_language text,p_region text,p_edition text,p_attrs jsonb,p_idempotency_key text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare actor uuid:=auth.uid();scope_id constant uuid:='00000000-0000-0000-0000-000000000000';
  k text:=btrim(p_idempotency_key);fp text;new_id uuid:=gen_random_uuid();result jsonb;
begin
  if actor is null or not e10.is_platform_admin()then raise exception using errcode='42501',message='platform_catalog_write_denied';end if;
  if p_release_name is null or length(btrim(p_release_name))not between 1 and 300
    or p_release_year is not null and p_release_year not between 1800 and 2200
    or p_attrs is null or jsonb_typeof(p_attrs)<>'object' or k is null or length(k)not between 1 and 200 then
    raise exception using errcode='22023',message='catalog_release_payload_invalid';end if;
  fp:=md5(jsonb_build_array('catalog-release-v1',p_manufacturer,p_brand_line,btrim(p_release_name),p_release_year,p_season,p_sport,p_language,p_region,p_edition,p_attrs)::text);
  perform pg_advisory_xact_lock(hashtextextended('platform|x1-catalog-release|'||k,0));
  result:=e10.x1_replay(scope_id,'catalog_release.create',k,fp);
  if result is not null then if not e10.is_platform_admin()then raise exception using errcode='42501',message='platform_catalog_write_denied';end if;return result;end if;
  if not e10.is_platform_admin()then raise exception using errcode='42501',message='platform_catalog_write_denied';end if;
  insert into public.e10_catalog_releases(id,manufacturer,brand_line,release_name,release_year,season,sport,language,region,edition,attrs)
    values(new_id,nullif(btrim(p_manufacturer),''),nullif(btrim(p_brand_line),''),btrim(p_release_name),p_release_year,nullif(btrim(p_season),''),nullif(btrim(p_sport),''),nullif(btrim(p_language),''),nullif(btrim(p_region),''),nullif(btrim(p_edition),''),p_attrs);
  result:=jsonb_build_object('ok',true,'replay',false,'catalog_release_id',new_id);
  insert into public.e10_x1_creation_commands values(scope_id,'catalog_release.create',k,fp,result,actor,clock_timestamp());return result;
end $$;

create function public.e10_platform_create_catalog_variant(
  p_release_id uuid,p_card_number text,p_exact_parallel text,p_color_family text,p_finish_pattern text,
  p_language text,p_edition text,p_rookie_designation boolean,p_print_run_denominator integer,
  p_attrs jsonb,p_subjects jsonb,p_idempotency_key text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare actor uuid:=auth.uid();scope_id constant uuid:='00000000-0000-0000-0000-000000000000';
  k text:=btrim(p_idempotency_key);fp text;new_id uuid:=gen_random_uuid();result jsonb;s jsonb;subject_ids uuid[]:='{}';pos integer;subject_id uuid;
begin
  if actor is null or not e10.is_platform_admin()then raise exception using errcode='42501',message='platform_catalog_write_denied';end if;
  if p_release_id is null or p_print_run_denominator is not null and p_print_run_denominator<=0
    or p_attrs is null or jsonb_typeof(p_attrs)<>'object' or p_subjects is null or jsonb_typeof(p_subjects)<>'array'
    or jsonb_array_length(p_subjects)>50 or k is null or length(k)not between 1 and 200 then
    raise exception using errcode='22023',message='catalog_variant_payload_invalid';end if;
  fp:=md5(jsonb_build_array('catalog-variant-v1',p_release_id,p_card_number,p_exact_parallel,p_color_family,p_finish_pattern,p_language,p_edition,p_rookie_designation,p_print_run_denominator,p_attrs,p_subjects)::text);
  perform pg_advisory_xact_lock(hashtextextended('platform|x1-catalog-variant|'||k,0));
  result:=e10.x1_replay(scope_id,'catalog_variant.create',k,fp);
  if result is not null then if not e10.is_platform_admin()then raise exception using errcode='42501',message='platform_catalog_write_denied';end if;return result;end if;
  perform 1 from public.e10_catalog_releases cr where cr.id=p_release_id for key share;
  if not found then raise exception using errcode='22023',message='catalog_release_invalid';end if;
  for s in select value from jsonb_array_elements(p_subjects)loop
    begin subject_id:=(s->>'player_id')::uuid;pos:=(s->>'position')::integer;exception when others then raise exception using errcode='22023',message='catalog_variant_subject_invalid';end;
    if subject_id is null or pos is null or pos<=0 or length(coalesce(s->>'subject_role','featured'))not between 1 and 100
      or subject_id=any(subject_ids) then raise exception using errcode='22023',message='catalog_variant_subject_invalid';end if;
    subject_ids:=array_append(subject_ids,subject_id);
    if not exists(select 1 from public.e10_players p where p.id=subject_id)then raise exception using errcode='22023',message='catalog_variant_subject_invalid';end if;
  end loop;
  if not e10.is_platform_admin()then raise exception using errcode='42501',message='platform_catalog_write_denied';end if;
  insert into public.e10_catalog_variants(id,release_id,card_number,exact_parallel,color_family,finish_pattern,language,edition,rookie_designation,print_run_denominator,attrs)
    values(new_id,p_release_id,nullif(btrim(p_card_number),''),nullif(btrim(p_exact_parallel),''),nullif(btrim(p_color_family),''),nullif(btrim(p_finish_pattern),''),nullif(btrim(p_language),''),nullif(btrim(p_edition),''),p_rookie_designation,p_print_run_denominator,p_attrs);
  insert into public.e10_catalog_variant_subjects(variant_id,player_id,subject_role,position)
    select new_id,(value->>'player_id')::uuid,coalesce(nullif(btrim(value->>'subject_role'),''),'featured'),(value->>'position')::integer from jsonb_array_elements(p_subjects);
  result:=jsonb_build_object('ok',true,'replay',false,'catalog_variant_id',new_id,'subject_count',jsonb_array_length(p_subjects));
  insert into public.e10_x1_creation_commands values(scope_id,'catalog_variant.create',k,fp,result,actor,clock_timestamp());return result;
end $$;

create function public.e10_platform_review_catalog_identity_mapping(
  p_provider text,p_entity_kind text,p_external_id text,p_player_id uuid,p_release_id uuid,p_variant_id uuid,
  p_match_status text,p_confidence numeric,p_source_payload jsonb,p_idempotency_key text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare actor uuid:=auth.uid();scope_id constant uuid:='00000000-0000-0000-0000-000000000000';
  k text:=btrim(p_idempotency_key);provider_key text:=btrim(p_provider);external_key text:=btrim(p_external_id);
  fp text;new_id uuid:=gen_random_uuid();result jsonb;prior record;next_revision integer;
begin
  if actor is null or not e10.is_platform_admin()then raise exception using errcode='42501',message='platform_catalog_write_denied';end if;
  if length(provider_key)not between 1 and 100 or p_entity_kind not in('player','release','variant') or length(external_key)not between 1 and 300
    or p_match_status not in('verified','candidate','rejected','superseded') or p_confidence is not null and (p_confidence<0 or p_confidence>1)
    or p_source_payload is null or jsonb_typeof(p_source_payload)<>'object' or k is null or length(k)not between 1 and 200
    or (p_entity_kind='player')is distinct from(p_player_id is not null and p_release_id is null and p_variant_id is null)
    or (p_entity_kind='release')is distinct from(p_player_id is null and p_release_id is not null and p_variant_id is null)
    or (p_entity_kind='variant')is distinct from(p_player_id is null and p_release_id is null and p_variant_id is not null) then
    raise exception using errcode='22023',message='catalog_identity_mapping_payload_invalid';end if;
  fp:=md5(jsonb_build_array('catalog-identity-mapping-v1',provider_key,p_entity_kind,external_key,p_player_id,p_release_id,p_variant_id,p_match_status,p_confidence,p_source_payload)::text);
  perform pg_advisory_xact_lock(hashtextextended('platform|x1-mapping-command|'||k,0));
  result:=e10.x1_replay(scope_id,'catalog_identity_mapping.review',k,fp);
  if result is not null then if not e10.is_platform_admin()then raise exception using errcode='42501',message='platform_catalog_write_denied';end if;return result;end if;
  perform pg_advisory_xact_lock(hashtextextended('platform|x1-mapping|'||provider_key||'|'||p_entity_kind||'|'||external_key,0));
  select * into prior from public.e10_catalog_identity_mappings m where m.provider=provider_key and m.entity_kind=p_entity_kind and m.external_id=external_key and m.is_current for update;
  next_revision:=coalesce(prior.mapping_revision,0)+1;
  if not e10.is_platform_admin()then raise exception using errcode='42501',message='platform_catalog_write_denied';end if;
  insert into public.e10_catalog_identity_mappings(id,provider,entity_kind,external_id,mapping_revision,player_id,release_id,variant_id,match_status,is_current,confidence,source_payload,reviewed_by,reviewed_at)
    values(new_id,provider_key,p_entity_kind,external_key,next_revision,p_player_id,p_release_id,p_variant_id,p_match_status,prior.id is null,p_confidence,p_source_payload,case when p_match_status='verified'then actor end,case when p_match_status='verified'then clock_timestamp()end);
  if prior.id is not null then
    update public.e10_catalog_identity_mappings set is_current=false where id=prior.id;
    update public.e10_catalog_identity_mappings set is_current=true where id=new_id;
  end if;
  result:=jsonb_build_object('ok',true,'replay',false,'mapping_id',new_id,'mapping_revision',next_revision,'supersedes_mapping_id',prior.id);
  insert into public.e10_x1_creation_commands values(scope_id,'catalog_identity_mapping.review',k,fp,result,actor,clock_timestamp());return result;
end $$;

revoke all on function public.e10_platform_create_catalog_release(text,text,text,integer,text,text,text,text,text,jsonb,text),public.e10_platform_create_catalog_variant(uuid,text,text,text,text,text,text,boolean,integer,jsonb,jsonb,text),public.e10_platform_review_catalog_identity_mapping(text,text,text,uuid,uuid,uuid,text,numeric,jsonb,text) from public,anon;
grant execute on function public.e10_platform_create_catalog_release(text,text,text,integer,text,text,text,text,text,jsonb,text),public.e10_platform_create_catalog_variant(uuid,text,text,text,text,text,text,boolean,integer,jsonb,jsonb,text),public.e10_platform_review_catalog_identity_mapping(text,text,text,uuid,uuid,uuid,text,numeric,jsonb,text) to authenticated,service_role;
