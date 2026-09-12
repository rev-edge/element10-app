\set ON_ERROR_STOP 0
begin;
do $$
declare oa uuid:=gen_random_uuid();ob uuid:=gen_random_uuid();ev1 uuid:=gen_random_uuid();ev2 uuid:=gen_random_uuid();ev3 uuid:=gen_random_uuid();q1 uuid:=gen_random_uuid();q2 uuid:=gen_random_uuid();q3 uuid:=gen_random_uuid();ca uuid:=gen_random_uuid();ca2 uuid:=gen_random_uuid();cb uuid:=gen_random_uuid();
 j jsonb;j2 jsonb;tok uuid;gen int;u uuid:=gen_random_uuid();r uuid:=gen_random_uuid();
begin
 raise notice '0 grants: anon claim=% auth claim=% auth ack=% service claim=% ; auth select outbox=% consumers=% acks=% claim_cmds=%',
  has_function_privilege('anon','public.e10_claim_outbox(uuid,uuid,integer,integer,text)','execute'),has_function_privilege('authenticated','public.e10_claim_outbox(uuid,uuid,integer,integer,text)','execute'),has_function_privilege('authenticated','public.e10_ack_outbox(uuid,uuid,uuid,uuid,integer,text,integer,text,text)','execute'),has_function_privilege('service_role','public.e10_claim_outbox(uuid,uuid,integer,integer,text)','execute'),
  has_table_privilege('authenticated','public.e10_integration_outbox','select'),has_table_privilege('authenticated','public.e10_outbox_consumers','select'),has_table_privilege('authenticated','public.e10_outbox_acknowledgements','select'),has_table_privilege('authenticated','public.e10_outbox_claim_commands','select');
 raise notice '0 consumers seeded=% ; triggers on outbox tables=%',(select count(*) from public.e10_outbox_consumers),(select string_agg(tgname||'->'||p.proname,', ') from pg_trigger t join pg_proc p on p.oid=t.tgfoid where t.tgrelid in('public.e10_integration_outbox'::regclass,'public.e10_outbox_acknowledgements'::regclass,'public.e10_outbox_claim_commands'::regclass,'public.e10_outbox_consumers'::regclass) and not t.tgisinternal);
 raise notice '0 installed extensions=%',(select string_agg(extname,',') from pg_extension);
 insert into public.e10_organizations(id,slug,name)values(oa,'e4a-'||substr(oa::text,1,8),'E4 A'),(ob,'e4b-'||substr(ob::text,1,8),'E4 B');
 insert into public.e10_commercial_events(id,organization_id,event_type,subject_type,subject_id,occurred_at,idempotency_key,source_kind,payload,request_fingerprint)values
  (ev1,oa,'listing_created','inventory_item','e4-1',now(),'e4-1','manual','{"listing_id":"1","channel":"manual"}','e4-1'),
  (ev2,oa,'listing_created','inventory_item','e4-2',now(),'e4-2','manual','{"listing_id":"2","channel":"manual"}','e4-2'),
  (ev3,ob,'listing_created','inventory_item','e4-b',now(),'e4-b','manual','{"listing_id":"b","channel":"manual"}','e4-b');
 insert into public.e10_outbox_consumers(id,organization_id,consumer_key,allowed_destination_keys)values(ca,oa,'w-a',array['dest']),(ca2,oa,'w-a2',array['dest']),(cb,ob,'w-b',array['dest']);
 insert into public.e10_integration_outbox(id,organization_id,commercial_event_id,destination_key,payload)values(q1,oa,ev1,'dest','{"e":1}'),(q2,oa,ev2,'dest','{"e":2}'),(q3,ob,ev3,'dest','{"e":"b"}');
 -- 1. authenticated user tries claim
 insert into auth.users(id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)values(u,'authenticated','authenticated','e4-u@x.invalid','',now(),'{}','{}',now(),now());
 perform set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated')::text,true);set local role authenticated;
 begin perform public.e10_claim_outbox(oa,ca,10,60,'e4-auth');raise notice 'FINDING 1: authenticated claimed outbox';exception when others then raise notice '1 authenticated claim -> % %',sqlstate,sqlerrm;end;
 reset role;
 -- 2. claim all as ca; second consumer ca2 gets none; consumer of other org sees only its own
 j:=public.e10_claim_outbox(oa,ca,10,60,'e4-c1');raise notice '2 ca claimed count=% authoritative=%',j->>'count',j->>'authoritative';
 tok:=(j#>>'{claims,0,claim_token}')::uuid;gen:=(j#>>'{claims,0,claim_generation}')::int;
 j2:=public.e10_claim_outbox(oa,ca2,10,60,'e4-c2');raise notice '2 ca2 concurrent-lease claim count=% (expect 0)',j2->>'count';
 j2:=public.e10_claim_outbox(ob,cb,10,60,'e4-cb');raise notice '2 cb (org b) count=% ids in org b only=%',j2->>'count',(select bool_and((x->>'outbox_id')::uuid=q3) from jsonb_array_elements(j2->'claims')x);
 -- 2b. cross-org consumer id
 begin perform public.e10_claim_outbox(oa,cb,10,60,'e4-cross');raise notice 'FINDING 2b: consumer of org b claimed in org a';exception when others then raise notice '2b cross-org consumer -> % %',sqlstate,sqlerrm;end;
 -- 3. claim replay same key -> replay; same key different limit -> mismatch
 j2:=public.e10_claim_outbox(oa,ca,10,60,'e4-c1');raise notice '3 replay=% authoritative=% count=%',j2->>'replay',j2->>'authoritative',j2->>'count';
 begin perform public.e10_claim_outbox(oa,ca,5,60,'e4-c1');raise notice 'FINDING 3b';exception when others then raise notice '3b key reuse different args -> % %',sqlstate,sqlerrm;end;
 -- 4. ack with wrong token / wrong generation / by other consumer
 begin perform public.e10_ack_outbox(oa,ca,q1,gen_random_uuid(),gen,'delivered',null,null,'e4-ack-badtok');raise notice 'FINDING 4a';exception when others then raise notice '4a wrong token -> % %',sqlstate,sqlerrm;end;
 begin perform public.e10_ack_outbox(oa,ca,q1,tok,gen+1,'delivered',null,null,'e4-ack-badgen');raise notice 'FINDING 4b';exception when others then raise notice '4b wrong generation -> % %',sqlstate,sqlerrm;end;
 begin perform public.e10_ack_outbox(oa,ca2,q1,tok,gen,'delivered',null,null,'e4-ack-other');raise notice 'FINDING 4c';exception when others then raise notice '4c other consumer w/ leaked token -> % %',sqlstate,sqlerrm;end;
 -- 5. ack retry, then replay, then second ack with new key
 j:=public.e10_ack_outbox(oa,ca,q1,tok,gen,'retry',30,'boom','e4-ack-1');raise notice '5 ack retry outcome=% retry_at set=%',j->>'outcome',j->>'retry_at' is not null;
 j2:=public.e10_ack_outbox(oa,ca,q1,tok,gen,'retry',30,'boom','e4-ack-1');raise notice '5 ack replay=%',j2->>'replay';
 begin perform public.e10_ack_outbox(oa,ca,q1,tok,gen,'delivered',null,null,'e4-ack-2');raise notice 'FINDING 5b: second ack with stale token accepted';exception when others then raise notice '5b re-ack new key -> % %',sqlstate,sqlerrm;end;
 raise notice '5 row state: status=% next_attempt_at future=% claim cleared=%',(select status from public.e10_integration_outbox where id=q1),(select next_attempt_at>clock_timestamp() from public.e10_integration_outbox where id=q1),(select claim_token is null from public.e10_integration_outbox where id=q1);
 -- 6. retry row not claimable until next_attempt_at
 j:=public.e10_claim_outbox(oa,ca2,10,60,'e4-c3');raise notice '6 claim during backoff count=% (expect 0; q2 still leased by ca)',j->>'count';
 -- 7. lease expiry: expire q2 lease and let ca2 take it; old owner ack fails
 select claim_token,claim_generation into tok,gen from public.e10_integration_outbox where id=q2;
 update public.e10_integration_outbox set claimed_at=clock_timestamp()-interval'2 seconds',claim_expires_at=clock_timestamp()-interval'1 second' where id=q2;
 j:=public.e10_claim_outbox(oa,ca2,10,60,'e4-c4');raise notice '7 ca2 after expiry count=% gen=% (expect 1 and %)',j->>'count',j#>>'{claims,0,claim_generation}',gen+1;
 begin perform public.e10_ack_outbox(oa,ca,q2,tok,gen,'delivered',null,null,'e4-ack-late');raise notice 'FINDING 7b: expired lease owner acked';exception when others then raise notice '7b old owner late ack -> % %',sqlstate,sqlerrm;end;
 -- 7c. new owner acks delivered; then no one can reclaim
 j:=public.e10_ack_outbox(oa,ca2,q2,(j#>>'{claims,0,claim_token}')::uuid,gen+1,'delivered',null,null,'e4-ack-new');raise notice '7c delivered=%',j->>'outcome';
 j:=public.e10_claim_outbox(oa,ca,10,60,'e4-c5');raise notice '7c reclaim delivered count=% (expect 0)',j->>'count';
 -- 7d. dead
 update public.e10_integration_outbox set next_attempt_at=null where id=q1;j:=public.e10_claim_outbox(oa,ca,10,60,'e4-c6');tok:=(j#>>'{claims,0,claim_token}')::uuid;gen:=(j#>>'{claims,0,claim_generation}')::int;
 j:=public.e10_ack_outbox(oa,ca,q1,tok,gen,'dead',null,'fatal','e4-ack-dead');raise notice '7d dead=% status=%',j->>'outcome',(select status from public.e10_integration_outbox where id=q1);
 j:=public.e10_claim_outbox(oa,ca,10,60,'e4-c7');raise notice '7d reclaim dead count=% (expect 0)',j->>'count';
 -- 8. disabled consumer replay of an earlier claim
 update public.e10_outbox_consumers set enabled=false where id=ca;
 begin perform public.e10_claim_outbox(oa,ca,10,60,'e4-c1');raise notice 'FINDING 8: disabled consumer replayed claim';exception when others then raise notice '8 disabled consumer replay -> % %',sqlstate,sqlerrm;end;
 update public.e10_outbox_consumers set enabled=true,allowed_destination_keys='{}' where id=ca;
 begin perform public.e10_claim_outbox(oa,ca,10,60,'e4-c1');raise notice 'FINDING 8b: destination removed but replay returned payload';exception when others then raise notice '8b destination removed replay -> % %',sqlstate,sqlerrm;end;
 -- 9. append-only
 begin update public.e10_outbox_acknowledgements set outcome='delivered';raise notice 'FINDING 9';exception when others then raise notice '9 ack update -> % %',sqlstate,sqlerrm;end;
 begin delete from public.e10_outbox_claim_commands;raise notice 'FINDING 9b';exception when others then raise notice '9b claim cmd delete -> % %',sqlstate,sqlerrm;end;
end $$;
rollback;
