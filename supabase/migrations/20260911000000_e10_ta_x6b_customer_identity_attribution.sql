-- TA-X6b customer identity and attribution history. No posted spend or automatic matching.

create table public.e10_customer_mutation_receipts (
  organization_id uuid not null references public.e10_organizations(id), idempotency_key text not null,
  operation text not null check(operation in ('create','update','identity','attribution')),
  entity_id uuid not null, request_fingerprint text not null check(btrim(request_fingerprint)<>''),
  result jsonb not null check(jsonb_typeof(result)='object'), created_by uuid references auth.users(id), created_at timestamptz not null default now(),
  primary key(organization_id,idempotency_key)
);

create table public.e10_customer_identity_decisions (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.e10_organizations(id),
  customer_id uuid not null, identity_kind text not null check(identity_kind in ('channel_account','alias')),
  channel text, external_account_id text, alias_text text, identity_action text not null check(identity_action in ('attach','detach')),
  verification_basis text not null check(verification_basis in ('operator_review','verified_handle')),
  verified_user_id uuid references auth.users(id) on delete set null,
  viewer_handle_claim_id uuid references public.e10_viewer_handle_claims(id),
  identity_stream_key text generated always as (case
    when identity_kind='alias' then customer_id::text||'|alias|'||lower(btrim(alias_text))
    when lower(btrim(channel))='whatnot' then 'channel|whatnot|'||lower(btrim(regexp_replace(external_account_id,'^@','')))
    else 'channel|'||lower(btrim(channel))||'|'||btrim(external_account_id) end) stored,
  supersedes_decision_id uuid, reason text not null check(btrim(reason)<>''), evidence jsonb not null default '{}' check(jsonb_typeof(evidence)='object'),
  idempotency_key text not null check(btrim(idempotency_key)<>''), request_fingerprint text not null check(btrim(request_fingerprint)<>''),
  created_by uuid references auth.users(id), decided_at timestamptz not null default now(),
  unique(organization_id,id), unique(organization_id,idempotency_key),
  foreign key(organization_id,customer_id) references public.e10_customers(organization_id,id),
  foreign key(organization_id,supersedes_decision_id) references public.e10_customer_identity_decisions(organization_id,id),
  check((identity_kind='channel_account' and channel is not null and btrim(channel)<>'' and external_account_id is not null and btrim(external_account_id)<>'' and alias_text is null)
     or (identity_kind='alias' and alias_text is not null and btrim(alias_text)<>'' and channel is null and external_account_id is null)),
  check((verification_basis='verified_handle' and identity_kind='channel_account' and lower(channel)='whatnot' and viewer_handle_claim_id is not null and verified_user_id is not null)
     or (verification_basis='operator_review' and viewer_handle_claim_id is null and verified_user_id is null))
);
create index e10_customer_identity_stream_idx on public.e10_customer_identity_decisions(organization_id,identity_stream_key,decided_at desc,id desc);
create unique index e10_customer_identity_successor_uq on public.e10_customer_identity_decisions(organization_id,supersedes_decision_id)
  where supersedes_decision_id is not null;
create unique index e10_customer_identity_root_uq on public.e10_customer_identity_decisions(organization_id,identity_stream_key)
  where supersedes_decision_id is null;

create table public.e10_customer_activity_attribution_decisions (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.e10_organizations(id),
  activity_observation_id uuid not null, customer_id uuid, decision_action text not null check(decision_action in ('attribute','unattribute')),
  supersedes_decision_id uuid, reason text not null check(btrim(reason)<>''), evidence jsonb not null default '{}' check(jsonb_typeof(evidence)='object'),
  idempotency_key text not null check(btrim(idempotency_key)<>''), request_fingerprint text not null check(btrim(request_fingerprint)<>''),
  created_by uuid references auth.users(id), decided_at timestamptz not null default now(),
  unique(organization_id,id), unique(organization_id,idempotency_key),
  foreign key(organization_id,activity_observation_id) references public.e10_customer_activity_observations(organization_id,id),
  foreign key(organization_id,customer_id) references public.e10_customers(organization_id,id),
  foreign key(organization_id,supersedes_decision_id) references public.e10_customer_activity_attribution_decisions(organization_id,id),
  check((decision_action='attribute' and customer_id is not null) or (decision_action='unattribute' and customer_id is null))
);
create index e10_customer_activity_attribution_stream_idx on public.e10_customer_activity_attribution_decisions(organization_id,activity_observation_id,decided_at desc,id desc);
create unique index e10_customer_activity_attribution_successor_uq on public.e10_customer_activity_attribution_decisions(organization_id,supersedes_decision_id)
  where supersedes_decision_id is not null;
create unique index e10_customer_activity_attribution_root_uq on public.e10_customer_activity_attribution_decisions(organization_id,activity_observation_id)
  where supersedes_decision_id is null;

alter table public.e10_customer_mutation_receipts enable row level security;
alter table public.e10_customer_identity_decisions enable row level security;
alter table public.e10_customer_activity_attribution_decisions enable row level security;
revoke all on public.e10_customer_mutation_receipts,public.e10_customer_identity_decisions,public.e10_customer_activity_attribution_decisions from public,anon,authenticated;
grant all on public.e10_customer_mutation_receipts,public.e10_customer_identity_decisions,public.e10_customer_activity_attribution_decisions to service_role;
create trigger e10_customer_mutation_receipts_append_only_trg before update or delete on public.e10_customer_mutation_receipts for each row execute function e10.reject_append_only_change();
create trigger e10_customer_identity_append_only_trg before update or delete on public.e10_customer_identity_decisions for each row execute function e10.reject_append_only_change();
create trigger e10_customer_attribution_append_only_trg before update or delete on public.e10_customer_activity_attribution_decisions for each row execute function e10.reject_append_only_change();

create view public.e10_current_customer_identities with (security_invoker=true) as
select d.id,d.organization_id,d.customer_id,d.identity_kind,d.channel,d.external_account_id,d.alias_text,d.identity_stream_key,d.identity_action,d.verification_basis,d.verified_user_id,d.viewer_handle_claim_id,d.decided_at
from public.e10_customer_identity_decisions d
where not exists(select 1 from public.e10_customer_identity_decisions successor
  where successor.organization_id=d.organization_id and successor.supersedes_decision_id=d.id);
create view public.e10_current_customer_activity_attributions with (security_invoker=true) as
select d.id,d.organization_id,d.activity_observation_id,d.customer_id,d.decision_action,d.decided_at
from public.e10_customer_activity_attribution_decisions d
where not exists(select 1 from public.e10_customer_activity_attribution_decisions successor
  where successor.organization_id=d.organization_id and successor.supersedes_decision_id=d.id);
revoke all on public.e10_current_customer_identities,public.e10_current_customer_activity_attributions from public,anon,authenticated;
grant select on public.e10_current_customer_identities,public.e10_current_customer_activity_attributions to service_role;

-- The customer auth_user_id column is a searchable projection, never verification authority. Recheck
-- the immutable identity decision and canonical claim on every new activity so later claim revocation
-- cannot leave cached verified status. Per ADR 0005, expires_at governs pending verification only.
create function e10.enforce_customer_activity_identity() returns trigger language plpgsql security definer set search_path=public as $$
begin
  if new.customer_id is null then new.buyer_identity_status:='unresolved';
  elsif new.buyer_user_id is not null and exists(
    select 1 from public.e10_current_customer_identities i join public.e10_viewer_handle_claims h on h.id=i.viewer_handle_claim_id
    where i.organization_id=new.organization_id and i.customer_id=new.customer_id and i.identity_action='attach'
      and i.verification_basis='verified_handle' and i.verified_user_id=new.buyer_user_id and h.user_id=new.buyer_user_id and h.status='verified'
  ) then new.buyer_identity_status:='verified_auth';
  else new.buyer_identity_status:='reviewed_attributed'; end if;
  return new;
end $$;
revoke all on function e10.enforce_customer_activity_identity() from public,anon,authenticated;
grant execute on function e10.enforce_customer_activity_identity() to service_role;
create trigger e10_customer_activity_identity_trg before insert on public.e10_customer_activity_observations
  for each row execute function e10.enforce_customer_activity_identity();

create function public.e10_org_create_customer(p_org uuid,p_display_name text,p_idempotency_key text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_fp text; v_id uuid:=gen_random_uuid(); v_receipt record; v_result jsonb;
begin
  if not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.manage_customers') then raise exception using errcode='42501',message='manage_customer_denied'; end if;
  if p_idempotency_key is null or btrim(p_idempotency_key)='' or p_display_name is null or btrim(p_display_name)='' then raise exception using errcode='22004',message='customer_identity_required'; end if;
  v_fp:=md5(jsonb_build_object('v','customer-create-v1','display_name',btrim(p_display_name))::text);
  perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|customer-mutation|'||p_idempotency_key,0));
  select request_fingerprint,result into v_receipt from public.e10_customer_mutation_receipts where organization_id=p_org and idempotency_key=p_idempotency_key;
  if found then if v_receipt.request_fingerprint<>v_fp then raise exception using errcode='22023',message='idempotency_key_mismatch'; end if; return v_receipt.result||'{"replay":true}'::jsonb; end if;
  insert into public.e10_customers(id,organization_id,display_name,created_by) values(v_id,p_org,btrim(p_display_name),auth.uid());
  v_result:=jsonb_build_object('ok',true,'replay',false,'customer_id',v_id,'revision',0);
  insert into public.e10_customer_mutation_receipts values(p_org,p_idempotency_key,'create',v_id,v_fp,v_result,auth.uid(),now());
  return v_result;
end $$;

create function public.e10_org_update_customer(p_org uuid,p_customer_id uuid,p_expected_revision bigint,p_display_name text,p_status text,p_idempotency_key text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_fp text; v_receipt record; v_result jsonb; v_revision bigint;
begin
  if not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.manage_customers') then raise exception using errcode='42501',message='manage_customer_denied'; end if;
  if p_idempotency_key is null or btrim(p_idempotency_key)='' or p_expected_revision is null or p_expected_revision<0 or p_display_name is null or btrim(p_display_name)='' or p_status not in ('active','archived') then raise exception using errcode='22023',message='customer_update_invalid'; end if;
  v_fp:=md5(jsonb_build_object('v','customer-update-v1','customer',p_customer_id,'expected_revision',p_expected_revision,'display_name',btrim(p_display_name),'status',p_status)::text);
  perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|customer-mutation|'||p_idempotency_key,0));
  select request_fingerprint,result into v_receipt from public.e10_customer_mutation_receipts where organization_id=p_org and idempotency_key=p_idempotency_key;
  if found then if v_receipt.request_fingerprint<>v_fp then raise exception using errcode='22023',message='idempotency_key_mismatch'; end if; return v_receipt.result||'{"replay":true}'::jsonb; end if;
  update public.e10_customers set display_name=btrim(p_display_name),status=p_status,revision=revision+1,updated_at=now()
    where organization_id=p_org and id=p_customer_id and revision=p_expected_revision returning revision into v_revision;
  if not found then
    if exists(select 1 from public.e10_customers where organization_id=p_org and id=p_customer_id) then raise exception using errcode='40001',message='customer_revision_conflict'; end if;
    raise exception using errcode='42501',message='customer_denied';
  end if;
  v_result:=jsonb_build_object('ok',true,'replay',false,'customer_id',p_customer_id,'revision',v_revision,'status',p_status);
  insert into public.e10_customer_mutation_receipts values(p_org,p_idempotency_key,'update',p_customer_id,v_fp,v_result,auth.uid(),now());
  return v_result;
end $$;

create function public.e10_org_decide_customer_identity(
  p_org uuid,p_customer_id uuid,p_identity_kind text,p_channel text,p_external_account_id text,p_alias_text text,
  p_identity_action text,p_viewer_handle_claim_id uuid,p_reason text,p_evidence jsonb,p_idempotency_key text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_fp text; v_key text; v_prior record; v_receipt record; v_id uuid:=gen_random_uuid(); v_verified_user uuid; v_current_verified_user uuid; v_basis text:='operator_review'; v_result jsonb;
begin
  if not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.manage_customers') then raise exception using errcode='42501',message='manage_customer_identity_denied'; end if;
  if p_idempotency_key is null or btrim(p_idempotency_key)='' or p_reason is null or btrim(p_reason)='' or p_evidence is null or jsonb_typeof(p_evidence)<>'object' or octet_length(p_evidence::text)>65536 then raise exception using errcode='22023',message='identity_decision_invalid'; end if;
  if p_identity_kind='channel_account' and p_channel is not null and btrim(p_channel)<>'' and p_external_account_id is not null and btrim(p_external_account_id)<>'' and p_alias_text is null then null;
  elsif p_identity_kind='alias' and p_alias_text is not null and btrim(p_alias_text)<>'' and p_channel is null and p_external_account_id is null and p_viewer_handle_claim_id is null then null;
  else raise exception using errcode='22023',message='identity_shape_invalid'; end if;
  if p_identity_action not in ('attach','detach') then raise exception using errcode='22023',message='identity_action_invalid'; end if;
  v_key:=case when p_identity_kind='alias' then p_customer_id::text||'|alias|'||lower(btrim(p_alias_text))
    when lower(btrim(p_channel))='whatnot' then 'channel|whatnot|'||lower(btrim(regexp_replace(p_external_account_id,'^@','')))
    else 'channel|'||lower(btrim(p_channel))||'|'||btrim(p_external_account_id) end;
  v_fp:=md5(jsonb_build_object('v','customer-identity-v1','customer',p_customer_id,'key',v_key,'action',p_identity_action,'claim',p_viewer_handle_claim_id,'reason',p_reason,'evidence',p_evidence)::text);
  perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|customer-identity|'||v_key,0));
  select request_fingerprint,result into v_receipt from public.e10_customer_mutation_receipts where organization_id=p_org and idempotency_key=p_idempotency_key;
  if found then if v_receipt.request_fingerprint<>v_fp then raise exception using errcode='22023',message='idempotency_key_mismatch'; end if; return v_receipt.result||'{"replay":true}'::jsonb; end if;
  perform 1 from public.e10_customers where organization_id=p_org and id=p_customer_id and status='active' for update;
  if not found then raise exception using errcode='42501',message='identity_customer_denied'; end if;
  select * into v_prior from public.e10_current_customer_identities where organization_id=p_org and identity_stream_key=v_key;
  if p_identity_action='attach' and found and v_prior.identity_action='attach' then raise exception using errcode='22023',message='identity_already_attached'; end if;
  if p_identity_action='detach' and (not found or v_prior.identity_action='detach' or v_prior.customer_id<>p_customer_id) then raise exception using errcode='22023',message='identity_not_attached_to_customer'; end if;
  if p_viewer_handle_claim_id is not null then
    if p_identity_kind<>'channel_account' or lower(btrim(p_channel))<>'whatnot' then raise exception using errcode='22023',message='verified_claim_channel_invalid'; end if;
    select user_id into v_verified_user from public.e10_viewer_handle_claims where id=p_viewer_handle_claim_id and status='verified' and handle_norm=lower(btrim(regexp_replace(p_external_account_id,'^@','')));
    if not found then raise exception using errcode='42501',message='verified_handle_claim_denied'; end if;
    v_basis:='verified_handle';
  end if;
  insert into public.e10_customer_identity_decisions(id,organization_id,customer_id,identity_kind,channel,external_account_id,alias_text,identity_action,verification_basis,verified_user_id,viewer_handle_claim_id,supersedes_decision_id,reason,evidence,idempotency_key,request_fingerprint,created_by)
  values(v_id,p_org,p_customer_id,p_identity_kind,nullif(btrim(p_channel),''),nullif(btrim(p_external_account_id),''),nullif(btrim(p_alias_text),''),p_identity_action,v_basis,v_verified_user,p_viewer_handle_claim_id,v_prior.id,btrim(p_reason),p_evidence,p_idempotency_key,v_fp,auth.uid());
  if v_basis='verified_handle' and p_identity_action='attach' then
    update public.e10_customers set auth_user_id=v_verified_user,revision=revision+1,updated_at=now() where organization_id=p_org and id=p_customer_id and (auth_user_id is null or auth_user_id=v_verified_user);
    if not found then raise exception using errcode='23505',message='customer_auth_link_conflict'; end if;
  end if;
  if p_identity_action='detach' then
    select i.verified_user_id into v_current_verified_user from public.e10_current_customer_identities i
      where i.organization_id=p_org and i.customer_id=p_customer_id and i.identity_action='attach'
        and i.verification_basis='verified_handle' and i.verified_user_id is not null order by i.decided_at desc,i.id desc limit 1;
    update public.e10_customers set auth_user_id=v_current_verified_user,revision=revision+1,updated_at=now()
      where organization_id=p_org and id=p_customer_id and auth_user_id is distinct from v_current_verified_user;
  end if;
  v_result:=jsonb_build_object('ok',true,'replay',false,'decision_id',v_id,'customer_id',p_customer_id,'action',p_identity_action,'verification_basis',v_basis);
  insert into public.e10_customer_mutation_receipts values(p_org,p_idempotency_key,'identity',v_id,v_fp,v_result,auth.uid(),now());
  return v_result;
end $$;

create function public.e10_org_attribute_customer_activity(p_org uuid,p_activity_id uuid,p_customer_id uuid,p_reason text,p_evidence jsonb,p_idempotency_key text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_fp text; v_prior record; v_receipt record; v_id uuid:=gen_random_uuid(); v_action text; v_result jsonb;
begin
  if not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.manage_customers') then raise exception using errcode='42501',message='attribute_customer_activity_denied'; end if;
  if p_idempotency_key is null or btrim(p_idempotency_key)='' or p_reason is null or btrim(p_reason)='' or p_evidence is null or jsonb_typeof(p_evidence)<>'object' or octet_length(p_evidence::text)>65536 then raise exception using errcode='22023',message='attribution_decision_invalid'; end if;
  v_action:=case when p_customer_id is null then 'unattribute' else 'attribute' end;
  v_fp:=md5(jsonb_build_object('v','activity-attribution-v1','activity',p_activity_id,'customer',p_customer_id,'reason',p_reason,'evidence',p_evidence)::text);
  perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|activity-attribution|'||p_activity_id::text,0));
  select request_fingerprint,result into v_receipt from public.e10_customer_mutation_receipts where organization_id=p_org and idempotency_key=p_idempotency_key;
  if found then if v_receipt.request_fingerprint<>v_fp then raise exception using errcode='22023',message='idempotency_key_mismatch'; end if; return v_receipt.result||'{"replay":true}'::jsonb; end if;
  if not exists(select 1 from public.e10_customer_activity_observations where organization_id=p_org and id=p_activity_id) then raise exception using errcode='42501',message='activity_denied'; end if;
  if p_customer_id is not null and not exists(select 1 from public.e10_customers where organization_id=p_org and id=p_customer_id and status='active') then raise exception using errcode='42501',message='attribution_customer_denied'; end if;
  select * into v_prior from public.e10_current_customer_activity_attributions where organization_id=p_org and activity_observation_id=p_activity_id;
  if found and v_prior.customer_id is not distinct from p_customer_id then raise exception using errcode='22023',message='attribution_unchanged'; end if;
  insert into public.e10_customer_activity_attribution_decisions(id,organization_id,activity_observation_id,customer_id,decision_action,supersedes_decision_id,reason,evidence,idempotency_key,request_fingerprint,created_by)
  values(v_id,p_org,p_activity_id,p_customer_id,v_action,v_prior.id,btrim(p_reason),p_evidence,p_idempotency_key,v_fp,auth.uid());
  v_result:=jsonb_build_object('ok',true,'replay',false,'decision_id',v_id,'activity_id',p_activity_id,'customer_id',p_customer_id,'action',v_action,'revenue_changed',false);
  insert into public.e10_customer_mutation_receipts values(p_org,p_idempotency_key,'attribution',v_id,v_fp,v_result,auth.uid(),now());
  return v_result;
end $$;

create function public.e10_org_find_customers(p_org uuid,p_query text,p_limit integer default 25)
returns table(customer_id uuid,display_name text,status text,matched_identity_kind text,matched_channel text,matched_value text)
language plpgsql stable security definer set search_path=public as $$
begin
  if not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.manage_customers') then raise exception using errcode='42501',message='find_customers_denied'; end if;
  if p_query is null or length(btrim(p_query))<2 or p_limit is null or p_limit<1 or p_limit>100 then raise exception using errcode='22023',message='customer_query_invalid'; end if;
  return query
  select c.id,c.display_name,c.status,m.identity_kind,m.channel,coalesce(m.external_account_id,m.alias_text)
  from public.e10_customers c
  left join lateral (
    select i.identity_kind,i.channel,i.external_account_id,i.alias_text from public.e10_current_customer_identities i
    where i.organization_id=c.organization_id and i.customer_id=c.id and i.identity_action='attach'
      and lower(coalesce(i.external_account_id,i.alias_text,'')) like '%'||lower(btrim(p_query))||'%'
    order by i.decided_at desc,i.id desc limit 1
  ) m on true
  where c.organization_id=p_org and c.status<>'merged' and (lower(c.display_name) like '%'||lower(btrim(p_query))||'%' or m.identity_kind is not null)
  order by lower(c.display_name),c.id limit p_limit;
end $$;

revoke all on function public.e10_org_create_customer(uuid,text,text) from public,anon;
revoke all on function public.e10_org_update_customer(uuid,uuid,bigint,text,text,text) from public,anon;
revoke all on function public.e10_org_decide_customer_identity(uuid,uuid,text,text,text,text,text,uuid,text,jsonb,text) from public,anon;
revoke all on function public.e10_org_attribute_customer_activity(uuid,uuid,uuid,text,jsonb,text) from public,anon;
revoke all on function public.e10_org_find_customers(uuid,text,integer) from public,anon;
grant execute on function public.e10_org_create_customer(uuid,text,text),public.e10_org_update_customer(uuid,uuid,bigint,text,text,text),public.e10_org_decide_customer_identity(uuid,uuid,text,text,text,text,text,uuid,text,jsonb,text),public.e10_org_attribute_customer_activity(uuid,uuid,uuid,text,jsonb,text),public.e10_org_find_customers(uuid,text,integer) to authenticated,service_role;

comment on table public.e10_customer_identity_decisions is 'Immutable reviewed channel-account and alias association history; no name/address auto-match.';
comment on table public.e10_customer_activity_attribution_decisions is 'Immutable reviewed attribution history. Decisions never rewrite source activity or change revenue.';
