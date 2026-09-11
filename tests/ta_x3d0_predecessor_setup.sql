\set ON_ERROR_STOP on

insert into public.e10_suppliers(id,organization_id,name,status)
values('d3000000-0000-4000-8000-000000000001','e1000000-0000-4000-8000-0000000000a6','X3d predecessor supplier','active');

insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at)
values('d3000000-0000-4000-8000-000000000005','00000000-0000-0000-0000-000000000000',
  'authenticated','authenticated','x3d-predecessor@example.invalid',now(),now());
insert into public.e10_organization_roles(id,organization_id,key,name)
values('d3000000-0000-4000-8000-000000000006','e1000000-0000-4000-8000-0000000000a6',
  'x3d-predecessor','X3d predecessor');
insert into public.e10_organization_memberships(organization_id,user_id,role_id,status)
values('e1000000-0000-4000-8000-0000000000a6','d3000000-0000-4000-8000-000000000005',
  'd3000000-0000-4000-8000-000000000006','active');
insert into public.e10_organization_role_permissions(organization_id,role_id,capability,allowed)
values('e1000000-0000-4000-8000-0000000000a6','d3000000-0000-4000-8000-000000000006',
  'act.purchasing_prepare',true);

-- These rows are legal under the predecessor schema and must survive the upgrade.
insert into public.e10_supplier_invoices
  (id,organization_id,supplier_id,currency,total_amount)
values
  ('d3000000-0000-4000-8000-000000000002','e1000000-0000-4000-8000-0000000000a6',
   'd3000000-0000-4000-8000-000000000001','CAD',1);

insert into public.e10_supplier_credits
  (id,organization_id,supplier_id,supplier_document_number,currency,total_amount)
values
  ('d3000000-0000-4000-8000-000000000003','e1000000-0000-4000-8000-0000000000a6',
   'd3000000-0000-4000-8000-000000000001','LEGACY-DUP','CAD',1),
  ('d3000000-0000-4000-8000-000000000004','e1000000-0000-4000-8000-0000000000a6',
   'd3000000-0000-4000-8000-000000000001',' legacy-dup ','CAD',2);
