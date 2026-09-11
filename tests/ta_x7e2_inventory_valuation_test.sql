\set ON_ERROR_STOP on
begin;
do $$
declare o uuid:=gen_random_uuid();user_id uuid:=gen_random_uuid();role_id uuid:=gen_random_uuid();release_id uuid:=gen_random_uuid();variant_id uuid:=gen_random_uuid();item1 uuid:=gen_random_uuid();item2 uuid:=gen_random_uuid();origin1 uuid:=gen_random_uuid();origin2 uuid:=gen_random_uuid();cost_obs uuid:=gen_random_uuid();j jsonb;j2 jsonb;itemj jsonb;cursor_value text;
begin
 insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at)values(user_id,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','x7ev-'||user_id||'@x.invalid',now(),now());
 insert into public.e10_organizations(id,slug,name)values(o,'x7ev-'||substr(o::text,1,8),'X7e valuation');insert into public.e10_organization_roles(id,organization_id,key,name,is_system)values(role_id,o,'x7ev','X7e valuation',false);insert into public.e10_organization_memberships(organization_id,user_id,role_id,status)values(o,user_id,role_id,'active');insert into public.e10_organization_role_permissions(organization_id,role_id,capability,allowed)values(o,role_id,'act.view_market_analytics',true);
 insert into public.e10_catalog_releases(id,release_name)values(release_id,'X7e valuation');insert into public.e10_catalog_variants(id,release_id)values(variant_id,release_id);insert into public.e10_unique_items(id,organization_id,catalog_variant_id,item_kind)values(item1,o,variant_id,'card'),(item2,o,variant_id,'card');
 insert into public.e10_commercial_events(id,organization_id,event_type,event_schema_version,subject_type,subject_id,occurred_at,occurred_at_precision,idempotency_key,source_kind,evidence_quality,payload,created_by)values
 (origin1,o,'acquisition',1,'unique_item',item1::text,'2026-01-01','exact','x7ev-origin1','manual','operator_asserted',jsonb_build_object('acquisition_id','a1'),user_id),
 (origin2,o,'acquisition',1,'unique_item',item2::text,'2026-01-05','exact','x7ev-origin2','manual','operator_asserted',jsonb_build_object('acquisition_id','a2'),user_id);
 insert into public.e10_unique_item_grade_assessments(organization_id,assessment_key,unique_item_id,revision,action,condition_state,grader_code,grade_label,assessed_at,assessed_at_precision,source_kind,method,method_version,review_status,reason,evidence,idempotency_key,request_fingerprint,reviewed_by)values
 (o,gen_random_uuid(),item1,1,'assert','graded','PSA','9','2026-01-02','exact','manual','cert','1','reviewed','PSA 9','{}','x7ev-grade9','fp',user_id),
 (o,gen_random_uuid(),item1,1,'assert','graded','PSA','10','2026-01-05','exact','manual','cert','1','reviewed','regrade PSA 10','{}','x7ev-grade10','fp',user_id),
 (o,gen_random_uuid(),item2,1,'assert','raw',null,null,'2026-01-05','exact','manual','condition','1','reviewed','raw','{}','x7ev-grade-raw','fp',user_id);
 insert into public.e10_valuation_evidence(organization_id,evidence_key,revision,action,unique_item_id,condition_state,grader_code,grade_label,method,method_version,currency,amount,observed_at,observed_at_precision,source_kind,review_status,reason,input_evidence,idempotency_key,request_fingerprint,reviewed_by)values
 (o,gen_random_uuid(),1,'assert',item1,'graded','PSA','9','local-index','1','USD',100,'2026-01-03','exact','manual','reviewed','opening','{}','x7ev-val9','fp',user_id),
 (o,gen_random_uuid(),1,'assert',item1,'graded','PSA','10','local-index','1','USD',120,'2026-01-06','exact','manual','reviewed','closing','{}','x7ev-val10','fp',user_id),
 (o,gen_random_uuid(),1,'assert',item1,'raw',null,null,'local-index','1','USD',999,'2026-01-06','exact','manual','reviewed','wrong condition','{}','x7ev-valraw-wrong','fp',user_id),
 (o,gen_random_uuid(),1,'assert',item2,'raw',null,null,'local-index','1','USD',50,'2026-01-06','exact','manual','reviewed','new holding','{}','x7ev-val2','fp',user_id);
 insert into public.e10_catalog_population_snapshots(organization_id,snapshot_key,catalog_variant_id,revision,action,condition_state,grader_code,grade_label,population_count,population_scope,observed_at,observed_at_precision,source_kind,method,method_version,review_status,reason,evidence,idempotency_key,request_fingerprint,reviewed_by)values
 (o,gen_random_uuid(),variant_id,1,'assert','graded','PSA','10',23,'grader-total','2026-01-06','exact','manual','population','1','reviewed','population','{}','x7ev-pop10','fp',user_id);
 set local session_replication_role=replica;insert into public.e10_market_observations(id,organization_id,observation_kind,unique_item_id,occurred_at,currency,amount,quantity,source_kind,source_reference,raw_payload_snapshot)values(cost_obs,o,'acquisition_cost',item1,'2026-01-01','USD',80,1,'manual','cost','{}');set local session_replication_role=origin;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',user_id,'role','authenticated')::text,true);set local role authenticated;
 j:=public.e10_org_inventory_valuation_coverage(o,'local-index','1','USD','2026-01-07','2026-01-04',365,1,null);
 if(j#>>'{summary,closing_holding_count}')::int<>2 or(j#>>'{summary,closing_value}')::numeric<>170 or(j#>>'{summary,market_movement}')is not null or(j#>>'{summary,comparable_count}')::int<>0 or(j#>>'{summary,uncomparable_count}')::int<>1 or(j#>>'{summary,acquisition_count}')::int<>1 or(j#>>'{summary,acquisition_endpoint_value}')::numeric<>50 or(j#>>'{summary,actual_cost_access}')<>'not_authorized'then raise exception'X7e valuation summary %',j;end if;
 select value into itemj from jsonb_array_elements(j->'items')where value->>'unique_item_id'=item1::text;
 if(itemj->>'actual_cost')is not null or(itemj->>'value')::numeric<>120 or(itemj->>'population_count')::int<>23 or(itemj->>'uncomparable_reason')<>'applicability_changed'then raise exception'grade-aware closing selection %',j;end if;
 cursor_value:=j->>'next_cursor';if cursor_value is null or jsonb_array_length(j->'items')<>1 then raise exception'valuation pagination missing %',j;end if;
 j2:=public.e10_org_inventory_valuation_coverage(o,'local-index','1','USD','2026-01-07','2026-01-04',365,1,cursor_value);if(j2#>>'{summary,closing_value}')::numeric<>170 or jsonb_array_length(j2->'items')<>1 then raise exception'valuation page two totals changed %',j2;end if;
 j:=public.e10_org_unique_item_evidence(o,item1,'2026-01-08',1,null);if(j->>'total_count')::int<4 or jsonb_array_length(j->'items')<>1 or j->>'next_cursor'is null then raise exception'evidence bounded read %',j;end if;
 reset role;insert into public.e10_organization_role_permissions(organization_id,role_id,capability,allowed)values(o,role_id,'financial.actual_cost.read',true);set local role authenticated;
 j:=public.e10_org_inventory_valuation_coverage(o,'local-index','1','USD','2026-01-07','2026-01-04',365,100,null);select value into itemj from jsonb_array_elements(j->'items')where value->>'unique_item_id'=item1::text;if j#>>'{summary,actual_cost_access}'<>'authorized'or(itemj->>'actual_cost')::numeric<>80 then raise exception'actual cost permission boundary %',j;end if;
 reset role;
 create temporary table x7e_bulk(item_id uuid primary key,n integer)on commit drop;
 insert into x7e_bulk select gen_random_uuid(),g from generate_series(1,201)g;
 insert into public.e10_unique_items(id,organization_id,catalog_variant_id,item_kind)select item_id,o,variant_id,'card'from x7e_bulk;
 insert into public.e10_commercial_events(organization_id,event_type,event_schema_version,subject_type,subject_id,occurred_at,occurred_at_precision,idempotency_key,source_kind,evidence_quality,payload,created_by)
 select o,'acquisition',1,'unique_item',item_id::text,'2026-01-05','exact','x7ev-bulk-origin-'||n,'manual','operator_asserted',jsonb_build_object('acquisition_id','bulk-'||n),user_id from x7e_bulk;
 insert into public.e10_unique_item_grade_assessments(organization_id,assessment_key,unique_item_id,revision,action,condition_state,assessed_at,assessed_at_precision,source_kind,method,method_version,review_status,reason,evidence,idempotency_key,request_fingerprint,reviewed_by)
 select o,gen_random_uuid(),item_id,1,'assert','raw','2026-01-05','exact','manual','condition','1','reviewed','bulk raw','{}','x7ev-bulk-grade-'||n,'fp',user_id from x7e_bulk;
 insert into public.e10_valuation_evidence(organization_id,evidence_key,revision,action,unique_item_id,condition_state,method,method_version,currency,amount,observed_at,observed_at_precision,source_kind,review_status,reason,input_evidence,idempotency_key,request_fingerprint,reviewed_by)
 select o,gen_random_uuid(),1,'assert',item_id,'raw','local-index','1','USD',1,'2026-01-06','exact','manual','reviewed','bulk value','{}','x7ev-bulk-value-'||n,'fp',user_id from x7e_bulk;
 set local role authenticated;
 j:=public.e10_org_inventory_valuation_coverage(o,'local-index','1','USD','2026-01-07',null,365,200,null);
 if(j#>>'{summary,closing_holding_count}')::int<>203 or jsonb_array_length(j->'items')<>200 or j->>'next_cursor'is null then raise exception'full totals were paginated %',j;end if;
 reset role;
end $$;
rollback;
select'TA-X7e.2 inventory valuation PASS'as result;
