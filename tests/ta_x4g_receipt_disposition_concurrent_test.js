// TA-X4g exact-lock proofs for disposition/CAS/reversal serialization.
const {Client}=require('pg');
const {randomUUID}=require('crypto');
const CONN=process.env.E10_DB_URL||'postgresql://postgres:postgres@127.0.0.1:54322/postgres';
const org='e1000000-0000-4000-8000-0000000000a6';
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
const x=Object.fromEntries(['user','role','supplier','location','product','config'].map(k=>[k,randomUUID()]));
x.run=randomUUID();x.items=['compete','cas','dispwin','revwin','auth','replay'].map(k=>`x4g-${k}-${x.run}`);
const jwt=JSON.stringify({sub:x.user,role:'authenticated'});
const line=item=>[{line_no:1,configuration_version_id:x.config,inventory_item_id:item,accepted_quantity:0,damaged_quantity:0,quarantined_quantity:3,expected_allocations:[]}];
async function auth(c){await c.query('select set_config($1,$2,true)',['request.jwt.claims',jwt]);await c.query('set local role authenticated');}
async function waitForLock(observer,pid,label){for(let i=0;i<500;i++){const q=await observer.query("select wait_event_type='Lock' waiting from pg_stat_activity where pid=$1",[pid]);if(q.rows[0]?.waiting)return;await sleep(10);}throw new Error(`${label} never established a real lock wait`);}
async function receive(c,item,key){await c.query('begin');await auth(c);const r=(await c.query('select public.e10_org_receive_batch($1,$2,$3,now(),$4::jsonb,$5) r',[org,x.supplier,x.location,JSON.stringify(line(item)),key])).rows[0].r;await c.query('commit');return r;}
async function dispose(c,receipt,action,quantity,pred,revision,reason,key){return (await c.query('select public.e10_org_review_receipt_disposition($1,$2,$3,$4,$5,$6,$7,$8) r',[org,receipt.lines[0].receipt_line_id,action,quantity,pred,revision,reason,key])).rows[0].r;}
async function cleanup(c){
 await c.query('set session_replication_role=replica');
 await c.query("delete from public.e10_integration_outbox where commercial_event_id in(select id from public.e10_commercial_events where subject_id=any($1::text[]))",[x.items]);
 await c.query('delete from public.e10_commercial_events where subject_id=any($1::text[])',[x.items]);
 await c.query("delete from public.e10_receipt_disposition_commands where organization_id=$1 and idempotency_key like $2",[org,`x4g-${x.run}%`]);
 await c.query("delete from public.e10_receipt_disposition_decisions where organization_id=$1 and stock_receipt_line_id in(select id from public.e10_stock_receipt_lines where organization_id=$1 and stock_receipt_id in(select id from public.e10_stock_receipts where organization_id=$1 and idempotency_key like $2))",[org,`x4g-${x.run}%`]);
 await c.query("delete from public.e10_receipt_reversal_commands where organization_id=$1 and idempotency_key like $2",[org,`x4g-${x.run}%`]);
 await c.query("delete from public.e10_receipt_commands where organization_id=$1 and idempotency_key like $2",[org,`x4g-${x.run}%`]);
 await c.query("delete from public.e10_stock_receipt_reversals where organization_id=$1 and stock_receipt_id in(select id from public.e10_stock_receipts where organization_id=$1 and idempotency_key like $2)",[org,`x4g-${x.run}%`]);
 await c.query('delete from public.e10_inventory_lots where organization_id=$1 and inventory_item_id=any($2::text[])',[org,x.items]);
 await c.query("delete from public.e10_stock_receipt_lines where organization_id=$1 and stock_receipt_id in(select id from public.e10_stock_receipts where organization_id=$1 and idempotency_key like $2)",[org,`x4g-${x.run}%`]);
 await c.query("delete from public.e10_stock_receipts where organization_id=$1 and idempotency_key like $2",[org,`x4g-${x.run}%`]);
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
  await setup.query("insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at)values($1,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',$2,now(),now())",[x.user,`x4g-${x.run}@example.invalid`]);
  await setup.query("insert into public.e10_organization_roles(id,organization_id,key,name,is_system)values($1,$2,$3,'X4g race',false)",[x.role,org,`x4g-${x.run}`]);
  await setup.query("insert into public.e10_organization_role_permissions(organization_id,role_id,capability,allowed)values($1,$2,'act.create_receiving',true),($1,$2,'act.resolve_recovery',true)",[org,x.role]);
  await setup.query("insert into public.e10_organization_memberships(organization_id,user_id,role_id,status)values($1,$2,$3,'active')",[org,x.user,x.role]);
  await setup.query("insert into public.e10_suppliers(id,organization_id,code,name,status)values($1,$2,$3,'X4g supplier','active')",[x.supplier,org,`X4G-${x.run}`]);
  await setup.query("insert into public.e10_locations(id,organization_id,code,name,status)values($1,$2,$3,'X4g location','active')",[x.location,org,`X4G-${x.run}`]);
  await setup.query('insert into public.e10_location_role_permissions(organization_id,location_id,role_id,can_receive)values($1,$2,$3,true)',[org,x.location,x.role]);
  await setup.query("insert into public.e10_product_masters(id,organization_id,name,status)values($1,$2,'X4g product','active')",[x.product,org]);
  await setup.query("insert into public.e10_product_configurations(id,organization_id,product_master_id,name,status)values($1,$2,$3,'Each','active')",[x.config,org,x.product]);
  await setup.query("insert into public.e10_product_configuration_versions(id,organization_id,configuration_id,version_no,state,packaging_kind,base_unit,base_units_per_package)values($1,$2,$1,1,'active','each','each',1)",[x.config,org]);
  for(const item of x.items)await setup.query('insert into public.e10_inventory_items(id,name,qty,organization_id)values($1,$2,0,$3)',[item,item,org]);

  // Competing dispositions serialize on the receipt. The first consumes two of
  // three quarantined units; the waiter rereads one remaining and fails.
  const compete=await receive(setup,x.items[0],`x4g-${x.run}-compete-receive`);
  await A.query('begin');await auth(A);const first=await dispose(A,compete,'accept',2,null,0,'first',`x4g-${x.run}-compete-a`);
  await B.query('begin');await auth(B);const competePid=(await B.query('select pg_backend_pid() pid')).rows[0].pid;let competeError;
   const competeCall=dispose(B,compete,'damage',2,null,0,'second',`x4g-${x.run}-compete-b`).catch(e=>{competeError=e;});
  await waitForLock(setup,competePid,'competing disposition');await A.query('commit');await competeCall;await B.query('rollback').catch(()=>{});
  if(!first.ok||!competeError||competeError.code!=='23514'||competeError.message!=='receipt_disposition_exceeds_quarantine')throw new Error(`competing disposition escaped ${competeError&&competeError.code}:${competeError&&competeError.message}`);

  // Two corrections name the same current head. The committed successor wins;
  // the waiter rereads the terminal head and fails revision CAS.
  const cas=await receive(setup,x.items[1],`x4g-${x.run}-cas-receive`);await setup.query('begin');await auth(setup);const base=await dispose(setup,cas,'accept',2,null,0,'base',`x4g-${x.run}-cas-base`);await setup.query('commit');
  await A.query('begin');await auth(A);const successor=await dispose(A,cas,'damage',1,base.decision_id,1,'winner',`x4g-${x.run}-cas-a`);
  await B.query('begin');await auth(B);const casPid=(await B.query('select pg_backend_pid() pid')).rows[0].pid;let casError;
  const casCall=dispose(B,cas,'accept',1,base.decision_id,1,'loser',`x4g-${x.run}-cas-b`).catch(e=>{casError=e;});
  await waitForLock(setup,casPid,'disposition CAS');await A.query('commit');await casCall;await B.query('rollback').catch(()=>{});
  if(!successor.ok||!casError||casError.code!=='40001'||casError.message!=='receipt_disposition_revision_conflict')throw new Error(`CAS race escaped ${casError&&casError.code}:${casError&&casError.message}`);

  // Disposition commits while reversal is waiting. X4g generation detection
  // makes reversal roll back all effects rather than execute afterward.
  const dispWin=await receive(setup,x.items[2],`x4g-${x.run}-dispwin-receive`);
  await A.query('begin');await auth(A);const dispWinner=await dispose(A,dispWin,'accept',2,null,0,'disposition wins',`x4g-${x.run}-dispwin`);
  await B.query('begin');await auth(B);const dispWinPid=(await B.query('select pg_backend_pid() pid')).rows[0].pid;let reverseError;
  const reverseCall=B.query('select public.e10_org_reverse_receipt_batch($1,$2,$3,$4)',[org,dispWin.receipt_id,'racing reversal',`x4g-${x.run}-dispwin-reverse`]).catch(e=>{reverseError=e;});
  await waitForLock(setup,dispWinPid,'reversal behind disposition');await A.query('commit');await reverseCall;await B.query('rollback').catch(()=>{});
  if(!dispWinner.ok||!reverseError||reverseError.code!=='40001'||reverseError.message!=='receipt_disposition_changed')throw new Error(`disposition-wins race escaped ${reverseError&&reverseError.code}:${reverseError&&reverseError.message}`);
  const dispProof=(await setup.query("select r.status,i.qty,(select count(*) from public.e10_stock_receipt_reversals where organization_id=$1 and stock_receipt_id=$2) reversals from public.e10_stock_receipts r join public.e10_inventory_items i on i.organization_id=r.organization_id and i.id=$3 where r.organization_id=$1 and r.id=$2",[org,dispWin.receipt_id,x.items[2]])).rows[0];
  if(dispProof.status!=='posted'||Number(dispProof.qty)!==2||Number(dispProof.reversals)!==0)throw new Error(`disposition winner residue invalid ${JSON.stringify(dispProof)}`);

  // Reverse direction: reversal holds the receipt lock, disposition waits, then
  // sees the terminal receipt and leaves no decision or movement.
  const revWin=await receive(setup,x.items[3],`x4g-${x.run}-revwin-receive`);
  await A.query('begin');await auth(A);const reverseWinner=(await A.query('select public.e10_org_reverse_receipt_batch($1,$2,$3,$4) r',[org,revWin.receipt_id,'reversal wins',`x4g-${x.run}-revwin`])).rows[0].r;
  await B.query('begin');await auth(B);const revWinPid=(await B.query('select pg_backend_pid() pid')).rows[0].pid;let dispositionError;
  const dispositionCall=dispose(B,revWin,'accept',1,null,0,'too late',`x4g-${x.run}-revwin-disposition`).catch(e=>{dispositionError=e;});
  await waitForLock(setup,revWinPid,'disposition behind reversal');await A.query('commit');await dispositionCall;await B.query('rollback').catch(()=>{});
  if(!reverseWinner.ok||!dispositionError||dispositionError.code!=='55000'||dispositionError.message!=='receipt_disposition_closed')throw new Error(`reversal-wins race escaped ${dispositionError&&dispositionError.code}:${dispositionError&&dispositionError.message}`);

  // Authority revoked during a real receipt-lock wait is reread after the wait.
  const authReceipt=await receive(setup,x.items[4],`x4g-${x.run}-auth-receive`);
  await A.query('begin');await A.query('select id from public.e10_stock_receipts where organization_id=$1 and id=$2 for update',[org,authReceipt.receipt_id]);
  await B.query('begin');await auth(B);const authPid=(await B.query('select pg_backend_pid() pid')).rows[0].pid;let authError;
  const authCall=dispose(B,authReceipt,'accept',1,null,0,'authority',`x4g-${x.run}-auth-disposition`).catch(e=>{authError=e;});
  await waitForLock(setup,authPid,'disposition authority');await setup.query("delete from public.e10_organization_role_permissions where organization_id=$1 and role_id=$2 and capability='act.resolve_recovery'",[org,x.role]);await A.query('commit');await authCall;await B.query('rollback').catch(()=>{});
  if(!authError||authError.code!=='42501'||authError.message!=='receipt_disposition_denied')throw new Error(`authority race escaped ${authError&&authError.code}:${authError&&authError.message}`);
  await setup.query("insert into public.e10_organization_role_permissions(organization_id,role_id,capability,allowed)values($1,$2,'act.resolve_recovery',true)",[org,x.role]);

  // Exact same command waits and returns the original immutable decision.
  const replayReceipt=await receive(setup,x.items[5],`x4g-${x.run}-replay-receive`);const replayKey=`x4g-${x.run}-replay`;
  await A.query('begin');await auth(A);const original=await dispose(A,replayReceipt,'damage',1,null,0,'same',replayKey);
  await B.query('begin');await auth(B);const replayPid=(await B.query('select pg_backend_pid() pid')).rows[0].pid;let replayResult,replayError;
  const replayCall=dispose(B,replayReceipt,'damage',1,null,0,'same',replayKey).then(r=>{replayResult=r;}).catch(e=>{replayError=e;});
  await waitForLock(setup,replayPid,'same-key disposition');await A.query('commit');await replayCall;await B.query('commit');
  if(replayError||original.replay||!replayResult.replay||original.decision_id!==replayResult.decision_id)throw new Error(`same-key disposition mismatch ${replayError||JSON.stringify(replayResult)}`);
  console.log(`TA-X4g disposition races: PASS (compete pid=${competePid}; CAS pid=${casPid}; disposition-wins pid=${dispWinPid}; reversal-wins pid=${revWinPid}; authority pid=${authPid}; replay pid=${replayPid})`);
 }finally{
  await A.query('rollback').catch(()=>{});await B.query('rollback').catch(()=>{});await setup.query('rollback').catch(()=>{});
  await cleanup(setup);await Promise.all([A.end(),B.end(),setup.end()]);
 }
}
main().catch(e=>{console.error('TA-X4g disposition concurrent test ERROR: '+(e.stack||e.message));process.exit(1);});
