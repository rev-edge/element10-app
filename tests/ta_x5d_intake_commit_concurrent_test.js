// TA-X5d two-connection proof: one reviewed batch commits exactly once under retry contention.
const { Client } = require('pg');
const { randomUUID } = require('crypto');
const CONN = process.env.E10_DB_URL || 'postgresql://postgres:postgres@127.0.0.1:54322/postgres';
const org = 'e1000000-0000-4000-8000-0000000000a6';
const x = { user: randomUUID(), role: randomUUID(), product: randomUUID(), run: randomUUID() };
const jwt = JSON.stringify({ sub: x.user, role: 'authenticated' });
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
async function cleanup(c) {
  await c.query('set session_replication_role=replica');
  await c.query('delete from public.e10_market_observations where intake_commit_id in(select id from public.e10_intake_commits where idempotency_key like $1)', [`${x.run}-%`]);
  await c.query('delete from public.e10_intake_commits where idempotency_key like $1', [`${x.run}-%`]);
  await c.query('delete from public.e10_intake_resolver_decisions where idempotency_key like $1', [`${x.run}-%`]);
  await c.query('delete from public.e10_intake_rows where batch_id in(select id from public.e10_intake_batches where idempotency_key like $1)', [`${x.run}-%`]);
  await c.query('delete from public.e10_intake_batches where idempotency_key like $1', [`${x.run}-%`]);
  await c.query('set session_replication_role=origin');
  await c.query('delete from public.e10_product_masters where id=$1', [x.product]);
  await c.query('delete from public.e10_organization_memberships where organization_id=$1 and user_id=$2', [org, x.user]);
  await c.query('delete from public.e10_organization_roles where id=$1', [x.role]);
  await c.query('delete from auth.users where id=$1', [x.user]);
}
async function main() {
  const s = new Client({ connectionString: CONN }); const a = new Client({ connectionString: CONN }); const b = new Client({ connectionString: CONN });
  await s.connect(); await a.connect(); await b.connect();
  try {
    await cleanup(s);
    await s.query("insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at) values($1,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',$2,now(),now())", [x.user, `x5d-${x.run}@x.invalid`]);
    await s.query("insert into public.e10_organization_roles(id,organization_id,key,name,is_system) values($1,$2,$3,'X5d Race',false)", [x.role, org, `x5d-${x.run}`]);
    await s.query("insert into public.e10_organization_role_permissions(organization_id,role_id,capability,allowed) values($1,$2,'act.manage_intake',true)", [org, x.role]);
    await s.query("insert into public.e10_organization_memberships(organization_id,user_id,role_id,status) values($1,$2,$3,'active')", [org, x.user, x.role]);
    await s.query("insert into public.e10_product_masters(id,organization_id,name) values($1,$2,'X5d Race Product')", [x.product, org]);
    await s.query('select set_config($1,$2,false)', ['request.jwt.claims', jwt]);
    await s.query('set role authenticated');
    const stage = (await s.query("select public.e10_org_stage_intake($1,'manual',null,'race',null,'race-fp',jsonb_build_array(jsonb_build_object('raw_payload',jsonb_build_object('source','race'),'observation_kind','completed_sale','occurred_at','2025-02-03T04:05:06Z','currency','CAD','amount',42)),$2) r", [org, `${x.run}-stage`])).rows[0].r;
    await s.query('reset role');
    const row = (await s.query('select id from public.e10_intake_rows where batch_id=$1', [stage.batch_id])).rows[0].id;
    await s.query('set role authenticated');
    await s.query("select public.e10_org_resolve_intake_row($1,$2,'match_product',$3,'reviewed race',null,$4)", [org, row, x.product, `${x.run}-resolve`]);
    const revision = Number((await s.query('select public.e10_org_intake_review_state($1,$2) r', [org, stage.batch_id])).rows[0].r.review_revision);
    await s.query('reset role');
    for (const c of [a, b]) { await c.query('select set_config($1,$2,false)', ['request.jwt.claims', jwt]); await c.query('set role authenticated'); }
    const [ar, br] = await Promise.all([a.query('select public.e10_org_commit_intake($1,$2,$3,$4) r', [org, stage.batch_id, revision, `${x.run}-commit`]), b.query('select public.e10_org_commit_intake($1,$2,$3,$4) r', [org, stage.batch_id, revision, `${x.run}-commit`])]);
    const results = [ar.rows[0].r, br.rows[0].r];
    if (results.filter((v) => !v.replay).length !== 1 || results[0].commit_id !== results[1].commit_id) throw new Error(`commit race not idempotent ${JSON.stringify(results)}`);
    const proof = (await s.query('select (select count(*) from public.e10_intake_commits where intake_batch_id=$1) commits,(select count(*) from public.e10_market_observations where intake_row_id=$2) observations', [stage.batch_id, row])).rows[0];
    if (Number(proof.commits) !== 1 || Number(proof.observations) !== 1) throw new Error(`commit race duplicated ${JSON.stringify(proof)}`);

    await s.query('set role authenticated');
    const raceStage = (await s.query("select public.e10_org_stage_intake($1,'manual',null,'review-race',null,'review-race-fp',jsonb_build_array(jsonb_build_object('raw_payload',jsonb_build_object('source','review-race'),'observation_kind','asking_price','occurred_at','2025-02-04T04:05:06Z','currency','CAD','amount',43)),$2) r", [org, `${x.run}-race-stage`])).rows[0].r;
    await s.query('reset role');
    const raceRow = (await s.query('select id from public.e10_intake_rows where batch_id=$1', [raceStage.batch_id])).rows[0].id;
    await s.query('set role authenticated');
    await s.query("select public.e10_org_resolve_intake_row($1,$2,'match_product',$3,'reviewed before commit',null,$4)", [org, raceRow, x.product, `${x.run}-race-resolve`]);
    const raceRevision = Number((await s.query('select public.e10_org_intake_review_state($1,$2) r', [org, raceStage.batch_id])).rows[0].r.review_revision);
    await s.query('reset role');
    await a.query('reset role');
    await a.query('begin');
    await a.query('select id from public.e10_intake_batches where organization_id=$1 and id=$2 for update', [org, raceStage.batch_id]);
    await a.query('set role authenticated');
    const bpid = (await b.query('select pg_backend_pid() pid')).rows[0].pid;
    let resolveError;
    const lateResolve = b.query("select public.e10_org_resolve_intake_row($1,$2,'clear_match',null,'late change',null,$3)", [org, raceRow, `${x.run}-late-resolve`]).catch((e) => { resolveError = e; });
    let waiting = false;
    for (let i = 0; i < 400; i++) {
      const state = await s.query("select wait_event_type='Lock' waiting from pg_stat_activity where pid=$1", [bpid]);
      if (state.rows[0]?.waiting) { waiting = true; break; }
      await sleep(10);
    }
    if (!waiting) throw new Error('late resolve never waited on commit batch lock');
    const committed = (await a.query('select public.e10_org_commit_intake($1,$2,$3,$4) r', [org, raceStage.batch_id, raceRevision, `${x.run}-race-commit`])).rows[0].r;
    await a.query('commit'); await lateResolve;
    if (!committed.ok || !resolveError || resolveError.code !== '55000') throw new Error(`resolve/commit race escaped commit=${JSON.stringify(committed)} resolve=${resolveError && resolveError.code}`);
    const raceProof = (await s.query('select r.match_status,(select count(*) from public.e10_market_observations where intake_row_id=r.id) observations,(select count(*) from public.e10_intake_resolver_decisions where idempotency_key=$2) late_decisions from public.e10_intake_rows r where r.id=$1', [raceRow, `${x.run}-late-resolve`])).rows[0];
    if (raceProof.match_status !== 'matched' || Number(raceProof.observations) !== 1 || Number(raceProof.late_decisions) !== 0) throw new Error(`stale resolve changed committed evidence ${JSON.stringify(raceProof)}`);
    console.log('TA-X5d concurrent commit: PASS (same-key exactly once; late resolve serialized and rejected)');
  } finally {
    for (const c of [a, b, s]) await c.query('rollback').catch(() => {});
    await cleanup(s); await a.end(); await b.end(); await s.end();
  }
}
main().catch((e) => { console.error(`TA-X5d concurrent commit ERROR: ${e.stack || e.message}`); process.exit(1); });
