-- Return the stable client-to-stored line identity map from every public
-- document writer that scopes caller UUIDs. Callers must not have to infer it.
create function e10.scoped_line_id_map(p_org uuid,p_lines jsonb,p_relation regclass)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare sanitized jsonb;result jsonb;
begin
 if p_lines is null or jsonb_typeof(p_lines)<>'array'then return'[]'::jsonb;end if;
 sanitized:=e10.sanitize_scoped_line_ids(p_org,p_lines,p_relation);
 select coalesce(jsonb_agg(jsonb_build_object('client_id',source.value->>'id','stored_id',target.value->>'id')order by source.ordinality),'[]'::jsonb)
 into result from jsonb_array_elements(p_lines)with ordinality source(value,ordinality)
 join jsonb_array_elements(sanitized)with ordinality target(value,ordinality)using(ordinality)
 where source.value?'id';
 return result;
end$$;
revoke all on function e10.scoped_line_id_map(uuid,jsonb,regclass)from public,anon,authenticated;
grant execute on function e10.scoped_line_id_map(uuid,jsonb,regclass)to service_role;

create or replace function public.e10_org_create_purchase_order(p_org uuid,p_supplier_id uuid,p_destination_location_id uuid,p_order_number text,p_currency text,p_expected_at timestamptz,p_lines jsonb,p_idempotency_key text)
returns jsonb language plpgsql security definer set search_path=public as $$declare mapped jsonb;result jsonb;begin
 mapped:=e10.sanitize_scoped_line_ids(p_org,p_lines,'public.e10_purchase_order_lines'::regclass);
 result:=public._e10_org_create_purchase_order_r6(p_org,p_supplier_id,p_destination_location_id,p_order_number,p_currency,p_expected_at,mapped,p_idempotency_key);
 return result||jsonb_build_object('line_id_map',e10.scoped_line_id_map(p_org,p_lines,'public.e10_purchase_order_lines'::regclass));
end$$;
create or replace function public.e10_org_amend_purchase_order(p_org uuid,p_purchase_order_id uuid,p_expected_revision integer,p_supplier_id uuid,p_destination_location_id uuid,p_order_number text,p_currency text,p_expected_at timestamptz,p_lines jsonb,p_reason text,p_idempotency_key text)
returns jsonb language plpgsql security definer set search_path=public as $$declare mapped jsonb;result jsonb;begin
 mapped:=e10.sanitize_scoped_line_ids(p_org,p_lines,'public.e10_purchase_order_lines'::regclass);
 result:=public._e10_org_amend_purchase_order_r6(p_org,p_purchase_order_id,p_expected_revision,p_supplier_id,p_destination_location_id,p_order_number,p_currency,p_expected_at,mapped,p_reason,p_idempotency_key);
 return result||jsonb_build_object('line_id_map',e10.scoped_line_id_map(p_org,p_lines,'public.e10_purchase_order_lines'::regclass));
end$$;
create or replace function public.e10_org_create_supplier_invoice(p_org uuid,p_supplier_id uuid,p_supplier_document_number text,p_currency text,p_document_date date,p_total_amount numeric,p_source_connection text,p_external_document_id text,p_payload_fingerprint text,p_duplicate_review_outcome text,p_duplicate_review_reason text,p_lines jsonb,p_idempotency_key text)
returns jsonb language plpgsql security definer set search_path=public as $$declare result jsonb;begin
 result:=public._e10_org_create_financial_document_x3d1a(p_org,'supplier_invoice',p_supplier_id,p_supplier_document_number,p_currency,p_document_date,p_total_amount,p_source_connection,p_external_document_id,p_payload_fingerprint,p_duplicate_review_outcome,p_duplicate_review_reason,p_lines,p_idempotency_key);
 return result||jsonb_build_object('line_id_map',e10.scoped_line_id_map(p_org,p_lines,'public.e10_supplier_invoice_lines'::regclass));
end$$;
create or replace function public.e10_org_amend_supplier_invoice(p_org uuid,p_supplier_invoice_id uuid,p_expected_revision integer,p_currency text,p_document_date date,p_total_amount numeric,p_lines jsonb,p_reason text,p_idempotency_key text)
returns jsonb language plpgsql security definer set search_path=public as $$declare result jsonb;begin
 result:=public._e10_org_amend_financial_document_x3d1b(p_org,'supplier_invoice',p_supplier_invoice_id,p_expected_revision,p_currency,p_document_date,p_total_amount,p_lines,p_reason,p_idempotency_key);
 return result||jsonb_build_object('line_id_map',e10.scoped_line_id_map(p_org,p_lines,'public.e10_supplier_invoice_lines'::regclass));
end$$;

