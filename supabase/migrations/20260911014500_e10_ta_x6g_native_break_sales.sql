-- TA-X6g atomic native break-sale capture. Provisional evidence only; never posted spend.
alter table public.e10_break_slots add column native_sale_revision bigint not null default 0 check(native_sale_revision>=0);

create table public.e10_native_break_sales(
 id uuid primary key default gen_random_uuid(),organization_id uuid not null,session_id uuid not null,slot_id uuid not null,
 sale_sequence bigint not null check(sale_sequence>0),buyer_user_id uuid references auth.users(id) on delete set null,buyer_handle text,
 customer_id uuid,buyer_identity_status text not null check(buyer_identity_status in ('unresolved','reviewed_attributed','verified_auth')),
 quantity numeric not null check(quantity>0 and quantity::text not in ('NaN','Infinity','-Infinity')),
 merchandise_gross numeric not null check(merchandise_gross>=0 and merchandise_gross::text not in ('NaN','Infinity','-Infinity')),
 currency text not null check(currency~'^[A-Z]{3}$'),sale_method text,occurred_at timestamptz not null check(isfinite(occurred_at)),
 incentives jsonb not null check(jsonb_typeof(incentives)='array'),raw_evidence jsonb not null check(jsonb_typeof(raw_evidence)='object'),
 prior_slot_price numeric,activity_observation_id uuid not null,commercial_event_id uuid not null,break_event_id bigint not null,
 idempotency_key text not null check(length(btrim(idempotency_key)) between 1 and 500),request_fingerprint text not null check(btrim(request_fingerprint)<>''),
 created_by uuid references auth.users(id),created_at timestamptz not null default now(),
 unique(organization_id,id),unique(organization_id,slot_id,sale_sequence),unique(organization_id,idempotency_key),
 unique(organization_id,activity_observation_id),unique(organization_id,commercial_event_id),unique(organization_id,break_event_id),
 foreign key(organization_id,session_id) references public.e10_break_sessions(organization_id,id),
 foreign key(organization_id,slot_id) references public.e10_break_slots(organization_id,id),
 foreign key(organization_id,customer_id) references public.e10_customers(organization_id,id),
 foreign key(organization_id,activity_observation_id) references public.e10_customer_activity_observations(organization_id,id),
 foreign key(organization_id,commercial_event_id) references public.e10_commercial_events(organization_id,id),
 foreign key(organization_id,break_event_id) references public.e10_break_events(organization_id,id),
 check(buyer_handle is null or btrim(buyer_handle)<>'')
);
create table public.e10_native_break_sale_transitions(
 id uuid primary key default gen_random_uuid(),organization_id uuid not null,sale_id uuid not null,
 transition_type text not null check(transition_type in ('committed','released')),reason text not null check(length(btrim(reason)) between 1 and 2000),
 evidence jsonb not null check(jsonb_typeof(evidence)='object' and octet_length(evidence::text)<=65536),
 break_event_id bigint,idempotency_key text not null check(length(btrim(idempotency_key)) between 1 and 500),
 request_fingerprint text not null check(btrim(request_fingerprint)<>''),created_by uuid references auth.users(id),created_at timestamptz not null default now(),
 unique(organization_id,id),unique(organization_id,sale_id,transition_type),unique(organization_id,idempotency_key),
 foreign key(organization_id,sale_id) references public.e10_native_break_sales(organization_id,id),
 foreign key(organization_id,break_event_id) references public.e10_break_events(organization_id,id),
 check((transition_type='committed' and break_event_id is null) or (transition_type='released' and break_event_id is not null))
);
create table public.e10_native_break_sale_receipts(
 organization_id uuid not null,idempotency_key text not null,operation text not null check(operation in ('commit','release')),
 entity_id uuid not null,request_fingerprint text not null,result jsonb not null check(jsonb_typeof(result)='object'),
 created_by uuid references auth.users(id),created_at timestamptz not null default now(),primary key(organization_id,idempotency_key),
 foreign key(organization_id) references public.e10_organizations(id)
);
create index e10_native_break_sales_slot_idx on public.e10_native_break_sales(organization_id,slot_id,sale_sequence desc);
create index e10_native_break_sales_customer_idx on public.e10_native_break_sales(organization_id,customer_id,occurred_at,id) where customer_id is not null;

alter table public.e10_native_break_sales enable row level security;
alter table public.e10_native_break_sale_transitions enable row level security;
alter table public.e10_native_break_sale_receipts enable row level security;
revoke all on public.e10_native_break_sales,public.e10_native_break_sale_transitions,public.e10_native_break_sale_receipts from public,anon,authenticated;
grant all on public.e10_native_break_sales,public.e10_native_break_sale_transitions,public.e10_native_break_sale_receipts to service_role;
create trigger e10_native_break_sales_append_only_trg before update or delete on public.e10_native_break_sales for each row execute function e10.reject_append_only_change();
create trigger e10_native_break_sale_transitions_append_only_trg before update or delete on public.e10_native_break_sale_transitions for each row execute function e10.reject_append_only_change();
create trigger e10_native_break_sale_receipts_append_only_trg before update or delete on public.e10_native_break_sale_receipts for each row execute function e10.reject_append_only_change();

create view public.e10_current_native_break_sales with(security_invoker=true) as
select s.* from public.e10_native_break_sales s where not exists(
 select 1 from public.e10_native_break_sale_transitions t where t.organization_id=s.organization_id and t.sale_id=s.id and t.transition_type='released');
revoke all on public.e10_current_native_break_sales from public,anon,authenticated;
grant select on public.e10_current_native_break_sales to service_role;

create function e10.native_break_slot_managed(p_org uuid,p_slot uuid) returns boolean language plpgsql stable security definer set search_path=public as $$
declare v_session uuid;v_caller text:=current_setting('role',true);
begin
 if v_caller in ('postgres','service_role') then
  return exists(select 1 from public.e10_native_break_sales s where s.organization_id=p_org and s.slot_id=p_slot);
 end if;
 select sl.session_id into v_session from public.e10_break_slots sl where sl.organization_id=p_org and sl.id=p_slot;
 if v_session is null or not e10.owns_session(v_session) or not e10.has_org_cap(p_org,'act.live_run') then
  raise exception using errcode='42501',message='native_break_slot_scope_denied';
 end if;
 return exists(select 1 from public.e10_native_break_sales s where s.organization_id=p_org and s.slot_id=p_slot);
end
$$;
revoke all on function e10.native_break_slot_managed(uuid,uuid) from public,anon;
grant execute on function e10.native_break_slot_managed(uuid,uuid) to authenticated,service_role;

create function e10.protect_managed_native_break_slot() returns trigger language plpgsql security invoker set search_path=public as $$
begin
 if current_user not in ('postgres','service_role') and e10.native_break_slot_managed(old.organization_id,old.id)
   and (tg_op='DELETE' or (new.organization_id,new.session_id,new.native_sale_revision,new.state,new.buyer_uid,new.buyer_handle,new.price,new.sold_at,new.incentives) is distinct from
       (old.organization_id,old.session_id,old.native_sale_revision,old.state,old.buyer_uid,old.buyer_handle,old.price,old.sold_at,old.incentives))
 then raise exception using errcode='42501',message='managed_native_break_slot_requires_rpc';end if;
 return case when tg_op='DELETE' then old else new end;
end $$;
revoke all on function e10.protect_managed_native_break_slot() from public,anon,authenticated;
grant execute on function e10.protect_managed_native_break_slot() to service_role;
create trigger e10_protect_managed_native_break_slot_trg before update or delete on public.e10_break_slots for each row execute function e10.protect_managed_native_break_slot();

create function e10.resolve_native_break_buyer(p_org uuid,p_buyer_user uuid,p_handle text)
returns table(customer_id uuid,identity_status text) language plpgsql stable security definer set search_path=public as $$
declare v_handle text:=lower(btrim(regexp_replace(coalesce(p_handle,''),'^@','')));v_user_customer uuid;v_handle_customer uuid;v_user_count integer:=0;v_handle_count integer:=0;v_consistent_verified integer:=0;
begin
 if p_buyer_user is not null then
  select count(distinct e10.customer_effective_id(p_org,i.customer_id)),(array_agg(distinct e10.customer_effective_id(p_org,i.customer_id)))[1]
  into v_user_count,v_user_customer
  from public.e10_current_customer_identities i join public.e10_viewer_handle_claims h on h.id=i.viewer_handle_claim_id
  join public.e10_customers c on c.organization_id=i.organization_id and c.id=e10.customer_effective_id(p_org,i.customer_id) and c.status='active'
  where i.organization_id=p_org and i.identity_action='attach' and i.verification_basis='verified_handle'
    and i.verified_user_id=p_buyer_user and h.user_id=p_buyer_user and h.status='verified';
  if v_handle<>'' then
   select count(distinct e10.customer_effective_id(p_org,i.customer_id)),(array_agg(distinct e10.customer_effective_id(p_org,i.customer_id)))[1],
     count(*) filter(where i.verification_basis='verified_handle' and i.verified_user_id=p_buyer_user and h.user_id=p_buyer_user and h.status='verified')
   into v_handle_count,v_handle_customer,v_consistent_verified
   from public.e10_current_customer_identities i left join public.e10_viewer_handle_claims h on h.id=i.viewer_handle_claim_id
   join public.e10_customers c on c.organization_id=i.organization_id and c.id=e10.customer_effective_id(p_org,i.customer_id) and c.status='active'
   where i.organization_id=p_org and i.identity_action='attach' and i.identity_kind='channel_account' and lower(i.channel)='whatnot'
    and lower(btrim(regexp_replace(i.external_account_id,'^@','')))=v_handle
    and (i.verification_basis='operator_review' or (i.verification_basis='verified_handle' and h.status='verified'));
  end if;
  if v_user_count=1 and (v_handle='' or (v_handle_count=1 and v_handle_customer=v_user_customer and v_consistent_verified=1)) then return query select v_user_customer,'verified_auth'::text;else return query select null::uuid,'unresolved'::text;end if;
  return;
 end if;
 if v_handle<>'' then
  select count(distinct e10.customer_effective_id(p_org,i.customer_id)),(array_agg(distinct e10.customer_effective_id(p_org,i.customer_id)))[1] into v_handle_count,v_handle_customer from public.e10_current_customer_identities i
  join public.e10_customers c on c.organization_id=i.organization_id and c.id=e10.customer_effective_id(p_org,i.customer_id) and c.status='active'
  left join public.e10_viewer_handle_claims h on h.id=i.viewer_handle_claim_id
  where i.organization_id=p_org and i.identity_action='attach' and i.identity_kind='channel_account' and lower(i.channel)='whatnot'
   and lower(btrim(regexp_replace(i.external_account_id,'^@','')))=v_handle
   and (i.verification_basis='operator_review' or (i.verification_basis='verified_handle' and h.status='verified'));
 end if;
 return query select case when v_handle_count=1 then v_handle_customer else null end,case when v_handle_count=1 then 'reviewed_attributed' else 'unresolved' end;
end $$;
revoke all on function e10.resolve_native_break_buyer(uuid,uuid,text) from public,anon,authenticated;
grant execute on function e10.resolve_native_break_buyer(uuid,uuid,text) to service_role;

create function public.e10_org_commit_native_break_sale(
 p_org uuid,p_session uuid,p_slot uuid,p_expected_slot_revision bigint,p_buyer_user uuid,p_buyer_handle text,p_quantity numeric,
 p_price numeric,p_currency text,p_sale_method text,p_occurred_at timestamptz,p_incentives jsonb,p_evidence jsonb,p_idempotency_key text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_fp text;v_receipt record;v_session record;v_slot record;v_customer uuid;v_identity text;v_sale uuid:=gen_random_uuid();v_activity uuid:=gen_random_uuid();v_event uuid:=gen_random_uuid();v_break_event bigint;v_seq bigint;v_result jsonb;v_handle text:=nullif(btrim(p_buyer_handle),'');
begin
 if not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.live_run') then raise exception using errcode='42501',message='native_break_sale_denied';end if;
 if p_expected_slot_revision is null or p_expected_slot_revision<0 or p_quantity is null or p_quantity<=0 or p_quantity::text in('NaN','Infinity','-Infinity')
  or p_price is null or p_price<0 or p_price::text in('NaN','Infinity','-Infinity') or p_currency is null or p_currency!~'^[A-Z]{3}$'
  or p_occurred_at is null or not isfinite(p_occurred_at) or p_incentives is null or jsonb_typeof(p_incentives)<>'array'
  or p_evidence is null or jsonb_typeof(p_evidence)<>'object' or octet_length(p_evidence::text)>65536
  or octet_length(p_incentives::text)>16384 or (v_handle is not null and length(v_handle)>200) or (p_sale_method is not null and length(btrim(p_sale_method)) not between 1 and 100)
  or p_idempotency_key is null or length(btrim(p_idempotency_key)) not between 1 and 500 or (p_buyer_user is null and v_handle is null)
 then raise exception using errcode='22023',message='native_break_sale_invalid';end if;
 v_fp:=md5(jsonb_build_object('v','native-break-sale-v1','session',p_session,'slot',p_slot,'expected',p_expected_slot_revision,'buyer_user',p_buyer_user,'handle',v_handle,'quantity',p_quantity,'price',p_price,'currency',p_currency,'method',p_sale_method,'occurred',extract(epoch from p_occurred_at),'incentives',p_incentives,'evidence',p_evidence)::text);
 perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|customer-resolution-topology',0));
 if not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.live_run') then raise exception using errcode='42501',message='native_break_sale_denied';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|native-break-sale-receipt|'||p_idempotency_key,0));
 select operation,request_fingerprint,result into v_receipt from public.e10_native_break_sale_receipts where organization_id=p_org and idempotency_key=p_idempotency_key;
 if found then if v_receipt.operation<>'commit' or v_receipt.request_fingerprint<>v_fp then raise exception using errcode='22023',message='idempotency_key_mismatch';end if;return v_receipt.result||'{"replay":true}'::jsonb;end if;
 select * into v_session from public.e10_break_sessions where organization_id=p_org and id=p_session for update;
 if not found or v_session.status<>'active' or not e10.owns_session(p_session) then raise exception using errcode='42501',message='native_break_session_denied';end if;
 select * into v_slot from public.e10_break_slots where organization_id=p_org and id=p_slot and session_id=p_session for update;
 if not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.live_run') then raise exception using errcode='42501',message='native_break_sale_denied';end if;
 if not found then raise exception using errcode='42501',message='native_break_slot_denied';end if;
 if v_slot.native_sale_revision<>p_expected_slot_revision or v_slot.state='sold' then raise exception using errcode='40001',message='native_break_slot_revision_conflict';end if;
 select r.customer_id,r.identity_status into v_customer,v_identity from e10.resolve_native_break_buyer(p_org,p_buyer_user,v_handle) r;
 select coalesce(max(sale_sequence),0)+1 into v_seq from public.e10_native_break_sales where organization_id=p_org and slot_id=p_slot;
 insert into public.e10_customer_activity_observations(id,organization_id,activity_kind,customer_id,buyer_user_id,buyer_alias,buyer_identity_status,break_session_id,break_slot_id,quantity,merchandise_gross,merchandise_discount,shipping_amount,tax_amount,currency,sale_method,occurred_at,occurred_at_precision,source_kind,source_connection_id,source_reference,source_event_id,raw_payload,evidence_quality,idempotency_key,request_fingerprint,commercial_event_id,created_by)
 values(v_activity,p_org,'break',v_customer,p_buyer_user,v_handle,v_identity,p_session,p_slot,p_quantity,p_price,0,null,null,p_currency,p_sale_method,p_occurred_at,'exact','native','live-break:'||p_session,p_slot::text,'sale:'||v_sale,p_evidence,'native_system','native-sale:'||md5(p_idempotency_key),v_fp,v_event,auth.uid());
 insert into public.e10_commercial_events(id,organization_id,event_type,event_schema_version,subject_type,subject_id,occurred_at,occurred_at_precision,idempotency_key,source_kind,source_connection_id,source_reference,source_event_id,correlation_id,evidence_quality,payload,created_by,request_fingerprint,customer_activity_observation_id)
 values(v_event,p_org,'sale_committed',1,'sale',v_sale::text,p_occurred_at,'exact','native-sale-event:'||md5(p_idempotency_key),'native','live-break:'||p_session,p_slot::text,'sale:'||v_sale,p_session::text,'native_system',jsonb_build_object('sale_id',v_sale,'activity_kind','break','provisional_only',true),auth.uid(),md5('native-sale-event|'||v_fp),v_activity);
 insert into public.e10_break_events(organization_id,session_id,slot_id,type,payload,actor_uid) values(p_org,p_session,p_slot,'spot_sold',jsonb_build_object('native_sale_id',v_sale,'buyer_handle',v_handle,'buyer_uid',p_buyer_user,'price',p_price,'currency',p_currency),auth.uid()) returning id into v_break_event;
 insert into public.e10_native_break_sales(id,organization_id,session_id,slot_id,sale_sequence,buyer_user_id,buyer_handle,customer_id,buyer_identity_status,quantity,merchandise_gross,currency,sale_method,occurred_at,incentives,raw_evidence,prior_slot_price,activity_observation_id,commercial_event_id,break_event_id,idempotency_key,request_fingerprint,created_by)
 values(v_sale,p_org,p_session,p_slot,v_seq,p_buyer_user,v_handle,v_customer,v_identity,p_quantity,p_price,p_currency,p_sale_method,p_occurred_at,p_incentives,p_evidence,v_slot.price,v_activity,v_event,v_break_event,p_idempotency_key,v_fp,auth.uid());
 insert into public.e10_native_break_sale_transitions(organization_id,sale_id,transition_type,reason,evidence,idempotency_key,request_fingerprint,created_by) values(p_org,v_sale,'committed','native board sale committed',p_evidence,'commit:'||md5(p_idempotency_key),v_fp,auth.uid());
 update public.e10_break_slots set state='sold',buyer_uid=p_buyer_user,buyer_handle=v_handle,price=p_price,sold_at=p_occurred_at,incentives=p_incentives,native_sale_revision=native_sale_revision+1,updated_at=clock_timestamp() where id=p_slot;
 v_result:=jsonb_build_object('ok',true,'replay',false,'sale_id',v_sale,'sale_sequence',v_seq,'activity_id',v_activity,'commercial_event_id',v_event,'break_event_id',v_break_event,'customer_id',v_customer,'identity_status',v_identity,'slot_revision',p_expected_slot_revision+1,'posted',false,'paid',false,'settled',false);
 insert into public.e10_native_break_sale_receipts values(p_org,p_idempotency_key,'commit',v_sale,v_fp,v_result,auth.uid(),now());return v_result;
end $$;

create function public.e10_org_release_native_break_sale(p_org uuid,p_session uuid,p_slot uuid,p_sale uuid,p_expected_slot_revision bigint,p_reason text,p_evidence jsonb,p_idempotency_key text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_fp text;v_receipt record;v_session record;v_slot record;v_sale_row record;v_break_event bigint;v_result jsonb;
begin
 if not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.live_run') then raise exception using errcode='42501',message='native_break_sale_release_denied';end if;
 if p_expected_slot_revision is null or p_expected_slot_revision<0 or p_reason is null or length(btrim(p_reason)) not between 1 and 2000 or p_evidence is null or jsonb_typeof(p_evidence)<>'object' or octet_length(p_evidence::text)>65536 or p_idempotency_key is null or length(btrim(p_idempotency_key)) not between 1 and 500 then raise exception using errcode='22023',message='native_break_sale_release_invalid';end if;
 v_fp:=md5(jsonb_build_object('v','native-break-release-v1','session',p_session,'slot',p_slot,'sale',p_sale,'expected',p_expected_slot_revision,'reason',btrim(p_reason),'evidence',p_evidence)::text);
 perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|customer-resolution-topology',0));
 if not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.live_run') then raise exception using errcode='42501',message='native_break_sale_release_denied';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|native-break-sale-receipt|'||p_idempotency_key,0));
 select operation,request_fingerprint,result into v_receipt from public.e10_native_break_sale_receipts where organization_id=p_org and idempotency_key=p_idempotency_key;
 if found then if v_receipt.operation<>'release' or v_receipt.request_fingerprint<>v_fp then raise exception using errcode='22023',message='idempotency_key_mismatch';end if;return v_receipt.result||'{"replay":true}'::jsonb;end if;
 select * into v_session from public.e10_break_sessions where organization_id=p_org and id=p_session for update;
 if not found or not e10.owns_session(p_session) then raise exception using errcode='42501',message='native_break_session_denied';end if;
 select * into v_slot from public.e10_break_slots where organization_id=p_org and id=p_slot and session_id=p_session for update;
 if not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.live_run') then raise exception using errcode='42501',message='native_break_sale_release_denied';end if;
 select * into v_sale_row from public.e10_current_native_break_sales where organization_id=p_org and id=p_sale and slot_id=p_slot and session_id=p_session;
 if v_slot.id is null or v_sale_row.id is null or v_slot.state<>'sold' then raise exception using errcode='42501',message='native_break_active_sale_denied';end if;
 if v_slot.native_sale_revision<>p_expected_slot_revision then raise exception using errcode='40001',message='native_break_slot_revision_conflict';end if;
 insert into public.e10_break_events(organization_id,session_id,slot_id,type,payload,actor_uid) values(p_org,p_session,p_slot,'spot_released',jsonb_build_object('native_sale_id',p_sale,'reason',btrim(p_reason)),auth.uid()) returning id into v_break_event;
 insert into public.e10_native_break_sale_transitions(organization_id,sale_id,transition_type,reason,evidence,break_event_id,idempotency_key,request_fingerprint,created_by) values(p_org,p_sale,'released',btrim(p_reason),p_evidence,v_break_event,'release:'||md5(p_idempotency_key),v_fp,auth.uid());
 update public.e10_break_slots set state='available',buyer_uid=null,buyer_handle=null,price=v_sale_row.prior_slot_price,sold_at=null,incentives='[]',native_sale_revision=native_sale_revision+1,updated_at=clock_timestamp() where id=p_slot;
 v_result:=jsonb_build_object('ok',true,'replay',false,'sale_id',p_sale,'break_event_id',v_break_event,'slot_revision',p_expected_slot_revision+1,'posted',false,'refund_created',false);
 insert into public.e10_native_break_sale_receipts values(p_org,p_idempotency_key,'release',p_sale,v_fp,v_result,auth.uid(),now());return v_result;
end $$;

revoke all on function public.e10_org_commit_native_break_sale(uuid,uuid,uuid,bigint,uuid,text,numeric,numeric,text,text,timestamptz,jsonb,jsonb,text) from public,anon;
revoke all on function public.e10_org_release_native_break_sale(uuid,uuid,uuid,uuid,bigint,text,jsonb,text) from public,anon;
grant execute on function public.e10_org_commit_native_break_sale(uuid,uuid,uuid,bigint,uuid,text,numeric,numeric,text,text,timestamptz,jsonb,jsonb,text),public.e10_org_release_native_break_sale(uuid,uuid,uuid,uuid,bigint,text,jsonb,text) to authenticated,service_role;
comment on table public.e10_native_break_sales is 'Immutable native board-sale identity and provisional evidence. Never official posted spend.';
comment on column public.e10_break_slots.native_sale_revision is 'Monotonic CAS for RPC-managed native sale/release transitions; legacy slots remain compatible until first managed sale.';
