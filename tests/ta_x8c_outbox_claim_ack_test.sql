-- TA-X8c exact claim/ack/idempotency contract. Transactionally rolled back.
begin;
do $$
declare
  oa uuid:='8c000000-0000-4000-8000-000000000001'; ob uuid:='8c000000-0000-4000-8000-000000000002';
  ev1 uuid:='8c000000-0000-4000-8000-000000000011'; ev2 uuid:='8c000000-0000-4000-8000-000000000012'; evb uuid:='8c000000-0000-4000-8000-000000000013';
  q1 uuid:='8c000000-0000-4000-8000-000000000021'; q2 uuid:='8c000000-0000-4000-8000-000000000022'; qb uuid:='8c000000-0000-4000-8000-000000000023';
  ca uuid:='8c000000-0000-4000-8000-000000000031'; ca2 uuid:='8c000000-0000-4000-8000-000000000032'; cb uuid:='8c000000-0000-4000-8000-000000000033';
  j jsonb; j2 jsonb; tok1 uuid; tok2 uuid; gen1 integer; gen2 integer; t text;
begin
  if exists(select 1 from public.e10_outbox_consumers) then raise exception 'X8c migration seeded a consumer'; end if;
  insert into public.e10_organizations(id,slug,name) values(oa,'x8c-func-a','X8c A'),(ob,'x8c-func-b','X8c B');
  insert into public.e10_commercial_events(id,organization_id,event_type,subject_type,subject_id,occurred_at,idempotency_key,source_kind,payload,request_fingerprint) values
    (ev1,oa,'listing_created','inventory_item','x8c-1',now(),'x8c-1','manual','{"listing_id":"1","channel":"manual"}','x8c-1'),
    (ev2,oa,'listing_created','inventory_item','x8c-2',now(),'x8c-2','manual','{"listing_id":"2","channel":"manual"}','x8c-2'),
    (evb,ob,'listing_created','inventory_item','x8c-b',now(),'x8c-b','manual','{"listing_id":"b","channel":"manual"}','x8c-b');
  insert into public.e10_outbox_consumers(id,organization_id,consumer_key,allowed_destination_keys) values
    (ca,oa,'worker-a',array['destination-a']), (ca2,oa,'worker-a2',array['destination-a']), (cb,ob,'worker-b',array['destination-a']);
  insert into public.e10_integration_outbox(id,organization_id,commercial_event_id,destination_key,payload,next_attempt_at) values
    (q1,oa,ev1,'destination-a','{"event":"1"}',null), (q2,oa,ev2,'destination-a','{"event":"2"}',now()+interval '1 hour'),
    (qb,ob,evb,'destination-a','{"event":"b"}',null);

  begin perform public.e10_claim_outbox(oa,ca,1,301,'bad-lease'); raise exception 'lease 301 accepted';
  exception when sqlstate '22023' then if sqlerrm<>'outbox_claim_lease_out_of_range' then raise; end if; end;
  begin perform public.e10_claim_outbox(oa,cb,1,60,'foreign'); raise exception 'foreign consumer accepted';
  exception when sqlstate '42501' then if sqlerrm<>'outbox_consumer_denied' then raise; end if; end;

  j:=public.e10_claim_outbox(oa,ca,1,60,'claim-1');
  tok1:=(j#>>'{claims,0,claim_token}')::uuid; gen1:=(j#>>'{claims,0,claim_generation}')::integer;
  if (j->>'count')::integer<>1 or not (j->>'authoritative')::boolean or (j#>>'{claims,0,outbox_id}')::uuid<>q1 or gen1<>1 then
    raise exception 'first bounded claim malformed: %',j; end if;
  j2:=public.e10_claim_outbox(oa,ca,1,60,'claim-1');
  if not (j2->>'replay')::boolean or not (j2->>'authoritative')::boolean or j2->'claims'<>j->'claims' then raise exception 'claim replay changed result: %',j2; end if;
  if (select attempt_count from public.e10_integration_outbox where id=q1)<>1 then raise exception 'claim replay incremented attempt'; end if;
  update public.e10_outbox_consumers set allowed_destination_keys='{}' where id=ca;
  begin perform public.e10_claim_outbox(oa,ca,1,60,'claim-1'); raise exception 'claim replay survived destination removal';
  exception when sqlstate '42501' then if sqlerrm<>'outbox_destination_denied' then raise; end if; end;
  update public.e10_outbox_consumers set allowed_destination_keys=array['destination-a'] where id=ca;
  update public.e10_outbox_consumers set enabled=false where id=ca;
  begin perform public.e10_claim_outbox(oa,ca,1,60,'claim-1'); raise exception 'claim replay survived consumer disablement';
  exception when sqlstate '42501' then if sqlerrm<>'outbox_consumer_denied' then raise; end if; end;
  update public.e10_outbox_consumers set enabled=true where id=ca;
  begin perform public.e10_claim_outbox(oa,ca,1,61,'claim-1'); raise exception 'changed claim key accepted';
  exception when sqlstate '22023' then if sqlerrm<>'outbox_claim_idempotency_mismatch' then raise; end if; end;

  update public.e10_integration_outbox set claimed_at=clock_timestamp()-interval '2 seconds',claim_expires_at=clock_timestamp()-interval '1 second' where id=q1;
  j2:=public.e10_claim_outbox(oa,ca,1,60,'claim-1');
  if (j2->>'authoritative')::boolean then raise exception 'expired historical claim remained authoritative'; end if;
  j2:=public.e10_claim_outbox(oa,ca2,1,60,'claim-2'); tok2:=(j2#>>'{claims,0,claim_token}')::uuid; gen2:=(j2#>>'{claims,0,claim_generation}')::integer;
  if gen2<>2 or tok2=tok1 then raise exception 'replacement lacked new generation/token: %',j2; end if;
  begin perform public.e10_ack_outbox(oa,ca,q1,tok1,gen1,'delivered',null,null,'stale-ack'); raise exception 'stale claim acknowledged';
  exception when sqlstate '42501' then if sqlerrm<>'outbox_claim_not_owned' then raise; end if; end;

  j:=public.e10_ack_outbox(oa,ca2,q1,tok2,gen2,'delivered',null,null,'ack-delivered');
  if (j->>'replay')::boolean or j->>'outcome'<>'delivered' then raise exception 'delivered ack malformed: %',j; end if;
  if exists(select 1 from public.e10_integration_outbox where id=q1 and (claim_token is not null or claim_owner_consumer_id is not null or claimed_at is not null or claim_expires_at is not null)) then raise exception 'delivered ack retained claim'; end if;
  j2:=public.e10_ack_outbox(oa,ca2,q1,tok2,gen2,'delivered',null,null,'ack-delivered');
  if not (j2->>'replay')::boolean or (select count(*) from public.e10_outbox_acknowledgements where outbox_id=q1)<>1 then raise exception 'exact ack replay duplicated receipt'; end if;
  update public.e10_outbox_consumers set allowed_destination_keys='{}' where id=ca2;
  begin perform public.e10_ack_outbox(oa,ca2,q1,tok2,gen2,'delivered',null,null,'ack-delivered'); raise exception 'ack replay survived destination removal';
  exception when sqlstate '42501' then if sqlerrm<>'outbox_destination_denied' then raise; end if; end;
  update public.e10_outbox_consumers set allowed_destination_keys=array['destination-a'] where id=ca2;
  begin perform public.e10_ack_outbox(oa,ca2,q1,tok2,gen2,'dead',null,'changed','ack-delivered'); raise exception 'changed ack key accepted';
  exception when sqlstate '22023' then if sqlerrm<>'outbox_ack_idempotency_mismatch' then raise; end if; end;

  update public.e10_integration_outbox set next_attempt_at=null where id=q2;
  j:=public.e10_claim_outbox(oa,ca,1,60,'claim-retry'); tok1:=(j#>>'{claims,0,claim_token}')::uuid; gen1:=(j#>>'{claims,0,claim_generation}')::integer;
  j:=public.e10_ack_outbox(oa,ca,q2,tok1,gen1,'retry',5,'temporary failure','ack-retry');
  if (select status from public.e10_integration_outbox where id=q2)<>'failed' or (select last_error from public.e10_integration_outbox where id=q2)<>'temporary failure'
     or (select next_attempt_at from public.e10_integration_outbox where id=q2) is null then raise exception 'retry outcome malformed'; end if;
  update public.e10_integration_outbox set next_attempt_at=clock_timestamp()-interval '1 second' where id=q2;
  j:=public.e10_claim_outbox(oa,ca,1,60,'claim-dead'); tok1:=(j#>>'{claims,0,claim_token}')::uuid; gen1:=(j#>>'{claims,0,claim_generation}')::integer;
  perform public.e10_ack_outbox(oa,ca,q2,tok1,gen1,'dead',null,'permanent failure','ack-dead');
  if (select status from public.e10_integration_outbox where id=q2)<>'dead' or (select next_attempt_at from public.e10_integration_outbox where id=q2) is not null
     or (select delivered_at from public.e10_integration_outbox where id=q2) is not null then raise exception 'dead outcome malformed'; end if;

  j:=public.e10_claim_outbox(ob,cb,1,60,'claim-b'); tok1:=(j#>>'{claims,0,claim_token}')::uuid; gen1:=(j#>>'{claims,0,claim_generation}')::integer;
  update public.e10_outbox_consumers set enabled=false where organization_id=ob and id=cb;
  begin perform public.e10_ack_outbox(ob,cb,qb,tok1,gen1,'delivered',null,null,'revoked-ack'); raise exception 'revoked consumer acknowledged';
  exception when sqlstate '42501' then if sqlerrm<>'outbox_consumer_denied' then raise; end if; end;
  if (select status from public.e10_integration_outbox where id=qb)<>'pending' then raise exception 'revoked ack mutated row'; end if;

  foreach t in array array['e10_outbox_consumers','e10_outbox_claim_commands','e10_outbox_acknowledgements'] loop
    if not (select relrowsecurity from pg_class where oid=('public.'||t)::regclass) then raise exception '% missing RLS',t; end if;
    if has_table_privilege('anon','public.'||t,'select') or has_table_privilege('authenticated','public.'||t,'select') then raise exception '% client exposed',t; end if;
  end loop;
  if has_function_privilege('anon','public.e10_claim_outbox(uuid,uuid,integer,integer,text)','execute')
    or has_function_privilege('authenticated','public.e10_claim_outbox(uuid,uuid,integer,integer,text)','execute')
    or has_function_privilege('anon','public.e10_ack_outbox(uuid,uuid,uuid,uuid,integer,text,integer,text,text)','execute')
    or has_function_privilege('authenticated','public.e10_ack_outbox(uuid,uuid,uuid,uuid,integer,text,integer,text,text)','execute') then raise exception 'X8c API client exposed'; end if;
end $$;
rollback;
select 'TA-X8c exact dormant outbox contract PASS' result;
