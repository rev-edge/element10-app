-- TA-X3e append-only purchasing comments and audience-safe projections.

alter table public.e10_commercial_comments
  add constraint e10_commercial_comments_body_bounds_chk
  check(length(body) between 1 and 4000 and btrim(body)<>'');

alter table public.e10_commercial_comments add column commercial_event_id uuid;
alter table public.e10_commercial_comments
  add constraint e10_commercial_comments_org_event_fkey
  foreign key(organization_id,commercial_event_id)
  references public.e10_commercial_events(organization_id,id)
  deferrable initially deferred;
create unique index e10_commercial_comments_org_event_uq
  on public.e10_commercial_comments(organization_id,commercial_event_id)
  where commercial_event_id is not null;
create unique index e10_commercial_comments_single_successor_uq
  on public.e10_commercial_comments(organization_id,supersedes_comment_id)
  where supersedes_comment_id is not null;
create index e10_commercial_comments_receipt_idx
  on public.e10_commercial_comments(organization_id,stock_receipt_id,created_at,id)
  where stock_receipt_id is not null;
create index e10_commercial_comments_credit_idx
  on public.e10_commercial_comments(organization_id,supplier_credit_id,created_at,id)
  where supplier_credit_id is not null;

create table public.e10_commercial_comment_commands (
  organization_id uuid not null references public.e10_organizations(id),
  idempotency_key text not null check(length(btrim(idempotency_key)) between 1 and 200),
  operation text not null check(operation in ('create','supersede')),
  comment_id uuid not null,
  commercial_event_id uuid not null,
  request_fingerprint text not null check(btrim(request_fingerprint)<>''),
  result jsonb not null check(jsonb_typeof(result)='object'),
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  primary key(organization_id,idempotency_key),
  unique(organization_id,comment_id),
  unique(organization_id,commercial_event_id),
  foreign key(organization_id,comment_id)
    references public.e10_commercial_comments(organization_id,id)
    deferrable initially deferred,
  foreign key(organization_id,commercial_event_id)
    references public.e10_commercial_events(organization_id,id)
    deferrable initially deferred,
  check(result->>'comment_id' is not distinct from comment_id::text
    and result->>'commercial_event_id' is not distinct from commercial_event_id::text)
);
alter table public.e10_commercial_comment_commands enable row level security;
revoke all on public.e10_commercial_comment_commands from public,anon,authenticated;
grant all on public.e10_commercial_comment_commands to service_role;
create trigger e10_commercial_comment_commands_append_only_trg
  before update or delete on public.e10_commercial_comment_commands
  for each row execute function e10.reject_append_only_change();

alter table public.e10_commercial_events drop constraint e10_commercial_events_event_type_check;
alter table public.e10_commercial_events add constraint e10_commercial_events_event_type_check check(event_type in (
  'acquisition','receipt','available_for_sale','listing_created','listing_published','listing_paused','listing_resumed',
  'listing_ended','listing_relisted','asking_price_changed','hold','release','sale_committed','customer_transaction_posted',
  'fulfillment','fee','payout','refund','return','cost_correction','correction','purchase_order_changed',
  'commercial_comment_changed'));
alter table public.e10_commercial_events add column commercial_comment_command_idempotency_key text;
alter table public.e10_commercial_events add constraint e10_commercial_events_org_comment_command_fkey
  foreign key(organization_id,commercial_comment_command_idempotency_key)
  references public.e10_commercial_comment_commands(organization_id,idempotency_key)
  deferrable initially deferred;
create unique index e10_commercial_events_org_comment_command_uq
  on public.e10_commercial_events(organization_id,commercial_comment_command_idempotency_key)
  where commercial_comment_command_idempotency_key is not null;
insert into public.e10_commercial_event_schemas(event_type,schema_version,required_payload_keys,description)
values('commercial_comment_changed',1,array['comment_id','document_kind','document_id','audience','operation'],
  'Audience-typed purchasing comment evidence. Payload deliberately excludes comment body and financial data.');

create or replace function e10.valid_commercial_event_payload(p_event_type text,p_payload jsonb) returns boolean
language plpgsql immutable set search_path=pg_catalog as $$
declare k text; required_text_keys text[]; amount_value numeric;
begin
  if p_payload is null or jsonb_typeof(p_payload) is distinct from 'object' then return false; end if;
  required_text_keys:=case p_event_type
    when 'acquisition' then array['acquisition_id'] when 'receipt' then array['receipt_id'] when 'available_for_sale' then array['availability_state']
    when 'listing_created' then array['listing_id','channel'] when 'listing_published' then array['listing_id','channel'] when 'listing_paused' then array['listing_id','channel']
    when 'listing_resumed' then array['listing_id','channel'] when 'listing_ended' then array['listing_id','channel'] when 'listing_relisted' then array['listing_id','channel']
    when 'asking_price_changed' then array['listing_id','channel','currency'] when 'hold' then array['hold_id'] when 'release' then array['hold_id']
    when 'sale_committed' then array['sale_id'] when 'customer_transaction_posted' then array['transaction_id'] when 'fulfillment' then array['fulfillment_id']
    when 'fee' then array['fee_id','currency'] when 'payout' then array['payout_id','currency'] when 'refund' then array['refund_id','currency']
    when 'return' then array['return_id'] when 'cost_correction' then array['cost_adjustment_id','currency'] when 'correction' then array['reason']
    when 'purchase_order_changed' then array['purchase_order_id','operation','status','revision']
    when 'commercial_comment_changed' then array['comment_id','document_kind','document_id','audience','operation'] else null end;
  if required_text_keys is null then return false; end if;
  foreach k in array required_text_keys loop
    if jsonb_typeof(p_payload->k) is distinct from 'string' or coalesce(btrim(p_payload->>k),'')='' then return false; end if;
  end loop;
  if p_event_type in ('asking_price_changed','fee','payout','refund','cost_correction') then
    if jsonb_typeof(p_payload->'amount') is distinct from 'number' or coalesce(p_payload->>'currency','')!~'^[A-Z]{3}$' then return false; end if;
    amount_value:=(p_payload->>'amount')::numeric;
    if amount_value<0 or amount_value::text in ('NaN','Infinity','-Infinity') then return false; end if;
  end if;
  return true;
exception when others then return false;
end $$;

create function e10.guard_commercial_comment_command() returns trigger
language plpgsql security definer set search_path=public as $$
begin
  if new.result->>'comment_id' is distinct from new.comment_id::text
    or new.result->>'commercial_event_id' is distinct from new.commercial_event_id::text
    or new.result->>'operation' is distinct from new.operation
    or not exists(select 1 from public.e10_commercial_comments c
      where c.organization_id=new.organization_id and c.id=new.comment_id
        and c.commercial_event_id=new.commercial_event_id)
    or not exists(select 1 from public.e10_commercial_events e
      where e.organization_id=new.organization_id and e.id=new.commercial_event_id
        and e.event_type='commercial_comment_changed'
        and e.commercial_comment_command_idempotency_key=new.idempotency_key) then
    raise exception using errcode='23514',message='commercial_comment_command_link_invalid';
  end if;
  return new;
end $$;

create function e10.guard_commercial_comment_lineage() returns trigger
language plpgsql security definer set search_path=public as $$
declare prior record;
begin
  if new.supersedes_comment_id is null then return new; end if;
  select c.* into prior from public.e10_commercial_comments c
    where c.organization_id=new.organization_id and c.id=new.supersedes_comment_id for update;
  if not found or prior.audience<>new.audience
    or prior.purchase_order_id is distinct from new.purchase_order_id
    or prior.supplier_invoice_id is distinct from new.supplier_invoice_id
    or prior.stock_receipt_id is distinct from new.stock_receipt_id
    or prior.supplier_credit_id is distinct from new.supplier_credit_id then
    raise exception using errcode='23514',message='commercial_comment_lineage_invalid';
  end if;
  return new;
end $$;

create function e10.guard_commercial_comment_event() returns trigger
language plpgsql security definer set search_path=public as $$
declare command_row record; comment_row record; document_kind text; document_id uuid;
begin
  if new.event_type<>'commercial_comment_changed' then
    if new.commercial_comment_command_idempotency_key is not null then
      raise exception using errcode='23514',message='commercial_comment_event_type_invalid';
    end if;
    return new;
  end if;
  if new.commercial_comment_command_idempotency_key is null then
    raise exception using errcode='42501',message='commercial_comment_event_requires_command';
  end if;
  select c.* into command_row from public.e10_commercial_comment_commands c
    where c.organization_id=new.organization_id
      and c.idempotency_key=new.commercial_comment_command_idempotency_key;
  if not found then raise exception using errcode='23514',message='commercial_comment_event_command_invalid'; end if;
  select c.* into comment_row from public.e10_commercial_comments c
    where c.organization_id=new.organization_id and c.id=command_row.comment_id
      and c.commercial_event_id=new.id;
  if not found then raise exception using errcode='23514',message='commercial_comment_event_link_invalid'; end if;
  document_kind:=case when comment_row.purchase_order_id is not null then 'purchase_order'
    when comment_row.supplier_invoice_id is not null then 'supplier_invoice'
    when comment_row.stock_receipt_id is not null then 'stock_receipt'
    else 'supplier_credit' end;
  document_id:=coalesce(comment_row.purchase_order_id,comment_row.supplier_invoice_id,
    comment_row.stock_receipt_id,comment_row.supplier_credit_id);
  if command_row.commercial_event_id<>new.id or command_row.operation is distinct from new.payload->>'operation'
    or new.payload->>'comment_id' is distinct from comment_row.id::text
    or new.payload->>'document_kind' is distinct from document_kind
    or new.payload->>'document_id' is distinct from document_id::text
    or new.payload->>'audience' is distinct from comment_row.audience
    or new.subject_type<>'other' or new.subject_id<>document_id::text
    or new.source_kind<>'manual' or new.source_connection_id is distinct from 'purchasing-comments'
    or new.source_reference is distinct from 'commercial_comment_command'
    or new.source_event_id is distinct from comment_row.id::text
    or new.correlation_id is distinct from document_kind||':'||document_id::text
    or new.evidence_quality<>'operator_asserted'
    or new.created_by is distinct from command_row.created_by
    or new.created_by is distinct from comment_row.created_by then
    raise exception using errcode='23514',message='commercial_comment_event_integrity_invalid';
  end if;
  return new;
end $$;
create trigger e10_commercial_comment_lineage_trg
  before insert on public.e10_commercial_comments
  for each row execute function e10.guard_commercial_comment_lineage();
create trigger e10_commercial_comment_event_guard_trg
  before insert on public.e10_commercial_events
  for each row execute function e10.guard_commercial_comment_event();

create constraint trigger e10_commercial_comment_command_link_trg
  after insert on public.e10_commercial_comment_commands deferrable initially deferred
  for each row execute function e10.guard_commercial_comment_command();
revoke all on function e10.guard_commercial_comment_command() from public,anon,authenticated;
revoke all on function e10.guard_commercial_comment_lineage() from public,anon,authenticated;
revoke all on function e10.guard_commercial_comment_event() from public,anon,authenticated;
grant execute on function e10.guard_commercial_comment_command() to service_role;
grant execute on function e10.guard_commercial_comment_lineage() to service_role;
grant execute on function e10.guard_commercial_comment_event() to service_role;

create function public.e10_org_add_commercial_comment(
  p_org uuid,p_document_kind text,p_document_id uuid,p_audience text,p_body text,
  p_supersedes_comment_id uuid,p_idempotency_key text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare
  actor uuid:=auth.uid(); fp text; existing_cmd record; prior record;
  comment_id uuid:=gen_random_uuid(); event_id uuid:=gen_random_uuid(); result jsonb;
  normalized_key text:=btrim(p_idempotency_key);
  operation text:=case when p_supersedes_comment_id is null then 'create' else 'supersede' end;
begin
  if actor is null or p_org is null
    or not exists(select 1 from public.e10_organizations where id=p_org and status='active')
    or not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.purchasing_prepare') then
    raise exception using errcode='42501',message='commercial_comment_write_denied';
  end if;
  if p_document_kind is null or p_document_kind not in ('purchase_order','supplier_invoice','stock_receipt','supplier_credit')
    or p_document_id is null or p_audience is null or p_audience not in ('internal','vendor')
    or p_body is null or btrim(p_body)='' or length(p_body)>4000
    or p_idempotency_key is null or btrim(p_idempotency_key)='' or length(p_idempotency_key)>200 then
    raise exception using errcode='22023',message='commercial_comment_payload_invalid';
  end if;
  fp:=md5(jsonb_build_object('v','commercial-comment-v1','org',p_org,'document_kind',p_document_kind,
    'document_id',p_document_id,'audience',p_audience,'body',p_body,
    'supersedes_comment_id',p_supersedes_comment_id)::text);
  perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|commercial-comment-command|'||normalized_key,0));
  select c.request_fingerprint,c.result into existing_cmd from public.e10_commercial_comment_commands c
    where c.organization_id=p_org and c.idempotency_key=normalized_key;
  if found then
    if existing_cmd.request_fingerprint<>fp then raise exception using errcode='22023',message='idempotency_key_mismatch'; end if;
    if auth.uid() is distinct from actor
      or not exists(select 1 from public.e10_organizations where id=p_org and status='active')
      or not e10.is_org_member(p_org)
      or not e10.has_org_cap(p_org,'act.purchasing_prepare') then
      raise exception using errcode='42501',message='commercial_comment_write_denied';
    end if;
    return existing_cmd.result||jsonb_build_object('replay',true);
  end if;

  if p_document_kind='purchase_order' then
    perform e10.lock_purchase_order(p_org,p_document_id);
  elsif p_document_kind in ('supplier_invoice','supplier_credit') then
    perform e10.lock_financial_document(p_org,p_document_kind,p_document_id);
  else
    perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|stock-receipt|'||p_document_id::text,0));
    perform 1 from public.e10_stock_receipts where organization_id=p_org and id=p_document_id for update;
    if not found then raise exception using errcode='42501',message='stock_receipt_access_denied'; end if;
  end if;
  if auth.uid() is distinct from actor
    or not exists(select 1 from public.e10_organizations where id=p_org and status='active')
    or not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.purchasing_prepare') then
    raise exception using errcode='42501',message='commercial_comment_write_denied';
  end if;
  if p_supersedes_comment_id is not null then
    select c.* into prior from public.e10_commercial_comments c
      where c.organization_id=p_org and c.id=p_supersedes_comment_id for update;
    if not found or prior.audience<>p_audience
      or (p_document_kind='purchase_order' and prior.purchase_order_id is distinct from p_document_id)
      or (p_document_kind='supplier_invoice' and prior.supplier_invoice_id is distinct from p_document_id)
      or (p_document_kind='stock_receipt' and prior.stock_receipt_id is distinct from p_document_id)
      or (p_document_kind='supplier_credit' and prior.supplier_credit_id is distinct from p_document_id) then
      raise exception using errcode='22023',message='commercial_comment_supersession_invalid';
    end if;
    if exists(select 1 from public.e10_commercial_comments c
      where c.organization_id=p_org and c.supersedes_comment_id=p_supersedes_comment_id) then
      raise exception using errcode='40001',message='commercial_comment_supersession_conflict';
    end if;
  end if;

  result:=jsonb_build_object('ok',true,'replay',false,'comment_id',comment_id,
    'commercial_event_id',event_id,'operation',operation,'audience',p_audience,
    'document_kind',p_document_kind,'document_id',p_document_id);
  insert into public.e10_commercial_comment_commands(organization_id,idempotency_key,operation,
    comment_id,commercial_event_id,request_fingerprint,result,created_by)
  values(p_org,normalized_key,operation,comment_id,event_id,fp,result,actor);
  insert into public.e10_commercial_comments(id,organization_id,audience,body,purchase_order_id,
    supplier_invoice_id,stock_receipt_id,supplier_credit_id,supersedes_comment_id,created_by,commercial_event_id)
  values(comment_id,p_org,p_audience,p_body,
    case when p_document_kind='purchase_order' then p_document_id end,
    case when p_document_kind='supplier_invoice' then p_document_id end,
    case when p_document_kind='stock_receipt' then p_document_id end,
    case when p_document_kind='supplier_credit' then p_document_id end,
    p_supersedes_comment_id,actor,event_id);
  insert into public.e10_commercial_events(id,organization_id,event_type,event_schema_version,subject_type,
    subject_id,occurred_at,occurred_at_precision,idempotency_key,source_kind,source_connection_id,
    source_reference,source_event_id,correlation_id,evidence_quality,payload,created_by,request_fingerprint,
    commercial_comment_command_idempotency_key)
  values(event_id,p_org,'commercial_comment_changed',1,'other',p_document_id::text,now(),'exact',
    'commercial-comment:'||normalized_key,'manual','purchasing-comments','commercial_comment_command',comment_id::text,
    p_document_kind||':'||p_document_id::text,'operator_asserted',jsonb_build_object('comment_id',comment_id,
      'document_kind',p_document_kind,'document_id',p_document_id,'audience',p_audience,'operation',operation),
    actor,md5('commercial-comment-event|'||fp),normalized_key);
  return result;
end $$;

create function public.e10_org_list_commercial_comments(
  p_org uuid,p_document_kind text,p_document_id uuid,p_limit integer default 50,
  p_before_created_at timestamptz default null,p_before_id uuid default null
) returns jsonb language plpgsql stable security definer set search_path=public as $$
declare rows jsonb;
begin
  if auth.uid() is null or not e10.is_org_member(p_org) then raise exception using errcode='42501',message='commercial_comment_read_denied'; end if;
  if p_document_kind not in ('purchase_order','supplier_invoice','stock_receipt','supplier_credit')
    or p_document_id is null or p_limit is null or p_limit not between 1 and 100
    or ((p_before_created_at is null)<>(p_before_id is null))
    or (p_before_created_at is not null and not isfinite(p_before_created_at)) then
    raise exception using errcode='22023',message='commercial_comment_page_invalid';
  end if;
  select coalesce(jsonb_agg(to_jsonb(q) order by q.created_at desc,q.id desc),'[]'::jsonb) into rows from(
    select c.id,c.audience,c.body,c.supersedes_comment_id,c.created_by,c.created_at,
      not exists(select 1 from public.e10_commercial_comments n
        where n.organization_id=c.organization_id and n.supersedes_comment_id=c.id) as effective
    from public.e10_commercial_comments c where c.organization_id=p_org
      and case p_document_kind when 'purchase_order' then c.purchase_order_id=p_document_id
        when 'supplier_invoice' then c.supplier_invoice_id=p_document_id
        when 'stock_receipt' then c.stock_receipt_id=p_document_id
        when 'supplier_credit' then c.supplier_credit_id=p_document_id else false end
      and (p_before_created_at is null or (c.created_at,c.id)<(p_before_created_at,p_before_id))
    order by c.created_at desc,c.id desc limit p_limit
  )q;
  return jsonb_build_object('document_kind',p_document_kind,'document_id',p_document_id,'items',rows,'limit',p_limit);
end $$;

create function public.e10_org_vendor_comment_projection(
  p_org uuid,p_document_kind text,p_document_id uuid,p_limit integer default 50
) returns jsonb language plpgsql stable security definer set search_path=public as $$
declare document_status text; document_reference text; rows jsonb;
begin
  if auth.uid() is null or not e10.is_org_member(p_org) then raise exception using errcode='42501',message='vendor_comment_projection_denied'; end if;
  if p_document_kind not in ('purchase_order','supplier_invoice','stock_receipt','supplier_credit')
    or p_document_id is null or p_limit is null or p_limit not between 1 and 100 then
    raise exception using errcode='22023',message='vendor_comment_projection_invalid';
  end if;
  if p_document_kind='purchase_order' then
    select status,order_number into document_status,document_reference from public.e10_purchase_orders where organization_id=p_org and id=p_document_id;
  elsif p_document_kind='supplier_invoice' then
    select status,supplier_document_number into document_status,document_reference from public.e10_supplier_invoices where organization_id=p_org and id=p_document_id;
  elsif p_document_kind='stock_receipt' then
    select status,receipt_number into document_status,document_reference from public.e10_stock_receipts where organization_id=p_org and id=p_document_id;
  else
    select status,supplier_document_number into document_status,document_reference from public.e10_supplier_credits where organization_id=p_org and id=p_document_id;
  end if;
  if not found then raise exception using errcode='42501',message='vendor_comment_projection_denied'; end if;
  select coalesce(jsonb_agg(jsonb_build_object('body',q.body) order by q.created_at,q.id),'[]'::jsonb) into rows from(
    select c.id,c.body,c.created_at from public.e10_commercial_comments c
    where c.organization_id=p_org and c.audience='vendor'
      and case p_document_kind when 'purchase_order' then c.purchase_order_id=p_document_id
        when 'supplier_invoice' then c.supplier_invoice_id=p_document_id
        when 'stock_receipt' then c.stock_receipt_id=p_document_id
        when 'supplier_credit' then c.supplier_credit_id=p_document_id else false end
      and not exists(select 1 from public.e10_commercial_comments n
        where n.organization_id=c.organization_id and n.supersedes_comment_id=c.id)
    order by c.created_at,c.id limit p_limit
  )q;
  return jsonb_build_object('document_kind',p_document_kind,'document_id',p_document_id,
    'document_status',document_status,'document_reference',document_reference,'vendor_comments',rows,'limit',p_limit);
end $$;

revoke all on function public.e10_org_add_commercial_comment(uuid,text,uuid,text,text,uuid,text) from public,anon;
revoke all on function public.e10_org_list_commercial_comments(uuid,text,uuid,integer,timestamptz,uuid) from public,anon;
revoke all on function public.e10_org_vendor_comment_projection(uuid,text,uuid,integer) from public,anon;
grant execute on function public.e10_org_add_commercial_comment(uuid,text,uuid,text,text,uuid,text) to authenticated,service_role;
grant execute on function public.e10_org_list_commercial_comments(uuid,text,uuid,integer,timestamptz,uuid) to authenticated,service_role;
grant execute on function public.e10_org_vendor_comment_projection(uuid,text,uuid,integer) to authenticated,service_role;

comment on function public.e10_org_vendor_comment_projection(uuid,text,uuid,integer) is
  'Vendor-safe allowlist only: document identity/status/reference and effective vendor bodies. No delivery channel.';
