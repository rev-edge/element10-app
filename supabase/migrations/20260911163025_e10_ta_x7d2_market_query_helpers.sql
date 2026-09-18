-- TA-X7d.2a bounded source-universe, provenance, and coverage helpers.
create function e10.market_source_universe(p_org uuid,p_mode text,p_observation_kind text,p_source_kind text,p_currency text,p_connections jsonb)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare v_result jsonb;v_count integer;
begin
 if p_org is null or p_mode is null or p_mode not in('none','explicit','all_reviewed_connections')or p_observation_kind is null or p_observation_kind not in('acquisition_cost','asking_price','completed_sale','estimated_value')or p_currency is null or p_currency!~'^[A-Z]{3}$'or(p_mode<>'none'and(p_source_kind is null or p_source_kind not in('manual','csv','native','api')))then raise exception using errcode='22023',message='market_source_universe_invalid';end if;
 if p_mode='none'then if p_source_kind is not null or p_connections is not null then raise exception using errcode='22023',message='market_source_universe_invalid';end if;return'[]'::jsonb;end if;
 if p_mode='explicit'then
  if p_connections is null or jsonb_typeof(p_connections)<>'array'or jsonb_array_length(p_connections)not between 1 and 50 or exists(select 1 from jsonb_array_elements(p_connections)e where jsonb_typeof(e.value)not in('string','null')or(jsonb_typeof(e.value)='string'and length(btrim(e.value#>>'{}'))not between 1 and 500))then raise exception using errcode='22023',message='market_source_universe_invalid';end if;
  select jsonb_agg(value order by case when jsonb_typeof(value)='null'then 0 else 1 end,value#>>'{}')into v_result from(select distinct value from jsonb_array_elements(p_connections))s;
  return v_result;
 end if;
 if p_connections is not null then raise exception using errcode='22023',message='market_source_universe_invalid';end if;
 select count(*),coalesce(jsonb_agg(value order by null_rank,sort_value),'[]'::jsonb)into v_count,v_result from(
  select*from(
  select distinct to_jsonb(d.source_connection_id)value,case when d.source_connection_id is null then 0 else 1 end null_rank,coalesce(d.source_connection_id,'')sort_value
  from public.e10_current_market_observation_coverage d where d.organization_id=p_org and d.observation_kind=p_observation_kind and d.source_kind=p_source_kind and d.currency=p_currency
  )bounded order by null_rank,sort_value limit 51
 )s;
 if v_count>50 then raise exception using errcode='54000',message='market_source_universe_too_large';end if;
 return v_result;
end $$;

create function e10.market_provenance_matches(p_org uuid,p_observation_ids uuid[],p_source_kind text,p_connections jsonb)
returns boolean language plpgsql stable security definer set search_path=public as $$
begin
 if p_org is null or p_observation_ids is null or cardinality(p_observation_ids)=0 or p_source_kind is not null and p_source_kind not in('manual','csv','native','api')or(p_source_kind is null and p_connections is not null)or(p_source_kind is not null and(p_connections is null or jsonb_typeof(p_connections)<>'array'or jsonb_array_length(p_connections)not between 1 and 50 or exists(select 1 from jsonb_array_elements(p_connections)e where jsonb_typeof(e.value)not in('string','null')or(jsonb_typeof(e.value)='string'and length(btrim(e.value#>>'{}'))not between 1 and 500))))then raise exception using errcode='22023',message='market_provenance_filter_invalid';end if;
 return case when p_source_kind is null then true else exists(
  select 1 from public.e10_current_market_observations o where o.organization_id=p_org and o.id=any(p_observation_ids)and o.source_kind=p_source_kind
  and exists(select 1 from jsonb_array_elements(p_connections)e where(jsonb_typeof(e.value)='null'and o.source_connection_id is null)or(jsonb_typeof(e.value)='string'and e.value#>>'{}'=o.source_connection_id))
 )end;
end
$$;

create function e10.market_coverage_status(p_org uuid,p_observation_kind text,p_source_kind text,p_currency text,p_from timestamptz,p_to timestamptz,p_connections jsonb)
returns text language plpgsql stable security definer set search_path=public as $$
declare v_result text;
begin
 if p_org is null or p_observation_kind is null or p_observation_kind not in('acquisition_cost','asking_price','completed_sale','estimated_value')or p_source_kind is null or p_source_kind not in('manual','csv','native','api')or p_currency is null or p_currency!~'^[A-Z]{3}$'or p_from is null or p_to is null or not isfinite(p_from)or not isfinite(p_to)or p_from>=p_to or p_connections is null or jsonb_typeof(p_connections)<>'array'or jsonb_array_length(p_connections)>50 or exists(select 1 from jsonb_array_elements(p_connections)e where jsonb_typeof(e.value)not in('string','null')or(jsonb_typeof(e.value)='string'and length(btrim(e.value#>>'{}'))not between 1 and 500))then raise exception using errcode='22023',message='market_coverage_request_invalid';end if;
 with sources as(
  select value connection from jsonb_array_elements(p_connections)
 ),per_source as(
  select s.connection,
   count(d.id)>0 any_reviewed,
   coalesce(tstzrange(p_from,p_to,'[)')<@range_agg(tstzrange(d.covered_from,d.covered_to,'[)'))filter(where d.coverage_status='complete'),false)complete_span,
   coalesce(bool_or(d.coverage_status='partial'and tstzrange(d.covered_from,d.covered_to,'[)')&&tstzrange(p_from,p_to,'[)')),false)has_partial,
   coalesce(bool_or(d.coverage_status='unavailable'and tstzrange(d.covered_from,d.covered_to,'[)')&&tstzrange(p_from,p_to,'[)')),false)has_unavailable
  from sources s left join public.e10_current_market_observation_coverage d on d.organization_id=p_org and d.observation_kind=p_observation_kind and d.source_kind=p_source_kind and d.currency=p_currency
   and((jsonb_typeof(s.connection)='null'and d.source_connection_id is null)or(jsonb_typeof(s.connection)='string'and s.connection#>>'{}'=d.source_connection_id))
  group by s.connection
 ),summary as(select count(*)source_count,coalesce(bool_and(any_reviewed),false)all_reviewed,coalesce(bool_and(complete_span and not has_partial and not has_unavailable),false)all_complete,coalesce(bool_or(has_partial),false)any_partial,coalesce(bool_or(has_unavailable),false)any_unavailable from per_source)
 select case when source_count=0 then'unknown'when any_unavailable then'unavailable'when all_complete then'complete'when all_reviewed or any_partial then'partial'else'unknown'end into v_result from summary;
 return v_result;
end
$$;

do $$begin
 revoke all on function e10.market_source_universe(uuid,text,text,text,text,jsonb)from public,anon,authenticated;
 revoke all on function e10.market_provenance_matches(uuid,uuid[],text,jsonb)from public,anon,authenticated;
 revoke all on function e10.market_coverage_status(uuid,text,text,text,timestamptz,timestamptz,jsonb)from public,anon,authenticated;
 grant execute on function e10.market_source_universe(uuid,text,text,text,text,jsonb),e10.market_provenance_matches(uuid,uuid[],text,jsonb),e10.market_coverage_status(uuid,text,text,text,timestamptz,timestamptz,jsonb)to service_role;
end $$;

comment on function e10.market_source_universe(uuid,text,text,text,text,jsonb)is'Resolves an exact-kind explicit or all-reviewed tenant-private source universe. Empty never implies complete market coverage.';
