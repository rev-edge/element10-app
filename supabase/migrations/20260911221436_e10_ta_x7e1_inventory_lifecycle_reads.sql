-- TA-X7e.1 eligible lifecycle events, signed cursors, and bounded lifecycle read.

create table public.e10_inventory_cursor_secrets(
 organization_id uuid primary key references public.e10_organizations(id)on delete cascade,
 secret text not null default encode(gen_random_bytes(32),'hex')check(secret~'^[0-9a-f]{64}$')
);
insert into public.e10_inventory_cursor_secrets(organization_id)select id from public.e10_organizations on conflict do nothing;
alter table public.e10_inventory_cursor_secrets enable row level security;
revoke all on public.e10_inventory_cursor_secrets from public,anon,authenticated;
grant all on public.e10_inventory_cursor_secrets to service_role;
create function e10.initialize_inventory_cursor_secret()returns trigger language plpgsql security definer set search_path=public as $$
begin insert into public.e10_inventory_cursor_secrets(organization_id)values(new.id)on conflict do nothing;return new;end $$;
revoke all on function e10.initialize_inventory_cursor_secret()from public,anon,authenticated;
grant execute on function e10.initialize_inventory_cursor_secret()to service_role;
create trigger e10_inventory_cursor_secret_init after insert on public.e10_organizations for each row execute function e10.initialize_inventory_cursor_secret();

create function e10.inventory_cursor_encode(p_org uuid,p_payload jsonb)returns text
language sql stable security definer set search_path=public as $$
 select replace(encode(convert_to(p_payload::text,'UTF8'),'base64'),E'\n','')||'.'||
   encode(extensions.hmac(p_payload::text,s.secret,'sha256'),'hex')
 from public.e10_inventory_cursor_secrets s where s.organization_id=p_org
$$;
create function e10.inventory_cursor_decode(p_org uuid,p_cursor text)returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare parts text[];payload text;expected text;secret_value text;
begin
 if p_org is null or p_cursor is null or length(p_cursor)not between 10 and 8192 then raise exception using errcode='22023',message='inventory_cursor_invalid';end if;
 parts:=string_to_array(p_cursor,'.');if cardinality(parts)<>2 then raise exception using errcode='22023',message='inventory_cursor_invalid';end if;
 begin payload:=convert_from(decode(parts[1],'base64'),'UTF8');exception when others then raise exception using errcode='22023',message='inventory_cursor_invalid';end;
 select secret into secret_value from public.e10_inventory_cursor_secrets where organization_id=p_org;
 expected:=encode(extensions.hmac(payload,secret_value,'sha256'),'hex');
 if expected is null or expected<>parts[2]then raise exception using errcode='22023',message='inventory_cursor_invalid';end if;
 return payload::jsonb;
exception when invalid_text_representation then raise exception using errcode='22023',message='inventory_cursor_invalid';
end $$;
revoke all on function e10.inventory_cursor_encode(uuid,jsonb),e10.inventory_cursor_decode(uuid,text)from public,anon,authenticated;
grant execute on function e10.inventory_cursor_encode(uuid,jsonb),e10.inventory_cursor_decode(uuid,text)to service_role;

create view public.e10_current_inventory_lifecycle_events with(security_invoker=true)as
select e.id,e.organization_id,r.unique_item_id,e.event_type,e.occurred_at,e.occurred_at_precision,e.created_at as recorded_at,
 e.payload->>'listing_id'as listing_id,e.payload->>'channel'as channel,e.source_kind,e.source_connection_id,e.source_reference,e.evidence_quality,e.correlation_id,e.causation_event_id
 ,case when e.correlation_id is null then'event:'||e.id::text else'corr:'||e.correlation_id end as episode_key
from public.e10_commercial_events e
join lateral(
 select case
  when e.subject_type='unique_item'and e.subject_id~*'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'then e.subject_id::uuid
  when e.subject_type='inventory_item'then(select(array_agg(u.id))[1]from public.e10_unique_items u where u.organization_id=e.organization_id and u.inventory_item_id=e.subject_id having count(*)=1)
 end unique_item_id
)r on r.unique_item_id is not null
where e.event_type in('acquisition','receipt','listing_created','listing_published','listing_paused','listing_resumed','listing_ended','listing_relisted','sale_committed','fulfillment','return')
and not exists(select 1 from public.e10_commercial_events n where n.organization_id=e.organization_id and n.corrects_event_id=e.id);
revoke all on public.e10_current_inventory_lifecycle_events from public,anon,authenticated;
grant select on public.e10_current_inventory_lifecycle_events to service_role;

create or replace view public.e10_current_inventory_disposition_links with(security_invoker=true)as
select d.*from public.e10_inventory_disposition_links d
where d.action='assert'and not exists(select 1 from public.e10_inventory_disposition_links n where n.organization_id=d.organization_id and n.supersedes_link_id=d.id)
and(
 d.customer_transaction_id is not null and d.disposition_kind='sale'and exists(select 1 from public.e10_customer_transactions t join public.e10_customer_transaction_lines l on l.organization_id=t.organization_id and l.transaction_id=t.id where t.organization_id=d.organization_id and t.id=d.customer_transaction_id and l.unique_item_id=d.unique_item_id and t.occurred_at=d.disposed_at and t.occurred_at_precision=d.disposed_at_precision
  and not exists(select 1 from public.e10_customer_transaction_adjustments c where c.organization_id=l.organization_id and c.transaction_line_id=l.id and c.adjustment_kind='cancellation'and not exists(select 1 from public.e10_customer_transaction_adjustments r where r.organization_id=c.organization_id and r.reinstates_cancellation_id=c.id)))
 or d.market_observation_id is not null and d.disposition_kind='sale'and d.disposed_at_precision='exact'and exists(select 1 from public.e10_current_market_observations m where m.organization_id=d.organization_id and m.id=d.market_observation_id and m.unique_item_id=d.unique_item_id and m.observation_kind='completed_sale'and m.source_kind in('manual','csv')and m.occurred_at=d.disposed_at)
 or d.commercial_event_id is not null and d.disposition_kind in('return','disposal')and exists(select 1 from public.e10_current_inventory_lifecycle_events e where e.organization_id=d.organization_id and e.id=d.commercial_event_id and e.unique_item_id=d.unique_item_id and e.event_type=case when d.disposition_kind='return'then'return'else'fulfillment'end and e.occurred_at=d.disposed_at and e.occurred_at_precision=d.disposed_at_precision)
);

create view public.e10_current_inventory_dispositions with(security_invoker=true)as
with native_attributed as(
 select t.organization_id,l.unique_item_id,o.id origin_event_id,o.episode_key,t.id customer_transaction_id,t.occurred_at disposed_at,t.occurred_at_precision disposed_at_precision,
  t.posted_at,t.commercial_event_id,
  row_number()over(partition by t.organization_id,t.id,l.id order by o.occurred_at desc,o.recorded_at desc,o.id desc)origin_rank
 from public.e10_customer_transactions t join public.e10_customer_transaction_lines l on l.organization_id=t.organization_id and l.transaction_id=t.id
 join public.e10_current_inventory_lifecycle_events o on o.organization_id=t.organization_id and o.unique_item_id=l.unique_item_id and o.occurred_at<=t.occurred_at and(
  o.event_type='acquisition'and not exists(select 1 from public.e10_current_inventory_lifecycle_events a where a.organization_id=o.organization_id and a.unique_item_id=o.unique_item_id and a.event_type='acquisition'and a.episode_key=o.episode_key and a.occurred_at<=t.occurred_at and a.id<>o.id)
  or o.event_type='receipt'and not exists(select 1 from public.e10_current_inventory_lifecycle_events a where a.organization_id=o.organization_id and a.unique_item_id=o.unique_item_id and a.event_type='acquisition'and a.episode_key=o.episode_key and a.occurred_at<=t.occurred_at))
 where not exists(select 1 from public.e10_customer_transaction_adjustments c where c.organization_id=l.organization_id and c.transaction_line_id=l.id and c.adjustment_kind='cancellation'and not exists(select 1 from public.e10_customer_transaction_adjustments r where r.organization_id=c.organization_id and r.reinstates_cancellation_id=c.id))
),native_sales as(
 select*from native_attributed n where n.origin_rank=1
)
select d.organization_id,d.unique_item_id,d.episode_origin_event_id as origin_event_id,d.episode_key,d.id disposition_link_id,d.disposition_kind,d.disposed_at,d.disposed_at_precision,d.recorded_at,d.customer_transaction_id,d.market_observation_id,d.commercial_event_id,'reviewed_link'::text source_basis
from public.e10_current_inventory_disposition_links d
union all
select n.organization_id,n.unique_item_id,n.origin_event_id,n.episode_key,null::uuid,'sale',n.disposed_at,n.disposed_at_precision,n.posted_at,n.customer_transaction_id,null::uuid,n.commercial_event_id,'trusted_posted_transaction'
from native_sales n;
revoke all on public.e10_current_inventory_disposition_links,public.e10_current_inventory_dispositions from public,anon,authenticated;
grant select on public.e10_current_inventory_disposition_links,public.e10_current_inventory_dispositions to service_role;

create function e10.inventory_active_exposure_seconds(p_org uuid,p_item uuid,p_start timestamptz,p_end timestamptz)
returns numeric language sql stable security definer set search_path=public as $$
 with opens as(
  select x.occurred_at as opened_at,coalesce((select min(y.occurred_at)
   from public.e10_current_inventory_lifecycle_events y
   where y.organization_id=x.organization_id and y.unique_item_id=x.unique_item_id
    and y.listing_id=x.listing_id and y.channel=x.channel
    and(y.occurred_at,y.recorded_at,y.id)>(x.occurred_at,x.recorded_at,x.id)
    and y.occurred_at<=p_end and y.event_type in('listing_paused','listing_ended')),p_end)as closed_at
  from public.e10_current_inventory_lifecycle_events x
  where x.organization_id=p_org and x.unique_item_id=p_item and x.occurred_at>=p_start and x.occurred_at<p_end
   and x.event_type in('listing_published','listing_resumed')
 ),merged as(select range_agg(tstzrange(opened_at,closed_at,'[)'))ranges from opens where closed_at>opened_at)
 select coalesce((select sum(extract(epoch from upper(r)-lower(r)))from merged m cross join lateral unnest(coalesce(m.ranges,'{}'::tstzmultirange))r),0)
$$;
revoke all on function e10.inventory_active_exposure_seconds(uuid,uuid,timestamptz,timestamptz)from public,anon,authenticated;
grant execute on function e10.inventory_active_exposure_seconds(uuid,uuid,timestamptz,timestamptz)to service_role;

create function public.e10_org_inventory_lifecycle(p_org uuid,p_as_of timestamptz,p_unique_item_id uuid default null,p_limit integer default 100,p_cursor text default null)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare actor uuid:=auth.uid();rev bigint;req_fp text;cur jsonb;after_item uuid;after_origin uuid;rows_json jsonb;exclusions jsonb;total_count integer;has_more boolean;last_item uuid;last_origin uuid;next_cursor text;
begin
 if actor is null or p_org is null or p_as_of is null or not isfinite(p_as_of)or p_limit is null or p_limit not between 1 and 200 or not exists(select 1 from public.e10_organizations where id=p_org and status='active')or not e10.is_org_member(p_org)or not e10.has_org_cap(p_org,'act.view_market_analytics')then raise exception using errcode='42501',message='inventory_lifecycle_read_denied';end if;
 select revision into rev from public.e10_inventory_reporting_revisions where organization_id=p_org;if rev is null then raise exception using errcode='55000',message='inventory_reporting_revision_missing';end if;
 req_fp:=encode(sha256(convert_to(jsonb_build_object('v','inventory-lifecycle-v1','org',p_org,'actor',actor,'as_of',extract(epoch from p_as_of),'item',p_unique_item_id,'revision',rev)::text,'UTF8')),'hex');
 if p_cursor is not null then cur:=e10.inventory_cursor_decode(p_org,p_cursor);if cur->>'fingerprint'<>req_fp or(cur->>'actor')::uuid<>actor or(cur->>'revision')::bigint<>rev then raise exception using errcode='40001',message='inventory_cursor_stale_or_foreign';end if;after_item:=(cur->>'unique_item_id')::uuid;after_origin:=(cur->>'origin_event_id')::uuid;end if;
 with current_raw as(
  select e.*from public.e10_commercial_events e where e.organization_id=p_org
   and e.event_type in('acquisition','receipt','listing_created','listing_published','listing_paused','listing_resumed','listing_ended','listing_relisted','sale_committed','fulfillment','return')
   and not exists(select 1 from public.e10_commercial_events n where n.organization_id=e.organization_id and n.corrects_event_id=e.id)
   and(p_unique_item_id is null or e.subject_type='unique_item'and e.subject_id=p_unique_item_id::text or e.subject_type='inventory_item'and exists(select 1 from public.e10_unique_items u where u.organization_id=e.organization_id and u.id=p_unique_item_id and u.inventory_item_id=e.subject_id))
 )select jsonb_build_object(
  'scope',case when p_unique_item_id is null then'organization'else'unique_item'end,
  'missing_occurrence_count',count(*)filter(where occurred_at is null or occurred_at_precision='unknown'),
  'ambiguous_identity_count',count(*)filter(where subject_type='unique_item'and subject_id!~*'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'or subject_type='inventory_item'and(select count(*)from public.e10_unique_items u where u.organization_id=current_raw.organization_id and u.inventory_item_id=current_raw.subject_id)<>1),
  'ambiguous_episode_correlation_count',(select count(*)from current_raw e where e.event_type='acquisition'and e.correlation_id is not null and exists(select 1 from current_raw a where a.organization_id=e.organization_id and a.subject_type=e.subject_type and a.subject_id=e.subject_id and a.event_type='acquisition'and a.correlation_id=e.correlation_id and a.id<>e.id))
 )into exclusions from current_raw;

 with ev as materialized(select*from public.e10_current_inventory_lifecycle_events where organization_id=p_org and occurred_at<=p_as_of and(p_unique_item_id is null or unique_item_id=p_unique_item_id)),
 origins as materialized(
  select e.*,
   case when e.event_type='receipt'then e.occurred_at else(select r.occurred_at from ev r where r.unique_item_id=e.unique_item_id and r.event_type='receipt'and r.correlation_id is not null and r.correlation_id=e.correlation_id order by r.occurred_at,r.recorded_at,r.id limit 1)end receipt_at,
   case when e.event_type='receipt'then e.recorded_at else(select r.recorded_at from ev r where r.unique_item_id=e.unique_item_id and r.event_type='receipt'and r.correlation_id is not null and r.correlation_id=e.correlation_id order by r.occurred_at,r.recorded_at,r.id limit 1)end receipt_recorded_at,
   case when e.event_type='receipt'then e.occurred_at_precision else(select r.occurred_at_precision from ev r where r.unique_item_id=e.unique_item_id and r.event_type='receipt'and r.correlation_id is not null and r.correlation_id=e.correlation_id order by r.occurred_at,r.recorded_at,r.id limit 1)end receipt_precision,
   lead(e.occurred_at)over(partition by e.unique_item_id order by e.occurred_at,e.recorded_at,e.id)next_origin_at,
   lead(e.recorded_at)over(partition by e.unique_item_id order by e.occurred_at,e.recorded_at,e.id)next_origin_recorded_at,
   lead(e.id)over(partition by e.unique_item_id order by e.occurred_at,e.recorded_at,e.id)next_origin_id
  from ev e where e.event_type='acquisition'and not exists(select 1 from ev a where a.unique_item_id=e.unique_item_id and a.event_type='acquisition'and a.episode_key=e.episode_key and a.id<>e.id)or e.event_type='receipt'and not exists(
   select 1 from ev a where a.unique_item_id=e.unique_item_id and a.event_type='acquisition'
    and a.episode_key=e.episode_key)
 ),eligible_dispositions as materialized(
  select d.*from public.e10_current_inventory_dispositions d where d.organization_id=p_org and d.disposed_at<=p_as_of
   and not(d.source_basis='trusted_posted_transaction'and exists(select 1 from public.e10_current_inventory_dispositions r where r.organization_id=d.organization_id and r.unique_item_id=d.unique_item_id and r.episode_key=d.episode_key and r.source_basis='reviewed_link'and r.disposed_at<=p_as_of))
 ),disposition_candidates as materialized(
  select d.*,row_number()over(partition by d.organization_id,d.unique_item_id,d.episode_key order by d.disposed_at,d.recorded_at,coalesce(d.disposition_link_id,d.customer_transaction_id,d.market_observation_id,d.commercial_event_id))rn,
   count(*)over(partition by d.organization_id,d.unique_item_id,d.episode_key)candidate_count
  from eligible_dispositions d
 ),unresolved_disposition_items as materialized(
  select distinct d.unique_item_id from eligible_dispositions d where not exists(select 1 from ev e where e.unique_item_id=d.unique_item_id and e.episode_key=d.episode_key and e.event_type in('acquisition','receipt'))
 ),episodes as materialized(
  select o.*,case when d.candidate_count=1 then d.disposition_link_id end disposition_link_id,case when d.candidate_count=1 then d.disposition_kind end disposition_kind,
   case when d.candidate_count=1 then d.disposed_at end disposed_at,case when d.candidate_count=1 then d.disposed_at_precision end disposed_at_precision,
   case when d.candidate_count=1 then d.recorded_at end disposition_recorded_at,case when d.candidate_count=1 then d.source_basis end source_basis,
   (coalesce(d.candidate_count,0)>1 or u.unique_item_id is not null)finality_conflict,
   least(coalesce(case when d.candidate_count=1 then d.disposed_at end,p_as_of),coalesce(o.next_origin_at,p_as_of),p_as_of)episode_end,
   d.candidate_count is null as censored,
   o.next_origin_at is not null and(coalesce(d.candidate_count,0)<>1 or o.next_origin_at<d.disposed_at)as overlapping_origin
  from origins o left join disposition_candidates d on d.organization_id=o.organization_id and d.unique_item_id=o.unique_item_id and d.episode_key=o.episode_key and d.rn=1
  left join unresolved_disposition_items u on u.unique_item_id=o.unique_item_id
 ),calculated as materialized(
  select ep.*,
   (select min(x.occurred_at)from ev x where x.unique_item_id=ep.unique_item_id and x.event_type='listing_published'and(x.occurred_at,x.recorded_at,x.id)>=(ep.occurred_at,ep.recorded_at,ep.id)and x.occurred_at<=ep.episode_end)first_published_at,
   (select bool_and(x.occurred_at_precision='exact')from ev x where x.unique_item_id=ep.unique_item_id and x.occurred_at>=ep.occurred_at and x.occurred_at<=ep.episode_end and x.event_type in('listing_published','listing_resumed','listing_paused','listing_ended'))listing_precision_exact,
   e10.inventory_active_exposure_seconds(ep.organization_id,ep.unique_item_id,ep.occurred_at,ep.episode_end)active_seconds,
   (select array_agg(q.id order by q.occurred_at,q.recorded_at,q.id)from(select x.id,x.occurred_at,x.recorded_at from ev x where x.unique_item_id=ep.unique_item_id and x.occurred_at>=ep.occurred_at and x.occurred_at<=ep.episode_end order by x.occurred_at,x.recorded_at,x.id limit 101)q)event_ids,
   (select count(*)from ev x where x.unique_item_id=ep.unique_item_id and x.occurred_at>=ep.occurred_at and x.occurred_at<=ep.episode_end)event_count
  from episodes ep
 ),ranked as materialized(
  select c.*,row_number()over(order by c.unique_item_id,c.id)rn,
   count(*)over()full_count
  from calculated c
 ),keyed as materialized(
  select*from ranked c
  where after_item is null or(c.unique_item_id,c.id)>(after_item,after_origin)
 ),page as materialized(select*from keyed order by unique_item_id,id limit p_limit+1),shown as materialized(select*from page order by unique_item_id,id limit p_limit)
 select coalesce((select max(full_count)from page),0),(select count(*)from page)>p_limit,
  coalesce(jsonb_agg(jsonb_build_object(
   'unique_item_id',unique_item_id,'episode_key',episode_key,'origin_event_id',id,'origin_kind',event_type,'origin_at',occurred_at,'origin_precision',occurred_at_precision,
   'acquired_at',case when event_type='acquisition'then occurred_at end,'received_at',receipt_at,'receipt_recorded_at',receipt_recorded_at,'receipt_precision',receipt_precision,
   'origin_recorded_at',recorded_at,'disposition_link_id',disposition_link_id,'disposition_kind',disposition_kind,'disposed_at',disposed_at,'disposition_recorded_at',disposition_recorded_at,'disposition_source_basis',source_basis,'censored',censored,'finality_conflict',finality_conflict,
   'inventory_age_seconds',case when not finality_conflict and occurred_at_precision='exact'and(disposed_at is null or disposed_at_precision='exact')and not overlapping_origin then extract(epoch from episode_end-occurred_at)end,
   'intake_delay_seconds',case when not finality_conflict and occurred_at_precision='exact'and listing_precision_exact and first_published_at is not null and not overlapping_origin then extract(epoch from first_published_at-occurred_at)end,
   'first_list_to_end_seconds',case when not finality_conflict and first_published_at is not null and listing_precision_exact and(disposed_at is null or disposed_at_precision='exact')and not overlapping_origin then extract(epoch from episode_end-first_published_at)end,
   'active_exposure_seconds',case when not finality_conflict and occurred_at_precision='exact'and listing_precision_exact and(disposed_at is null or disposed_at_precision='exact')and not overlapping_origin then active_seconds end,
   'first_published_at',first_published_at,'overlapping_origin',overlapping_origin,
   'availability',case when finality_conflict then'finality_conflict'when overlapping_origin then'episode_ambiguous'when occurred_at_precision<>'exact'or coalesce(listing_precision_exact,true)=false or disposed_at is not null and disposed_at_precision<>'exact'then'precision_unavailable'else'available'end,
   'contributing_event_ids',coalesce(to_jsonb(event_ids[1:100]),'[]'::jsonb),'contributing_event_count',event_count,'contributing_events_truncated',event_count>100
  )order by unique_item_id,id),'[]'::jsonb),
  (select unique_item_id from shown order by unique_item_id desc,id desc limit 1),(select id from shown order by unique_item_id desc,id desc limit 1)
 into total_count,has_more,rows_json,last_item,last_origin from shown;
 if has_more and last_item is not null then next_cursor:=e10.inventory_cursor_encode(p_org,jsonb_build_object('fingerprint',req_fp,'actor',actor,'revision',rev,'unique_item_id',last_item,'origin_event_id',last_origin));end if;
 if auth.uid()is distinct from actor or not e10.is_org_member(p_org)or not e10.has_org_cap(p_org,'act.view_market_analytics')then raise exception using errcode='42501',message='inventory_lifecycle_read_denied';end if;
 return jsonb_build_object('metric_version','inventory-lifecycle-v1','organization_revision',rev,'as_of',p_as_of,'total_count',total_count,'exclusions',exclusions,'items',rows_json,'next_cursor',next_cursor);
end $$;
revoke all on function public.e10_org_inventory_lifecycle(uuid,timestamptz,uuid,integer,text)from public,anon;
grant execute on function public.e10_org_inventory_lifecycle(uuid,timestamptz,uuid,integer,text)to authenticated,service_role;
comment on function public.e10_org_inventory_lifecycle(uuid,timestamptz,uuid,integer,text)is'Bounded current-restated lifecycle and exposure read. Provisional sales and unreviewed external comps do not close tenant ownership.';
