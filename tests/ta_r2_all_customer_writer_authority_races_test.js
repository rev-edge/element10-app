const { Client } = require('pg');
const { randomUUID } = require('crypto');

const db = process.env.E10_DB_URL || 'postgresql://postgres:postgres@127.0.0.1:54322/postgres';
const org = 'e1000000-0000-4000-8000-0000000000a6';
const run = randomUUID();
const user = randomUUID();
const role = randomUUID();
const claims = JSON.stringify({ sub: user, role: 'authenticated' });
const bounded = (promise, label, ms = 8000) => Promise.race([
  promise,
  new Promise((_, reject) => setTimeout(() => reject(new Error(`${label} timeout after ${ms}ms`)), ms)),
]);

const cases = [
  {
    name: 'record_customer_activity', cap: 'act.record_commercial_events', message: 'record_customer_activity_denied',
    lock: key => `${org}|customer-activity|${key}`,
    call: key => ["select public.e10_org_record_customer_activity($1,'retail',null,null,'race',null,null,1,1,0,0,0,'CAD','manual',now(),'exact','manual',null,$2,$3,'{}','operator_asserted',$4)", [org, `${run}-source`, `${run}-event`, key]],
  },
  {
    name: 'create_customer', cap: 'act.manage_customers', message: 'manage_customer_denied',
    lock: key => `${org}|customer-mutation|${key}`,
    call: key => ['select public.e10_org_create_customer($1,$2,$3)', [org, `R2 ${run}`, key]],
  },
  {
    name: 'update_customer', cap: 'act.manage_customers', message: 'manage_customer_denied',
    lock: () => `${org}|customer-resolution-topology`,
    call: key => ["select public.e10_org_update_customer($1,$2,0,'R2','active',$3)", [org, randomUUID(), key]],
  },
  {
    name: 'decide_customer_identity', cap: 'act.manage_customers', message: 'manage_customer_identity_denied',
    lock: () => `${org}|customer-resolution-topology`,
    call: key => ["select public.e10_org_decide_customer_identity($1,$2,'alias',null,null,$3,'attach',null,'race','{}',$4)", [org, randomUUID(), `alias-${run}`, key]],
  },
  {
    name: 'attribute_customer_activity', cap: 'act.manage_customers', message: 'attribute_customer_activity_denied',
    activity: randomUUID(),
    lock(key, test) { return `${org}|activity-attribution|${test.activity}`; },
    call(key, test) { return ["select public.e10_org_attribute_customer_activity($1,$2,null,'race','{}',$3)", [org, test.activity, key]]; },
  },
  {
    name: 'create_customer_transaction_draft', cap: 'act.prepare_customer_transactions', message: 'prepare_customer_transaction_denied',
    lock: key => `${org}|customer-commercial|${key}`,
    call: key => ["select public.e10_org_create_customer_transaction_draft($1,$2,'CAD',now(),'exact','race','[]',$3)", [org, randomUUID(), key]],
  },
  {
    name: 'amend_customer_transaction_draft', cap: 'act.prepare_customer_transactions', message: 'prepare_customer_transaction_denied',
    lock: key => `${org}|customer-commercial|${key}`,
    call: key => ["select public.e10_org_amend_customer_transaction_draft($1,$2,1,$3,'CAD',now(),'exact','race','[]',$4)", [org, randomUUID(), randomUUID(), key]],
  },
  {
    name: 'approve_customer_transaction_draft', cap: 'act.approve_customer_transactions', message: 'approve_customer_transaction_denied',
    lock: key => `${org}|customer-commercial|${key}`,
    call: key => ['select public.e10_org_approve_customer_transaction_draft($1,$2,1,$3)', [org, randomUUID(), key]],
  },
  {
    name: 'reopen_customer_transaction_draft', cap: 'act.approve_customer_transactions', message: 'reopen_customer_transaction_denied',
    lock: key => `${org}|customer-commercial|${key}`,
    call: key => ["select public.e10_org_reopen_customer_transaction_draft($1,$2,1,'race',$3)", [org, randomUUID(), key]],
  },
  {
    name: 'post_customer_transaction_draft', cap: 'act.post_customer_transactions', message: 'post_customer_transaction_denied',
    lock: key => `${org}|customer-commercial|${key}`,
    call: key => ['select public.e10_org_post_customer_transaction_draft($1,$2,1,$3)', [org, randomUUID(), key]],
  },
  {
    name: 'adjust_customer_transaction', cap: 'act.adjust_customer_transactions', message: 'adjust_customer_transaction_denied',
    lock: key => `${org}|customer-commercial|${key}`,
    call: key => ["select public.e10_org_adjust_customer_transaction($1,$2,$3,'correction','increase','CAD',1,0,0,now(),'exact','race','manual',null,$4,$5,null,'{}',$6)", [org, randomUUID(), randomUUID(), `${run}-adjust-event`, `${run}-adjust-component`, key]],
  },
  {
    name: 'finalize_customer_transaction_component', cap: 'act.reconcile_customer_transactions', message: 'finalize_customer_component_denied',
    lock: key => `${org}|customer-commercial|${key}`,
    call: key => ["select public.e10_org_finalize_customer_transaction_component($1,$2,$3,'shipping',1,'CAD','race','manual',null,$4,$5,'{}',$6)", [org, randomUUID(), randomUUID(), `${run}-final-event`, `${run}-final-component`, key]],
  },
];

async function waitForExactBlock(observer, waiterPid, holderPid, label) {
  for (let i = 0; i < 80; i++) {
    const q = await observer.query(
      "select wait_event_type='Lock' and $2::int=any(pg_blocking_pids($1::int)) waiting from pg_stat_activity where pid=$1",
      [waiterPid, holderPid],
    );
    if (q.rows[0]?.waiting) return;
    await new Promise(resolve => setTimeout(resolve, 50));
  }
  throw new Error(`${label}: exact backend did not block on exact holder`);
}

async function main() {
  const holder = new Client({ connectionString: db });
  const writer = new Client({ connectionString: db });
  const admin = new Client({ connectionString: db });
  await Promise.all([holder.connect(), writer.connect(), admin.connect()]);
  try {
    await admin.query("insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at) values($1,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',$2,now(),now())", [user, `${run}@x.invalid`]);
    await admin.query("insert into public.e10_organization_roles(id,organization_id,key,name,is_system) values($1,$2,$3,'R2 authority races',false)", [role, org, run]);
    await admin.query('insert into public.e10_organization_memberships(organization_id,user_id,role_id,status) values($1,$2,$3,\'active\')', [org, user, role]);
    for (const cap of [...new Set(cases.map(test => test.cap))]) {
      await admin.query('insert into public.e10_organization_role_permissions(organization_id,role_id,capability,allowed) values($1,$2,$3,true)', [org, role, cap]);
    }
    await writer.query('select set_config($1,$2,false)', ['request.jwt.claims', claims]);
    await writer.query('set role authenticated');
    const writerPid = Number((await writer.query('select pg_backend_pid() pid')).rows[0].pid);
    const holderPid = Number((await holder.query('select pg_backend_pid() pid')).rows[0].pid);

    for (let i = 0; i < cases.length; i++) {
      const test = cases[i];
      const key = `${run}-${i}-${test.name}`;
      await holder.query('begin');
      await holder.query('select pg_advisory_xact_lock(hashtextextended($1,0))', [test.lock(key, test)]);
      const [sql, args] = test.call(key, test);
      const pending = writer.query(sql, args).then(
        value => ({ ok: true, value }),
        error => ({ ok: false, error }),
      );
      await waitForExactBlock(admin, writerPid, holderPid, test.name);
      await admin.query('delete from public.e10_organization_role_permissions where organization_id=$1 and role_id=$2 and capability=$3', [org, role, test.cap]);
      await holder.query('commit');
      const settled = await bounded(pending, test.name);
      const outcome = settled.ok
        ? { ok: true }
        : { ok: false, code: settled.error.code, message: settled.error.message };
      if (outcome.ok || outcome.code !== '42501' || outcome.message !== test.message) {
        throw new Error(`${test.name}: post-lock authority result ${JSON.stringify(outcome)}`);
      }
      await admin.query('insert into public.e10_organization_role_permissions(organization_id,role_id,capability,allowed) values($1,$2,$3,true)', [org, role, test.cap]);
      console.log(`[proof] ${test.name}: writer pid=${writerPid} blocked by holder pid=${holderPid}; revoked ${test.cap}; denied 42501`);
    }

    const residue = Number((await admin.query("select (select count(*) from public.e10_customer_mutation_receipts where idempotency_key like $1)+(select count(*) from public.e10_customer_commercial_receipts where idempotency_key like $1)+(select count(*) from public.e10_customer_activity_observations where idempotency_key like $1) n", [`${run}%`])).rows[0].n);
    if (residue !== 0) throw new Error(`R2 authority races left ${residue} mutation rows`);
    console.log('TA-R2 all twelve customer-writer authority races: PASS (exact PID/holder, post-lock revoke, zero effect)');
  } finally {
    await holder.query('rollback').catch(() => {});
    await writer.query('reset role').catch(() => {});
    await admin.query('delete from public.e10_organization_memberships where user_id=$1', [user]).catch(() => {});
    await admin.query('delete from public.e10_organization_role_permissions where role_id=$1', [role]).catch(() => {});
    await admin.query('delete from public.e10_organization_roles where id=$1', [role]).catch(() => {});
    await admin.query('delete from auth.users where id=$1', [user]).catch(() => {});
    await Promise.all([holder.end(), writer.end(), admin.end()]);
  }
}

main().catch(error => { console.error(error.stack); process.exit(1); });
