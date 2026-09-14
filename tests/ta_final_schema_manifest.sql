\pset format unaligned
\pset tuples_only on
\pset fieldsep '|'

with manifest as (
  select 'function_metadata' category,
    n.nspname||'.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')' object_key,
    concat_ws('|',pg_get_function_arguments(p.oid),pg_get_function_result(p.oid),l.lanname,
      p.provolatile,p.proisstrict,p.prosecdef,p.proleakproof,p.proparallel,
      coalesce(p.proconfig::text,''),coalesce(p.proacl::text,'')) value
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  join pg_language l on l.oid=p.prolang where n.nspname in('public','e10')
  union all
  select 'function_definition',n.nspname||'.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')',
    pg_get_functiondef(p.oid)
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname in('public','e10')
  union all
  select 'table',n.nspname||'.'||c.relname,
    concat_ws('|',c.relkind,c.relrowsecurity,c.relforcerowsecurity,coalesce(c.relacl::text,''))
  from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where n.nspname in('public','e10')and c.relkind in('r','p')
  union all
  select 'column',n.nspname||'.'||c.relname||'.'||a.attname,
    concat_ws('|',a.attnum,format_type(a.atttypid,a.atttypmod),a.attnotnull,
      coalesce(pg_get_expr(d.adbin,d.adrelid),''),a.attidentity,a.attgenerated)
  from pg_attribute a join pg_class c on c.oid=a.attrelid
  join pg_namespace n on n.oid=c.relnamespace
  left join pg_attrdef d on d.adrelid=a.attrelid and d.adnum=a.attnum
  where n.nspname in('public','e10')and c.relkind in('r','p')
    and a.attnum>0 and not a.attisdropped
  union all
  select 'constraint',n.nspname||'.'||c.relname||'.'||x.conname,
    concat_ws('|',x.contype,x.convalidated,x.condeferrable,x.condeferred,
      pg_get_constraintdef(x.oid,true))
  from pg_constraint x join pg_class c on c.oid=x.conrelid
  join pg_namespace n on n.oid=c.relnamespace where n.nspname in('public','e10')
  union all
  select 'index',schemaname||'.'||tablename||'.'||indexname,indexdef
  from pg_indexes where schemaname in('public','e10')
  union all
  select 'trigger',n.nspname||'.'||c.relname||'.'||t.tgname,
    concat_ws('|',t.tgenabled,pg_get_triggerdef(t.oid,true))
  from pg_trigger t join pg_class c on c.oid=t.tgrelid
  join pg_namespace n on n.oid=c.relnamespace
  where n.nspname in('public','e10')and not t.tgisinternal
  union all
  select 'policy',n.nspname||'.'||c.relname||'.'||p.polname,
    concat_ws('|',p.polcmd,p.polpermissive,
      coalesce((select string_agg(coalesce(r.rolname,'PUBLIC'),','order by coalesce(r.rolname,'PUBLIC'))
        from unnest(p.polroles)u(role_oid)left join pg_roles r on r.oid=u.role_oid),''),
      coalesce(pg_get_expr(p.polqual,p.polrelid),''),
      coalesce(pg_get_expr(p.polwithcheck,p.polrelid),''))
  from pg_policy p join pg_class c on c.oid=p.polrelid
  join pg_namespace n on n.oid=c.relnamespace where n.nspname in('public','e10')
)
select category,object_key,
  encode(digest(convert_to(value,'UTF8'),'sha256'),'hex') value_sha256
from manifest order by category,object_key;
