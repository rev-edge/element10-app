// TA-X4e: a receipt waiting behind invoice void must reread the terminal invoice state.
const { Client } = require('pg');
const { randomUUID } = require('crypto');
const CONN = process.env.E10_DB_URL || 'postgresql://postgres:postgres@127.0.0.1:54322/postgres';
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
const org = 'e1000000-0000-4000-8000-0000000000a6';
const x = Object.fromEntries(['user','role','supplier','location','product','config','invoice','invoiceLine'].map((k) => [k, randomUUID()]));
x.item = `x4e-race-${randomUUID()}`; x.run = randomUUID();
const jwt = JSON.stringify({ sub: x.user, role: 'authenticated' });

async function cleanup(c) {
  await c.query('set session_replication_role=replica');
  await c.query("delete from public.e10_integration_outbox where commercial_event_id in (select id from public.e10_commercial_events where subject_id=$1 or payload->>'command'=$2)",[x.item,`x4e-receipt-${x.run}`]);
  await c.query("delete from public.e10_commercial_events where subject_id=$1 or payload->>'command'=$2",[x.item,`x4e-receipt-${x.run}`]);
  await c.query('delete from public.e10_receipt_commands where organization_id=$1 and idempotency_key=$2',[org,`x4e-receipt-${x.run}`]);
  await c.query('delete from public.e10_inventory_lots where organization_id=$1 and inventory_item_id=$2',[org,x.item]);
  await c.query('delete from public.e10_receipt_invoice_allocations where organization_id=$1 and invoice_line_id=$2',[org,x.invoiceLine]);
  await c.query("delete from public.e10_stock_receipt_lines where organization_id=$1 and stock_receipt_id in(select id from public.e10_stock_receipts where organization_id=$1 and idempotency_key=$2)",[org,`x4e-receipt-${x.run}`]);
  await c.query('delete from public.e10_stock_receipts where organization_id=$1 and idempotency_key=$2',[org,`x4e-receipt-${x.run}`]);
  await c.query('delete from public.e10_inventory_movements where organization_id=$1 and item_id=$2',[org,x.item]);
  await c.query('delete from public.e10_financial_document_events where organization_id=$1 and document_id=$2',[org,x.invoice]);
  await c.query("delete from public.e10_financial_document_commands where organization_id=$1 and idempotency_key=$2",[org,`x4e-void-${x.run}`]);
  await c.query('delete from public.e10_supplier_invoice_revisions where organization_id=$1 and supplier_invoice_id=$2',[org,x.invoice]);
  await c.query('delete from public.e10_supplier_invoice_lines where organization_id=$1 and supplier_invoice_id=$2',[org,x.invoice]);
  await c.query('delete from public.e10_supplier_invoices where organization_id=$1 and id=$2',[org,x.invoice]);
  await c.query('delete from public.e10_inventory_items where organization_id=$1 and id=$2',[org,x.item]);
  await c.query('delete from public.e10_product_configuration_versions where organization_id=$1 and id=$2',[org,x.config]);
  await c.query('delete from public.e10_product_configurations where organization_id=$1 and id=$2',[org,x.config]);
  await c.query('delete from public.e10_product_masters where organization_id=$1 and id=$2',[org,x.product]);
  await c.query('delete from public.e10_location_role_permissions where organization_id=$1 and location_id=$2',[org,x.location]);
  await c.query('delete from public.e10_locations where organization_id=$1 and id=$2',[org,x.location]);
  await c.query('delete from public.e10_suppliers where organization_id=$1 and id=$2',[org,x.supplier]);
  await c.query('delete from public.e10_organization_memberships where organization_id=$1 and user_id=$2',[org,x.user]);
  await c.query('delete from public.e10_organization_role_permissions where organization_id=$1 and role_id=$2',[org,x.role]);
  await c.query('delete from public.e10_organization_roles where organization_id=$1 and id=$2',[org,x.role]);
  await c.query('delete from auth.users where id=$1',[x.user]);
  await c.query('set session_replication_role=origin');
}

async function main() {
  const setup = new Client({connectionString:CONN});
  const A = new Client({connectionString:CONN});
  const B = new Client({connectionString:CONN});
  await Promise.all([setup.connect(),A.connect(),B.connect()]);
  try {
    await cleanup(setup);
    await setup.query("insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at) values($1,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',$2,now(),now())",[x.user,`x4e-${x.run}@example.invalid`]);
    await setup.query("insert into public.e10_organization_roles(id,organization_id,key,name,is_system) values($1,$2,$3,'X4e race',false)",[x.role,org,`x4e-${x.run}`]);
    await setup.query("insert into public.e10_organization_role_permissions(organization_id,role_id,capability,allowed) values($1,$2,'act.create_receiving',true),($1,$2,'act.purchasing_cancel',true)",[org,x.role]);
    await setup.query("insert into public.e10_organization_memberships(organization_id,user_id,role_id,status) values($1,$2,$3,'active')",[org,x.user,x.role]);
    await setup.query("insert into public.e10_suppliers(id,organization_id,code,name,status) values($1,$2,$3,'X4e supplier','active')",[x.supplier,org,`X4E-${x.run}`]);
    await setup.query("insert into public.e10_locations(id,organization_id,code,name,status) values($1,$2,$3,'X4e location','active')",[x.location,org,`X4E-${x.run}`]);
    await setup.query('insert into public.e10_location_role_permissions(organization_id,location_id,role_id,can_receive) values($1,$2,$3,true)',[org,x.location,x.role]);
    await setup.query("insert into public.e10_product_masters(id,organization_id,name,status) values($1,$2,'X4e product','active')",[x.product,org]);
    await setup.query("insert into public.e10_product_configurations(id,organization_id,product_master_id,name,status) values($1,$2,$3,'Each','active')",[x.config,org,x.product]);
    await setup.query("insert into public.e10_product_configuration_versions(id,organization_id,configuration_id,version_no,state,packaging_kind,base_unit,base_units_per_package) values($1,$2,$1,1,'active','each','each',1)",[x.config,org]);
    await setup.query("insert into public.e10_inventory_items(id,name,qty,organization_id) values($1,'X4e item',0,$2)",[x.item,org]);
    await setup.query("insert into public.e10_supplier_invoices(id,organization_id,supplier_id,supplier_document_number,status,currency,created_by) values($1,$2,$3,$4,'draft','CAD',$5)",[x.invoice,org,x.supplier,`X4E-${x.run}`,x.user]);
    await setup.query("insert into public.e10_supplier_invoice_lines(id,organization_id,supplier_invoice_id,configuration_version_id,line_no,invoiced_quantity,line_amount,state) values($1,$2,$3,$4,1,5,50,'active')",[x.invoiceLine,org,x.invoice,x.config]);

    await A.query('begin'); await A.query('select set_config($1,$2,true)',['request.jwt.claims',jwt]);
    await A.query("select e10.lock_financial_document($1,'supplier_invoice',$2)",[org,x.invoice]);
    await B.query('begin'); await B.query('select set_config($1,$2,true)',['request.jwt.claims',jwt]);
    const bpid=(await B.query('select pg_backend_pid() pid')).rows[0].pid;
    let receiptError;
    const lines=JSON.stringify([{line_no:1,configuration_version_id:x.config,inventory_item_id:x.item,accepted_quantity:1,damaged_quantity:0,quarantined_quantity:0,actual_unit_cost:10,currency:'CAD',invoice_line_id:x.invoiceLine,expected_allocations:[]}]);
    const receiptCall=B.query('select public.e10_org_receive_batch($1,$2,$3,now(),$4::jsonb,$5)',[org,x.supplier,x.location,lines,`x4e-receipt-${x.run}`]).catch((e)=>{receiptError=e;});
    let waiting=false;
    for(let i=0;i<400;i++){
      const q=await setup.query("select wait_event_type='Lock' waiting from pg_stat_activity where pid=$1",[bpid]);
      if(q.rows[0]?.waiting){waiting=true;break;} await sleep(10);
    }
    if(!waiting) throw new Error('receipt backend never established a real lock wait');
    const voided=(await A.query("select public.e10_org_void_supplier_invoice($1,$2,1,'void wins race',$3) result",[org,x.invoice,`x4e-void-${x.run}`])).rows[0].result;
    await A.query('commit');
    await receiptCall; await B.query('rollback').catch(()=>{});
    if(voided.status!=='void' || !receiptError || receiptError.code!=='42501' || receiptError.message!=='invoice_line_access_denied')
      throw new Error(`unexpected outcomes void=${JSON.stringify(voided)} receipt=${receiptError&&receiptError.code}:${receiptError&&receiptError.message}`);
    const proof=(await setup.query("select i.status,(select count(*) from public.e10_stock_receipts where organization_id=$1 and idempotency_key=$3) receipts,(select count(*) from public.e10_receipt_invoice_allocations where organization_id=$1 and invoice_line_id=$2) allocations,(select qty from public.e10_inventory_items where organization_id=$1 and id=$4) qty from public.e10_supplier_invoices i where i.organization_id=$1 and i.id=$2",[org,x.invoice,`x4e-receipt-${x.run}`,x.item])).rows[0];
    if(proof.status!=='void'||Number(proof.receipts)!==0||Number(proof.allocations)!==0||Number(proof.qty)!==0)
      throw new Error('losing receipt left residue: '+JSON.stringify(proof));
    console.log(`TA-X4e invoice-void race: PASS (B pid=${bpid} waited; void won; receipt reread denied; zero residue)`);
  } finally {
    await A.query('rollback').catch(()=>{}); await B.query('rollback').catch(()=>{}); await setup.query('rollback').catch(()=>{});
    await cleanup(setup); await Promise.all([A.end(),B.end(),setup.end()]);
  }
}
main().catch((e)=>{console.error('TA-X4e invoice-void concurrent test ERROR: '+(e.stack||e.message));process.exit(1);});
