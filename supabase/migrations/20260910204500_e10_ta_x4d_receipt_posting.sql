-- TA-X4d conservative PO-line receipt posting and reversal.
-- Over-receipt is rejected. No invoice approval, payment, or landed-cost allocation is implied.

alter table public.e10_stock_receipts add column idempotency_key text;
alter table public.e10_stock_receipts add column request_fingerprint text;
alter table public.e10_stock_receipts add constraint e10_stock_receipts_idempotency_chk
  check(idempotency_key is null or btrim(idempotency_key)<>'');
create unique index e10_stock_receipts_org_idempotency_uq
  on public.e10_stock_receipts(organization_id,idempotency_key) where idempotency_key is not null;

alter table public.e10_inventory_items add column configuration_version_id uuid;
alter table public.e10_inventory_items add constraint e10_inventory_items_org_configuration_fkey
  foreign key(organization_id,configuration_version_id)
  references public.e10_product_configuration_versions(organization_id,id);

alter table public.e10_stock_receipt_lines add column inventory_lot_id uuid;
alter table public.e10_stock_receipt_lines add column inventory_movement_id uuid;
alter table public.e10_stock_receipt_lines add constraint e10_receipt_lines_org_movement_fkey
  foreign key(organization_id,inventory_movement_id) references public.e10_inventory_movements(organization_id,id);
alter table public.e10_stock_receipt_lines add constraint e10_receipt_lines_org_lot_fkey
  foreign key(organization_id,inventory_lot_id) references public.e10_inventory_lots(organization_id,id);

create table public.e10_stock_receipt_reversals (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.e10_organizations(id),
  stock_receipt_id uuid not null, stock_receipt_line_id uuid not null, inventory_lot_id uuid not null,
  quantity numeric not null check(quantity>0), reason text not null check(btrim(reason)<>''),
  idempotency_key text not null check(btrim(idempotency_key)<>''), request_fingerprint text not null,
  inventory_movement_id uuid, reversed_by uuid references auth.users(id), reversed_at timestamptz not null default now(),
  unique(organization_id,id), unique(organization_id,idempotency_key),
  foreign key(organization_id,stock_receipt_id) references public.e10_stock_receipts(organization_id,id),
  foreign key(organization_id,stock_receipt_line_id) references public.e10_stock_receipt_lines(organization_id,id),
  foreign key(organization_id,inventory_lot_id) references public.e10_inventory_lots(organization_id,id),
  foreign key(organization_id,inventory_movement_id) references public.e10_inventory_movements(organization_id,id)
);
alter table public.e10_stock_receipt_reversals enable row level security;
revoke all on table public.e10_stock_receipt_reversals from public,anon,authenticated;
grant all on table public.e10_stock_receipt_reversals to service_role;
create trigger e10_stock_receipt_reversals_append_only_trg before update or delete on public.e10_stock_receipt_reversals
  for each row execute function e10.reject_append_only_change();

alter table public.e10_expected_inventory_allocations add column fulfilled_quantity numeric not null default 0;
alter table public.e10_expected_inventory_allocations add constraint e10_expected_allocations_fulfilled_chk
  check(fulfilled_quantity>=0 and fulfilled_quantity<=expected_quantity);

create table public.e10_expected_allocation_events (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.e10_organizations(id),
  expected_allocation_id uuid not null, receipt_line_id uuid not null, receipt_reversal_id uuid,
  action text not null check(action in ('fulfill','reverse')), quantity numeric not null check(quantity>0),
  created_at timestamptz not null default now(), unique(organization_id,id),
  foreign key(organization_id,expected_allocation_id) references public.e10_expected_inventory_allocations(organization_id,id),
  foreign key(organization_id,receipt_line_id) references public.e10_stock_receipt_lines(organization_id,id),
  foreign key(organization_id,receipt_reversal_id) references public.e10_stock_receipt_reversals(organization_id,id),
  check((action='fulfill' and receipt_reversal_id is null) or (action='reverse' and receipt_reversal_id is not null))
);
create unique index e10_expected_allocation_events_fulfill_uq
  on public.e10_expected_allocation_events(organization_id,expected_allocation_id,receipt_line_id) where action='fulfill';
create unique index e10_expected_allocation_events_reverse_uq
  on public.e10_expected_allocation_events(organization_id,expected_allocation_id,receipt_reversal_id) where action='reverse';
alter table public.e10_expected_allocation_events enable row level security;
revoke all on table public.e10_expected_allocation_events from public,anon,authenticated;
grant all on table public.e10_expected_allocation_events to service_role;
create trigger e10_expected_allocation_events_append_only_trg before update or delete on public.e10_expected_allocation_events
  for each row execute function e10.reject_append_only_change();

create or replace function public.e10_org_receive_po_line(
  p_org uuid, p_purchase_order_line_id uuid, p_inventory_item_id text,
  p_accepted_quantity numeric, p_damaged_quantity numeric, p_quarantined_quantity numeric,
  p_lot_code text, p_received_at timestamptz, p_expected_allocations jsonb, p_idempotency_key text
) returns jsonb
language plpgsql security definer set search_path=public as $$
declare
  v_pol record; v_total numeric; v_prior numeric; v_fp text; v_existing record;
  v_receipt uuid; v_line uuid; v_lot uuid; v_mid uuid; v_status text; v_movement_key text;
  v_to_allocate numeric; v_alloc record;
begin
  if not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.create_receiving') then
    raise exception using errcode='42501',message='create_receiving_denied';
  end if;
  if p_idempotency_key is null or btrim(p_idempotency_key)='' then raise exception using errcode='22004',message='idempotency_key_required'; end if;
  if coalesce(p_accepted_quantity,0)<0 or coalesce(p_damaged_quantity,0)<0 or coalesce(p_quarantined_quantity,0)<0 then
    raise exception using errcode='22023',message='receipt_quantities_must_be_nonnegative';
  end if;
  v_total:=coalesce(p_accepted_quantity,0)+coalesce(p_damaged_quantity,0)+coalesce(p_quarantined_quantity,0);
  if v_total<=0 then raise exception using errcode='22023',message='received_quantity_must_be_positive'; end if;
  v_fp:=md5(p_purchase_order_line_id::text||'|'||coalesce(p_inventory_item_id,'')||'|'||coalesce(p_accepted_quantity,0)::text||'|'||
    coalesce(p_damaged_quantity,0)::text||'|'||coalesce(p_quarantined_quantity,0)::text||'|'||coalesce(p_lot_code,'')||'|'||
    coalesce(p_received_at::text,'')||'|'||coalesce(p_expected_allocations,'[]'::jsonb)::text);
  perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|receive|'||p_idempotency_key,0));
  select id,request_fingerprint,status into v_existing from public.e10_stock_receipts
    where organization_id=p_org and idempotency_key=p_idempotency_key;
  if found then
    if v_existing.request_fingerprint is distinct from v_fp then raise exception using errcode='22023',message='idempotency_key_mismatch'; end if;
    select id,inventory_lot_id,inventory_movement_id into v_line,v_lot,v_mid from public.e10_stock_receipt_lines
      where organization_id=p_org and stock_receipt_id=v_existing.id order by line_no limit 1;
    return jsonb_build_object('ok',true,'replay',true,'receipt_id',v_existing.id,'receipt_line_id',v_line,'lot_id',v_lot,'movement_id',v_mid,'status',v_existing.status);
  end if;
  select pol.id,pol.ordered_quantity,pol.configuration_version_id,po.id purchase_order_id,po.supplier_id,
         po.destination_location_id,po.status po_status
    into v_pol from public.e10_purchase_order_lines pol join public.e10_purchase_orders po
      on po.organization_id=pol.organization_id and po.id=pol.purchase_order_id
    where pol.organization_id=p_org and pol.id=p_purchase_order_line_id for update of pol,po;
  if not found then raise exception using errcode='42501',message='purchase_order_line_access_denied'; end if;
  if v_pol.po_status not in ('approved','submitted') then raise exception using errcode='55000',message='purchase_order_not_receivable'; end if;
  if not e10.can_receive_at(p_org,v_pol.destination_location_id) then
    raise exception using errcode='42501',message='receive_location_denied';
  end if;
  perform 1 from public.e10_inventory_items i where organization_id=p_org and id=p_inventory_item_id
    and (configuration_version_id=v_pol.configuration_version_id or
      (configuration_version_id is null and qty=0
       and not exists(select 1 from public.e10_inventory_movements m where m.organization_id=p_org and m.item_id=i.id)
       and not exists(select 1 from public.e10_inventory_reservations r where r.organization_id=p_org and r.item_id=i.id))) for update;
  if not found then raise exception using errcode='42501',message='inventory_item_access_denied'; end if;
  update public.e10_inventory_items set configuration_version_id=v_pol.configuration_version_id
    where organization_id=p_org and id=p_inventory_item_id and configuration_version_id is null;
  select coalesce(sum(ra.allocated_quantity),0) into v_prior
    from public.e10_receipt_po_allocations ra join public.e10_stock_receipt_lines rl
      on rl.organization_id=ra.organization_id and rl.id=ra.receipt_line_id
    join public.e10_stock_receipts sr on sr.organization_id=rl.organization_id and sr.id=rl.stock_receipt_id
    where ra.organization_id=p_org and ra.purchase_order_line_id=p_purchase_order_line_id and sr.status<>'reversed';
  if v_prior+v_total>v_pol.ordered_quantity then raise exception using errcode='23514',message='over_receipt_not_authorized'; end if;
  insert into public.e10_stock_receipts(organization_id,supplier_id,destination_location_id,status,received_at,created_by,idempotency_key,request_fingerprint)
    values(p_org,v_pol.supplier_id,v_pol.destination_location_id,'posted',coalesce(p_received_at,now()),auth.uid(),p_idempotency_key,v_fp)
    returning id into v_receipt;
  v_status:=case when coalesce(p_accepted_quantity,0)>0 then 'available' else 'quarantined' end;
  insert into public.e10_inventory_lots(organization_id,configuration_version_id,location_id,supplier_id,stock_receipt_line_id,
    inventory_item_id,lot_code,status,accepted_quantity,quarantined_quantity)
  values(p_org,v_pol.configuration_version_id,v_pol.destination_location_id,v_pol.supplier_id,null,p_inventory_item_id,p_lot_code,
    v_status,coalesce(p_accepted_quantity,0),coalesce(p_quarantined_quantity,0)) returning id into v_lot;
  insert into public.e10_stock_receipt_lines(organization_id,stock_receipt_id,configuration_version_id,line_no,received_quantity,
    accepted_quantity,damaged_quantity,quarantined_quantity,inventory_lot_id)
  values(p_org,v_receipt,v_pol.configuration_version_id,1,v_total,coalesce(p_accepted_quantity,0),coalesce(p_damaged_quantity,0),
    coalesce(p_quarantined_quantity,0),v_lot) returning id into v_line;
  update public.e10_inventory_lots set stock_receipt_line_id=v_line where organization_id=p_org and id=v_lot;
  insert into public.e10_receipt_po_allocations(organization_id,receipt_line_id,purchase_order_line_id,allocated_quantity)
    values(p_org,v_line,p_purchase_order_line_id,v_total);
  if coalesce(p_accepted_quantity,0)>0 then
    update public.e10_inventory_items set qty=qty+p_accepted_quantity,updated_by=auth.uid(),updated_at=now()
      where organization_id=p_org and id=p_inventory_item_id;
    v_movement_key:=p_org::text||':receive:'||p_idempotency_key;
    perform set_config('e10.emit','on',true);
    insert into public.e10_inventory_movements(workspace_id,item_id,movement_type,on_hand_delta,reserved_delta,
      source_entity_type,source_entity_id,source_action,actor_uid,reason_code,note,idempotency_key,meta,organization_id)
    values('shared',p_inventory_item_id,'intake',p_accepted_quantity,0,'stock_receipt_line',v_line::text,'receive',auth.uid(),
      'intake','accepted receipt quantity',v_movement_key,jsonb_build_object('receipt_id',v_receipt,'lot_id',v_lot),p_org)
    returning id into v_mid;
    update public.e10_stock_receipt_lines set inventory_movement_id=v_mid where organization_id=p_org and id=v_line;
  end if;
  if jsonb_typeof(coalesce(p_expected_allocations,'[]'::jsonb))<>'array' then
    raise exception using errcode='22023',message='expected_allocations_must_be_array';
  end if;
  select coalesce(sum((x->>'quantity')::numeric),0) into v_to_allocate
    from jsonb_array_elements(coalesce(p_expected_allocations,'[]'::jsonb)) x;
  if v_to_allocate>coalesce(p_accepted_quantity,0) then raise exception using errcode='23514',message='expected_allocation_exceeds_accepted_quantity'; end if;
  for v_alloc in select (x->>'id')::uuid id,(x->>'quantity')::numeric quantity
    from jsonb_array_elements(coalesce(p_expected_allocations,'[]'::jsonb)) x order by (x->>'id')::uuid loop
    if v_alloc.quantity<=0 then raise exception using errcode='22023',message='expected_allocation_quantity_must_be_positive'; end if;
    perform 1 from public.e10_expected_inventory_allocations ea
      where ea.organization_id=p_org and ea.id=v_alloc.id and ea.purchase_order_line_id=p_purchase_order_line_id
        and ea.destination_location_id=v_pol.destination_location_id and ea.status='open'
        and ea.fulfilled_quantity+v_alloc.quantity<=ea.expected_quantity for update;
    if not found then raise exception using errcode='23514',message='expected_allocation_invalid_or_exceeded'; end if;
    insert into public.e10_expected_allocation_events(organization_id,expected_allocation_id,receipt_line_id,action,quantity)
      values(p_org,v_alloc.id,v_line,'fulfill',v_alloc.quantity);
    update public.e10_expected_inventory_allocations set fulfilled_quantity=fulfilled_quantity+v_alloc.quantity,
      status=case when fulfilled_quantity+v_alloc.quantity=expected_quantity then 'fulfilled' else 'open' end,updated_at=now()
      where organization_id=p_org and id=v_alloc.id;
  end loop;
  return jsonb_build_object('ok',true,'replay',false,'receipt_id',v_receipt,'receipt_line_id',v_line,'lot_id',v_lot,'movement_id',v_mid,'status','posted');
end;
$$;

create or replace function public.e10_org_reverse_receipt(
  p_org uuid, p_receipt_id uuid, p_reason text, p_idempotency_key text
) returns jsonb
language plpgsql security definer set search_path=public as $$
declare v record; v_existing record; v_fp text; v_mid uuid; v_movement_key text; v_reversal uuid;
        v_po_line uuid; v_active_reserved numeric; a record;
begin
  if not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.resolve_recovery') then
    raise exception using errcode='42501',message='resolve_recovery_denied';
  end if;
  if p_reason is null or btrim(p_reason)='' then raise exception using errcode='22004',message='reversal_reason_required'; end if;
  if p_idempotency_key is null or btrim(p_idempotency_key)='' then raise exception using errcode='22004',message='idempotency_key_required'; end if;
  v_fp:=md5(p_receipt_id::text||'|'||p_reason);
  perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|receipt-reverse|'||p_idempotency_key,0));
  select id,request_fingerprint,inventory_movement_id,stock_receipt_id into v_existing
    from public.e10_stock_receipt_reversals where organization_id=p_org and idempotency_key=p_idempotency_key;
  if found then
    if v_existing.request_fingerprint is distinct from v_fp then raise exception using errcode='22023',message='idempotency_key_mismatch'; end if;
    return jsonb_build_object('ok',true,'replay',true,'reversal_id',v_existing.id,'receipt_id',v_existing.stock_receipt_id,'movement_id',v_existing.inventory_movement_id);
  end if;
  select purchase_order_line_id into v_po_line from public.e10_receipt_po_allocations
    where organization_id=p_org and receipt_line_id in
      (select id from public.e10_stock_receipt_lines where organization_id=p_org and stock_receipt_id=p_receipt_id)
    limit 1;
  if not found then raise exception using errcode='42501',message='receipt_access_denied'; end if;
  perform 1 from public.e10_purchase_order_lines where organization_id=p_org and id=v_po_line for update;
  if (select count(*) from public.e10_stock_receipt_lines where organization_id=p_org and stock_receipt_id=p_receipt_id)<>1 then
    raise exception using errcode='55000',message='multi_line_receipt_requires_batch_reversal';
  end if;
  select sr.id receipt_id,sr.status,rl.id line_id,rl.received_quantity,rl.accepted_quantity,rl.inventory_lot_id,l.inventory_item_id,l.status lot_status
    into v from public.e10_stock_receipts sr join public.e10_stock_receipt_lines rl
      on rl.organization_id=sr.organization_id and rl.stock_receipt_id=sr.id
    join public.e10_inventory_lots l on l.organization_id=rl.organization_id and l.id=rl.inventory_lot_id
    where sr.organization_id=p_org and sr.id=p_receipt_id for update of sr,rl,l;
  if not found then raise exception using errcode='42501',message='receipt_access_denied'; end if;
  if v.status<>'posted' then raise exception using errcode='55000',message='receipt_not_reversible'; end if;
  if exists(select 1 from public.e10_lot_reservations where organization_id=p_org and lot_id=v.inventory_lot_id
      and (status='active' or consumed_quantity>0)) then
    raise exception using errcode='55000',message='receipt_lot_has_committed_quantity';
  end if;
  perform 1 from public.e10_inventory_items where organization_id=p_org and id=v.inventory_item_id for update;
  if not found then raise exception using errcode='55000',message='accepted_quantity_no_longer_reversible'; end if;
  select coalesce(sum(qty),0) into v_active_reserved from public.e10_inventory_reservations
    where organization_id=p_org and item_id=v.inventory_item_id and status='active';
  if (select qty from public.e10_inventory_items where organization_id=p_org and id=v.inventory_item_id)-v.accepted_quantity<v_active_reserved then
    raise exception using errcode='55000',message='accepted_quantity_is_reserved';
  end if;
  update public.e10_inventory_items set qty=qty-v.accepted_quantity,updated_by=auth.uid(),updated_at=now()
    where organization_id=p_org and id=v.inventory_item_id;
  update public.e10_inventory_lots set status='reversed',updated_at=now() where organization_id=p_org and id=v.inventory_lot_id;
  update public.e10_stock_receipts set status='reversed',updated_at=now() where organization_id=p_org and id=p_receipt_id;
  if v.accepted_quantity>0 then
    v_movement_key:=p_org::text||':receipt-reverse:'||p_idempotency_key;
    perform set_config('e10.emit','on',true);
    insert into public.e10_inventory_movements(workspace_id,item_id,movement_type,on_hand_delta,reserved_delta,
      source_entity_type,source_entity_id,source_action,actor_uid,reason_code,note,idempotency_key,meta,organization_id)
    values('shared',v.inventory_item_id,'correction',-v.accepted_quantity,0,'stock_receipt',p_receipt_id::text,'reverse',auth.uid(),
      'correction',p_reason,v_movement_key,jsonb_build_object('receipt_id',p_receipt_id,'lot_id',v.inventory_lot_id),p_org)
    returning id into v_mid;
  end if;
  insert into public.e10_stock_receipt_reversals(organization_id,stock_receipt_id,stock_receipt_line_id,inventory_lot_id,
    quantity,reason,idempotency_key,request_fingerprint,inventory_movement_id,reversed_by)
  values(p_org,p_receipt_id,v.line_id,v.inventory_lot_id,v.received_quantity,p_reason,p_idempotency_key,v_fp,v_mid,auth.uid()) returning id into v_reversal;
  for a in select expected_allocation_id,quantity from public.e10_expected_allocation_events
    where organization_id=p_org and receipt_line_id=v.line_id and action='fulfill' order by created_at,id loop
    insert into public.e10_expected_allocation_events(organization_id,expected_allocation_id,receipt_line_id,receipt_reversal_id,action,quantity)
      values(p_org,a.expected_allocation_id,v.line_id,v_reversal,'reverse',a.quantity);
    update public.e10_expected_inventory_allocations set fulfilled_quantity=fulfilled_quantity-a.quantity,
      status=case when status='cancelled' then 'cancelled' else 'open' end,updated_at=now()
      where organization_id=p_org and id=a.expected_allocation_id;
  end loop;
  return jsonb_build_object('ok',true,'replay',false,'reversal_id',v_reversal,'receipt_id',p_receipt_id,'movement_id',v_mid,'status','reversed');
end;
$$;

revoke all on function public.e10_org_receive_po_line(uuid,uuid,text,numeric,numeric,numeric,text,timestamptz,jsonb,text) from public,anon;
revoke all on function public.e10_org_reverse_receipt(uuid,uuid,text,text) from public,anon;
grant execute on function public.e10_org_receive_po_line(uuid,uuid,text,numeric,numeric,numeric,text,timestamptz,jsonb,text) to authenticated,service_role;
grant execute on function public.e10_org_reverse_receipt(uuid,uuid,text,text) to authenticated,service_role;

comment on function public.e10_org_receive_po_line(uuid,uuid,text,numeric,numeric,numeric,text,timestamptz,jsonb,text) is
  'Strict non-over-receipt PO-line writer; posts physical accepted/quarantined evidence only.';
