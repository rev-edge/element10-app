\set ON_ERROR_STOP on
begin;
do $$
declare
 o uuid:='e1000000-0000-4000-8000-0000000000a6'; other uuid:=gen_random_uuid(); u uuid:=gen_random_uuid(); r uuid:=gen_random_uuid(); c uuid:=gen_random_uuid(); c2 uuid:=gen_random_uuid(); p1 uuid:=gen_random_uuid();p2 uuid:=gen_random_uuid();cfg1 uuid:=gen_random_uuid();cfg2 uuid:=gen_random_uuid();v1 uuid:=gen_random_uuid();v2 uuid:=gen_random_uuid();copy1 uuid:=gen_random_uuid(); activity uuid; d uuid; tx uuid; result jsonb; lines jsonb; denied boolean:=false;
begin
 insert into public.e10_organizations(id,name,slug) values(other,'X6c Other','x6c-'||replace(other::text,'-',''));
 insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at) values(u,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',u||'@x.invalid',now(),now());
 insert into public.e10_organization_roles(id,organization_id,key,name,is_system) values(r,o,'x6c-'||u,'X6c',false);
 insert into public.e10_organization_role_permissions values(o,r,'act.prepare_customer_transactions',true),(o,r,'act.record_commercial_events',true),(o,r,'act.manage_customers',true);
 insert into public.e10_organization_memberships(organization_id,user_id,role_id,status) values(o,u,r,'active');
 insert into public.e10_customers(id,organization_id,display_name) values(c,o,'X6c Customer'),(c2,o,'X6c Customer Two');
 insert into public.e10_product_masters(id,organization_id,name) values(p1,o,'Product One'),(p2,o,'Product Two');
 insert into public.e10_product_configurations(id,organization_id,product_master_id,name) values(cfg1,o,p1,'Config One'),(cfg2,o,p2,'Config Two');
 insert into public.e10_product_configuration_versions(id,organization_id,configuration_id,version_no,state,packaging_kind,base_unit,base_units_per_package) values(v1,o,cfg1,1,'active','box','unit',1),(v2,o,cfg2,1,'active','box','unit',1);
 insert into public.e10_unique_items(id,organization_id,item_kind,product_master_id,configuration_version_id) values(copy1,o,'card',p1,v1);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated')::text,true);
 result:=public.e10_org_record_customer_activity(o,'retail',c,null,'walk-in',null,null,1,30,null,null,null,'CAD','manual','2026-01-02T00:00:00Z','exact','manual',null,'operator','x6c-activity-source','{}','operator_asserted','x6c-activity');
 activity:=(result->>'activity_id')::uuid;
 perform public.e10_org_attribute_customer_activity(o,activity,null,'remove original attribution','{}','x6c-unattribute');
 perform public.e10_org_create_customer_transaction_draft(o,null,'CAD',now(),'exact','anonymous after unattribute',jsonb_build_array(jsonb_build_object('purchase_kind','retail','capture_source','manual','source_line_id','unattr-anon','activity_observation_id',activity,'quantity',1,'merchandise_gross',30)),'x6c-unattr-anon');
 begin perform public.e10_org_create_customer_transaction_draft(o,c,'CAD',now(),'exact','must not resurrect original',jsonb_build_array(jsonb_build_object('purchase_kind','retail','capture_source','manual','source_line_id','unattr-old','activity_observation_id',activity,'quantity',1,'merchandise_gross',30)),'x6c-unattr-old');exception when sqlstate '42501' then denied:=true;end;if not denied then raise exception 'unattribute resurrected original customer';end if;denied:=false;
 perform public.e10_org_attribute_customer_activity(o,activity,c2,'reviewed reattribution','{}','x6c-reattribute-b');
 perform public.e10_org_create_customer_transaction_draft(o,c2,'CAD',now(),'exact','new customer accepted',jsonb_build_array(jsonb_build_object('purchase_kind','retail','capture_source','manual','source_line_id','reattr-new','activity_observation_id',activity,'quantity',1,'merchandise_gross',30)),'x6c-reattr-new');
 begin perform public.e10_org_create_customer_transaction_draft(o,c,'CAD',now(),'exact','old customer denied',jsonb_build_array(jsonb_build_object('purchase_kind','retail','capture_source','manual','source_line_id','reattr-old','activity_observation_id',activity,'quantity',1,'merchandise_gross',30)),'x6c-reattr-old');exception when sqlstate '42501' then denied:=true;end;if not denied then raise exception 'reattribution allowed old customer';end if;denied:=false;
 perform public.e10_org_attribute_customer_activity(o,activity,c,'restore for posting fixture','{}','x6c-reattribute-a');
 begin perform public.e10_org_create_customer_transaction_draft(o,c,'CAD',now(),'exact','native spoof',jsonb_build_array(jsonb_build_object('purchase_kind','retail','capture_source','native','source_line_id','native-spoof','quantity',1,'merchandise_gross',1)),'x6c-native-spoof');exception when sqlstate '42501' then denied:=true;end;if not denied then raise exception 'untrusted native line accepted';end if;denied:=false;
 begin perform public.e10_org_create_customer_transaction_draft(o,c,'CAD',now(),'exact','config mismatch',jsonb_build_array(jsonb_build_object('purchase_kind','retail','capture_source','manual','source_line_id','bad-config','product_master_id',p1,'configuration_version_id',v2,'quantity',1,'merchandise_gross',1)),'x6c-bad-config');exception when sqlstate '42501' then denied:=true;end;if not denied then raise exception 'cross-product configuration accepted';end if;denied:=false;
 begin perform public.e10_org_create_customer_transaction_draft(o,c,'CAD',now(),'exact','copy mismatch',jsonb_build_array(jsonb_build_object('purchase_kind','retail','capture_source','manual','source_line_id','bad-copy','product_master_id',p2,'configuration_version_id',v2,'unique_item_id',copy1,'quantity',1,'merchandise_gross',1)),'x6c-bad-copy');exception when sqlstate '42501' then denied:=true;end;if not denied then raise exception 'incoherent copy target accepted';end if;denied:=false;
 lines:=jsonb_build_array(
   jsonb_build_object('purchase_kind','retail','sales_channel','store','capture_source','manual','source_line_id','manual-line-1','activity_observation_id',activity,'quantity',1,'merchandise_gross',30,'merchandise_discount',null,'shipping_amount',null,'tax_amount',null,'raw_evidence',jsonb_build_object('source','operator')),
   jsonb_build_object('purchase_kind','break','sales_channel','marketplace','source_session_reference','external-show-22','capture_source','import','source_connection_id','file-a','source_line_id','line-2','quantity',2,'merchandise_gross',20,'merchandise_discount',5,'shipping_amount',4,'tax_amount',3,'raw_evidence',jsonb_build_object('row',2))
 );
 result:=public.e10_org_create_customer_transaction_draft(o,c,'CAD','2026-01-02T00:00:00Z','exact','review mixed order',lines,'x6c-draft');d:=(result->>'draft_id')::uuid;
 if not (public.e10_org_create_customer_transaction_draft(o,c,'CAD','2026-01-02T00:00:00Z','exact','review mixed order',lines,'x6c-draft')->>'replay')::boolean then raise exception 'draft retry failed';end if;
 if (select count(*)<>2 from public.e10_customer_transaction_draft_lines where draft_id=d and revision=1) then raise exception 'mixed lines missing';end if;
 if not exists(select 1 from public.e10_customer_transaction_draft_lines where draft_id=d and revision=1 and purchase_kind='break' and break_session_id is null and source_session_reference='external-show-22') then raise exception 'external break line required fabricated native session';end if;
 if not exists(select 1 from public.e10_customer_transaction_draft_lines where draft_id=d and line_no=1 and merchandise_discount is null and shipping_amount is null and tax_amount is null and merchandise_net is null) then raise exception 'unknown components coerced';end if;
 begin perform public.e10_org_approve_customer_transaction_draft(o,d,1,'x6c-approve-denied');exception when sqlstate '42501' then denied:=true;end;if not denied then raise exception 'prepare authority approved draft';end if;denied:=false;
 insert into public.e10_organization_role_permissions values(o,r,'act.approve_customer_transactions',true);
 result:=public.e10_org_amend_customer_transaction_draft(o,d,1,c,'CAD','2026-01-02T00:00:00Z','exact','reviewed exact lines',lines,'x6c-amend');
 if (result->>'revision')::int<>2 or (select count(*)<>2 from public.e10_customer_transaction_draft_revisions where draft_id=d) then raise exception 'revision history missing';end if;
 perform public.e10_org_approve_customer_transaction_draft(o,d,2,'x6c-approve');
 perform public.e10_org_reopen_customer_transaction_draft(o,d,2,'review correction required','x6c-reopen');
 if (select count(*)<>2 from public.e10_customer_transaction_draft_decisions where draft_id=d) then raise exception 'approval/reopen history missing';end if;
 perform public.e10_org_amend_customer_transaction_draft(o,d,2,c,'CAD','2026-01-02T00:00:00Z','exact','corrected after review',lines,'x6c-amend-3');
 perform public.e10_org_approve_customer_transaction_draft(o,d,3,'x6c-approve-3');
 begin perform public.e10_org_post_customer_transaction_draft(o,d,3,'x6c-post-denied');exception when sqlstate '42501' then denied:=true;end;if not denied then raise exception 'approval authority posted draft';end if;denied:=false;
 begin perform public.e10_org_record_commercial_event_v2(o,'customer_transaction_posted',1,'unique_item',copy1::text,now(),'exact','manual',null,null,'forged-post',null,null,'operator_asserted',jsonb_build_object('transaction_id',gen_random_uuid()),null,'{}','x6c-forged-post');exception when sqlstate '42501' then denied:=true;end;if not denied then raise exception 'generic event writer forged posted transaction';end if;denied:=false;
 begin perform public.e10_org_record_commercial_event(o,'customer_transaction_posted','unique_item',copy1::text,now(),'manual','forged-v1',jsonb_build_object('transaction_id',gen_random_uuid()),null,'{}','x6c-forged-post-v1');exception when sqlstate '42501' then denied:=true;end;if not denied then raise exception 'legacy generic event writer forged posted transaction';end if;denied:=false;
 insert into public.e10_organization_role_permissions values(o,r,'act.post_customer_transactions',true);
 perform public.e10_org_attribute_customer_activity(o,activity,c2,'changed after approval','{}','x6c-after-approval-b');
 begin perform public.e10_org_post_customer_transaction_draft(o,d,3,'x6c-post-stale-b');exception when sqlstate '40001' then denied:=true;end;if not denied then raise exception 'stale customer attribution posted';end if;denied:=false;
 perform public.e10_org_attribute_customer_activity(o,activity,c,'restored after approval','{}','x6c-after-approval-a');
 begin perform public.e10_org_post_customer_transaction_draft(o,d,3,'x6c-post-stale-restored');exception when sqlstate '40001' then denied:=true;end;if not denied then raise exception 'restored attribution bypassed fresh review';end if;denied:=false;
 perform public.e10_org_reopen_customer_transaction_draft(o,d,3,'attribution changed after approval','x6c-reopen-3');
 perform public.e10_org_approve_customer_transaction_draft(o,d,3,'x6c-approve-3-fresh');
 result:=public.e10_org_post_customer_transaction_draft(o,d,3,'x6c-post');tx:=(result->>'transaction_id')::uuid;
 if (result->>'paid')::boolean or (result->>'settled')::boolean then raise exception 'posting asserted payment';end if;
 if not exists(select 1 from public.e10_customer_transactions where id=tx and customer_id=c and currency='CAD') or (select count(*)<>2 from public.e10_customer_transaction_lines where transaction_id=tx) then raise exception 'atomic posted transaction missing';end if;
 if not exists(select 1 from public.e10_commercial_events where customer_transaction_id=tx and event_type='customer_transaction_posted' and payload->>'posted_not_paid'='true') then raise exception 'posting event missing';end if;
 if not (public.e10_org_post_customer_transaction_draft(o,d,3,'x6c-post')->>'replay')::boolean then raise exception 'post retry failed';end if;
 begin perform public.e10_org_amend_customer_transaction_draft(o,d,3,c,'CAD',now(),'exact','illegal',lines,'x6c-amend-posted');exception when sqlstate '40001' then denied:=true;end;if not denied then raise exception 'posted draft amended';end if;denied:=false;
 begin perform public.e10_org_create_customer_transaction_draft(o,c,'CAD',now(),'exact','cross tenant',jsonb_build_array(jsonb_build_object('purchase_kind','retail','capture_source','manual','source_line_id','cross','location_id',gen_random_uuid(),'quantity',1,'merchandise_gross',1)),'x6c-cross');exception when sqlstate '42501' then denied:=true;end;if not denied then raise exception 'cross/missing org target accepted';end if;denied:=false;
 perform set_config('role','authenticated',true);begin perform 1 from public.e10_customer_transactions where id=tx;exception when sqlstate '42501' then denied:=true;end;if not denied then raise exception 'direct posted read allowed';end if;perform set_config('role','postgres',true);
 raise notice 'TA-X6c customer posting: PASS (mixed lines, unknowns, revisions, separate authority, atomic post, replay, tenant denial)';
end $$;
rollback;
