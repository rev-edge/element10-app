const { Client } = require('pg');

const connectionString = process.env.DATABASE_URL || 'postgresql://postgres:postgres@127.0.0.1:54322/postgres';
const run = Date.now().toString();
const ids = {
  org: 'd3110000-0000-4000-8000-000000000001',
  actor: 'd3110000-0000-4000-8000-000000000002',
  role: 'd3110000-0000-4000-8000-000000000003',
  supplier: 'd3110000-0000-4000-8000-000000000004',
  lineCommand: 'd3110000-0000-4000-8000-000000000005',
  lineIdentity: 'd3110000-0000-4000-8000-000000000006',
};
const timeoutMs = 8000;
const admin = new Client({ connectionString });
const a = new Client({ connectionString });
const b = new Client({ connectionString });

async function claims(client) {
  await client.query('set local role authenticated');
  await client.query(
    `select set_config('request.jwt.claims',$1,true)`,
    [JSON.stringify({ sub: ids.actor, role: 'authenticated' })],
  );
}

async function waitBlocked(pid) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const q = await admin.query(
      `select count(*)::int n from pg_locks where pid=$1 and locktype='advisory' and not granted`,
      [pid],
    );
    if (q.rows[0].n > 0) return;
    await new Promise((resolve) => setTimeout(resolve, 25));
  }
  throw new Error(`backend ${pid} did not reach the expected advisory-lock wait`);
}

function create(client, number, lineId, key) {
  return client.query(
    `select public.e10_org_create_supplier_invoice(
      $1,$2,$3,'CAD',null,10,null,null,null,null,null,
      jsonb_build_array(jsonb_build_object('id',$4::text,'line_no',1,'line_amount',10)),$5
    ) result`,
    [ids.org, ids.supplier, number, lineId, key],
  );
}

async function bounded(promise) {
  let timer;
  try {
    return await Promise.race([
      promise,
      new Promise((_, reject) => { timer = setTimeout(() => reject(new Error('bounded create timeout')), timeoutMs); }),
    ]);
  } finally { clearTimeout(timer); }
}

async function main() {
  await Promise.all([admin.connect(), a.connect(), b.connect()]);
  await admin.query('begin');
  await admin.query(
    `insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at)
       values($1,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',$2,now(),now())`,
    [ids.actor, `x3d1a-${run}@example.invalid`],
  );
  await admin.query(`insert into public.e10_organizations(id,name,slug) values($1,'X3d1a race',$2)`,
    [ids.org, `x3d1a-race-${run}`]);
  await admin.query(`insert into public.e10_organization_roles(id,organization_id,key,name)
    values($1,$2,'x3d1a-race','X3d1a race')`, [ids.role, ids.org]);
  await admin.query(`insert into public.e10_organization_memberships(organization_id,user_id,role_id,status)
    values($1,$2,$3,'active')`, [ids.org, ids.actor, ids.role]);
  await admin.query(`insert into public.e10_organization_role_permissions(organization_id,role_id,capability,allowed)
    values($1,$2,'act.purchasing_prepare',true)`, [ids.org, ids.role]);
  await admin.query(`insert into public.e10_suppliers(id,organization_id,name,status)
    values($1,$2,'X3d1a race supplier','active')`, [ids.supplier, ids.org]);
  await admin.query('commit');

  const commandKey = `x3d1a-command-${run}`;
  await a.query('begin');
  await claims(a);
  await a.query(`select pg_advisory_xact_lock(hashtextextended($1,0))`, [`${ids.org}|financial-document-command|${commandKey}`]);
  await b.query('begin');
  await claims(b);
  const bPid = (await b.query('select pg_backend_pid() pid')).rows[0].pid;
  const blockedCommand = create(b, `CMD-${run}`, ids.lineCommand, commandKey);
  await waitBlocked(bPid);
  const winner = await create(a, `CMD-${run}`, ids.lineCommand, commandKey);
  await a.query('commit');
  const replay = await bounded(blockedCommand);
  await b.query('commit');
  if (replay.rows[0].result.replay !== true
    || replay.rows[0].result.supplier_invoice_id !== winner.rows[0].result.supplier_invoice_id) {
    throw new Error('command-lock replay did not return the committed winner');
  }
  console.log(`[proof] backend ${bPid} waited on the exact command key; one create and one replay`);

  const identityNumber = `IDENTITY-${run}`;
  const keyA = `x3d1a-identity-a-${run}`;
  const keyB = `x3d1a-identity-b-${run}`;
  await a.query('begin');
  await claims(a);
  await a.query(
    `select pg_advisory_xact_lock(hashtextextended($1,0))`,
    [`${ids.org}|supplier_invoice|manual|${ids.supplier}|${identityNumber.toLowerCase()}`],
  );
  await b.query('begin');
  await claims(b);
  const identityPid = (await b.query('select pg_backend_pid() pid')).rows[0].pid;
  const blockedIdentity = create(b, identityNumber.toLowerCase(), ids.lineIdentity, keyB);
  await waitBlocked(identityPid);
  const identityWinner = await create(a, identityNumber, ids.lineIdentity, keyA);
  await a.query('commit');
  const identityReplay = await bounded(blockedIdentity);
  await b.query('commit');
  if (identityReplay.rows[0].result.identity_replay !== true
    || identityReplay.rows[0].result.supplier_invoice_id !== identityWinner.rows[0].result.supplier_invoice_id) {
    throw new Error('identity-lock replay did not converge on the committed document');
  }
  const count = await admin.query(
    `select count(*)::int n from public.e10_supplier_invoices
      where organization_id=$1 and supplier_id=$2 and lower(btrim(supplier_document_number))=lower($3)`,
    [ids.org, ids.supplier, identityNumber],
  );
  if (count.rows[0].n !== 1) throw new Error(`identity race created ${count.rows[0].n} documents`);
  console.log(`[proof] backend ${identityPid} waited on the exact manual identity; two command keys converged on one document`);
  console.log('TA-X3d.1a concurrent create: PASS (fixture-free)');
}

async function cleanup() {
  try {
    await admin.query('begin');
    await admin.query(`set local session_replication_role='replica'`);
    await admin.query('delete from public.e10_financial_document_events where organization_id=$1', [ids.org]);
    await admin.query('delete from public.e10_financial_document_reconciliation_cases where organization_id=$1', [ids.org]);
    await admin.query('delete from public.e10_financial_document_commands where organization_id=$1', [ids.org]);
    await admin.query('delete from public.e10_supplier_invoice_revisions where organization_id=$1', [ids.org]);
    await admin.query('delete from public.e10_supplier_invoice_lines where organization_id=$1', [ids.org]);
    await admin.query('delete from public.e10_supplier_invoices where organization_id=$1', [ids.org]);
    await admin.query('delete from public.e10_suppliers where organization_id=$1', [ids.org]);
    await admin.query('delete from public.e10_organization_role_permissions where organization_id=$1', [ids.org]);
    await admin.query('delete from public.e10_organization_memberships where organization_id=$1', [ids.org]);
    await admin.query('delete from public.e10_organization_roles where organization_id=$1', [ids.org]);
    await admin.query('delete from public.e10_organizations where id=$1', [ids.org]);
    await admin.query('delete from auth.users where id=$1', [ids.actor]);
    await admin.query('commit');
  } catch (error) {
    try { await admin.query('rollback'); } catch {}
    throw error;
  }
}

main().finally(async () => {
  await Promise.allSettled([a.query('rollback'), b.query('rollback')]);
  try { await cleanup(); } catch (error) { console.error(error); process.exitCode = 1; }
  await Promise.allSettled([admin.end(), a.end(), b.end()]);
}).catch((error) => { console.error(error); process.exitCode = 1; });
