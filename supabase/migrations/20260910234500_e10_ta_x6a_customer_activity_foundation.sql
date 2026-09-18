-- TA-X6a customer identity and provisional activity foundation. No posted customer spend.

create table public.e10_customers (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.e10_organizations(id),
  auth_user_id uuid references auth.users(id) on delete set null, display_name text,
  status text not null default 'active' check(status in ('active','merged','archived')),
  revision bigint not null default 0 check(revision>=0), created_by uuid references auth.users(id),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unique(organization_id,id), check(display_name is null or btrim(display_name)<>'')
);
create unique index e10_customers_org_auth_user_uq on public.e10_customers(organization_id,auth_user_id) where auth_user_id is not null and status='active';
create index e10_customers_org_name_idx on public.e10_customers(organization_id,lower(display_name),id) where display_name is not null;

create table public.e10_customer_activity_observations (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.e10_organizations(id),
  activity_kind text not null check(activity_kind in ('retail','break','unclassified')),
  customer_id uuid, buyer_user_id uuid references auth.users(id) on delete set null, buyer_alias text,
  buyer_identity_status text not null check(buyer_identity_status in ('unresolved','reviewed_attributed','verified_auth')),
  break_session_id uuid, break_slot_id uuid, quantity numeric not null check(quantity>0 and quantity::text not in ('NaN','Infinity','-Infinity')),
  merchandise_gross numeric not null check(merchandise_gross>=0 and merchandise_gross::text not in ('NaN','Infinity','-Infinity')),
  merchandise_discount numeric check(merchandise_discount>=0 and merchandise_discount::text not in ('NaN','Infinity','-Infinity')),
  shipping_amount numeric check(shipping_amount>=0 and shipping_amount::text not in ('NaN','Infinity','-Infinity')),
  tax_amount numeric check(tax_amount>=0 and tax_amount::text not in ('NaN','Infinity','-Infinity')),
  merchandise_net numeric generated always as (merchandise_gross-merchandise_discount) stored,
  currency text not null check(currency~'^[A-Z]{3}$'), sale_method text,
  occurred_at timestamptz, occurred_at_precision text not null check(occurred_at_precision in ('exact','date','unknown')),
  source_kind text not null check(source_kind in ('manual','import','native')), source_connection_id text,
  source_reference text, source_event_id text not null check(btrim(source_event_id)<>''), raw_payload jsonb not null check(jsonb_typeof(raw_payload)='object'),
  evidence_quality text not null check(evidence_quality in ('operator_asserted','imported_unreviewed','reviewed_import','native_system')),
  idempotency_key text not null check(btrim(idempotency_key)<>''), request_fingerprint text not null check(btrim(request_fingerprint)<>''),
  commercial_event_id uuid not null, created_by uuid references auth.users(id), recorded_at timestamptz not null default now(),
  unique(organization_id,id), unique(organization_id,idempotency_key), unique(organization_id,commercial_event_id),
  foreign key(organization_id,customer_id) references public.e10_customers(organization_id,id),
  foreign key(organization_id,break_session_id) references public.e10_break_sessions(organization_id,id),
  foreign key(organization_id,break_slot_id) references public.e10_break_slots(organization_id,id),
  check(merchandise_discount<=merchandise_gross),
  check((occurred_at_precision='unknown' and occurred_at is null) or (occurred_at_precision in ('exact','date') and occurred_at is not null and isfinite(occurred_at))),
  check(activity_kind<>'break' or break_session_id is not null), check(break_slot_id is null or break_session_id is not null),
  check(buyer_alias is null or btrim(buyer_alias)<>'')
);
create unique index e10_customer_activity_source_uq on public.e10_customer_activity_observations(organization_id,source_kind,coalesce(source_connection_id,''),source_event_id);
create index e10_customer_activity_customer_time_idx on public.e10_customer_activity_observations(organization_id,customer_id,occurred_at,id) where customer_id is not null;
create index e10_customer_activity_session_slot_idx on public.e10_customer_activity_observations(organization_id,break_session_id,break_slot_id,id) where break_session_id is not null;

alter table public.e10_commercial_events add column customer_activity_observation_id uuid;
alter table public.e10_commercial_events add constraint e10_commercial_events_org_customer_activity_fkey
  foreign key(organization_id,customer_activity_observation_id) references public.e10_customer_activity_observations(organization_id,id) deferrable initially deferred;
alter table public.e10_customer_activity_observations add constraint e10_customer_activity_org_event_fkey
  foreign key(organization_id,commercial_event_id) references public.e10_commercial_events(organization_id,id) deferrable initially deferred;

alter table public.e10_customers enable row level security;
alter table public.e10_customer_activity_observations enable row level security;
revoke all on public.e10_customers,public.e10_customer_activity_observations from public,anon,authenticated;
grant all on public.e10_customers,public.e10_customer_activity_observations to service_role;
create trigger e10_customer_activity_append_only_trg before update or delete on public.e10_customer_activity_observations for each row execute function e10.reject_append_only_change();

create or replace function e10.normalize_commercial_event_envelope() returns trigger language plpgsql security definer set search_path=public as $$
begin
  if new.source_kind='native' then
    if new.inventory_movement_id is null and new.customer_activity_observation_id is null then raise exception using errcode='42501',message='native_evidence_requires_trusted_source'; end if;
    new.evidence_quality:='native_system';
    new.source_connection_id:=coalesce(nullif(btrim(new.source_connection_id),''),case when new.inventory_movement_id is not null then 'inventory-ledger' else 'live-break-slot' end);
    new.source_event_id:=coalesce(nullif(btrim(new.source_event_id),''),new.inventory_movement_id::text,new.customer_activity_observation_id::text);
    new.correlation_id:=coalesce(nullif(btrim(new.correlation_id),''),nullif(btrim(new.source_reference),''),new.inventory_movement_id::text,new.customer_activity_observation_id::text);
  elsif new.source_kind='system' then raise exception using errcode='42501',message='system_evidence_requires_trusted_writer';
  elsif new.source_kind='import' and new.evidence_quality='operator_asserted' then new.evidence_quality:='imported_unreviewed'; end if;
  if new.source_kind<>'native' and not e10.valid_commercial_event_payload(new.event_type,new.payload) then raise exception using errcode='22023',message='event_payload_invalid_for_schema'; end if;
  return new;
end $$;

create function public.e10_org_record_customer_activity(
  p_org uuid,p_activity_kind text,p_customer_id uuid,p_buyer_user_id uuid,p_buyer_alias text,
  p_break_session_id uuid,p_break_slot_id uuid,p_quantity numeric,p_merchandise_gross numeric,p_merchandise_discount numeric,
  p_shipping_amount numeric,p_tax_amount numeric,p_currency text,p_sale_method text,p_occurred_at timestamptz,p_occurred_at_precision text,
  p_source_kind text,p_source_connection_id text,p_source_reference text,p_source_event_id text,p_raw_payload jsonb,p_evidence_quality text,p_idempotency_key text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_fp text; v_existing record; v_activity uuid:=gen_random_uuid(); v_event uuid:=gen_random_uuid(); v_customer_auth uuid; v_identity_status text:='unresolved';
begin
  if not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.record_commercial_events') then raise exception using errcode='42501',message='record_customer_activity_denied'; end if;
  if p_idempotency_key is null or btrim(p_idempotency_key)='' or p_source_event_id is null or btrim(p_source_event_id)='' then raise exception using errcode='22004',message='activity_identity_required'; end if;
  if p_activity_kind not in ('retail','break','unclassified') then raise exception using errcode='22023',message='activity_kind_invalid'; end if;
  if p_source_kind not in ('manual','import') or (p_source_kind='manual' and p_evidence_quality<>'operator_asserted') or (p_source_kind='import' and p_evidence_quality not in ('imported_unreviewed','reviewed_import')) then raise exception using errcode='42501',message='activity_source_provenance_invalid'; end if;
  if p_raw_payload is null or jsonb_typeof(p_raw_payload)<>'object' or octet_length(p_raw_payload::text)>262144 then raise exception using errcode='22023',message='activity_payload_invalid'; end if;
  if p_quantity is null or p_quantity<=0 or p_quantity::text in ('NaN','Infinity','-Infinity') or p_merchandise_gross is null or p_merchandise_gross<0 or p_merchandise_gross::text in ('NaN','Infinity','-Infinity')
    or (p_merchandise_discount is not null and (p_merchandise_discount<0 or p_merchandise_discount>p_merchandise_gross or p_merchandise_discount::text in ('NaN','Infinity','-Infinity')))
    or (p_shipping_amount is not null and (p_shipping_amount<0 or p_shipping_amount::text in ('NaN','Infinity','-Infinity')))
    or (p_tax_amount is not null and (p_tax_amount<0 or p_tax_amount::text in ('NaN','Infinity','-Infinity'))) then raise exception using errcode='22023',message='activity_amount_invalid'; end if;
  if p_currency is null or p_currency!~'^[A-Z]{3}$' then raise exception using errcode='22023',message='activity_currency_invalid'; end if;
  if p_occurred_at_precision not in ('exact','date','unknown') or ((p_occurred_at_precision='unknown')<>(p_occurred_at is null)) or (p_occurred_at is not null and not isfinite(p_occurred_at)) then raise exception using errcode='22023',message='activity_occurrence_invalid'; end if;
  v_fp:=md5(jsonb_build_object('v','customer-activity-v1','kind',p_activity_kind,'customer',p_customer_id,'buyer_user',p_buyer_user_id,'buyer_alias',p_buyer_alias,'session',p_break_session_id,'slot',p_break_slot_id,'quantity',p_quantity,'gross',p_merchandise_gross,'discount',p_merchandise_discount,'shipping',p_shipping_amount,'tax',p_tax_amount,'currency',p_currency,'method',p_sale_method,'occurred_epoch',extract(epoch from p_occurred_at)::numeric,'precision',p_occurred_at_precision,'source_kind',p_source_kind,'connection',p_source_connection_id,'reference',p_source_reference,'source_event',p_source_event_id,'payload',p_raw_payload,'quality',p_evidence_quality)::text);
  perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|customer-activity|'||p_idempotency_key,0));
  select id,commercial_event_id,request_fingerprint into v_existing from public.e10_customer_activity_observations where organization_id=p_org and idempotency_key=p_idempotency_key;
  if found then if v_existing.request_fingerprint<>v_fp then raise exception using errcode='22023',message='idempotency_key_mismatch'; end if; return jsonb_build_object('ok',true,'replay',true,'activity_id',v_existing.id,'event_id',v_existing.commercial_event_id,'posted',false); end if;
  if p_customer_id is not null then
    select auth_user_id into v_customer_auth from public.e10_customers where organization_id=p_org and id=p_customer_id and status='active';
    if not found then raise exception using errcode='42501',message='activity_customer_denied'; end if;
    if p_buyer_user_id is not null and p_buyer_user_id is distinct from v_customer_auth then raise exception using errcode='22023',message='activity_buyer_identity_mismatch'; end if;
    v_identity_status:=case when p_buyer_user_id is not null and p_buyer_user_id=v_customer_auth then 'verified_auth' else 'reviewed_attributed' end;
  end if;
  if p_break_session_id is not null and not exists(select 1 from public.e10_break_sessions where organization_id=p_org and id=p_break_session_id) then raise exception using errcode='42501',message='activity_session_denied'; end if;
  if p_break_slot_id is not null and not exists(select 1 from public.e10_break_slots where organization_id=p_org and id=p_break_slot_id and session_id=p_break_session_id) then raise exception using errcode='42501',message='activity_slot_denied'; end if;
  if p_activity_kind='break' and p_break_session_id is null then raise exception using errcode='22023',message='break_activity_requires_session'; end if;
  insert into public.e10_customer_activity_observations(id,organization_id,activity_kind,customer_id,buyer_user_id,buyer_alias,buyer_identity_status,break_session_id,break_slot_id,quantity,merchandise_gross,merchandise_discount,shipping_amount,tax_amount,currency,sale_method,occurred_at,occurred_at_precision,source_kind,source_connection_id,source_reference,source_event_id,raw_payload,evidence_quality,idempotency_key,request_fingerprint,commercial_event_id,created_by)
  values(v_activity,p_org,p_activity_kind,p_customer_id,p_buyer_user_id,nullif(btrim(p_buyer_alias),''),v_identity_status,p_break_session_id,p_break_slot_id,p_quantity,p_merchandise_gross,p_merchandise_discount,p_shipping_amount,p_tax_amount,p_currency,p_sale_method,p_occurred_at,p_occurred_at_precision,p_source_kind,p_source_connection_id,p_source_reference,p_source_event_id,p_raw_payload,p_evidence_quality,p_idempotency_key,v_fp,v_event,auth.uid());
  insert into public.e10_commercial_events(id,organization_id,event_type,event_schema_version,subject_type,subject_id,occurred_at,occurred_at_precision,idempotency_key,source_kind,source_connection_id,source_reference,source_event_id,correlation_id,evidence_quality,payload,created_by,request_fingerprint,customer_activity_observation_id)
  values(v_event,p_org,'sale_committed',1,'sale',v_activity::text,p_occurred_at,p_occurred_at_precision,'activity:'||p_idempotency_key,p_source_kind,p_source_connection_id,p_source_reference,p_source_event_id,coalesce(p_break_session_id::text,v_activity::text),p_evidence_quality,jsonb_build_object('sale_id',v_activity,'activity_kind',p_activity_kind,'provisional_only',true),auth.uid(),md5('activity-event|'||v_fp),v_activity);
  return jsonb_build_object('ok',true,'replay',false,'activity_id',v_activity,'event_id',v_event,'posted',false);
exception when unique_violation then
  if exists(select 1 from public.e10_customer_activity_observations where organization_id=p_org and source_kind=p_source_kind and coalesce(source_connection_id,'')=coalesce(p_source_connection_id,'') and source_event_id=p_source_event_id) then raise exception using errcode='23505',message='customer_activity_source_already_recorded'; end if;
  raise;
end $$;

revoke all on function public.e10_org_record_customer_activity(uuid,text,uuid,uuid,text,uuid,uuid,numeric,numeric,numeric,numeric,numeric,text,text,timestamptz,text,text,text,text,text,jsonb,text,text) from public,anon;
grant execute on function public.e10_org_record_customer_activity(uuid,text,uuid,uuid,text,uuid,uuid,numeric,numeric,numeric,numeric,numeric,text,text,timestamptz,text,text,text,text,text,jsonb,text,text) to authenticated,service_role;

comment on table public.e10_customer_activity_observations is 'Immutable provisional customer activity. It is never official posted spend and never asserts payment or settlement.';
comment on function public.e10_org_record_customer_activity(uuid,text,uuid,uuid,text,uuid,uuid,numeric,numeric,numeric,numeric,numeric,text,text,timestamptz,text,text,text,text,text,jsonb,text,text) is 'Records provisional activity and its operational event atomically; posted=false is invariant.';
