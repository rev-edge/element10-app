-- TA-X6e reviewed customer whole-record merge/unmerge. Source evidence and spend remain immutable.

alter table public.e10_customer_mutation_receipts drop constraint e10_customer_mutation_receipts_operation_check;
alter table public.e10_customer_mutation_receipts add constraint e10_customer_mutation_receipts_operation_check
  check(operation in ('create','update','identity','attribution','resolution'));

-- Duplicate customer records may legitimately project the same verified account before review.
-- Effective-component guards below replace this cache-level uniqueness with authoritative identity validation.
drop index public.e10_customers_org_auth_user_uq;
create index e10_customers_org_auth_user_idx on public.e10_customers(organization_id,auth_user_id)
  where auth_user_id is not null and status='active';

create table public.e10_customer_resolution_decisions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.e10_organizations(id),
  source_customer_id uuid not null,
  revision integer not null check(revision>0),
  action text not null check(action in ('merge','split')),
  target_customer_id uuid,
  source_customer_revision bigint not null check(source_customer_revision>=0),
  target_customer_revision bigint,
  review_basis text not null check(review_basis in ('operator_review','channel_identity')),
  identity_decision_ids uuid[] not null default '{}' check(cardinality(identity_decision_ids)<=32),
  supersedes_decision_id uuid,
  reason text not null check(length(btrim(reason)) between 1 and 2000),
  evidence jsonb not null check(jsonb_typeof(evidence)='object' and octet_length(evidence::text)<=65536),
  idempotency_key text not null check(length(btrim(idempotency_key)) between 1 and 500),
  request_fingerprint text not null check(btrim(request_fingerprint)<>''),
  decided_by uuid references auth.users(id),
  decided_at timestamptz not null default now(),
  unique(organization_id,id),
  unique(organization_id,source_customer_id,revision),
  unique(organization_id,idempotency_key),
  foreign key(organization_id,source_customer_id) references public.e10_customers(organization_id,id),
  foreign key(organization_id,target_customer_id) references public.e10_customers(organization_id,id),
  foreign key(organization_id,supersedes_decision_id) references public.e10_customer_resolution_decisions(organization_id,id),
  check((action='merge' and target_customer_id is not null and target_customer_id<>source_customer_id and target_customer_revision is not null)
     or (action='split' and target_customer_id is null and target_customer_revision is null))
);
create unique index e10_customer_resolution_root_uq on public.e10_customer_resolution_decisions(organization_id,source_customer_id)
  where supersedes_decision_id is null;
create unique index e10_customer_resolution_successor_uq on public.e10_customer_resolution_decisions(organization_id,supersedes_decision_id)
  where supersedes_decision_id is not null;
create index e10_customer_resolution_target_idx on public.e10_customer_resolution_decisions(organization_id,target_customer_id,source_customer_id)
  where action='merge';

alter table public.e10_customer_resolution_decisions enable row level security;
revoke all on public.e10_customer_resolution_decisions from public,anon,authenticated;
grant all on public.e10_customer_resolution_decisions to service_role;
create trigger e10_customer_resolution_append_only_trg before update or delete on public.e10_customer_resolution_decisions
  for each row execute function e10.reject_append_only_change();

create view public.e10_current_customer_resolutions with (security_invoker=true) as
select d.* from public.e10_customer_resolution_decisions d
where not exists(select 1 from public.e10_customer_resolution_decisions s
  where s.organization_id=d.organization_id and s.supersedes_decision_id=d.id);
revoke all on public.e10_current_customer_resolutions from public,anon,authenticated;
grant select on public.e10_current_customer_resolutions to service_role;

create function e10.customer_effective_id(p_org uuid,p_customer uuid) returns uuid
language plpgsql stable security definer set search_path=public as $$
declare v_current uuid:=p_customer;v_next uuid;v_seen uuid[]:=array[p_customer];v_depth integer:=0;
begin
  if p_org is null or p_customer is null then return null;end if;
  if not exists(select 1 from public.e10_customers where organization_id=p_org and id=p_customer) then return null;end if;
  loop
    select target_customer_id into v_next from public.e10_current_customer_resolutions
      where organization_id=p_org and source_customer_id=v_current and action='merge';
    if not found then return v_current;end if;
    v_depth:=v_depth+1;
    if v_depth>32 or v_next=any(v_seen) then raise exception using errcode='54001',message='customer_resolution_graph_invalid';end if;
    v_seen:=array_append(v_seen,v_next);v_current:=v_next;
  end loop;
end $$;
revoke all on function e10.customer_effective_id(uuid,uuid) from public,anon,authenticated;
grant execute on function e10.customer_effective_id(uuid,uuid) to service_role;

create view public.e10_current_effective_customer_identities with (security_invoker=true) as
select i.*,e10.customer_effective_id(i.organization_id,i.customer_id) effective_customer_id
from public.e10_current_customer_identities i;
revoke all on public.e10_current_effective_customer_identities from public,anon,authenticated;
grant select on public.e10_current_effective_customer_identities to service_role;

create function e10.guard_customer_resolution_archive() returns trigger
language plpgsql security definer set search_path=public as $$
begin
  if new.status='archived' and old.status<>'archived' and exists(
    select 1 from public.e10_current_customer_resolutions r where r.organization_id=old.organization_id and r.action='merge' and (r.source_customer_id=old.id or r.target_customer_id=old.id)
  ) then
    raise exception using errcode='22023',message='customer_resolution_participant_cannot_archive';
  end if;
  return new;
end $$;
revoke all on function e10.guard_customer_resolution_archive() from public,anon,authenticated;
grant execute on function e10.guard_customer_resolution_archive() to service_role;
create trigger e10_customer_resolution_archive_guard_trg before update on public.e10_customers
  for each row execute function e10.guard_customer_resolution_archive();

create function e10.guard_customer_identity_resolution() returns trigger
language plpgsql security definer set search_path=public as $$
declare v_effective uuid;v_other_verified integer;
begin
  if not exists(select 1 from public.e10_customers where organization_id=new.organization_id and id=new.customer_id and status='active') then
    raise exception using errcode='42501',message='identity_customer_not_active_terminal';
  end if;
  v_effective:=e10.customer_effective_id(new.organization_id,new.customer_id);
  if new.identity_action='attach' and v_effective<>new.customer_id then raise exception using errcode='42501',message='identity_customer_not_active_terminal';end if;
  if new.identity_action='attach' and new.verification_basis='verified_handle' and new.verified_user_id is not null then
    select count(distinct i.verified_user_id) into v_other_verified
    from public.e10_current_effective_customer_identities i join public.e10_viewer_handle_claims h on h.id=i.viewer_handle_claim_id
    where i.organization_id=new.organization_id and i.effective_customer_id=v_effective and i.identity_action='attach'
      and i.verification_basis='verified_handle' and i.verified_user_id is distinct from new.verified_user_id and h.status='verified';
    if v_other_verified>0 then raise exception using errcode='22023',message='customer_effective_verified_identity_conflict';end if;
  end if;
  return new;
end $$;
revoke all on function e10.guard_customer_identity_resolution() from public,anon,authenticated;
grant execute on function e10.guard_customer_identity_resolution() to service_role;
create trigger e10_customer_identity_resolution_guard_trg before insert on public.e10_customer_identity_decisions
  for each row execute function e10.guard_customer_identity_resolution();

-- Preserve the public signatures while enforcing topology-first lock order around the X6b writers.
alter function public.e10_org_update_customer(uuid,uuid,bigint,text,text,text) rename to e10_org_update_customer_x6b_impl;
revoke all on function public.e10_org_update_customer_x6b_impl(uuid,uuid,bigint,text,text,text) from public,anon,authenticated;
create function public.e10_org_update_customer(p_org uuid,p_customer_id uuid,p_expected_revision bigint,p_display_name text,p_status text,p_idempotency_key text)
returns jsonb language plpgsql security definer set search_path=public as $$
begin
  if not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.manage_customers') then raise exception using errcode='42501',message='manage_customer_denied';end if;
  perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|customer-resolution-topology',0));
  return public.e10_org_update_customer_x6b_impl(p_org,p_customer_id,p_expected_revision,p_display_name,p_status,p_idempotency_key);
end $$;
revoke all on function public.e10_org_update_customer(uuid,uuid,bigint,text,text,text) from public,anon;
grant execute on function public.e10_org_update_customer(uuid,uuid,bigint,text,text,text) to authenticated,service_role;

alter function public.e10_org_decide_customer_identity(uuid,uuid,text,text,text,text,text,uuid,text,jsonb,text) rename to e10_org_decide_customer_identity_x6b_impl;
revoke all on function public.e10_org_decide_customer_identity_x6b_impl(uuid,uuid,text,text,text,text,text,uuid,text,jsonb,text) from public,anon,authenticated;
create function public.e10_org_decide_customer_identity(
  p_org uuid,p_customer_id uuid,p_identity_kind text,p_channel text,p_external_account_id text,p_alias_text text,
  p_identity_action text,p_viewer_handle_claim_id uuid,p_reason text,p_evidence jsonb,p_idempotency_key text
) returns jsonb language plpgsql security definer set search_path=public as $$
begin
  if not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.manage_customers') then raise exception using errcode='42501',message='manage_customer_identity_denied';end if;
  perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|customer-resolution-topology',0));
  return public.e10_org_decide_customer_identity_x6b_impl(p_org,p_customer_id,p_identity_kind,p_channel,p_external_account_id,p_alias_text,p_identity_action,p_viewer_handle_claim_id,p_reason,p_evidence,p_idempotency_key);
end $$;
revoke all on function public.e10_org_decide_customer_identity(uuid,uuid,text,text,text,text,text,uuid,text,jsonb,text) from public,anon;
grant execute on function public.e10_org_decide_customer_identity(uuid,uuid,text,text,text,text,text,uuid,text,jsonb,text) to authenticated,service_role;

create or replace function e10.enforce_customer_activity_identity() returns trigger language plpgsql security definer set search_path=public as $$
begin
  if new.customer_id is not null and e10.customer_effective_id(new.organization_id,new.customer_id)<>new.customer_id then
    raise exception using errcode='22023',message='customer_activity_requires_effective_customer';
  end if;
  if new.customer_id is null then new.buyer_identity_status:='unresolved';
  elsif new.buyer_user_id is not null and exists(
    select 1 from public.e10_current_effective_customer_identities i join public.e10_viewer_handle_claims h on h.id=i.viewer_handle_claim_id
    where i.organization_id=new.organization_id and i.effective_customer_id=new.customer_id and i.identity_action='attach'
      and i.verification_basis='verified_handle' and i.verified_user_id=new.buyer_user_id and h.user_id=new.buyer_user_id and h.status='verified'
  ) then new.buyer_identity_status:='verified_auth';
  else new.buyer_identity_status:='reviewed_attributed';end if;
  return new;
end $$;

create function e10.guard_customer_draft_effective_customer() returns trigger language plpgsql security definer set search_path=public as $$
begin
  if new.customer_id is not null and e10.customer_effective_id(new.organization_id,new.customer_id)<>new.customer_id then
    raise exception using errcode='22023',message='customer_draft_requires_effective_customer';
  end if;
  return new;
end $$;
revoke all on function e10.guard_customer_draft_effective_customer() from public,anon,authenticated;
grant execute on function e10.guard_customer_draft_effective_customer() to service_role;
create trigger e10_customer_draft_effective_customer_trg before insert on public.e10_customer_transaction_draft_revisions
  for each row execute function e10.guard_customer_draft_effective_customer();

create function public.e10_org_decide_customer_resolution(
  p_org uuid,p_source_customer_id uuid,p_target_customer_id uuid,
  p_expected_source_revision bigint,p_expected_target_revision bigint,p_expected_resolution_revision integer,
  p_action text,p_review_basis text,p_identity_decision_ids uuid[],p_reason text,p_evidence jsonb,p_idempotency_key text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_fp text;v_receipt record;v_source record;v_target record;v_prior record;v_id uuid:=gen_random_uuid();v_result jsonb;v_verified_count integer;v_cited_count integer;v_components integer;v_depth integer;
begin
  if not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.merge_customers') then raise exception using errcode='42501',message='customer_resolution_denied';end if;
  if p_expected_source_revision is null or p_expected_source_revision<0 or p_expected_resolution_revision is null or p_expected_resolution_revision<0
    or p_action not in ('merge','split') or p_review_basis not in ('operator_review','channel_identity')
    or p_identity_decision_ids is null or cardinality(p_identity_decision_ids)>32
    or p_reason is null or length(btrim(p_reason)) not between 1 and 2000
    or p_evidence is null or jsonb_typeof(p_evidence)<>'object' or octet_length(p_evidence::text)>65536
    or p_idempotency_key is null or length(btrim(p_idempotency_key)) not between 1 and 500 then
    raise exception using errcode='22023',message='customer_resolution_invalid';end if;
  if (p_action='merge' and (p_target_customer_id is null or p_target_customer_id=p_source_customer_id or p_expected_target_revision is null or p_expected_target_revision<0))
    or (p_action='split' and (p_target_customer_id is not null or p_expected_target_revision is not null)) then
    raise exception using errcode='22023',message='customer_resolution_shape_invalid';end if;
  if cardinality(p_identity_decision_ids)<>(select count(distinct x) from unnest(p_identity_decision_ids)x) then raise exception using errcode='22023',message='customer_resolution_duplicate_identity_citation';end if;
  v_fp:=md5(jsonb_build_object('v','customer-resolution-v1','source',p_source_customer_id,'target',p_target_customer_id,'source_revision',p_expected_source_revision,'target_revision',p_expected_target_revision,'resolution_revision',p_expected_resolution_revision,'action',p_action,'basis',p_review_basis,'identities',p_identity_decision_ids,'reason',btrim(p_reason),'evidence',p_evidence)::text);
  perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|customer-resolution-topology',0));
  if not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.merge_customers') then raise exception using errcode='42501',message='customer_resolution_denied';end if;
  perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|customer-mutation|'||p_idempotency_key,0));
  select request_fingerprint,result into v_receipt from public.e10_customer_mutation_receipts where organization_id=p_org and idempotency_key=p_idempotency_key;
  if found then if v_receipt.request_fingerprint<>v_fp then raise exception using errcode='22023',message='idempotency_key_mismatch';end if;return v_receipt.result||'{"replay":true}'::jsonb;end if;
  perform 1 from public.e10_customers where organization_id=p_org and id=any(array_remove(array[p_source_customer_id,p_target_customer_id],null)) order by id for update;
  select * into v_source from public.e10_customers where organization_id=p_org and id=p_source_customer_id;
  if not found then raise exception using errcode='42501',message='customer_resolution_source_denied';end if;
  if v_source.revision<>p_expected_source_revision then raise exception using errcode='40001',message='customer_resolution_customer_revision_conflict';end if;
  select * into v_prior from public.e10_current_customer_resolutions where organization_id=p_org and source_customer_id=p_source_customer_id;
  if coalesce(v_prior.revision,0)<>p_expected_resolution_revision then raise exception using errcode='40001',message='customer_resolution_revision_conflict';end if;
  if p_action='merge' then
    select * into v_target from public.e10_customers where organization_id=p_org and id=p_target_customer_id;
    if not found then raise exception using errcode='42501',message='customer_resolution_target_denied';end if;
    if v_source.status<>'active' or v_target.status<>'active' then raise exception using errcode='22023',message='customer_resolution_requires_active_customers';end if;
    if v_target.revision<>p_expected_target_revision then raise exception using errcode='40001',message='customer_resolution_customer_revision_conflict';end if;
    if v_prior.id is not null and v_prior.action='merge' then raise exception using errcode='22023',message='customer_already_merged';end if;
    if e10.customer_effective_id(p_org,p_target_customer_id)<>p_target_customer_id then raise exception using errcode='22023',message='customer_resolution_target_not_terminal';end if;
    with recursive incoming(id,depth,path) as (
      select p_source_customer_id,0,array[p_source_customer_id]
      union all
      select r.source_customer_id,i.depth+1,array_append(i.path,r.source_customer_id)
      from incoming i join public.e10_current_customer_resolutions r on r.organization_id=p_org and r.target_customer_id=i.id and r.action='merge'
      where i.depth<32 and not r.source_customer_id=any(i.path)
    ) select coalesce(max(depth),0) into v_depth from incoming;
    if v_depth+1>32 then raise exception using errcode='54001',message='customer_resolution_depth_exceeded';end if;
    if p_review_basis='channel_identity' then
      select count(*),count(distinct e10.customer_effective_id(i.organization_id,i.customer_id)) into v_cited_count,v_components
      from public.e10_current_customer_identities i where i.organization_id=p_org and i.id=any(p_identity_decision_ids)
        and i.identity_kind='channel_account' and i.identity_action='attach'
        and e10.customer_effective_id(i.organization_id,i.customer_id) in (p_source_customer_id,p_target_customer_id);
      if v_cited_count<>cardinality(p_identity_decision_ids) or v_cited_count<2 or v_components<>2 then raise exception using errcode='22023',message='customer_resolution_channel_evidence_invalid';end if;
    elsif cardinality(p_identity_decision_ids)>0 and exists(
      select 1 from unnest(p_identity_decision_ids)x where not exists(select 1 from public.e10_current_customer_identities i where i.organization_id=p_org and i.id=x and i.identity_kind='channel_account' and i.identity_action='attach' and e10.customer_effective_id(i.organization_id,i.customer_id) in (p_source_customer_id,p_target_customer_id))
    ) then raise exception using errcode='22023',message='customer_resolution_identity_citation_invalid';end if;
    select count(distinct i.verified_user_id) into v_verified_count
    from public.e10_current_effective_customer_identities i join public.e10_viewer_handle_claims h on h.id=i.viewer_handle_claim_id
    where i.organization_id=p_org and i.effective_customer_id in (p_source_customer_id,p_target_customer_id)
      and i.identity_action='attach' and i.verification_basis='verified_handle' and i.verified_user_id is not null and h.status='verified';
    if v_verified_count>1 then raise exception using errcode='22023',message='customer_resolution_verified_identity_conflict';end if;
  else
    if v_source.status<>'active' or v_prior.id is null or v_prior.action<>'merge' then raise exception using errcode='22023',message='customer_not_currently_merged';end if;
  end if;
  insert into public.e10_customer_resolution_decisions(id,organization_id,source_customer_id,revision,action,target_customer_id,source_customer_revision,target_customer_revision,review_basis,identity_decision_ids,supersedes_decision_id,reason,evidence,idempotency_key,request_fingerprint,decided_by)
  values(v_id,p_org,p_source_customer_id,p_expected_resolution_revision+1,p_action,p_target_customer_id,p_expected_source_revision,p_expected_target_revision,p_review_basis,p_identity_decision_ids,v_prior.id,btrim(p_reason),p_evidence,p_idempotency_key,v_fp,auth.uid());
  v_result:=jsonb_build_object('ok',true,'replay',false,'decision_id',v_id,'source_customer_id',p_source_customer_id,'target_customer_id',p_target_customer_id,'revision',p_expected_resolution_revision+1,'source_revision',p_expected_source_revision,'action',p_action,'effective_customer_id',case when p_action='merge' then p_target_customer_id else p_source_customer_id end,'source_rows_rewritten',false,'revenue_changed',false);
  insert into public.e10_customer_mutation_receipts values(p_org,p_idempotency_key,'resolution',v_id,v_fp,v_result,auth.uid(),now());
  return v_result;
end $$;

create function public.e10_org_list_customer_resolution_history(p_org uuid,p_source_customer_id uuid,p_limit integer default 25,p_before_revision integer default null)
returns table(decision_id uuid,revision integer,action text,target_customer_id uuid,review_basis text,identity_decision_ids uuid[],reason text,evidence jsonb,decided_by uuid,decided_at timestamptz)
language plpgsql stable security definer set search_path=public as $$
begin
  if not e10.is_org_member(p_org) or not (e10.has_org_cap(p_org,'act.manage_customers') or e10.has_org_cap(p_org,'act.merge_customers')) then raise exception using errcode='42501',message='customer_resolution_history_denied';end if;
  if p_limit is null or p_limit<1 or p_limit>100 or (p_before_revision is not null and p_before_revision<1) then raise exception using errcode='22023',message='customer_resolution_page_invalid';end if;
  return query select d.id,d.revision,d.action,d.target_customer_id,d.review_basis,d.identity_decision_ids,d.reason,d.evidence,d.decided_by,d.decided_at
    from public.e10_customer_resolution_decisions d where d.organization_id=p_org and d.source_customer_id=p_source_customer_id and (p_before_revision is null or d.revision<p_before_revision)
    order by d.revision desc limit p_limit;
end $$;

create function public.e10_org_resolve_customers(p_org uuid,p_customer_ids uuid[])
returns table(customer_id uuid,effective_customer_id uuid)
language plpgsql stable security definer set search_path=public as $$
begin
  if not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.manage_customers') then raise exception using errcode='42501',message='resolve_customers_denied';end if;
  if p_customer_ids is null or cardinality(p_customer_ids)<1 or cardinality(p_customer_ids)>100 or cardinality(p_customer_ids)<>(select count(distinct x) from unnest(p_customer_ids)x) then raise exception using errcode='22023',message='resolve_customers_input_invalid';end if;
  return query select c.id,e10.customer_effective_id(p_org,c.id) from public.e10_customers c where c.organization_id=p_org and c.id=any(p_customer_ids) order by c.id;
end $$;

create or replace function public.e10_org_find_customers(p_org uuid,p_query text,p_limit integer default 25)
returns table(customer_id uuid,display_name text,status text,matched_identity_kind text,matched_channel text,matched_value text)
language plpgsql stable security definer set search_path=public as $$
begin
  if not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.manage_customers') then raise exception using errcode='42501',message='find_customers_denied';end if;
  if p_query is null or length(btrim(p_query))<2 or p_limit is null or p_limit<1 or p_limit>100 then raise exception using errcode='22023',message='customer_query_invalid';end if;
  return query
  select c.id,c.display_name,c.status,m.identity_kind,m.channel,coalesce(m.external_account_id,m.alias_text)
  from public.e10_customers c
  left join lateral(
    select i.identity_kind,i.channel,i.external_account_id,i.alias_text from public.e10_current_effective_customer_identities i
    where i.organization_id=c.organization_id and i.effective_customer_id=c.id and i.identity_action='attach'
      and lower(coalesce(i.external_account_id,i.alias_text,'')) like '%'||lower(btrim(p_query))||'%'
    order by i.decided_at desc,i.id desc limit 1
  )m on true
  where c.organization_id=p_org and c.status='active' and e10.customer_effective_id(p_org,c.id)=c.id
    and (lower(c.display_name) like '%'||lower(btrim(p_query))||'%' or m.identity_kind is not null)
  order by lower(c.display_name),c.id limit p_limit;
end $$;

revoke all on function public.e10_org_decide_customer_resolution(uuid,uuid,uuid,bigint,bigint,integer,text,text,uuid[],text,jsonb,text) from public,anon;
revoke all on function public.e10_org_list_customer_resolution_history(uuid,uuid,integer,integer) from public,anon;
revoke all on function public.e10_org_resolve_customers(uuid,uuid[]) from public,anon;
grant execute on function public.e10_org_decide_customer_resolution(uuid,uuid,uuid,bigint,bigint,integer,text,text,uuid[],text,jsonb,text),public.e10_org_list_customer_resolution_history(uuid,uuid,integer,integer),public.e10_org_resolve_customers(uuid,uuid[]) to authenticated,service_role;

comment on table public.e10_customer_resolution_decisions is 'Immutable reviewed whole-record customer merge/split history. Source identities, observations and posted transactions are never rewritten.';
