\set ON_ERROR_STOP on
begin;

do $$
declare
 org uuid:='c7000000-0000-4000-8000-000000000001';admin_user uuid:='c7000000-0000-4000-8000-000000000002';
 member_user uuid:='c7000000-0000-4000-8000-000000000003';admin_role uuid:='c7000000-0000-4000-8000-000000000004';
 member_role uuid:='c7000000-0000-4000-8000-000000000005';supplier uuid:='c7000000-0000-4000-8000-000000000006';
begin
 insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at)values
 (admin_user,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','c7-admin@example.invalid',now(),now()),
 (member_user,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','c7-member@example.invalid',now(),now());
 perform set_config('request.jwt.claims',jsonb_build_object('sub',admin_user,'role','authenticated')::text,true);
 perform set_config('e10.audit_request_id','c7-request',true);perform set_config('e10.audit_reason','supplier correction',true);
 insert into public.e10_organizations(id,slug,name,created_by)values(org,'c7-org','C7 Org',admin_user);
 insert into public.e10_organization_roles(id,organization_id,key,name,is_system)values
 (admin_role,org,'admin','Admin',false),(member_role,org,'member','Member',false);
 insert into public.e10_organization_memberships(organization_id,user_id,role_id,status)values
 (org,admin_user,admin_role,'active'),(org,member_user,member_role,'active');
 insert into public.e10_organization_role_permissions(organization_id,role_id,capability,allowed)values
 (org,admin_role,'act.permissions_config',true);
 insert into public.e10_suppliers(id,organization_id,code,name,contact,attrs,created_by)
 values(supplier,org,'S1','Supplier One','{"email":"secret@example.invalid"}','{"private_note":"do not copy"}',admin_user);
 update public.e10_suppliers set name='Supplier Renamed',contact='{"email":"new-secret@example.invalid"}'where id=supplier;
 if not exists(select 1 from public.e10_audit_change_batches where organization_id=org and object_type='supplier'and operation='update'and request_id='c7-request'and reason='supplier correction')then raise exception 'supplier audit batch missing context';end if;
 if not exists(select 1 from public.e10_audit_change_records where organization_id=org and object_type='supplier'and object_id=supplier::text and field_name='name'and old_value='"Supplier One"'::jsonb and new_value='"Supplier Renamed"'::jsonb and classification='sensitive')then raise exception 'ordinary supplier field delta missing';end if;
 if not exists(select 1 from public.e10_audit_change_records where organization_id=org and object_type='supplier'and field_name='contact'and old_value->>'redacted'='true'and new_value->>'redacted'='true'and length(old_value->>'sha256')=64 and classification='restricted')then raise exception 'restricted supplier field not hashed';end if;
 if exists(select 1 from public.e10_audit_change_records where old_value::text like'%secret@example.invalid%'or new_value::text like'%new-secret@example.invalid%')then raise exception 'restricted plaintext leaked into audit';end if;
 if exists(select 1 from pg_trigger where not tgisinternal and tgrelid in('public.e10_commercial_events'::regclass,'public.e10_organization_status_transitions'::regclass)and tgname like'e10_audit_%')then raise exception 'authoritative append-only history was duplicated';end if;
 begin update public.e10_audit_change_records set field_name='tampered'where organization_id=org;raise exception 'audit record mutation accepted';
 exception when object_not_in_prerequisite_state then if sqlerrm<>'e10_audit_change_records_is_append_only'then raise;end if;end;
end$$;

select set_config('request.jwt.claims','{"sub":"c7000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
set local role authenticated;
do $$begin if not exists(select 1 from public.e10_audit_change_records where organization_id='c7000000-0000-4000-8000-000000000001')then raise exception 'authorized admin audit read missing';end if;end$$;
reset role;
select set_config('request.jwt.claims','{"sub":"c7000000-0000-4000-8000-000000000003","role":"authenticated"}',true);
set local role authenticated;
do $$begin if exists(select 1 from public.e10_audit_change_records where organization_id='c7000000-0000-4000-8000-000000000001')then raise exception 'ordinary member saw administrative audit';end if;end$$;
reset role;

rollback;
select 'schema review C7 central audit PASS' result;
