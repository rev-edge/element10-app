-- BILL-07/08/09/10/17 durable vendor document capture and reviewed extraction.
begin;
do $$
declare
 o uuid:=gen_random_uuid();actor uuid:=gen_random_uuid();role_id uuid:=gen_random_uuid();doc uuid;changed_doc uuid;attempt uuid;r jsonb;review jsonb;
 source jsonb:=jsonb_build_object('connection','fixture-provider','external_id','vendor-doc-1','revision','1','payload_fingerprint','source-fp-1');
 attachment jsonb:=jsonb_build_object('storage_bucket','vendor-documents','storage_path','org/test/invoice.pdf','content_sha256',repeat('a',64),'mime_type','application/pdf','byte_size',1234,'page_count',2);
begin
 insert into auth.users(id,instance_id,aud,role,email,created_at,updated_at)values(actor,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','vendor-doc-'||actor||'@example.invalid',now(),now());
 insert into public.e10_organizations(id,name,slug)values(o,'Vendor document org','vendor-doc-'||substr(o::text,1,8));
 insert into public.e10_organization_roles(id,organization_id,key,name)values(role_id,o,'vendor-doc','Vendor document');
 insert into public.e10_organization_memberships(organization_id,user_id,role_id,status)values(o,actor,role_id,'active');
 insert into public.e10_organization_role_permissions(organization_id,role_id,capability,allowed)values(o,role_id,'act.purchasing_prepare',true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',actor,'role','authenticated')::text,true);set local role authenticated;
 r:=public.e10_org_capture_vendor_document(o,'manual_upload','unknown',source,attachment,'capture-1');doc:=(r->>'document_id')::uuid;
 if r->>'replay'<>'false'or r->>'domain_write_performed'<>'false'then raise exception 'capture invalid: %',r;end if;
 if(public.e10_org_capture_vendor_document(o,'api','supplier_invoice',source,attachment,'capture-1-retry')->>'document_id')<>doc::text then raise exception 'content replay duplicated document';end if;
 attachment:=attachment||jsonb_build_object('storage_path','org/test/invoice-changed.pdf','content_sha256',repeat('b',64));
  source:=source||jsonb_build_object('payload_fingerprint','source-fp-2');
  r:=public.e10_org_capture_vendor_document(o,'api','supplier_invoice',source,attachment,'capture-2');changed_doc:=(r->>'document_id')::uuid;
  reset role;
  if changed_doc=doc or not exists(select 1 from public.e10_vendor_document_events e where e.organization_id=o and e.document_id=changed_doc and e.event_type='duplicate_candidate')then raise exception 'changed content did not become durable candidate';end if;

  perform set_config('request.jwt.claims',jsonb_build_object('sub',actor,'role','service_role')::text,true);set local role service_role;
 r:=public.e10_org_record_vendor_extraction(o,changed_doc,'deterministic_fixture','fixture-v1','failed','{"text":"untrusted"}',null,'fixture_failure','retryable fixture failure',clock_timestamp());
 r:=public.e10_org_record_vendor_extraction(o,changed_doc,'deterministic_fixture','fixture-v1','succeeded','{"text":"invoice total 12.00"}',
   '{"document_type":"supplier_invoice","total":{"value":12.00,"confidence":0.51,"source":{"page":1,"text":"12.00"}},"lines":[]}',null,null,clock_timestamp());
 attempt:=(r->>'attempt_id')::uuid;
 if r->>'attempt_no'<>'2'or(select count(*)from public.e10_vendor_extraction_attempts where organization_id=o and document_id=changed_doc)<>2 then raise exception 'extraction retry history invalid';end if;
 reset role;

 perform set_config('request.jwt.claims',jsonb_build_object('sub',actor,'role','authenticated')::text,true);set local role authenticated;
  review:=public.e10_org_review_vendor_document(o,changed_doc,attempt,'order_confirmation',
   '{"document_type":"order_confirmation","supplier_document_number":"CONF-1","lines":[]}',
   '[{"field":"document_type","from":"supplier_invoice","to":"order_confirmation","source":"operator"}]',
   'ready_for_domain_writer','review-1');
  if review->>'next_action'<>'use_existing_domain_writer'or review->>'domain_write_performed'<>'false'or review->>'payment_status'<>'unavailable_not_modeled' then raise exception 'review boundary invalid: %',review;end if;
  reset role;
  if(select reviewed_document_type from public.e10_vendor_document_reviews where id=(review->>'review_id')::uuid)<>'order_confirmation'then raise exception 'operator correction not preserved';end if;
  if exists(select 1 from public.e10_supplier_invoices where organization_id=o)or exists(select 1 from public.e10_inventory_lots where organization_id=o)then raise exception 'extraction/review posted domain data';end if;
 if has_function_privilege('anon','public.e10_org_capture_vendor_document(uuid,text,text,jsonb,jsonb,text)','execute')
  or has_function_privilege('authenticated','public.e10_org_record_vendor_extraction(uuid,uuid,text,text,text,jsonb,jsonb,text,text,timestamptz)','execute')then raise exception 'document ACL invalid';end if;
 raise notice 'Vendor document capture: PASS (exact replay, changed-content candidate, retry history, reviewed correction, zero posting)';
end$$;
rollback;
