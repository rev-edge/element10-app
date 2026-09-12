\set ON_ERROR_STOP on
begin;

do $$
declare
  actor uuid:='c1000000-0000-4000-8000-000000000001';
  outsider uuid:='c1000000-0000-4000-8000-000000000002';
  checklist uuid:='c1000000-0000-4000-8000-000000000010';
  release_id uuid:='c1000000-0000-4000-8000-000000000011';
  other_release uuid:='c1000000-0000-4000-8000-000000000012';
  player uuid:='c1000000-0000-4000-8000-000000000013';
  gold uuid:='c1000000-0000-4000-8000-000000000020';
  shimmer uuid:='c1000000-0000-4000-8000-000000000021';
begin
  insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at) values
    (actor,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','c1-actor@example.invalid',now(),now()),
    (outsider,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','c1-outsider@example.invalid',now(),now());
  insert into public.e10_platform_admins(user_id) values(actor);
  insert into public.e10_players(id,name) values(player,'C1 Player');
  insert into public.e10_sets(id,name) values('c1000000-0000-4000-8000-000000000014','C1 Set');
  insert into public.e10_checklists(id,name,set_id,card_count) values
    (checklist,'C1 Checklist','c1000000-0000-4000-8000-000000000014',0);
  insert into public.e10_cards(id,checklist_id,player_id,num,name,parallel,color) values
    ('c1000000-0000-4000-8000-000000000101',checklist,player,'1','Resolved','Gold Shimmer','Gold'),
    ('c1000000-0000-4000-8000-000000000102',checklist,player,'2','Unknown','Mystery Foil',null),
    ('c1000000-0000-4000-8000-000000000103',checklist,player,'3','Base',null,null);
  insert into public.e10_catalog_releases(id,release_name) values(release_id,'C1 Release'),(other_release,'C1 Other');
  insert into public.e10_catalog_facet_term_keys(id,namespace) values(gold,'color_family'),(shimmer,'finish_family');
  insert into public.e10_catalog_facet_taxonomy_terms(term_key,namespace,canonical_name,revision,action,reason,evidence,idempotency_key,request_fingerprint,reviewed_by)
  values(gold,'color_family','Gold',1,'assert','C1','{}','c1-term-gold','fp',actor),
        (shimmer,'finish_family','Shimmer',1,'assert','C1','{}','c1-term-shimmer','fp',actor);
  insert into public.e10_catalog_facet_taxonomy_aliases(alias_key,namespace,alias,term_key,revision,action,reason,evidence,idempotency_key,request_fingerprint,reviewed_by)
  values(gen_random_uuid(),'color_family','Gold',gold,1,'assert','C1','{}','c1-alias-gold','fp',actor),
        (gen_random_uuid(),'finish_family','Gold Shimmer',shimmer,1,'assert','C1','{}','c1-alias-shimmer','fp',actor);
end $$;

do $$
declare
  actor uuid:='c1000000-0000-4000-8000-000000000001';
  outsider uuid:='c1000000-0000-4000-8000-000000000002';
  checklist uuid:='c1000000-0000-4000-8000-000000000010';
  release_id uuid:='c1000000-0000-4000-8000-000000000011';
  other_release uuid:='c1000000-0000-4000-8000-000000000012';
  gold uuid:='c1000000-0000-4000-8000-000000000020';
  shimmer uuid:='c1000000-0000-4000-8000-000000000021';
  result jsonb;
  promotion uuid;
  n bigint;
begin
  perform set_config('request.jwt.claim.sub',outsider::text,true);
  begin
    perform public.e10_platform_promote_checklist(checklist,release_id,'c1-promote');
    raise exception 'non-platform-admin promotion unexpectedly succeeded';
  exception when insufficient_privilege then
    if sqlerrm<>'platform_catalog_curation_denied' then raise;end if;
  end;

  perform set_config('request.jwt.claim.sub',actor::text,true);
  result:=public.e10_platform_promote_checklist(checklist,release_id,'c1-promote');
  if result->>'replay'<>'false' or (result->>'promoted_count')::int<>3
     or (result->>'unresolved_color_count')::int<>1
     or (result->>'unresolved_finish_count')::int<>1 then
    raise exception 'promotion result mismatch: %',result;
  end if;
  promotion:=(result->>'promotion_id')::uuid;
  if (select card_count from public.e10_checklists where id=checklist)<>3 then
    raise exception 'checklist count not reconciled';
  end if;
  if (select count(*) from public.e10_catalog_checklist_entries where checklist_id=checklist)<>3
     or (select count(*) from public.e10_catalog_variants where legacy_card_id in(
       'c1000000-0000-4000-8000-000000000101','c1000000-0000-4000-8000-000000000102','c1000000-0000-4000-8000-000000000103'))<>3 then
    raise exception 'canonical row count mismatch';
  end if;
  if not exists(
    select 1 from public.e10_catalog_variants v
    join public.e10_catalog_variant_subjects s on s.variant_id=v.id
    where v.legacy_card_id='c1000000-0000-4000-8000-000000000101'
      and v.exact_parallel='Gold Shimmer' and s.player_id='c1000000-0000-4000-8000-000000000013'
  ) then raise exception 'exact parallel or subject not preserved';end if;
  if (select count(*) from public.e10_catalog_variant_facet_decisions d
      join public.e10_catalog_variants v on v.id=d.variant_id
      where v.legacy_card_id='c1000000-0000-4000-8000-000000000101'
        and ((d.facet_key='color_family' and d.term_key=gold)
          or (d.facet_key='finish_family' and d.term_key=shimmer)))<>2 then
    raise exception 'reviewed facet aliases not resolved';
  end if;
  if not exists(
    select 1 from public.e10_catalog_checklist_promotion_rows r
    join public.e10_catalog_checklist_entries e on e.id=r.checklist_entry_id
    where r.promotion_id=promotion and e.legacy_card_id='c1000000-0000-4000-8000-000000000102'
      and r.source_exact_parallel='Mystery Foil'
      and r.color_resolution_status='unresolved' and r.finish_resolution_status='unresolved'
      and r.color_term_key is null and r.finish_term_key is null
  ) then raise exception 'unknown facets were not preserved unresolved';end if;
  if not exists(
    select 1 from public.e10_catalog_checklist_promotion_rows r
    join public.e10_catalog_checklist_entries e on e.id=r.checklist_entry_id
    where r.promotion_id=promotion and e.legacy_card_id='c1000000-0000-4000-8000-000000000103'
      and r.color_resolution_status='not_supplied' and r.finish_resolution_status='not_supplied'
  ) then raise exception 'base facet status mismatch';end if;

  begin
    insert into public.e10_catalog_checklist_promotion_rows(
      promotion_id,checklist_entry_id,color_term_key,color_resolution_status,finish_resolution_status)
    select promotion,e.id,shimmer,'resolved','not_supplied'
    from public.e10_catalog_checklist_entries e
    where e.checklist_id=checklist
    order by e.position
    limit 1;
    raise exception 'wrong-namespace color term unexpectedly accepted';
  exception when check_violation then
    if sqlerrm<>'promotion_color_term_namespace_invalid' then raise;end if;
  end;

  result:=public.e10_platform_promote_checklist(checklist,release_id,'c1-promote');
  if result->>'replay'<>'true' or (result->>'promotion_id')::uuid<>promotion then
    raise exception 'exact replay mismatch: %',result;
  end if;
  begin
    perform public.e10_platform_promote_checklist(checklist,other_release,'c1-promote');
    raise exception 'changed idempotency reuse unexpectedly succeeded';
  exception when invalid_parameter_value then
    if sqlerrm<>'idempotency_key_mismatch' then raise;end if;
  end;
  begin
    perform public.e10_platform_promote_checklist(checklist,release_id,'c1-promote-again');
    raise exception 'second promotion unexpectedly succeeded';
  exception when object_not_in_prerequisite_state then
    if sqlerrm<>'checklist_already_promoted' then raise;end if;
  end;

  select count(*) into n from public.e10_catalog_checklist_promotion_commands where checklist_id=checklist;
  if n<>1 then raise exception 'command receipt count mismatch';end if;
  if has_function_privilege('anon','public.e10_platform_promote_checklist(uuid,uuid,text)','execute') then
    raise exception 'anon execute leak';
  end if;
end $$;

rollback;
select 'schema review C1 checklist promotion PASS' as result;
