-- shared fixture: org0 user uA with manage_intake + record_commercial_events + reconcile; org B with user uB same caps
create temp table fx as select
 'e1000000-0000-4000-8000-0000000000a6'::uuid as org_a, gen_random_uuid() as org_b,
 gen_random_uuid() as u_a, gen_random_uuid() as u_b, gen_random_uuid() as role_a, gen_random_uuid() as role_b,
 gen_random_uuid() as prod_a, gen_random_uuid() as prod_b;
insert into public.e10_organizations(id,name,slug) select org_b,'C Other','c-'||replace(org_b::text,'-','') from fx;
insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at)
 select u_a,'00000000-0000-0000-0000-000000000000'::uuid,'authenticated','authenticated',u_a||'@x.invalid',now(),now() from fx
 union all select u_b,'00000000-0000-0000-0000-000000000000'::uuid,'authenticated','authenticated',u_b||'@x.invalid',now(),now() from fx;
insert into public.e10_organization_roles(id,organization_id,key,name,is_system) select role_a,org_a,'c-'||u_a,'C A',false from fx union all select role_b,org_b,'c-'||u_b,'C B',false from fx;
insert into public.e10_organization_role_permissions(organization_id,role_id,capability,allowed)
 select org_a,role_a,c,true from fx, unnest(array['act.manage_intake','act.record_commercial_events','act.reconcile_customer_transactions','act.adjust_customer_transactions']) c
 union all select org_b,role_b,c,true from fx, unnest(array['act.manage_intake','act.record_commercial_events','act.reconcile_customer_transactions','act.adjust_customer_transactions']) c;
insert into public.e10_organization_memberships(organization_id,user_id,role_id,status) select org_a,u_a,role_a,'active' from fx union all select org_b,u_b,role_b,'active' from fx;
insert into public.e10_product_masters(id,organization_id,name) select prod_a,org_a,'C Prod A' from fx union all select prod_b,org_b,'C Prod B' from fx;
insert into public.e10_inventory_items(id,organization_id,name,qty) select 'c-item-a',org_a,'C item A',1 from fx;
insert into public.e10_inventory_items(id,organization_id,name,qty) select 'c-item-b',org_b,'C item B',1 from fx;
create or replace function pg_temp.as_a() returns void language plpgsql as $$ begin perform set_config('request.jwt.claims',jsonb_build_object('sub',(select u_a from fx),'role','authenticated')::text,true); end $$;
create or replace function pg_temp.as_b() returns void language plpgsql as $$ begin perform set_config('request.jwt.claims',jsonb_build_object('sub',(select u_b from fx),'role','authenticated')::text,true); end $$;
create or replace function pg_temp.try(p_label text, p_sql text) returns text language plpgsql as $$
declare v text; begin
  execute p_sql into v;
  return p_label||' => OK: '||coalesce(v,'(null)');
exception when others then
  return p_label||' => ERR '||sqlstate||': '||sqlerrm;
end $$;
grant execute on function pg_temp.try(text,text) to public;
grant execute on function pg_temp.as_a() to public;
grant execute on function pg_temp.as_b() to public;
grant select on fx to public;
