const { Client } = require('pg');
const { randomUUID } = require('crypto');
const db = process.env.E10_DB_URL || 'postgresql://postgres:postgres@127.0.0.1:54322/postgres';
const org = 'e1000000-0000-4000-8000-0000000000a6';
const x = { run: randomUUID(), user: randomUUID(), role: randomUUID(), c1: randomUUID(), c2: randomUUID() };

async function main() {
  const s = new Client({ connectionString: db }), a = new Client({ connectionString: db }), b = new Client({ connectionString: db });
  await Promise.all([s.connect(), a.connect(), b.connect()]);
  try {
    await s.query("insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at) values($1,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',$2,now(),now())", [x.user, `${x.run}@x.invalid`]);
    await s.query("insert into public.e10_organization_roles(id,organization_id,key,name,is_system) values($1,$2,$3,'X6b Race',false)", [x.role, org, x.run]);
    await s.query("insert into public.e10_organization_role_permissions values($1,$2,'act.manage_customers',true),($1,$2,'act.record_commercial_events',true)", [org, x.role]);
    await s.query('insert into public.e10_organization_memberships(organization_id,user_id,role_id,status) values($1,$2,$3,\'active\')', [org, x.user, x.role]);
    for (const c of [a, b]) {
      await c.query('select set_config($1,$2,false)', ['request.jwt.claims', JSON.stringify({ sub: x.user, role: 'authenticated' })]);
      await c.query('set role authenticated');
    }

    const createSql = 'select public.e10_org_create_customer($1,$2,$3) r';
    const created = await Promise.all([a.query(createSql, [org, 'Race Customer', `${x.run}-create`]), b.query(createSql, [org, 'Race Customer', `${x.run}-create`])]);
    const createResults = created.map(v => v.rows[0].r);
    if (createResults.filter(v => v.replay).length !== 1 || createResults[0].customer_id !== createResults[1].customer_id) throw new Error(`create race ${JSON.stringify(createResults)}`);
    x.c1 = createResults[0].customer_id;
    await s.query('insert into public.e10_customers(id,organization_id,display_name) values($1,$2,\'Race Other\')', [x.c2, org]);

    const updates = await Promise.allSettled([
      a.query('select public.e10_org_update_customer($1,$2,0,\'Winner A\',\'active\',$3)', [org, x.c1, `${x.run}-update-a`]),
      b.query('select public.e10_org_update_customer($1,$2,0,\'Winner B\',\'active\',$3)', [org, x.c1, `${x.run}-update-b`])
    ]);
    if (updates.filter(v => v.status === 'fulfilled').length !== 1 || updates.filter(v => v.status === 'rejected' && v.reason.code === '40001').length !== 1) throw new Error(`update race ${JSON.stringify(updates)}`);

    const identities = await Promise.allSettled([
      a.query("select public.e10_org_decide_customer_identity($1,$2,'channel_account','market','same-account',null,'attach',null,'review','{}',$3)", [org, x.c1, `${x.run}-identity-a`]),
      b.query("select public.e10_org_decide_customer_identity($1,$2,'channel_account','market','same-account',null,'attach',null,'review','{}',$3)", [org, x.c2, `${x.run}-identity-b`])
    ]);
    if (identities.filter(v => v.status === 'fulfilled').length !== 1 || identities.filter(v => v.status === 'rejected' && v.reason.code === '22023').length !== 1) throw new Error(`identity race ${JSON.stringify(identities)}`);

    const activityResult = await a.query("select public.e10_org_record_customer_activity($1,'retail',null,$2,'race',null,null,1,10,null,null,null,'CAD','manual','2026-01-01T00:00:00Z','exact','manual',null,'operator',$3,'{}','operator_asserted',$4) r", [org, x.user, `${x.run}-source`, `${x.run}-activity`]);
    const activity = activityResult.rows[0].r.activity_id;
    const attributed = await Promise.all([
      a.query("select public.e10_org_attribute_customer_activity($1,$2,$3,'race a','{}',$4)", [org, activity, x.c1, `${x.run}-attr-a`]),
      b.query("select public.e10_org_attribute_customer_activity($1,$2,$3,'race b','{}',$4)", [org, activity, x.c2, `${x.run}-attr-b`])
    ]);
    if (attributed.length !== 2) throw new Error('attribution calls incomplete');
    const proof = (await s.query('select count(*)::int decisions,count(*) filter(where supersedes_decision_id is null)::int roots,count(*) filter(where supersedes_decision_id is not null)::int successors from public.e10_customer_activity_attribution_decisions where organization_id=$1 and activity_observation_id=$2', [org, activity])).rows[0];
    if (proof.decisions !== 2 || proof.roots !== 1 || proof.successors !== 1) throw new Error(`attribution fork ${JSON.stringify(proof)}`);
    console.log('TA-X6b concurrent customer identity: PASS (create replay, CAS winner, identity winner, attribution chain)');
  } finally {
    await s.query('set session_replication_role=replica').catch(() => {});
    await s.query('delete from public.e10_commercial_events where idempotency_key=$1', [`activity:${x.run}-activity`]).catch(() => {});
    await s.query('delete from public.e10_customer_activity_attribution_decisions where idempotency_key like $1', [`${x.run}%`]).catch(() => {});
    await s.query('delete from public.e10_customer_activity_observations where idempotency_key=$1', [`${x.run}-activity`]).catch(() => {});
    await s.query('delete from public.e10_customer_identity_decisions where idempotency_key like $1', [`${x.run}%`]).catch(() => {});
    await s.query('delete from public.e10_customer_mutation_receipts where idempotency_key like $1', [`${x.run}%`]).catch(() => {});
    await s.query('delete from public.e10_customers where id=any($1::uuid[])', [[x.c1, x.c2]]).catch(() => {});
    await s.query('set session_replication_role=origin').catch(() => {});
    await s.query('delete from public.e10_organization_memberships where user_id=$1', [x.user]).catch(() => {});
    await s.query('delete from public.e10_organization_roles where id=$1', [x.role]).catch(() => {});
    await s.query('delete from auth.users where id=$1', [x.user]).catch(() => {});
    await Promise.all([s.end(), a.end(), b.end()]);
  }
}
main().catch(e => { console.error(e.stack); process.exit(1); });
