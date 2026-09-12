-- TA-R6 X7e: bind page size into signed cursor fingerprints and source
-- total_count from the complete ranked cohort, including empty trailing pages.
do $$
declare fn regprocedure;definition text;corrected text;
begin
  foreach fn in array array[
    'public.e10_org_inventory_lifecycle(uuid,timestamptz,uuid,integer,text)'::regprocedure,
    'public.e10_org_unique_item_evidence(uuid,uuid,timestamptz,integer,text)'::regprocedure,
    'public.e10_org_inventory_valuation_coverage(uuid,text,text,text,timestamptz,timestamptz,integer,integer,text)'::regprocedure
  ] loop
    select pg_get_functiondef(fn) into definition;
    corrected:=replace(definition,'''revision'', rev)', '''limit'', p_limit, ''revision'', rev)');
    corrected:=replace(corrected,'''revision'',rev)', '''limit'',p_limit,''revision'',rev)');
    if corrected=definition then
      raise exception 'R6 cursor fingerprint patch did not match %',fn;
    end if;
    if fn='public.e10_org_inventory_lifecycle(uuid,timestamptz,uuid,integer,text)'::regprocedure then
      corrected:=replace(corrected,'coalesce((select max(full_count)from page),0)','coalesce((select max(full_count)from keyed),0)');
    elsif fn='public.e10_org_unique_item_evidence(uuid,uuid,timestamptz,integer,text)'::regprocedure then
      corrected:=replace(corrected,'coalesce((select max(full_count)from page),0)','coalesce((select max(full_count)from ranked),0)');
    end if;
    execute corrected;
  end loop;
end $$;
