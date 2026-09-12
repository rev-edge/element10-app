\set ON_ERROR_STOP 0
begin;
do $$
declare o uuid:=gen_random_uuid();o2 uuid:=gen_random_uuid();u uuid:=gen_random_uuid();u2 uuid:=gen_random_uuid();role1 uuid:=gen_random_uuid();role2 uuid:=gen_random_uuid();rel uuid:=gen_random_uuid();
 vids uuid[];obs uuid[];res jsonb;res2 jsonb;cur uuid;fp text;i int;n int;ctx uuid;agg1 jsonb;agg2 jsonb;tot int:=0;keys text[]:='{}';
 v uuid;ob uuid;fake uuid:=gen_random_uuid();dctx uuid;dres jsonb;dcur uuid;ck text;
begin
 insert into auth.users(id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)values(u,'authenticated','authenticated','e1-u@x.invalid','',now(),'{}','{}',now(),now()),(u2,'authenticated','authenticated','e1-u2@x.invalid','',now(),'{}','{}',now(),now());
 insert into public.e10_organizations(id,slug,name)values(o,'e1-'||substr(o::text,1,8),'E1'),(o2,'e1f-'||substr(o2::text,1,8),'E1 foreign');
 insert into public.e10_organization_roles(id,organization_id,key,name)values(role1,o,'reader','Reader'),(role2,o2,'reader','Reader');
 insert into public.e10_organization_memberships(organization_id,user_id,role_id,status)values(o,u,role1,'active'),(o,u2,role1,'active'),(o2,u2,role2,'active');
 insert into public.e10_organization_role_permissions(organization_id,role_id,capability,allowed)values(o,role1,'act.view_market_analytics',true),(o2,role2,'act.view_market_analytics',true);
 insert into public.e10_catalog_releases(id,release_name,release_year,sport)values(rel,'E1 release',2026,'baseball');
 -- 7 variants; variants 1..5 get observations (variant k gets k observations), 6,7 have none; plus one observation with unknown target mapping
 for i in 1..7 loop v:=gen_random_uuid();vids:=array_append(vids,v);insert into public.e10_catalog_variants(id,release_id,card_number)values(v,rel,i::text);end loop;
 set local session_replication_role=replica;
 for i in 1..5 loop for n in 1..i loop ob:=gen_random_uuid();obs:=array_append(obs,ob);
  insert into public.e10_market_observations(id,organization_id,observation_kind,catalog_variant_id,occurred_at,currency,amount,quantity,source_kind,source_connection_id,source_reference,raw_payload_snapshot)values(ob,o,'completed_sale',vids[i],'2026-01-10'::timestamptz+(n||' days')::interval,'USD',10*i+n,1,'manual','one','ref','{}');
 end loop;end loop;
 set local session_replication_role=origin;
 foreach ob in array obs loop insert into public.e10_market_observation_fact_decisions(organization_id,decision_key,observation_id,revision,action,condition_state,transaction_quantity,amount_basis,reviewed_unit_amount,reason,evidence,idempotency_key,request_fingerprint)values(o,gen_random_uuid(),ob,1,'assert','raw',1,'unit_price',(select amount from public.e10_market_observations where id=ob),'x','{}','e1-'||ob,'fp');end loop;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated')::text,true);set local role authenticated;

 -- A. aggregation before pagination: page size 2 over 7 cohorts (grouping variant, metric count)
 cur:=null;i:=0;
 loop res:=public.e10_org_market_screener(o,'catalog','variant','count','completed_sale','2026-01-01','2026-02-01','2026-02-01',null,'none',null,null,'{}','observed_count_desc',2,cur);i:=i+1;
  if i=1 then agg1:=jsonb_build_object('unknown_counts',res->'unknown_counts','exclusion_counts',res->'exclusion_counts','coverage',res->'coverage_status');fp:=res->>'query_fingerprint';
  else agg2:=jsonb_build_object('unknown_counts',res->'unknown_counts','exclusion_counts',res->'exclusion_counts','coverage',res->'coverage_status');if agg2<>agg1 then raise notice 'FINDING: per-page aggregates differ page %: % vs %',i,agg1,agg2;end if;end if;
  tot:=tot+jsonb_array_length(res->'rows');
  keys:=keys||array(select x->>'cohort_key' from jsonb_array_elements(res->'rows')x);
  exit when res->>'next_cursor' is null;cur:=(res->>'next_cursor')::uuid;if i>10 then raise exception 'loop';end if;
 end loop;
 raise notice 'A: pages=% total_rows=% distinct_keys=% aggregates(page1)=%',i,tot,cardinality(array(select distinct x from unnest(keys)x)),agg1;
 reset role;select total_row_count into n from public.e10_market_query_contexts where organization_id=o and actor_id=u and query_fingerprint=fp;set local role authenticated;
 raise notice 'A: context total_row_count=% (expected 7)',n;
 -- sale_count_min filter is a post-aggregation filter: verify it is applied to the whole cohort (count of rows with observed_count>=3 => variants 3,4,5 => 3 rows)
 res:=public.e10_org_market_screener(o,'catalog','variant','count','completed_sale','2026-01-01','2026-02-01','2026-02-01',null,'none',null,null,'{"sale_count_min":3}','observed_count_desc',1,null);
 reset role;select total_row_count into n from public.e10_market_query_contexts where organization_id=o and actor_id=u and query_fingerprint=(res->>'query_fingerprint');set local role authenticated;
 raise notice 'A: sale_count_min=3 limit=1 -> page rows=% context total=% (expected 1 and 3), first observed_count=%',jsonb_array_length(res->'rows'),n,res#>>'{rows,0,observed_count}';

 -- B. cursor scope
 res:=public.e10_org_market_screener(o,'catalog','variant','count','completed_sale','2026-01-01','2026-02-01','2026-02-01',null,'none',null,null,'{}','cohort_asc',2,null);cur:=(res->>'next_cursor')::uuid;fp:=res->>'query_fingerprint';
 -- B1 replay with different limit (limit is part of fingerprint?)
 begin perform public.e10_org_market_screener(o,'catalog','variant','count','completed_sale','2026-01-01','2026-02-01','2026-02-01',null,'none',null,null,'{}','cohort_asc',3,cur);raise notice 'FINDING B1: cursor accepted with different limit';exception when others then raise notice 'B1 different limit -> % %',sqlstate,sqlerrm;end;
 -- B2 different sort
 begin perform public.e10_org_market_screener(o,'catalog','variant','count','completed_sale','2026-01-01','2026-02-01','2026-02-01',null,'none',null,null,'{}','observed_count_desc',2,cur);raise notice 'FINDING B2: cursor accepted with different sort';exception when others then raise notice 'B2 different sort -> % %',sqlstate,sqlerrm;end;
 -- B3 forged random uuid
 begin perform public.e10_org_market_screener(o,'catalog','variant','count','completed_sale','2026-01-01','2026-02-01','2026-02-01',null,'none',null,null,'{}','cohort_asc',2,fake);raise notice 'FINDING B3: random cursor accepted';exception when others then raise notice 'B3 forged cursor -> % %',sqlstate,sqlerrm;end;
 -- B4 another member of same org replays cursor
 perform set_config('request.jwt.claims',jsonb_build_object('sub',u2,'role','authenticated')::text,true);
 begin perform public.e10_org_market_screener(o,'catalog','variant','count','completed_sale','2026-01-01','2026-02-01','2026-02-01',null,'none',null,null,'{}','cohort_asc',2,cur);raise notice 'FINDING B4: other actor cursor accepted';exception when others then raise notice 'B4 other actor -> % %',sqlstate,sqlerrm;end;
 -- B5 other org with the same cursor
 begin perform public.e10_org_market_screener(o2,'catalog','variant','count','completed_sale','2026-01-01','2026-02-01','2026-02-01',null,'none',null,null,'{}','cohort_asc',2,cur);raise notice 'FINDING B5: other org cursor accepted';exception when others then raise notice 'B5 other org -> % %',sqlstate,sqlerrm;end;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated')::text,true);
 -- B6 dataset revision change (new observation through real path: fact decision insert bumps org revision)
 reset role;insert into public.e10_market_observation_coverage_decisions(organization_id,decision_key,observation_kind,source_kind,source_connection_id,currency,covered_from,covered_to,revision,action,coverage_status,reason,evidence,idempotency_key,request_fingerprint)values(o,gen_random_uuid(),'asking_price','manual','bump','USD','2026-01-01','2026-02-01',1,'assert','complete','x','{}','e1-bump','fp');set local role authenticated;
 begin perform public.e10_org_market_screener(o,'catalog','variant','count','completed_sale','2026-01-01','2026-02-01','2026-02-01',null,'none',null,null,'{}','cohort_asc',2,cur);raise notice 'FINDING B6: stale-revision cursor accepted';exception when others then raise notice 'B6 revision changed -> % %',sqlstate,sqlerrm;end;
 -- B7 same query after revocation of capability
 res:=public.e10_org_market_screener(o,'catalog','variant','count','completed_sale','2026-01-01','2026-02-01','2026-02-01',null,'none',null,null,'{}','cohort_asc',2,null);cur:=(res->>'next_cursor')::uuid;
 reset role;update public.e10_organization_role_permissions set allowed=false where organization_id=o and role_id=role1 and capability='act.view_market_analytics';set local role authenticated;
 begin perform public.e10_org_market_screener(o,'catalog','variant','count','completed_sale','2026-01-01','2026-02-01','2026-02-01',null,'none',null,null,'{}','cohort_asc',2,cur);raise notice 'FINDING B7: revoked cap cursor accepted';exception when others then raise notice 'B7 after cap revoke -> % %',sqlstate,sqlerrm;end;
 reset role;update public.e10_organization_role_permissions set allowed=true where organization_id=o and role_id=role1 and capability='act.view_market_analytics';set local role authenticated;
 -- B8 membership removed (delete membership row)
 reset role;delete from public.e10_organization_memberships where organization_id=o and user_id=u;set local role authenticated;
 begin perform public.e10_org_market_screener(o,'catalog','variant','count','completed_sale','2026-01-01','2026-02-01','2026-02-01',null,'none',null,null,'{}','cohort_asc',2,cur);raise notice 'FINDING B8: removed member cursor accepted';exception when others then raise notice 'B8 after membership delete -> % %',sqlstate,sqlerrm;end;
 reset role;insert into public.e10_organization_memberships(organization_id,user_id,role_id,status)values(o,u,role1,'active');set local role authenticated;

 -- C. drilldown: parent fingerprint of another actor; cohort key not in parent; cursor replay; forged fingerprint
 res:=public.e10_org_market_screener(o,'catalog','variant','count','completed_sale','2026-01-01','2026-02-01','2026-02-01',null,'none',null,null,'{}','observed_count_desc',10,null);fp:=res->>'query_fingerprint';ck:=res#>>'{rows,0,cohort_key}';
 dres:=public.e10_org_market_observation_drilldown(o,fp,ck,'completed_sale','2026-01-01','2026-02-01','2026-02-01',null,'none',null,null,2,null);dcur:=(dres->>'next_cursor')::uuid;
 raise notice 'C: drilldown page1 rows=% next_cursor set=% (variant5 has 5 obs)',jsonb_array_length(dres->'rows'),dcur is not null;
 i:=jsonb_array_length(dres->'rows');
 loop exit when dcur is null;dres:=public.e10_org_market_observation_drilldown(o,fp,ck,'completed_sale','2026-01-01','2026-02-01','2026-02-01',null,'none',null,null,2,dcur);i:=i+jsonb_array_length(dres->'rows');dcur:=(dres->>'next_cursor')::uuid;end loop;
 raise notice 'C: drilldown total rows via pages=% (expected 5)',i;
 begin perform public.e10_org_market_observation_drilldown(o,fp,'not-a-cohort','completed_sale','2026-01-01','2026-02-01','2026-02-01',null,'none',null,null,2,null);raise notice 'FINDING C1: foreign cohort key accepted';exception when others then raise notice 'C1 unknown cohort key -> % %',sqlstate,sqlerrm;end;
 begin perform public.e10_org_market_observation_drilldown(o,fp,ck,'completed_sale','2026-01-01','2026-02-01','2026-02-01','USD','none',null,null,2,null);raise notice 'FINDING C2: parent mismatch accepted';exception when others then raise notice 'C2 parent param mismatch -> % %',sqlstate,sqlerrm;end;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',u2,'role','authenticated')::text,true);
 begin perform public.e10_org_market_observation_drilldown(o,fp,ck,'completed_sale','2026-01-01','2026-02-01','2026-02-01',null,'none',null,null,2,null);raise notice 'FINDING C3: other actor used foreign parent fingerprint';exception when others then raise notice 'C3 other actor parent fp -> % %',sqlstate,sqlerrm;end;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated')::text,true);
 -- C4: drilldown cursor used in screener endpoint
 dres:=public.e10_org_market_observation_drilldown(o,fp,ck,'completed_sale','2026-01-01','2026-02-01','2026-02-01',null,'none',null,null,2,null);dcur:=(dres->>'next_cursor')::uuid;
 begin perform public.e10_org_market_screener(o,'catalog','variant','count','completed_sale','2026-01-01','2026-02-01','2026-02-01',null,'none',null,null,'{}','observed_count_desc',10,dcur);raise notice 'FINDING C4: drilldown cursor accepted by screener';exception when others then raise notice 'C4 cross-endpoint cursor -> % %',sqlstate,sqlerrm;end;
 -- D. capacity: 100 contexts per actor/org then 54000
 reset role;
 select count(*) into n from public.e10_market_query_contexts where organization_id=o and actor_id=u;raise notice 'D: contexts so far=%',n;
 set local role authenticated;
 begin for i in 1..110 loop perform public.e10_org_market_screener(o,'catalog','variant','count','completed_sale','2026-01-01','2026-02-01','2026-02-01',null,'none',null,null,jsonb_build_object('release_year',1900+i),'cohort_asc',2,null);end loop;raise notice 'FINDING D: >100 contexts allowed';exception when others then raise notice 'D context cap -> % % at i=%',sqlstate,sqlerrm,i;end;
 -- E. secrets/grants
 reset role;
 raise notice 'E: authenticated select on e10_market_query_contexts=% cursors=% inventory_cursor_secrets=% ; exec market_query_fingerprint=% save_ctx=%',
  has_table_privilege('authenticated','public.e10_market_query_contexts','select'),has_table_privilege('authenticated','public.e10_market_query_cursors','select'),has_table_privilege('authenticated','public.e10_inventory_cursor_secrets','select'),
  has_function_privilege('authenticated','e10.market_query_fingerprint(text,uuid,uuid,text,jsonb,jsonb,bigint,bigint)','execute'),has_function_privilege('authenticated','e10.save_market_query_context(text,uuid,uuid,text,text,jsonb,jsonb,bigint,bigint,text[])','execute');
end $$;
rollback;
