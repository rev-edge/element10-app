// TA-X4h two-connection proof for generic, non-session lot demand.
const { Client } = require('pg');
const { randomUUID } = require('crypto');
const CONN = process.env.E10_DB_URL || 'postgresql://postgres:postgres@127.0.0.1:54322/postgres';
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
const org = 'e1000000-0000-4000-8000-0000000000a6';
const ids = { user: randomUUID(), role: randomUUID(), supplier: randomUUID(), location: randomUUID(), product: randomUUID(), config: randomUUID(), lot: randomUUID(), lot2: randomUUID(), item: `x4h-${randomUUID()}`, item2: `x4h-${randomUUID()}` };
const jwt = JSON.stringify({ sub: ids.user, role: 'authenticated' });
const run = randomUUID();

async function waitForLock(observer, pid, label) {
  for (let i = 0; i < 500; i++) {
    const q = await observer.query("select wait_event_type='Lock' waiting from pg_stat_activity where pid=$1", [pid]);
    if (q.rows[0]?.waiting) return;
    await sleep(10);
  }
  throw new Error(`${label} never reached a database lock wait`);
}

async function cleanup(c) {
  await c.query('set session_replication_role=replica');
  await c.query("delete from public.e10_integration_outbox where commercial_event_id in (select id from public.e10_commercial_events where subject_type='inventory_item' and subject_id=any($1::text[]))", [[ids.item, ids.item2]]);
  await c.query("delete from public.e10_commercial_events where subject_type='inventory_item' and subject_id=any($1::text[])", [[ids.item, ids.item2]]);
  await c.query('set session_replication_role=origin');
  await c.query('delete from public.e10_lot_reservations where lot_id=any($1::uuid[])', [[ids.lot, ids.lot2]]);
  await c.query('delete from public.e10_inventory_reservations where item_id=any($1::text[])', [[ids.item, ids.item2]]);
  await c.query('delete from public.e10_inventory_movements where item_id=any($1::text[])', [[ids.item, ids.item2]]);
  await c.query('delete from public.e10_inventory_lots where id=any($1::uuid[])', [[ids.lot, ids.lot2]]);
  await c.query('delete from public.e10_inventory_items where id=any($1::text[])', [[ids.item, ids.item2]]);
  await c.query('delete from public.e10_product_configuration_versions where id=$1', [ids.config]);
  await c.query('delete from public.e10_product_configurations where id=$1', [ids.config]);
  await c.query('delete from public.e10_product_masters where id=$1', [ids.product]);
  await c.query('delete from public.e10_locations where id=$1', [ids.location]);
  await c.query('delete from public.e10_suppliers where id=$1', [ids.supplier]);
  await c.query('delete from public.e10_organization_memberships where organization_id=$1 and user_id=$2', [org, ids.user]);
  await c.query('delete from public.e10_organization_roles where organization_id=$1 and id=$2', [org, ids.role]);
  await c.query('delete from auth.users where id=$1', [ids.user]);
}

async function main() {
  const setup = new Client({ connectionString: CONN });
  const A = new Client({ connectionString: CONN });
  const B = new Client({ connectionString: CONN });
  await setup.connect(); await A.connect(); await B.connect();
  try {
    await cleanup(setup);
    await setup.query("insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at) values($1,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',$2,now(),now())", [ids.user, `x4h-${run}@x.invalid`]);
    await setup.query("insert into public.e10_organization_roles(id,organization_id,key,name,is_system) values($1,$2,$3,'X4h role',false)", [ids.role, org, `x4h-${run}`]);
    await setup.query("insert into public.e10_organization_role_permissions(organization_id,role_id,capability,allowed) values($1,$2,'act.reserve_inventory',true)", [org, ids.role]);
    await setup.query("insert into public.e10_organization_memberships(organization_id,user_id,role_id,status) values($1,$2,$3,'active')", [org, ids.user, ids.role]);
    await setup.query("insert into public.e10_suppliers(id,organization_id,name) values($1,$2,'X4h supplier')", [ids.supplier, org]);
    await setup.query("insert into public.e10_locations(id,organization_id,name) values($1,$2,'X4h location')", [ids.location, org]);
    await setup.query("insert into public.e10_product_masters(id,organization_id,name) values($1,$2,'X4h product')", [ids.product, org]);
    await setup.query("insert into public.e10_product_configurations(id,organization_id,product_master_id,name) values($1,$2,$3,'Each')", [ids.config, org, ids.product]);
    await setup.query("insert into public.e10_product_configuration_versions(id,organization_id,configuration_id,version_no,state,packaging_kind,base_unit,base_units_per_package) values($1,$2,$1,1,'active','each','each',1)", [ids.config, org]);
    await setup.query("insert into public.e10_inventory_items(id,name,qty,organization_id) values($1,'X4h item',5,$3),($2,'X4h item 2',5,$3)", [ids.item, ids.item2, org]);
    await setup.query("insert into public.e10_inventory_lots(id,organization_id,configuration_version_id,location_id,supplier_id,inventory_item_id,status,accepted_quantity) values($1,$3,$4,$5,$6,$7,'available',5),($2,$3,$4,$5,$6,$8,'available',5)", [ids.lot, ids.lot2, org, ids.config, ids.location, ids.supplier, ids.item, ids.item2]);

    await A.query('begin'); await A.query('select set_config($1,$2,true)', ['request.jwt.claims', jwt]);
    await A.query("select pg_advisory_xact_lock(hashtextextended($1||'|lot|'||$2,0))", [org, ids.lot]);
    await B.query('begin'); await B.query('select set_config($1,$2,true)', ['request.jwt.claims', jwt]);
    const bpid = (await B.query('select pg_backend_pid() pid')).rows[0].pid;
    let bError;
    const bCall = B.query("select public.e10_org_lot_reserve_for_demand($1,$2,4,'manual',$3,'B demand',$4)", [org, ids.lot, `b-${run}`, `b-${run}`]).catch((e) => { bError = e; });
    await waitForLock(setup, bpid, 'generic competing reservation');
    const a = (await A.query("select public.e10_org_lot_reserve_for_demand($1,$2,4,'manual',$3,'A demand',$4) result", [org, ids.lot, `a-${run}`, `a-${run}`])).rows[0].result;
    await A.query('commit'); await bCall; await B.query('rollback').catch(() => {});
    if (!a.ok || !bError || bError.code !== '23514') throw new Error(`generic contention outcomes A=${JSON.stringify(a)} B=${bError && bError.code}`);
    const proof = (await setup.query("select coalesce(sum(quantity),0) lot_reserved,(select coalesce(sum(qty),0) from public.e10_inventory_reservations where organization_id=$1 and item_id=$2 and status='active') legacy_reserved from public.e10_lot_reservations where organization_id=$1 and lot_id=$3 and status='active'", [org, ids.item, ids.lot])).rows[0];
    if (Number(proof.lot_reserved) !== 4 || Number(proof.legacy_reserved) !== 4) throw new Error(`generic reservation projections diverged ${JSON.stringify(proof)}`);

    const itemDenyKey = `item-deny-${run}`;
    await A.query('begin'); await A.query('select id from public.e10_inventory_items where organization_id=$1 and id=$2 for update', [org, ids.item2]);
    await B.query('begin'); await B.query('select set_config($1,$2,true)', ['request.jwt.claims', jwt]);
    let itemDenied;
    const itemDeniedCall = B.query("select public.e10_org_lot_reserve_for_demand($1,$2,1,'manual',$3,'Item-lock revoked demand',$4)", [org, ids.lot2, `item-deny-${run}`, itemDenyKey]).catch((e) => { itemDenied = e; });
    await waitForLock(setup, bpid, 'generic item-row post-wait revocation');
    await setup.query("delete from public.e10_organization_role_permissions where organization_id=$1 and role_id=$2 and capability='act.reserve_inventory'", [org, ids.role]);
    await A.query('commit'); await itemDeniedCall; await B.query('rollback').catch(() => {});
    if (!itemDenied || itemDenied.code !== '42501') throw new Error(`item-row post-wait revocation was not denied: ${itemDenied && itemDenied.code}`);
    let residue = await setup.query("select (select count(*) from public.e10_lot_reservations where organization_id=$1 and lot_id=$2) lot_rows,(select count(*) from public.e10_inventory_reservations where organization_id=$1 and item_id=$3) legacy_rows,(select count(*) from public.e10_inventory_movements where organization_id=$1 and item_id=$3) movement_rows", [org, ids.lot2, ids.item2]);
    if (Object.values(residue.rows[0]).some((v) => Number(v) !== 0)) throw new Error(`item-row revoked generic reservation left residue ${JSON.stringify(residue.rows[0])}`);
    await setup.query("insert into public.e10_organization_role_permissions(organization_id,role_id,capability,allowed) values($1,$2,'act.reserve_inventory',true)", [org, ids.role]);

    const denyKey = `deny-${run}`;
    await A.query('begin'); await A.query("select pg_advisory_xact_lock(hashtextextended($1||'|lot-demand-command|'||$2,0))", [org, denyKey]);
    await B.query('begin'); await B.query('select set_config($1,$2,true)', ['request.jwt.claims', jwt]);
    let denied;
    const deniedCall = B.query("select public.e10_org_lot_reserve_for_demand($1,$2,1,'manual',$3,'Revoked demand',$4)", [org, ids.lot2, `deny-${run}`, denyKey]).catch((e) => { denied = e; });
    await waitForLock(setup, bpid, 'generic post-wait revocation');
    await setup.query("delete from public.e10_organization_role_permissions where organization_id=$1 and role_id=$2 and capability='act.reserve_inventory'", [org, ids.role]);
    await A.query('commit'); await deniedCall; await B.query('rollback').catch(() => {});
    if (!denied || denied.code !== '42501') throw new Error(`post-wait revocation was not denied: ${denied && denied.code}`);
    residue = await setup.query("select (select count(*) from public.e10_lot_reservations where organization_id=$1 and lot_id=$2) lot_rows,(select count(*) from public.e10_inventory_reservations where organization_id=$1 and item_id=$3) legacy_rows,(select count(*) from public.e10_inventory_movements where organization_id=$1 and item_id=$3) movement_rows", [org, ids.lot2, ids.item2]);
    if (Object.values(residue.rows[0]).some((v) => Number(v) !== 0)) throw new Error(`revoked generic reservation left residue ${JSON.stringify(residue.rows[0])}`);
    console.log(`TA-X4h generic reservation concurrency: PASS (one winner, no overcommit, command and item-row post-wait revocation, zero denied residue)`);
  } finally {
    await A.query('rollback').catch(() => {}); await B.query('rollback').catch(() => {});
    await cleanup(setup);
    await A.end(); await B.end(); await setup.end();
  }
}

main().catch((e) => { console.error(`TA-X4h concurrent test ERROR: ${e.stack || e.message}`); process.exit(1); });
