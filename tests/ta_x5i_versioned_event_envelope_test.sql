\set ON_ERROR_STOP on
begin;
do $$
declare
  o uuid:='e1000000-0000-4000-8000-0000000000a6'; other_org uuid:=gen_random_uuid(); u uuid:=gen_random_uuid(); other_user uuid:=gen_random_uuid(); role_id uuid:=gen_random_uuid(); other_role uuid:=gen_random_uuid(); item_id text:='x5i-'||gen_random_uuid(); copy_id uuid:=gen_random_uuid();
  event_types text[]:=array['acquisition','receipt','available_for_sale','listing_created','listing_published','listing_paused','listing_resumed','listing_ended','listing_relisted','asking_price_changed','hold','release','sale_committed','fulfillment','fee','payout','refund','return','cost_correction','correction'];
  payloads jsonb:=jsonb_build_object(
    'acquisition',jsonb_build_object('acquisition_id','acq-1'),'receipt',jsonb_build_object('receipt_id','receipt-1'),'available_for_sale',jsonb_build_object('availability_state','available'),
    'listing_created',jsonb_build_object('listing_id','listing-a','channel','channel-a'),'listing_published',jsonb_build_object('listing_id','listing-a','channel','channel-a'),
    'listing_paused',jsonb_build_object('listing_id','listing-a','channel','channel-a'),'listing_resumed',jsonb_build_object('listing_id','listing-a','channel','channel-a'),
    'listing_ended',jsonb_build_object('listing_id','listing-a','channel','channel-a'),'listing_relisted',jsonb_build_object('listing_id','listing-a','channel','channel-a'),
    'asking_price_changed',jsonb_build_object('listing_id','listing-a','channel','channel-a','currency','CAD','amount',25),
    'hold',jsonb_build_object('hold_id','hold-1'),'release',jsonb_build_object('hold_id','hold-1'),'sale_committed',jsonb_build_object('sale_id','sale-1'),
    'fulfillment',jsonb_build_object('fulfillment_id','fulfill-1'),'fee',jsonb_build_object('fee_id','fee-1','currency','CAD','amount',2),
    'payout',jsonb_build_object('payout_id','payout-1','currency','CAD','amount',20),'refund',jsonb_build_object('refund_id','refund-1','currency','CAD','amount',5),
    'return',jsonb_build_object('return_id','return-1'),'cost_correction',jsonb_build_object('cost_adjustment_id','cost-1','currency','CAD','amount',1),
    'correction',jsonb_build_object('reason','reviewed correction'));
  event_type text; prior_event uuid; first_event uuid; result jsonb; i integer:=0;
begin
  insert into public.e10_organizations(id,name,slug) values(other_org,'X5i Other','x5i-'||replace(other_org::text,'-',''));
  insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at) values
    (u,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',u||'@x.invalid',now(),now()),
    (other_user,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',other_user||'@x.invalid',now(),now());
  insert into public.e10_organization_roles(id,organization_id,key,name,is_system) values
    (role_id,o,'x5i-'||u,'X5i',false),(other_role,other_org,'x5i-'||other_user,'X5i Other',false);
  insert into public.e10_organization_role_permissions(organization_id,role_id,capability,allowed) values
    (o,role_id,'act.record_commercial_events',true),(other_org,other_role,'act.record_commercial_events',true);
  insert into public.e10_organization_memberships(organization_id,user_id,role_id,status) values(o,u,role_id,'active'),(other_org,other_user,other_role,'active');
  insert into public.e10_inventory_items(id,organization_id,name,qty) values(item_id,o,'X5i item',1);
  insert into public.e10_unique_items(id,organization_id,inventory_item_id,item_kind) values(copy_id,o,item_id,'card');
  perform set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated')::text,true);

  foreach event_type in array event_types loop
    i:=i+1;
    result:=public.e10_org_record_commercial_event_v2(o,event_type,1,'unique_item',copy_id::text,
      case when event_type='available_for_sale' then null else '2026-01-01T00:00:00Z'::timestamptz+i*interval '1 minute' end,
      case when event_type='available_for_sale' then 'unknown' else 'exact' end,
      'manual',null,'x5i-fixture','source-'||i,'corr-x5i',prior_event,'operator_asserted',payloads->event_type,
      case when event_type in ('cost_correction','correction') then prior_event else null end,'{}','x5i-event-'||i);
    if i=1 then first_event:=(result->>'event_id')::uuid; end if;
    prior_event:=(result->>'event_id')::uuid;
  end loop;
  if (select count(*) from public.e10_commercial_events where organization_id=o and correlation_id='corr-x5i')<>20 then raise exception 'event family incomplete'; end if;
  if (select count(distinct ce.event_type) from public.e10_commercial_events ce where ce.organization_id=o and ce.correlation_id='corr-x5i')<>20 then raise exception 'event family types incomplete'; end if;
  if not exists(select 1 from public.e10_commercial_events ce where ce.organization_id=o and ce.correlation_id='corr-x5i' and ce.event_type='available_for_sale' and ce.occurred_at is null and ce.occurred_at_precision='unknown') then raise exception 'unknown occurrence time not preserved'; end if;

  result:=public.e10_org_record_commercial_event_v2(o,'acquisition',1,'unique_item',copy_id::text,'2025-12-31T19:01:00-05'::timestamptz,'exact','manual',null,'x5i-fixture','source-1','corr-x5i',null,'operator_asserted',payloads->'acquisition',null,'{}','x5i-event-1');
  if not (result->>'replay')::boolean or (result->>'event_id')::uuid<>first_event then raise exception 'timezone-stable replay failed'; end if;
  begin perform public.e10_org_record_commercial_event_v2(o,'acquisition',1,'unique_item',copy_id::text,'2026-01-01T00:01:00Z','exact','manual',null,'x5i-fixture','source-1','different',null,'operator_asserted',payloads->'acquisition',null,'{}','x5i-event-1'); raise exception 'idempotency mismatch accepted'; exception when sqlstate '22023' then null; end;
  begin perform public.e10_org_record_commercial_event_v2(o,'listing_created',1,'unique_item',copy_id::text,now(),'exact','manual',null,null,'missing-keys','corr',null,'operator_asserted','{}',null,'{}','x5i-missing'); raise exception 'missing required payload accepted'; exception when sqlstate '22023' then null; end;
  begin perform public.e10_org_record_commercial_event_v2(o,'listing_created',99,'unique_item',copy_id::text,now(),'exact','manual',null,null,'unknown-schema','corr',null,'operator_asserted',payloads->'listing_created',null,'{}','x5i-schema'); raise exception 'unknown schema accepted'; exception when sqlstate '22023' then null; end;
  begin perform public.e10_org_record_commercial_event_v2(o,'listing_created',1,'unique_item',copy_id::text,now(),'exact','manual',null,null,'source-4','corr',null,'operator_asserted',payloads->'listing_created',null,'{}','x5i-source-duplicate'); raise exception 'source event duplicate accepted'; exception when unique_violation then null; end;

  perform public.e10_org_record_commercial_event_v2(o,'listing_created',1,'unique_item',copy_id::text,'2026-01-02T00:00:00Z','exact','manual',null,'second channel','listing-b-created','corr-listings',null,'operator_asserted',jsonb_build_object('listing_id','listing-b','channel','channel-b'),null,'{}','x5i-listing-b');
  if (select count(*) from public.e10_commercial_events ce where ce.organization_id=o and ce.subject_type='unique_item' and ce.subject_id=copy_id::text and ce.event_type='listing_created')<>2 then raise exception 'competing channel listings did not share physical copy'; end if;

  perform set_config('request.jwt.claims',jsonb_build_object('sub',other_user,'role','authenticated')::text,true);
  perform set_config('role','authenticated',true);
  begin perform public.e10_org_record_commercial_event_v2(o,'return',1,'unique_item',copy_id::text,now(),'exact','manual',null,null,'hostile','corr',null,'operator_asserted',payloads->'return',null,'{}','x5i-hostile'); raise exception 'cross-org event accepted'; exception when insufficient_privilege then null; end;
  begin perform 1 from public.e10_commercial_events where id=first_event; raise exception 'authenticated direct event SELECT allowed'; exception when insufficient_privilege then null; end;
  perform set_config('role','postgres',true);
  raise notice 'TA-X5i event envelope: PASS (20 families, schemas, lineage, unknown time, competing channels, replay, tenant denial)';
end $$;
rollback;
