-- TA-R6 14g: a client-supplied line UUID that exists only in another tenant
-- is treated exactly like a new UUID. It is replaced before the legacy writer
-- performs any global identity check or insert, removing the existence oracle.

create function e10.sanitize_scoped_line_ids(p_org uuid,p_lines jsonb,p_relation regclass)
returns jsonb language plpgsql security definer set search_path=public as $$
declare element jsonb;candidate uuid;foreign_collision boolean;result jsonb:='[]'::jsonb;
begin
  if p_lines is null or jsonb_typeof(p_lines)<>'array' then return p_lines;end if;
  for element in select value from jsonb_array_elements(p_lines) loop
    if jsonb_typeof(element)='object' and element ? 'id' then
      begin candidate:=(element->>'id')::uuid;
      exception when invalid_text_representation then candidate:=null;end;
      if candidate is not null then
        execute format('select exists(select 1 from %s where id=$1 and organization_id<>$2)',p_relation)
          into foreign_collision using candidate,p_org;
        if foreign_collision then
          element:=jsonb_set(element,'{id}',to_jsonb(gen_random_uuid()::text));
        end if;
      end if;
    end if;
    result:=result||jsonb_build_array(element);
  end loop;
  return result;
end $$;
revoke all on function e10.sanitize_scoped_line_ids(uuid,jsonb,regclass) from public,anon,authenticated;
grant execute on function e10.sanitize_scoped_line_ids(uuid,jsonb,regclass) to service_role;

alter function public.e10_org_create_purchase_order(uuid,uuid,uuid,text,text,timestamptz,jsonb,text)
rename to _e10_org_create_purchase_order_r6;
revoke all on function public._e10_org_create_purchase_order_r6(uuid,uuid,uuid,text,text,timestamptz,jsonb,text) from public,anon,authenticated;
grant execute on function public._e10_org_create_purchase_order_r6(uuid,uuid,uuid,text,text,timestamptz,jsonb,text) to service_role;
create function public.e10_org_create_purchase_order(p_org uuid,p_supplier_id uuid,p_destination_location_id uuid,p_order_number text,p_currency text,p_expected_at timestamptz,p_lines jsonb,p_idempotency_key text)
returns jsonb language sql security definer set search_path=public as $$
 select public._e10_org_create_purchase_order_r6(p_org,p_supplier_id,p_destination_location_id,p_order_number,p_currency,p_expected_at,e10.sanitize_scoped_line_ids(p_org,p_lines,'public.e10_purchase_order_lines'::regclass),p_idempotency_key)
$$;

alter function public.e10_org_amend_purchase_order(uuid,uuid,integer,uuid,uuid,text,text,timestamptz,jsonb,text,text)
rename to _e10_org_amend_purchase_order_r6;
revoke all on function public._e10_org_amend_purchase_order_r6(uuid,uuid,integer,uuid,uuid,text,text,timestamptz,jsonb,text,text) from public,anon,authenticated;
grant execute on function public._e10_org_amend_purchase_order_r6(uuid,uuid,integer,uuid,uuid,text,text,timestamptz,jsonb,text,text) to service_role;
create function public.e10_org_amend_purchase_order(p_org uuid,p_purchase_order_id uuid,p_expected_revision integer,p_supplier_id uuid,p_destination_location_id uuid,p_order_number text,p_currency text,p_expected_at timestamptz,p_lines jsonb,p_reason text,p_idempotency_key text)
returns jsonb language sql security definer set search_path=public as $$
 select public._e10_org_amend_purchase_order_r6(p_org,p_purchase_order_id,p_expected_revision,p_supplier_id,p_destination_location_id,p_order_number,p_currency,p_expected_at,e10.sanitize_scoped_line_ids(p_org,p_lines,'public.e10_purchase_order_lines'::regclass),p_reason,p_idempotency_key)
$$;

alter function public._e10_org_create_financial_document_x3d1a(uuid,text,uuid,text,text,date,numeric,text,text,text,text,text,jsonb,text)
rename to _e10_org_create_financial_document_r6;
revoke all on function public._e10_org_create_financial_document_r6(uuid,text,uuid,text,text,date,numeric,text,text,text,text,text,jsonb,text) from public,anon,authenticated;
grant execute on function public._e10_org_create_financial_document_r6(uuid,text,uuid,text,text,date,numeric,text,text,text,text,text,jsonb,text) to service_role;
create function public._e10_org_create_financial_document_x3d1a(p_org uuid,p_document_kind text,p_supplier_id uuid,p_supplier_document_number text,p_currency text,p_document_date date,p_total_amount numeric,p_source_connection text,p_external_document_id text,p_payload_fingerprint text,p_duplicate_review_outcome text,p_duplicate_review_reason text,p_lines jsonb,p_idempotency_key text)
returns jsonb language sql security definer set search_path=public as $$
 select public._e10_org_create_financial_document_r6(p_org,p_document_kind,p_supplier_id,p_supplier_document_number,p_currency,p_document_date,p_total_amount,p_source_connection,p_external_document_id,p_payload_fingerprint,p_duplicate_review_outcome,p_duplicate_review_reason,e10.sanitize_scoped_line_ids(p_org,p_lines,case p_document_kind when 'supplier_invoice' then 'public.e10_supplier_invoice_lines'::regclass else 'public.e10_supplier_credit_lines'::regclass end),p_idempotency_key)
$$;

alter function public._e10_org_amend_financial_document_x3d1b(uuid,text,uuid,integer,text,date,numeric,jsonb,text,text)
rename to _e10_org_amend_financial_document_r6;
revoke all on function public._e10_org_amend_financial_document_r6(uuid,text,uuid,integer,text,date,numeric,jsonb,text,text) from public,anon,authenticated;
grant execute on function public._e10_org_amend_financial_document_r6(uuid,text,uuid,integer,text,date,numeric,jsonb,text,text) to service_role;
create function public._e10_org_amend_financial_document_x3d1b(p_org uuid,p_document_kind text,p_document_id uuid,p_expected_revision integer,p_currency text,p_document_date date,p_total_amount numeric,p_lines jsonb,p_reason text,p_idempotency_key text)
returns jsonb language sql security definer set search_path=public as $$
 select public._e10_org_amend_financial_document_r6(p_org,p_document_kind,p_document_id,p_expected_revision,p_currency,p_document_date,p_total_amount,e10.sanitize_scoped_line_ids(p_org,p_lines,case p_document_kind when 'supplier_invoice' then 'public.e10_supplier_invoice_lines'::regclass else 'public.e10_supplier_credit_lines'::regclass end),p_reason,p_idempotency_key)
$$;

revoke all on function public.e10_org_create_purchase_order(uuid,uuid,uuid,text,text,timestamptz,jsonb,text),public.e10_org_amend_purchase_order(uuid,uuid,integer,uuid,uuid,text,text,timestamptz,jsonb,text,text) from public,anon;
grant execute on function public.e10_org_create_purchase_order(uuid,uuid,uuid,text,text,timestamptz,jsonb,text),public.e10_org_amend_purchase_order(uuid,uuid,integer,uuid,uuid,text,text,timestamptz,jsonb,text,text) to authenticated,service_role;
revoke all on function public._e10_org_create_financial_document_x3d1a(uuid,text,uuid,text,text,date,numeric,text,text,text,text,text,jsonb,text),public._e10_org_amend_financial_document_x3d1b(uuid,text,uuid,integer,text,date,numeric,jsonb,text,text) from public,anon,authenticated;
grant execute on function public._e10_org_create_financial_document_x3d1a(uuid,text,uuid,text,text,date,numeric,text,text,text,text,text,jsonb,text),public._e10_org_amend_financial_document_x3d1b(uuid,text,uuid,integer,text,date,numeric,jsonb,text,text) to service_role;
