-- TA-R6 14b: retain full-cohort totals on an empty trailing v1 page.
alter function public.e10_org_customer_spend_summary(uuid,timestamptz,timestamptz,timestamptz,text,text,integer,uuid,text,uuid,text,uuid,uuid,uuid,uuid,text,integer,uuid,bigint,text) rename to _e10_org_customer_spend_summary_r6;
revoke all on function public._e10_org_customer_spend_summary_r6(uuid,timestamptz,timestamptz,timestamptz,text,text,integer,uuid,text,uuid,text,uuid,uuid,uuid,uuid,text,integer,uuid,bigint,text) from public,anon,authenticated;
grant execute on function public._e10_org_customer_spend_summary_r6(uuid,timestamptz,timestamptz,timestamptz,text,text,integer,uuid,text,uuid,text,uuid,uuid,uuid,uuid,text,integer,uuid,bigint,text) to service_role;
create function public.e10_org_customer_spend_summary(p_org uuid,p_from timestamptz,p_to timestamptz,p_observation_cutoff timestamptz,p_currency text,p_timezone text,p_week_start integer,p_customer uuid,p_purchase_kind text,p_location uuid,p_channel text,p_product uuid,p_configuration uuid,p_copy uuid,p_session uuid,p_capture_source text,p_limit integer,p_after_customer_id uuid,p_expected_dataset_revision bigint,p_expected_query_fingerprint text)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare result jsonb;anchor jsonb;
begin
 result:=public._e10_org_customer_spend_summary_r6(p_org,p_from,p_to,p_observation_cutoff,p_currency,p_timezone,p_week_start,p_customer,p_purchase_kind,p_location,p_channel,p_product,p_configuration,p_copy,p_session,p_capture_source,p_limit,p_after_customer_id,p_expected_dataset_revision,p_expected_query_fingerprint);
 if p_after_customer_id is not null and jsonb_array_length(coalesce(result->'items','[]'))=0 then
  anchor:=public._e10_org_customer_spend_summary_r6(p_org,p_from,p_to,p_observation_cutoff,p_currency,p_timezone,p_week_start,p_customer,p_purchase_kind,p_location,p_channel,p_product,p_configuration,p_copy,p_session,p_capture_source,p_limit,null,p_expected_dataset_revision,p_expected_query_fingerprint);
  result:=jsonb_set(result,'{full_cohort_totals}',coalesce(anchor->'full_cohort_totals','{}'));
 end if;
 return result;
end$$;
revoke all on function public.e10_org_customer_spend_summary(uuid,timestamptz,timestamptz,timestamptz,text,text,integer,uuid,text,uuid,text,uuid,uuid,uuid,uuid,text,integer,uuid,bigint,text) from public,anon;
grant execute on function public.e10_org_customer_spend_summary(uuid,timestamptz,timestamptz,timestamptz,text,text,integer,uuid,text,uuid,text,uuid,uuid,uuid,uuid,text,integer,uuid,bigint,text) to authenticated,service_role;
