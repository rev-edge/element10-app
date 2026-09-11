const { Client } = require('pg');

const connectionString=process.env.DATABASE_URL||'postgresql://postgres:postgres@127.0.0.1:54322/postgres';
const run=Date.now().toString();
const id=n=>`d3310000-0000-4000-8000-${String(n).padStart(12,'0')}`;
const x={org:id(1),actor:id(2),role:id(3),supplier:id(4),location:id(5),po:id(6)};
const timeoutMs=8000;
const admin=new Client({connectionString}),a=new Client({connectionString}),b=new Client({connectionString});
async function claims(c){await c.query('set local role authenticated');await c.query("select set_config('request.jwt.claims',$1,true)",[JSON.stringify({sub:x.actor,role:'authenticated'})]);}
async function bounded(p){let t;try{return await Promise.race([p,new Promise((_,reject)=>{t=setTimeout(()=>reject(Error('bounded X3e timeout')),timeoutMs)})]);}finally{clearTimeout(t)}}
async function waitBlocked(pid){const end=Date.now()+timeoutMs;while(Date.now()<end){const q=await admin.query("select count(*)::int n from pg_locks where pid=$1 and locktype='advisory' and not granted",[pid]);if(q.rows[0].n>0)return;await new Promise(r=>setTimeout(r,25));}throw Error(`backend ${pid} did not establish exact advisory wait`)}
async function setup(){
 await admin.query("insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at) values($1,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',$2,now(),now())",[x.actor,`x3e-${run}@example.invalid`]);
 await admin.query('insert into public.e10_organizations(id,name,slug) values($1,$2,$3)',[x.org,'X3e race',`x3e-race-${run}`]);
 await admin.query("insert into public.e10_organization_roles(id,organization_id,key,name) values($1,$2,'x3e-race','X3e race')",[x.role,x.org]);
 await admin.query("insert into public.e10_organization_memberships(organization_id,user_id,role_id,status) values($1,$2,$3,'active')",[x.org,x.actor,x.role]);
 await admin.query("insert into public.e10_organization_role_permissions(organization_id,role_id,capability,allowed) values($1,$2,'act.purchasing_prepare',true)",[x.org,x.role]);
 await admin.query("insert into public.e10_suppliers(id,organization_id,name,status) values($1,$2,'supplier','active')",[x.supplier,x.org]);
 await admin.query("insert into public.e10_locations(id,organization_id,name,status) values($1,$2,'location','active')",[x.location,x.org]);
 await admin.query("insert into public.e10_purchase_orders(id,organization_id,supplier_id,destination_location_id,order_number,status,currency,revision,created_by) values($1,$2,$3,$4,$5,'approved','CAD',9,$6)",[x.po,x.org,x.supplier,x.location,`PO-X3E-${run}`,x.actor]);
}
async function add(c,body,supersedes,key){return c.query('select public.e10_org_add_commercial_comment($1,$2,$3,$4,$5,$6,$7) r',[x.org,'purchase_order',x.po,'vendor',body,supersedes,key]);}
async function main(){
 await Promise.all([admin.connect(),a.connect(),b.connect()]);await setup();
 await admin.query('begin');await admin.query("set local role authenticated");await admin.query("select set_config('request.jwt.claims',$1,true)",[JSON.stringify({sub:x.actor,role:'authenticated'})]);
 const root=(await add(admin,'Original vendor instruction',null,`root-${run}`)).rows[0].r;await admin.query('commit');

 await a.query('begin');await a.query('select e10.lock_purchase_order($1,$2)',[x.org,x.po]);
 await b.query('begin');await claims(b);const bPid=(await b.query('select pg_backend_pid() pid')).rows[0].pid;
 const pending=add(b,'Competing amendment B',root.comment_id,`branch-b-${run}`);
 await waitBlocked(bPid);
 await claims(a);const winner=await add(a,'Winning amendment A',root.comment_id,`branch-a-${run}`);await a.query('commit');
 let loser;try{await bounded(pending)}catch(e){loser=e}await b.query('rollback');
 if(!loser||loser.code!=='40001')throw Error(`stale successor was not serialization-denied: ${loser&&loser.code}`);
 const chain=await admin.query('select body,supersedes_comment_id from public.e10_commercial_comments where organization_id=$1 order by created_at,id',[x.org]);
 if(chain.rowCount!==2||chain.rows[1].body!=='Winning amendment A'||chain.rows[1].supersedes_comment_id!==root.comment_id)throw Error('single-successor retained chain invalid');
 const po=await admin.query('select revision,status from public.e10_purchase_orders where organization_id=$1 and id=$2',[x.org,x.po]);
 if(po.rows[0].revision!==9||po.rows[0].status!=='approved')throw Error('comment concurrency changed PO revision or approval');
 console.log(`[proof] backend ${bPid} waited on the exact document lock; one successor committed and stale competitor was rejected`);

 await a.query('begin');await a.query('select e10.lock_purchase_order($1,$2)',[x.org,x.po]);
 await b.query('begin');await claims(b);const revokePid=(await b.query('select pg_backend_pid() pid')).rows[0].pid;
 const revoked=add(b,'Must not persist',winner.rows[0].r.comment_id,`revoked-${run}`);await waitBlocked(revokePid);
 await admin.query("delete from public.e10_organization_role_permissions where organization_id=$1 and role_id=$2 and capability='act.purchasing_prepare'",[x.org,x.role]);
 await a.query('commit');let denied;try{await bounded(revoked)}catch(e){denied=e}await b.query('rollback');
 if(!denied||denied.code!=='42501')throw Error(`post-lock authority revoke failed: ${denied&&denied.code}`);
 const residue=await admin.query('select count(*)::int n from public.e10_commercial_comment_commands where organization_id=$1 and idempotency_key=$2',[x.org,`revoked-${run}`]);
 if(residue.rows[0].n)throw Error('revoked comment command left residue');
 console.log(`[proof] backend ${revokePid} reread prepare authority after its exact document-lock wait; no residue`);
}
async function cleanup(){
 await admin.query('begin');await admin.query("set local session_replication_role='replica'");
 for(const table of ['e10_commercial_events','e10_commercial_comment_commands','e10_commercial_comments','e10_purchase_orders','e10_locations','e10_suppliers','e10_organization_role_permissions','e10_organization_memberships','e10_organization_roles'])await admin.query(`delete from public.${table} where organization_id=$1`,[x.org]);
 await admin.query('delete from public.e10_organizations where id=$1',[x.org]);await admin.query('delete from auth.users where id=$1',[x.actor]);await admin.query('commit');
 const q=await admin.query('select (select count(*) from public.e10_organizations where id=$1)+(select count(*) from auth.users where id=$2)+(select count(*) from public.e10_commercial_comments where organization_id=$1) n',[x.org,x.actor]);
 if(Number(q.rows[0].n))throw Error(`X3e cleanup residue=${q.rows[0].n}`);
}
(async()=>{try{await main();await Promise.allSettled([a.query('rollback'),b.query('rollback')]);await cleanup();console.log('TA-X3e concurrent single-successor and post-lock authorization: PASS (fixture-free)')}catch(e){await Promise.allSettled([a.query('rollback'),b.query('rollback')]);try{await cleanup()}catch(c){console.error(c)}console.error(e);process.exitCode=1}finally{await Promise.allSettled([admin.end(),a.end(),b.end()])}})();
