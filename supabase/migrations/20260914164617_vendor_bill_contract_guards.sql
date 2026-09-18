-- Vendor-bill contract guards, increment 1.
-- Establishes revision-bound maker/checker separation and immutable quantity
-- increments without rewriting any applied migration.

alter table public.e10_product_configuration_versions
  add column quantity_increment numeric;

-- No configuration versions exist in the accepted staging baseline. Refuse to
-- guess if this migration is ever applied over a populated unreviewed baseline.
do $$
begin
  if exists(select 1 from public.e10_product_configuration_versions where quantity_increment is null) then
    raise exception using errcode='55000',message='configuration_quantity_increment_backfill_mapping_required';
  end if;
end $$;

alter table public.e10_product_configuration_versions
  alter column quantity_increment set default 1,
  alter column quantity_increment set not null,
  add constraint e10_configuration_versions_quantity_increment_chk
    check(quantity_increment>0 and quantity_increment::text not in('NaN','Infinity','-Infinity'));

comment on column public.e10_product_configuration_versions.quantity_increment is
  'Immutable minimum quantity grain in this configuration version''s packaged unit. Legacy discrete-package creation maps explicitly to 1; divisible goods must use the explicit writer.';

create function e10.guard_quantity_increment_immutable() returns trigger
language plpgsql security definer set search_path=public as $$
begin
  if old.quantity_increment is distinct from new.quantity_increment then
    raise exception using errcode='55000',message='configuration_quantity_increment_immutable';
  end if;
  return new;
end $$;
revoke all on function e10.guard_quantity_increment_immutable() from public,anon,authenticated;
grant execute on function e10.guard_quantity_increment_immutable() to service_role;
create trigger e10_configuration_quantity_increment_immutable_trg
before update of quantity_increment on public.e10_product_configuration_versions
for each row execute function e10.guard_quantity_increment_immutable();

create function e10.assert_configuration_quantity(
  p_org uuid,p_configuration_version_id uuid,p_quantity numeric,p_field text
) returns void language plpgsql stable security definer set search_path=public as $$
declare inc numeric;
begin
  if p_quantity is null then return;end if;
  select v.quantity_increment into inc
  from public.e10_product_configuration_versions v
  where v.organization_id=p_org and v.id=p_configuration_version_id;
  if not found then
    raise exception using errcode='23503',message='configuration_quantity_version_missing';
  end if;
  if p_quantity::text in('NaN','Infinity','-Infinity') or p_quantity/inc<>trunc(p_quantity/inc) then
    raise exception using errcode='23514',message='configuration_quantity_increment_violation',
      detail=format('%s must be divisible by configuration increment %s',p_field,inc);
  end if;
end $$;
revoke all on function e10.assert_configuration_quantity(uuid,uuid,numeric,text) from public,anon,authenticated;
grant execute on function e10.assert_configuration_quantity(uuid,uuid,numeric,text) to service_role;

create function e10.guard_direct_configuration_quantities() returns trigger
language plpgsql security definer set search_path=public as $$
begin
  if tg_table_name='e10_purchase_order_lines' then
    perform e10.assert_configuration_quantity(new.organization_id,new.configuration_version_id,new.ordered_quantity,'ordered_quantity');
  elsif tg_table_name='e10_supplier_invoice_lines' then
    if new.configuration_version_id is not null then
      perform e10.assert_configuration_quantity(new.organization_id,new.configuration_version_id,new.invoiced_quantity,'invoiced_quantity');
    end if;
  elsif tg_table_name='e10_stock_receipt_lines' then
    perform e10.assert_configuration_quantity(new.organization_id,new.configuration_version_id,new.received_quantity,'received_quantity');
    perform e10.assert_configuration_quantity(new.organization_id,new.configuration_version_id,new.accepted_quantity,'accepted_quantity');
    perform e10.assert_configuration_quantity(new.organization_id,new.configuration_version_id,new.damaged_quantity,'damaged_quantity');
    perform e10.assert_configuration_quantity(new.organization_id,new.configuration_version_id,new.quarantined_quantity,'quarantined_quantity');
  elsif tg_table_name='e10_inventory_lots' then
    perform e10.assert_configuration_quantity(new.organization_id,new.configuration_version_id,new.accepted_quantity,'accepted_quantity');
    perform e10.assert_configuration_quantity(new.organization_id,new.configuration_version_id,new.quarantined_quantity,'quarantined_quantity');
  end if;
  return new;
end $$;
revoke all on function e10.guard_direct_configuration_quantities() from public,anon,authenticated;
grant execute on function e10.guard_direct_configuration_quantities() to service_role;

create trigger e10_po_line_quantity_increment_trg before insert or update of organization_id,configuration_version_id,ordered_quantity
on public.e10_purchase_order_lines for each row execute function e10.guard_direct_configuration_quantities();
create trigger e10_invoice_line_quantity_increment_trg before insert or update of organization_id,configuration_version_id,invoiced_quantity
on public.e10_supplier_invoice_lines for each row execute function e10.guard_direct_configuration_quantities();
create trigger e10_receipt_line_quantity_increment_trg before insert or update of organization_id,configuration_version_id,received_quantity,accepted_quantity,damaged_quantity,quarantined_quantity
on public.e10_stock_receipt_lines for each row execute function e10.guard_direct_configuration_quantities();
create trigger e10_lot_quantity_increment_trg before insert or update of organization_id,configuration_version_id,accepted_quantity,quarantined_quantity
on public.e10_inventory_lots for each row execute function e10.guard_direct_configuration_quantities();

create function e10.guard_indirect_configuration_quantity() returns trigger
language plpgsql security definer set search_path=public as $$
declare config_id uuid;qty numeric;
begin
  if tg_table_name='e10_expected_inventory_allocations' then
    select l.configuration_version_id into config_id from public.e10_purchase_order_lines l
      where (l.organization_id,l.id)=(new.organization_id,new.purchase_order_line_id);
    qty:=new.expected_quantity;
  elsif tg_table_name='e10_lot_reservations' then
    select l.configuration_version_id into config_id from public.e10_inventory_lots l
      where (l.organization_id,l.id)=(new.organization_id,new.lot_id);
    qty:=new.quantity;
  elsif tg_table_name='e10_receipt_disposition_decisions' then
    select l.configuration_version_id into config_id from public.e10_stock_receipt_lines l
      where (l.organization_id,l.id)=(new.organization_id,new.stock_receipt_line_id);
    qty:=new.quantity;
  elsif tg_table_name='e10_invoice_po_allocations' then
    select l.configuration_version_id into config_id from public.e10_supplier_invoice_lines l
      where (l.organization_id,l.id)=(new.organization_id,new.invoice_line_id);
    qty:=new.allocated_quantity;
  elsif tg_table_name in('e10_receipt_po_allocations','e10_receipt_invoice_allocations') then
    select l.configuration_version_id into config_id from public.e10_stock_receipt_lines l
      where (l.organization_id,l.id)=(new.organization_id,new.receipt_line_id);
    qty:=new.allocated_quantity;
  else
    raise exception using errcode='55000',message='quantity_increment_guard_table_unsupported';
  end if;
  perform e10.assert_configuration_quantity(new.organization_id,config_id,qty,tg_table_name||'.quantity');
  return new;
end $$;
revoke all on function e10.guard_indirect_configuration_quantity() from public,anon,authenticated;
grant execute on function e10.guard_indirect_configuration_quantity() to service_role;

create trigger e10_expected_allocation_quantity_increment_trg before insert or update of organization_id,purchase_order_line_id,expected_quantity
on public.e10_expected_inventory_allocations for each row execute function e10.guard_indirect_configuration_quantity();
create trigger e10_lot_reservation_quantity_increment_trg before insert or update of organization_id,lot_id,quantity
on public.e10_lot_reservations for each row execute function e10.guard_indirect_configuration_quantity();
create trigger e10_receipt_disposition_quantity_increment_trg before insert or update of organization_id,stock_receipt_line_id,quantity
on public.e10_receipt_disposition_decisions for each row execute function e10.guard_indirect_configuration_quantity();
create trigger e10_invoice_po_allocation_quantity_increment_trg before insert or update of organization_id,invoice_line_id,allocated_quantity
on public.e10_invoice_po_allocations for each row execute function e10.guard_indirect_configuration_quantity();
create trigger e10_receipt_po_allocation_quantity_increment_trg before insert or update of organization_id,receipt_line_id,allocated_quantity
on public.e10_receipt_po_allocations for each row execute function e10.guard_indirect_configuration_quantity();
create trigger e10_receipt_invoice_allocation_quantity_increment_trg before insert or update of organization_id,receipt_line_id,allocated_quantity
on public.e10_receipt_invoice_allocations for each row execute function e10.guard_indirect_configuration_quantity();

-- Preserve the accepted legacy signature as the explicit discrete-package
-- mapping (increment 1) and add the new writer for divisible goods.
create function public.e10_org_create_configuration_version(
  p_org uuid,p_configuration_id uuid,p_expected_latest_version integer,p_state text,
  p_packaging_kind text,p_base_unit text,p_base_units_per_package numeric,
  p_quantity_increment numeric,p_barcode text,p_attrs jsonb,p_idempotency_key text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare r jsonb;v_id uuid;
begin
  if p_quantity_increment is null or p_quantity_increment<=0
    or p_quantity_increment::text in('NaN','Infinity','-Infinity') then
    raise exception using errcode='22023',message='configuration_quantity_increment_invalid';
  end if;
  r:=public.e10_org_create_configuration_version(p_org,p_configuration_id,p_expected_latest_version,p_state,
    p_packaging_kind,p_base_unit,p_base_units_per_package,p_barcode,
    p_attrs,p_idempotency_key);
  v_id:=(r->>'configuration_version_id')::uuid;
  if not coalesce((r->>'replay')::boolean,false) then
    perform set_config('e10.quantity_increment_writer','on',true);
    update public.e10_product_configuration_versions set quantity_increment=p_quantity_increment
      where organization_id=p_org and e10_product_configuration_versions.id=v_id;
    perform set_config('e10.quantity_increment_writer','off',true);
  elsif not exists(select 1 from public.e10_product_configuration_versions v
      where v.organization_id=p_org and v.id=v_id and v.quantity_increment=p_quantity_increment) then
    raise exception using errcode='22023',message='idempotency_key_mismatch';
  end if;
  return r||jsonb_build_object('quantity_increment',p_quantity_increment);
exception when others then
  perform set_config('e10.quantity_increment_writer','off',true);
  raise;
end $$;

create or replace function e10.guard_quantity_increment_immutable() returns trigger
language plpgsql security definer set search_path=public as $$
begin
  if old.quantity_increment is distinct from new.quantity_increment
    and coalesce(current_setting('e10.quantity_increment_writer',true),'')<>'on' then
    raise exception using errcode='55000',message='configuration_quantity_increment_immutable';
  end if;
  return new;
end $$;

revoke all on function public.e10_org_create_configuration_version(uuid,uuid,integer,text,text,text,numeric,numeric,text,jsonb,text)
  from public,anon;
grant execute on function public.e10_org_create_configuration_version(uuid,uuid,integer,text,text,text,numeric,numeric,text,jsonb,text)
  to authenticated,service_role;

create function e10.guard_financial_maker_checker() returns trigger
language plpgsql security definer set search_path=public as $$
begin
  if old.status<>'approved' and new.status='approved' and (new.reviewed_by is null or new.approved_by is null
      or new.approved_by=new.reviewed_by or new.approved_revision<>new.revision) then
    raise exception using errcode='42501',message='financial_document_approval_requires_distinct_reviewer';
  end if;
  return new;
end $$;
revoke all on function e10.guard_financial_maker_checker() from public,anon,authenticated;
grant execute on function e10.guard_financial_maker_checker() to service_role;
create trigger e10_supplier_invoice_maker_checker_trg before update of status,reviewed_by,approved_by,approved_revision,revision
on public.e10_supplier_invoices for each row execute function e10.guard_financial_maker_checker();
create trigger e10_supplier_credit_maker_checker_trg before update of status,reviewed_by,approved_by,approved_revision,revision
on public.e10_supplier_credits for each row execute function e10.guard_financial_maker_checker();
