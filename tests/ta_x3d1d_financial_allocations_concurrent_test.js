const { Client } = require('pg');

const connectionString = process.env.DATABASE_URL || 'postgresql://postgres:postgres@127.0.0.1:54322/postgres';
const run = Date.now().toString();
const id = (n) => `d3200000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const x = { org:id(1), actor:id(2), role:id(3), supplier:id(4), location:id(5), product:id(6), config:id(7), version:id(8),
  po:id(9), pol:id(10), inv1:id(11), il1:id(12), inv2:id(13), il2:id(14), inv3:id(15), il3:id(16) };
const timeoutMs = 8000;
const admin = new Client({ connectionString }); const a = new Client({ connectionString }); const b = new Client({ connectionString });
async function claims(c){await c.query('set local role authenticated');await c.query("select set_config('request.jwt.claims',$1,true)",[JSON.stringify({sub:x.actor,role:'authenticated'})]);}
async function bounded(p){let t;try{return await Promise.race([p,new Promise((_,r)=>{t=setTimeout(()=>r(Error('bounded allocation timeout')),timeoutMs)})]);}finally{clearTimeout(t)}}
async function waitBlocked(pid){const end=Date.now()+timeoutMs;while(Date.now()<end){const q=await admin.query("select count(*)::int n from pg_locks where pid=$1 and locktype='advisory' and not granted",[pid]);if(q.rows[0].n>0)return;await new Promise(r=>setTimeout(r,25));}throw Error(`backend ${pid} did not block`)}
function allocate(c,invLine,key){return c.query('select public.e10_org_allocate_invoice_to_po($1,$2,$3,1,1,6,$4,$4) r',[x.org,invLine,x.pol,key])}
async function setup(){
 await admin.query("insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at) values($1,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',$2,now(),now())",[x.actor,`x3d1d-${run}@example.invalid`]);
 await admin.query('insert into public.e10_organizations(id,name,slug) values($1,$2,$3)',[x.org,'X3d1d race',`x3d1d-${run}`]);
 await admin.query("insert into public.e10_organization_roles(id,organization_id,key,name) values($1,$2,'x3d1d','X3d1d')",[x.role,x.org]);
 await admin.query("insert into public.e10_organization_memberships(organization_id,user_id,role_id,status) values($1,$2,$3,'active')",[x.org,x.actor,x.role]);
 await admin.query("insert into public.e10_organization_role_permissions(organization_id,role_id,capability,allowed) values($1,$2,'act.purchasing_prepare',true)",[x.org,x.role]);
 await admin.query("insert into public.e10_suppliers(id,organization_id,name,status) values($1,$2,'supplier','active')",[x.supplier,x.org]);
 await admin.query("insert into public.e10_locations(id,organization_id,name,status) values($1,$2,'location','active')",[x.location,x.org]);
 await admin.query('insert into public.e10_location_role_permissions(organization_id,location_id,role_id,can_receive) values($1,$2,$3,true)',[x.org,x.location,x.role]);
 await admin.query("insert into public.e10_product_masters(id,organization_id,name) values($1,$2,'product')",[x.product,x.org]);
 await admin.query("insert into public.e10_product_configurations(id,organization_id,product_master_id,name) values($1,$2,$3,'config')",[x.config,x.org,x.product]);
 await admin.query("insert into public.e10_product_configuration_versions(id,organization_id,configuration_id,version_no,state,packaging_kind,base_unit,base_units_per_package) values($1,$2,$3,1,'active','unit','unit',1)",[x.version,x.org,x.config]);
 await admin.query("insert into public.e10_purchase_orders(id,organization_id,supplier_id,destination_location_id,order_number,status,currency,created_by) values($1,$2,$3,$4,$5,'approved','CAD',$6)",[x.po,x.org,x.supplier,x.location,`PO-${run}`,x.actor]);
 await admin.query('insert into public.e10_purchase_order_lines(id,organization_id,purchase_order_id,configuration_version_id,line_no,ordered_quantity) values($1,$2,$3,$4,1,10)',[x.pol,x.org,x.po,x.version]);
 for(const [inv,line,no] of [[x.inv1,x.il1,1],[x.inv2,x.il2,2],[x.inv3,x.il3,3]]){await admin.query("insert into public.e10_supplier_invoices(id,organization_id,supplier_id,supplier_document_number,currency,total_amount,created_by) values($1,$2,$3,$4,'CAD',60,$5)",[inv,x.org,x.supplier,`INV-${run}-${no}`,x.actor]);await admin.query('insert into public.e10_supplier_invoice_lines(id,organization_id,supplier_invoice_id,configuration_version_id,line_no,invoiced_quantity,unit_cost,line_amount) values($1,$2,$3,$4,1,6,10,60)',[line,x.org,inv,x.version]);}
}
async function main(){await Promise.all([admin.connect(),a.connect(),b.connect()]);await setup();
 await a.query('begin');await b.query('begin');await claims(a);await claims(b);
 const pa=allocate(a,x.il1,`race-a-${run}`).then(value=>({client:a,other:b,value,label:'a'}));
 const pb=allocate(b,x.il2,`race-b-${run}`).then(value=>({client:b,other:a,value,label:'b'}));
 const winner=await bounded(Promise.race([pa,pb]));await winner.client.query('commit');
 let bad;try{await bounded(winner.label==='a'?pb:pa)}catch(e){bad=e}await winner.other.query('rollback');
 if(!bad||bad.code!=='23514')throw Error(`conservation race loser invalid ${bad&&bad.code}`);
 const total=await admin.query('select sum(allocated_quantity)::text q from public.e10_invoice_po_allocations where organization_id=$1 and purchase_order_line_id=$2',[x.org,x.pol]);
 if(total.rows[0].q!=='6')throw Error('target overallocated');console.log('[proof] competing source documents serialized on target PO; one accepted, one conservation-denied');

 await a.query('begin');await a.query('select pg_advisory_xact_lock(hashtextextended($1,0))',[`${x.org}|financial-document|supplier_invoice|${x.inv3}`]);
 await b.query('begin');await claims(b);const pid=(await b.query('select pg_backend_pid() pid')).rows[0].pid;
 const pending=allocate(b,x.il3,`revoked-${run}`);await waitBlocked(pid);
 await admin.query("delete from public.e10_organization_role_permissions where organization_id=$1 and role_id=$2 and capability='act.purchasing_prepare'",[x.org,x.role]);await a.query('commit');
 let denied;try{await bounded(pending)}catch(e){denied=e}await b.query('rollback');
 if(!denied||denied.code!=='42501')throw Error(`post-lock revoke failed ${denied&&denied.code}`);
 const residue=await admin.query('select count(*)::int n from public.e10_financial_allocation_commands where organization_id=$1 and idempotency_key=$2',[x.org,`revoked-${run}`]);if(residue.rows[0].n)throw Error('revoked command residue');
 console.log(`[proof] backend ${pid} reread prepare authority after exact invoice lock wait; no residue`);
}
async function cleanup(){await admin.query('begin');await admin.query("set local session_replication_role='replica'");for(const t of ['e10_invoice_po_allocation_events','e10_financial_allocation_commands','e10_supplier_invoice_revisions','e10_invoice_po_allocations','e10_supplier_invoice_lines','e10_supplier_invoices','e10_purchase_order_lines','e10_purchase_orders','e10_product_configuration_versions','e10_product_configurations','e10_product_masters','e10_locations','e10_suppliers','e10_organization_role_permissions','e10_organization_memberships','e10_organization_roles'])await admin.query(`delete from public.${t} where organization_id=$1`,[x.org]);await admin.query('delete from public.e10_organizations where id=$1',[x.org]);await admin.query('delete from auth.users where id=$1',[x.actor]);await admin.query('commit');}
(async()=>{try{await main();await Promise.allSettled([a.query('rollback'),b.query('rollback')]);await cleanup();console.log('TA-X3d.1d concurrent conservation and post-lock authorization: PASS (fixture-free)')}catch(e){await Promise.allSettled([a.query('rollback'),b.query('rollback')]);try{await cleanup()}catch(c){console.error(c)}console.error(e);process.exitCode=1}finally{await Promise.allSettled([admin.end(),a.end(),b.end()])}})();
