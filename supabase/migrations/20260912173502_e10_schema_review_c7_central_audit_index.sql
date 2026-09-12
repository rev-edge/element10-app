-- Schema-review checkpoint 7: central audit index for mutable administrative/master data.
-- Domain append-only histories remain authoritative and are deliberately excluded.

create table public.e10_audit_change_batches(
  id uuid primary key default gen_random_uuid(),
  organization_id uuid,
  actor_user_id uuid,
  request_id text check(request_id is null or length(request_id)between 1 and 500),
  operation text not null check(operation in('insert','update','delete')),
  object_type text not null check(length(btrim(object_type))between 1 and 100),
  object_id text not null check(length(object_id)between 1 and 1000),
  reason text check(reason is null or length(btrim(reason))between 1 and 2000),
  retention_class text not null default'standard'check(retention_class in('standard','restricted','legal_hold')),
  occurred_at timestamptz not null default clock_timestamp()
);
create table public.e10_audit_change_records(
  id uuid primary key default gen_random_uuid(),
  batch_id uuid not null references public.e10_audit_change_batches(id)on delete restrict,
  organization_id uuid,
  object_type text not null,
  object_id text not null,
  field_name text not null check(length(field_name)between 1 and 100),
  old_value jsonb,
  new_value jsonb,
  classification text not null check(classification in('ordinary','sensitive','restricted')),
  created_at timestamptz not null default clock_timestamp(),
  check(old_value is not null or new_value is not null),
  check(old_value is null or jsonb_typeof(old_value)<>'null'),
  check(new_value is null or jsonb_typeof(new_value)<>'null')
);
create index e10_audit_change_records_object_idx on public.e10_audit_change_records(organization_id,object_type,object_id,created_at,id);
create index e10_audit_change_batches_actor_idx on public.e10_audit_change_batches(actor_user_id,occurred_at,id)where actor_user_id is not null;

create function e10.audit_redacted_value(p_value jsonb)returns jsonb
language sql immutable security definer set search_path=public as $$
 select case when p_value is null or p_value='null'::jsonb then null else jsonb_build_object(
  'redacted',true,'sha256',encode(sha256(convert_to(p_value::text,'UTF8')),'hex'))end
$$;
create function e10.capture_mutable_audit()returns trigger
language plpgsql security definer set search_path=public as $$
declare oldj jsonb:=case when tg_op='INSERT'then'{}'::jsonb else to_jsonb(old)end;
 newj jsonb:=case when tg_op='DELETE'then'{}'::jsonb else to_jsonb(new)end;
 object_type text:=tg_argv[0];org_field text:=tg_argv[1];id_fields text[]:=string_to_array(tg_argv[2],',');
 base_class text:=tg_argv[3];redacted text[]:=case when coalesce(tg_argv[4],'')=''then'{}'::text[]else string_to_array(tg_argv[4],',')end;
 ignored text[]:=array['created_at','updated_at','created_by','updated_by']||id_fields||case when org_field in('','@self')then'{}'::text[]else array[org_field]end;
 sourcej jsonb:=case when tg_op='DELETE'then oldj else newj end;org uuid;object_id text;field text;ov jsonb;nv jsonb;batch uuid;
begin
 if current_setting('e10.audit_suppress',true)='on'then if tg_op='DELETE'then return old;else return new;end if;end if;
 if org_field='@self'then org:=nullif(sourcej->>'id','')::uuid;
 elsif org_field<>''then org:=nullif(sourcej->>org_field,'')::uuid;end if;
 select string_agg(coalesce(sourcej->>k,'<null>'),'|'order by ord)into object_id from unnest(id_fields)with ordinality u(k,ord);
 for field in select key from(select jsonb_object_keys(oldj)key union select jsonb_object_keys(newj))f
  where key<>all(ignored)order by key loop
  ov:=oldj->field;nv:=newj->field;
  if tg_op='UPDATE'and ov is not distinct from nv then continue;end if;
  if ov='null'::jsonb then ov:=null;end if;if nv='null'::jsonb then nv:=null;end if;
  if ov is null and nv is null then continue;end if;
  if batch is null then
   batch:=gen_random_uuid();
   insert into public.e10_audit_change_batches(id,organization_id,actor_user_id,request_id,operation,object_type,object_id,reason,retention_class)
   values(batch,org,auth.uid(),nullif(current_setting('e10.audit_request_id',true),''),lower(tg_op),object_type,object_id,
    nullif(current_setting('e10.audit_reason',true),''),case when base_class='restricted'or cardinality(redacted)>0 then'restricted'else'standard'end);
  end if;
  insert into public.e10_audit_change_records(batch_id,organization_id,object_type,object_id,field_name,old_value,new_value,classification)
  values(batch,org,object_type,object_id,field,
   case when field=any(redacted)then e10.audit_redacted_value(ov)else ov end,
   case when field=any(redacted)then e10.audit_redacted_value(nv)else nv end,
   case when field=any(redacted)then'restricted'else base_class end);
 end loop;
 if tg_op='DELETE'then return old;else return new;end if;
end$$;
revoke all on function e10.audit_redacted_value(jsonb),e10.capture_mutable_audit()from public,anon,authenticated;
grant execute on function e10.audit_redacted_value(jsonb),e10.capture_mutable_audit()to service_role;

create trigger e10_audit_organizations after insert or update or delete on public.e10_organizations for each row execute function e10.capture_mutable_audit('organization','@self','id','sensitive','settings');
create trigger e10_audit_organization_roles after insert or update or delete on public.e10_organization_roles for each row execute function e10.capture_mutable_audit('organization_role','organization_id','id','sensitive','');
create trigger e10_audit_role_permissions after insert or update or delete on public.e10_organization_role_permissions for each row execute function e10.capture_mutable_audit('organization_role_permission','organization_id','role_id,capability','restricted','');
create trigger e10_audit_organization_modules after insert or update or delete on public.e10_organization_modules for each row execute function e10.capture_mutable_audit('organization_module','organization_id','module_key','sensitive','');
create trigger e10_audit_locations after insert or update or delete on public.e10_locations for each row execute function e10.capture_mutable_audit('location','organization_id','id','sensitive','address,attrs');
create trigger e10_audit_suppliers after insert or update or delete on public.e10_suppliers for each row execute function e10.capture_mutable_audit('supplier','organization_id','id','sensitive','contact,attrs');
create trigger e10_audit_supplier_offerings after insert or update or delete on public.e10_supplier_offerings for each row execute function e10.capture_mutable_audit('supplier_offering','organization_id','id','sensitive','attrs');
create trigger e10_audit_product_masters after insert or update or delete on public.e10_product_masters for each row execute function e10.capture_mutable_audit('product_master','organization_id','id','ordinary','attrs');
create trigger e10_audit_product_configurations after insert or update or delete on public.e10_product_configurations for each row execute function e10.capture_mutable_audit('product_configuration','organization_id','id','ordinary','attrs');
create trigger e10_audit_custom_field_definitions after insert or update or delete on public.e10_custom_field_definitions for each row execute function e10.capture_mutable_audit('custom_field_definition','organization_id','id','sensitive','');
create trigger e10_audit_custom_field_terms after insert or update or delete on public.e10_custom_field_terms for each row execute function e10.capture_mutable_audit('custom_field_term','organization_id','id','sensitive','');
create trigger e10_audit_custom_field_values after insert or update or delete on public.e10_custom_field_values for each row execute function e10.capture_mutable_audit('custom_field_value','organization_id','id','restricted','value_text,value_numeric,value_boolean,value_date,value_timestamp,value_term_id');

alter table public.e10_audit_change_batches enable row level security;alter table public.e10_audit_change_records enable row level security;
create policy e10_audit_change_batches_sel on public.e10_audit_change_batches for select to authenticated using(e10.is_platform_admin()or(organization_id is not null and e10.is_org_admin(organization_id)and e10.has_org_cap(organization_id,'act.permissions_config')));
create policy e10_audit_change_records_sel on public.e10_audit_change_records for select to authenticated using(e10.is_platform_admin()or(organization_id is not null and e10.is_org_admin(organization_id)and e10.has_org_cap(organization_id,'act.permissions_config')));
revoke all on public.e10_audit_change_batches,public.e10_audit_change_records from public,anon,authenticated;
grant select on public.e10_audit_change_batches,public.e10_audit_change_records to authenticated;
grant all on public.e10_audit_change_batches,public.e10_audit_change_records to service_role;
create trigger e10_audit_change_batches_append_only before update or delete on public.e10_audit_change_batches for each row execute function e10.reject_append_only_change();
create trigger e10_audit_change_records_append_only before update or delete on public.e10_audit_change_records for each row execute function e10.reject_append_only_change();

comment on table public.e10_audit_change_records is'Central searchable index for mutable administrative/master changes. It does not replace authoritative domain events or append-only decision histories.';
comment on column public.e10_audit_change_batches.retention_class is'Policy classification only. No deletion interval is implied until retention/export policy is approved.';
