\set ON_ERROR_STOP on
do $$
declare n integer;
begin
 select count(*) into n from information_schema.role_table_grants g
 join pg_class c on c.relname=g.table_name join pg_namespace ns on ns.oid=c.relnamespace and ns.nspname=g.table_schema
 where g.table_schema='public'and g.grantee in('anon','authenticated')and g.privilege_type='TRUNCATE'and c.relkind in('r','p');
 if n<>0 then raise exception'API roles retain % public TRUNCATE grants',n;end if;
end $$;
select 'TA-R7 legacy TRUNCATE closure: PASS' result;
