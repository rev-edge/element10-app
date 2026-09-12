// TA-X4e: a receipt waiting behind invoice void must reread the terminal invoice state.
const { Client } = require('pg');
const { randomUUID } = require('crypto');
const CONN = process.env.E10_DB_URL || 'postgresql://postgres:postgres@127.0.0.1:54322/postgres';
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
const org = 'e1000000-0000-4000-8000-0000000000a6';
const x = Object.fromEntries(['user','role','supplier','location','product','config','po','poLine','invoice','invoiceLine','directInvoice','directInvoiceLine'].map((k) => [k, randomUUID()]));
x.item = `x4e-race-${randomUUID()}`; x.item2=`x4e-race-${randomUUID()}`; x.run = randomUUID();
const jwt = JSON.stringify({ sub: x.user, role: 'authenticated' });
async function waitForLock(observer,pid,label){for(let i=0;i<400;i++){const q=await observer.query("select wait_event_type='Lock' waiting from pg_stat_activity where pid=$1",[pid]);if(q.rows[0]?.waiting)return;await sleep(10);}throw new Error(`${label} never established a real lock wait`);}

async function cleanup(c) {
  await c.query('set session_replication_role=replica');
  await c.query("delete from public.e10_integration_outbox where commercial_event_id in (select id from public.e10_commercial_events where subject_id=any($1::text[]) or payload->>'command' like $2)",[[x.item,x.item2],`x4e-receipt-${x.run}%`]);
  await c.query("delete from public.e10_commercial_events where subject_id=any($1::text[]) or payload->>'command' like $2",[[x.item,x.item2],`x4e-receipt-${x.run}%`]);
  await c.query("delete from public.e10_receipt_commands where organization_id=$1 and idempotency_key like $2",[org,`x4e-receipt-${x.run}%`]);
  await c.query('delete from public.e10_inventory_lots where organization_id=$1 and inventory_item_id=any($2::text[])',[org,[x.item,x.item2]]);
  await c.query('delete from public.e10_receipt_po_allocations where organization_id=$1 and purchase_order_line_id=$2',[org,x.poLine]);
  await c.query('delete from public.e10_receipt_invoice_allocations where organization_id=$1 and invoice_line_id=$2',[org,x.invoiceLine]);
  await c.query("delete from public.e10_stock_receipt_lines where organization_id=$1 and stock_receipt_id in(select id from public.e10_stock_receipts where organization_id=$1 and idempotency_key like $2)",[org,`x4e-receipt-${x.run}%`]);
  await c.query("delete from public.e10_stock_receipts where organization_id=$1 and idempotency_key like $2",[org,`x4e-receipt-${x.run}%`]);
  await c.query('delete from public.e10_inventory_movements where organization_id=$1 and item_id=any($2::text[])',[org,[x.item,x.item2]]);
  await c.query('delete from public.e10_financial_document_events where organization_id=$1 and document_id=any($2::uuid[])',[org,[x.invoice,x.directInvoice]]);
  await c.query('delete from public.e10_financial_document_commands where organization_id=$1 and document_id=any($2::uuid[])',[org,[x.invoice,x.directInvoice]]);
  await c.query('delete from public.e10_supplier_invoice_revisions where organization_id=$1 and supplier_invoice_id=any($2::uuid[])',[org,[x.invoice,x.directInvoice]]);
  await c.query('delete from public.e10_supplier_invoice_lines where organization_id=$1 and supplier_invoice_id=any($2::uuid[])',[org,[x.invoice,x.directInvoice]]);
  await c.query('delete from public.e10_supplier_invoices where organization_id=$1 and id=any($2::uuid[])',[org,[x.invoice,x.directInvoice]]);
  await c.query('delete from public.e10_purchase_order_lines where organization_id=$1 and id=$2',[org,x.poLine]);
  await c.query('delete from public.e10_purchase_orders where organization_id=$1 and id=$2',[org,x.po]);
  await c.query('delete from public.e10_inventory_items where organization_id=$1 and id=any($2::text[])',[org,[x.item,x.item2]]);
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
    await setup.query("insert into public.e10_organization_role_permissions(organization_id,role_id,capability,allowed) values($1,$2,'act.create_receiving',true),($1,$2,'act.purchasing_cancel',true),($1,$2,'act.purchasing_prepare',true)",[org,x.role]);
    await setup.query("insert into public.e10_organization_memberships(organization_id,user_id,role_id,status) values($1,$2,$3,'active')",[org,x.user,x.role]);
    await setup.query("insert into public.e10_suppliers(id,organization_id,code,name,status) values($1,$2,$3,'X4e supplier','active')",[x.supplier,org,`X4E-${x.run}`]);
    await setup.query("insert into public.e10_locations(id,organization_id,code,name,status) values($1,$2,$3,'X4e location','active')",[x.location,org,`X4E-${x.run}`]);
    await setup.query('insert into public.e10_location_role_permissions(organization_id,location_id,role_id,can_receive) values($1,$2,$3,true)',[org,x.location,x.role]);
    await setup.query("insert into public.e10_product_masters(id,organization_id,name,status) values($1,$2,'X4e product','active')",[x.product,org]);
    await setup.query("insert into public.e10_product_configurations(id,organization_id,product_master_id,name,status) values($1,$2,$3,'Each','active')",[x.config,org,x.product]);
    await setup.query("insert into public.e10_product_configuration_versions(id,organization_id,configuration_id,version_no,state,packaging_kind,base_unit,base_units_per_package) values($1,$2,$1,1,'active','each','each',1)",[x.config,org]);
    await setup.query("insert into public.e10_inventory_items(id,name,qty,organization_id) values($1,'X4e item',0,$3),($2,'X4e item 2',0,$3)",[x.item,x.item2,org]);
    await setup.query("insert into public.e10_purchase_orders(id,organization_id,supplier_id,destination_location_id,status,currency,created_by)values($1,$2,$3,$4,'approved','CAD',$5)",[x.po,org,x.supplier,x.location,x.user]);
    await setup.query("insert into public.e10_purchase_order_lines(id,organization_id,purchase_order_id,configuration_version_id,line_no,ordered_quantity,state)values($1,$2,$3,$4,1,5,'active')",[x.poLine,org,x.po,x.config]);
    await setup.query("insert into public.e10_supplier_invoices(id,organization_id,supplier_id,supplier_document_number,status,currency,created_by) values($1,$2,$3,$4,'draft','CAD',$5)",[x.invoice,org,x.supplier,`X4E-${x.run}`,x.user]);
    await setup.query("insert into public.e10_supplier_invoice_lines(id,organization_id,supplier_invoice_id,configuration_version_id,line_no,invoiced_quantity,line_amount,state) values($1,$2,$3,$4,1,5,50,'active')",[x.invoiceLine,org,x.invoice,x.config]);
    await setup.query("insert into public.e10_supplier_invoices(id,organization_id,supplier_id,supplier_document_number,status,currency,created_by) values($1,$2,$3,$4,'draft','CAD',$5)",[x.directInvoice,org,x.supplier,`X4E-DIRECT-${x.run}`,x.user]);
    await setup.query("insert into public.e10_supplier_invoice_lines(id,organization_id,supplier_invoice_id,configuration_version_id,line_no,invoiced_quantity,line_amount,state) values($1,$2,$3,$4,1,5,50,'active')",[x.directInvoiceLine,org,x.directInvoice,x.config]);

    await A.query('begin');
    await A.query("select e10.lock_financial_document($1,'supplier_invoice',$2)",[org,x.invoice]);
    await A.query('select set_config($1,$2,true)',['request.jwt.claims',jwt]); await A.query('set local role authenticated');
    await B.query('begin'); await B.query('select set_config($1,$2,true)',['request.jwt.claims',jwt]); await B.query('set local role authenticated');
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
    const proof=(await setup.query("select i.status,(select count(*) from public.e10_stock_receipts where organization_id=$1 and idempotency_key=$3) receipts,(select count(*) from public.e10_receipt_invoice_allocations where organization_id=$1 and invoice_line_id=$5) allocations,(select qty from public.e10_inventory_items where organization_id=$1 and id=$4) qty from public.e10_supplier_invoices i where i.organization_id=$1 and i.id=$2",[org,x.invoice,`x4e-receipt-${x.run}`,x.item,x.invoiceLine])).rows[0];
    if(proof.status!=='void'||Number(proof.receipts)!==0||Number(proof.allocations)!==0||Number(proof.qty)!==0)
      throw new Error('losing receipt left residue: '+JSON.stringify(proof));

    // Reverse direction: receipt commits while void waits, then void must see the
    // physical allocation and fail rather than orphaning it.
    await setup.query("update public.e10_supplier_invoices set status='draft' where organization_id=$1 and id=$2",[org,x.invoice]);
    const receiptLines=JSON.stringify([{line_no:1,configuration_version_id:x.config,inventory_item_id:x.item2,accepted_quantity:3,damaged_quantity:0,quarantined_quantity:0,actual_unit_cost:10,currency:'CAD',purchase_order_line_id:x.poLine,invoice_line_id:x.invoiceLine,expected_allocations:[]}]);
    await A.query('begin');await A.query('select set_config($1,$2,true)',['request.jwt.claims',jwt]);await A.query('set local role authenticated');
    const receiptWon=(await A.query('select public.e10_org_receive_batch($1,$2,$3,now(),$4::jsonb,$5) r',[org,x.supplier,x.location,receiptLines,`x4e-receipt-${x.run}-wins`])).rows[0].r;
    await B.query('begin');await B.query('select set_config($1,$2,true)',['request.jwt.claims',jwt]);await B.query('set local role authenticated');
    const voidPid=(await B.query('select pg_backend_pid() pid')).rows[0].pid;let voidError;
    const voidCall=B.query("select public.e10_org_void_supplier_invoice($1,$2,2,'receipt wins race',$3)",[org,x.invoice,`x4e-void-after-${x.run}`]).catch(e=>{voidError=e;});
    await waitForLock(setup,voidPid,'void backend');
    await A.query('commit');await voidCall;await B.query('rollback').catch(()=>{});
    if(!receiptWon.ok||!voidError||voidError.code!=='55000'||voidError.message!=='financial_document_has_active_allocations')throw new Error(`receipt-wins outcome invalid receipt=${JSON.stringify(receiptWon)} void=${voidError&&voidError.code}:${voidError&&voidError.message}`);
    const protectedProof=(await setup.query("select i.status,(select sum(a.allocated_quantity) from public.e10_receipt_invoice_allocations a where a.organization_id=$1 and a.invoice_line_id=$3) allocated,(select qty from public.e10_inventory_items where organization_id=$1 and id=$4) qty from public.e10_supplier_invoices i where i.organization_id=$1 and i.id=$2",[org,x.invoice,x.invoiceLine,x.item2])).rows[0];
    if(protectedProof.status!=='draft'||Number(protectedProof.allocated)!==3||Number(protectedProof.qty)!==3)throw new Error('receipt-wins protection residue invalid: '+JSON.stringify(protectedProof));

    // Competing PO and invoice capacity: A consumes the exact remainder while B
    // waits on the shared document hierarchy, then B must fail atomically.
    const capacityLines=JSON.stringify([{line_no:1,configuration_version_id:x.config,inventory_item_id:x.item2,accepted_quantity:2,damaged_quantity:0,quarantined_quantity:0,actual_unit_cost:10,currency:'CAD',purchase_order_line_id:x.poLine,invoice_line_id:x.invoiceLine,expected_allocations:[]}]);
    await A.query('begin');await A.query('select set_config($1,$2,true)',['request.jwt.claims',jwt]);await A.query('set local role authenticated');
    const capacityWinner=(await A.query('select public.e10_org_receive_batch($1,$2,$3,now(),$4::jsonb,$5) r',[org,x.supplier,x.location,capacityLines,`x4e-receipt-${x.run}-capacity-winner`])).rows[0].r;
    await B.query('begin');await B.query('select set_config($1,$2,true)',['request.jwt.claims',jwt]);await B.query('set local role authenticated');
    const capacityPid=(await B.query('select pg_backend_pid() pid')).rows[0].pid;let capacityError;
    const losingCall=B.query('select public.e10_org_receive_batch($1,$2,$3,now(),$4::jsonb,$5)',[org,x.supplier,x.location,capacityLines,`x4e-receipt-${x.run}-capacity-loser`]).catch(e=>{capacityError=e;});
    await waitForLock(setup,capacityPid,'capacity backend');
    await A.query('commit');await losingCall;await B.query('rollback').catch(()=>{});
    if(!capacityWinner.ok||!capacityError||capacityError.code!=='23514')throw new Error(`capacity race invalid winner=${JSON.stringify(capacityWinner)} loser=${capacityError&&capacityError.code}:${capacityError&&capacityError.message}`);
    const capacityProof=(await setup.query("select (select sum(a.allocated_quantity) from public.e10_receipt_invoice_allocations a where a.organization_id=$1 and a.invoice_line_id=$2) invoice_qty,(select sum(a.allocated_quantity) from public.e10_receipt_po_allocations a where a.organization_id=$1 and a.purchase_order_line_id=$3) po_qty,(select count(*) from public.e10_stock_receipts where organization_id=$1 and idempotency_key=$4) loser_receipts",[org,x.invoiceLine,x.poLine,`x4e-receipt-${x.run}-capacity-loser`])).rows[0];
    if(Number(capacityProof.invoice_qty)!==5||Number(capacityProof.po_qty)!==5||Number(capacityProof.loser_receipts)!==0)throw new Error('capacity loser residue: '+JSON.stringify(capacityProof));

    // Invoice-only receipt wins while an incompatible amendment waits. The
    // authenticated amend RPC must reread the physical link and preserve the
    // invoice currency, configuration and quantity.
    const direct3=JSON.stringify([{line_no:1,configuration_version_id:x.config,inventory_item_id:x.item,accepted_quantity:3,damaged_quantity:0,quarantined_quantity:0,actual_unit_cost:10,currency:'CAD',invoice_line_id:x.directInvoiceLine,expected_allocations:[]}]);
    await A.query('begin');await A.query('select set_config($1,$2,true)',['request.jwt.claims',jwt]);await A.query('set local role authenticated');
    const directWinner=(await A.query('select public.e10_org_receive_batch($1,$2,$3,now(),$4::jsonb,$5) r',[org,x.supplier,x.location,direct3,`x4e-receipt-${x.run}-direct3`])).rows[0].r;
    await B.query('begin');await B.query('select set_config($1,$2,true)',['request.jwt.claims',jwt]);await B.query('set local role authenticated');
    const amendPid=(await B.query('select pg_backend_pid() pid')).rows[0].pid;let amendError;
    const amendLines=JSON.stringify([{id:x.directInvoiceLine,line_no:1,configuration_version_id:null,description:'incompatible',invoiced_quantity:2,unit_cost:10,line_amount:20}]);
    const amendCall=B.query("select public.e10_org_amend_supplier_invoice($1,$2,1,'USD',null,20,$3::jsonb,'incompatible after receipt',$4)",[org,x.directInvoice,amendLines,`x4e-amend-${x.run}`]).catch(e=>{amendError=e;});
    await waitForLock(setup,amendPid,'amend backend');await A.query('commit');await amendCall;await B.query('rollback').catch(()=>{});
    if(!directWinner.ok||!amendError||amendError.code!=='55000')throw new Error(`receipt/amend race invalid winner=${JSON.stringify(directWinner)} amend=${amendError&&amendError.code}:${amendError&&amendError.message}`);
    const amendProof=(await setup.query('select i.currency,i.revision,l.configuration_version_id,l.invoiced_quantity from public.e10_supplier_invoices i join public.e10_supplier_invoice_lines l on l.organization_id=i.organization_id and l.supplier_invoice_id=i.id where i.organization_id=$1 and i.id=$2',[org,x.directInvoice])).rows[0];
    if(amendProof.currency!=='CAD'||Number(amendProof.revision)!==1||amendProof.configuration_version_id!==x.config||Number(amendProof.invoiced_quantity)!==5)throw new Error('amend changed receipt-linked source: '+JSON.stringify(amendProof));

    // Independent invoice-only capacity race, with no PO allocation available to
    // reject first. A fills the exact remainder; B waits then fails invoice capacity.
    const direct2=JSON.stringify([{line_no:1,configuration_version_id:x.config,inventory_item_id:x.item,accepted_quantity:2,damaged_quantity:0,quarantined_quantity:0,actual_unit_cost:10,currency:'CAD',invoice_line_id:x.directInvoiceLine,expected_allocations:[]}]);
    await A.query('begin');await A.query('select set_config($1,$2,true)',['request.jwt.claims',jwt]);await A.query('set local role authenticated');
    const directCapacityWinner=(await A.query('select public.e10_org_receive_batch($1,$2,$3,now(),$4::jsonb,$5) r',[org,x.supplier,x.location,direct2,`x4e-receipt-${x.run}-direct2-winner`])).rows[0].r;
    await B.query('begin');await B.query('select set_config($1,$2,true)',['request.jwt.claims',jwt]);await B.query('set local role authenticated');
    const directCapacityPid=(await B.query('select pg_backend_pid() pid')).rows[0].pid;let directCapacityError;
    const directCapacityCall=B.query('select public.e10_org_receive_batch($1,$2,$3,now(),$4::jsonb,$5)',[org,x.supplier,x.location,direct2,`x4e-receipt-${x.run}-direct2-loser`]).catch(e=>{directCapacityError=e;});
    await waitForLock(setup,directCapacityPid,'invoice-only capacity backend');await A.query('commit');await directCapacityCall;await B.query('rollback').catch(()=>{});
    if(!directCapacityWinner.ok||!directCapacityError||directCapacityError.code!=='23514'||directCapacityError.message!=='invoice_receipt_overallocated')throw new Error(`invoice-only capacity invalid winner=${JSON.stringify(directCapacityWinner)} loser=${directCapacityError&&directCapacityError.code}:${directCapacityError&&directCapacityError.message}`);
    const directCapacityProof=(await setup.query("select (select sum(a.allocated_quantity) from public.e10_receipt_invoice_allocations a where a.organization_id=$1 and a.invoice_line_id=$2) allocated,(select count(*) from public.e10_receipt_po_allocations p join public.e10_stock_receipt_lines l on l.organization_id=p.organization_id and l.id=p.receipt_line_id join public.e10_stock_receipts r on r.organization_id=l.organization_id and r.id=l.stock_receipt_id where r.organization_id=$1 and r.idempotency_key like $3) po_rows,(select count(*) from public.e10_stock_receipts where organization_id=$1 and idempotency_key=$4) loser_receipts",[org,x.directInvoiceLine,`x4e-receipt-${x.run}-direct%`, `x4e-receipt-${x.run}-direct2-loser`])).rows[0];
    if(Number(directCapacityProof.allocated)!==5||Number(directCapacityProof.po_rows)!==0||Number(directCapacityProof.loser_receipts)!==0)throw new Error('invoice-only capacity residue: '+JSON.stringify(directCapacityProof));
    console.log(`TA-X4e source races: PASS (void ${bpid}; receipt ${voidPid}; combined capacity ${capacityPid}; amend ${amendPid}; invoice-only capacity ${directCapacityPid})`);
  } finally {
    await A.query('rollback').catch(()=>{}); await B.query('rollback').catch(()=>{}); await setup.query('rollback').catch(()=>{});
    await cleanup(setup); await Promise.all([A.end(),B.end(),setup.end()]);
  }
}
main().catch((e)=>{console.error('TA-X4e invoice-void concurrent test ERROR: '+(e.stack||e.message));process.exit(1);});
