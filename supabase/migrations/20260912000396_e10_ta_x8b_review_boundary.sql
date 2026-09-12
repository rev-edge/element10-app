-- TA-X8b.7 operation-specific preview authority and amend post-command recheck.

create function e10.x8b_preview_values(
 p_org uuid,p_operation text,p_values jsonb,p_allow_purchase_financial boolean,p_allow_contact boolean
)returns jsonb language plpgsql stable security definer set search_path=public as $$
declare line jsonb;projected jsonb;lines jsonb:='[]';allow_line_financial boolean;location_id uuid;
begin
 if p_operation='purchase_order.create'then
  return e10.x8b_redact_json(p_values,p_allow_purchase_financial,p_allow_contact);
 end if;
 if p_operation<>'customer_transaction.create_draft'then
  raise exception using errcode='22023',message='action_operation_unsupported';
 end if;
 projected:=p_values-'lines';
 for line in select value from jsonb_array_elements(coalesce(p_values->'lines','[]'))loop
  location_id:=nullif(line->>'location_id','')::uuid;
  allow_line_financial:=e10.can_view_customer_financials_at(p_org,location_id);
  lines:=lines||jsonb_build_array(e10.x8b_redact_json(line,allow_line_financial,p_allow_contact));
 end loop;
 return projected||jsonb_build_object('lines',lines);
end $$;

create or replace function public.e10_org_preview_action_draft(p_org uuid,p_draft_id uuid,p_revision integer)
returns jsonb language plpgsql security definer set search_path=public as $$
declare d record;r record;can_purchase_fin boolean;can_contact boolean;can_all_fin boolean;show_unstructured boolean;
begin
 if p_revision is null or p_revision<=0 then raise exception using errcode='22023',message='action_revision_invalid';end if;
 if not e10.x8b_authorized(p_org,p_draft_id,'preview')then raise exception using errcode='42501',message='action_preview_denied';end if;
 select * into d from public.e10_action_drafts where organization_id=p_org and id=p_draft_id;
 select * into r from public.e10_action_draft_revisions where organization_id=p_org and draft_id=p_draft_id and revision=p_revision;
 if not found then raise exception using errcode='22023',message='action_revision_not_found';end if;
 can_purchase_fin:=e10.has_org_cap(p_org,'financial.actual_cost.read');
 can_contact:=e10.has_org_cap(p_org,'act.manage_customers');
 if d.operation='purchase_order.create'then can_all_fin:=can_purchase_fin;
 else
  select not exists(
   select 1 from jsonb_array_elements(coalesce(r.proposed_values->'lines','[]'))line
   where not e10.can_view_customer_financials_at(p_org,nullif(line->>'location_id','')::uuid)
  )into can_all_fin;
 end if;
 show_unstructured:=can_contact and can_all_fin;
 return jsonb_build_object('draft_id',d.id,'operation',d.operation,'status',d.status,'current_revision',d.current_revision,'revision',r.revision,'approved_revision',d.approved_revision,
  'values',e10.x8b_preview_values(p_org,d.operation,r.proposed_values,can_purchase_fin,can_contact),'missing_fields',r.missing_fields,
  'field_provenance',case when show_unstructured then r.field_provenance else'{}'::jsonb end,
  'source_references',case when show_unstructured then r.source_references else'[]'::jsonb end,'reference_fingerprint',r.reference_fingerprint,
  'redactions',jsonb_build_object('financial',not can_all_fin,'contact_and_narrative',not can_contact,'unstructured_provenance',not show_unstructured));
end $$;

create or replace function public.e10_org_amend_action_draft(
 p_org uuid,p_draft_id uuid,p_expected_revision integer,p_values jsonb,p_field_provenance jsonb,p_source_references jsonb,p_idempotency_key text
)returns jsonb language plpgsql security definer set search_path=public as $$
declare d record;snap jsonb;fp text;old jsonb;result jsonb;nextrev integer;
begin
 if p_expected_revision is null or p_expected_revision<=0 then raise exception using errcode='22023',message='action_revision_invalid';end if;
 if not e10.x8b_authorized(p_org,p_draft_id,'amend')then raise exception using errcode='42501',message='action_amend_denied';end if;
 fp:=encode(extensions.digest(convert_to(jsonb_build_object('v','x8-action-amend-v1','draft',p_draft_id,'expected',p_expected_revision,'values',p_values,'provenance',p_field_provenance,'sources',p_source_references)::text,'UTF8'),'sha256'),'hex');
 old:=e10.x8b_command(p_org,p_idempotency_key,'amend',p_draft_id,fp);
 if not e10.x8b_authorized(p_org,p_draft_id,'amend')then raise exception using errcode='42501',message='action_amend_denied';end if;
 if old is not null then return old;end if;
 select * into d from public.e10_action_drafts where organization_id=p_org and id=p_draft_id for update;
 if not e10.x8b_authorized(p_org,p_draft_id,'amend')then raise exception using errcode='42501',message='action_amend_denied';end if;
 if not found or d.status not in('draft','approved')or d.current_revision<>p_expected_revision then raise exception using errcode='40001',message='action_revision_or_state_conflict';end if;
 snap:=e10.x8b_proposal_snapshot(p_org,d.operation,p_values,p_field_provenance,p_source_references);nextrev:=p_expected_revision+1;
 insert into public.e10_action_draft_revisions values(p_org,p_draft_id,nextrev,d.operation,snap->'values',array(select jsonb_array_elements_text(snap->'missing_fields')),p_field_provenance,p_source_references,snap->>'reference_fingerprint',fp,auth.uid(),statement_timestamp());
 update public.e10_action_drafts set current_revision=nextrev,status='draft',approved_revision=null,updated_at=statement_timestamp()where organization_id=p_org and id=p_draft_id;
 result:=jsonb_build_object('ok',true,'replay',false,'draft_id',p_draft_id,'revision',nextrev,'status','draft','missing_fields',snap->'missing_fields');
 insert into public.e10_action_draft_commands values(p_org,auth.uid(),p_idempotency_key,'amend',p_draft_id,fp,null,result,statement_timestamp());return result;
end $$;

comment on column public.e10_action_draft_revisions.source_references is
 'Opaque caller-supplied provenance retained internally and fingerprinted. Source connection/reference strings are not foreign keys or mutable registry validation; mutable first-party entities are separately mapped, fingerprinted and locked.';

revoke all on function e10.x8b_preview_values(uuid,text,jsonb,boolean,boolean)from public,anon,authenticated;
grant execute on function e10.x8b_preview_values(uuid,text,jsonb,boolean,boolean)to service_role;
revoke all on function public.e10_org_preview_action_draft(uuid,uuid,integer),public.e10_org_amend_action_draft(uuid,uuid,integer,jsonb,jsonb,jsonb,text)from public,anon;
grant execute on function public.e10_org_preview_action_draft(uuid,uuid,integer),public.e10_org_amend_action_draft(uuid,uuid,integer,jsonb,jsonb,jsonb,text)to authenticated,service_role;
