-- TA-X8b.5 explicit revision validation and post-lock authorization ordering.

create or replace function public.e10_org_approve_action_draft(
 p_org uuid,p_draft_id uuid,p_expected_revision integer,p_idempotency_key text
)returns jsonb language plpgsql security definer set search_path=public as $$
declare d record;r record;snap jsonb;fp text;old jsonb;result jsonb;
begin
 if p_expected_revision is null or p_expected_revision<=0 then raise exception using errcode='22023',message='action_revision_invalid';end if;
 if not e10.x8b_authorized(p_org,p_draft_id,'approve')then raise exception using errcode='42501',message='action_approve_denied';end if;
 fp:=encode(extensions.digest(convert_to(jsonb_build_object('v','x8-action-approve-v1','draft',p_draft_id,'revision',p_expected_revision)::text,'UTF8'),'sha256'),'hex');
 old:=e10.x8b_command(p_org,p_idempotency_key,'approve',p_draft_id,fp);
 if not e10.x8b_authorized(p_org,p_draft_id,'approve')then raise exception using errcode='42501',message='action_approve_denied';end if;
 if old is not null then return old;end if;
 select * into d from public.e10_action_drafts where organization_id=p_org and id=p_draft_id for update;
 if not e10.x8b_authorized(p_org,p_draft_id,'approve')then raise exception using errcode='42501',message='action_approve_denied';end if;
 if not found or d.status<>'draft'or d.current_revision<>p_expected_revision then raise exception using errcode='40001',message='action_revision_or_state_conflict';end if;
 select * into r from public.e10_action_draft_revisions where organization_id=p_org and draft_id=p_draft_id and revision=p_expected_revision;
 if cardinality(r.missing_fields)>0 then raise exception using errcode='22023',message='action_required_fields_missing';end if;
 snap:=e10.x8b_proposal_snapshot(p_org,d.operation,r.proposed_values,r.field_provenance,r.source_references);
 if snap->>'reference_fingerprint'<>r.reference_fingerprint or jsonb_array_length(snap->'missing_fields')>0 then raise exception using errcode='40001',message='action_references_stale';end if;
 insert into public.e10_action_draft_decisions(organization_id,draft_id,revision,decision_action,decided_by)values(p_org,p_draft_id,p_expected_revision,'approve',auth.uid());
 update public.e10_action_drafts set status='approved',approved_revision=p_expected_revision,updated_at=statement_timestamp()where organization_id=p_org and id=p_draft_id;
 result:=jsonb_build_object('ok',true,'replay',false,'draft_id',p_draft_id,'revision',p_expected_revision,'status','approved');
 insert into public.e10_action_draft_commands values(p_org,auth.uid(),p_idempotency_key,'approve',p_draft_id,fp,null,result,statement_timestamp());return result;
end $$;

create or replace function public.e10_org_cancel_action_draft(
 p_org uuid,p_draft_id uuid,p_expected_revision integer,p_reason text,p_idempotency_key text
)returns jsonb language plpgsql security definer set search_path=public as $$
declare d record;fp text;old jsonb;result jsonb;
begin
 if p_expected_revision is null or p_expected_revision<=0 then raise exception using errcode='22023',message='action_revision_invalid';end if;
 if not e10.x8b_authorized(p_org,p_draft_id,'cancel')then raise exception using errcode='42501',message='action_cancel_denied';end if;
 if coalesce(btrim(p_reason),'')=''or length(p_reason)>2000 then raise exception using errcode='22023',message='action_cancel_reason_invalid';end if;
 fp:=encode(extensions.digest(convert_to(jsonb_build_object('v','x8-action-cancel-v1','draft',p_draft_id,'revision',p_expected_revision,'reason',btrim(p_reason))::text,'UTF8'),'sha256'),'hex');
 old:=e10.x8b_command(p_org,p_idempotency_key,'cancel',p_draft_id,fp);
 if not e10.x8b_authorized(p_org,p_draft_id,'cancel')then raise exception using errcode='42501',message='action_cancel_denied';end if;
 if old is not null then return old;end if;
 select * into d from public.e10_action_drafts where organization_id=p_org and id=p_draft_id for update;
 if not e10.x8b_authorized(p_org,p_draft_id,'cancel')then raise exception using errcode='42501',message='action_cancel_denied';end if;
 if not found or d.status not in('draft','approved')or d.current_revision<>p_expected_revision then raise exception using errcode='40001',message='action_revision_or_state_conflict';end if;
 insert into public.e10_action_draft_decisions(organization_id,draft_id,revision,decision_action,reason,decided_by)values(p_org,p_draft_id,p_expected_revision,'cancel',btrim(p_reason),auth.uid());
 update public.e10_action_drafts set status='cancelled',approved_revision=null,cancelled_at=statement_timestamp(),updated_at=statement_timestamp()where organization_id=p_org and id=p_draft_id;
 result:=jsonb_build_object('ok',true,'replay',false,'draft_id',p_draft_id,'revision',p_expected_revision,'status','cancelled');
 insert into public.e10_action_draft_commands values(p_org,auth.uid(),p_idempotency_key,'cancel',p_draft_id,fp,null,result,statement_timestamp());return result;
end $$;

create or replace function public.e10_org_commit_action_draft(
 p_org uuid,p_draft_id uuid,p_expected_revision integer,p_idempotency_key text
)returns jsonb language plpgsql security definer set search_path=public as $$
declare d record;r record;snap jsonb;fp text;old jsonb;result jsonb;downkey text;
begin
 if p_expected_revision is null or p_expected_revision<=0 then raise exception using errcode='22023',message='action_revision_invalid';end if;
 if not e10.x8b_authorized(p_org,p_draft_id,'commit')then raise exception using errcode='42501',message='action_commit_denied';end if;
 fp:=encode(extensions.digest(convert_to(jsonb_build_object('v','x8-action-commit-v1','draft',p_draft_id,'revision',p_expected_revision)::text,'UTF8'),'sha256'),'hex');
 old:=e10.x8b_command(p_org,p_idempotency_key,'commit',p_draft_id,fp);
 if not e10.x8b_authorized(p_org,p_draft_id,'commit')then raise exception using errcode='42501',message='action_commit_denied';end if;
 if old is not null then return old;end if;
 select * into d from public.e10_action_drafts where organization_id=p_org and id=p_draft_id for update;
 if not e10.x8b_authorized(p_org,p_draft_id,'commit')then raise exception using errcode='42501',message='action_commit_denied';end if;
 if not found or d.status<>'approved'or d.current_revision<>p_expected_revision or d.approved_revision<>p_expected_revision then raise exception using errcode='40001',message='action_revision_or_state_conflict';end if;
 select * into r from public.e10_action_draft_revisions where organization_id=p_org and draft_id=p_draft_id and revision=p_expected_revision;
 downkey:='x8:'||d.operation||':'||d.id||':'||p_expected_revision||':'||encode(extensions.digest(convert_to(p_idempotency_key,'UTF8'),'sha256'),'hex');
 perform pg_advisory_xact_lock(hashtextextended(p_org::text||case d.operation when'purchase_order.create'then'|purchase-order-command|'else'|customer-commercial|'end||downkey,0));
 if not e10.x8b_authorized(p_org,p_draft_id,'commit')then raise exception using errcode='42501',message='action_commit_denied';end if;
 perform e10.x8b_lock_references(p_org,d.operation,r.proposed_values);
 if not e10.x8b_authorized(p_org,p_draft_id,'commit')then raise exception using errcode='42501',message='action_commit_denied';end if;
 snap:=e10.x8b_proposal_snapshot(p_org,d.operation,r.proposed_values,r.field_provenance,r.source_references);
 if snap->>'reference_fingerprint'<>r.reference_fingerprint or jsonb_array_length(snap->'missing_fields')>0 then raise exception using errcode='40001',message='action_references_stale';end if;
 if d.operation='purchase_order.create'then
  result:=public.e10_org_create_purchase_order(p_org,(r.proposed_values->>'supplier_id')::uuid,(r.proposed_values->>'destination_location_id')::uuid,r.proposed_values->>'order_number',r.proposed_values->>'currency',(r.proposed_values->>'expected_at')::timestamptz,r.proposed_values->'lines',downkey);
 else
  result:=public.e10_org_create_customer_transaction_draft(p_org,(r.proposed_values->>'customer_id')::uuid,r.proposed_values->>'currency',(r.proposed_values->>'occurred_at')::timestamptz,r.proposed_values->>'precision',r.proposed_values->>'note',r.proposed_values->'lines',downkey);
 end if;
 update public.e10_action_drafts set status='committed',approved_revision=null,ordinary_result=result,committed_at=statement_timestamp(),updated_at=statement_timestamp()where organization_id=p_org and id=p_draft_id;
 result:=jsonb_build_object('ok',true,'replay',false,'draft_id',p_draft_id,'revision',p_expected_revision,'status','committed','ordinary_result',result);
 insert into public.e10_action_draft_commands values(p_org,auth.uid(),p_idempotency_key,'commit',p_draft_id,fp,downkey,result,statement_timestamp());return result;
end $$;

revoke all on function public.e10_org_approve_action_draft(uuid,uuid,integer,text),public.e10_org_cancel_action_draft(uuid,uuid,integer,text,text),public.e10_org_commit_action_draft(uuid,uuid,integer,text)from public,anon;
grant execute on function public.e10_org_approve_action_draft(uuid,uuid,integer,text),public.e10_org_cancel_action_draft(uuid,uuid,integer,text,text),public.e10_org_commit_action_draft(uuid,uuid,integer,text)to authenticated,service_role;
