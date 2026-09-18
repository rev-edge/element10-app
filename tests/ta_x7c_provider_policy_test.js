const { Client } = require("pg");
const { randomUUID } = require("crypto");
const db =
  process.env.E10_DB_URL ||
  "postgresql://postgres:postgres@127.0.0.1:54322/postgres";
async function denied(p, code, msg) {
  try {
    await p;
    return false;
  } catch (e) {
    return e.code === code && e.message === msg;
  }
}
async function main() {
  const s = new Client({ connectionString: db }),
    a = new Client({ connectionString: db });
  await Promise.all([s.connect(), a.connect()]);
  const x = {
    org: randomUUID(),
    user: randomUUID(),
    role: randomUUID(),
    run: randomUUID(),
  };
  let ok = false;
  try {
    await s.query(
      "insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at)values($1,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',$2,now(),now())",
      [x.user, x.run + "@x.invalid"],
    );
    await s.query(
      "insert into public.e10_organizations(id,slug,name)values($1,$2,'X7c policy')",
      [x.org, "x7cp-" + x.run.slice(0, 8)],
    );
    await s.query(
      "insert into public.e10_organization_roles(id,organization_id,key,name,is_system)values($1,$2,$3,'X7c reviewer',false)",
      [x.role, x.org, x.run],
    );
    await s.query(
      "insert into public.e10_organization_memberships(organization_id,user_id,role_id,status)values($1,$2,$3,'active')",
      [x.org, x.user, x.role],
    );
    await s.query(
      "insert into public.e10_organization_role_permissions values($1,$2,'act.configure_attendance_normalization',true)",
      [x.org, x.role],
    );
    await s.query(
      "insert into public.e10_presence_collection_policies(organization_id,policy_version,source_class,provider_key,enabled,notice_version,heartbeat_expiry_seconds,min_event_interval_ms,max_events_per_minute,retention_interval,coverage_label,effective_from,created_by)values($1,1,'authorized_platform','fixture',true,'n1',300,0,60,interval '30 days','fixture','2026-01-01',$2)",
      [x.org, x.user],
    );
    await a.query("select set_config('request.jwt.claims',$1,false)", [
      JSON.stringify({ sub: x.user, role: "authenticated" }),
    ]);
    await a.query("set role authenticated");
    const call =
      "select public.e10_org_review_provider_presence_normalization_policy($1,'fixture',$2,$3,$4,$5,$6,$7,1,$8,'{}',$9) r";
    const review = (expected,action,from,through,expiry,late,reason,key) =>
      a.query(call,[x.org,expected,action,from,through,expiry,late,reason,key]);
    let r = (
      await review(0,"enable","2026-01-01","2027-01-01","5 minutes","1 day","initial",x.run+"-1")
    ).rows[0].r;
    if (r.replay || r.revision !== 1) throw Error("enable failed");
    let replay = (
      await review(0,"enable","2026-01-01","2027-01-01","5 minutes","1 day","initial",x.run+"-1")
    ).rows[0].r;
    if (!replay.replay) throw Error("replay failed");
    if (
      !(await denied(
        review(0,"enable","2026-01-01","2027-01-01","5 minutes","2 days","changed",x.run+"-1"),
        "22023",
        "idempotency_key_mismatch",
      ))
    )
      throw Error("fingerprint mismatch accepted");
    r = (
      await review(1,"supersede","2026-06-01","2027-01-01","4 minutes","2 days","supersede",x.run+"-2")
    ).rows[0].r;
    if (r.revision !== 2) throw Error("supersede failed");
    r = (
      await review(2,"revoke","2026-09-01","2027-01-01",null,null,"revoke",x.run+"-3")
    ).rows[0].r;
    if (r.revision !== 3) throw Error("revoke failed");
    const asOf=async at=>(await s.query("select revision from e10.provider_presence_normalization_policy_at($1,'fixture',$2)",[x.org,at])).rows[0]?.revision;
    if(Number(await asOf('2026-02-01'))!==1||Number(await asOf('2026-07-01'))!==2||await asOf('2026-10-01')!==undefined)throw Error('historical policy resolution failed');
    r=(await review(3,"supersede","2026-11-01","2027-01-01","3 minutes","1 day","restore",x.run+"-restore")).rows[0].r;
    if(r.revision!==4||Number(await asOf('2026-12-01'))!==4)throw Error('revoke restoration failed');
    if(!(await denied(review(4,null,"2026-12-01","2027-01-01","3 minutes","1 day","null action",x.run+"-null"),'22023','provider_normalization_policy_invalid')))throw Error('NULL action accepted');
    await s.query("delete from public.e10_organization_role_permissions where organization_id=$1 and role_id=$2 and capability='act.configure_attendance_normalization'",[x.org,x.role]);
    if(!(await denied(review(4,"supersede","2026-12-01","2027-01-01","3 minutes","1 day","missing cap",x.run+"-nocap"),'42501','provider_normalization_policy_denied')))throw Error('missing capability accepted');
    await s.query("insert into public.e10_organization_role_permissions values($1,$2,'act.configure_attendance_normalization',true)",[x.org,x.role]);await s.query("update public.e10_organization_memberships set status='suspended' where organization_id=$1 and user_id=$2",[x.org,x.user]);
    if(!(await denied(review(4,"supersede","2026-12-01","2027-01-01","3 minutes","1 day","inactive",x.run+"-inactive"),'42501','provider_normalization_policy_denied')))throw Error('inactive member accepted');
    await s.query("update public.e10_organization_memberships set status='active' where organization_id=$1 and user_id=$2",[x.org,x.user]);
    if(!(await denied(a.query(call,[randomUUID(),0,"enable","2026-01-01","2027-01-01","3 minutes","1 day","foreign",x.run+"-foreign"]),'42501','provider_normalization_policy_denied')))throw Error('foreign organization accepted');
    const current = Number(
      (
        await s.query(
          "select count(*) n from public.e10_current_provider_presence_normalization_policies where organization_id=$1",
          [x.org],
        )
      ).rows[0].n,
    );
    if (current !== 0) throw Error("future policy appeared current");
    if (
      !(await denied(
        review(2,"supersede","2026-10-01","2027-01-01","4 minutes","2 days","stale",x.run+"-4"),
        "40001",
        "provider_normalization_policy_revision_conflict",
      ))
    )
      throw Error("stale CAS accepted");
    const acl = (
      await s.query(
        "select has_function_privilege('anon','public.e10_org_review_provider_presence_normalization_policy(uuid,text,bigint,text,timestamptz,timestamptz,interval,interval,bigint,text,jsonb,text)','execute') anon,has_table_privilege('authenticated','public.e10_provider_presence_normalization_policy_decisions','select') direct",
      )
    ).rows[0];
    if (acl.anon || acl.direct) throw Error("ACL failed");
    ok = true;
  } finally {
    await a.query("reset role").catch(() => {});
    await s.query("set session_replication_role=replica");
    for (const t of [
      "e10_provider_presence_normalization_policy_decisions",
      "e10_presence_policy_state_history",
      "e10_presence_collection_policies",
      "e10_organization_role_permissions",
      "e10_organization_memberships",
      "e10_organization_roles",
      "e10_reporting_dataset_revisions",
    ])
      await s.query(`delete from public.${t} where organization_id=$1`, [
        x.org,
      ]);
    await s.query("delete from public.e10_organizations where id=$1", [x.org]);
    await s.query("set session_replication_role=origin");
    await s.query("delete from auth.users where id=$1", [x.user]);
    const residue = Number(
      (
        await s.query(
          "select count(*) n from public.e10_organizations where id=$1",
          [x.org],
        )
      ).rows[0].n,
    );
    await Promise.all([s.end(), a.end()]);
    if (residue) throw Error("cleanup failed");
  }
  if (ok) console.log("TA-X7c provider normalization policy: PASS");
}
main().catch((e) => {
  console.error(e.stack);
  process.exit(1);
});
