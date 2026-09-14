const { Client } = require("pg");
const { randomUUID } = require("crypto");
const db =
  process.env.E10_DB_URL ||
  "postgresql://postgres:postgres@127.0.0.1:54322/postgres";
const x = {
  org: randomUUID(),
  user: randomUUID(),
  role: randomUUID(),
  session: randomUUID(),
  customer: randomUUID(),
  activity: randomUUID(),
};
const report =
  "select public.e10_org_customer_spend_contributions($1,$2,$3,$4,$5,null,null,null,null,null,null,null,null,null,100,null,null,null,$6,null) j";
async function denied(p, code, msg) {
  try {
    await p;
    return false;
  } catch (e) {
    return e.code === code && e.message === msg;
  }
}
async function waitForLock(observer, pid) {
  for (let n = 0; n < 150; n++) {
    const r = (
      await observer.query(
        "select wait_event_type from pg_stat_activity where pid=$1",
        [pid],
      )
    ).rows[0];
    if (r && r.wait_event_type === "Lock") return true;
    await new Promise((r) => setTimeout(r, 20));
  }
  return false;
}
async function main() {
  const s = new Client({ connectionString: db }),
    reader = new Client({ connectionString: db }),
    writer = new Client({ connectionString: db }),
    obs = new Client({ connectionString: db });
  await Promise.all([
    s.connect(),
    reader.connect(),
    writer.connect(),
    obs.connect(),
  ]);
  let ok = false,
    pending;
  try {
    for (const c of [s, reader, writer, obs])
      await c.query("set statement_timeout='8s'");
    await s.query(
      "insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at) values($1,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',$2,now(),now())",
      [x.user, x.user + "@x.invalid"],
    );
    await s.query(
      "insert into public.e10_organizations(id,slug,name) values($1,$2,'X7b race')",
      [x.org, "x7br-" + x.org.slice(0, 8)],
    );
    await s.query(
      "insert into public.e10_organization_roles(id,organization_id,key,name,is_system) values($1,$2,'reader','Reader',false)",
      [x.role, x.org],
    );
    await s.query(
      "insert into public.e10_organization_memberships(organization_id,user_id,role_id,status) values($1,$2,$3,'active')",
      [x.org, x.user, x.role],
    );
    await s.query(
      "insert into public.e10_organization_role_permissions values($1,$2,'act.view_customer_financials',true)",
      [x.org, x.role],
    );
    await s.query(
      "insert into public.e10_break_sessions(id,organization_id,streamer_uid,name,status,visibility) values($1,$2,$3,'Race','active','private')",
      [x.session, x.org, x.user],
    );
    await reader.query("select set_config('request.jwt.claims',$1,false)", [
      JSON.stringify({ sub: x.user, role: "authenticated" }),
    ]);
    await reader.query("set role authenticated");
    await s.query(
      "insert into public.e10_organization_role_permissions values($1,$2,'act.reconcile_customer_transactions',true),($1,$2,'act.record_commercial_events',true)",
      [x.org, x.role],
    );
    await s.query(
      "insert into public.e10_customers(id,organization_id,display_name) values($1,$2,'Race customer')",
      [x.customer, x.org],
    );
    x.activity = (
      await reader.query(
        "select public.e10_org_record_customer_activity($1,'retail',$2,null,null,null,null,1,10,0,0,0,'USD',null,'2026-01-10','exact','import','race-conn','batch','race-event','{}','reviewed_import',$3) r",
        [x.org, x.customer, "race-activity-" + x.org],
      )
    ).rows[0].r.activity_id;
    let rev = Number(
      (
        await s.query(
          "select revision from public.e10_reporting_dataset_revisions where organization_id=$1",
          [x.org],
        )
      ).rows[0].revision,
    );
    await reader.query("begin");
    await reader.query(report, [
      x.org,
      "2026-01-01",
      "2026-02-01",
      "2026-02-01",
      "USD",
      rev,
    ]);
    const wpid = (await writer.query("select pg_backend_pid() pid")).rows[0]
      .pid;
    pending = writer.query(
      "update public.e10_organization_memberships set status='suspended' where organization_id=$1 and user_id=$2",
      [x.org, x.user],
    );
    if (!(await waitForLock(obs, wpid)))
      throw Error("authority writer did not wait on exact backend");
    await reader.query("commit");
    await pending;
    pending = null;
    console.log(
      "[proof] reader-first report held revision; exact authority writer waited",
    );
    if (
      !(await denied(
        reader.query(report, [
          x.org,
          "2026-01-01",
          "2026-02-01",
          "2026-02-01",
          "USD",
          rev,
        ]),
        "42501",
        "customer_spend_denied",
      ))
    )
      throw Error("post-lock revoked authority did not deny");
    await s.query(
      "update public.e10_organization_memberships set status='active' where organization_id=$1 and user_id=$2",
      [x.org, x.user],
    );
    rev = Number(
      (
        await s.query(
          "select revision from public.e10_reporting_dataset_revisions where organization_id=$1",
          [x.org],
        )
      ).rows[0].revision,
    );
    await writer.query("begin");
    await writer.query(
      "update public.e10_organization_memberships set status='suspended' where organization_id=$1 and user_id=$2",
      [x.org, x.user],
    );
    let rpid = (await reader.query("select pg_backend_pid() pid")).rows[0].pid;
    pending = reader.query(report, [
      x.org,
      "2026-01-01",
      "2026-02-01",
      "2026-02-01",
      "USD",
      rev,
    ]);
    pending.catch(() => {});
    if (!(await waitForLock(obs, rpid)))
      throw Error(
        "revoked-authority report reader did not wait on exact backend",
      );
    await writer.query("commit");
    if (!(await denied(pending, "42501", "customer_spend_denied")))
      throw Error("blocked reader retained revoked authority");
    pending = null;
    console.log(
      "[proof] blocked authenticated reader reread and rejected revoked authority",
    );
    await s.query(
      "update public.e10_organization_memberships set status='active' where organization_id=$1 and user_id=$2",
      [x.org, x.user],
    );
    rev = Number(
      (
        await s.query(
          "select revision from public.e10_reporting_dataset_revisions where organization_id=$1",
          [x.org],
        )
      ).rows[0].revision,
    );
    await writer.query("begin");
    await writer.query(
      "update public.e10_break_sessions set ended_at=clock_timestamp() where organization_id=$1 and id=$2",
      [x.org, x.session],
    );
    rpid = (await reader.query("select pg_backend_pid() pid")).rows[0].pid;
    pending = reader.query(report, [
      x.org,
      "2026-01-01",
      "2026-02-01",
      "2026-02-01",
      "USD",
      rev,
    ]);
    pending.catch(() => {});
    if (!(await waitForLock(obs, rpid)))
      throw Error("report reader did not wait on exact backend");
    await writer.query("commit");
    if (!(await denied(pending, "40001", "customer_spend_revision_stale")))
      throw Error("writer-first report did not reject stale revision");
    pending = null;
    console.log(
      "[proof] writer-first report exact backend waited and rejected stale revision",
    );
    await s.query(
      "update public.e10_organization_memberships set status='active' where organization_id=$1 and user_id=$2",
      [x.org, x.user],
    );
    const mapKey = "race-map-" + x.org;
    await writer.query("begin");
    await writer.query("select pg_advisory_xact_lock(hashtextextended($1,0))", [
      x.org + "|activity-source-map|" + mapKey,
    ]);
    rpid = (await reader.query("select pg_backend_pid() pid")).rows[0].pid;
    pending = reader.query(
      "select public.e10_org_bind_customer_activity_source_component($1,$2,'race-component','reviewed race',$3)",
      [x.org, x.activity, mapKey],
    );
    pending.catch(() => {});
    if (!(await waitForLock(obs, rpid)))
      throw Error("mapping caller did not wait on exact advisory lock");
    await s.query(
      "update public.e10_organization_memberships set status='suspended' where organization_id=$1 and user_id=$2",
      [x.org, x.user],
    );
    await writer.query("commit");
    if (
      !(await denied(
        pending,
        "42501",
        "customer_activity_source_mapping_denied",
      ))
    )
      throw Error("blocked mapping caller retained revoked authority");
    pending = null;
    const mappingResidue = Number(
      (
        await s.query(
          "select count(*) n from public.e10_customer_activity_source_components where organization_id=$1 and activity_observation_id=$2",
          [x.org, x.activity],
        )
      ).rows[0].n,
    );
    if (mappingResidue !== 0) throw Error("revoked mapping survived rollback");
    console.log(
      "[proof] blocked mapping caller reread authority; no mapping or revision-trigger effects survived",
    );
    ok = true;
  } finally {
    if (pending) await Promise.allSettled([pending]);
    await s.query("rollback").catch(() => {});
    await Promise.allSettled([
      reader.query("rollback"),
      writer.query("rollback"),
    ]);
    await reader.query("reset role").catch(() => {});
    await s.query("set session_replication_role=replica");
    const tables = [
      "e10_customer_commercial_receipts",
      "e10_commercial_events",
      "e10_customer_activity_source_components",
      "e10_customer_activity_observations",
      "e10_break_sessions",
      "e10_customers",
      "e10_organization_role_permissions",
      "e10_organization_memberships",
      "e10_organization_roles",
      "e10_reporting_dataset_revisions",
    ];
    for (const t of tables)
      await s.query(`delete from public.${t} where organization_id=$1`, [
        x.org,
      ]);
    await s.query("delete from public.e10_organizations where id=$1", [x.org]);
    await s.query("set session_replication_role=origin");
    await s.query("delete from auth.users where id=$1", [x.user]);
    let residue = Number(
      (
        await s.query(
          "select count(*) n from public.e10_organizations where id=$1",
          [x.org],
        )
      ).rows[0].n,
    );
    for (const t of tables)
      residue += Number(
        (
          await s.query(
            `select count(*) n from public.${t} where organization_id=$1`,
            [x.org],
          )
        ).rows[0].n,
      );
    residue += Number(
      (await s.query("select count(*) n from auth.users where id=$1", [x.user]))
        .rows[0].n,
    );
    const sentinel = Number(
      (
        await s.query(
          "select count(*) n from public.e10_organizations where id='e1000000-0000-4000-8000-0000000000a6'",
        )
      ).rows[0].n,
    );
    await Promise.all([s.end(), reader.end(), writer.end(), obs.end()]);
    if (residue || sentinel !== 1)
      throw Error(
        "X7b race cleanup failed " + JSON.stringify({ residue, sentinel }),
      );
  }
  if (ok) console.log("TA-X7b spend reporting concurrency: PASS");
}
main().catch((e) => {
  console.error(e.stack);
  process.exit(1);
});
