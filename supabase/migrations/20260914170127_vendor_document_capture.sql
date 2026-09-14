-- Durable, tenant-scoped vendor document capture and reviewed extraction.
-- Extraction is advisory only: it cannot create finance, stock, or payment facts.

create table public.e10_vendor_documents(
 id uuid primary key default gen_random_uuid(),organization_id uuid not null references public.e10_organizations(id),
 channel text not null check(channel in('manual_upload','email','api','edi','structured_import')),
 document_type text not null default'unknown' check(document_type in('unknown','supplier_invoice','supplier_credit','purchase_receipt','order_confirmation','packing_slip')),
 source_connection text,external_document_id text,source_revision text,source_payload_fingerprint text,
 content_sha256 text not null check(content_sha256~'^[0-9a-f]{64}$'),received_at timestamptz not null default clock_timestamp(),
 created_by uuid not null references auth.users(id),created_at timestamptz not null default clock_timestamp(),
 unique(organization_id,id),unique(organization_id,content_sha256),
 check((source_connection is null and external_document_id is null)or(source_connection is not null and btrim(source_connection)<>''and external_document_id is not null and btrim(external_document_id)<>''and source_payload_fingerprint is not null and btrim(source_payload_fingerprint)<>''))
);
create unique index e10_vendor_documents_source_revision_uq on public.e10_vendor_documents(organization_id,source_connection,external_document_id,coalesce(source_revision,''),source_payload_fingerprint)where source_connection is not null;

create table public.e10_vendor_document_attachments(
 id uuid primary key default gen_random_uuid(),organization_id uuid not null,document_id uuid not null,
 storage_bucket text not null check(btrim(storage_bucket)<>''),storage_path text not null check(btrim(storage_path)<>''),
 content_sha256 text not null check(content_sha256~'^[0-9a-f]{64}$'),mime_type text not null check(btrim(mime_type)<>''),
 byte_size bigint not null check(byte_size between 1 and 52428800),page_count integer check(page_count between 1 and 1000),created_at timestamptz not null default clock_timestamp(),
 unique(organization_id,id),unique(organization_id,storage_bucket,storage_path),
 foreign key(organization_id,document_id)references public.e10_vendor_documents(organization_id,id)on delete cascade
);

create table public.e10_vendor_document_events(
 id uuid primary key default gen_random_uuid(),organization_id uuid not null,document_id uuid not null,
 event_type text not null check(event_type in('received','processing_started','extraction_succeeded','extraction_failed','classification_corrected','reviewed','duplicate_candidate','linked')),
 detail jsonb not null default'{}'check(jsonb_typeof(detail)='object'),actor_id uuid references auth.users(id),created_at timestamptz not null default clock_timestamp(),
 unique(organization_id,id),foreign key(organization_id,document_id)references public.e10_vendor_documents(organization_id,id)on delete cascade
);

create table public.e10_vendor_extraction_attempts(
 id uuid primary key default gen_random_uuid(),organization_id uuid not null,document_id uuid not null,
 attempt_no integer not null check(attempt_no>0),provider_key text not null check(btrim(provider_key)<>''),extractor_version text not null check(btrim(extractor_version)<>''),
 status text not null check(status in('succeeded','failed')),raw_result jsonb,normalized_draft jsonb,error_code text,error_detail text,
 started_at timestamptz not null,finished_at timestamptz not null default clock_timestamp(),
 unique(organization_id,id),unique(organization_id,document_id,attempt_no),
 foreign key(organization_id,document_id)references public.e10_vendor_documents(organization_id,id)on delete cascade,
 check((status='succeeded'and normalized_draft is not null and jsonb_typeof(normalized_draft)='object'and error_code is null)
   or(status='failed'and normalized_draft is null and error_code is not null and btrim(error_code)<>''))
);

create table public.e10_vendor_document_reviews(
 id uuid primary key default gen_random_uuid(),organization_id uuid not null,document_id uuid not null,extraction_attempt_id uuid,
 reviewed_document_type text not null check(reviewed_document_type in('supplier_invoice','supplier_credit','purchase_receipt','order_confirmation','packing_slip')),
 reviewed_payload jsonb not null check(jsonb_typeof(reviewed_payload)='object'),corrections jsonb not null default'[]'check(jsonb_typeof(corrections)='array'),
 disposition text not null check(disposition in('ready_for_domain_writer','needs_more_information','duplicate_candidate','rejected')),
 idempotency_key text not null,request_fingerprint text not null,reviewed_by uuid not null references auth.users(id),reviewed_at timestamptz not null default clock_timestamp(),
 unique(organization_id,id),unique(organization_id,document_id),unique(organization_id,idempotency_key),
 foreign key(organization_id,document_id)references public.e10_vendor_documents(organization_id,id)on delete cascade,
 foreign key(organization_id,extraction_attempt_id)references public.e10_vendor_extraction_attempts(organization_id,id)
);

create table public.e10_vendor_inbound_messages(
 id uuid primary key default gen_random_uuid(),organization_id uuid not null references public.e10_organizations(id),
 connection_key text not null check(btrim(connection_key)<>''),message_kind text not null check(message_kind in('vendor_order','order_confirmation','supplier_invoice','supplier_credit')),
 external_id text not null check(btrim(external_id)<>''),external_revision text not null default'',payload_fingerprint text not null check(btrim(payload_fingerprint)<>''),
 payload jsonb not null check(jsonb_typeof(payload)='object'),document_id uuid,received_at timestamptz not null default clock_timestamp(),
 unique(organization_id,id),unique(organization_id,connection_key,message_kind,external_id,external_revision),
 foreign key(organization_id,document_id)references public.e10_vendor_documents(organization_id,id)
);

do $$declare t text;begin foreach t in array array['e10_vendor_documents','e10_vendor_document_attachments','e10_vendor_document_events','e10_vendor_extraction_attempts','e10_vendor_document_reviews','e10_vendor_inbound_messages']loop
 execute format('alter table public.%I enable row level security',t);execute format('revoke all on public.%I from public,anon,authenticated',t);execute format('grant all on public.%I to service_role',t);end loop;end$$;
create trigger e10_vendor_documents_append_only_trg before update or delete on public.e10_vendor_documents for each row execute function e10.reject_append_only_change();
create trigger e10_vendor_attachments_append_only_trg before update or delete on public.e10_vendor_document_attachments for each row execute function e10.reject_append_only_change();
create trigger e10_vendor_events_append_only_trg before update or delete on public.e10_vendor_document_events for each row execute function e10.reject_append_only_change();
create trigger e10_vendor_attempts_append_only_trg before update or delete on public.e10_vendor_extraction_attempts for each row execute function e10.reject_append_only_change();
create trigger e10_vendor_reviews_append_only_trg before update or delete on public.e10_vendor_document_reviews for each row execute function e10.reject_append_only_change();
create trigger e10_vendor_inbound_append_only_trg before update or delete on public.e10_vendor_inbound_messages for each row execute function e10.reject_append_only_change();

create function public.e10_org_capture_vendor_document(p_org uuid,p_channel text,p_document_type text,p_source jsonb,p_attachment jsonb,p_idempotency_key text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare actor uuid:=auth.uid();hash text:=lower(p_attachment->>'content_sha256');existing record;new_id uuid:=gen_random_uuid();source_fp text;
begin
 if actor is null or not e10.is_org_member(p_org)or not e10.has_org_cap(p_org,'act.purchasing_prepare')then raise exception using errcode='42501',message='vendor_document_capture_denied';end if;
 if p_channel not in('manual_upload','email','api','edi','structured_import')or p_document_type not in('unknown','supplier_invoice','supplier_credit','purchase_receipt','order_confirmation','packing_slip')
  or p_source is null or jsonb_typeof(p_source)<>'object'or p_attachment is null or jsonb_typeof(p_attachment)<>'object'or hash!~'^[0-9a-f]{64}$'
  or coalesce(p_attachment->>'storage_bucket','')=''or coalesce(p_attachment->>'storage_path','')=''or coalesce(p_attachment->>'mime_type','')=''
  or(p_attachment->>'byte_size')is null or(p_attachment->>'byte_size')::bigint not between 1 and 52428800 or coalesce(btrim(p_idempotency_key),'')=''then raise exception using errcode='22023',message='vendor_document_capture_payload_invalid';end if;
 source_fp:=coalesce(nullif(p_source->>'payload_fingerprint',''),md5(p_source::text));
 perform pg_advisory_xact_lock(hashtextextended(p_org||'|vendor-document|'||hash,0));
 select d.* into existing from public.e10_vendor_documents d where d.organization_id=p_org and d.content_sha256=hash;
 if found then return jsonb_build_object('ok',true,'replay',true,'document_id',existing.id,'state','received','domain_write_performed',false);end if;
 if auth.uid()is distinct from actor or not e10.is_org_member(p_org)or not e10.has_org_cap(p_org,'act.purchasing_prepare')then raise exception using errcode='42501',message='vendor_document_capture_denied';end if;
 insert into public.e10_vendor_documents(id,organization_id,channel,document_type,source_connection,external_document_id,source_revision,source_payload_fingerprint,content_sha256,created_by)
 values(new_id,p_org,p_channel,p_document_type,nullif(p_source->>'connection',''),nullif(p_source->>'external_id',''),p_source->>'revision',source_fp,hash,actor);
 insert into public.e10_vendor_document_attachments(organization_id,document_id,storage_bucket,storage_path,content_sha256,mime_type,byte_size,page_count)
 values(p_org,new_id,p_attachment->>'storage_bucket',p_attachment->>'storage_path',hash,p_attachment->>'mime_type',(p_attachment->>'byte_size')::bigint,(p_attachment->>'page_count')::integer);
 insert into public.e10_vendor_document_events(organization_id,document_id,event_type,detail,actor_id)values(p_org,new_id,'received',jsonb_build_object('channel',p_channel,'idempotency_key',p_idempotency_key),actor);
 if exists(select 1 from public.e10_vendor_documents d where d.organization_id=p_org and d.id<>new_id and d.external_document_id=nullif(p_source->>'external_id',''))then
  insert into public.e10_vendor_document_events(organization_id,document_id,event_type,detail,actor_id)values(p_org,new_id,'duplicate_candidate',jsonb_build_object('reason','same_external_identity_or_cross_channel'),actor);end if;
 return jsonb_build_object('ok',true,'replay',false,'document_id',new_id,'state','received','domain_write_performed',false);
end$$;

create function public.e10_org_record_vendor_extraction(p_org uuid,p_document uuid,p_provider text,p_version text,p_status text,p_raw jsonb,p_draft jsonb,p_error_code text,p_error_detail text,p_started_at timestamptz)
returns jsonb language plpgsql security definer set search_path=public as $$
declare n integer;new_id uuid:=gen_random_uuid();
begin
 if auth.role()<>'service_role'then raise exception using errcode='42501',message='vendor_extraction_service_only';end if;
 if not exists(select 1 from public.e10_vendor_documents d where d.organization_id=p_org and d.id=p_document)or p_status not in('succeeded','failed')then raise exception using errcode='22023',message='vendor_extraction_payload_invalid';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_org||'|vendor-extraction|'||p_document,0));
 select coalesce(max(a.attempt_no),0)+1 into n from public.e10_vendor_extraction_attempts a where a.organization_id=p_org and a.document_id=p_document;
 insert into public.e10_vendor_extraction_attempts(id,organization_id,document_id,attempt_no,provider_key,extractor_version,status,raw_result,normalized_draft,error_code,error_detail,started_at)
 values(new_id,p_org,p_document,n,p_provider,p_version,p_status,p_raw,p_draft,p_error_code,p_error_detail,p_started_at);
 insert into public.e10_vendor_document_events(organization_id,document_id,event_type,detail)values(p_org,p_document,case when p_status='succeeded'then'extraction_succeeded'else'extraction_failed'end,jsonb_build_object('attempt_id',new_id,'attempt_no',n,'provider',p_provider,'version',p_version));
 return jsonb_build_object('ok',true,'attempt_id',new_id,'attempt_no',n,'domain_write_performed',false);
end$$;

create function public.e10_org_review_vendor_document(p_org uuid,p_document uuid,p_attempt uuid,p_document_type text,p_reviewed_payload jsonb,p_corrections jsonb,p_disposition text,p_idempotency_key text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare actor uuid:=auth.uid();fp text;r record;new_id uuid:=gen_random_uuid();
begin
 if actor is null or not e10.is_org_member(p_org)or not e10.has_org_cap(p_org,'act.purchasing_prepare')then raise exception using errcode='42501',message='vendor_document_review_denied';end if;
 if p_document_type not in('supplier_invoice','supplier_credit','purchase_receipt','order_confirmation','packing_slip')or p_reviewed_payload is null or jsonb_typeof(p_reviewed_payload)<>'object'or p_corrections is null or jsonb_typeof(p_corrections)<>'array'or p_disposition not in('ready_for_domain_writer','needs_more_information','duplicate_candidate','rejected')or coalesce(btrim(p_idempotency_key),'')=''then raise exception using errcode='22023',message='vendor_document_review_payload_invalid';end if;
 fp:=md5(jsonb_build_array('vendor-document-review-v1',p_org,p_document,p_attempt,p_document_type,p_reviewed_payload,p_corrections,p_disposition)::text);
 perform pg_advisory_xact_lock(hashtextextended(p_org||'|vendor-document-review|'||p_document,0));
 select * into r from public.e10_vendor_document_reviews x where x.organization_id=p_org and(x.document_id=p_document or x.idempotency_key=p_idempotency_key);
 if found then if r.request_fingerprint<>fp then raise exception using errcode='22023',message='vendor_document_already_reviewed';end if;return jsonb_build_object('ok',true,'replay',true,'review_id',r.id,'disposition',r.disposition,'domain_write_performed',false);end if;
 if not exists(select 1 from public.e10_vendor_documents d where d.organization_id=p_org and d.id=p_document)or(p_attempt is not null and not exists(select 1 from public.e10_vendor_extraction_attempts a where a.organization_id=p_org and a.document_id=p_document and a.id=p_attempt and a.status='succeeded'))then raise exception using errcode='42501',message='vendor_document_review_source_denied';end if;
 if auth.uid()is distinct from actor or not e10.is_org_member(p_org)or not e10.has_org_cap(p_org,'act.purchasing_prepare')then raise exception using errcode='42501',message='vendor_document_review_denied';end if;
 insert into public.e10_vendor_document_reviews values(new_id,p_org,p_document,p_attempt,p_document_type,p_reviewed_payload,p_corrections,p_disposition,p_idempotency_key,fp,actor,clock_timestamp());
 insert into public.e10_vendor_document_events(organization_id,document_id,event_type,detail,actor_id)values(p_org,p_document,'reviewed',jsonb_build_object('review_id',new_id,'disposition',p_disposition),actor);
 return jsonb_build_object('ok',true,'replay',false,'review_id',new_id,'disposition',p_disposition,'next_action',case when p_disposition='ready_for_domain_writer'then'use_existing_domain_writer'else'none'end,'domain_write_performed',false,'payment_status','unavailable_not_modeled');
end$$;

revoke all on function public.e10_org_capture_vendor_document(uuid,text,text,jsonb,jsonb,text),public.e10_org_record_vendor_extraction(uuid,uuid,text,text,text,jsonb,jsonb,text,text,timestamptz),public.e10_org_review_vendor_document(uuid,uuid,uuid,text,jsonb,jsonb,text,text)from public,anon;
grant execute on function public.e10_org_capture_vendor_document(uuid,text,text,jsonb,jsonb,text),public.e10_org_review_vendor_document(uuid,uuid,uuid,text,jsonb,jsonb,text,text)to authenticated,service_role;
grant execute on function public.e10_org_record_vendor_extraction(uuid,uuid,text,text,text,jsonb,jsonb,text,text,timestamptz)to service_role;

comment on table public.e10_vendor_documents is 'Immutable original vendor-document identity; current state is derived from append-only events and review.';
comment on table public.e10_vendor_extraction_attempts is 'Provider-neutral extraction attempts. Results are untrusted drafts and never post finance, stock, or payment facts.';
comment on table public.e10_vendor_inbound_messages is 'Typed inbound envelope. An order confirmation never becomes a payable automatically.';
