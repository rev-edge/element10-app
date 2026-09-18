-- TA-R7 SCOPE-7: TRUNCATE bypasses row-level security and is not part of any
-- supported client contract. Remove it from all API roles without changing
-- the still-inventoried row-level compatibility grants.
do $$
declare r record;
begin
 for r in select c.oid::regclass relation_name from pg_class c join pg_namespace n on n.oid=c.relnamespace
   where n.nspname='public'and c.relkind in('r','p')
 loop
   execute format('revoke truncate on table %s from anon,authenticated',r.relation_name);
 end loop;
end $$;
