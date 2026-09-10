-- TA-X4c lot-aware consume/release transitions. Keeps lot and legacy ledgers atomic.

create table public.e10_lot_reservation_transitions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.e10_organizations(id),
  lot_reservation_id uuid not null,
  action text not null check(action in ('consume','release')),
  quantity numeric not null check(quantity>0),
  idempotency_key text not null check(btrim(idempotency_key)<>''),
  request_fingerprint text not null,
  movement_id uuid not null,
  resulting_status text not null check(resulting_status in ('active','released','consumed')),
  resulting_consumed_quantity numeric not null check(resulting_consumed_quantity>=0),
  resulting_remaining_quantity numeric not null check(resulting_remaining_quantity>=0),
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  unique(organization_id,id),
  unique(organization_id,idempotency_key),
  foreign key(organization_id,lot_reservation_id)
    references public.e10_lot_reservations(organization_id,id),
  foreign key(organization_id,movement_id)
    references public.e10_inventory_movements(organization_id,id)
);
create index e10_lot_reservation_transitions_reservation_idx
  on public.e10_lot_reservation_transitions(organization_id,lot_reservation_id,created_at,id);
alter table public.e10_lot_reservation_transitions enable row level security;
revoke all on table public.e10_lot_reservation_transitions from public,anon,authenticated;
grant all on table public.e10_lot_reservation_transitions to service_role;
create trigger e10_lot_reservation_transitions_append_only_trg
  before update or delete on public.e10_lot_reservation_transitions
  for each row execute function e10.reject_append_only_change();

-- Once linked, the legacy reservation remains owned by the lot transition model
-- even after terminal status. Only reviewed lot writers may mutate it.
create table e10.lot_transition_guards (
  backend_pid integer not null,
  transaction_id bigint not null,
  primary key(backend_pid,transaction_id)
);
revoke all on table e10.lot_transition_guards from public,anon,authenticated;
grant all on table e10.lot_transition_guards to service_role;

create or replace function e10.guard_lot_linked_legacy_reservation() returns trigger
language plpgsql security definer set search_path=public as $$
begin
  if not exists(select 1 from e10.lot_transition_guards g
       where g.backend_pid=pg_backend_pid() and g.transaction_id=txid_current())
     and exists(select 1 from public.e10_lot_reservations lr
       where lr.organization_id=old.organization_id and lr.legacy_reservation_id=old.id) then
    raise exception using errcode='55000',message='lot_linked_reservation_requires_lot_writer';
  end if;
  if tg_op='DELETE' then return old; end if;
  return new;
end;
$$;

create or replace function public.e10_org_lot_consume(
  p_org uuid, p_reservation_id uuid, p_quantity numeric, p_idempotency_key text
) returns jsonb
language plpgsql security definer set search_path=public as $$
declare
  v_lr record; v_lot record; v_existing record; v_fp text; v_remaining numeric;
  v_new_consumed numeric; v_new_status text; v_mid uuid; v_movement_key text;
begin
  if not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.inventory_edit') then
    raise exception using errcode='42501',message='consume_inventory_denied';
  end if;
  if p_quantity is null or p_quantity<=0 then raise exception using errcode='22023',message='quantity_must_be_positive'; end if;
  if p_idempotency_key is null or btrim(p_idempotency_key)='' then raise exception using errcode='22004',message='idempotency_key_required'; end if;
  v_fp:=md5(p_reservation_id::text||'|'||p_quantity::text||'|consume');
  perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|lot-transition|'||p_idempotency_key,0));
  select action,quantity,request_fingerprint,movement_id,resulting_status,resulting_consumed_quantity,resulting_remaining_quantity into v_existing
    from public.e10_lot_reservation_transitions where organization_id=p_org and idempotency_key=p_idempotency_key;
  if found then
    if v_existing.request_fingerprint is distinct from v_fp then raise exception using errcode='22023',message='idempotency_key_mismatch'; end if;
    return jsonb_build_object('ok',true,'replay',true,'movement_id',v_existing.movement_id,'status',v_existing.resulting_status,
      'consumed_quantity',v_existing.resulting_consumed_quantity,'remaining_quantity',v_existing.resulting_remaining_quantity);
  end if;
  select id,lot_id,quantity,consumed_quantity,status,legacy_reservation_id,source_id into v_lr
    from public.e10_lot_reservations where organization_id=p_org and id=p_reservation_id for update;
  if not found then raise exception using errcode='42501',message='lot_reservation_access_denied'; end if;
  if v_lr.status<>'active' then raise exception using errcode='55000',message='lot_reservation_not_active'; end if;
  v_remaining:=v_lr.quantity-v_lr.consumed_quantity;
  if p_quantity>v_remaining then raise exception using errcode='23514',message='consume_exceeds_reserved_quantity'; end if;
  select id,inventory_item_id into v_lot from public.e10_inventory_lots
    where organization_id=p_org and id=v_lr.lot_id for update;
  if v_lot.inventory_item_id is null then raise exception using errcode='55000',message='lot_inventory_item_missing'; end if;
  perform 1 from public.e10_inventory_items where organization_id=p_org and id=v_lot.inventory_item_id for update;
  if not found then raise exception using errcode='P0002',message='inventory_item_not_found'; end if;
  v_new_consumed:=v_lr.consumed_quantity+p_quantity;
  v_new_status:=case when v_new_consumed=v_lr.quantity then 'consumed' else 'active' end;
  insert into e10.lot_transition_guards(backend_pid,transaction_id)
    values(pg_backend_pid(),txid_current()) on conflict do nothing;
  if v_new_status='consumed' then
    update public.e10_inventory_reservations set status='consumed'
      where organization_id=p_org and id=v_lr.legacy_reservation_id and status='active';
  else
    update public.e10_inventory_reservations set qty=qty-p_quantity
      where organization_id=p_org and id=v_lr.legacy_reservation_id and status='active';
  end if;
  if not found then raise exception using errcode='55000',message='linked_legacy_reservation_not_active'; end if;
  delete from e10.lot_transition_guards where backend_pid=pg_backend_pid() and transaction_id=txid_current();
  update public.e10_inventory_items set qty=qty-p_quantity,updated_by=auth.uid(),updated_at=now()
    where organization_id=p_org and id=v_lot.inventory_item_id and qty>=p_quantity;
  if not found then raise exception using errcode='23514',message='insufficient_on_hand_quantity'; end if;
  update public.e10_lot_reservations set consumed_quantity=v_new_consumed,status=v_new_status,updated_at=now()
    where organization_id=p_org and id=p_reservation_id;
  v_movement_key:=p_org::text||':lot-consume:'||p_idempotency_key;
  v_mid:=public.e10_org_emit_inventory_movement(p_org,v_lot.inventory_item_id,'break_consumption',-p_quantity,-p_quantity,
    v_movement_key,'break','lot-backed consumption','lot_reservation',p_reservation_id::text,'consume',null,
    jsonb_build_object('lot_id',v_lr.lot_id,'lot_reservation_id',p_reservation_id,'consumed_quantity',v_new_consumed));
  insert into public.e10_lot_reservation_transitions(organization_id,lot_reservation_id,action,quantity,idempotency_key,
    request_fingerprint,movement_id,resulting_status,resulting_consumed_quantity,resulting_remaining_quantity,created_by)
  values(p_org,p_reservation_id,'consume',p_quantity,p_idempotency_key,v_fp,v_mid,v_new_status,v_new_consumed,v_lr.quantity-v_new_consumed,auth.uid());
  return jsonb_build_object('ok',true,'replay',false,'movement_id',v_mid,'status',v_new_status,'consumed_quantity',v_new_consumed,'remaining_quantity',v_lr.quantity-v_new_consumed);
end;
$$;

create or replace function public.e10_org_lot_release(
  p_org uuid, p_reservation_id uuid, p_idempotency_key text
) returns jsonb
language plpgsql security definer set search_path=public as $$
declare
  v_lr record; v_lot record; v_existing record; v_fp text; v_remaining numeric;
  v_mid uuid; v_movement_key text;
begin
  if not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.inventory_edit') then
    raise exception using errcode='42501',message='release_inventory_denied';
  end if;
  if p_idempotency_key is null or btrim(p_idempotency_key)='' then raise exception using errcode='22004',message='idempotency_key_required'; end if;
  v_fp:=md5(p_reservation_id::text||'|release');
  perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|lot-transition|'||p_idempotency_key,0));
  select action,quantity,request_fingerprint,movement_id,resulting_status,resulting_consumed_quantity,resulting_remaining_quantity into v_existing
    from public.e10_lot_reservation_transitions where organization_id=p_org and idempotency_key=p_idempotency_key;
  if found then
    if v_existing.request_fingerprint is distinct from v_fp then raise exception using errcode='22023',message='idempotency_key_mismatch'; end if;
    return jsonb_build_object('ok',true,'replay',true,'movement_id',v_existing.movement_id,'status',v_existing.resulting_status,
      'released_quantity',v_existing.quantity,'consumed_quantity',v_existing.resulting_consumed_quantity,'remaining_quantity',v_existing.resulting_remaining_quantity);
  end if;
  select id,lot_id,quantity,consumed_quantity,status,legacy_reservation_id into v_lr
    from public.e10_lot_reservations where organization_id=p_org and id=p_reservation_id for update;
  if not found then raise exception using errcode='42501',message='lot_reservation_access_denied'; end if;
  if v_lr.status<>'active' then raise exception using errcode='55000',message='lot_reservation_not_active'; end if;
  v_remaining:=v_lr.quantity-v_lr.consumed_quantity;
  if v_remaining<=0 then raise exception using errcode='55000',message='no_releasable_quantity'; end if;
  select id,inventory_item_id into v_lot from public.e10_inventory_lots
    where organization_id=p_org and id=v_lr.lot_id for update;
  if v_lot.inventory_item_id is null then raise exception using errcode='55000',message='lot_inventory_item_missing'; end if;
  perform 1 from public.e10_inventory_items where organization_id=p_org and id=v_lot.inventory_item_id for update;
  if not found then raise exception using errcode='P0002',message='inventory_item_not_found'; end if;
  insert into e10.lot_transition_guards(backend_pid,transaction_id)
    values(pg_backend_pid(),txid_current()) on conflict do nothing;
  update public.e10_inventory_reservations set status='released'
    where organization_id=p_org and id=v_lr.legacy_reservation_id and status='active';
  if not found then raise exception using errcode='55000',message='linked_legacy_reservation_not_active'; end if;
  delete from e10.lot_transition_guards where backend_pid=pg_backend_pid() and transaction_id=txid_current();
  update public.e10_lot_reservations set status='released',updated_at=now()
    where organization_id=p_org and id=p_reservation_id;
  v_movement_key:=p_org::text||':lot-release:'||p_idempotency_key;
  v_mid:=public.e10_org_emit_inventory_movement(p_org,v_lot.inventory_item_id,'reservation_release',0,-v_remaining,
    v_movement_key,'release','lot-backed reservation released','lot_reservation',p_reservation_id::text,'release',null,
    jsonb_build_object('lot_id',v_lr.lot_id,'lot_reservation_id',p_reservation_id,'released_quantity',v_remaining,'consumed_quantity',v_lr.consumed_quantity));
  insert into public.e10_lot_reservation_transitions(organization_id,lot_reservation_id,action,quantity,idempotency_key,
    request_fingerprint,movement_id,resulting_status,resulting_consumed_quantity,resulting_remaining_quantity,created_by)
  values(p_org,p_reservation_id,'release',v_remaining,p_idempotency_key,v_fp,v_mid,'released',v_lr.consumed_quantity,0,auth.uid());
  return jsonb_build_object('ok',true,'replay',false,'movement_id',v_mid,'status','released','released_quantity',v_remaining,'consumed_quantity',v_lr.consumed_quantity);
end;
$$;

revoke all on function public.e10_org_lot_consume(uuid,uuid,numeric,text) from public,anon;
revoke all on function public.e10_org_lot_release(uuid,uuid,text) from public,anon;
grant execute on function public.e10_org_lot_consume(uuid,uuid,numeric,text) to authenticated,service_role;
grant execute on function public.e10_org_lot_release(uuid,uuid,text) to authenticated,service_role;

comment on table public.e10_lot_reservation_transitions is
  'Immutable idempotency and audit rows for lot reservation consume/release transitions.';
