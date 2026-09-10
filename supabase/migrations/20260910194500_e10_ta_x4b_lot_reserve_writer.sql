-- TA-X4b atomic lot reservation writer and demand attribution.

alter table public.e10_inventory_lots add column inventory_item_id text;
alter table public.e10_inventory_lots add constraint e10_inventory_lots_org_inventory_item_fkey
  foreign key(organization_id,inventory_item_id) references public.e10_inventory_items(organization_id,id);

alter table public.e10_lot_reservations add column request_fingerprint text;
alter table public.e10_lot_reservations add column legacy_reservation_id uuid;
alter table public.e10_lot_reservations add column movement_id uuid;
alter table public.e10_lot_reservations add column consumed_quantity numeric not null default 0 check(consumed_quantity>=0 and consumed_quantity<=quantity);
alter table public.e10_lot_reservations add constraint e10_lot_reservations_org_legacy_reservation_fkey
  foreign key(organization_id,legacy_reservation_id) references public.e10_inventory_reservations(organization_id,id);
alter table public.e10_lot_reservations add constraint e10_lot_reservations_org_movement_fkey
  foreign key(organization_id,movement_id) references public.e10_inventory_movements(organization_id,id);

alter table public.e10_expected_inventory_allocations add column break_session_id uuid;
alter table public.e10_expected_inventory_allocations add column planning_reference text;
alter table public.e10_expected_inventory_allocations add constraint e10_expected_allocations_demand_chk
  check(num_nonnulls(break_session_id,planning_reference)=1) not valid;
alter table public.e10_expected_inventory_allocations add constraint e10_expected_allocations_org_session_fkey
  foreign key(organization_id,break_session_id) references public.e10_break_sessions(organization_id,id) not valid;
alter table public.e10_expected_inventory_allocations validate constraint e10_expected_allocations_demand_chk;
alter table public.e10_expected_inventory_allocations validate constraint e10_expected_allocations_org_session_fkey;

create or replace function public.e10_org_lot_reserve(
  p_org uuid,
  p_lot_id uuid,
  p_quantity numeric,
  p_break_session_id uuid,
  p_idempotency_key text
) returns jsonb
language plpgsql security definer set search_path=public as $$
declare
  v_lot record; v_session record; v_item_qty numeric; v_item_reserved numeric; v_lot_reserved numeric;
  v_fp text; v_movement_key text; v_existing record; v_legacy_id uuid; v_movement_id uuid;
begin
  if not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.reserve_inventory') then
    raise exception using errcode='42501',message='reserve_inventory_denied';
  end if;
  if p_quantity is null or p_quantity<=0 then raise exception using errcode='22023',message='quantity_must_be_positive'; end if;
  if p_idempotency_key is null or btrim(p_idempotency_key)='' then raise exception using errcode='22004',message='idempotency_key_required'; end if;
  v_fp:=md5(p_lot_id::text||'|'||p_quantity::text||'|'||p_break_session_id::text);
  v_movement_key:=p_org::text||':lot-reserve:'||p_idempotency_key;
  perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|lot-reserve|'||p_idempotency_key,0));
  perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|lot|'||p_lot_id::text,0));
  select id,request_fingerprint,legacy_reservation_id,movement_id,status,consumed_quantity into v_existing
    from public.e10_lot_reservations where organization_id=p_org and idempotency_key=p_idempotency_key;
  if found then
    if v_existing.request_fingerprint is distinct from v_fp then raise exception using errcode='22023',message='idempotency_key_mismatch'; end if;
    return jsonb_build_object('ok',true,'replay',true,'reservation_id',v_existing.id,'legacy_reservation_id',v_existing.legacy_reservation_id,'movement_id',v_existing.movement_id,'status',v_existing.status,'consumed_quantity',v_existing.consumed_quantity);
  end if;
  select id,organization_id,inventory_item_id,status,accepted_quantity,location_id into v_lot
    from public.e10_inventory_lots where id=p_lot_id and organization_id=p_org for update;
  if not found then raise exception using errcode='42501',message='lot_access_denied'; end if;
  if v_lot.status<>'available' or v_lot.inventory_item_id is null then raise exception using errcode='55000',message='lot_not_reservable'; end if;
  if not exists(select 1 from public.e10_locations where organization_id=p_org and id=v_lot.location_id and status='active') then
    raise exception using errcode='55000',message='lot_location_inactive';
  end if;
  select id,organization_id,name,streamer_uid,source_show_ref into v_session
    from public.e10_break_sessions where id=p_break_session_id;
  if not found or v_session.organization_id<>p_org then raise exception using errcode='42501',message='cross_org_session_denied'; end if;
  if (select status from public.e10_break_sessions where id=p_break_session_id and organization_id=p_org)<>'active' then
    raise exception using errcode='55000',message='break_session_not_active';
  end if;
  select qty into v_item_qty from public.e10_inventory_items
    where organization_id=p_org and id=v_lot.inventory_item_id for update;
  if not found then raise exception using errcode='P0002',message='inventory_item_not_found'; end if;
  select coalesce(sum(qty),0) into v_item_reserved from public.e10_inventory_reservations
    where organization_id=p_org and item_id=v_lot.inventory_item_id and status='active';
  select coalesce(sum(case when status='active' then quantity else 0 end),0)+coalesce(sum(consumed_quantity),0)
    into v_lot_reserved from public.e10_lot_reservations where organization_id=p_org and lot_id=p_lot_id;
  if p_quantity>coalesce(v_item_qty,0)-v_item_reserved or p_quantity>v_lot.accepted_quantity-v_lot_reserved then
    raise exception using errcode='23514',message='insufficient_unreserved_quantity';
  end if;
  insert into public.e10_inventory_reservations(item_id,show_ref,show_label,streamer_uid,qty,status,created_by,organization_id)
    values(v_lot.inventory_item_id,coalesce(v_session.source_show_ref,p_break_session_id::text),v_session.name,v_session.streamer_uid::text,p_quantity,'active',auth.uid(),p_org)
    returning id into v_legacy_id;
  perform set_config('e10.emit','on',true);
  insert into public.e10_inventory_movements(workspace_id,item_id,movement_type,on_hand_delta,reserved_delta,
    source_entity_type,source_entity_id,source_action,actor_uid,reason_code,note,idempotency_key,meta,organization_id)
  values('shared',v_lot.inventory_item_id,'reservation',0,p_quantity,'break_session',p_break_session_id::text,'lot_reserve',auth.uid(),
    'reserve','lot-backed reservation',v_movement_key,jsonb_build_object('lot_id',p_lot_id,'legacy_reservation_id',v_legacy_id),p_org)
  returning id into v_movement_id;
  insert into public.e10_lot_reservations(organization_id,lot_id,quantity,source_type,source_id,status,idempotency_key,
    request_fingerprint,legacy_reservation_id,movement_id,created_by)
  values(p_org,p_lot_id,p_quantity,'break_session',p_break_session_id::text,'active',p_idempotency_key,
    v_fp,v_legacy_id,v_movement_id,auth.uid()) returning id into v_existing.id;
  return jsonb_build_object('ok',true,'replay',false,'reservation_id',v_existing.id,'legacy_reservation_id',v_legacy_id,'movement_id',v_movement_id,'status','active','consumed_quantity',0);
end;
$$;
revoke all on function public.e10_org_lot_reserve(uuid,uuid,numeric,uuid,text) from public,anon;
grant execute on function public.e10_org_lot_reserve(uuid,uuid,numeric,uuid,text) to authenticated,service_role;

create or replace function e10.guard_lot_linked_legacy_reservation() returns trigger
language plpgsql security definer set search_path=public as $$
begin
  if current_setting('e10.lot_transition',true) is distinct from 'on'
     and exists(select 1 from public.e10_lot_reservations lr
       where lr.organization_id=old.organization_id and lr.legacy_reservation_id=old.id and lr.status='active') then
    raise exception using errcode='55000',message='lot_linked_reservation_requires_lot_writer';
  end if;
  return new;
end;
$$;
revoke all on function e10.guard_lot_linked_legacy_reservation() from public,anon,authenticated;
grant execute on function e10.guard_lot_linked_legacy_reservation() to service_role;
create trigger e10_guard_lot_linked_legacy_reservation_trg before update or delete on public.e10_inventory_reservations
  for each row execute function e10.guard_lot_linked_legacy_reservation();

comment on function public.e10_org_lot_reserve(uuid,uuid,numeric,uuid,text) is
  'Atomic idempotent lot reservation. Validates tenant/session, locks lot and legacy item, and writes both reservation models plus the movement ledger.';
