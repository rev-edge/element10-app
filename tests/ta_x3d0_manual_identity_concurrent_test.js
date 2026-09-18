const { Client } = require('pg');

const connectionString = process.env.DATABASE_URL || 'postgresql://postgres:postgres@127.0.0.1:54322/postgres';
const org = 'e1000000-0000-4000-8000-0000000000a6';
const supplier = 'd3000000-0000-4000-8000-000000000011';
const number = `X3D-RACE-${Date.now()}`;
const timeoutMs = 8000;

const admin = new Client({ connectionString });
const a = new Client({ connectionString });
const b = new Client({ connectionString });

async function waitForExactBlockedPid(pid) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const q = await admin.query(
      `select count(*)::int n from pg_locks where pid=$1 and locktype='advisory' and not granted`,
      [pid],
    );
    if (q.rows[0].n > 0) return;
    await new Promise((resolve) => setTimeout(resolve, 25));
  }
  throw new Error(`timeout waiting for backend ${pid} on exact manual-identity advisory lock`);
}

async function main() {
  await Promise.all([admin.connect(), a.connect(), b.connect()]);
  await admin.query(
    `insert into public.e10_suppliers(id,organization_id,name,status) values($1,$2,'X3d race supplier','active')`,
    [supplier, org],
  );
  const key = `${org}|supplier_invoice|manual|${supplier}|${number.toLowerCase()}`;
  await a.query('begin');
  await a.query('select pg_advisory_xact_lock(hashtextextended($1,0))', [key]);
  const pid = (await b.query('select pg_backend_pid() pid')).rows[0].pid;
  const blockedInsert = b.query(
    `insert into public.e10_supplier_invoices
       (organization_id,supplier_id,supplier_document_number,currency,total_amount)
     values($1,$2,$3,'CAD',1)`,
    [org, supplier, ` ${number.toLowerCase()} `],
  );
  await waitForExactBlockedPid(pid);
  await a.query(
    `insert into public.e10_supplier_invoices
       (organization_id,supplier_id,supplier_document_number,currency,total_amount)
     values($1,$2,$3,'CAD',1)`,
    [org, supplier, number],
  );
  await a.query('commit');
  let rejected = false;
  try {
    await Promise.race([
      blockedInsert,
      new Promise((_, reject) => setTimeout(() => reject(new Error('bounded duplicate insert timeout')), timeoutMs)),
    ]);
  } catch (error) {
    if (error.code === '23505' && error.message.includes('financial_manual_identity_conflict')) rejected = true;
    else throw error;
  }
  if (!rejected) throw new Error('concurrent normalized manual duplicate was accepted');
  const count = await admin.query(
    `select count(*)::int n from public.e10_supplier_invoices
      where organization_id=$1 and supplier_id=$2 and lower(btrim(supplier_document_number))=lower($3)`,
    [org, supplier, number],
  );
  if (count.rows[0].n !== 1) throw new Error(`expected one durable identity row, found ${count.rows[0].n}`);
  console.log(`[proof] backend ${pid} waited on the exact normalized manual-identity lock; one insert won and one failed 23505`);
  console.log('TA-X3d.0 concurrent manual identity: PASS (fixture-free)');
}

main().finally(async () => {
  try { await a.query('rollback'); } catch {}
  try { await admin.query('delete from public.e10_supplier_invoices where organization_id=$1 and supplier_id=$2', [org, supplier]); } catch {}
  try { await admin.query('delete from public.e10_suppliers where organization_id=$1 and id=$2', [org, supplier]); } catch {}
  await Promise.allSettled([admin.end(), a.end(), b.end()]);
}).catch((error) => { console.error(error); process.exitCode = 1; });
