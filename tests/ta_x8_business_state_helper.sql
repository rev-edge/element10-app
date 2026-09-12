create or replace function pg_temp.x8_business_state()
returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare r record;n bigint;h text;result jsonb:='{}'::jsonb;
begin
 for r in
  select n.nspname schema_name,c.relname table_name
  from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='public'and c.relkind in('r','p')and c.relname<>all(array[
   'e10_query_contexts','e10_query_context_commands','e10_market_query_contexts','e10_market_query_cursors'])
  order by c.relname
 loop
  execute format('select count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'''' order by md5(to_jsonb(t)::text)),''''))from %I.%I t',r.schema_name,r.table_name)into n,h;
  result:=result||jsonb_build_object(r.table_name,jsonb_build_object('rows',n,'content_md5',h));
 end loop;
 return result;
end $$;
grant execute on function pg_temp.x8_business_state()to authenticated,service_role;

create or replace function pg_temp.x8_assert_envelope(p_value jsonb,p_operation text,p_grain text)
returns void language plpgsql as $$
declare required_keys constant text[]:=array['version','operation','organization_id','context_id','query_fingerprint','as_of','cutoff','grain','units','metric_definition','coverage','sources','unknowns','result'];k text;
begin
 if jsonb_typeof(p_value)<>'object'or p_value->>'version'<>'x8-query-v1'or p_value->>'operation'is distinct from p_operation or p_value->>'grain'is distinct from p_grain then raise exception'X8 envelope identity invalid: %',p_value;end if;
 foreach k in array required_keys loop if not(p_value?k)then raise exception'X8 envelope missing %: %',k,p_value;end if;end loop;
 if jsonb_typeof(p_value->'sources')<>'array'or jsonb_typeof(p_value->'unknowns')<>'array'or p_value->>'query_fingerprint'is null then raise exception'X8 envelope metadata shape invalid: %',p_value;end if;
 foreach k in array array['as_of','cutoff','units','metric_definition','coverage']loop if p_value->k='null'::jsonb and not(p_value->'unknowns'@>jsonb_build_array(k))then raise exception'X8 envelope null % not declared unknown: %',k,p_value;end if;end loop;
end $$;
grant execute on function pg_temp.x8_assert_envelope(jsonb,text,text)to authenticated,service_role;
