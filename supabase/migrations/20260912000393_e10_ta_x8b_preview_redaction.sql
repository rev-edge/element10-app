-- TA-X8b.4 permission-aware recursive proposal preview projection.

create function e10.x8b_redact_json(p_value jsonb,p_allow_financial boolean,p_allow_contact boolean)
returns jsonb language plpgsql immutable security definer set search_path=public as $$
declare k text;v jsonb;out_value jsonb;begin
 if p_value is null then return null;end if;
 if jsonb_typeof(p_value)='array'then select coalesce(jsonb_agg(e10.x8b_redact_json(value,p_allow_financial,p_allow_contact)),'[]')into out_value from jsonb_array_elements(p_value);return out_value;end if;
 if jsonb_typeof(p_value)<>'object'then return p_value;end if;
 out_value:='{}';
 for k,v in select key,value from jsonb_each(p_value)loop
  if not p_allow_financial and k in('cost','estimated_unit_cost','actual_cost','unit_cost','amount','price','value','currency','merchandise_gross','merchandise_discount','shipping_amount','tax_amount','merchandise_net')then continue;end if;
  if not p_allow_contact and k in('contact','email','phone','address','note','text','raw_evidence','raw_payload','payload')then continue;end if;
  out_value:=out_value||jsonb_build_object(k,e10.x8b_redact_json(v,p_allow_financial,p_allow_contact));
 end loop;
 return out_value;
end $$;

create or replace function public.e10_org_preview_action_draft(p_org uuid,p_draft_id uuid,p_revision integer)
returns jsonb language plpgsql security definer set search_path=public as $$
declare d record;r record;can_fin boolean;can_contact boolean;begin
 if p_revision is null or p_revision<=0 then raise exception using errcode='22023',message='action_revision_invalid';end if;
 if not e10.x8b_authorized(p_org,p_draft_id,'preview')then raise exception using errcode='42501',message='action_preview_denied';end if;
 select * into d from public.e10_action_drafts where organization_id=p_org and id=p_draft_id;
 select * into r from public.e10_action_draft_revisions where organization_id=p_org and draft_id=p_draft_id and revision=p_revision;
 if not found then raise exception using errcode='22023',message='action_revision_not_found';end if;
 can_fin:=e10.has_org_cap(p_org,'financial.actual_cost.read');can_contact:=e10.has_org_cap(p_org,'act.manage_customers');
 return jsonb_build_object('draft_id',d.id,'operation',d.operation,'status',d.status,'current_revision',d.current_revision,'revision',r.revision,'approved_revision',d.approved_revision,
  'values',e10.x8b_redact_json(r.proposed_values,can_fin,can_contact),'missing_fields',r.missing_fields,
  'field_provenance',e10.x8b_redact_json(r.field_provenance,can_fin,can_contact),
  'source_references',e10.x8b_redact_json(r.source_references,can_fin,can_contact),'reference_fingerprint',r.reference_fingerprint,
  'redactions',jsonb_build_object('financial',not can_fin,'contact_and_narrative',not can_contact));
end $$;

revoke all on function e10.x8b_redact_json(jsonb,boolean,boolean)from public,anon,authenticated;
grant execute on function e10.x8b_redact_json(jsonb,boolean,boolean)to service_role;
revoke all on function public.e10_org_preview_action_draft(uuid,uuid,integer)from public,anon;
grant execute on function public.e10_org_preview_action_draft(uuid,uuid,integer)to authenticated,service_role;
