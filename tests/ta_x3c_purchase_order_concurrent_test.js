const {Client}=require('pg');
const {randomUUID}=require('crypto');
const db=process.env.E10_DB_URL||'postgresql://postgres:postgres@127.0.0.1:54322/postgres';
const outcome=p=>p.then(value=>({ok:true,value}),error=>({ok:false,error}));
async function bounded(p,ms=10000){let timer;try{return await Promise.race([p,new Promise((_,reject)=>{timer=setTimeout(()=>reject(Error(`TIMEOUT ${ms}ms`)),ms)})])}finally{clearTimeout(timer)}}
async function waitBlocked(obs,pid,blocker,label){const end=Date.now()+5000;while(Date.now()<end){const q=(await obs.query('select wait_event_type,$2=any(pg_blocking_pids($1)) exact from pg_stat_activity where pid=$1',[pid,blocker])).rows[0];if(q?.wait_event_type==='Lock'&&q.exact)return;await new Promise(r=>setTimeout(r,25))}throw Error(`${label}: backend ${pid} not blocked by ${blocker}`)}
async function actor(id){const c=new Client({connectionString:db});await c.connect();await c.query("set statement_timeout='10s';set lock_timeout='9s'");await c.query('select set_config($1,$2,false)',['request.jwt.claims',JSON.stringify({sub:id,role:'authenticated'})]);await c.query('set role authenticated');return c}
async function main(){
 const s=new Client({connectionString:db}),obs=new Client({connectionString:db});await Promise.all([s.connect(),obs.connect()]);for(const c of[s,obs])await c.query("set statement_timeout='10s';set lock_timeout='9s'");
 const x={org:randomUUID(),prep:randomUUID(),role:randomUUID(),loc:randomUUID(),supplier:randomUUID(),product:randomUUID(),config:randomUUID(),version:randomUUID(),item:'x3c-'+randomUUID(),line:randomUUID(),expected:randomUUID(),invoice:randomUUID(),invoiceLine:randomUUID(),run:randomUUID()};let a,b,pending=[],completed=false;
 const lines=JSON.stringify([{id:x.line,line_no:1,configuration_version_id:x.version,ordered_quantity:10,estimated_unit_cost:5}]);
 const createSql='select public.e10_org_create_purchase_order($1,$2,$3,$4,$5,null,$6::jsonb,$7) r';
 try{
  await s.query("insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at)values($1,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',$2,now(),now())",[x.prep,x.prep+'@x.invalid']);
  await s.query("insert into public.e10_organizations(id,name,slug)values($1,$2,$3)",[x.org,'X3c '+x.run,'x3c-'+x.run]);
  await s.query("insert into public.e10_organization_roles(id,organization_id,key,name,is_system)values($1,$2,'prep','Prepare',false)",[x.role,x.org]);
  await s.query("insert into public.e10_organization_memberships(organization_id,user_id,role_id,status)values($1,$2,$3,'active')",[x.org,x.prep,x.role]);
  await s.query("insert into public.e10_organization_role_permissions(organization_id,role_id,capability,allowed)values($1,$2,'act.purchasing_prepare',true),($1,$2,'act.purchasing_cancel',true),($1,$2,'act.create_receiving',true)",[x.org,x.role]);
  await s.query("insert into public.e10_locations(id,organization_id,name,status)values($1,$2,'X3c location','active')",[x.loc,x.org]);
  await s.query('insert into public.e10_location_role_permissions(organization_id,location_id,role_id,can_receive)values($1,$2,$3,true)',[x.org,x.loc,x.role]);
  await s.query("insert into public.e10_suppliers(id,organization_id,name,status)values($1,$2,'X3c supplier','active')",[x.supplier,x.org]);
  await s.query("insert into public.e10_product_masters(id,organization_id,name)values($1,$2,'X3c product')",[x.product,x.org]);
  await s.query("insert into public.e10_product_configurations(id,organization_id,product_master_id,name)values($1,$2,$3,'Case')",[x.config,x.org,x.product]);
  await s.query("insert into public.e10_product_configuration_versions(id,organization_id,configuration_id,version_no,state,packaging_kind,base_unit,base_units_per_package)values($1,$2,$3,1,'active','case','unit',1)",[x.version,x.org,x.config]);
  await s.query('insert into public.e10_inventory_items(id,name,qty,organization_id)values($1,$2,0,$3)',[x.item,'X3c item',x.org]);
  await s.query("insert into public.e10_supplier_invoices(id,organization_id,supplier_id,supplier_document_number,status,currency,total_amount,created_by)values($1,$2,$3,$4,'approved','CAD',10,$5)",[x.invoice,x.org,x.supplier,'INV-'+x.run,x.prep]);
  await s.query('insert into public.e10_supplier_invoice_lines(id,organization_id,supplier_invoice_id,configuration_version_id,line_no,invoiced_quantity,unit_cost,line_amount)values($1,$2,$3,$4,1,1,10,10)',[x.invoiceLine,x.org,x.invoice,x.version]);
  [a,b]=await Promise.all([actor(x.prep),actor(x.prep)]);const ap=Number((await a.query('select pg_backend_pid() pid')).rows[0].pid),bp=Number((await b.query('select pg_backend_pid() pid')).rows[0].pid);

  const idem=x.run+'-same';await a.query('begin');await a.query("select pg_advisory_xact_lock(hashtextextended($1||'|purchase-order-command|'||$2,0))",[x.org,idem]);
  const pb=outcome(b.query(createSql,[x.org,x.supplier,x.loc,'RACE-1','CAD',lines,idem]));pending=[pb];await waitBlocked(obs,bp,ap,'create idempotency');
  const ar=await a.query(createSql,[x.org,x.supplier,x.loc,'RACE-1','CAD',lines,idem]);await a.query('commit');const br=await bounded(pb);pending=[];if(!br.ok)throw br.error;
  if(ar.rows[0].r.replay!==false||br.value.rows[0].r.replay!==true)throw Error('create expected one insert and one replay');
  const po=ar.rows[0].r.purchase_order_id;console.log(`[proof] create backend ${bp} waited on exact command lock held by ${ap}; one insert + one replay`);

  const deniedKey=x.run+'-denied';await s.query('begin');const sp=Number((await s.query('select pg_backend_pid() pid')).rows[0].pid);await s.query("select pg_advisory_xact_lock(hashtextextended($1||'|purchase-order-command|'||$2,0))",[x.org,deniedKey]);
  const denied=outcome(b.query(createSql,[x.org,x.supplier,x.loc,'DENIED','CAD',lines,deniedKey]));pending=[denied];await waitBlocked(obs,bp,sp,'post-lock capability');
  await s.query("delete from public.e10_organization_role_permissions where organization_id=$1 and role_id=$2 and capability='act.purchasing_prepare'",[x.org,x.role]);await s.query('commit');const dr=await bounded(denied);pending=[];
  if(dr.ok||dr.error.code!=='42501')throw Error('post-lock capability revocation not denied');
  if(Number((await s.query('select count(*) n from public.e10_purchase_order_commands where organization_id=$1 and idempotency_key=$2',[x.org,deniedKey])).rows[0].n))throw Error('denied command persisted');
  console.log('[proof] create reread removed purchasing capability after exact command-lock wait');
  await s.query("insert into public.e10_organization_role_permissions(organization_id,role_id,capability,allowed)values($1,$2,'act.purchasing_prepare',true)",[x.org,x.role]);

  const blockedSubmit=x.run+'-blocked-submit';await s.query('begin');await s.query("select pg_advisory_xact_lock(hashtextextended($1||'|purchase-order|'||$2,0))",[x.org,po]);
  const transitionDenied=outcome(b.query('select public.e10_org_transition_purchase_order($1,$2,1,$3,$4,$5)',[x.org,po,'submit','blocked capability',blockedSubmit]));pending=[transitionDenied];await waitBlocked(obs,bp,sp,'transition capability after PO lock');
  await s.query("delete from public.e10_organization_role_permissions where organization_id=$1 and role_id=$2 and capability='act.purchasing_prepare'",[x.org,x.role]);await s.query('commit');const td=await bounded(transitionDenied);pending=[];
  if(td.ok||td.error.code!=='42501')throw Error('transition post-PO-lock capability revocation not denied');
  if(Number((await s.query('select count(*) n from public.e10_purchase_order_commands where organization_id=$1 and idempotency_key=$2',[x.org,blockedSubmit])).rows[0].n))throw Error('denied transition persisted');
  console.log('[proof] transition reread removed purchasing capability after exact PO-lock wait');
  await s.query("insert into public.e10_organization_role_permissions(organization_id,role_id,capability,allowed)values($1,$2,'act.purchasing_prepare',true)",[x.org,x.role]);

  const blockedOrg=x.run+'-blocked-org';await s.query('begin');await s.query("select pg_advisory_xact_lock(hashtextextended($1||'|purchase-order|'||$2,0))",[x.org,po]);
  const orgDenied=outcome(b.query('select public.e10_org_transition_purchase_order($1,$2,1,$3,$4,$5)',[x.org,po,'submit','blocked org',blockedOrg]));pending=[orgDenied];await waitBlocked(obs,bp,sp,'transition organization after PO lock');
  await s.query("update public.e10_organizations set status='suspended' where id=$1",[x.org]);await s.query('commit');const od=await bounded(orgDenied);pending=[];
  if(od.ok||od.error.code!=='42501')throw Error('transition post-PO-lock organization suspension not denied');
  if(Number((await s.query('select count(*) n from public.e10_purchase_order_commands where organization_id=$1 and idempotency_key=$2',[x.org,blockedOrg])).rows[0].n))throw Error('suspended-org transition persisted');
  console.log('[proof] transition reread suspended organization after exact PO-lock wait');await s.query("update public.e10_organizations set status='active' where id=$1",[x.org]);

  const blockedInvoiceCancel=x.run+'-blocked-invoice-cancel';await s.query('begin');await s.query("select pg_advisory_xact_lock(hashtextextended($1||'|purchase-order|'||$2,0))",[x.org,po]);
  const invoiceCancelDenied=outcome(b.query('select public.e10_org_transition_purchase_order($1,$2,1,$3,$4,$5)',[x.org,po,'cancel','blocked invoice allocation',blockedInvoiceCancel]));pending=[invoiceCancelDenied];await waitBlocked(obs,bp,sp,'cancel versus invoice allocation');
  await s.query('insert into public.e10_invoice_po_allocations(organization_id,invoice_line_id,purchase_order_line_id,allocated_quantity)values($1,$2,$3,1)',[x.org,x.invoiceLine,x.line]);await s.query('commit');const icd=await bounded(invoiceCancelDenied);pending=[];
  if(icd.ok||icd.error.code!=='55000')throw Error('cancel did not observe post-lock invoice allocation');
  if(Number((await s.query('select count(*) n from public.e10_purchase_order_commands where organization_id=$1 and idempotency_key=$2',[x.org,blockedInvoiceCancel])).rows[0].n))throw Error('invoice-allocation-denied cancel persisted');
  console.log('[proof] cancel backend observed invoice allocation inserted before exact PO-lock release and denied with zero command residue');
  await s.query('delete from public.e10_invoice_po_allocations where organization_id=$1 and invoice_line_id=$2',[x.org,x.invoiceLine]);

  const blockedCancel=x.run+'-blocked-cancel';await s.query('begin');await s.query("select pg_advisory_xact_lock(hashtextextended($1||'|purchase-order|'||$2,0))",[x.org,po]);
  const cancelDenied=outcome(b.query('select public.e10_org_transition_purchase_order($1,$2,1,$3,$4,$5)',[x.org,po,'cancel','blocked commitment',blockedCancel]));pending=[cancelDenied];await waitBlocked(obs,bp,sp,'cancel versus commitment');
  await s.query("insert into public.e10_expected_inventory_allocations(id,organization_id,purchase_order_line_id,destination_location_id,expected_quantity,status,planning_reference)values($1,$2,$3,$4,1,'open',$5)",[x.expected,x.org,x.line,x.loc,x.run]);await s.query('commit');const cd=await bounded(cancelDenied);pending=[];
  if(cd.ok||cd.error.code!=='55000')throw Error('cancel did not observe post-lock commitment');
  if(Number((await s.query('select count(*) n from public.e10_purchase_order_commands where organization_id=$1 and idempotency_key=$2',[x.org,blockedCancel])).rows[0].n))throw Error('denied cancel persisted');
  console.log('[proof] cancel backend observed commitment inserted before exact PO-lock release and denied with zero command residue');
  await s.query('delete from public.e10_expected_inventory_allocations where organization_id=$1 and id=$2',[x.org,x.expected]);

  const staleAmendKey=x.run+'-stale-amend';await a.query('begin');await a.query("select pg_advisory_xact_lock(hashtextextended($1||'|purchase-order|'||$2,0))",[x.org,po]);
  const staleAmend=outcome(b.query('select public.e10_org_amend_purchase_order($1,$2,1,$3,$4,$5,$6,null,$7::jsonb,$8,$9)',[x.org,po,x.supplier,x.loc,'RACE-1','CAD',lines,'stale after submit',staleAmendKey]));pending=[staleAmend];await waitBlocked(obs,bp,ap,'amend CAS versus submit');
  await a.query('select public.e10_org_transition_purchase_order($1,$2,1,$3,$4,$5)',[x.org,po,'submit','ready',x.run+'-submit']);await a.query('commit');const sa=await bounded(staleAmend);pending=[];
  if(sa.ok||sa.error.code!=='40001')throw Error('blocked amend did not fail stale after concurrent submit');
  if(Number((await s.query('select count(*) n from public.e10_purchase_order_commands where organization_id=$1 and idempotency_key=$2',[x.org,staleAmendKey])).rows[0].n))throw Error('stale amend persisted command');
  console.log('[proof] amend backend waited on exact PO lock and failed CAS after concurrent submit with zero command residue');
  await a.query('begin');await a.query("select pg_advisory_xact_lock(hashtextextended($1||'|purchase-order|'||$2,0))",[x.org,po]);
  const receive=outcome(b.query("select public.e10_org_receive_po_line($1,$2,$3,10,0,0,null,now(),'[]'::jsonb,$4) r",[x.org,x.line,x.item,x.run+'-receive']));pending=[receive];await waitBlocked(obs,bp,ap,'receive versus amend');
  const amendLines=JSON.stringify([{id:x.line,line_no:1,configuration_version_id:x.version,ordered_quantity:5,estimated_unit_cost:5}]);
  const amended=await a.query('select public.e10_org_amend_purchase_order($1,$2,2,$3,$4,$5,$6,null,$7::jsonb,$8,$9) r',[x.org,po,x.supplier,x.loc,'RACE-1','CAD',amendLines,'reduce before receipt',x.run+'-amend']);
  if(amended.rows[0].r.revision!==3)throw Error('amend did not commit revision 3');
  await a.query('select public.e10_org_transition_purchase_order($1,$2,3,$3,$4,$5)',[x.org,po,'submit','re-submit reduced order',x.run+'-resubmit']);
  await a.query('commit');const rr=await bounded(receive);pending=[];
  if(rr.ok||rr.error.code!=='23514'||rr.error.message!=='over_receipt_not_authorized')throw Error('serialized receipt did not observe reduced PO quantity');
  if(Number((await s.query('select count(*) n from public.e10_stock_receipts where organization_id=$1',[x.org])).rows[0].n))throw Error('failed receipt left residue');
  console.log(`[proof] receive backend ${bp} waited on exact PO lock held by ${ap}; post-amend over-receipt denied with zero residue`);completed=true;
 }finally{
  for(const c of[a,b])if(c){await c.query('rollback').catch(()=>{});await c.query('reset role').catch(()=>{});await c.end().catch(()=>{})}if(pending.length)await Promise.allSettled(pending.map(p=>bounded(p).catch(()=>{})));
  await s.query('rollback').catch(()=>{});await s.query('set session_replication_role=replica');
  for(const table of['e10_commercial_events','e10_purchase_order_commands','e10_purchase_order_revisions','e10_stock_receipt_reversals','e10_stock_receipt_lines','e10_stock_receipts','e10_receipt_po_allocations','e10_expected_inventory_allocations','e10_invoice_po_allocations','e10_supplier_invoice_lines','e10_supplier_invoices','e10_purchase_order_lines','e10_purchase_orders','e10_inventory_items','e10_location_role_permissions','e10_locations','e10_suppliers','e10_product_configuration_versions','e10_product_configurations','e10_product_masters','e10_organization_role_permissions','e10_organization_memberships','e10_organization_roles'])await s.query(`delete from public.${table} where organization_id=$1`,[x.org]);
  await s.query('delete from public.e10_organizations where id=$1',[x.org]);await s.query('set session_replication_role=origin');await s.query('delete from auth.users where id=$1',[x.prep]);
  const residue=Number((await s.query("select (select count(*) from public.e10_purchase_orders where organization_id=$1)+(select count(*) from public.e10_purchase_order_lines where organization_id=$1)+(select count(*) from public.e10_purchase_order_revisions where organization_id=$1)+(select count(*) from public.e10_purchase_order_commands where organization_id=$1)+(select count(*) from public.e10_commercial_events where organization_id=$1)+(select count(*) from public.e10_expected_inventory_allocations where organization_id=$1)+(select count(*) from public.e10_invoice_po_allocations where organization_id=$1)+(select count(*) from public.e10_supplier_invoice_lines where organization_id=$1)+(select count(*) from public.e10_supplier_invoices where organization_id=$1)+(select count(*) from public.e10_stock_receipts where organization_id=$1)+(select count(*) from public.e10_organization_memberships where organization_id=$1)+(select count(*) from public.e10_organizations where id=$1)+(select count(*) from auth.users where id=$2) n",[x.org,x.prep])).rows[0].n);await Promise.all([s.end(),obs.end()]);if(residue)throw Error('cleanup residue '+residue);if(completed)console.log('TA-X3c concurrent command/receipt locks: PASS (fixture-free)');
 }
}
main().catch(e=>{console.error(e.stack);process.exit(1)});
