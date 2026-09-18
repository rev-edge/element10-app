-- Correct X6d.3 lock order: reconciliation decisions and draft posting that
-- contend for one source component acquire the same source lock first.
alter function public.e10_org_decide_customer_transaction_reconciliation(uuid,uuid,integer,text,text,uuid,uuid,text,jsonb,text)
 rename to e10_org_decide_customer_transaction_reconciliation_x6d3_impl;

revoke all on function public.e10_org_decide_customer_transaction_reconciliation_x6d3_impl(uuid,uuid,integer,text,text,uuid,uuid,text,jsonb,text)from public,anon,authenticated;
grant execute on function public.e10_org_decide_customer_transaction_reconciliation_x6d3_impl(uuid,uuid,integer,text,text,uuid,uuid,text,jsonb,text)to service_role;

create function public.e10_org_decide_customer_transaction_reconciliation(
 p_org uuid,p_case uuid,p_expected_revision integer,p_action text,p_match_basis text,p_transaction_id uuid,p_transaction_line_id uuid,
 p_reason text,p_evidence jsonb,p_idempotency_key text
)returns jsonb language plpgsql security definer set search_path=public as $$
declare v_case record;
begin
 if not e10.is_org_member(p_org)or not e10.has_org_cap(p_org,'act.reconcile_customer_transactions')then raise exception using errcode='42501',message='decide_customer_reconciliation_denied';end if;
 if p_idempotency_key is null or btrim(p_idempotency_key)=''then raise exception using errcode='22023',message='customer_reconciliation_decision_invalid';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|customer-commercial|'||p_idempotency_key,0));
 select source_kind,source_connection_id,source_component_id into v_case from public.e10_customer_transaction_reconciliation_cases where organization_id=p_org and id=p_case;
 if found then perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|posted|source|'||v_case.source_kind||'|'||coalesce(v_case.source_connection_id,'')||'|'||v_case.source_component_id,0));end if;
 return public.e10_org_decide_customer_transaction_reconciliation_x6d3_impl(p_org,p_case,p_expected_revision,p_action,p_match_basis,p_transaction_id,p_transaction_line_id,p_reason,p_evidence,p_idempotency_key);
end $$;

revoke all on function public.e10_org_decide_customer_transaction_reconciliation(uuid,uuid,integer,text,text,uuid,uuid,text,jsonb,text)from public,anon;
grant execute on function public.e10_org_decide_customer_transaction_reconciliation(uuid,uuid,integer,text,text,uuid,uuid,text,jsonb,text)to authenticated,service_role;
comment on function public.e10_org_decide_customer_transaction_reconciliation(uuid,uuid,integer,text,text,uuid,uuid,text,jsonb,text)is'X6d.3 decision API with source-identity lock ordered before the existing reviewed decision implementation, preventing link/revoke versus post deadlocks.';
