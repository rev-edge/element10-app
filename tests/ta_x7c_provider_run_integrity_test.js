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
  const c = new Client({ connectionString: db });
  await c.connect();
  const x = {
    org: randomUUID(),
    org2: randomUUID(),
    user: randomUUID(),
    session: randomUUID(),
    stream: randomUUID(),
    segment: randomUUID(),
    event: randomUUID(),
    policy: randomUUID(),
    run: randomUUID(),
    run2: randomUUID(),
  };
  let ok = false;
  try {
    await c.query(
      "insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at)values($1,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',$2,now(),now())",
      [x.user, x.user + "@x.invalid"],
    );
    await c.query(
      "insert into public.e10_organizations(id,slug,name)values($1,$3,'X7c run'),($2,$4,'X7c hostile')",
      [
        x.org,
        x.org2,
        "x7ci-" + x.org.slice(0, 8),
        "x7ch-" + x.org2.slice(0, 8),
      ],
    );
    await c.query(
      "insert into public.e10_break_sessions(id,organization_id,streamer_uid,name,status,visibility)values($1,$2,$3,'Run','active','private')",
      [x.session, x.org, x.user],
    );
    await c.query(
      "insert into public.e10_presence_collection_policies(organization_id,policy_version,source_class,provider_key,enabled,notice_version,heartbeat_expiry_seconds,min_event_interval_ms,max_events_per_minute,retention_interval,coverage_label,effective_from)values($1,1,'authorized_platform','whatnot',true,'n1',300,0,60,interval '30 days','fixture','2026-01-01')",
      [x.org],
    );
    await c.query(
      "insert into public.e10_provider_presence_normalization_policy_decisions(id,organization_id,provider_key,revision,action,effective_from,effective_through,heartbeat_expiry,maximum_late_arrival,collection_policy_version,reason,evidence,idempotency_key,request_fingerprint)values($1,$2,'whatnot',1,'enable','2026-01-01','2027-01-01',interval '5 minutes',interval '1 day',1,'fixture','{}','policy','fp')",
      [x.policy, x.org],
    );
    await c.query(
      "insert into public.e10_session_presence_streams(id,organization_id,session_id,source_class,provider_key,subject_key,connection_id,platform_attendee_key,identity_status,collection_policy_version,notice_version,coverage_label,retention_expires_at)values($1,$2,$3,'authorized_platform','whatnot','attendee','connection','attendee','unresolved',1,'n1','fixture','2027-01-01')",
      [x.stream, x.org, x.session],
    );
    await c.query(
      "insert into public.e10_session_presence_segments(id,organization_id,stream_id,segment_sequence,heartbeat_expiry_seconds,retention_expires_at,collection_policy_version,notice_version,coverage_label)values($1,$2,$3,1,300,'2027-01-01',1,'n1','fixture')",
      [x.segment, x.org, x.stream],
    );
    await c.query(
      "insert into public.e10_session_presence_events(id,organization_id,stream_id,segment_id,event_sequence,event_kind,server_received_at,provider_occurred_at,provider_event_id,provider_key,evidence,request_fingerprint)values($1,$2,$3,$4,1,'join','2026-01-02 10:00Z','2026-01-02 10:00Z','event-a','whatnot','{}','event-fp')",
      [x.event, x.org, x.stream, x.segment],
    );
    const run =
      "insert into public.e10_provider_presence_normalization_runs(id,organization_id,provider_key,policy_decision_id,window_from,window_to,observation_cutoff,input_reporting_revision,dependency_fingerprint,algorithm_version,status,input_event_count,interval_count,quarantine_count,idempotency_key,request_fingerprint)values($1,$2,'whatnot',$3,'2026-01-01','2026-02-01','2026-02-01',1,$4,'provider-presence-v1','building',1,1,0,$5,'run-fp')";
    if(!await denied(c.query(run.replace("'whatnot'","'provider-b'"),[randomUUID(),x.org,x.policy,"c".repeat(64),"wrong-provider"]),"23503","provider_normalization_run_identity_invalid"))throw Error("policy/provider mismatch accepted");
    if(!await denied(c.query(run.replace("'building'","'complete'"),[randomUUID(),x.org,x.policy,"d".repeat(64),"complete-insert"]),"23503","provider_normalization_run_identity_invalid"))throw Error("completed insert bypassed seal");
    await c.query(run, [x.run, x.org, x.policy, "a".repeat(64), "run-a"]);
    await c.query(
      "insert into public.e10_provider_presence_normalized_intervals(organization_id,run_id,session_id,stream_id,subject_key,connection_id,started_at,ended_at,expiry_reason,source_event_ids)values($1,$2,$3,$4,'attendee','connection','2026-01-02 10:00Z','2026-01-02 10:05Z','heartbeat_expiry',$5)",
      [x.org, x.run, x.session, x.stream, [x.event]],
    );
    if(!await denied(c.query("update public.e10_provider_presence_normalization_runs set status='complete',window_from='2026-01-02',output_reporting_revision=2,completed_at=clock_timestamp() where id=$1",[x.run]),"55000","provider_normalization_run_immutable"))throw Error("seal changed frozen input");
    await c.query(
      "update public.e10_provider_presence_normalization_runs set status='complete',output_reporting_revision=2,completed_at=clock_timestamp() where organization_id=$1 and id=$2",
      [x.org, x.run],
    );
    if (
      !(await denied(
        c.query(
          "insert into public.e10_provider_presence_normalized_intervals(organization_id,run_id,session_id,stream_id,subject_key,connection_id,started_at,ended_at,expiry_reason,source_event_ids)values($1,$2,$3,$4,'attendee','connection','2026-01-03','2026-01-04','provider_leave',$5)",
          [x.org, x.run, x.session, x.stream, [x.event]],
        ),
        "55000",
        "provider_normalization_run_sealed",
      ))
    )
      throw Error("sealed append accepted");
    if (
      !(await denied(
        c.query(
          "update public.e10_provider_presence_normalization_runs set interval_count=2 where id=$1",
          [x.run],
        ),
        "55000",
        "provider_normalization_run_immutable",
      ))
    )
      throw Error("sealed run update accepted");
    await c.query(run, [x.run2, x.org, x.policy, "b".repeat(64), "run-b"]);
    if (
      !(await denied(
        c.query(
          "insert into public.e10_provider_presence_normalized_intervals(organization_id,run_id,session_id,stream_id,subject_key,connection_id,started_at,ended_at,expiry_reason,source_event_ids)values($1,$2,$3,$4,'wrong','connection','2026-01-02','2026-01-03','provider_leave',$5)",
          [x.org, x.run2, x.session, x.stream, [x.event]],
        ),
        "23503",
        "provider_normalization_child_identity_invalid",
      ))
    )
      throw Error("hostile subject link accepted");
    if (
      !(await denied(
        c.query(
          "update public.e10_provider_presence_normalization_runs set status='complete',output_reporting_revision=2,completed_at=clock_timestamp() where id=$1",
          [x.run2],
        ),
        "55000",
        "provider_normalization_run_immutable",
      ))
    )
      throw Error("count-mismatched seal accepted");
    ok = true;
  } finally {
    await c.query("set session_replication_role=replica");
    for (const t of [
      "e10_provider_presence_normalized_intervals",
      "e10_provider_presence_quarantine_rows",
      "e10_provider_presence_normalization_runs",
      "e10_session_presence_events",
      "e10_session_presence_segments",
      "e10_session_presence_streams",
      "e10_provider_presence_normalization_policy_decisions",
      "e10_presence_policy_state_history",
      "e10_presence_collection_policies",
      "e10_break_sessions",
      "e10_reporting_dataset_revisions",
    ])
      await c.query(`delete from public.${t} where organization_id in($1,$2)`, [
        x.org,
        x.org2,
      ]);
    await c.query("delete from public.e10_organizations where id in($1,$2)", [
      x.org,
      x.org2,
    ]);
    await c.query("set session_replication_role=origin");
    await c.query("delete from auth.users where id=$1", [x.user]);
    const residue = Number(
      (
        await c.query(
          "select count(*) n from public.e10_organizations where id in($1,$2)",
          [x.org, x.org2],
        )
      ).rows[0].n,
    );
    await c.end();
    if (residue) throw Error("cleanup failed");
  }
  if (ok) console.log("TA-X7c provider normalization run integrity: PASS");
}
main().catch((e) => {
  console.error(e.stack);
  process.exit(1);
});
