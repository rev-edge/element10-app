-- R1 corrective: disposition-aware compatibility reversal, complete receipt
-- origin evidence, and final authority rereads after legacy/internal writers.

create function e10.ensure_receipt_origin_evidence(p_org uuid,p_receipt_id uuid) returns void
language plpgsql security definer set search_path=public as $$
declare r record;
begin
  for r in
    select rl.id line_id,rl.inventory_movement_id,l.inventory_item_id,l.id lot_id,
      sr.received_at,rl.received_quantity,rl.accepted_quantity,rl.damaged_quantity,
      rl.quarantined_quantity
    from public.e10_stock_receipt_lines rl
    join public.e10_stock_receipts sr
      on(sr.organization_id,sr.id)=(rl.organization_id,rl.stock_receipt_id)
    join public.e10_inventory_lots l
      on(l.organization_id,l.id)=(rl.organization_id,rl.inventory_lot_id)
    where rl.organization_id=p_org and rl.stock_receipt_id=p_receipt_id
      and not exists(
        select 1 from public.e10_commercial_events ce
        where ce.organization_id=rl.organization_id and ce.event_type='receipt'
          and ce.payload->>'receipt_line_id'=rl.id::text)
    order by rl.line_no,rl.id
  loop
    perform set_config('e10.receipt_evidence','on',true);
    insert into public.e10_commercial_events(
      organization_id,event_type,event_schema_version,subject_type,subject_id,
      occurred_at,occurred_at_precision,idempotency_key,source_kind,
      source_connection_id,source_reference,source_event_id,correlation_id,
      evidence_quality,payload,created_by,request_fingerprint,inventory_movement_id)
    values(
      p_org,'receipt',1,'inventory_item',r.inventory_item_id,
      coalesce(r.received_at,now()),'exact',
      p_org::text||':receipt-origin:'||r.line_id,'native','receipt-ledger',
      'stock_receipt_line:'||r.line_id,r.line_id::text,p_receipt_id::text,
      'native_system',jsonb_build_object(
        'movement_id',r.inventory_movement_id,'movement_type','intake',
        'on_hand_delta',r.accepted_quantity,'reserved_delta',0,
        'source_action','receive','reason_code','intake',
        'receipt_id',p_receipt_id,'receipt_line_id',r.line_id,'lot_id',r.lot_id,
        'received_quantity',r.received_quantity,
        'accepted_quantity',r.accepted_quantity,
        'damaged_quantity',r.damaged_quantity,
        'quarantined_quantity',r.quarantined_quantity,
        'captured_retroactively',r.inventory_movement_id is null),
      auth.uid(),md5(r.line_id::text||'|receipt|'||r.inventory_item_id),
      r.inventory_movement_id)
    on conflict do nothing;
  end loop;
end $$;
revoke all on function e10.ensure_receipt_origin_evidence(uuid,uuid) from public,anon,authenticated;
grant execute on function e10.ensure_receipt_origin_evidence(uuid,uuid) to service_role;

alter function public.e10_org_lot_reserve(uuid,uuid,numeric,uuid,text)
  rename to _e10_org_lot_reserve_r1;
revoke all on function public._e10_org_lot_reserve_r1(uuid,uuid,numeric,uuid,text)
  from public,anon,authenticated;
grant execute on function public._e10_org_lot_reserve_r1(uuid,uuid,numeric,uuid,text) to service_role;
create function public.e10_org_lot_reserve(
  p_org uuid,p_lot_id uuid,p_quantity numeric,p_break_session_id uuid,p_idempotency_key text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare result jsonb;
begin
  result:=public._e10_org_lot_reserve_r1(p_org,p_lot_id,p_quantity,p_break_session_id,p_idempotency_key);
  if auth.uid() is null
    or not exists(select 1 from public.e10_organizations where id=p_org and status='active')
    or not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.reserve_inventory') then
    raise exception using errcode='42501',message='reserve_inventory_denied';
  end if;
  return result;
end $$;

alter function public.e10_org_lot_consume(uuid,uuid,numeric,text)
  rename to _e10_org_lot_consume_r1;
revoke all on function public._e10_org_lot_consume_r1(uuid,uuid,numeric,text) from public,anon,authenticated;
grant execute on function public._e10_org_lot_consume_r1(uuid,uuid,numeric,text) to service_role;
create function public.e10_org_lot_consume(
  p_org uuid,p_reservation_id uuid,p_quantity numeric,p_idempotency_key text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare result jsonb;
begin
  result:=public._e10_org_lot_consume_r1(p_org,p_reservation_id,p_quantity,p_idempotency_key);
  if auth.uid() is null
    or not exists(select 1 from public.e10_organizations where id=p_org and status='active')
    or not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.inventory_edit') then
    raise exception using errcode='42501',message='consume_inventory_denied';
  end if;
  return result;
end $$;

alter function public.e10_org_lot_release(uuid,uuid,text)
  rename to _e10_org_lot_release_r1;
revoke all on function public._e10_org_lot_release_r1(uuid,uuid,text) from public,anon,authenticated;
grant execute on function public._e10_org_lot_release_r1(uuid,uuid,text) to service_role;
create function public.e10_org_lot_release(
  p_org uuid,p_reservation_id uuid,p_idempotency_key text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare result jsonb;
begin
  result:=public._e10_org_lot_release_r1(p_org,p_reservation_id,p_idempotency_key);
  if auth.uid() is null
    or not exists(select 1 from public.e10_organizations where id=p_org and status='active')
    or not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.inventory_edit') then
    raise exception using errcode='42501',message='release_inventory_denied';
  end if;
  return result;
end $$;

alter function public.e10_org_receive_po_line(uuid,uuid,text,numeric,numeric,numeric,text,timestamptz,jsonb,text)
  rename to _e10_org_receive_po_line_r1;
revoke all on function public._e10_org_receive_po_line_r1(uuid,uuid,text,numeric,numeric,numeric,text,timestamptz,jsonb,text)
  from public,anon,authenticated;
grant execute on function public._e10_org_receive_po_line_r1(uuid,uuid,text,numeric,numeric,numeric,text,timestamptz,jsonb,text)
  to service_role;
create function public.e10_org_receive_po_line(
  p_org uuid,p_purchase_order_line_id uuid,p_inventory_item_id text,
  p_accepted_quantity numeric,p_damaged_quantity numeric,p_quarantined_quantity numeric,
  p_lot_code text,p_received_at timestamptz,p_expected_allocations jsonb,p_idempotency_key text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare result jsonb;destination uuid;receipt uuid;
begin
  result:=public._e10_org_receive_po_line_r1(p_org,p_purchase_order_line_id,p_inventory_item_id,
    p_accepted_quantity,p_damaged_quantity,p_quarantined_quantity,p_lot_code,p_received_at,
    p_expected_allocations,p_idempotency_key);
  receipt:=nullif(result->>'receipt_id','')::uuid;
  select destination_location_id into destination from public.e10_stock_receipts
    where organization_id=p_org and id=receipt;
  if auth.uid() is null
    or not exists(select 1 from public.e10_organizations where id=p_org and status='active')
    or not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.create_receiving')
    or destination is null or not e10.can_receive_at(p_org,destination) then
    raise exception using errcode='42501',message='create_receiving_denied';
  end if;
  perform e10.ensure_receipt_origin_evidence(p_org,receipt);
  return result;
end $$;

alter function public.e10_org_reverse_receipt_batch(uuid,uuid,text,text)
  rename to _e10_org_reverse_receipt_batch_r1;
revoke all on function public._e10_org_reverse_receipt_batch_r1(uuid,uuid,text,text)
  from public,anon,authenticated;
grant execute on function public._e10_org_reverse_receipt_batch_r1(uuid,uuid,text,text) to service_role;
create function public.e10_org_reverse_receipt_batch(
  p_org uuid,p_receipt_id uuid,p_reason text,p_idempotency_key text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare result jsonb;destination uuid;
begin
  select destination_location_id into destination from public.e10_stock_receipts
    where organization_id=p_org and id=p_receipt_id;
  if auth.uid() is null
    or not exists(select 1 from public.e10_organizations where id=p_org and status='active')
    or not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.resolve_recovery')
    or destination is null or not e10.can_receive_at(p_org,destination) then
    raise exception using errcode='42501',message='resolve_recovery_denied';
  end if;
  perform e10.ensure_receipt_origin_evidence(p_org,p_receipt_id);
  result:=public._e10_org_reverse_receipt_batch_r1(p_org,p_receipt_id,p_reason,p_idempotency_key);
  if auth.uid() is null
    or not exists(select 1 from public.e10_organizations where id=p_org and status='active')
    or not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.resolve_recovery')
    or not e10.can_receive_at(p_org,destination) then
    raise exception using errcode='42501',message='resolve_recovery_denied';
  end if;
  return result;
end $$;

alter function public.e10_org_reverse_receipt(uuid,uuid,text,text)
  rename to _e10_org_reverse_receipt_unsafe_r1;
revoke all on function public._e10_org_reverse_receipt_unsafe_r1(uuid,uuid,text,text)
  from public,anon,authenticated;
grant execute on function public._e10_org_reverse_receipt_unsafe_r1(uuid,uuid,text,text) to service_role;
create function public.e10_org_reverse_receipt(
  p_org uuid,p_receipt_id uuid,p_reason text,p_idempotency_key text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare batch_result jsonb;first_line jsonb;
begin
  batch_result:=public.e10_org_reverse_receipt_batch(p_org,p_receipt_id,p_reason,p_idempotency_key);
  first_line:=batch_result->'lines'->0;
  return jsonb_build_object('ok',true,'replay',coalesce((batch_result->>'replay')::boolean,false),
    'reversal_id',first_line->'reversal_id','receipt_id',p_receipt_id,
    'movement_id',first_line->'movement_id','status',batch_result->>'status');
end $$;

-- Legacy reservation APIs remain granted for compatibility. Keep their result
-- contracts, but make any authority change observed after their blocking work
-- abort the full transaction.
alter function public.e10_org_inv_reserve(uuid,text,text,text,numeric,text)
  rename to _e10_org_inv_reserve_r1;
revoke all on function public._e10_org_inv_reserve_r1(uuid,text,text,text,numeric,text)
  from public,anon,authenticated;
grant execute on function public._e10_org_inv_reserve_r1(uuid,text,text,text,numeric,text) to service_role;
create function public.e10_org_inv_reserve(
  p_org uuid,p_id text,p_show_ref text,p_show_label text,p_qty numeric,p_idempotency_key text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare result jsonb;
begin
  result:=public._e10_org_inv_reserve_r1(p_org,p_id,p_show_ref,p_show_label,p_qty,p_idempotency_key);
  if auth.uid() is null
    or not exists(select 1 from public.e10_organizations where id=p_org and status='active')
    or not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.inventory_edit') then
    raise exception using errcode='42501',message='reserve_inventory_denied';
  end if;
  return result;
end $$;

alter function public.e10_org_inv_release(uuid,text,text,text)
  rename to _e10_org_inv_release_r1;
revoke all on function public._e10_org_inv_release_r1(uuid,text,text,text) from public,anon,authenticated;
grant execute on function public._e10_org_inv_release_r1(uuid,text,text,text) to service_role;
create function public.e10_org_inv_release(
  p_org uuid,p_id text,p_show_ref text,p_idempotency_key text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare result jsonb;
begin
  result:=public._e10_org_inv_release_r1(p_org,p_id,p_show_ref,p_idempotency_key);
  if auth.uid() is null
    or not exists(select 1 from public.e10_organizations where id=p_org and status='active')
    or not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.inventory_edit') then
    raise exception using errcode='42501',message='release_inventory_denied';
  end if;
  return result;
end $$;

alter function public.e10_org_inv_consume(uuid,text,text,text,numeric,text)
  rename to _e10_org_inv_consume_r1;
revoke all on function public._e10_org_inv_consume_r1(uuid,text,text,text,numeric,text)
  from public,anon,authenticated;
grant execute on function public._e10_org_inv_consume_r1(uuid,text,text,text,numeric,text) to service_role;
create function public.e10_org_inv_consume(
  p_org uuid,p_id text,p_break_session_id text,p_source_show_ref text,p_qty numeric,p_idempotency_key text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare result jsonb;
begin
  result:=public._e10_org_inv_consume_r1(p_org,p_id,p_break_session_id,p_source_show_ref,p_qty,p_idempotency_key);
  if auth.uid() is null
    or not exists(select 1 from public.e10_organizations where id=p_org and status='active')
    or not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.inventory_edit') then
    raise exception using errcode='42501',message='consume_inventory_denied';
  end if;
  return result;
end $$;

do $$
begin
  execute 'revoke all on function public.e10_org_lot_reserve(uuid,uuid,numeric,uuid,text) from public,anon';
  execute 'grant execute on function public.e10_org_lot_reserve(uuid,uuid,numeric,uuid,text) to authenticated,service_role';
  execute 'revoke all on function public.e10_org_lot_consume(uuid,uuid,numeric,text) from public,anon';
  execute 'grant execute on function public.e10_org_lot_consume(uuid,uuid,numeric,text) to authenticated,service_role';
  execute 'revoke all on function public.e10_org_lot_release(uuid,uuid,text) from public,anon';
  execute 'grant execute on function public.e10_org_lot_release(uuid,uuid,text) to authenticated,service_role';
  execute 'revoke all on function public.e10_org_receive_po_line(uuid,uuid,text,numeric,numeric,numeric,text,timestamptz,jsonb,text) from public,anon';
  execute 'grant execute on function public.e10_org_receive_po_line(uuid,uuid,text,numeric,numeric,numeric,text,timestamptz,jsonb,text) to authenticated,service_role';
  execute 'revoke all on function public.e10_org_reverse_receipt_batch(uuid,uuid,text,text) from public,anon';
  execute 'grant execute on function public.e10_org_reverse_receipt_batch(uuid,uuid,text,text) to authenticated,service_role';
  execute 'revoke all on function public.e10_org_reverse_receipt(uuid,uuid,text,text) from public,anon';
  execute 'grant execute on function public.e10_org_reverse_receipt(uuid,uuid,text,text) to authenticated,service_role';
  execute 'revoke all on function public.e10_org_inv_reserve(uuid,text,text,text,numeric,text) from public,anon';
  execute 'grant execute on function public.e10_org_inv_reserve(uuid,text,text,text,numeric,text) to authenticated,service_role';
  execute 'revoke all on function public.e10_org_inv_release(uuid,text,text,text) from public,anon';
  execute 'grant execute on function public.e10_org_inv_release(uuid,text,text,text) to authenticated,service_role';
  execute 'revoke all on function public.e10_org_inv_consume(uuid,text,text,text,numeric,text) from public,anon';
  execute 'grant execute on function public.e10_org_inv_consume(uuid,text,text,text,numeric,text) to authenticated,service_role';
end $$;
