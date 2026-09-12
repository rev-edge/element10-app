\set ON_ERROR_STOP on
begin;

do $$
declare
  org uuid:='c2000000-0000-4000-8000-000000000001';
  other_org uuid:='c2000000-0000-4000-8000-000000000002';
  admin_user uuid:='c2000000-0000-4000-8000-000000000003';
  member_user uuid:='c2000000-0000-4000-8000-000000000004';
  admin_role uuid:='c2000000-0000-4000-8000-000000000005';
  member_role uuid:='c2000000-0000-4000-8000-000000000006';
begin
  insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at) values
    (admin_user,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','c2-admin@example.invalid',now(),now()),
    (member_user,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','c2-member@example.invalid',now(),now());
  insert into public.e10_organizations(id,slug,name) values
    (org,'c2-org','C2 Org'),(other_org,'c2-other','C2 Other');
  insert into public.e10_organization_roles(id,organization_id,key,name,is_system) values
    (admin_role,org,'admin','Admin',false),(member_role,org,'member','Member',false);
  insert into public.e10_organization_memberships(organization_id,user_id,role_id,status) values
    (org,admin_user,admin_role,'active'),(org,member_user,member_role,'active');
  insert into public.e10_organization_role_permissions(organization_id,role_id,capability,allowed) values
    (org,admin_role,'act.permissions_config',true),
    (org,admin_role,'custom.catalog.read',true),
    (org,admin_role,'custom.catalog.write',true),
    (org,member_role,'custom.catalog.read',true);
  insert into public.e10_product_masters(id,organization_id,name) values
    ('c2000000-0000-4000-8000-000000000010',org,'C2 product'),
    ('c2000000-0000-4000-8000-000000000011',other_org,'C2 foreign product');
end $$;

do $$
declare
  org uuid:='c2000000-0000-4000-8000-000000000001';
  admin_user uuid:='c2000000-0000-4000-8000-000000000003';
  member_user uuid:='c2000000-0000-4000-8000-000000000004';
  member_role uuid:='c2000000-0000-4000-8000-000000000006';
  numeric_def uuid;term_def uuid;multi_def uuid;gold uuid;value_id uuid;
begin
  perform set_config('request.jwt.claims',jsonb_build_object('sub',admin_user,'role','authenticated')::text,true);
  numeric_def:=public.e10_org_define_custom_field(org,'product_master','market_weight','Market weight','numeric','g','single','range','custom.catalog.read','custom.catalog.write');
  term_def:=public.e10_org_define_custom_field(org,'product_master','foil_treatment','Foil treatment','term',null,'single','exact',null,null);
  multi_def:=public.e10_org_define_custom_field(org,'product_master','search_tag','Search tag','text',null,'multiple','exact',null,null);
  gold:=public.e10_org_add_custom_field_term(org,term_def,'gold_shimmer','Gold shimmer');
  value_id:=public.e10_org_set_custom_field_value(org,numeric_def,'c2000000-0000-4000-8000-000000000010',1,'12.5'::jsonb);
  perform public.e10_org_set_custom_field_value(org,term_def,'c2000000-0000-4000-8000-000000000010',1,'"gold_shimmer"'::jsonb);
  perform public.e10_org_set_custom_field_value(org,multi_def,'c2000000-0000-4000-8000-000000000010',1,'"rookie"'::jsonb);
  perform public.e10_org_set_custom_field_value(org,multi_def,'c2000000-0000-4000-8000-000000000010',2,'"limited"'::jsonb);
  if (select value_numeric from public.e10_custom_field_values where id=value_id)<>12.5 then raise exception 'numeric value mismatch';end if;
  if (select count(*) from public.e10_custom_field_values where field_definition_id=multi_def)<>2 then raise exception 'multiple values mismatch';end if;
  if not exists(select 1 from public.e10_custom_field_values where field_definition_id=term_def and value_term_id=gold) then raise exception 'controlled term mismatch';end if;

  begin
    perform public.e10_org_set_custom_field_value(org,numeric_def,'c2000000-0000-4000-8000-000000000011',1,'3'::jsonb);
    raise exception 'cross-org object accepted';
  exception when foreign_key_violation then
    if sqlerrm<>'custom_field_object_not_found' then raise;end if;
  end;
  begin
    perform public.e10_org_set_custom_field_value(org,numeric_def,'c2000000-0000-4000-8000-000000000010',2,'3'::jsonb);
    raise exception 'single-valued second position accepted';
  exception when check_violation then
    if sqlerrm<>'custom_field_single_position_invalid' then raise;end if;
  end;

  perform set_config('request.jwt.claims',jsonb_build_object('sub',member_user,'role','authenticated')::text,true);
  begin
    perform public.e10_org_set_custom_field_value(org,numeric_def,'c2000000-0000-4000-8000-000000000010',1,'14'::jsonb);
    raise exception 'missing write capability accepted';
  exception when insufficient_privilege then
    if sqlerrm<>'custom_field_value_write_denied' then raise;end if;
  end;
  insert into public.e10_organization_role_permissions(organization_id,role_id,capability,allowed)
  values(org,member_role,'custom.catalog.write',true);
  perform public.e10_org_set_custom_field_value(org,numeric_def,'c2000000-0000-4000-8000-000000000010',1,'14'::jsonb);
  if (select value_numeric from public.e10_custom_field_values where id=value_id)<>14 then raise exception 'capability write failed';end if;
end $$;

select set_config('request.jwt.claims','{"sub":"c2000000-0000-4000-8000-000000000004","role":"authenticated"}',true);
set local role authenticated;
do $$
begin
  if (select count(*) from public.e10_custom_field_definitions where field_key='market_weight')<>1
    or (select count(*) from public.e10_custom_field_values v join public.e10_custom_field_definitions d on d.id=v.field_definition_id where d.field_key='market_weight')<>1 then
    raise exception 'authorized custom-field read failed';
  end if;
  begin
    insert into public.e10_custom_field_values(organization_id,field_definition_id,object_type,object_id,value_text)
    values('c2000000-0000-4000-8000-000000000001','c2000000-0000-4000-8000-000000000099','product_master','x','bypass');
    raise exception 'direct authenticated write accepted';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;

delete from public.e10_organization_role_permissions
where organization_id='c2000000-0000-4000-8000-000000000001'
  and role_id='c2000000-0000-4000-8000-000000000006'
  and capability='custom.catalog.read';
set local role authenticated;
do $$
begin
  if exists(select 1 from public.e10_custom_field_definitions where field_key='market_weight')
    or exists(select 1 from public.e10_custom_field_values v join public.e10_custom_field_definitions d on d.id=v.field_definition_id where d.field_key='market_weight') then
    raise exception 'missing read capability exposed custom field';
  end if;
end $$;
reset role;

do $$
begin
  if has_function_privilege('anon','public.e10_org_define_custom_field(uuid,text,text,text,text,text,text,text,text,text)','execute')
    or has_function_privilege('anon','public.e10_org_set_custom_field_value(uuid,uuid,text,integer,jsonb)','execute') then
    raise exception 'anonymous custom-field execute leak';
  end if;
  if not has_function_privilege('authenticated','public.e10_org_set_custom_field_value(uuid,uuid,text,integer,jsonb)','execute') then
    raise exception 'authenticated writer missing';
  end if;
end $$;

rollback;
select 'schema review C2 governed custom fields PASS' result;
