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

set role authenticated;
do $$
begin
  perform set_config('request.jwt.claims',jsonb_build_object(
    'sub','d3000000-0000-4000-8000-000000000005','role','authenticated')::text,true);
  begin
    perform public.e10_org_create_supplier_credit(
      'e1000000-0000-4000-8000-0000000000a6','d3000000-0000-4000-8000-000000000001',
      'legacy-dup','CAD',null,3,null,null,null,null,null,
      jsonb_build_array(jsonb_build_object('id','d3000000-0000-4000-8000-000000000007',
        'line_no',1,'line_amount',3)),'x3d-predecessor-ambiguous');
    raise exception 'X3d.1a silently selected one predecessor duplicate';
  exception when check_violation then null; end;
  raise notice 'TA-X3d.1a predecessor ambiguity: PASS (deterministic denial, no arbitrary target)';
end $$;
reset role;
