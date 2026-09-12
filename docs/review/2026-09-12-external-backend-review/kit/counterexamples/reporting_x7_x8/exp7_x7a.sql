\set ON_ERROR_STOP 0
begin;
do $$
declare o uuid:=gen_random_uuid();u uuid:=gen_random_uuid();u2 uuid:=gen_random_uuid();rid uuid:=gen_random_uuid();cust uuid:=gen_random_uuid();cust2 uuid:=gen_random_uuid();sess uuid[];s uuid;st uuid;sg uuid;i int;j jsonb;
 r record;avgs numeric[]:='{}';cov text[]:='{}';weeks date[]:='{}';fp text;rev bigint;after date;pages int:=0;n int;tot numeric;segtot numeric[]:='{}';segn int:=0;segafter uuid;
 wfrom timestamptz:='2026-01-05T00:00:00Z';wto timestamptz:='2026-02-02T00:00:00Z';cut timestamptz:='2026-02-02T00:00:00Z';
begin
 insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at)values(u,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','e7-'||u||'@x.invalid',now(),now()),(u2,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','e7-'||u2||'@x.invalid',now(),now());
 insert into public.e10_organizations(id,slug,name)values(o,'e7-'||substr(o::text,1,8),'E7');
 insert into public.e10_organization_roles(id,organization_id,key,name,is_system)values(rid,o,'e7','E7',false);
 insert into public.e10_organization_role_permissions values(o,rid,'act.view_customer_engagement',true),(o,rid,'act.manage_attendance_coverage',true);
 insert into public.e10_organization_memberships(organization_id,user_id,role_id,status)values(o,u,rid,'active'),(o,u2,rid,'active');
 insert into public.e10_customers(id,organization_id,display_name)values(cust,o,'C1'),(cust2,o,'C2');
 insert into public.e10_presence_collection_policies(organization_id,policy_version,source_class,provider_key,enabled,notice_version,heartbeat_expiry_seconds,min_event_interval_ms,max_events_per_minute,retention_interval,coverage_label,effective_from,effective_through)values(o,1,'companion','companion',true,'notice-v1',300,0,600,interval'365 days','fixture','2026-01-01T00:00:00Z','2026-03-01T00:00:00Z');
 -- 6 sessions: week1:1, week2:2, week3:3, week4:0 ; each attended by cust for 600s; session 1 also has 3 segments for cust (contributors)
 for i in 1..6 loop s:=gen_random_uuid();sess:=array_append(sess,s);
  insert into public.e10_break_sessions(id,organization_id,streamer_uid,name,status,ended_at,visibility)values(s,o,u,'E7 '||i,'ended',case when i=1 then '2026-01-06T12:00:00Z'::timestamptz when i<=3 then '2026-01-13T12:00:00Z' else '2026-01-20T12:00:00Z' end,'private');
  st:=gen_random_uuid();sg:=gen_random_uuid();
  insert into public.e10_session_presence_streams(id,organization_id,session_id,source_class,provider_key,subject_key,connection_id,observed_user_id,original_customer_id,identity_status,collection_policy_version,notice_version,coverage_label,retention_expires_at)values(st,o,s,'companion','companion',u,'conn-'||i,u,cust,'reviewed_attributed',1,'notice-v1','fixture','2026-03-01T00:00:00Z');
  insert into public.e10_session_presence_segments(id,organization_id,stream_id,segment_sequence,heartbeat_expiry_seconds,retention_expires_at,collection_policy_version,notice_version,coverage_label)values(sg,o,st,1,300,'2026-03-01T00:00:00Z',1,'notice-v1','fixture');
  insert into public.e10_session_presence_events(organization_id,stream_id,segment_id,event_sequence,event_kind,server_received_at,evidence,request_fingerprint)values
   (o,st,sg,1,'join',case when i=1 then '2026-01-06T10:00:00Z'::timestamptz when i<=3 then '2026-01-13T10:00:00Z' else '2026-01-20T10:00:00Z' end,'{}','e7-'||i),
   (o,st,sg,2,'heartbeat',case when i=1 then '2026-01-06T10:05:00Z'::timestamptz when i<=3 then '2026-01-13T10:05:00Z' else '2026-01-20T10:05:00Z' end,'{}','e7-'||i),
   (o,st,sg,3,'leave',case when i=1 then '2026-01-06T10:10:00Z'::timestamptz when i<=3 then '2026-01-13T10:10:00Z' else '2026-01-20T10:10:00Z' end,'{}','e7-'||i);
 end loop;
 -- extra contributor segments for session 1 / cust (3 more streams, overlapping 10:05-10:15 -> union 15 min = 900s)
 for i in 1..3 loop st:=gen_random_uuid();sg:=gen_random_uuid();
  insert into public.e10_session_presence_streams(id,organization_id,session_id,source_class,provider_key,subject_key,connection_id,observed_user_id,original_customer_id,identity_status,collection_policy_version,notice_version,coverage_label,retention_expires_at)values(st,o,sess[1],'companion','companion',u,'xconn-'||i,u,cust,'reviewed_attributed',1,'notice-v1','fixture','2026-03-01T00:00:00Z');
  insert into public.e10_session_presence_segments(id,organization_id,stream_id,segment_sequence,heartbeat_expiry_seconds,retention_expires_at,collection_policy_version,notice_version,coverage_label)values(sg,o,st,1,300,'2026-03-01T00:00:00Z',1,'notice-v1','fixture');
  insert into public.e10_session_presence_events(organization_id,stream_id,segment_id,event_sequence,event_kind,server_received_at,evidence,request_fingerprint)values(o,st,sg,1,'join','2026-01-06T10:05:00Z','{}','e7x-'||i),(o,st,sg,2,'heartbeat','2026-01-06T10:10:00Z','{}','e7x-'||i),(o,st,sg,3,'leave','2026-01-06T10:15:00Z','{}','e7x-'||i);
 end loop;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated')::text,true);set local role authenticated;
 -- complete coverage across the whole window
 j:=public.e10_org_review_attendance_coverage(o,null,0,'assert','companion','companion',wfrom,wto,'complete',1,'fixture','{}','e7-cov');raise notice '0 coverage=%',j->>'coverage_status';
 -- A. weekly with limit 2 over 4 weeks: complete_window_average must be identical on every page and equal 6/4=1.5
 after:=null;
 loop pages:=pages+1;n:=0;
  for r in select * from public.e10_org_weekly_attendance(o,wfrom,wto,cut,'UTC',1,null,'companion','companion',2,after,rev,fp) loop n:=n+1;avgs:=array_append(avgs,r.complete_window_average_sessions_per_week);cov:=array_append(cov,r.coverage_status);weeks:=array_append(weeks,r.week_start_date);fp:=r.query_fingerprint;rev:=r.dataset_revision;after:=r.week_start_date;end loop;
  exit when n<2 or pages>5;
 end loop;
 raise notice 'A weekly pages=% weeks=% coverage=% window-average per row=% (expect all 1.5)',pages,weeks,cov,avgs;
 -- A2. cursor tampering: fingerprint from another query (customer filter) ; stale revision
 begin perform * from public.e10_org_weekly_attendance(o,wfrom,wto,cut,'UTC',1,null,'companion','companion',2,weeks[1],rev,md5('x'));raise notice 'FINDING A2: wrong fingerprint accepted';exception when others then raise notice 'A2 wrong fp -> % %',sqlstate,sqlerrm;end;
 begin perform * from public.e10_org_weekly_attendance(o,wfrom,wto,cut,'UTC',1,null,'companion','companion',2,weeks[1],rev+1,fp);raise notice 'FINDING A3: stale revision accepted';exception when others then raise notice 'A3 stale revision -> % %',sqlstate,sqlerrm;end;
 -- A4: same-org other member reuses fingerprint+cursor (fingerprint is not actor bound)
 perform set_config('request.jwt.claims',jsonb_build_object('sub',u2,'role','authenticated')::text,true);
 begin select count(*) into n from public.e10_org_weekly_attendance(o,wfrom,wto,cut,'UTC',1,null,'companion','companion',2,weeks[1],rev,fp);raise notice 'A4 other member reused cursor+fp: rows=% (authorized member; fingerprint is deterministic, not actor-bound)',n;exception when others then raise notice 'A4 -> % %',sqlstate,sqlerrm;end;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated')::text,true);
 -- B. contributions: limit 1 pagination over 6 rows; totals
 n:=0;tot:=0;r:=null;
 declare aft_s uuid;aft_c uuid;begin
 loop
  select * into r from public.e10_org_attendance_contributions(o,wfrom,wto,cut,null,'companion','companion',1,aft_s,aft_c,rev,fp) limit 1;
  exit when r is null or r.session_id is null;n:=n+1;tot:=tot+r.observed_seconds;aft_s:=r.session_id;aft_c:=r.effective_customer_id;fp:=r.query_fingerprint;rev:=r.dataset_revision;r:=null;if n>20 then exit;end if;
 end loop;end;
 raise notice 'B contributions rows via limit-1 pages=% total observed seconds=% (expect 6 rows; 5*600+900=3900)',n,tot;
 -- C. segments: session 1 / cust has 4 contributors; page limit 1; union total must be 900 on every page
 fp:=null;rev:=null;segafter:=null;
 loop select * into r from public.e10_org_attendance_contribution_segments(o,wfrom,wto,cut,cust,sess[1],'companion','companion',1,segafter,rev,fp) limit 1;exit when r is null or r.segment_id is null;segn:=segn+1;segtot:=array_append(segtot,r.session_union_observed_seconds);segafter:=r.segment_id;fp:=r.query_fingerprint;rev:=r.dataset_revision;r:=null;if segn>20 then exit;end if;end loop;
 raise notice 'C segments pages=% union per page=% contributor_count=% (expect 4 pages, all 900)',segn,segtot,null;
 -- D. cross-check weekly totals: sum of distinct sessions across weeks
 select sum(distinct_attended_sessions),sum(observed_attendance_seconds) into r from public.e10_org_weekly_attendance(o,wfrom,wto,cut,'UTC',1,null,'companion','companion',54,null,null,null);
 raise notice 'D weekly sessions total=% seconds total=% (expect 6, 3900)',r.sum,r.sum;
 select sum(distinct_attended_sessions) s1,sum(observed_attendance_seconds) s2 into r from public.e10_org_weekly_attendance(o,wfrom,wto,cut,'UTC',1,null,'companion','companion',54,null,null,null);
 raise notice 'D weekly sessions total=% seconds total=%',r.s1,r.s2;
 -- E. suspended org: reads still allowed? (is_org_member semantics)
 reset role;update public.e10_organizations set status='suspended' where id=o;set local role authenticated;
 begin select count(*) into n from public.e10_org_weekly_attendance(o,wfrom,wto,cut,'UTC',1,null,'companion','companion',54,null,null,null);raise notice 'E suspended org weekly read rows=%',n;exception when others then raise notice 'E suspended org -> % %',sqlstate,sqlerrm;end;
 begin j:=public.e10_org_review_attendance_coverage(o,null,0,'assert','companion','companion',wfrom,wto,'partial',1,'fixture','{}','e7-cov-susp');raise notice 'E suspended org coverage write ok=% (writer does not check org status)',j->>'ok';exception when others then raise notice 'E suspended org coverage write -> % %',sqlstate,sqlerrm;end;
end $$;
rollback;
