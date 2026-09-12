-- Complete the R6 scoped-line response contract for supplier credits.

create or replace function public.e10_org_create_supplier_credit(
  p_org uuid,p_supplier_id uuid,p_supplier_document_number text,p_currency text,p_document_date date,
  p_total_amount numeric,p_source_connection text,p_external_document_id text,p_payload_fingerprint text,
  p_duplicate_review_outcome text,p_duplicate_review_reason text,p_lines jsonb,p_idempotency_key text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare result jsonb;
begin
  result:=public._e10_org_create_financial_document_x3d1a(p_org,'supplier_credit',p_supplier_id,
    p_supplier_document_number,p_currency,p_document_date,p_total_amount,p_source_connection,
    p_external_document_id,p_payload_fingerprint,p_duplicate_review_outcome,p_duplicate_review_reason,
    p_lines,p_idempotency_key);
  return result||jsonb_build_object('line_id_map',
    e10.scoped_line_id_map(p_org,p_lines,'public.e10_supplier_credit_lines'::regclass));
end $$;

create or replace function public.e10_org_amend_supplier_credit(
  p_org uuid,p_supplier_credit_id uuid,p_expected_revision integer,p_currency text,
  p_document_date date,p_total_amount numeric,p_lines jsonb,p_reason text,p_idempotency_key text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare result jsonb;
begin
  result:=public._e10_org_amend_financial_document_x3d1b(p_org,'supplier_credit',p_supplier_credit_id,
    p_expected_revision,p_currency,p_document_date,p_total_amount,p_lines,p_reason,p_idempotency_key);
  return result||jsonb_build_object('line_id_map',
    e10.scoped_line_id_map(p_org,p_lines,'public.e10_supplier_credit_lines'::regclass));
end $$;

revoke all on function public.e10_org_create_supplier_credit(
  uuid,uuid,text,text,date,numeric,text,text,text,text,text,jsonb,text
) from public,anon;
grant execute on function public.e10_org_create_supplier_credit(
  uuid,uuid,text,text,date,numeric,text,text,text,text,text,jsonb,text
) to authenticated,service_role;

revoke all on function public.e10_org_amend_supplier_credit(
  uuid,uuid,integer,text,date,numeric,jsonb,text,text
) from public,anon;
grant execute on function public.e10_org_amend_supplier_credit(
  uuid,uuid,integer,text,date,numeric,jsonb,text,text
) to authenticated,service_role;
