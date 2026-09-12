-- Preserve the legacy NULL-as-empty allocation contract and make malformed
-- allocation rejection null-safe before any casts or delegate work.
create or replace function public.e10_org_receive_po_line(p_org uuid,p_purchase_order_line_id uuid,p_inventory_item_id text,p_accepted_quantity numeric,p_damaged_quantity numeric,p_quarantined_quantity numeric,p_lot_code text,p_received_at timestamptz,p_expected_allocations jsonb,p_idempotency_key text)returns jsonb
language plpgsql security definer set search_path=public as $$
declare prior record;stored_allocations jsonb;requested_allocations jsonb;normalized_allocations jsonb:=coalesce(p_expected_allocations,'[]'::jsonb);
begin
 if auth.uid()is null or not e10.has_org_cap(p_org,'act.create_receiving')then raise exception using errcode='42501',message='create_receiving_denied';end if;
 if jsonb_typeof(normalized_allocations)<>'array'or jsonb_array_length(normalized_allocations)>200 then raise exception using errcode='22023',message='expected_allocations_must_be_array';end if;
 begin
  if exists(select 1 from jsonb_array_elements(normalized_allocations)x where jsonb_typeof(x)is distinct from'object'or jsonb_typeof(x->'id')is distinct from'string'or coalesce(x->>'id','')!~'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89aAbB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$'or jsonb_typeof(x->'quantity')is distinct from'number'or(x->>'quantity')::numeric<=0)
    or(select count(*)from jsonb_array_elements(normalized_allocations))<>(select count(distinct(x->>'id')::uuid)from jsonb_array_elements(normalized_allocations)x)then raise exception using errcode='22023',message='expected_allocations_invalid';end if;
 exception when invalid_text_representation or numeric_value_out_of_range then raise exception using errcode='22023',message='expected_allocations_invalid';end;
 perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|receipt-any-command|'||btrim(p_idempotency_key),0));
 if not e10.has_org_cap(p_org,'act.create_receiving')then raise exception using errcode='42501',message='create_receiving_denied';end if;
 if exists(select 1 from public.e10_receipt_commands c where c.organization_id=p_org and c.idempotency_key=btrim(p_idempotency_key))then raise exception using errcode='22023',message='idempotency_key_mismatch';end if;
 select sr.id receipt_id,sr.status,sr.received_at,sr.destination_location_id,rl.id receipt_line_id,rl.accepted_quantity,rl.damaged_quantity,rl.quarantined_quantity,rl.inventory_lot_id,rl.inventory_movement_id,l.inventory_item_id,l.lot_code,a.purchase_order_line_id
 into prior from public.e10_stock_receipts sr join public.e10_stock_receipt_lines rl on(rl.organization_id,rl.stock_receipt_id)=(sr.organization_id,sr.id)join public.e10_inventory_lots l on(l.organization_id,l.id)=(rl.organization_id,rl.inventory_lot_id)join public.e10_receipt_po_allocations a on(a.organization_id,a.receipt_line_id)=(rl.organization_id,rl.id)
 where sr.organization_id=p_org and sr.idempotency_key=btrim(p_idempotency_key)order by rl.line_no limit 1;
 if found then
  if not e10.can_receive_at(p_org,prior.destination_location_id)then raise exception using errcode='42501',message='receive_location_denied';end if;
  select coalesce(jsonb_agg(jsonb_build_object('id',e.expected_allocation_id,'quantity',e.quantity)order by e.expected_allocation_id),'[]')into stored_allocations from public.e10_expected_allocation_events e where e.organization_id=p_org and e.receipt_line_id=prior.receipt_line_id and e.action='fulfill';
  select coalesce(jsonb_agg(jsonb_build_object('id',(x->>'id')::uuid,'quantity',(x->>'quantity')::numeric)order by(x->>'id')::uuid),'[]')into requested_allocations from jsonb_array_elements(normalized_allocations)x;
  if row(prior.purchase_order_line_id,prior.inventory_item_id,prior.accepted_quantity,prior.damaged_quantity,prior.quarantined_quantity,prior.lot_code,stored_allocations)is distinct from row(p_purchase_order_line_id,p_inventory_item_id,coalesce(p_accepted_quantity,0),coalesce(p_damaged_quantity,0),coalesce(p_quarantined_quantity,0),p_lot_code,requested_allocations)
    or p_received_at is not null and p_received_at is distinct from prior.received_at then raise exception using errcode='22023',message='idempotency_key_mismatch';end if;
  return jsonb_build_object('ok',true,'replay',true,'receipt_id',prior.receipt_id,'receipt_line_id',prior.receipt_line_id,'lot_id',prior.inventory_lot_id,'movement_id',prior.inventory_movement_id,'status',prior.status);
 end if;
 return public._e10_org_receive_po_line_r6(p_org,p_purchase_order_line_id,p_inventory_item_id,trim_scale(p_accepted_quantity),trim_scale(p_damaged_quantity),trim_scale(p_quarantined_quantity),p_lot_code,p_received_at,normalized_allocations,p_idempotency_key);
end $$;

