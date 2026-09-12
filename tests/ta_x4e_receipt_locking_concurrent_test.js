// TA-X4e concurrency: same-key serialization, post-wait authority reread,
// and globally sorted shared-item locks across different supplier/location roots.
const { Client } = require('pg');
const { randomUUID } = require('crypto');
const CONN=process.env.E10_DB_URL||'postgresql://postgres:postgres@127.0.0.1:54322/postgres';
const sleep=(ms)=>new Promise((r)=>setTimeout(r,ms));
const org='e1000000-0000-4000-8000-0000000000a6';
const x=Object.fromEntries(['user','role','supplier1','supplier2','location1','location2','product','config','po','pol'].map(k=>[k,randomUUID()]));
x.run=randomUUID(); x.itemA=`x4e-lock-a-${x.run}`; x.itemB=`x4e-lock-b-${x.run}`; x.itemC=`x4e-lock-c-${x.run}`;
const jwt=JSON.stringify({sub:x.user,role:'authenticated'});
const line=(item,n)=>[{line_no:n,configuration_version_id:x.config,inventory_item_id:item,accepted_quantity:1,damaged_quantity:0,quarantined_quantity:0,expected_allocations:[]}];

async function auth(c){await c.query('select set_config($1,$2,true)',['request.jwt.claims',jwt]);await c.query('set local role authenticated');}
async function waitForLock(observer,pid,label){for(let i=0;i<500;i++){const q=await observer.query("select wait_event_type='Lock' waiting from pg_stat_activity where pid=$1",[pid]);if(q.rows[0]?.waiting)return;await sleep(10);}throw new Error(`${label} never established a real lock wait`);}
async function bounded(promise,label){let timer;try{return await Promise.race([promise,new Promise((_,reject)=>{timer=setTimeout(()=>reject(new Error(`${label} timed out`)),8000);})]);}finally{clearTimeout(timer);}}
async function cleanup(c){
  await c.query('set session_replication_role=replica');
  await c.query("delete from public.e10_integration_outbox where commercial_event_id in(select id from public.e10_commercial_events where subject_id=any($1::text[]))",[[x.itemA,x.itemB,x.itemC]]);
  await c.query('delete from public.e10_commercial_events where subject_id=any($1::text[])',[[x.itemA,x.itemB,x.itemC]]);
  await c.query("delete from public.e10_receipt_commands where organization_id=$1 and idempotency_key like $2",[org,`x4e-lock-${x.run}%`]);
  await c.query("delete from public.e10_receipt_po_allocations where organization_id=$1 and receipt_line_id in(select l.id from public.e10_stock_receipt_lines l join public.e10_stock_receipts r on(r.organization_id,r.id)=(l.organization_id,l.stock_receipt_id)where r.organization_id=$1 and r.idempotency_key like $2)",[org,`x4e-lock-${x.run}%`]);
  await c.query('delete from public.e10_inventory_lots where organization_id=$1 and inventory_item_id=any($2::text[])',[org,[x.itemA,x.itemB,x.itemC]]);
  await c.query("delete from public.e10_stock_receipt_lines where organization_id=$1 and stock_receipt_id in(select id from public.e10_stock_receipts where organization_id=$1 and idempotency_key like $2)",[org,`x4e-lock-${x.run}%`]);
  await c.query("delete from public.e10_stock_receipts where organization_id=$1 and idempotency_key like $2",[org,`x4e-lock-${x.run}%`]);
  await c.query('delete from public.e10_inventory_movements where organization_id=$1 and item_id=any($2::text[])',[org,[x.itemA,x.itemB,x.itemC]]);
  await c.query('delete from public.e10_inventory_items where organization_id=$1 and id=any($2::text[])',[org,[x.itemA,x.itemB,x.itemC]]);
  await c.query('delete from public.e10_purchase_order_lines where organization_id=$1 and purchase_order_id=$2',[org,x.po]);
  await c.query('delete from public.e10_purchase_orders where organization_id=$1 and id=$2',[org,x.po]);
  await c.query('delete from public.e10_product_configuration_versions where organization_id=$1 and id=$2',[org,x.config]);
  await c.query('delete from public.e10_product_configurations where organization_id=$1 and id=$2',[org,x.config]);
  await c.query('delete from public.e10_product_masters where organization_id=$1 and id=$2',[org,x.product]);
  await c.query('delete from public.e10_location_role_permissions where organization_id=$1 and role_id=$2',[org,x.role]);
  await c.query('delete from public.e10_locations where organization_id=$1 and id=any($2::uuid[])',[org,[x.location1,x.location2]]);
  await c.query('delete from public.e10_suppliers where organization_id=$1 and id=any($2::uuid[])',[org,[x.supplier1,x.supplier2]]);
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
    await setup.query("insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at)values($1,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',$2,now(),now())",[x.user,`x4e-lock-${x.run}@example.invalid`]);
    await setup.query("insert into public.e10_organization_roles(id,organization_id,key,name,is_system)values($1,$2,$3,'X4e lock',false)",[x.role,org,`x4e-${x.run}`]);
    await setup.query("insert into public.e10_organization_role_permissions(organization_id,role_id,capability,allowed)values($1,$2,'act.create_receiving',true)",[org,x.role]);
    await setup.query("insert into public.e10_organization_memberships(organization_id,user_id,role_id,status)values($1,$2,$3,'active')",[org,x.user,x.role]);
    await setup.query("insert into public.e10_suppliers(id,organization_id,code,name,status)values($1,$3,$4,'S1','active'),($2,$3,$5,'S2','active')",[x.supplier1,x.supplier2,org,`S1-${x.run}`,`S2-${x.run}`]);
    await setup.query("insert into public.e10_locations(id,organization_id,code,name,status)values($1,$3,$4,'L1','active'),($2,$3,$5,'L2','active')",[x.location1,x.location2,org,`L1-${x.run}`,`L2-${x.run}`]);
    await setup.query('insert into public.e10_location_role_permissions(organization_id,location_id,role_id,can_receive)values($1,$2,$4,true),($1,$3,$4,true)',[org,x.location1,x.location2,x.role]);
    await setup.query("insert into public.e10_product_masters(id,organization_id,name,status)values($1,$2,'X4e','active')",[x.product,org]);
    await setup.query("insert into public.e10_product_configurations(id,organization_id,product_master_id,name,status)values($1,$2,$3,'Each','active')",[x.config,org,x.product]);
    await setup.query("insert into public.e10_product_configuration_versions(id,organization_id,configuration_id,version_no,state,packaging_kind,base_unit,base_units_per_package)values($1,$2,$1,1,'active','each','each',1)",[x.config,org]);
    await setup.query("insert into public.e10_inventory_items(id,name,qty,organization_id)values($1,'A',0,$4),($2,'B',0,$4),($3,'C',0,$4)",[x.itemA,x.itemB,x.itemC,org]);
    await setup.query("insert into public.e10_purchase_orders(id,organization_id,supplier_id,destination_location_id,status,currency,revision,created_by)values($1,$2,$3,$4,'approved','CAD',1,$5)",[x.po,org,x.supplier1,x.location1,x.user]);
    await setup.query("insert into public.e10_purchase_order_lines(id,organization_id,purchase_order_id,configuration_version_id,line_no,ordered_quantity,state)values($1,$2,$3,$4,1,2,'active')",[x.pol,org,x.po,x.config]);

    // Same idempotency key: B demonstrably waits, then replays A's exact result.
    const sameKey=`x4e-lock-${x.run}-same`;
    await A.query('begin');await A.query('select pg_advisory_xact_lock(hashtextextended($1,0))',[`${org}|receipt-any-command|${sameKey}`]);await auth(A);
    await B.query('begin');await auth(B);const bpid=(await B.query('select pg_backend_pid() pid')).rows[0].pid;
    let bResult,bError;const bCall=B.query('select public.e10_org_receive_batch($1,$2,$3,$4::timestamptz,$5::jsonb,$6) r',[org,x.supplier1,x.location1,'2026-09-12T02:00:00Z',JSON.stringify(line(x.itemA,1)),sameKey]).then(q=>{bResult=q.rows[0].r;}).catch(e=>{bError=e;});
    await waitForLock(setup,bpid,'same-key receipt');
    const aResult=(await A.query('select public.e10_org_receive_batch($1,$2,$3,$4::timestamptz,$5::jsonb,$6) r',[org,x.supplier1,x.location1,'2026-09-12T02:00:00Z',JSON.stringify(line(x.itemA,1)),sameKey])).rows[0].r;
    await A.query('commit');await bCall;await B.query('commit');
    if(bError||aResult.replay||!bResult.replay||aResult.receipt_id!==bResult.receipt_id)throw new Error(`same-key result mismatch A=${JSON.stringify(aResult)} B=${JSON.stringify(bResult)} E=${bError}`);

    // Authority revoked while B waits on the globally ordered item dependency.
    const authKey=`x4e-lock-${x.run}-auth`;
    await A.query('begin');await A.query('select id from public.e10_inventory_items where organization_id=$1 and id=$2 for update',[org,x.itemC]);
    await B.query('begin');await auth(B);const authPid=(await B.query('select pg_backend_pid() pid')).rows[0].pid;let authError;
    const authCall=B.query('select public.e10_org_receive_batch($1,$2,$3,now(),$4::jsonb,$5)',[org,x.supplier1,x.location1,JSON.stringify(line(x.itemC,1)),authKey]).catch(e=>{authError=e;});
    await waitForLock(setup,authPid,'authority-reread receipt');
    await setup.query("delete from public.e10_organization_role_permissions where organization_id=$1 and role_id=$2 and capability='act.create_receiving'",[org,x.role]);
    await A.query('commit');await authCall;await B.query('rollback').catch(()=>{});
    if(!authError||authError.code!=='42501'||authError.message!=='create_receiving_denied')throw new Error(`post-wait revocation escaped ${authError&&authError.code}:${authError&&authError.message}`);
    const residue=(await setup.query("select count(*) n from public.e10_stock_receipts where organization_id=$1 and idempotency_key=$2",[org,authKey])).rows[0].n;
    if(Number(residue)!==0)throw new Error('authority loser left receipt residue');
    await setup.query("insert into public.e10_organization_role_permissions(organization_id,role_id,capability,allowed)values($1,$2,'act.create_receiving',true)",[org,x.role]);

    // The single-line public entry point also reaches a valid request, waits on
    // its exact item dependency, then rechecks destination authority.
    const locationKey=`x4e-lock-${x.run}-single-location`;
    await A.query('begin');await A.query('select id from public.e10_inventory_items where organization_id=$1 and id=$2 for update',[org,x.itemC]);
    await B.query('begin');await auth(B);const locationPid=(await B.query('select pg_backend_pid() pid')).rows[0].pid;let locationError;
    const locationCall=B.query("select public.e10_org_receive_po_line($1,$2,$3,1,0,0,null,now(),'[]'::jsonb,$4)",[org,x.pol,x.itemC,locationKey]).catch(e=>{locationError=e;});
    await waitForLock(setup,locationPid,'single-line destination reread');
    await setup.query('delete from public.e10_location_role_permissions where organization_id=$1 and location_id=$2 and role_id=$3',[org,x.location1,x.role]);
    await A.query('commit');await locationCall;await B.query('rollback').catch(()=>{});
    if(!locationError||locationError.code!=='42501'||locationError.message!=='create_receiving_denied')throw new Error(`post-wait destination revocation escaped ${locationError&&locationError.code}:${locationError&&locationError.message}`);
    const singleResidue=(await setup.query("select count(*) n from public.e10_stock_receipts where organization_id=$1 and idempotency_key=$2",[org,locationKey])).rows[0].n;
    if(Number(singleResidue)!==0)throw new Error('single-line destination loser left receipt residue');
    await setup.query('insert into public.e10_location_role_permissions(organization_id,location_id,role_id,can_receive)values($1,$2,$3,true)',[org,x.location1,x.role]);
    await B.query('begin');await auth(B);
    const singleControl=(await B.query("select public.e10_org_receive_po_line($1,$2,$3,1,0,0,null,now(),'[]'::jsonb,$4) r",[org,x.pol,x.itemC,`${locationKey}-control`])).rows[0].r;
    await B.query('commit');if(!singleControl.ok||singleControl.replay)throw new Error('single-line valid control failed after destination restore');

    // Different supplier/location roots, opposite caller item order. Both complete.
    await A.query('begin');await auth(A);await B.query('begin');await auth(B);
    const linesAB=[...line(x.itemA,1),...line(x.itemB,2)],linesBA=[...line(x.itemB,1),...line(x.itemA,2)];
    const [ra,rb]=await Promise.all([
      bounded(A.query('select public.e10_org_receive_batch($1,$2,$3,now(),$4::jsonb,$5) r',[org,x.supplier1,x.location1,JSON.stringify(linesAB),`x4e-lock-${x.run}-ab`]).then(async q=>{await A.query('commit');return q;}),'AB'),
      bounded(B.query('select public.e10_org_receive_batch($1,$2,$3,now(),$4::jsonb,$5) r',[org,x.supplier2,x.location2,JSON.stringify(linesBA),`x4e-lock-${x.run}-ba`]).then(async q=>{await B.query('commit');return q;}),'BA')
    ]);
    if(!ra.rows[0].r.ok||!rb.rows[0].r.ok)throw new Error('opposite-order receipt failed');
    console.log(`TA-X4e locking races: PASS (same-key B pid=${bpid} replayed; authority B pid=${authPid} denied; single-line location B pid=${locationPid} denied; opposite item order completed)`);
  }finally{
    await A.query('rollback').catch(()=>{});await B.query('rollback').catch(()=>{});await setup.query('rollback').catch(()=>{});
    await cleanup(setup);
    const residue=await setup.query("select (select count(*)from public.e10_stock_receipts where organization_id=$1 and idempotency_key like $2)::int receipts,(select count(*)from public.e10_receipt_commands where organization_id=$1 and idempotency_key like $2)::int commands,(select count(*)from public.e10_inventory_items where organization_id=$1 and id=any($3::text[]))::int items,(select count(*)from public.e10_purchase_orders where organization_id=$1 and id=$4)::int purchase_orders,(select count(*)from auth.users where id=$5)::int users",[org,`x4e-lock-${x.run}%`,[x.itemA,x.itemB,x.itemC],x.po,x.user]);
    if(Object.values(residue.rows[0]).some(Number))throw new Error(`X4e cleanup residue ${JSON.stringify(residue.rows[0])}`);
    await Promise.all([A.end(),B.end(),setup.end()]);
  }
}
main().catch(e=>{console.error('TA-X4e locking concurrent test ERROR: '+(e.stack||e.message));process.exit(1);});
