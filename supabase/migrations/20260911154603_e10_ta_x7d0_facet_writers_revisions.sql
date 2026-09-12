-- TA-X7d.0b catalog/tenant market revisions and reviewed facet writers.

create table public.e10_market_catalog_revision(
  singleton boolean primary key default true check(singleton),
  revision bigint not null default 1 check(revision>0),
  changed_at timestamptz not null default clock_timestamp()
);
insert into public.e10_market_catalog_revision(singleton) values(true);

create table public.e10_market_org_revisions(
  organization_id uuid primary key references public.e10_organizations(id) on delete cascade,
  revision bigint not null default 1 check(revision>0),
  changed_at timestamptz not null default clock_timestamp()
);
insert into public.e10_market_org_revisions(organization_id)
select id from public.e10_organizations on conflict do nothing;

alter table public.e10_market_catalog_revision enable row level security;
alter table public.e10_market_org_revisions enable row level security;
revoke all on public.e10_market_catalog_revision,public.e10_market_org_revisions from public,anon,authenticated;
grant all on public.e10_market_catalog_revision,public.e10_market_org_revisions to service_role;

create function e10.bump_market_catalog_revision() returns trigger
language plpgsql security definer set search_path=public as $$
begin
  update public.e10_market_catalog_revision
  set revision=revision+1,changed_at=clock_timestamp() where singleton;
  return case when tg_op='DELETE' then old else new end;
end $$;
create function e10.bump_market_org_revision() returns trigger
language plpgsql security definer set search_path=public as $$
declare v_org uuid;
begin
  v_org:=case when tg_op='DELETE' then old.organization_id else new.organization_id end;
  insert into public.e10_market_org_revisions(organization_id,revision,changed_at)
  values(v_org,1,clock_timestamp()) on conflict(organization_id) do update
  set revision=public.e10_market_org_revisions.revision+1,changed_at=excluded.changed_at;
  return case when tg_op='DELETE' then old else new end;
end $$;
create function e10.initialize_market_org_revision() returns trigger
language plpgsql security definer set search_path=public as $$
begin
  insert into public.e10_market_org_revisions(organization_id) values(new.id) on conflict do nothing;
  return new;
end $$;
revoke all on function e10.bump_market_catalog_revision(),e10.bump_market_org_revision(),e10.initialize_market_org_revision() from public,anon,authenticated;
grant execute on function e10.bump_market_catalog_revision(),e10.bump_market_org_revision(),e10.initialize_market_org_revision() to service_role;

create trigger e10_market_org_revision_init after insert on public.e10_organizations
for each row execute function e10.initialize_market_org_revision();
do $$declare t text;begin
  foreach t in array array['e10_catalog_facet_term_keys','e10_catalog_facet_taxonomy_terms','e10_catalog_facet_taxonomy_aliases','e10_catalog_variant_facet_decisions','e10_catalog_releases','e10_catalog_variants','e10_catalog_variant_subjects'] loop
    execute format('create trigger %I after insert or update or delete on public.%I for each row execute function e10.bump_market_catalog_revision()',t||'_market_revision',t);
  end loop;
end $$;
create trigger e10_org_catalog_variant_facet_market_revision
after insert on public.e10_org_catalog_variant_facet_overrides
for each row execute function e10.bump_market_org_revision();

create function public.e10_platform_review_catalog_facet_term(
  p_term_key uuid,p_expected_revision bigint,p_namespace text,p_canonical_name text,
  p_action text,p_reason text,p_evidence jsonb,p_idempotency_key text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_actor uuid:=auth.uid();v_key uuid:=p_term_key;v_prior record;v_prior_id uuid;v_replay record;
  v_id uuid:=gen_random_uuid();v_fp text;
begin
  if v_actor is null or not e10.is_platform_admin() then raise exception using errcode='42501',message='platform_catalog_curation_denied';end if;
  if p_expected_revision is null or p_expected_revision<0 or p_namespace is null or p_namespace not in('color_family','finish_family')
    or p_canonical_name is null or length(btrim(p_canonical_name)) not between 1 and 100
    or p_action is null or p_action not in('assert','revoke') or p_reason is null or length(btrim(p_reason)) not between 1 and 2000
    or p_evidence is null or jsonb_typeof(p_evidence)<>'object' or octet_length(p_evidence::text)>65536
    or p_idempotency_key is null or length(btrim(p_idempotency_key)) not between 1 and 500 then
    raise exception using errcode='22023',message='catalog_facet_term_review_invalid';end if;
  v_fp:=md5(jsonb_build_object('v','catalog-facet-term-v1','key',p_term_key,'expected',p_expected_revision,'namespace',p_namespace,'name',btrim(p_canonical_name),'action',p_action,'reason',btrim(p_reason),'evidence',p_evidence)::text);
  perform pg_advisory_xact_lock(hashtextextended('catalog-facet-term-idempotency|'||p_idempotency_key,0));
  if auth.uid() is distinct from v_actor or not e10.is_platform_admin() then raise exception using errcode='42501',message='platform_catalog_curation_denied';end if;
  select * into v_replay from public.e10_catalog_facet_taxonomy_terms where idempotency_key=p_idempotency_key;
  if found then if v_replay.request_fingerprint<>v_fp then raise exception using errcode='22023',message='idempotency_key_mismatch';end if;
    return jsonb_build_object('ok',true,'replay',true,'term_key',v_replay.term_key,'revision',v_replay.revision,'action',v_replay.action);end if;
  perform pg_advisory_xact_lock(hashtextextended('catalog-facet-term|'||coalesce(p_term_key::text,p_namespace||'|'||lower(btrim(p_canonical_name))),0));
  perform revision from public.e10_market_catalog_revision where singleton for update;
  if auth.uid() is distinct from v_actor or not e10.is_platform_admin() then raise exception using errcode='42501',message='platform_catalog_curation_denied';end if;
  if v_key is null then
    if p_expected_revision<>0 or p_action<>'assert' then raise exception using errcode='22023',message='catalog_facet_term_transition_invalid';end if;
    if exists(select 1 from public.e10_catalog_facet_taxonomy_terms where namespace=p_namespace and lower(btrim(canonical_name))=lower(btrim(p_canonical_name)) and supersedes_term_id is null) then raise exception using errcode='23505',message='catalog_facet_term_exists';end if;
    insert into public.e10_catalog_facet_term_keys(namespace) values(p_namespace) returning id into v_key;
  else
    select * into v_prior from public.e10_current_catalog_facet_taxonomy_terms where term_key=v_key;
    if not found or v_prior.namespace<>p_namespace or v_prior.canonical_name<>btrim(p_canonical_name) then raise exception using errcode='22023',message='catalog_facet_term_key_invalid';end if;
    if v_prior.revision<>p_expected_revision then raise exception using errcode='40001',message='catalog_facet_term_revision_conflict';end if;v_prior_id:=v_prior.id;
  end if;
  insert into public.e10_catalog_facet_taxonomy_terms(id,term_key,namespace,canonical_name,revision,action,supersedes_term_id,reason,evidence,idempotency_key,request_fingerprint,reviewed_by)
  values(v_id,v_key,p_namespace,btrim(p_canonical_name),p_expected_revision+1,p_action,v_prior_id,btrim(p_reason),p_evidence,p_idempotency_key,v_fp,v_actor);
  return jsonb_build_object('ok',true,'replay',false,'term_key',v_key,'decision_id',v_id,'revision',p_expected_revision+1,'action',p_action);
end $$;
revoke all on function public.e10_platform_review_catalog_facet_term(uuid,bigint,text,text,text,text,jsonb,text) from public,anon;
grant execute on function public.e10_platform_review_catalog_facet_term(uuid,bigint,text,text,text,text,jsonb,text) to authenticated,service_role;

create function public.e10_platform_review_catalog_facet_alias(
  p_alias_key uuid,p_expected_revision bigint,p_namespace text,p_alias text,p_action text,
  p_term_key uuid,p_reason text,p_evidence jsonb,p_idempotency_key text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_actor uuid:=auth.uid();v_key uuid:=coalesce(p_alias_key,gen_random_uuid());v_prior record;v_prior_id uuid;v_replay record;v_id uuid:=gen_random_uuid();v_fp text;
begin
  if v_actor is null or not e10.is_platform_admin() then raise exception using errcode='42501',message='platform_catalog_curation_denied';end if;
  if p_expected_revision is null or p_expected_revision<0 or p_namespace is null or p_namespace not in('color_family','finish_family') or p_alias is null or length(btrim(p_alias)) not between 1 and 100
    or p_action is null or p_action not in('assert','revoke') or ((p_action='assert')<>(p_term_key is not null))
    or p_reason is null or length(btrim(p_reason)) not between 1 and 2000 or p_evidence is null or jsonb_typeof(p_evidence)<>'object' or octet_length(p_evidence::text)>65536
    or p_idempotency_key is null or length(btrim(p_idempotency_key)) not between 1 and 500 then raise exception using errcode='22023',message='catalog_facet_alias_review_invalid';end if;
  v_fp:=md5(jsonb_build_object('v','catalog-facet-alias-v1','key',p_alias_key,'expected',p_expected_revision,'namespace',p_namespace,'alias',btrim(p_alias),'action',p_action,'term',p_term_key,'reason',btrim(p_reason),'evidence',p_evidence)::text);
  perform pg_advisory_xact_lock(hashtextextended('catalog-facet-alias-idempotency|'||p_idempotency_key,0));
  if auth.uid() is distinct from v_actor or not e10.is_platform_admin() then raise exception using errcode='42501',message='platform_catalog_curation_denied';end if;
  select * into v_replay from public.e10_catalog_facet_taxonomy_aliases where idempotency_key=p_idempotency_key;
  if found then if v_replay.request_fingerprint<>v_fp then raise exception using errcode='22023',message='idempotency_key_mismatch';end if;return jsonb_build_object('ok',true,'replay',true,'alias_key',v_replay.alias_key,'revision',v_replay.revision);end if;
  perform pg_advisory_xact_lock(hashtextextended('catalog-facet-alias|'||coalesce(p_alias_key::text,p_namespace||'|'||lower(btrim(p_alias))),0));
  perform revision from public.e10_market_catalog_revision where singleton for update;
  if auth.uid() is distinct from v_actor or not e10.is_platform_admin() then raise exception using errcode='42501',message='platform_catalog_curation_denied';end if;
  if p_alias_key is null then if p_expected_revision<>0 or p_action<>'assert' then raise exception using errcode='22023',message='catalog_facet_alias_transition_invalid';end if;
  else select * into v_prior from public.e10_catalog_facet_taxonomy_aliases a where a.alias_key=p_alias_key and not exists(select 1 from public.e10_catalog_facet_taxonomy_aliases n where n.supersedes_alias_id=a.id);
    if not found or v_prior.namespace<>p_namespace or v_prior.alias<>btrim(p_alias) then raise exception using errcode='22023',message='catalog_facet_alias_key_invalid';end if;if v_prior.revision<>p_expected_revision then raise exception using errcode='40001',message='catalog_facet_alias_revision_conflict';end if;v_prior_id:=v_prior.id;end if;
  insert into public.e10_catalog_facet_taxonomy_aliases(id,alias_key,namespace,alias,term_key,revision,action,supersedes_alias_id,reason,evidence,idempotency_key,request_fingerprint,reviewed_by)
  values(v_id,v_key,p_namespace,btrim(p_alias),p_term_key,p_expected_revision+1,p_action,v_prior_id,btrim(p_reason),p_evidence,p_idempotency_key,v_fp,v_actor);
  return jsonb_build_object('ok',true,'replay',false,'alias_key',v_key,'decision_id',v_id,'revision',p_expected_revision+1,'action',p_action);
end $$;
revoke all on function public.e10_platform_review_catalog_facet_alias(uuid,bigint,text,text,text,uuid,text,jsonb,text) from public,anon;
grant execute on function public.e10_platform_review_catalog_facet_alias(uuid,bigint,text,text,text,uuid,text,jsonb,text) to authenticated,service_role;

create function public.e10_platform_review_catalog_variant_facet(
  p_decision_key uuid,p_variant_id uuid,p_subject_id uuid,p_facet_key text,p_expected_revision bigint,p_action text,
  p_boolean_value boolean,p_integer_value integer,p_term_key uuid,p_reason text,p_evidence jsonb,p_idempotency_key text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_actor uuid:=auth.uid();v_key uuid:=coalesce(p_decision_key,gen_random_uuid());v_prior record;v_prior_id uuid;v_replay record;v_id uuid:=gen_random_uuid();v_fp text;
begin
  if v_actor is null or not e10.is_platform_admin() then raise exception using errcode='42501',message='platform_catalog_curation_denied';end if;
  if p_variant_id is null or p_expected_revision is null or p_expected_revision<0 or p_facet_key is null or p_facet_key not in('rookie_designation','rookie_season','color_family','finish_family') or p_action is null or p_action not in('assert','revoke')
    or p_reason is null or length(btrim(p_reason)) not between 1 and 2000 or p_evidence is null or jsonb_typeof(p_evidence)<>'object' or octet_length(p_evidence::text)>65536 or p_idempotency_key is null or length(btrim(p_idempotency_key)) not between 1 and 500 then raise exception using errcode='22023',message='catalog_variant_facet_review_invalid';end if;
  v_fp:=md5(jsonb_build_object('v','catalog-variant-facet-v1','key',p_decision_key,'variant',p_variant_id,'subject',p_subject_id,'facet',p_facet_key,'expected',p_expected_revision,'action',p_action,'bool',p_boolean_value,'integer',p_integer_value,'term',p_term_key,'reason',btrim(p_reason),'evidence',p_evidence)::text);
  perform pg_advisory_xact_lock(hashtextextended('catalog-variant-facet-idempotency|'||p_idempotency_key,0));
  if auth.uid() is distinct from v_actor or not e10.is_platform_admin() then raise exception using errcode='42501',message='platform_catalog_curation_denied';end if;
  select * into v_replay from public.e10_catalog_variant_facet_decisions where idempotency_key=p_idempotency_key;
  if found then if v_replay.request_fingerprint<>v_fp then raise exception using errcode='22023',message='idempotency_key_mismatch';end if;return jsonb_build_object('ok',true,'replay',true,'decision_key',v_replay.decision_key,'revision',v_replay.revision);end if;
  perform pg_advisory_xact_lock(hashtextextended('catalog-variant-facet|'||p_variant_id::text||'|'||coalesce(p_subject_id::text,'')||'|'||p_facet_key,0));
  perform revision from public.e10_market_catalog_revision where singleton for update;
  if auth.uid() is distinct from v_actor or not e10.is_platform_admin() then raise exception using errcode='42501',message='platform_catalog_curation_denied';end if;
  select * into v_prior from public.e10_catalog_variant_facet_decisions d where d.variant_id=p_variant_id and d.subject_id is not distinct from p_subject_id and d.facet_key=p_facet_key and not exists(select 1 from public.e10_catalog_variant_facet_decisions n where n.supersedes_decision_id=d.id);
  if p_decision_key is null then if found or p_expected_revision<>0 or p_action<>'assert' then raise exception using errcode='22023',message='catalog_variant_facet_transition_invalid';end if;
  else if not found or v_prior.decision_key<>p_decision_key then raise exception using errcode='22023',message='catalog_variant_facet_key_invalid';end if;if v_prior.revision<>p_expected_revision then raise exception using errcode='40001',message='catalog_variant_facet_revision_conflict';end if;v_prior_id:=v_prior.id;end if;
  insert into public.e10_catalog_variant_facet_decisions(id,decision_key,variant_id,subject_id,facet_key,revision,action,boolean_value,integer_value,term_key,supersedes_decision_id,reason,evidence,idempotency_key,request_fingerprint,reviewed_by)
  values(v_id,v_key,p_variant_id,p_subject_id,p_facet_key,p_expected_revision+1,p_action,p_boolean_value,p_integer_value,p_term_key,v_prior_id,btrim(p_reason),p_evidence,p_idempotency_key,v_fp,v_actor);
  return jsonb_build_object('ok',true,'replay',false,'decision_key',v_key,'decision_id',v_id,'revision',p_expected_revision+1,'action',p_action);
end $$;
revoke all on function public.e10_platform_review_catalog_variant_facet(uuid,uuid,uuid,text,bigint,text,boolean,integer,uuid,text,jsonb,text) from public,anon;
grant execute on function public.e10_platform_review_catalog_variant_facet(uuid,uuid,uuid,text,bigint,text,boolean,integer,uuid,text,jsonb,text) to authenticated,service_role;

create function public.e10_org_review_catalog_variant_facet_override(
  p_org uuid,p_decision_key uuid,p_variant_id uuid,p_subject_id uuid,p_facet_key text,p_expected_revision bigint,p_action text,
  p_boolean_value boolean,p_integer_value integer,p_term_key uuid,p_reason text,p_evidence jsonb,p_idempotency_key text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_actor uuid:=auth.uid();v_key uuid:=coalesce(p_decision_key,gen_random_uuid());v_prior record;v_prior_id uuid;v_replay record;v_id uuid:=gen_random_uuid();v_fp text;
begin
  if v_actor is null or not exists(select 1 from public.e10_organizations where id=p_org and status='active') or not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.curate_market_analytics') then raise exception using errcode='42501',message='market_facet_curation_denied';end if;
  if p_org is null or p_variant_id is null or p_expected_revision is null or p_expected_revision<0 or p_facet_key is null or p_facet_key not in('rookie_designation','rookie_season','color_family','finish_family') or p_action is null or p_action not in('assert','mask','clear')
    or p_reason is null or length(btrim(p_reason)) not between 1 and 2000 or p_evidence is null or jsonb_typeof(p_evidence)<>'object' or octet_length(p_evidence::text)>65536 or p_idempotency_key is null or length(btrim(p_idempotency_key)) not between 1 and 500 then raise exception using errcode='22023',message='market_facet_override_review_invalid';end if;
  v_fp:=md5(jsonb_build_object('v','org-catalog-variant-facet-v1','org',p_org,'key',p_decision_key,'variant',p_variant_id,'subject',p_subject_id,'facet',p_facet_key,'expected',p_expected_revision,'action',p_action,'bool',p_boolean_value,'integer',p_integer_value,'term',p_term_key,'reason',btrim(p_reason),'evidence',p_evidence)::text);
  perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|market-facet-idempotency|'||p_idempotency_key,0));
  if auth.uid() is distinct from v_actor or not exists(select 1 from public.e10_organizations where id=p_org and status='active') or not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.curate_market_analytics') then raise exception using errcode='42501',message='market_facet_curation_denied';end if;
  select * into v_replay from public.e10_org_catalog_variant_facet_overrides where organization_id=p_org and idempotency_key=p_idempotency_key;
  if found then if v_replay.request_fingerprint<>v_fp then raise exception using errcode='22023',message='idempotency_key_mismatch';end if;return jsonb_build_object('ok',true,'replay',true,'decision_key',v_replay.decision_key,'revision',v_replay.revision,'action',v_replay.action);end if;
  perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|market-facet|'||p_variant_id::text||'|'||coalesce(p_subject_id::text,'')||'|'||p_facet_key,0));
  perform revision from public.e10_market_org_revisions where organization_id=p_org for update;
  if auth.uid() is distinct from v_actor or not exists(select 1 from public.e10_organizations where id=p_org and status='active') or not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.curate_market_analytics') then raise exception using errcode='42501',message='market_facet_curation_denied';end if;
  select * into v_prior from public.e10_org_catalog_variant_facet_overrides d where d.organization_id=p_org and d.variant_id=p_variant_id and d.subject_id is not distinct from p_subject_id and d.facet_key=p_facet_key and not exists(select 1 from public.e10_org_catalog_variant_facet_overrides n where n.organization_id=d.organization_id and n.supersedes_decision_id=d.id);
  if p_decision_key is null then if found or p_expected_revision<>0 or p_action not in('assert','mask') then raise exception using errcode='22023',message='market_facet_override_transition_invalid';end if;
  else if not found or v_prior.decision_key<>p_decision_key then raise exception using errcode='22023',message='market_facet_override_key_invalid';end if;if v_prior.revision<>p_expected_revision then raise exception using errcode='40001',message='market_facet_override_revision_conflict';end if;v_prior_id:=v_prior.id;end if;
  insert into public.e10_org_catalog_variant_facet_overrides(id,organization_id,decision_key,variant_id,subject_id,facet_key,revision,action,boolean_value,integer_value,term_key,supersedes_decision_id,reason,evidence,idempotency_key,request_fingerprint,reviewed_by)
  values(v_id,p_org,v_key,p_variant_id,p_subject_id,p_facet_key,p_expected_revision+1,p_action,p_boolean_value,p_integer_value,p_term_key,v_prior_id,btrim(p_reason),p_evidence,p_idempotency_key,v_fp,v_actor);
  return jsonb_build_object('ok',true,'replay',false,'decision_key',v_key,'decision_id',v_id,'revision',p_expected_revision+1,'action',p_action);
end $$;
revoke all on function public.e10_org_review_catalog_variant_facet_override(uuid,uuid,uuid,uuid,text,bigint,text,boolean,integer,uuid,text,jsonb,text) from public,anon;
grant execute on function public.e10_org_review_catalog_variant_facet_override(uuid,uuid,uuid,uuid,text,bigint,text,boolean,integer,uuid,text,jsonb,text) to authenticated,service_role;

comment on function public.e10_org_review_catalog_variant_facet_override(uuid,uuid,uuid,uuid,text,bigint,text,boolean,integer,uuid,text,jsonb,text) is
  'Tenant-private reviewed facet override. Reserved capability act.curate_market_analytics has no default grant.';
