// TA-X4b two-connection proof: one lot cannot be over-reserved under contention.
const { Client } = require('pg');
const { randomUUID } = require('crypto');
const CONN = process.env.E10_DB_URL || 'postgresql://postgres:postgres@127.0.0.1:54322/postgres';
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const ids = {
  user: randomUUID(), role: randomUUID(), lot: randomUUID(), lot2: randomUUID(), session: randomUUID(), supplier: randomUUID(),
  location: randomUUID(), product: randomUUID(), config: randomUUID(), item: `x4c-${randomUUID()}`, item2: `x4c-${randomUUID()}`,
};
const org = 'e1000000-0000-4000-8000-0000000000a6';
const jwt = JSON.stringify({ sub: ids.user, role: 'authenticated' });
const run = randomUUID();

async function cleanup(c) {
  // Superuser-only fixture teardown for the immutable audit table; production callers cannot do this.
  await c.query("set session_replication_role=replica");
  await c.query("delete from public.e10_lot_reservation_transitions where lot_reservation_id in (select id from public.e10_lot_reservations where lot_id=any($1::uuid[]))", [[ids.lot, ids.lot2]]);
  await c.query("set session_replication_role=origin");
  await c.query("delete from public.e10_lot_reservations where lot_id=any($1::uuid[])", [[ids.lot, ids.lot2]]);
  await c.query("delete from public.e10_inventory_reservations where item_id=any($1::text[])", [[ids.item, ids.item2]]);
  await c.query("delete from public.e10_inventory_movements where item_id=any($1::text[])", [[ids.item, ids.item2]]);
  await c.query("delete from public.e10_break_sessions where id=$1", [ids.session]);
  await c.query("delete from public.e10_inventory_lots where id=any($1::uuid[])", [[ids.lot, ids.lot2]]);
  await c.query("delete from public.e10_inventory_items where id=any($1::text[])", [[ids.item, ids.item2]]);
  await c.query("delete from public.e10_product_configuration_versions where id=$1", [ids.config]);
  await c.query("delete from public.e10_product_configurations where id=$1", [ids.config]);
  await c.query("delete from public.e10_product_masters where id=$1", [ids.product]);
  await c.query("delete from public.e10_locations where id=$1", [ids.location]);
  await c.query("delete from public.e10_suppliers where id=$1", [ids.supplier]);
  await c.query("delete from public.e10_organization_memberships where organization_id=$1 and user_id=$2", [org, ids.user]);
  await c.query("delete from public.e10_organization_roles where organization_id=$1 and id=$2", [org, ids.role]);
  await c.query("delete from auth.users where id=$1", [ids.user]);
}

async function main() {
  const setup = new Client({ connectionString: CONN }); const A = new Client({ connectionString: CONN }); const B = new Client({ connectionString: CONN });
  await setup.connect(); await A.connect(); await B.connect();
  try {
    await cleanup(setup);
    await setup.query(`insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at) values($1,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',$2,now(),now())`, [ids.user, `x4c-${run}@x.invalid`]);
    await setup.query(`insert into public.e10_organization_roles(id,organization_id,key,name,is_system) values($1,$2,$3,'X4c Test Role',false)`, [ids.role, org, `x4c-${run}`]);
    await setup.query(`insert into public.e10_organization_role_permissions(organization_id,role_id,capability,allowed) values($1,$2,'act.reserve_inventory',true),($1,$2,'act.inventory_edit',true)`, [org, ids.role]);
    await setup.query(`insert into public.e10_organization_memberships(organization_id,user_id,role_id,status) values($1,$2,$3,'active')`, [org, ids.user, ids.role]);
    await setup.query(`insert into public.e10_suppliers(id,organization_id,name) values($1,$2,'X4c Supplier')`, [ids.supplier, org]);
    await setup.query(`insert into public.e10_locations(id,organization_id,name) values($1,$2,'X4c Location')`, [ids.location, org]);
    await setup.query(`insert into public.e10_product_masters(id,organization_id,name) values($1,$2,'X4c Product')`, [ids.product, org]);
    await setup.query(`insert into public.e10_product_configurations(id,organization_id,product_master_id,name) values($1,$2,$3,'Each')`, [ids.config, org, ids.product]);
    await setup.query(`insert into public.e10_product_configuration_versions(id,organization_id,configuration_id,version_no,state,packaging_kind,base_unit,base_units_per_package) values($1,$2,$1,1,'active','each','each',1)`, [ids.config, org]);
    await setup.query(`insert into public.e10_inventory_items(id,name,qty,organization_id) values($1,'X4c Item',5,$2)`, [ids.item, org]);
    await setup.query(`insert into public.e10_inventory_items(id,name,qty,organization_id) values($1,'X4c Item 2',5,$2)`, [ids.item2, org]);
    await setup.query(`insert into public.e10_inventory_lots(id,organization_id,configuration_version_id,location_id,supplier_id,inventory_item_id,status,accepted_quantity) values($1,$2,$3,$4,$5,$6,'available',5)`, [ids.lot, org, ids.config, ids.location, ids.supplier, ids.item]);
    await setup.query(`insert into public.e10_inventory_lots(id,organization_id,configuration_version_id,location_id,supplier_id,inventory_item_id,status,accepted_quantity) values($1,$2,$3,$4,$5,$6,'available',5)`, [ids.lot2, org, ids.config, ids.location, ids.supplier, ids.item2]);
    await setup.query(`insert into public.e10_break_sessions(id,name,streamer_uid,organization_id,source_show_ref) values($1,'X4c Session',$2,$3,'x4c-show')`, [ids.session, ids.user, org]);
    await A.query('begin'); await A.query('select set_config($1,$2,true)', ['request.jwt.claims', jwt]);
    await A.query("select pg_advisory_xact_lock(hashtextextended($1||'|lot|'||$2,0))", [org, ids.lot]);
    await B.query('begin'); await B.query('select set_config($1,$2,true)', ['request.jwt.claims', jwt]);
    const bpid = (await B.query('select pg_backend_pid() pid')).rows[0].pid;
    let bError; const bCall = B.query('select public.e10_org_lot_reserve($1,$2,4,$3,$4)', [org, ids.lot, ids.session, `x4c-b-${run}`]).catch((e) => { bError = e; });
    let waiting = false;
    for (let i = 0; i < 400; i++) { const q = await setup.query("select wait_event_type='Lock' waiting from pg_stat_activity where pid=$1", [bpid]); if (q.rows[0]?.waiting) { waiting = true; break; } await sleep(10); }
    if (!waiting) throw new Error('B never waited on the lot row lock');
    const pre = (await A.query(`select i.qty,(select coalesce(sum(r.qty),0) from public.e10_inventory_reservations r where r.organization_id=$1 and r.item_id=$2 and r.status='active') item_reserved,l.accepted_quantity,(select coalesce(sum(case when lr.status='active' then lr.quantity else 0 end),0)+coalesce(sum(lr.consumed_quantity),0) from public.e10_lot_reservations lr where lr.organization_id=$1 and lr.lot_id=$3) lot_used from public.e10_inventory_items i join public.e10_inventory_lots l on l.organization_id=i.organization_id and l.inventory_item_id=i.id where i.organization_id=$1 and i.id=$2`, [org, ids.item, ids.lot])).rows[0];
    if (Number(pre.qty) !== 5 || Number(pre.item_reserved) !== 0 || Number(pre.accepted_quantity) !== 5 || Number(pre.lot_used) !== 0) throw new Error('dirty precondition: ' + JSON.stringify(pre));
    const a = (await A.query('select public.e10_org_lot_reserve($1,$2,4,$3,$4) result', [org, ids.lot, ids.session, `x4c-a-${run}`])).rows[0].result;
    await A.query('commit'); await bCall; await B.query('rollback').catch(() => {});
    if (!a.ok || !bError || bError.code !== '23514') throw new Error(`unexpected outcomes A=${JSON.stringify(a)} B=${bError && bError.code}`);
    const proof = (await setup.query(`select coalesce(sum(quantity),0) lot_reserved,(select coalesce(sum(qty),0) from public.e10_inventory_reservations where organization_id=$1 and item_id=$2 and status='active') legacy_reserved,(select count(*) from public.e10_inventory_movements where organization_id=$1 and item_id=$2) movements from public.e10_lot_reservations where organization_id=$1 and lot_id=$3 and status='active'`, [org, ids.item, ids.lot])).rows[0];
    if (Number(proof.lot_reserved) !== 4 || Number(proof.legacy_reserved) !== 4 || Number(proof.movements) !== 1) throw new Error('reservation ledgers diverged: ' + JSON.stringify(proof));
    // Serialize consume versus release on the same reservation. Consume wins first; release must then release only the remainder.
    const reservationId = a.reservation_id;
    await A.query('begin'); await A.query('select set_config($1,$2,true)', ['request.jwt.claims', jwt]);
    await A.query('select id from public.e10_lot_reservations where organization_id=$1 and id=$2 for update', [org, reservationId]);
    await B.query('begin'); await B.query('select set_config($1,$2,true)', ['request.jwt.claims', jwt]);
    const releaseCall = B.query('select public.e10_org_lot_release($1,$2,$3) result', [org, reservationId, `x4c-release-${run}`]);
    let transitionWaiting = false;
    for (let i = 0; i < 400; i++) { const q = await setup.query("select wait_event_type='Lock' waiting from pg_stat_activity where pid=$1", [bpid]); if (q.rows[0]?.waiting) { transitionWaiting = true; break; } await sleep(10); }
    if (!transitionWaiting) throw new Error('release never waited on consume-held reservation lock');
    const consume = (await A.query('select public.e10_org_lot_consume($1,$2,1,$3) result', [org, reservationId, `x4c-consume-${run}`])).rows[0].result;
    await A.query('commit');
    const release = (await releaseCall).rows[0].result; await B.query('commit');
    if (!consume.ok || !release.ok || Number(release.released_quantity) !== 3 || Number(release.consumed_quantity) !== 1) throw new Error(`transition race diverged consume=${JSON.stringify(consume)} release=${JSON.stringify(release)}`);
    const transitionProof = (await setup.query('select status,consumed_quantity,(select qty from public.e10_inventory_items where organization_id=$1 and id=$3) on_hand,(select count(*) from e10.lot_transition_guards) guards from public.e10_lot_reservations where organization_id=$1 and id=$2', [org, reservationId, ids.item])).rows[0];
    if (transitionProof.status !== 'released' || Number(transitionProof.consumed_quantity) !== 1 || Number(transitionProof.on_hand) !== 4 || Number(transitionProof.guards) !== 0) throw new Error('serialized transition state wrong: ' + JSON.stringify(transitionProof));
    // Overlap the new writer with the existing legacy writer on their shared item lock.
    await A.query('begin'); await A.query('select set_config($1,$2,true)', ['request.jwt.claims', jwt]);
    const heldItem = await A.query('select id from public.e10_inventory_items where organization_id=$1 and id=$2 for update', [org, ids.item2]);
    if (heldItem.rowCount !== 1) throw new Error('failed to lock shared inventory item');
    await B.query('begin'); await B.query('select set_config($1,$2,true)', ['request.jwt.claims', jwt]);
    let bLegacyError; const bAgainstLegacy = B.query('select public.e10_org_lot_reserve($1,$2,4,$3,$4)', [org, ids.lot2, ids.session, `x4c-new-against-legacy-${run}`]).catch((e) => { bLegacyError = e; });
    let waitingOnLegacy = false;
    for (let i = 0; i < 400; i++) { const q = await setup.query("select wait_event_type='Lock' waiting from pg_stat_activity where pid=$1", [bpid]); if (q.rows[0]?.waiting) { waitingOnLegacy = true; break; } await sleep(10); }
    if (!waitingOnLegacy) throw new Error('new writer never waited on legacy-held item lock');
    const legacy = (await A.query("select public.e10_org_inv_reserve($1,$2,'x4c-show','X4c Session',4,$3) result", [org, ids.item2, `x4c-legacy-${run}`])).rows[0].result;
    await A.query('commit'); await bAgainstLegacy; await B.query('rollback').catch(() => {});
    if (!legacy.ok || !bLegacyError || bLegacyError.code !== '23514') throw new Error(`legacy overlap outcomes legacy=${JSON.stringify(legacy)} new=${bLegacyError && bLegacyError.code}`);
    const overlap = (await setup.query(`select (select count(*) from public.e10_lot_reservations where lot_id=$1) lot_rows,(select coalesce(sum(qty),0) from public.e10_inventory_reservations where organization_id=$2 and item_id=$3 and status='active') legacy_reserved`, [ids.lot2, org, ids.item2])).rows[0];
    if (Number(overlap.lot_rows) !== 0 || Number(overlap.legacy_reserved) !== 4) throw new Error('legacy overlap diverged: ' + JSON.stringify(overlap));
    console.log(`TA-X4b/X4c concurrency: PASS (reserve contention, consume/release serialization, legacy/new overlap; no overcommit; ledgers reconciled)`);
  } finally {
    await A.query('rollback').catch(() => {}); await B.query('rollback').catch(() => {});
    await cleanup(setup);
    await A.end(); await B.end(); await setup.end();
  }
}
main().catch((e) => { console.error('TA-X4b concurrent test ERROR: ' + (e.stack || e.message)); process.exit(1); });
