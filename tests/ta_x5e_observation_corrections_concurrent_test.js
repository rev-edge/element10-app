const { Client } = require('pg');
const { randomUUID } = require('crypto');

const db = process.env.E10_DB_URL || 'postgresql://postgres:postgres@127.0.0.1:54322/postgres';
const org = 'e1000000-0000-4000-8000-0000000000a6';
const x = { u: randomUUID(), role: randomUUID(), p: randomUUID(), run: randomUUID() };
const ids = { batches: [randomUUID(), randomUUID()], rows: [randomUUID(), randomUUID()], commits: [randomUUID(), randomUUID()], observations: [randomUUID(), randomUUID()] };

async function main() {
  const s = new Client({ connectionString: db });
  const a = new Client({ connectionString: db });
  const b = new Client({ connectionString: db });
  await Promise.all([s.connect(), a.connect(), b.connect()]);
  try {
    await s.query('begin');
    await s.query("insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at) values($1,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',$2,now(),now())", [x.u, `${x.run}@x.invalid`]);
    await s.query("insert into public.e10_organization_roles(id,organization_id,key,name,is_system) values($1,$2,$3,'X5e Race',false)", [x.role, org, x.run]);
    await s.query("insert into public.e10_organization_role_permissions values($1,$2,'act.manage_intake',true)", [org, x.role]);
    await s.query("insert into public.e10_organization_memberships(organization_id,user_id,role_id,status) values($1,$2,$3,'active')", [org, x.u, x.role]);
    await s.query("insert into public.e10_product_masters(id,organization_id,name) values($1,$2,'X5e Race')", [x.p, org]);
    const old = (await s.query("insert into public.e10_market_observations(organization_id,observation_kind,product_master_id,occurred_at,currency,amount,source_kind,raw_payload_snapshot) values($1,'asking_price',$2,now(),'CAD',1,'manual','{}') returning id", [org, x.p])).rows[0].id;
    for (let i = 0; i < 2; i += 1) {
      await s.query("insert into public.e10_intake_batches(id,organization_id,source_kind,payload_fingerprint,status) values($1,$2,'api',$3,'committed')", [ids.batches[i], org, `${x.run}-batch-${i}`]);
      await s.query("insert into public.e10_intake_rows(id,organization_id,batch_id,source_row_number,raw_payload,observation_kind,occurred_at,currency,amount,match_status,product_master_id) values($1,$2,$3,1,'{}','estimated_value',now(),'CAD',$4,'matched',$5)", [ids.rows[i], org, ids.batches[i], i + 2, x.p]);
      await s.query("insert into public.e10_intake_commits(id,organization_id,intake_batch_id,idempotency_key,request_fingerprint,included_observation_count,rejected_row_count) values($1,$2,$3,$4,$5,1,0)", [ids.commits[i], org, ids.batches[i], `${x.run}-commit-${i}`, `${x.run}-fp-${i}`]);
      await s.query("insert into public.e10_market_observations(id,organization_id,intake_commit_id,intake_row_id,observation_kind,product_master_id,occurred_at,currency,amount,source_kind,raw_payload_snapshot) values($1,$2,$3,$4,'estimated_value',$5,now(),'CAD',$6,'api','{}')", [ids.observations[i], org, ids.commits[i], ids.rows[i], x.p, i + 2]);
    }
    await s.query('commit');

    for (const c of [a, b]) {
      await c.query('select set_config($1,$2,false)', ['request.jwt.claims', JSON.stringify({ sub: x.u, role: 'authenticated' })]);
      await c.query('set role authenticated');
    }
    const correction = "select public.e10_org_correct_market_observation($1,$2,'estimated_value','product',$3,'2025-01-01T00:00:00Z','CAD',2,1,'race','{}','race',$4) r";
    const [ra, rb] = await Promise.all([a.query(correction, [org, old, x.p, x.run]), b.query(correction, [org, old, x.p, x.run])]);
    const corrected = [ra.rows[0].r, rb.rows[0].r];
    if (corrected.filter((v) => !v.replay).length !== 1 || corrected[0].observation_id !== corrected[1].observation_id) throw new Error(JSON.stringify(corrected));
    console.log('TA-X5e concurrent correction: PASS');

    const link = 'select public.e10_org_reconcile_market_observation_reimport($1,$2,$3,$4,$5) r';
    const reverse = await Promise.allSettled([
      a.query(link, [org, ids.observations[0], ids.observations[1], 'race forward', `${x.run}-forward`]),
      b.query(link, [org, ids.observations[1], ids.observations[0], 'race reverse', `${x.run}-reverse`]),
    ]);
    const winners = reverse.filter((v) => v.status === 'fulfilled');
    const cycleLosers = reverse.filter((v) => v.status === 'rejected' && v.reason.code === '22023' && v.reason.message === 'observation_lineage_cycle');
    if (winners.length !== 1 || cycleLosers.length !== 1) throw new Error(`reverse-link outcome: ${JSON.stringify(reverse)}`);
    const edges = (await s.query('select superseded_observation_id,replacement_observation_id from public.e10_market_observation_supersessions where idempotency_key in($1,$2)', [`${x.run}-forward`, `${x.run}-reverse`])).rows;
    if (edges.length !== 1) throw new Error(`expected one reverse-link edge, got ${JSON.stringify(edges)}`);
    console.log('TA-X5e concurrent reverse-link cycle: PASS (one winner, cycle loser, no deadlock)');
  } finally {
    await s.query('rollback').catch(() => {});
    await s.query('set session_replication_role=replica').catch(() => {});
    await s.query('delete from public.e10_market_observation_supersessions where idempotency_key=$1 or idempotency_key like $2', [x.run, `${x.run}-%`]).catch(() => {});
    await s.query('delete from public.e10_market_observations where organization_id=$1 and product_master_id=$2', [org, x.p]).catch(() => {});
    await s.query('delete from public.e10_intake_commits where organization_id=$1 and id = any($2::uuid[])', [org, ids.commits]).catch(() => {});
    await s.query('delete from public.e10_intake_rows where organization_id=$1 and id = any($2::uuid[])', [org, ids.rows]).catch(() => {});
    await s.query('delete from public.e10_intake_batches where organization_id=$1 and id = any($2::uuid[])', [org, ids.batches]).catch(() => {});
    await s.query('set session_replication_role=origin').catch(() => {});
    await s.query('delete from public.e10_product_masters where id=$1', [x.p]).catch(() => {});
    await s.query('delete from public.e10_organization_memberships where user_id=$1', [x.u]).catch(() => {});
    await s.query('delete from public.e10_organization_roles where id=$1', [x.role]).catch(() => {});
    await s.query('delete from auth.users where id=$1', [x.u]).catch(() => {});
    await Promise.all([s.end(), a.end(), b.end()]);
  }
}

main().catch((e) => { console.error(e.stack); process.exit(1); });
