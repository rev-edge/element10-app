-- Bounded bill detail, reviewed-document linkage, and typed inbound replay.

alter table public.e10_vendor_inbound_messages
  drop constraint e10_vendor_inbound_messages_organization_id_connection_key__key;
alter table public.e10_vendor_inbound_messages
  add constraint e10_vendor_inbound_messages_identity_fingerprint_uq
  unique(organization_id,connection_key,message_kind,external_id,external_revision,payload_fingerprint);

create function public.e10_org_record_vendor_inbound(p_org uuid,p_connection text,p_kind text,p_external_id text,p_external_revision text,p_fingerprint text,p_payload jsonb,p_document uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare existing record;new_id uuid:=gen_random_uuid();conflict boolean;
begin
 if auth.role()<>'service_role'then raise exception using errcode='42501',message='vendor_inbound_service_only';end if;
 if coalesce(btrim(p_connection),'')=''or p_kind not in('vendor_order','order_confirmation','supplier_invoice','supplier_credit')or coalesce(btrim(p_external_id),'')=''or coalesce(btrim(p_fingerprint),'')=''or p_payload is null or jsonb_typeof(p_payload)<>'object'then raise exception using errcode='22023',message='vendor_inbound_payload_invalid';end if;
 if p_document is not null and not exists(select 1 from public.e10_vendor_documents d where d.organization_id=p_org and d.id=p_document)then raise exception using errcode='42501',message='vendor_inbound_document_denied';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_org||'|vendor-inbound|'||p_connection||'|'||p_kind||'|'||p_external_id||'|'||coalesce(p_external_revision,''),0));
 select m.* into existing from public.e10_vendor_inbound_messages m where m.organization_id=p_org and m.connection_key=btrim(p_connection)and m.message_kind=p_kind and m.external_id=btrim(p_external_id)and m.external_revision=coalesce(p_external_revision,'')and m.payload_fingerprint=btrim(p_fingerprint);
 if found then return jsonb_build_object('ok',true,'replay',true,'message_id',existing.id,'conflict',false,'payable_created',false,'stock_changed',false);end if;
 conflict:=exists(select 1 from public.e10_vendor_inbound_messages m where m.organization_id=p_org and m.connection_key=btrim(p_connection)and m.message_kind=p_kind and m.external_id=btrim(p_external_id)and m.external_revision=coalesce(p_external_revision,''));
 insert into public.e10_vendor_inbound_messages(id,organization_id,connection_key,message_kind,external_id,external_revision,payload_fingerprint,payload,document_id)
 values(new_id,p_org,btrim(p_connection),p_kind,btrim(p_external_id),coalesce(p_external_revision,''),btrim(p_fingerprint),p_payload,p_document);
 if conflict and p_document is not null then insert into public.e10_vendor_document_events(organization_id,document_id,event_type,detail)values(p_org,p_document,'duplicate_candidate',jsonb_build_object('reason','changed_payload_same_external_revision','inbound_message_id',new_id));end if;
 return jsonb_build_object('ok',true,'replay',false,'message_id',new_id,'conflict',conflict,'next_action',case when conflict then'review_changed_payload'else'review_document'end,'payable_created',false,'stock_changed',false);
end$$;

create function public.e10_org_link_vendor_document(p_org uuid,p_document uuid,p_domain_kind text,p_domain_id uuid,p_idempotency_key text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare actor uuid:=auth.uid();existing record;new_id uuid:=gen_random_uuid();
begin
 if actor is null or not e10.is_org_member(p_org)or not e10.has_org_cap(p_org,'act.purchasing_prepare')then raise exception using errcode='42501',message='vendor_document_link_denied';end if;
 if p_domain_kind not in('supplier_invoice','supplier_credit','stock_receipt','purchase_order')or coalesce(btrim(p_idempotency_key),'')=''then raise exception using errcode='22023',message='vendor_document_link_payload_invalid';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_org||'|vendor-document-link|'||p_document,0));
 select e.* into existing from public.e10_vendor_document_events e where e.organization_id=p_org and e.document_id=p_document and e.event_type='linked';
 if found then
  if existing.detail->>'domain_kind'<>p_domain_kind or existing.detail->>'domain_id'<>p_domain_id::text then raise exception using errcode='22023',message='vendor_document_already_linked';end if;
  return jsonb_build_object('ok',true,'replay',true,'event_id',existing.id);
 end if;
 if not exists(select 1 from public.e10_vendor_document_reviews r where r.organization_id=p_org and r.document_id=p_document and r.disposition='ready_for_domain_writer')
  or(p_domain_kind='supplier_invoice'and not exists(select 1 from public.e10_supplier_invoices i where i.organization_id=p_org and i.id=p_domain_id))
  or(p_domain_kind='supplier_credit'and not exists(select 1 from public.e10_supplier_credits c where c.organization_id=p_org and c.id=p_domain_id))
  or(p_domain_kind='stock_receipt'and not exists(select 1 from public.e10_stock_receipts r where r.organization_id=p_org and r.id=p_domain_id))
  or(p_domain_kind='purchase_order'and not exists(select 1 from public.e10_purchase_orders po where po.organization_id=p_org and po.id=p_domain_id))then raise exception using errcode='42501',message='vendor_document_link_target_denied';end if;
 if auth.uid()is distinct from actor or not e10.is_org_member(p_org)or not e10.has_org_cap(p_org,'act.purchasing_prepare')then raise exception using errcode='42501',message='vendor_document_link_denied';end if;
 insert into public.e10_vendor_document_events(id,organization_id,document_id,event_type,detail,actor_id)values(new_id,p_org,p_document,'linked',jsonb_build_object('domain_kind',p_domain_kind,'domain_id',p_domain_id,'idempotency_key',p_idempotency_key),actor);
 return jsonb_build_object('ok',true,'replay',false,'event_id',new_id,'domain_kind',p_domain_kind,'domain_id',p_domain_id);
end$$;

create function public.e10_org_bill_detail(p_org uuid,p_invoice uuid,p_line_limit integer default 100,p_after_line_no integer default null)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare actor uuid:=auth.uid();header jsonb;lines jsonb;more boolean;history jsonb;documents jsonb;
begin
 if actor is null or not exists(select 1 from public.e10_organizations where id=p_org and status='active')or not e10.is_org_member(p_org)or not e10.has_org_cap(p_org,'financial.actual_cost.read')then raise exception using errcode='42501',message='bill_detail_denied';end if;
 if p_line_limit not between 1 and 200 then raise exception using errcode='22023',message='bill_detail_bounds_invalid';end if;
 select jsonb_build_object('invoice_id',i.id,'supplier_id',i.supplier_id,'supplier_name',s.name,'supplier_document_number',i.supplier_document_number,'document_date',i.document_date,'currency',i.currency,'total_amount',i.total_amount,'document_status',i.status,'revision',i.revision,'payment_status','unavailable_not_modeled','source_connection',i.source_connection,'external_document_id',i.external_document_id)
 into header from public.e10_supplier_invoices i join public.e10_suppliers s on(s.organization_id,s.id)=(i.organization_id,i.supplier_id)where i.organization_id=p_org and i.id=p_invoice;
 if header is null then raise exception using errcode='42501',message='bill_detail_access_denied';end if;
 with page as(select l.* from public.e10_supplier_invoice_lines l where l.organization_id=p_org and l.supplier_invoice_id=p_invoice and(p_after_line_no is null or l.line_no>p_after_line_no)order by l.line_no,l.id limit p_line_limit+1),shown as(select * from page order by line_no,id limit p_line_limit)
 select coalesce(jsonb_agg(jsonb_build_object('invoice_line_id',l.id,'line_no',l.line_no,'description',l.description,'configuration_version_id',l.configuration_version_id,'configuration_name',pc.name,'product_id',pm.id,'product_name',pm.name,'invoiced_quantity',l.invoiced_quantity,'unit_cost',l.unit_cost,'line_amount',l.line_amount,
  'purchase_order_allocations',coalesce((select jsonb_agg(jsonb_build_object('purchase_order_line_id',a.purchase_order_line_id,'purchase_order_id',pol.purchase_order_id,'order_number',po.order_number,'allocated_quantity',a.allocated_quantity)order by po.created_at,po.id)from public.e10_invoice_po_allocations a join public.e10_purchase_order_lines pol on(pol.organization_id,pol.id)=(a.organization_id,a.purchase_order_line_id)join public.e10_purchase_orders po on(po.organization_id,po.id)=(pol.organization_id,pol.purchase_order_id)where a.organization_id=p_org and a.invoice_line_id=l.id),'[]'),
  'receipt_allocations',coalesce((select jsonb_agg(jsonb_build_object('receipt_line_id',a.receipt_line_id,'stock_receipt_id',rl.stock_receipt_id,'receipt_number',r.receipt_number,'allocated_quantity',a.allocated_quantity,'receipt_status',r.status)order by r.received_at,r.id)from public.e10_receipt_invoice_allocations a join public.e10_stock_receipt_lines rl on(rl.organization_id,rl.id)=(a.organization_id,a.receipt_line_id)join public.e10_stock_receipts r on(r.organization_id,r.id)=(rl.organization_id,rl.stock_receipt_id)where a.organization_id=p_org and a.invoice_line_id=l.id),'[]'),
  'credit_allocations',coalesce((select jsonb_agg(jsonb_build_object('supplier_credit_id',cl.supplier_credit_id,'credit_line_id',a.credit_line_id,'allocated_amount',a.allocated_amount,'credit_status',c.status)order by c.created_at,c.id)from public.e10_credit_invoice_allocations a join public.e10_supplier_credit_lines cl on(cl.organization_id,cl.id)=(a.organization_id,a.credit_line_id)join public.e10_supplier_credits c on(c.organization_id,c.id)=(cl.organization_id,cl.supplier_credit_id)where a.organization_id=p_org and a.invoice_line_id=l.id),'[]'))order by l.line_no,l.id),'[]'),(select count(*)>p_line_limit from page)into lines,more
 from shown l left join public.e10_product_configuration_versions v on(v.organization_id,v.id)=(l.organization_id,l.configuration_version_id)left join public.e10_product_configurations pc on(pc.organization_id,pc.id)=(v.organization_id,v.configuration_id)left join public.e10_product_masters pm on(pm.organization_id,pm.id)=(pc.organization_id,pc.product_master_id);
 select coalesce(jsonb_agg(jsonb_build_object('revision',r.revision,'status',r.status,'change_reason',r.change_reason,'created_by',r.created_by,'created_at',r.created_at)order by r.revision),'[]')into history from public.e10_supplier_invoice_revisions r where r.organization_id=p_org and r.supplier_invoice_id=p_invoice;
 select coalesce(jsonb_agg(jsonb_build_object('document_id',e.document_id,'content_sha256',d.content_sha256,'channel',d.channel,'event_id',e.id)order by e.created_at,e.id),'[]')into documents from public.e10_vendor_document_events e join public.e10_vendor_documents d on(d.organization_id,d.id)=(e.organization_id,e.document_id)where e.organization_id=p_org and e.event_type='linked'and e.detail->>'domain_kind'='supplier_invoice'and e.detail->>'domain_id'=p_invoice::text;
 return jsonb_build_object('header',header,'lines',lines,'line_has_more',more,'line_next_after',case when more then(lines->-1->>'line_no')::integer end,'history',history,'source_documents',documents,'payment_status','unavailable_not_modeled');
end$$;

revoke all on function public.e10_org_record_vendor_inbound(uuid,text,text,text,text,text,jsonb,uuid),public.e10_org_link_vendor_document(uuid,uuid,text,uuid,text),public.e10_org_bill_detail(uuid,uuid,integer,integer)from public,anon;
grant execute on function public.e10_org_record_vendor_inbound(uuid,text,text,text,text,text,jsonb,uuid)to service_role;
grant execute on function public.e10_org_link_vendor_document(uuid,uuid,text,uuid,text),public.e10_org_bill_detail(uuid,uuid,integer,integer)to authenticated,service_role;
