const {Client}=require('pg');const {randomUUID}=require('crypto');
const db=process.env.E10_DB_URL||'postgresql://postgres:postgres@127.0.0.1:54322/postgres';
const x={run:randomUUID(),org:randomUUID(),org2:randomUUID(),user:randomUUID(),outsider:randomUUID(),role:randomUUID(),role2:randomUUID(),customer:randomUUID(),customer2:randomUUID(),bigSession:randomUUID()};
const sessions=Array.from({length:4},()=>randomUUID());
const report='select * from public.e10_org_weekly_attendance($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13)';
const detail='select * from public.e10_org_attendance_contributions($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)';
const segments='select * from public.e10_org_attendance_contribution_segments($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)';
async function denied(p,code,msg){try{await p;return false}catch(e){return e.code===code&&(!msg||e.message===msg)}}
async function addInterval(s,{session,customer,start,end,connection}){
  const stream=randomUUID(),segment=randomUUID();
  await s.query("insert into public.e10_session_presence_streams(id,organization_id,session_id,source_class,provider_key,subject_key,connection_id,observed_user_id,original_customer_id,identity_status,collection_policy_version,notice_version,coverage_label,retention_expires_at) values($1,$2,$3,'companion','companion',$4,$5,$6,$7,'reviewed_attributed',1,'notice-v1','fixture',$8)",[stream,x.org,session,x.user,connection,x.user,customer,new Date('2026-02-01T00:00:00Z')]);
  await s.query("insert into public.e10_session_presence_segments(id,organization_id,stream_id,segment_sequence,heartbeat_expiry_seconds,retention_expires_at,collection_policy_version,notice_version,coverage_label) values($1,$2,$3,1,300,'2026-02-01T00:00:00Z',1,'notice-v1','fixture')",[segment,x.org,stream]);
  const midpoint=new Date((new Date(start).getTime()+new Date(end).getTime())/2);
  await s.query("insert into public.e10_session_presence_events(organization_id,stream_id,segment_id,event_sequence,event_kind,server_received_at,evidence,request_fingerprint) values($1,$2,$3,1,'join',$4,'{}',$7),($1,$2,$3,2,'heartbeat',$6,'{}',$7),($1,$2,$3,3,'leave',$5,'{}',$7)",[x.org,stream,segment,start,end,midpoint,x.run+'-'+connection]);
  return {stream,segment};
}
async function main(){const s=new Client({connectionString:db}),a=new Client({connectionString:db}),b=new Client({connectionString:db}),o=new Client({connectionString:db}),i=new Client({connectionString:db});await Promise.all([s.connect(),a.connect(),b.connect(),o.connect(),i.connect()]);let success=false,pendingWriter=null,pendingReader=null,spid=null,apid=null;
 try{
  await s.query(require('fs').readFileSync('tests/ta_x8_business_state_helper.sql','utf8'));
  for(const c of[s,a,b,o,i])await c.query("set statement_timeout='8s'");
  for(const [id,label]of[[x.user,'member'],[x.outsider,'outsider']])await s.query("insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at) values($1,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',$2,now(),now())",[id,`${x.run}-${label}@x.invalid`]);
  await s.query("insert into public.e10_organizations(id,slug,name) values($1,$2,'X7a fixture')",[x.org,'x7a-'+x.run]);
  await s.query("insert into public.e10_organizations(id,slug,name) values($1,$2,'X7a foreign fixture')",[x.org2,'x7f-'+x.run]);
  await s.query("insert into public.e10_organization_roles(id,organization_id,key,name,is_system) values($1,$2,$3,'X7a',false)",[x.role,x.org,x.run]);
  await s.query("insert into public.e10_organization_roles(id,organization_id,key,name,is_system) values($1,$2,$3,'X7a foreign',false)",[x.role2,x.org2,x.run]);
  await s.query("insert into public.e10_organization_role_permissions values($1,$2,'act.view_customer_engagement',true),($1,$2,'act.manage_attendance_coverage',true),($1,$2,'act.manage_customers',true),($1,$2,'act.merge_customers',true)",[x.org,x.role]);
  await s.query("insert into public.e10_organization_memberships(organization_id,user_id,role_id,status) values($1,$2,$3,'active')",[x.org,x.user,x.role]);
  await s.query("insert into public.e10_organization_memberships(organization_id,user_id,role_id,status) values($1,$2,$3,'active')",[x.org2,x.outsider,x.role2]);
  await s.query("insert into public.e10_customers(id,organization_id,display_name) values($1,$3,'Customer one'),($2,$3,'Customer two')",[x.customer,x.customer2,x.org]);
  for(let i=0;i<sessions.length;i++)await s.query("insert into public.e10_break_sessions(id,organization_id,streamer_uid,name,status,ended_at,visibility) values($1,$2,$3,$4,'ended',$5,'private')",[sessions[i],x.org,x.user,'X7a '+i,new Date(`2026-01-${String(6+i).padStart(2,'0')}T11:00:00Z`)]);
  await s.query("insert into public.e10_presence_collection_policies(organization_id,policy_version,source_class,provider_key,enabled,notice_version,heartbeat_expiry_seconds,min_event_interval_ms,max_events_per_minute,retention_interval,coverage_label,effective_from,effective_through) values($1,1,'companion','companion',true,'notice-v1',300,0,600,interval '365 days','fixture','2026-01-01T00:00:00Z','2026-02-01T00:00:00Z')",[x.org]);
  for(const [c,id]of[[a,x.user],[b,x.user],[o,x.outsider]]){await c.query('select set_config($1,$2,false)',['request.jwt.claims',JSON.stringify({sub:id,role:'authenticated'})]);await c.query('set role authenticated');}

  const review='select public.e10_org_review_attendance_coverage($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13) r';
  const reviewArgs=[x.org,null,0,'assert','companion','companion','2026-01-05T00:00:00Z','2026-01-19T00:00:00Z','complete',1,'reviewed fixture',{},x.run+'-coverage'];
  const concurrent=await Promise.all([a.query(review,reviewArgs),b.query(review,reviewArgs)]);
  const first=concurrent[0].rows[0].r,replay=concurrent[1].rows[0].r;
  if(first.replay===replay.replay||replay.assertion_id!==first.assertion_id||replay.coverage_key!==first.coverage_key)throw Error('coverage create replay failed');
  console.log('[proof] concurrent coverage create serialized to one assertion');
  if(!await denied(a.query(review,[x.org,null,0,'assert','companion','companion','2025-12-01','2025-12-02','complete',1,'unsupported',{},x.run+'-bad-complete']),'22023','attendance_complete_coverage_not_supported'))throw Error('unsupported complete coverage accepted');
  if(!await denied(a.query(review,[x.org,first.coverage_key,0,'assert','companion','companion','2026-01-05','2026-01-19','complete',1,'stale',{},x.run+'-stale-cas']),'40001','attendance_coverage_revision_conflict'))throw Error('coverage stale CAS accepted');
  if(!await denied(a.query(review,[x.org,null,0,'assert','companion','companion','2026-01-05','2026-01-19','partial',1,'mismatch',{},x.run+'-coverage']),'22023','idempotency_key_mismatch'))throw Error('coverage idempotency mismatch accepted');
  await s.query("delete from public.e10_organization_role_permissions where organization_id=$1 and role_id=$2 and capability='act.manage_attendance_coverage'",[x.org,x.role]);
  if(!await denied(a.query(review,[x.org,null,0,'assert','companion','companion','2026-01-05','2026-01-06','partial',1,'denied',{},x.run+'-denied-review']),'42501','attendance_coverage_review_denied'))throw Error('missing coverage capability write allowed');
  await s.query("insert into public.e10_organization_role_permissions values($1,$2,'act.manage_attendance_coverage',true)",[x.org,x.role]);
  await s.query("update public.e10_presence_collection_policies set enabled=false where organization_id=$1 and source_class='companion' and provider_key='companion'",[x.org]);
  const historical=(await a.query(review,reviewArgs)).rows[0].r;if(!historical.replay||historical.assertion_id!==first.assertion_id)throw Error('historical replay depended on current policy state');
  let disabledRows=(await a.query(report,[x.org,'2026-01-05','2026-01-19','2026-01-20','UTC',1,x.customer,'companion','companion',54,null,null,null])).rows;
  if(disabledRows.some(r=>r.coverage_status!=='complete'))throw Error('current disable rewrote prior coverage');
  await s.query("update public.e10_presence_collection_policies set enabled=true where organization_id=$1 and source_class='companion' and provider_key='companion'",[x.org]);

  const baseInterval=await addInterval(s,{session:sessions[0],customer:x.customer,start:'2026-01-06T10:00:00Z',end:'2026-01-06T10:10:00Z',connection:'a'});
  await addInterval(s,{session:sessions[0],customer:x.customer,start:'2026-01-06T10:00:00Z',end:'2026-01-06T10:10:00Z',connection:'b'});
  await addInterval(s,{session:sessions[0],customer:x.customer,start:'2026-01-12T00:05:00Z',end:'2026-01-12T00:15:00Z',connection:'cross-week'});
  await s.query("update public.e10_break_sessions set ended_at='2026-01-12T01:00:00Z' where id=$1",[sessions[0]]);
  for(let i=1;i<4;i++)await addInterval(s,{session:sessions[i],customer:x.customer,start:`2026-01-0${6+i}T10:00:00Z`,end:`2026-01-0${6+i}T10:10:00Z`,connection:'s'+i});
  const cutoff='2026-01-20T00:00:00Z',from='2026-01-05T00:00:00Z',to='2026-01-19T00:00:00Z';
  let rows=(await a.query(report,[x.org,from,to,cutoff,'UTC',1,x.customer,'companion','companion',54,null,null,null])).rows;
  if(rows.length!==2||Number(rows[0].distinct_attended_sessions)!==4||Number(rows[0].observed_attendance_seconds)!==2400||Number(rows[0].attended_customer_sessions)!==4||Number(rows[0].average_observed_seconds_per_customer_session)!==600||Number(rows[1].distinct_attended_sessions)!==0||Number(rows[1].observed_attendance_seconds)!==600||Number(rows[1].attended_customer_sessions)!==1||Number(rows[1].average_observed_seconds_per_customer_session)!==600||Number(rows[0].complete_window_average_sessions_per_week)!==2||rows.some(r=>r.coverage_status!=='complete'))throw Error('weekly union/zero/average failed '+JSON.stringify(rows));
  const x8ctx=(await a.query("select public.e10_org_create_query_context($1,'workspace',600,$2) r",[x.org,'x8-x7a-'+x.run])).rows[0].r.context_id;
  const x8state=(await s.query('select pg_temp.x8_business_state() s')).rows[0].s;const x8weekly=(await a.query('select public.e10_org_typed_query($1,$2,$3,$4) j',[x.org,x8ctx,'attendance.weekly',{from,to,observation_cutoff:cutoff,timezone:'UTC',week_start:1,customer:x.customer,source_class:'companion',provider_key:'companion',limit:54}])).rows[0].j;if(JSON.stringify((await s.query('select pg_temp.x8_business_state() s')).rows[0].s)!==JSON.stringify(x8state))throw Error('X8 attendance weekly changed business data');
  await s.query("select pg_temp.x8_assert_envelope($1,'attendance.weekly','customer_local_calendar_week')",[x8weekly]);
  if(x8weekly.operation!=='attendance.weekly'||x8weekly.grain!=='customer_local_calendar_week'||x8weekly.result.items.length!==2)throw Error('X8 attendance weekly dispatch failed '+JSON.stringify(x8weekly));
  if(rows.some(r=>r.session_count_grain!=='distinct_session'||r.duration_grain!=='customer_session_attendee_seconds'))throw Error('metric grain missing');
  const rev=Number(rows[0].dataset_revision),fp=rows[0].query_fingerprint;
  const d1=(await a.query(detail,[x.org,from,to,cutoff,x.customer,'companion','companion',1,null,null,null,null])).rows[0];
  if(!d1||d1.grain!=='effective_customer_session'||Number(d1.observed_seconds)<=0||!d1.segment_ids.length||!d1.stream_ids.length)throw Error('attendance detail lineage missing '+JSON.stringify(d1));
  const d2=(await a.query(detail,[x.org,from,to,cutoff,x.customer,'companion','companion',1,d1.session_id,d1.effective_customer_id,Number(d1.dataset_revision),d1.query_fingerprint])).rows[0];
  if(!d2||d2.session_id===d1.session_id)throw Error('attendance detail cursor failed');
  if(!await denied(a.query(detail,[x.org,from,to,cutoff,null,'companion','companion',1,d1.session_id,d1.effective_customer_id,Number(d1.dataset_revision),d1.query_fingerprint]),'22023','attendance_detail_cursor_query_mismatch'))throw Error('detail cursor query rebinding allowed');
  const page=(await a.query(report,[x.org,from,to,cutoff,'UTC',1,x.customer,'companion','companion',1,rows[0].week_start_date,rev,fp])).rows;
  if(page.length!==1||page[0].week_start_date.toISOString().slice(0,10)!=='2026-01-12')throw Error('weekly cursor failed');
  if(!await denied(a.query(report,[x.org,from,to,cutoff,'America/Toronto',1,x.customer,'companion','companion',1,rows[0].week_start_date,rev,fp]),'22023','attendance_report_cursor_query_mismatch'))throw Error('cursor query rebinding allowed');
  const clipped=(await a.query(report,[x.org,'2026-01-12','2026-01-19',cutoff,'UTC',1,x.customer,'companion','companion',54,null,null,null])).rows[0];
  if(Number(clipped.distinct_attended_sessions)!==0||Number(clipped.observed_attendance_seconds)!==600)throw Error('query window moved cross-week session count');
  const dst=(await a.query(report,[x.org,'2026-03-02T05:00:00Z','2026-03-16T04:00:00Z','2026-03-20T00:00:00Z','America/Toronto',1,x.customer,'companion','companion',54,null,null,null])).rows;
  if(dst.length!==2||(new Date(dst[0].week_ended_at)-new Date(dst[0].week_started_at))/3600000!==167||(new Date(dst[1].week_ended_at)-new Date(dst[1].week_started_at))/3600000!==168)throw Error('DST local-week boundaries incorrect '+JSON.stringify(dst));
  if(!await denied(a.query(report,[x.org,from,to,cutoff,'UTC',1,x.customer,null,'companion',54,null,null,null]),'22023','attendance_report_bounds_invalid'))throw Error('NULL source accepted');
  if(!await denied(o.query(report,[x.org,from,to,cutoff,'UTC',1,null,'companion','companion',54,null,null,null]),'42501','attendance_report_denied'))throw Error('hostile member read allowed');
  await s.query("delete from public.e10_organization_role_permissions where organization_id=$1 and role_id=$2 and capability='act.view_customer_engagement'",[x.org,x.role]);
  if(!await denied(a.query(report,[x.org,from,to,cutoff,'UTC',1,null,'companion','companion',54,null,null,null]),'42501','attendance_report_denied')||!await denied(a.query(detail,[x.org,from,to,cutoff,null,'companion','companion',10,null,null,null,null]),'42501','attendance_detail_denied'))throw Error('missing capability read allowed');
  await s.query("insert into public.e10_organization_role_permissions values($1,$2,'act.view_customer_engagement',true)",[x.org,x.role]);
  const beforeAttribution=Number((await s.query('select revision from public.e10_reporting_dataset_revisions where organization_id=$1',[x.org])).rows[0].revision);
  await a.query("select public.e10_org_decide_presence_attribution($1,$2,0,'attribute',$3,'X7a revision proof','{}',$4)",[x.org,baseInterval.stream,x.customer,x.run+'-attribution']);
  if(!await denied(a.query(report,[x.org,from,to,cutoff,'UTC',1,x.customer,'companion','companion',54,null,beforeAttribution,null]),'40001','attendance_dataset_revision_stale'))throw Error('attribution did not invalidate report revision');

  await a.query('begin');
  const locked=(await a.query(report,[x.org,from,to,cutoff,'UTC',1,x.customer,'companion','companion',54,null,null,null])).rows[0];
  spid=(await s.query('select pg_backend_pid() pid')).rows[0].pid;
  pendingWriter=s.query("update public.e10_break_sessions set ended_at=ended_at+interval '1 second' where id=$1",[sessions[0]]);
  let waited=false;for(let n=0;n<100;n++){const q=(await i.query("select wait_event_type from pg_stat_activity where pid=$1",[spid])).rows[0];if(q&&q.wait_event_type==='Lock'){waited=true;break}await new Promise(r=>setTimeout(r,20));}
  if(!waited){await a.query('rollback');throw Error('reporting revision writer did not wait on snapshot lock')}
  await a.query('commit');await pendingWriter;pendingWriter=null;console.log('[proof] report snapshot held dataset revision against concurrent writer');
  if(!await denied(a.query(report,[x.org,from,to,cutoff,'UTC',1,x.customer,'companion','companion',54,null,Number(locked.dataset_revision),null]),'40001','attendance_dataset_revision_stale'))throw Error('post-snapshot stale revision accepted');
  const beforeWriter=Number((await s.query('select revision from public.e10_reporting_dataset_revisions where organization_id=$1',[x.org])).rows[0].revision);
  apid=(await a.query('select pg_backend_pid() pid')).rows[0].pid;
  await s.query('begin');await s.query("update public.e10_break_sessions set ended_at=ended_at+interval '1 second' where id=$1",[sessions[0]]);
  pendingReader=a.query(report,[x.org,from,to,cutoff,'UTC',1,x.customer,'companion','companion',54,null,beforeWriter,null]);
  waited=false;for(let n=0;n<100;n++){const q=(await i.query("select wait_event_type from pg_stat_activity where pid=$1",[apid])).rows[0];if(q&&q.wait_event_type==='Lock'){waited=true;break}await new Promise(r=>setTimeout(r,20));}
  if(!waited){await s.query('rollback');throw Error('report reader did not wait behind revision writer')}
  await s.query('commit');if(!await denied(pendingReader,'40001','attendance_dataset_revision_stale'))throw Error('reader behind writer returned mixed revision');pendingReader=null;
  console.log('[proof] reader waited behind writer and rejected stale revision');

  const partial=(await a.query(review,[x.org,null,0,'assert','companion','companion','2026-01-12','2026-01-19','partial',1,'known partial overlap',{},x.run+'-partial'])).rows[0].r;
  rows=(await a.query(report,[x.org,from,to,cutoff,'UTC',1,x.customer,'companion','companion',54,null,null,null])).rows;
  if(rows[1].coverage_status==='complete'||Number(rows[1].unknown_coverage_seconds)<=0||rows[0].complete_window_average_sessions_per_week!==null)throw Error('overlapping partial assertion was erased');
  await a.query(review,[x.org,partial.coverage_key,1,'revoke','companion','companion','2026-01-12','2026-01-19',null,1,'reviewed partial revoke',{},x.run+'-partial-revoke']);

  await addInterval(s,{session:sessions[0],customer:x.customer2,start:'2026-01-12T00:20:00Z',end:'2026-01-12T00:30:00Z',connection:'other-customer'});
  rows=(await a.query(report,[x.org,from,to,cutoff,'UTC',1,null,'companion','companion',54,null,null,null])).rows;
  if(Number(rows[0].distinct_attended_sessions)!==4||Number(rows[1].distinct_attended_sessions)!==0||Number(rows[0].observed_attendance_seconds)!==2400||Number(rows[1].observed_attendance_seconds)!==1200)throw Error('session/customer grain conflated '+JSON.stringify(rows));
  if(!await denied(a.query(report,[x.org,from,to,cutoff,'UTC',1,null,'companion','companion',54,null,rev,null]),'40001','attendance_dataset_revision_stale'))throw Error('stale revision accepted');
  const customerRevisions=(await s.query('select id,revision from public.e10_customers where organization_id=$1 and id=any($2) order by id',[x.org,[x.customer,x.customer2]])).rows;
  const source=customerRevisions.find(r=>r.id===x.customer2),target=customerRevisions.find(r=>r.id===x.customer);
  const beforeMerge=Number((await s.query('select revision from public.e10_reporting_dataset_revisions where organization_id=$1',[x.org])).rows[0].revision);
  await a.query("select public.e10_org_decide_customer_resolution($1,$2,$3,$4,$5,0,'merge','operator_review','{}'::uuid[],'X7a merge revision','{}',$6)",[x.org,x.customer2,x.customer,source.revision,target.revision,x.run+'-merge']);
  if(!await denied(a.query(report,[x.org,from,to,cutoff,'UTC',1,null,'companion','companion',54,null,beforeMerge,null]),'40001','attendance_dataset_revision_stale'))throw Error('customer merge did not invalidate report revision');

  await s.query("insert into public.e10_break_sessions(id,organization_id,streamer_uid,name,status,ended_at,visibility) values($1,$2,$3,'X7a large contribution','ended','2026-01-14','private')",[x.bigSession,x.org,x.user]);
  for(let n=0;n<201;n++)await addInterval(s,{session:x.bigSession,customer:x.customer,start:'2026-01-13T10:00:00Z',end:'2026-01-13T10:10:00Z',connection:'large-'+n});
  const summaries=(await a.query(detail,[x.org,from,to,cutoff,x.customer,'companion','companion',100,null,null,null,null])).rows;
  const large=summaries.find(r=>r.session_id===x.bigSession);
  if(!large||Number(large.observed_seconds)!==600||Number(large.contributor_count)!==201||!large.contributors_truncated||large.stream_ids.length!==200||large.segment_ids.length!==200||large.collection_policy_versions.length>200||large.notice_versions.length>200)throw Error('large contribution summary bound failed '+JSON.stringify(large));
  const seg1=(await a.query(segments,[x.org,from,to,cutoff,x.customer,x.bigSession,'companion','companion',200,null,null,null])).rows;
  const segLast=seg1[seg1.length-1];
  const seg2=(await a.query(segments,[x.org,from,to,cutoff,x.customer,x.bigSession,'companion','companion',200,segLast.segment_id,Number(segLast.dataset_revision),segLast.query_fingerprint])).rows;
  if(seg1.length!==200||seg2.length!==1||new Set([...seg1,...seg2].map(r=>r.segment_id)).size!==201||[...seg1,...seg2].some(r=>Number(r.session_union_observed_seconds)!==600||Number(r.contributor_count)!==201))throw Error('complete contributor pagination/union proof failed');
  if(!await denied(a.query(segments,[x.org,from,to,cutoff,x.customer,sessions[0],'companion','companion',200,segLast.segment_id,Number(segLast.dataset_revision),segLast.query_fingerprint]),'22023','attendance_segment_detail_cursor_query_mismatch'))throw Error('segment cursor query rebinding allowed');

  await s.query("insert into public.e10_presence_policy_state_history(organization_id,source_class,provider_key,policy_version,enabled,state_from) values($1,'companion','companion',1,false,'2026-01-10'),($1,'companion','companion',1,true,'2026-01-11')",[x.org]);
  rows=(await a.query(report,[x.org,from,to,cutoff,'UTC',1,x.customer,'companion','companion',54,null,null,null])).rows;
  if(rows.some(r=>r.coverage_status==='complete')||rows[0].complete_window_average_sessions_per_week!==null)throw Error('known disabled interval erased by re-enable');

  const revokeArgs=[x.org,first.coverage_key,1,'revoke','companion','companion','2026-01-05T00:00:00Z','2026-01-19T00:00:00Z',null,1,'reviewed revoke',{},x.run+'-revoke'];
  const revoked=(await a.query(review,revokeArgs)).rows[0].r,revokeReplay=(await a.query(review,revokeArgs)).rows[0].r;
  if(revoked.replay||!revokeReplay.replay||revoked.assertion_id!==revokeReplay.assertion_id)throw Error('coverage revoke replay failed');
  rows=(await a.query(report,[x.org,from,to,cutoff,'UTC',1,x.customer,'companion','companion',54,null,null,null])).rows;
  if(rows.some(r=>r.coverage_status==='complete'||Number(r.unknown_coverage_seconds)<=0||r.complete_window_average_sessions_per_week!==null))throw Error('unknown coverage became zero/complete');
  const acl=(await s.query("select has_table_privilege('authenticated','public.e10_attendance_coverage_assertions','select') auth_table,has_table_privilege('anon','public.e10_reporting_dataset_revisions','select') anon_revision,has_function_privilege('anon','public.e10_org_weekly_attendance(uuid,timestamptz,timestamptz,timestamptz,text,integer,uuid,text,text,integer,date,bigint,text)','execute') anon_report,has_function_privilege('anon','public.e10_org_attendance_contributions(uuid,timestamptz,timestamptz,timestamptz,uuid,text,text,integer,uuid,uuid,bigint,text)','execute') anon_detail,has_function_privilege('anon','public.e10_org_attendance_contribution_segments(uuid,timestamptz,timestamptz,timestamptz,uuid,uuid,text,text,integer,uuid,bigint,text)','execute') anon_segments,has_function_privilege('authenticated','e10.attendance_contribution_rows(uuid,timestamptz,timestamptz,timestamptz,uuid,text,text)','execute') auth_helper")).rows[0];
  if(acl.auth_table||acl.anon_revision||acl.anon_report||acl.anon_detail||acl.anon_segments||acl.auth_helper)throw Error('X7a ACL failed '+JSON.stringify(acl));
  success=true;
 }finally{
  if(pendingWriter&&spid)await i.query('select pg_cancel_backend($1)',[spid]).catch(()=>{});
  if(pendingReader&&apid)await i.query('select pg_cancel_backend($1)',[apid]).catch(()=>{});
  await Promise.allSettled([pendingWriter,pendingReader].filter(Boolean));
  await Promise.allSettled([a.query('rollback'),b.query('rollback'),o.query('rollback'),s.query('rollback')]);
  for(const c of[a,b,o,s,i])await c.query('reset role').catch(()=>{});await s.query('set session_replication_role=replica');
  for(const q of['delete from public.e10_attendance_coverage_assertions where organization_id=$1','delete from public.e10_reporting_dataset_revisions where organization_id=$1','delete from public.e10_session_presence_attribution_decisions where organization_id=$1','delete from public.e10_session_presence_events where organization_id=$1','delete from public.e10_session_presence_segments where organization_id=$1','delete from public.e10_session_presence_streams where organization_id=$1','delete from public.e10_presence_policy_state_history where organization_id=$1','delete from public.e10_presence_collection_policies where organization_id=$1','delete from public.e10_customer_resolution_decisions where organization_id=$1','delete from public.e10_customer_mutation_receipts where organization_id=$1','delete from public.e10_break_sessions where organization_id=$1','delete from public.e10_customers where organization_id=$1','delete from public.e10_organization_memberships where organization_id=$1','delete from public.e10_organization_role_permissions where organization_id=$1','delete from public.e10_organization_roles where organization_id=$1','delete from public.e10_organizations where id=$1']){await s.query(q,[x.org]);await s.query(q,[x.org2]);}
  await s.query('set session_replication_role=origin');await s.query('delete from auth.users where id in($1,$2)',[x.user,x.outsider]);
  const residue=Number((await s.query('select (select count(*) from public.e10_organizations where id in($1,$4))+(select count(*) from public.e10_attendance_coverage_assertions where organization_id in($1,$4))+(select count(*) from public.e10_reporting_dataset_revisions where organization_id in($1,$4))+(select count(*) from public.e10_presence_policy_state_history where organization_id in($1,$4))+(select count(*) from public.e10_presence_collection_policies where organization_id in($1,$4))+(select count(*) from public.e10_session_presence_streams where organization_id in($1,$4))+(select count(*) from public.e10_session_presence_segments where organization_id in($1,$4))+(select count(*) from public.e10_session_presence_events where organization_id in($1,$4))+(select count(*) from public.e10_session_presence_attribution_decisions where organization_id in($1,$4))+(select count(*) from public.e10_customer_resolution_decisions where organization_id in($1,$4))+(select count(*) from public.e10_customer_mutation_receipts where organization_id in($1,$4))+(select count(*) from public.e10_break_sessions where organization_id in($1,$4))+(select count(*) from public.e10_customers where organization_id in($1,$4))+(select count(*) from public.e10_organization_memberships where organization_id in($1,$4))+(select count(*) from public.e10_organization_role_permissions where organization_id in($1,$4))+(select count(*) from public.e10_organization_roles where organization_id in($1,$4))+(select count(*) from auth.users where id in($2,$3)) n',[x.org,x.user,x.outsider,x.org2])).rows[0].n);
  const sentinel=Number((await s.query("select count(*) n from public.e10_organizations where id='e1000000-0000-4000-8000-0000000000a6'")).rows[0].n);await Promise.all([s.end(),a.end(),b.end(),o.end(),i.end()]);if(residue||sentinel!==1)throw Error('X7a cleanup/sentinel '+JSON.stringify({residue,sentinel}));
 }
 if(success)console.log('TA-X7a attendance reporting: PASS');
}
main().catch(e=>{console.error(e.stack);process.exit(1)});
