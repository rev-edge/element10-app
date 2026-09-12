#!/usr/bin/env bash
# Two-connection proof for e10_org_receive_po_line / e10_org_reverse_receipt (X3c wrappers over X4d bodies).
set -u
export PGPASSWORD=postgres
PSQL="psql -X -q -At -h 127.0.0.1 -p 54323 -U postgres -d postgres"
ORG=e1000000-0000-4000-8000-0000000000a6
U=fa5e0000-0000-4000-8000-00000000d001
ROLE=fa5e0000-0000-4000-8000-00000000d002
SUP=fa5e0000-0000-4000-8000-00000000d003
LOC=fa5e0000-0000-4000-8000-00000000d004
PROD=fa5e0000-0000-4000-8000-00000000d005
CFG=fa5e0000-0000-4000-8000-00000000d006
PO=fa5e0000-0000-4000-8000-00000000d007
POL=fa5e0000-0000-4000-8000-00000000d008
ITEM=stale-auth-item-d009
JWT='{"sub":"fa5e0000-0000-4000-8000-00000000d001","role":"authenticated"}'
OUT=/tmp/claude-0/-home-user-element10-app/b90b77d6-92f2-5418-b94f-f7ae6750dc5a/scratchpad

cleanup() {
$PSQL <<SQL
set session_replication_role=replica;
delete from public.e10_integration_outbox where commercial_event_id in (select id from public.e10_commercial_events where organization_id='$ORG' and subject_type='inventory_item' and subject_id='$ITEM');
delete from public.e10_commercial_events where organization_id='$ORG' and subject_type='inventory_item' and subject_id='$ITEM';
delete from public.e10_expected_allocation_events where organization_id='$ORG' and receipt_line_id in (select id from public.e10_stock_receipt_lines where organization_id='$ORG' and stock_receipt_id in (select id from public.e10_stock_receipts where organization_id='$ORG' and supplier_id='$SUP'));
delete from public.e10_stock_receipt_reversals where organization_id='$ORG' and stock_receipt_id in (select id from public.e10_stock_receipts where organization_id='$ORG' and supplier_id='$SUP');
delete from public.e10_receipt_po_allocations where organization_id='$ORG' and purchase_order_line_id='$POL';
delete from public.e10_stock_receipt_lines where organization_id='$ORG' and stock_receipt_id in (select id from public.e10_stock_receipts where organization_id='$ORG' and supplier_id='$SUP');
delete from public.e10_inventory_lots where organization_id='$ORG' and inventory_item_id='$ITEM';
delete from public.e10_stock_receipts where organization_id='$ORG' and supplier_id='$SUP';
delete from public.e10_inventory_movements where organization_id='$ORG' and item_id='$ITEM';
delete from public.e10_inventory_items where id='$ITEM' and organization_id='$ORG';
delete from public.e10_purchase_order_revisions where organization_id='$ORG' and purchase_order_id='$PO';
delete from public.e10_purchase_order_lines where organization_id='$ORG' and purchase_order_id='$PO';
delete from public.e10_purchase_orders where organization_id='$ORG' and id='$PO';
delete from public.e10_product_configuration_versions where id='$CFG';
delete from public.e10_product_configurations where id='$CFG';
delete from public.e10_product_masters where id='$PROD';
delete from public.e10_location_role_permissions where location_id='$LOC';
delete from public.e10_locations where id='$LOC';
delete from public.e10_suppliers where id='$SUP';
delete from public.e10_organization_memberships where organization_id='$ORG' and user_id='$U';
delete from public.e10_organization_role_permissions where organization_id='$ORG' and role_id='$ROLE';
delete from public.e10_organization_roles where organization_id='$ORG' and id='$ROLE';
delete from auth.users where id='$U';
set session_replication_role=origin;
SQL
}
residue() {
$PSQL -c "select 'residue rows: '||((select count(*) from public.e10_stock_receipts where supplier_id='$SUP')+(select count(*) from public.e10_inventory_lots where inventory_item_id='$ITEM')+(select count(*) from public.e10_inventory_items where id='$ITEM')+(select count(*) from auth.users where id='$U')+(select count(*) from public.e10_inventory_movements where item_id='$ITEM')+(select count(*) from public.e10_commercial_events where subject_id='$ITEM')+(select count(*) from public.e10_purchase_orders where id='$PO')+(select count(*) from public.e10_organization_roles where id='$ROLE'))"
}

cleanup >/dev/null 2>&1
echo "== setup (committed fixture in org0: approved PO with one line, user with create_receiving+resolve_recovery and location grant)"
$PSQL <<SQL
insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at) values('$U','00000000-0000-0000-0000-000000000000','authenticated','authenticated','stale-auth-d@x.invalid',now(),now());
insert into public.e10_organization_roles(id,organization_id,key,name,is_system) values('$ROLE','$ORG','stale-auth-role-d','Stale auth role D',false);
insert into public.e10_organization_role_permissions(organization_id,role_id,capability,allowed) values('$ORG','$ROLE','act.create_receiving',true),('$ORG','$ROLE','act.resolve_recovery',true);
insert into public.e10_organization_memberships(organization_id,user_id,role_id,status) values('$ORG','$U','$ROLE','active');
insert into public.e10_suppliers(id,organization_id,name) values('$SUP','$ORG','Stale Supplier D');
insert into public.e10_locations(id,organization_id,name) values('$LOC','$ORG','Stale Location D');
insert into public.e10_location_role_permissions(organization_id,location_id,role_id,can_receive) values('$ORG','$LOC','$ROLE',true);
insert into public.e10_product_masters(id,organization_id,name) values('$PROD','$ORG','Stale Product D');
insert into public.e10_product_configurations(id,organization_id,product_master_id,name) values('$CFG','$ORG','$PROD','Each');
insert into public.e10_product_configuration_versions(id,organization_id,configuration_id,version_no,state,packaging_kind,base_unit,base_units_per_package) values('$CFG','$ORG','$CFG',1,'active','each','each',1);
insert into public.e10_inventory_items(id,name,qty,organization_id) values('$ITEM','Stale Item D',0,'$ORG');
insert into public.e10_purchase_orders(id,organization_id,supplier_id,destination_location_id,order_number,revision,status,currency,created_by) values('$PO','$ORG','$SUP','$LOC','STALE-PO-D',1,'approved','CAD','$U');
insert into public.e10_purchase_order_lines(id,organization_id,purchase_order_id,configuration_version_id,line_no,ordered_quantity,state) values('$POL','$ORG','$PO','$CFG',1,10,'active');
SQL

race() { # $1 label, $2 sql held by S1, $3 call by S2, $4 capability to revoke, $5 commit|rollback for S2
  local label=$1 hold=$2 call=$3 cap=$4 fin=$5
  $PSQL -c "update public.e10_organization_role_permissions set allowed=true where organization_id='$ORG' and role_id='$ROLE'" >/dev/null
  $PSQL -c "begin; $hold; select pg_sleep(6); rollback;" >/dev/null 2>&1 &
  S1=$!
  sleep 1
  $PSQL -o "$OUT/race_$label.out" <<SQL 2>&1 &
begin;
set role authenticated;
select set_config('request.jwt.claims','$JWT',true);
select $call as result;
$fin;
SQL
  S2=$!
  sleep 1.5
  $PSQL -c "select 'S2 state before revocation: wait_event_type='||coalesce(wait_event_type,'none')||' query='||left(regexp_replace(query,'\s+',' ','g'),60) from pg_stat_activity where state='active' and query ilike '%public.e10_org_re%' and pid<>pg_backend_pid()"
  $PSQL -c "update public.e10_organization_role_permissions set allowed=false where organization_id='$ORG' and role_id='$ROLE' and capability='$cap'" >/dev/null
  $PSQL -c "select 'after S3 commit: '||string_agg(capability||'='||allowed,',') from public.e10_organization_role_permissions where organization_id='$ORG' and role_id='$ROLE'"
  wait $S1; wait $S2
  echo "--- S2 outcome ($label):"; cat "$OUT/race_$label.out"
}

echo
echo "== RACE 6: e10_org_receive_po_line — S1 holds inventory_items row FOR UPDATE; S3 revokes act.create_receiving while S2 waits (S2 commits)"
race receive "select 1 from public.e10_inventory_items where organization_id='$ORG' and id='$ITEM' for update" "public.e10_org_receive_po_line('$ORG','$POL','$ITEM',3,0,0,null,now(),'[]'::jsonb,'stale-receive-1')" act.create_receiving commit
$PSQL -c "select 'post-race: receipts='||(select count(*) from public.e10_stock_receipts where organization_id='$ORG' and supplier_id='$SUP' and status='posted')||' item qty='||(select qty from public.e10_inventory_items where id='$ITEM')||' movements='||(select count(*) from public.e10_inventory_movements where item_id='$ITEM')"
RCPT=$($PSQL -c "select id from public.e10_stock_receipts where organization_id='$ORG' and supplier_id='$SUP' and status='posted' limit 1")
echo "receipt=$RCPT"

echo
echo "== RACE 7: e10_org_reverse_receipt — S1 holds the stock_receipts row FOR UPDATE; S3 revokes act.resolve_recovery while S2 waits (S2 commits)"
race reverse "select 1 from public.e10_stock_receipts where organization_id='$ORG' and id='$RCPT' for update" "public.e10_org_reverse_receipt('$ORG','$RCPT','stale reason','stale-reverse-1')" act.resolve_recovery commit
$PSQL -c "select 'post-race: receipt status='||(select status from public.e10_stock_receipts where id='$RCPT')||' item qty='||(select qty from public.e10_inventory_items where id='$ITEM')||' reversals='||(select count(*) from public.e10_stock_receipt_reversals where stock_receipt_id='$RCPT')"

echo
echo "== cleanup"
cleanup >/dev/null 2>&1
residue
