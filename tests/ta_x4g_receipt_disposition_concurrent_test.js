// TA-X4g exact-lock proofs for disposition/CAS/reversal serialization.
const {Client}=require('pg');
const {randomUUID}=require('crypto');
const CONN=process.env.E10_DB_URL||'postgresql://postgres:postgres@127.0.0.1:54322/postgres';
const org='e1000000-0000-4000-8000-0000000000a6';
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
const x=Object.fromEntries(['user','role','supplier','location','product','config'].map(k=>[k,randomUUID()]));
x.run=randomUUID();x.session=randomUUID();x.items=['compete','cas','dispwin','revwin','auth','replay','corrdisp','corrrev','location','org','reserveauth','single'].map(k=>`x4g-${k}-${x.run}`);
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
 await c.query('delete from public.e10_break_sessions where organization_id=$1 and id=$2',[org,x.session]);
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
  await setup.query("insert into public.e10_organization_role_permissions(organization_id,role_id,capability,allowed)values($1,$2,'act.create_receiving',true),($1,$2,'act.resolve_recovery',true),($1,$2,'act.reserve_inventory',true)",[org,x.role]);
  await setup.query("insert into public.e10_organization_memberships(organization_id,user_id,role_id,status)values($1,$2,$3,'active')",[org,x.user,x.role]);
  await setup.query("insert into public.e10_suppliers(id,organization_id,code,name,status)values($1,$2,$3,'X4g supplier','active')",[x.supplier,org,`X4G-${x.run}`]);
  await setup.query("insert into public.e10_locations(id,organization_id,code,name,status)values($1,$2,$3,'X4g location','active')",[x.location,org,`X4G-${x.run}`]);
  await setup.query('insert into public.e10_location_role_permissions(organization_id,location_id,role_id,can_receive)values($1,$2,$3,true)',[org,x.location,x.role]);
  await setup.query("insert into public.e10_product_masters(id,organization_id,name,status)values($1,$2,'X4g product','active')",[x.product,org]);
  await setup.query("insert into public.e10_product_configurations(id,organization_id,product_master_id,name,status)values($1,$2,$3,'Each','active')",[x.config,org,x.product]);
  await setup.query("insert into public.e10_product_configuration_versions(id,organization_id,configuration_id,version_no,state,packaging_kind,base_unit,base_units_per_package)values($1,$2,$1,1,'active','each','each',1)",[x.config,org]);
  await setup.query("insert into public.e10_break_sessions(id,name,streamer_uid,organization_id,source_show_ref)values($1,'X4g reserve auth',$2,$3,$4)",[x.session,x.user,org,`x4g-${x.run}`]);
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

  // A correction naming a predecessor wins against reversal. The reversal
  // detects the generation change and rolls back without a command or event.
  const corrDisp=await receive(setup,x.items[6],`x4g-${x.run}-corrdisp-receive`);await setup.query('begin');await auth(setup);const corrDispBase=await dispose(setup,corrDisp,'accept',2,null,0,'base',`x4g-${x.run}-corrdisp-base`);await setup.query('commit');
  await A.query('begin');await auth(A);const corrDispWinner=await dispose(A,corrDisp,'damage',1,corrDispBase.decision_id,1,'correction wins',`x4g-${x.run}-corrdisp-correct`);
  await B.query('begin');await auth(B);const corrDispPid=(await B.query('select pg_backend_pid() pid')).rows[0].pid;let corrDispReverseError;
  const corrDispReverseCall=B.query('select public.e10_org_reverse_receipt_batch($1,$2,$3,$4)',[org,corrDisp.receipt_id,'losing reversal',`x4g-${x.run}-corrdisp-reverse`]).catch(e=>{corrDispReverseError=e;});
  await waitForLock(setup,corrDispPid,'correction before reversal');await A.query('commit');await corrDispReverseCall;await B.query('rollback').catch(()=>{});
  if(!corrDispWinner.ok||!corrDispReverseError||corrDispReverseError.code!=='40001'||corrDispReverseError.message!=='receipt_disposition_changed')throw new Error(`correction-wins race escaped ${corrDispReverseError&&corrDispReverseError.code}:${corrDispReverseError&&corrDispReverseError.message}`);
  const corrDispProof=(await setup.query('select (select count(*) from public.e10_receipt_disposition_decisions where organization_id=$1 and stock_receipt_line_id=$2) decisions,(select count(*) from public.e10_stock_receipt_reversals where organization_id=$1 and stock_receipt_id=$3) reversals',[org,corrDisp.lines[0].receipt_line_id,corrDisp.receipt_id])).rows[0];
  if(Number(corrDispProof.decisions)!==2||Number(corrDispProof.reversals)!==0)throw new Error(`correction-wins residue ${JSON.stringify(corrDispProof)}`);

  // Reversal wins against an actual correction naming a predecessor. The
  // waiter rereads terminal state and leaves no successor decision or command.
  const corrRev=await receive(setup,x.items[7],`x4g-${x.run}-corrrev-receive`);await setup.query('begin');await auth(setup);const corrRevBase=await dispose(setup,corrRev,'accept',2,null,0,'base',`x4g-${x.run}-corrrev-base`);await setup.query('commit');
  await A.query('begin');await auth(A);const corrRevWinner=(await A.query('select public.e10_org_reverse_receipt_batch($1,$2,$3,$4) r',[org,corrRev.receipt_id,'reversal wins correction race',`x4g-${x.run}-corrrev-reverse`])).rows[0].r;
  await B.query('begin');await auth(B);const corrRevPid=(await B.query('select pg_backend_pid() pid')).rows[0].pid;let corrRevError;
  const corrRevCall=dispose(B,corrRev,'damage',1,corrRevBase.decision_id,1,'losing correction',`x4g-${x.run}-corrrev-correct`).catch(e=>{corrRevError=e;});
  await waitForLock(setup,corrRevPid,'reversal before correction');await A.query('commit');await corrRevCall;await B.query('rollback').catch(()=>{});
  if(!corrRevWinner.ok||!corrRevError||corrRevError.code!=='55000'||corrRevError.message!=='receipt_disposition_closed')throw new Error(`reversal-wins-correction race escaped ${corrRevError&&corrRevError.code}:${corrRevError&&corrRevError.message}`);
  const corrRevProof=(await setup.query('select (select count(*) from public.e10_receipt_disposition_decisions where organization_id=$1 and stock_receipt_line_id=$2) decisions,(select count(*) from public.e10_receipt_disposition_commands where organization_id=$1 and idempotency_key=$3) losing_commands',[org,corrRev.lines[0].receipt_line_id,`x4g-${x.run}-corrrev-correct`])).rows[0];
  if(Number(corrRevProof.decisions)!==1||Number(corrRevProof.losing_commands)!==0)throw new Error(`reversal-wins-correction residue ${JSON.stringify(corrRevProof)}`);

  // Destination permission and organization status are both reread after a
  // real receipt-row wait, not trusted from the pre-lock authorization check.
  const locReceipt=await receive(setup,x.items[8],`x4g-${x.run}-location-receive`);
  await A.query('begin');await A.query('select id from public.e10_stock_receipts where organization_id=$1 and id=$2 for update',[org,locReceipt.receipt_id]);await B.query('begin');await auth(B);const locPid=(await B.query('select pg_backend_pid() pid')).rows[0].pid;let locError;
  const locCall=dispose(B,locReceipt,'accept',1,null,0,'location revoked',`x4g-${x.run}-location-disposition`).catch(e=>{locError=e;});await waitForLock(setup,locPid,'destination revocation');await setup.query('delete from public.e10_location_role_permissions where organization_id=$1 and location_id=$2 and role_id=$3',[org,x.location,x.role]);await A.query('commit');await locCall;await B.query('rollback').catch(()=>{});
  if(!locError||locError.code!=='42501'||locError.message!=='receipt_disposition_denied')throw new Error(`destination revocation escaped ${locError&&locError.code}:${locError&&locError.message}`);await setup.query('insert into public.e10_location_role_permissions(organization_id,location_id,role_id,can_receive)values($1,$2,$3,true)',[org,x.location,x.role]);

  const orgReceipt=await receive(setup,x.items[9],`x4g-${x.run}-org-receive`);
  await A.query('begin');await A.query('select id from public.e10_stock_receipts where organization_id=$1 and id=$2 for update',[org,orgReceipt.receipt_id]);await B.query('begin');await auth(B);const orgPid=(await B.query('select pg_backend_pid() pid')).rows[0].pid;let orgError;
  const orgCall=dispose(B,orgReceipt,'accept',1,null,0,'organization suspended',`x4g-${x.run}-org-disposition`).catch(e=>{orgError=e;});await waitForLock(setup,orgPid,'organization suspension');await setup.query("update public.e10_organizations set status='suspended' where id=$1",[org]);await A.query('commit');await orgCall;await B.query('rollback').catch(()=>{});
  if(!orgError||orgError.code!=='42501'||orgError.message!=='receipt_disposition_denied')throw new Error(`organization suspension escaped ${orgError&&orgError.code}:${orgError&&orgError.message}`);await setup.query("update public.e10_organizations set status='active' where id=$1",[org]);

  // Reserve authority is reread after the canonical lot advisory wait and
  // before inspecting a deliberately divergent receipt-backed projection.
  const reserveAuth=await receive(setup,x.items[10],`x4g-${x.run}-reserveauth-receive`);await setup.query('begin');await auth(setup);await dispose(setup,reserveAuth,'accept',2,null,0,'reserve auth stock',`x4g-${x.run}-reserveauth-disposition`);await setup.query('commit');
  const reserveLot=reserveAuth.lines[0].lot_id;await setup.query('update public.e10_inventory_lots set accepted_quantity=accepted_quantity+1 where organization_id=$1 and id=$2',[org,reserveLot]);
  await A.query('begin');await A.query("select pg_advisory_xact_lock(hashtextextended($1::text||'|lot|'||$2::text,0))",[org,reserveLot]);
  await B.query('begin');await auth(B);const reserveAuthPid=(await B.query('select pg_backend_pid() pid')).rows[0].pid;let reserveAuthError;
  const reserveAuthCall=B.query('select public.e10_org_lot_reserve($1,$2,1,$3,$4)',[org,reserveLot,x.session,`x4g-${x.run}-reserveauth-reserve`]).catch(e=>{reserveAuthError=e;});
  await waitForLock(setup,reserveAuthPid,'reserve post-lock authority');await setup.query("delete from public.e10_organization_role_permissions where organization_id=$1 and role_id=$2 and capability='act.reserve_inventory'",[org,x.role]);await A.query('commit');await reserveAuthCall;await B.query('rollback').catch(()=>{});
  if(!reserveAuthError||reserveAuthError.code!=='42501'||reserveAuthError.message!=='reserve_inventory_denied')throw new Error(`reserve post-lock authority leaked projection ${reserveAuthError&&reserveAuthError.code}:${reserveAuthError&&reserveAuthError.message}`);
  const reserveResidue=(await setup.query("select (select count(*) from public.e10_lot_reservations where organization_id=$1 and lot_id=$2) reservations,(select count(*) from public.e10_inventory_movements where organization_id=$1 and idempotency_key=$3) movements",[org,reserveLot,`${org}:lot-reserve:x4g-${x.run}-reserveauth-reserve`])).rows[0];if(Number(reserveResidue.reservations)!==0||Number(reserveResidue.movements)!==0)throw new Error(`reserve revocation residue ${JSON.stringify(reserveResidue)}`);
  await setup.query("insert into public.e10_organization_role_permissions(organization_id,role_id,capability,allowed)values($1,$2,'act.reserve_inventory',true)",[org,x.role]);

  // The legacy single-line name must now use the disposition-aware batch
  // implementation. A quarantine-only receipt gets origin evidence, two units
  // are accepted, and reversal removes exactly those two without phantom stock.
  const single=await receive(setup,x.items[11],`x4g-${x.run}-single-receive`);
  await setup.query('begin');await auth(setup);await dispose(setup,single,'accept',2,null,0,'single compatibility',`x4g-${x.run}-single-disposition`);const singleReverse=(await setup.query('select public.e10_org_reverse_receipt($1,$2,$3,$4) r',[org,single.receipt_id,'single compatibility reverse',`x4g-${x.run}-single-reverse`])).rows[0].r;await setup.query('commit');
  const singleProof=(await setup.query("select sr.status receipt_status,i.qty,l.status lot_status,(select count(*) from public.e10_commercial_events ce where ce.organization_id=$1 and ce.payload->>'receipt_line_id'=$4 and ce.event_type='receipt') origins,(select count(*) from public.e10_commercial_events ce where ce.organization_id=$1 and ce.payload->>'reversal_id'=$5 and ce.event_type='correction') reversal_corrections from public.e10_stock_receipts sr join public.e10_stock_receipt_lines rl on(rl.organization_id,rl.stock_receipt_id)=(sr.organization_id,sr.id) join public.e10_inventory_lots l on(l.organization_id,l.id)=(rl.organization_id,rl.inventory_lot_id) join public.e10_inventory_items i on(i.organization_id,i.id)=(l.organization_id,l.inventory_item_id) where sr.organization_id=$1 and sr.id=$2 and i.id=$3",[org,single.receipt_id,x.items[11],single.lines[0].receipt_line_id,singleReverse.reversal_id])).rows[0];
  if(!singleReverse.ok||singleProof.receipt_status!=='reversed'||singleProof.lot_status!=='reversed'||Number(singleProof.qty)!==0||Number(singleProof.origins)!==1||Number(singleProof.reversal_corrections)!==1)throw new Error(`single reversal compatibility failed ${JSON.stringify(singleProof)} ${JSON.stringify(singleReverse)}`);
  console.log(`TA-X4g disposition races: PASS (initial/CAS/reversal, compatibility reversal, origin evidence, authority/location/org rereads, replay; waiter pid=${orgPid})`);
 }finally{
  await A.query('rollback').catch(()=>{});await B.query('rollback').catch(()=>{});await setup.query('rollback').catch(()=>{});
  await cleanup(setup);await Promise.all([A.end(),B.end(),setup.end()]);
 }
}
main().catch(e=>{console.error('TA-X4g disposition concurrent test ERROR: '+(e.stack||e.message));process.exit(1);});
