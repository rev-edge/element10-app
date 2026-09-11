\set ON_ERROR_STOP on
begin;
do $$
declare
 o uuid:=gen_random_uuid(); actor uuid:=gen_random_uuid(); role_id uuid:=gen_random_uuid();
 release_id uuid:=gen_random_uuid(); variant_id uuid:=gen_random_uuid();
 item_late uuid:=gen_random_uuid(); item_cutoff uuid:=gen_random_uuid(); item_overlap uuid:=gen_random_uuid();
 receipt_id uuid:=gen_random_uuid(); corrected_receipt_id uuid:=gen_random_uuid(); acquisition_id uuid:=gen_random_uuid(); fulfillment_id uuid:=gen_random_uuid();
 cutoff_origin uuid:=gen_random_uuid(); native_tx uuid:=gen_random_uuid(); reviewed_fulfillment uuid:=gen_random_uuid();
 overlap_a uuid:=gen_random_uuid(); overlap_b uuid:=gen_random_uuid(); disposition_key uuid; j jsonb; j2 jsonb;
begin
 insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at)values(actor,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','x7et-'||actor||'@x.invalid',now(),now());
 insert into public.e10_organizations(id,slug,name)values(o,'x7et-'||substr(o::text,1,8),'X7e temporal regression');
 insert into public.e10_organization_roles(id,organization_id,key,name)values(role_id,o,'x7et','X7e temporal regression');
 insert into public.e10_organization_memberships(organization_id,user_id,role_id,status)values(o,actor,role_id,'active');
 insert into public.e10_organization_role_permissions(organization_id,role_id,capability,allowed)values(o,role_id,'act.view_market_analytics',true),(o,role_id,'act.curate_market_analytics',true);
 insert into public.e10_catalog_releases(id,release_name)values(release_id,'X7e temporal regression');
 insert into public.e10_catalog_variants(id,release_id)values(variant_id,release_id);
 insert into public.e10_unique_items(id,organization_id,catalog_variant_id,item_kind)values(item_late,o,variant_id,'card'),(item_cutoff,o,variant_id,'card'),(item_overlap,o,variant_id,'card');

 insert into public.e10_commercial_events(id,organization_id,event_type,event_schema_version,subject_type,subject_id,occurred_at,occurred_at_precision,correlation_id,idempotency_key,source_kind,evidence_quality,payload,created_by)values
 (receipt_id,o,'receipt',1,'unique_item',item_late::text,'2026-01-02','exact','late-episode','x7et-receipt','manual','operator_asserted',jsonb_build_object('receipt_id','late-r'),actor),
 (fulfillment_id,o,'fulfillment',1,'unique_item',item_late::text,'2026-01-05','exact',null,'x7et-fulfillment','manual','operator_asserted',jsonb_build_object('fulfillment_id','late-f'),actor),
 (cutoff_origin,o,'acquisition',1,'unique_item',item_cutoff::text,'2026-01-01','exact',null,'x7et-cutoff-origin','manual','operator_asserted',jsonb_build_object('acquisition_id','cutoff-a'),actor),
 (reviewed_fulfillment,o,'fulfillment',1,'unique_item',item_cutoff::text,'2026-01-20','exact',null,'x7et-reviewed-finality','manual','operator_asserted',jsonb_build_object('fulfillment_id','cutoff-f'),actor),
 (overlap_a,o,'acquisition',1,'unique_item',item_overlap::text,'2026-01-01','exact',null,'x7et-overlap-a','manual','operator_asserted',jsonb_build_object('acquisition_id','overlap-a'),actor),
 (overlap_b,o,'acquisition',1,'unique_item',item_overlap::text,'2026-01-02','exact',null,'x7et-overlap-b','manual','operator_asserted',jsonb_build_object('acquisition_id','overlap-b'),actor);
 set local session_replication_role=replica;
 insert into public.e10_customer_transactions(id,organization_id,currency,occurred_at,occurred_at_precision,source_draft_id,source_draft_revision,commercial_event_id,posted_by,posted_at)values(native_tx,o,'USD','2026-01-09','exact',gen_random_uuid(),1,gen_random_uuid(),actor,'2026-01-09 00:01Z');
 insert into public.e10_customer_transaction_lines(organization_id,transaction_id,line_no,purchase_kind,capture_source,source_line_id,unique_item_id,quantity,merchandise_gross,merchandise_discount,shipping_amount,tax_amount,raw_evidence)values(o,native_tx,1,'retail','native','x7et-native',item_cutoff,1,100,0,0,0,'{}');
 set local session_replication_role=origin;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',actor,'role','authenticated')::text,true);set local role authenticated;

 j:=public.e10_org_review_inventory_evidence(o,'disposition_link',null,0,'assert',jsonb_build_object('unique_item_id',item_late,'origin_event_id',receipt_id,'disposition_kind','disposal','disposed_at','2026-01-05T00:00:00Z','disposed_at_precision','exact','commercial_event_id',fulfillment_id),'late episode disposal','x7et-late-disposal');
 disposition_key:=(j->>'evidence_key')::uuid;
 j:=public.e10_org_inventory_lifecycle(o,'2026-01-06',item_late,10,null);if j#>>'{items,0,disposition_kind}'<>'disposal'then raise exception'initial receipt disposal missing %',j;end if;
 reset role;
 insert into public.e10_commercial_events(id,organization_id,event_type,event_schema_version,subject_type,subject_id,occurred_at,occurred_at_precision,correlation_id,idempotency_key,source_kind,evidence_quality,payload,created_by)values(acquisition_id,o,'acquisition',1,'unique_item',item_late::text,'2026-01-01','exact','late-episode','x7et-late-acquisition','manual','operator_asserted',jsonb_build_object('acquisition_id','late-a'),actor);
 insert into public.e10_commercial_events(id,organization_id,event_type,event_schema_version,subject_type,subject_id,occurred_at,occurred_at_precision,correlation_id,corrects_event_id,idempotency_key,source_kind,evidence_quality,payload,created_by)values(corrected_receipt_id,o,'receipt',1,'unique_item',item_late::text,'2026-01-02','exact','late-episode',receipt_id,'x7et-corrected-receipt','manual','operator_asserted',jsonb_build_object('receipt_id','late-r-corrected'),actor);
 set local role authenticated;
 j:=public.e10_org_inventory_lifecycle(o,'2026-01-06',item_late,10,null);if j#>>'{items,0,origin_event_id}'<>acquisition_id::text or j#>>'{items,0,disposition_kind}'<>'disposal'or(j#>>'{items,0,censored}')::boolean then raise exception'late acquisition/correction detached finality %',j;end if;
 begin perform public.e10_org_review_inventory_evidence(o,'disposition_link',null,0,'assert',jsonb_build_object('unique_item_id',item_late,'origin_event_id',acquisition_id,'disposition_kind','disposal','disposed_at','2026-01-05T00:00:00Z','disposed_at_precision','exact','commercial_event_id',fulfillment_id),'duplicate late episode root','x7et-duplicate-root');raise exception'duplicate episode root accepted';exception when unique_violation then null;end;
 perform public.e10_org_review_inventory_evidence(o,'disposition_link',disposition_key,1,'revoke',jsonb_build_object('unique_item_id',item_late,'origin_event_id',receipt_id),'revoke corrected episode','x7et-revoke');
 j:=public.e10_org_inventory_lifecycle(o,'2026-01-06',item_late,10,null);if(j#>>'{items,0,censored}')::boolean is not true then raise exception'corrected episode could not be revoked %',j;end if;

 j:=public.e10_org_inventory_lifecycle(o,'2026-01-10',item_cutoff,10,null);if j#>>'{items,0,disposition_source_basis}'<>'trusted_posted_transaction'then raise exception'future reviewed finality erased early native finality %',j;end if;
 perform public.e10_org_review_inventory_evidence(o,'disposition_link',null,0,'assert',jsonb_build_object('unique_item_id',item_cutoff,'origin_event_id',cutoff_origin,'disposition_kind','disposal','disposed_at','2026-01-20T00:00:00Z','disposed_at_precision','exact','commercial_event_id',reviewed_fulfillment),'reviewed later finality','x7et-reviewed-link');
 j:=public.e10_org_inventory_lifecycle(o,'2026-01-10',item_cutoff,10,null);if j#>>'{items,0,disposition_source_basis}'<>'trusted_posted_transaction'then raise exception'future reviewed finality changed early cutoff %',j;end if;
 j:=public.e10_org_inventory_lifecycle(o,'2026-01-21',item_cutoff,10,null);if j#>>'{items,0,disposition_source_basis}'<>'reviewed_link'or(j#>>'{items,0,finality_conflict}')::boolean then raise exception'reviewed finality did not take cutoff-local precedence %',j;end if;
 j:=public.e10_org_inventory_valuation_coverage(o,'manual','1','USD','2026-01-10',null,365,10,null);if jsonb_path_exists(j,'$.items[*] ? (@.unique_item_id == $id)',jsonb_build_object('id',item_cutoff::text))then raise exception'early valuation treated sold item as holding %',j;end if;
 j:=public.e10_org_inventory_valuation_coverage(o,'manual','1','USD','2026-01-21',null,365,10,null);if jsonb_path_exists(j,'$.items[*] ? (@.unique_item_id == $id)',jsonb_build_object('id',item_cutoff::text))then raise exception'late valuation treated disposed item as holding %',j;end if;

 j:=public.e10_org_inventory_lifecycle(o,'2026-01-03',item_overlap,10,null);j2:=jsonb_path_query_first(j,'$.items[*] ? (@.origin_event_id == $id)',jsonb_build_object('id',overlap_a::text));if j2->>'availability'<>'episode_ambiguous'or(j2->>'overlapping_origin')::boolean is not true then raise exception'unclosed prior episode labeled available %',j;end if;
 reset role;
end $$;
rollback;
select'TA-X7e temporal episode/cutoff regressions PASS'as result;
