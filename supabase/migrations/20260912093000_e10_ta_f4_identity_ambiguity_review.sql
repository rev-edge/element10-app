-- Track A final F4: bounded, platform-only review of ambiguous player identity
-- proposals. This does not approve, link, merge, split, or generate candidates.

drop index public.e10_players_name_norm_uidx;
drop index public.e10_players_name_uidx;
create index e10_players_name_norm_idx on public.e10_players(name_norm,id);

create table public.e10_catalog_identity_review_cases(
  id uuid primary key default gen_random_uuid(),
  entity_kind text not null default'player'check(entity_kind='player'),
  source_namespace text not null check(length(btrim(source_namespace))between 1 and 200),
  source_key text not null check(length(btrim(source_key))between 1 and 500),
  source_display_name text not null check(length(btrim(source_display_name))between 1 and 500),
  proposer_kind text not null check(proposer_kind in('manual','model','tool')),
  proposer_name text not null check(length(btrim(proposer_name))between 1 and 200),
  proposer_version text check(proposer_version is null or length(btrim(proposer_version))between 1 and 200),
  source_evidence jsonb not null check(jsonb_typeof(source_evidence)='object'and octet_length(source_evidence::text)<=65536),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default clock_timestamp(),
  unique(source_namespace,entity_kind,source_key),
  check(proposer_kind<>'manual'or source_namespace like'manual:%'),
  check(proposer_kind='manual'or proposer_version is not null)
);
create table public.e10_catalog_identity_review_candidates(
  case_id uuid not null references public.e10_catalog_identity_review_cases(id),
  player_id uuid not null references public.e10_players(id),
  confidence_status text not null check(confidence_status in('known','unknown')),
  confidence numeric,
  evidence jsonb not null check(jsonb_typeof(evidence)='object'and octet_length(evidence::text)<=65536),
  created_at timestamptz not null default clock_timestamp(),
  primary key(case_id,player_id),
  check((confidence_status='unknown'and confidence is null)or(confidence_status='known'and confidence is not null and confidence between 0 and 1))
);
create table public.e10_catalog_identity_review_decisions(
  id uuid primary key default gen_random_uuid(),
  case_id uuid not null references public.e10_catalog_identity_review_cases(id),
  revision bigint not null check(revision>0),
  action text not null check(action in('propose','reject')),
  supersedes_decision_id uuid references public.e10_catalog_identity_review_decisions(id),
  reason text not null check(length(btrim(reason))between 1 and 2000),
  evidence jsonb not null check(jsonb_typeof(evidence)='object'and octet_length(evidence::text)<=65536),
  idempotency_key text not null check(length(btrim(idempotency_key))between 1 and 500),
  request_fingerprint text not null check(length(request_fingerprint)=64),
  reviewed_by uuid not null references auth.users(id),
  reviewed_at timestamptz not null default clock_timestamp(),
  unique(case_id,revision),unique(idempotency_key),
  check((revision=1 and action='propose'and supersedes_decision_id is null)or(revision>1 and action='reject'and supersedes_decision_id is not null))
);
create unique index e10_catalog_identity_review_decisions_successor_uq
  on public.e10_catalog_identity_review_decisions(supersedes_decision_id)
  where supersedes_decision_id is not null;
create index e10_catalog_identity_review_candidates_player_idx on public.e10_catalog_identity_review_candidates(player_id,case_id);
create index e10_catalog_identity_review_decisions_case_idx on public.e10_catalog_identity_review_decisions(case_id,revision desc);

alter table public.e10_catalog_identity_review_cases enable row level security;
alter table public.e10_catalog_identity_review_candidates enable row level security;
alter table public.e10_catalog_identity_review_decisions enable row level security;
revoke all on public.e10_catalog_identity_review_cases,public.e10_catalog_identity_review_candidates,public.e10_catalog_identity_review_decisions from public,anon,authenticated;
grant all on public.e10_catalog_identity_review_cases,public.e10_catalog_identity_review_candidates,public.e10_catalog_identity_review_decisions to service_role;
create trigger e10_catalog_identity_review_cases_append_only before update or delete on public.e10_catalog_identity_review_cases for each row execute function e10.reject_append_only_change();
create trigger e10_catalog_identity_review_candidates_append_only before update or delete on public.e10_catalog_identity_review_candidates for each row execute function e10.reject_append_only_change();
create trigger e10_catalog_identity_review_decisions_append_only before update or delete on public.e10_catalog_identity_review_decisions for each row execute function e10.reject_append_only_change();

create function public.e10_platform_propose_player_identity_review(
  p_source_namespace text,p_source_key text,p_source_display_name text,
  p_proposer_kind text,p_proposer_name text,p_proposer_version text,
  p_source_evidence jsonb,p_candidates jsonb,p_reason text,p_evidence jsonb,
  p_idempotency_key text
)returns jsonb language plpgsql security definer set search_path=public as $$
declare actor uuid:=auth.uid();fp text;replay record;existing_case record;case_id uuid:=gen_random_uuid();decision_id uuid:=gen_random_uuid();candidate jsonb;candidate_ids uuid[]:=array[]::uuid[];
begin
  if actor is null or not e10.is_platform_admin()then raise exception using errcode='42501',message='platform_identity_review_denied';end if;
  if p_source_namespace is null or length(btrim(p_source_namespace))not between 1 and 200
    or p_source_key is null or length(btrim(p_source_key))not between 1 and 500
    or p_source_display_name is null or length(btrim(p_source_display_name))not between 1 and 500
    or p_proposer_kind is null or p_proposer_kind not in('manual','model','tool')
    or p_proposer_name is null or length(btrim(p_proposer_name))not between 1 and 200
    or(p_proposer_kind='manual'and btrim(p_source_namespace)not like'manual:%')
    or(p_proposer_kind<>'manual'and(p_proposer_version is null or length(btrim(p_proposer_version))not between 1 and 200))
    or(p_proposer_version is not null and length(btrim(p_proposer_version))not between 1 and 200)
    or p_source_evidence is null or jsonb_typeof(p_source_evidence)<>'object'or octet_length(p_source_evidence::text)>65536
    or p_candidates is null or jsonb_typeof(p_candidates)<>'array'or jsonb_array_length(p_candidates)not between 2 and 20
    or p_reason is null or length(btrim(p_reason))not between 1 and 2000
    or p_evidence is null or jsonb_typeof(p_evidence)<>'object'or octet_length(p_evidence::text)>65536
    or p_idempotency_key is null or length(btrim(p_idempotency_key))not between 1 and 500 then
    raise exception using errcode='22023',message='player_identity_review_proposal_invalid';end if;
  for candidate in select value from jsonb_array_elements(p_candidates)loop
    if jsonb_typeof(candidate)<>'object'or exists(select 1 from jsonb_object_keys(candidate)k where k<>all(array['player_id','confidence_status','confidence','evidence']))
      or not(candidate?'player_id')or jsonb_typeof(candidate->'player_id')<>'string'
      or not(candidate?'confidence_status')or candidate->>'confidence_status'not in('known','unknown')
      or not(candidate?'confidence')
      or not(candidate?'evidence')or jsonb_typeof(candidate->'evidence')<>'object'or octet_length((candidate->'evidence')::text)>65536
      or(candidate->>'confidence_status'='unknown'and candidate->'confidence'<>'null'::jsonb)
      or(candidate->>'confidence_status'='known'and(jsonb_typeof(candidate->'confidence')<>'number'or(candidate->>'confidence')::numeric not between 0 and 1))then
      raise exception using errcode='22023',message='player_identity_review_candidate_invalid';end if;
    candidate_ids:=array_append(candidate_ids,(candidate->>'player_id')::uuid);
  end loop;
  if cardinality(array(select distinct x from unnest(candidate_ids)x))<>cardinality(candidate_ids)
    or exists(select 1 from unnest(candidate_ids)x where not exists(select 1 from public.e10_players p where p.id=x))then
    raise exception using errcode='22023',message='player_identity_review_candidate_invalid';end if;
  fp:=encode(sha256(convert_to(jsonb_build_object('v','player-identity-review-v1','namespace',btrim(p_source_namespace),'source_key',btrim(p_source_key),'display_name',btrim(p_source_display_name),'proposer_kind',p_proposer_kind,'proposer_name',btrim(p_proposer_name),'proposer_version',case when p_proposer_version is null then null else btrim(p_proposer_version)end,'source_evidence',p_source_evidence,'candidates',p_candidates,'reason',btrim(p_reason),'evidence',p_evidence)::text,'UTF8')),'hex');
  perform pg_advisory_xact_lock(hashtextextended('player-identity-review-idempotency|'||p_idempotency_key,0));
  if auth.uid()is distinct from actor or not e10.is_platform_admin()then raise exception using errcode='42501',message='platform_identity_review_denied';end if;
  select * into replay from public.e10_catalog_identity_review_decisions where idempotency_key=p_idempotency_key;
  if found then if replay.request_fingerprint<>fp then raise exception using errcode='22023',message='idempotency_key_mismatch';end if;
    return jsonb_build_object('ok',true,'replay',true,'case_id',replay.case_id,'decision_id',replay.id,'revision',replay.revision,'status','pending');end if;
  perform pg_advisory_xact_lock(hashtextextended('player-identity-review-source|'||btrim(p_source_namespace)||'|player|'||btrim(p_source_key),0));
  if auth.uid()is distinct from actor or not e10.is_platform_admin()then raise exception using errcode='42501',message='platform_identity_review_denied';end if;
  select * into existing_case from public.e10_catalog_identity_review_cases where source_namespace=btrim(p_source_namespace)and entity_kind='player'and source_key=btrim(p_source_key);
  if found then raise exception using errcode='23505',message='player_identity_review_source_exists';end if;
  insert into public.e10_catalog_identity_review_cases(id,source_namespace,source_key,source_display_name,proposer_kind,proposer_name,proposer_version,source_evidence,created_by)
  values(case_id,btrim(p_source_namespace),btrim(p_source_key),btrim(p_source_display_name),p_proposer_kind,btrim(p_proposer_name),case when p_proposer_version is null then null else btrim(p_proposer_version)end,p_source_evidence,actor);
  for candidate in select value from jsonb_array_elements(p_candidates)loop
    insert into public.e10_catalog_identity_review_candidates(case_id,player_id,confidence_status,confidence,evidence)
    values(case_id,(candidate->>'player_id')::uuid,candidate->>'confidence_status',case when candidate->>'confidence_status'='known'then(candidate->>'confidence')::numeric end,candidate->'evidence');
  end loop;
  insert into public.e10_catalog_identity_review_decisions(id,case_id,revision,action,reason,evidence,idempotency_key,request_fingerprint,reviewed_by)
  values(decision_id,case_id,1,'propose',btrim(p_reason),p_evidence,p_idempotency_key,fp,actor);
  return jsonb_build_object('ok',true,'replay',false,'case_id',case_id,'decision_id',decision_id,'revision',1,'status','pending');
end $$;

create function public.e10_platform_reject_player_identity_review(
  p_case_id uuid,p_expected_revision bigint,p_reason text,p_evidence jsonb,p_idempotency_key text
)returns jsonb language plpgsql security definer set search_path=public as $$
declare actor uuid:=auth.uid();fp text;replay record;prior record;decision_id uuid:=gen_random_uuid();
begin
  if actor is null or not e10.is_platform_admin()then raise exception using errcode='42501',message='platform_identity_review_denied';end if;
  if p_case_id is null or p_expected_revision is null or p_expected_revision<1
    or p_reason is null or length(btrim(p_reason))not between 1 and 2000
    or p_evidence is null or jsonb_typeof(p_evidence)<>'object'or octet_length(p_evidence::text)>65536
    or p_idempotency_key is null or length(btrim(p_idempotency_key))not between 1 and 500 then
    raise exception using errcode='22023',message='player_identity_review_rejection_invalid';end if;
  fp:=encode(sha256(convert_to(jsonb_build_object('v','player-identity-reject-v1','case',p_case_id,'expected',p_expected_revision,'reason',btrim(p_reason),'evidence',p_evidence)::text,'UTF8')),'hex');
  perform pg_advisory_xact_lock(hashtextextended('player-identity-review-idempotency|'||p_idempotency_key,0));
  if auth.uid()is distinct from actor or not e10.is_platform_admin()then raise exception using errcode='42501',message='platform_identity_review_denied';end if;
  select * into replay from public.e10_catalog_identity_review_decisions where idempotency_key=p_idempotency_key;
  if found then if replay.request_fingerprint<>fp then raise exception using errcode='22023',message='idempotency_key_mismatch';end if;
    return jsonb_build_object('ok',true,'replay',true,'case_id',replay.case_id,'decision_id',replay.id,'revision',replay.revision,'status','rejected');end if;
  perform 1 from public.e10_catalog_identity_review_cases where id=p_case_id for update;
  if not found then raise exception using errcode='22023',message='player_identity_review_case_invalid';end if;
  if auth.uid()is distinct from actor or not e10.is_platform_admin()then raise exception using errcode='42501',message='platform_identity_review_denied';end if;
  select * into prior from public.e10_catalog_identity_review_decisions d where d.case_id=p_case_id order by d.revision desc limit 1 for update;
  if prior.revision<>p_expected_revision then raise exception using errcode='40001',message='player_identity_review_revision_conflict';end if;
  if prior.action<>'propose'then raise exception using errcode='22023',message='player_identity_review_transition_invalid';end if;
  insert into public.e10_catalog_identity_review_decisions(id,case_id,revision,action,supersedes_decision_id,reason,evidence,idempotency_key,request_fingerprint,reviewed_by)
  values(decision_id,p_case_id,p_expected_revision+1,'reject',prior.id,btrim(p_reason),p_evidence,p_idempotency_key,fp,actor);
  return jsonb_build_object('ok',true,'replay',false,'case_id',p_case_id,'decision_id',decision_id,'revision',p_expected_revision+1,'status','rejected');
end $$;

create function public.e10_platform_player_identity_review_cases(
  p_status text default null,p_limit integer default 50,p_after_case_id uuid default null
)returns jsonb language plpgsql stable security definer set search_path=public as $$
declare actor uuid:=auth.uid();rows jsonb;next_id uuid;
begin
  if actor is null or not e10.is_platform_admin()then raise exception using errcode='42501',message='platform_identity_review_denied';end if;
  if p_status is not null and p_status not in('pending','rejected')or p_limit is null or p_limit not between 1 and 100 then
    raise exception using errcode='22023',message='player_identity_review_query_invalid';end if;
  with current_cases as(
    select c.*,d.action,d.revision,d.reviewed_by,d.reviewed_at,
      case when d.action='propose'then'pending'else'rejected'end status
    from public.e10_catalog_identity_review_cases c
    join lateral(select x.*from public.e10_catalog_identity_review_decisions x where x.case_id=c.id order by x.revision desc limit 1)d on true
    where(p_after_case_id is null or c.id>p_after_case_id)
  ),page as(select *from current_cases where(p_status is null or status=p_status)order by id limit p_limit+1),kept as(select *from page order by id limit p_limit)
  select coalesce(jsonb_agg(jsonb_build_object('case_id',k.id,'entity_kind',k.entity_kind,'source_namespace',k.source_namespace,'source_key',k.source_key,'source_display_name',k.source_display_name,'proposer_kind',k.proposer_kind,'proposer_name',k.proposer_name,'proposer_version',k.proposer_version,'source_evidence',k.source_evidence,'status',k.status,'revision',k.revision,'created_by',k.created_by,'created_at',k.created_at,'reviewed_by',k.reviewed_by,'reviewed_at',k.reviewed_at,'candidates',coalesce((select jsonb_agg(jsonb_build_object('player_id',c.player_id,'display_name',p.name,'confidence_status',c.confidence_status,'confidence',c.confidence,'evidence',c.evidence)order by c.player_id)from public.e10_catalog_identity_review_candidates c join public.e10_players p on p.id=c.player_id where c.case_id=k.id),'[]'::jsonb),'decision_history',coalesce((select jsonb_agg(jsonb_build_object('decision_id',d.id,'revision',d.revision,'action',d.action,'reason',d.reason,'evidence',d.evidence,'reviewed_by',d.reviewed_by,'reviewed_at',d.reviewed_at)order by d.revision)from public.e10_catalog_identity_review_decisions d where d.case_id=k.id),'[]'::jsonb))order by k.id),'[]'::jsonb),case when(select count(*)from page)>p_limit then(select id from kept order by id desc limit 1)end into rows,next_id from kept k;
  if auth.uid()is distinct from actor or not e10.is_platform_admin()then raise exception using errcode='42501',message='platform_identity_review_denied';end if;
  return jsonb_build_object('rows',rows,'next_after_case_id',next_id,'limit',p_limit,'status',p_status,'contract','player-identity-ambiguity-review-v1','limitations',jsonb_build_array('no_approval','no_canonical_link','no_merge_or_split','no_automatic_candidate_generation'));
end $$;

revoke all on function public.e10_platform_propose_player_identity_review(text,text,text,text,text,text,jsonb,jsonb,text,jsonb,text)from public,anon;
revoke all on function public.e10_platform_reject_player_identity_review(uuid,bigint,text,jsonb,text)from public,anon;
revoke all on function public.e10_platform_player_identity_review_cases(text,integer,uuid)from public,anon;
grant execute on function public.e10_platform_propose_player_identity_review(text,text,text,text,text,text,jsonb,jsonb,text,jsonb,text)to authenticated,service_role;
grant execute on function public.e10_platform_reject_player_identity_review(uuid,bigint,text,jsonb,text)to authenticated,service_role;
grant execute on function public.e10_platform_player_identity_review_cases(text,integer,uuid)to authenticated,service_role;
comment on function public.e10_platform_player_identity_review_cases(text,integer,uuid)is'Bounded platform-admin ambiguity review. Does not approve, canonically link, merge, split, or generate candidates.';
