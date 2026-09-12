\set ON_ERROR_STOP on
begin;
\ir ta_x8_business_state_helper.sql
do $$
declare o uuid:=gen_random_uuid();user_id uuid:=gen_random_uuid();role_id uuid:=gen_random_uuid();release_id uuid:=gen_random_uuid();variant_id uuid:=gen_random_uuid();item1 uuid:=gen_random_uuid();item2 uuid:=gen_random_uuid();item3 uuid:=gen_random_uuid();item4 uuid:=gen_random_uuid();item5 uuid:=gen_random_uuid();item6 uuid:=gen_random_uuid();item7 uuid:=gen_random_uuid();origin1 uuid:=gen_random_uuid();origin2 uuid:=gen_random_uuid();origin3 uuid:=gen_random_uuid();origin4 uuid:=gen_random_uuid();receipt4 uuid:=gen_random_uuid();origin5 uuid:=gen_random_uuid();origin6 uuid:=gen_random_uuid();disposal_event uuid:=gen_random_uuid();tx_id uuid:=gen_random_uuid();tx2 uuid:=gen_random_uuid();tx3 uuid:=gen_random_uuid();tx4 uuid:=gen_random_uuid();line6 uuid:=gen_random_uuid();cancel6 uuid:=gen_random_uuid();sale_obs uuid:=gen_random_uuid();replacement_obs uuid:=gen_random_uuid();external_obs uuid:=gen_random_uuid();j jsonb;j2 jsonb;bs jsonb;cursor_value text;x8ctx uuid;
begin
 insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at)values(user_id,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','x7el-'||user_id||'@x.invalid',now(),now());
 insert into public.e10_organizations(id,slug,name)values(o,'x7el-'||substr(o::text,1,8),'X7e lifecycle');
 insert into public.e10_organization_roles(id,organization_id,key,name,is_system)values(role_id,o,'x7el','X7e lifecycle',false);
 insert into public.e10_organization_memberships(organization_id,user_id,role_id,status)values(o,user_id,role_id,'active');
 insert into public.e10_organization_role_permissions(organization_id,role_id,capability,allowed)values(o,role_id,'act.view_market_analytics',true),(o,role_id,'act.curate_market_analytics',true);
 insert into public.e10_catalog_releases(id,release_name)values(release_id,'X7e lifecycle');insert into public.e10_catalog_variants(id,release_id)values(variant_id,release_id);
 insert into public.e10_unique_items(id,organization_id,catalog_variant_id,item_kind)values(item1,o,variant_id,'card'),(item2,o,variant_id,'card'),(item3,o,variant_id,'card'),(item4,o,variant_id,'card'),(item5,o,variant_id,'card'),(item6,o,variant_id,'card'),(item7,o,variant_id,'card');

 insert into public.e10_commercial_events(id,organization_id,event_type,event_schema_version,subject_type,subject_id,occurred_at,occurred_at_precision,idempotency_key,source_kind,evidence_quality,payload,created_by)values
 (origin1,o,'receipt',1,'unique_item',item1::text,'2026-01-01 00:00Z','exact','x7el-origin1','manual','operator_asserted',jsonb_build_object('receipt_id','r1'),user_id),
 (gen_random_uuid(),o,'listing_published',1,'unique_item',item1::text,'2026-01-03 00:00Z','exact','x7el-pub-a','manual','operator_asserted',jsonb_build_object('listing_id','a','channel','shop'),user_id),
 (gen_random_uuid(),o,'listing_published',1,'unique_item',item1::text,'2026-01-03 12:00Z','exact','x7el-pub-b','manual','operator_asserted',jsonb_build_object('listing_id','b','channel','market'),user_id),
 (gen_random_uuid(),o,'listing_paused',1,'unique_item',item1::text,'2026-01-03 18:00Z','exact','x7el-pause-b','manual','operator_asserted',jsonb_build_object('listing_id','b','channel','market'),user_id),
 (gen_random_uuid(),o,'listing_paused',1,'unique_item',item1::text,'2026-01-04 00:00Z','exact','x7el-pause-a','manual','operator_asserted',jsonb_build_object('listing_id','a','channel','shop'),user_id),
 (gen_random_uuid(),o,'listing_resumed',1,'unique_item',item1::text,'2026-01-06 00:00Z','exact','x7el-resume-a','manual','operator_asserted',jsonb_build_object('listing_id','a','channel','shop'),user_id),
 (origin2,o,'acquisition',1,'unique_item',item2::text,'2026-01-01 00:00Z','exact','x7el-origin2','manual','operator_asserted',jsonb_build_object('acquisition_id','a2'),user_id),
 (disposal_event,o,'fulfillment',1,'unique_item',item2::text,'2026-01-08 00:00Z','exact','x7el-disposal2','manual','operator_asserted',jsonb_build_object('fulfillment_id','f2'),user_id),
 (origin3,o,'acquisition',1,'unique_item',item3::text,'2026-01-01 00:00Z','date','x7el-origin3','manual','operator_asserted',jsonb_build_object('acquisition_id','a3'),user_id),
 (gen_random_uuid(),o,'listing_published',1,'unique_item',item3::text,'2026-01-03 00:00Z','exact','x7el-pub-3','manual','operator_asserted',jsonb_build_object('listing_id','date-origin','channel','shop'),user_id),
 (origin4,o,'acquisition',1,'unique_item',item4::text,'2026-01-01 00:00Z','exact','x7el-origin4','manual','operator_asserted',jsonb_build_object('acquisition_id','a4'),user_id),
 (receipt4,o,'receipt',1,'unique_item',item4::text,'2026-01-02 00:00Z','exact','x7el-receipt4','manual','operator_asserted',jsonb_build_object('receipt_id','r4'),user_id),
 (gen_random_uuid(),o,'listing_published',1,'unique_item',item4::text,'2026-01-03 00:00Z','exact','x7el-pub-4','manual','operator_asserted',jsonb_build_object('listing_id','native-4','channel','shop'),user_id),
 (origin5,o,'acquisition',1,'unique_item',item5::text,'2026-01-01 00:00Z','exact','x7el-origin5','manual','operator_asserted',jsonb_build_object('acquisition_id','a5'),user_id),
 (gen_random_uuid(),o,'sale_committed',1,'unique_item',item5::text,'2026-01-08 00:00Z','exact','x7el-provisional5','manual','operator_asserted',jsonb_build_object('sale_id','s5'),user_id),
 (origin6,o,'acquisition',1,'unique_item',item6::text,'2026-01-01 00:00Z','exact','x7el-origin6','manual','operator_asserted',jsonb_build_object('acquisition_id','a6'),user_id),
 (gen_random_uuid(),o,'listing_published',1,'unique_item',item6::text,'2026-01-03 00:00Z','exact','x7el-pub-6','manual','operator_asserted',jsonb_build_object('listing_id','native-date','channel','shop'),user_id);
 set local session_replication_role=replica;
 update public.e10_commercial_events set correlation_id='purchase-4'where organization_id=o and id=origin4;
 update public.e10_commercial_events set correlation_id='purchase-4'where organization_id=o and idempotency_key='x7el-receipt4';
 insert into public.e10_commercial_events(organization_id,event_type,event_schema_version,subject_type,subject_id,occurred_at,occurred_at_precision,idempotency_key,source_kind,evidence_quality,payload,created_by)values
 (o,'acquisition',1,'unique_item',item2::text,null,'unknown','x7el-unknown-time','manual','operator_asserted',jsonb_build_object('acquisition_id','unknown'),user_id),
 (o,'acquisition',1,'unique_item','not-a-uuid','2026-01-02','exact','x7el-ambiguous-id','manual','operator_asserted',jsonb_build_object('acquisition_id','ambiguous'),user_id),
 (o,'acquisition',1,'unique_item',item7::text,'2026-01-01','exact','x7el-ambiguous-correlation-a','manual','operator_asserted',jsonb_build_object('acquisition_id','ambiguous-a'),user_id),
 (o,'acquisition',1,'unique_item',item7::text,'2026-01-02','exact','x7el-ambiguous-correlation-b','manual','operator_asserted',jsonb_build_object('acquisition_id','ambiguous-b'),user_id);
 update public.e10_commercial_events set correlation_id='ambiguous-purchase-7'where organization_id=o and idempotency_key in('x7el-ambiguous-correlation-a','x7el-ambiguous-correlation-b');
 set local session_replication_role=replica;
 insert into public.e10_market_observations(id,organization_id,observation_kind,unique_item_id,occurred_at,currency,amount,quantity,source_kind,source_reference,raw_payload_snapshot)values
 (sale_obs,o,'completed_sale',item1,'2026-01-09 00:00Z','USD',150,1,'manual','local-sale','{}'),
 (external_obs,o,'completed_sale',item2,'2026-01-05 00:00Z','USD',200,1,'manual','external-comp','{}');
 insert into public.e10_customer_transactions(id,organization_id,currency,occurred_at,occurred_at_precision,source_draft_id,source_draft_revision,commercial_event_id,posted_by,posted_at)values
 (tx_id,o,'USD','2026-01-09 00:00Z','date',gen_random_uuid(),1,gen_random_uuid(),user_id,'2026-01-09 00:01Z'),
 (tx2,o,'USD','2026-01-08 00:00Z','exact',gen_random_uuid(),1,gen_random_uuid(),user_id,'2026-01-08 00:01Z'),
 (tx3,o,'USD','2026-01-20 00:00Z','exact',gen_random_uuid(),1,gen_random_uuid(),user_id,'2026-01-20 00:01Z');
 insert into public.e10_customer_transactions(id,organization_id,currency,occurred_at,occurred_at_precision,source_draft_id,source_draft_revision,commercial_event_id,posted_by,posted_at)values(tx4,o,'USD','2026-01-09 00:00Z','date',gen_random_uuid(),1,gen_random_uuid(),user_id,'2026-01-09 00:02Z');
 insert into public.e10_customer_transaction_lines(organization_id,transaction_id,line_no,purchase_kind,capture_source,source_line_id,unique_item_id,quantity,merchandise_gross,merchandise_discount,shipping_amount,tax_amount,raw_evidence)values
 (o,tx_id,1,'retail','native','x7el-native-line',item4,1,200,0,0,0,'{}'),
 (o,tx2,1,'retail','native','x7el-native-conflict-1',item5,1,200,0,0,0,'{}'),
 (o,tx3,1,'retail','native','x7el-native-conflict-2',item5,1,210,0,0,0,'{}');
 insert into public.e10_customer_transaction_lines(id,organization_id,transaction_id,line_no,purchase_kind,capture_source,source_line_id,unique_item_id,quantity,merchandise_gross,merchandise_discount,shipping_amount,tax_amount,raw_evidence)values(line6,o,tx4,1,'retail','native','x7el-native-date',item6,1,220,0,0,0,'{}');
 set local session_replication_role=origin;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',user_id,'role','authenticated')::text,true);set local role authenticated;
 perform public.e10_org_review_inventory_evidence(o,'disposition_link',null,0,'assert',jsonb_build_object('unique_item_id',item1,'origin_event_id',origin1,'disposition_kind','sale','disposed_at','2026-01-09T00:00:00Z','disposed_at_precision','exact','market_observation_id',sale_obs,'evidence',jsonb_build_object('local_shop_sale',true)),'local sale','x7el-disposition');
 perform public.e10_org_review_inventory_evidence(o,'disposition_link',null,0,'assert',jsonb_build_object('unique_item_id',item4,'origin_event_id',receipt4,'disposition_kind','sale','disposed_at','2026-01-09T00:00:00Z','disposed_at_precision','date','customer_transaction_id',tx_id,'evidence',jsonb_build_object('correlated_receipt',true)),'correlated receipt sale','x7el-receipt-disposition');
 j:=public.e10_org_inventory_lifecycle(o,'2026-01-10 00:00Z',item1,100,null);
 if j#>>'{items,0,origin_kind}'<>'receipt'or(j#>>'{items,0,inventory_age_seconds}')::numeric<>691200 or(j#>>'{items,0,intake_delay_seconds}')::numeric<>172800 or(j#>>'{items,0,first_list_to_end_seconds}')::numeric<>518400 or(j#>>'{items,0,active_exposure_seconds}')::numeric<>345600 then raise exception'X7e lifecycle arithmetic %',j;end if;
 j:=public.e10_org_inventory_lifecycle(o,'2026-01-10 00:00Z',item2,100,null);if(j#>>'{items,0,censored}')::boolean is not true or j#>>'{items,0,disposition_link_id}'is not null then raise exception'external comp closed ownership %',j;end if;
 begin perform public.e10_org_review_inventory_evidence(o,'disposition_link',null,0,'assert',jsonb_build_object('unique_item_id',item2,'origin_event_id',origin2,'disposition_kind','disposal','disposed_at','2026-01-08T00:00:00Z','disposed_at_precision','date','commercial_event_id',disposal_event),'wrong precision','x7el-disposal-wrong');raise exception'wrong disposal precision accepted';exception when check_violation then null;end;
 perform public.e10_org_review_inventory_evidence(o,'disposition_link',null,0,'assert',jsonb_build_object('unique_item_id',item2,'origin_event_id',origin2,'disposition_kind','disposal','disposed_at','2026-01-08T00:00:00Z','disposed_at_precision','exact','commercial_event_id',disposal_event),'reviewed disposal','x7el-disposal');
 j:=public.e10_org_inventory_lifecycle(o,'2026-01-10 00:00Z',item2,100,null);if j#>>'{items,0,disposition_kind}'<>'disposal'or(j#>>'{items,0,censored}')::boolean then raise exception'reviewed disposal did not close %',j;end if;
 j:=public.e10_org_inventory_lifecycle(o,'2026-01-10 00:00Z',item3,100,null);if j#>>'{items,0,availability}'<>'precision_unavailable'or j#>>'{items,0,inventory_age_seconds}'is not null or j#>>'{items,0,active_exposure_seconds}'is not null then raise exception'date precision claimed duration %',j;end if;
 j:=public.e10_org_inventory_lifecycle(o,'2026-01-10 00:00Z',item4,100,null);if jsonb_array_length(j->'items')<>1 or j#>>'{items,0,origin_event_id}'<>origin4::text or j#>>'{items,0,received_at}'is null or j#>>'{items,0,disposition_source_basis}'<>'reviewed_link'or(j#>>'{items,0,censored}')::boolean or j#>>'{items,0,availability}'<>'precision_unavailable'or j#>>'{items,0,first_list_to_end_seconds}'is not null or j#>>'{items,0,active_exposure_seconds}'is not null then raise exception'native sale or correlated receipt episode invalid %',j;end if;
 j:=public.e10_org_inventory_lifecycle(o,'2026-01-10 00:00Z',item5,100,null);if j#>>'{items,0,disposition_source_basis}'<>'trusted_posted_transaction'or(j#>>'{items,0,finality_conflict}')::boolean then raise exception'future native sale suppressed valid cutoff finality %',j;end if;
 j:=public.e10_org_inventory_lifecycle(o,'2026-01-21 00:00Z',item5,100,null);if j#>>'{items,0,availability}'<>'finality_conflict'or(j#>>'{items,0,finality_conflict}')::boolean is not true or j#>>'{items,0,inventory_age_seconds}'is not null then raise exception'native finality conflict reported as ordinary holding %',j;end if;
 j:=public.e10_org_inventory_lifecycle(o,'2026-01-10 00:00Z',item6,100,null);if j#>>'{items,0,disposition_source_basis}'<>'trusted_posted_transaction'or j#>>'{items,0,availability}'<>'precision_unavailable'or j#>>'{items,0,first_list_to_end_seconds}'is not null then raise exception'independent date-precision native finality invalid %',j;end if;
 reset role;set local session_replication_role=replica;
 insert into public.e10_customer_transaction_adjustments(id,organization_id,transaction_id,transaction_line_id,adjustment_kind,currency,merchandise_amount,occurred_at,occurred_at_precision,reason,commercial_event_id,created_by,effect,source_kind,source_event_id,source_component_id,evidence,idempotency_key,request_fingerprint)values(cancel6,o,tx4,line6,'cancellation','USD',220,'2026-01-10','exact','cancel',gen_random_uuid(),user_id,'decrease','manual','cancel-6','whole','{}','x7el-cancel-6','fp');
 set local session_replication_role=origin;set local role authenticated;
 x8ctx:=(public.e10_org_create_query_context(o,'workspace',600,'x8-x7e1')->>'context_id')::uuid;bs:=pg_temp.x8_business_state();j:=public.e10_org_typed_query(o,x8ctx,'inventory.lifecycle',jsonb_build_object('as_of','2026-01-10T00:00:00Z','unique_item_id',item1,'limit',100));if pg_temp.x8_business_state()is distinct from bs then raise exception'X8 lifecycle changed business data';end if;perform pg_temp.x8_assert_envelope(j,'inventory.lifecycle','unique_item_ownership_episode');if j#>>'{result,items,0,unique_item_id}'<>item1::text then raise exception'X8 lifecycle dispatch %',j;end if;
 j:=public.e10_org_inventory_lifecycle(o,'2026-01-10 00:00Z',item6,100,null);if(j#>>'{items,0,censored}')::boolean is not true then raise exception'cancelled native line still closed %',j;end if;
 reset role;set local session_replication_role=replica;
 insert into public.e10_customer_transaction_adjustments(organization_id,transaction_id,transaction_line_id,adjustment_kind,currency,merchandise_amount,occurred_at,occurred_at_precision,reason,commercial_event_id,created_by,effect,source_kind,source_event_id,source_component_id,reinstates_cancellation_id,evidence,idempotency_key,request_fingerprint)values(o,tx4,line6,'correction','USD',220,'2026-01-10','exact','reinstate',gen_random_uuid(),user_id,'increase','manual','reinstate-6','whole',cancel6,'{}','x7el-reinstate-6','fp');
 set local session_replication_role=origin;set local role authenticated;
 j:=public.e10_org_inventory_lifecycle(o,'2026-01-10 00:00Z',item6,100,null);if j#>>'{items,0,disposition_source_basis}'<>'trusted_posted_transaction'then raise exception'reinstated native line did not restore finality %',j;end if;
 reset role;set local session_replication_role=replica;
 insert into public.e10_market_observations(id,organization_id,observation_kind,unique_item_id,occurred_at,currency,amount,quantity,source_kind,source_reference,raw_payload_snapshot)values(replacement_obs,o,'completed_sale',item1,'2026-01-09 00:00Z','USD',151,1,'manual','corrected-sale','{}');
 insert into public.e10_market_observation_supersessions(organization_id,superseded_observation_id,replacement_observation_id,lineage_kind,correction_reason,idempotency_key,request_fingerprint,created_by)values(o,sale_obs,replacement_obs,'manual_correction','correct sale','x7el-correct-sale','fp',user_id);
 set local session_replication_role=origin;set local role authenticated;
 j:=public.e10_org_inventory_lifecycle(o,'2026-01-10 00:00Z',item1,100,null);if(j#>>'{items,0,censored}')::boolean is not true then raise exception'superseded disposition source still closed ownership %',j;end if;
 j:=public.e10_org_inventory_lifecycle(o,'2026-01-10 00:00Z',null,1,null);cursor_value:=j->>'next_cursor';if(j->>'total_count')::int<>6 or(j#>>'{exclusions,missing_occurrence_count}')::int<>1 or(j#>>'{exclusions,ambiguous_identity_count}')::int<>1 or(j#>>'{exclusions,ambiguous_episode_correlation_count}')::int<>2 or jsonb_array_length(j->'items')<>1 or cursor_value is null then raise exception'bounded page one invalid %',j;end if;
 j2:=public.e10_org_inventory_lifecycle(o,'2026-01-10 00:00Z',null,1,cursor_value);if(j2->>'total_count')::int<>6 or jsonb_array_length(j2->'items')<>1 then raise exception'bounded page two invalid %',j2;end if;
 begin perform public.e10_org_inventory_lifecycle(o,'2026-01-10',null,1,cursor_value||'x');raise exception'tampered cursor accepted';exception when invalid_parameter_value then null;end;
 reset role;
end $$;
rollback;
select'TA-X7e.1 inventory lifecycle PASS'as result;
