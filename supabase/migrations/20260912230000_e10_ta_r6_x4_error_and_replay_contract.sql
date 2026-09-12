-- TA-R6 14e: stable X4 reservation/receipt errors and numeric replay identity.
alter function public.e10_org_lot_reserve(uuid,uuid,numeric,uuid,text) rename to _e10_org_lot_reserve_r6;
alter function public.e10_org_lot_reserve_for_demand(uuid,uuid,numeric,text,text,text,text) rename to _e10_org_lot_reserve_for_demand_r6;
revoke all on function public._e10_org_lot_reserve_r6(uuid,uuid,numeric,uuid,text),public._e10_org_lot_reserve_for_demand_r6(uuid,uuid,numeric,text,text,text,text) from public,anon,authenticated;
grant execute on function public._e10_org_lot_reserve_r6(uuid,uuid,numeric,uuid,text),public._e10_org_lot_reserve_for_demand_r6(uuid,uuid,numeric,text,text,text,text) to service_role;
create function public.e10_org_lot_reserve(p_org uuid,p_lot_id uuid,p_quantity numeric,p_break_session_id uuid,p_idempotency_key text)returns jsonb
language plpgsql security definer set search_path=public as $$begin
  return public._e10_org_lot_reserve_r6(p_org,p_lot_id,trim_scale(p_quantity),p_break_session_id,p_idempotency_key);
exception when unique_violation then raise exception using errcode='55000',message='lot_reservation_already_active';end$$;
create function public.e10_org_lot_reserve_for_demand(p_org uuid,p_lot_id uuid,p_quantity numeric,p_demand_type text,p_demand_reference text,p_demand_label text,p_idempotency_key text)returns jsonb
language plpgsql security definer set search_path=public as $$begin
  return public._e10_org_lot_reserve_for_demand_r6(p_org,p_lot_id,trim_scale(p_quantity),p_demand_type,p_demand_reference,p_demand_label,p_idempotency_key);
exception when unique_violation then raise exception using errcode='55000',message='lot_reservation_already_active';end$$;

alter function public.e10_org_receive_batch(uuid,uuid,uuid,timestamptz,jsonb,text) rename to _e10_org_receive_batch_r6;
alter function public.e10_org_receive_po_line(uuid,uuid,text,numeric,numeric,numeric,text,timestamptz,jsonb,text) rename to _e10_org_receive_po_line_r6;
revoke all on function public._e10_org_receive_batch_r6(uuid,uuid,uuid,timestamptz,jsonb,text),public._e10_org_receive_po_line_r6(uuid,uuid,text,numeric,numeric,numeric,text,timestamptz,jsonb,text) from public,anon,authenticated;
grant execute on function public._e10_org_receive_batch_r6(uuid,uuid,uuid,timestamptz,jsonb,text),public._e10_org_receive_po_line_r6(uuid,uuid,text,numeric,numeric,numeric,text,timestamptz,jsonb,text) to service_role;
create function public.e10_org_receive_batch(p_org uuid,p_supplier_id uuid,p_destination_location_id uuid,p_received_at timestamptz,p_lines jsonb,p_idempotency_key text)returns jsonb
language plpgsql security definer set search_path=public as $$begin
  if p_lines is not null and jsonb_typeof(p_lines)='array'and exists(select 1 from jsonb_array_elements(p_lines)x where nullif(btrim(x->>'lot_code'),'')is not null group by lower(btrim(x->>'lot_code'))having count(*)>1)then raise exception using errcode='22023',message='duplicate_batch_lot_code';end if;
  perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|receipt-any-command|'||btrim(p_idempotency_key),0));
  if exists(select 1 from public.e10_stock_receipts r where r.organization_id=p_org and r.idempotency_key=btrim(p_idempotency_key))and not exists(select 1 from public.e10_receipt_commands c where c.organization_id=p_org and c.idempotency_key=btrim(p_idempotency_key))then raise exception using errcode='22023',message='idempotency_key_mismatch';end if;
  return public._e10_org_receive_batch_r6(p_org,p_supplier_id,p_destination_location_id,p_received_at,p_lines,p_idempotency_key);
end$$;
create function public.e10_org_receive_po_line(p_org uuid,p_purchase_order_line_id uuid,p_inventory_item_id text,p_accepted_quantity numeric,p_damaged_quantity numeric,p_quarantined_quantity numeric,p_lot_code text,p_received_at timestamptz,p_expected_allocations jsonb,p_idempotency_key text)returns jsonb
language plpgsql security definer set search_path=public as $$begin
  perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|receipt-any-command|'||btrim(p_idempotency_key),0));
  if exists(select 1 from public.e10_receipt_commands c where c.organization_id=p_org and c.idempotency_key=btrim(p_idempotency_key))then raise exception using errcode='22023',message='idempotency_key_mismatch';end if;
  return public._e10_org_receive_po_line_r6(p_org,p_purchase_order_line_id,p_inventory_item_id,trim_scale(p_accepted_quantity),trim_scale(p_damaged_quantity),trim_scale(p_quarantined_quantity),p_lot_code,p_received_at,p_expected_allocations,p_idempotency_key);
end$$;

revoke all on function public.e10_org_lot_reserve(uuid,uuid,numeric,uuid,text),public.e10_org_lot_reserve_for_demand(uuid,uuid,numeric,text,text,text,text),public.e10_org_receive_batch(uuid,uuid,uuid,timestamptz,jsonb,text),public.e10_org_receive_po_line(uuid,uuid,text,numeric,numeric,numeric,text,timestamptz,jsonb,text) from public,anon;
grant execute on function public.e10_org_lot_reserve(uuid,uuid,numeric,uuid,text),public.e10_org_lot_reserve_for_demand(uuid,uuid,numeric,text,text,text,text),public.e10_org_receive_batch(uuid,uuid,uuid,timestamptz,jsonb,text),public.e10_org_receive_po_line(uuid,uuid,text,numeric,numeric,numeric,text,timestamptz,jsonb,text) to authenticated,service_role;
