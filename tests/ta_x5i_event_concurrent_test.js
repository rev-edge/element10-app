const { Client } = require('pg');
const { randomUUID } = require('crypto');

const db = process.env.E10_DB_URL || 'postgresql://postgres:postgres@127.0.0.1:54322/postgres';
const org = 'e1000000-0000-4000-8000-0000000000a6';
const x = { user: randomUUID(), role: randomUUID(), item: `x5i-${randomUUID()}`, run: randomUUID() };

async function main() {
  const s = new Client({ connectionString: db });
  const a = new Client({ connectionString: db });
  const b = new Client({ connectionString: db });
  await Promise.all([s.connect(), a.connect(), b.connect()]);
  try {
    await s.query("insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at) values($1,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',$2,now(),now())", [x.user, `${x.run}@x.invalid`]);
    await s.query("insert into public.e10_organization_roles(id,organization_id,key,name,is_system) values($1,$2,$3,'X5i Race',false)", [x.role, org, x.run]);
    await s.query("insert into public.e10_organization_role_permissions values($1,$2,'act.record_commercial_events',true)", [org, x.role]);
    await s.query("insert into public.e10_organization_memberships(organization_id,user_id,role_id,status) values($1,$2,$3,'active')", [org, x.user, x.role]);
    await s.query("insert into public.e10_inventory_items(id,organization_id,name,qty) values($1,$2,'X5i Race',1)", [x.item, org]);
    for (const c of [a, b]) {
      await c.query('select set_config($1,$2,false)', ['request.jwt.claims', JSON.stringify({ sub: x.user, role: 'authenticated' })]);
      await c.query('set role authenticated');
    }
    const sql = "select public.e10_org_record_commercial_event_v2($1,'listing_created',1,'inventory_item',$2,'2026-01-01T00:00:00Z','exact','manual',null,'race',$3,$4,null,'operator_asserted',jsonb_build_object('listing_id','listing-race','channel','race'),null,'{}',$5) r";
    const [ra, rb] = await Promise.all([a.query(sql, [org, x.item, `${x.run}-source`, `${x.run}-corr`, `${x.run}-key`]), b.query(sql, [org, x.item, `${x.run}-source`, `${x.run}-corr`, `${x.run}-key`])]);
    const results = [ra.rows[0].r, rb.rows[0].r];
    if (results.filter((v) => !v.replay).length !== 1 || results.filter((v) => v.replay).length !== 1 || results[0].event_id !== results[1].event_id) throw new Error(JSON.stringify(results));
    const count = Number((await s.query('select count(*) c from public.e10_commercial_events where organization_id=$1 and idempotency_key=$2', [org, `${x.run}-key`])).rows[0].c);
    if (count !== 1) throw new Error(`expected one event, got ${count}`);
    console.log('TA-X5i concurrent event replay: PASS (one insert, one replay, one event)');
  } finally {
    await s.query('set session_replication_role=replica').catch(() => {});
    await s.query('delete from public.e10_integration_outbox where organization_id=$1 and commercial_event_id in(select id from public.e10_commercial_events where idempotency_key like $2)', [org, `${x.run}%`]).catch(() => {});
    await s.query('delete from public.e10_commercial_events where organization_id=$1 and idempotency_key like $2', [org, `${x.run}%`]).catch(() => {});
    await s.query('set session_replication_role=origin').catch(() => {});
    await s.query('delete from public.e10_inventory_items where organization_id=$1 and id=$2', [org, x.item]).catch(() => {});
    await s.query('delete from public.e10_organization_memberships where user_id=$1', [x.user]).catch(() => {});
    await s.query('delete from public.e10_organization_roles where id=$1', [x.role]).catch(() => {});
    await s.query('delete from auth.users where id=$1', [x.user]).catch(() => {});
    await Promise.all([s.end(), a.end(), b.end()]);
  }
}

main().catch((e) => { console.error(e.stack); process.exit(1); });
