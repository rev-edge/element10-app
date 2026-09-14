-- Preserve historical receipt-origin repair after the R6 replay wrapper.

alter function public.e10_org_receive_po_line(
  uuid,uuid,text,numeric,numeric,numeric,text,timestamptz,jsonb,text
) rename to _e10_org_receive_po_line_r6_replay_compat;

revoke all on function public._e10_org_receive_po_line_r6_replay_compat(
  uuid,uuid,text,numeric,numeric,numeric,text,timestamptz,jsonb,text
) from public,anon,authenticated;
grant execute on function public._e10_org_receive_po_line_r6_replay_compat(
  uuid,uuid,text,numeric,numeric,numeric,text,timestamptz,jsonb,text
) to service_role;

create function public.e10_org_receive_po_line(
  p_org uuid,p_purchase_order_line_id uuid,p_inventory_item_id text,
  p_accepted_quantity numeric,p_damaged_quantity numeric,p_quarantined_quantity numeric,
  p_lot_code text,p_received_at timestamptz,p_expected_allocations jsonb,p_idempotency_key text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare result jsonb;receipt uuid;destination uuid;
begin
  result:=public._e10_org_receive_po_line_r6_replay_compat(p_org,p_purchase_order_line_id,
    p_inventory_item_id,p_accepted_quantity,p_damaged_quantity,p_quarantined_quantity,
    p_lot_code,p_received_at,p_expected_allocations,p_idempotency_key);
  if coalesce((result->>'replay')::boolean,false) then
    receipt:=(result->>'receipt_id')::uuid;
    perform e10.ensure_receipt_origin_evidence(p_org,receipt,true);
    select destination_location_id into destination from public.e10_stock_receipts
      where organization_id=p_org and id=receipt;
    if auth.uid() is null
      or not exists(select 1 from public.e10_organizations where id=p_org and status='active')
      or not e10.is_org_member(p_org)
      or not e10.has_org_cap(p_org,'act.create_receiving')
      or destination is null or not e10.can_receive_at(p_org,destination) then
      raise exception using errcode='42501',message='create_receiving_denied';
    end if;
  end if;
  return result;
end $$;

revoke all on function public.e10_org_receive_po_line(
  uuid,uuid,text,numeric,numeric,numeric,text,timestamptz,jsonb,text
) from public,anon;
grant execute on function public.e10_org_receive_po_line(
  uuid,uuid,text,numeric,numeric,numeric,text,timestamptz,jsonb,text
) to authenticated,service_role;
