\set ON_ERROR_STOP 0
begin;
do $$
declare o uuid:=gen_random_uuid();o2 uuid:=gen_random_uuid();u uuid:=gen_random_uuid();u2 uuid:=gen_random_uuid();pa uuid:=gen_random_uuid();role1 uuid:=gen_random_uuid();role2 uuid:=gen_random_uuid();rel uuid:=gen_random_uuid();v1 uuid:=gen_random_uuid();
 j jsonb;term uuid;term2 uuid;dk uuid;r record;
begin
 insert into auth.users(id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)values(u,'authenticated','authenticated','e5-u@x.invalid','',now(),'{}','{}',now(),now()),(u2,'authenticated','authenticated','e5-u2@x.invalid','',now(),'{}','{}',now(),now()),(pa,'authenticated','authenticated','e5-pa@x.invalid','',now(),'{}','{}',now(),now());
 insert into public.e10_organizations(id,slug,name)values(o,'e5-'||substr(o::text,1,8),'E5'),(o2,'e5f-'||substr(o2::text,1,8),'E5 foreign');
 insert into public.e10_organization_roles(id,organization_id,key,name)values(role1,o,'cur','Curator'),(role2,o2,'cur','Curator');
 insert into public.e10_organization_memberships(organization_id,user_id,role_id,status)values(o,u,role1,'active'),(o2,u2,role2,'active');
 insert into public.e10_organization_role_permissions(organization_id,role_id,capability,allowed)values(o,role1,'act.curate_market_analytics',true),(o,role1,'act.view_market_analytics',true),(o2,role2,'act.curate_market_analytics',true),(o2,role2,'act.view_market_analytics',true);
 insert into public.e10_platform_admins(user_id)values(pa);
 insert into public.e10_catalog_releases(id,release_name,release_year,sport)values(rel,'E5 release',2026,'baseball');insert into public.e10_catalog_variants(id,release_id,card_number)values(v1,rel,'1');
 -- 1. org member (with curate cap, not platform admin) tries shared catalog writers
 perform set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated')::text,true);set local role authenticated;
 begin perform public.e10_platform_review_catalog_facet_term(null,0,'color_family','Gold','assert','x','{}','e5-term-u');raise notice 'FINDING 1a: org member created shared term';exception when others then raise notice '1a org member term -> % %',sqlstate,sqlerrm;end;
 begin perform public.e10_platform_review_catalog_facet_alias(null,0,'color_family','golden','assert',gen_random_uuid(),'x','{}','e5-alias-u');raise notice 'FINDING 1b';exception when others then raise notice '1b org member alias -> % %',sqlstate,sqlerrm;end;
 begin perform public.e10_platform_review_catalog_variant_facet(null,v1,null,'rookie_designation',0,'assert',true,null,null,'x','{}','e5-vf-u');raise notice 'FINDING 1c';exception when others then raise notice '1c org member variant facet -> % %',sqlstate,sqlerrm;end;
 begin update public.e10_catalog_variants set card_number='9' where id=v1;raise notice 'FINDING 1d: org member updated catalog variant';exception when others then raise notice '1d direct catalog update -> % %',sqlstate,sqlerrm;end;
 begin update public.e10_catalog_releases set league='NL' where id=rel;raise notice 'FINDING 1e: org member updated release league';exception when others then raise notice '1e direct release update -> % %',sqlstate,sqlerrm;end;
 -- 2. platform admin creates term + global facet
 perform set_config('request.jwt.claims',jsonb_build_object('sub',pa,'role','authenticated')::text,true);
 j:=public.e10_platform_review_catalog_facet_term(null,0,'color_family','Gold','assert','x','{}','e5-term');term:=(j->>'term_key')::uuid;
 j:=public.e10_platform_review_catalog_facet_term(null,0,'color_family','Silver','assert','x','{}','e5-term2');term2:=(j->>'term_key')::uuid;
 j:=public.e10_platform_review_catalog_variant_facet(null,v1,null,'color_family',0,'assert',null,null,term,'x','{}','e5-vf');raise notice '2 global facet rev=%',j->>'revision';
 j:=public.e10_platform_review_catalog_variant_facet(null,v1,null,'rookie_designation',0,'assert',true,null,null,'x','{}','e5-vf-rookie');
 -- 2b. platform admin replay with same key different payload
 begin perform public.e10_platform_review_catalog_facet_term(null,0,'color_family','Bronze','assert','x','{}','e5-term');raise notice 'FINDING 2b';exception when others then raise notice '2b idem mismatch -> % %',sqlstate,sqlerrm;end;
 -- 3. org u overrides color to Silver and masks rookie in org o
 perform set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated')::text,true);
 j:=public.e10_org_review_catalog_variant_facet_override(o,null,v1,null,'color_family',0,'assert',null,null,term2,'x','{}','e5-ov');dk:=(j->>'decision_key')::uuid;raise notice '3 org override rev=%',j->>'revision';
 j:=public.e10_org_review_catalog_variant_facet_override(o,null,v1,null,'rookie_designation',0,'mask',null,null,null,'x','{}','e5-ov-rookie');
 -- 3b. u2 (org o2) tries to write override into org o
 perform set_config('request.jwt.claims',jsonb_build_object('sub',u2,'role','authenticated')::text,true);
 begin perform public.e10_org_review_catalog_variant_facet_override(o,null,v1,null,'finish_family',0,'mask',null,null,null,'x','{}','e5-ov-x');raise notice 'FINDING 3b: cross-org override written';exception when others then raise notice '3b cross-org override -> % %',sqlstate,sqlerrm;end;
 -- 3c. u2 tries to supersede org o decision key from org o2 (key guessing)
 begin perform public.e10_org_review_catalog_variant_facet_override(o2,dk,v1,null,'color_family',1,'clear',null,null,null,'x','{}','e5-ov-x2');raise notice 'FINDING 3c';exception when others then raise notice '3c foreign decision key in own org -> % %',sqlstate,sqlerrm;end;
 reset role;
 -- 4. projection isolation
 select color_family_term_id,color_family_status,rookie_designation,rookie_designation_status into r from e10.market_catalog_entities(o) where catalog_variant_id=v1;
 raise notice '4 org o sees color=% (%), rookie=% (%)  [expect Silver term % org_override, null org_masked]',r.color_family_term_id,r.color_family_status,r.rookie_designation,r.rookie_designation_status,term2;
 select color_family_term_id,color_family_status,rookie_designation,rookie_designation_status into r from e10.market_catalog_entities(o2) where catalog_variant_id=v1;
 raise notice '4 org o2 sees color=% (%), rookie=% (%)  [expect Gold term % global_reviewed, true global_reviewed]',r.color_family_term_id,r.color_family_status,r.rookie_designation,r.rookie_designation_status,term;
 if r.color_family_term_id<>term or r.rookie_designation is not true then raise notice 'FINDING 4: org override leaked into other org';end if;
 -- 5. append-only even for owner
 begin update public.e10_catalog_variant_facet_decisions set boolean_value=false where variant_id=v1;raise notice 'FINDING 5a';exception when others then raise notice '5a owner update decision -> % %',sqlstate,sqlerrm;end;
 begin delete from public.e10_org_catalog_variant_facet_overrides where organization_id=o;raise notice 'FINDING 5b';exception when others then raise notice '5b owner delete override -> % %',sqlstate,sqlerrm;end;
 begin update public.e10_catalog_facet_taxonomy_terms set canonical_name='X' where term_key=term;raise notice 'FINDING 5c';exception when others then raise notice '5c owner update term -> % %',sqlstate,sqlerrm;end;
 -- 6. revision/supersession chain: org o revises override to clear, revisions are separate rows
 perform set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated')::text,true);set local role authenticated;
 j:=public.e10_org_review_catalog_variant_facet_override(o,dk,v1,null,'color_family',1,'clear',null,null,null,'x','{}','e5-ov-clear');raise notice '6 clear rev=%',j->>'revision';
 begin perform public.e10_org_review_catalog_variant_facet_override(o,dk,v1,null,'color_family',1,'clear',null,null,null,'x','{}','e5-ov-clear2');raise notice 'FINDING 6b: stale expected revision accepted';exception when others then raise notice '6b stale revision -> % %',sqlstate,sqlerrm;end;
 reset role;
 raise notice '6 override rows for org o=% ; current color for org o=%',(select count(*) from public.e10_org_catalog_variant_facet_overrides where organization_id=o),(select color_family_term_id||' '||color_family_status from e10.market_catalog_entities(o) where catalog_variant_id=v1);
 -- 7. grants
 raise notice '7 authenticated select on facet decisions=% overrides=% ; anon exec platform term=%',has_table_privilege('authenticated','public.e10_catalog_variant_facet_decisions','select'),has_table_privilege('authenticated','public.e10_org_catalog_variant_facet_overrides','select'),has_function_privilege('anon','public.e10_platform_review_catalog_facet_term(uuid,bigint,text,text,text,text,jsonb,text)','execute');
end $$;
rollback;
