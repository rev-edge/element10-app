const { Client } = require('pg');

const connectionString=process.env.DATABASE_URL||'postgresql://postgres:postgres@127.0.0.1:54322/postgres';
const run=Date.now().toString();
const id=n=>`d3310000-0000-4000-8000-${String(n).padStart(12,'0')}`;
const x={org:id(1),actor:id(2),role:id(3),supplier:id(4),location:id(5),po:id(6),invoice:id(7)};
const timeoutMs=8000;
const cleanupTables=['e10_commercial_events','e10_commercial_comment_commands','e10_commercial_comments','e10_supplier_invoices','e10_purchase_orders','e10_locations','e10_suppliers','e10_organization_role_permissions','e10_organization_memberships','e10_organization_roles','e10_organization_status_transitions'];
const admin=new Client({connectionString}),a=new Client({connectionString}),b=new Client({connectionString});
async function claims(c){await c.query('set local role authenticated');await c.query("select set_config('request.jwt.claims',$1,true)",[JSON.stringify({sub:x.actor,role:'authenticated'})]);}
async function bounded(p){let t;try{return await Promise.race([p,new Promise((_,reject)=>{t=setTimeout(()=>reject(Error('bounded X3e timeout')),timeoutMs)})]);}finally{clearTimeout(t)}}
async function waitBlocked(pid,holderPid){const end=Date.now()+timeoutMs;while(Date.now()<end){const q=await admin.query("select exists(select 1 from pg_locks where pid=$1 and locktype='advisory' and not granted) and $2=any(pg_blocking_pids($1)) waiting",[pid,holderPid]);if(q.rows[0].waiting)return;await new Promise(r=>setTimeout(r,25));}throw Error(`backend ${pid} did not establish advisory wait on holder ${holderPid}`)}
async function setup(){
 await admin.query("insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at) values($1,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',$2,now(),now())",[x.actor,`x3e-${run}@example.invalid`]);
 await admin.query('insert into public.e10_organizations(id,name,slug) values($1,$2,$3)',[x.org,'X3e race',`x3e-race-${run}`]);
 await admin.query("insert into public.e10_organization_roles(id,organization_id,key,name) values($1,$2,'x3e-race','X3e race')",[x.role,x.org]);
 await admin.query("insert into public.e10_organization_memberships(organization_id,user_id,role_id,status) values($1,$2,$3,'active')",[x.org,x.actor,x.role]);
 await admin.query("insert into public.e10_organization_role_permissions(organization_id,role_id,capability,allowed) values($1,$2,'act.purchasing_prepare',true)",[x.org,x.role]);
 await admin.query("insert into public.e10_organization_role_permissions(organization_id,role_id,capability,allowed) values($1,$2,'financial.actual_cost.read',true)",[x.org,x.role]);
 await admin.query("insert into public.e10_suppliers(id,organization_id,name,status) values($1,$2,'supplier','active')",[x.supplier,x.org]);
 await admin.query("insert into public.e10_locations(id,organization_id,name,status) values($1,$2,'location','active')",[x.location,x.org]);
 await admin.query("insert into public.e10_purchase_orders(id,organization_id,supplier_id,destination_location_id,order_number,status,currency,revision,created_by) values($1,$2,$3,$4,$5,'approved','CAD',9,$6)",[x.po,x.org,x.supplier,x.location,`PO-X3E-${run}`,x.actor]);
 await admin.query("insert into public.e10_supplier_invoices(id,organization_id,supplier_id,supplier_document_number,revision,status,currency,total_amount,created_by) values($1,$2,$3,$4,1,'draft','CAD',10,$5)",[x.invoice,x.org,x.supplier,`INV-X3E-${run}`,x.actor]);
}
async function add(c,body,supersedes,key){return c.query('select public.e10_org_add_commercial_comment($1,$2,$3,$4,$5,$6,$7) r',[x.org,'purchase_order',x.po,'vendor',body,supersedes,key]);}
async function addInvoice(c,body,key){return c.query('select public.e10_org_add_commercial_comment($1,$2,$3,$4,$5,null,$6) r',[x.org,'supplier_invoice',x.invoice,'internal',body,key]);}
async function main(){
 await Promise.all([admin.connect(),a.connect(),b.connect()]);await setup();
 const aPid=Number((await a.query('select pg_backend_pid() pid')).rows[0].pid);
 await admin.query('begin');await admin.query("set local role authenticated");await admin.query("select set_config('request.jwt.claims',$1,true)",[JSON.stringify({sub:x.actor,role:'authenticated'})]);
 const root=(await add(admin,'Original vendor instruction',null,`root-${run}`)).rows[0].r;await admin.query('commit');
 await admin.query('begin');await admin.query('set local role authenticated');await admin.query("select set_config('request.jwt.claims',$1,true)",[JSON.stringify({sub:x.actor,role:'authenticated'})]);
 const paddedReplay=(await add(admin,'Original vendor instruction',null,` root-${run} `)).rows[0].r;await admin.query('commit');
 if(!paddedReplay.replay||paddedReplay.comment_id!==root.comment_id)throw Error('padded idempotency replay did not canonicalize');

 const equivalentKey=`equivalent-${run}`;
 await a.query('begin');await a.query('select pg_advisory_xact_lock(hashtextextended($1,0))',[`${x.org}|commercial-comment-command|${equivalentKey}`]);
 await b.query('begin');await claims(b);const equivalentPid=(await b.query('select pg_backend_pid() pid')).rows[0].pid;
 const equivalentPending=add(b,'Equivalent key comment',null,` ${equivalentKey} `);await waitBlocked(equivalentPid,aPid);
 await claims(a);const equivalentWinner=await add(a,'Equivalent key comment',null,equivalentKey);await a.query('commit');
 const equivalentReplay=await bounded(equivalentPending);await b.query('commit');
 if(equivalentWinner.rows[0].r.comment_id!==equivalentReplay.rows[0].r.comment_id||!equivalentReplay.rows[0].r.replay)throw Error('concurrent canonical keys did not converge');
 await admin.query('begin');await admin.query('set local role authenticated');await admin.query("select set_config('request.jwt.claims',$1,true)",[JSON.stringify({sub:x.actor,role:'authenticated'})]);
 let mismatch;try{await add(admin,'Changed equivalent payload',null,` ${equivalentKey} `)}catch(e){mismatch=e}await admin.query('rollback');
 if(!mismatch||mismatch.code!=='22023')throw Error('canonical key changed-payload mismatch accepted');
 console.log(`[proof] backend ${equivalentPid} waited on the canonical command key; padded/unpadded requests converged and changed payload was denied`);

 await a.query('begin');await a.query('select e10.lock_purchase_order($1,$2)',[x.org,x.po]);
 await b.query('begin');await claims(b);const bPid=(await b.query('select pg_backend_pid() pid')).rows[0].pid;
 const pending=add(b,'Competing amendment B',root.comment_id,`branch-b-${run}`);
 await waitBlocked(bPid,aPid);
 await claims(a);const winner=await add(a,'Winning amendment A',root.comment_id,`branch-a-${run}`);await a.query('commit');
 let loser;try{await bounded(pending)}catch(e){loser=e}await b.query('rollback');
 if(!loser||loser.code!=='40001')throw Error(`stale successor was not serialization-denied: ${loser&&loser.code}`);
 const chain=await admin.query("select count(*)::int total,count(*) filter(where supersedes_comment_id=$2)::int successors,count(*) filter(where supersedes_comment_id=$2 and body='Winning amendment A')::int winner from public.e10_commercial_comments where organization_id=$1",[x.org,root.comment_id]);
 if(chain.rows[0].total!==3||chain.rows[0].successors!==1||chain.rows[0].winner!==1)throw Error('single-successor retained chain invalid');
 const po=await admin.query('select revision,status from public.e10_purchase_orders where organization_id=$1 and id=$2',[x.org,x.po]);
 if(po.rows[0].revision!==9||po.rows[0].status!=='approved')throw Error('comment concurrency changed PO revision or approval');
 console.log(`[proof] backend ${bPid} waited on the exact document lock; one successor committed and stale competitor was rejected`);

 await a.query('begin');await a.query('select e10.lock_purchase_order($1,$2)',[x.org,x.po]);
 await b.query('begin');await claims(b);const revokePid=(await b.query('select pg_backend_pid() pid')).rows[0].pid;
 const revoked=add(b,'Must not persist',winner.rows[0].r.comment_id,`revoked-${run}`);await waitBlocked(revokePid,aPid);
 await admin.query("delete from public.e10_organization_role_permissions where organization_id=$1 and role_id=$2 and capability='act.purchasing_prepare'",[x.org,x.role]);
 await a.query('commit');let denied;try{await bounded(revoked)}catch(e){denied=e}await b.query('rollback');
 if(!denied||denied.code!=='42501')throw Error(`post-lock authority revoke failed: ${denied&&denied.code}`);
 const residue=await admin.query("select (select count(*) from public.e10_commercial_comment_commands where organization_id=$1 and idempotency_key=$2)+(select count(*) from public.e10_commercial_comments where organization_id=$1 and body='Must not persist')+(select count(*) from public.e10_commercial_events where organization_id=$1 and commercial_comment_command_idempotency_key=$2) n",[x.org,`revoked-${run}`]);
 if(Number(residue.rows[0].n))throw Error('revoked comment left command/comment/event residue');
 console.log(`[proof] backend ${revokePid} reread prepare authority after its exact document-lock wait; no residue`);

 await admin.query("insert into public.e10_organization_role_permissions(organization_id,role_id,capability,allowed) values($1,$2,'act.purchasing_prepare',true)",[x.org,x.role]);
 await a.query('begin');await a.query("select e10.lock_financial_document($1,'supplier_invoice',$2)",[x.org,x.invoice]);
 await b.query('begin');await claims(b);const financialPid=(await b.query('select pg_backend_pid() pid')).rows[0].pid;
 const financialPending=addInvoice(b,'Must not persist financially',`financial-revoked-${run}`);await waitBlocked(financialPid,aPid);
 await admin.query("delete from public.e10_organization_role_permissions where organization_id=$1 and role_id=$2 and capability='financial.actual_cost.read'",[x.org,x.role]);
 await a.query('commit');let financialDenied;try{await bounded(financialPending)}catch(e){financialDenied=e}await b.query('rollback');
 if(!financialDenied||financialDenied.code!=='42501')throw Error(`post-lock financial authority revoke failed: ${financialDenied&&financialDenied.code}`);
 const financialResidue=await admin.query("select (select count(*) from public.e10_commercial_comment_commands where organization_id=$1 and idempotency_key=$2)+(select count(*) from public.e10_commercial_comments where organization_id=$1 and body='Must not persist financially')+(select count(*) from public.e10_commercial_events where organization_id=$1 and commercial_comment_command_idempotency_key=$2) n",[x.org,`financial-revoked-${run}`]);
 if(Number(financialResidue.rows[0].n))throw Error('revoked financial comment left command/comment/event residue');
 console.log(`[proof] backend ${financialPid} reread actual-cost authority after its exact financial-document wait; zero command/comment/event residue`);

 await a.query('begin');await a.query('select pg_advisory_xact_lock(hashtextextended($1,0))',[`${x.org}|commercial-comment-command|root-${run}`]);
 await b.query('begin');await claims(b);const pausedPid=(await b.query('select pg_backend_pid() pid')).rows[0].pid;
 const pausedReplay=add(b,'Original vendor instruction',null,` root-${run} `);await waitBlocked(pausedPid,aPid);
 await admin.query("update public.e10_organizations set status='suspended' where id=$1",[x.org]);await a.query('commit');
 let pausedDenied;try{await bounded(pausedReplay)}catch(e){pausedDenied=e}await b.query('rollback');
 if(!pausedDenied||pausedDenied.code!=='42501')throw Error(`paused organization replay succeeded: ${pausedDenied&&pausedDenied.code}`);
 const rootCount=await admin.query('select count(*)::int n from public.e10_commercial_comment_commands where organization_id=$1 and idempotency_key=$2',[x.org,`root-${run}`]);
 if(rootCount.rows[0].n!==1)throw Error('paused replay changed command cardinality');
 await admin.query("update public.e10_organizations set status='active' where id=$1",[x.org]);
 console.log(`[proof] backend ${pausedPid} reread active organization state after exact replay lock wait; replay denied with no write`);
}
async function cleanup(){
 await admin.query('begin');await admin.query("set local session_replication_role='replica'");
 for(const table of cleanupTables)await admin.query(`delete from public.${table} where organization_id=$1`,[x.org]);
 await admin.query('delete from public.e10_organizations where id=$1',[x.org]);await admin.query('delete from auth.users where id=$1',[x.actor]);await admin.query('commit');
 for(const table of cleanupTables){const q=await admin.query(`select count(*)::int n from public.${table} where organization_id=$1`,[x.org]);if(q.rows[0].n)throw Error(`X3e cleanup residue ${table}=${q.rows[0].n}`)}
 const q=await admin.query('select (select count(*) from public.e10_organizations where id=$1)+(select count(*) from auth.users where id=$2) n',[x.org,x.actor]);
 if(Number(q.rows[0].n))throw Error(`X3e identity cleanup residue=${q.rows[0].n}`);
}
(async()=>{try{await main();await Promise.allSettled([a.query('rollback'),b.query('rollback')]);await cleanup();console.log('TA-X3e concurrent single-successor and post-lock authorization: PASS (fixture-free)')}catch(e){await Promise.allSettled([a.query('rollback'),b.query('rollback')]);try{await cleanup()}catch(c){console.error(c)}console.error(e);process.exitCode=1}finally{await Promise.allSettled([admin.end(),a.end(),b.end()])}})();
