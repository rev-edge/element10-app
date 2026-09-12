-- TA-X5c.1 preserve source occurrence time and link reversals of pre-X5c receipts.
-- created_at remains ingestion time. Operational sale/fulfillment evidence is not official customer spend.

create or replace function e10.capture_native_inventory_event() returns trigger
language plpgsql security definer set search_path=public as $$
declare
  v_event_type text;
  v_corrects uuid;
  v_fp text;
  v_occurred_at timestamptz:=new.created_at;
  v_receipt_id uuid;
  v_original record;
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

  if v_event_type='receipt' and new.source_entity_type='stock_receipt_line' then
    select sr.received_at into v_occurred_at
      from public.e10_stock_receipt_lines rl
      join public.e10_stock_receipts sr on sr.organization_id=rl.organization_id and sr.id=rl.stock_receipt_id
      where rl.organization_id=new.organization_id and rl.id=nullif(new.source_entity_id,'')::uuid;
    v_occurred_at:=coalesce(v_occurred_at,new.created_at);
  end if;

  if v_event_type='correction' then
    v_receipt_id:=nullif(new.meta->>'receipt_id','')::uuid;
    select ce.id into v_corrects
      from public.e10_stock_receipt_lines rl
      join public.e10_commercial_events ce on ce.organization_id=rl.organization_id
        and ce.inventory_movement_id=rl.inventory_movement_id
      where rl.organization_id=new.organization_id and rl.stock_receipt_id=v_receipt_id
      order by ce.created_at,ce.id limit 1;

    if not found then
      select m.*,sr.received_at as source_occurred_at into v_original
        from public.e10_stock_receipt_lines rl
        join public.e10_stock_receipts sr on sr.organization_id=rl.organization_id and sr.id=rl.stock_receipt_id
        join public.e10_inventory_movements m on m.organization_id=rl.organization_id and m.id=rl.inventory_movement_id
        where rl.organization_id=new.organization_id and rl.stock_receipt_id=v_receipt_id
        order by rl.line_no,rl.id limit 1;
      if not found then return new; end if;

      v_fp:=md5(v_original.id::text||'|receipt|'||v_original.item_id);
      insert into public.e10_commercial_events(organization_id,event_type,subject_type,subject_id,occurred_at,
        idempotency_key,source_kind,source_reference,payload,created_by,request_fingerprint,inventory_movement_id)
      values(v_original.organization_id,'receipt','inventory_item',v_original.item_id,
        coalesce(v_original.source_occurred_at,v_original.created_at),
        v_original.organization_id::text||':native-movement:'||v_original.id::text,
        'native',v_original.source_entity_type||':'||coalesce(v_original.source_entity_id,''),
        jsonb_build_object('movement_id',v_original.id,'movement_type',v_original.movement_type,
          'on_hand_delta',v_original.on_hand_delta,'reserved_delta',v_original.reserved_delta,
          'source_action',v_original.source_action,'reason_code',v_original.reason_code,
          'captured_retroactively',true,'source_receipt_id',v_receipt_id),
        v_original.actor_uid,v_fp,v_original.id)
      on conflict(organization_id,inventory_movement_id) where inventory_movement_id is not null do nothing
      returning id into v_corrects;
      if v_corrects is null then
        select id into v_corrects from public.e10_commercial_events
          where organization_id=v_original.organization_id
            and inventory_movement_id=v_original.id;
      end if;
    end if;
    if v_corrects is null then return new; end if;
  end if;

  v_fp:=md5(new.id::text||'|'||v_event_type||'|'||new.item_id);
  insert into public.e10_commercial_events(organization_id,event_type,subject_type,subject_id,occurred_at,
    idempotency_key,source_kind,source_reference,payload,corrects_event_id,created_by,request_fingerprint,inventory_movement_id)
  values(new.organization_id,v_event_type,'inventory_item',new.item_id,v_occurred_at,
    new.organization_id::text||':native-movement:'||new.id::text,'native',new.source_entity_type||':'||coalesce(new.source_entity_id,''),
    jsonb_build_object('movement_id',new.id,'movement_type',new.movement_type,'on_hand_delta',new.on_hand_delta,
      'reserved_delta',new.reserved_delta,'source_action',new.source_action,'reason_code',new.reason_code,
      'operational_evidence_only',v_event_type in ('sale_committed','fulfillment')),
    v_corrects,new.actor_uid,v_fp,new.id)
  on conflict(organization_id,inventory_movement_id) where inventory_movement_id is not null do nothing;
  return new;
end;
$$;

revoke all on function e10.capture_native_inventory_event() from public,anon,authenticated;
grant execute on function e10.capture_native_inventory_event() to service_role;

comment on function e10.capture_native_inventory_event() is
  'Same-transaction native inventory lifecycle evidence with source occurrence time where captured. Sale and fulfillment events are operational evidence, not official customer spend.';
