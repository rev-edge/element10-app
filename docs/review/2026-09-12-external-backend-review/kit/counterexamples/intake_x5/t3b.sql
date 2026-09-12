\set ON_ERROR_STOP 0
\pset format unaligned
\pset tuples_only on
begin;
\i fixture.sql
create temp table st(k text primary key, v uuid); grant all on st to public;
select pg_temp.as_a(); set local role authenticated;
select pg_temp.try('R2 open reconciliation import', $q$select public.e10_org_open_customer_transaction_reconciliation(org_a,'import','shop','e1','c1','CAD',1,null,null,'{}','T-r-2')::text from fx$q$);
reset role;
insert into st select 'case',id from public.e10_customer_transaction_reconciliation_cases where organization_id=(select org_a from fx) and source_event_id='e1' and source_component_id='c1';
select pg_temp.as_b(); set local role authenticated;
select pg_temp.try('R5 orgB decides orgA case p_org=B', $q$select public.e10_org_decide_customer_transaction_reconciliation(org_b,(select v from st where k='case'),0,'reject',null,null,null,'x','{}','T-r-5')::text from fx$q$);
select pg_temp.try('R6 orgB decides orgA case p_org=A', $q$select public.e10_org_decide_customer_transaction_reconciliation(org_a,(select v from st where k='case'),0,'reject',null,null,null,'x','{}','T-r-6')::text from fx$q$);
select pg_temp.try('R7 orgB bind activity random', $q$select public.e10_org_bind_customer_activity_source_component(org_b,gen_random_uuid(),'c','r','T-r-7')::text from fx$q$);
select pg_temp.try('R8 orgB opens case with same source identity as orgA (tenant separation expected)', $q$select public.e10_org_open_customer_transaction_reconciliation(org_b,'import','shop','e1','c1','CAD',1,null,null,'{}','T-r-8')::text from fx$q$);
reset role;
select pg_temp.as_a(); set local role authenticated;
select pg_temp.try('R9 orgA decide link to nonexistent line', $q$select public.e10_org_decide_customer_transaction_reconciliation(org_a,(select v from st where k='case'),0,'link','reviewed_match',gen_random_uuid(),gen_random_uuid(),'x','{}','T-r-9')::text from fx$q$);
select pg_temp.try('R10 orgA decide reject rev 0', $q$select public.e10_org_decide_customer_transaction_reconciliation(org_a,(select v from st where k='case'),0,'reject',null,null,null,'x','{}','T-r-10')::text from fx$q$);
select pg_temp.try('R11 replay same key', $q$select public.e10_org_decide_customer_transaction_reconciliation(org_a,(select v from st where k='case'),0,'reject',null,null,null,'x','{}','T-r-10')::text from fx$q$);
select pg_temp.try('R12 same key different reason', $q$select public.e10_org_decide_customer_transaction_reconciliation(org_a,(select v from st where k='case'),0,'reject',null,null,null,'y','{}','T-r-10')::text from fx$q$);
select pg_temp.try('R13 stale revision', $q$select public.e10_org_decide_customer_transaction_reconciliation(org_a,(select v from st where k='case'),0,'ambiguous',null,null,null,'x','{}','T-r-13')::text from fx$q$);
select pg_temp.try('R14 unlink when not linked', $q$select public.e10_org_decide_customer_transaction_reconciliation(org_a,(select v from st where k='case'),1,'unlink',null,null,null,'x','{}','T-r-14')::text from fx$q$);
reset role;
rollback;
