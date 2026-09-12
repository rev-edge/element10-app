-- fixture prologue: must be run inside a transaction as postgres
create temp table ids(k text primary key, v uuid);
grant select on ids to authenticated, anon;
create function pg_temp.i(k text) returns uuid language sql stable as $$ select v from ids where k=$1 $$;
grant execute on function pg_temp.i(text) to authenticated, anon, public;
create function pg_temp.as_user(k text) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', jsonb_build_object('sub', pg_temp.i(k), 'role','authenticated','email',k||'@x.invalid')::text, true);
end $$;
grant execute on function pg_temp.as_user(text) to authenticated, anon, public;
insert into ids values
 ('org','e1000000-0000-4000-8000-0000000000a6'),
 ('u1',gen_random_uuid()),('u2',gen_random_uuid()),('u3',gen_random_uuid()),('uadmin',gen_random_uuid()),('ufor',gen_random_uuid()),
 ('r1',gen_random_uuid()),('r2',gen_random_uuid()),('r3',gen_random_uuid()),('rfor',gen_random_uuid()),
 ('c1',gen_random_uuid()),('c2',gen_random_uuid()),('c3',gen_random_uuid()),
 ('L1',gen_random_uuid()),('L2',gen_random_uuid()),
 ('S',gen_random_uuid()),('slot1',gen_random_uuid()),('slot2',gen_random_uuid()),
 ('org2',gen_random_uuid()),('c_for',gen_random_uuid()),('L_for',gen_random_uuid());
insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at)
 select v,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',k||'-'||v||'@x.invalid',now(),now() from ids where k in ('u1','u2','u3','uadmin','ufor');
insert into public.e10_organizations(id,name,slug) values(pg_temp.i('org2'),'Foreign org','for-'||replace(pg_temp.i('org2')::text,'-',''));
insert into public.e10_reporting_dataset_revisions(organization_id) values(pg_temp.i('org2')) on conflict do nothing;
insert into public.e10_organization_roles(id,organization_id,key,name,is_system) values
 (pg_temp.i('r1'),pg_temp.i('org'),'rev-all-'||pg_temp.i('r1'),'All caps',false),
 (pg_temp.i('r2'),pg_temp.i('org'),'rev-approve-'||pg_temp.i('r2'),'Approver only',false),
 (pg_temp.i('r3'),pg_temp.i('org'),'rev-loc-'||pg_temp.i('r3'),'Location reader',false),
 (pg_temp.i('rfor'),pg_temp.i('org2'),'admin','Admin',true);
insert into public.e10_organization_role_permissions(organization_id,role_id,capability,allowed)
 select pg_temp.i('org'),pg_temp.i('r1'),c,true from unnest(array['act.record_commercial_events','act.manage_customers','act.prepare_customer_transactions','act.approve_customer_transactions','act.post_customer_transactions','act.adjust_customer_transactions','act.reconcile_customer_transactions','act.merge_customers','act.correct_customer_attribution','act.view_customer_financials','act.view_customer_engagement','act.live_run']) c;
insert into public.e10_organization_role_permissions values(pg_temp.i('org'),pg_temp.i('r2'),'act.approve_customer_transactions',true);
insert into public.e10_organization_role_permissions values(pg_temp.i('org'),pg_temp.i('r3'),'act.manage_customers',true);
insert into public.e10_organization_role_permissions(organization_id,role_id,capability,allowed)
 select pg_temp.i('org2'),pg_temp.i('rfor'),c,true from unnest(array['act.record_commercial_events','act.manage_customers','act.prepare_customer_transactions','act.approve_customer_transactions','act.post_customer_transactions','act.adjust_customer_transactions','act.reconcile_customer_transactions','act.merge_customers','act.correct_customer_attribution','act.view_customer_financials','act.view_customer_engagement','act.live_run','act.permissions_config']) c;
insert into public.e10_organization_memberships(organization_id,user_id,role_id,status) values
 (pg_temp.i('org'),pg_temp.i('u1'),pg_temp.i('r1'),'active'),
 (pg_temp.i('org'),pg_temp.i('u2'),pg_temp.i('r2'),'active'),
 (pg_temp.i('org'),pg_temp.i('u3'),pg_temp.i('r3'),'active'),
 (pg_temp.i('org'),pg_temp.i('uadmin'),'e1000000-0000-4000-8000-000000000001','active'),
 (pg_temp.i('org2'),pg_temp.i('ufor'),pg_temp.i('rfor'),'active');
insert into public.e10_organization_role_permissions values(pg_temp.i('org'),'e1000000-0000-4000-8000-000000000001','act.permissions_config',true) on conflict do nothing;
insert into public.e10_customers(id,organization_id,display_name) values
 (pg_temp.i('c1'),pg_temp.i('org'),'Alice'),(pg_temp.i('c2'),pg_temp.i('org'),'Bob'),(pg_temp.i('c3'),pg_temp.i('org'),'alice'),
 (pg_temp.i('c_for'),pg_temp.i('org2'),'Foreign Alice');
insert into public.e10_locations(id,organization_id,name,status) values (pg_temp.i('L1'),pg_temp.i('org'),'Store One','active'),(pg_temp.i('L2'),pg_temp.i('org'),'Store Two','active'),(pg_temp.i('L_for'),pg_temp.i('org2'),'Foreign store','active');
insert into public.e10_break_sessions(id,organization_id,streamer_uid,name,status) values(pg_temp.i('S'),pg_temp.i('org'),pg_temp.i('u1'),'Rev break','active');
insert into public.e10_break_slots(id,organization_id,session_id,label,price,state,position) values (pg_temp.i('slot1'),pg_temp.i('org'),pg_temp.i('S'),'A',12,'available',1),(pg_temp.i('slot2'),pg_temp.i('org'),pg_temp.i('S'),'B',7,'available',2);
create function pg_temp.try(sql text) returns text language plpgsql as $$
declare r text;
begin
  execute 'select ('||sql||')::text' into r; return 'OK '||coalesce(r,'<null>');
exception when others then return 'ERR '||sqlstate||' '||sqlerrm;
end $$;
grant execute on function pg_temp.try(text) to authenticated, anon, public;
create function pg_temp.remember(k text, v uuid) returns uuid language sql as $$ insert into ids values(k,v) returning v $$;
grant execute on function pg_temp.remember(text,uuid) to authenticated, anon, public;
grant insert on ids to authenticated, anon;
