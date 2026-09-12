-- TA-R5: database-enforced immutable configuration and provider-mapping history.

create function e10.guard_configuration_version_history() returns trigger
language plpgsql security definer set search_path=public as $$
begin
  if tg_op='DELETE' then
    raise exception using errcode='55000',message='configuration_version_history_immutable';
  end if;
  if row(new.id,new.organization_id,new.configuration_id,new.version_no,new.packaging_kind,
      new.base_unit,new.base_units_per_package,new.barcode,new.attrs,new.created_by,new.created_at)
    is distinct from
    row(old.id,old.organization_id,old.configuration_id,old.version_no,old.packaging_kind,
      old.base_unit,old.base_units_per_package,old.barcode,old.attrs,old.created_by,old.created_at) then
    raise exception using errcode='55000',message='configuration_version_content_immutable';
  end if;
  if new.state is distinct from old.state and not (
    (old.state='draft' and new.state in ('active','retired'))
    or (old.state='active' and new.state='retired')) then
    raise exception using errcode='55000',message='configuration_version_transition_invalid';
  end if;
  return new;
end $$;

create trigger e10_configuration_version_history_guard_trg
before update or delete on public.e10_product_configuration_versions
for each row execute function e10.guard_configuration_version_history();

create function e10.guard_catalog_identity_mapping_history() returns trigger
language plpgsql security definer set search_path=public as $$
begin
  if tg_op='DELETE' then
    raise exception using errcode='55000',message='catalog_identity_mapping_history_immutable';
  end if;
  if row(new.id,new.provider,new.entity_kind,new.external_id,new.mapping_revision,
      new.player_id,new.release_id,new.variant_id,new.match_status,new.confidence,
      new.source_payload,new.reviewed_by,new.reviewed_at,new.created_at)
    is distinct from
    row(old.id,old.provider,old.entity_kind,old.external_id,old.mapping_revision,
      old.player_id,old.release_id,old.variant_id,old.match_status,old.confidence,
      old.source_payload,old.reviewed_by,old.reviewed_at,old.created_at) then
    raise exception using errcode='55000',message='catalog_identity_mapping_history_immutable';
  end if;
  if new.is_current is distinct from old.is_current then
    if old.is_current and not new.is_current then
      if not exists(select 1 from public.e10_catalog_identity_mappings successor
        where successor.provider=old.provider and successor.entity_kind=old.entity_kind
          and successor.external_id=old.external_id
          and successor.mapping_revision=old.mapping_revision+1) then
        raise exception using errcode='55000',message='catalog_identity_mapping_successor_required';
      end if;
    elsif not old.is_current and new.is_current then
      if not exists(select 1 from public.e10_catalog_identity_mappings predecessor
        where predecessor.provider=old.provider and predecessor.entity_kind=old.entity_kind
          and predecessor.external_id=old.external_id
          and predecessor.mapping_revision=old.mapping_revision-1
          and predecessor.is_current=false) then
        raise exception using errcode='55000',message='catalog_identity_mapping_predecessor_not_retired';
      end if;
    else
      raise exception using errcode='55000',message='catalog_identity_mapping_current_transition_invalid';
    end if;
  end if;
  return new;
end $$;

create trigger e10_catalog_identity_mapping_history_guard_trg
before update or delete on public.e10_catalog_identity_mappings
for each row execute function e10.guard_catalog_identity_mapping_history();

revoke all on function e10.guard_configuration_version_history(),e10.guard_catalog_identity_mapping_history() from public,anon,authenticated;
grant execute on function e10.guard_configuration_version_history(),e10.guard_catalog_identity_mapping_history() to service_role;
