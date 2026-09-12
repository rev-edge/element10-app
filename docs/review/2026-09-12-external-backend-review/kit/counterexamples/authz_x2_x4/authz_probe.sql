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

-- ---------------------------------------------------------------- org B documents (as ub_full)
select set_config('request.jwt.claims','{"sub":"b1b00000-0000-4000-8000-000000000021","role":"authenticated"}',true);
select pg_temp.probe('B create PO', $q$public.e10_org_create_purchase_order('b1b00000-0000-4000-8000-000000000001','b1b00000-0000-4000-8000-000000000041','b1b00000-0000-4000-8000-000000000031','PO-B','CAD',null,
  jsonb_build_array(jsonb_build_object('id','b1b00000-0000-4000-8000-000000000101','line_no',1,'configuration_version_id','b1b00000-0000-4000-8000-000000000071','ordered_quantity',10)),'b-po-create')$q$);
select set_config('e10.probe.pob',pg_temp.lookup($l$select purchase_order_id::text from public.e10_purchase_order_commands where organization_id='b1b00000-0000-4000-8000-000000000001' and idempotency_key='b-po-create'$l$),true);
select pg_temp.probe('B submit PO', format($q$public.e10_org_transition_purchase_order('b1b00000-0000-4000-8000-000000000001',%L,1,'submit','go','b-po-submit')$q$,current_setting('e10.probe.pob')));
select pg_temp.probe('B approve PO', format($q$public.e10_org_transition_purchase_order('b1b00000-0000-4000-8000-000000000001',%L,2,'approve','go','b-po-approve')$q$,current_setting('e10.probe.pob')));
select pg_temp.probe('B create invoice', $q$public.e10_org_create_supplier_invoice('b1b00000-0000-4000-8000-000000000001','b1b00000-0000-4000-8000-000000000041','INV-B','CAD',current_date,50,null,null,null,null,null,
  jsonb_build_array(jsonb_build_object('id','b1b00000-0000-4000-8000-000000000201','line_no',1,'configuration_version_id','b1b00000-0000-4000-8000-000000000071','invoiced_quantity',10,'unit_cost',5,'line_amount',50)),'b-inv-create')$q$);
select set_config('e10.probe.invb',pg_temp.lookup($l$select document_id::text from public.e10_financial_document_commands where organization_id='b1b00000-0000-4000-8000-000000000001' and idempotency_key='b-inv-create'$l$),true);
select pg_temp.probe('B create credit', $q$public.e10_org_create_supplier_credit('b1b00000-0000-4000-8000-000000000001','b1b00000-0000-4000-8000-000000000041','CR-B','CAD',current_date,20,null,null,null,null,null,
  jsonb_build_array(jsonb_build_object('id','b1b00000-0000-4000-8000-000000000301','line_no',1,'configuration_version_id','b1b00000-0000-4000-8000-000000000071','line_amount',20)),'b-cr-create')$q$);
select set_config('e10.probe.crb',pg_temp.lookup($l$select document_id::text from public.e10_financial_document_commands where organization_id='b1b00000-0000-4000-8000-000000000001' and idempotency_key='b-cr-create'$l$),true);

\echo ================= 1. CROSS-TENANT PROBES (caller = ub_full, member/admin of org B only)
select pg_temp.probe('X01 transition A PO with p_org=B', format($q$public.e10_org_transition_purchase_order('b1b00000-0000-4000-8000-000000000001',%L,3,'cancel','x','x01')$q$,current_setting('e10.probe.poa')));
select pg_temp.probe('X02 transition A PO with p_org=A (non-member)', format($q$public.e10_org_transition_purchase_order('a1a00000-0000-4000-8000-000000000001',%L,3,'cancel','x','x02')$q$,current_setting('e10.probe.poa')));
select pg_temp.probe('X03 amend A PO with p_org=B', format($q$public.e10_org_amend_purchase_order('b1b00000-0000-4000-8000-000000000001',%L,3,'b1b00000-0000-4000-8000-000000000041','b1b00000-0000-4000-8000-000000000031','PO-A','CAD',null,jsonb_build_array(jsonb_build_object('id',gen_random_uuid(),'line_no',1,'configuration_version_id','b1b00000-0000-4000-8000-000000000071','ordered_quantity',1)),'x','x03')$q$,current_setting('e10.probe.poa')));
select pg_temp.probe('X04 create PO in B using A supplier', $q$public.e10_org_create_purchase_order('b1b00000-0000-4000-8000-000000000001','a1a00000-0000-4000-8000-000000000041','b1b00000-0000-4000-8000-000000000031',null,'CAD',null,jsonb_build_array(jsonb_build_object('line_no',1,'configuration_version_id','b1b00000-0000-4000-8000-000000000071','ordered_quantity',1)),'x04')$q$);
select pg_temp.probe('X05 create PO in B using A location', $q$public.e10_org_create_purchase_order('b1b00000-0000-4000-8000-000000000001','b1b00000-0000-4000-8000-000000000041','a1a00000-0000-4000-8000-000000000031',null,'CAD',null,jsonb_build_array(jsonb_build_object('line_no',1,'configuration_version_id','b1b00000-0000-4000-8000-000000000071','ordered_quantity',1)),'x05')$q$);
select pg_temp.probe('X06 create PO in B using A config version', $q$public.e10_org_create_purchase_order('b1b00000-0000-4000-8000-000000000001','b1b00000-0000-4000-8000-000000000041','b1b00000-0000-4000-8000-000000000031',null,'CAD',null,jsonb_build_array(jsonb_build_object('line_no',1,'configuration_version_id','a1a00000-0000-4000-8000-000000000071','ordered_quantity',1)),'x06')$q$);
select pg_temp.probe('X07 ORACLE create PO in B with line id = A PO line id', $q$public.e10_org_create_purchase_order('b1b00000-0000-4000-8000-000000000001','b1b00000-0000-4000-8000-000000000041','b1b00000-0000-4000-8000-000000000031',null,'CAD',null,jsonb_build_array(jsonb_build_object('id','a1a00000-0000-4000-8000-000000000101','line_no',1,'configuration_version_id','b1b00000-0000-4000-8000-000000000071','ordered_quantity',1)),'x07')$q$);
select pg_temp.probe('X07b control create PO in B with fresh line id', $q$public.e10_org_create_purchase_order('b1b00000-0000-4000-8000-000000000001','b1b00000-0000-4000-8000-000000000041','b1b00000-0000-4000-8000-000000000031',null,'CAD',null,jsonb_build_array(jsonb_build_object('id','b1b00000-0000-4000-8000-000000000199','line_no',1,'configuration_version_id','b1b00000-0000-4000-8000-000000000071','ordered_quantity',1)),'x07b')$q$);
select pg_temp.probe('X08 ORACLE amend B PO adding line id = A PO line id', format($q$public.e10_org_amend_purchase_order('b1b00000-0000-4000-8000-000000000001',%L,3,'b1b00000-0000-4000-8000-000000000041','b1b00000-0000-4000-8000-000000000031','PO-B','CAD',null,jsonb_build_array(jsonb_build_object('id','b1b00000-0000-4000-8000-000000000101','line_no',1,'configuration_version_id','b1b00000-0000-4000-8000-000000000071','ordered_quantity',10),jsonb_build_object('id','a1a00000-0000-4000-8000-000000000101','line_no',2,'configuration_version_id','b1b00000-0000-4000-8000-000000000071','ordered_quantity',1)),'x','x08')$q$,current_setting('e10.probe.pob')));
select pg_temp.probe('X09 create invoice in B with A supplier', $q$public.e10_org_create_supplier_invoice('b1b00000-0000-4000-8000-000000000001','a1a00000-0000-4000-8000-000000000041','INV-X','CAD',current_date,1,null,null,null,null,null,jsonb_build_array(jsonb_build_object('id',gen_random_uuid(),'line_no',1,'line_amount',1)),'x09')$q$);
select pg_temp.probe('X10 create invoice in B with A config version', $q$public.e10_org_create_supplier_invoice('b1b00000-0000-4000-8000-000000000001','b1b00000-0000-4000-8000-000000000041','INV-X','CAD',current_date,1,null,null,null,null,null,jsonb_build_array(jsonb_build_object('id',gen_random_uuid(),'line_no',1,'configuration_version_id','a1a00000-0000-4000-8000-000000000071','line_amount',1)),'x10')$q$);
select pg_temp.probe('X11 ORACLE create invoice in B with line id = A invoice line', $q$public.e10_org_create_supplier_invoice('b1b00000-0000-4000-8000-000000000001','b1b00000-0000-4000-8000-000000000041','INV-X2','CAD',current_date,1,null,null,null,null,null,jsonb_build_array(jsonb_build_object('id','a1a00000-0000-4000-8000-000000000201','line_no',1,'line_amount',1)),'x11')$q$);
select pg_temp.probe('X12 amend A invoice with p_org=B', format($q$public.e10_org_amend_supplier_invoice('b1b00000-0000-4000-8000-000000000001',%L,1,'CAD',current_date,1,jsonb_build_array(jsonb_build_object('id',gen_random_uuid(),'line_no',1,'line_amount',1)),'x','x12')$q$,current_setting('e10.probe.inva')));
select pg_temp.probe('X13 ORACLE amend B invoice adding line id = A invoice line', format($q$public.e10_org_amend_supplier_invoice('b1b00000-0000-4000-8000-000000000001',%L,1,'CAD',current_date,51,jsonb_build_array(jsonb_build_object('id','b1b00000-0000-4000-8000-000000000201','line_no',1,'configuration_version_id','b1b00000-0000-4000-8000-000000000071','invoiced_quantity',10,'unit_cost',5,'line_amount',50),jsonb_build_object('id','a1a00000-0000-4000-8000-000000000201','line_no',2,'line_amount',1)),'x','x13')$q$,current_setting('e10.probe.invb')));
select pg_temp.probe('X13b control amend B invoice adding fresh line id', format($q$public.e10_org_amend_supplier_invoice('b1b00000-0000-4000-8000-000000000001',%L,1,'CAD',current_date,51,jsonb_build_array(jsonb_build_object('id','b1b00000-0000-4000-8000-000000000201','line_no',1,'configuration_version_id','b1b00000-0000-4000-8000-000000000071','invoiced_quantity',10,'unit_cost',5,'line_amount',50),jsonb_build_object('id','b1b00000-0000-4000-8000-000000000299','line_no',2,'line_amount',1)),'x','x13b')$q$,current_setting('e10.probe.invb')));
select pg_temp.probe('X14 review A invoice p_org=B', format($q$public.e10_org_review_supplier_invoice('b1b00000-0000-4000-8000-000000000001',%L,1,'x','x14')$q$,current_setting('e10.probe.inva')));
select pg_temp.probe('X15 approve A invoice p_org=B', format($q$public.e10_org_approve_supplier_invoice('b1b00000-0000-4000-8000-000000000001',%L,1,'x','x15')$q$,current_setting('e10.probe.inva')));
select pg_temp.probe('X16 void A credit p_org=B', format($q$public.e10_org_void_supplier_credit('b1b00000-0000-4000-8000-000000000001',%L,1,'x','x16')$q$,current_setting('e10.probe.cra')));
select pg_temp.probe('X17 allocate B invoice line -> A PO line', $q$public.e10_org_allocate_invoice_to_po('b1b00000-0000-4000-8000-000000000001','b1b00000-0000-4000-8000-000000000201','a1a00000-0000-4000-8000-000000000101',2,3,1,'x','x17')$q$);
select pg_temp.probe('X18 allocate A invoice line -> B PO line', $q$public.e10_org_allocate_invoice_to_po('b1b00000-0000-4000-8000-000000000001','a1a00000-0000-4000-8000-000000000201','b1b00000-0000-4000-8000-000000000101',1,3,1,'x','x18')$q$);
select pg_temp.probe('X19 allocate B credit line -> A invoice line', $q$public.e10_org_allocate_credit_to_invoice('b1b00000-0000-4000-8000-000000000001','b1b00000-0000-4000-8000-000000000301','a1a00000-0000-4000-8000-000000000201',1,1,1,'x','x19')$q$);
select pg_temp.probe('X20 release A invoice from A PO p_org=B', $q$public.e10_org_release_invoice_from_po('b1b00000-0000-4000-8000-000000000001','a1a00000-0000-4000-8000-000000000201','a1a00000-0000-4000-8000-000000000101',1,3,1,'x','x20')$q$);
select pg_temp.probe('X21 comment on A PO p_org=B', format($q$public.e10_org_add_commercial_comment('b1b00000-0000-4000-8000-000000000001','purchase_order',%L,'internal','x',null,'x21')$q$,current_setting('e10.probe.poa')));
select pg_temp.probe('X22 comment on A invoice p_org=B', format($q$public.e10_org_add_commercial_comment('b1b00000-0000-4000-8000-000000000001','supplier_invoice',%L,'internal','x',null,'x22')$q$,current_setting('e10.probe.inva')));
select pg_temp.probe('X23 comment on A receipt p_org=B', format($q$public.e10_org_add_commercial_comment('b1b00000-0000-4000-8000-000000000001','stock_receipt',%L,'internal','x',null,'x23')$q$,current_setting('e10.probe.ra')));
select pg_temp.probe('X24 supersede A comment from B PO', format($q$public.e10_org_add_commercial_comment('b1b00000-0000-4000-8000-000000000001','purchase_order',%L,'internal','x',%L,'x24')$q$,current_setting('e10.probe.pob'),current_setting('e10.probe.cmta')));
select pg_temp.probe('X25 list A invoice comments p_org=B', format($q$public.e10_org_list_commercial_comments('b1b00000-0000-4000-8000-000000000001','supplier_invoice',%L,50,null,null)$q$,current_setting('e10.probe.inva')));
select pg_temp.probe('X26 list A invoice comments p_org=A (non-member)', format($q$public.e10_org_list_commercial_comments('a1a00000-0000-4000-8000-000000000001','supplier_invoice',%L,50,null,null)$q$,current_setting('e10.probe.inva')));
select pg_temp.probe('X27 vendor projection A PO p_org=B', format($q$public.e10_org_vendor_comment_projection('b1b00000-0000-4000-8000-000000000001','purchase_order',%L,50)$q$,current_setting('e10.probe.poa')));
select pg_temp.probe('X28 supplier workspace A supplier p_org=B', $q$public.e10_org_supplier_workspace('b1b00000-0000-4000-8000-000000000001','a1a00000-0000-4000-8000-000000000041',50,null)$q$);
select pg_temp.probe('X29 supplier workspace p_org=A (non-member)', $q$public.e10_org_supplier_workspace('a1a00000-0000-4000-8000-000000000001','a1a00000-0000-4000-8000-000000000041',50,null)$q$);
select pg_temp.probe('X30 actual cost history A supplier p_org=B', $q$public.e10_org_supplier_actual_cost_history('b1b00000-0000-4000-8000-000000000001','a1a00000-0000-4000-8000-000000000041','a1a00000-0000-4000-8000-000000000071','CAD',now(),50,null)$q$);
select pg_temp.probe('X31 lot_reserve A lot p_org=B', format($q$public.e10_org_lot_reserve('b1b00000-0000-4000-8000-000000000001',%L,1,'b1b00000-0000-4000-8000-000000000081','x31')$q$,current_setting('e10.probe.lota')));
select pg_temp.probe('X32 lot_reserve_for_demand A lot p_org=B', format($q$public.e10_org_lot_reserve_for_demand('b1b00000-0000-4000-8000-000000000001',%L,1,'manual','ref','label','x32')$q$,current_setting('e10.probe.lota')));
select pg_temp.probe('X33 lot_consume A reservation p_org=B', format($q$public.e10_org_lot_consume('b1b00000-0000-4000-8000-000000000001',%L,1,'x33')$q$,current_setting('e10.probe.resa')));
select pg_temp.probe('X34 lot_release A reservation p_org=B', format($q$public.e10_org_lot_release('b1b00000-0000-4000-8000-000000000001',%L,'x34')$q$,current_setting('e10.probe.resa')));
select pg_temp.probe('X35 receive_po_line A PO line p_org=B', $q$public.e10_org_receive_po_line('b1b00000-0000-4000-8000-000000000001','a1a00000-0000-4000-8000-000000000101','probe-item-b',1,0,0,null,now(),'[]'::jsonb,'x35')$q$);
select pg_temp.probe('X36 receive_batch into A location p_org=B', $q$public.e10_org_receive_batch('b1b00000-0000-4000-8000-000000000001','b1b00000-0000-4000-8000-000000000041','a1a00000-0000-4000-8000-000000000031',now(),jsonb_build_array(jsonb_build_object('line_no',1,'configuration_version_id','b1b00000-0000-4000-8000-000000000071','inventory_item_id','probe-item-b','accepted_quantity',1,'damaged_quantity',0,'quarantined_quantity',0)),'x36')$q$);
select pg_temp.probe('X37 receive_batch B with A PO line', $q$public.e10_org_receive_batch('b1b00000-0000-4000-8000-000000000001','b1b00000-0000-4000-8000-000000000041','b1b00000-0000-4000-8000-000000000031',now(),jsonb_build_array(jsonb_build_object('line_no',1,'configuration_version_id','b1b00000-0000-4000-8000-000000000071','inventory_item_id','probe-item-b','accepted_quantity',1,'damaged_quantity',0,'quarantined_quantity',0,'purchase_order_line_id','a1a00000-0000-4000-8000-000000000101')),'x37')$q$);
select pg_temp.probe('X38 receive_batch B with A invoice line', $q$public.e10_org_receive_batch('b1b00000-0000-4000-8000-000000000001','b1b00000-0000-4000-8000-000000000041','b1b00000-0000-4000-8000-000000000031',now(),jsonb_build_array(jsonb_build_object('line_no',1,'configuration_version_id','b1b00000-0000-4000-8000-000000000071','inventory_item_id','probe-item-b','accepted_quantity',1,'damaged_quantity',0,'quarantined_quantity',0,'invoice_line_id','a1a00000-0000-4000-8000-000000000201')),'x38')$q$);
select pg_temp.probe('X39 receive_batch B with A inventory item', $q$public.e10_org_receive_batch('b1b00000-0000-4000-8000-000000000001','b1b00000-0000-4000-8000-000000000041','b1b00000-0000-4000-8000-000000000031',now(),jsonb_build_array(jsonb_build_object('line_no',1,'configuration_version_id','b1b00000-0000-4000-8000-000000000071','inventory_item_id','probe-item-a','accepted_quantity',1,'damaged_quantity',0,'quarantined_quantity',0)),'x39')$q$);
select pg_temp.probe('X40 receive_batch B with A config version', $q$public.e10_org_receive_batch('b1b00000-0000-4000-8000-000000000001','b1b00000-0000-4000-8000-000000000041','b1b00000-0000-4000-8000-000000000031',now(),jsonb_build_array(jsonb_build_object('line_no',1,'configuration_version_id','a1a00000-0000-4000-8000-000000000071','inventory_item_id','probe-item-b','accepted_quantity',1,'damaged_quantity',0,'quarantined_quantity',0)),'x40')$q$);
select pg_temp.probe('X41 reverse_receipt A receipt p_org=B', format($q$public.e10_org_reverse_receipt('b1b00000-0000-4000-8000-000000000001',%L,'x','x41')$q$,current_setting('e10.probe.ra')));
select pg_temp.probe('X42 reverse_receipt_batch A receipt p_org=B', format($q$public.e10_org_reverse_receipt_batch('b1b00000-0000-4000-8000-000000000001',%L,'x','x42')$q$,current_setting('e10.probe.ra')));
select pg_temp.probe('X43 review_receipt_disposition A line p_org=B', format($q$public.e10_org_review_receipt_disposition('b1b00000-0000-4000-8000-000000000001',%L,'accept',1,null,0,'x','x43')$q$,current_setting('e10.probe.rla')));
select pg_temp.probe('X44 set_location_financial_access A location p_org=B', $q$public.e10_org_set_location_financial_access('b1b00000-0000-4000-8000-000000000001','a1a00000-0000-4000-8000-000000000031','b1b00000-0000-4000-8000-000000000011',null,true,'x','{}'::jsonb,'x44')$q$);
select pg_temp.probe('X45 set_location_financial_access B location, A role', $q$public.e10_org_set_location_financial_access('b1b00000-0000-4000-8000-000000000001','b1b00000-0000-4000-8000-000000000031','a1a00000-0000-4000-8000-000000000011',null,true,'x','{}'::jsonb,'x45')$q$);
select pg_temp.probe('X46 purchase_destinations p_org=A (non-member)', $q$(select count(*) from public.e10_org_purchase_destinations('a1a00000-0000-4000-8000-000000000001'))$q$);
select pg_temp.probe('X47 direct table read A purchase_orders as B member', $q$(select count(*) from public.e10_purchase_orders where organization_id='a1a00000-0000-4000-8000-000000000001')$q$);
select pg_temp.probe('X48 direct table read invoices (any)', $q$(select count(*) from public.e10_supplier_invoices)$q$);
select pg_temp.probe('X49 direct table read lot reservations', $q$(select count(*) from public.e10_lot_reservations)$q$);
select pg_temp.probe('X50 direct table read commercial comments', $q$(select count(*) from public.e10_commercial_comments)$q$);
select pg_temp.probe('X51 internal e10.lock_purchase_order', $q$e10.lock_purchase_order('b1b00000-0000-4000-8000-000000000001','b1b00000-0000-4000-8000-000000000101')$q$);
select pg_temp.probe('X52 internal _e10_org_lot_reserve_x4b', format($q$public._e10_org_lot_reserve_x4b('b1b00000-0000-4000-8000-000000000001',%L,1,'b1b00000-0000-4000-8000-000000000081','x52')$q$,current_setting('e10.probe.lota')));
select pg_temp.probe('X53 e10.can_receive_at A location as B member', $q$e10.can_receive_at('a1a00000-0000-4000-8000-000000000001','a1a00000-0000-4000-8000-000000000031')$q$);
-- A lot reserved against a B break session by an A member
select set_config('request.jwt.claims','{"sub":"a1a00000-0000-4000-8000-000000000021","role":"authenticated"}',true);
select pg_temp.probe('X54 A member: lot_reserve A lot against B break session', format($q$public.e10_org_lot_reserve('a1a00000-0000-4000-8000-000000000001',%L,1,'b1b00000-0000-4000-8000-000000000081','x54')$q$,current_setting('e10.probe.lota')));
select pg_temp.probe('X55 A member: receive_batch with expected allocation id from B', $q$public.e10_org_receive_batch('a1a00000-0000-4000-8000-000000000001','a1a00000-0000-4000-8000-000000000041','a1a00000-0000-4000-8000-000000000031',now(),jsonb_build_array(jsonb_build_object('line_no',1,'configuration_version_id','a1a00000-0000-4000-8000-000000000071','inventory_item_id','probe-item-a','accepted_quantity',1,'damaged_quantity',0,'quarantined_quantity',0,'purchase_order_line_id','a1a00000-0000-4000-8000-000000000101','expected_allocations',jsonb_build_array(jsonb_build_object('id','b1b00000-0000-4000-8000-000000000999','quantity',1)))),'x55')$q$);

\echo ================= 2. CAPABILITY / ROLE PROBES (org A)
-- ua_admin: role key 'admin' but NO purchasing caps
select set_config('request.jwt.claims','{"sub":"a1a00000-0000-4000-8000-000000000023","role":"authenticated"}',true);
select pg_temp.probe('C01 admin w/o caps: create PO', $q$public.e10_org_create_purchase_order('a1a00000-0000-4000-8000-000000000001','a1a00000-0000-4000-8000-000000000041','a1a00000-0000-4000-8000-000000000031',null,'CAD',null,jsonb_build_array(jsonb_build_object('line_no',1,'configuration_version_id','a1a00000-0000-4000-8000-000000000071','ordered_quantity',1)),'c01')$q$);
select pg_temp.probe('C02 admin w/o caps: approve PO', format($q$public.e10_org_transition_purchase_order('a1a00000-0000-4000-8000-000000000001',%L,3,'cancel','x','c02')$q$,current_setting('e10.probe.poa')));
select pg_temp.probe('C03 admin w/o caps: receive_batch', $q$public.e10_org_receive_batch('a1a00000-0000-4000-8000-000000000001','a1a00000-0000-4000-8000-000000000041','a1a00000-0000-4000-8000-000000000031',now(),jsonb_build_array(jsonb_build_object('line_no',1,'configuration_version_id','a1a00000-0000-4000-8000-000000000071','inventory_item_id','probe-item-a','accepted_quantity',1,'damaged_quantity',0,'quarantined_quantity',0)),'c03')$q$);
select pg_temp.probe('C04 admin w/o caps: actual cost history', $q$public.e10_org_supplier_actual_cost_history('a1a00000-0000-4000-8000-000000000001','a1a00000-0000-4000-8000-000000000041','a1a00000-0000-4000-8000-000000000071','CAD',now(),50,null)$q$);
select pg_temp.probe('C05 admin w/o location grant: purchase_destinations', $q$(select jsonb_agg(name) from public.e10_org_purchase_destinations('a1a00000-0000-4000-8000-000000000001'))$q$);
select pg_temp.probe('C06 admin w/o caps: set_location_financial_access (needs permissions_config)', $q$public.e10_org_set_location_financial_access('a1a00000-0000-4000-8000-000000000001','a1a00000-0000-4000-8000-000000000031','a1a00000-0000-4000-8000-000000000012',null,true,'x','{}'::jsonb,'c06')$q$);
-- ua_prep: only act.purchasing_prepare (+ location grant)
select set_config('request.jwt.claims','{"sub":"a1a00000-0000-4000-8000-000000000024","role":"authenticated"}',true);
select pg_temp.probe('C10 prep-only: create PO', $q$public.e10_org_create_purchase_order('a1a00000-0000-4000-8000-000000000001','a1a00000-0000-4000-8000-000000000041','a1a00000-0000-4000-8000-000000000031','PO-A2','CAD',null,jsonb_build_array(jsonb_build_object('line_no',1,'configuration_version_id','a1a00000-0000-4000-8000-000000000071','ordered_quantity',1)),'c10')$q$);
select set_config('e10.probe.poa2',pg_temp.lookup($l$select purchase_order_id::text from public.e10_purchase_order_commands where organization_id='a1a00000-0000-4000-8000-000000000001' and idempotency_key='c10'$l$),true);
select pg_temp.probe('C11 prep-only: submit PO', format($q$public.e10_org_transition_purchase_order('a1a00000-0000-4000-8000-000000000001',%L,1,'submit','x','c11')$q$,current_setting('e10.probe.poa2')));
select pg_temp.probe('C12 prep-only: approve PO', format($q$public.e10_org_transition_purchase_order('a1a00000-0000-4000-8000-000000000001',%L,2,'approve','x','c12')$q$,current_setting('e10.probe.poa2')));
select pg_temp.probe('C13 prep-only: cancel PO', format($q$public.e10_org_transition_purchase_order('a1a00000-0000-4000-8000-000000000001',%L,2,'cancel','x','c13')$q$,current_setting('e10.probe.poa2')));
select pg_temp.probe('C14 prep-only: review invoice', format($q$public.e10_org_review_supplier_invoice('a1a00000-0000-4000-8000-000000000001',%L,1,'x','c14')$q$,current_setting('e10.probe.inva')));
select pg_temp.probe('C15 prep-only: approve invoice', format($q$public.e10_org_approve_supplier_invoice('a1a00000-0000-4000-8000-000000000001',%L,2,'x','c15')$q$,current_setting('e10.probe.inva')));
select pg_temp.probe('C16 prep-only: void invoice', format($q$public.e10_org_void_supplier_invoice('a1a00000-0000-4000-8000-000000000001',%L,2,'x','c16')$q$,current_setting('e10.probe.inva')));
select pg_temp.probe('C17 prep-only: receive_batch (no create_receiving)', $q$public.e10_org_receive_batch('a1a00000-0000-4000-8000-000000000001','a1a00000-0000-4000-8000-000000000041','a1a00000-0000-4000-8000-000000000031',now(),jsonb_build_array(jsonb_build_object('line_no',1,'configuration_version_id','a1a00000-0000-4000-8000-000000000071','inventory_item_id','probe-item-a','accepted_quantity',1,'damaged_quantity',0,'quarantined_quantity',0)),'c17')$q$);
select pg_temp.probe('C18 prep-only: lot_consume (no inventory_edit)', format($q$public.e10_org_lot_consume('a1a00000-0000-4000-8000-000000000001',%L,1,'c18')$q$,current_setting('e10.probe.resa')));
-- ua_appr: approve + cancel only
select set_config('request.jwt.claims','{"sub":"a1a00000-0000-4000-8000-000000000025","role":"authenticated"}',true);
select pg_temp.probe('C20 approve-only: approve PO', format($q$public.e10_org_transition_purchase_order('a1a00000-0000-4000-8000-000000000001',%L,2,'approve','x','c20')$q$,current_setting('e10.probe.poa2')));
select pg_temp.probe('C21 approve-only: submit (needs prepare)', format($q$public.e10_org_transition_purchase_order('a1a00000-0000-4000-8000-000000000001',%L,3,'submit','x','c21')$q$,current_setting('e10.probe.poa2')));
select pg_temp.probe('C22 approve-only: amend PO (needs prepare)', format($q$public.e10_org_amend_purchase_order('a1a00000-0000-4000-8000-000000000001',%L,3,'a1a00000-0000-4000-8000-000000000041','a1a00000-0000-4000-8000-000000000031','PO-A2','CAD',null,jsonb_build_array(jsonb_build_object('id',gen_random_uuid(),'line_no',1,'configuration_version_id','a1a00000-0000-4000-8000-000000000071','ordered_quantity',1)),'x','c22')$q$,current_setting('e10.probe.poa2')));
select pg_temp.probe('C23 approve-only: approve invoice (reviewed by prep)', format($q$public.e10_org_approve_supplier_invoice('a1a00000-0000-4000-8000-000000000001',%L,2,'x','c23')$q$,current_setting('e10.probe.inva')));
select pg_temp.probe('C24 approve-only: allocate invoice->PO (needs prepare)', $q$public.e10_org_allocate_invoice_to_po('a1a00000-0000-4000-8000-000000000001','a1a00000-0000-4000-8000-000000000201','a1a00000-0000-4000-8000-000000000101',3,3,1,'x','c24')$q$);
-- amend of an approved invoice by prep-only user: status and reviewed_by afterwards
select set_config('request.jwt.claims','{"sub":"a1a00000-0000-4000-8000-000000000024","role":"authenticated"}',true);
select pg_temp.probe('C30 prep-only: amend APPROVED invoice', format($q$public.e10_org_amend_supplier_invoice('a1a00000-0000-4000-8000-000000000001',%L,3,'CAD',current_date,60,jsonb_build_array(jsonb_build_object('id','a1a00000-0000-4000-8000-000000000201','line_no',1,'configuration_version_id','a1a00000-0000-4000-8000-000000000071','invoiced_quantity',10,'unit_cost',6,'line_amount',60)),'bump price','c30')$q$,current_setting('e10.probe.inva')));
select pg_temp.lookup(format($l$select 'C30 state => status='||status||' reviewed_by='||coalesce(reviewed_by::text,'null')||' approved_by='||coalesce(approved_by::text,'null')||' total='||total_amount from public.e10_supplier_invoices where id=%L$l$,current_setting('e10.probe.inva')));

\echo ================= 3. LOCATION GATING (org A, ua_noloc has all caps, NO location grant, not admin)
select set_config('request.jwt.claims','{"sub":"a1a00000-0000-4000-8000-000000000026","role":"authenticated"}',true);
select pg_temp.probe('L01 noloc: purchase_destinations', $q$(select coalesce(jsonb_agg(name),'[]') from public.e10_org_purchase_destinations('a1a00000-0000-4000-8000-000000000001'))$q$);
select pg_temp.probe('L02 noloc: create PO to loc A', $q$public.e10_org_create_purchase_order('a1a00000-0000-4000-8000-000000000001','a1a00000-0000-4000-8000-000000000041','a1a00000-0000-4000-8000-000000000031',null,'CAD',null,jsonb_build_array(jsonb_build_object('line_no',1,'configuration_version_id','a1a00000-0000-4000-8000-000000000071','ordered_quantity',1)),'l02')$q$);
select pg_temp.probe('L03 noloc: receive_batch at loc A', $q$public.e10_org_receive_batch('a1a00000-0000-4000-8000-000000000001','a1a00000-0000-4000-8000-000000000041','a1a00000-0000-4000-8000-000000000031',now(),jsonb_build_array(jsonb_build_object('line_no',1,'configuration_version_id','a1a00000-0000-4000-8000-000000000071','inventory_item_id','probe-item-a','accepted_quantity',1,'damaged_quantity',0,'quarantined_quantity',0)),'l03')$q$);
select pg_temp.probe('L04 noloc: receive_po_line at loc A', $q$public.e10_org_receive_po_line('a1a00000-0000-4000-8000-000000000001','a1a00000-0000-4000-8000-000000000101','probe-item-a',1,0,0,null,now(),'[]'::jsonb,'l04')$q$);
select pg_temp.probe('L05 noloc: review disposition at loc A', format($q$public.e10_org_review_receipt_disposition('a1a00000-0000-4000-8000-000000000001',%L,'accept',1,null,0,'x','l05')$q$,current_setting('e10.probe.rla')));
select pg_temp.probe('L06 noloc: allocate invoice->PO at loc A', $q$public.e10_org_allocate_invoice_to_po('a1a00000-0000-4000-8000-000000000001','a1a00000-0000-4000-8000-000000000201','a1a00000-0000-4000-8000-000000000101',4,3,1,'x','l06')$q$);
select pg_temp.probe('L07 noloc: approve PO at loc A', format($q$public.e10_org_transition_purchase_order('a1a00000-0000-4000-8000-000000000001',%L,3,'approve','x','l07')$q$,current_setting('e10.probe.poa2')));
select pg_temp.probe('L08 noloc: lot_reserve_for_demand on lot at loc A', format($q$public.e10_org_lot_reserve_for_demand('a1a00000-0000-4000-8000-000000000001',%L,1,'manual','ref','label','l08')$q$,current_setting('e10.probe.lota')));
select pg_temp.probe('L09 noloc: lot_release A reservation (lot at loc A)', format($q$public.e10_org_lot_release('a1a00000-0000-4000-8000-000000000001',%L,'l09')$q$,current_setting('e10.probe.resa')));
select pg_temp.probe('L10 noloc: reverse_receipt_batch at loc A', format($q$public.e10_org_reverse_receipt_batch('a1a00000-0000-4000-8000-000000000001',%L,'x','l10')$q$,current_setting('e10.probe.ra')));
select pg_temp.lookup(format($l$select 'L10 state => receipt status='||status from public.e10_stock_receipts where id=%L$l$,current_setting('e10.probe.ra')));

\echo ================= 4. READ-SIDE LEAK PROBES (org A, ua_none = member with NO capabilities)
select set_config('request.jwt.claims','{"sub":"a1a00000-0000-4000-8000-000000000022","role":"authenticated"}',true);
select pg_temp.probe('R01 none: direct select invoices', $q$(select count(*) from public.e10_supplier_invoices where organization_id='a1a00000-0000-4000-8000-000000000001')$q$);
select pg_temp.probe('R02 none: list INTERNAL comments on invoice', format($q$public.e10_org_list_commercial_comments('a1a00000-0000-4000-8000-000000000001','supplier_invoice',%L,50,null,null)$q$,current_setting('e10.probe.inva')));
select pg_temp.probe('R03 none: vendor projection on invoice', format($q$public.e10_org_vendor_comment_projection('a1a00000-0000-4000-8000-000000000001','supplier_invoice',%L,50)$q$,current_setting('e10.probe.inva')));
select pg_temp.probe('R04 none: supplier workspace', $q$public.e10_org_supplier_workspace('a1a00000-0000-4000-8000-000000000001','a1a00000-0000-4000-8000-000000000041',50,null)$q$);
select pg_temp.probe('R05 none: actual cost history', $q$public.e10_org_supplier_actual_cost_history('a1a00000-0000-4000-8000-000000000001','a1a00000-0000-4000-8000-000000000041','a1a00000-0000-4000-8000-000000000071','CAD',now(),50,null)$q$);
select pg_temp.probe('R06 none: PO lines (RLS act.view_financial_estimates)', $q$(select count(*) from public.e10_purchase_order_lines where organization_id='a1a00000-0000-4000-8000-000000000001')$q$);
select pg_temp.probe('R07 none: stock receipt lines direct', $q$(select count(*) from public.e10_stock_receipt_lines)$q$);
-- ua_full has financial.actual_cost.read: check workspace shows costs
select set_config('request.jwt.claims','{"sub":"a1a00000-0000-4000-8000-000000000021","role":"authenticated"}',true);
select pg_temp.probe('R10 full: supplier workspace (financial)', $q$(select jsonb_build_object('fin',w->'financial_access','summary',w->'financial_summary','item_kinds',(select jsonb_agg(i->>'kind') from jsonb_array_elements(w->'items') i)) from public.e10_org_supplier_workspace('a1a00000-0000-4000-8000-000000000001','a1a00000-0000-4000-8000-000000000041',50,null) w)$q$);
select pg_temp.probe('R11 full: actual cost history', $q$public.e10_org_supplier_actual_cost_history('a1a00000-0000-4000-8000-000000000001','a1a00000-0000-4000-8000-000000000041','a1a00000-0000-4000-8000-000000000071','CAD',now(),50,null)$q$);
-- replay of another user's command with same key+payload (same org, same cap)
select set_config('request.jwt.claims','{"sub":"a1a00000-0000-4000-8000-000000000024","role":"authenticated"}',true);
select pg_temp.probe('R20 prep-only replays ua_full create-PO command key', $q$public.e10_org_create_purchase_order('a1a00000-0000-4000-8000-000000000001','a1a00000-0000-4000-8000-000000000041','a1a00000-0000-4000-8000-000000000031','PO-A','CAD',null,
  jsonb_build_array(jsonb_build_object('id','a1a00000-0000-4000-8000-000000000101','line_no',1,'configuration_version_id','a1a00000-0000-4000-8000-000000000071','ordered_quantity',10,'estimated_unit_cost',4.5)),'a-po-create')$q$);

rollback;
