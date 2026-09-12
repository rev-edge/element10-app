-- TA-X4f bounded, idempotent, atomic full-receipt reversal.
-- Allocation rows and original receipt evidence remain immutable. Reversal does
-- not create a supplier credit, payment, settlement, or accounting write-off.

create table public.e10_receipt_reversal_commands (
  organization_id uuid not null references public.e10_organizations(id),
  idempotency_key text not null check (btrim(idempotency_key)<>''),
  request_fingerprint text not null,
  stock_receipt_id uuid not null,
  result jsonb not null,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  primary key(organization_id,idempotency_key),
  foreign key(organization_id,stock_receipt_id)
    references public.e10_stock_receipts(organization_id,id)
);
alter table public.e10_receipt_reversal_commands enable row level security;
revoke all on table public.e10_receipt_reversal_commands from public,anon,authenticated;
grant all on table public.e10_receipt_reversal_commands to service_role;
create trigger e10_receipt_reversal_commands_append_only_trg
  before update or delete on public.e10_receipt_reversal_commands
  for each row execute function e10.reject_append_only_change();

-- Permit a trusted reversal writer to retain correction evidence for a line
-- whose effective accepted quantity is zero and therefore has no movement.
create or replace function e10.normalize_commercial_event_envelope() returns trigger
language plpgsql security definer set search_path=public as $$
begin
  if new.source_kind='native' then
    if new.inventory_movement_id is null and new.customer_activity_observation_id is null and not(
      current_setting('e10.receipt_evidence',true)='on' and new.event_type='receipt'
      and new.source_connection_id='receipt-ledger' and nullif(btrim(new.source_event_id),'') is not null
      and new.subject_type='inventory_item') and not(
      current_setting('e10.receipt_reversal_evidence',true)='on' and new.event_type='correction'
      and new.source_connection_id='receipt-ledger' and nullif(btrim(new.source_event_id),'') is not null
      and new.subject_type='inventory_item') then
      raise exception using errcode='42501',message='native_evidence_requires_inventory_movement';
    end if;
    new.evidence_quality:='native_system';
    new.source_connection_id:=coalesce(nullif(btrim(new.source_connection_id),''),
      case when new.inventory_movement_id is not null then 'inventory-ledger'
        when new.customer_activity_observation_id is not null then 'live-break-slot' else 'receipt-ledger' end);
    new.source_event_id:=coalesce(nullif(btrim(new.source_event_id),''),new.inventory_movement_id::text,
      new.customer_activity_observation_id::text);
    new.correlation_id:=coalesce(nullif(btrim(new.correlation_id),''),nullif(btrim(new.source_reference),''),
      new.inventory_movement_id::text,new.customer_activity_observation_id::text);
  elsif new.source_kind='system' then
    raise exception using errcode='42501',message='system_evidence_requires_trusted_writer';
  elsif new.source_kind='import' and new.evidence_quality='operator_asserted' then
    new.evidence_quality:='imported_unreviewed';
  end if;
  if new.source_kind<>'native' and not e10.valid_commercial_event_payload(new.event_type,new.payload) then
    raise exception using errcode='22023',message='event_payload_invalid_for_schema';
  end if;
  return new;
end $$;
revoke all on function e10.normalize_commercial_event_envelope() from public,anon,authenticated;
grant execute on function e10.normalize_commercial_event_envelope() to service_role;

-- Preserve the X5c.1 native semantics while making receipt correction lineage
-- exact to the affected receipt line instead of selecting the receipt's first line.
create or replace function e10.capture_native_inventory_event() returns trigger
language plpgsql security definer set search_path=public as $$
declare
  v_event_type text;v_corrects uuid;v_fp text;v_payload jsonb;v_receipt_line_id uuid;
  v_occurred_at timestamptz:=new.created_at;v_receipt_id uuid;v_original record;receipt_source record;
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
    select sr.received_at,rl.id receipt_line_id,rl.stock_receipt_id,rl.inventory_lot_id,
      po.purchase_order_line_id,inv.invoice_line_id
    into receipt_source
    from public.e10_stock_receipt_lines rl
    join public.e10_stock_receipts sr on sr.organization_id=rl.organization_id and sr.id=rl.stock_receipt_id
    left join public.e10_receipt_po_allocations po on po.organization_id=rl.organization_id and po.receipt_line_id=rl.id
    left join public.e10_receipt_invoice_allocations inv on inv.organization_id=rl.organization_id and inv.receipt_line_id=rl.id
    where rl.organization_id=new.organization_id and rl.id=nullif(new.source_entity_id,'')::uuid;
    if found then v_receipt_line_id:=receipt_source.receipt_line_id;v_occurred_at:=coalesce(receipt_source.received_at,new.created_at); end if;
  end if;
  if v_event_type='correction' then
    v_receipt_id:=nullif(new.meta->>'receipt_id','')::uuid;
    v_receipt_line_id:=coalesce(nullif(new.meta->>'receipt_line_id','')::uuid,
      case when new.source_entity_type='stock_receipt_line' then nullif(new.source_entity_id,'')::uuid end);
    select ce.id into v_corrects
    from public.e10_stock_receipt_lines rl
    join public.e10_commercial_events ce on ce.organization_id=rl.organization_id
      and ce.inventory_movement_id=rl.inventory_movement_id
    where rl.organization_id=new.organization_id and rl.stock_receipt_id=v_receipt_id
      and (v_receipt_line_id is null or rl.id=v_receipt_line_id)
    order by ce.created_at,ce.id limit 1;
    if not found then
      select m.*,sr.received_at source_occurred_at,rl.id receipt_line_id,rl.inventory_lot_id
      into v_original
      from public.e10_stock_receipt_lines rl
      join public.e10_stock_receipts sr on sr.organization_id=rl.organization_id and sr.id=rl.stock_receipt_id
      join public.e10_inventory_movements m on m.organization_id=rl.organization_id and m.id=rl.inventory_movement_id
      where rl.organization_id=new.organization_id and rl.stock_receipt_id=v_receipt_id
        and (v_receipt_line_id is null or rl.id=v_receipt_line_id)
      order by rl.line_no,rl.id limit 1;
      if not found then return new;end if;
      v_fp:=md5(v_original.id::text||'|receipt|'||v_original.item_id);
      insert into public.e10_commercial_events(organization_id,event_type,subject_type,subject_id,occurred_at,
        idempotency_key,source_kind,source_reference,payload,created_by,request_fingerprint,inventory_movement_id)
      values(v_original.organization_id,'receipt','inventory_item',v_original.item_id,
        coalesce(v_original.source_occurred_at,v_original.created_at),
        v_original.organization_id::text||':native-movement:'||v_original.id::text,'native',
        v_original.source_entity_type||':'||coalesce(v_original.source_entity_id,''),
        jsonb_build_object('movement_id',v_original.id,'movement_type',v_original.movement_type,
          'on_hand_delta',v_original.on_hand_delta,'reserved_delta',v_original.reserved_delta,
          'source_action',v_original.source_action,'reason_code',v_original.reason_code,
          'captured_retroactively',true,'source_receipt_id',v_receipt_id,
          'receipt_line_id',v_original.receipt_line_id,'lot_id',v_original.inventory_lot_id),
        v_original.actor_uid,v_fp,v_original.id)
      on conflict(organization_id,inventory_movement_id) where inventory_movement_id is not null do nothing
      returning id into v_corrects;
      if v_corrects is null then select id into v_corrects from public.e10_commercial_events
        where organization_id=v_original.organization_id and inventory_movement_id=v_original.id;end if;
    end if;
    if v_corrects is null then return new;end if;
  end if;
  v_payload:=jsonb_build_object('movement_id',new.id,'movement_type',new.movement_type,
    'on_hand_delta',new.on_hand_delta,'reserved_delta',new.reserved_delta,
    'source_action',new.source_action,'reason_code',new.reason_code,
    'operational_evidence_only',v_event_type in('sale_committed','fulfillment'));
  if v_event_type='receipt' and v_receipt_line_id is not null then
    v_payload:=v_payload||jsonb_build_object('receipt_id',receipt_source.stock_receipt_id::text,
      'receipt_line_id',receipt_source.receipt_line_id,'lot_id',receipt_source.inventory_lot_id,
      'purchase_order_line_id',receipt_source.purchase_order_line_id,
      'invoice_line_id',receipt_source.invoice_line_id,'command',new.meta->>'command');
  elsif v_event_type='correction' and v_receipt_id is not null then
    v_payload:=v_payload||jsonb_build_object('receipt_id',v_receipt_id,'receipt_line_id',v_receipt_line_id,
      'lot_id',nullif(new.meta->>'lot_id','')::uuid,'reversal_id',nullif(new.meta->>'reversal_id','')::uuid,
      'command',new.meta->>'command');
  end if;
  v_fp:=md5(new.id::text||'|'||v_event_type||'|'||new.item_id);
  insert into public.e10_commercial_events(organization_id,event_type,subject_type,subject_id,occurred_at,
    idempotency_key,source_kind,source_reference,payload,corrects_event_id,created_by,
    request_fingerprint,inventory_movement_id)
  values(new.organization_id,v_event_type,'inventory_item',new.item_id,v_occurred_at,
    new.organization_id::text||':native-movement:'||new.id::text,'native',
    new.source_entity_type||':'||coalesce(new.source_entity_id,''),v_payload,v_corrects,
    new.actor_uid,v_fp,new.id)
  on conflict(organization_id,inventory_movement_id) where inventory_movement_id is not null do nothing;
  return new;
end $$;
revoke all on function e10.capture_native_inventory_event() from public,anon,authenticated;
grant execute on function e10.capture_native_inventory_event() to service_role;
comment on function e10.capture_native_inventory_event() is
  'Same-transaction native inventory lifecycle evidence with exact receipt-line correction lineage. Sale and fulfillment events are operational evidence, not official customer spend.';

create function public.e10_org_reverse_receipt_batch(
  p_org uuid,p_receipt_id uuid,p_reason text,p_idempotency_key text
) returns jsonb
language plpgsql security definer set search_path=public as $$
#variable_conflict use_variable
declare
  actor uuid:=auth.uid();fp text;existing record;receipt_status text;line_count integer;topology_count integer;processed_count integer:=0;
  line record;q record;allocation record;effective_accepted numeric;active_reserved numeric;
  reversal_id uuid;movement_id uuid;event_id uuid;original_event uuid;
  lines jsonb:='[]'::jsonb;result jsonb;
begin
  if actor is null or not exists(select 1 from public.e10_organizations where id=p_org and status='active')
    or not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.resolve_recovery') then
    raise exception using errcode='42501',message='resolve_recovery_denied';
  end if;
  if p_receipt_id is null or p_reason is null or btrim(p_reason)='' or length(p_reason)>2000
    or p_idempotency_key is null or btrim(p_idempotency_key)='' or length(p_idempotency_key)>160 then
    raise exception using errcode='22023',message='receipt_reversal_payload_invalid';
  end if;
  fp:=md5(jsonb_build_object('v','receipt-reversal-batch-v1','org',p_org,
    'receipt',p_receipt_id,'reason',p_reason)::text);
  perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|receipt-reversal-command|'||p_idempotency_key,0));
  select c.request_fingerprint,c.result into existing from public.e10_receipt_reversal_commands c
    where c.organization_id=p_org and c.idempotency_key=p_idempotency_key;
  if found then
    if existing.request_fingerprint<>fp then raise exception using errcode='22023',message='idempotency_key_mismatch';end if;
    if auth.uid() is distinct from actor
      or not exists(select 1 from public.e10_organizations where id=p_org and status='active')
      or not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.resolve_recovery') then
      raise exception using errcode='42501',message='resolve_recovery_denied';
    end if;
    return existing.result||jsonb_build_object('replay',true);
  end if;

  -- Reuse the financial-document then purchase-order lock hierarchy for every
  -- source represented by the receipt before locking physical dependencies.
  for allocation in
    select distinct il.supplier_invoice_id id
    from public.e10_stock_receipt_lines rl
    join public.e10_receipt_invoice_allocations a on(a.organization_id,a.receipt_line_id)=(rl.organization_id,rl.id)
    join public.e10_supplier_invoice_lines il on(il.organization_id,il.id)=(a.organization_id,a.invoice_line_id)
    where rl.organization_id=p_org and rl.stock_receipt_id=p_receipt_id order by id
  loop perform e10.lock_financial_document(p_org,'supplier_invoice',allocation.id);end loop;
  for allocation in
    select distinct pl.purchase_order_id id
    from public.e10_stock_receipt_lines rl
    join public.e10_receipt_po_allocations a on(a.organization_id,a.receipt_line_id)=(rl.organization_id,rl.id)
    join public.e10_purchase_order_lines pl on(pl.organization_id,pl.id)=(a.organization_id,a.purchase_order_line_id)
    where rl.organization_id=p_org and rl.stock_receipt_id=p_receipt_id order by id
  loop perform e10.lock_purchase_order(p_org,allocation.id);end loop;

  select r.status into receipt_status from public.e10_stock_receipts r
    where r.organization_id=p_org and r.id=p_receipt_id for update;
  if not found then raise exception using errcode='42501',message='receipt_access_denied';end if;
  if receipt_status not in('posted','corrected') then raise exception using errcode='55000',message='receipt_not_reversible';end if;
  select count(*) into line_count from public.e10_stock_receipt_lines rl
    where rl.organization_id=p_org and rl.stock_receipt_id=p_receipt_id;
  if line_count not between 1 and 100 then raise exception using errcode='55000',message='receipt_line_count_out_of_bounds';end if;
  select count(*) into topology_count
  from public.e10_stock_receipt_lines rl
  join public.e10_inventory_lots l on(l.organization_id,l.id)=(rl.organization_id,rl.inventory_lot_id)
    and l.stock_receipt_line_id=rl.id and l.inventory_item_id is not null
  join public.e10_inventory_items i on(i.organization_id,i.id)=(l.organization_id,l.inventory_item_id)
  where rl.organization_id=p_org and rl.stock_receipt_id=p_receipt_id;
  if topology_count<>line_count then
    raise exception using errcode='55000',message='receipt_line_topology_invalid';
  end if;

  perform 1 from public.e10_stock_receipt_lines rl where rl.organization_id=p_org and rl.stock_receipt_id=p_receipt_id order by rl.id for update;
  perform 1 from public.e10_receipt_po_allocations a where a.organization_id=p_org and a.receipt_line_id in(
    select id from public.e10_stock_receipt_lines where organization_id=p_org and stock_receipt_id=p_receipt_id) order by a.receipt_line_id,a.purchase_order_line_id for update;
  perform 1 from public.e10_receipt_invoice_allocations a where a.organization_id=p_org and a.receipt_line_id in(
    select id from public.e10_stock_receipt_lines where organization_id=p_org and stock_receipt_id=p_receipt_id) order by a.receipt_line_id,a.invoice_line_id for update;
  -- Match X4b's per-lot advisory key before any reservation or lot row. This
  -- prevents a new lot reservation from appearing after the dependency census.
  for allocation in
    select l.id from public.e10_inventory_lots l where l.organization_id=p_org and l.stock_receipt_line_id in(
      select id from public.e10_stock_receipt_lines where organization_id=p_org and stock_receipt_id=p_receipt_id)
    order by l.id
  loop perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|lot|'||allocation.id::text,0));end loop;
  -- X4c transitions lock reservation -> lot -> item, so preserve that row-lock
  -- order after taking the reservation-creation advisory keys.
  perform 1 from public.e10_lot_reservations lr where lr.organization_id=p_org and lr.lot_id in(
    select l.id from public.e10_inventory_lots l join public.e10_stock_receipt_lines rl
      on(rl.organization_id,rl.id)=(l.organization_id,l.stock_receipt_line_id)
    where rl.organization_id=p_org and rl.stock_receipt_id=p_receipt_id) order by lr.id for update;
  perform 1 from public.e10_inventory_lots l where l.organization_id=p_org and l.stock_receipt_line_id in(
    select id from public.e10_stock_receipt_lines where organization_id=p_org and stock_receipt_id=p_receipt_id) order by l.id for update;
  perform 1 from public.e10_inventory_items i where i.organization_id=p_org and i.id in(
    select l.inventory_item_id from public.e10_inventory_lots l join public.e10_stock_receipt_lines rl
      on(rl.organization_id,rl.id)=(l.organization_id,l.stock_receipt_line_id)
    where rl.organization_id=p_org and rl.stock_receipt_id=p_receipt_id) order by i.id for update;
  perform 1 from public.e10_expected_inventory_allocations ea where ea.organization_id=p_org and ea.id in(
    select ev.expected_allocation_id from public.e10_expected_allocation_events ev join public.e10_stock_receipt_lines rl
      on(rl.organization_id,rl.id)=(ev.organization_id,ev.receipt_line_id)
    where rl.organization_id=p_org and rl.stock_receipt_id=p_receipt_id and ev.action='fulfill') order by ea.id for update;
  perform 1 from public.e10_inventory_reservations ir where ir.organization_id=p_org and ir.item_id in(
    select l.inventory_item_id from public.e10_inventory_lots l join public.e10_stock_receipt_lines rl
      on(rl.organization_id,rl.id)=(l.organization_id,l.stock_receipt_line_id)
    where rl.organization_id=p_org and rl.stock_receipt_id=p_receipt_id) order by ir.id for update;

  if auth.uid() is distinct from actor
    or not exists(select 1 from public.e10_organizations where id=p_org and status='active')
    or not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.resolve_recovery') then
    raise exception using errcode='42501',message='resolve_recovery_denied';
  end if;
  if exists(select 1 from public.e10_stock_receipt_reversals rv join public.e10_stock_receipt_lines rl
      on(rl.organization_id,rl.id)=(rv.organization_id,rv.stock_receipt_line_id)
      where rl.organization_id=p_org and rl.stock_receipt_id=p_receipt_id) then
    raise exception using errcode='55000',message='receipt_not_reversible';
  end if;
  if exists(select 1 from public.e10_lot_reservations lr join public.e10_inventory_lots l
      on(l.organization_id,l.id)=(lr.organization_id,lr.lot_id)
      join public.e10_stock_receipt_lines rl on(rl.organization_id,rl.id)=(l.organization_id,l.stock_receipt_line_id)
      where rl.organization_id=p_org and rl.stock_receipt_id=p_receipt_id
        and (lr.status='active' or lr.consumed_quantity>0)) then
    raise exception using errcode='55000',message='receipt_lot_has_committed_quantity';
  end if;
  if exists(
    select 1 from public.e10_stock_receipt_lines rl
    join public.e10_inventory_lots l on(l.organization_id,l.id)=(rl.organization_id,rl.inventory_lot_id)
    cross join lateral e10.receipt_line_effective_quantities(rl.organization_id,rl.id) eq
    where rl.organization_id=p_org and rl.stock_receipt_id=p_receipt_id
      and l.accepted_quantity<eq.effective_accepted
  ) then raise exception using errcode='55000',message='accepted_quantity_no_longer_reversible';end if;

  -- A shared legacy item can receive more than one line, so validate the item
  -- reservation floor against the aggregate removal before applying any line.
  for line in
    select l.inventory_item_id item_id,sum(eq.effective_accepted) removal,i.qty
    from public.e10_stock_receipt_lines rl
    join public.e10_inventory_lots l on(l.organization_id,l.stock_receipt_line_id)=(rl.organization_id,rl.id)
    join public.e10_inventory_items i on(i.organization_id,i.id)=(l.organization_id,l.inventory_item_id)
    cross join lateral e10.receipt_line_effective_quantities(rl.organization_id,rl.id) eq
    where rl.organization_id=p_org and rl.stock_receipt_id=p_receipt_id
    group by l.inventory_item_id,i.qty order by l.inventory_item_id
  loop
    select coalesce(sum(ir.qty),0) into active_reserved from public.e10_inventory_reservations ir
      where ir.organization_id=p_org and ir.item_id=line.item_id and ir.status='active';
    if line.qty-line.removal<active_reserved then
      raise exception using errcode='55000',message='accepted_quantity_is_reserved';
    end if;
  end loop;

  for line in
    select rl.id line_id,rl.line_no,rl.received_quantity,rl.inventory_lot_id,l.inventory_item_id,l.accepted_quantity
    from public.e10_stock_receipt_lines rl join public.e10_inventory_lots l
      on(l.organization_id,l.id)=(rl.organization_id,rl.inventory_lot_id)
    where rl.organization_id=p_org and rl.stock_receipt_id=p_receipt_id order by rl.id
  loop
    select * into q from e10.receipt_line_effective_quantities(p_org,line.line_id);
    effective_accepted:=q.effective_accepted;
    reversal_id:=gen_random_uuid();movement_id:=null;
    if effective_accepted>0 then
      update public.e10_inventory_items set qty=qty-effective_accepted,updated_by=actor,updated_at=now()
        where organization_id=p_org and id=line.inventory_item_id and qty>=effective_accepted;
      if not found then raise exception using errcode='55000',message='accepted_quantity_no_longer_reversible';end if;
      perform set_config('e10.emit','on',true);
      insert into public.e10_inventory_movements(workspace_id,item_id,movement_type,on_hand_delta,reserved_delta,
        source_entity_type,source_entity_id,source_action,actor_uid,reason_code,note,idempotency_key,meta,organization_id)
      values('shared',line.inventory_item_id,'correction',-effective_accepted,0,'stock_receipt_line',line.line_id::text,
        'reverse',actor,'correction',p_reason,p_org::text||':receipt-reversal-batch:'||p_idempotency_key||':'||line.line_id,
        jsonb_build_object('receipt_id',p_receipt_id,'receipt_line_id',line.line_id,'lot_id',line.inventory_lot_id,
          'reversal_id',reversal_id,'command',p_idempotency_key),p_org) returning id into movement_id;
    end if;
    insert into public.e10_stock_receipt_reversals(id,organization_id,stock_receipt_id,stock_receipt_line_id,inventory_lot_id,
      quantity,reason,idempotency_key,request_fingerprint,inventory_movement_id,reversed_by)
    values(reversal_id,p_org,p_receipt_id,line.line_id,line.inventory_lot_id,line.received_quantity,p_reason,
      p_idempotency_key||':'||line.line_id,fp,movement_id,actor);
    if movement_id is null then
      select ce.id into original_event from public.e10_commercial_events ce
        where ce.organization_id=p_org and ce.event_type='receipt'
          and ce.payload->>'receipt_line_id'=line.line_id::text order by ce.created_at,ce.id limit 1;
      if original_event is null then raise exception using errcode='55000',message='receipt_evidence_missing';end if;
      event_id:=gen_random_uuid();perform set_config('e10.receipt_reversal_evidence','on',true);
      insert into public.e10_commercial_events(id,organization_id,event_type,event_schema_version,subject_type,subject_id,
        occurred_at,occurred_at_precision,idempotency_key,source_kind,source_connection_id,source_reference,source_event_id,
        correlation_id,evidence_quality,payload,corrects_event_id,created_by,request_fingerprint)
      values(event_id,p_org,'correction',1,'inventory_item',line.inventory_item_id,now(),'exact',
        p_org::text||':receipt-reversal-event:'||p_idempotency_key||':'||line.line_id,'native','receipt-ledger',
        'stock_receipt_line:'||line.line_id,reversal_id::text,p_receipt_id::text,'native_system',
        jsonb_build_object('movement_id',null,'movement_type','correction','on_hand_delta',0,'reserved_delta',0,
          'source_action','reverse','reason_code','correction','receipt_id',p_receipt_id,'receipt_line_id',line.line_id,
          'lot_id',line.inventory_lot_id,'reversal_id',reversal_id,'command',p_idempotency_key),
        original_event,actor,md5(reversal_id::text||'|correction|'||line.inventory_item_id));
    end if;
    for allocation in
      select ev.expected_allocation_id,ev.quantity from public.e10_expected_allocation_events ev
      where ev.organization_id=p_org and ev.receipt_line_id=line.line_id and ev.action='fulfill'
      order by ev.expected_allocation_id,ev.id
    loop
      insert into public.e10_expected_allocation_events(organization_id,expected_allocation_id,receipt_line_id,
        receipt_reversal_id,action,quantity)
      values(p_org,allocation.expected_allocation_id,line.line_id,reversal_id,'reverse',allocation.quantity);
      update public.e10_expected_inventory_allocations set fulfilled_quantity=fulfilled_quantity-allocation.quantity,
        status=case when status='cancelled' then 'cancelled' else 'open' end,updated_at=now()
      where organization_id=p_org and id=allocation.expected_allocation_id;
    end loop;
    update public.e10_inventory_lots set status='reversed',updated_at=now()
      where organization_id=p_org and id=line.inventory_lot_id;
    lines:=lines||jsonb_build_array(jsonb_build_object('line_no',line.line_no,'receipt_line_id',line.line_id,
      'lot_id',line.inventory_lot_id,'reversal_id',reversal_id,'movement_id',movement_id,
      'effective_accepted_removed',effective_accepted));
    processed_count:=processed_count+1;
  end loop;
  if processed_count<>line_count then
    raise exception using errcode='55000',message='receipt_line_topology_invalid';
  end if;
  update public.e10_stock_receipts set status='reversed',updated_at=now()
    where organization_id=p_org and id=p_receipt_id;
  result:=jsonb_build_object('ok',true,'replay',false,'receipt_id',p_receipt_id,'status','reversed','lines',lines);
  insert into public.e10_receipt_reversal_commands(organization_id,idempotency_key,request_fingerprint,
    stock_receipt_id,result,created_by) values(p_org,p_idempotency_key,fp,p_receipt_id,result,actor);
  return result;
end $$;

revoke all on function public.e10_org_reverse_receipt_batch(uuid,uuid,text,text) from public,anon;
grant execute on function public.e10_org_reverse_receipt_batch(uuid,uuid,text,text) to authenticated,service_role;
comment on function public.e10_org_reverse_receipt_batch(uuid,uuid,text,text) is
  'Atomic full-receipt reversal. Preserves source allocations and history; creates no credit, payment, settlement, or accounting write-off.';
