-- TA-X3c purchase-order lifecycle. Purchasing authority is distinct from receiving.

alter table public.e10_purchase_orders
  add column approved_revision integer,
  add column approved_by uuid references auth.users(id),
  add column approved_at timestamptz,
  add column cancelled_by uuid references auth.users(id),
  add column cancelled_at timestamptz,
  add column closed_by uuid references auth.users(id),
  add column closed_at timestamptz,
  add constraint e10_purchase_orders_approval_state_chk check (
    (status='approved' and ((approved_revision is null and approved_by is null and approved_at is null)
      or (approved_revision=revision and approved_by is not null and approved_at is not null)))
    or status<>'approved'),
  add constraint e10_purchase_orders_cancel_state_chk check (
    (status='cancelled' and ((cancelled_by is null and cancelled_at is null)
      or (cancelled_by is not null and cancelled_at is not null)))
    or status<>'cancelled'),
  add constraint e10_purchase_orders_close_state_chk check (
    (status='closed' and ((closed_by is null and closed_at is null)
      or (closed_by is not null and closed_at is not null)))
    or status<>'closed');

alter table public.e10_purchase_order_lines
  add column state text not null default 'active' check(state in ('active','cancelled'));
alter table public.e10_purchase_order_lines
  drop constraint e10_purchase_order_lines_organization_id_purchase_order_id__key,
  add constraint e10_purchase_order_lines_org_po_line_no_uq
    unique(organization_id,purchase_order_id,line_no) deferrable initially immediate;

create table public.e10_purchase_order_commands (
  organization_id uuid not null references public.e10_organizations(id),
  idempotency_key text not null check(btrim(idempotency_key)<>''),
  operation text not null check(operation in ('create','amend','submit','approve','cancel','close')),
  purchase_order_id uuid not null,
  request_fingerprint text not null check(btrim(request_fingerprint)<>''),
  result jsonb not null check(jsonb_typeof(result)='object'),
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  primary key(organization_id,idempotency_key),
  foreign key(organization_id,purchase_order_id)
    references public.e10_purchase_orders(organization_id,id)
);
alter table public.e10_purchase_order_commands enable row level security;
revoke all on public.e10_purchase_order_commands from public,anon,authenticated;
grant all on public.e10_purchase_order_commands to service_role;
create trigger e10_purchase_order_commands_append_only_trg
  before update or delete on public.e10_purchase_order_commands
  for each row execute function e10.reject_append_only_change();

-- These capabilities intentionally receive no role grants in this migration.
comment on table public.e10_purchase_order_commands is
  'Idempotent PO command receipts. act.purchasing_prepare, act.purchasing_approve and act.purchasing_cancel have zero default grants.';

alter table public.e10_commercial_events drop constraint e10_commercial_events_event_type_check;
alter table public.e10_commercial_events add constraint e10_commercial_events_event_type_check check(event_type in (
  'acquisition','receipt','available_for_sale','listing_created','listing_published','listing_paused','listing_resumed',
  'listing_ended','listing_relisted','asking_price_changed','hold','release','sale_committed','customer_transaction_posted',
  'fulfillment','fee','payout','refund','return','cost_correction','correction','purchase_order_changed'));
alter table public.e10_commercial_events add column purchase_order_command_idempotency_key text;
alter table public.e10_commercial_events add constraint e10_commercial_events_org_po_command_fkey
  foreign key(organization_id,purchase_order_command_idempotency_key)
  references public.e10_purchase_order_commands(organization_id,idempotency_key)
  deferrable initially deferred;
create unique index e10_commercial_events_org_po_command_uq
  on public.e10_commercial_events(organization_id,purchase_order_command_idempotency_key)
  where purchase_order_command_idempotency_key is not null;
insert into public.e10_commercial_event_schemas(event_type,schema_version,required_payload_keys,description)
values('purchase_order_changed',1,array['purchase_order_id','operation','status','revision'],
  'Purchase-order lifecycle evidence. It does not assert receipt, payment or accounting recognition.');

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
    when 'purchase_order_changed' then array['purchase_order_id','operation','status','revision'] else null end;
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

create function e10.lock_purchase_order(p_org uuid,p_purchase_order_id uuid) returns void
language plpgsql security definer set search_path=public as $$
declare r record;
begin
  perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|purchase-order|'||p_purchase_order_id::text,0));
  perform 1 from public.e10_purchase_orders where organization_id=p_org and id=p_purchase_order_id for update;
  if not found then raise exception using errcode='42501',message='purchase_order_access_denied'; end if;
  for r in select id from public.e10_purchase_order_lines where organization_id=p_org and purchase_order_id=p_purchase_order_id order by id for update loop perform r.id; end loop;
  for r in select a.organization_id,a.invoice_line_id,a.purchase_order_line_id from public.e10_invoice_po_allocations a
    join public.e10_purchase_order_lines l on l.organization_id=a.organization_id and l.id=a.purchase_order_line_id
    where l.organization_id=p_org and l.purchase_order_id=p_purchase_order_id order by a.invoice_line_id,a.purchase_order_line_id for update of a loop perform r.invoice_line_id; end loop;
  for r in select a.organization_id,a.receipt_line_id,a.purchase_order_line_id from public.e10_receipt_po_allocations a
    join public.e10_purchase_order_lines l on l.organization_id=a.organization_id and l.id=a.purchase_order_line_id
    where l.organization_id=p_org and l.purchase_order_id=p_purchase_order_id order by a.receipt_line_id,a.purchase_order_line_id for update of a loop perform r.receipt_line_id; end loop;
  for r in select a.id from public.e10_expected_inventory_allocations a
    join public.e10_purchase_order_lines l on l.organization_id=a.organization_id and l.id=a.purchase_order_line_id
    where l.organization_id=p_org and l.purchase_order_id=p_purchase_order_id order by a.id for update of a loop perform r.id; end loop;
end $$;
revoke all on function e10.lock_purchase_order(uuid,uuid) from public,anon,authenticated;
grant execute on function e10.lock_purchase_order(uuid,uuid) to service_role;

create function e10.purchase_order_snapshot(p_org uuid,p_purchase_order_id uuid) returns jsonb
language sql stable security definer set search_path=public as $$
  select jsonb_build_object(
    'id',p.id,'organization_id',p.organization_id,'supplier_id',p.supplier_id,
    'destination_location_id',p.destination_location_id,'order_number',p.order_number,
    'revision',p.revision,'status',p.status,'currency',p.currency,'expected_at',p.expected_at,
    'approved_revision',p.approved_revision,
    'lines',coalesce((select jsonb_agg(jsonb_build_object('id',l.id,'line_no',l.line_no,
      'configuration_version_id',l.configuration_version_id,'ordered_quantity',l.ordered_quantity,
      'estimated_unit_cost',l.estimated_unit_cost,'state',l.state) order by l.line_no,l.id)
      from public.e10_purchase_order_lines l where l.organization_id=p.organization_id and l.purchase_order_id=p.id),'[]'::jsonb))
  from public.e10_purchase_orders p where p.organization_id=p_org and p.id=p_purchase_order_id
$$;
revoke all on function e10.purchase_order_snapshot(uuid,uuid) from public,anon,authenticated;
grant execute on function e10.purchase_order_snapshot(uuid,uuid) to service_role;

create function e10.guard_purchase_order_event() returns trigger
language plpgsql security definer set search_path=public as $$
begin
  if new.event_type='purchase_order_changed' then
    if new.purchase_order_command_idempotency_key is null or new.subject_type<>'other'
      or not exists(
        select 1 from public.e10_purchase_order_commands c
        join public.e10_purchase_order_revisions r
          on r.organization_id=c.organization_id and r.purchase_order_id=c.purchase_order_id
          and r.revision=(c.result->>'revision')::integer
        where c.organization_id=new.organization_id
          and c.idempotency_key=new.purchase_order_command_idempotency_key
          and c.purchase_order_id::text=new.subject_id
          and c.operation=new.payload->>'operation'
          and c.result->>'status'=new.payload->>'status'
          and c.result->>'revision'=new.payload->>'revision'
          and new.payload->>'purchase_order_id'=c.purchase_order_id::text)
    then raise exception using errcode='42501',message='purchase_order_event_link_invalid'; end if;
  elsif new.purchase_order_command_idempotency_key is not null then
    raise exception using errcode='23514',message='purchase_order_event_link_type_invalid';
  end if;
  return new;
end $$;
revoke all on function e10.guard_purchase_order_event() from public,anon,authenticated;
grant execute on function e10.guard_purchase_order_event() to service_role;
create trigger e10_purchase_order_event_link_trg before insert on public.e10_commercial_events
  for each row execute function e10.guard_purchase_order_event();

create function e10.lock_purchase_order_line(p_org uuid,p_purchase_order_line_id uuid) returns uuid
language plpgsql security definer set search_path=public as $$
declare v_purchase_order_id uuid;
begin
  select purchase_order_id into v_purchase_order_id
  from public.e10_purchase_order_lines
  where organization_id=p_org and id=p_purchase_order_line_id;
  if not found then raise exception using errcode='42501',message='purchase_order_line_access_denied'; end if;
  perform e10.lock_purchase_order(p_org,v_purchase_order_id);
  if not exists(select 1 from public.e10_purchase_order_lines
    where organization_id=p_org and id=p_purchase_order_line_id and purchase_order_id=v_purchase_order_id)
  then raise exception using errcode='42501',message='purchase_order_line_access_denied'; end if;
  return v_purchase_order_id;
end $$;
revoke all on function e10.lock_purchase_order_line(uuid,uuid) from public,anon,authenticated;
grant execute on function e10.lock_purchase_order_line(uuid,uuid) to service_role;

create function e10.lock_receipt_purchase_orders(p_org uuid,p_receipt_id uuid) returns void
language plpgsql security definer set search_path=public as $$
declare r record; v_found boolean:=false;
begin
  for r in
    select distinct l.purchase_order_id
    from public.e10_stock_receipt_lines rl
    join public.e10_receipt_po_allocations a
      on a.organization_id=rl.organization_id and a.receipt_line_id=rl.id
    join public.e10_purchase_order_lines l
      on l.organization_id=a.organization_id and l.id=a.purchase_order_line_id
    where rl.organization_id=p_org and rl.stock_receipt_id=p_receipt_id
    order by l.purchase_order_id
  loop
    v_found:=true;
    perform e10.lock_purchase_order(p_org,r.purchase_order_id);
  end loop;
  if not v_found then raise exception using errcode='42501',message='receipt_access_denied'; end if;
end $$;
revoke all on function e10.lock_receipt_purchase_orders(uuid,uuid) from public,anon,authenticated;
grant execute on function e10.lock_receipt_purchase_orders(uuid,uuid) to service_role;

alter function public.e10_org_receive_po_line(uuid,uuid,text,numeric,numeric,numeric,text,timestamptz,jsonb,text)
  rename to _e10_org_receive_po_line_x4d;
revoke all on function public._e10_org_receive_po_line_x4d(uuid,uuid,text,numeric,numeric,numeric,text,timestamptz,jsonb,text)
  from public,anon,authenticated;
grant execute on function public._e10_org_receive_po_line_x4d(uuid,uuid,text,numeric,numeric,numeric,text,timestamptz,jsonb,text)
  to service_role;

create function public.e10_org_receive_po_line(
  p_org uuid,p_purchase_order_line_id uuid,p_inventory_item_id text,
  p_accepted_quantity numeric,p_damaged_quantity numeric,p_quarantined_quantity numeric,
  p_lot_code text,p_received_at timestamptz,p_expected_allocations jsonb,p_idempotency_key text
) returns jsonb language plpgsql security definer set search_path=public as $$
begin
  if not exists(select 1 from public.e10_organizations where id=p_org and status='active')
    or not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.create_receiving') then
    raise exception using errcode='42501',message='create_receiving_denied';
  end if;
  perform e10.lock_purchase_order_line(p_org,p_purchase_order_line_id);
  if not exists(select 1 from public.e10_organizations where id=p_org and status='active')
    or not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.create_receiving') then
    raise exception using errcode='42501',message='create_receiving_denied';
  end if;
  if not exists(select 1 from public.e10_stock_receipts
      where organization_id=p_org and idempotency_key=p_idempotency_key)
    and not exists(select 1 from public.e10_purchase_order_lines
      where organization_id=p_org and id=p_purchase_order_line_id and state='active') then
    raise exception using errcode='55000',message='purchase_order_line_not_receivable';
  end if;
  return public._e10_org_receive_po_line_x4d(p_org,p_purchase_order_line_id,p_inventory_item_id,
    p_accepted_quantity,p_damaged_quantity,p_quarantined_quantity,p_lot_code,p_received_at,
    p_expected_allocations,p_idempotency_key);
end $$;
revoke all on function public.e10_org_receive_po_line(uuid,uuid,text,numeric,numeric,numeric,text,timestamptz,jsonb,text)
  from public,anon;
grant execute on function public.e10_org_receive_po_line(uuid,uuid,text,numeric,numeric,numeric,text,timestamptz,jsonb,text)
  to authenticated,service_role;

alter function public.e10_org_reverse_receipt(uuid,uuid,text,text)
  rename to _e10_org_reverse_receipt_x4d;
revoke all on function public._e10_org_reverse_receipt_x4d(uuid,uuid,text,text)
  from public,anon,authenticated;
grant execute on function public._e10_org_reverse_receipt_x4d(uuid,uuid,text,text) to service_role;

create function public.e10_org_reverse_receipt(
  p_org uuid,p_receipt_id uuid,p_reason text,p_idempotency_key text
) returns jsonb language plpgsql security definer set search_path=public as $$
begin
  if not exists(select 1 from public.e10_organizations where id=p_org and status='active')
    or not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.resolve_recovery') then
    raise exception using errcode='42501',message='resolve_recovery_denied';
  end if;
  perform e10.lock_receipt_purchase_orders(p_org,p_receipt_id);
  if not exists(select 1 from public.e10_organizations where id=p_org and status='active')
    or not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.resolve_recovery') then
    raise exception using errcode='42501',message='resolve_recovery_denied';
  end if;
  return public._e10_org_reverse_receipt_x4d(p_org,p_receipt_id,p_reason,p_idempotency_key);
end $$;
revoke all on function public.e10_org_reverse_receipt(uuid,uuid,text,text) from public,anon;
grant execute on function public.e10_org_reverse_receipt(uuid,uuid,text,text) to authenticated,service_role;

create function public.e10_org_create_purchase_order(
  p_org uuid,p_supplier_id uuid,p_destination_location_id uuid,p_order_number text,
  p_currency text,p_expected_at timestamptz,p_lines jsonb,p_idempotency_key text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare
  v_actor uuid:=auth.uid(); v_fp text; v_existing record; v_po uuid:=gen_random_uuid();
  v_event uuid:=gen_random_uuid(); v_result jsonb; v_snapshot jsonb; v_line record;
  v_count integer; v_line_id uuid;
begin
  if v_actor is null or not exists(select 1 from public.e10_organizations where id=p_org and status='active')
    or not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.purchasing_prepare') then
    raise exception using errcode='42501',message='purchase_order_prepare_denied';
  end if;
  if p_idempotency_key is null or btrim(p_idempotency_key)='' or length(p_idempotency_key)>200 then
    raise exception using errcode='22004',message='idempotency_key_invalid';
  end if;
  if p_currency is null or p_currency!~'^[A-Z]{3}$' or p_expected_at is not null and not isfinite(p_expected_at)
    or p_order_number is not null and (btrim(p_order_number)='' or length(p_order_number)>200)
    or p_lines is null or jsonb_typeof(p_lines)<>'array' or octet_length(p_lines::text)>262144 then
    raise exception using errcode='22023',message='purchase_order_payload_invalid';
  end if;
  v_count:=jsonb_array_length(p_lines);
  if v_count<1 or v_count>200 then raise exception using errcode='22023',message='purchase_order_lines_count_invalid'; end if;
  v_fp:=md5(jsonb_build_object('v','purchase-order-create-v1','org',p_org,'supplier',p_supplier_id,
    'destination',p_destination_location_id,'order_number',nullif(btrim(p_order_number),''),
    'currency',p_currency,'expected_epoch',extract(epoch from p_expected_at)::numeric,
    'lines',p_lines)::text);
  perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|purchase-order-command|'||p_idempotency_key,0));
  select purchase_order_id,request_fingerprint,result into v_existing
  from public.e10_purchase_order_commands where organization_id=p_org and idempotency_key=p_idempotency_key;
  if found then
    if v_existing.request_fingerprint<>v_fp then raise exception using errcode='22023',message='idempotency_key_mismatch'; end if;
    if auth.uid() is distinct from v_actor or not exists(select 1 from public.e10_organizations where id=p_org and status='active') or not e10.is_org_member(p_org)
      or not e10.has_org_cap(p_org,'act.purchasing_prepare') then
      raise exception using errcode='42501',message='purchase_order_prepare_denied';
    end if;
    return v_existing.result||jsonb_build_object('replay',true);
  end if;
  if auth.uid() is distinct from v_actor or not exists(select 1 from public.e10_organizations where id=p_org and status='active') or not e10.is_org_member(p_org)
    or not e10.has_org_cap(p_org,'act.purchasing_prepare') then
    raise exception using errcode='42501',message='purchase_order_prepare_denied';
  end if;
  perform 1 from public.e10_suppliers where organization_id=p_org and id=p_supplier_id and status='active';
  if not found then raise exception using errcode='42501',message='purchase_order_supplier_denied'; end if;
  perform 1 from public.e10_locations where organization_id=p_org and id=p_destination_location_id and status='active';
  if not found or not e10.can_receive_at(p_org,p_destination_location_id) then
    raise exception using errcode='42501',message='purchase_order_destination_denied';
  end if;
  if (select count(*) from (select (x->>'line_no')::integer n from jsonb_array_elements(p_lines) x group by 1) q)<>v_count then
    raise exception using errcode='22023',message='purchase_order_line_numbers_duplicate';
  end if;
  insert into public.e10_purchase_orders(id,organization_id,supplier_id,destination_location_id,order_number,
    revision,status,currency,expected_at,created_by)
  values(v_po,p_org,p_supplier_id,p_destination_location_id,nullif(btrim(p_order_number),''),1,'draft',p_currency,p_expected_at,v_actor);
  for v_line in
    select x,(x->>'line_no')::integer line_no,(x->>'configuration_version_id')::uuid configuration_version_id,
      (x->>'ordered_quantity')::numeric ordered_quantity,
      case when x ? 'estimated_unit_cost' and jsonb_typeof(x->'estimated_unit_cost')<>'null'
        then (x->>'estimated_unit_cost')::numeric end estimated_unit_cost
    from jsonb_array_elements(p_lines) x order by (x->>'line_no')::integer
  loop
    if v_line.line_no is null or v_line.line_no<=0 or v_line.ordered_quantity is null or v_line.ordered_quantity<=0
      or v_line.ordered_quantity::text in ('NaN','Infinity','-Infinity')
      or v_line.estimated_unit_cost is not null and (v_line.estimated_unit_cost<0
        or v_line.estimated_unit_cost::text in ('NaN','Infinity','-Infinity')) then
      raise exception using errcode='22023',message='purchase_order_line_value_invalid';
    end if;
    perform 1 from public.e10_product_configuration_versions
      where organization_id=p_org and id=v_line.configuration_version_id and state='active';
    if not found then raise exception using errcode='42501',message='purchase_order_configuration_denied'; end if;
    v_line_id:=case when v_line.x ? 'id' then (v_line.x->>'id')::uuid else gen_random_uuid() end;
    insert into public.e10_purchase_order_lines(id,organization_id,purchase_order_id,configuration_version_id,
      line_no,ordered_quantity,estimated_unit_cost,state)
    values(v_line_id,p_org,v_po,v_line.configuration_version_id,v_line.line_no,v_line.ordered_quantity,
      v_line.estimated_unit_cost,'active');
  end loop;
  v_snapshot:=e10.purchase_order_snapshot(p_org,v_po);
  insert into public.e10_purchase_order_revisions(organization_id,purchase_order_id,revision,status,snapshot,
    payload_fingerprint,change_reason,created_by)
  values(p_org,v_po,1,'draft',v_snapshot,v_fp,'created',v_actor);
  v_result:=jsonb_build_object('ok',true,'replay',false,'purchase_order_id',v_po,
    'status','draft','revision',1,'commercial_event_id',v_event);
  insert into public.e10_purchase_order_commands(organization_id,idempotency_key,operation,purchase_order_id,
    request_fingerprint,result,created_by)
  values(p_org,p_idempotency_key,'create',v_po,v_fp,v_result,v_actor);
  insert into public.e10_commercial_events(id,organization_id,event_type,event_schema_version,subject_type,subject_id,
    occurred_at,occurred_at_precision,idempotency_key,source_kind,source_reference,source_event_id,
    correlation_id,evidence_quality,payload,created_by,request_fingerprint,purchase_order_command_idempotency_key)
  values(v_event,p_org,'purchase_order_changed',1,'other',v_po::text,now(),'exact',
    'purchase-order:'||p_idempotency_key,'manual','purchase_order',p_idempotency_key,v_po::text,
    'operator_asserted',jsonb_build_object('purchase_order_id',v_po::text,'operation','create',
      'status','draft','revision','1'),v_actor,md5('purchase-order-event|'||v_fp),p_idempotency_key);
  return v_result;
exception
  when invalid_text_representation or numeric_value_out_of_range then
    raise exception using errcode='22023',message='purchase_order_line_encoding_invalid';
end $$;
revoke all on function public.e10_org_create_purchase_order(uuid,uuid,uuid,text,text,timestamptz,jsonb,text)
  from public,anon;
grant execute on function public.e10_org_create_purchase_order(uuid,uuid,uuid,text,text,timestamptz,jsonb,text)
  to authenticated,service_role;

create function e10.purchase_order_has_remaining_work(p_org uuid,p_purchase_order_id uuid) returns boolean
language sql stable security definer set search_path=public as $$
  select exists(
    select 1 from public.e10_purchase_order_lines l
    where l.organization_id=p_org and l.purchase_order_id=p_purchase_order_id and l.state='active'
      and (
        coalesce((select sum(a.allocated_quantity) from public.e10_receipt_po_allocations a
          join public.e10_stock_receipt_lines rl on rl.organization_id=a.organization_id and rl.id=a.receipt_line_id
          join public.e10_stock_receipts r on r.organization_id=rl.organization_id and r.id=rl.stock_receipt_id
          where a.organization_id=l.organization_id and a.purchase_order_line_id=l.id and r.status<>'reversed'),0)
          < l.ordered_quantity
        or exists(select 1 from public.e10_expected_inventory_allocations ea
          where ea.organization_id=l.organization_id and ea.purchase_order_line_id=l.id and ea.status='open')
      )
  )
$$;
revoke all on function e10.purchase_order_has_remaining_work(uuid,uuid) from public,anon,authenticated;
grant execute on function e10.purchase_order_has_remaining_work(uuid,uuid) to service_role;

create function public.e10_org_transition_purchase_order(
  p_org uuid,p_purchase_order_id uuid,p_expected_revision integer,p_action text,
  p_reason text,p_idempotency_key text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare
  v_actor uuid:=auth.uid(); v_cap text; v_fp text; v_existing record; v_po record;
  v_event uuid:=gen_random_uuid(); v_result jsonb; v_snapshot jsonb; v_new_status text;
begin
  v_cap:=case when p_action='submit' then 'act.purchasing_prepare'
    when p_action='approve' then 'act.purchasing_approve'
    when p_action in ('cancel','close') then 'act.purchasing_cancel' end;
  if v_cap is null or v_actor is null or not exists(select 1 from public.e10_organizations where id=p_org and status='active')
    or not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,v_cap) then
    raise exception using errcode='42501',message='purchase_order_transition_denied';
  end if;
  if p_expected_revision is null or p_expected_revision<1 or p_reason is null or btrim(p_reason)=''
    or length(p_reason)>2000 or p_idempotency_key is null or btrim(p_idempotency_key)=''
    or length(p_idempotency_key)>200 then
    raise exception using errcode='22023',message='purchase_order_transition_payload_invalid';
  end if;
  v_fp:=md5(jsonb_build_object('v','purchase-order-transition-v1','org',p_org,'po',p_purchase_order_id,
    'expected_revision',p_expected_revision,'action',p_action,'reason',btrim(p_reason))::text);
  perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|purchase-order-command|'||p_idempotency_key,0));
  select purchase_order_id,request_fingerprint,result into v_existing
    from public.e10_purchase_order_commands where organization_id=p_org and idempotency_key=p_idempotency_key;
  if found then
    if v_existing.request_fingerprint<>v_fp then raise exception using errcode='22023',message='idempotency_key_mismatch'; end if;
    if auth.uid() is distinct from v_actor or not exists(select 1 from public.e10_organizations where id=p_org and status='active') or not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,v_cap) then
      raise exception using errcode='42501',message='purchase_order_transition_denied';
    end if;
    return v_existing.result||jsonb_build_object('replay',true);
  end if;
  perform e10.lock_purchase_order(p_org,p_purchase_order_id);
  if auth.uid() is distinct from v_actor or not exists(select 1 from public.e10_organizations where id=p_org and status='active') or not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,v_cap) then
    raise exception using errcode='42501',message='purchase_order_transition_denied';
  end if;
  select * into v_po from public.e10_purchase_orders where organization_id=p_org and id=p_purchase_order_id;
  if v_po.revision<>p_expected_revision then raise exception using errcode='40001',message='purchase_order_stale_revision'; end if;
  if p_action in ('submit','approve','close') and not exists(select 1 from public.e10_purchase_order_lines
    where organization_id=p_org and purchase_order_id=p_purchase_order_id and state='active') then
    raise exception using errcode='55000',message='purchase_order_has_no_active_lines';
  end if;
  if p_action in ('submit','approve') then
    if not exists(select 1 from public.e10_suppliers where organization_id=p_org and id=v_po.supplier_id and status='active') then
      raise exception using errcode='55000',message='purchase_order_supplier_inactive'; end if;
    if not exists(select 1 from public.e10_locations where organization_id=p_org and id=v_po.destination_location_id and status='active')
      or not e10.can_receive_at(p_org,v_po.destination_location_id) then
      raise exception using errcode='42501',message='purchase_order_destination_denied'; end if;
    if exists(select 1 from public.e10_purchase_order_lines l
      left join public.e10_product_configuration_versions v on v.organization_id=l.organization_id
        and v.id=l.configuration_version_id and v.state='active'
      where l.organization_id=p_org and l.purchase_order_id=p_purchase_order_id and l.state='active' and v.id is null) then
      raise exception using errcode='55000',message='purchase_order_configuration_inactive'; end if;
  end if;
  if p_action='submit' then
    if v_po.status<>'draft' then raise exception using errcode='55000',message='purchase_order_transition_invalid'; end if;
    v_new_status:='submitted';
  elsif p_action='approve' then
    if v_po.status<>'submitted' then raise exception using errcode='55000',message='purchase_order_transition_invalid'; end if;
    v_new_status:='approved';
  elsif p_action='cancel' then
    if v_po.status not in ('draft','submitted','approved') then raise exception using errcode='55000',message='purchase_order_transition_invalid'; end if;
    if exists(select 1 from public.e10_purchase_order_lines l
      join public.e10_receipt_po_allocations a on a.organization_id=l.organization_id and a.purchase_order_line_id=l.id
      join public.e10_stock_receipt_lines rl on rl.organization_id=a.organization_id and rl.id=a.receipt_line_id
      join public.e10_stock_receipts r on r.organization_id=rl.organization_id and r.id=rl.stock_receipt_id
      where l.organization_id=p_org and l.purchase_order_id=p_purchase_order_id and r.status<>'reversed')
      or exists(select 1 from public.e10_purchase_order_lines l join public.e10_expected_inventory_allocations ea
        on ea.organization_id=l.organization_id and ea.purchase_order_line_id=l.id
        where l.organization_id=p_org and l.purchase_order_id=p_purchase_order_id and ea.status='open') then
      raise exception using errcode='55000',message='purchase_order_has_committed_supply';
    end if;
    v_new_status:='cancelled';
  elsif p_action='close' then
    if v_po.status<>'approved' or e10.purchase_order_has_remaining_work(p_org,p_purchase_order_id) then
      raise exception using errcode='55000',message='purchase_order_has_remaining_work';
    end if;
    v_new_status:='closed';
  end if;
  update public.e10_purchase_orders set status=v_new_status,revision=revision+1,updated_at=now(),
    approved_revision=case when p_action='approve' then revision+1 else approved_revision end,
    approved_by=case when p_action='approve' then v_actor else approved_by end,
    approved_at=case when p_action='approve' then now() else approved_at end,
    cancelled_by=case when p_action='cancel' then v_actor else cancelled_by end,
    cancelled_at=case when p_action='cancel' then now() else cancelled_at end,
    closed_by=case when p_action='close' then v_actor else closed_by end,
    closed_at=case when p_action='close' then now() else closed_at end
  where organization_id=p_org and id=p_purchase_order_id;
  v_snapshot:=e10.purchase_order_snapshot(p_org,p_purchase_order_id);
  insert into public.e10_purchase_order_revisions(organization_id,purchase_order_id,revision,status,snapshot,
    payload_fingerprint,change_reason,created_by)
  values(p_org,p_purchase_order_id,p_expected_revision+1,v_new_status,v_snapshot,v_fp,btrim(p_reason),v_actor);
  v_result:=jsonb_build_object('ok',true,'replay',false,'purchase_order_id',p_purchase_order_id,
    'status',v_new_status,'revision',p_expected_revision+1,'commercial_event_id',v_event);
  insert into public.e10_purchase_order_commands(organization_id,idempotency_key,operation,purchase_order_id,
    request_fingerprint,result,created_by)
  values(p_org,p_idempotency_key,p_action,p_purchase_order_id,v_fp,v_result,v_actor);
  insert into public.e10_commercial_events(id,organization_id,event_type,event_schema_version,subject_type,subject_id,
    occurred_at,occurred_at_precision,idempotency_key,source_kind,source_reference,source_event_id,
    correlation_id,evidence_quality,payload,created_by,request_fingerprint,purchase_order_command_idempotency_key)
  values(v_event,p_org,'purchase_order_changed',1,'other',p_purchase_order_id::text,now(),'exact',
    'purchase-order:'||p_idempotency_key,'manual','purchase_order',p_idempotency_key,p_purchase_order_id::text,
    'operator_asserted',jsonb_build_object('purchase_order_id',p_purchase_order_id::text,'operation',p_action,
      'status',v_new_status,'revision',(p_expected_revision+1)::text,'reason',btrim(p_reason)),
    v_actor,md5('purchase-order-event|'||v_fp),p_idempotency_key);
  return v_result;
end $$;
revoke all on function public.e10_org_transition_purchase_order(uuid,uuid,integer,text,text,text) from public,anon;
grant execute on function public.e10_org_transition_purchase_order(uuid,uuid,integer,text,text,text)
  to authenticated,service_role;

create function public.e10_org_amend_purchase_order(
  p_org uuid,p_purchase_order_id uuid,p_expected_revision integer,p_supplier_id uuid,
  p_destination_location_id uuid,p_order_number text,p_currency text,p_expected_at timestamptz,
  p_lines jsonb,p_reason text,p_idempotency_key text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare
  v_actor uuid:=auth.uid(); v_fp text; v_existing record; v_po record; v_line record; v_old record;
  v_event uuid:=gen_random_uuid(); v_result jsonb; v_snapshot jsonb; v_count integer; v_line_id uuid;
  v_new_status text; v_committed numeric;
begin
  if v_actor is null or not exists(select 1 from public.e10_organizations where id=p_org and status='active')
    or not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.purchasing_prepare') then
    raise exception using errcode='42501',message='purchase_order_prepare_denied';
  end if;
  if p_expected_revision is null or p_expected_revision<1 or p_reason is null or btrim(p_reason)=''
    or length(p_reason)>2000 or p_idempotency_key is null or btrim(p_idempotency_key)=''
    or length(p_idempotency_key)>200 or p_currency is null or p_currency!~'^[A-Z]{3}$'
    or p_expected_at is not null and not isfinite(p_expected_at)
    or p_order_number is not null and (btrim(p_order_number)='' or length(p_order_number)>200)
    or p_lines is null or jsonb_typeof(p_lines)<>'array' or octet_length(p_lines::text)>262144 then
    raise exception using errcode='22023',message='purchase_order_amend_payload_invalid';
  end if;
  v_count:=jsonb_array_length(p_lines);
  if v_count<1 or v_count>200 then raise exception using errcode='22023',message='purchase_order_lines_count_invalid'; end if;
  v_fp:=md5(jsonb_build_object('v','purchase-order-amend-v1','org',p_org,'po',p_purchase_order_id,
    'expected_revision',p_expected_revision,'supplier',p_supplier_id,'destination',p_destination_location_id,
    'order_number',nullif(btrim(p_order_number),''),'currency',p_currency,
    'expected_epoch',extract(epoch from p_expected_at)::numeric,'lines',p_lines,'reason',btrim(p_reason))::text);
  perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|purchase-order-command|'||p_idempotency_key,0));
  select purchase_order_id,request_fingerprint,result into v_existing
    from public.e10_purchase_order_commands where organization_id=p_org and idempotency_key=p_idempotency_key;
  if found then
    if v_existing.request_fingerprint<>v_fp then raise exception using errcode='22023',message='idempotency_key_mismatch'; end if;
    if auth.uid() is distinct from v_actor or not exists(select 1 from public.e10_organizations where id=p_org and status='active') or not e10.is_org_member(p_org)
      or not e10.has_org_cap(p_org,'act.purchasing_prepare') then
      raise exception using errcode='42501',message='purchase_order_prepare_denied';
    end if;
    return v_existing.result||jsonb_build_object('replay',true);
  end if;
  perform e10.lock_purchase_order(p_org,p_purchase_order_id);
  set constraints e10_purchase_order_lines_org_po_line_no_uq deferred;
  if auth.uid() is distinct from v_actor or not exists(select 1 from public.e10_organizations where id=p_org and status='active') or not e10.is_org_member(p_org)
    or not e10.has_org_cap(p_org,'act.purchasing_prepare') then
    raise exception using errcode='42501',message='purchase_order_prepare_denied';
  end if;
  select * into v_po from public.e10_purchase_orders where organization_id=p_org and id=p_purchase_order_id;
  if v_po.revision<>p_expected_revision then raise exception using errcode='40001',message='purchase_order_stale_revision'; end if;
  if v_po.status not in ('draft','submitted','approved') then raise exception using errcode='55000',message='purchase_order_not_editable'; end if;
  perform 1 from public.e10_suppliers where organization_id=p_org and id=p_supplier_id and status='active';
  if not found then raise exception using errcode='42501',message='purchase_order_supplier_denied'; end if;
  perform 1 from public.e10_locations where organization_id=p_org and id=p_destination_location_id and status='active';
  if not found or not e10.can_receive_at(p_org,p_destination_location_id) then
    raise exception using errcode='42501',message='purchase_order_destination_denied';
  end if;
  if (select count(*) from (select (x->>'line_no')::integer n from jsonb_array_elements(p_lines) x group by 1) q)<>v_count
    or (select count(*) from jsonb_array_elements(p_lines) x where x ? 'id')<>v_count
    or (select count(*) from (select (x->>'id')::uuid id from jsonb_array_elements(p_lines) x
      where x ? 'id' group by 1) q)<>(select count(*) from jsonb_array_elements(p_lines) x where x ? 'id') then
    raise exception using errcode='22023',message='purchase_order_line_identity_duplicate';
  end if;
  if (p_supplier_id,p_destination_location_id,p_currency) is distinct from
      (v_po.supplier_id,v_po.destination_location_id,v_po.currency)
    and (exists(select 1 from public.e10_purchase_order_lines l
      join public.e10_receipt_po_allocations a on a.organization_id=l.organization_id and a.purchase_order_line_id=l.id
      where l.organization_id=p_org and l.purchase_order_id=p_purchase_order_id)
      or exists(select 1 from public.e10_purchase_order_lines l
        join public.e10_invoice_po_allocations a on a.organization_id=l.organization_id and a.purchase_order_line_id=l.id
        where l.organization_id=p_org and l.purchase_order_id=p_purchase_order_id)
      or exists(select 1 from public.e10_purchase_order_lines l
        join public.e10_expected_inventory_allocations a on a.organization_id=l.organization_id and a.purchase_order_line_id=l.id
        where l.organization_id=p_org and l.purchase_order_id=p_purchase_order_id)) then
    raise exception using errcode='55000',message='purchase_order_bound_header_change_denied';
  end if;
  for v_line in
    select x,(x->>'line_no')::integer line_no,(x->>'configuration_version_id')::uuid configuration_version_id,
      (x->>'ordered_quantity')::numeric ordered_quantity,
      case when x ? 'estimated_unit_cost' and jsonb_typeof(x->'estimated_unit_cost')<>'null'
        then (x->>'estimated_unit_cost')::numeric end estimated_unit_cost
    from jsonb_array_elements(p_lines) x order by (x->>'line_no')::integer
  loop
    if v_line.line_no is null or v_line.line_no<=0 or v_line.ordered_quantity is null or v_line.ordered_quantity<=0
      or v_line.ordered_quantity::text in ('NaN','Infinity','-Infinity')
      or v_line.estimated_unit_cost is not null and (v_line.estimated_unit_cost<0
        or v_line.estimated_unit_cost::text in ('NaN','Infinity','-Infinity')) then
      raise exception using errcode='22023',message='purchase_order_line_value_invalid';
    end if;
    perform 1 from public.e10_product_configuration_versions
      where organization_id=p_org and id=v_line.configuration_version_id and state='active';
    if not found then raise exception using errcode='42501',message='purchase_order_configuration_denied'; end if;
    if v_line.x ? 'id' then
      v_line_id:=(v_line.x->>'id')::uuid;
      select * into v_old from public.e10_purchase_order_lines
        where organization_id=p_org and id=v_line_id and purchase_order_id=p_purchase_order_id;
      if found then
        select greatest(
          coalesce((select sum(a.allocated_quantity) from public.e10_invoice_po_allocations a
            where a.organization_id=p_org and a.purchase_order_line_id=v_line_id),0),
          coalesce((select sum(a.allocated_quantity) from public.e10_receipt_po_allocations a
            join public.e10_stock_receipt_lines rl on rl.organization_id=a.organization_id and rl.id=a.receipt_line_id
            join public.e10_stock_receipts r on r.organization_id=rl.organization_id and r.id=rl.stock_receipt_id
            where a.organization_id=p_org and a.purchase_order_line_id=v_line_id and r.status<>'reversed'),0)
          +coalesce((select sum(a.expected_quantity-coalesce(a.fulfilled_quantity,0))
            from public.e10_expected_inventory_allocations a
            where a.organization_id=p_org and a.purchase_order_line_id=v_line_id and a.status='open'),0)) into v_committed;
        if v_line.ordered_quantity<v_committed then raise exception using errcode='23514',message='purchase_order_reduction_below_committed'; end if;
        if v_line.configuration_version_id<>v_old.configuration_version_id and (
          exists(select 1 from public.e10_receipt_po_allocations where organization_id=p_org and purchase_order_line_id=v_line_id)
          or exists(select 1 from public.e10_invoice_po_allocations where organization_id=p_org and purchase_order_line_id=v_line_id)
          or exists(select 1 from public.e10_expected_inventory_allocations where organization_id=p_org and purchase_order_line_id=v_line_id)) then
          raise exception using errcode='55000',message='purchase_order_bound_configuration_change_denied';
        end if;
        update public.e10_purchase_order_lines set line_no=v_line.line_no,
          configuration_version_id=v_line.configuration_version_id,ordered_quantity=v_line.ordered_quantity,
          estimated_unit_cost=v_line.estimated_unit_cost,state='active'
        where organization_id=p_org and id=v_line_id;
      else
        insert into public.e10_purchase_order_lines(id,organization_id,purchase_order_id,configuration_version_id,
          line_no,ordered_quantity,estimated_unit_cost,state)
        values(v_line_id,p_org,p_purchase_order_id,v_line.configuration_version_id,v_line.line_no,
          v_line.ordered_quantity,v_line.estimated_unit_cost,'active');
      end if;
    end if;
  end loop;
  for v_old in select * from public.e10_purchase_order_lines
    where organization_id=p_org and purchase_order_id=p_purchase_order_id and state='active'
      and not exists(select 1 from jsonb_array_elements(p_lines) x where x ? 'id' and (x->>'id')::uuid=e10_purchase_order_lines.id)
    order by id
  loop
    if exists(select 1 from public.e10_receipt_po_allocations where organization_id=p_org and purchase_order_line_id=v_old.id)
      or exists(select 1 from public.e10_invoice_po_allocations where organization_id=p_org and purchase_order_line_id=v_old.id)
      or exists(select 1 from public.e10_expected_inventory_allocations where organization_id=p_org and purchase_order_line_id=v_old.id) then
      raise exception using errcode='55000',message='purchase_order_bound_line_removal_denied';
    end if;
    update public.e10_purchase_order_lines set state='cancelled' where organization_id=p_org and id=v_old.id;
  end loop;
  v_new_status:=case v_po.status when 'approved' then 'submitted' when 'submitted' then 'draft' else 'draft' end;
  update public.e10_purchase_orders set supplier_id=p_supplier_id,destination_location_id=p_destination_location_id,
    order_number=nullif(btrim(p_order_number),''),currency=p_currency,expected_at=p_expected_at,
    status=v_new_status,revision=revision+1,approved_revision=null,approved_by=null,approved_at=null,updated_at=now()
  where organization_id=p_org and id=p_purchase_order_id;
  v_snapshot:=e10.purchase_order_snapshot(p_org,p_purchase_order_id);
  insert into public.e10_purchase_order_revisions(organization_id,purchase_order_id,revision,status,snapshot,
    payload_fingerprint,change_reason,created_by)
  values(p_org,p_purchase_order_id,p_expected_revision+1,v_new_status,v_snapshot,v_fp,btrim(p_reason),v_actor);
  v_result:=jsonb_build_object('ok',true,'replay',false,'purchase_order_id',p_purchase_order_id,
    'status',v_new_status,'revision',p_expected_revision+1,'commercial_event_id',v_event);
  insert into public.e10_purchase_order_commands(organization_id,idempotency_key,operation,purchase_order_id,
    request_fingerprint,result,created_by)
  values(p_org,p_idempotency_key,'amend',p_purchase_order_id,v_fp,v_result,v_actor);
  insert into public.e10_commercial_events(id,organization_id,event_type,event_schema_version,subject_type,subject_id,
    occurred_at,occurred_at_precision,idempotency_key,source_kind,source_reference,source_event_id,
    correlation_id,evidence_quality,payload,created_by,request_fingerprint,purchase_order_command_idempotency_key)
  values(v_event,p_org,'purchase_order_changed',1,'other',p_purchase_order_id::text,now(),'exact',
    'purchase-order:'||p_idempotency_key,'manual','purchase_order',p_idempotency_key,p_purchase_order_id::text,
    'operator_asserted',jsonb_build_object('purchase_order_id',p_purchase_order_id::text,'operation','amend',
      'status',v_new_status,'revision',(p_expected_revision+1)::text,'reason',btrim(p_reason)),v_actor,
    md5('purchase-order-event|'||v_fp),p_idempotency_key);
  return v_result;
exception
  when invalid_text_representation or numeric_value_out_of_range then
    raise exception using errcode='22023',message='purchase_order_line_encoding_invalid';
end $$;
revoke all on function public.e10_org_amend_purchase_order(uuid,uuid,integer,uuid,uuid,text,text,timestamptz,jsonb,text,text)
  from public,anon;
grant execute on function public.e10_org_amend_purchase_order(uuid,uuid,integer,uuid,uuid,text,text,timestamptz,jsonb,text,text)
  to authenticated,service_role;
