-- TA-X4h generic non-session lot demand. This does not replace the
-- break-session-specific API. It exposes the same lot, item, receipt-projection,
-- idempotency and overcommit controls without fabricating a break session.

create function public.e10_org_lot_reserve_for_demand(
  p_org uuid,
  p_lot_id uuid,
  p_quantity numeric,
  p_demand_type text,
  p_demand_reference text,
  p_demand_label text,
  p_idempotency_key text
) returns jsonb
language plpgsql security definer set search_path=public as $$
declare
  actor uuid:=auth.uid();
  v_lot record;
  v_item_qty numeric;
  v_item_reserved numeric;
  v_lot_reserved numeric;
  v_fp text;
  v_movement_key text;
  v_existing record;
  v_legacy_id uuid;
  v_movement_id uuid;
  v_reservation_id uuid;
begin
  if actor is null or not exists(select 1 from public.e10_organizations where id=p_org and status='active')
    or not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.reserve_inventory') then
    raise exception using errcode='42501',message='reserve_inventory_denied';
  end if;
  if p_quantity is null or p_quantity<=0 or p_quantity::text in('NaN','Infinity','-Infinity')
    or p_demand_type not in('sale_order','manual')
    or p_demand_reference is null or btrim(p_demand_reference)='' or octet_length(p_demand_reference)>160
    or p_demand_label is null or btrim(p_demand_label)='' or octet_length(p_demand_label)>500
    or p_idempotency_key is null or btrim(p_idempotency_key)='' or octet_length(p_idempotency_key)>160 then
    raise exception using errcode='22023',message='lot_demand_payload_invalid';
  end if;
  v_fp:=encode(extensions.digest(jsonb_build_object(
    'v','lot-demand-v1','org',p_org,'lot',p_lot_id,'quantity',p_quantity,
    'demand_type',p_demand_type,'demand_reference',p_demand_reference,
    'demand_label',p_demand_label)::text,'sha256'),'hex');
  v_movement_key:=p_org::text||':lot-demand:'||p_idempotency_key;

  perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|lot-demand-command|'||p_idempotency_key,0));
  if auth.uid() is distinct from actor or not exists(select 1 from public.e10_organizations where id=p_org and status='active')
    or not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.reserve_inventory') then
    raise exception using errcode='42501',message='reserve_inventory_denied';
  end if;
  select lr.id,lr.request_fingerprint,lr.legacy_reservation_id,lr.movement_id,lr.status,lr.consumed_quantity
    into v_existing from public.e10_lot_reservations lr
    where lr.organization_id=p_org and lr.idempotency_key=p_idempotency_key;
  if found then
    if v_existing.request_fingerprint is distinct from v_fp then
      raise exception using errcode='22023',message='idempotency_key_mismatch';
    end if;
    return jsonb_build_object('ok',true,'replay',true,'reservation_id',v_existing.id,
      'legacy_reservation_id',v_existing.legacy_reservation_id,'movement_id',v_existing.movement_id,
      'status',v_existing.status,'consumed_quantity',v_existing.consumed_quantity);
  end if;

  perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|lot|'||p_lot_id::text,0));
  select l.id,l.inventory_item_id,l.status,l.accepted_quantity,l.location_id
    into v_lot from public.e10_inventory_lots l
    where l.organization_id=p_org and l.id=p_lot_id for update;
  if not found then raise exception using errcode='42501',message='lot_access_denied'; end if;
  if auth.uid() is distinct from actor or not exists(select 1 from public.e10_organizations where id=p_org and status='active')
    or not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.reserve_inventory') then
    raise exception using errcode='42501',message='reserve_inventory_denied';
  end if;
  if v_lot.status<>'available' or v_lot.inventory_item_id is null then
    raise exception using errcode='55000',message='lot_not_reservable';
  end if;
  if not exists(select 1 from public.e10_locations where organization_id=p_org and id=v_lot.location_id and status='active') then
    raise exception using errcode='55000',message='lot_location_inactive';
  end if;
  perform e10.assert_receipt_lot_projection(p_org,p_lot_id);

  select i.qty into v_item_qty from public.e10_inventory_items i
    where i.organization_id=p_org and i.id=v_lot.inventory_item_id for update;
  if not found then raise exception using errcode='P0002',message='inventory_item_not_found'; end if;
  select coalesce(sum(r.qty),0) into v_item_reserved from public.e10_inventory_reservations r
    where r.organization_id=p_org and r.item_id=v_lot.inventory_item_id and r.status='active';
  select coalesce(sum(case when lr.status='active' then lr.quantity else 0 end),0)+coalesce(sum(lr.consumed_quantity),0)
    into v_lot_reserved from public.e10_lot_reservations lr
    where lr.organization_id=p_org and lr.lot_id=p_lot_id;
  if p_quantity>coalesce(v_item_qty,0)-v_item_reserved
    or p_quantity>v_lot.accepted_quantity-v_lot_reserved then
    raise exception using errcode='23514',message='insufficient_unreserved_quantity';
  end if;

  insert into public.e10_inventory_reservations(
    item_id,show_ref,show_label,streamer_uid,qty,status,created_by,organization_id
  ) values(
    v_lot.inventory_item_id,p_demand_reference,p_demand_label,null,p_quantity,'active',actor,p_org
  ) returning id into v_legacy_id;
  perform set_config('e10.emit','on',true);
  insert into public.e10_inventory_movements(
    workspace_id,item_id,movement_type,on_hand_delta,reserved_delta,
    source_entity_type,source_entity_id,source_action,actor_uid,reason_code,note,
    idempotency_key,meta,organization_id
  ) values(
    'shared',v_lot.inventory_item_id,'reservation',0,p_quantity,p_demand_type,
    p_demand_reference,'lot_reserve_for_demand',actor,'reserve',p_demand_label,
    v_movement_key,jsonb_build_object('lot_id',p_lot_id,'legacy_reservation_id',v_legacy_id),p_org
  ) returning id into v_movement_id;
  insert into public.e10_lot_reservations(
    organization_id,lot_id,quantity,source_type,source_id,status,idempotency_key,
    request_fingerprint,legacy_reservation_id,movement_id,created_by
  ) values(
    p_org,p_lot_id,p_quantity,p_demand_type,p_demand_reference,'active',p_idempotency_key,
    v_fp,v_legacy_id,v_movement_id,actor
  ) returning id into v_reservation_id;
  return jsonb_build_object('ok',true,'replay',false,'reservation_id',v_reservation_id,
    'legacy_reservation_id',v_legacy_id,'movement_id',v_movement_id,'status','active',
    'consumed_quantity',0);
end;
$$;

revoke all on function public.e10_org_lot_reserve_for_demand(uuid,uuid,numeric,text,text,text,text)
  from public,anon;
grant execute on function public.e10_org_lot_reserve_for_demand(uuid,uuid,numeric,text,text,text,text)
  to authenticated,service_role;

comment on function public.e10_org_lot_reserve_for_demand(uuid,uuid,numeric,text,text,text,text) is
  'Atomic idempotent lot reservation for non-session demand. Uses sale_order or manual demand identity and does not fabricate a break session.';
