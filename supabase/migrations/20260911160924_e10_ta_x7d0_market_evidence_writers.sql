-- TA-X7d.0d self-authorizing tenant market-evidence writers.
alter table public.e10_unique_item_facet_decisions add constraint e10_unique_item_facet_text_bounds_ck check(
 (pictured_number is null or length(btrim(pictured_number))between 1 and 200)
 and(team_reference is null or length(btrim(team_reference))between 1 and 500)
 and(season_reference is null or length(btrim(season_reference))between 1 and 200)
 and(marking_text is null or length(btrim(marking_text))between 1 and 2000));
alter table public.e10_market_observation_fact_decisions add constraint e10_market_observation_fact_text_bounds_ck check(
 (grade_qualifier is null or length(btrim(grade_qualifier))between 1 and 200)
 and(pictured_number is null or length(btrim(pictured_number))between 1 and 200)
 and(team_reference is null or length(btrim(team_reference))between 1 and 500)
 and(season_reference is null or length(btrim(season_reference))between 1 and 200));
alter table public.e10_market_observation_coverage_decisions add constraint e10_market_observation_coverage_connection_bounds_ck check(source_connection_id is null or length(btrim(source_connection_id))between 1 and 500);

create or replace function e10.market_observation_fingerprint(p_org uuid,p_observation uuid)returns text language sql stable security definer set search_path=public as $$
 select md5(jsonb_build_object(
  'id',o.id,'kind',o.observation_kind,'currency',o.currency,'amount',o.amount,'quantity',o.quantity,'occurred_epoch',extract(epoch from o.occurred_at),
  'product',o.product_master_id,'configuration',o.configuration_version_id,'item',o.unique_item_id,'variant',o.catalog_variant_id,
  'fact_decision_id',f.id,'fact_revision',f.revision,'fact_signature',e10.market_observation_fact_signature(p_org,p_observation))::text)
 from public.e10_current_market_observations o
 left join public.e10_market_observation_fact_decisions f on f.organization_id=o.organization_id and f.observation_id=o.id and f.action='assert'
  and not exists(select 1 from public.e10_market_observation_fact_decisions n where n.organization_id=f.organization_id and n.supersedes_decision_id=f.id)
 where o.organization_id=p_org and o.id=p_observation
$$;
revoke all on function e10.market_observation_fingerprint(uuid,uuid)from public,anon,authenticated;grant execute on function e10.market_observation_fingerprint(uuid,uuid)to service_role;

create function public.e10_org_review_unique_item_facet(
 p_org uuid,p_decision_key uuid,p_unique_item_id uuid,p_subject_id uuid,p_expected_revision bigint,p_action text,
 p_jersey_match boolean,p_pictured_number text,p_team_reference text,p_season_reference text,p_marking_text text,
 p_reason text,p_evidence jsonb,p_idempotency_key text
)returns jsonb language plpgsql security definer set search_path=public as $$
declare v_actor uuid:=auth.uid();v_key uuid:=coalesce(p_decision_key,gen_random_uuid());v_prior record;v_replay record;v_id uuid:=gen_random_uuid();v_fp text;
begin
 if v_actor is null or not exists(select 1 from public.e10_organizations where id=p_org and status='active')or not e10.is_org_member(p_org)or not e10.has_org_cap(p_org,'act.curate_market_analytics')then raise exception using errcode='42501',message='market_evidence_curation_denied';end if;
 if p_org is null or p_unique_item_id is null or p_subject_id is null or p_expected_revision is null or p_expected_revision<0 or p_action is null or p_action not in('assert','revoke')or p_reason is null or length(btrim(p_reason))not between 1 and 2000 or p_evidence is null or jsonb_typeof(p_evidence)<>'object'or octet_length(p_evidence::text)>65536 or p_idempotency_key is null or length(btrim(p_idempotency_key))not between 1 and 500 then raise exception using errcode='22023',message='unique_item_facet_review_invalid';end if;
 v_fp:=md5(jsonb_build_object('v','unique-item-facet-v1','org',p_org,'key',p_decision_key,'item',p_unique_item_id,'subject',p_subject_id,'expected',p_expected_revision,'action',p_action,'jersey',p_jersey_match,'number',p_pictured_number,'team',p_team_reference,'season',p_season_reference,'marking',p_marking_text,'reason',btrim(p_reason),'evidence',p_evidence)::text);
 perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|unique-item-facet-idempotency|'||p_idempotency_key,0));
 if auth.uid()is distinct from v_actor or not exists(select 1 from public.e10_organizations where id=p_org and status='active')or not e10.is_org_member(p_org)or not e10.has_org_cap(p_org,'act.curate_market_analytics')then raise exception using errcode='42501',message='market_evidence_curation_denied';end if;
 select*into v_replay from public.e10_unique_item_facet_decisions where organization_id=p_org and idempotency_key=p_idempotency_key;
 if found then if v_replay.request_fingerprint<>v_fp then raise exception using errcode='22023',message='idempotency_key_mismatch';end if;return jsonb_build_object('ok',true,'replay',true,'decision_key',v_replay.decision_key,'revision',v_replay.revision);end if;
 perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|unique-item-facet|'||p_unique_item_id::text||'|'||p_subject_id::text,0));
 perform revision from public.e10_market_org_revisions where organization_id=p_org for update;
 if auth.uid()is distinct from v_actor or not exists(select 1 from public.e10_organizations where id=p_org and status='active')or not e10.is_org_member(p_org)or not e10.has_org_cap(p_org,'act.curate_market_analytics')then raise exception using errcode='42501',message='market_evidence_curation_denied';end if;
 select*into v_prior from public.e10_unique_item_facet_decisions d where d.organization_id=p_org and d.unique_item_id=p_unique_item_id and d.subject_id=p_subject_id and not exists(select 1 from public.e10_unique_item_facet_decisions n where n.organization_id=d.organization_id and n.supersedes_decision_id=d.id);
 if p_decision_key is null then if found or p_expected_revision<>0 or p_action<>'assert'then raise exception using errcode='22023',message='market_evidence_transition_invalid';end if;else if not found or v_prior.decision_key<>p_decision_key then raise exception using errcode='22023',message='market_evidence_key_invalid';end if;if v_prior.revision<>p_expected_revision then raise exception using errcode='40001',message='market_evidence_revision_conflict';end if;end if;
 insert into public.e10_unique_item_facet_decisions(id,organization_id,decision_key,unique_item_id,subject_id,revision,action,jersey_match,pictured_number,team_reference,season_reference,marking_text,supersedes_decision_id,reason,evidence,idempotency_key,request_fingerprint,reviewed_by)
 values(v_id,p_org,v_key,p_unique_item_id,p_subject_id,p_expected_revision+1,p_action,p_jersey_match,p_pictured_number,p_team_reference,p_season_reference,p_marking_text,v_prior.id,btrim(p_reason),p_evidence,p_idempotency_key,v_fp,v_actor);
 return jsonb_build_object('ok',true,'replay',false,'decision_key',v_key,'decision_id',v_id,'revision',p_expected_revision+1);
end $$;

create function public.e10_org_review_market_observation_fact(
 p_org uuid,p_decision_key uuid,p_observation_id uuid,p_expected_revision bigint,p_action text,p_condition_state text,p_grader_code text,p_grade_label text,p_grade_qualifier text,
 p_serial_numerator integer,p_serial_denominator integer,p_jersey_match boolean,p_subject_id uuid,p_pictured_number text,p_team_reference text,p_season_reference text,
 p_transaction_quantity numeric,p_amount_basis text,p_reviewed_unit_amount numeric,p_reason text,p_evidence jsonb,p_idempotency_key text
)returns jsonb language plpgsql security definer set search_path=public as $$
declare v_actor uuid:=auth.uid();v_key uuid:=coalesce(p_decision_key,gen_random_uuid());v_prior record;v_replay record;v_id uuid:=gen_random_uuid();v_fp text;
begin
 if v_actor is null or not exists(select 1 from public.e10_organizations where id=p_org and status='active')or not e10.is_org_member(p_org)or not e10.has_org_cap(p_org,'act.curate_market_analytics')then raise exception using errcode='42501',message='market_evidence_curation_denied';end if;
 if p_org is null or p_observation_id is null or p_expected_revision is null or p_expected_revision<0 or p_action is null or p_action not in('assert','revoke')or p_reason is null or length(btrim(p_reason))not between 1 and 2000 or p_evidence is null or jsonb_typeof(p_evidence)<>'object'or octet_length(p_evidence::text)>65536 or p_idempotency_key is null or length(btrim(p_idempotency_key))not between 1 and 500 then raise exception using errcode='22023',message='market_observation_fact_review_invalid';end if;
 v_fp:=md5(jsonb_build_object('v','market-observation-fact-v1','org',p_org,'key',p_decision_key,'observation',p_observation_id,'expected',p_expected_revision,'action',p_action,'condition',p_condition_state,'grader',p_grader_code,'grade',p_grade_label,'qualifier',p_grade_qualifier,'serial_n',p_serial_numerator,'serial_d',p_serial_denominator,'jersey',p_jersey_match,'subject',p_subject_id,'number',p_pictured_number,'team',p_team_reference,'season',p_season_reference,'quantity',p_transaction_quantity,'basis',p_amount_basis,'unit',p_reviewed_unit_amount,'reason',btrim(p_reason),'evidence',p_evidence)::text);
 perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|market-fact-idempotency|'||p_idempotency_key,0));
 if auth.uid()is distinct from v_actor or not exists(select 1 from public.e10_organizations where id=p_org and status='active')or not e10.is_org_member(p_org)or not e10.has_org_cap(p_org,'act.curate_market_analytics')then raise exception using errcode='42501',message='market_evidence_curation_denied';end if;
 select*into v_replay from public.e10_market_observation_fact_decisions where organization_id=p_org and idempotency_key=p_idempotency_key;if found then if v_replay.request_fingerprint<>v_fp then raise exception using errcode='22023',message='idempotency_key_mismatch';end if;return jsonb_build_object('ok',true,'replay',true,'decision_key',v_replay.decision_key,'revision',v_replay.revision);end if;
 perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|market-fact|'||p_observation_id::text,0));perform revision from public.e10_market_org_revisions where organization_id=p_org for update;
 if auth.uid()is distinct from v_actor or not exists(select 1 from public.e10_organizations where id=p_org and status='active')or not e10.is_org_member(p_org)or not e10.has_org_cap(p_org,'act.curate_market_analytics')then raise exception using errcode='42501',message='market_evidence_curation_denied';end if;
 select*into v_prior from public.e10_market_observation_fact_decisions d where d.organization_id=p_org and d.observation_id=p_observation_id and not exists(select 1 from public.e10_market_observation_fact_decisions n where n.organization_id=d.organization_id and n.supersedes_decision_id=d.id);
 if p_decision_key is null then if found or p_expected_revision<>0 or p_action<>'assert'then raise exception using errcode='22023',message='market_evidence_transition_invalid';end if;else if not found or v_prior.decision_key<>p_decision_key then raise exception using errcode='22023',message='market_evidence_key_invalid';end if;if v_prior.revision<>p_expected_revision then raise exception using errcode='40001',message='market_evidence_revision_conflict';end if;end if;
 insert into public.e10_market_observation_fact_decisions(id,organization_id,decision_key,observation_id,revision,action,condition_state,grader_code,grade_label,grade_qualifier,serial_numerator,serial_denominator,jersey_match,subject_id,pictured_number,team_reference,season_reference,transaction_quantity,amount_basis,reviewed_unit_amount,supersedes_decision_id,reason,evidence,idempotency_key,request_fingerprint,reviewed_by)
 values(v_id,p_org,v_key,p_observation_id,p_expected_revision+1,p_action,p_condition_state,p_grader_code,p_grade_label,p_grade_qualifier,p_serial_numerator,p_serial_denominator,p_jersey_match,p_subject_id,p_pictured_number,p_team_reference,p_season_reference,p_transaction_quantity,p_amount_basis,p_reviewed_unit_amount,v_prior.id,btrim(p_reason),p_evidence,p_idempotency_key,v_fp,v_actor);
 return jsonb_build_object('ok',true,'replay',false,'decision_key',v_key,'decision_id',v_id,'revision',p_expected_revision+1);
end $$;

create function public.e10_org_review_market_observation_equivalence(p_org uuid,p_decision_key uuid,p_duplicate_observation_id uuid,p_canonical_observation_id uuid,p_expected_revision bigint,p_action text,p_reason text,p_evidence jsonb,p_idempotency_key text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_actor uuid:=auth.uid();v_key uuid:=coalesce(p_decision_key,gen_random_uuid());v_prior record;v_replay record;v_id uuid:=gen_random_uuid();v_fp text;v_df text;v_cf text;
begin
 if v_actor is null or not exists(select 1 from public.e10_organizations where id=p_org and status='active')or not e10.is_org_member(p_org)or not e10.has_org_cap(p_org,'act.curate_market_analytics')then raise exception using errcode='42501',message='market_evidence_curation_denied';end if;
 if p_org is null or p_duplicate_observation_id is null or p_expected_revision is null or p_expected_revision<0 or p_action is null or p_action not in('link','unlink')or(p_action='link'and p_canonical_observation_id is null)or(p_action='unlink'and p_canonical_observation_id is not null)or p_reason is null or length(btrim(p_reason))not between 1 and 2000 or p_evidence is null or jsonb_typeof(p_evidence)<>'object'or octet_length(p_evidence::text)>65536 or p_idempotency_key is null or length(btrim(p_idempotency_key))not between 1 and 500 then raise exception using errcode='22023',message='market_equivalence_review_invalid';end if;
 v_fp:=md5(jsonb_build_object('v','market-equivalence-v1','org',p_org,'key',p_decision_key,'duplicate',p_duplicate_observation_id,'canonical',p_canonical_observation_id,'expected',p_expected_revision,'action',p_action,'reason',btrim(p_reason),'evidence',p_evidence)::text);
 perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|market-equivalence-idempotency|'||p_idempotency_key,0));
 if auth.uid()is distinct from v_actor or not exists(select 1 from public.e10_organizations where id=p_org and status='active')or not e10.is_org_member(p_org)or not e10.has_org_cap(p_org,'act.curate_market_analytics')then raise exception using errcode='42501',message='market_evidence_curation_denied';end if;
 select*into v_replay from public.e10_market_observation_equivalence_decisions where organization_id=p_org and idempotency_key=p_idempotency_key;if found then if v_replay.request_fingerprint<>v_fp then raise exception using errcode='22023',message='idempotency_key_mismatch';end if;return jsonb_build_object('ok',true,'replay',true,'decision_key',v_replay.decision_key,'revision',v_replay.revision);end if;
 perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|market-equivalence-graph',0));perform revision from public.e10_market_org_revisions where organization_id=p_org for update;
 if auth.uid()is distinct from v_actor or not exists(select 1 from public.e10_organizations where id=p_org and status='active')or not e10.is_org_member(p_org)or not e10.has_org_cap(p_org,'act.curate_market_analytics')then raise exception using errcode='42501',message='market_evidence_curation_denied';end if;
 select*into v_prior from public.e10_market_observation_equivalence_decisions d where d.organization_id=p_org and d.duplicate_observation_id=p_duplicate_observation_id and not exists(select 1 from public.e10_market_observation_equivalence_decisions n where n.organization_id=d.organization_id and n.supersedes_decision_id=d.id);
 if p_decision_key is null then if found or p_expected_revision<>0 or p_action<>'link'then raise exception using errcode='22023',message='market_evidence_transition_invalid';end if;else if not found or v_prior.decision_key<>p_decision_key then raise exception using errcode='22023',message='market_evidence_key_invalid';end if;if v_prior.revision<>p_expected_revision then raise exception using errcode='40001',message='market_evidence_revision_conflict';end if;end if;
 if p_action='link'then v_df:=e10.market_observation_fingerprint(p_org,p_duplicate_observation_id);v_cf:=e10.market_observation_fingerprint(p_org,p_canonical_observation_id);end if;
 insert into public.e10_market_observation_equivalence_decisions(id,organization_id,decision_key,duplicate_observation_id,canonical_observation_id,revision,action,duplicate_fingerprint,canonical_fingerprint,supersedes_decision_id,reason,evidence,idempotency_key,request_fingerprint,reviewed_by)
 values(v_id,p_org,v_key,p_duplicate_observation_id,p_canonical_observation_id,p_expected_revision+1,p_action,v_df,v_cf,v_prior.id,btrim(p_reason),p_evidence,p_idempotency_key,v_fp,v_actor);
 return jsonb_build_object('ok',true,'replay',false,'decision_key',v_key,'decision_id',v_id,'revision',p_expected_revision+1);
end $$;

create function public.e10_org_review_market_observation_coverage(p_org uuid,p_decision_key uuid,p_observation_kind text,p_source_kind text,p_source_connection_id text,p_currency text,p_covered_from timestamptz,p_covered_to timestamptz,p_expected_revision bigint,p_action text,p_coverage_status text,p_reason text,p_evidence jsonb,p_idempotency_key text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_actor uuid:=auth.uid();v_key uuid:=coalesce(p_decision_key,gen_random_uuid());v_prior record;v_replay record;v_id uuid:=gen_random_uuid();v_fp text;
begin
 if v_actor is null or not exists(select 1 from public.e10_organizations where id=p_org and status='active')or not e10.is_org_member(p_org)or not e10.has_org_cap(p_org,'act.curate_market_analytics')then raise exception using errcode='42501',message='market_evidence_curation_denied';end if;
 if p_org is null or p_observation_kind is null or p_source_kind is null or p_currency is null or p_covered_from is null or p_covered_to is null or p_expected_revision is null or p_expected_revision<0 or p_action is null or p_action not in('assert','revoke')or p_reason is null or length(btrim(p_reason))not between 1 and 2000 or p_evidence is null or jsonb_typeof(p_evidence)<>'object'or octet_length(p_evidence::text)>65536 or p_idempotency_key is null or length(btrim(p_idempotency_key))not between 1 and 500 then raise exception using errcode='22023',message='market_coverage_review_invalid';end if;
 v_fp:=md5(jsonb_build_object('v','market-coverage-v1','org',p_org,'key',p_decision_key,'kind',p_observation_kind,'source_kind',p_source_kind,'connection',p_source_connection_id,'currency',p_currency,'from_epoch',extract(epoch from p_covered_from),'to_epoch',extract(epoch from p_covered_to),'expected',p_expected_revision,'action',p_action,'status',p_coverage_status,'reason',btrim(p_reason),'evidence',p_evidence)::text);
 perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|market-coverage-idempotency|'||p_idempotency_key,0));
 if auth.uid()is distinct from v_actor or not exists(select 1 from public.e10_organizations where id=p_org and status='active')or not e10.is_org_member(p_org)or not e10.has_org_cap(p_org,'act.curate_market_analytics')then raise exception using errcode='42501',message='market_evidence_curation_denied';end if;
 select*into v_replay from public.e10_market_observation_coverage_decisions where organization_id=p_org and idempotency_key=p_idempotency_key;if found then if v_replay.request_fingerprint<>v_fp then raise exception using errcode='22023',message='idempotency_key_mismatch';end if;return jsonb_build_object('ok',true,'replay',true,'decision_key',v_replay.decision_key,'revision',v_replay.revision);end if;
 perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|market-coverage|'||p_observation_kind||'|'||p_source_kind||'|'||coalesce(p_source_connection_id,'')||'|'||p_currency||'|'||extract(epoch from p_covered_from)::text||'|'||extract(epoch from p_covered_to)::text,0));perform revision from public.e10_market_org_revisions where organization_id=p_org for update;
 if auth.uid()is distinct from v_actor or not exists(select 1 from public.e10_organizations where id=p_org and status='active')or not e10.is_org_member(p_org)or not e10.has_org_cap(p_org,'act.curate_market_analytics')then raise exception using errcode='42501',message='market_evidence_curation_denied';end if;
 select*into v_prior from public.e10_market_observation_coverage_decisions d where d.organization_id=p_org and d.observation_kind=p_observation_kind and d.source_kind=p_source_kind and d.source_connection_id is not distinct from p_source_connection_id and d.currency=p_currency and d.covered_from=p_covered_from and d.covered_to=p_covered_to and not exists(select 1 from public.e10_market_observation_coverage_decisions n where n.organization_id=d.organization_id and n.supersedes_decision_id=d.id);
 if p_decision_key is null then if found or p_expected_revision<>0 or p_action<>'assert'then raise exception using errcode='22023',message='market_evidence_transition_invalid';end if;else if not found or v_prior.decision_key<>p_decision_key then raise exception using errcode='22023',message='market_evidence_key_invalid';end if;if v_prior.revision<>p_expected_revision then raise exception using errcode='40001',message='market_evidence_revision_conflict';end if;end if;
 insert into public.e10_market_observation_coverage_decisions(id,organization_id,decision_key,observation_kind,source_kind,source_connection_id,currency,covered_from,covered_to,revision,action,coverage_status,supersedes_decision_id,reason,evidence,idempotency_key,request_fingerprint,reviewed_by)
 values(v_id,p_org,v_key,p_observation_kind,p_source_kind,p_source_connection_id,p_currency,p_covered_from,p_covered_to,p_expected_revision+1,p_action,p_coverage_status,v_prior.id,btrim(p_reason),p_evidence,p_idempotency_key,v_fp,v_actor);
 return jsonb_build_object('ok',true,'replay',false,'decision_key',v_key,'decision_id',v_id,'revision',p_expected_revision+1);
end $$;

revoke all on function public.e10_org_review_unique_item_facet(uuid,uuid,uuid,uuid,bigint,text,boolean,text,text,text,text,text,jsonb,text)from public,anon;
grant execute on function public.e10_org_review_unique_item_facet(uuid,uuid,uuid,uuid,bigint,text,boolean,text,text,text,text,text,jsonb,text)to authenticated,service_role;
revoke all on function public.e10_org_review_market_observation_fact(uuid,uuid,uuid,bigint,text,text,text,text,text,integer,integer,boolean,uuid,text,text,text,numeric,text,numeric,text,jsonb,text)from public,anon;
grant execute on function public.e10_org_review_market_observation_fact(uuid,uuid,uuid,bigint,text,text,text,text,text,integer,integer,boolean,uuid,text,text,text,numeric,text,numeric,text,jsonb,text)to authenticated,service_role;
revoke all on function public.e10_org_review_market_observation_equivalence(uuid,uuid,uuid,uuid,bigint,text,text,jsonb,text)from public,anon;
grant execute on function public.e10_org_review_market_observation_equivalence(uuid,uuid,uuid,uuid,bigint,text,text,jsonb,text)to authenticated,service_role;
revoke all on function public.e10_org_review_market_observation_coverage(uuid,uuid,text,text,text,text,timestamptz,timestamptz,bigint,text,text,text,jsonb,text)from public,anon;
grant execute on function public.e10_org_review_market_observation_coverage(uuid,uuid,text,text,text,text,timestamptz,timestamptz,bigint,text,text,text,jsonb,text)to authenticated,service_role;

comment on function public.e10_org_review_market_observation_equivalence(uuid,uuid,uuid,uuid,bigint,text,text,jsonb,text)is'Tenant-private reviewed equivalence writer. Serializes the organization graph before validation; reserved act.curate_market_analytics has no default grant.';
