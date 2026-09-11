-- TA-X1b governed player affiliations and release-time subject context.
-- Platform catalog evidence is append-only. No provider feed or automatic merge is enabled.

create table public.e10_player_affiliation_decisions(
  id uuid primary key default gen_random_uuid(),
  decision_key uuid not null,
  player_id uuid not null references public.e10_players(id),
  team_id uuid not null references public.e10_teams(id),
  sport text not null check(length(btrim(sport)) between 1 and 100),
  league text not null check(length(btrim(league)) between 1 and 100),
  effective_from date not null,
  effective_to date,
  revision bigint not null check(revision>0),
  action text not null check(action in('assert','revoke')),
  supersedes_decision_id uuid references public.e10_player_affiliation_decisions(id),
  source_kind text not null check(source_kind in('manual_review','official_source','documentary_source')),
  source_reference text not null check(length(btrim(source_reference)) between 1 and 1000),
  reason text not null check(length(btrim(reason)) between 1 and 2000),
  evidence jsonb not null check(jsonb_typeof(evidence)='object' and octet_length(evidence::text)<=65536),
  idempotency_key text not null unique check(length(btrim(idempotency_key)) between 1 and 500),
  request_fingerprint text not null check(request_fingerprint~'^[0-9a-f]{64}$'),
  reviewed_by uuid not null references auth.users(id),
  reviewed_at timestamptz not null default clock_timestamp(),
  unique(decision_key,revision),
  check(effective_to is null or effective_to>effective_from)
);
create unique index e10_player_affiliation_root_uq on public.e10_player_affiliation_decisions(decision_key) where supersedes_decision_id is null;
create unique index e10_player_affiliation_logical_root_uq on public.e10_player_affiliation_decisions(player_id,team_id,effective_from) where supersedes_decision_id is null;
create unique index e10_player_affiliation_successor_uq on public.e10_player_affiliation_decisions(supersedes_decision_id) where supersedes_decision_id is not null;
create index e10_player_affiliation_query_idx on public.e10_player_affiliation_decisions(player_id,effective_from,effective_to,id);

create table public.e10_catalog_variant_subject_context_decisions(
  id uuid primary key default gen_random_uuid(),
  decision_key uuid not null,
  variant_id uuid not null,
  player_id uuid not null,
  context_status text not null check(context_status in('known','unknown')),
  depicted_team_id uuid references public.e10_teams(id),
  revision bigint not null check(revision>0),
  action text not null check(action in('assert','revoke')),
  supersedes_decision_id uuid references public.e10_catalog_variant_subject_context_decisions(id),
  source_kind text not null check(source_kind in('manual_review','official_source','documentary_source')),
  source_reference text not null check(length(btrim(source_reference)) between 1 and 1000),
  reason text not null check(length(btrim(reason)) between 1 and 2000),
  evidence jsonb not null check(jsonb_typeof(evidence)='object' and octet_length(evidence::text)<=65536),
  idempotency_key text not null unique check(length(btrim(idempotency_key)) between 1 and 500),
  request_fingerprint text not null check(request_fingerprint~'^[0-9a-f]{64}$'),
  reviewed_by uuid not null references auth.users(id),
  reviewed_at timestamptz not null default clock_timestamp(),
  unique(decision_key,revision),
  foreign key(variant_id,player_id) references public.e10_catalog_variant_subjects(variant_id,player_id) on delete cascade,
  check((action='assert' and ((context_status='known' and depicted_team_id is not null) or (context_status='unknown' and depicted_team_id is null))) or (action='revoke' and depicted_team_id is null))
);
create unique index e10_variant_subject_context_root_uq on public.e10_catalog_variant_subject_context_decisions(decision_key) where supersedes_decision_id is null;
create unique index e10_variant_subject_context_logical_root_uq on public.e10_catalog_variant_subject_context_decisions(variant_id,player_id) where supersedes_decision_id is null;
create unique index e10_variant_subject_context_successor_uq on public.e10_catalog_variant_subject_context_decisions(supersedes_decision_id) where supersedes_decision_id is not null;

create function e10.validate_player_catalog_decision_insert() returns trigger
language plpgsql security definer set search_path=public as $$
declare prior record;
begin
  if new.supersedes_decision_id is null then
    if new.revision<>1 then raise exception using errcode='23514',message='root_revision_invalid';end if;
  else
    if new.supersedes_decision_id=new.id then raise exception using errcode='23514',message='self_successor_invalid';end if;
    if tg_table_name='e10_player_affiliation_decisions' then
      select * into prior from public.e10_player_affiliation_decisions where id=new.supersedes_decision_id;
      if not found or prior.decision_key<>new.decision_key or prior.player_id<>new.player_id or prior.team_id<>new.team_id
        or prior.effective_from<>new.effective_from or new.revision<>prior.revision+1 then
        raise exception using errcode='23514',message='affiliation_successor_mismatch';
      end if;
    else
      select * into prior from public.e10_catalog_variant_subject_context_decisions where id=new.supersedes_decision_id;
      if not found or prior.decision_key<>new.decision_key or prior.variant_id<>new.variant_id or prior.player_id<>new.player_id
        or new.revision<>prior.revision+1 then
        raise exception using errcode='23514',message='subject_context_successor_mismatch';
      end if;
    end if;
  end if;
  return new;
end $$;
revoke all on function e10.validate_player_catalog_decision_insert() from public,anon,authenticated;
grant execute on function e10.validate_player_catalog_decision_insert() to service_role;

alter table public.e10_player_affiliation_decisions enable row level security;
alter table public.e10_catalog_variant_subject_context_decisions enable row level security;
revoke all on public.e10_player_affiliation_decisions,public.e10_catalog_variant_subject_context_decisions from public,anon,authenticated;
grant all on public.e10_player_affiliation_decisions,public.e10_catalog_variant_subject_context_decisions to service_role;
create trigger e10_player_affiliation_append_only before update or delete on public.e10_player_affiliation_decisions for each row execute function e10.reject_append_only_change();
create trigger e10_variant_subject_context_append_only before update or delete on public.e10_catalog_variant_subject_context_decisions for each row execute function e10.reject_append_only_change();
create trigger e10_player_affiliation_insert_guard before insert on public.e10_player_affiliation_decisions for each row execute function e10.validate_player_catalog_decision_insert();
create trigger e10_variant_subject_context_insert_guard before insert on public.e10_catalog_variant_subject_context_decisions for each row execute function e10.validate_player_catalog_decision_insert();
create trigger e10_player_affiliation_market_revision after insert on public.e10_player_affiliation_decisions for each row execute function e10.bump_market_catalog_revision();
create trigger e10_variant_subject_context_market_revision after insert on public.e10_catalog_variant_subject_context_decisions for each row execute function e10.bump_market_catalog_revision();

create function public.e10_platform_review_player_affiliation(
  p_decision_key uuid,p_player_id uuid,p_team_id uuid,p_sport text,p_league text,p_effective_from date,p_effective_to date,
  p_expected_revision bigint,p_action text,p_source_kind text,p_source_reference text,p_reason text,p_evidence jsonb,p_idempotency_key text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare actor uuid:=auth.uid();k uuid:=coalesce(p_decision_key,gen_random_uuid());prior record;prior_id uuid;replay record;new_id uuid:=gen_random_uuid();fp text;
begin
  if actor is null or not e10.is_platform_admin() then raise exception using errcode='42501',message='platform_catalog_curation_denied';end if;
  if p_player_id is null or p_team_id is null or p_sport is null or length(btrim(p_sport))not between 1 and 100
    or p_league is null or length(btrim(p_league))not between 1 and 100 or p_effective_from is null or(p_effective_to is not null and p_effective_to<=p_effective_from)
    or p_expected_revision is null or p_expected_revision<0 or p_action is null or p_action not in('assert','revoke')
    or p_source_kind is null or p_source_kind not in('manual_review','official_source','documentary_source')
    or p_source_reference is null or length(btrim(p_source_reference))not between 1 and 1000 or p_reason is null or length(btrim(p_reason))not between 1 and 2000
    or p_evidence is null or jsonb_typeof(p_evidence)<>'object' or octet_length(p_evidence::text)>65536
    or p_idempotency_key is null or length(btrim(p_idempotency_key))not between 1 and 500 then raise exception using errcode='22023',message='player_affiliation_review_invalid';end if;
  fp:=encode(sha256(convert_to(jsonb_build_object('v','player-affiliation-v1','key',p_decision_key,'player',p_player_id,'team',p_team_id,'sport',btrim(p_sport),'league',btrim(p_league),'from',p_effective_from,'to',p_effective_to,'expected',p_expected_revision,'action',p_action,'source_kind',p_source_kind,'source_reference',btrim(p_source_reference),'reason',btrim(p_reason),'evidence',p_evidence)::text,'UTF8')),'hex');
  perform pg_advisory_xact_lock(hashtextextended('player-affiliation-idempotency|'||p_idempotency_key,0));
  if auth.uid() is distinct from actor or not e10.is_platform_admin() then raise exception using errcode='42501',message='platform_catalog_curation_denied';end if;
  select * into replay from public.e10_player_affiliation_decisions where idempotency_key=p_idempotency_key;
  if found then if replay.request_fingerprint<>fp then raise exception using errcode='22023',message='idempotency_key_mismatch';end if;return jsonb_build_object('ok',true,'replay',true,'decision_key',replay.decision_key,'revision',replay.revision,'action',replay.action);end if;
  perform pg_advisory_xact_lock(hashtextextended('player-affiliation|'||p_player_id::text||'|'||p_team_id::text||'|'||p_effective_from::text,0));
  perform revision from public.e10_market_catalog_revision where singleton for update;
  if auth.uid() is distinct from actor or not e10.is_platform_admin() then raise exception using errcode='42501',message='platform_catalog_curation_denied';end if;
  select * into prior from public.e10_player_affiliation_decisions d where d.player_id=p_player_id and d.team_id=p_team_id and d.effective_from=p_effective_from and not exists(select 1 from public.e10_player_affiliation_decisions n where n.supersedes_decision_id=d.id);
  if p_decision_key is null then if found or p_expected_revision<>0 or p_action<>'assert' then raise exception using errcode='22023',message='player_affiliation_transition_invalid';end if;
  else if not found or prior.decision_key<>p_decision_key then raise exception using errcode='22023',message='player_affiliation_key_invalid';end if;if prior.revision<>p_expected_revision then raise exception using errcode='40001',message='player_affiliation_revision_conflict';end if;prior_id:=prior.id;end if;
  insert into public.e10_player_affiliation_decisions(id,decision_key,player_id,team_id,sport,league,effective_from,effective_to,revision,action,supersedes_decision_id,source_kind,source_reference,reason,evidence,idempotency_key,request_fingerprint,reviewed_by)
  values(new_id,k,p_player_id,p_team_id,btrim(p_sport),btrim(p_league),p_effective_from,p_effective_to,p_expected_revision+1,p_action,prior_id,p_source_kind,btrim(p_source_reference),btrim(p_reason),p_evidence,p_idempotency_key,fp,actor);
  return jsonb_build_object('ok',true,'replay',false,'decision_key',k,'decision_id',new_id,'revision',p_expected_revision+1,'action',p_action);
end $$;

create function public.e10_platform_review_variant_subject_context(
  p_decision_key uuid,p_variant_id uuid,p_player_id uuid,p_expected_revision bigint,p_action text,p_context_status text,p_depicted_team_id uuid,
  p_source_kind text,p_source_reference text,p_reason text,p_evidence jsonb,p_idempotency_key text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare actor uuid:=auth.uid();k uuid:=coalesce(p_decision_key,gen_random_uuid());prior record;prior_id uuid;replay record;new_id uuid:=gen_random_uuid();fp text;
begin
  if actor is null or not e10.is_platform_admin() then raise exception using errcode='42501',message='platform_catalog_curation_denied';end if;
  if p_variant_id is null or p_player_id is null or p_expected_revision is null or p_expected_revision<0 or p_action is null or p_action not in('assert','revoke')
    or p_context_status is null or p_context_status not in('known','unknown') or (p_action='assert' and ((p_context_status='known')<>(p_depicted_team_id is not null))) or(p_action='revoke' and p_depicted_team_id is not null)
    or p_source_kind is null or p_source_kind not in('manual_review','official_source','documentary_source')
    or p_source_reference is null or length(btrim(p_source_reference))not between 1 and 1000 or p_reason is null or length(btrim(p_reason))not between 1 and 2000
    or p_evidence is null or jsonb_typeof(p_evidence)<>'object' or octet_length(p_evidence::text)>65536
    or p_idempotency_key is null or length(btrim(p_idempotency_key))not between 1 and 500 then raise exception using errcode='22023',message='variant_subject_context_review_invalid';end if;
  fp:=encode(sha256(convert_to(jsonb_build_object('v','variant-subject-context-v1','key',p_decision_key,'variant',p_variant_id,'player',p_player_id,'expected',p_expected_revision,'action',p_action,'status',p_context_status,'team',p_depicted_team_id,'source_kind',p_source_kind,'source_reference',btrim(p_source_reference),'reason',btrim(p_reason),'evidence',p_evidence)::text,'UTF8')),'hex');
  perform pg_advisory_xact_lock(hashtextextended('variant-subject-context-idempotency|'||p_idempotency_key,0));
  if auth.uid() is distinct from actor or not e10.is_platform_admin() then raise exception using errcode='42501',message='platform_catalog_curation_denied';end if;
  select * into replay from public.e10_catalog_variant_subject_context_decisions where idempotency_key=p_idempotency_key;
  if found then if replay.request_fingerprint<>fp then raise exception using errcode='22023',message='idempotency_key_mismatch';end if;return jsonb_build_object('ok',true,'replay',true,'decision_key',replay.decision_key,'revision',replay.revision,'action',replay.action);end if;
  perform pg_advisory_xact_lock(hashtextextended('variant-subject-context|'||p_variant_id::text||'|'||p_player_id::text,0));
  perform revision from public.e10_market_catalog_revision where singleton for update;
  if auth.uid() is distinct from actor or not e10.is_platform_admin() then raise exception using errcode='42501',message='platform_catalog_curation_denied';end if;
  select * into prior from public.e10_catalog_variant_subject_context_decisions d where d.variant_id=p_variant_id and d.player_id=p_player_id and not exists(select 1 from public.e10_catalog_variant_subject_context_decisions n where n.supersedes_decision_id=d.id);
  if p_decision_key is null then if found or p_expected_revision<>0 or p_action<>'assert' then raise exception using errcode='22023',message='variant_subject_context_transition_invalid';end if;
  else if not found or prior.decision_key<>p_decision_key then raise exception using errcode='22023',message='variant_subject_context_key_invalid';end if;if prior.revision<>p_expected_revision then raise exception using errcode='40001',message='variant_subject_context_revision_conflict';end if;prior_id:=prior.id;end if;
  insert into public.e10_catalog_variant_subject_context_decisions(id,decision_key,variant_id,player_id,context_status,depicted_team_id,revision,action,supersedes_decision_id,source_kind,source_reference,reason,evidence,idempotency_key,request_fingerprint,reviewed_by)
  values(new_id,k,p_variant_id,p_player_id,p_context_status,p_depicted_team_id,p_expected_revision+1,p_action,prior_id,p_source_kind,btrim(p_source_reference),btrim(p_reason),p_evidence,p_idempotency_key,fp,actor);
  return jsonb_build_object('ok',true,'replay',false,'decision_key',k,'decision_id',new_id,'revision',p_expected_revision+1,'action',p_action);
end $$;

create function public.e10_catalog_player_affiliations(p_player_id uuid,p_window_from date default null,p_window_to date default null,p_limit integer default 100)
returns jsonb language plpgsql security definer set search_path=public as $$
declare actor uuid:=auth.uid();rows jsonb;
begin
  if actor is null or not(e10.is_platform_admin() or exists(select 1 from public.e10_organization_memberships m where m.user_id=actor and m.status='active')) then raise exception using errcode='42501',message='catalog_read_denied';end if;
  if p_player_id is null or p_limit is null or p_limit not between 1 and 200 or(p_window_from is not null and p_window_to is not null and p_window_to<=p_window_from) then raise exception using errcode='22023',message='player_affiliation_query_invalid';end if;
  select coalesce(jsonb_agg(jsonb_build_object('decision_key',d.decision_key,'revision',d.revision,'action',d.action,'player_id',d.player_id,'team_id',d.team_id,'team_name',t.name,'sport',d.sport,'league',d.league,'effective_from',d.effective_from,'effective_to',d.effective_to,'source_kind',d.source_kind,'source_reference',d.source_reference,'reviewed_at',d.reviewed_at) order by d.effective_from desc,d.id),'[]'::jsonb) into rows
  from(select d.* from public.e10_player_affiliation_decisions d where d.player_id=p_player_id and not exists(select 1 from public.e10_player_affiliation_decisions n where n.supersedes_decision_id=d.id) and d.action='assert' and(p_window_to is null or d.effective_from<p_window_to)and(p_window_from is null or d.effective_to is null or d.effective_to>p_window_from)order by d.effective_from desc,d.id limit p_limit)d join public.e10_teams t on t.id=d.team_id;
  return jsonb_build_object('player_id',p_player_id,'window_from',p_window_from,'window_to',p_window_to,'limit',p_limit,'rows',rows);
end $$;

create function public.e10_catalog_variant_subject_context(p_variant_id uuid,p_limit integer default 50)
returns jsonb language plpgsql security definer set search_path=public as $$
declare actor uuid:=auth.uid();rows jsonb;
begin
  if actor is null or not(e10.is_platform_admin() or exists(select 1 from public.e10_organization_memberships m where m.user_id=actor and m.status='active')) then raise exception using errcode='42501',message='catalog_read_denied';end if;
  if p_variant_id is null or p_limit is null or p_limit not between 1 and 100 then raise exception using errcode='22023',message='variant_subject_context_query_invalid';end if;
  select coalesce(jsonb_agg(jsonb_build_object('decision_key',d.decision_key,'revision',d.revision,'action',d.action,'variant_id',d.variant_id,'player_id',d.player_id,'context_status',d.context_status,'depicted_team_id',d.depicted_team_id,'depicted_team_name',t.name,'source_kind',d.source_kind,'source_reference',d.source_reference,'reviewed_at',d.reviewed_at)order by s.position,d.id),'[]'::jsonb)into rows
  from(select d.* from public.e10_catalog_variant_subject_context_decisions d where d.variant_id=p_variant_id and not exists(select 1 from public.e10_catalog_variant_subject_context_decisions n where n.supersedes_decision_id=d.id)and d.action='assert' order by d.player_id limit p_limit)d join public.e10_catalog_variant_subjects s on(s.variant_id,s.player_id)=(d.variant_id,d.player_id) left join public.e10_teams t on t.id=d.depicted_team_id;
  return jsonb_build_object('variant_id',p_variant_id,'limit',p_limit,'rows',rows);
end $$;

revoke all on function public.e10_platform_review_player_affiliation(uuid,uuid,uuid,text,text,date,date,bigint,text,text,text,text,jsonb,text),public.e10_platform_review_variant_subject_context(uuid,uuid,uuid,bigint,text,text,uuid,text,text,text,jsonb,text),public.e10_catalog_player_affiliations(uuid,date,date,integer),public.e10_catalog_variant_subject_context(uuid,integer) from public,anon;
grant execute on function public.e10_platform_review_player_affiliation(uuid,uuid,uuid,text,text,date,date,bigint,text,text,text,text,jsonb,text),public.e10_platform_review_variant_subject_context(uuid,uuid,uuid,bigint,text,text,uuid,text,text,text,jsonb,text),public.e10_catalog_player_affiliations(uuid,date,date,integer),public.e10_catalog_variant_subject_context(uuid,integer) to authenticated,service_role;

comment on table public.e10_player_affiliation_decisions is 'Reviewed dated player-team evidence. Stable player identity is independent of current affiliation.';
comment on table public.e10_catalog_variant_subject_context_decisions is 'Reviewed release/card depiction context. Never derived from a player current-team value.';
