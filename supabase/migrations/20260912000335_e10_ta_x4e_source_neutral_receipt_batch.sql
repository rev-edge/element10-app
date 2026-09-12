-- TA-X4e source-neutral, bounded, multi-line physical receipt posting.
-- This records physical receipt evidence only. It does not approve invoices,
-- recognize charges, allocate landed cost, create payments, or create credits.

create table public.e10_receipt_commands (
  organization_id uuid not null references public.e10_organizations(id),
  idempotency_key text not null check (btrim(idempotency_key) <> ''),
  request_fingerprint text not null,
  stock_receipt_id uuid not null,
  result jsonb not null,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  primary key (organization_id,idempotency_key),
  foreign key (organization_id,stock_receipt_id)
    references public.e10_stock_receipts(organization_id,id)
);
alter table public.e10_receipt_commands enable row level security;
revoke all on table public.e10_receipt_commands from public,anon,authenticated;
grant all on table public.e10_receipt_commands to service_role;
create trigger e10_receipt_commands_append_only_trg
  before update or delete on public.e10_receipt_commands
  for each row execute function e10.reject_append_only_change();

create index e10_receipt_invoice_allocations_invoice_idx
  on public.e10_receipt_invoice_allocations(organization_id,invoice_line_id,receipt_line_id);

create function e10.receipt_line_effective_quantities(p_org uuid,p_receipt_line uuid)
returns table(
  physical_received numeric,effective_accepted numeric,effective_damaged numeric,
  unresolved_quarantined numeric,reversed_quantity numeric,remaining_quantity numeric
) language sql stable security definer set search_path=public as $$
 select l.received_quantity,
   case when r.status not in('posted','corrected') or exists(select 1 from public.e10_stock_receipt_reversals rv
     where rv.organization_id=l.organization_id and rv.stock_receipt_line_id=l.id) then 0 else l.accepted_quantity end,
   case when r.status not in('posted','corrected') or exists(select 1 from public.e10_stock_receipt_reversals rv
     where rv.organization_id=l.organization_id and rv.stock_receipt_line_id=l.id) then 0 else l.damaged_quantity end,
   case when r.status not in('posted','corrected') or exists(select 1 from public.e10_stock_receipt_reversals rv
     where rv.organization_id=l.organization_id and rv.stock_receipt_line_id=l.id) then 0 else l.quarantined_quantity end,
   case when r.status='reversed' or exists(select 1 from public.e10_stock_receipt_reversals rv
     where rv.organization_id=l.organization_id and rv.stock_receipt_line_id=l.id) then l.received_quantity else 0 end,
   case when r.status not in('posted','corrected') or exists(select 1 from public.e10_stock_receipt_reversals rv
     where rv.organization_id=l.organization_id and rv.stock_receipt_line_id=l.id) then 0
        else l.received_quantity-l.accepted_quantity-l.damaged_quantity-l.quarantined_quantity end
 from public.e10_stock_receipt_lines l
 join public.e10_stock_receipts r
   on r.organization_id=l.organization_id and r.id=l.stock_receipt_id
 where l.organization_id=p_org and l.id=p_receipt_line
$$;
revoke all on function e10.receipt_line_effective_quantities(uuid,uuid)
  from public,anon,authenticated;
grant execute on function e10.receipt_line_effective_quantities(uuid,uuid) to service_role;

create function public.e10_org_receive_batch(
  p_org uuid,p_supplier_id uuid,p_destination_location_id uuid,p_received_at timestamptz,
  p_lines jsonb,p_idempotency_key text
) returns jsonb
language plpgsql security definer set search_path=public as $$
#variable_conflict use_variable
declare
  actor uuid:=auth.uid(); fp text; existing record; receipt_id uuid:=gen_random_uuid();
  line_json jsonb; line_result jsonb:='[]'::jsonb; line_id uuid; lot_id uuid; movement_id uuid;
  line_no integer; config_id uuid; item_id text; po_line_id uuid; invoice_line_id uuid;
  accepted numeric; damaged numeric; quarantined numeric; physical numeric; prior numeric;
  lot_code text; unit_cost numeric; currency text; source_supplier uuid; source_destination uuid;
  source_config uuid; source_status text; source_line_state text; source_currency text; po_currency text; source_quantity numeric;
  expected jsonb; expected_total numeric; allocation record; lot_status text; event_id uuid;
  result jsonb;
begin
  if actor is null or not exists(select 1 from public.e10_organizations where id=p_org and status='active')
    or not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.create_receiving') then
    raise exception using errcode='42501',message='create_receiving_denied';
  end if;
  if p_supplier_id is null or p_destination_location_id is null
    or p_idempotency_key is null or btrim(p_idempotency_key)='' or length(p_idempotency_key)>200
    or p_lines is null or jsonb_typeof(p_lines)<>'array'
    or jsonb_array_length(p_lines) not between 1 and 100
    or octet_length(p_lines::text)>1048576
    or p_received_at is not null and not isfinite(p_received_at) then
    raise exception using errcode='22023',message='receipt_batch_payload_invalid';
  end if;
  fp:=md5(jsonb_build_object('v','receipt-batch-v1','org',p_org,'supplier',p_supplier_id,
    'destination',p_destination_location_id,'received_epoch',extract(epoch from p_received_at)::numeric,
    'lines',p_lines)::text);
  perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|receipt-command|'||p_idempotency_key,0));
  select c.request_fingerprint,c.result into existing from public.e10_receipt_commands c
    where c.organization_id=p_org and c.idempotency_key=p_idempotency_key;
  if found then
    if existing.request_fingerprint<>fp then
      raise exception using errcode='22023',message='idempotency_key_mismatch';
    end if;
    if auth.uid() is distinct from actor
      or not exists(select 1 from public.e10_organizations where id=p_org and status='active')
      or not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.create_receiving') then
      raise exception using errcode='42501',message='create_receiving_denied';
    end if;
    return existing.result||jsonb_build_object('replay',true);
  end if;

  perform 1 from public.e10_suppliers s
    where s.organization_id=p_org and s.id=p_supplier_id and s.status='active' for update;
  if not found then raise exception using errcode='42501',message='supplier_access_denied'; end if;
  perform 1 from public.e10_locations l
    where l.organization_id=p_org and l.id=p_destination_location_id for update;
  if not found or not e10.can_receive_at(p_org,p_destination_location_id) then
    raise exception using errcode='42501',message='receive_location_denied';
  end if;

  if exists(
    select 1 from jsonb_array_elements(p_lines) x
    group by (x->>'line_no')::integer having count(*)>1
  ) then raise exception using errcode='22023',message='duplicate_receipt_line_number'; end if;

  -- Reuse the established financial-document then purchase-order lock hierarchy.
  for allocation in
    select distinct il.supplier_invoice_id id from public.e10_supplier_invoice_lines il
    where il.organization_id=p_org and il.id in(
      select (x->>'invoice_line_id')::uuid from jsonb_array_elements(p_lines) x
      where nullif(x->>'invoice_line_id','') is not null) order by id
  loop perform e10.lock_financial_document(p_org,'supplier_invoice',allocation.id); end loop;
  for allocation in
    select distinct pol.purchase_order_id id from public.e10_purchase_order_lines pol
    where pol.organization_id=p_org and pol.id in(
      select (x->>'purchase_order_line_id')::uuid from jsonb_array_elements(p_lines) x
      where nullif(x->>'purchase_order_line_id','') is not null) order by id
  loop perform e10.lock_purchase_order(p_org,allocation.id); end loop;

  -- Lock every mutable physical dependency globally by class and ID before the
  -- final authority reread. Later per-line locks are therefore reentrant only.
  perform 1 from public.e10_inventory_items i where i.organization_id=p_org and i.id in(
    select x->>'inventory_item_id' from jsonb_array_elements(p_lines) x) order by i.id for update;
  perform 1 from public.e10_expected_inventory_allocations ea where ea.organization_id=p_org and ea.id in(
    select (a->>'id')::uuid from jsonb_array_elements(p_lines) x
    cross join lateral jsonb_array_elements(case when jsonb_typeof(x->'expected_allocations')='array'
      then x->'expected_allocations' else '[]'::jsonb end) a) order by ea.id for update;

  if auth.uid() is distinct from actor
    or not exists(select 1 from public.e10_organizations where id=p_org and status='active')
    or not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.create_receiving')
    or not e10.can_receive_at(p_org,p_destination_location_id) then
    raise exception using errcode='42501',message='create_receiving_denied';
  end if;

  insert into public.e10_stock_receipts(id,organization_id,supplier_id,destination_location_id,status,
    received_at,created_by,idempotency_key,request_fingerprint)
  values(receipt_id,p_org,p_supplier_id,p_destination_location_id,'posted',coalesce(p_received_at,now()),
    actor,p_idempotency_key,fp);

  for line_json in select x from jsonb_array_elements(p_lines) x order by (x->>'line_no')::integer loop
    begin
      if jsonb_typeof(line_json) is distinct from 'object'
        or jsonb_typeof(line_json->'line_no') is distinct from 'number'
        or jsonb_typeof(line_json->'configuration_version_id') is distinct from 'string'
        or jsonb_typeof(line_json->'inventory_item_id') is distinct from 'string'
        or jsonb_typeof(line_json->'accepted_quantity') is distinct from 'number'
        or jsonb_typeof(line_json->'damaged_quantity') is distinct from 'number'
        or jsonb_typeof(line_json->'quarantined_quantity') is distinct from 'number'
        or (line_json ? 'actual_unit_cost' and jsonb_typeof(line_json->'actual_unit_cost') not in('number','null'))
        or (line_json ? 'currency' and jsonb_typeof(line_json->'currency') not in('string','null'))
        or (line_json ? 'expected_allocations' and jsonb_typeof(line_json->'expected_allocations')<>'array') then
        raise exception using errcode='22023',message='receipt_line_payload_invalid';
      end if;
      line_no:=(line_json->>'line_no')::integer;
      config_id:=(line_json->>'configuration_version_id')::uuid;
      item_id:=line_json->>'inventory_item_id';
      po_line_id:=nullif(line_json->>'purchase_order_line_id','')::uuid;
      invoice_line_id:=nullif(line_json->>'invoice_line_id','')::uuid;
      accepted:=coalesce((line_json->>'accepted_quantity')::numeric,0);
      damaged:=coalesce((line_json->>'damaged_quantity')::numeric,0);
      quarantined:=coalesce((line_json->>'quarantined_quantity')::numeric,0);
      physical:=accepted+damaged+quarantined;
      lot_code:=nullif(btrim(line_json->>'lot_code'),'');
      unit_cost:=case when jsonb_typeof(line_json->'actual_unit_cost')='number' then (line_json->>'actual_unit_cost')::numeric end;
      currency:=nullif(line_json->>'currency','');
      expected:=coalesce(line_json->'expected_allocations','[]'::jsonb);
    exception when others then
      raise exception using errcode='22023',message='receipt_line_payload_invalid';
    end;
    if line_no is null or line_no<1 or config_id is null or coalesce(btrim(item_id),'')=''
      or accepted<0 or damaged<0 or quarantined<0 or physical<=0
      or accepted::text in('NaN','Infinity','-Infinity') or damaged::text in('NaN','Infinity','-Infinity')
      or quarantined::text in('NaN','Infinity','-Infinity')
      or unit_cost<0 or unit_cost::text in('NaN','Infinity','-Infinity')
      or (currency is not null and currency!~'^[A-Z]{3}$')
      or (unit_cost is null)<>(currency is null) or jsonb_typeof(expected)<>'array'
      or jsonb_array_length(expected)>100 then
      raise exception using errcode='22023',message='receipt_line_payload_invalid';
    end if;
    if exists(select 1 from jsonb_array_elements(expected) x group by (x->>'id')::uuid having count(*)>1) then
      raise exception using errcode='22023',message='duplicate_expected_allocation';
    end if;
    if exists(select 1 from jsonb_array_elements(expected) x
      where jsonb_typeof(x) is distinct from 'object'
        or jsonb_typeof(x->'id') is distinct from 'string'
        or jsonb_typeof(x->'quantity') is distinct from 'number'
        or (x->>'quantity')::numeric<=0
        or (x->>'quantity') in('NaN','Infinity','-Infinity')) then
      raise exception using errcode='22023',message='expected_allocation_payload_invalid';
    end if;

    if po_line_id is not null then
      select po.supplier_id,po.destination_location_id,pol.configuration_version_id,po.status,po.currency,pol.ordered_quantity,pol.state
        into source_supplier,source_destination,source_config,source_status,po_currency,source_quantity,source_line_state
      from public.e10_purchase_order_lines pol join public.e10_purchase_orders po
        on po.organization_id=pol.organization_id and po.id=pol.purchase_order_id
      where pol.organization_id=p_org and pol.id=po_line_id;
      if not found or source_supplier is distinct from p_supplier_id or source_destination is distinct from p_destination_location_id
        or source_config is distinct from config_id or source_status not in('submitted','approved')
        or source_line_state is distinct from 'active' then
        raise exception using errcode='42501',message='purchase_order_line_access_denied';
      end if;
      select coalesce(sum(a.allocated_quantity),0) into prior
      from public.e10_receipt_po_allocations a
      join public.e10_stock_receipt_lines rl on rl.organization_id=a.organization_id and rl.id=a.receipt_line_id
      join public.e10_stock_receipts sr on sr.organization_id=rl.organization_id and sr.id=rl.stock_receipt_id
      where a.organization_id=p_org and a.purchase_order_line_id=po_line_id and sr.status<>'reversed';
      if prior+physical>source_quantity then raise exception using errcode='23514',message='over_receipt_not_authorized'; end if;
    end if;

    if invoice_line_id is not null then
      select si.supplier_id,il.configuration_version_id,si.status,si.currency,il.invoiced_quantity
        into source_supplier,source_config,source_status,source_currency,source_quantity
      from public.e10_supplier_invoice_lines il join public.e10_supplier_invoices si
        on si.organization_id=il.organization_id and si.id=il.supplier_invoice_id
      where il.organization_id=p_org and il.id=invoice_line_id and il.state='active';
      if not found or source_supplier is distinct from p_supplier_id or source_config is distinct from config_id
        or source_status not in('draft','reviewed','approved') or source_quantity is null
        or currency is not null and source_currency<>currency
        or po_line_id is not null and source_currency<>po_currency then
        raise exception using errcode='42501',message='invoice_line_access_denied';
      end if;
      select coalesce(sum(a.allocated_quantity),0) into prior
      from public.e10_receipt_invoice_allocations a
      join public.e10_stock_receipt_lines rl on rl.organization_id=a.organization_id and rl.id=a.receipt_line_id
      join public.e10_stock_receipts sr on sr.organization_id=rl.organization_id and sr.id=rl.stock_receipt_id
      where a.organization_id=p_org and a.invoice_line_id=invoice_line_id and sr.status<>'reversed';
      if prior+physical>source_quantity then raise exception using errcode='23514',message='invoice_receipt_overallocated'; end if;
    end if;

    perform 1 from public.e10_product_configuration_versions v
      where v.organization_id=p_org and v.id=config_id and v.state='active';
    if not found then raise exception using errcode='42501',message='configuration_access_denied'; end if;
    perform 1 from public.e10_inventory_items i where i.organization_id=p_org and i.id=item_id
      and (i.configuration_version_id=config_id or (i.configuration_version_id is null and i.qty=0
        and not exists(select 1 from public.e10_inventory_movements m where m.organization_id=p_org and m.item_id=i.id)
        and not exists(select 1 from public.e10_inventory_reservations r where r.organization_id=p_org and r.item_id=i.id))) for update;
    if not found then raise exception using errcode='42501',message='inventory_item_access_denied'; end if;
    update public.e10_inventory_items set configuration_version_id=config_id
      where organization_id=p_org and id=item_id and configuration_version_id is null;

    lot_status:=case when accepted>0 then 'available' else 'quarantined' end;
    insert into public.e10_inventory_lots(organization_id,configuration_version_id,location_id,supplier_id,
      inventory_item_id,lot_code,status,accepted_quantity,quarantined_quantity)
    values(p_org,config_id,p_destination_location_id,p_supplier_id,item_id,lot_code,lot_status,accepted,quarantined)
    returning id into lot_id;
    insert into public.e10_stock_receipt_lines(organization_id,stock_receipt_id,configuration_version_id,line_no,
      received_quantity,accepted_quantity,damaged_quantity,quarantined_quantity,actual_unit_cost,currency,inventory_lot_id)
    values(p_org,receipt_id,config_id,line_no,physical,accepted,damaged,quarantined,unit_cost,currency,lot_id)
    returning id into line_id;
    update public.e10_inventory_lots set stock_receipt_line_id=line_id where organization_id=p_org and id=lot_id;
    if po_line_id is not null then
      insert into public.e10_receipt_po_allocations values(p_org,line_id,po_line_id,physical,now());
    end if;
    if invoice_line_id is not null then
      insert into public.e10_receipt_invoice_allocations values(p_org,line_id,invoice_line_id,physical,now());
    end if;

    select coalesce(sum((x->>'quantity')::numeric),0) into expected_total from jsonb_array_elements(expected) x;
    if expected_total>accepted or expected_total>0 and po_line_id is null then
      raise exception using errcode='23514',message='expected_allocation_exceeds_accepted_quantity';
    end if;
    for allocation in select (x->>'id')::uuid id,(x->>'quantity')::numeric quantity
      from jsonb_array_elements(expected) x order by (x->>'id')::uuid loop
      perform 1 from public.e10_expected_inventory_allocations ea where ea.organization_id=p_org and ea.id=allocation.id
        and ea.purchase_order_line_id=po_line_id and ea.destination_location_id=p_destination_location_id
        and ea.status='open' and ea.fulfilled_quantity+allocation.quantity<=ea.expected_quantity for update;
      if not found then raise exception using errcode='23514',message='expected_allocation_invalid_or_exceeded'; end if;
      insert into public.e10_expected_allocation_events(organization_id,expected_allocation_id,receipt_line_id,action,quantity)
      values(p_org,allocation.id,line_id,'fulfill',allocation.quantity);
      update public.e10_expected_inventory_allocations set fulfilled_quantity=fulfilled_quantity+allocation.quantity,
        status=case when fulfilled_quantity+allocation.quantity=expected_quantity then 'fulfilled' else 'open' end,updated_at=now()
      where organization_id=p_org and id=allocation.id;
    end loop;

    movement_id:=null;
    if accepted>0 then
      update public.e10_inventory_items set qty=qty+accepted,updated_by=actor,updated_at=now()
        where organization_id=p_org and id=item_id;
      perform set_config('e10.emit','on',true);
      insert into public.e10_inventory_movements(workspace_id,item_id,movement_type,on_hand_delta,reserved_delta,
        source_entity_type,source_entity_id,source_action,actor_uid,reason_code,note,idempotency_key,meta,organization_id,created_at)
      values('shared',item_id,'intake',accepted,0,'stock_receipt_line',line_id::text,'receive',actor,'intake',
        'accepted receipt quantity',p_org::text||':receive-batch:'||p_idempotency_key||':'||line_no,
        jsonb_build_object('receipt_id',receipt_id,'receipt_line_id',line_id,'lot_id',lot_id,
          'purchase_order_line_id',po_line_id,'invoice_line_id',invoice_line_id,'command',p_idempotency_key),p_org,
        coalesce(p_received_at,now()))
      returning id into movement_id;
      update public.e10_stock_receipt_lines set inventory_movement_id=movement_id
        where organization_id=p_org and id=line_id;
    else
      event_id:=gen_random_uuid();
      perform set_config('e10.receipt_evidence','on',true);
      insert into public.e10_commercial_events(id,organization_id,event_type,event_schema_version,subject_type,subject_id,
        occurred_at,occurred_at_precision,idempotency_key,source_kind,source_connection_id,source_reference,source_event_id,correlation_id,
        evidence_quality,payload,created_by,request_fingerprint)
      values(event_id,p_org,'receipt',1,'inventory_item',item_id,coalesce(p_received_at,now()),'exact',
        p_org::text||':receipt-batch-event:'||p_idempotency_key||':'||line_no,'native','receipt-ledger',
        'stock_receipt_line:'||line_id::text,line_id::text,receipt_id::text,'native_system',
        jsonb_build_object('receipt_id',receipt_id::text,'receipt_line_id',line_id,'lot_id',lot_id,
          'movement_id',null,'purchase_order_line_id',po_line_id,'invoice_line_id',invoice_line_id,
          'command',p_idempotency_key,'physical_received',physical,'accepted_quantity',accepted),actor,
        md5(receipt_id::text||'|'||line_id::text||'|'||p_idempotency_key));
    end if;
    line_result:=line_result||jsonb_build_array(jsonb_build_object('line_no',line_no,'receipt_line_id',line_id,
      'lot_id',lot_id,'movement_id',movement_id,'purchase_order_line_id',po_line_id,'invoice_line_id',invoice_line_id));
  end loop;

  result:=jsonb_build_object('ok',true,'replay',false,'receipt_id',receipt_id,'status','posted','lines',line_result);
  insert into public.e10_receipt_commands(organization_id,idempotency_key,request_fingerprint,stock_receipt_id,result,created_by)
  values(p_org,p_idempotency_key,fp,receipt_id,result,actor);
  return result;
exception when invalid_text_representation or numeric_value_out_of_range or division_by_zero then
  raise exception using errcode='22023',message='receipt_batch_payload_invalid';
end $$;

revoke all on function public.e10_org_receive_batch(uuid,uuid,uuid,timestamptz,jsonb,text)
  from public,anon;
grant execute on function public.e10_org_receive_batch(uuid,uuid,uuid,timestamptz,jsonb,text)
  to authenticated,service_role;

comment on function public.e10_org_receive_batch(uuid,uuid,uuid,timestamptz,jsonb,text) is
  'Bounded source-neutral physical receipt writer. Does not approve invoices, recognize charges, allocate landed cost, pay, settle, or create credits.';

create or replace function e10.normalize_commercial_event_envelope() returns trigger
language plpgsql security definer set search_path=public as $$
begin
  if new.source_kind='native' then
    if new.inventory_movement_id is null and not(
      current_setting('e10.receipt_evidence',true)='on' and new.event_type='receipt'
      and new.source_connection_id='receipt-ledger' and nullif(btrim(new.source_event_id),'') is not null
      and new.subject_type='inventory_item') then
      raise exception using errcode='42501',message='native_evidence_requires_inventory_movement';
    end if;
    new.evidence_quality:='native_system';
    new.source_connection_id:=coalesce(nullif(btrim(new.source_connection_id),''),
      case when new.inventory_movement_id is not null then 'inventory-ledger' else 'receipt-ledger' end);
    new.source_event_id:=coalesce(nullif(btrim(new.source_event_id),''),new.inventory_movement_id::text);
    new.correlation_id:=coalesce(nullif(btrim(new.correlation_id),''),nullif(btrim(new.source_reference),''),
      new.inventory_movement_id::text);
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

-- Enrich native receipt evidence with the exact physical source correlations.
-- The unique movement index keeps this at one event for each accepted line.
create or replace function e10.capture_native_inventory_event() returns trigger
language plpgsql security definer set search_path=public as $$
declare v_event_type text; v_corrects uuid; v_fp text; v_payload jsonb; receipt_source record;
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
  v_payload:=jsonb_build_object('movement_id',new.id,'movement_type',new.movement_type,
    'on_hand_delta',new.on_hand_delta,'reserved_delta',new.reserved_delta,
    'source_action',new.source_action,'reason_code',new.reason_code);
  if v_event_type='receipt' and new.source_entity_type='stock_receipt_line' then
    select rl.id receipt_line_id,rl.stock_receipt_id,rl.inventory_lot_id,
      po.purchase_order_line_id,inv.invoice_line_id
    into receipt_source
    from public.e10_stock_receipt_lines rl
    left join public.e10_receipt_po_allocations po
      on po.organization_id=rl.organization_id and po.receipt_line_id=rl.id
    left join public.e10_receipt_invoice_allocations inv
      on inv.organization_id=rl.organization_id and inv.receipt_line_id=rl.id
    where rl.organization_id=new.organization_id and rl.id=new.source_entity_id::uuid;
    if found then
      v_payload:=v_payload||jsonb_build_object('receipt_id',receipt_source.stock_receipt_id::text,
        'receipt_line_id',receipt_source.receipt_line_id,'lot_id',receipt_source.inventory_lot_id,
        'purchase_order_line_id',receipt_source.purchase_order_line_id,
        'invoice_line_id',receipt_source.invoice_line_id,'command',new.meta->>'command');
    end if;
  end if;
  v_fp:=md5(new.id::text||'|'||v_event_type||'|'||new.item_id);
  insert into public.e10_commercial_events(organization_id,event_type,subject_type,subject_id,occurred_at,
    idempotency_key,source_kind,source_reference,payload,corrects_event_id,created_by,
    request_fingerprint,inventory_movement_id)
  values(new.organization_id,v_event_type,'inventory_item',new.item_id,new.created_at,
    new.organization_id::text||':native-movement:'||new.id::text,'native',
    new.source_entity_type||':'||coalesce(new.source_entity_id,''),v_payload,v_corrects,
    new.actor_uid,v_fp,new.id)
  on conflict(organization_id,inventory_movement_id) where inventory_movement_id is not null do nothing;
  return new;
end $$;
revoke all on function e10.capture_native_inventory_event() from public,anon,authenticated;
grant execute on function e10.capture_native_inventory_event() to service_role;

-- Route existing purchasing reads through the single effective-quantity contract.
create or replace function e10.supplier_open_commitment_summary(p_org uuid,p_supplier uuid,p_currency text)
returns jsonb language sql stable security definer set search_path=public as $$
 with receipt_allocations as(
  select a.purchase_order_line_id,a.allocated_quantity,q.effective_accepted accepted_quantity,
   count(*)over(partition by a.organization_id,a.receipt_line_id)n,
   sum(a.allocated_quantity)over(partition by a.organization_id,a.receipt_line_id)allocated_total
  from public.e10_receipt_po_allocations a
  join public.e10_stock_receipt_lines rl on(rl.organization_id,rl.id)=(a.organization_id,a.receipt_line_id)
  cross join lateral e10.receipt_line_effective_quantities(rl.organization_id,rl.id) q
  where a.organization_id=p_org and q.effective_accepted>0
 ),received as(
  select purchase_order_line_id,
   sum(case when allocated_total<=accepted_quantity then allocated_quantity when n=1 then accepted_quantity end)accepted_quantity,
   bool_or(allocated_total>accepted_quantity and n>1)ambiguous
  from receipt_allocations group by purchase_order_line_id
 ),open_lines as(
  select l.id,l.estimated_unit_cost,
   case when coalesce(r.ambiguous,false)then null else greatest(l.ordered_quantity-coalesce(r.accepted_quantity,0),0)end outstanding,
   coalesce(r.ambiguous,false)ambiguous
  from public.e10_purchase_order_lines l join public.e10_purchase_orders po
    on(po.organization_id,po.id)=(l.organization_id,l.purchase_order_id)
  left join received r on r.purchase_order_line_id=l.id
  where po.organization_id=p_org and po.supplier_id=p_supplier and po.currency=p_currency
   and po.status in('submitted','approved')and l.state='active'
 ),stats as(select
  coalesce(sum(outstanding*estimated_unit_cost)filter(where not ambiguous and outstanding>0 and estimated_unit_cost is not null),0)known,
  count(*)filter(where not ambiguous and outstanding>0 and estimated_unit_cost is null)unknown_lines,
  coalesce(sum(outstanding)filter(where not ambiguous and outstanding>0 and estimated_unit_cost is null),0)unknown_quantity,
  count(*)filter(where ambiguous)ambiguous_lines from open_lines)
 select jsonb_build_object('known_subtotal',known,'unknown_outstanding_line_count',unknown_lines,
  'unknown_outstanding_quantity',unknown_quantity,'ambiguous_allocation_line_count',ambiguous_lines,
  'status',case when unknown_lines>0 or ambiguous_lines>0 then'incomplete'else'complete'end,
  'estimate',case when unknown_lines=0 and ambiguous_lines=0 then known end)from stats
$$;

create or replace function e10.purchase_order_open_commitment_summary(p_org uuid,p_purchase_order uuid)
returns jsonb language sql stable security definer set search_path=public as $$
 with receipt_allocations as(
  select a.purchase_order_line_id,a.allocated_quantity,q.effective_accepted accepted_quantity,
   count(*)over(partition by a.organization_id,a.receipt_line_id)n,
   sum(a.allocated_quantity)over(partition by a.organization_id,a.receipt_line_id)allocated_total
  from public.e10_receipt_po_allocations a
  join public.e10_stock_receipt_lines rl on(rl.organization_id,rl.id)=(a.organization_id,a.receipt_line_id)
  cross join lateral e10.receipt_line_effective_quantities(rl.organization_id,rl.id) q
  where a.organization_id=p_org and q.effective_accepted>0
 ),received as(
  select purchase_order_line_id,
   sum(case when allocated_total<=accepted_quantity then allocated_quantity when n=1 then accepted_quantity end)accepted_quantity,
   bool_or(allocated_total>accepted_quantity and n>1)ambiguous
  from receipt_allocations group by purchase_order_line_id
 ),lines as(
  select l.ordered_quantity,l.estimated_unit_cost,
   case when po.status not in('submitted','approved')then 0
    when coalesce(r.ambiguous,false)then null else greatest(l.ordered_quantity-coalesce(r.accepted_quantity,0),0)end outstanding,
   po.status in('submitted','approved')and coalesce(r.ambiguous,false)ambiguous
  from public.e10_purchase_order_lines l join public.e10_purchase_orders po
    on(po.organization_id,po.id)=(l.organization_id,l.purchase_order_id)
  left join received r on r.purchase_order_line_id=l.id
  where l.organization_id=p_org and l.purchase_order_id=p_purchase_order and l.state='active'
 ),stats as(select
  coalesce(sum(ordered_quantity*estimated_unit_cost)filter(where estimated_unit_cost is not null),0)ordered_known,
  count(*)filter(where estimated_unit_cost is null)ordered_unknown_lines,
  coalesce(sum(outstanding*estimated_unit_cost)filter(where not ambiguous and outstanding>0 and estimated_unit_cost is not null),0)known,
  count(*)filter(where not ambiguous and outstanding>0 and estimated_unit_cost is null)unknown_lines,
  coalesce(sum(outstanding)filter(where not ambiguous and outstanding>0 and estimated_unit_cost is null),0)unknown_quantity,
  count(*)filter(where ambiguous)ambiguous_lines from lines)
 select jsonb_build_object(
  'ordered_known_subtotal',ordered_known,'ordered_unknown_line_count',ordered_unknown_lines,
  'ordered_status',case when ordered_unknown_lines>0 then'incomplete'else'complete'end,
  'ordered_estimate',case when ordered_unknown_lines=0 then ordered_known end,
  'known_subtotal',known,'unknown_outstanding_line_count',unknown_lines,
  'unknown_outstanding_quantity',unknown_quantity,'ambiguous_allocation_line_count',ambiguous_lines,
  'status',case when unknown_lines>0 or ambiguous_lines>0 then'incomplete'else'complete'end,
  'estimate',case when unknown_lines=0 and ambiguous_lines=0 then known end)from stats
$$;

create or replace function public.e10_org_supplier_actual_cost_history(
 p_org uuid,p_supplier_id uuid,p_configuration_version_id uuid,p_currency text,p_as_of timestamptz,
 p_limit integer default 50,p_cursor text default null
)returns jsonb language plpgsql stable security definer set search_path=public as $$
declare c jsonb;cursor_at timestamptz;cursor_id uuid;items jsonb;more boolean;last_row record;
begin
 if not exists(select 1 from public.e10_organizations where id=p_org and status='active')or not e10.is_org_member(p_org)or not e10.has_org_cap(p_org,'financial.actual_cost.read')then raise exception using errcode='42501',message='supplier_actual_cost_denied';end if;
 if p_supplier_id is null or p_configuration_version_id is null or p_currency is null or p_currency!~'^[A-Z]{3}$'
  or p_as_of is null or not isfinite(p_as_of)or p_limit is null or p_limit not between 1 and 100
  or not exists(select 1 from public.e10_suppliers where organization_id=p_org and id=p_supplier_id)
  or not exists(select 1 from public.e10_product_configuration_versions where organization_id=p_org and id=p_configuration_version_id)
 then raise exception using errcode='22023',message='supplier_actual_cost_bounds_invalid';end if;
 if p_cursor is not null then begin c:=e10.inventory_cursor_decode(p_org,p_cursor);cursor_at:=(c->>'received_at')::timestamptz;cursor_id:=(c->>'receipt_line_id')::uuid;
  if c->>'scope'is distinct from'supplier-actual-cost-v1'or(c->>'supplier_id')::uuid is distinct from p_supplier_id
   or(c->>'configuration_version_id')::uuid is distinct from p_configuration_version_id or c->>'currency'is distinct from p_currency
   or(c->>'as_of')::timestamptz is distinct from p_as_of or cursor_at is null or not isfinite(cursor_at)or cursor_id is null
  then raise exception using errcode='22023',message='supplier_actual_cost_cursor_mismatch';end if;
  exception when others then raise exception using errcode='22023',message='supplier_actual_cost_cursor_invalid';end;end if;
 with eligible as(select rl.id receipt_line_id,sr.id receipt_id,rl.inventory_lot_id,rl.configuration_version_id,sr.supplier_id,
  q.effective_accepted accepted_quantity,rl.actual_unit_cost,rl.currency,sr.received_at,rl.created_at
  from public.e10_stock_receipt_lines rl join public.e10_stock_receipts sr on(sr.organization_id,sr.id)=(rl.organization_id,rl.stock_receipt_id)
  cross join lateral e10.receipt_line_effective_quantities(rl.organization_id,rl.id)q
  where rl.organization_id=p_org and sr.supplier_id=p_supplier_id and rl.configuration_version_id=p_configuration_version_id
   and rl.currency=p_currency and rl.actual_unit_cost is not null and q.effective_accepted>0
   and sr.received_at<=p_as_of and(p_cursor is null or(sr.received_at,rl.id)<(cursor_at,cursor_id))),
 page as(select * from eligible order by received_at desc,receipt_line_id desc limit p_limit+1),shown as(select * from page order by received_at desc,receipt_line_id desc limit p_limit)
 select coalesce(jsonb_agg(jsonb_build_object('source_kind','accepted_stock_receipt','supplier_id',supplier_id,'configuration_version_id',configuration_version_id,
  'receipt_id',receipt_id,'receipt_line_id',receipt_line_id,'inventory_lot_id',inventory_lot_id,'accepted_quantity',accepted_quantity,
  'actual_unit_cost',actual_unit_cost,'currency',currency,'received_at',received_at)order by received_at desc,receipt_line_id desc),'[]'),(select count(*)from page)>p_limit
 into items,more from shown;
 with eligible as(select sr.received_at,rl.id from public.e10_stock_receipt_lines rl join public.e10_stock_receipts sr on(sr.organization_id,sr.id)=(rl.organization_id,rl.stock_receipt_id)
  cross join lateral e10.receipt_line_effective_quantities(rl.organization_id,rl.id)q
  where rl.organization_id=p_org and sr.supplier_id=p_supplier_id and rl.configuration_version_id=p_configuration_version_id and rl.currency=p_currency and rl.actual_unit_cost is not null and q.effective_accepted>0 and sr.received_at<=p_as_of
   and(p_cursor is null or(sr.received_at,rl.id)<(cursor_at,cursor_id))order by sr.received_at desc,rl.id desc limit p_limit)
 select received_at,id into last_row from eligible order by received_at,id limit 1;
 return jsonb_build_object('supplier_id',p_supplier_id,'configuration_version_id',p_configuration_version_id,'currency',p_currency,
  'as_of',p_as_of,'conversion','none_exact_currency_only','items',items,'has_more',more,'next_cursor',case when more and last_row.id is not null then e10.inventory_cursor_encode(p_org,jsonb_build_object('scope','supplier-actual-cost-v1','supplier_id',p_supplier_id,'configuration_version_id',p_configuration_version_id,'currency',p_currency,'as_of',p_as_of,'received_at',last_row.received_at,'receipt_line_id',last_row.id))end);
end $$;

revoke all on function e10.supplier_open_commitment_summary(uuid,uuid,text),
  e10.purchase_order_open_commitment_summary(uuid,uuid) from public,anon,authenticated;
grant execute on function e10.supplier_open_commitment_summary(uuid,uuid,text),
  e10.purchase_order_open_commitment_summary(uuid,uuid) to service_role;
