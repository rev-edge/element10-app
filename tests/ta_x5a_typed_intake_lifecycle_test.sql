\set ON_ERROR_STOP on
begin;
do $$
declare o uuid:='e1000000-0000-4000-8000-0000000000a6'; ob uuid:=gen_random_uuid();
  b uuid:=gen_random_uuid(); bb uuid:=gen_random_uuid(); row1 uuid:=gen_random_uuid(); d1 uuid:=gen_random_uuid(); d2 uuid:=gen_random_uuid();
  ev1 uuid:=gen_random_uuid(); ev2 uuid:=gen_random_uuid(); c bigint; t text;
begin
  insert into public.e10_organizations(id,name,slug) values(ob,'X5a Org B','x5a-org-b');
  insert into public.e10_intake_batches(id,organization_id,source_kind,source_reference,original_file_reference,payload_fingerprint)
    values(b,o,'csv','upload-1','storage://x5a/source.csv','same-payload'),(bb,ob,'csv','upload-1','storage://x5a/source.csv','same-payload');
  insert into public.e10_intake_rows(id,organization_id,batch_id,source_row_number,raw_payload,observation_kind,occurred_at,currency,amount,match_status)
    values(row1,o,b,1,'{"kind":"ask","amount":"25"}','asking_price',now(),'CAD',25,'unresolved');
  insert into public.e10_intake_rows(organization_id,batch_id,source_row_number,raw_payload,observation_kind,occurred_at,currency,amount,match_status)
    values(o,b,2,'{"kind":"sale","amount":"25"}','completed_sale',now(),'CAD',25,'unresolved');
  select count(distinct observation_kind) into c from public.e10_intake_rows where organization_id=o and batch_id=b;
  if c<>2 then raise exception 'typed kinds collapsed'; end if;
  begin
    insert into public.e10_intake_rows(organization_id,batch_id,source_row_number,raw_payload)
      values(ob,b,3,'{}'); raise exception 'cross-org batch link accepted';
  exception when foreign_key_violation then null; end;
  insert into public.e10_intake_resolver_decisions(id,organization_id,intake_row_id,decision,reason)
    values(d1,o,row1,'reject','ambiguous identity');
  insert into public.e10_intake_resolver_decisions(id,organization_id,intake_row_id,decision,reason,corrects_decision_id)
    values(d2,o,row1,'clear_match','review reopened',d1);
  begin update public.e10_intake_resolver_decisions set reason='rewrite' where id=d1; raise exception 'resolver history mutated';
  exception when sqlstate '55000' then null; end;
  insert into public.e10_commercial_events(id,organization_id,event_type,subject_type,subject_id,occurred_at,idempotency_key,source_kind,payload)
    values(ev1,o,'listing_created','inventory_item','x5a-item',now(),'x5a-event-1','manual','{"ask":25}');
  insert into public.e10_commercial_events(id,organization_id,event_type,subject_type,subject_id,occurred_at,idempotency_key,source_kind,payload,corrects_event_id)
    values(ev2,o,'correction','inventory_item','x5a-item',now(),'x5a-event-2','manual','{"reason":"wrong ask"}',ev1);
  begin update public.e10_commercial_events set payload='{}' where id=ev1; raise exception 'commercial event mutated';
  exception when sqlstate '55000' then null; end;
  begin
    insert into public.e10_commercial_events(organization_id,event_type,subject_type,subject_id,occurred_at,idempotency_key,source_kind)
      values(o,'correction','other','x',now(),'x5a-bad-correction','manual'); raise exception 'lineage-free correction accepted';
  exception when check_violation then null; end;
  insert into public.e10_integration_outbox(organization_id,commercial_event_id,destination_key,payload)
    values(o,ev1,'dormant-test','{"event":"listing_created"}');
  select status into t from public.e10_integration_outbox where commercial_event_id=ev1;
  if t<>'pending' then raise exception 'outbox not pending: %',t; end if;
  foreach t in array array['e10_intake_batches','e10_intake_rows','e10_intake_resolver_decisions','e10_commercial_events','e10_integration_outbox'] loop
    if not (select relrowsecurity from pg_class where oid=('public.'||t)::regclass) then raise exception '% missing RLS',t; end if;
    if has_table_privilege('authenticated','public.'||t,'select') or has_table_privilege('anon','public.'||t,'select') then
      raise exception '% exposed before bounded API',t;
    end if;
  end loop;
  raise notice 'TA-X5a typed intake/lifecycle: PASS (raw+typed separation, tenant FKs, correction lineage, immutable events, dormant outbox)';
end $$;
rollback;
