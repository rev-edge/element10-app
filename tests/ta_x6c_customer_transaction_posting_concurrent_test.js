const { Client } = require('pg');
const { randomUUID } = require('crypto');
const db = process.env.E10_DB_URL || 'postgresql://postgres:postgres@127.0.0.1:54322/postgres';
const org = 'e1000000-0000-4000-8000-0000000000a6';
const x = { run: randomUUID(), user: randomUUID(), role: randomUUID(), customer: randomUUID(), customer2: randomUUID() };
const timeout = (p, ms = 8000) => Promise.race([p, new Promise((_, reject) => setTimeout(() => reject(new Error(`posting race timeout ${ms}ms`)), ms))]);

async function main() {
  const s = new Client({ connectionString: db }), a = new Client({ connectionString: db }), b = new Client({ connectionString: db }), c = new Client({ connectionString: db });
  await Promise.all([s.connect(), a.connect(), b.connect(), c.connect()]);
  try {
    await s.query("insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at) values($1,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',$2,now(),now())", [x.user, `${x.run}@x.invalid`]);
    await s.query("insert into public.e10_organization_roles(id,organization_id,key,name,is_system) values($1,$2,$3,'X6c Race',false)", [x.role, org, x.run]);
    await s.query("insert into public.e10_organization_role_permissions values($1,$2,'act.prepare_customer_transactions',true),($1,$2,'act.approve_customer_transactions',true),($1,$2,'act.post_customer_transactions',true),($1,$2,'act.record_commercial_events',true),($1,$2,'act.manage_customers',true)", [org, x.role]);
    await s.query("insert into public.e10_organization_memberships(organization_id,user_id,role_id,status) values($1,$2,$3,'active')", [org, x.user, x.role]);
    await s.query("insert into public.e10_customers(id,organization_id,display_name) values($1,$3,'X6c Race Customer'),($2,$3,'X6c Race Customer Two')", [x.customer, x.customer2, org]);
    for (const c of [a, b]) { await c.query('select set_config($1,$2,false)', ['request.jwt.claims', JSON.stringify({ sub: x.user, role: 'authenticated' })]); await c.query('set role authenticated'); }
    const activityResult = await a.query("select public.e10_org_record_customer_activity($1,'retail',$2,null,'race',null,null,1,10,null,null,null,'CAD','manual','2026-01-01T00:00:00Z','exact','manual',null,'operator',$3,'{}','operator_asserted',$4) r", [org, x.customer, `${x.run}-activity-source`, `${x.run}-activity`]);
    const activity = activityResult.rows[0].r.activity_id;
    const lineA = { purchase_kind: 'retail', capture_source: 'manual', source_line_id: `${x.run}-A`, activity_observation_id: activity, quantity: 1, merchandise_gross: 10 };
    const lineB = { purchase_kind: 'unclassified', capture_source: 'import', source_connection_id: 'race-file', source_line_id: `${x.run}-B`, quantity: 1, merchandise_gross: 5 };
    async function draft(c, suffix, lines) {
      const made = (await c.query("select public.e10_org_create_customer_transaction_draft($1,$2,'CAD','2026-01-01T00:00:00Z','exact','race',$3,$4) r", [org, x.customer, JSON.stringify(lines), `${x.run}-draft-${suffix}`])).rows[0].r;
      await c.query('select public.e10_org_approve_customer_transaction_draft($1,$2,1,$3)', [org, made.draft_id, `${x.run}-approve-${suffix}`]);
      return made.draft_id;
    }
    const d1 = await draft(a, 'one', [lineA, lineB]);
    const d2 = await draft(b, 'two', [lineB, lineA]);
    const settled = await timeout(Promise.allSettled([
      a.query('select public.e10_org_post_customer_transaction_draft($1,$2,1,$3)', [org, d1, `${x.run}-post-one`]),
      b.query('select public.e10_org_post_customer_transaction_draft($1,$2,1,$3)', [org, d2, `${x.run}-post-two`]),
      s.query('select set_config($1,$2,false)', ['request.jwt.claims', JSON.stringify({ sub: x.user, role: 'authenticated' })]).then(() => s.query('select public.e10_org_approve_customer_transaction_draft($1,$2,1,$3)', [org, d1, `${x.run}-approve-duplicate`]))
    ]));
    if (settled.filter(v => v.status === 'fulfilled').length !== 1 || settled.filter(v => v.status === 'rejected' && v.reason.code === '23505').length !== 1 || settled.filter(v => v.status === 'rejected' && v.reason.code === '40001').length !== 1) throw new Error(`post/approve race ${JSON.stringify(settled)}`);
    const proof = (await s.query("select (select count(*)::int from public.e10_customer_transactions where source_draft_id=any($1::uuid[])) transactions,(select count(*)::int from public.e10_customer_transaction_lines where source_line_id=any($2::text[])) lines,(select count(*)::int from public.e10_customer_transaction_lines where activity_observation_id=$3) activity_uses", [[d1, d2], [`${x.run}-A`, `${x.run}-B`], activity])).rows[0];
    if (proof.transactions !== 1 || proof.lines !== 2 || proof.activity_uses !== 1) throw new Error(`post duplication ${JSON.stringify(proof)}`);

    const activity2Result = await a.query("select public.e10_org_record_customer_activity($1,'retail',$2,null,'race-two',null,null,1,11,null,null,null,'CAD','manual','2026-01-02T00:00:00Z','exact','manual',null,'operator',$3,'{}','operator_asserted',$4) r", [org, x.customer, `${x.run}-activity-source-2`, `${x.run}-activity-2`]);
    const activity2 = activity2Result.rows[0].r.activity_id;
    const d3 = await draft(b, 'three', [{ purchase_kind: 'retail', capture_source: 'manual', source_line_id: `${x.run}-C`, activity_observation_id: activity2, quantity: 1, merchandise_gross: 11 }]);
    const bPid = (await b.query('select pg_backend_pid() pid')).rows[0].pid;
    await a.query('begin');
    await a.query("select public.e10_org_attribute_customer_activity($1,$2,$3,'concurrent correction','{}',$4)", [org, activity2, x.customer2, `${x.run}-attr-race`]);
    const postPromise = b.query('select public.e10_org_post_customer_transaction_draft($1,$2,1,$3)', [org, d3, `${x.run}-post-three`]);
    let waiting = false;
    for (let i = 0; i < 40; i++) {
      const q = await s.query("select exists(select 1 from pg_locks where pid=$1 and locktype='advisory' and not granted) waiting", [bPid]);
      if (q.rows[0].waiting) { waiting = true; break; }
      await new Promise(resolve => setTimeout(resolve, 50));
    }
    if (!waiting) throw new Error('post did not wait on attribution lock');
    await a.query('commit');
    const postAfterCorrection = await timeout(Promise.allSettled([postPromise]));
    if (postAfterCorrection[0].status !== 'rejected' || postAfterCorrection[0].reason.code !== '40001') throw new Error(`reattribution race ${JSON.stringify(postAfterCorrection)}`);

    await a.query("select public.e10_org_attribute_customer_activity($1,$2,$3,'restore for authority race','{}',$4)", [org, activity2, x.customer, `${x.run}-attr-restore`]);
    await b.query('select public.e10_org_reopen_customer_transaction_draft($1,$2,1,$3,$4)', [org, d3, 'authority re-review', `${x.run}-reopen-three`]);
    await b.query('select public.e10_org_approve_customer_transaction_draft($1,$2,1,$3)', [org, d3, `${x.run}-reapprove-three`]);
    await s.query('begin');
    await s.query('select 1 from public.e10_customer_transaction_drafts where id=$1 for update', [d3]);
    const authorityPost = b.query('select public.e10_org_post_customer_transaction_draft($1,$2,1,$3)', [org, d3, `${x.run}-post-authority`]);
    waiting = false;
    for (let i = 0; i < 40; i++) {
      const q = await c.query("select exists(select 1 from pg_locks where pid=$1 and locktype='tuple' and not granted) or exists(select 1 from pg_stat_activity where pid=$1 and wait_event_type='Lock') waiting", [bPid]);
      if (q.rows[0].waiting) { waiting = true; break; }
      await new Promise(resolve => setTimeout(resolve, 50));
    }
    if (!waiting) throw new Error('post did not wait on its exact draft-row lock');
    await c.query("delete from public.e10_organization_role_permissions where organization_id=$1 and role_id=$2 and capability='act.post_customer_transactions'", [org, x.role]);
    await s.query('commit');
    const deniedPost = await timeout(Promise.allSettled([authorityPost]));
    if (deniedPost[0].status !== 'rejected' || deniedPost[0].reason.code !== '42501') throw new Error(`post-lock authority race ${JSON.stringify(deniedPost)}`);
    const deniedResidue = (await c.query('select count(*)::int n from public.e10_customer_transactions where source_draft_id=$1', [d3])).rows[0].n;
    if (deniedResidue !== 0) throw new Error(`post-lock authority residue ${deniedResidue}`);
    console.log(`TA-X6c concurrent posting: PASS (reverse-order locks, one winner, source/activity once; post-lock revoke pid=${bPid}, zero effect)`);
  } finally {
    await a.query('rollback').catch(() => {}); await b.query('rollback').catch(() => {});
    await s.query('set session_replication_role=replica').catch(() => {});
    await s.query("delete from public.e10_commercial_events where idempotency_key like $1 or idempotency_key like $2", [`transaction-post:${x.run}%`, `activity:${x.run}-activity%`]).catch(() => {});
    await s.query("delete from public.e10_customer_activity_attribution_decisions where idempotency_key like $1", [`${x.run}%`]).catch(() => {});
    await s.query("delete from public.e10_customer_transaction_source_claims where source_line_id like $1", [`${x.run}%`]).catch(() => {});
    await s.query("delete from public.e10_customer_transaction_lines where source_line_id like $1", [`${x.run}%`]).catch(() => {});
    await s.query("delete from public.e10_customer_transactions where source_draft_id in(select id from public.e10_customer_transaction_drafts where id in(select draft_id from public.e10_customer_transaction_draft_revisions where review_note='race'))").catch(() => {});
    await s.query("delete from public.e10_customer_transaction_draft_decisions where idempotency_key like $1", [`${x.run}%`]).catch(() => {});
    await s.query("delete from public.e10_customer_transaction_draft_lines where draft_id in(select draft_id from public.e10_customer_transaction_draft_revisions where review_note='race')").catch(() => {});
    await s.query("delete from public.e10_customer_transaction_draft_revisions where review_note='race'").catch(() => {});
    await s.query("delete from public.e10_customer_transaction_drafts where created_by=$1", [x.user]).catch(() => {});
    await s.query("delete from public.e10_customer_commercial_receipts where idempotency_key like $1", [`${x.run}%`]).catch(() => {});
    await s.query("delete from public.e10_customer_activity_observations where idempotency_key like $1", [`${x.run}-activity%`]).catch(() => {});
    await s.query('delete from public.e10_customers where id=any($1::uuid[])', [[x.customer, x.customer2]]).catch(() => {});
    await s.query('set session_replication_role=origin').catch(() => {});
    await s.query('delete from public.e10_organization_memberships where user_id=$1', [x.user]).catch(() => {});
    await s.query('delete from public.e10_organization_roles where id=$1', [x.role]).catch(() => {});
    await s.query('delete from auth.users where id=$1', [x.user]).catch(() => {});
    await Promise.all([s.end(), a.end(), b.end(), c.end()]);
  }
}
main().catch(e => { console.error(e.stack); process.exit(1); });
