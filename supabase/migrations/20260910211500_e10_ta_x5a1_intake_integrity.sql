-- TA-X5a.1 integrity correction before first staging apply.

alter table public.e10_intake_batches drop constraint e10_intake_batches_organization_id_source_kind_payload_fing_key;
alter table public.e10_intake_batches add column idempotency_key text;
alter table public.e10_intake_batches add column request_fingerprint text;
alter table public.e10_intake_batches add constraint e10_intake_batches_idempotency_chk
  check(idempotency_key is null or btrim(idempotency_key)<>'');
alter table public.e10_intake_batches add constraint e10_intake_batches_request_fingerprint_chk
  check((idempotency_key is null)=(request_fingerprint is null));
create unique index e10_intake_batches_org_idempotency_uq
  on public.e10_intake_batches(organization_id,idempotency_key) where idempotency_key is not null;
create unique index e10_intake_batches_external_source_uq
  on public.e10_intake_batches(organization_id,source_kind,source_connection_id,source_reference)
  where source_connection_id is not null and source_reference is not null;
create index e10_intake_batches_payload_fingerprint_idx
  on public.e10_intake_batches(organization_id,payload_fingerprint);

alter table public.e10_intake_rows add constraint e10_intake_rows_one_target_chk
  check(num_nonnulls(product_master_id,configuration_version_id,unique_item_id)<=1);

create or replace function e10.guard_intake_raw_payload() returns trigger
language plpgsql security definer set search_path=public as $$
begin
  if new.organization_id is distinct from old.organization_id
     or new.batch_id is distinct from old.batch_id
     or new.source_row_number is distinct from old.source_row_number
     or new.raw_payload is distinct from old.raw_payload then
    raise exception using errcode='55000',message='intake_raw_source_is_immutable';
  end if;
  return new;
end;
$$;
revoke all on function e10.guard_intake_raw_payload() from public,anon,authenticated;
grant execute on function e10.guard_intake_raw_payload() to service_role;
create trigger e10_intake_rows_raw_immutable_trg before update on public.e10_intake_rows
  for each row execute function e10.guard_intake_raw_payload();

create or replace function e10.guard_intake_resolution_lineage() returns trigger
language plpgsql security definer set search_path=public as $$
declare v_row uuid;
begin
  if new.corrects_decision_id is not null then
    select intake_row_id into v_row from public.e10_intake_resolver_decisions
      where organization_id=new.organization_id and id=new.corrects_decision_id;
    if not found or v_row<>new.intake_row_id then
      raise exception using errcode='23514',message='resolver_correction_must_target_same_intake_row';
    end if;
  end if;
  return new;
end;
$$;
revoke all on function e10.guard_intake_resolution_lineage() from public,anon,authenticated;
grant execute on function e10.guard_intake_resolution_lineage() to service_role;
create trigger e10_intake_resolution_lineage_trg before insert on public.e10_intake_resolver_decisions
  for each row execute function e10.guard_intake_resolution_lineage();

create or replace function e10.guard_commercial_event_correction() returns trigger
language plpgsql security definer set search_path=public as $$
declare v record;
begin
  if new.corrects_event_id is not null then
    select subject_type,subject_id into v from public.e10_commercial_events
      where organization_id=new.organization_id and id=new.corrects_event_id;
    if not found or v.subject_type<>new.subject_type or v.subject_id<>new.subject_id then
      raise exception using errcode='23514',message='commercial_event_correction_subject_mismatch';
    end if;
  end if;
  return new;
end;
$$;
revoke all on function e10.guard_commercial_event_correction() from public,anon,authenticated;
grant execute on function e10.guard_commercial_event_correction() to service_role;
create trigger e10_commercial_event_correction_trg before insert on public.e10_commercial_events
  for each row execute function e10.guard_commercial_event_correction();
