const { Client } = require("pg");
const { randomUUID } = require("crypto");

const db = process.env.E10_DB_URL || "postgresql://postgres:postgres@127.0.0.1:54322/postgres";
async function rejected(p, code) {
  try { await p; return false; } catch (e) { return e.code === code; }
}
async function main() {
  const c = new Client({ connectionString: db });
  await c.connect();
  const x = {org:randomUUID(),user:randomUUID(),session:randomUUID(),stream:randomUUID(),segment:randomUUID(),policy:randomUUID(),coverage:randomUUID()};
  let ok=false;
  try {
    await c.query("insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at)values($1,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',$2,now(),now())",[x.user,`${x.user}@x.invalid`]);
    await c.query("insert into public.e10_organizations(id,slug,name)values($1,$2,'X7c runner')",[x.org,`x7cr-${x.org.slice(0,8)}`]);
    await c.query("insert into public.e10_break_sessions(id,organization_id,streamer_uid,name,status,visibility,created_at,ended_at)values($1,$2,$3,'Runner','ended','private','2026-01-01','2026-01-31')",[x.session,x.org,x.user]);
    await c.query("insert into public.e10_presence_collection_policies(organization_id,policy_version,source_class,provider_key,enabled,notice_version,heartbeat_expiry_seconds,min_event_interval_ms,max_events_per_minute,retention_interval,coverage_label,effective_from)values($1,1,'authorized_platform','provider-a',true,'n1',300,0,60,interval '30 days','fixture','2026-01-01')",[x.org]);
    await c.query("insert into public.e10_provider_presence_normalization_policy_decisions(id,organization_id,provider_key,revision,action,effective_from,effective_through,heartbeat_expiry,maximum_late_arrival,collection_policy_version,reason,evidence,idempotency_key,request_fingerprint)values($1,$2,'provider-a',1,'enable','2026-01-01','2027-01-01',interval '5 minutes',interval '1 day',1,'fixture','{}','policy','policy-fp')",[x.policy,x.org]);
    await c.query("insert into public.e10_attendance_coverage_assertions(id,organization_id,coverage_key,revision,action,source_class,provider_key,covered_from,covered_to,coverage_status,policy_version,review_basis,evidence,idempotency_key,request_fingerprint)values($1,$2,$3,1,'assert','authorized_platform','provider-a','2026-01-01','2026-02-01','complete',1,'fixture','{}','coverage','coverage-fp')",[x.coverage,x.org,x.coverage]);
    const unknown=(await c.query("select disposition,extract(epoch from ended_at-started_at)::int seconds from e10.provider_normalization_coverage_parts($1,'provider-a',1,'2026-01-01','2026-02-01')",[x.org])).rows;
    if(JSON.stringify(unknown)!==JSON.stringify([{disposition:'coverage_unavailable',seconds:2678400}]))throw Error(`pre-history coverage did not fail closed ${JSON.stringify(unknown)}`);
    await c.query("insert into public.e10_presence_policy_state_history(organization_id,source_class,provider_key,policy_version,enabled,state_from)values($1,'authorized_platform','provider-a',1,true,'2026-01-01')",[x.org]);
    const degraded=randomUUID();
    await c.query("insert into public.e10_attendance_coverage_assertions(id,organization_id,coverage_key,revision,action,source_class,provider_key,covered_from,covered_to,coverage_status,policy_version,review_basis,evidence,idempotency_key,request_fingerprint)values($1,$2,$1,1,'assert','authorized_platform','provider-a','2026-01-02 10:01Z','2026-01-02 10:02Z','partial',1,'fixture','{}','coverage-partial','coverage-partial-fp')",[degraded,x.org]);
    await c.query("insert into public.e10_presence_policy_state_history(organization_id,source_class,provider_key,policy_version,enabled,state_from)values($1,'authorized_platform','provider-a',1,false,'2026-01-02 10:02Z'),($1,'authorized_platform','provider-a',1,true,'2026-01-02 10:03Z')",[x.org]);
    await c.query("insert into public.e10_session_presence_streams(id,organization_id,session_id,source_class,provider_key,subject_key,connection_id,platform_attendee_key,identity_status,collection_policy_version,notice_version,coverage_label,retention_expires_at)values($1,$2,$3,'authorized_platform','provider-a','attendee','connection','attendee','unresolved',1,'n1','fixture','2027-01-01')",[x.stream,x.org,x.session]);
    await c.query("insert into public.e10_session_presence_segments(id,organization_id,stream_id,segment_sequence,heartbeat_expiry_seconds,retention_expires_at,collection_policy_version,notice_version,coverage_label)values($1,$2,$3,1,300,'2027-01-01',1,'n1','fixture')",[x.segment,x.org,x.stream]);
    const events=[
      ['join','2026-01-02T10:00:00Z','2026-01-02T10:00:01Z'],
      ['heartbeat','2026-01-02T10:02:00Z','2026-01-02T10:02:01Z'],
      ['leave','2026-01-02T10:04:00Z','2026-01-02T10:04:01Z'],
      ['join',null,'2026-01-03T10:00:00Z'],
      ['heartbeat','2026-03-01T10:00:00Z','2026-01-04T10:00:00Z'],
      ['leave','2026-01-05T10:00:00Z','2026-01-07T10:00:00Z'],
    ];
    for(let i=0;i<events.length;i++) await c.query("insert into public.e10_session_presence_events(id,organization_id,stream_id,segment_id,event_sequence,event_kind,provider_occurred_at,server_received_at,provider_event_id,provider_key,evidence,request_fingerprint)values($1,$2,$3,$4,$5,$6,$7,$8,$9,'provider-a','{}',$10)",[randomUUID(),x.org,x.stream,x.segment,i+1,events[i][0],events[i][1],events[i][2],`event-${i}`,`fp-${i}`]);
    const call="select public.e10_service_run_provider_presence_normalization($1,'provider-a',$2,'2026-01-01T00:00:00Z','2026-02-01T00:00:00Z','2026-02-01T00:00:00Z',100,'run-1') result";
    const first=(await c.query(call,[x.org,x.policy])).rows[0].result;
    if(first.replay!==false||first.status!=="complete"||first.interval_count!==2||first.quarantine_count!==5)throw Error(`unexpected runner result ${JSON.stringify(first)}`);
    const interval=(await c.query("select sum(extract(epoch from ended_at-started_at))::int seconds,array_agg(expiry_reason order by started_at) reasons from public.e10_provider_presence_normalized_intervals where run_id=$1",[first.run_id])).rows[0];
    if(interval.seconds!==120||interval.reasons.some(x=>x!=="provider_leave"))throw Error("coverage/policy clipping wrong");
    const reasons=(await c.query("select array_agg(reason order by reason) reasons from public.e10_provider_presence_quarantine_rows where run_id=$1",[first.run_id])).rows[0].reasons;
    if(JSON.stringify(reasons)!==JSON.stringify(["collection_disabled","coverage_unavailable","future_provider_time","late_beyond_policy","missing_provider_time"]))throw Error(`quarantine wrong ${reasons}`);
    const replay=(await c.query(call,[x.org,x.policy])).rows[0].result;
    if(replay.replay!==true||replay.run_id!==first.run_id)throw Error("idempotent replay created another run");
    if(!await rejected(c.query(call.replace("'run-1'","'run-2'").replace(",100,",",2,"),[x.org,x.policy]),"54000"))throw Error("hard input bound accepted");
    await c.query("set role authenticated");
    const denied=await rejected(c.query(call,[x.org,x.policy]),"42501");
    await c.query("reset role");
    if(!denied)throw Error("authenticated caller executed service runner");
    const run=(await c.query("select status,input_event_count,interval_count,quarantine_count,output_reporting_revision>input_reporting_revision advanced from public.e10_provider_presence_normalization_runs where id=$1",[first.run_id])).rows[0];
    if(run.status!=="complete"||Number(run.input_event_count)!==6||!run.advanced)throw Error("sealed run metadata wrong");
    ok=true;
  } finally {
    await c.query("reset role").catch(()=>{});await c.query("set session_replication_role=replica");
    for(const t of ["e10_provider_presence_normalized_intervals","e10_provider_presence_quarantine_rows","e10_provider_presence_normalization_runs","e10_attendance_coverage_assertions","e10_session_presence_events","e10_session_presence_segments","e10_session_presence_streams","e10_provider_presence_normalization_policy_decisions","e10_presence_policy_state_history","e10_presence_collection_policies","e10_break_sessions","e10_reporting_dataset_revisions"])await c.query(`delete from public.${t} where organization_id=$1`,[x.org]);
    await c.query("delete from public.e10_organizations where id=$1",[x.org]);await c.query("set session_replication_role=origin");await c.query("delete from auth.users where id=$1",[x.user]);
    const residue=Number((await c.query("select count(*) n from public.e10_organizations where id=$1",[x.org])).rows[0].n);await c.end();if(residue)throw Error("cleanup failed");
  }
  if(ok)console.log("TA-X7c provider normalization runner: PASS");
}
main().catch(e=>{console.error(e.stack);process.exit(1)});
