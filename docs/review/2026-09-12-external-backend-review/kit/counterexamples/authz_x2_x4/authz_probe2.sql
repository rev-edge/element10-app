\set ON_ERROR_STOP 0
\pset format unaligned
\pset tuples_only on
begin;

-- probe helper: runs a statement as the CURRENT role and reports sqlstate/message or result
create function pg_temp.probe(label text, stmt text) returns text language plpgsql as $$
declare r text;
begin
  execute 'select ('||stmt||')::text' into r;
  return label||' => OK '||left(coalesce(r,'<null>'),400);
exception when others then
  return label||' => '||sqlstate||' '||sqlerrm;
end $$;
grant execute on function pg_temp.probe(text,text) to authenticated;
-- privileged lookup helper (runs as postgres) for capturing ids / state from server-only tables
create function pg_temp.lookup(stmt text) returns text language plpgsql security definer as $$
declare r text; begin execute stmt into r; return r; end $$;
grant execute on function pg_temp.lookup(text) to authenticated;

-- ---------------------------------------------------------------- fixtures (as postgres)
do $$
declare
  oa uuid:='a1a00000-0000-4000-8000-000000000001'; ob uuid:='b1b00000-0000-4000-8000-000000000001';
  ra_full uuid:='a1a00000-0000-4000-8000-000000000011'; ra_none uuid:='a1a00000-0000-4000-8000-000000000012';
  ra_admin uuid:='a1a00000-0000-4000-8000-000000000013'; ra_prep uuid:='a1a00000-0000-4000-8000-000000000014';
  ra_appr uuid:='a1a00000-0000-4000-8000-000000000015'; ra_noloc uuid:='a1a00000-0000-4000-8000-000000000016';
  rb_full uuid:='b1b00000-0000-4000-8000-000000000011';
  ua_full uuid:='a1a00000-0000-4000-8000-000000000021'; ua_none uuid:='a1a00000-0000-4000-8000-000000000022';
  ua_admin uuid:='a1a00000-0000-4000-8000-000000000023'; ua_prep uuid:='a1a00000-0000-4000-8000-000000000024';
  ua_appr uuid:='a1a00000-0000-4000-8000-000000000025'; ua_noloc uuid:='a1a00000-0000-4000-8000-000000000026';
  ub_full uuid:='b1b00000-0000-4000-8000-000000000021';
  la uuid:='a1a00000-0000-4000-8000-000000000031'; lb uuid:='b1b00000-0000-4000-8000-000000000031';
  sa uuid:='a1a00000-0000-4000-8000-000000000041'; sb uuid:='b1b00000-0000-4000-8000-000000000041';
  pa uuid:='a1a00000-0000-4000-8000-000000000051'; pb uuid:='b1b00000-0000-4000-8000-000000000051';
  ca uuid:='a1a00000-0000-4000-8000-000000000061'; cb uuid:='b1b00000-0000-4000-8000-000000000061';
  va uuid:='a1a00000-0000-4000-8000-000000000071'; vb uuid:='b1b00000-0000-4000-8000-000000000071';
  sessa uuid:='a1a00000-0000-4000-8000-000000000081'; sessb uuid:='b1b00000-0000-4000-8000-000000000081';
  cap text; caps text[]:=array['act.purchasing_prepare','act.purchasing_approve','act.purchasing_cancel','act.create_receiving',
    'act.resolve_recovery','act.reserve_inventory','act.inventory_edit','act.view_financial_estimates','financial.actual_cost.read','act.permissions_config'];
begin
  insert into public.e10_organizations(id,name,slug) values(oa,'Probe org A','probe-org-a'),(ob,'Probe org B','probe-org-b');
  insert into public.e10_organization_roles(id,organization_id,key,name) values
    (ra_full,oa,'probe-full','A full'),(ra_none,oa,'probe-none','A none'),(ra_admin,oa,'admin','A admin'),
    (ra_prep,oa,'probe-prep','A prep only'),(ra_appr,oa,'probe-appr','A approve only'),(ra_noloc,oa,'probe-noloc','A full no location'),
    (rb_full,ob,'admin','B admin-full');
  insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at) values
    (ua_full,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','probe-a-full@x.invalid',now(),now()),
    (ua_none,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','probe-a-none@x.invalid',now(),now()),
    (ua_admin,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','probe-a-admin@x.invalid',now(),now()),
    (ua_prep,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','probe-a-prep@x.invalid',now(),now()),
    (ua_appr,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','probe-a-appr@x.invalid',now(),now()),
    (ua_noloc,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','probe-a-noloc@x.invalid',now(),now()),
    (ub_full,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','probe-b-full@x.invalid',now(),now());
  insert into public.e10_organization_memberships(organization_id,user_id,role_id,status) values
    (oa,ua_full,ra_full,'active'),(oa,ua_none,ra_none,'active'),(oa,ua_admin,ra_admin,'active'),
    (oa,ua_prep,ra_prep,'active'),(oa,ua_appr,ra_appr,'active'),(oa,ua_noloc,ra_noloc,'active'),(ob,ub_full,rb_full,'active');
  foreach cap in array caps loop
    insert into public.e10_organization_role_permissions(organization_id,role_id,capability,allowed) values
      (oa,ra_full,cap,true),(oa,ra_noloc,cap,true),(ob,rb_full,cap,true);
  end loop;
  insert into public.e10_organization_role_permissions(organization_id,role_id,capability,allowed) values
    (oa,ra_prep,'act.purchasing_prepare',true),(oa,ra_appr,'act.purchasing_approve',true),(oa,ra_appr,'act.purchasing_cancel',true);
  insert into public.e10_locations(id,organization_id,code,name,status) values(la,oa,'LA','Loc A','active'),(lb,ob,'LB','Loc B','active');
  insert into public.e10_location_role_permissions(organization_id,location_id,role_id,can_receive) values
    (oa,la,ra_full,true),(oa,la,ra_prep,true),(oa,la,ra_appr,true),(ob,lb,rb_full,true);
  insert into public.e10_suppliers(id,organization_id,code,name,status) values(sa,oa,'SA','Supp A','active'),(sb,ob,'SB','Supp B','active');
  insert into public.e10_product_masters(id,organization_id,name) values(pa,oa,'Prod A'),(pb,ob,'Prod B');
  insert into public.e10_product_configurations(id,organization_id,product_master_id,name) values(ca,oa,pa,'Case A'),(cb,ob,pb,'Case B');
  insert into public.e10_product_configuration_versions(id,organization_id,configuration_id,version_no,state,packaging_kind,base_unit,base_units_per_package)
    values(va,oa,ca,1,'active','case','unit',12),(vb,ob,cb,1,'active','case','unit',12);
  insert into public.e10_inventory_items(id,name,qty,organization_id) values('probe-item-a','Item A',0,oa),('probe-item-b','Item B',0,ob);
  insert into public.e10_break_sessions(id,name,streamer_uid,organization_id,source_show_ref,status) values
    (sessa,'Sess A',ua_full,oa,'probe-show-a','active'),(sessb,'Sess B',ub_full,ob,'probe-show-b','active');
end $$;

set role authenticated;

-- ---------------------------------------------------------------- org A documents (as ua_full)
select set_config('request.jwt.claims','{"sub":"a1a00000-0000-4000-8000-000000000021","role":"authenticated"}',true);
select pg_temp.probe('A create PO', $q$public.e10_org_create_purchase_order('a1a00000-0000-4000-8000-000000000001','a1a00000-0000-4000-8000-000000000041','a1a00000-0000-4000-8000-000000000031','PO-A','CAD',null,
  jsonb_build_array(jsonb_build_object('id','a1a00000-0000-4000-8000-000000000101','line_no',1,'configuration_version_id','a1a00000-0000-4000-8000-000000000071','ordered_quantity',10,'estimated_unit_cost',4.5)),'a-po-create')$q$);
select set_config('e10.probe.poa',pg_temp.lookup($l$select purchase_order_id::text from public.e10_purchase_order_commands where organization_id='a1a00000-0000-4000-8000-000000000001' and idempotency_key='a-po-create'$l$),true);
select pg_temp.probe('A submit PO', format($q$public.e10_org_transition_purchase_order('a1a00000-0000-4000-8000-000000000001',%L,1,'submit','go','a-po-submit')$q$,current_setting('e10.probe.poa')));
select pg_temp.probe('A approve PO', format($q$public.e10_org_transition_purchase_order('a1a00000-0000-4000-8000-000000000001',%L,2,'approve','go','a-po-approve')$q$,current_setting('e10.probe.poa')));
select pg_temp.probe('A create invoice', $q$public.e10_org_create_supplier_invoice('a1a00000-0000-4000-8000-000000000001','a1a00000-0000-4000-8000-000000000041','INV-A','CAD',current_date,50,null,null,null,null,null,
  jsonb_build_array(jsonb_build_object('id','a1a00000-0000-4000-8000-000000000201','line_no',1,'configuration_version_id','a1a00000-0000-4000-8000-000000000071','invoiced_quantity',10,'unit_cost',5,'line_amount',50)),'a-inv-create')$q$);
select set_config('e10.probe.inva',pg_temp.lookup($l$select document_id::text from public.e10_financial_document_commands where organization_id='a1a00000-0000-4000-8000-000000000001' and idempotency_key='a-inv-create'$l$),true);
select pg_temp.probe('A create credit', $q$public.e10_org_create_supplier_credit('a1a00000-0000-4000-8000-000000000001','a1a00000-0000-4000-8000-000000000041','CR-A','CAD',current_date,20,null,null,null,null,null,
  jsonb_build_array(jsonb_build_object('id','a1a00000-0000-4000-8000-000000000301','line_no',1,'configuration_version_id','a1a00000-0000-4000-8000-000000000071','line_amount',20)),'a-cr-create')$q$);
select set_config('e10.probe.cra',pg_temp.lookup($l$select document_id::text from public.e10_financial_document_commands where organization_id='a1a00000-0000-4000-8000-000000000001' and idempotency_key='a-cr-create'$l$),true);
select pg_temp.probe('A receive batch', $q$public.e10_org_receive_batch('a1a00000-0000-4000-8000-000000000001','a1a00000-0000-4000-8000-000000000041','a1a00000-0000-4000-8000-000000000031',now(),
  jsonb_build_array(jsonb_build_object('line_no',1,'configuration_version_id','a1a00000-0000-4000-8000-000000000071','inventory_item_id','probe-item-a','accepted_quantity',5,'damaged_quantity',0,'quarantined_quantity',1,
    'purchase_order_line_id','a1a00000-0000-4000-8000-000000000101','actual_unit_cost',4.75,'currency','CAD')),'a-rcpt-1')$q$);
select set_config('e10.probe.ra',pg_temp.lookup($l$select stock_receipt_id::text from public.e10_receipt_commands where organization_id='a1a00000-0000-4000-8000-000000000001' and idempotency_key='a-rcpt-1'$l$),true);
select set_config('e10.probe.rla',pg_temp.lookup($l$select result->'lines'->0->>'receipt_line_id' from public.e10_receipt_commands where organization_id='a1a00000-0000-4000-8000-000000000001' and idempotency_key='a-rcpt-1'$l$),true);
select set_config('e10.probe.lota',pg_temp.lookup($l$select result->'lines'->0->>'lot_id' from public.e10_receipt_commands where organization_id='a1a00000-0000-4000-8000-000000000001' and idempotency_key='a-rcpt-1'$l$),true);
select pg_temp.probe('A lot reserve', format($q$public.e10_org_lot_reserve('a1a00000-0000-4000-8000-000000000001',%L,2,'a1a00000-0000-4000-8000-000000000081','a-res-1')$q$,current_setting('e10.probe.lota')));
select set_config('e10.probe.resa',pg_temp.lookup($l$select id::text from public.e10_lot_reservations where organization_id='a1a00000-0000-4000-8000-000000000001' and idempotency_key='a-res-1'$l$),true);
select pg_temp.probe('A internal comment on invoice', format($q$public.e10_org_add_commercial_comment('a1a00000-0000-4000-8000-000000000001','supplier_invoice',%L,'internal','INTERNAL: supplier overcharged us, unit cost really 4.10',null,'a-cmt-int')$q$,current_setting('e10.probe.inva')));
select pg_temp.probe('A vendor comment on PO', format($q$public.e10_org_add_commercial_comment('a1a00000-0000-4000-8000-000000000001','purchase_order',%L,'vendor','VENDOR: please ship by Friday',null,'a-cmt-vendor')$q$,current_setting('e10.probe.poa')));
select set_config('e10.probe.cmta',pg_temp.lookup($l$select comment_id::text from public.e10_commercial_comment_commands where organization_id='a1a00000-0000-4000-8000-000000000001' and idempotency_key='a-cmt-int'$l$),true);


\echo ================= 5. LOCATION AUTHORITY ON REVERSAL (ua_noloc: all caps, no location grant, not admin)
-- release the reservation first so the receipt is reversible
select set_config('request.jwt.claims','{"sub":"a1a00000-0000-4000-8000-000000000021","role":"authenticated"}',true);
select pg_temp.probe('P00 full: release reservation', format($q$public.e10_org_lot_release('a1a00000-0000-4000-8000-000000000001',%L,'p00')$q$,current_setting('e10.probe.resa')));
select pg_temp.probe('P01 full: receive_po_line (single-line receipt r2)', $q$public.e10_org_receive_po_line('a1a00000-0000-4000-8000-000000000001','a1a00000-0000-4000-8000-000000000101','probe-item-a',1,0,0,null,now(),'[]'::jsonb,'p01')$q$);
select set_config('e10.probe.r2',pg_temp.lookup($l$select id::text from public.e10_stock_receipts where organization_id='a1a00000-0000-4000-8000-000000000001' and idempotency_key='p01'$l$),true);
select set_config('request.jwt.claims','{"sub":"a1a00000-0000-4000-8000-000000000026","role":"authenticated"}',true);
select pg_temp.probe('P02 noloc: can_receive_at loc A', $q$e10.can_receive_at('a1a00000-0000-4000-8000-000000000001','a1a00000-0000-4000-8000-000000000031')$q$);
select pg_temp.probe('P03 noloc: reverse_receipt_batch (batch receipt at loc A)', format($q$public.e10_org_reverse_receipt_batch('a1a00000-0000-4000-8000-000000000001',%L,'x','p03')$q$,current_setting('e10.probe.ra')));
select pg_temp.lookup(format($l$select 'P03 state => receipt status='||status from public.e10_stock_receipts where id=%L$l$,current_setting('e10.probe.ra')));
select pg_temp.probe('P04 noloc: reverse_receipt (single-line receipt at loc A)', format($q$public.e10_org_reverse_receipt('a1a00000-0000-4000-8000-000000000001',%L,'x','p04')$q$,current_setting('e10.probe.r2')));
select pg_temp.lookup(format($l$select 'P04 state => receipt status='||status||' item qty='||(select qty from public.e10_inventory_items where id='probe-item-a') from public.e10_stock_receipts where id=%L$l$,current_setting('e10.probe.r2')));
-- comment on a receipt at a location without authority, and lot_consume without location authority
select pg_temp.probe('P05 noloc: comment on receipt at loc A', format($q$public.e10_org_add_commercial_comment('a1a00000-0000-4000-8000-000000000001','stock_receipt',%L,'internal','x',null,'p05')$q$,current_setting('e10.probe.ra')));
rollback;
