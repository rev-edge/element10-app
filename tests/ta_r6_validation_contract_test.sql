\set ON_ERROR_STOP on
begin;
do $$
declare o uuid:=gen_random_uuid();u uuid:=gen_random_uuid();v_role uuid:=gen_random_uuid();item text:='r6-'||gen_random_uuid();c1 uuid:=gen_random_uuid();c2 uuid:=gen_random_uuid();release_id uuid:=gen_random_uuid();variant_id uuid:=gen_random_uuid();player_id uuid:=gen_random_uuid();first_result jsonb;second_result jsonb;n integer:=0;denied boolean:=false;bad jsonb;
begin
 insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at)values(u,'00000000-0000-0000-0000-000000000000','authenticated','authenticated',u||'@r6.invalid',now(),now());
 insert into public.e10_platform_admins(user_id)values(u);
 insert into public.e10_organizations(id,slug,name)values(o,'r6-'||left(o::text,8),'R6');
 insert into public.e10_organization_roles(id,organization_id,key,name)values(v_role,o,'r6','R6');
 insert into public.e10_organization_memberships(organization_id,user_id,role_id,status)values(o,u,v_role,'active');
 insert into public.e10_organization_role_permissions values(o,v_role,'act.record_commercial_events',true),(o,v_role,'act.manage_customers',true),(o,v_role,'act.create_receiving',true);
 insert into public.e10_inventory_items(id,name,qty,organization_id)values(item,'R6 item',1,o);
 insert into public.e10_customers(id,organization_id,display_name)values(c1,o,'Literal %% buyer'),(c2,o,'Ordinary buyer');
 insert into public.e10_catalog_releases(id,release_name)values(release_id,'R6 release');
 insert into public.e10_catalog_variants(id,release_id)values(variant_id,release_id);
 insert into public.e10_players(id,name)values(player_id,'R6 player');
 perform set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated')::text,true);set local role authenticated;
 set local timezone='America/Toronto';first_result:=public.e10_org_record_commercial_event(o,'listing_created','inventory_item',item,'2026-01-01T12:00:00Z','manual','r6','{"listing_id":"r6","channel":"test"}',null,'{}','r6-timezone');
 set local timezone='Asia/Tokyo';second_result:=public.e10_org_record_commercial_event(o,'listing_created','inventory_item',item,'2026-01-01T12:00:00Z','manual','r6','{"listing_id":"r6","channel":"test"}',null,'{}','r6-timezone');
 if not(second_result->>'replay')::boolean or second_result->>'event_id'<>first_result->>'event_id'then raise exception'timezone-neutral event replay failed';end if;
 select count(*)into n from public.e10_org_find_customers(o,'%%',25);if n<>1 then raise exception'LIKE metacharacters were not literal: %',n;end if;
 begin perform public.e10_platform_propose_player_identity_review('r6','source','Source','manual','R6','1','{}','[{"player_id":"not-a-uuid","confidence_status":"unknown","evidence":{}}]','reason','{}','r6-f4');exception when sqlstate'22023'then denied:=true;end;if not denied then raise exception'malformed F4 UUID accepted';end if;denied:=false;
 begin perform public.e10_platform_review_variant_subject_context(null,variant_id,player_id,0,'assert','known',null,'manual_review','r6','reason','{}','r6-x1b');exception when sqlstate'22023'then denied:=true;end;if not denied then raise exception'non-subject context accepted';end if;
 foreach bad in array array['[{"id":"00000000-0000-4000-8000-000000000001"}]'::jsonb,'[{"id":"00000000-0000-4000-8000-000000000001","quantity":null}]'::jsonb,'[{"id":"00000000-0000-4000-8000-000000000001","quantity":"1"}]'::jsonb,'[{"id":"00000000-0000-4000-8000-000000000001","quantity":0}]'::jsonb,'[{"id":"00000000-0000-4000-8000-000000000001","quantity":-1}]'::jsonb,'[{"quantity":1}]'::jsonb,'[{"id":"bad","quantity":1}]'::jsonb,'[{"id":"00000000-0000-4000-8000-000000000001","quantity":1},{"id":"00000000-0000-4000-8000-000000000001","quantity":1}]'::jsonb,'{}'::jsonb] loop
  denied:=false;begin perform public.e10_org_receive_po_line(o,null,item,1,0,0,null,null,bad,'r6-bad-'||n);exception when sqlstate'22023'then denied:=true;end;if not denied then raise exception'malformed allocation accepted: %',bad;end if;n:=n+1;
 end loop;
end$$;
rollback;
select 'TA-R6 validation contract: PASS' result;
