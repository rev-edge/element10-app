// TA-X4d: a legacy reservation committing while receipt reversal waits must be seen by the reversal.
const { Client } = require('pg');
const { randomUUID } = require('crypto');
const CONN = process.env.E10_DB_URL || 'postgresql://postgres:postgres@127.0.0.1:54322/postgres';
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const org = 'e1000000-0000-4000-8000-0000000000a6';
const x = Object.fromEntries(['user','role','supplier','location','product','config','po','pol','expected'].map((k) => [k, randomUUID()]));
x.item = `x4d-${randomUUID()}`; x.run = randomUUID();
const jwt = JSON.stringify({ sub: x.user, role: 'authenticated' });

async function cleanup(c) {
  await c.query('set session_replication_role=replica');
  await c.query("delete from public.e10_integration_outbox where commercial_event_id in (select id from public.e10_commercial_events where subject_type='inventory_item' and subject_id=$1)", [x.item]);
  await c.query("delete from public.e10_commercial_events where subject_type='inventory_item' and subject_id=$1", [x.item]);
  await c.query("delete from public.e10_expected_allocation_events where receipt_line_id in (select id from public.e10_stock_receipt_lines where stock_receipt_id in (select id from public.e10_stock_receipts where idempotency_key=$1))", [`x4d-receive-${x.run}`]);
  await c.query("delete from public.e10_stock_receipt_reversals where stock_receipt_id in (select id from public.e10_stock_receipts where idempotency_key=$1)", [`x4d-receive-${x.run}`]);
  await c.query("delete from public.e10_inventory_lots where inventory_item_id=$1", [x.item]);
  await c.query("delete from public.e10_receipt_po_allocations where purchase_order_line_id=$1", [x.pol]);
  await c.query("delete from public.e10_stock_receipt_lines where stock_receipt_id in (select id from public.e10_stock_receipts where idempotency_key=$1)", [`x4d-receive-${x.run}`]);
  await c.query("delete from public.e10_stock_receipts where idempotency_key=$1", [`x4d-receive-${x.run}`]);
  await c.query('set session_replication_role=origin');
  await c.query("delete from public.e10_inventory_reservations where item_id=$1", [x.item]);
  await c.query("delete from public.e10_inventory_movements where item_id=$1", [x.item]);
  await c.query("delete from public.e10_expected_inventory_allocations where id=$1", [x.expected]);
  await c.query("delete from public.e10_purchase_order_lines where id=$1", [x.pol]);
  await c.query("delete from public.e10_purchase_orders where id=$1", [x.po]);
  await c.query("delete from public.e10_inventory_items where id=$1", [x.item]);
  await c.query("delete from public.e10_product_configuration_versions where id=$1", [x.config]);
  await c.query("delete from public.e10_product_configurations where id=$1", [x.config]);
  await c.query("delete from public.e10_product_masters where id=$1", [x.product]);
  await c.query("delete from public.e10_location_role_permissions where organization_id=$1 and role_id=$2", [org,x.role]);
  await c.query("delete from public.e10_locations where id=$1", [x.location]);
  await c.query("delete from public.e10_suppliers where id=$1", [x.supplier]);
  await c.query("delete from public.e10_organization_memberships where organization_id=$1 and user_id=$2", [org,x.user]);
  await c.query("delete from public.e10_organization_roles where id=$1", [x.role]);
  await c.query("delete from auth.users where id=$1", [x.user]);
}

async function main() {
  const setup = new Client({ connectionString: CONN }); const A = new Client({ connectionString: CONN }); const B = new Client({ connectionString: CONN });
  await setup.connect(); await A.connect(); await B.connect();
  try {
    await cleanup(setup);
    await setup.query("insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at) values($1,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',$2,now(),now())", [x.user,`x4d-${x.run}@x.invalid`]);
    await setup.query("insert into public.e10_organization_roles(id,organization_id,key,name,is_system) values($1,$2,$3,'X4d Race',false)",[x.role,org,`x4d-${x.run}`]);
    await setup.query("insert into public.e10_organization_role_permissions(organization_id,role_id,capability,allowed) values($1,$2,'act.create_receiving',true),($1,$2,'act.resolve_recovery',true),($1,$2,'act.inventory_edit',true)",[org,x.role]);
    await setup.query("insert into public.e10_organization_memberships(organization_id,user_id,role_id,status) values($1,$2,$3,'active')",[org,x.user,x.role]);
    await setup.query("insert into public.e10_suppliers(id,organization_id,name) values($1,$2,'X4d Supplier')",[x.supplier,org]);
    await setup.query("insert into public.e10_locations(id,organization_id,name) values($1,$2,'X4d Location')",[x.location,org]);
    await setup.query("insert into public.e10_location_role_permissions(organization_id,location_id,role_id,can_receive) values($1,$2,$3,true)",[org,x.location,x.role]);
    await setup.query("insert into public.e10_product_masters(id,organization_id,name) values($1,$2,'X4d Product')",[x.product,org]);
    await setup.query("insert into public.e10_product_configurations(id,organization_id,product_master_id,name) values($1,$2,$3,'Each')",[x.config,org,x.product]);
    await setup.query("insert into public.e10_product_configuration_versions(id,organization_id,configuration_id,version_no,state,packaging_kind,base_unit,base_units_per_package) values($1,$2,$1,1,'active','each','each',1)",[x.config,org]);
    await setup.query("insert into public.e10_inventory_items(id,name,qty,organization_id) values($1,'X4d Item',0,$2)",[x.item,org]);
    await setup.query("insert into public.e10_purchase_orders(id,organization_id,supplier_id,destination_location_id,status,currency,created_by) values($1,$2,$3,$4,'approved','CAD',$5)",[x.po,org,x.supplier,x.location,x.user]);
    await setup.query("insert into public.e10_purchase_order_lines(id,organization_id,purchase_order_id,configuration_version_id,line_no,ordered_quantity) values($1,$2,$3,$4,1,10)",[x.pol,org,x.po,x.config]);
    await setup.query("insert into public.e10_expected_inventory_allocations(id,organization_id,purchase_order_line_id,destination_location_id,expected_quantity,planning_reference) values($1,$2,$3,$4,5,'x4d-race')",[x.expected,org,x.pol,x.location]);
    await setup.query('begin'); await setup.query('select set_config($1,$2,true)',['request.jwt.claims',jwt]);
    const receipt = (await setup.query("select public.e10_org_receive_po_line($1,$2,$3,5,0,0,null,now(),jsonb_build_array(jsonb_build_object('id',$4::uuid,'quantity',5)),$5) r",[org,x.pol,x.item,x.expected,`x4d-receive-${x.run}`])).rows[0].r;
    await setup.query('commit');
    await A.query('begin'); await A.query('select set_config($1,$2,true)',['request.jwt.claims',jwt]);
    await A.query('select id from public.e10_inventory_items where organization_id=$1 and id=$2 for update',[org,x.item]);
    await B.query('begin'); await B.query('select set_config($1,$2,true)',['request.jwt.claims',jwt]); await B.query('set local role authenticated');
    const bpid=(await B.query('select pg_backend_pid() pid')).rows[0].pid;
    let reverseError; const reverseCall=B.query('select public.e10_org_reverse_receipt($1,$2,$3,$4)',[org,receipt.receipt_id,'race',`x4d-reverse-${x.run}`]).catch((e)=>{reverseError=e;});
    let waiting=false; for(let i=0;i<400;i++){const q=await setup.query("select wait_event_type='Lock' waiting from pg_stat_activity where pid=$1",[bpid]);if(q.rows[0]?.waiting){waiting=true;break;}await sleep(10);}
    if(!waiting) throw new Error('reversal never waited on legacy-held inventory item');
    const legacy=(await A.query("select public.e10_org_inv_reserve($1,$2,'x4d-race','X4d Race',1,$3) r",[org,x.item,`x4d-legacy-${x.run}`])).rows[0].r;
    await A.query('commit'); await reverseCall; await B.query('rollback').catch(()=>{});
    if(!legacy.ok || !reverseError || reverseError.code!=='55000') throw new Error(`unexpected race outcomes legacy=${JSON.stringify(legacy)} reverse=${reverseError&&reverseError.code}`);
    const proof=(await setup.query("select sr.status,i.qty,(select coalesce(sum(qty),0) from public.e10_inventory_reservations where organization_id=$1 and item_id=$3 and status='active') reserved,(select count(*) from public.e10_stock_receipt_reversals where stock_receipt_id=$2) reversals from public.e10_stock_receipts sr join public.e10_inventory_items i on i.organization_id=sr.organization_id and i.id=$3 where sr.organization_id=$1 and sr.id=$2",[org,receipt.receipt_id,x.item])).rows[0];
    if(proof.status!=='posted'||Number(proof.qty)!==5||Number(proof.reserved)!==1||Number(proof.reversals)!==0) throw new Error('stale reversal escaped: '+JSON.stringify(proof));

    // The internal X4d receiver takes the item row after its wrapper's first
    // authorization check. Revoke the capability while it waits on that exact
    // last blocking row and require the compatibility wrapper to roll back all
    // receipt, lot, allocation, movement and commercial-event effects.
    await A.query('begin');
    await A.query('select id from public.e10_inventory_items where organization_id=$1 and id=$2 for update',[org,x.item]);
    await B.query('begin'); await B.query('select set_config($1,$2,true)',['request.jwt.claims',jwt]); await B.query('set local role authenticated');
    const receivePid=(await B.query('select pg_backend_pid() pid')).rows[0].pid; let receiveError;
    const secondKey=`x4d-receive-revoked-${x.run}`;
    const receiveCall=B.query("select public.e10_org_receive_po_line($1,$2,$3,1,0,0,null,now(),'[]'::jsonb,$4)",[org,x.pol,x.item,secondKey]).catch((e)=>{receiveError=e;});
    waiting=false; for(let i=0;i<400;i++){const q=await setup.query("select wait_event_type='Lock' waiting from pg_stat_activity where pid=$1",[receivePid]);if(q.rows[0]?.waiting){waiting=true;break;}await sleep(10);}
    if(!waiting) throw new Error('receiver never waited on the held inventory item');
    await setup.query("delete from public.e10_organization_role_permissions where organization_id=$1 and role_id=$2 and capability='act.create_receiving'",[org,x.role]);
    await A.query('commit'); await receiveCall; await B.query('rollback').catch(()=>{});
    if(!receiveError||receiveError.code!=='42501'||receiveError.message!=='create_receiving_denied') throw new Error(`post-lock receiving authority escaped ${receiveError&&receiveError.code}:${receiveError&&receiveError.message}`);
    const residue=(await setup.query("select (select count(*) from public.e10_stock_receipts where organization_id=$1 and idempotency_key=$2) receipts,(select count(*) from public.e10_inventory_movements where organization_id=$1 and idempotency_key=$3) movements",[org,secondKey,`${org}:receive:${secondKey}`])).rows[0];
    if(Number(residue.receipts)!==0||Number(residue.movements)!==0) throw new Error('revoked receiver left residue: '+JSON.stringify(residue));
    await setup.query("insert into public.e10_organization_role_permissions(organization_id,role_id,capability,allowed) values($1,$2,'act.create_receiving',true)",[org,x.role]);
    console.log(`TA-X4d receipt races: PASS (reservation floor; post-lock capability pid=${receivePid}; zero residue)`);
  } finally {
    await A.query('rollback').catch(()=>{}); await B.query('rollback').catch(()=>{}); await setup.query('rollback').catch(()=>{}); await cleanup(setup);
    await A.end(); await B.end(); await setup.end();
  }
}
main().catch((e)=>{console.error('TA-X4d concurrent test ERROR: '+(e.stack||e.message));process.exit(1);});
