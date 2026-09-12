\set ON_ERROR_STOP 0
begin;
do $$
declare o uuid:=gen_random_uuid();o2 uuid:=gen_random_uuid();u uuid:=gen_random_uuid();u2 uuid:=gen_random_uuid();u3 uuid:=gen_random_uuid();rid uuid:=gen_random_uuid();role_approver uuid:=gen_random_uuid();role2 uuid:=gen_random_uuid();loc uuid:=gen_random_uuid();supplier uuid:=gen_random_uuid();product uuid:=gen_random_uuid();config uuid:=gen_random_uuid();version uuid:=gen_random_uuid();
 j jsonb;j2 jsonb;d uuid;po_values jsonb;n int;po uuid;
begin
 insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at)values(u,'00000000-0000-0000-8000-000000000000','authenticated','authenticated','e3-'||u||'@x.invalid',now(),now()),(u2,'00000000-0000-0000-8000-000000000000','authenticated','authenticated','e3-'||u2||'@x.invalid',now(),now()),(u3,'00000000-0000-0000-8000-000000000000','authenticated','authenticated','e3-'||u3||'@x.invalid',now(),now());
 insert into public.e10_organizations(id,slug,name)values(o,'e3-'||substr(o::text,1,8),'E3'),(o2,'e3f-'||substr(o2::text,1,8),'E3 foreign');
 insert into public.e10_organization_roles(id,organization_id,key,name,is_system)values(rid,o,'e3','E3',false),(role_approver,o,'e3a','E3 approver',false),(role2,o2,'e3f','E3f',false);
 insert into public.e10_organization_memberships(organization_id,user_id,role_id,status)values(o,u,rid,'active'),(o,u2,role_approver,'active'),(o2,u3,role2,'active');
 insert into public.e10_organization_role_permissions values(o,rid,'act.purchasing_prepare',true),(o,rid,'act.purchasing_approve',true),(o,role_approver,'act.purchasing_approve',true),(o,role_approver,'act.purchasing_prepare',true),(o2,role2,'act.purchasing_prepare',true),(o2,role2,'act.purchasing_approve',true);
 insert into public.e10_locations(id,organization_id,code,name,status)values(loc,o,'E3','E3 receiving','active');
 insert into public.e10_location_role_permissions(organization_id,location_id,role_id,can_receive)values(o,loc,rid,true),(o,loc,role_approver,true);
 insert into public.e10_suppliers(id,organization_id,code,name,status)values(supplier,o,'E3','E3 supplier','active');
 insert into public.e10_product_masters(id,organization_id,name)values(product,o,'E3 product');
 insert into public.e10_product_configurations(id,organization_id,product_master_id,name)values(config,o,product,'E3 configuration');
 insert into public.e10_product_configuration_versions(id,organization_id,configuration_id,version_no,state,packaging_kind,base_unit,base_units_per_package)values(version,o,config,1,'active','unit','unit',1);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated')::text,true);set local role authenticated;
 po_values:=jsonb_build_object('supplier_id',supplier,'destination_location_id',loc,'order_number','E3-PO','currency','CAD','expected_at',null,'lines',jsonb_build_array(jsonb_build_object('line_no',1,'configuration_version_id',version,'ordered_quantity',2,'estimated_unit_cost',12.50)));
 j:=public.e10_org_create_action_draft(o,'purchase_order.create',po_values,'{}','[]','e3-create');d:=(j->>'draft_id')::uuid;
 raise notice '1 created draft rev=% missing=%',j->>'revision',j->'missing_fields';
 -- inert check
 reset role;select count(*) into n from public.e10_purchase_orders where organization_id=o;raise notice '1 purchase orders after create+approve prep=% (expect 0)',n;set local role authenticated;
 -- 2. cross-org: u3 (member of o2 only) preview/approve/commit with p_org=o and with p_org=o2
 perform set_config('request.jwt.claims',jsonb_build_object('sub',u3,'role','authenticated')::text,true);
 begin perform public.e10_org_preview_action_draft(o,d,1);raise notice 'FINDING 2a: non-member previewed';exception when others then raise notice '2a non-member preview p_org=o -> % %',sqlstate,sqlerrm;end;
 begin perform public.e10_org_preview_action_draft(o2,d,1);raise notice 'FINDING 2b: cross-org preview';exception when others then raise notice '2b cross-org preview p_org=o2 -> % %',sqlstate,sqlerrm;end;
 begin perform public.e10_org_approve_action_draft(o2,d,1,'e3-x-approve');raise notice 'FINDING 2c';exception when others then raise notice '2c cross-org approve -> % %',sqlstate,sqlerrm;end;
 begin perform public.e10_org_commit_action_draft(o2,d,1,'e3-x-commit');raise notice 'FINDING 2d';exception when others then raise notice '2d cross-org commit -> % %',sqlstate,sqlerrm;end;
 -- 3. u2 (approver, prepare cap, not creator, not admin): can approve; can commit?
 perform set_config('request.jwt.claims',jsonb_build_object('sub',u2,'role','authenticated')::text,true);
 j:=public.e10_org_approve_action_draft(o,d,1,'e3-approve-u2');raise notice '3 approve by non-creator approver: status=%',j->>'status';
 begin j:=public.e10_org_commit_action_draft(o,d,1,'e3-commit-u2');raise notice '3 commit by non-creator with prepare cap: status=%',j->>'status';exception when others then raise notice '3 commit by non-creator -> % %',sqlstate,sqlerrm;end;
 begin j:=public.e10_org_amend_action_draft(o,d,1,po_values,'{}','[]','e3-amend-u2');raise notice '3 amend by non-creator: rev=%',j->>'revision';exception when others then raise notice '3 amend by non-creator -> % %',sqlstate,sqlerrm;end;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated')::text,true);
 -- 4. exact revision: approved at 1; commit with 2 -> conflict; amend -> rev 2 draft; commit with 1 -> conflict; approve again at 2 then commit with 1
 begin perform public.e10_org_commit_action_draft(o,d,2,'e3-commit-wrong');raise notice 'FINDING 4a';exception when others then raise notice '4a commit wrong rev -> % %',sqlstate,sqlerrm;end;
 -- 5. changed payload / reference drift: supplier renamed (updated_at changes) after approval -> commit must fail stale
 reset role;update public.e10_suppliers set name='E3 supplier renamed',updated_at=clock_timestamp() where id=supplier;set local role authenticated;
 begin perform public.e10_org_commit_action_draft(o,d,1,'e3-commit-stale');raise notice 'FINDING 5: committed with drifted reference';exception when others then raise notice '5 reference drift commit -> % %',sqlstate,sqlerrm;end;
 -- re-approve after amend (fresh snapshot)
 j:=public.e10_org_amend_action_draft(o,d,1,po_values,'{}','[]','e3-amend-1');raise notice '5 amend -> rev=% status=%',j->>'revision',j->>'status';
 begin perform public.e10_org_commit_action_draft(o,d,2,'e3-commit-unapproved');raise notice 'FINDING 5b: committed unapproved revision';exception when others then raise notice '5b commit unapproved -> % %',sqlstate,sqlerrm;end;
 j:=public.e10_org_approve_action_draft(o,d,2,'e3-approve-2');
 -- 6. supplier deactivated after approval (status change) -> stale
 reset role;update public.e10_suppliers set status='inactive',updated_at=clock_timestamp() where id=supplier;set local role authenticated;
 begin perform public.e10_org_commit_action_draft(o,d,2,'e3-commit-inactive');raise notice 'FINDING 6: committed with inactive supplier';exception when others then raise notice '6 inactive supplier commit -> % %',sqlstate,sqlerrm;end;
 reset role;update public.e10_suppliers set status='active' where id=supplier;set local role authenticated;
 begin perform public.e10_org_commit_action_draft(o,d,2,'e3-commit-inactive2');raise notice '6b commit after reactivation (updated_at changed): status=%',null;exception when others then raise notice '6b reactivated but updated_at drifted -> % %',sqlstate,sqlerrm;end;
 -- 7. fresh amend/approve then commit succeeds; check writer authority: revoke prepare cap of creator -> commit denied
 j:=public.e10_org_amend_action_draft(o,d,2,po_values,'{}','[]','e3-amend-2');j:=public.e10_org_approve_action_draft(o,d,3,'e3-approve-3');
 reset role;delete from public.e10_organization_role_permissions where organization_id=o and role_id=rid and capability='act.purchasing_prepare';set local role authenticated;
 begin perform public.e10_org_commit_action_draft(o,d,3,'e3-commit-nocap');raise notice 'FINDING 7: committed without prepare cap';exception when others then raise notice '7 commit without prepare cap -> % %',sqlstate,sqlerrm;end;
 reset role;insert into public.e10_organization_role_permissions values(o,rid,'act.purchasing_prepare',true);set local role authenticated;
 -- 7b. location receive permission revoked for the creator's role: does the ordinary writer enforce it?
 reset role;delete from public.e10_location_role_permissions where organization_id=o and location_id=loc and role_id=rid;set local role authenticated;
 begin j:=public.e10_org_commit_action_draft(o,d,3,'e3-commit-noloc');raise notice '7b commit without location can_receive: status=% (writer enforces location permission? check)',j->>'status';exception when others then raise notice '7b commit without location perm -> % %',sqlstate,sqlerrm;end;
 reset role;insert into public.e10_location_role_permissions(organization_id,location_id,role_id,can_receive)values(o,loc,rid,true);set local role authenticated;
 begin j:=public.e10_org_commit_action_draft(o,d,3,'e3-commit-ok');po:=(j#>>'{ordinary_result,purchase_order_id}')::uuid;raise notice '8 commit ok status=% po=%',j->>'status',po;exception when others then raise notice '8 commit -> % %',sqlstate,sqlerrm;end;
 reset role;select count(*) into n from public.e10_purchase_orders where organization_id=o;raise notice '8 purchase orders now=%',n;set local role authenticated;
 -- 9. idempotent replay and post-commit transitions
 j2:=public.e10_org_commit_action_draft(o,d,3,'e3-commit-ok');raise notice '9 replay=% same po=%',j2->>'replay',(j2#>>'{ordinary_result,purchase_order_id}')=po::text;
 begin perform public.e10_org_commit_action_draft(o,d,3,'e3-commit-again');raise notice 'FINDING 9b: double commit with new key';exception when others then raise notice '9b re-commit new key -> % %',sqlstate,sqlerrm;end;
 begin perform public.e10_org_amend_action_draft(o,d,3,po_values,'{}','[]','e3-amend-post');raise notice 'FINDING 9c: amend after commit';exception when others then raise notice '9c amend after commit -> % %',sqlstate,sqlerrm;end;
 begin perform public.e10_org_cancel_action_draft(o,d,3,'x','e3-cancel-post');raise notice 'FINDING 9d: cancel after commit';exception when others then raise notice '9d cancel after commit -> % %',sqlstate,sqlerrm;end;
 -- 10. direct table tamper attempts as authenticated
 begin update public.e10_action_drafts set status='approved',approved_revision=1 where id=d;raise notice 'FINDING 10: authenticated updated drafts';exception when others then raise notice '10 direct update -> % %',sqlstate,sqlerrm;end;
 reset role;
 begin update public.e10_action_draft_revisions set proposed_values='{}' where draft_id=d;raise notice 'FINDING 10b: revision mutable';exception when others then raise notice '10b revision update as owner -> % %',sqlstate,sqlerrm;end;
 begin delete from public.e10_action_draft_decisions where draft_id=d;raise notice 'FINDING 10c: decisions deletable';exception when others then raise notice '10c decision delete as owner -> % %',sqlstate,sqlerrm;end;
 -- 11. self approval: u has both prepare+approve: created, approved and committed by same user (already shown). Report as design note.
 raise notice '11 decisions=% commands=% revisions=%',(select count(*) from public.e10_action_draft_decisions where draft_id=d),(select count(*) from public.e10_action_draft_commands where draft_id=d),(select count(*) from public.e10_action_draft_revisions where draft_id=d);
end $$;
rollback;
