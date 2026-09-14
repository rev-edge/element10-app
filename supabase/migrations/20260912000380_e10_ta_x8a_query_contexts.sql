-- TA-X8a.1 explicit actor/org query contexts. Query metadata only.

create table public.e10_query_contexts(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.e10_organizations(id) on delete cascade,
 actor_id uuid not null references auth.users(id) on delete cascade,
 purpose text not null check(purpose in('workspace','export','assistant')),
 created_at timestamptz not null,
 expires_at timestamptz not null,
 revoked_at timestamptz,
 revoked_by uuid references auth.users(id),
 unique(organization_id,id),
 check(expires_at>created_at and expires_at<=created_at+interval'24 hours'),
 check((revoked_at is null)=(revoked_by is null))
);
create index e10_query_context_actor_expiry_idx on public.e10_query_contexts(organization_id,actor_id,expires_at,id);

create table public.e10_query_context_commands(
 organization_id uuid not null references public.e10_organizations(id) on delete cascade,
 actor_id uuid not null references auth.users(id) on delete cascade,
 idempotency_key text not null check(length(btrim(idempotency_key))between 1 and 200),
 command_type text not null check(command_type in('create','revoke')),
 context_id uuid not null,
 request_fingerprint text not null check(request_fingerprint~'^[0-9a-f]{64}$'),
 result jsonb not null check(jsonb_typeof(result)='object'and octet_length(result::text)<=8192),
 created_at timestamptz not null default statement_timestamp(),
 primary key(organization_id,actor_id,idempotency_key),
 foreign key(organization_id,context_id) references public.e10_query_contexts(organization_id,id) on delete cascade
);
create index e10_query_context_commands_context_idx on public.e10_query_context_commands(organization_id,context_id,created_at);

alter table public.e10_query_contexts enable row level security;
alter table public.e10_query_context_commands enable row level security;
revoke all on public.e10_query_contexts,public.e10_query_context_commands from public,anon,authenticated,service_role;
grant select,insert,update on public.e10_query_contexts to service_role;
grant select,insert on public.e10_query_context_commands to service_role;

create function e10.reject_query_context_command_change()returns trigger language plpgsql security definer set search_path=public as $$
begin if tg_op='DELETE'and(current_setting('e10.query_context_retention_purge',true)='on'or pg_trigger_depth()>1)then return old;end if;raise exception using errcode='55000',message='query_context_command_immutable';end $$;
create trigger e10_query_context_commands_immutable before update or delete on public.e10_query_context_commands for each row execute function e10.reject_query_context_command_change();

create function e10.x8_query_context_actor(p_org uuid,p_context uuid,p_lock boolean default false)
returns uuid language plpgsql volatile security definer set search_path=public as $$
declare a uuid:=auth.uid();c record;n timestamptz;
begin
 if a is null or p_org is null or p_context is null or not exists(select 1 from public.e10_organizations o where o.id=p_org and o.status='active')or not e10.is_org_member(p_org)then raise exception using errcode='42501',message='query_context_denied';end if;
 if p_lock then
  select q.actor_id,q.expires_at,q.revoked_at into c from public.e10_query_contexts q where q.organization_id=p_org and q.id=p_context for update;
 else
  select q.actor_id,q.expires_at,q.revoked_at into c from public.e10_query_contexts q where q.organization_id=p_org and q.id=p_context for share;
 end if;
 n:=clock_timestamp();
 if not found or c.actor_id is distinct from a or c.revoked_at is not null or c.expires_at<=n or auth.uid()is distinct from a or not exists(select 1 from public.e10_organizations o where o.id=p_org and o.status='active')or not e10.is_org_member(p_org)then raise exception using errcode='42501',message='query_context_denied';end if;
 return a;
end $$;

create function public.e10_org_create_query_context(p_org uuid,p_purpose text,p_lifetime_seconds integer,p_idempotency_key text)
returns jsonb language plpgsql volatile security definer set search_path=public as $$
declare a uuid:=auth.uid();fp text;old record;n timestamptz;cid uuid:=gen_random_uuid();r jsonb;
begin
 if a is null or p_org is null or not exists(select 1 from public.e10_organizations o where o.id=p_org and o.status='active')or not e10.is_org_member(p_org)then raise exception using errcode='42501',message='query_context_create_denied';end if;
 if p_purpose is null or p_purpose not in('workspace','export','assistant')or p_lifetime_seconds is null or p_lifetime_seconds not between 60 and 86400 or p_idempotency_key is null or length(btrim(p_idempotency_key))not between 1 and 200 then raise exception using errcode='22023',message='query_context_request_invalid';end if;
 fp:=encode(sha256(convert_to(jsonb_build_object('v','x8-query-context-v1','org',p_org,'actor',a,'purpose',p_purpose,'lifetime_seconds',p_lifetime_seconds)::text,'UTF8')),'hex');
 perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|'||a::text||'|x8-query-context|'||btrim(p_idempotency_key),0));
 select command_type,request_fingerprint,result into old from public.e10_query_context_commands where organization_id=p_org and actor_id=a and idempotency_key=btrim(p_idempotency_key);
 if found then if old.command_type<>'create'or old.request_fingerprint<>fp then raise exception using errcode='22023',message='query_context_idempotency_mismatch';end if;if auth.uid()is distinct from a or not exists(select 1 from public.e10_organizations o where o.id=p_org and o.status='active')or not e10.is_org_member(p_org)then raise exception using errcode='42501',message='query_context_create_denied';end if;return old.result||jsonb_build_object('replay',true);end if;
 perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|'||a::text||'|x8-query-context-cap',0));
 if(select count(*)from public.e10_query_contexts q where q.organization_id=p_org and q.actor_id=a and q.revoked_at is null and q.expires_at>clock_timestamp())>=100 then raise exception using errcode='54000',message='query_context_live_limit';end if;
 if auth.uid()is distinct from a or not exists(select 1 from public.e10_organizations o where o.id=p_org and o.status='active')or not e10.is_org_member(p_org)then raise exception using errcode='42501',message='query_context_create_denied';end if;
 n:=clock_timestamp();insert into public.e10_query_contexts(id,organization_id,actor_id,purpose,created_at,expires_at)values(cid,p_org,a,p_purpose,n,n+make_interval(secs=>p_lifetime_seconds));
 r:=jsonb_build_object('ok',true,'replay',false,'context_id',cid,'organization_id',p_org,'purpose',p_purpose,'created_at',n,'expires_at',n+make_interval(secs=>p_lifetime_seconds));
 insert into public.e10_query_context_commands(organization_id,actor_id,idempotency_key,command_type,context_id,request_fingerprint,result)values(p_org,a,btrim(p_idempotency_key),'create',cid,fp,r);
 return r;
end $$;

create function public.e10_org_revoke_query_context(p_org uuid,p_context_id uuid,p_idempotency_key text)
returns jsonb language plpgsql volatile security definer set search_path=public as $$
declare a uuid:=auth.uid();fp text;old record;c record;n timestamptz;r jsonb;
begin
 if a is null or p_org is null or p_context_id is null or not exists(select 1 from public.e10_organizations o where o.id=p_org and o.status='active')or not e10.is_org_member(p_org)then raise exception using errcode='42501',message='query_context_revoke_denied';end if;
 if p_idempotency_key is null or length(btrim(p_idempotency_key))not between 1 and 200 then raise exception using errcode='22023',message='query_context_request_invalid';end if;
 fp:=encode(sha256(convert_to(jsonb_build_object('v','x8-query-context-revoke-v1','org',p_org,'actor',a,'context',p_context_id)::text,'UTF8')),'hex');
 perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|'||a::text||'|x8-query-context|'||btrim(p_idempotency_key),0));
 select command_type,request_fingerprint,result into old from public.e10_query_context_commands where organization_id=p_org and actor_id=a and idempotency_key=btrim(p_idempotency_key);
 if found then if old.command_type<>'revoke'or old.request_fingerprint<>fp then raise exception using errcode='22023',message='query_context_idempotency_mismatch';end if;if auth.uid()is distinct from a or not exists(select 1 from public.e10_organizations o where o.id=p_org and o.status='active')or not e10.is_org_member(p_org)then raise exception using errcode='42501',message='query_context_revoke_denied';end if;return old.result||jsonb_build_object('replay',true);end if;
 select q.actor_id,q.revoked_at into c from public.e10_query_contexts q where q.organization_id=p_org and q.id=p_context_id for update;
 if not found or(c.actor_id is distinct from a and not e10.is_org_admin(p_org))or c.revoked_at is not null or auth.uid()is distinct from a or not exists(select 1 from public.e10_organizations o where o.id=p_org and o.status='active')or not e10.is_org_member(p_org)then raise exception using errcode='42501',message='query_context_revoke_denied';end if;
 n:=clock_timestamp();update public.e10_query_contexts set revoked_at=n,revoked_by=a where organization_id=p_org and id=p_context_id;
 r:=jsonb_build_object('ok',true,'replay',false,'context_id',p_context_id,'organization_id',p_org,'revoked_at',n,'revoked_by',a);
 insert into public.e10_query_context_commands(organization_id,actor_id,idempotency_key,command_type,context_id,request_fingerprint,result)values(p_org,a,btrim(p_idempotency_key),'revoke',p_context_id,fp,r);
 return r;
end $$;

create function e10.purge_query_contexts(p_limit integer default 1000)
returns integer language plpgsql volatile security definer set search_path=public as $$
declare n integer;
begin
 if p_limit is null or p_limit not between 1 and 1000 then raise exception using errcode='22023',message='query_context_purge_limit_invalid';end if;
 perform set_config('e10.query_context_retention_purge','on',true);
 with victims as(select q.id from public.e10_query_contexts q where coalesce(q.revoked_at,q.expires_at)<clock_timestamp()-interval'30 days'order by coalesce(q.revoked_at,q.expires_at),q.id for update skip locked limit p_limit),d as(delete from public.e10_query_contexts q using victims v where q.id=v.id returning 1)select count(*)into n from d;
 perform set_config('e10.query_context_retention_purge','off',true);return n;
end $$;

revoke all on function e10.reject_query_context_command_change(),e10.x8_query_context_actor(uuid,uuid,boolean),e10.purge_query_contexts(integer)from public,anon,authenticated;
grant execute on function e10.reject_query_context_command_change(),e10.x8_query_context_actor(uuid,uuid,boolean),e10.purge_query_contexts(integer)to service_role;
revoke all on function public.e10_org_create_query_context(uuid,text,integer,text),public.e10_org_revoke_query_context(uuid,uuid,text)from public,anon;
grant execute on function public.e10_org_create_query_context(uuid,text,integer,text),public.e10_org_revoke_query_context(uuid,uuid,text)to authenticated,service_role;

comment on table public.e10_query_contexts is'X8 actor/org-bound query-control metadata only. No query result cache.';
comment on table public.e10_query_context_commands is'Immutable X8 query-context create/revoke idempotency evidence.';
