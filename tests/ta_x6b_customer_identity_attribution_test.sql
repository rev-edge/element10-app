\set ON_ERROR_STOP on
begin;
do $$
declare
  a uuid:='e1000000-0000-4000-8000-0000000000a6'; b uuid:=gen_random_uuid(); ua uuid:=gen_random_uuid(); ub uuid:=gen_random_uuid(); ra uuid:=gen_random_uuid(); rb uuid:=gen_random_uuid();
  ca uuid; cb uuid; activity uuid; claim uuid:=gen_random_uuid(); r jsonb; first_decision uuid; original_customer uuid; denied boolean:=false; n integer;
begin
  insert into public.e10_organizations(id,name,slug) values(b,'X6b B','x6b-'||replace(b::text,'-',''));
  insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at) values
    (ua,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',ua||'@x.invalid',now(),now()),
    (ub,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',ub||'@x.invalid',now(),now());
  insert into public.e10_organization_roles(id,organization_id,key,name,is_system) values(ra,a,'x6b-'||ua,'X6b A',false),(rb,b,'x6b-'||ub,'X6b B',false);
  insert into public.e10_organization_role_permissions values
    (a,ra,'act.manage_customers',true),(a,ra,'act.record_commercial_events',true),(b,rb,'act.manage_customers',true);
  insert into public.e10_organization_memberships(organization_id,user_id,role_id,status) values(a,ua,ra,'active'),(b,ub,rb,'active');

  perform set_config('request.jwt.claims',jsonb_build_object('sub',ua,'role','authenticated')::text,true);
  r:=public.e10_org_create_customer(a,'Alice Collector','x6b-create-a'); ca:=(r->>'customer_id')::uuid;
  if not (public.e10_org_create_customer(a,'Alice Collector','x6b-create-a')->>'replay')::boolean then raise exception 'create retry did not replay'; end if;
  begin perform public.e10_org_create_customer(a,'Changed','x6b-create-a'); exception when sqlstate '22023' then denied:=true; end;
  if not denied then raise exception 'create mismatch accepted'; end if; denied:=false;
  r:=public.e10_org_create_customer(a,'Second Customer','x6b-create-b'); cb:=(r->>'customer_id')::uuid;
  r:=public.e10_org_update_customer(a,ca,0,'Alice Updated','active','x6b-update-a');
  if (r->>'revision')::bigint<>1 then raise exception 'CAS revision missing'; end if;
  begin perform public.e10_org_update_customer(a,ca,0,'Stale','active','x6b-update-stale'); exception when sqlstate '40001' then denied:=true; end;
  if not denied then raise exception 'stale CAS accepted'; end if; denied:=false;

  r:=public.e10_org_decide_customer_identity(a,ca,'alias',null,null,'Alice Breaker','attach',null,'reviewed alias','{}','x6b-alias-1');
  first_decision:=(r->>'decision_id')::uuid;
  perform public.e10_org_decide_customer_identity(a,ca,'alias',null,null,'Alice Breaker','detach',null,'alias retired','{}','x6b-alias-2');
  if (select identity_action<>'detach' from public.e10_current_customer_identities where organization_id=a and identity_kind='alias' and lower(alias_text)='alice breaker') then raise exception 'alias history current state wrong'; end if;
  if (select count(*)<>2 from public.e10_customer_identity_decisions where organization_id=a and lower(alias_text)='alice breaker') then raise exception 'alias history not preserved'; end if;
  perform public.e10_org_decide_customer_identity(a,cb,'alias',null,null,'Alice Breaker','attach',null,'same alias, different customer','{}','x6b-alias-other');
  if (select count(*)<>2 from public.e10_current_customer_identities where organization_id=a and identity_kind='alias' and lower(alias_text)='alice breaker') then raise exception 'ordinary alias was made globally unique'; end if;

  insert into public.e10_viewer_handle_claims(id,user_id,whatnot_handle,status,evidence,verified_at,expires_at)
    values(claim,ua,'@AliceCards','verified','{}',now(),now()+interval '1 day');
  r:=public.e10_org_decide_customer_identity(a,ca,'channel_account','whatnot','alicecards',null,'attach',claim,'verified handle','{}','x6b-handle');
  if r->>'verification_basis'<>'verified_handle' or (select auth_user_id from public.e10_customers where id=ca)<>ua then raise exception 'verified auth link not proven'; end if;
  begin perform public.e10_org_decide_customer_identity(a,cb,'channel_account','whatnot','alicecards',null,'attach',claim,'steal','{}','x6b-steal'); exception when sqlstate '22023' then denied:=true; end;
  if not denied then raise exception 'active identity reassignment accepted'; end if; denied:=false;
  perform public.e10_org_decide_customer_identity(a,ca,'channel_account','whatnot','@ALICECARDS',null,'detach',null,'verified link detached','{}','x6b-handle-detach');
  if (select auth_user_id is not null from public.e10_customers where id=ca) then raise exception 'detached verified identity left stale auth link'; end if;
  begin perform public.e10_org_record_customer_activity(a,'retail',ca,ua,'alicecards',null,null,1,1,null,null,null,'CAD','manual','2026-01-01T00:00:00Z','exact','manual',null,'operator','x6b-stale-source','{}','operator_asserted','x6b-stale-activity'); exception when sqlstate '22023' then denied:=true; end;
  if not denied then raise exception 'detached identity still produced verified attribution'; end if; denied:=false;
  perform public.e10_org_decide_customer_identity(a,ca,'channel_account','whatnot','alicecards',null,'attach',claim,'verified link restored','{}','x6b-handle-reattach');
  update public.e10_viewer_handle_claims set status='rejected' where id=claim;
  r:=public.e10_org_record_customer_activity(a,'retail',ca,ua,'alicecards',null,null,1,1,null,null,null,'CAD','manual','2026-01-01T00:00:00Z','exact','manual',null,'operator','x6b-revoked-source','{}','operator_asserted','x6b-revoked-activity');
  if (select buyer_identity_status<>'reviewed_attributed' from public.e10_customer_activity_observations where id=(r->>'activity_id')::uuid) then raise exception 'revoked claim retained verified attribution'; end if;

  r:=public.e10_org_record_customer_activity(a,'retail',null,ua,'alicecards',null,null,1,20,null,null,null,'CAD','manual','2026-01-01T00:00:00Z','exact','manual',null,'operator','x6b-source','{}','operator_asserted','x6b-activity');
  activity:=(r->>'activity_id')::uuid;
  select customer_id into original_customer from public.e10_customer_activity_observations where id=activity;
  r:=public.e10_org_attribute_customer_activity(a,activity,ca,'matched verified handle','{"basis":"verified_handle"}','x6b-attr-1');
  if (r->>'revenue_changed')::boolean then raise exception 'attribution claims revenue change'; end if;
  perform public.e10_org_attribute_customer_activity(a,activity,cb,'review correction','{}','x6b-attr-2');
  if (select customer_id<>cb from public.e10_current_customer_activity_attributions where organization_id=a and activity_observation_id=activity) then raise exception 'corrected attribution not current'; end if;
  if (select count(*)<>2 from public.e10_customer_activity_attribution_decisions where organization_id=a and activity_observation_id=activity) then raise exception 'attribution history not preserved'; end if;
  if (select customer_id is distinct from original_customer from public.e10_customer_activity_observations where id=activity) then raise exception 'source activity was rewritten'; end if;
  select count(*) into n from public.e10_org_find_customers(a,'alice',10);
  if n<>2 then raise exception 'bounded identity lookup returned %',n; end if;
  begin perform * from public.e10_org_find_customers(a,'a',10); exception when sqlstate '22023' then denied:=true; end;
  if not denied then raise exception 'unbounded-short lookup accepted'; end if; denied:=false;

  perform set_config('request.jwt.claims',jsonb_build_object('sub',ub,'role','authenticated')::text,true);
  begin perform public.e10_org_update_customer(a,ca,1,'Cross Org','active','x6b-cross'); exception when sqlstate '42501' then denied:=true; end;
  if not denied then raise exception 'cross-org mutation accepted'; end if; denied:=false;
  begin perform public.e10_org_attribute_customer_activity(b,activity,ca,'cross org','{}','x6b-cross-attr'); exception when sqlstate '42501' then denied:=true; end;
  if not denied then raise exception 'cross-org attribution accepted'; end if;

  raise notice 'TA-X6b customer identity: PASS (CAS, history, verified handle, attribution correction, bounded lookup, hostile tenant)';
end $$;
rollback;
