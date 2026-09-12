const { Client } = require("pg");
const { randomUUID } = require("crypto");

const db = process.env.E10_DB_URL || "postgresql://postgres:postgres@127.0.0.1:54322/postgres";
async function rejected(p, code) {
  try { await p; return false; } catch (e) { return e.code === code; }
}
async function main() {
  const c = new Client({ connectionString: db });
  await c.connect();
  const x = {org:randomUUID(),user:randomUUID(),role:randomUUID(),customer:randomUUID(),customer2:randomUUID(),session:randomUUID(),stream:randomUUID(),stream2:randomUUID(),segment:randomUUID(),segment2:randomUUID(),policy:randomUUID(),policyB:randomUUID(),coverage:randomUUID(),coverageB:randomUUID(),platform:randomUUID()};
  let ok=false;
  try {
    await c.query("insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at)values($1,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',$2,now(),now())",[x.user,`${x.user}@x.invalid`]);
    await c.query("insert into public.e10_organizations(id,slug,name)values($1,$2,'X7c runner')",[x.org,`x7cr-${x.org.slice(0,8)}`]);
    await c.query("insert into public.e10_platforms(id,slug,current_name)values($1,$2,'X7c provider B')",[x.platform,`x7c-provider-${x.platform.slice(0,8)}`]);
    await c.query("insert into public.e10_platform_keys(platform_id,key_kind,key_value)values($1,'provider','provider-b')",[x.platform]);
    await c.query("insert into public.e10_organization_roles(id,organization_id,key,name,is_system)values($1,$2,'x7c-reader','X7c reader',false)",[x.role,x.org]);
    await c.query("insert into public.e10_organization_role_permissions(organization_id,role_id,capability)values($1,$2,'act.view_customer_engagement')",[x.org,x.role]);
    await c.query("insert into public.e10_organization_memberships(organization_id,user_id,role_id,status)values($1,$2,$3,'active')",[x.org,x.user,x.role]);
    await c.query("insert into public.e10_customers(id,organization_id,display_name)values($1,$3,'X7c customer'),($2,$3,'X7c customer 2')",[x.customer,x.customer2,x.org]);
    await c.query("insert into public.e10_break_sessions(id,organization_id,streamer_uid,name,status,visibility,created_at,ended_at)values($1,$2,$3,'Runner','ended','private','2026-01-01','2026-01-31')",[x.session,x.org,x.user]);
    await c.query("insert into public.e10_presence_collection_policies(organization_id,policy_version,source_class,provider_key,enabled,notice_version,heartbeat_expiry_seconds,min_event_interval_ms,max_events_per_minute,retention_interval,coverage_label,effective_from)values($1,1,'authorized_platform','whatnot',true,'n1',300,0,60,interval '30 days','fixture','2026-01-01')",[x.org]);
    await c.query("insert into public.e10_provider_presence_normalization_policy_decisions(id,organization_id,provider_key,revision,action,effective_from,effective_through,heartbeat_expiry,maximum_late_arrival,collection_policy_version,reason,evidence,idempotency_key,request_fingerprint)values($1,$2,'whatnot',1,'enable','2026-01-01','2027-01-01',interval '5 minutes',interval '1 day',1,'fixture','{}','policy','policy-fp')",[x.policy,x.org]);
    await c.query("insert into public.e10_attendance_coverage_assertions(id,organization_id,coverage_key,revision,action,source_class,provider_key,covered_from,covered_to,coverage_status,policy_version,review_basis,evidence,idempotency_key,request_fingerprint)values($1,$2,$3,1,'assert','authorized_platform','whatnot','2026-01-01','2026-02-01','complete',1,'fixture','{}','coverage','coverage-fp')",[x.coverage,x.org,x.coverage]);
    const unknown=(await c.query("select disposition,extract(epoch from ended_at-started_at)::int seconds from e10.provider_normalization_coverage_parts($1,'whatnot',1,'2026-01-01','2026-02-01')",[x.org])).rows;
    if(JSON.stringify(unknown)!==JSON.stringify([{disposition:'coverage_unavailable',seconds:2678400}]))throw Error(`pre-history coverage did not fail closed ${JSON.stringify(unknown)}`);
    await c.query("insert into public.e10_presence_policy_state_history(organization_id,source_class,provider_key,policy_version,enabled,state_from)values($1,'authorized_platform','whatnot',1,true,'2026-01-01')",[x.org]);
    await c.query("insert into public.e10_presence_collection_policies(organization_id,policy_version,source_class,provider_key,enabled,notice_version,heartbeat_expiry_seconds,min_event_interval_ms,max_events_per_minute,retention_interval,coverage_label,effective_from)values($1,1,'authorized_platform','provider-b',true,'n1',300,0,60,interval '30 days','fixture','2026-01-01')",[x.org]);
    await c.query("insert into public.e10_provider_presence_normalization_policy_decisions(id,organization_id,provider_key,revision,action,effective_from,effective_through,heartbeat_expiry,maximum_late_arrival,collection_policy_version,reason,evidence,idempotency_key,request_fingerprint)values($1,$2,'provider-b',1,'enable','2026-01-01','2027-01-01',interval '5 minutes',interval '1 day',1,'fixture','{}','policy-b','policy-b-fp')",[x.policyB,x.org]);
    await c.query("insert into public.e10_attendance_coverage_assertions(id,organization_id,coverage_key,revision,action,source_class,provider_key,covered_from,covered_to,coverage_status,policy_version,review_basis,evidence,idempotency_key,request_fingerprint)values($1,$2,$1,1,'assert','authorized_platform','provider-b','2026-01-01','2026-02-01','complete',1,'fixture','{}','coverage-b','coverage-b-fp')",[x.coverageB,x.org]);
    await c.query("insert into public.e10_presence_policy_state_history(organization_id,source_class,provider_key,policy_version,enabled,state_from)values($1,'authorized_platform','provider-b',1,true,'2026-01-01')",[x.org]);
    const degraded=randomUUID();
    await c.query("insert into public.e10_attendance_coverage_assertions(id,organization_id,coverage_key,revision,action,source_class,provider_key,covered_from,covered_to,coverage_status,policy_version,review_basis,evidence,idempotency_key,request_fingerprint)values($1,$2,$1,1,'assert','authorized_platform','whatnot','2026-01-02 10:01Z','2026-01-02 10:02Z','partial',1,'fixture','{}','coverage-partial','coverage-partial-fp')",[degraded,x.org]);
    await c.query("insert into public.e10_presence_policy_state_history(organization_id,source_class,provider_key,policy_version,enabled,state_from)values($1,'authorized_platform','whatnot',1,false,'2026-01-02 10:02Z'),($1,'authorized_platform','whatnot',1,true,'2026-01-02 10:03Z')",[x.org]);
    await c.query("insert into public.e10_session_presence_streams(id,organization_id,session_id,source_class,provider_key,subject_key,connection_id,platform_attendee_key,original_customer_id,identity_status,collection_policy_version,notice_version,coverage_label,retention_expires_at)values($1,$2,$3,'authorized_platform','whatnot','attendee','connection','attendee',$4,'reviewed_attributed',1,'n1','fixture','2027-01-01')",[x.stream,x.org,x.session,x.customer]);
    await c.query("insert into public.e10_session_presence_segments(id,organization_id,stream_id,segment_sequence,heartbeat_expiry_seconds,retention_expires_at,collection_policy_version,notice_version,coverage_label)values($1,$2,$3,1,300,'2027-01-01',1,'n1','fixture')",[x.segment,x.org,x.stream]);
    await c.query("insert into public.e10_session_presence_streams(id,organization_id,session_id,source_class,provider_key,subject_key,connection_id,platform_attendee_key,original_customer_id,identity_status,collection_policy_version,notice_version,coverage_label,retention_expires_at)values($1,$2,$3,'authorized_platform','whatnot','attendee-2','connection-2','attendee-2',$4,'reviewed_attributed',1,'n1','fixture','2027-01-01')",[x.stream2,x.org,x.session,x.customer]);
    await c.query("insert into public.e10_session_presence_segments(id,organization_id,stream_id,segment_sequence,heartbeat_expiry_seconds,retention_expires_at,collection_policy_version,notice_version,coverage_label)values($1,$2,$3,1,300,'2027-01-01',1,'n1','fixture')",[x.segment2,x.org,x.stream2]);
    const events=[
      ['join','2026-01-02T10:00:00Z','2026-01-02T10:00:01Z'],
      ['heartbeat','2026-01-02T10:02:00Z','2026-01-02T10:02:01Z'],
      ['leave','2026-01-02T10:04:00Z','2026-01-02T10:04:01Z'],
      ['join',null,'2026-01-03T10:00:00Z'],
      ['heartbeat','2026-03-01T10:00:00Z','2026-01-04T10:00:00Z'],
      ['leave','2026-01-05T10:00:00Z','2026-01-07T10:00:00Z'],
    ];
    for(let i=0;i<events.length;i++) await c.query("insert into public.e10_session_presence_events(id,organization_id,stream_id,segment_id,event_sequence,event_kind,provider_occurred_at,server_received_at,provider_event_id,provider_key,evidence,request_fingerprint)values($1,$2,$3,$4,$5,$6,$7,$8,$9,'whatnot','{}',$10)",[randomUUID(),x.org,x.stream,x.segment,i+1,events[i][0],events[i][1],events[i][2],`event-${i}`,`fp-${i}`]);
    await c.query("insert into public.e10_session_presence_events(id,organization_id,stream_id,segment_id,event_sequence,event_kind,provider_occurred_at,server_received_at,provider_event_id,provider_key,evidence,request_fingerprint)values($1,$2,$3,$4,1,'join','2026-01-02 10:00Z','2026-01-02 10:00:02Z','overlap-join','whatnot','{}','overlap-1'),($5,$2,$3,$4,2,'leave','2026-01-02 10:01Z','2026-01-02 10:01:02Z','overlap-leave','whatnot','{}','overlap-2')",[randomUUID(),x.org,x.stream2,x.segment2,randomUUID()]);
    const call="select public.e10_service_run_provider_presence_normalization($1,'whatnot',$2,'2026-01-01T00:00:00Z','2026-02-01T00:00:00Z','2026-02-01T00:00:00Z',100,'run-1') result";
    const first=(await c.query(call,[x.org,x.policy])).rows[0].result;
    if(first.replay!==false||first.status!=="complete"||first.interval_count!==3||first.quarantine_count!==5)throw Error(`unexpected runner result ${JSON.stringify(first)}`);
    const interval=(await c.query("select sum(extract(epoch from ended_at-started_at))::int seconds,array_agg(expiry_reason order by started_at) reasons from public.e10_provider_presence_normalized_intervals where run_id=$1",[first.run_id])).rows[0];
    if(interval.seconds!==180||interval.reasons.some(x=>x!=="provider_leave"))throw Error("coverage/policy clipping wrong");
    const reasons=(await c.query("select array_agg(reason order by reason) reasons from public.e10_provider_presence_quarantine_rows where run_id=$1",[first.run_id])).rows[0].reasons;
    if(JSON.stringify(reasons)!==JSON.stringify(["collection_disabled","coverage_unavailable","future_provider_time","late_beyond_policy","missing_provider_time"]))throw Error(`quarantine wrong ${reasons}`);
    const replay=(await c.query(call,[x.org,x.policy])).rows[0].result;
    if(replay.replay!==true||replay.run_id!==first.run_id)throw Error("idempotent replay created another run");
    const cutoff2=(await c.query("select public.e10_service_run_provider_presence_normalization($1,'whatnot',$2,'2026-01-01','2026-02-01','2026-02-02',100,'run-cutoff-2') result",[x.org,x.policy])).rows[0].result;
    const providerB=(await c.query("select public.e10_service_run_provider_presence_normalization($1,'provider-b',$2,'2026-01-01','2026-02-01','2026-02-01',100,'run-provider-b') result",[x.org,x.policyB])).rows[0].result;
    const coexist=Number((await c.query("select ((e10.current_provider_normalization_run($1,'whatnot','2026-01-01','2026-02-01','2026-02-01')).id is not null)::int+((e10.current_provider_normalization_run($1,'whatnot','2026-01-01','2026-02-01','2026-02-02')).id is not null)::int+((e10.current_provider_normalization_run($1,'provider-b','2026-01-01','2026-02-01','2026-02-01')).id is not null)::int n",[x.org])).rows[0].n);
    if(cutoff2.status!=="complete"||providerB.status!=="complete"||coexist!==3)throw Error("provider/cutoff current runs did not coexist");
    if(!await rejected(c.query(call.replace("'run-1'","'run-2'").replace(",100,",",2,"),[x.org,x.policy]),"54000"))throw Error("hard input bound accepted");
    await c.query("set role authenticated");
    const denied=await rejected(c.query(call,[x.org,x.policy]),"42501");
    await c.query("reset role");
    if(!denied)throw Error("authenticated caller executed service runner");
    const run=(await c.query("select status,input_event_count,interval_count,quarantine_count,output_reporting_revision>input_reporting_revision advanced from public.e10_provider_presence_normalization_runs where id=$1",[first.run_id])).rows[0];
    if(run.status!=="complete"||Number(run.input_event_count)!==8||!run.advanced)throw Error("sealed run metadata wrong");
    const jwt=JSON.stringify({sub:x.user,role:'authenticated'});await c.query("select set_config('request.jwt.claims',$1,false)",[jwt]);await c.query("set role authenticated");
    const noCoverage=(await c.query("select * from public.e10_org_source_attendance_summary($1,'provider-none',$2,$3,'2026-01-01','2026-02-01','2026-02-01') order by source_class",[x.org,x.session,x.customer])).rows;await c.query('reset role');
    if(noCoverage.length!==2||noCoverage.some(v=>!v.availability.startsWith('unavailable_')||v.observed_seconds!==null))throw Error(`missing run/coverage manufactured zero ${JSON.stringify(noCoverage)}`);
    await c.query("insert into public.e10_presence_collection_policies(organization_id,policy_version,source_class,provider_key,enabled,notice_version,heartbeat_expiry_seconds,min_event_interval_ms,max_events_per_minute,retention_interval,coverage_label,effective_from,effective_through)values($1,1,'companion','companion',true,'cn1',300,0,60,interval '365 days','fixture','2026-01-01','2026-02-01')",[x.org]);
    const cc=randomUUID(),cp=randomUUID();
    await c.query("insert into public.e10_attendance_coverage_assertions(id,organization_id,coverage_key,revision,action,source_class,provider_key,covered_from,covered_to,coverage_status,policy_version,review_basis,evidence,idempotency_key,request_fingerprint)values($1,$3,$1,1,'assert','companion','companion','2026-01-01','2026-02-01','complete',1,'fixture','{}','comp-complete','cc'),($2,$3,$2,1,'assert','companion','companion','2026-01-02 10:00:30Z','2026-01-02 10:00:45Z','partial',1,'fixture','{}','comp-partial','cp')",[cc,cp,x.org]);
    const cs1=randomUUID(),cs2=randomUUID(),cg1=randomUUID(),cg2=randomUUID();
    for(const [st,sg,connection]of[[cs1,cg1,'comp-1'],[cs2,cg2,'comp-2']]){await c.query("insert into public.e10_session_presence_streams(id,organization_id,session_id,source_class,provider_key,subject_key,connection_id,observed_user_id,original_customer_id,identity_status,collection_policy_version,notice_version,coverage_label,retention_expires_at)values($1,$2,$3,'companion','companion',$4::uuid::text,$5,$4::uuid,$6,'reviewed_attributed',1,'cn1','fixture','2027-01-01')",[st,x.org,x.session,x.user,connection,x.customer]);await c.query("insert into public.e10_session_presence_segments(id,organization_id,stream_id,segment_sequence,heartbeat_expiry_seconds,retention_expires_at,collection_policy_version,notice_version,coverage_label)values($1,$2,$3,1,300,'2027-01-01',1,'cn1','fixture')",[sg,x.org,st]);await c.query("insert into public.e10_session_presence_events(id,organization_id,stream_id,segment_id,event_sequence,event_kind,server_received_at,evidence,request_fingerprint)values($1,$2,$3,$4,1,'join','2026-01-02 10:00Z','{}',$5),($6,$2,$3,$4,2,'leave','2026-01-02 10:01Z','{}',$7)",[randomUUID(),x.org,st,sg,connection+'-join',randomUUID(),connection+'-leave']);}
    await c.query("set role authenticated");
    const detail="select * from public.e10_org_provider_attendance_intervals($1,'whatnot',$2,$3,'2026-01-01','2026-02-01','2026-02-01',1,$4,$5,$6,$7)";
    const page1=(await c.query(detail,[x.org,x.session,x.customer,null,null,null,null])).rows[0];
    if(!page1||page1.availability!=="available"||page1.source_class!=="authorized_platform"||Number(page1.observed_seconds)!==60)throw Error(`provider detail wrong ${JSON.stringify(page1)}`);
    const page2=(await c.query(detail,[x.org,x.session,x.customer,page1.started_at,page1.interval_id,Number(page1.dataset_revision),page1.query_fingerprint])).rows[0];
    if(!page2||page2.interval_id===page1.interval_id)throw Error("provider detail cursor failed");
    if(!await rejected(c.query(detail,[x.org,x.session,x.customer,page1.started_at,page1.interval_id,Number(page1.dataset_revision),page1.query_fingerprint+'x']),"22023"))throw Error("provider cursor rebind accepted");
    const targetFp=(await c.query("select md5(jsonb_build_object('metric','provider-attendance-intervals-v1','org',$1::uuid,'provider','whatnot','session',$2::uuid,'customer',$3::uuid,'from','2026-01-01'::timestamptz,'to','2026-02-01'::timestamptz,'cutoff','2026-02-01'::timestamptz,'revision',$4::bigint,'run',$5::uuid)::text) fp",[x.org,x.session,x.customer2,page1.dataset_revision,page1.run_id])).rows[0].fp;
    if(!await rejected(c.query(detail,[x.org,x.session,x.customer2,page1.started_at,page1.interval_id,Number(page1.dataset_revision),targetFp]),"22023"))throw Error("interval cursor crossed customer cohort");
    const quarantine=(await c.query("select * from public.e10_org_provider_attendance_quarantine($1,'whatnot','2026-01-01','2026-02-01','2026-02-01',null,2,null,null,null)",[x.org])).rows;
    if(quarantine.length!==2||quarantine.some(r=>r.availability!=="available"||r.evidence_event_count<1))throw Error("quarantine read wrong");
    const summary=(await c.query("select * from public.e10_org_source_attendance_summary($1,'whatnot',$2,$3,'2026-01-01','2026-02-01','2026-02-01') order by source_class",[x.org,x.session,x.customer])).rows;
    if(summary.length!==2||summary[0].source_class!=="authorized_platform"||summary[1].source_class!=="companion"||Number(summary[0].observed_seconds)!==120||summary[0].availability!=="available_partial_coverage"||summary[1].availability!=="available_partial_coverage"||Number(summary[1].observed_seconds)!==45)throw Error(`source separation/overlap wrong ${JSON.stringify(summary)}`);
    if(!await rejected(c.query("select * from public.e10_org_source_attendance_summary($1,'whatnot',$2,$3,'2026-01-01','2026-02-01','2026-02-01')",[x.org,randomUUID(),x.customer]),"22023"))throw Error("foreign summary session accepted");
    const qa=(await c.query("select * from public.e10_org_provider_attendance_quarantine($1,'whatnot','2026-01-01','2026-02-01','2026-02-01','missing_provider_time',2,null,null,null)",[x.org])).rows[0];
    const qb=(await c.query("select * from public.e10_org_provider_attendance_quarantine($1,'whatnot','2026-01-01','2026-02-01','2026-02-01','future_provider_time',2,null,null,null)",[x.org])).rows[0];
    if(!await rejected(c.query("select * from public.e10_org_provider_attendance_quarantine($1,'whatnot','2026-01-01','2026-02-01','2026-02-01','future_provider_time',2,$2,$3,$4)",[x.org,qa.quarantine_id,Number(qb.dataset_revision),qb.query_fingerprint]),"22023"))throw Error("quarantine cursor crossed reason cohort");
    await c.query("reset role");await c.query("delete from public.e10_organization_role_permissions where organization_id=$1 and role_id=$2 and capability='act.view_customer_engagement'",[x.org,x.role]);await c.query("set role authenticated");
    if(!await rejected(c.query(detail,[x.org,x.session,x.customer,null,null,null,null]),"42501")||!await rejected(c.query("select * from public.e10_org_provider_attendance_quarantine($1,'whatnot','2026-01-01','2026-02-01','2026-02-01',null,2,null,null,null)",[x.org]),"42501")||!await rejected(c.query("select * from public.e10_org_source_attendance_summary($1,'whatnot',$2,$3,'2026-01-01','2026-02-01','2026-02-01')",[x.org,x.session,x.customer]),"42501"))throw Error("missing-cap provider RPC allowed");
    await c.query("reset role");await c.query("insert into public.e10_organization_role_permissions(organization_id,role_id,capability)values($1,$2,'act.view_customer_engagement')",[x.org,x.role]);await c.query("set role anon");
    if(!await rejected(c.query(detail,[x.org,x.session,x.customer,null,null,null,null]),"42501")||!await rejected(c.query("select * from public.e10_org_provider_attendance_quarantine($1,'whatnot','2026-01-01','2026-02-01','2026-02-01',null,2,null,null,null)",[x.org]),"42501")||!await rejected(c.query("select * from public.e10_org_source_attendance_summary($1,'whatnot',$2,$3,'2026-01-01','2026-02-01','2026-02-01')",[x.org,x.session,x.customer]),"42501"))throw Error("anon provider RPC allowed");
    await c.query("reset role");
    const stale=randomUUID();await c.query("insert into public.e10_session_presence_attribution_decisions(id,organization_id,stream_id,revision,action,customer_id,reason,evidence,idempotency_key,request_fingerprint)values($1,$2,$3,1,'attribute',$4,'stale fixture','{}','stale-attribution','stale-fp')",[stale,x.org,x.stream,x.customer2]);
    await c.query("set role authenticated");
    const unavailable=(await c.query(detail,[x.org,x.session,x.customer,null,null,null,null])).rows[0];await c.query("reset role");
    if(unavailable.availability!=="unavailable_rebuild_required"||unavailable.observed_seconds!==null)throw Error("stale run manufactured attendance");
    const unaffected=(await c.query("select (e10.current_provider_normalization_run($1,'provider-b','2026-01-01','2026-02-01','2026-02-01')).id id",[x.org])).rows[0].id;
    if(unaffected!==providerB.run_id)throw Error("provider A attribution invalidated provider B");
    const rebuilt=(await c.query(call.replace("'run-1'","'run-after-attribution'"),[x.org,x.policy])).rows[0].result;
    if(rebuilt.status!=="complete"||rebuilt.run_id===first.run_id)throw Error("attribution rebuild failed");
    const detailAll=detail.replace(',1,$4,$5,$6,$7)',',200,$4,$5,$6,$7)');await c.query("set role authenticated");const oldCustomer=(await c.query(detailAll,[x.org,x.session,x.customer,null,null,null,null])).rows;const freshRows=(await c.query(detailAll,[x.org,x.session,x.customer2,null,null,null,null])).rows;const fresh=freshRows[0];await c.query("reset role");
    if(oldCustomer.length!==1||Number(oldCustomer[0].observed_seconds)!==60||freshRows.length!==2||freshRows.some(v=>v.availability!=="available"||v.run_id!==rebuilt.run_id)||freshRows.reduce((n,v)=>n+Number(v.observed_seconds),0)!==120)throw Error(`rebuilt attribution did not move corrected stream customer ${JSON.stringify({oldCustomer,freshRows,rebuilt})}`);
    ok=true;
  } finally {
    await c.query("reset role").catch(()=>{});await c.query("set session_replication_role=replica");
    for(const t of ["e10_provider_presence_normalized_intervals","e10_provider_presence_quarantine_rows","e10_provider_presence_normalization_runs","e10_attendance_coverage_assertions","e10_session_presence_attribution_decisions","e10_session_presence_events","e10_session_presence_segments","e10_session_presence_streams","e10_provider_presence_normalization_policy_decisions","e10_presence_policy_state_history","e10_presence_collection_policies","e10_break_sessions","e10_customers","e10_reporting_dataset_revisions","e10_organization_memberships","e10_organization_role_permissions","e10_organization_roles"])await c.query(`delete from public.${t} where organization_id=$1`,[x.org]);
    await c.query("delete from public.e10_organizations where id=$1",[x.org]);await c.query("delete from public.e10_platform_keys where platform_id=$1",[x.platform]);await c.query("delete from public.e10_platforms where id=$1",[x.platform]);await c.query("set session_replication_role=origin");await c.query("delete from auth.users where id=$1",[x.user]);
    const residue=Number((await c.query("select count(*) n from public.e10_organizations where id=$1",[x.org])).rows[0].n);await c.end();if(residue)throw Error("cleanup failed");
  }
  if(ok)console.log("TA-X7c provider normalization runner: PASS");
}
main().catch(e=>{console.error(e.stack);process.exit(1)});
