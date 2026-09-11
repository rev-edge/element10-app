\set ON_ERROR_STOP on

do $$
declare
  o constant uuid:='e1000000-0000-4000-8000-0000000000a6';
  supplier constant uuid:='d3000000-0000-4000-8000-000000000001';
begin
  if (select count(*) from public.e10_supplier_invoices
      where id='d3000000-0000-4000-8000-000000000002')<>1
    or (select count(*) from public.e10_supplier_credits
      where id in ('d3000000-0000-4000-8000-000000000003','d3000000-0000-4000-8000-000000000004'))<>2 then
    raise exception 'predecessor financial rows did not survive X3d.0 migration';
  end if;

  update public.e10_supplier_invoices set total_amount=2
    where id='d3000000-0000-4000-8000-000000000002';
  update public.e10_supplier_credits set total_amount=total_amount+1
    where id in ('d3000000-0000-4000-8000-000000000003','d3000000-0000-4000-8000-000000000004');

  begin
    insert into public.e10_supplier_invoices(organization_id,supplier_id,currency,total_amount)
      values(o,supplier,'CAD',1);
    raise exception 'new unresolved invoice accepted after X3d.0 migration';
  exception when check_violation then null; end;

  begin
    insert into public.e10_supplier_credits
      (organization_id,supplier_id,supplier_document_number,currency,total_amount)
      values(o,supplier,'legacy-dup','CAD',3);
    raise exception 'new normalized duplicate credit accepted after X3d.0 migration';
  exception when unique_violation then null; end;

  raise notice 'TA-X3d.0 predecessor upgrade: PASS (unresolved and duplicate legacy rows survive; new violations denied)';
end $$;
