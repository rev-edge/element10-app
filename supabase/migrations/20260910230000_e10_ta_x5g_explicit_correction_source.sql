-- TA-X5g explicit predecessor for source-less/manual corrected multirow intake.
create function public.e10_org_stage_corrected_intake(
 p_org uuid,p_supersedes_batch_id uuid,p_source_kind text,p_source_connection_id text,p_source_reference text,
 p_original_file_reference text,p_payload_fingerprint text,p_rows jsonb,p_idempotency_key text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare result jsonb; new_batch uuid; current_predecessor uuid; predecessor_status text;
begin
 if not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.manage_intake') then raise exception using errcode='42501',message='manage_intake_denied'; end if;
 if p_supersedes_batch_id is null then raise exception using errcode='22004',message='supersedes_batch_required'; end if;
 select status into predecessor_status from public.e10_intake_batches where organization_id=p_org and id=p_supersedes_batch_id for key share;
 if not found then raise exception using errcode='42501',message='predecessor_batch_access_denied'; end if;
 if predecessor_status<>'committed' then raise exception using errcode='55000',message='predecessor_batch_must_be_committed'; end if;
 result:=public.e10_org_stage_intake(p_org,p_source_kind,p_source_connection_id,p_source_reference,p_original_file_reference,
   p_payload_fingerprint,p_rows,p_idempotency_key);
 new_batch:=(result->>'batch_id')::uuid;
 if new_batch=p_supersedes_batch_id then raise exception using errcode='22023',message='batch_cannot_supersede_itself'; end if;
 select supersedes_intake_batch_id into current_predecessor from public.e10_intake_batches
  where organization_id=p_org and id=new_batch for update;
 if current_predecessor is not null and current_predecessor<>p_supersedes_batch_id then
  raise exception using errcode='22023',message='corrected_intake_predecessor_mismatch';
 end if;
 if current_predecessor is null then update public.e10_intake_batches set supersedes_intake_batch_id=p_supersedes_batch_id
   where organization_id=p_org and id=new_batch; end if;
 return result||jsonb_build_object('corrected_source',true,'supersedes_batch_id',p_supersedes_batch_id);
end $$;
revoke all on function public.e10_org_stage_corrected_intake(uuid,uuid,text,text,text,text,text,jsonb,text) from public,anon;
grant execute on function public.e10_org_stage_corrected_intake(uuid,uuid,text,text,text,text,text,jsonb,text) to authenticated,service_role;
comment on function public.e10_org_stage_corrected_intake(uuid,uuid,text,text,text,text,text,jsonb,text) is
 'Stages a reviewed corrected batch with an explicit committed predecessor when provider identity cannot establish lineage; commit still requires complete per-row classification.';
