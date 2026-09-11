const { Client } = require('pg');

const connectionString = process.env.DATABASE_URL || 'postgresql://postgres:postgres@127.0.0.1:54322/postgres';
const run = Date.now().toString();
const x = {
  org: 'd31e0000-0000-4000-8000-000000000001', actor: 'd31e0000-0000-4000-8000-000000000002',
  role: 'd31e0000-0000-4000-8000-000000000003', supplier: 'd31e0000-0000-4000-8000-000000000004',
  invoice: 'd31e0000-0000-4000-8000-000000000005', line: 'd31e0000-0000-4000-8000-000000000006',
};
const timeoutMs = 8000;
const admin = new Client({ connectionString });
const a = new Client({ connectionString });
const b = new Client({ connectionString });

async function claims(client) {
  await client.query('set local role authenticated');
  await client.query(`select set_config('request.jwt.claims',$1,true)`,
    [JSON.stringify({ sub: x.actor, role: 'authenticated' })]);
}
async function waitBlocked(pid) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const q = await admin.query(`select count(*)::int n from pg_locks
      where pid=$1 and locktype='advisory' and not granted`, [pid]);
    if (q.rows[0].n === 1) return;
    await new Promise((resolve) => setTimeout(resolve, 25));
  }
  throw new Error(`backend ${pid} did not reach the exact document-lock wait`);
}
async function bounded(promise) {
  let timer;
  try {
    return await Promise.race([promise, new Promise((_, reject) => {
      timer = setTimeout(() => reject(new Error('bounded transition timeout')), timeoutMs);
    })]);
  } finally { clearTimeout(timer); }
}
function review(client, key) {
  return client.query(`select public.e10_org_review_supplier_invoice($1,$2,1,$3,$4) result`,
    [x.org, x.invoice, key, key]);
}
function approve(client, key) {
  return client.query(`select public.e10_org_approve_supplier_invoice($1,$2,2,$3,$4) result`,
    [x.org, x.invoice, key, key]);
}

async function setup() {
  await admin.query(`insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at)
    values($1,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',$2,now(),now())`,
  [x.actor, `x3d1c-${run}@example.invalid`]);
  await admin.query(`insert into public.e10_organizations(id,name,slug) values($1,'X3d1c race',$2)`,
    [x.org, `x3d1c-race-${run}`]);
  await admin.query(`insert into public.e10_organization_roles(id,organization_id,key,name)
    values($1,$2,'x3d1c-race','X3d1c race')`, [x.role, x.org]);
  await admin.query(`insert into public.e10_organization_memberships(organization_id,user_id,role_id,status)
    values($1,$2,$3,'active')`, [x.org, x.actor, x.role]);
  await admin.query(`insert into public.e10_organization_role_permissions(organization_id,role_id,capability,allowed)
    values($1,$2,'act.purchasing_prepare',true),($1,$2,'act.purchasing_approve',true)`, [x.org, x.role]);
  await admin.query(`insert into public.e10_suppliers(id,organization_id,name,status)
    values($1,$2,'X3d1c race supplier','active')`, [x.supplier, x.org]);
  await admin.query(`insert into public.e10_supplier_invoices
    (id,organization_id,supplier_id,supplier_document_number,currency,total_amount,created_by)
    values($1,$2,$3,$4,'CAD',10,$5)`, [x.invoice, x.org, x.supplier, `RACE-${run}`, x.actor]);
  await admin.query(`insert into public.e10_supplier_invoice_lines
    (id,organization_id,supplier_invoice_id,line_no,invoiced_quantity,unit_cost,line_amount)
    values($1,$2,$3,1,1,10,10)`, [x.line, x.org, x.invoice]);
}

async function main() {
  await Promise.all([admin.connect(), a.connect(), b.connect()]); await setup();
  await a.query('begin'); await claims(a);
  await a.query(`select pg_advisory_xact_lock(hashtextextended($1,0))`,
    [`${x.org}|financial-document|supplier_invoice|${x.invoice}`]);
  await b.query('begin'); await claims(b);
  const pid = (await b.query('select pg_backend_pid() pid')).rows[0].pid;
  const blocked = review(b, `x3d1c-review-b-${run}`);
  await waitBlocked(pid);
  const winner = await review(a, `x3d1c-review-a-${run}`);
  await a.query('commit');
  let stale; try { await bounded(blocked); } catch (error) { stale = error; }
  await b.query('rollback');
  if (winner.rows[0].result.revision !== 2 || !stale || stale.code !== '40001')
    throw new Error(`transition CAS race invalid: winner=${JSON.stringify(winner.rows[0])}, loser=${stale && stale.code}`);
  console.log(`[proof] backend ${pid} waited on exact document lock; one reviewed successor, stale peer denied`);

  await a.query('begin');
  await a.query(`select pg_advisory_xact_lock(hashtextextended($1,0))`,
    [`${x.org}|financial-document|supplier_invoice|${x.invoice}`]);
  await b.query('begin'); await claims(b);
  const revokePid = (await b.query('select pg_backend_pid() pid')).rows[0].pid;
  const blockedApprove = approve(b, `x3d1c-approve-revoked-${run}`);
  await waitBlocked(revokePid);
  await admin.query(`delete from public.e10_organization_role_permissions
    where organization_id=$1 and role_id=$2 and capability='act.purchasing_approve'`, [x.org, x.role]);
  await a.query('commit');
  let denied; try { await bounded(blockedApprove); } catch (error) { denied = error; }
  await b.query('rollback');
  if (!denied || denied.code !== '42501') throw new Error(`post-lock approval revocation failed: ${denied && denied.code}`);
  const state = await admin.query(`select status,revision from public.e10_supplier_invoices where id=$1`, [x.invoice]);
  if (state.rows[0].status !== 'reviewed' || state.rows[0].revision !== 2) throw new Error('revoked approval mutated document');
  console.log(`[proof] backend ${revokePid} reread approval capability after exact document-lock wait; no residue`);
}

async function cleanup() {
  await admin.query('begin'); await admin.query(`set local session_replication_role='replica'`);
  for (const t of ['e10_financial_document_events','e10_financial_document_commands','e10_supplier_invoice_revisions',
    'e10_supplier_invoice_lines','e10_supplier_invoices','e10_suppliers','e10_organization_role_permissions',
    'e10_organization_memberships','e10_organization_roles'])
    await admin.query(`delete from public.${t} where organization_id=$1`, [x.org]);
  await admin.query('delete from public.e10_organizations where id=$1', [x.org]);
  await admin.query('delete from auth.users where id=$1', [x.actor]); await admin.query('commit');
  const residue = await admin.query(`select
    (select count(*) from public.e10_supplier_invoices where organization_id=$1)+
    (select count(*) from public.e10_financial_document_commands where organization_id=$1)+
    (select count(*) from public.e10_organizations where id=$1)+(select count(*) from auth.users where id=$2) n`, [x.org, x.actor]);
  if (Number(residue.rows[0].n)) throw new Error(`X3d.1c cleanup residue=${residue.rows[0].n}`);
}

(async () => {
  try { await main(); await Promise.allSettled([a.query('rollback'), b.query('rollback')]); await cleanup();
    console.log('TA-X3d.1c concurrent transitions: PASS (fixture-free)');
  } catch (error) { await Promise.allSettled([a.query('rollback'), b.query('rollback')]);
    try { await cleanup(); } catch (cleanupError) { console.error(cleanupError); }
    console.error(error); process.exitCode = 1;
  } finally { await Promise.allSettled([admin.end(), a.end(), b.end()]); }
})();
