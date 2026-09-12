// TA-X4f exact-lock proofs: same-key replay, post-wait authority reread,
// reservation-floor rejection, and deterministic shared-item lock order.
const {Client}=require('pg');
const {randomUUID}=require('crypto');
const CONN=process.env.E10_DB_URL||'postgresql://postgres:postgres@127.0.0.1:54322/postgres';
const org='e1000000-0000-4000-8000-0000000000a6';
const sleep=(ms)=>new Promise(r=>setTimeout(r,ms));
const x=Object.fromEntries(['user','role','supplier','location','product','config'].map(k=>[k,randomUUID()]));
x.run=randomUUID();x.items=['a','b','c','d','e','f'].map(k=>`x4f-${k}-${x.run}`);
const jwt=JSON.stringify({sub:x.user,role:'authenticated'});
const one=(item,n=1)=>[{line_no:n,configuration_version_id:x.config,inventory_item_id:item,accepted_quantity:1,damaged_quantity:0,quarantined_quantity:0,expected_allocations:[]}];

async function auth(c){await c.query('select set_config($1,$2,true)',['request.jwt.claims',jwt]);await c.query('set local role authenticated');}
async function waitForLock(observer,pid,label){for(let i=0;i<500;i++){const q=await observer.query("select wait_event_type='Lock' waiting from pg_stat_activity where pid=$1",[pid]);if(q.rows[0]?.waiting)return;await sleep(10);}throw new Error(`${label} never established a real lock wait`);}
async function bounded(p,label){let t;try{return await Promise.race([p,new Promise((_,rej)=>{t=setTimeout(()=>rej(new Error(`${label} timed out`)),8000);})]);}finally{clearTimeout(t);}}
async function receive(c,items,key){await c.query('begin');await auth(c);const lines=items.map((item,i)=>one(item,i+1)[0]);const r=(await c.query('select public.e10_org_receive_batch($1,$2,$3,now(),$4::jsonb,$5) r',[org,x.supplier,x.location,JSON.stringify(lines),key])).rows[0].r;await c.query('commit');return r;}
async function cleanup(c){
  await c.query('set session_replication_role=replica');
  await c.query("delete from public.e10_integration_outbox where commercial_event_id in(select id from public.e10_commercial_events where subject_id=any($1::text[]))",[x.items]);
  await c.query('delete from public.e10_commercial_events where subject_id=any($1::text[])',[x.items]);
  await c.query("delete from public.e10_expected_allocation_events where receipt_line_id in(select id from public.e10_stock_receipt_lines where organization_id=$1 and stock_receipt_id in(select id from public.e10_stock_receipts where organization_id=$1 and idempotency_key like $2))",[org,`x4f-${x.run}%`]);
  await c.query("delete from public.e10_receipt_reversal_commands where organization_id=$1 and idempotency_key like $2",[org,`x4f-${x.run}%`]);
  await c.query("delete from public.e10_receipt_commands where organization_id=$1 and idempotency_key like $2",[org,`x4f-${x.run}%`]);
  await c.query("delete from public.e10_stock_receipt_reversals where organization_id=$1 and stock_receipt_id in(select id from public.e10_stock_receipts where organization_id=$1 and idempotency_key like $2)",[org,`x4f-${x.run}%`]);
  await c.query("delete from public.e10_lot_reservations where organization_id=$1 and lot_id in(select id from public.e10_inventory_lots where organization_id=$1 and inventory_item_id=any($2::text[]))",[org,x.items]);
  await c.query('delete from public.e10_inventory_reservations where organization_id=$1 and item_id=any($2::text[])',[org,x.items]);
  await c.query('delete from public.e10_inventory_lots where organization_id=$1 and inventory_item_id=any($2::text[])',[org,x.items]);
  await c.query("delete from public.e10_stock_receipt_lines where organization_id=$1 and stock_receipt_id in(select id from public.e10_stock_receipts where organization_id=$1 and idempotency_key like $2)",[org,`x4f-${x.run}%`]);
  await c.query("delete from public.e10_stock_receipts where organization_id=$1 and idempotency_key like $2",[org,`x4f-${x.run}%`]);
  await c.query('delete from public.e10_inventory_movements where organization_id=$1 and item_id=any($2::text[])',[org,x.items]);
  await c.query('delete from public.e10_inventory_items where organization_id=$1 and id=any($2::text[])',[org,x.items]);
  await c.query('delete from public.e10_product_configuration_versions where organization_id=$1 and id=$2',[org,x.config]);
  await c.query('delete from public.e10_product_configurations where organization_id=$1 and id=$2',[org,x.config]);
  await c.query('delete from public.e10_product_masters where organization_id=$1 and id=$2',[org,x.product]);
  await c.query('delete from public.e10_location_role_permissions where organization_id=$1 and role_id=$2',[org,x.role]);
  await c.query('delete from public.e10_locations where organization_id=$1 and id=$2',[org,x.location]);
  await c.query('delete from public.e10_suppliers where organization_id=$1 and id=$2',[org,x.supplier]);
  await c.query('delete from public.e10_organization_memberships where organization_id=$1 and user_id=$2',[org,x.user]);
  await c.query('delete from public.e10_organization_role_permissions where organization_id=$1 and role_id=$2',[org,x.role]);
  await c.query('delete from public.e10_organization_roles where organization_id=$1 and id=$2',[org,x.role]);
  await c.query('delete from auth.users where id=$1',[x.user]);
  await c.query('set session_replication_role=origin');
}

async function main(){
  const setup=new Client({connectionString:CONN}),A=new Client({connectionString:CONN}),B=new Client({connectionString:CONN});
  await Promise.all([setup.connect(),A.connect(),B.connect()]);
  try{
    await cleanup(setup);
    await setup.query("insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at)values($1,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',$2,now(),now())",[x.user,`x4f-${x.run}@example.invalid`]);
    await setup.query("insert into public.e10_organization_roles(id,organization_id,key,name,is_system)values($1,$2,$3,'X4f race',false)",[x.role,org,`x4f-${x.run}`]);
    await setup.query("insert into public.e10_organization_role_permissions(organization_id,role_id,capability,allowed)values($1,$2,'act.create_receiving',true),($1,$2,'act.resolve_recovery',true)",[org,x.role]);
    await setup.query("insert into public.e10_organization_memberships(organization_id,user_id,role_id,status)values($1,$2,$3,'active')",[org,x.user,x.role]);
    await setup.query("insert into public.e10_suppliers(id,organization_id,code,name,status)values($1,$2,$3,'X4f supplier','active')",[x.supplier,org,`X4F-${x.run}`]);
    await setup.query("insert into public.e10_locations(id,organization_id,code,name,status)values($1,$2,$3,'X4f location','active')",[x.location,org,`X4F-${x.run}`]);
    await setup.query('insert into public.e10_location_role_permissions(organization_id,location_id,role_id,can_receive)values($1,$2,$3,true)',[org,x.location,x.role]);
    await setup.query("insert into public.e10_product_masters(id,organization_id,name,status)values($1,$2,'X4f product','active')",[x.product,org]);
    await setup.query("insert into public.e10_product_configurations(id,organization_id,product_master_id,name,status)values($1,$2,$3,'Each','active')",[x.config,org,x.product]);
    await setup.query("insert into public.e10_product_configuration_versions(id,organization_id,configuration_id,version_no,state,packaging_kind,base_unit,base_units_per_package)values($1,$2,$1,1,'active','each','each',1)",[x.config,org]);
    for(const item of x.items)await setup.query('insert into public.e10_inventory_items(id,name,qty,organization_id)values($1,$2,0,$3)',[item,item,org]);

    // Reservation commits while reversal waits on the item. The whole reversal loses.
    const reservedReceipt=await receive(setup,[x.items[0]],`x4f-${x.run}-reserved-receive`);
    await A.query('begin');await A.query('select id from public.e10_inventory_items where organization_id=$1 and id=$2 for update',[org,x.items[0]]);
    await B.query('begin');await auth(B);const reservePid=(await B.query('select pg_backend_pid() pid')).rows[0].pid;let reserveError;
    const reserveCall=B.query('select public.e10_org_reverse_receipt_batch($1,$2,$3,$4)',[org,reservedReceipt.receipt_id,'reservation wins',`x4f-${x.run}-reserved-reverse`]).catch(e=>{reserveError=e;});
    await waitForLock(setup,reservePid,'reserved reversal');
    await A.query("insert into public.e10_inventory_reservations(item_id,show_ref,show_label,streamer_uid,qty,status,created_by,organization_id)values($1,$2,'X4f','x4f',1,'active',$3,$4)",[x.items[0],`x4f-${x.run}`,x.user,org]);
    await A.query('commit');await reserveCall;await B.query('rollback').catch(()=>{});
    if(!reserveError||reserveError.code!=='55000'||reserveError.message!=='accepted_quantity_is_reserved')throw new Error(`reservation race escaped ${reserveError&&reserveError.code}:${reserveError&&reserveError.message}`);
    const reservedProof=(await setup.query("select r.status,(select count(*) from public.e10_stock_receipt_reversals where organization_id=$1 and stock_receipt_id=$2) reversals from public.e10_stock_receipts r where r.organization_id=$1 and r.id=$2",[org,reservedReceipt.receipt_id])).rows[0];
    if(reservedProof.status!=='posted'||Number(reservedProof.reversals)!==0)throw new Error(`reservation loser residue ${JSON.stringify(reservedProof)}`);

    // Authority is revoked during a real item-lock wait and must be reread.
    const authReceipt=await receive(setup,[x.items[1]],`x4f-${x.run}-auth-receive`);
    await A.query('begin');await A.query('select id from public.e10_inventory_items where organization_id=$1 and id=$2 for update',[org,x.items[1]]);
    await B.query('begin');await auth(B);const authPid=(await B.query('select pg_backend_pid() pid')).rows[0].pid;let authError;
    const authCall=B.query('select public.e10_org_reverse_receipt_batch($1,$2,$3,$4)',[org,authReceipt.receipt_id,'authority reread',`x4f-${x.run}-auth-reverse`]).catch(e=>{authError=e;});
    await waitForLock(setup,authPid,'authority reversal');
    await setup.query("delete from public.e10_organization_role_permissions where organization_id=$1 and role_id=$2 and capability='act.resolve_recovery'",[org,x.role]);
    await A.query('commit');await authCall;await B.query('rollback').catch(()=>{});
    if(!authError||authError.code!=='42501'||authError.message!=='resolve_recovery_denied')throw new Error(`authority race escaped ${authError&&authError.code}:${authError&&authError.message}`);
    await setup.query("insert into public.e10_organization_role_permissions(organization_id,role_id,capability,allowed)values($1,$2,'act.resolve_recovery',true)",[org,x.role]);

    // A lot consumption becomes terminal while reversal waits on that exact
    // reservation row. Reversal must reread it and leave the receipt intact.
    const consumeReceipt=await receive(setup,[x.items[5]],`x4f-${x.run}-consume-receive`);
    const consumeLot=consumeReceipt.lines[0].lot_id,lotReservation=randomUUID();
    await setup.query("insert into public.e10_lot_reservations(id,organization_id,lot_id,quantity,source_type,source_id,status,idempotency_key,request_fingerprint,consumed_quantity,created_by)values($1,$2,$3,1,'manual',$4,'active',$5,'fixture',0,$6)",[lotReservation,org,consumeLot,`x4f-${x.run}`,`x4f-${x.run}-consume-reservation`,x.user]);
    await A.query('begin');await A.query('select id from public.e10_lot_reservations where organization_id=$1 and id=$2 for update',[org,lotReservation]);
    await B.query('begin');await auth(B);const consumePid=(await B.query('select pg_backend_pid() pid')).rows[0].pid;let consumeError;
    const consumeCall=B.query('select public.e10_org_reverse_receipt_batch($1,$2,$3,$4)',[org,consumeReceipt.receipt_id,'consume wins',`x4f-${x.run}-consume-reverse`]).catch(e=>{consumeError=e;});
    await waitForLock(setup,consumePid,'consume reversal');
    await A.query("update public.e10_lot_reservations set status='consumed',consumed_quantity=1 where organization_id=$1 and id=$2",[org,lotReservation]);
    await A.query('commit');await consumeCall;await B.query('rollback').catch(()=>{});
    if(!consumeError||consumeError.code!=='55000'||consumeError.message!=='receipt_lot_has_committed_quantity')throw new Error(`consume race escaped ${consumeError&&consumeError.code}:${consumeError&&consumeError.message}`);
    if((await setup.query('select status from public.e10_stock_receipts where organization_id=$1 and id=$2',[org,consumeReceipt.receipt_id])).rows[0].status!=='posted')throw new Error('consume race partially reversed receipt');

    // Exact same command waits on A's advisory lock and replays A's result.
    const sameReceipt=await receive(setup,[x.items[4]],`x4f-${x.run}-same-receive`);const sameKey=`x4f-${x.run}-same-reverse`;
    await A.query('begin');await auth(A);const aResult=(await A.query('select public.e10_org_reverse_receipt_batch($1,$2,$3,$4) r',[org,sameReceipt.receipt_id,'same key',sameKey])).rows[0].r;
    await B.query('begin');await auth(B);const samePid=(await B.query('select pg_backend_pid() pid')).rows[0].pid;let bResult,bError;
    const sameCall=B.query('select public.e10_org_reverse_receipt_batch($1,$2,$3,$4) r',[org,sameReceipt.receipt_id,'same key',sameKey]).then(q=>{bResult=q.rows[0].r;}).catch(e=>{bError=e;});
    await waitForLock(setup,samePid,'same-key reversal');await A.query('commit');await sameCall;await B.query('commit');
    if(bError||aResult.replay||!bResult.replay||JSON.stringify(aResult.lines)!==JSON.stringify(bResult.lines))throw new Error(`same-key replay mismatch A=${JSON.stringify(aResult)} B=${JSON.stringify(bResult)} E=${bError}`);

    // Opposite line order in separate receipts shares both items. Global item sorting prevents deadlock.
    const receiptCD=await receive(setup,[x.items[2],x.items[3]],`x4f-${x.run}-cd-receive`);
    const receiptDC=await receive(setup,[x.items[3],x.items[2]],`x4f-${x.run}-dc-receive`);
    await A.query('begin');await auth(A);await B.query('begin');await auth(B);
    const [ra,rb]=await Promise.all([
      bounded(A.query('select public.e10_org_reverse_receipt_batch($1,$2,$3,$4) r',[org,receiptCD.receipt_id,'CD',`x4f-${x.run}-cd-reverse`]).then(async q=>{await A.query('commit');return q.rows[0].r;}),'CD reversal'),
      bounded(B.query('select public.e10_org_reverse_receipt_batch($1,$2,$3,$4) r',[org,receiptDC.receipt_id,'DC',`x4f-${x.run}-dc-reverse`]).then(async q=>{await B.query('commit');return q.rows[0].r;}),'DC reversal')
    ]);
    if(!ra.ok||!rb.ok||(await setup.query('select sum(qty) n from public.e10_inventory_items where organization_id=$1 and id=any($2::text[])',[org,[x.items[2],x.items[3]]])).rows[0].n!=='0')throw new Error('opposite-order reversal failed');
    console.log(`TA-X4f reversal races: PASS (reservation pid=${reservePid} denied; authority pid=${authPid} denied; consume pid=${consumePid} denied; same-key pid=${samePid} replayed; opposite line order completed)`);
  }finally{
    await A.query('rollback').catch(()=>{});await B.query('rollback').catch(()=>{});await setup.query('rollback').catch(()=>{});
    await cleanup(setup);await Promise.all([A.end(),B.end(),setup.end()]);
  }
}
main().catch(e=>{console.error('TA-X4f reversal concurrent test ERROR: '+(e.stack||e.message));process.exit(1);});
