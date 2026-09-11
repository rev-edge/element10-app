-- TA-X7e.0 immutable grading, population, valuation, and disposition evidence.
-- Reporting evidence only. No inventory, receipt, sale, payment, or accounting mutation.

create table public.e10_unique_item_grade_assessments(
 id uuid primary key default gen_random_uuid(),organization_id uuid not null,
 assessment_key uuid not null,unique_item_id uuid not null,revision bigint not null check(revision>0),
 action text not null check(action in('assert','revoke')),
 condition_state text,grader_code text,grade_label text,grade_qualifier text,autograph_designation text,
 assessed_at timestamptz,assessed_at_precision text not null check(assessed_at_precision in('exact','date','unknown')),
 source_kind text not null check(source_kind in('manual','csv','api')),source_connection_id text,source_reference text,
 method text not null,method_version text not null,review_status text not null check(review_status in('reviewed','rejected')),
 supersedes_assessment_id uuid,reason text not null,evidence jsonb not null,
 idempotency_key text not null,request_fingerprint text not null,reviewed_by uuid references auth.users(id),
 recorded_at timestamptz not null default clock_timestamp(),
 unique(organization_id,id),unique(organization_id,assessment_key,revision),unique(organization_id,idempotency_key),
 foreign key(organization_id,unique_item_id)references public.e10_unique_items(organization_id,id),
 foreign key(organization_id,supersedes_assessment_id)references public.e10_unique_item_grade_assessments(organization_id,id),
 check((assessed_at_precision='unknown'and assessed_at is null)or(assessed_at_precision in('exact','date')and assessed_at is not null and isfinite(assessed_at))),
 check((action='revoke'and num_nonnulls(condition_state,grader_code,grade_label,grade_qualifier,autograph_designation)=0)
   or(action='assert'and condition_state in('raw','graded')
     and(condition_state='raw'and grader_code is null and grade_label is null and grade_qualifier is null
       or condition_state='graded'and grader_code is not null and grade_label is not null and length(btrim(grader_code))between 1 and 50 and length(btrim(grade_label))between 1 and 50))),
 check(action='revoke'or action='assert'and condition_state is not null),
 check(length(btrim(method))between 1 and 100 and length(btrim(method_version))between 1 and 100),
 check(source_connection_id is null or length(btrim(source_connection_id))between 1 and 500),
 check(source_reference is null or length(btrim(source_reference))between 1 and 2000),
 check(grade_qualifier is null or length(btrim(grade_qualifier))between 1 and 200),
 check(autograph_designation is null or length(btrim(autograph_designation))between 1 and 200),
 check(length(btrim(reason))between 1 and 2000),check(jsonb_typeof(evidence)='object'and octet_length(evidence::text)<=65536),
 check(length(btrim(idempotency_key))between 1 and 500 and btrim(request_fingerprint)<>'')
);
create unique index e10_grade_assessment_successor_uq on public.e10_unique_item_grade_assessments(organization_id,supersedes_assessment_id)where supersedes_assessment_id is not null;
create index e10_grade_assessment_item_time_idx on public.e10_unique_item_grade_assessments(organization_id,unique_item_id,assessed_at desc,recorded_at desc,id);

create table public.e10_catalog_population_snapshots(
 id uuid primary key default gen_random_uuid(),organization_id uuid not null,
 snapshot_key uuid not null,catalog_variant_id uuid not null,revision bigint not null check(revision>0),
 action text not null check(action in('assert','revoke')),
 condition_state text,grader_code text,grade_label text,grade_qualifier text,autograph_designation text,
 population_count bigint,population_scope text,
 observed_at timestamptz,observed_at_precision text not null check(observed_at_precision in('exact','date','unknown')),
 source_kind text not null check(source_kind in('manual','csv','api')),source_connection_id text,source_reference text,
 method text not null,method_version text not null,review_status text not null check(review_status in('reviewed','rejected')),
 supersedes_snapshot_id uuid,reason text not null,evidence jsonb not null,
 idempotency_key text not null,request_fingerprint text not null,reviewed_by uuid references auth.users(id),
 recorded_at timestamptz not null default clock_timestamp(),
 unique(organization_id,id),unique(organization_id,snapshot_key,revision),unique(organization_id,idempotency_key),
 foreign key(organization_id)references public.e10_organizations(id),
 foreign key(catalog_variant_id)references public.e10_catalog_variants(id),
 foreign key(organization_id,supersedes_snapshot_id)references public.e10_catalog_population_snapshots(organization_id,id),
 check((observed_at_precision='unknown'and observed_at is null)or(observed_at_precision in('exact','date')and observed_at is not null and isfinite(observed_at))),
 check((action='revoke'and num_nonnulls(condition_state,grader_code,grade_label,grade_qualifier,autograph_designation,population_count,population_scope)=0)
   or(action='assert'and population_count>=0 and length(btrim(population_scope))between 1 and 200
     and condition_state in('raw','graded','all_conditions')
     and(condition_state in('raw','all_conditions')and grader_code is null and grade_label is null and grade_qualifier is null
       or condition_state='graded'and grader_code is not null and grade_label is not null and length(btrim(grader_code))between 1 and 50 and length(btrim(grade_label))between 1 and 50))),
 check(action='revoke'or action='assert'and condition_state is not null and population_count is not null and population_scope is not null),
 check(length(btrim(method))between 1 and 100 and length(btrim(method_version))between 1 and 100),
 check(source_connection_id is null or length(btrim(source_connection_id))between 1 and 500),
 check(source_reference is null or length(btrim(source_reference))between 1 and 2000),
 check(grade_qualifier is null or length(btrim(grade_qualifier))between 1 and 200),
 check(autograph_designation is null or length(btrim(autograph_designation))between 1 and 200),
 check(length(btrim(reason))between 1 and 2000),check(jsonb_typeof(evidence)='object'and octet_length(evidence::text)<=65536),
 check(length(btrim(idempotency_key))between 1 and 500 and btrim(request_fingerprint)<>'')
);
create unique index e10_population_snapshot_successor_uq on public.e10_catalog_population_snapshots(organization_id,supersedes_snapshot_id)where supersedes_snapshot_id is not null;
create index e10_population_snapshot_variant_time_idx on public.e10_catalog_population_snapshots(organization_id,catalog_variant_id,observed_at desc,recorded_at desc,id);

create table public.e10_valuation_evidence(
 id uuid primary key default gen_random_uuid(),organization_id uuid not null,
 evidence_key uuid not null,revision bigint not null check(revision>0),action text not null check(action in('assert','revoke')),
 unique_item_id uuid,catalog_variant_id uuid,
 condition_state text,grader_code text,grade_label text,grade_qualifier text,autograph_designation text,
 method text not null,method_version text not null,currency text,amount numeric,
 observed_at timestamptz,observed_at_precision text not null check(observed_at_precision in('exact','date','unknown')),
 source_kind text not null check(source_kind in('manual','csv','api')),source_connection_id text,source_reference text,
 review_status text not null check(review_status in('reviewed','rejected')),
 supersedes_evidence_id uuid,reason text not null,input_evidence jsonb not null,
 idempotency_key text not null,request_fingerprint text not null,reviewed_by uuid references auth.users(id),
 recorded_at timestamptz not null default clock_timestamp(),
 unique(organization_id,id),unique(organization_id,evidence_key,revision),unique(organization_id,idempotency_key),
 foreign key(organization_id)references public.e10_organizations(id),
 foreign key(organization_id,unique_item_id)references public.e10_unique_items(organization_id,id),
 foreign key(catalog_variant_id)references public.e10_catalog_variants(id),
 foreign key(organization_id,supersedes_evidence_id)references public.e10_valuation_evidence(organization_id,id),
 check(num_nonnulls(unique_item_id,catalog_variant_id)=1),
 check((observed_at_precision='unknown'and observed_at is null)or(observed_at_precision in('exact','date')and observed_at is not null and isfinite(observed_at))),
 check((action='revoke'and num_nonnulls(condition_state,grader_code,grade_label,grade_qualifier,autograph_designation,currency,amount)=0)
   or(action='assert'and currency~'^[A-Z]{3}$'and amount>=0 and amount::text not in('NaN','Infinity','-Infinity')
     and condition_state in('raw','graded','all_conditions')
     and(condition_state in('raw','all_conditions')and grader_code is null and grade_label is null and grade_qualifier is null
       or condition_state='graded'and grader_code is not null and grade_label is not null and length(btrim(grader_code))between 1 and 50 and length(btrim(grade_label))between 1 and 50))),
 check(action='revoke'or action='assert'and condition_state is not null and currency is not null and amount is not null),
 check(length(btrim(method))between 1 and 100 and length(btrim(method_version))between 1 and 100),
 check(source_connection_id is null or length(btrim(source_connection_id))between 1 and 500),
 check(source_reference is null or length(btrim(source_reference))between 1 and 2000),
 check(grade_qualifier is null or length(btrim(grade_qualifier))between 1 and 200),
 check(autograph_designation is null or length(btrim(autograph_designation))between 1 and 200),
 check(length(btrim(reason))between 1 and 2000),check(jsonb_typeof(input_evidence)='object'and octet_length(input_evidence::text)<=65536),
 check(length(btrim(idempotency_key))between 1 and 500 and btrim(request_fingerprint)<>'')
);
create unique index e10_valuation_evidence_successor_uq on public.e10_valuation_evidence(organization_id,supersedes_evidence_id)where supersedes_evidence_id is not null;
create index e10_valuation_evidence_item_time_idx on public.e10_valuation_evidence(organization_id,unique_item_id,method,method_version,currency,observed_at desc,recorded_at desc,id)where unique_item_id is not null;
create index e10_valuation_evidence_variant_time_idx on public.e10_valuation_evidence(organization_id,catalog_variant_id,method,method_version,currency,observed_at desc,recorded_at desc,id)where catalog_variant_id is not null;

create table public.e10_inventory_disposition_links(
 id uuid primary key default gen_random_uuid(),organization_id uuid not null,
 disposition_key uuid not null,unique_item_id uuid not null,origin_event_id uuid not null,
 revision bigint not null check(revision>0),action text not null check(action in('assert','revoke')),
 disposition_kind text,disposed_at timestamptz,disposed_at_precision text not null,
 customer_transaction_id uuid,market_observation_id uuid,commercial_event_id uuid,
 supersedes_link_id uuid,reason text not null,evidence jsonb not null,
 idempotency_key text not null,request_fingerprint text not null,reviewed_by uuid references auth.users(id),
 recorded_at timestamptz not null default clock_timestamp(),
 unique(organization_id,id),unique(organization_id,disposition_key,revision),unique(organization_id,idempotency_key),
 foreign key(organization_id)references public.e10_organizations(id),
 foreign key(organization_id,unique_item_id)references public.e10_unique_items(organization_id,id),
 foreign key(organization_id,origin_event_id)references public.e10_commercial_events(organization_id,id),
 foreign key(organization_id,customer_transaction_id)references public.e10_customer_transactions(organization_id,id),
 foreign key(organization_id,market_observation_id)references public.e10_market_observations(organization_id,id),
 foreign key(organization_id,commercial_event_id)references public.e10_commercial_events(organization_id,id),
 foreign key(organization_id,supersedes_link_id)references public.e10_inventory_disposition_links(organization_id,id),
 check(disposed_at_precision in('exact','date','unknown')),
 check((disposed_at_precision='unknown'and disposed_at is null)or(disposed_at_precision in('exact','date')and disposed_at is not null and isfinite(disposed_at))),
 check((action='revoke'and disposition_kind is null and num_nonnulls(customer_transaction_id,market_observation_id,commercial_event_id)=0)
   or(action='assert'and disposition_kind in('sale','disposal','return')and num_nonnulls(customer_transaction_id,market_observation_id,commercial_event_id)=1)),
 check(action='revoke'or action='assert'and disposition_kind is not null),
 check(length(btrim(reason))between 1 and 2000),check(jsonb_typeof(evidence)='object'and octet_length(evidence::text)<=65536),
 check(length(btrim(idempotency_key))between 1 and 500 and btrim(request_fingerprint)<>'')
);
create unique index e10_inventory_disposition_successor_uq on public.e10_inventory_disposition_links(organization_id,supersedes_link_id)where supersedes_link_id is not null;
create unique index e10_inventory_disposition_episode_root_uq on public.e10_inventory_disposition_links(organization_id,unique_item_id,origin_event_id)where supersedes_link_id is null;
create index e10_inventory_disposition_item_time_idx on public.e10_inventory_disposition_links(organization_id,unique_item_id,disposed_at desc,recorded_at desc,id);

create table public.e10_inventory_reporting_revisions(
 organization_id uuid primary key references public.e10_organizations(id)on delete cascade,
 revision bigint not null default 1 check(revision>0),changed_at timestamptz not null default clock_timestamp()
);
insert into public.e10_inventory_reporting_revisions(organization_id)select id from public.e10_organizations on conflict do nothing;

do $$declare t text;begin foreach t in array array[
 'e10_unique_item_grade_assessments','e10_catalog_population_snapshots','e10_valuation_evidence',
 'e10_inventory_disposition_links','e10_inventory_reporting_revisions']loop
 execute format('alter table public.%I enable row level security',t);
 execute format('revoke all on public.%I from public,anon,authenticated',t);
 execute format('grant all on public.%I to service_role',t);
end loop;end $$;

do $$declare t text;begin foreach t in array array[
 'e10_unique_item_grade_assessments','e10_catalog_population_snapshots','e10_valuation_evidence','e10_inventory_disposition_links']loop
 execute format('create trigger %I before update or delete on public.%I for each row execute function e10.reject_append_only_change()',t||'_append_only',t);
end loop;end $$;

create view public.e10_current_unique_item_grade_assessments with(security_invoker=true)as
 select d.*from public.e10_unique_item_grade_assessments d where d.action='assert'and d.review_status='reviewed'
 and not exists(select 1 from public.e10_unique_item_grade_assessments n where n.organization_id=d.organization_id and n.supersedes_assessment_id=d.id);
create view public.e10_current_catalog_population_snapshots with(security_invoker=true)as
 select d.*from public.e10_catalog_population_snapshots d where d.action='assert'and d.review_status='reviewed'
 and not exists(select 1 from public.e10_catalog_population_snapshots n where n.organization_id=d.organization_id and n.supersedes_snapshot_id=d.id);
create view public.e10_current_valuation_evidence with(security_invoker=true)as
 select d.*from public.e10_valuation_evidence d where d.action='assert'and d.review_status='reviewed'
 and not exists(select 1 from public.e10_valuation_evidence n where n.organization_id=d.organization_id and n.supersedes_evidence_id=d.id);
create view public.e10_current_inventory_disposition_links with(security_invoker=true)as
 select d.*from public.e10_inventory_disposition_links d where d.action='assert'
 and not exists(select 1 from public.e10_inventory_disposition_links n where n.organization_id=d.organization_id and n.supersedes_link_id=d.id);
revoke all on public.e10_current_unique_item_grade_assessments,public.e10_current_catalog_population_snapshots,
 public.e10_current_valuation_evidence,public.e10_current_inventory_disposition_links from public,anon,authenticated;
grant select on public.e10_current_unique_item_grade_assessments,public.e10_current_catalog_population_snapshots,
 public.e10_current_valuation_evidence,public.e10_current_inventory_disposition_links to service_role;

create function e10.bump_inventory_reporting_revision()returns trigger language plpgsql security definer set search_path=public as $$
declare v_org uuid;begin
 v_org:=case when tg_op='DELETE'then old.organization_id else new.organization_id end;
 insert into public.e10_inventory_reporting_revisions(organization_id,revision,changed_at)values(v_org,1,clock_timestamp())
 on conflict(organization_id)do update set revision=public.e10_inventory_reporting_revisions.revision+1,changed_at=excluded.changed_at;
 return case when tg_op='DELETE'then old else new end;
end $$;
create function e10.initialize_inventory_reporting_revision()returns trigger language plpgsql security definer set search_path=public as $$
begin insert into public.e10_inventory_reporting_revisions(organization_id)values(new.id)on conflict do nothing;return new;end $$;
revoke all on function e10.bump_inventory_reporting_revision(),e10.initialize_inventory_reporting_revision()from public,anon,authenticated;
grant execute on function e10.bump_inventory_reporting_revision(),e10.initialize_inventory_reporting_revision()to service_role;
create trigger e10_inventory_reporting_revision_init after insert on public.e10_organizations for each row execute function e10.initialize_inventory_reporting_revision();

do $$declare t text;begin foreach t in array array[
 'e10_commercial_events','e10_unique_items','e10_inventory_items','e10_inventory_lots','e10_lot_cost_evidence',
 'e10_stock_receipts','e10_stock_receipt_lines','e10_stock_receipt_reversals','e10_customer_transactions',
 'e10_customer_transaction_lines','e10_customer_transaction_adjustments','e10_customer_transaction_component_finalizations',
 'e10_customer_transaction_attribution_decisions','e10_market_observations','e10_market_observation_supersessions',
 'e10_market_observation_fact_decisions','e10_market_observation_equivalence_decisions',
 'e10_unique_item_grade_assessments','e10_catalog_population_snapshots','e10_valuation_evidence','e10_inventory_disposition_links']loop
 execute format('create trigger %I after insert or update or delete on public.%I for each row execute function e10.bump_inventory_reporting_revision()',t||'_inventory_reporting_revision',t);
end loop;end $$;

comment on table public.e10_catalog_population_snapshots is'Provider population evidence. Population is not print run.';
comment on table public.e10_valuation_evidence is'Versioned estimate/index evidence. It is not a completed sale or accounting value.';
comment on table public.e10_inventory_disposition_links is'Reviewed reporting linkage only. It does not mutate stock, post a sale, or recognize accounting.';
