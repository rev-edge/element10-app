-- TA-X5d reviewed intake commit to immutable evidence observations.
-- Inventory receipts and customer activity require their domain writers and are never posted here.

alter table public.e10_intake_batches add column review_revision bigint not null default 0 check(review_revision>=0);

create table public.e10_intake_commits (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.e10_organizations(id),
  intake_batch_id uuid not null,
  idempotency_key text not null check(btrim(idempotency_key)<>''),
  request_fingerprint text not null,
  included_observation_count integer not null check(included_observation_count>=0),
  rejected_row_count integer not null check(rejected_row_count>=0),
  committed_by uuid references auth.users(id), committed_at timestamptz not null default now(),
  unique(organization_id,id), unique(organization_id,intake_batch_id), unique(organization_id,idempotency_key),
  foreign key(organization_id,intake_batch_id) references public.e10_intake_batches(organization_id,id)
);

create table public.e10_market_observations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.e10_organizations(id),
  intake_commit_id uuid not null, intake_row_id uuid not null,
  observation_kind text not null check(observation_kind in ('acquisition_cost','asking_price','completed_sale','estimated_value')),
  product_master_id uuid, configuration_version_id uuid, unique_item_id uuid,
  occurred_at timestamptz not null, recorded_at timestamptz not null default now(),
  currency text not null check(currency ~ '^[A-Z]{3}$'), amount numeric not null check(amount>=0),
  quantity numeric check(quantity is null or quantity>0),
  source_kind text not null check(source_kind in ('manual','csv','native','api')),
  source_connection_id text, source_reference text, raw_payload_snapshot jsonb not null check(jsonb_typeof(raw_payload_snapshot)='object'),
  evidence_quality text not null default 'operator_reviewed' check(evidence_quality='operator_reviewed'),
  unique(organization_id,id), unique(organization_id,intake_row_id),
  foreign key(organization_id,intake_commit_id) references public.e10_intake_commits(organization_id,id),
  foreign key(organization_id,intake_row_id) references public.e10_intake_rows(organization_id,id),
  foreign key(organization_id,product_master_id) references public.e10_product_masters(organization_id,id),
  foreign key(organization_id,configuration_version_id) references public.e10_product_configuration_versions(organization_id,id),
  foreign key(organization_id,unique_item_id) references public.e10_unique_items(organization_id,id),
  check(num_nonnulls(product_master_id,configuration_version_id,unique_item_id)=1)
);
create index e10_market_observations_subject_time_idx
  on public.e10_market_observations(organization_id,observation_kind,occurred_at desc,id);

do $$ declare t text; begin
  foreach t in array array['e10_intake_commits','e10_market_observations'] loop
    execute format('alter table public.%I enable row level security',t);
    execute format('revoke all on table public.%I from public,anon,authenticated',t);
    execute format('grant all on table public.%I to service_role',t);
    execute format('create trigger %I before update or delete on public.%I for each row execute function e10.reject_append_only_change()',t||'_append_only_trg',t);
  end loop;
end $$;

create or replace function e10.reject_committed_intake_row_change() returns trigger
language plpgsql set search_path=public as $$
declare v_status text;
begin
  select status into v_status from public.e10_intake_batches
    where organization_id=old.organization_id and id=old.batch_id for update;
  if v_status='committed' then
    raise exception using errcode='55000',message='committed_intake_row_is_immutable';
  end if;
  update public.e10_intake_batches set review_revision=review_revision+1,updated_at=now()
    where organization_id=old.organization_id and id=old.batch_id;
  return case when tg_op='DELETE' then old else new end;
end;
$$;
revoke all on function e10.reject_committed_intake_row_change() from public,anon,authenticated;
grant execute on function e10.reject_committed_intake_row_change() to service_role;
create trigger e10_intake_rows_committed_immutable_trg before update or delete on public.e10_intake_rows
  for each row execute function e10.reject_committed_intake_row_change();

-- Put row resolution and commit on the same batch-first lock order. The relocated X5b implementation
-- remains service-only; callers retain the exact public signature through this authorizing wrapper.
alter function public.e10_org_resolve_intake_row(uuid,uuid,text,uuid,text,uuid,text)
  rename to _e10_org_resolve_intake_row_x5b;
revoke all on function public._e10_org_resolve_intake_row_x5b(uuid,uuid,text,uuid,text,uuid,text) from public,anon,authenticated;
grant execute on function public._e10_org_resolve_intake_row_x5b(uuid,uuid,text,uuid,text,uuid,text) to service_role;

create function public.e10_org_resolve_intake_row(
  p_org uuid,p_intake_row_id uuid,p_decision text,p_target_id uuid,p_reason text,p_corrects_decision_id uuid,p_idempotency_key text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_batch_id uuid; v_status text;
begin
  if not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.manage_intake') then
    raise exception using errcode='42501',message='manage_intake_denied';
  end if;
  select batch_id into v_batch_id from public.e10_intake_rows where organization_id=p_org and id=p_intake_row_id;
  if not found then raise exception using errcode='42501',message='intake_row_access_denied'; end if;
  select status into v_status from public.e10_intake_batches
    where organization_id=p_org and id=v_batch_id for update;
  if v_status='committed' then
    if exists(select 1 from public.e10_intake_resolver_decisions d where d.organization_id=$1 and d.idempotency_key=$7) then
      return public._e10_org_resolve_intake_row_x5b(p_org,p_intake_row_id,p_decision,p_target_id,p_reason,p_corrects_decision_id,p_idempotency_key);
    end if;
    raise exception using errcode='55000',message='committed_intake_row_is_immutable';
  end if;
  return public._e10_org_resolve_intake_row_x5b(p_org,p_intake_row_id,p_decision,p_target_id,p_reason,p_corrects_decision_id,p_idempotency_key);
end;
$$;
revoke all on function public.e10_org_resolve_intake_row(uuid,uuid,text,uuid,text,uuid,text) from public,anon;
grant execute on function public.e10_org_resolve_intake_row(uuid,uuid,text,uuid,text,uuid,text) to authenticated,service_role;

create or replace function public.e10_org_intake_review_state(p_org uuid,p_batch_id uuid) returns jsonb
language plpgsql security definer stable set search_path=public as $$
declare v jsonb;
begin
  if not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.manage_intake') then
    raise exception using errcode='42501',message='manage_intake_denied';
  end if;
  select jsonb_build_object('batch_id',b.id,'status',b.status,'review_revision',b.review_revision,
    'unresolved_count',count(*) filter(where r.match_status='unresolved'),
    'matched_count',count(*) filter(where r.match_status='matched'),
    'rejected_count',count(*) filter(where r.match_status='rejected'),
    'invalid_count',count(*) filter(where jsonb_array_length(r.validation_errors)>0)) into v
  from public.e10_intake_batches b join public.e10_intake_rows r on r.organization_id=b.organization_id and r.batch_id=b.id
  where b.organization_id=p_org and b.id=p_batch_id group by b.id,b.status,b.review_revision;
  if v is null then raise exception using errcode='42501',message='intake_batch_access_denied'; end if;
  return v;
end;
$$;

create or replace function public.e10_org_commit_intake(p_org uuid,p_batch_id uuid,p_expected_review_revision bigint,p_idempotency_key text) returns jsonb
language plpgsql security definer set search_path=public as $$
declare v_batch record; v_existing record; v_fp text; v_commit uuid; v_included integer; v_rejected integer;
begin
  if not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.manage_intake') then
    raise exception using errcode='42501',message='manage_intake_denied';
  end if;
  if p_idempotency_key is null or btrim(p_idempotency_key)='' then raise exception using errcode='22004',message='idempotency_key_required'; end if;
  if p_expected_review_revision is null or p_expected_review_revision<0 then raise exception using errcode='22023',message='expected_review_revision_required'; end if;
  v_fp:=md5(p_batch_id::text||'|'||p_expected_review_revision::text||'|commit-v1');
  perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|intake-commit|'||p_idempotency_key,0));
  select id,request_fingerprint,intake_batch_id,included_observation_count,rejected_row_count into v_existing
    from public.e10_intake_commits where organization_id=p_org and idempotency_key=p_idempotency_key;
  if found then
    if v_existing.request_fingerprint is distinct from v_fp then raise exception using errcode='22023',message='idempotency_key_mismatch'; end if;
    return jsonb_build_object('ok',true,'replay',true,'commit_id',v_existing.id,'batch_id',v_existing.intake_batch_id,
      'observation_count',v_existing.included_observation_count,'rejected_row_count',v_existing.rejected_row_count);
  end if;
  select id,status,source_kind,source_connection_id,source_reference,review_revision into v_batch
    from public.e10_intake_batches where organization_id=p_org and id=p_batch_id for update;
  if not found then raise exception using errcode='42501',message='intake_batch_access_denied'; end if;
  if v_batch.status='committed' then raise exception using errcode='23505',message='intake_batch_already_committed'; end if;
  if v_batch.status<>'validated' then raise exception using errcode='55000',message='intake_batch_not_validated'; end if;
  if v_batch.review_revision<>p_expected_review_revision then raise exception using errcode='40001',message='intake_review_revision_conflict'; end if;
  if exists(select 1 from public.e10_intake_rows where organization_id=p_org and batch_id=p_batch_id
      and (jsonb_array_length(validation_errors)>0 or match_status='unresolved')) then
    raise exception using errcode='55000',message='intake_rows_require_resolution';
  end if;
  if exists(select 1 from public.e10_intake_rows where organization_id=p_org and batch_id=p_batch_id
      and match_status='matched' and observation_kind in ('inventory_receipt','customer_activity')) then
    raise exception using errcode='55000',message='actionable_intake_requires_domain_writer';
  end if;
  select count(*) filter(where match_status='matched'),count(*) filter(where match_status='rejected')
    into v_included,v_rejected from public.e10_intake_rows where organization_id=p_org and batch_id=p_batch_id;
  insert into public.e10_intake_commits(organization_id,intake_batch_id,idempotency_key,request_fingerprint,
    included_observation_count,rejected_row_count,committed_by)
  values(p_org,p_batch_id,p_idempotency_key,v_fp,v_included,v_rejected,auth.uid()) returning id into v_commit;
  insert into public.e10_market_observations(organization_id,intake_commit_id,intake_row_id,observation_kind,
    product_master_id,configuration_version_id,unique_item_id,occurred_at,currency,amount,quantity,
    source_kind,source_connection_id,source_reference,raw_payload_snapshot)
  select p_org,v_commit,r.id,r.observation_kind,r.product_master_id,r.configuration_version_id,r.unique_item_id,
    r.occurred_at,r.currency,r.amount,r.quantity,v_batch.source_kind,v_batch.source_connection_id,v_batch.source_reference,r.raw_payload
  from public.e10_intake_rows r where r.organization_id=p_org and r.batch_id=p_batch_id and r.match_status='matched'
    and r.observation_kind in ('acquisition_cost','asking_price','completed_sale','estimated_value')
  order by r.source_row_number,r.id;
  update public.e10_intake_batches set status='committed',updated_at=now() where organization_id=p_org and id=p_batch_id;
  return jsonb_build_object('ok',true,'replay',false,'commit_id',v_commit,'batch_id',p_batch_id,
    'observation_count',v_included,'rejected_row_count',v_rejected);
end;
$$;
revoke all on function public.e10_org_intake_review_state(uuid,uuid) from public,anon;
revoke all on function public.e10_org_commit_intake(uuid,uuid,bigint,text) from public,anon;
grant execute on function public.e10_org_intake_review_state(uuid,uuid) to authenticated,service_role;
grant execute on function public.e10_org_commit_intake(uuid,uuid,bigint,text) to authenticated,service_role;
comment on function public.e10_org_commit_intake(uuid,uuid,bigint,text) is
  'Commits reviewed non-actionable intake evidence only; never posts inventory, customer spend, finance, or settlement.';
