-- TA-X5c atomic native inventory-action to lifecycle-event linkage.

alter table public.e10_commercial_events add column inventory_movement_id uuid;
alter table public.e10_commercial_events add constraint e10_commercial_events_org_movement_fkey
  foreign key(organization_id,inventory_movement_id) references public.e10_inventory_movements(organization_id,id);
create unique index e10_commercial_events_org_movement_uq
  on public.e10_commercial_events(organization_id,inventory_movement_id) where inventory_movement_id is not null;

create or replace function e10.capture_native_inventory_event() returns trigger
language plpgsql security definer set search_path=public as $$
declare v_event_type text; v_corrects uuid; v_fp text;
begin
  v_event_type:=case
    when new.movement_type='intake' then 'receipt'
    when new.movement_type='reservation' then 'hold'
    when new.movement_type='reservation_release' then 'release'
    when new.movement_type='sale' then 'sale_committed'
    when new.movement_type='break_consumption' then 'fulfillment'
    when new.movement_type='return' then 'return'
    when new.movement_type='correction' and new.source_action='reverse' then 'correction'
    else null end;
  if v_event_type is null then return new; end if;
  if v_event_type='correction' then
    select ce.id into v_corrects
      from public.e10_stock_receipt_lines rl
      join public.e10_commercial_events ce on ce.organization_id=rl.organization_id
        and ce.inventory_movement_id=rl.inventory_movement_id
      where rl.organization_id=new.organization_id
        and rl.stock_receipt_id=nullif(new.meta->>'receipt_id','')::uuid
      order by ce.created_at,ce.id limit 1;
    if not found then return new; end if;
  end if;
  v_fp:=md5(new.id::text||'|'||v_event_type||'|'||new.item_id);
  insert into public.e10_commercial_events(organization_id,event_type,subject_type,subject_id,occurred_at,
    idempotency_key,source_kind,source_reference,payload,corrects_event_id,created_by,request_fingerprint,inventory_movement_id)
  values(new.organization_id,v_event_type,'inventory_item',new.item_id,new.created_at,
    new.organization_id::text||':native-movement:'||new.id::text,'native',new.source_entity_type||':'||coalesce(new.source_entity_id,''),
    jsonb_build_object('movement_id',new.id,'movement_type',new.movement_type,'on_hand_delta',new.on_hand_delta,
      'reserved_delta',new.reserved_delta,'source_action',new.source_action,'reason_code',new.reason_code),
    v_corrects,new.actor_uid,v_fp,new.id)
  on conflict(organization_id,inventory_movement_id) where inventory_movement_id is not null do nothing;
  return new;
end;
$$;
revoke all on function e10.capture_native_inventory_event() from public,anon,authenticated;
grant execute on function e10.capture_native_inventory_event() to service_role;
create trigger e10_capture_native_inventory_event_trg after insert on public.e10_inventory_movements
  for each row execute function e10.capture_native_inventory_event();

comment on function e10.capture_native_inventory_event() is
  'Same-transaction lifecycle evidence for trusted inventory movements. Does not post finance or customer spend.';
