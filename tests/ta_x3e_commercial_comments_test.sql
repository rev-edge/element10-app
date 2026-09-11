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
  supplier uuid:='d3300000-0000-4000-8000-000000000007';
  location_id uuid:='d3300000-0000-4000-8000-000000000008';
  po uuid:='d3300000-0000-4000-8000-000000000009';
begin
  insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at) values
    (actor,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','x3e-writer@example.invalid',now(),now()),
    (low_actor,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','x3e-low@example.invalid',now(),now());
  insert into public.e10_organizations(id,name,slug) values(o,'X3e org','x3e-org'),(foreign_org,'X3e foreign','x3e-foreign');
  insert into public.e10_organization_roles(id,organization_id,key,name) values
    (role_id,o,'x3e-writer','X3e writer'),(low_role,o,'x3e-low','X3e low');
  insert into public.e10_organization_memberships(organization_id,user_id,role_id,status) values
    (o,actor,role_id,'active'),(o,low_actor,low_role,'active');
  insert into public.e10_organization_role_permissions(organization_id,role_id,capability,allowed)
    values(o,role_id,'act.purchasing_prepare',true);
  insert into public.e10_suppliers(id,organization_id,name,status) values(supplier,o,'X3e supplier','active');
  insert into public.e10_locations(id,organization_id,name,status) values(location_id,o,'X3e location','active');
  insert into public.e10_purchase_orders(id,organization_id,supplier_id,destination_location_id,order_number,status,currency,revision,created_by)
    values(po,o,supplier,location_id,'PO-X3E','approved','CAD',7,actor);
end $$;

create temp table x3e_results(k text primary key,v jsonb);
grant select,insert on x3e_results to authenticated;

set local role authenticated;
do $$
declare
  o uuid:='d3300000-0000-4000-8000-000000000001';
  po uuid:='d3300000-0000-4000-8000-000000000009';
  original jsonb; replay jsonb; vendor1 jsonb; vendor2 jsonb; internal_read jsonb; vendor_output jsonb;
begin
  perform set_config('request.jwt.claims',jsonb_build_object('sub','d3300000-0000-4000-8000-000000000003','role','authenticated')::text,true);
  original:=public.e10_org_add_commercial_comment(o,'purchase_order',po,'internal',
    'SECRET DEAL NOTE: never vendor-visible',null,'x3e-internal-create');
  replay:=public.e10_org_add_commercial_comment(o,'purchase_order',po,'internal',
    'SECRET DEAL NOTE: never vendor-visible',null,'x3e-internal-create');
  if replay->>'replay'<>'true' or replay->>'comment_id'<>original->>'comment_id' then raise exception 'comment replay failed: %',replay; end if;
  vendor1:=public.e10_org_add_commercial_comment(o,'purchase_order',po,'vendor',
    'Deliver at loading bay A',null,'x3e-vendor-create');
  vendor2:=public.e10_org_add_commercial_comment(o,'purchase_order',po,'vendor',
    'Deliver at loading bay B',(vendor1->>'comment_id')::uuid,'x3e-vendor-amend');
  begin
    perform public.e10_org_add_commercial_comment(o,'purchase_order',po,'internal','bad audience chain',
      (vendor2->>'comment_id')::uuid,'x3e-cross-audience');
    raise exception 'cross-audience supersession accepted';
  exception when sqlstate '22023' then null; end;
  begin
    perform public.e10_org_add_commercial_comment(o,'purchase_order',po,'vendor',' ',null,'x3e-blank');
    raise exception 'blank comment accepted';
  exception when sqlstate '22023' then null; end;
  begin
    perform public.e10_org_add_commercial_comment(o,'purchase_order',po,'vendor',repeat('x',4001),null,'x3e-long');
    raise exception 'oversized comment accepted';
  exception when sqlstate '22023' then null; end;

  internal_read:=public.e10_org_list_commercial_comments(o,'purchase_order',po,20,null,null);
  vendor_output:=public.e10_org_vendor_comment_projection(o,'purchase_order',po,20);
  if internal_read::text not like '%SECRET DEAL NOTE%' or internal_read::text not like '%Deliver at loading bay A%'
    or internal_read::text not like '%Deliver at loading bay B%' then raise exception 'internal retained history incomplete: %',internal_read; end if;
  if vendor_output::text like '%SECRET DEAL NOTE%' or vendor_output::text like '%loading bay A%'
    or vendor_output::text not like '%loading bay B%' then raise exception 'vendor effective projection leaked or lost content: %',vendor_output; end if;
  if vendor_output ?| array['created_by','created_at','supersedes_comment_id','commercial_event_id','total_amount','currency','payload']
    or vendor_output::text like '%created_by%' or vendor_output::text like '%supersedes%'
    or vendor_output::text like '%commercial_event%' or vendor_output::text like '%total_amount%'
    or vendor_output::text like '%raw_%' then raise exception 'vendor projection returned forbidden metadata: %',vendor_output; end if;
  if vendor_output->>'document_status'<>'approved' or vendor_output->>'document_reference'<>'PO-X3E' then raise exception 'vendor allowlist missing document identity'; end if;
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
  if (select count(*) from public.e10_commercial_comments where organization_id=o)<>3
    or (select count(*) from public.e10_commercial_comment_commands where organization_id=o)<>3
    or (select count(*) from public.e10_commercial_events where organization_id=o and event_type='commercial_comment_changed')<>3 then
    raise exception 'comment/command/event cardinality invalid';
  end if;
  if (select supersedes_comment_id from public.e10_commercial_comments where id=vendor2) is distinct from vendor1
    or exists(select 1 from public.e10_commercial_comments where id=original and commercial_event_id is null) then
    raise exception 'comment lineage or event linkage invalid';
  end if;
  if (select revision from public.e10_purchase_orders where id=po)<>7
    or (select status from public.e10_purchase_orders where id=po)<>'approved' then
    raise exception 'comment changed financial revision or approval';
  end if;
  if exists(select 1 from public.e10_commercial_events where organization_id=o and event_type='commercial_comment_changed'
      and payload ? 'body') then raise exception 'comment body leaked into commercial event'; end if;
  if has_table_privilege('authenticated','public.e10_commercial_comments','select')
    or has_table_privilege('authenticated','public.e10_commercial_comment_commands','select')
    or has_function_privilege('anon','public.e10_org_add_commercial_comment(uuid,text,uuid,text,text,uuid,text)','execute')
    or has_function_privilege('anon','public.e10_org_vendor_comment_projection(uuid,text,uuid,integer)','execute')
    or not has_function_privilege('authenticated','public.e10_org_add_commercial_comment(uuid,text,uuid,text,text,uuid,text)','execute')
    or has_function_privilege('authenticated','e10.guard_commercial_comment_command()','execute') then
    raise exception 'X3e ACL closure failed';
  end if;
  raise notice 'TA-X3e durable lineage, approval preservation and ACL: PASS';
end $$;

rollback;
