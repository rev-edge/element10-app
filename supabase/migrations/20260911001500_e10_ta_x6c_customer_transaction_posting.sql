-- TA-X6c reviewed customer-transaction posting. Posted does not mean paid or settled.

alter table public.e10_unique_items add column product_master_id uuid, add column configuration_version_id uuid;
alter table public.e10_unique_items add constraint e10_unique_items_org_product_fkey foreign key(organization_id,product_master_id) references public.e10_product_masters(organization_id,id);
alter table public.e10_unique_items add constraint e10_unique_items_org_configuration_version_fkey foreign key(organization_id,configuration_version_id) references public.e10_product_configuration_versions(organization_id,id);
create index e10_unique_items_org_product_config_idx on public.e10_unique_items(organization_id,product_master_id,configuration_version_id,id) where product_master_id is not null;
create function e10.enforce_unique_item_product_configuration() returns trigger language plpgsql security definer set search_path=public as $$
begin
  if new.configuration_version_id is not null and (new.product_master_id is null or not exists(
    select 1 from public.e10_product_configuration_versions v join public.e10_product_configurations c on c.organization_id=v.organization_id and c.id=v.configuration_id
    where v.organization_id=new.organization_id and v.id=new.configuration_version_id and c.product_master_id=new.product_master_id))
  then raise exception using errcode='23514',message='unique_item_product_configuration_mismatch'; end if;
  return new;
end $$;
revoke all on function e10.enforce_unique_item_product_configuration() from public,anon,authenticated;
grant execute on function e10.enforce_unique_item_product_configuration() to service_role;
create trigger e10_unique_item_product_configuration_trg before insert or update of organization_id,product_master_id,configuration_version_id on public.e10_unique_items
  for each row execute function e10.enforce_unique_item_product_configuration();

create table public.e10_customer_transaction_drafts (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.e10_organizations(id),
  status text not null default 'draft' check(status in ('draft','approved','posted','cancelled')),
  current_revision integer not null default 1 check(current_revision>0), approved_revision integer,approval_decision_id uuid,
  approved_by uuid references auth.users(id), approved_at timestamptz, posted_transaction_id uuid,
  created_by uuid references auth.users(id), created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unique(organization_id,id), check((status='approved' and approved_revision=current_revision and approved_by is not null and approved_at is not null)
    or status<>'approved')
);
create table public.e10_customer_transaction_draft_revisions (
  organization_id uuid not null, draft_id uuid not null, revision integer not null check(revision>0),
  customer_id uuid, currency text not null check(currency~'^[A-Z]{3}$'), occurred_at timestamptz,
  occurred_at_precision text not null check(occurred_at_precision in ('exact','date','unknown')),
  review_note text not null check(btrim(review_note)<>''), created_by uuid references auth.users(id), created_at timestamptz not null default now(),
  primary key(organization_id,draft_id,revision),
  foreign key(organization_id,draft_id) references public.e10_customer_transaction_drafts(organization_id,id),
  foreign key(organization_id,customer_id) references public.e10_customers(organization_id,id),
  check((occurred_at_precision='unknown' and occurred_at is null) or (occurred_at_precision in ('exact','date') and occurred_at is not null and isfinite(occurred_at)))
);
create table public.e10_customer_transaction_draft_lines (
  organization_id uuid not null, draft_id uuid not null, revision integer not null, line_no integer not null check(line_no>0),
  purchase_kind text not null check(purchase_kind in ('retail','break','unclassified')),
  sales_channel text, location_id uuid, capture_source text not null check(capture_source in ('manual','import','native')),
  source_session_reference text,
  source_connection_id text, source_line_id text not null check(btrim(source_line_id)<>''), activity_observation_id uuid,
  product_master_id uuid, configuration_version_id uuid, unique_item_id uuid, break_session_id uuid, break_slot_id uuid,
  quantity numeric not null check(quantity>0 and quantity::text not in ('NaN','Infinity','-Infinity')),
  merchandise_gross numeric not null check(merchandise_gross>=0 and merchandise_gross::text not in ('NaN','Infinity','-Infinity')),
  merchandise_discount numeric check(merchandise_discount>=0 and merchandise_discount<=merchandise_gross and merchandise_discount::text not in ('NaN','Infinity','-Infinity')),
  shipping_amount numeric check(shipping_amount>=0 and shipping_amount::text not in ('NaN','Infinity','-Infinity')),
  tax_amount numeric check(tax_amount>=0 and tax_amount::text not in ('NaN','Infinity','-Infinity')),
  merchandise_net numeric generated always as (merchandise_gross-merchandise_discount) stored,
  raw_evidence jsonb not null default '{}' check(jsonb_typeof(raw_evidence)='object'),
  primary key(organization_id,draft_id,revision,line_no),
  foreign key(organization_id,draft_id,revision) references public.e10_customer_transaction_draft_revisions(organization_id,draft_id,revision),
  foreign key(organization_id,location_id) references public.e10_locations(organization_id,id),
  foreign key(organization_id,activity_observation_id) references public.e10_customer_activity_observations(organization_id,id),
  foreign key(organization_id,product_master_id) references public.e10_product_masters(organization_id,id),
  foreign key(organization_id,configuration_version_id) references public.e10_product_configuration_versions(organization_id,id),
  foreign key(organization_id,unique_item_id) references public.e10_unique_items(organization_id,id),
  foreign key(organization_id,break_session_id) references public.e10_break_sessions(organization_id,id),
  foreign key(organization_id,break_slot_id) references public.e10_break_slots(organization_id,id),
  check(sales_channel is null or btrim(sales_channel)<>''), check(source_connection_id is null or btrim(source_connection_id)<>''),
  check(source_session_reference is null or btrim(source_session_reference)<>''), check(break_slot_id is null or break_session_id is not null)
);

create table public.e10_customer_transactions (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.e10_organizations(id),
  customer_id uuid, currency text not null check(currency~'^[A-Z]{3}$'), occurred_at timestamptz,
  occurred_at_precision text not null check(occurred_at_precision in ('exact','date','unknown')),
  source_draft_id uuid not null, source_draft_revision integer not null, commercial_event_id uuid not null,
  posted_by uuid references auth.users(id), posted_at timestamptz not null default now(),
  unique(organization_id,id), unique(organization_id,source_draft_id), unique(organization_id,commercial_event_id),
  foreign key(organization_id,customer_id) references public.e10_customers(organization_id,id),
  foreign key(organization_id,source_draft_id,source_draft_revision) references public.e10_customer_transaction_draft_revisions(organization_id,draft_id,revision),
  check((occurred_at_precision='unknown' and occurred_at is null) or (occurred_at_precision in ('exact','date') and occurred_at is not null and isfinite(occurred_at)))
);
create table public.e10_customer_transaction_lines (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null, transaction_id uuid not null, line_no integer not null,
  purchase_kind text not null check(purchase_kind in ('retail','break','unclassified')), sales_channel text, location_id uuid,source_session_reference text,
  capture_source text not null check(capture_source in ('manual','import','native')), source_connection_id text, source_line_id text not null,
  activity_observation_id uuid, product_master_id uuid, configuration_version_id uuid, unique_item_id uuid, break_session_id uuid, break_slot_id uuid,
  quantity numeric not null check(quantity>0 and quantity::text not in ('NaN','Infinity','-Infinity')),
  merchandise_gross numeric not null check(merchandise_gross>=0 and merchandise_gross::text not in ('NaN','Infinity','-Infinity')),
  merchandise_discount numeric check(merchandise_discount>=0 and merchandise_discount<=merchandise_gross and merchandise_discount::text not in ('NaN','Infinity','-Infinity')),
  shipping_amount numeric check(shipping_amount>=0 and shipping_amount::text not in ('NaN','Infinity','-Infinity')),
  tax_amount numeric check(tax_amount>=0 and tax_amount::text not in ('NaN','Infinity','-Infinity')),
  merchandise_net numeric generated always as (merchandise_gross-merchandise_discount) stored,
  raw_evidence jsonb not null, unique(organization_id,id), unique(organization_id,transaction_id,line_no),
  foreign key(organization_id,transaction_id) references public.e10_customer_transactions(organization_id,id),
  foreign key(organization_id,location_id) references public.e10_locations(organization_id,id),
  foreign key(organization_id,activity_observation_id) references public.e10_customer_activity_observations(organization_id,id),
  foreign key(organization_id,product_master_id) references public.e10_product_masters(organization_id,id),
  foreign key(organization_id,configuration_version_id) references public.e10_product_configuration_versions(organization_id,id),
  foreign key(organization_id,unique_item_id) references public.e10_unique_items(organization_id,id),
  foreign key(organization_id,break_session_id) references public.e10_break_sessions(organization_id,id),
  foreign key(organization_id,break_slot_id) references public.e10_break_slots(organization_id,id)
);
create unique index e10_customer_transaction_activity_uq on public.e10_customer_transaction_lines(organization_id,activity_observation_id) where activity_observation_id is not null;
create unique index e10_customer_transaction_source_line_uq on public.e10_customer_transaction_lines(organization_id,capture_source,coalesce(source_connection_id,''),source_line_id);
create index e10_customer_transaction_customer_time_idx on public.e10_customer_transactions(organization_id,customer_id,occurred_at,id) where customer_id is not null;

create table public.e10_customer_transaction_adjustments (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null, transaction_id uuid not null, transaction_line_id uuid,
  adjustment_kind text not null check(adjustment_kind in ('refund','cancellation','correction')),
  currency text not null check(currency~'^[A-Z]{3}$'),
  merchandise_amount numeric check(merchandise_amount>=0 and merchandise_amount::text not in ('NaN','Infinity','-Infinity')),
  shipping_amount numeric check(shipping_amount>=0 and shipping_amount::text not in ('NaN','Infinity','-Infinity')),
  tax_amount numeric check(tax_amount>=0 and tax_amount::text not in ('NaN','Infinity','-Infinity')),
  occurred_at timestamptz, occurred_at_precision text not null check(occurred_at_precision in ('exact','date','unknown')),
  reason text not null check(btrim(reason)<>''), source_reference text, commercial_event_id uuid,
  created_by uuid references auth.users(id),created_at timestamptz not null default now(),unique(organization_id,id),
  foreign key(organization_id,transaction_id) references public.e10_customer_transactions(organization_id,id),
  foreign key(organization_id,transaction_line_id) references public.e10_customer_transaction_lines(organization_id,id),
  check((occurred_at_precision='unknown' and occurred_at is null) or (occurred_at_precision in ('exact','date') and occurred_at is not null and isfinite(occurred_at))),
  check(num_nonnulls(merchandise_amount,shipping_amount,tax_amount)>0)
);

create table public.e10_customer_commercial_receipts (
  organization_id uuid not null references public.e10_organizations(id),idempotency_key text not null,operation text not null check(operation in ('create_draft','amend_draft','approve_draft','reopen_draft','post_draft')),
  entity_id uuid not null,request_fingerprint text not null,result jsonb not null check(jsonb_typeof(result)='object'),created_by uuid references auth.users(id),created_at timestamptz not null default now(),primary key(organization_id,idempotency_key)
);
create table public.e10_customer_transaction_draft_decisions (
  id uuid primary key default gen_random_uuid(),organization_id uuid not null,draft_id uuid not null,revision integer not null,
  decision_action text not null check(decision_action in ('approve','reopen')),reason text not null check(btrim(reason)<>''),
  idempotency_key text not null,decided_by uuid references auth.users(id),decided_at timestamptz not null default now(),
  unique(organization_id,id),unique(organization_id,idempotency_key),
  foreign key(organization_id,draft_id,revision) references public.e10_customer_transaction_draft_revisions(organization_id,draft_id,revision)
);
alter table public.e10_customer_transaction_drafts add constraint e10_customer_transaction_drafts_org_approval_decision_fkey
  foreign key(organization_id,approval_decision_id) references public.e10_customer_transaction_draft_decisions(organization_id,id);
create table public.e10_customer_transaction_approval_activity_snapshots (
  organization_id uuid not null,approval_decision_id uuid not null,activity_observation_id uuid not null,attribution_decision_id uuid,effective_customer_id uuid,
  primary key(organization_id,approval_decision_id,activity_observation_id),
  foreign key(organization_id,approval_decision_id) references public.e10_customer_transaction_draft_decisions(organization_id,id),
  foreign key(organization_id,activity_observation_id) references public.e10_customer_activity_observations(organization_id,id),
  foreign key(organization_id,attribution_decision_id) references public.e10_customer_activity_attribution_decisions(organization_id,id),
  foreign key(organization_id,effective_customer_id) references public.e10_customers(organization_id,id)
);

alter table public.e10_commercial_events add column customer_transaction_id uuid;
alter table public.e10_commercial_events add constraint e10_commercial_events_org_customer_transaction_fkey
  foreign key(organization_id,customer_transaction_id) references public.e10_customer_transactions(organization_id,id) deferrable initially deferred;
alter table public.e10_customer_transactions add constraint e10_customer_transactions_org_event_fkey
  foreign key(organization_id,commercial_event_id) references public.e10_commercial_events(organization_id,id) deferrable initially deferred;
alter table public.e10_customer_transaction_drafts add constraint e10_customer_transaction_drafts_org_posted_fkey
  foreign key(organization_id,posted_transaction_id) references public.e10_customer_transactions(organization_id,id);

insert into public.e10_commercial_event_schemas(event_type,schema_version,required_payload_keys,description)
values('customer_transaction_posted',1,array['transaction_id'],'Reviewed customer spend posting; not payment, settlement or accounting recognition.');
alter table public.e10_commercial_events drop constraint e10_commercial_events_event_type_check;
alter table public.e10_commercial_events add constraint e10_commercial_events_event_type_check check(event_type in (
  'acquisition','receipt','available_for_sale','listing_created','listing_published','listing_paused','listing_resumed','listing_ended','listing_relisted',
  'asking_price_changed','hold','release','sale_committed','customer_transaction_posted','fulfillment','fee','payout','refund','return','cost_correction','correction'));
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
    when 'return' then array['return_id'] when 'cost_correction' then array['cost_adjustment_id','currency'] when 'correction' then array['reason'] else null end;
  if required_text_keys is null then return false; end if;
  foreach k in array required_text_keys loop if jsonb_typeof(p_payload->k) is distinct from 'string' or coalesce(btrim(p_payload->>k),'')='' then return false; end if; end loop;
  if p_event_type in ('asking_price_changed','fee','payout','refund','cost_correction') then
    if jsonb_typeof(p_payload->'amount') is distinct from 'number' or coalesce(p_payload->>'currency','')!~'^[A-Z]{3}$' then return false; end if;
    amount_value:=(p_payload->>'amount')::numeric; if amount_value<0 or amount_value::text in ('NaN','Infinity','-Infinity') then return false; end if;
  end if; return true;
exception when others then return false;
end $$;
create function e10.enforce_customer_post_event_link() returns trigger language plpgsql security definer set search_path=public as $$
begin
  if new.event_type='customer_transaction_posted' and (
    new.customer_transaction_id is null or new.subject_type is distinct from 'customer_transaction' or new.subject_id is distinct from new.customer_transaction_id::text
    or new.payload->>'transaction_id' is distinct from new.customer_transaction_id::text
    or not exists(select 1 from public.e10_customer_transactions t where t.organization_id=new.organization_id and t.id=new.customer_transaction_id and t.commercial_event_id=new.id)
  ) then raise exception using errcode='42501',message='customer_post_event_requires_transaction'; end if;
  return new;
end $$;
revoke all on function e10.enforce_customer_post_event_link() from public,anon,authenticated;
grant execute on function e10.enforce_customer_post_event_link() to service_role;
create trigger e10_customer_post_event_link_trg before insert on public.e10_commercial_events for each row execute function e10.enforce_customer_post_event_link();

alter table public.e10_customer_transaction_drafts enable row level security;
alter table public.e10_customer_transaction_draft_revisions enable row level security;
alter table public.e10_customer_transaction_draft_lines enable row level security;
alter table public.e10_customer_transactions enable row level security;
alter table public.e10_customer_transaction_lines enable row level security;
alter table public.e10_customer_transaction_adjustments enable row level security;
alter table public.e10_customer_commercial_receipts enable row level security;
alter table public.e10_customer_transaction_draft_decisions enable row level security;
alter table public.e10_customer_transaction_approval_activity_snapshots enable row level security;
revoke all on public.e10_customer_transaction_drafts,public.e10_customer_transaction_draft_revisions,public.e10_customer_transaction_draft_lines,public.e10_customer_transactions,public.e10_customer_transaction_lines,public.e10_customer_transaction_adjustments,public.e10_customer_commercial_receipts,public.e10_customer_transaction_draft_decisions,public.e10_customer_transaction_approval_activity_snapshots from public,anon,authenticated;
grant all on public.e10_customer_transaction_drafts,public.e10_customer_transaction_draft_revisions,public.e10_customer_transaction_draft_lines,public.e10_customer_transactions,public.e10_customer_transaction_lines,public.e10_customer_transaction_adjustments,public.e10_customer_commercial_receipts,public.e10_customer_transaction_draft_decisions,public.e10_customer_transaction_approval_activity_snapshots to service_role;
create trigger e10_customer_draft_revision_append_only_trg before update or delete on public.e10_customer_transaction_draft_revisions for each row execute function e10.reject_append_only_change();
create trigger e10_customer_draft_line_append_only_trg before update or delete on public.e10_customer_transaction_draft_lines for each row execute function e10.reject_append_only_change();
create trigger e10_customer_transaction_append_only_trg before update or delete on public.e10_customer_transactions for each row execute function e10.reject_append_only_change();
create trigger e10_customer_transaction_line_append_only_trg before update or delete on public.e10_customer_transaction_lines for each row execute function e10.reject_append_only_change();
create trigger e10_customer_transaction_adjustment_append_only_trg before update or delete on public.e10_customer_transaction_adjustments for each row execute function e10.reject_append_only_change();
create trigger e10_customer_commercial_receipt_append_only_trg before update or delete on public.e10_customer_commercial_receipts for each row execute function e10.reject_append_only_change();
create trigger e10_customer_draft_decision_append_only_trg before update or delete on public.e10_customer_transaction_draft_decisions for each row execute function e10.reject_append_only_change();
create trigger e10_customer_approval_activity_snapshot_append_only_trg before update or delete on public.e10_customer_transaction_approval_activity_snapshots for each row execute function e10.reject_append_only_change();

create function e10.insert_customer_draft_revision(p_org uuid,p_draft uuid,p_revision integer,p_customer uuid,p_currency text,p_occurred_at timestamptz,p_precision text,p_note text,p_lines jsonb)
returns void language plpgsql security definer set search_path=public as $$
declare l jsonb; n integer:=0; v_activity uuid; v_location uuid; v_product uuid; v_config uuid; v_copy uuid; v_session uuid; v_slot uuid; v_customer uuid; v_activity_source text; v_attr record; v_copy_product uuid; v_copy_config uuid;
begin
  if p_currency is null or p_currency!~'^[A-Z]{3}$' or p_note is null or btrim(p_note)='' or p_precision not in ('exact','date','unknown') or ((p_precision='unknown')<>(p_occurred_at is null)) or (p_occurred_at is not null and not isfinite(p_occurred_at)) then raise exception using errcode='22023',message='draft_header_invalid'; end if;
  if p_customer is not null and not exists(select 1 from public.e10_customers where organization_id=p_org and id=p_customer and status='active') then raise exception using errcode='42501',message='draft_customer_denied'; end if;
  if p_lines is null or jsonb_typeof(p_lines)<>'array' or jsonb_array_length(p_lines)<1 or jsonb_array_length(p_lines)>100 or octet_length(p_lines::text)>1048576 then raise exception using errcode='22023',message='draft_lines_invalid'; end if;
  insert into public.e10_customer_transaction_draft_revisions values(p_org,p_draft,p_revision,p_customer,p_currency,p_occurred_at,p_precision,btrim(p_note),auth.uid(),now());
  for l in select value from jsonb_array_elements(p_lines) loop
    n:=n+1;
    begin
      v_activity:=nullif(l->>'activity_observation_id','')::uuid;v_location:=nullif(l->>'location_id','')::uuid;v_product:=nullif(l->>'product_master_id','')::uuid;v_config:=nullif(l->>'configuration_version_id','')::uuid;v_copy:=nullif(l->>'unique_item_id','')::uuid;v_session:=nullif(l->>'break_session_id','')::uuid;v_slot:=nullif(l->>'break_slot_id','')::uuid;
      if coalesce(l->>'purchase_kind','') not in ('retail','break','unclassified') or coalesce(l->>'capture_source','') not in ('manual','import','native') or coalesce(btrim(l->>'source_line_id'),'')='' then raise exception 'shape'; end if;
      if (l->>'quantity')::numeric<=0 or (l->>'merchandise_gross')::numeric<0 then raise exception 'amount'; end if;
      if l ? 'merchandise_discount' and l->'merchandise_discount'<>'null'::jsonb and ((l->>'merchandise_discount')::numeric<0 or (l->>'merchandise_discount')::numeric>(l->>'merchandise_gross')::numeric) then raise exception 'discount'; end if;
      if (l ? 'shipping_amount' and l->'shipping_amount'<>'null'::jsonb and (l->>'shipping_amount')::numeric<0) or (l ? 'tax_amount' and l->'tax_amount'<>'null'::jsonb and (l->>'tax_amount')::numeric<0) then raise exception 'component'; end if;
    exception when others then raise exception using errcode='22023',message='draft_line_invalid_'||n; end;
    if v_activity is not null then
      select o.customer_id,o.source_kind into v_customer,v_activity_source from public.e10_customer_activity_observations o where o.organization_id=p_org and o.id=v_activity;
      if not found then raise exception using errcode='42501',message='draft_activity_denied'; end if;
      select * into v_attr from public.e10_current_customer_activity_attributions a where a.organization_id=p_org and a.activity_observation_id=v_activity;
      if found then v_customer:=case when v_attr.decision_action='attribute' then v_attr.customer_id else null end;
      end if;
      if v_customer is distinct from p_customer then raise exception using errcode='42501',message='draft_activity_customer_denied'; end if;
    end if;
    if l->>'capture_source'='native' and (v_activity is null or v_activity_source<>'native') then raise exception using errcode='42501',message='native_line_requires_native_activity'; end if;
    if v_location is not null and not exists(select 1 from public.e10_locations where organization_id=p_org and id=v_location) then raise exception using errcode='42501',message='draft_location_denied'; end if;
    if v_product is not null and not exists(select 1 from public.e10_product_masters where organization_id=p_org and id=v_product) then raise exception using errcode='42501',message='draft_product_denied'; end if;
    if v_config is not null and not exists(select 1 from public.e10_product_configuration_versions v join public.e10_product_configurations c on c.organization_id=v.organization_id and c.id=v.configuration_id where v.organization_id=p_org and v.id=v_config and (v_product is null or c.product_master_id=v_product)) then raise exception using errcode='42501',message='draft_configuration_product_mismatch'; end if;
    if v_copy is not null then
      select product_master_id,configuration_version_id into v_copy_product,v_copy_config from public.e10_unique_items where organization_id=p_org and id=v_copy;
      if not found or (v_product is not null and v_copy_product is distinct from v_product) or (v_config is not null and v_copy_config is distinct from v_config) then raise exception using errcode='42501',message='draft_copy_identity_mismatch'; end if;
    end if;
    if v_session is not null and not exists(select 1 from public.e10_break_sessions where organization_id=p_org and id=v_session) then raise exception using errcode='42501',message='draft_session_denied'; end if;
    if v_slot is not null and not exists(select 1 from public.e10_break_slots where organization_id=p_org and id=v_slot and session_id=v_session) then raise exception using errcode='42501',message='draft_slot_denied'; end if;
    insert into public.e10_customer_transaction_draft_lines(organization_id,draft_id,revision,line_no,purchase_kind,sales_channel,location_id,source_session_reference,capture_source,source_connection_id,source_line_id,activity_observation_id,product_master_id,configuration_version_id,unique_item_id,break_session_id,break_slot_id,quantity,merchandise_gross,merchandise_discount,shipping_amount,tax_amount,raw_evidence)
    values(p_org,p_draft,p_revision,n,l->>'purchase_kind',nullif(btrim(l->>'sales_channel'),''),v_location,nullif(btrim(l->>'source_session_reference'),''),l->>'capture_source',nullif(btrim(l->>'source_connection_id'),''),btrim(l->>'source_line_id'),v_activity,v_product,v_config,v_copy,v_session,v_slot,(l->>'quantity')::numeric,(l->>'merchandise_gross')::numeric,nullif(l->>'merchandise_discount','')::numeric,nullif(l->>'shipping_amount','')::numeric,nullif(l->>'tax_amount','')::numeric,coalesce(l->'raw_evidence','{}'));
  end loop;
end $$;
revoke all on function e10.insert_customer_draft_revision(uuid,uuid,integer,uuid,text,timestamptz,text,text,jsonb) from public,anon,authenticated;
grant execute on function e10.insert_customer_draft_revision(uuid,uuid,integer,uuid,text,timestamptz,text,text,jsonb) to service_role;

create function e10.customer_activity_effective_customer(p_org uuid,p_activity uuid) returns uuid language sql stable security definer set search_path=public as $$
  select case when a.id is not null then case when a.decision_action='attribute' then a.customer_id else null end else o.customer_id end
  from public.e10_customer_activity_observations o left join public.e10_current_customer_activity_attributions a
    on a.organization_id=o.organization_id and a.activity_observation_id=o.id
  where o.organization_id=p_org and o.id=p_activity
$$;
revoke all on function e10.customer_activity_effective_customer(uuid,uuid) from public,anon,authenticated;
grant execute on function e10.customer_activity_effective_customer(uuid,uuid) to service_role;

create function public.e10_org_create_customer_transaction_draft(p_org uuid,p_customer uuid,p_currency text,p_occurred_at timestamptz,p_precision text,p_note text,p_lines jsonb,p_idempotency_key text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_fp text;v_id uuid:=gen_random_uuid();v_old record;v_result jsonb;
begin
 if not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.prepare_customer_transactions') then raise exception using errcode='42501',message='prepare_customer_transaction_denied';end if;
 if p_idempotency_key is null or btrim(p_idempotency_key)='' then raise exception using errcode='22004',message='idempotency_key_required';end if;
 v_fp:=md5(jsonb_build_object('v','customer-draft-v1','customer',p_customer,'currency',p_currency,'occurred',extract(epoch from p_occurred_at)::numeric,'precision',p_precision,'note',p_note,'lines',p_lines)::text);
 perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|customer-commercial|'||p_idempotency_key,0));select request_fingerprint,result into v_old from public.e10_customer_commercial_receipts where organization_id=p_org and idempotency_key=p_idempotency_key;
 if found then if v_old.request_fingerprint<>v_fp then raise exception using errcode='22023',message='idempotency_key_mismatch';end if;return v_old.result||'{"replay":true}'::jsonb;end if;
 insert into public.e10_customer_transaction_drafts(id,organization_id,created_by) values(v_id,p_org,auth.uid());perform e10.insert_customer_draft_revision(p_org,v_id,1,p_customer,p_currency,p_occurred_at,p_precision,p_note,p_lines);
 v_result:=jsonb_build_object('ok',true,'replay',false,'draft_id',v_id,'revision',1,'status','draft');insert into public.e10_customer_commercial_receipts values(p_org,p_idempotency_key,'create_draft',v_id,v_fp,v_result,auth.uid(),now());return v_result;
end $$;

create function public.e10_org_amend_customer_transaction_draft(p_org uuid,p_draft uuid,p_expected_revision integer,p_customer uuid,p_currency text,p_occurred_at timestamptz,p_precision text,p_note text,p_lines jsonb,p_idempotency_key text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_fp text;v_old record;v_next integer;v_result jsonb;
begin
 if not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.prepare_customer_transactions') then raise exception using errcode='42501',message='prepare_customer_transaction_denied';end if;
 if p_idempotency_key is null or btrim(p_idempotency_key)='' then raise exception using errcode='22004',message='idempotency_key_required';end if;
 v_fp:=md5(jsonb_build_object('v','customer-draft-amend-v1','draft',p_draft,'expected',p_expected_revision,'customer',p_customer,'currency',p_currency,'occurred',extract(epoch from p_occurred_at)::numeric,'precision',p_precision,'note',p_note,'lines',p_lines)::text);
 perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|customer-commercial|'||p_idempotency_key,0));select request_fingerprint,result into v_old from public.e10_customer_commercial_receipts where organization_id=p_org and idempotency_key=p_idempotency_key;
 if found then if v_old.request_fingerprint<>v_fp then raise exception using errcode='22023',message='idempotency_key_mismatch';end if;return v_old.result||'{"replay":true}'::jsonb;end if;
 perform 1 from public.e10_customer_transaction_drafts where organization_id=p_org and id=p_draft and status='draft' and current_revision=p_expected_revision for update;
 if not found then raise exception using errcode='40001',message='draft_revision_or_state_conflict';end if;v_next:=p_expected_revision+1;
 perform e10.insert_customer_draft_revision(p_org,p_draft,v_next,p_customer,p_currency,p_occurred_at,p_precision,p_note,p_lines);update public.e10_customer_transaction_drafts set current_revision=v_next,updated_at=now() where organization_id=p_org and id=p_draft;
 v_result:=jsonb_build_object('ok',true,'replay',false,'draft_id',p_draft,'revision',v_next,'status','draft');insert into public.e10_customer_commercial_receipts values(p_org,p_idempotency_key,'amend_draft',p_draft,v_fp,v_result,auth.uid(),now());return v_result;
end $$;

create function public.e10_org_approve_customer_transaction_draft(p_org uuid,p_draft uuid,p_expected_revision integer,p_idempotency_key text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_fp text;v_old record;v_result jsonb;v_customer uuid;v_activity uuid;v_decision uuid:=gen_random_uuid();
begin
 if not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.approve_customer_transactions') then raise exception using errcode='42501',message='approve_customer_transaction_denied';end if;
 if p_idempotency_key is null or btrim(p_idempotency_key)='' then raise exception using errcode='22004',message='idempotency_key_required';end if;
 v_fp:=md5(jsonb_build_object('v','customer-draft-approve-v1','draft',p_draft,'revision',p_expected_revision)::text);perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|customer-commercial|'||p_idempotency_key,0));
 select request_fingerprint,result into v_old from public.e10_customer_commercial_receipts where organization_id=p_org and idempotency_key=p_idempotency_key;if found then if v_old.request_fingerprint<>v_fp then raise exception using errcode='22023',message='idempotency_key_mismatch';end if;return v_old.result||'{"replay":true}'::jsonb;end if;
 perform 1 from public.e10_customer_transaction_drafts where organization_id=p_org and id=p_draft and status='draft' and current_revision=p_expected_revision for update;
 if not found then raise exception using errcode='40001',message='draft_revision_or_state_conflict';end if;
 for v_activity in select distinct activity_observation_id from public.e10_customer_transaction_draft_lines where organization_id=p_org and draft_id=p_draft and revision=p_expected_revision and activity_observation_id is not null order by activity_observation_id
 loop perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|activity-attribution|'||v_activity::text,0));end loop;
 select customer_id into v_customer from public.e10_customer_transaction_draft_revisions where organization_id=p_org and draft_id=p_draft and revision=p_expected_revision;
 if not found or exists(select 1 from public.e10_customer_transaction_draft_lines l where l.organization_id=p_org and l.draft_id=p_draft and l.revision=p_expected_revision and l.activity_observation_id is not null and e10.customer_activity_effective_customer(p_org,l.activity_observation_id) is distinct from v_customer) then raise exception using errcode='40001',message='draft_activity_attribution_changed';end if;
 insert into public.e10_customer_transaction_draft_decisions(id,organization_id,draft_id,revision,decision_action,reason,idempotency_key,decided_by) values(v_decision,p_org,p_draft,p_expected_revision,'approve','review approved',p_idempotency_key,auth.uid());
 update public.e10_customer_transaction_drafts set status='approved',approved_revision=current_revision,approval_decision_id=v_decision,approved_by=auth.uid(),approved_at=now(),updated_at=now() where organization_id=p_org and id=p_draft;
 insert into public.e10_customer_transaction_approval_activity_snapshots(organization_id,approval_decision_id,activity_observation_id,attribution_decision_id,effective_customer_id)
 select p_org,v_decision,l.activity_observation_id,a.id,e10.customer_activity_effective_customer(p_org,l.activity_observation_id)
 from (select distinct activity_observation_id from public.e10_customer_transaction_draft_lines where organization_id=p_org and draft_id=p_draft and revision=p_expected_revision and activity_observation_id is not null) l
 left join public.e10_current_customer_activity_attributions a on a.organization_id=p_org and a.activity_observation_id=l.activity_observation_id;
 v_result:=jsonb_build_object('ok',true,'replay',false,'draft_id',p_draft,'revision',p_expected_revision,'status','approved');insert into public.e10_customer_commercial_receipts values(p_org,p_idempotency_key,'approve_draft',p_draft,v_fp,v_result,auth.uid(),now());return v_result;
end $$;

create function public.e10_org_reopen_customer_transaction_draft(p_org uuid,p_draft uuid,p_expected_revision integer,p_reason text,p_idempotency_key text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_fp text;v_old record;v_result jsonb;
begin
 if not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.approve_customer_transactions') then raise exception using errcode='42501',message='reopen_customer_transaction_denied';end if;
 if p_idempotency_key is null or btrim(p_idempotency_key)='' or p_reason is null or btrim(p_reason)='' then raise exception using errcode='22004',message='reopen_identity_required';end if;
 v_fp:=md5(jsonb_build_object('v','customer-draft-reopen-v1','draft',p_draft,'revision',p_expected_revision,'reason',btrim(p_reason))::text);perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|customer-commercial|'||p_idempotency_key,0));
 select request_fingerprint,result into v_old from public.e10_customer_commercial_receipts where organization_id=p_org and idempotency_key=p_idempotency_key;if found then if v_old.request_fingerprint<>v_fp then raise exception using errcode='22023',message='idempotency_key_mismatch';end if;return v_old.result||'{"replay":true}'::jsonb;end if;
 perform 1 from public.e10_customer_transaction_drafts where organization_id=p_org and id=p_draft and status='approved' and current_revision=p_expected_revision and approved_revision=p_expected_revision for update;
 if not found then raise exception using errcode='40001',message='draft_not_reopenable';end if;
 insert into public.e10_customer_transaction_draft_decisions(organization_id,draft_id,revision,decision_action,reason,idempotency_key,decided_by) values(p_org,p_draft,p_expected_revision,'reopen',btrim(p_reason),p_idempotency_key,auth.uid());
 update public.e10_customer_transaction_drafts set status='draft',approved_revision=null,approval_decision_id=null,approved_by=null,approved_at=null,updated_at=now() where organization_id=p_org and id=p_draft;
 v_result:=jsonb_build_object('ok',true,'replay',false,'draft_id',p_draft,'revision',p_expected_revision,'status','draft');insert into public.e10_customer_commercial_receipts values(p_org,p_idempotency_key,'reopen_draft',p_draft,v_fp,v_result,auth.uid(),now());return v_result;
end $$;

create function public.e10_org_post_customer_transaction_draft(p_org uuid,p_draft uuid,p_expected_revision integer,p_idempotency_key text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_fp text;v_old record;v_draft record;v_revision record;v_lock text;v_activity uuid;v_tx uuid:=gen_random_uuid();v_event uuid:=gen_random_uuid();v_result jsonb;
begin
 if not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.post_customer_transactions') then raise exception using errcode='42501',message='post_customer_transaction_denied';end if;
 if p_idempotency_key is null or btrim(p_idempotency_key)='' then raise exception using errcode='22004',message='idempotency_key_required';end if;
 v_fp:=md5(jsonb_build_object('v','customer-draft-post-v1','draft',p_draft,'revision',p_expected_revision)::text);perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|customer-commercial|'||p_idempotency_key,0));
 select request_fingerprint,result into v_old from public.e10_customer_commercial_receipts where organization_id=p_org and idempotency_key=p_idempotency_key;if found then if v_old.request_fingerprint<>v_fp then raise exception using errcode='22023',message='idempotency_key_mismatch';end if;return v_old.result||'{"replay":true}'::jsonb;end if;
 select * into v_draft from public.e10_customer_transaction_drafts where organization_id=p_org and id=p_draft for update;
 if not found or v_draft.status<>'approved' or v_draft.approved_revision<>p_expected_revision then raise exception using errcode='40001',message='draft_not_approved_at_revision';end if;
 select * into v_revision from public.e10_customer_transaction_draft_revisions where organization_id=p_org and draft_id=p_draft and revision=p_expected_revision;
 for v_activity in select distinct activity_observation_id from public.e10_customer_transaction_draft_lines where organization_id=p_org and draft_id=p_draft and revision=p_expected_revision and activity_observation_id is not null order by activity_observation_id
 loop perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|activity-attribution|'||v_activity::text,0));end loop;
 if exists(select 1 from public.e10_customer_transaction_draft_lines l where l.organization_id=p_org and l.draft_id=p_draft and l.revision=p_expected_revision and l.activity_observation_id is not null and (
      e10.customer_activity_effective_customer(p_org,l.activity_observation_id) is distinct from v_revision.customer_id
      or not exists(select 1 from public.e10_customer_transaction_approval_activity_snapshots s left join public.e10_current_customer_activity_attributions a on a.organization_id=p_org and a.activity_observation_id=s.activity_observation_id
        where s.organization_id=p_org and s.approval_decision_id=v_draft.approval_decision_id and s.activity_observation_id=l.activity_observation_id
          and s.attribution_decision_id is not distinct from a.id and s.effective_customer_id is not distinct from e10.customer_activity_effective_customer(p_org,l.activity_observation_id))
    )) then raise exception using errcode='40001',message='draft_activity_attribution_changed';end if;
 for v_lock in
   select lock_key from (
     select distinct 'activity|'||activity_observation_id::text lock_key from public.e10_customer_transaction_draft_lines where organization_id=p_org and draft_id=p_draft and revision=p_expected_revision and activity_observation_id is not null
     union
     select distinct 'source|'||capture_source||'|'||coalesce(source_connection_id,'')||'|'||source_line_id from public.e10_customer_transaction_draft_lines where organization_id=p_org and draft_id=p_draft and revision=p_expected_revision
   ) locks order by lock_key
 loop perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|posted|'||v_lock,0));end loop;
 insert into public.e10_customer_transactions(id,organization_id,customer_id,currency,occurred_at,occurred_at_precision,source_draft_id,source_draft_revision,commercial_event_id,posted_by)
 values(v_tx,p_org,v_revision.customer_id,v_revision.currency,v_revision.occurred_at,v_revision.occurred_at_precision,p_draft,p_expected_revision,v_event,auth.uid());
 insert into public.e10_customer_transaction_lines(organization_id,transaction_id,line_no,purchase_kind,sales_channel,location_id,source_session_reference,capture_source,source_connection_id,source_line_id,activity_observation_id,product_master_id,configuration_version_id,unique_item_id,break_session_id,break_slot_id,quantity,merchandise_gross,merchandise_discount,shipping_amount,tax_amount,raw_evidence)
 select organization_id,v_tx,line_no,purchase_kind,sales_channel,location_id,source_session_reference,capture_source,source_connection_id,source_line_id,activity_observation_id,product_master_id,configuration_version_id,unique_item_id,break_session_id,break_slot_id,quantity,merchandise_gross,merchandise_discount,shipping_amount,tax_amount,raw_evidence from public.e10_customer_transaction_draft_lines where organization_id=p_org and draft_id=p_draft and revision=p_expected_revision;
 insert into public.e10_commercial_events(id,organization_id,event_type,event_schema_version,subject_type,subject_id,occurred_at,occurred_at_precision,idempotency_key,source_kind,source_connection_id,source_event_id,correlation_id,evidence_quality,payload,created_by,request_fingerprint,customer_transaction_id)
 values(v_event,p_org,'customer_transaction_posted',1,'customer_transaction',v_tx::text,v_revision.occurred_at,v_revision.occurred_at_precision,'transaction-post:'||p_idempotency_key,'manual','customer-posting',v_tx::text,p_draft::text,'operator_asserted',jsonb_build_object('transaction_id',v_tx,'posted_not_paid',true),auth.uid(),md5('customer-post-event|'||v_fp),v_tx);
 update public.e10_customer_transaction_drafts set status='posted',posted_transaction_id=v_tx,updated_at=now() where organization_id=p_org and id=p_draft;
 v_result:=jsonb_build_object('ok',true,'replay',false,'draft_id',p_draft,'revision',p_expected_revision,'transaction_id',v_tx,'event_id',v_event,'status','posted','paid',false,'settled',false);insert into public.e10_customer_commercial_receipts values(p_org,p_idempotency_key,'post_draft',v_tx,v_fp,v_result,auth.uid(),now());return v_result;
exception when unique_violation then raise exception using errcode='23505',message='customer_transaction_source_already_posted';
end $$;

revoke all on function public.e10_org_create_customer_transaction_draft(uuid,uuid,text,timestamptz,text,text,jsonb,text),public.e10_org_amend_customer_transaction_draft(uuid,uuid,integer,uuid,text,timestamptz,text,text,jsonb,text),public.e10_org_approve_customer_transaction_draft(uuid,uuid,integer,text),public.e10_org_reopen_customer_transaction_draft(uuid,uuid,integer,text,text),public.e10_org_post_customer_transaction_draft(uuid,uuid,integer,text) from public,anon;
grant execute on function public.e10_org_create_customer_transaction_draft(uuid,uuid,text,timestamptz,text,text,jsonb,text),public.e10_org_amend_customer_transaction_draft(uuid,uuid,integer,uuid,text,timestamptz,text,text,jsonb,text),public.e10_org_approve_customer_transaction_draft(uuid,uuid,integer,text),public.e10_org_reopen_customer_transaction_draft(uuid,uuid,integer,text,text),public.e10_org_post_customer_transaction_draft(uuid,uuid,integer,text) to authenticated,service_role;

comment on table public.e10_customer_transactions is 'Reviewed posted customer spend. Posted is distinct from paid, settled, payout and accounting recognition.';
comment on table public.e10_customer_transaction_adjustments is 'Additive refund/cancellation/correction seam; no mutation API is granted in TA-X6c.';
