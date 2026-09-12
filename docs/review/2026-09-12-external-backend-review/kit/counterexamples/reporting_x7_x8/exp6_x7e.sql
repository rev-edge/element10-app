\set ON_ERROR_STOP 0
begin;
do $$
declare o uuid:=gen_random_uuid();o2 uuid:=gen_random_uuid();u uuid:=gen_random_uuid();u2 uuid:=gen_random_uuid();role1 uuid:=gen_random_uuid();role2 uuid:=gen_random_uuid();rel uuid:=gen_random_uuid();v1 uuid:=gen_random_uuid();items uuid[];it uuid;i int;
 j jsonb;j2 jsonb;cur text;tot int;totals int[]:='{}';excl jsonb[]:='{}';pages int:=0;seen uuid[]:='{}';parts text[];payload jsonb;tampered text;secret_fn text;n int;sums jsonb[]:='{}';
begin
 insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at)values(u,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','e6-'||u||'@x.invalid',now(),now()),(u2,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','e6-'||u2||'@x.invalid',now(),now());
 insert into public.e10_organizations(id,slug,name)values(o,'e6-'||substr(o::text,1,8),'E6'),(o2,'e6f-'||substr(o2::text,1,8),'E6 foreign');
 insert into public.e10_organization_roles(id,organization_id,key,name,is_system)values(role1,o,'e6','E6',false),(role2,o2,'e6','E6',false);
 insert into public.e10_organization_memberships(organization_id,user_id,role_id,status)values(o,u,role1,'active'),(o,u2,role1,'active'),(o2,u2,role2,'active');
 insert into public.e10_organization_role_permissions(organization_id,role_id,capability,allowed)values(o,role1,'act.view_market_analytics',true),(o2,role2,'act.view_market_analytics',true);
 insert into public.e10_catalog_releases(id,release_name)values(rel,'E6');insert into public.e10_catalog_variants(id,release_id)values(v1,rel);
 for i in 1..7 loop it:=gen_random_uuid();items:=array_append(items,it);insert into public.e10_unique_items(id,organization_id,catalog_variant_id,item_kind)values(it,o,v1,'card');
  insert into public.e10_commercial_events(id,organization_id,event_type,event_schema_version,subject_type,subject_id,occurred_at,occurred_at_precision,idempotency_key,source_kind,evidence_quality,payload,created_by)values
  (gen_random_uuid(),o,'acquisition',1,'unique_item',it::text,'2026-01-01 00:00Z','exact','e6-acq-'||i,'manual','operator_asserted',jsonb_build_object('acquisition_id','a'||i),u),
  (gen_random_uuid(),o,'listing_published',1,'unique_item',it::text,'2026-01-03 00:00Z','exact','e6-pub-'||i,'manual','operator_asserted',jsonb_build_object('listing_id','l'||i,'channel','shop'),u);
 end loop;
 -- one event with unknown precision to populate exclusions
 insert into public.e10_commercial_events(id,organization_id,event_type,event_schema_version,subject_type,subject_id,occurred_at,occurred_at_precision,idempotency_key,source_kind,evidence_quality,payload,created_by)values(gen_random_uuid(),o,'listing_paused',1,'unique_item',items[1]::text,null,'unknown','e6-unk','manual','operator_asserted',jsonb_build_object('listing_id','l1','channel','shop'),u);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated')::text,true);set local role authenticated;
 -- A. lifecycle: page size 2 over 7 episodes; totals/exclusions per page
 cur:=null;
 loop j:=public.e10_org_inventory_lifecycle(o,'2026-02-01',null,2,cur);pages:=pages+1;totals:=array_append(totals,(j->>'total_count')::int);excl:=array_append(excl,j->'exclusions');seen:=seen||array(select (x->>'unique_item_id')::uuid from jsonb_array_elements(j->'items')x);
  exit when j->>'next_cursor' is null;cur:=j->>'next_cursor';if pages>10 then raise exception 'loop';end if;end loop;
 raise notice 'A lifecycle pages=% totals per page=% distinct items=% exclusions page1=% all pages equal=%',pages,totals,cardinality(array(select distinct x from unnest(seen)x)),excl[1],(select bool_and(e=excl[1]) from unnest(excl)e);
 -- A2. cursor after the last page: build by requesting with a large limit? not available; instead re-run page 4 (last) and ensure next_cursor null
 -- B. cursor tampering
 j:=public.e10_org_inventory_lifecycle(o,'2026-02-01',null,2,null);cur:=j->>'next_cursor';parts:=string_to_array(cur,'.');payload:=convert_from(decode(parts[1],'base64'),'UTF8')::jsonb;
 raise notice 'B cursor payload keys=%',(select string_agg(k,',') from jsonb_object_keys(payload)k);
 tampered:=replace(encode(convert_to((payload||jsonb_build_object('unique_item_id',items[7]))::text,'UTF8'),'base64'),E'\n','')||'.'||parts[2];
 begin perform public.e10_org_inventory_lifecycle(o,'2026-02-01',null,2,tampered);raise notice 'FINDING B1: tampered payload accepted';exception when others then raise notice 'B1 tampered payload -> % %',sqlstate,sqlerrm;end;
 begin perform public.e10_org_inventory_lifecycle(o,'2026-02-01',null,2,parts[1]||'.'||repeat('0',64));raise notice 'FINDING B2: bad signature accepted';exception when others then raise notice 'B2 bad signature -> % %',sqlstate,sqlerrm;end;
 begin perform public.e10_org_inventory_lifecycle(o,'2026-02-01',null,2,'garbage');raise notice 'FINDING B3';exception when others then raise notice 'B3 garbage cursor -> % %',sqlstate,sqlerrm;end;
 begin perform public.e10_org_inventory_lifecycle(o,'2026-02-01',null,2,'!!!!.'||parts[2]);raise notice 'FINDING B4';exception when others then raise notice 'B4 non-base64 -> % %',sqlstate,sqlerrm;end;
 begin perform public.e10_org_inventory_lifecycle(o,'2026-02-01',null,3,cur);raise notice 'B5 cursor with different limit accepted (limit not in fingerprint; rows=%)',null;exception when others then raise notice 'B5 different limit -> % %',sqlstate,sqlerrm;end;
 begin perform public.e10_org_inventory_lifecycle(o,'2026-02-02',null,2,cur);raise notice 'FINDING B6: different as_of accepted';exception when others then raise notice 'B6 different as_of -> % %',sqlstate,sqlerrm;end;
 -- B7 other actor same org; B8 other org
 perform set_config('request.jwt.claims',jsonb_build_object('sub',u2,'role','authenticated')::text,true);
 begin perform public.e10_org_inventory_lifecycle(o,'2026-02-01',null,2,cur);raise notice 'FINDING B7: foreign actor cursor accepted';exception when others then raise notice 'B7 other actor -> % %',sqlstate,sqlerrm;end;
 begin perform public.e10_org_inventory_lifecycle(o2,'2026-02-01',null,2,cur);raise notice 'FINDING B8: other org cursor accepted';exception when others then raise notice 'B8 other org -> % %',sqlstate,sqlerrm;end;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated')::text,true);
 -- B9 revision change
 reset role;insert into public.e10_commercial_events(id,organization_id,event_type,event_schema_version,subject_type,subject_id,occurred_at,occurred_at_precision,idempotency_key,source_kind,evidence_quality,payload,created_by)values(gen_random_uuid(),o,'listing_paused',1,'unique_item',items[2]::text,'2026-01-06 00:00Z','exact','e6-bump','manual','operator_asserted',jsonb_build_object('listing_id','l2','channel','shop'),u);set local role authenticated;
 begin perform public.e10_org_inventory_lifecycle(o,'2026-02-01',null,2,cur);raise notice 'FINDING B9: stale revision cursor accepted';exception when others then raise notice 'B9 revision changed -> % %',sqlstate,sqlerrm;end;
 -- C. unique item evidence: foreign item, foreign org
 begin perform public.e10_org_unique_item_evidence(o2,items[1],'2026-02-01',10,null);raise notice 'FINDING C1';exception when others then raise notice 'C1 evidence via other org -> % %',sqlstate,sqlerrm;end;
 j:=public.e10_org_unique_item_evidence(o,items[1],'2026-02-01',10,null);raise notice 'C2 evidence total=% items=%',j->>'total_count',jsonb_array_length(j->'items');
 -- D. valuation coverage: summary consistent across pages, no evidence -> unvalued
 cur:=null;pages:=0;
 loop j:=public.e10_org_inventory_valuation_coverage(o,'m','1','USD','2026-02-01',null,365,3,cur);pages:=pages+1;sums:=array_append(sums,j->'summary');exit when j->>'next_cursor' is null;cur:=j->>'next_cursor';if pages>10 then raise exception 'loop';end if;end loop;
 raise notice 'D valuation pages=% summary equal across pages=% summary=%',pages,(select bool_and(s=sums[1]) from unnest(sums)s),sums[1];
 -- D2: actual_cost_access without financial cap
 raise notice 'D2 actual_cost_access=%',sums[1]->>'actual_cost_access';
 -- E. secret exposure
 reset role;
 select string_agg(p.oid::regprocedure::text,', ') into secret_fn from pg_proc p where p.prosrc ilike '%e10_inventory_cursor_secrets%' and has_function_privilege('authenticated',p.oid,'execute');
 raise notice 'E functions touching secrets executable by authenticated: %',coalesce(secret_fn,'(none)');
 raise notice 'E authenticated select on secrets=% ; anon=% ; service_role=%',has_table_privilege('authenticated','public.e10_inventory_cursor_secrets','select'),has_table_privilege('anon','public.e10_inventory_cursor_secrets','select'),has_table_privilege('service_role','public.e10_inventory_cursor_secrets','select');
 raise notice 'E secret-table policies=%',(select count(*) from pg_policies where tablename='e10_inventory_cursor_secrets');
end $$;
rollback;
