-- TA-R6 14i/14j: stable identity-input errors and literal customer search.
alter function public.e10_platform_propose_player_identity_review(text,text,text,text,text,text,jsonb,jsonb,text,jsonb,text) rename to _e10_platform_propose_player_identity_review_r6;
revoke all on function public._e10_platform_propose_player_identity_review_r6(text,text,text,text,text,text,jsonb,jsonb,text,jsonb,text) from public,anon,authenticated;
grant execute on function public._e10_platform_propose_player_identity_review_r6(text,text,text,text,text,text,jsonb,jsonb,text,jsonb,text) to service_role;
create function public.e10_platform_propose_player_identity_review(p_source_namespace text,p_source_key text,p_source_display_name text,p_proposer_kind text,p_proposer_name text,p_proposer_version text,p_source_evidence jsonb,p_candidates jsonb,p_reason text,p_evidence jsonb,p_idempotency_key text)returns jsonb
language plpgsql security definer set search_path=public as $$begin
  return public._e10_platform_propose_player_identity_review_r6(p_source_namespace,p_source_key,p_source_display_name,p_proposer_kind,p_proposer_name,p_proposer_version,p_source_evidence,p_candidates,p_reason,p_evidence,p_idempotency_key);
exception when invalid_text_representation or foreign_key_violation then raise exception using errcode='22023',message='player_identity_review_candidate_invalid';end$$;

alter function public.e10_platform_review_variant_subject_context(uuid,uuid,uuid,bigint,text,text,uuid,text,text,text,jsonb,text) rename to _e10_platform_review_variant_subject_context_r6;
revoke all on function public._e10_platform_review_variant_subject_context_r6(uuid,uuid,uuid,bigint,text,text,uuid,text,text,text,jsonb,text) from public,anon,authenticated;
grant execute on function public._e10_platform_review_variant_subject_context_r6(uuid,uuid,uuid,bigint,text,text,uuid,text,text,text,jsonb,text) to service_role;
create function public.e10_platform_review_variant_subject_context(p_decision_key uuid,p_variant_id uuid,p_player_id uuid,p_expected_revision bigint,p_action text,p_context_status text,p_depicted_team_id uuid,p_source_kind text,p_source_reference text,p_reason text,p_evidence jsonb,p_idempotency_key text)returns jsonb
language plpgsql security definer set search_path=public as $$begin
  return public._e10_platform_review_variant_subject_context_r6(p_decision_key,p_variant_id,p_player_id,p_expected_revision,p_action,p_context_status,p_depicted_team_id,p_source_kind,p_source_reference,p_reason,p_evidence,p_idempotency_key);
exception when foreign_key_violation then raise exception using errcode='22023',message='variant_subject_context_target_invalid';end$$;

create or replace function public.e10_org_find_customers(p_org uuid,p_query text,p_limit integer default 25)
returns table(customer_id uuid,display_name text,status text,matched_identity_kind text,matched_channel text,matched_value text)
language plpgsql stable security definer set search_path=public as $$
declare literal_query text;
begin
  if not e10.is_org_member(p_org)or not e10.has_org_cap(p_org,'act.manage_customers')then raise exception using errcode='42501',message='find_customers_denied';end if;
  if p_query is null or length(btrim(p_query))<2 or p_limit is null or p_limit<1 or p_limit>100 then raise exception using errcode='22023',message='customer_query_invalid';end if;
  literal_query:=replace(replace(replace(lower(btrim(p_query)),'\','\\'),'%','\%'),'_','\_');
  return query select c.id,c.display_name,c.status,m.identity_kind,m.channel,coalesce(m.external_account_id,m.alias_text)
  from public.e10_customers c left join lateral(
    select i.identity_kind,i.channel,i.external_account_id,i.alias_text from public.e10_current_effective_customer_identities i
    where i.organization_id=c.organization_id and i.effective_customer_id=c.id and i.identity_action='attach'
      and lower(coalesce(i.external_account_id,i.alias_text,''))like'%'||literal_query||'%'escape'\'
    order by i.decided_at desc,i.id desc limit 1)m on true
  where c.organization_id=p_org and c.status='active'and e10.customer_effective_id(p_org,c.id)=c.id
    and(lower(c.display_name)like'%'||literal_query||'%'escape'\'or m.identity_kind is not null)
  order by lower(c.display_name),c.id limit p_limit;
end$$;

revoke all on function public.e10_platform_propose_player_identity_review(text,text,text,text,text,text,jsonb,jsonb,text,jsonb,text),public.e10_platform_review_variant_subject_context(uuid,uuid,uuid,bigint,text,text,uuid,text,text,text,jsonb,text),public.e10_org_find_customers(uuid,text,integer) from public,anon;
grant execute on function public.e10_platform_propose_player_identity_review(text,text,text,text,text,text,jsonb,jsonb,text,jsonb,text),public.e10_platform_review_variant_subject_context(uuid,uuid,uuid,bigint,text,text,uuid,text,text,text,jsonb,text),public.e10_org_find_customers(uuid,text,integer) to authenticated,service_role;
