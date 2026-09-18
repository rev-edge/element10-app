-- TA-X7d.0c immutable tenant-private market evidence.
create table public.e10_unique_item_facet_decisions(
 id uuid primary key default gen_random_uuid(),organization_id uuid not null,decision_key uuid not null,
 unique_item_id uuid not null,subject_id uuid not null references public.e10_players(id),revision bigint not null check(revision>0),
 action text not null check(action in('assert','revoke')),jersey_match boolean,pictured_number text,team_reference text,season_reference text,marking_text text,
 supersedes_decision_id uuid,reason text not null check(length(btrim(reason))between 1 and 2000),evidence jsonb not null check(jsonb_typeof(evidence)='object'and octet_length(evidence::text)<=65536),
 idempotency_key text not null,request_fingerprint text not null check(btrim(request_fingerprint)<>''),reviewed_by uuid references auth.users(id),reviewed_at timestamptz not null default clock_timestamp(),
 unique(organization_id,id),unique(organization_id,decision_key,revision),unique(organization_id,idempotency_key),
 foreign key(organization_id,unique_item_id)references public.e10_unique_items(organization_id,id),foreign key(organization_id,supersedes_decision_id)references public.e10_unique_item_facet_decisions(organization_id,id),
 check((action='revoke'and jersey_match is null and pictured_number is null and team_reference is null and season_reference is null and marking_text is null)or(action='assert'and num_nonnulls(jersey_match,nullif(btrim(pictured_number),''),nullif(btrim(team_reference),''),nullif(btrim(season_reference),''),nullif(btrim(marking_text),''))>0 and(jersey_match is null or num_nonnulls(nullif(btrim(pictured_number),''),nullif(btrim(team_reference),''),nullif(btrim(season_reference),''),nullif(btrim(marking_text),''))>0))));
create unique index e10_unique_item_facet_root_uq on public.e10_unique_item_facet_decisions(organization_id,unique_item_id,subject_id)where supersedes_decision_id is null;
create unique index e10_unique_item_facet_successor_uq on public.e10_unique_item_facet_decisions(organization_id,supersedes_decision_id)where supersedes_decision_id is not null;

create table public.e10_market_observation_fact_decisions(
 id uuid primary key default gen_random_uuid(),organization_id uuid not null,decision_key uuid not null,observation_id uuid not null,
 revision bigint not null check(revision>0),action text not null check(action in('assert','revoke')),
 condition_state text check(condition_state in('raw','graded')),grader_code text,grade_label text,grade_qualifier text,
 serial_numerator integer check(serial_numerator is null or serial_numerator>0),serial_denominator integer check(serial_denominator is null or serial_denominator>0),
 jersey_match boolean,subject_id uuid references public.e10_players(id),pictured_number text,team_reference text,season_reference text,
 transaction_quantity numeric,amount_basis text check(amount_basis in('transaction_total','unit_price','unknown')),reviewed_unit_amount numeric,
 supersedes_decision_id uuid,reason text not null check(length(btrim(reason))between 1 and 2000),evidence jsonb not null check(jsonb_typeof(evidence)='object'and octet_length(evidence::text)<=65536),idempotency_key text not null,request_fingerprint text not null check(btrim(request_fingerprint)<>''),reviewed_by uuid references auth.users(id),reviewed_at timestamptz not null default clock_timestamp(),
 unique(organization_id,id),unique(organization_id,decision_key,revision),unique(organization_id,idempotency_key),foreign key(organization_id,observation_id)references public.e10_market_observations(organization_id,id),foreign key(organization_id,supersedes_decision_id)references public.e10_market_observation_fact_decisions(organization_id,id),
 check((action='revoke'and num_nonnulls(condition_state,grader_code,grade_label,grade_qualifier,serial_numerator,serial_denominator,jersey_match,subject_id,pictured_number,team_reference,season_reference,transaction_quantity,amount_basis,reviewed_unit_amount)=0)
 or(action='assert'and num_nonnulls(condition_state,serial_numerator,serial_denominator,jersey_match,transaction_quantity,amount_basis)>0
 and(transaction_quantity is null or(transaction_quantity>0 and transaction_quantity::text not in('NaN','Infinity','-Infinity')))
 and((condition_state is null and grader_code is null and grade_label is null and grade_qualifier is null)or(condition_state='raw'and grader_code is null and grade_label is null and grade_qualifier is null)or(condition_state='graded'and grader_code is not null and grade_label is not null and length(btrim(grader_code))between 1 and 50 and length(btrim(grade_label))between 1 and 50))
 and((serial_numerator is null and serial_denominator is null)or(serial_numerator is not null and serial_denominator is not null and serial_numerator<=serial_denominator))
 and((jersey_match is null and subject_id is null and pictured_number is null and team_reference is null and season_reference is null)or(jersey_match is not null and subject_id is not null and num_nonnulls(nullif(btrim(pictured_number),''),nullif(btrim(team_reference),''),nullif(btrim(season_reference),''))>0))
 and(reviewed_unit_amount is null or(reviewed_unit_amount>=0 and reviewed_unit_amount::text not in('NaN','Infinity','-Infinity')))
 and(amount_basis is not null or reviewed_unit_amount is null)
 and(amount_basis is distinct from 'unknown' or reviewed_unit_amount is null)
 and(amount_basis is distinct from 'unit_price' or reviewed_unit_amount is not null)
 and(reviewed_unit_amount is null or amount_basis='unit_price' or transaction_quantity is not null))));
create unique index e10_market_observation_fact_root_uq on public.e10_market_observation_fact_decisions(organization_id,observation_id)where supersedes_decision_id is null;
create unique index e10_market_observation_fact_successor_uq on public.e10_market_observation_fact_decisions(organization_id,supersedes_decision_id)where supersedes_decision_id is not null;
alter table public.e10_market_observation_fact_decisions add constraint e10_market_observation_fact_grading_shape_ck check((
 (condition_state is null and grader_code is null and grade_label is null and grade_qualifier is null)
 or(condition_state='raw'and grader_code is null and grade_label is null and grade_qualifier is null)
 or(condition_state='graded'and grader_code is not null and grade_label is not null and length(btrim(grader_code))between 1 and 50 and length(btrim(grade_label))between 1 and 50)
)is true);

create table public.e10_market_observation_equivalence_decisions(
 id uuid primary key default gen_random_uuid(),organization_id uuid not null,decision_key uuid not null,duplicate_observation_id uuid not null,canonical_observation_id uuid,
 revision bigint not null check(revision>0),action text not null check(action in('link','unlink')),duplicate_fingerprint text,canonical_fingerprint text,
 supersedes_decision_id uuid,reason text not null check(length(btrim(reason))between 1 and 2000),evidence jsonb not null check(jsonb_typeof(evidence)='object'and octet_length(evidence::text)<=65536),idempotency_key text not null,request_fingerprint text not null check(btrim(request_fingerprint)<>''),reviewed_by uuid references auth.users(id),reviewed_at timestamptz not null default clock_timestamp(),
 unique(organization_id,id),unique(organization_id,decision_key,revision),unique(organization_id,idempotency_key),foreign key(organization_id,duplicate_observation_id)references public.e10_market_observations(organization_id,id),foreign key(organization_id,canonical_observation_id)references public.e10_market_observations(organization_id,id),foreign key(organization_id,supersedes_decision_id)references public.e10_market_observation_equivalence_decisions(organization_id,id),
 check(duplicate_observation_id is distinct from canonical_observation_id),check((action='link'and canonical_observation_id is not null and duplicate_fingerprint is not null and canonical_fingerprint is not null)or(action='unlink'and canonical_observation_id is null and duplicate_fingerprint is null and canonical_fingerprint is null)));
create unique index e10_market_observation_equivalence_root_uq on public.e10_market_observation_equivalence_decisions(organization_id,duplicate_observation_id)where supersedes_decision_id is null;
create unique index e10_market_observation_equivalence_successor_uq on public.e10_market_observation_equivalence_decisions(organization_id,supersedes_decision_id)where supersedes_decision_id is not null;

create table public.e10_market_observation_coverage_decisions(
 id uuid primary key default gen_random_uuid(),organization_id uuid not null,decision_key uuid not null,
 observation_kind text not null check(observation_kind in('acquisition_cost','asking_price','completed_sale','estimated_value')),source_kind text not null check(source_kind in('manual','csv','native','api')),source_connection_id text,currency text not null check(currency~'^[A-Z]{3}$'),covered_from timestamptz not null check(isfinite(covered_from)),covered_to timestamptz not null check(isfinite(covered_to)and covered_to>covered_from),
 revision bigint not null check(revision>0),action text not null check(action in('assert','revoke')),coverage_status text check(coverage_status in('complete','partial','unavailable')),supersedes_decision_id uuid,
 reason text not null check(length(btrim(reason))between 1 and 2000),evidence jsonb not null check(jsonb_typeof(evidence)='object'and octet_length(evidence::text)<=65536),idempotency_key text not null,request_fingerprint text not null check(btrim(request_fingerprint)<>''),reviewed_by uuid references auth.users(id),reviewed_at timestamptz not null default clock_timestamp(),
 unique(organization_id,id),unique(organization_id,decision_key,revision),unique(organization_id,idempotency_key),foreign key(organization_id,supersedes_decision_id)references public.e10_market_observation_coverage_decisions(organization_id,id),check((action='assert'and coverage_status is not null)or(action='revoke'and coverage_status is null)));
create unique index e10_market_observation_coverage_root_uq on public.e10_market_observation_coverage_decisions(organization_id,observation_kind,source_kind,source_connection_id,currency,covered_from,covered_to)nulls not distinct where supersedes_decision_id is null;
create unique index e10_market_observation_coverage_successor_uq on public.e10_market_observation_coverage_decisions(organization_id,supersedes_decision_id)where supersedes_decision_id is not null;

do $$declare t text;begin foreach t in array array['e10_unique_item_facet_decisions','e10_market_observation_fact_decisions','e10_market_observation_equivalence_decisions','e10_market_observation_coverage_decisions']loop execute format('alter table public.%I enable row level security',t);execute format('revoke all on public.%I from public,anon,authenticated',t);execute format('grant all on public.%I to service_role',t);execute format('create trigger %I before update or delete on public.%I for each row execute function e10.reject_append_only_change()',t||'_append_only',t);end loop;end $$;

create function e10.market_observation_fact_signature(p_org uuid,p_observation uuid)returns text language sql stable security definer set search_path=public as $$
 select md5(jsonb_build_object(
  'condition_state',d.condition_state,'grader_code',d.grader_code,'grade_label',d.grade_label,'grade_qualifier',d.grade_qualifier,
  'serial_numerator',d.serial_numerator,'serial_denominator',d.serial_denominator,'jersey_match',d.jersey_match,'subject_id',d.subject_id,
  'pictured_number',d.pictured_number,'team_reference',d.team_reference,'season_reference',d.season_reference,
  'transaction_quantity',d.transaction_quantity,'amount_basis',d.amount_basis,'reviewed_unit_amount',d.reviewed_unit_amount)::text)
 from public.e10_market_observation_fact_decisions d
 where d.organization_id=p_org and d.observation_id=p_observation and d.action='assert'
 and not exists(select 1 from public.e10_market_observation_fact_decisions n where n.organization_id=d.organization_id and n.supersedes_decision_id=d.id)
$$;
revoke all on function e10.market_observation_fact_signature(uuid,uuid)from public,anon,authenticated;grant execute on function e10.market_observation_fact_signature(uuid,uuid)to service_role;

create function e10.market_observation_fingerprint(p_org uuid,p_observation uuid)returns text language sql stable security definer set search_path=public as $$
 select md5(jsonb_build_object(
  'id',o.id,'kind',o.observation_kind,'currency',o.currency,'amount',o.amount,'quantity',o.quantity,'occurred_at',o.occurred_at,
  'product',o.product_master_id,'configuration',o.configuration_version_id,'item',o.unique_item_id,'variant',o.catalog_variant_id,
  'fact_decision_id',f.id,'fact_revision',f.revision,'fact_signature',e10.market_observation_fact_signature(p_org,p_observation))::text)
 from public.e10_current_market_observations o
 left join public.e10_market_observation_fact_decisions f on f.organization_id=o.organization_id and f.observation_id=o.id and f.action='assert'
  and not exists(select 1 from public.e10_market_observation_fact_decisions n where n.organization_id=f.organization_id and n.supersedes_decision_id=f.id)
 where o.organization_id=p_org and o.id=p_observation
$$;
revoke all on function e10.market_observation_fingerprint(uuid,uuid)from public,anon,authenticated;grant execute on function e10.market_observation_fingerprint(uuid,uuid)to service_role;

create function e10.validate_market_evidence_insert()returns trigger language plpgsql security definer set search_path=public as $$
declare p record;v_duplicate record;v_canonical record;v_variant uuid;v_amount numeric;v_next uuid;v_seen uuid[];v_hops integer;v_upstream integer;
begin
 if new.supersedes_decision_id is null then if new.revision<>1 then raise exception using errcode='23514',message='market_evidence_root_revision_invalid';end if;
 else
  if new.supersedes_decision_id=new.id then raise exception using errcode='23514',message='market_evidence_self_successor';end if;
  if tg_table_name='e10_unique_item_facet_decisions'then select*into p from public.e10_unique_item_facet_decisions where organization_id=new.organization_id and id=new.supersedes_decision_id;if not found or p.decision_key<>new.decision_key or p.unique_item_id<>new.unique_item_id or p.subject_id<>new.subject_id or new.revision<>p.revision+1 then raise exception using errcode='23514',message='market_evidence_successor_invalid';end if;
  elsif tg_table_name='e10_market_observation_fact_decisions'then select*into p from public.e10_market_observation_fact_decisions where organization_id=new.organization_id and id=new.supersedes_decision_id;if not found or p.decision_key<>new.decision_key or p.observation_id<>new.observation_id or new.revision<>p.revision+1 then raise exception using errcode='23514',message='market_evidence_successor_invalid';end if;
  elsif tg_table_name='e10_market_observation_equivalence_decisions'then select*into p from public.e10_market_observation_equivalence_decisions where organization_id=new.organization_id and id=new.supersedes_decision_id;if not found or p.decision_key<>new.decision_key or p.duplicate_observation_id<>new.duplicate_observation_id or new.revision<>p.revision+1 then raise exception using errcode='23514',message='market_evidence_successor_invalid';end if;
  else select*into p from public.e10_market_observation_coverage_decisions where organization_id=new.organization_id and id=new.supersedes_decision_id;if not found or p.decision_key<>new.decision_key or p.observation_kind<>new.observation_kind or p.source_kind<>new.source_kind or p.source_connection_id is distinct from new.source_connection_id or p.currency<>new.currency or p.covered_from<>new.covered_from or p.covered_to<>new.covered_to or new.revision<>p.revision+1 then raise exception using errcode='23514',message='market_evidence_successor_invalid';end if;
  end if;
 end if;
 if tg_table_name='e10_unique_item_facet_decisions'then select catalog_variant_id into v_variant from public.e10_unique_items where organization_id=new.organization_id and id=new.unique_item_id;if v_variant is not null and not exists(select 1 from public.e10_catalog_variant_subjects where variant_id=v_variant and player_id=new.subject_id)then raise exception using errcode='23514',message='copy_subject_not_on_variant';end if;
 elsif tg_table_name='e10_market_observation_fact_decisions'and new.action='assert'then
  select mo.amount,coalesce(mo.catalog_variant_id,(select u.catalog_variant_id from public.e10_unique_items u where u.organization_id=mo.organization_id and u.id=mo.unique_item_id))into v_amount,v_variant from public.e10_market_observations mo where mo.organization_id=new.organization_id and mo.id=new.observation_id;
  if new.subject_id is not null and v_variant is not null and not exists(select 1 from public.e10_catalog_variant_subjects where variant_id=v_variant and player_id=new.subject_id)then raise exception using errcode='23514',message='observation_subject_not_on_variant';end if;
  if new.amount_basis='unknown'and new.reviewed_unit_amount is not null then raise exception using errcode='23514',message='unknown_amount_basis_has_unit_amount';end if;
  if new.amount_basis='unit_price'and new.reviewed_unit_amount is distinct from v_amount then raise exception using errcode='23514',message='unit_price_not_conserving';end if;
  if new.amount_basis='transaction_total'and new.reviewed_unit_amount is not null and new.reviewed_unit_amount*new.transaction_quantity<>v_amount then raise exception using errcode='23514',message='transaction_total_not_conserving';end if;
	 elsif tg_table_name='e10_market_observation_equivalence_decisions'and new.action='link'then
	  select*into v_duplicate from public.e10_current_market_observations where organization_id=new.organization_id and id=new.duplicate_observation_id;select*into v_canonical from public.e10_current_market_observations where organization_id=new.organization_id and id=new.canonical_observation_id;
	  if not found or v_duplicate.id is null or v_canonical.id is null or v_duplicate.observation_kind<>v_canonical.observation_kind or v_duplicate.currency<>v_canonical.currency or v_duplicate.amount<>v_canonical.amount or v_duplicate.quantity is distinct from v_canonical.quantity or v_duplicate.occurred_at<>v_canonical.occurred_at or v_duplicate.product_master_id is distinct from v_canonical.product_master_id or v_duplicate.configuration_version_id is distinct from v_canonical.configuration_version_id or v_duplicate.unique_item_id is distinct from v_canonical.unique_item_id or v_duplicate.catalog_variant_id is distinct from v_canonical.catalog_variant_id then raise exception using errcode='23514',message='observation_equivalence_incoherent';end if;
	  if e10.market_observation_fact_signature(new.organization_id,new.duplicate_observation_id)is distinct from e10.market_observation_fact_signature(new.organization_id,new.canonical_observation_id)then raise exception using errcode='23514',message='observation_equivalence_fact_incoherent';end if;
	  if new.duplicate_fingerprint<>e10.market_observation_fingerprint(new.organization_id,new.duplicate_observation_id)or new.canonical_fingerprint<>e10.market_observation_fingerprint(new.organization_id,new.canonical_observation_id)then raise exception using errcode='23514',message='observation_equivalence_fingerprint_mismatch';end if;
	  v_seen:=array[new.duplicate_observation_id];v_next:=new.canonical_observation_id;v_hops:=0;
	  loop
	   if v_next=any(v_seen)then raise exception using errcode='23514',message='observation_equivalence_cycle';end if;
	   v_seen:=array_append(v_seen,v_next);v_hops:=v_hops+1;
	   select d.canonical_observation_id into v_next from public.e10_market_observation_equivalence_decisions d
	   where d.organization_id=new.organization_id and d.duplicate_observation_id=v_next and d.action='link'
	   and not exists(select 1 from public.e10_market_observation_equivalence_decisions n where n.organization_id=d.organization_id and n.supersedes_decision_id=d.id);
	   exit when v_next is null;
	   if v_hops>=32 then raise exception using errcode='23514',message='observation_equivalence_depth_exceeded';end if;
	  end loop;
	  with recursive ancestors(id,depth)as(
	   select new.duplicate_observation_id,0
	   union all
	   select d.duplicate_observation_id,a.depth+1 from ancestors a join public.e10_market_observation_equivalence_decisions d
	   on d.organization_id=new.organization_id and d.canonical_observation_id=a.id and d.action='link'
	   and not exists(select 1 from public.e10_market_observation_equivalence_decisions n where n.organization_id=d.organization_id and n.supersedes_decision_id=d.id)
	   where a.depth<33
	  )select max(depth)into v_upstream from ancestors;
	  if v_upstream+v_hops>32 then raise exception using errcode='23514',message='observation_equivalence_depth_exceeded';end if;
	 end if;
 return new;
end $$;
revoke all on function e10.validate_market_evidence_insert()from public,anon,authenticated;grant execute on function e10.validate_market_evidence_insert()to service_role;
do $$declare t text;begin foreach t in array array['e10_unique_item_facet_decisions','e10_market_observation_fact_decisions','e10_market_observation_equivalence_decisions','e10_market_observation_coverage_decisions']loop execute format('create trigger %I before insert on public.%I for each row execute function e10.validate_market_evidence_insert()',t||'_insert_guard',t);end loop;end $$;

create view public.e10_current_unique_item_facets with(security_invoker=true)as select d.*from public.e10_unique_item_facet_decisions d where d.action='assert'and not exists(select 1 from public.e10_unique_item_facet_decisions n where n.organization_id=d.organization_id and n.supersedes_decision_id=d.id);
create view public.e10_current_market_observation_facts with(security_invoker=true)as select d.*from public.e10_market_observation_fact_decisions d where d.action='assert'and not exists(select 1 from public.e10_market_observation_fact_decisions n where n.organization_id=d.organization_id and n.supersedes_decision_id=d.id);
create view public.e10_market_observation_equivalence_status with(security_invoker=true)as
select d.*,case when d.duplicate_fingerprint=e10.market_observation_fingerprint(d.organization_id,d.duplicate_observation_id)
 and d.canonical_fingerprint=e10.market_observation_fingerprint(d.organization_id,d.canonical_observation_id)then'valid'else'review_required'end as review_status
from public.e10_market_observation_equivalence_decisions d where d.action='link'
and not exists(select 1 from public.e10_market_observation_equivalence_decisions n where n.organization_id=d.organization_id and n.supersedes_decision_id=d.id);
create view public.e10_current_market_observation_equivalences with(security_invoker=true)as select s.*from public.e10_market_observation_equivalence_status s where s.review_status='valid';
create view public.e10_current_market_observation_coverage with(security_invoker=true)as select d.*from public.e10_market_observation_coverage_decisions d where d.action='assert'and not exists(select 1 from public.e10_market_observation_coverage_decisions n where n.organization_id=d.organization_id and n.supersedes_decision_id=d.id);
revoke all on public.e10_current_unique_item_facets,public.e10_current_market_observation_facts,public.e10_market_observation_equivalence_status,public.e10_current_market_observation_equivalences,public.e10_current_market_observation_coverage from public,anon,authenticated;
grant select on public.e10_current_unique_item_facets,public.e10_current_market_observation_facts,public.e10_market_observation_equivalence_status,public.e10_current_market_observation_equivalences,public.e10_current_market_observation_coverage to service_role;

do $$declare t text;begin
 foreach t in array array['e10_unique_item_facet_decisions','e10_market_observation_fact_decisions','e10_market_observation_equivalence_decisions','e10_market_observation_coverage_decisions','e10_market_observations','e10_market_observation_supersessions','e10_unique_items']loop
  execute format('create trigger %I after insert or update or delete on public.%I for each row execute function e10.bump_market_org_revision()',t||'_market_revision',t);
 end loop;
end $$;
