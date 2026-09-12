const { Client } = require("pg");
const { randomUUID } = require("crypto");
const db =
    process.env.DATABASE_URL ||
    "postgresql://postgres:postgres@127.0.0.1:54322/postgres",
  run = randomUUID();
const x = {
  org: randomUUID(),
  user: randomUUID(),
  role: randomUUID(),
  product: randomUUID(),
  config: randomUUID(),
  release: randomUUID(),
  variant: randomUUID(),
  player: randomUUID(),
};
const admin = new Client({ connectionString: db }),
  locker = new Client({ connectionString: db }),
  a = new Client({ connectionString: db }),
  b = new Client({ connectionString: db }),
  obs = new Client({ connectionString: db });
let pending = [];
async function auth(c) {
  await c.query("select set_config('request.jwt.claims',$1,false)", [
    JSON.stringify({ sub: x.user, role: "authenticated" }),
  ]);
  await c.query("set role authenticated");
}
const settled = (p) =>
  p.then(
    (v) => ({ ok: true, v }),
    (error) => ({ ok: false, error }),
  );
const bounded = (p) =>
  Promise.race([
    p,
    new Promise((_, rej) =>
      setTimeout(() => rej(Error("R5 bounded timeout")), 8000),
    ),
  ]);
async function blocked(pid, holder, label) {
  for (let i = 0; i < 160; i++) {
    const q = await obs.query("select $2=any(pg_blocking_pids($1)) waiting", [
      pid,
      holder,
    ]);
    if (q.rows[0].waiting) {
      console.log(
        `[proof] ${label}: backend ${pid} waits on exact holder ${holder}`,
      );
      return;
    }
    await new Promise((r) => setTimeout(r, 25));
  }
  throw Error(`${label} wait not established`);
}
async function setup() {
  await admin.query(
    "insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at)values($1,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',$2,now(),now())",
    [x.user, run + "@r5.invalid"],
  );
  await admin.query(
    "insert into public.e10_organizations(id,slug,name)values($1,$2,'R5 race')",
    [x.org, "r5-" + run.slice(0, 8)],
  );
  await admin.query(
    "insert into public.e10_organization_roles(id,organization_id,key,name)values($1,$2,'r5','R5')",
    [x.role, x.org],
  );
  await admin.query(
    "insert into public.e10_organization_memberships(organization_id,user_id,role_id,status) values($1,$2,$3,'active')",
    [x.org, x.user, x.role],
  );
  await admin.query(
    "insert into public.e10_organization_role_permissions values($1,$2,'catalog.propose',true)",
    [x.org, x.role],
  );
  await admin.query(
    "insert into public.e10_product_masters(id,organization_id,name,created_by)values($1,$2,'R5 parent',$3)",
    [x.product, x.org, x.user],
  );
  await admin.query(
    "insert into public.e10_product_configurations(id,organization_id,product_master_id,name,created_by)values($1,$2,$3,'R5 config',$4)",
    [x.config, x.org, x.product, x.user],
  );
  await admin.query(
    "insert into public.e10_catalog_releases(id,release_name)values($1,'R5 mapping target')",
    [x.release],
  );
  await admin.query("insert into public.e10_catalog_variants(id,release_id,card_number)values($1,$2,'R5')",[x.variant,x.release]);
  await admin.query("insert into public.e10_players(id,name)values($1,'R5 player')",[x.player]);
}
async function main() {
  await Promise.all([admin, locker, a, b, obs].map((c) => c.connect()));
  for (const c of [locker, a, b]) await c.query("set statement_timeout='8s'");
  await setup();
  await Promise.all([auth(a), auth(b)]);
  const lp = Number(
      (await locker.query("select pg_backend_pid()pid")).rows[0].pid,
    ),
    ap = Number((await a.query("select pg_backend_pid()pid")).rows[0].pid),
    bp = Number((await b.query("select pg_backend_pid()pid")).rows[0].pid);
  const same = "same-" + run;
  await locker.query("begin");
  await locker.query("select pg_advisory_xact_lock(hashtextextended($1,0))", [
    x.org + "|x1-product-master|" + same,
  ]);
  const pa = settled(
      a.query("select e10_org_create_product_master($1,'Same',null,'{}',$2)r", [
        x.org,
        same,
      ]),
    ),
    pb = settled(
      b.query("select e10_org_create_product_master($1,'Same',null,'{}',$2)r", [
        x.org,
        same,
      ]),
    );
  pending = [pa, pb];
  await blocked(ap, lp, "same-key A");
  await blocked(bp, lp, "same-key B");
  await locker.query("commit");
  const sr = await bounded(Promise.all([pa, pb]));
  pending = [];
  if (
    sr.some((z) => !z.ok) ||
    sr.filter((z) => z.v.rows[0].r.replay).length !== 1 ||
    new Set(sr.map((z) => z.v.rows[0].r.product_master_id)).size !== 1
  )
    throw Error("same-key requests did not converge");
  const changed = "changed-" + run;
  await locker.query("begin");
  await locker.query("select pg_advisory_xact_lock(hashtextextended($1,0))",[x.org+"|x1-product-master|"+changed]);
  const ca=settled(a.query("select e10_org_create_product_master($1,'First',null,'{}',$2)r",[x.org,changed]));
  const cb=settled(b.query("select e10_org_create_product_master($1,'Second',null,'{}',$2)r",[x.org,changed]));
  pending=[ca,cb];await blocked(ap,lp,"changed-key A");await blocked(bp,lp,"changed-key B");await locker.query("commit");
  const cr=await bounded(Promise.all([ca,cb]));pending=[];
  if(cr.filter(z=>z.ok).length!==1||cr.filter(z=>!z.ok).length!==1||cr.find(z=>!z.ok).error.code!=="22023")throw Error("same-key changed payload was not refused");
  const v1 = settled(
      a.query(
        "select e10_org_create_configuration_version($1,$2,0,'draft','box','each',1,null,'{}',$3)r",
        [x.org, x.config, "version-a-" + run],
      ),
    ),
    v2 = settled(
      b.query(
        "select e10_org_create_configuration_version($1,$2,0,'draft','box','each',1,null,'{}',$3)r",
        [x.org, x.config, "version-b-" + run],
      ),
    );
  const vr = await bounded(Promise.all([v1, v2]));
  if (
    vr.filter((z) => z.ok).length !== 1 ||
    vr.filter((z) => !z.ok).length !== 1 ||
    vr.find((z) => !z.ok).error.code !== "40001"
  )
    throw Error("competing version CAS failed");
  await locker.query("begin");
  await locker.query("select id from public.e10_product_masters where id=$1 for update",[x.product]);
  const denied = settled(
    a.query(
      "select e10_org_create_product_configuration($1,$2,'Denied',null,'{}',$3)",
      [x.org, x.product, "revoked-" + run],
    ),
  );
  pending = [denied];
  await blocked(ap, lp, "tenant final authority");
  await admin.query("delete from public.e10_organization_memberships where organization_id=$1 and user_id=$2",[x.org,x.user]);
  await locker.query("commit");
  const dr = await bounded(denied);
  pending = [];
  if (dr.ok || dr.error.code !== "42501")
    throw Error("tenant post-lock revocation escaped");
  await admin.query("insert into public.e10_organization_memberships(organization_id,user_id,role_id,status)values($1,$2,$3,'active')",[x.org,x.user,x.role]);
  await locker.query("begin");
  await locker.query("select id from public.e10_catalog_variants where id=$1 for update",[x.variant]);
  const itemDenied=settled(a.query("select e10_org_create_unique_item($1,null,$2,'collectible',null,null,null,null,null,'{}','{}',$3)",[x.org,x.variant,"item-revoke-"+run]));
  pending=[itemDenied];await blocked(ap,lp,"unique-item target final authority");
  await admin.query("delete from public.e10_organization_memberships where organization_id=$1 and user_id=$2",[x.org,x.user]);
  await locker.query("commit");const idr=await bounded(itemDenied);pending=[];
  if(idr.ok||idr.error.code!=="42501")throw Error("unique-item target-lock revocation escaped");
  await admin.query("insert into public.e10_organization_memberships(organization_id,user_id,role_id,status)values($1,$2,$3,'active')",[x.org,x.user,x.role]);
  await admin.query('insert into public.e10_platform_admins(user_id)values($1)',[x.user]);
  await locker.query("begin");await locker.query("select id from public.e10_players where id=$1 for update",[x.player]);
  const variantDenied=settled(b.query("select e10_platform_create_catalog_variant($1,'R',null,null,null,null,null,false,null,'{}',$2,$3)",[x.release,JSON.stringify([{player_id:x.player,position:1}]),"variant-revoke-"+run]));
  pending=[variantDenied];await blocked(bp,lp,"variant subject final authority");
  await admin.query("delete from public.e10_platform_admins where user_id=$1",[x.user]);await locker.query("commit");
  const vdr=await bounded(variantDenied);pending=[];
  if(vdr.ok||vdr.error.code!=="42501")throw Error("variant subject-lock revocation escaped");
  await admin.query('insert into public.e10_platform_admins(user_id)values($1)',[x.user]);
  const mapKey = "map-" + run,
    provider = "r5-" + run;
  await locker.query("begin");
  await locker.query("select pg_advisory_xact_lock(hashtextextended($1,0))", [
    "platform|x1-mapping|" + provider + "|release|external",
  ]);
  const mp = settled(
    b.query(
      "select e10_platform_review_catalog_identity_mapping($1,'release','external',null,$2,null,'candidate',null,'{}',$3)",
      [provider, x.release, mapKey],
    ),
  );
  pending = [mp];
  await blocked(bp, lp, "platform mapping authority");
  await admin.query("delete from public.e10_platform_admins where user_id=$1", [
    x.user,
  ]);
  await locker.query("commit");
  const mr = await bounded(mp);
  pending = [];
  if (mr.ok || mr.error.code !== "42501")
    throw Error("platform post-lock revocation escaped");
  const residue = Number(
    (
      await admin.query(
        "select(select count(*)from public.e10_product_configurations where organization_id=$1 and name='Denied')+(select count(*)from public.e10_catalog_identity_mappings where provider=$2)+(select count(*)from public.e10_x1_creation_commands where idempotency_key in($3,$4))n",
        [x.org, provider, "revoked-" + run, mapKey],
      )
    ).rows[0].n,
  );
  if (residue) throw Error("revoked writers left residue");
  console.log("TA-R5 concurrent creation/revision/final-authority: PASS");
}
async function cleanup() {
  await admin.query("reset role");
  await admin.query("set session_replication_role=replica");
  for (const t of [
    "e10_audit_change_records",
    "e10_audit_change_batches",
    "e10_x1_creation_commands",
    "e10_product_configuration_versions",
    "e10_product_configurations",
    "e10_product_masters",
    "e10_organization_role_permissions",
    "e10_organization_memberships",
    "e10_organization_roles",
    "e10_organization_status_transitions",
  ])
    await admin.query(
      `delete from public.${t} where ${t === "e10_x1_creation_commands" ? "authority_scope" : "organization_id"}=$1`,
      [x.org],
    );
  await admin.query(
    "delete from public.e10_catalog_identity_mappings where provider=$1",
    ["r5-" + run],
  );
  await admin.query("delete from public.e10_catalog_variant_subjects where variant_id=$1",[x.variant]);
  await admin.query("delete from public.e10_catalog_variants where id=$1",[x.variant]);
  await admin.query("delete from public.e10_catalog_releases where id=$1", [
    x.release,
  ]);
  await admin.query("delete from public.e10_players where id=$1",[x.player]);
  await admin.query("delete from public.e10_platform_admins where user_id=$1", [
    x.user,
  ]);
  await admin.query("delete from public.e10_organizations where id=$1", [
    x.org,
  ]);
  await admin.query("delete from auth.users where id=$1", [x.user]);
  const residue = Number((await admin.query(
    "select (select count(*) from public.e10_audit_change_batches where organization_id=$1)+(select count(*) from public.e10_audit_change_records where organization_id=$1)+(select count(*) from public.e10_organizations where id=$1)+(select count(*) from auth.users where id=$2) n",
    [x.org,x.user],
  )).rows[0].n);
  if (residue) throw Error(`R5 cleanup residue: ${residue}`);
  await admin.query("set session_replication_role=origin");
}
(async () => {
  let error;
  try {
    await main();
  } catch (e) {
    error = e;
  } finally {
    await Promise.allSettled(pending);
    await Promise.allSettled([
      locker.query("rollback"),
      a.query("rollback"),
      b.query("rollback"),
    ]);
    try {
      await cleanup();
    } catch (e) {
      if (!error) error = e;
    }
    await Promise.allSettled([admin, locker, a, b, obs].map((c) => c.end()));
  }
  if (error) {
    console.error(error);
    process.exitCode = 1;
  }
})();
