-- TA-X3f bounded supplier purchasing workspace and accepted actual-cost evidence reads.
-- No payment/accounting state, currency conversion, cost allocation, or write path is implied.

create index e10_stock_receipts_org_supplier_created_idx
  on public.e10_stock_receipts(organization_id,supplier_id,created_at desc,id desc);
create index e10_supplier_credits_org_supplier_created_idx
  on public.e10_supplier_credits(organization_id,supplier_id,created_at desc,id desc);

create function e10.supplier_open_commitment_summary(p_org uuid,p_supplier uuid,p_currency text)returns jsonb
language sql stable security definer set search_path=public as $$
 with receipt_allocations as(
  select a.purchase_order_line_id,a.allocated_quantity,rl.accepted_quantity,
   count(*)over(partition by a.organization_id,a.receipt_line_id)n,
   sum(a.allocated_quantity)over(partition by a.organization_id,a.receipt_line_id)allocated_total
  from public.e10_receipt_po_allocations a
  join public.e10_stock_receipt_lines rl on(rl.organization_id,rl.id)=(a.organization_id,a.receipt_line_id)
  join public.e10_stock_receipts sr on(sr.organization_id,sr.id)=(rl.organization_id,rl.stock_receipt_id)
  where a.organization_id=p_org and sr.status in('posted','corrected')
   and not exists(select 1 from public.e10_stock_receipt_reversals rv where rv.organization_id=rl.organization_id and rv.stock_receipt_line_id=rl.id)
 ),received as(
  select purchase_order_line_id,
   sum(case when allocated_total<=accepted_quantity then allocated_quantity when n=1 then accepted_quantity end)accepted_quantity,
   bool_or(allocated_total>accepted_quantity and n>1)ambiguous
  from receipt_allocations group by purchase_order_line_id
 ),open_lines as(
  select l.id,l.estimated_unit_cost,
   case when coalesce(r.ambiguous,false)then null else greatest(l.ordered_quantity-coalesce(r.accepted_quantity,0),0)end outstanding,
   coalesce(r.ambiguous,false)ambiguous
  from public.e10_purchase_order_lines l join public.e10_purchase_orders po on(po.organization_id,po.id)=(l.organization_id,l.purchase_order_id)
  left join received r on r.purchase_order_line_id=l.id
  where po.organization_id=p_org and po.supplier_id=p_supplier and po.currency=p_currency
   and po.status in('submitted','approved')and l.state='active'
 ),stats as(select coalesce(sum(outstanding*estimated_unit_cost)filter(where not ambiguous and outstanding>0 and estimated_unit_cost is not null),0)known,
  count(*)filter(where not ambiguous and outstanding>0 and estimated_unit_cost is null)unknown_lines,
  coalesce(sum(outstanding)filter(where not ambiguous and outstanding>0 and estimated_unit_cost is null),0)unknown_quantity,
  count(*)filter(where ambiguous)ambiguous_lines from open_lines)
 select jsonb_build_object('known_subtotal',known,'unknown_outstanding_line_count',unknown_lines,
  'unknown_outstanding_quantity',unknown_quantity,'ambiguous_allocation_line_count',ambiguous_lines,
  'status',case when unknown_lines>0 or ambiguous_lines>0 then'incomplete'else'complete'end,
  'estimate',case when unknown_lines=0 and ambiguous_lines=0 then known end)from stats
$$;
revoke all on function e10.supplier_open_commitment_summary(uuid,uuid,text)from public,anon,authenticated;
grant execute on function e10.supplier_open_commitment_summary(uuid,uuid,text)to service_role;

create function e10.purchase_order_open_commitment_summary(p_org uuid,p_purchase_order uuid)returns jsonb
language sql stable security definer set search_path=public as $$
 with receipt_allocations as(
  select a.purchase_order_line_id,a.allocated_quantity,rl.accepted_quantity,
   count(*)over(partition by a.organization_id,a.receipt_line_id)n,
   sum(a.allocated_quantity)over(partition by a.organization_id,a.receipt_line_id)allocated_total
  from public.e10_receipt_po_allocations a
  join public.e10_stock_receipt_lines rl on(rl.organization_id,rl.id)=(a.organization_id,a.receipt_line_id)
  join public.e10_stock_receipts sr on(sr.organization_id,sr.id)=(rl.organization_id,rl.stock_receipt_id)
  where a.organization_id=p_org and sr.status in('posted','corrected')
   and not exists(select 1 from public.e10_stock_receipt_reversals rv where rv.organization_id=rl.organization_id and rv.stock_receipt_line_id=rl.id)
 ),received as(
  select purchase_order_line_id,
   sum(case when allocated_total<=accepted_quantity then allocated_quantity when n=1 then accepted_quantity end)accepted_quantity,
   bool_or(allocated_total>accepted_quantity and n>1)ambiguous
  from receipt_allocations group by purchase_order_line_id
 ),lines as(
  select l.ordered_quantity,l.estimated_unit_cost,
   case when po.status not in('submitted','approved')then 0
    when coalesce(r.ambiguous,false)then null else greatest(l.ordered_quantity-coalesce(r.accepted_quantity,0),0)end outstanding,
   po.status in('submitted','approved')and coalesce(r.ambiguous,false)ambiguous
  from public.e10_purchase_order_lines l join public.e10_purchase_orders po on(po.organization_id,po.id)=(l.organization_id,l.purchase_order_id)
  left join received r on r.purchase_order_line_id=l.id
  where l.organization_id=p_org and l.purchase_order_id=p_purchase_order and l.state='active'
 ),stats as(select
  coalesce(sum(ordered_quantity*estimated_unit_cost)filter(where estimated_unit_cost is not null),0)ordered_known,
  count(*)filter(where estimated_unit_cost is null)ordered_unknown_lines,
  coalesce(sum(outstanding*estimated_unit_cost)filter(where not ambiguous and outstanding>0 and estimated_unit_cost is not null),0)known,
  count(*)filter(where not ambiguous and outstanding>0 and estimated_unit_cost is null)unknown_lines,
  coalesce(sum(outstanding)filter(where not ambiguous and outstanding>0 and estimated_unit_cost is null),0)unknown_quantity,
  count(*)filter(where ambiguous)ambiguous_lines from lines)
 select jsonb_build_object(
  'ordered_known_subtotal',ordered_known,'ordered_unknown_line_count',ordered_unknown_lines,
  'ordered_status',case when ordered_unknown_lines>0 then'incomplete'else'complete'end,
  'ordered_estimate',case when ordered_unknown_lines=0 then ordered_known end,
  'known_subtotal',known,'unknown_outstanding_line_count',unknown_lines,
  'unknown_outstanding_quantity',unknown_quantity,'ambiguous_allocation_line_count',ambiguous_lines,
  'status',case when unknown_lines>0 or ambiguous_lines>0 then'incomplete'else'complete'end,
  'estimate',case when unknown_lines=0 and ambiguous_lines=0 then known end)from stats
$$;
revoke all on function e10.purchase_order_open_commitment_summary(uuid,uuid)from public,anon,authenticated;
grant execute on function e10.purchase_order_open_commitment_summary(uuid,uuid)to service_role;

create function public.e10_org_supplier_workspace(
  p_org uuid,p_supplier_id uuid,p_limit integer default 50,p_cursor text default null
) returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare c jsonb;cursor_at timestamptz;cursor_kind text;cursor_id uuid;can_fin boolean;items jsonb;last_at timestamptz;last_kind text;last_id uuid;more boolean;
begin
 if not exists(select 1 from public.e10_organizations where id=p_org and status='active')or not e10.is_org_member(p_org)then raise exception using errcode='42501',message='supplier_workspace_denied';end if;
 if p_supplier_id is null or p_limit is null or p_limit not between 1 and 100 or not exists(
  select 1 from public.e10_suppliers s where s.organization_id=p_org and s.id=p_supplier_id
 )then raise exception using errcode='22023',message='supplier_workspace_bounds_invalid';end if;
 can_fin:=e10.has_org_cap(p_org,'financial.actual_cost.read');
 if p_cursor is not null then
  begin c:=e10.inventory_cursor_decode(p_org,p_cursor);cursor_at:=(c->>'at')::timestamptz;cursor_kind:=c->>'kind';cursor_id:=(c->>'id')::uuid;
   if c->>'scope'is distinct from'supplier-workspace-v1'or(c->>'supplier_id')::uuid is distinct from p_supplier_id
    or(c->>'financial')::boolean is distinct from can_fin or cursor_at is null or not isfinite(cursor_at)
    or cursor_kind is null or cursor_kind not in('purchase_order','stock_receipt','supplier_invoice','supplier_credit')or cursor_id is null
   then raise exception using errcode='22023',message='supplier_workspace_cursor_mismatch';end if;
  exception when others then raise exception using errcode='22023',message='supplier_workspace_cursor_invalid';end;
 end if;
 with headers as(
  select po.created_at,'purchase_order'::text kind,po.id from public.e10_purchase_orders po where po.organization_id=p_org and po.supplier_id=p_supplier_id
  union all select r.created_at,'stock_receipt',r.id from public.e10_stock_receipts r where r.organization_id=p_org and r.supplier_id=p_supplier_id
  union all select i.created_at,'supplier_invoice',i.id from public.e10_supplier_invoices i where can_fin and i.organization_id=p_org and i.supplier_id=p_supplier_id
  union all select cr.created_at,'supplier_credit',cr.id from public.e10_supplier_credits cr where can_fin and cr.organization_id=p_org and cr.supplier_id=p_supplier_id
 ),page as(select * from headers where p_cursor is null or(created_at,kind,id)<(cursor_at,cursor_kind,cursor_id)
  order by created_at desc,kind desc,id desc limit p_limit+1),shown as(select * from page order by created_at desc,kind desc,id desc limit p_limit),
 hydrated as(select h.*,
  case h.kind
   when'purchase_order'then(select jsonb_build_object('kind',h.kind,'id',po.id,'supplier_id',po.supplier_id,'status',po.status,'revision',po.revision,'order_number',po.order_number,'destination_location_id',po.destination_location_id,'expected_at',po.expected_at,'created_at',po.created_at,'currency',po.currency,
    'financial_access',case when can_fin then'authorized'else'not_authorized'end,
    'ordered_estimate_known_subtotal',case when can_fin then ps.pstat->'ordered_known_subtotal'end,
    'ordered_estimate_unknown_line_count',case when can_fin then ps.pstat->'ordered_unknown_line_count'end,
    'ordered_estimate_status',case when can_fin then ps.pstat->>'ordered_status'else'not_authorized'end,
    'ordered_estimate_total',case when can_fin then ps.pstat->'ordered_estimate'end,
    'open_commitment_known_subtotal',case when can_fin then ps.pstat->'known_subtotal'end,
    'open_commitment_unknown_line_count',case when can_fin then ps.pstat->'unknown_outstanding_line_count'end,
    'open_commitment_unknown_quantity',case when can_fin then ps.pstat->'unknown_outstanding_quantity'end,
    'open_commitment_ambiguous_line_count',case when can_fin then ps.pstat->'ambiguous_allocation_line_count'end,
    'open_commitment_status',case when can_fin then ps.pstat->>'status'else'not_authorized'end,
    'open_commitment_estimate',case when can_fin then ps.pstat->'estimate'end,
    'line_count',x.line_count,'line_ids',x.line_ids,'line_ids_truncated',x.line_count>20,'payment_status','unavailable_not_modeled')
    from public.e10_purchase_orders po
    cross join lateral(select e10.purchase_order_open_commitment_summary(p_org,h.id)pstat)ps
    cross join lateral(select count(*)line_count,coalesce((select jsonb_agg(q.id order by q.line_no,q.id)from(select id,line_no from public.e10_purchase_order_lines where organization_id=p_org and purchase_order_id=h.id order by line_no,id limit 20)q),'[]')line_ids
     from public.e10_purchase_order_lines l where l.organization_id=p_org and l.purchase_order_id=h.id)x where po.organization_id=p_org and po.id=h.id)
   when'stock_receipt'then(select jsonb_build_object('kind',h.kind,'id',r.id,'supplier_id',r.supplier_id,'status',r.status,'receipt_number',r.receipt_number,'destination_location_id',r.destination_location_id,'received_at',r.received_at,'created_at',r.created_at,
    'financial_access',case when can_fin then'authorized'else'not_authorized'end,'accepted_quantity',case when can_fin then x.accepted_quantity end,'line_count',x.line_count,'line_ids',x.line_ids,'line_ids_truncated',x.line_count>20,'payment_status','unavailable_not_modeled')
    from public.e10_stock_receipts r cross join lateral(select count(*)line_count,sum(l.accepted_quantity)accepted_quantity,
     coalesce((select jsonb_agg(q.id order by q.line_no,q.id)from(select id,line_no from public.e10_stock_receipt_lines where organization_id=p_org and stock_receipt_id=h.id order by line_no,id limit 20)q),'[]')line_ids
     from public.e10_stock_receipt_lines l where l.organization_id=p_org and l.stock_receipt_id=h.id)x where r.organization_id=p_org and r.id=h.id)
   when'supplier_invoice'then(select jsonb_build_object('kind',h.kind,'id',i.id,'supplier_id',i.supplier_id,'status',i.status,'revision',i.revision,'supplier_document_number',i.supplier_document_number,'document_date',i.document_date,'currency',i.currency,'total_amount',i.total_amount,'source_connection',i.source_connection,'external_document_id',i.external_document_id,'created_at',i.created_at,'financial_access','authorized','line_count',x.line_count,'line_ids',x.line_ids,'line_ids_truncated',x.line_count>20,'payment_status','unavailable_not_modeled')
    from public.e10_supplier_invoices i cross join lateral(select count(*)line_count,coalesce((select jsonb_agg(q.id order by q.line_no,q.id)from(select id,line_no from public.e10_supplier_invoice_lines where organization_id=p_org and supplier_invoice_id=h.id order by line_no,id limit 20)q),'[]')line_ids from public.e10_supplier_invoice_lines l where l.organization_id=p_org and l.supplier_invoice_id=h.id)x where i.organization_id=p_org and i.id=h.id)
   when'supplier_credit'then(select jsonb_build_object('kind',h.kind,'id',cr.id,'supplier_id',cr.supplier_id,'status',cr.status,'revision',cr.revision,'supplier_document_number',cr.supplier_document_number,'document_date',cr.document_date,'currency',cr.currency,'total_amount',cr.total_amount,'source_connection',cr.source_connection,'external_document_id',cr.external_document_id,'created_at',cr.created_at,'financial_access','authorized','line_count',x.line_count,'line_ids',x.line_ids,'line_ids_truncated',x.line_count>20,'payment_status','unavailable_not_modeled')
    from public.e10_supplier_credits cr cross join lateral(select count(*)line_count,coalesce((select jsonb_agg(q.id order by q.line_no,q.id)from(select id,line_no from public.e10_supplier_credit_lines where organization_id=p_org and supplier_credit_id=h.id order by line_no,id limit 20)q),'[]')line_ids from public.e10_supplier_credit_lines l where l.organization_id=p_org and l.supplier_credit_id=h.id)x where cr.organization_id=p_org and cr.id=h.id)
  end body from shown h)
 select coalesce(jsonb_agg(body order by created_at desc,kind desc,id desc),'[]'),(select count(*)from page)>p_limit,
  (select created_at from shown order by created_at,kind,id limit 1),(select kind from shown order by created_at,kind,id limit 1),(select id from shown order by created_at,kind,id limit 1)
 into items,more,last_at,last_kind,last_id from hydrated;
 return jsonb_build_object('supplier_id',p_supplier_id,'financial_access',case when can_fin then'authorized'else'not_authorized'end,
  'payment_status','unavailable_not_modeled','financial_summary',case when can_fin then(
   with currencies as(
    select currency from public.e10_purchase_orders where organization_id=p_org and supplier_id=p_supplier_id
    union select currency from public.e10_supplier_invoices where organization_id=p_org and supplier_id=p_supplier_id
    union select currency from public.e10_supplier_credits where organization_id=p_org and supplier_id=p_supplier_id
   )select coalesce(jsonb_agg(jsonb_build_object('currency',currency,
    'open_commitment_known_subtotal',oc->'known_subtotal','open_commitment_unknown_line_count',oc->'unknown_outstanding_line_count',
    'open_commitment_unknown_quantity',oc->'unknown_outstanding_quantity','open_commitment_ambiguous_line_count',oc->'ambiguous_allocation_line_count',
    'open_commitment_status',oc->>'status','open_commitment_estimate',oc->'estimate',
    'approved_invoice_amount',coalesce((select sum(total_amount)from public.e10_supplier_invoices i where i.organization_id=p_org and i.supplier_id=p_supplier_id and i.currency=currencies.currency and i.status='approved'),0),
    'approved_credit_amount',coalesce((select sum(total_amount)from public.e10_supplier_credits cr where cr.organization_id=p_org and cr.supplier_id=p_supplier_id and cr.currency=currencies.currency and cr.status='approved'),0),
    'allocated_approved_credit_amount',coalesce((select sum(ca.allocated_amount)from public.e10_credit_invoice_allocations ca
      join public.e10_supplier_credit_lines cl on(cl.organization_id,cl.id)=(ca.organization_id,ca.credit_line_id)
      join public.e10_supplier_credits cr on(cr.organization_id,cr.id)=(cl.organization_id,cl.supplier_credit_id)
      join public.e10_supplier_invoice_lines il on(il.organization_id,il.id)=(ca.organization_id,ca.invoice_line_id)
      join public.e10_supplier_invoices i on(i.organization_id,i.id)=(il.organization_id,il.supplier_invoice_id)
      where cr.organization_id=p_org and cr.supplier_id=p_supplier_id and cr.currency=currencies.currency and cr.status='approved'
       and i.supplier_id=p_supplier_id and i.currency=currencies.currency and i.status='approved'and cl.state='active'and il.state='active'),0),
    'net_approved_invoice_amount',coalesce((select sum(total_amount)from public.e10_supplier_invoices i where i.organization_id=p_org and i.supplier_id=p_supplier_id and i.currency=currencies.currency and i.status='approved'),0)-coalesce((select sum(ca.allocated_amount)from public.e10_credit_invoice_allocations ca
      join public.e10_supplier_credit_lines cl on(cl.organization_id,cl.id)=(ca.organization_id,ca.credit_line_id)
      join public.e10_supplier_credits cr on(cr.organization_id,cr.id)=(cl.organization_id,cl.supplier_credit_id)
      join public.e10_supplier_invoice_lines il on(il.organization_id,il.id)=(ca.organization_id,ca.invoice_line_id)
      join public.e10_supplier_invoices i on(i.organization_id,i.id)=(il.organization_id,il.supplier_invoice_id)
      where cr.organization_id=p_org and cr.supplier_id=p_supplier_id and cr.currency=currencies.currency and cr.status='approved'
       and i.supplier_id=p_supplier_id and i.currency=currencies.currency and i.status='approved'and cl.state='active'and il.state='active'),0),
    'unused_approved_credit_amount',coalesce((select sum(greatest(cl.line_amount-coalesce(a.used,0),0))from public.e10_supplier_credit_lines cl join public.e10_supplier_credits cr on(cr.organization_id,cr.id)=(cl.organization_id,cl.supplier_credit_id)
      left join lateral(select sum(ca.allocated_amount)used from public.e10_credit_invoice_allocations ca where ca.organization_id=cl.organization_id and ca.credit_line_id=cl.id) a on true
      where cr.organization_id=p_org and cr.supplier_id=p_supplier_id and cr.currency=currencies.currency and cr.status='approved'and cl.state='active'),0),
    'payment_status','unavailable_not_modeled')order by currency),'[]')from currencies
     cross join lateral(select e10.supplier_open_commitment_summary(p_org,p_supplier_id,currencies.currency)oc)x)else null end,
  'items',items,'has_more',more,'next_cursor',case when more and last_id is not null then e10.inventory_cursor_encode(p_org,jsonb_build_object('scope','supplier-workspace-v1','supplier_id',p_supplier_id,'financial',can_fin,'at',last_at,'kind',last_kind,'id',last_id))end);
end $$;

create function public.e10_org_supplier_actual_cost_history(
 p_org uuid,p_supplier_id uuid,p_configuration_version_id uuid,p_currency text,p_as_of timestamptz,
 p_limit integer default 50,p_cursor text default null
)returns jsonb language plpgsql stable security definer set search_path=public as $$
declare c jsonb;cursor_at timestamptz;cursor_id uuid;items jsonb;more boolean;last_row record;
begin
 if not exists(select 1 from public.e10_organizations where id=p_org and status='active')or not e10.is_org_member(p_org)or not e10.has_org_cap(p_org,'financial.actual_cost.read')then raise exception using errcode='42501',message='supplier_actual_cost_denied';end if;
 if p_supplier_id is null or p_configuration_version_id is null or p_currency is null or p_currency!~'^[A-Z]{3}$'
  or p_as_of is null or not isfinite(p_as_of)or p_limit is null or p_limit not between 1 and 100
  or not exists(select 1 from public.e10_suppliers where organization_id=p_org and id=p_supplier_id)
  or not exists(select 1 from public.e10_product_configuration_versions where organization_id=p_org and id=p_configuration_version_id)
 then raise exception using errcode='22023',message='supplier_actual_cost_bounds_invalid';end if;
 if p_cursor is not null then begin c:=e10.inventory_cursor_decode(p_org,p_cursor);cursor_at:=(c->>'received_at')::timestamptz;cursor_id:=(c->>'receipt_line_id')::uuid;
  if c->>'scope'is distinct from'supplier-actual-cost-v1'or(c->>'supplier_id')::uuid is distinct from p_supplier_id
   or(c->>'configuration_version_id')::uuid is distinct from p_configuration_version_id or c->>'currency'is distinct from p_currency
   or(c->>'as_of')::timestamptz is distinct from p_as_of or cursor_at is null or not isfinite(cursor_at)or cursor_id is null
  then raise exception using errcode='22023',message='supplier_actual_cost_cursor_mismatch';end if;
  exception when others then raise exception using errcode='22023',message='supplier_actual_cost_cursor_invalid';end;end if;
 with eligible as(select rl.id receipt_line_id,sr.id receipt_id,rl.inventory_lot_id,rl.configuration_version_id,sr.supplier_id,
  rl.accepted_quantity,rl.actual_unit_cost,rl.currency,sr.received_at,rl.created_at
  from public.e10_stock_receipt_lines rl join public.e10_stock_receipts sr on(sr.organization_id,sr.id)=(rl.organization_id,rl.stock_receipt_id)
  where rl.organization_id=p_org and sr.supplier_id=p_supplier_id and rl.configuration_version_id=p_configuration_version_id
   and rl.currency=p_currency and rl.actual_unit_cost is not null and rl.accepted_quantity>0 and sr.status in('posted','corrected')
   and sr.received_at<=p_as_of and not exists(select 1 from public.e10_stock_receipt_reversals rv where rv.organization_id=rl.organization_id and rv.stock_receipt_line_id=rl.id)
   and(p_cursor is null or(sr.received_at,rl.id)<(cursor_at,cursor_id))),
 page as(select * from eligible order by received_at desc,receipt_line_id desc limit p_limit+1),shown as(select * from page order by received_at desc,receipt_line_id desc limit p_limit)
 select coalesce(jsonb_agg(jsonb_build_object('source_kind','accepted_stock_receipt','supplier_id',supplier_id,'configuration_version_id',configuration_version_id,
  'receipt_id',receipt_id,'receipt_line_id',receipt_line_id,'inventory_lot_id',inventory_lot_id,'accepted_quantity',accepted_quantity,
  'actual_unit_cost',actual_unit_cost,'currency',currency,'received_at',received_at)order by received_at desc,receipt_line_id desc),'[]'),(select count(*)from page)>p_limit
 into items,more from shown;
 with eligible as(select sr.received_at,rl.id from public.e10_stock_receipt_lines rl join public.e10_stock_receipts sr on(sr.organization_id,sr.id)=(rl.organization_id,rl.stock_receipt_id)
  where rl.organization_id=p_org and sr.supplier_id=p_supplier_id and rl.configuration_version_id=p_configuration_version_id and rl.currency=p_currency and rl.actual_unit_cost is not null and rl.accepted_quantity>0 and sr.status in('posted','corrected')and sr.received_at<=p_as_of
   and not exists(select 1 from public.e10_stock_receipt_reversals rv where rv.organization_id=rl.organization_id and rv.stock_receipt_line_id=rl.id)
   and(p_cursor is null or(sr.received_at,rl.id)<(cursor_at,cursor_id))order by sr.received_at desc,rl.id desc limit p_limit)
 select received_at,id into last_row from eligible order by received_at,id limit 1;
 return jsonb_build_object('supplier_id',p_supplier_id,'configuration_version_id',p_configuration_version_id,'currency',p_currency,
  'as_of',p_as_of,'conversion','none_exact_currency_only','items',items,'has_more',more,'next_cursor',case when more and last_row.id is not null then e10.inventory_cursor_encode(p_org,jsonb_build_object('scope','supplier-actual-cost-v1','supplier_id',p_supplier_id,'configuration_version_id',p_configuration_version_id,'currency',p_currency,'as_of',p_as_of,'received_at',last_row.received_at,'receipt_line_id',last_row.id))end);
end $$;

revoke all on function public.e10_org_supplier_workspace(uuid,uuid,integer,text),public.e10_org_supplier_actual_cost_history(uuid,uuid,uuid,text,timestamptz,integer,text)from public,anon;
grant execute on function public.e10_org_supplier_workspace(uuid,uuid,integer,text),public.e10_org_supplier_actual_cost_history(uuid,uuid,uuid,text,timestamptz,integer,text)to authenticated,service_role;
