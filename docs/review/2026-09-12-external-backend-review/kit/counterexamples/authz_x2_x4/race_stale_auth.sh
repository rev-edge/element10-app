#!/usr/bin/env bash
# Two-connection proof: does a lot writer recheck membership after waiting on a lock?
# Fixture is committed into org0 with unique ids and removed at the end (same pattern as tests/ta_x4b_lot_reserve_concurrent_test.js).
set -u
export PGPASSWORD=postgres
PSQL="psql -X -q -At -h 127.0.0.1 -p 54323 -U postgres -d postgres"
ORG=e1000000-0000-4000-8000-0000000000a6
U=fa5e0000-0000-4000-8000-00000000c001
ROLE=fa5e0000-0000-4000-8000-00000000c002
SUP=fa5e0000-0000-4000-8000-00000000c003
LOC=fa5e0000-0000-4000-8000-00000000c004
PROD=fa5e0000-0000-4000-8000-00000000c005
CFG=fa5e0000-0000-4000-8000-00000000c006
LOT=fa5e0000-0000-4000-8000-00000000c007
SESS=fa5e0000-0000-4000-8000-00000000c008
SESS2=fa5e0000-0000-4000-8000-00000000c00a
ITEM=stale-auth-item-c009
JWT='{"sub":"fa5e0000-0000-4000-8000-00000000c001","role":"authenticated"}'
OUT=/tmp/claude-0/-home-user-element10-app/b90b77d6-92f2-5418-b94f-f7ae6750dc5a/scratchpad

cleanup() {
$PSQL <<SQL
set session_replication_role=replica;
delete from public.e10_lot_reservation_transitions where organization_id='$ORG' and lot_reservation_id in (select id from public.e10_lot_reservations where lot_id='$LOT');
delete from public.e10_integration_outbox where commercial_event_id in (select id from public.e10_commercial_events where organization_id='$ORG' and subject_type='inventory_item' and subject_id='$ITEM');
delete from public.e10_commercial_events where organization_id='$ORG' and subject_type='inventory_item' and subject_id='$ITEM';
set session_replication_role=origin;
delete from public.e10_lot_reservations where organization_id='$ORG' and lot_id='$LOT';
delete from public.e10_inventory_reservations where organization_id='$ORG' and item_id='$ITEM';
delete from public.e10_inventory_movements where organization_id='$ORG' and item_id='$ITEM';
delete from public.e10_break_sessions where id in ('$SESS','$SESS2');
delete from public.e10_inventory_lots where id='$LOT';
delete from public.e10_inventory_items where id='$ITEM' and organization_id='$ORG';
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
SQL
}
residue() {
$PSQL -c "select 'residue rows: '||((select count(*) from public.e10_lot_reservations where lot_id='$LOT')+(select count(*) from public.e10_inventory_lots where id='$LOT')+(select count(*) from public.e10_inventory_items where id='$ITEM')+(select count(*) from auth.users where id='$U')+(select count(*) from public.e10_inventory_movements where item_id='$ITEM')+(select count(*) from public.e10_commercial_events where subject_id='$ITEM')+(select count(*) from public.e10_organization_roles where id='$ROLE'))"
}

cleanup >/dev/null 2>&1
echo "== setup (committed fixture in org0)"
$PSQL <<SQL
insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at) values('$U','00000000-0000-0000-0000-000000000000','authenticated','authenticated','stale-auth@x.invalid',now(),now());
insert into public.e10_organization_roles(id,organization_id,key,name,is_system) values('$ROLE','$ORG','stale-auth-role','Stale auth role',false);
insert into public.e10_organization_role_permissions(organization_id,role_id,capability,allowed) values('$ORG','$ROLE','act.reserve_inventory',true),('$ORG','$ROLE','act.inventory_edit',true);
insert into public.e10_organization_memberships(organization_id,user_id,role_id,status) values('$ORG','$U','$ROLE','active');
insert into public.e10_suppliers(id,organization_id,name) values('$SUP','$ORG','Stale Supplier');
insert into public.e10_locations(id,organization_id,name) values('$LOC','$ORG','Stale Location');
insert into public.e10_product_masters(id,organization_id,name) values('$PROD','$ORG','Stale Product');
insert into public.e10_product_configurations(id,organization_id,product_master_id,name) values('$CFG','$ORG','$PROD','Each');
insert into public.e10_product_configuration_versions(id,organization_id,configuration_id,version_no,state,packaging_kind,base_unit,base_units_per_package) values('$CFG','$ORG','$CFG',1,'active','each','each',1);
insert into public.e10_inventory_items(id,name,qty,organization_id) values('$ITEM','Stale Item',10,'$ORG');
insert into public.e10_inventory_lots(id,organization_id,configuration_version_id,location_id,supplier_id,inventory_item_id,status,accepted_quantity) values('$LOT','$ORG','$CFG','$LOC','$SUP','$ITEM','available',10);
insert into public.e10_break_sessions(id,name,streamer_uid,organization_id,source_show_ref) values('$SESS','Stale Session','$U','$ORG','stale-show'),('$SESS2','Stale Session 2','$U','$ORG','stale-show-2');
SQL
RES=$($PSQL <<SQL
begin;
set role authenticated;
select set_config('request.jwt.claims','$JWT',true);
select 'RESID='||(public.e10_org_lot_reserve('$ORG','$LOT',4,'$SESS','stale-reserve')->>'reservation_id');
commit;
SQL
)
RES=$(echo "$RES" | grep -o 'RESID=.*' | cut -d= -f2)
echo "reservation_id=$RES"

race() { # $1 label, $2 sql held by S1 (row lock), $3 sql call by S2, $4 revocation mode
  local label=$1 hold=$2 call=$3 mode=$4
  $PSQL -c "update public.e10_organization_memberships set status='active' where organization_id='$ORG' and user_id='$U'; update public.e10_organization_role_permissions set allowed=true where organization_id='$ORG' and role_id='$ROLE'" >/dev/null
  # S1: hold a row lock for 6s
  $PSQL -c "begin; $hold; select pg_sleep(6); rollback;" >/dev/null 2>&1 &
  S1=$!
  sleep 1
  # S2: authenticated caller; blocks behind S1
  $PSQL -o "$OUT/race_$label.out" <<SQL 2>&1 &
select pg_backend_pid() as s2_pid;
begin;
set role authenticated;
select set_config('request.jwt.claims','$JWT',true);
select $call as result;
rollback;
SQL
  S2=$!
  sleep 1.5
  # S3: while S2 waits, revoke membership (committed) and report S2's wait state
  $PSQL -c "select 'S2 state while membership still active: pid='||pid||' wait_event_type='||coalesce(wait_event_type,'none')||' query='||left(regexp_replace(query,'\s+',' ','g'),70) from pg_stat_activity where state='active' and query ilike '%public.e10_org_lot_%' and pid<>pg_backend_pid()"
  if [ "$mode" = membership ]; then
    $PSQL -c "update public.e10_organization_memberships set status='suspended' where organization_id='$ORG' and user_id='$U'" >/dev/null
  else
    $PSQL -c "update public.e10_organization_role_permissions set allowed=false where organization_id='$ORG' and role_id='$ROLE'" >/dev/null
  fi
  $PSQL -c "select 'after S3 commit ($mode revoked): membership='||(select status from public.e10_organization_memberships where organization_id='$ORG' and user_id='$U')||' caps_allowed='||(select string_agg(capability||'='||allowed,',') from public.e10_organization_role_permissions where organization_id='$ORG' and role_id='$ROLE')"
  wait $S1; wait $S2
  echo "--- S2 outcome ($label):"; cat "$OUT/race_$label.out"
}

echo
echo "== RACE 1: e10_org_lot_consume (X4c) — S1 holds lot_reservations row FOR UPDATE; S3 revokes act.inventory_edit CAPABILITY while S2 waits"
race consume "select 1 from public.e10_lot_reservations where id='$RES' for update" "public.e10_org_lot_consume('$ORG','$RES',1,'stale-consume-1')" capability
$PSQL -c "select 'post-race state: lot_reservation consumed_quantity='||consumed_quantity||' status='||status||'; item qty='||(select qty from public.e10_inventory_items where id='$ITEM')||'; transitions='||(select count(*) from public.e10_lot_reservation_transitions where lot_reservation_id='$RES') from public.e10_lot_reservations where id='$RES'"

echo
echo "== RACE 2: e10_org_lot_release (X4c) — S3 revokes act.inventory_edit CAPABILITY while S2 waits"
race release "select 1 from public.e10_lot_reservations where id='$RES' for update" "public.e10_org_lot_release('$ORG','$RES','stale-release-1')" capability
$PSQL -c "select 'post-race state: lot_reservation status='||status from public.e10_lot_reservations where id='$RES'"

echo
echo "== RACE 3 (control): e10_org_lot_reserve_for_demand (X4h) — S1 holds inventory_items row; S3 revokes act.reserve_inventory CAPABILITY"
race demand "select 1 from public.e10_inventory_items where organization_id='$ORG' and id='$ITEM' for update" "public.e10_org_lot_reserve_for_demand('$ORG','$LOT',1,'manual','ref-1','label','stale-demand-1')" capability

echo
echo "== RACE 4: e10_org_lot_reserve (X4g wrapper over X4b), second break session — S1 holds inventory_items row; S3 suspends MEMBERSHIP"
race reserve "select 1 from public.e10_inventory_items where organization_id='$ORG' and id='$ITEM' for update" "public.e10_org_lot_reserve('$ORG','$LOT',1,'$SESS2','stale-reserve-2')" membership

echo
echo "== RACE 5: e10_org_lot_reserve — S1 holds inventory_items row; S3 revokes act.reserve_inventory CAPABILITY"
race reserve2 "select 1 from public.e10_inventory_items where organization_id='$ORG' and id='$ITEM' for update" "public.e10_org_lot_reserve('$ORG','$LOT',1,'$SESS2','stale-reserve-3')" capability

echo
echo "== cleanup"
cleanup >/dev/null 2>&1
residue
