-- Emulates tests/provision_local_users.js without GoTrue: creates the three CI users directly.
do $$
declare s record; v_uid uuid; v_role uuid;
begin
  for s in select * from (values ('e10adm@example.com','admin'),('e10mem@example.com','member'),('e10gate@example.com','member')) t(email,role) loop
    select id into v_uid from auth.users where lower(email)=s.email;
    if v_uid is null then
      v_uid := gen_random_uuid();
      insert into auth.users(id,instance_id,aud,role,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
      values (v_uid,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',s.email,now(),'{"provider":"email","providers":["email"]}','{}',now(),now());
    end if;
    insert into public.e10_members(user_id,email,role) values (v_uid,s.email,s.role) on conflict (user_id) do update set email=excluded.email, role=excluded.role;
    v_role := case when s.role='admin' then 'e1000000-0000-4000-8000-000000000001'::uuid else 'e1000000-0000-4000-8000-000000000002'::uuid end;
    insert into public.e10_organization_memberships(organization_id,user_id,role_id,status)
      values ('e1000000-0000-4000-8000-0000000000a6',v_uid,v_role,'active')
      on conflict (organization_id,user_id) do update set role_id=excluded.role_id, status='active';
  end loop;
end $$;
