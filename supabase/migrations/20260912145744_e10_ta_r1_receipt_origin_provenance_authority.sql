-- R1 provenance corrective: classification is supplied only by service-only
-- callers from actual command state, never by a caller-controlled session GUC.

create function e10.ensure_receipt_origin_evidence(
  p_org uuid,p_receipt_id uuid,p_captured_retroactively boolean
) returns void language plpgsql security definer set search_path=public as $$
declare r record;
begin
  if p_captured_retroactively is null then
    raise exception using errcode='22004',message='receipt_origin_provenance_required';end if;
  perform 1 from public.e10_stock_receipts sr
    where sr.organization_id=p_org and sr.id=p_receipt_id for update;
  if not found then raise exception using errcode='42501',message='receipt_access_denied';end if;
  for r in
    select rl.id line_id,rl.inventory_movement_id,l.inventory_item_id,l.id lot_id,
      sr.received_at,rl.received_quantity,rl.accepted_quantity,rl.damaged_quantity,
      rl.quarantined_quantity
    from public.e10_stock_receipt_lines rl
    join public.e10_stock_receipts sr on(sr.organization_id,sr.id)=(rl.organization_id,rl.stock_receipt_id)
    join public.e10_inventory_lots l on(l.organization_id,l.id)=(rl.organization_id,rl.inventory_lot_id)
    where rl.organization_id=p_org and rl.stock_receipt_id=p_receipt_id
      and not exists(select 1 from public.e10_commercial_events ce
        where ce.organization_id=rl.organization_id and ce.event_type='receipt'
          and ce.payload->>'receipt_line_id'=rl.id::text)
    order by rl.line_no,rl.id
  loop
    perform set_config('e10.receipt_evidence','on',true);
    insert into public.e10_commercial_events(
      organization_id,event_type,event_schema_version,subject_type,subject_id,
      occurred_at,occurred_at_precision,idempotency_key,source_kind,source_connection_id,
      source_reference,source_event_id,correlation_id,evidence_quality,payload,created_by,
      request_fingerprint,inventory_movement_id)
    values(p_org,'receipt',1,'inventory_item',r.inventory_item_id,coalesce(r.received_at,now()),'exact',
      p_org::text||':receipt-origin:'||r.line_id,'native','receipt-ledger',
      'stock_receipt_line:'||r.line_id,r.line_id::text,p_receipt_id::text,'native_system',
      jsonb_build_object('movement_id',r.inventory_movement_id,'movement_type','intake',
        'on_hand_delta',r.accepted_quantity,'reserved_delta',0,'source_action','receive',
        'reason_code','intake','receipt_id',p_receipt_id,'receipt_line_id',r.line_id,
        'lot_id',r.lot_id,'received_quantity',r.received_quantity,
        'accepted_quantity',r.accepted_quantity,'damaged_quantity',r.damaged_quantity,
        'quarantined_quantity',r.quarantined_quantity,
        'captured_retroactively',p_captured_retroactively),auth.uid(),
      md5(r.line_id::text||'|receipt|'||r.inventory_item_id),r.inventory_movement_id)
    on conflict do nothing;
    if not exists(select 1 from public.e10_commercial_events ce
      where ce.organization_id=p_org and ce.event_type='receipt'
        and ce.payload->>'receipt_line_id'=r.line_id::text) then
      raise exception using errcode='23505',message='receipt_evidence_conflict';end if;
  end loop;
end $$;
revoke all on function e10.ensure_receipt_origin_evidence(uuid,uuid,boolean) from public,anon,authenticated;
grant execute on function e10.ensure_receipt_origin_evidence(uuid,uuid,boolean) to service_role;

create or replace function public.e10_org_receive_po_line(
  p_org uuid,p_purchase_order_line_id uuid,p_inventory_item_id text,
  p_accepted_quantity numeric,p_damaged_quantity numeric,p_quarantined_quantity numeric,
  p_lot_code text,p_received_at timestamptz,p_expected_allocations jsonb,p_idempotency_key text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare result jsonb;destination uuid;receipt uuid;is_replay boolean;
begin
  result:=public._e10_org_receive_po_line_r1(p_org,p_purchase_order_line_id,p_inventory_item_id,
    p_accepted_quantity,p_damaged_quantity,p_quarantined_quantity,p_lot_code,p_received_at,
    p_expected_allocations,p_idempotency_key);
  receipt:=nullif(result->>'receipt_id','')::uuid;
  is_replay:=coalesce((result->>'replay')::boolean,false);
  select destination_location_id into destination from public.e10_stock_receipts
    where organization_id=p_org and id=receipt;
  if auth.uid() is null or not exists(select 1 from public.e10_organizations where id=p_org and status='active')
    or not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.create_receiving')
    or destination is null or not e10.can_receive_at(p_org,destination) then
    raise exception using errcode='42501',message='create_receiving_denied';end if;
  perform e10.ensure_receipt_origin_evidence(p_org,receipt,is_replay);
  if auth.uid() is null or not exists(select 1 from public.e10_organizations where id=p_org and status='active')
    or not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.create_receiving')
    or not e10.can_receive_at(p_org,destination) then
    raise exception using errcode='42501',message='create_receiving_denied';end if;
  return result;
end $$;

create or replace function public.e10_org_reverse_receipt_batch(
  p_org uuid,p_receipt_id uuid,p_reason text,p_idempotency_key text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare result jsonb;destination uuid;before_revision bigint;after_revision bigint;
begin
  select destination_location_id,disposition_revision into destination,before_revision
    from public.e10_stock_receipts where organization_id=p_org and id=p_receipt_id;
  if auth.uid() is null or not exists(select 1 from public.e10_organizations where id=p_org and status='active')
    or not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.resolve_recovery')
    or destination is null or not e10.can_receive_at(p_org,destination) then
    raise exception using errcode='42501',message='resolve_recovery_denied';end if;
  perform pg_advisory_xact_lock(hashtextextended(
    p_org::text||'|receipt-reversal-command|'||p_idempotency_key,0));
  perform e10.ensure_receipt_origin_evidence(p_org,p_receipt_id,true);
  if auth.uid() is null or not exists(select 1 from public.e10_organizations where id=p_org and status='active')
    or not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.resolve_recovery')
    or not e10.can_receive_at(p_org,destination) then
    raise exception using errcode='42501',message='resolve_recovery_denied';end if;
  result:=public._e10_org_reverse_receipt_batch_r1(p_org,p_receipt_id,p_reason,p_idempotency_key);
  if auth.uid() is null or not exists(select 1 from public.e10_organizations where id=p_org and status='active')
    or not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.resolve_recovery')
    or not e10.can_receive_at(p_org,destination) then
    raise exception using errcode='42501',message='resolve_recovery_denied';end if;
  if not coalesce((result->>'replay')::boolean,false) then
    select disposition_revision into after_revision from public.e10_stock_receipts
      where organization_id=p_org and id=p_receipt_id;
    if after_revision is distinct from before_revision then
      raise exception using errcode='40001',message='receipt_disposition_changed';end if;
  end if;
  return result;
end $$;

drop function e10.ensure_receipt_origin_evidence(uuid,uuid);
