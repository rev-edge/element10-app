\set ON_ERROR_STOP on
begin;
do $$
declare o uuid:=gen_random_uuid();user_id uuid:=gen_random_uuid();role_id uuid:=gen_random_uuid();release_id uuid:=gen_random_uuid();variant_id uuid:=gen_random_uuid();item1 uuid:=gen_random_uuid();item2 uuid:=gen_random_uuid();item3 uuid:=gen_random_uuid();origin1 uuid:=gen_random_uuid();origin2 uuid:=gen_random_uuid();origin3 uuid:=gen_random_uuid();sale_obs uuid:=gen_random_uuid();external_obs uuid:=gen_random_uuid();j jsonb;j2 jsonb;cursor_value text;
begin
 insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at)values(user_id,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','x7el-'||user_id||'@x.invalid',now(),now());
 insert into public.e10_organizations(id,slug,name)values(o,'x7el-'||substr(o::text,1,8),'X7e lifecycle');
 insert into public.e10_organization_roles(id,organization_id,key,name,is_system)values(role_id,o,'x7el','X7e lifecycle',false);
 insert into public.e10_organization_memberships(organization_id,user_id,role_id,status)values(o,user_id,role_id,'active');
 insert into public.e10_organization_role_permissions(organization_id,role_id,capability,allowed)values(o,role_id,'act.view_market_analytics',true),(o,role_id,'act.curate_market_analytics',true);
 insert into public.e10_catalog_releases(id,release_name)values(release_id,'X7e lifecycle');insert into public.e10_catalog_variants(id,release_id)values(variant_id,release_id);
 insert into public.e10_unique_items(id,organization_id,catalog_variant_id,item_kind)values(item1,o,variant_id,'card'),(item2,o,variant_id,'card'),(item3,o,variant_id,'card');

 insert into public.e10_commercial_events(id,organization_id,event_type,event_schema_version,subject_type,subject_id,occurred_at,occurred_at_precision,idempotency_key,source_kind,evidence_quality,payload,created_by)values
 (origin1,o,'receipt',1,'unique_item',item1::text,'2026-01-01 00:00Z','exact','x7el-origin1','manual','operator_asserted',jsonb_build_object('receipt_id','r1'),user_id),
 (gen_random_uuid(),o,'listing_published',1,'unique_item',item1::text,'2026-01-03 00:00Z','exact','x7el-pub-a','manual','operator_asserted',jsonb_build_object('listing_id','a','channel','shop'),user_id),
 (gen_random_uuid(),o,'listing_published',1,'unique_item',item1::text,'2026-01-03 12:00Z','exact','x7el-pub-b','manual','operator_asserted',jsonb_build_object('listing_id','b','channel','market'),user_id),
 (gen_random_uuid(),o,'listing_paused',1,'unique_item',item1::text,'2026-01-03 18:00Z','exact','x7el-pause-b','manual','operator_asserted',jsonb_build_object('listing_id','b','channel','market'),user_id),
 (gen_random_uuid(),o,'listing_paused',1,'unique_item',item1::text,'2026-01-04 00:00Z','exact','x7el-pause-a','manual','operator_asserted',jsonb_build_object('listing_id','a','channel','shop'),user_id),
 (gen_random_uuid(),o,'listing_resumed',1,'unique_item',item1::text,'2026-01-06 00:00Z','exact','x7el-resume-a','manual','operator_asserted',jsonb_build_object('listing_id','a','channel','shop'),user_id),
 (origin2,o,'acquisition',1,'unique_item',item2::text,'2026-01-01 00:00Z','exact','x7el-origin2','manual','operator_asserted',jsonb_build_object('acquisition_id','a2'),user_id),
 (origin3,o,'acquisition',1,'unique_item',item3::text,'2026-01-01 00:00Z','date','x7el-origin3','manual','operator_asserted',jsonb_build_object('acquisition_id','a3'),user_id);
 set local session_replication_role=replica;
 insert into public.e10_market_observations(id,organization_id,observation_kind,unique_item_id,occurred_at,currency,amount,quantity,source_kind,source_reference,raw_payload_snapshot)values
 (sale_obs,o,'completed_sale',item1,'2026-01-09 00:00Z','USD',150,1,'manual','local-sale','{}'),
 (external_obs,o,'completed_sale',item2,'2026-01-05 00:00Z','USD',200,1,'manual','external-comp','{}');
 set local session_replication_role=origin;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',user_id,'role','authenticated')::text,true);set local role authenticated;
 perform public.e10_org_review_inventory_evidence(o,'disposition_link',null,0,'assert',jsonb_build_object('unique_item_id',item1,'origin_event_id',origin1,'disposition_kind','sale','disposed_at','2026-01-09T00:00:00Z','disposed_at_precision','exact','market_observation_id',sale_obs,'evidence',jsonb_build_object('local_shop_sale',true)),'local sale','x7el-disposition');
 j:=public.e10_org_inventory_lifecycle(o,'2026-01-10 00:00Z',item1,100,null);
 if j#>>'{items,0,origin_kind}'<>'receipt'or(j#>>'{items,0,inventory_age_seconds}')::numeric<>691200 or(j#>>'{items,0,intake_delay_seconds}')::numeric<>172800 or(j#>>'{items,0,first_list_to_end_seconds}')::numeric<>518400 or(j#>>'{items,0,active_exposure_seconds}')::numeric<>345600 then raise exception'X7e lifecycle arithmetic %',j;end if;
 j:=public.e10_org_inventory_lifecycle(o,'2026-01-10 00:00Z',item2,100,null);if(j#>>'{items,0,censored}')::boolean is not true or j#>>'{items,0,disposition_link_id}'is not null then raise exception'external comp closed ownership %',j;end if;
 j:=public.e10_org_inventory_lifecycle(o,'2026-01-10 00:00Z',item3,100,null);if j#>>'{items,0,availability}'<>'precision_unavailable'or j#>>'{items,0,inventory_age_seconds}'is not null then raise exception'date precision claimed duration %',j;end if;
 j:=public.e10_org_inventory_lifecycle(o,'2026-01-10 00:00Z',null,1,null);cursor_value:=j->>'next_cursor';if(j->>'total_count')::int<>3 or jsonb_array_length(j->'items')<>1 or cursor_value is null then raise exception'bounded page one invalid %',j;end if;
 j2:=public.e10_org_inventory_lifecycle(o,'2026-01-10 00:00Z',null,1,cursor_value);if(j2->>'total_count')::int<>3 or jsonb_array_length(j2->'items')<>1 then raise exception'bounded page two invalid %',j2;end if;
 begin perform public.e10_org_inventory_lifecycle(o,'2026-01-10',null,1,cursor_value||'x');raise exception'tampered cursor accepted';exception when invalid_parameter_value then null;end;
 reset role;
end $$;
rollback;
select'TA-X7e.1 inventory lifecycle PASS'as result;
