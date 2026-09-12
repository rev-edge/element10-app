-- TA-R5 closure: acquire the final referenced-parent locks and recheck
-- authority in the same statement that writes the dependent row.

create function e10.guard_unique_item_final_authority() returns trigger
language plpgsql security definer set search_path=public as $$
begin
  if new.catalog_variant_id is not null then
    perform 1 from public.e10_catalog_variants v
      where v.id=new.catalog_variant_id for key share;
    if not found then
      raise exception using errcode='22023',message='catalog_variant_invalid';
    end if;
  end if;
  if auth.uid() is not null and not e10.has_org_cap(new.organization_id,'catalog.propose') then
    raise exception using errcode='42501',message='catalog_propose_denied';
  end if;
  return new;
end $$;
create trigger e10_unique_item_final_authority_trg
before insert on public.e10_unique_items for each row
execute function e10.guard_unique_item_final_authority();

create function e10.guard_variant_subject_final_authority() returns trigger
language plpgsql security definer set search_path=public as $$
begin
  perform 1 from public.e10_players p where p.id=new.player_id for key share;
  if not found then
    raise exception using errcode='22023',message='catalog_variant_subject_invalid';
  end if;
  if auth.uid() is not null and not e10.is_platform_admin() then
    raise exception using errcode='42501',message='platform_catalog_write_denied';
  end if;
  return new;
end $$;
create trigger e10_variant_subject_final_authority_trg
before insert on public.e10_catalog_variant_subjects for each row
execute function e10.guard_variant_subject_final_authority();

create function e10.guard_mapping_status_r5() returns trigger
language plpgsql security definer set search_path=public as $$
begin
  if new.match_status is null or new.match_status not in('verified','candidate','rejected','superseded') then
    raise exception using errcode='22023',message='catalog_identity_mapping_payload_invalid';
  end if;
  return new;
end $$;
create trigger e10_catalog_mapping_status_r5_trg
before insert or update on public.e10_catalog_identity_mappings for each row
execute function e10.guard_mapping_status_r5();

revoke all on function e10.guard_unique_item_final_authority(),e10.guard_variant_subject_final_authority(),e10.guard_mapping_status_r5()
from public,anon,authenticated;
grant execute on function e10.guard_unique_item_final_authority(),e10.guard_variant_subject_final_authority(),e10.guard_mapping_status_r5()
to service_role;
