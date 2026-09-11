-- TA-X3e append-only comments and audience-safe projection. Self-failing and rolled back.
begin;

do $$
declare
  o uuid:='d3300000-0000-4000-8000-000000000001';
  foreign_org uuid:='d3300000-0000-4000-8000-000000000002';
  actor uuid:='d3300000-0000-4000-8000-000000000003';
  low_actor uuid:='d3300000-0000-4000-8000-000000000004';
  role_id uuid:='d3300000-0000-4000-8000-000000000005';
  low_role uuid:='d3300000-0000-4000-8000-000000000006';
  foreign_role uuid:='d3300000-0000-4000-8000-000000000010';
  supplier uuid:='d3300000-0000-4000-8000-000000000007';
  location_id uuid:='d3300000-0000-4000-8000-000000000008';
  po uuid:='d3300000-0000-4000-8000-000000000009';
begin
  insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at) values
    (actor,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','x3e-writer@example.invalid',now(),now()),
    (low_actor,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','x3e-low@example.invalid',now(),now());
  insert into public.e10_organizations(id,name,slug) values(o,'X3e org','x3e-org'),(foreign_org,'X3e foreign','x3e-foreign');
  insert into public.e10_organization_roles(id,organization_id,key,name) values
    (role_id,o,'x3e-writer','X3e writer'),(low_role,o,'x3e-low','X3e low'),
    (foreign_role,foreign_org,'x3e-foreign','X3e foreign');
  insert into public.e10_organization_memberships(organization_id,user_id,role_id,status) values
    (o,actor,role_id,'active'),(o,low_actor,low_role,'active'),(foreign_org,actor,foreign_role,'active');
  insert into public.e10_organization_role_permissions(organization_id,role_id,capability,allowed)
    values(o,role_id,'act.purchasing_prepare',true),(o,role_id,'act.record_commercial_events',true),
      (foreign_org,foreign_role,'act.purchasing_prepare',true);
  insert into public.e10_suppliers(id,organization_id,name,status) values
    (supplier,o,'X3e supplier','active'),('d3300000-0000-4000-8000-000000000011',foreign_org,'X3e foreign supplier','active');
  insert into public.e10_locations(id,organization_id,name,status) values
    (location_id,o,'X3e location','active'),('d3300000-0000-4000-8000-000000000012',foreign_org,'X3e foreign location','active');
  insert into public.e10_purchase_orders(id,organization_id,supplier_id,destination_location_id,order_number,status,currency,revision,approved_revision,approved_by,approved_at,created_by)
    values(po,o,supplier,location_id,'PO-X3E','approved','CAD',7,7,actor,'2026-09-11T12:00:00Z',actor),
      ('d3300000-0000-4000-8000-000000000013',o,supplier,location_id,'PO-X3E-2','draft','CAD',1,null,null,null,actor),
      ('d3300000-0000-4000-8000-000000000014',foreign_org,'d3300000-0000-4000-8000-000000000011',
        'd3300000-0000-4000-8000-000000000012','PO-X3E-F','draft','CAD',1,null,null,null,actor);
  insert into public.e10_supplier_invoices(id,organization_id,supplier_id,supplier_document_number,revision,status,currency,total_amount,approved_revision,approved_by,approved_at,created_by)
    values('d3300000-0000-4000-8000-000000000015',o,supplier,'INV-X3E',4,'approved','CAD',25,4,actor,'2026-09-11T12:00:00Z',actor);
  insert into public.e10_stock_receipts(id,organization_id,supplier_id,destination_location_id,receipt_number,status,created_by)
    values('d3300000-0000-4000-8000-000000000016',o,supplier,location_id,'REC-X3E','posted',actor);
  insert into public.e10_supplier_credits(id,organization_id,supplier_id,supplier_document_number,revision,status,currency,total_amount,approved_revision,approved_by,approved_at,created_by)
    values('d3300000-0000-4000-8000-000000000017',o,supplier,'CR-X3E',3,'approved','CAD',5,3,actor,'2026-09-11T12:00:00Z',actor);
end $$;

create temp table x3e_results(k text primary key,v jsonb);
grant select,insert on x3e_results to authenticated;

set local role authenticated;
do $$
declare
  o uuid:='d3300000-0000-4000-8000-000000000001';
  po uuid:='d3300000-0000-4000-8000-000000000009';
  original jsonb; replay jsonb; vendor1 jsonb; vendor2 jsonb; internal_read jsonb; vendor_output jsonb;
  page1 jsonb; page2 jsonb; cursor_row jsonb;
begin
  perform set_config('request.jwt.claims',jsonb_build_object('sub','d3300000-0000-4000-8000-000000000003','role','authenticated')::text,true);
  original:=public.e10_org_add_commercial_comment(o,'purchase_order',po,'internal',
    'SECRET DEAL NOTE: never vendor-visible',null,'x3e-internal-create');
  replay:=public.e10_org_add_commercial_comment(o,'purchase_order',po,'internal',
    'SECRET DEAL NOTE: never vendor-visible',null,' x3e-internal-create ');
  if replay->>'replay'<>'true' or replay->>'comment_id'<>original->>'comment_id' then raise exception 'comment replay failed: %',replay; end if;
  vendor1:=public.e10_org_add_commercial_comment(o,'purchase_order',po,'vendor',
    'Deliver at loading bay A',null,'x3e-vendor-create');
  vendor2:=public.e10_org_add_commercial_comment(o,'purchase_order',po,'vendor',
    'Deliver at loading bay B',(vendor1->>'comment_id')::uuid,'x3e-vendor-amend');
  perform public.e10_org_add_commercial_comment(o,'supplier_invoice','d3300000-0000-4000-8000-000000000015','internal','invoice note',null,'x3e-invoice');
  perform public.e10_org_add_commercial_comment(o,'stock_receipt','d3300000-0000-4000-8000-000000000016','vendor','receipt note',null,'x3e-receipt');
  perform public.e10_org_add_commercial_comment(o,'supplier_credit','d3300000-0000-4000-8000-000000000017','internal','credit note',null,'x3e-credit');
  begin
    perform public.e10_org_add_commercial_comment(o,'purchase_order',po,'internal','bad audience chain',
      (vendor2->>'comment_id')::uuid,'x3e-cross-audience');
    raise exception 'cross-audience supersession accepted';
  exception when sqlstate '22023' then null; end;
  begin
    perform public.e10_org_add_commercial_comment(o,'purchase_order','d3300000-0000-4000-8000-000000000013','vendor','bad document chain',
      (vendor2->>'comment_id')::uuid,'x3e-cross-document');
    raise exception 'cross-document supersession accepted';
  exception when sqlstate '22023' then null; end;
  begin
    perform public.e10_org_add_commercial_comment('d3300000-0000-4000-8000-000000000002','purchase_order','d3300000-0000-4000-8000-000000000014',
      'vendor','bad multi-membership chain',(vendor2->>'comment_id')::uuid,'x3e-cross-org-chain');
    raise exception 'multi-membership cross-org supersession accepted';
  exception when sqlstate '22023' then null; end;
  begin perform public.e10_org_add_commercial_comment(o,null,po,'vendor','bad',null,'x3e-null-kind');
    raise exception 'NULL document kind accepted'; exception when sqlstate '22023' then null; end;
  begin perform public.e10_org_add_commercial_comment(o,'purchase_order',po,null,'bad',null,'x3e-null-audience');
    raise exception 'NULL audience accepted'; exception when sqlstate '22023' then null; end;
  begin
    perform public.e10_org_add_commercial_comment(o,'purchase_order',po,'vendor',' ',null,'x3e-blank');
    raise exception 'blank comment accepted';
  exception when sqlstate '22023' then null; end;
  begin
    perform public.e10_org_add_commercial_comment(o,'purchase_order',po,'vendor',repeat('x',4001),null,'x3e-long');
    raise exception 'oversized comment accepted';
  exception when sqlstate '22023' then null; end;

  internal_read:=public.e10_org_list_commercial_comments(o,'purchase_order',po,20,null,null);
  page1:=public.e10_org_list_commercial_comments(o,'purchase_order',po,2,null,null);
  cursor_row:=page1->'items'->1;
  page2:=public.e10_org_list_commercial_comments(o,'purchase_order',po,2,
    (cursor_row->>'created_at')::timestamptz,(cursor_row->>'id')::uuid);
  if jsonb_array_length(page1->'items')<>2 or jsonb_array_length(page2->'items')<>1 then
    raise exception 'bounded history traversal failed: page1 %, page2 %',page1,page2;
  end if;
  begin perform public.e10_org_list_commercial_comments(o,'purchase_order',po,101,null,null);
    raise exception 'oversized page accepted'; exception when sqlstate '22023' then null; end;
  begin perform public.e10_org_list_commercial_comments(o,null,po,20,null,null);
    raise exception 'NULL history kind accepted'; exception when sqlstate '22023' then null; end;
  begin perform public.e10_org_list_commercial_comments(o,'not_a_document',po,20,null,null);
    raise exception 'invalid history kind accepted'; exception when sqlstate '22023' then null; end;
  begin perform public.e10_org_list_commercial_comments(o,'purchase_order',po,20,now(),null);
    raise exception 'half cursor accepted'; exception when sqlstate '22023' then null; end;
  begin perform public.e10_org_list_commercial_comments(o,'purchase_order',po,20,'infinity',gen_random_uuid());
    raise exception 'nonfinite cursor accepted'; exception when sqlstate '22023' then null; end;
  vendor_output:=public.e10_org_vendor_comment_projection(o,'purchase_order',po,20);
  begin perform public.e10_org_vendor_comment_projection(o,null,po,20);
    raise exception 'NULL vendor kind accepted'; exception when sqlstate '22023' then null; end;
  begin perform public.e10_org_vendor_comment_projection(o,'not_a_document',po,20);
    raise exception 'invalid vendor kind accepted'; exception when sqlstate '22023' then null; end;
  begin perform public.e10_org_vendor_comment_projection(o,'purchase_order',po,101);
    raise exception 'oversized vendor page accepted'; exception when sqlstate '22023' then null; end;
  if internal_read::text not like '%SECRET DEAL NOTE%' or internal_read::text not like '%Deliver at loading bay A%'
    or internal_read::text not like '%Deliver at loading bay B%' then raise exception 'internal retained history incomplete: %',internal_read; end if;
  if vendor_output::text like '%SECRET DEAL NOTE%' or vendor_output::text like '%loading bay A%'
    or vendor_output::text not like '%loading bay B%' then raise exception 'vendor effective projection leaked or lost content: %',vendor_output; end if;
  if vendor_output ?| array['created_by','created_at','supersedes_comment_id','commercial_event_id','total_amount','currency','payload']
    or vendor_output::text like '%created_by%' or vendor_output::text like '%supersedes%'
    or vendor_output::text like '%commercial_event%' or vendor_output::text like '%total_amount%'
    or vendor_output::text like '%raw_%' then raise exception 'vendor projection returned forbidden metadata: %',vendor_output; end if;
  if vendor_output->>'document_status'<>'approved' or vendor_output->>'document_reference'<>'PO-X3E' then raise exception 'vendor allowlist missing document identity'; end if;
  begin
    perform public.e10_org_record_commercial_event_v2(o,'commercial_comment_changed',1,'receipt',
      'd3300000-0000-4000-8000-000000000016',now(),'exact','manual','forged','forged','forged','forged',null,
      'operator_asserted',jsonb_build_object('comment_id',gen_random_uuid(),'document_kind','stock_receipt',
        'document_id','d3300000-0000-4000-8000-000000000016','audience','vendor','operation','create'),null,'{}','x3e-forged-event');
    raise exception 'generic event writer forged comment history';
  exception when insufficient_privilege then null; end;
  insert into x3e_results values('original',original),('vendor1',vendor1),('vendor2',vendor2),('vendor_output',vendor_output);

  perform set_config('request.jwt.claims',jsonb_build_object('sub','d3300000-0000-4000-8000-000000000004','role','authenticated')::text,true);
  begin
    perform public.e10_org_add_commercial_comment(o,'purchase_order',po,'vendor','unauthorized',null,'x3e-low');
    raise exception 'member without prepare capability wrote comment';
  exception when insufficient_privilege then null; end;
  begin
    perform public.e10_org_list_commercial_comments('d3300000-0000-4000-8000-000000000002','purchase_order',po,20,null,null);
    raise exception 'foreign organization history read accepted';
  exception when insufficient_privilege then null; end;
  raise notice 'TA-X3e authenticated writer/read/projection behavior: PASS';
end $$;
reset role;

set constraints all immediate;
set constraints all deferred;

do $$
declare
  o uuid:='d3300000-0000-4000-8000-000000000001';
  po uuid:='d3300000-0000-4000-8000-000000000009';
  original uuid:=((select v from x3e_results where k='original')->>'comment_id')::uuid;
  vendor1 uuid:=((select v from x3e_results where k='vendor1')->>'comment_id')::uuid;
  vendor2 uuid:=((select v from x3e_results where k='vendor2')->>'comment_id')::uuid;
begin
  if (select count(*) from public.e10_commercial_comments where organization_id=o)<>6
    or (select count(*) from public.e10_commercial_comment_commands where organization_id=o)<>6
    or (select count(*) from public.e10_commercial_events where organization_id=o and event_type='commercial_comment_changed')<>6 then
    raise exception 'comment/command/event cardinality invalid';
  end if;
  if (select supersedes_comment_id from public.e10_commercial_comments where id=vendor2) is distinct from vendor1
    or exists(select 1 from public.e10_commercial_comments where id=original and commercial_event_id is null) then
    raise exception 'comment lineage or event linkage invalid';
  end if;
  if (select row(revision,status,approved_revision,approved_by,approved_at) from public.e10_purchase_orders where id=po)
      is distinct from row(7,'approved'::text,7,'d3300000-0000-4000-8000-000000000003'::uuid,'2026-09-11T12:00:00Z'::timestamptz) then
    raise exception 'comment changed financial revision or approval';
  end if;
  if (select row(revision,status,approved_revision,approved_by,approved_at) from public.e10_supplier_invoices where id='d3300000-0000-4000-8000-000000000015')
      is distinct from row(4,'approved'::text,4,'d3300000-0000-4000-8000-000000000003'::uuid,'2026-09-11T12:00:00Z'::timestamptz)
    or (select row(revision,status,approved_revision,approved_by,approved_at) from public.e10_supplier_credits where id='d3300000-0000-4000-8000-000000000017')
      is distinct from row(3,'approved'::text,3,'d3300000-0000-4000-8000-000000000003'::uuid,'2026-09-11T12:00:00Z'::timestamptz)
    or (select status from public.e10_stock_receipts where id='d3300000-0000-4000-8000-000000000016')<>'posted' then
    raise exception 'comments changed invoice, credit or receipt state';
  end if;
  begin update public.e10_commercial_comments set body='mutated' where id=original;
    raise exception 'append-only comment update accepted'; exception when sqlstate '55000' then null; end;
  if exists(select 1 from public.e10_commercial_events where organization_id=o and event_type='commercial_comment_changed'
      and payload ? 'body') then raise exception 'comment body leaked into commercial event'; end if;
  begin
    insert into public.e10_commercial_events(organization_id,event_type,event_schema_version,subject_type,subject_id,
      occurred_at,occurred_at_precision,idempotency_key,source_kind,evidence_quality,payload,created_by,request_fingerprint,
      commercial_comment_command_idempotency_key)
    values(o,'return',1,'other',po::text,now(),'exact','x3e-wrong-event-type','manual','operator_asserted',
      jsonb_build_object('return_id','forged'),'d3300000-0000-4000-8000-000000000003','forged','x3e-internal-create');
    raise exception 'comment command key attached to wrong event type';
  exception when sqlstate '23514' then null; end;
  begin
    insert into public.e10_commercial_events(organization_id,event_type,event_schema_version,subject_type,subject_id,
      occurred_at,occurred_at_precision,idempotency_key,source_kind,source_connection_id,source_reference,source_event_id,
      correlation_id,evidence_quality,payload,created_by,request_fingerprint,commercial_comment_command_idempotency_key)
    values(o,'commercial_comment_changed',1,'other',po::text,now(),'exact','x3e-bad-link','manual',
      'purchasing-comments','commercial_comment_command',gen_random_uuid()::text,'purchase_order:'||po::text,
      'operator_asserted',jsonb_build_object('comment_id',gen_random_uuid(),'document_kind','purchase_order',
        'document_id',po,'audience','internal','operation','create'),
      'd3300000-0000-4000-8000-000000000003','forged','x3e-internal-create');
    raise exception 'malformed comment event link accepted';
  exception when sqlstate '23514' then null; end;
  if has_table_privilege('authenticated','public.e10_commercial_comments','select')
    or has_table_privilege('authenticated','public.e10_commercial_comment_commands','select')
    or has_function_privilege('anon','public.e10_org_add_commercial_comment(uuid,text,uuid,text,text,uuid,text)','execute')
    or has_function_privilege('anon','public.e10_org_vendor_comment_projection(uuid,text,uuid,integer)','execute')
    or not has_function_privilege('authenticated','public.e10_org_add_commercial_comment(uuid,text,uuid,text,text,uuid,text)','execute')
    or has_function_privilege('authenticated','e10.guard_commercial_comment_command()','execute')
    or has_function_privilege('authenticated','e10.guard_commercial_comment_event()','execute') then
    raise exception 'X3e ACL closure failed';
  end if;
  raise notice 'TA-X3e durable lineage, approval preservation and ACL: PASS';
end $$;

rollback;
