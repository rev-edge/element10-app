const { Client } = require("pg");
const { randomUUID } = require("crypto");

const db =
  process.env.E10_DB_URL ||
  "postgresql://postgres:postgres@127.0.0.1:54322/postgres";

async function rejected(promise, code, message) {
  try {
    await promise;
    return false;
  } catch (error) {
    return (
      error.code === code &&
      (message === undefined || error.message === message)
    );
  }
}

async function main() {
  const c = new Client({ connectionString: db });
  await c.connect();
  const x = {
    org: randomUUID(),
    org2: randomUUID(),
    user: randomUUID(),
    session: randomUUID(),
    unrelatedSession: randomUUID(),
    streamA: randomUUID(),
    streamB: randomUUID(),
    unrelatedStream: randomUUID(),
    segmentA: randomUUID(),
    segmentB: randomUUID(),
    unrelatedSegment: randomUUID(),
    policy: randomUUID(),
    coverage: randomUUID(),
    platform: randomUUID(),
  };
  const fp = () =>
    c.query(
      "select e10.provider_normalization_dependency_fingerprint($1,'whatnot','2026-01-01T00:00:00Z','2026-02-01T00:00:00Z','2026-02-01T00:00:00Z',100) value",
      [x.org],
    );
  let ok = false;
  try {
    await c.query(
      "insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at)values($1,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',$2,now(),now())",
      [x.user, `${x.user}@x.invalid`],
    );
    await c.query(
      "insert into public.e10_organizations(id,slug,name)values($1,$2,'X7c dependency fingerprint')",
      [x.org, `x7cdf-${x.org.slice(0, 8)}`],
    );
    await c.query(
      "insert into public.e10_organizations(id,slug,name)values($1,$2,'X7c dependency hostile')",
      [x.org2, `x7cdf-${x.org2.slice(0, 8)}`],
    );
    await c.query(
      "insert into public.e10_platforms(id,slug,current_name)values($1,$2,'X7c provider B')",
      [x.platform, `x7c-provider-${x.platform.slice(0, 8)}`],
    );
    await c.query(
      "insert into public.e10_platform_keys(platform_id,key_kind,key_value)values($1,'provider','provider-b')",
      [x.platform],
    );
    await c.query(
      "insert into public.e10_break_sessions(id,organization_id,streamer_uid,name,status,visibility,created_at,ended_at)values($1,$3,$4,'Fingerprint','ended','private','2026-01-01','2026-01-31'),($2,$3,$4,'Unrelated','ended','private','2025-01-01','2025-01-31')",
      [x.session, x.unrelatedSession, x.org, x.user],
    );
    await c.query(
      "insert into public.e10_presence_collection_policies(organization_id,policy_version,source_class,provider_key,enabled,notice_version,heartbeat_expiry_seconds,min_event_interval_ms,max_events_per_minute,retention_interval,coverage_label,effective_from)values($1,1,'authorized_platform','whatnot',true,'n1',300,0,60,interval '30 days','fixture','2026-01-01'),($1,1,'authorized_platform','provider-b',true,'n1',300,0,60,interval '30 days','fixture','2026-01-01')",
      [x.org],
    );
    await c.query(
      "insert into public.e10_provider_presence_normalization_policy_decisions(id,organization_id,provider_key,revision,action,effective_from,effective_through,heartbeat_expiry,maximum_late_arrival,collection_policy_version,reason,evidence,idempotency_key,request_fingerprint)values($1,$2,'whatnot',1,'enable','2026-01-01','2027-01-01',interval '5 minutes',interval '1 day',1,'fixture','{}','policy','policy-fp')",
      [x.policy, x.org],
    );
    await c.query(
      "insert into public.e10_session_presence_streams(id,organization_id,session_id,source_class,provider_key,subject_key,connection_id,platform_attendee_key,identity_status,collection_policy_version,notice_version,coverage_label,retention_expires_at)values($1,$4,$5,'authorized_platform','whatnot','attendee-a','connection-a','attendee-a','unresolved',1,'n1','fixture','2027-01-01'),($2,$4,$5,'authorized_platform','provider-b','attendee-b','connection-b','attendee-b','unresolved',1,'n1','fixture','2027-01-01'),($3,$4,$6,'authorized_platform','whatnot','unrelated','unrelated','unrelated','unresolved',1,'n1','fixture','2027-01-01')",
      [x.streamA, x.streamB, x.unrelatedStream, x.org, x.session, x.unrelatedSession],
    );
    await c.query(
      "insert into public.e10_session_presence_segments(id,organization_id,stream_id,segment_sequence,heartbeat_expiry_seconds,retention_expires_at,collection_policy_version,notice_version,coverage_label)values($1,$4,$5,1,300,'2027-01-01',1,'n1','fixture'),($2,$4,$6,1,300,'2027-01-01',1,'n1','fixture'),($3,$4,$7,1,300,'2027-01-01',1,'n1','fixture')",
      [x.segmentA, x.segmentB, x.unrelatedSegment, x.org, x.streamA, x.streamB, x.unrelatedStream],
    );

    const base = (await fp()).rows[0].value;
    const repeat = (await fp()).rows[0].value;
    if (!/^[0-9a-f]{64}$/.test(base) || repeat !== base)
      throw Error("fingerprint is not stable SHA-256");
    await c.query("set timezone='America/Los_Angeles';set intervalstyle='iso_8601'");
    if ((await fp()).rows[0].value !== base)
      throw Error("session time rendering changed fingerprint");
    await c.query("set timezone='UTC';set intervalstyle='postgres'");

    const revoke = randomUUID();
    await c.query(
      "insert into public.e10_provider_presence_normalization_policy_decisions(id,organization_id,provider_key,revision,action,effective_from,effective_through,heartbeat_expiry,maximum_late_arrival,collection_policy_version,reason,evidence,supersedes_decision_id,idempotency_key,request_fingerprint)values($1,$2,'whatnot',2,'revoke','2026-01-10','2026-01-11',null,null,1,'short suppressor','{}',$3,'revoke','revoke-fp')",
      [revoke, x.org, x.policy],
    );
    const afterRevoke = (await fp()).rows[0].value;
    if (afterRevoke === base)
      throw Error("historical suppressor decision did not change fingerprint");
    const restore = randomUUID();
    await c.query(
      "insert into public.e10_provider_presence_normalization_policy_decisions(id,organization_id,provider_key,revision,action,effective_from,effective_through,heartbeat_expiry,maximum_late_arrival,collection_policy_version,reason,evidence,supersedes_decision_id,idempotency_key,request_fingerprint)values($1,$2,'whatnot',3,'supersede','2026-01-12','2027-01-01',interval '5 minutes',interval '1 day',1,'restore','{}',$3,'restore','restore-fp')",
      [restore, x.org, revoke],
    );
    const afterRestore = (await fp()).rows[0].value;
    if (afterRestore === afterRevoke)
      throw Error("restored policy decision did not change fingerprint");

    const missingTime = randomUUID();
    await c.query(
      "insert into public.e10_session_presence_events(id,organization_id,stream_id,segment_id,event_sequence,event_kind,server_received_at,provider_occurred_at,provider_event_id,provider_key,evidence,request_fingerprint)values($1,$2,$3,$4,1,'join','2026-01-02',null,'missing-time','whatnot','{}','event-missing')",
      [missingTime, x.org, x.streamA, x.segmentA],
    );
    const afterMissing = (await fp()).rows[0].value;
    if (afterMissing === afterRestore) throw Error("missing provider time was omitted");

    const futureTime = randomUUID();
    await c.query(
      "insert into public.e10_session_presence_events(id,organization_id,stream_id,segment_id,event_sequence,event_kind,server_received_at,provider_occurred_at,provider_event_id,provider_key,evidence,request_fingerprint)values($1,$2,$3,$4,2,'heartbeat','2026-01-03','2027-01-03','future-time','whatnot','{}','event-future')",
      [futureTime, x.org, x.streamA, x.segmentA],
    );
    const afterFuture = (await fp()).rows[0].value;
    if (afterFuture === afterMissing)
      throw Error("future provider time was omitted");

    await c.query(
      "insert into public.e10_session_presence_events(id,organization_id,stream_id,segment_id,event_sequence,event_kind,server_received_at,provider_occurred_at,provider_event_id,provider_key,evidence,request_fingerprint)values($1,$2,$3,$4,1,'join','2026-01-04','2026-01-04','other-provider','provider-b','{}','event-other')",
      [randomUUID(), x.org, x.streamB, x.segmentB],
    );
    if ((await fp()).rows[0].value !== afterFuture)
      throw Error("other provider changed fingerprint");

    await c.query(
      "insert into public.e10_session_presence_events(id,organization_id,stream_id,segment_id,event_sequence,event_kind,server_received_at,provider_occurred_at,provider_event_id,provider_key,evidence,request_fingerprint)values($1,$2,$3,$4,1,'join','2025-01-02','2025-01-02','other-window','whatnot','{}','event-other-window')",
      [randomUUID(), x.org, x.unrelatedStream, x.unrelatedSegment],
    );
    if ((await fp()).rows[0].value !== afterFuture)
      throw Error("non-overlapping provider window changed fingerprint");

    await c.query(
      "insert into public.e10_session_presence_events(id,organization_id,stream_id,segment_id,event_sequence,event_kind,server_received_at,provider_occurred_at,provider_event_id,provider_key,evidence,request_fingerprint)values($1,$2,$3,$4,3,'leave','2026-02-02','2026-01-05','after-cutoff','whatnot','{}','event-late-receipt')",
      [randomUUID(), x.org, x.streamA, x.segmentA],
    );
    const afterLateReceipt = (await fp()).rows[0].value;
    if (afterLateReceipt === afterFuture)
      throw Error("later-recorded relevant evidence did not invalidate fingerprint");

    await c.query(
      "insert into public.e10_session_presence_events(id,organization_id,stream_id,segment_id,event_sequence,event_kind,server_received_at,provider_occurred_at,provider_event_id,provider_key,corrects_event_id,evidence,request_fingerprint)values($1,$2,$3,$4,4,'join','2026-03-01','2026-01-02','correction','whatnot',$5,'{}','event-correction')",
      [randomUUID(), x.org, x.streamA, x.segmentA, missingTime],
    );
    const afterCorrection = (await fp()).rows[0].value;
    if (afterCorrection === afterLateReceipt)
      throw Error("later correction did not invalidate fingerprint");

    const alternateCutoff = (
      await c.query(
        "select e10.provider_normalization_dependency_fingerprint($1,'whatnot','2026-01-01T00:00:00Z','2026-02-01T00:00:00Z','2026-02-02T00:00:00Z',100) value",
        [x.org],
      )
    ).rows[0].value;
    if (alternateCutoff === afterCorrection)
      throw Error("distinct cutoff collided with dependency identity");

    await c.query(
      "insert into public.e10_attendance_coverage_assertions(id,organization_id,coverage_key,revision,action,source_class,provider_key,covered_from,covered_to,coverage_status,policy_version,review_basis,evidence,idempotency_key,request_fingerprint)values($1,$2,$3,1,'assert','authorized_platform','whatnot','2026-01-01','2026-02-01','complete',1,'fixture','{}','coverage','coverage-fp')",
      [x.coverage, x.org, x.coverage],
    );
    const afterCoverage = (await fp()).rows[0].value;
    if (afterCoverage === afterCorrection)
      throw Error("coverage decision did not change fingerprint");

    await c.query(
      "insert into public.e10_session_presence_attribution_decisions(id,organization_id,stream_id,revision,action,customer_id,reason,evidence,idempotency_key,request_fingerprint)values($1,$2,$3,1,'unattribute',null,'fixture','{}','attribution','attribution-fp')",
      [randomUUID(), x.org, x.streamA],
    );
    if ((await fp()).rows[0].value === afterCoverage)
      throw Error("attribution decision did not change fingerprint");

    if (
      !(await rejected(
        c.query(
          "select e10.provider_normalization_dependency_fingerprint($1,'whatnot','2026-01-01T00:00:00Z','2026-02-01T00:00:00Z','2026-02-01T00:00:00Z',1)",
          [x.org],
        ),
        "54000",
        "provider_normalization_dependency_bound_exceeded",
      ))
    )
      throw Error("event bound did not fail closed");
    if (
      !(await rejected(
        c.query(
          "select e10.provider_normalization_dependency_fingerprint($1,'whatnot','2026-02-01T00:00:00Z','2026-01-01T00:00:00Z','2026-02-01T00:00:00Z',100)",
          [x.org],
        ),
        "22023",
        "provider_normalization_dependency_bounds_invalid",
      ))
    )
      throw Error("invalid bounds accepted");

    await c.query("set role authenticated");
    const aclDenied = await rejected(
      c.query(
        "select e10.provider_normalization_dependency_fingerprint($1,'whatnot','2026-01-01T00:00:00Z','2026-02-01T00:00:00Z','2026-02-01T00:00:00Z',100)",
        [x.org],
      ),
      "42501",
    );
    await c.query("reset role");
    if (!aclDenied) throw Error("authenticated caller executed service function");
    await c.query("set role anon");
    const anonDenied = await rejected(
      c.query(
        "select e10.provider_normalization_dependency_fingerprint($1,'whatnot','2026-01-01T00:00:00Z','2026-02-01T00:00:00Z','2026-02-01T00:00:00Z',100)",
        [x.org],
      ),
      "42501",
    );
    await c.query("reset role");
    if (!anonDenied) throw Error("anon caller executed service function");

    const beforeForeign = (await fp()).rows[0].value;
    await c.query(
      "insert into public.e10_presence_collection_policies(organization_id,policy_version,source_class,provider_key,enabled,notice_version,heartbeat_expiry_seconds,min_event_interval_ms,max_events_per_minute,retention_interval,coverage_label,effective_from)values($1,1,'authorized_platform','whatnot',true,'n1',300,0,60,interval '30 days','foreign','2026-01-01')",
      [x.org2],
    );
    if ((await fp()).rows[0].value !== beforeForeign)
      throw Error("foreign organization changed fingerprint");
    ok = true;
  } finally {
    await c.query("reset role").catch(() => {});
    await c.query("set session_replication_role=replica");
    for (const table of [
      "e10_session_presence_attribution_decisions",
      "e10_attendance_coverage_assertions",
      "e10_session_presence_events",
      "e10_session_presence_segments",
      "e10_session_presence_streams",
      "e10_provider_presence_normalization_policy_decisions",
      "e10_presence_policy_state_history",
      "e10_presence_collection_policies",
      "e10_break_sessions",
      "e10_reporting_dataset_revisions",
    ])
      await c.query(`delete from public.${table} where organization_id in($1,$2)`, [
        x.org,x.org2,
      ]);
    await c.query("delete from public.e10_organizations where id in($1,$2)", [x.org,x.org2]);
    await c.query("delete from public.e10_platform_keys where platform_id=$1", [x.platform]);
    await c.query("delete from public.e10_platforms where id=$1", [x.platform]);
    await c.query("set session_replication_role=origin");
    await c.query("delete from auth.users where id=$1", [x.user]);
    const residue = Number(
      (
        await c.query(
          "select count(*) n from public.e10_organizations where id in($1,$2)",
          [x.org,x.org2],
        )
      ).rows[0].n,
    );
    await c.end();
    if (residue) throw Error("cleanup failed");
  }
  if (ok) console.log("TA-X7c provider dependency fingerprint: PASS");
}

main().catch((error) => {
  console.error(error.stack);
  process.exit(1);
});
