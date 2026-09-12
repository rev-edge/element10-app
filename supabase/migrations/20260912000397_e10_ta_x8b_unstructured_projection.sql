-- TA-X8b.8 unstructured values require every relevant permission; incomplete arrays remain previewable.

create or replace function e10.x8b_preview_values(
 p_org uuid,p_operation text,p_values jsonb,p_allow_purchase_financial boolean,p_allow_contact boolean
)returns jsonb language plpgsql stable security definer set search_path=public as $$
declare line jsonb;projected jsonb;lines jsonb:='[]';input_lines jsonb;allow_line_financial boolean;allow_all_financial boolean:=true;location_id uuid;
begin
 if p_operation='purchase_order.create'then
  return e10.x8b_redact_json(p_values,p_allow_purchase_financial,p_allow_contact and p_allow_purchase_financial);
 end if;
 if p_operation<>'customer_transaction.create_draft'then raise exception using errcode='22023',message='action_operation_unsupported';end if;
 input_lines:=case when jsonb_typeof(p_values->'lines')='array'then p_values->'lines'else'[]'::jsonb end;
 projected:=(p_values-'lines')-'note';
 for line in select value from jsonb_array_elements(input_lines)loop
  location_id:=nullif(line->>'location_id','')::uuid;
  allow_line_financial:=e10.can_view_customer_financials_at(p_org,location_id);
  allow_all_financial:=allow_all_financial and allow_line_financial;
  lines:=lines||jsonb_build_array(e10.x8b_redact_json(line,allow_line_financial,p_allow_contact and allow_line_financial));
 end loop;
 if p_allow_contact and allow_all_financial and p_values?'note'then projected:=projected||jsonb_build_object('note',p_values->'note');end if;
 return projected||jsonb_build_object('lines',lines);
end $$;

create or replace function public.e10_org_preview_action_draft(p_org uuid,p_draft_id uuid,p_revision integer)
returns jsonb language plpgsql security definer set search_path=public as $$
declare d record;r record;can_purchase_fin boolean;can_contact boolean;can_all_fin boolean;show_unstructured boolean;input_lines jsonb;
begin
 if p_revision is null or p_revision<=0 then raise exception using errcode='22023',message='action_revision_invalid';end if;
 if not e10.x8b_authorized(p_org,p_draft_id,'preview')then raise exception using errcode='42501',message='action_preview_denied';end if;
 select * into d from public.e10_action_drafts where organization_id=p_org and id=p_draft_id;
 select * into r from public.e10_action_draft_revisions where organization_id=p_org and draft_id=p_draft_id and revision=p_revision;
 if not found then raise exception using errcode='22023',message='action_revision_not_found';end if;
 can_purchase_fin:=e10.has_org_cap(p_org,'financial.actual_cost.read');can_contact:=e10.has_org_cap(p_org,'act.manage_customers');
 if d.operation='purchase_order.create'then can_all_fin:=can_purchase_fin;
 else
  input_lines:=case when jsonb_typeof(r.proposed_values->'lines')='array'then r.proposed_values->'lines'else'[]'::jsonb end;
  select not exists(select 1 from jsonb_array_elements(input_lines)line where not e10.can_view_customer_financials_at(p_org,nullif(line->>'location_id','')::uuid))into can_all_fin;
 end if;
 show_unstructured:=can_contact and can_all_fin;
 return jsonb_build_object('draft_id',d.id,'operation',d.operation,'status',d.status,'current_revision',d.current_revision,'revision',r.revision,'approved_revision',d.approved_revision,
  'values',e10.x8b_preview_values(p_org,d.operation,r.proposed_values,can_purchase_fin,can_contact),'missing_fields',r.missing_fields,
  'field_provenance',case when show_unstructured then r.field_provenance else'{}'::jsonb end,
  'source_references',case when show_unstructured then r.source_references else'[]'::jsonb end,'reference_fingerprint',r.reference_fingerprint,
  'redactions',jsonb_build_object('financial',not can_all_fin,'contact_and_narrative',not can_contact,'unstructured_provenance',not show_unstructured));
end $$;

revoke all on function e10.x8b_preview_values(uuid,text,jsonb,boolean,boolean)from public,anon,authenticated;
grant execute on function e10.x8b_preview_values(uuid,text,jsonb,boolean,boolean)to service_role;
revoke all on function public.e10_org_preview_action_draft(uuid,uuid,integer)from public,anon;
grant execute on function public.e10_org_preview_action_draft(uuid,uuid,integer)to authenticated,service_role;
