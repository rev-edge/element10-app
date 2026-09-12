-- Schema-review checkpoint 1: canonical checklist promotion.
-- Additive only. Legacy checklist/card rows remain unchanged and readable.

create unique index e10_catalog_variants_legacy_card_uq
  on public.e10_catalog_variants(legacy_card_id)
  where legacy_card_id is not null;

create table public.e10_catalog_checklist_entries (
  id uuid primary key default gen_random_uuid(),
  checklist_id uuid not null references public.e10_checklists(id) on delete restrict,
  legacy_card_id uuid not null references public.e10_cards(id) on delete restrict,
  catalog_variant_id uuid not null references public.e10_catalog_variants(id) on delete restrict,
  position bigint not null check(position > 0),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default clock_timestamp(),
  unique(checklist_id,legacy_card_id),
  unique(checklist_id,position)
);
create index e10_catalog_checklist_entries_variant_idx
  on public.e10_catalog_checklist_entries(catalog_variant_id,checklist_id);

create table public.e10_catalog_checklist_promotion_rows (
  id uuid primary key default gen_random_uuid(),
  promotion_id uuid not null,
  checklist_entry_id uuid not null references public.e10_catalog_checklist_entries(id) on delete restrict,
  source_exact_parallel text,
  color_source_value text,
  color_term_key uuid references public.e10_catalog_facet_term_keys(id),
  color_resolution_status text not null check(color_resolution_status in ('resolved','unresolved','not_supplied')),
  finish_source_value text,
  finish_term_key uuid references public.e10_catalog_facet_term_keys(id),
  finish_resolution_status text not null check(finish_resolution_status in ('resolved','unresolved','not_supplied')),
  created_at timestamptz not null default clock_timestamp(),
  unique(promotion_id,checklist_entry_id),
  check((color_resolution_status='resolved')=(color_term_key is not null)),
  check((finish_resolution_status='resolved')=(finish_term_key is not null))
);
create index e10_catalog_checklist_promotion_rows_unresolved_idx
  on public.e10_catalog_checklist_promotion_rows(color_resolution_status,finish_resolution_status,promotion_id)
  where color_resolution_status='unresolved' or finish_resolution_status='unresolved';

create function e10.validate_checklist_promotion_row_insert() returns trigger
language plpgsql
security definer
set search_path=public
as $$
begin
  if new.color_term_key is not null and not exists(
    select 1 from public.e10_catalog_facet_term_keys
    where id=new.color_term_key and namespace='color_family'
  ) then
    raise exception using errcode='23514',message='promotion_color_term_namespace_invalid';
  end if;
  if new.finish_term_key is not null and not exists(
    select 1 from public.e10_catalog_facet_term_keys
    where id=new.finish_term_key and namespace='finish_family'
  ) then
    raise exception using errcode='23514',message='promotion_finish_term_namespace_invalid';
  end if;
  return new;
end $$;
revoke all on function e10.validate_checklist_promotion_row_insert() from public,anon,authenticated;
grant execute on function e10.validate_checklist_promotion_row_insert() to service_role;

create table public.e10_catalog_checklist_promotion_commands (
  id uuid primary key default gen_random_uuid(),
  checklist_id uuid not null references public.e10_checklists(id) on delete restrict,
  release_id uuid not null references public.e10_catalog_releases(id) on delete restrict,
  idempotency_key text not null unique check(length(btrim(idempotency_key)) between 1 and 500),
  request_fingerprint text not null check(btrim(request_fingerprint)<>''),
  result jsonb not null check(jsonb_typeof(result)='object'),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default clock_timestamp()
);

alter table public.e10_catalog_checklist_promotion_rows
  add constraint e10_catalog_checklist_promotion_rows_promotion_fkey
  foreign key(promotion_id) references public.e10_catalog_checklist_promotion_commands(id) on delete restrict
  deferrable initially deferred;

do $$ declare t text; begin
  foreach t in array array[
    'e10_catalog_checklist_entries',
    'e10_catalog_checklist_promotion_rows',
    'e10_catalog_checklist_promotion_commands'
  ] loop
    execute format('alter table public.%I enable row level security',t);
    execute format('revoke all on public.%I from public,anon,authenticated',t);
    execute format('grant all on public.%I to service_role',t);
  end loop;
end $$;

create trigger e10_catalog_checklist_promotion_rows_append_only
  before update or delete on public.e10_catalog_checklist_promotion_rows
  for each row execute function e10.reject_append_only_change();
create trigger e10_catalog_checklist_promotion_rows_insert_guard
  before insert on public.e10_catalog_checklist_promotion_rows
  for each row execute function e10.validate_checklist_promotion_row_insert();
create trigger e10_catalog_checklist_entries_append_only
  before update or delete on public.e10_catalog_checklist_entries
  for each row execute function e10.reject_append_only_change();
create trigger e10_catalog_checklist_promotion_commands_append_only
  before update or delete on public.e10_catalog_checklist_promotion_commands
  for each row execute function e10.reject_append_only_change();

create function public.e10_platform_promote_checklist(
  p_checklist_id uuid,
  p_release_id uuid,
  p_idempotency_key text
) returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_actor uuid:=auth.uid();
  v_fp text;
  v_prior record;
  v_promotion uuid:=gen_random_uuid();
  v_card record;
  v_variant uuid;
  v_entry uuid;
  v_color_source text;
  v_finish_source text;
  v_color_term uuid;
  v_finish_term uuid;
  v_color_status text;
  v_finish_status text;
  v_position bigint:=0;
  v_count bigint;
  v_unresolved_color bigint:=0;
  v_unresolved_finish bigint:=0;
  v_result jsonb;
begin
  if v_actor is null or not e10.is_platform_admin() then
    raise exception using errcode='42501',message='platform_catalog_curation_denied';
  end if;
  if p_checklist_id is null or p_release_id is null or p_idempotency_key is null
     or length(btrim(p_idempotency_key)) not between 1 and 500 then
    raise exception using errcode='22023',message='checklist_promotion_invalid';
  end if;
  v_fp:=md5(jsonb_build_object('v','checklist-promotion-v1','checklist',p_checklist_id,'release',p_release_id)::text);
  perform pg_advisory_xact_lock(hashtextextended('checklist-promotion-idempotency|'||btrim(p_idempotency_key),0));
  select * into v_prior from public.e10_catalog_checklist_promotion_commands where idempotency_key=btrim(p_idempotency_key);
  if found then
    if v_prior.request_fingerprint<>v_fp then
      raise exception using errcode='22023',message='idempotency_key_mismatch';
    end if;
    return v_prior.result||'{"replay":true}'::jsonb;
  end if;
  perform pg_advisory_xact_lock(hashtextextended('checklist-promotion|'||p_checklist_id::text,0));
  if auth.uid() is distinct from v_actor or not e10.is_platform_admin() then
    raise exception using errcode='42501',message='platform_catalog_curation_denied';
  end if;
  perform 1 from public.e10_checklists where id=p_checklist_id for update;
  if not found then raise exception using errcode='22023',message='checklist_not_found';end if;
  if not exists(select 1 from public.e10_catalog_releases where id=p_release_id) then
    raise exception using errcode='22023',message='catalog_release_not_found';
  end if;
  if exists(select 1 from public.e10_catalog_checklist_entries where checklist_id=p_checklist_id) then
    raise exception using errcode='55000',message='checklist_already_promoted';
  end if;
  select count(*) into v_count from public.e10_cards where checklist_id=p_checklist_id;
  if v_count=0 then raise exception using errcode='55000',message='checklist_has_no_cards';end if;

  for v_card in
    select c.* from public.e10_cards c where c.checklist_id=p_checklist_id
    order by c.created_at,c.id
  loop
    v_position:=v_position+1;
    v_color_source:=coalesce(nullif(btrim(v_card.color),''),nullif(btrim(v_card.parallel),''));
    v_finish_source:=nullif(btrim(v_card.parallel),'');
    v_color_term:=null;
    v_finish_term:=null;

    if v_color_source is not null then
      select a.term_key into v_color_term
      from public.e10_catalog_facet_taxonomy_aliases a
      join public.e10_catalog_facet_taxonomy_terms t on t.term_key=a.term_key and t.namespace='color_family'
      where a.namespace='color_family' and lower(btrim(a.alias))=lower(v_color_source) and a.action='assert'
        and not exists(select 1 from public.e10_catalog_facet_taxonomy_aliases n where n.supersedes_alias_id=a.id)
        and t.action='assert' and not exists(select 1 from public.e10_catalog_facet_taxonomy_terms nt where nt.supersedes_term_id=t.id)
      order by a.reviewed_at desc,a.id desc limit 1;
    end if;
    if v_finish_source is not null then
      select a.term_key into v_finish_term
      from public.e10_catalog_facet_taxonomy_aliases a
      join public.e10_catalog_facet_taxonomy_terms t on t.term_key=a.term_key and t.namespace='finish_family'
      where a.namespace='finish_family' and lower(btrim(a.alias))=lower(v_finish_source) and a.action='assert'
        and not exists(select 1 from public.e10_catalog_facet_taxonomy_aliases n where n.supersedes_alias_id=a.id)
        and t.action='assert' and not exists(select 1 from public.e10_catalog_facet_taxonomy_terms nt where nt.supersedes_term_id=t.id)
      order by a.reviewed_at desc,a.id desc limit 1;
    end if;
    v_color_status:=case when v_color_source is null then'not_supplied' when v_color_term is null then'unresolved' else'resolved'end;
    v_finish_status:=case when v_finish_source is null then'not_supplied' when v_finish_term is null then'unresolved' else'resolved'end;

    insert into public.e10_catalog_variants(release_id,legacy_card_id,card_number,exact_parallel)
    values(p_release_id,v_card.id,v_card.num,nullif(btrim(v_card.parallel),''))
    returning id into v_variant;
    if v_card.player_id is not null then
      insert into public.e10_catalog_variant_subjects(variant_id,player_id,subject_role,position)
      values(v_variant,v_card.player_id,'featured',1);
    end if;
    insert into public.e10_catalog_checklist_entries(checklist_id,legacy_card_id,catalog_variant_id,position,created_by)
    values(p_checklist_id,v_card.id,v_variant,v_position,v_actor) returning id into v_entry;
    if v_color_term is not null then
      insert into public.e10_catalog_variant_facet_decisions(
        decision_key,variant_id,facet_key,revision,action,term_key,reason,evidence,idempotency_key,request_fingerprint,reviewed_by)
      values(gen_random_uuid(),v_variant,'color_family',1,'assert',v_color_term,'resolved from reviewed checklist-import alias',
        jsonb_build_object('checklist_id',p_checklist_id,'legacy_card_id',v_card.id,'source_value',v_color_source),
        'checklist-promotion:'||v_promotion||':color:'||v_card.id,md5(v_fp||'|color|'||v_card.id),v_actor);
    end if;
    if v_finish_term is not null then
      insert into public.e10_catalog_variant_facet_decisions(
        decision_key,variant_id,facet_key,revision,action,term_key,reason,evidence,idempotency_key,request_fingerprint,reviewed_by)
      values(gen_random_uuid(),v_variant,'finish_family',1,'assert',v_finish_term,'resolved from reviewed checklist-import alias',
        jsonb_build_object('checklist_id',p_checklist_id,'legacy_card_id',v_card.id,'source_value',v_finish_source),
        'checklist-promotion:'||v_promotion||':finish:'||v_card.id,md5(v_fp||'|finish|'||v_card.id),v_actor);
    end if;
    insert into public.e10_catalog_checklist_promotion_rows(
      promotion_id,checklist_entry_id,source_exact_parallel,color_source_value,color_term_key,color_resolution_status,
      finish_source_value,finish_term_key,finish_resolution_status)
    values(v_promotion,v_entry,nullif(btrim(v_card.parallel),''),v_color_source,v_color_term,v_color_status,
      v_finish_source,v_finish_term,v_finish_status);
    v_unresolved_color:=v_unresolved_color+(v_color_status='unresolved')::integer;
    v_unresolved_finish:=v_unresolved_finish+(v_finish_status='unresolved')::integer;
  end loop;

  update public.e10_checklists set card_count=v_count,updated_at=clock_timestamp() where id=p_checklist_id;
  v_result:=jsonb_build_object('ok',true,'replay',false,'promotion_id',v_promotion,'checklist_id',p_checklist_id,
    'release_id',p_release_id,'promoted_count',v_count,'unresolved_color_count',v_unresolved_color,
    'unresolved_finish_count',v_unresolved_finish);
  insert into public.e10_catalog_checklist_promotion_commands(
    id,checklist_id,release_id,idempotency_key,request_fingerprint,result,created_by)
  values(v_promotion,p_checklist_id,p_release_id,btrim(p_idempotency_key),v_fp,v_result,v_actor);
  return v_result;
end $$;

revoke all on function public.e10_platform_promote_checklist(uuid,uuid,text) from public,anon;
grant execute on function public.e10_platform_promote_checklist(uuid,uuid,text) to authenticated,service_role;

comment on function public.e10_platform_promote_checklist(uuid,uuid,text) is
  'Platform-reviewed atomic promotion of legacy checklist rows into canonical variants. Exact parallel is preserved; color/finish resolve only through current reviewed aliases; unknowns remain explicit.';
