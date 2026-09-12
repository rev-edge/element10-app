-- TA-X7d.2b bounded server-side query contexts and opaque cursor positions.
create table public.e10_market_query_contexts(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.e10_organizations(id)on delete cascade,
 actor_id uuid not null references auth.users(id)on delete cascade,
 endpoint text not null check(endpoint in('screener','drilldown')),
 api_version text not null check(length(btrim(api_version))between 1 and 50),
 query_fingerprint text not null check(query_fingerprint~'^[0-9a-f]{64}$'),
 normalized_request jsonb not null check(jsonb_typeof(normalized_request)='object'and octet_length(normalized_request::text)<=65536),
 resolved_source_universe jsonb not null check(jsonb_typeof(resolved_source_universe)='array'and jsonb_array_length(resolved_source_universe)<=50),
 organization_revision bigint not null check(organization_revision>0),
 catalog_revision bigint not null check(catalog_revision>0),
 cohort_keys text[] not null check(cardinality(cohort_keys)<=100000),
 total_row_count integer not null check(total_row_count between 0 and 100000 and total_row_count=cardinality(cohort_keys)),
 created_at timestamptz not null default statement_timestamp(),
 expires_at timestamptz not null default(statement_timestamp()+interval'15 minutes'),
 unique(organization_id,id),
 unique(organization_id,actor_id,endpoint,query_fingerprint),
 check(expires_at>created_at and expires_at<=created_at+interval'15 minutes')
);
create index e10_market_query_context_actor_expiry_idx on public.e10_market_query_contexts(organization_id,actor_id,expires_at,id);

create table public.e10_market_query_cursors(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null,
 actor_id uuid not null references auth.users(id)on delete cascade,
 context_id uuid not null,
 endpoint text not null check(endpoint in('screener','drilldown')),
 query_fingerprint text not null check(query_fingerprint~'^[0-9a-f]{64}$'),
 sort_position jsonb not null check(jsonb_typeof(sort_position)='object'and octet_length(sort_position::text)<=8192),
 parent_cohort_key text check(parent_cohort_key is null or length(parent_cohort_key)between 1 and 256),
 organization_revision bigint not null check(organization_revision>0),
 catalog_revision bigint not null check(catalog_revision>0),
 created_at timestamptz not null default statement_timestamp(),
 expires_at timestamptz not null default(statement_timestamp()+interval'15 minutes'),
 foreign key(organization_id,context_id)references public.e10_market_query_contexts(organization_id,id)on delete cascade,
 check(expires_at>created_at and expires_at<=created_at+interval'15 minutes')
);
create index e10_market_query_cursor_actor_expiry_idx on public.e10_market_query_cursors(organization_id,actor_id,expires_at,id);

alter table public.e10_market_query_contexts enable row level security;
alter table public.e10_market_query_cursors enable row level security;
revoke all on public.e10_market_query_contexts,public.e10_market_query_cursors from public,anon,authenticated;
grant all on public.e10_market_query_contexts,public.e10_market_query_cursors to service_role;

create function e10.market_query_fingerprint(p_api_version text,p_org uuid,p_actor uuid,p_endpoint text,p_request jsonb,p_source_universe jsonb,p_org_revision bigint,p_catalog_revision bigint)
returns text language plpgsql immutable security definer set search_path=public as $$
begin
 if p_api_version is null or length(btrim(p_api_version))not between 1 and 50 or p_org is null or p_actor is null or p_endpoint is null or p_endpoint not in('screener','drilldown')or p_request is null or jsonb_typeof(p_request)<>'object'or octet_length(p_request::text)>65536 or p_source_universe is null or jsonb_typeof(p_source_universe)<>'array'or jsonb_array_length(p_source_universe)>50 or p_org_revision is null or p_org_revision<1 or p_catalog_revision is null or p_catalog_revision<1 then raise exception using errcode='22023',message='market_query_fingerprint_invalid';end if;
 return encode(sha256(convert_to(jsonb_build_object('api',p_api_version,'org',p_org,'actor',p_actor,'endpoint',p_endpoint,'request',p_request,'source_universe',p_source_universe,'org_revision',p_org_revision,'catalog_revision',p_catalog_revision)::text,'UTF8')),'hex');
end $$;

create function e10.save_market_query_context(p_api_version text,p_org uuid,p_actor uuid,p_endpoint text,p_fingerprint text,p_request jsonb,p_source_universe jsonb,p_org_revision bigint,p_catalog_revision bigint,p_cohort_keys text[])
returns uuid language plpgsql volatile security definer set search_path=public as $$
declare v_id uuid;v_count integer;v_expected text;v_saved_keys text[];v_now timestamptz;
begin
 if p_api_version is null or length(btrim(p_api_version))not between 1 and 50 or p_org is null or p_actor is null or p_endpoint is null or p_endpoint not in('screener','drilldown')or p_fingerprint is null or p_fingerprint!~'^[0-9a-f]{64}$'or p_request is null or jsonb_typeof(p_request)<>'object'or octet_length(p_request::text)>65536 or p_source_universe is null or jsonb_typeof(p_source_universe)<>'array'or jsonb_array_length(p_source_universe)>50 or p_org_revision is null or p_org_revision<1 or p_catalog_revision is null or p_catalog_revision<1 or p_cohort_keys is null or cardinality(p_cohort_keys)>100000 or exists(select 1 from unnest(p_cohort_keys)k where k is null or length(k)not between 1 and 256)then raise exception using errcode='22023',message='market_query_context_invalid';end if;
 v_expected:=e10.market_query_fingerprint(p_api_version,p_org,p_actor,p_endpoint,p_request,p_source_universe,p_org_revision,p_catalog_revision);if p_fingerprint<>v_expected then raise exception using errcode='22023',message='market_query_context_fingerprint_mismatch';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|'||p_actor::text||'|market-query-state',0));
 delete from public.e10_market_query_contexts where organization_id=p_org and actor_id=p_actor and expires_at<=clock_timestamp();
 select id,cohort_keys into v_id,v_saved_keys from public.e10_market_query_contexts where organization_id=p_org and actor_id=p_actor and endpoint=p_endpoint and query_fingerprint=p_fingerprint and expires_at>clock_timestamp();if found then if v_saved_keys is distinct from p_cohort_keys then raise exception using errcode='22023',message='market_query_context_cohort_mismatch';end if;return v_id;end if;
 select count(*)into v_count from public.e10_market_query_contexts where organization_id=p_org and actor_id=p_actor and expires_at>clock_timestamp();
 if v_count>=100 then raise exception using errcode='54000',message='market_query_context_limit';end if;
 v_now:=clock_timestamp();insert into public.e10_market_query_contexts(organization_id,actor_id,endpoint,api_version,query_fingerprint,normalized_request,resolved_source_universe,organization_revision,catalog_revision,cohort_keys,total_row_count,created_at,expires_at)
 values(p_org,p_actor,p_endpoint,p_api_version,p_fingerprint,p_request,p_source_universe,p_org_revision,p_catalog_revision,p_cohort_keys,cardinality(p_cohort_keys),v_now,v_now+interval'15 minutes')returning id into v_id;
 return v_id;
end $$;

create function e10.save_market_query_cursor(p_context uuid,p_org uuid,p_actor uuid,p_endpoint text,p_fingerprint text,p_position jsonb,p_parent_cohort_key text,p_org_revision bigint,p_catalog_revision bigint)
returns uuid language plpgsql volatile security definer set search_path=public as $$
declare v_id uuid;v_count integer;v_context_expiry timestamptz;v_context_keys text[];v_now timestamptz;
begin
 if p_context is null or p_org is null or p_actor is null or p_endpoint is null or p_endpoint not in('screener','drilldown')or p_fingerprint is null or p_fingerprint!~'^[0-9a-f]{64}$'or p_position is null or jsonb_typeof(p_position)<>'object'or octet_length(p_position::text)>8192 or p_parent_cohort_key is not null and length(p_parent_cohort_key)not between 1 and 256 or(p_endpoint='screener'and p_parent_cohort_key is not null)or(p_endpoint='drilldown'and p_parent_cohort_key is null)or p_org_revision is null or p_org_revision<1 or p_catalog_revision is null or p_catalog_revision<1 then raise exception using errcode='22023',message='market_query_cursor_invalid';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|'||p_actor::text||'|market-query-state',0));
 select q.expires_at,q.cohort_keys into v_context_expiry,v_context_keys from public.e10_market_query_contexts q where q.id=p_context and q.organization_id=p_org and q.actor_id=p_actor and q.endpoint=p_endpoint and q.query_fingerprint=p_fingerprint and q.organization_revision=p_org_revision and q.catalog_revision=p_catalog_revision and q.expires_at>clock_timestamp()for update;
 if not found or v_context_expiry<=clock_timestamp()or(p_endpoint='drilldown'and not(p_parent_cohort_key=any(v_context_keys)))then raise exception using errcode='22023',message='market_query_cursor_invalid';end if;
 delete from public.e10_market_query_cursors where organization_id=p_org and actor_id=p_actor and expires_at<=clock_timestamp();
 select count(*)into v_count from public.e10_market_query_cursors where organization_id=p_org and actor_id=p_actor and expires_at>clock_timestamp();if v_count>=1000 then raise exception using errcode='54000',message='market_query_cursor_limit';end if;
 v_now:=clock_timestamp();insert into public.e10_market_query_cursors(organization_id,actor_id,context_id,endpoint,query_fingerprint,sort_position,parent_cohort_key,organization_revision,catalog_revision,created_at,expires_at)
 values(p_org,p_actor,p_context,p_endpoint,p_fingerprint,p_position,p_parent_cohort_key,p_org_revision,p_catalog_revision,v_now,least(v_now+interval'15 minutes',v_context_expiry))returning id into v_id;return v_id;
end $$;

create function e10.reject_market_query_state_update()returns trigger language plpgsql security definer set search_path=public as $$begin raise exception using errcode='55000',message='market_query_state_immutable';end $$;
create trigger e10_market_query_context_immutable before update on public.e10_market_query_contexts for each row execute function e10.reject_market_query_state_update();
create trigger e10_market_query_cursor_immutable before update on public.e10_market_query_cursors for each row execute function e10.reject_market_query_state_update();

do $$begin
 revoke all on function e10.market_query_fingerprint(text,uuid,uuid,text,jsonb,jsonb,bigint,bigint),e10.save_market_query_context(text,uuid,uuid,text,text,jsonb,jsonb,bigint,bigint,text[]),e10.save_market_query_cursor(uuid,uuid,uuid,text,text,jsonb,text,bigint,bigint),e10.reject_market_query_state_update()from public,anon,authenticated;
 grant execute on function e10.market_query_fingerprint(text,uuid,uuid,text,jsonb,jsonb,bigint,bigint),e10.save_market_query_context(text,uuid,uuid,text,text,jsonb,jsonb,bigint,bigint,text[]),e10.save_market_query_cursor(uuid,uuid,uuid,text,text,jsonb,text,bigint,bigint),e10.reject_market_query_state_update()to service_role;
end $$;

comment on table public.e10_market_query_contexts is'Bounded, expiring server-side parent query state. Maximum 100 live contexts per actor and organization, 100000 cohort keys, 15-minute lifetime.';
comment on table public.e10_market_query_cursors is'Opaque, bounded, expiring server-side cursor positions. Maximum 1000 live cursors per actor and organization, 15-minute lifetime.';
