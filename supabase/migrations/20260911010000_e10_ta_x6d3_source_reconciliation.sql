-- TA-X6d.3 additional evidence reconciliation. Evidence attaches to one existing contribution; it never creates a second sale.

create table public.e10_customer_transaction_reconciliation_cases (
  id uuid primary key default gen_random_uuid(),organization_id uuid not null references public.e10_organizations(id),
  source_kind text not null check(source_kind in ('manual','import','native')),source_connection_id text,source_event_id text not null,source_component_id text not null,
  currency text not null check(currency~'^[A-Z]{3}$'),observed_merchandise_amount numeric,observed_shipping_amount numeric,observed_tax_amount numeric,
  evidence jsonb not null check(jsonb_typeof(evidence)='object' and octet_length(evidence::text)<=65536),
  idempotency_key text not null,request_fingerprint text not null,created_by uuid references auth.users(id),created_at timestamptz not null default now(),
  unique(organization_id,id),unique(organization_id,idempotency_key),
  check(btrim(source_event_id)<>'' and btrim(source_component_id)<>'' and btrim(idempotency_key)<>'' and btrim(request_fingerprint)<>''),
  check(source_connection_id is null or btrim(source_connection_id)<>''),
  check(num_nonnulls(observed_merchandise_amount,observed_shipping_amount,observed_tax_amount)>0),
  check((observed_merchandise_amount is null or (observed_merchandise_amount>=0 and observed_merchandise_amount::text not in ('NaN','Infinity','-Infinity'))) and (observed_shipping_amount is null or (observed_shipping_amount>=0 and observed_shipping_amount::text not in ('NaN','Infinity','-Infinity'))) and (observed_tax_amount is null or (observed_tax_amount>=0 and observed_tax_amount::text not in ('NaN','Infinity','-Infinity'))))
);
create unique index e10_customer_reconciliation_source_uq on public.e10_customer_transaction_reconciliation_cases(organization_id,source_kind,coalesce(source_connection_id,''),source_event_id,source_component_id);
create index e10_customer_reconciliation_time_idx on public.e10_customer_transaction_reconciliation_cases(organization_id,created_at desc,id desc);

create table public.e10_customer_transaction_reconciliation_decisions (
  id uuid primary key default gen_random_uuid(),organization_id uuid not null,case_id uuid not null,revision integer not null,
  action text not null check(action in ('ambiguous','link','reject')),match_basis text,
  transaction_id uuid,transaction_line_id uuid,reason text not null check(btrim(reason)<>''),evidence jsonb not null check(jsonb_typeof(evidence)='object' and octet_length(evidence::text)<=65536),
  idempotency_key text not null,request_fingerprint text not null,decided_by uuid references auth.users(id),decided_at timestamptz not null default now(),
  unique(organization_id,id),unique(organization_id,case_id,revision),unique(organization_id,idempotency_key),
  foreign key(organization_id,case_id) references public.e10_customer_transaction_reconciliation_cases(organization_id,id),
  foreign key(organization_id,transaction_id) references public.e10_customer_transactions(organization_id,id),
  foreign key(organization_id,transaction_line_id) references public.e10_customer_transaction_lines(organization_id,id),
  check((action='link' and match_basis in ('durable_external_id','reviewed_match') and transaction_id is not null and transaction_line_id is not null) or (action in ('ambiguous','reject') and match_basis is null and transaction_id is null and transaction_line_id is null))
);
create index e10_customer_reconciliation_decision_latest_idx on public.e10_customer_transaction_reconciliation_decisions(organization_id,case_id,revision desc);

create table public.e10_customer_transaction_evidence_links (
  id uuid primary key default gen_random_uuid(),organization_id uuid not null,case_id uuid not null,decision_id uuid not null,
  transaction_id uuid not null,transaction_line_id uuid not null,linked_by uuid references auth.users(id),linked_at timestamptz not null default now(),
  unique(organization_id,id),unique(organization_id,case_id),unique(organization_id,decision_id),
  foreign key(organization_id,case_id) references public.e10_customer_transaction_reconciliation_cases(organization_id,id),
  foreign key(organization_id,decision_id) references public.e10_customer_transaction_reconciliation_decisions(organization_id,id),
  foreign key(organization_id,transaction_id) references public.e10_customer_transactions(organization_id,id),
  foreign key(organization_id,transaction_line_id) references public.e10_customer_transaction_lines(organization_id,id)
);

alter table public.e10_customer_commercial_receipts drop constraint e10_customer_commercial_receipts_operation_check;
alter table public.e10_customer_commercial_receipts add constraint e10_customer_commercial_receipts_operation_check check(operation in ('create_draft','amend_draft','approve_draft','reopen_draft','post_draft','adjust_transaction','finalize_transaction_component','open_transaction_reconciliation','decide_transaction_reconciliation'));

alter table public.e10_customer_transaction_reconciliation_cases enable row level security;
alter table public.e10_customer_transaction_reconciliation_decisions enable row level security;
alter table public.e10_customer_transaction_evidence_links enable row level security;
revoke all on public.e10_customer_transaction_reconciliation_cases,public.e10_customer_transaction_reconciliation_decisions,public.e10_customer_transaction_evidence_links from public,anon,authenticated;
grant all on public.e10_customer_transaction_reconciliation_cases,public.e10_customer_transaction_reconciliation_decisions,public.e10_customer_transaction_evidence_links to service_role;
create trigger e10_customer_reconciliation_case_append_only_trg before update or delete on public.e10_customer_transaction_reconciliation_cases for each row execute function e10.reject_append_only_change();
create trigger e10_customer_reconciliation_decision_append_only_trg before update or delete on public.e10_customer_transaction_reconciliation_decisions for each row execute function e10.reject_append_only_change();
create trigger e10_customer_evidence_link_append_only_trg before update or delete on public.e10_customer_transaction_evidence_links for each row execute function e10.reject_append_only_change();

create function public.e10_org_open_customer_transaction_reconciliation(
  p_org uuid,p_source_kind text,p_source_connection_id text,p_source_event_id text,p_source_component_id text,p_currency text,
  p_merchandise_amount numeric,p_shipping_amount numeric,p_tax_amount numeric,p_evidence jsonb,p_idempotency_key text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_fp text;v_old record;v_id uuid:=gen_random_uuid();v_result jsonb;
begin
  if current_setting('role',true)<>'service_role' and (not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.reconcile_customer_transactions')) then raise exception using errcode='42501',message='open_customer_reconciliation_denied';end if;
  if p_source_kind not in ('manual','import','native') or (p_source_kind='native' and current_setting('role',true)<>'service_role') then raise exception using errcode='42501',message='untrusted_native_reconciliation_source';end if;
  if p_source_event_id is null or btrim(p_source_event_id)='' or p_source_component_id is null or btrim(p_source_component_id)='' or p_idempotency_key is null or btrim(p_idempotency_key)='' or p_currency is null or p_currency!~'^[A-Z]{3}$' or p_evidence is null or jsonb_typeof(p_evidence)<>'object' or octet_length(p_evidence::text)>65536 or num_nonnulls(p_merchandise_amount,p_shipping_amount,p_tax_amount)=0 then raise exception using errcode='22023',message='customer_reconciliation_evidence_invalid';end if;
  if (p_merchandise_amount is not null and (p_merchandise_amount<0 or p_merchandise_amount::text in ('NaN','Infinity','-Infinity'))) or (p_shipping_amount is not null and (p_shipping_amount<0 or p_shipping_amount::text in ('NaN','Infinity','-Infinity'))) or (p_tax_amount is not null and (p_tax_amount<0 or p_tax_amount::text in ('NaN','Infinity','-Infinity'))) then raise exception using errcode='22023',message='customer_reconciliation_amount_invalid';end if;
  v_fp:=md5(jsonb_build_object('v','customer-reconciliation-case-v1','source_kind',p_source_kind,'connection',p_source_connection_id,'event',p_source_event_id,'component',p_source_component_id,'currency',p_currency,'merchandise',p_merchandise_amount,'shipping',p_shipping_amount,'tax',p_tax_amount,'evidence',p_evidence)::text);
  perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|customer-commercial|'||p_idempotency_key,0));
  select request_fingerprint,result into v_old from public.e10_customer_commercial_receipts where organization_id=p_org and idempotency_key=p_idempotency_key;
  if found then if v_old.request_fingerprint<>v_fp then raise exception using errcode='22023',message='idempotency_key_mismatch';end if;return v_old.result||'{"replay":true}'::jsonb;end if;
  insert into public.e10_customer_transaction_reconciliation_cases(id,organization_id,source_kind,source_connection_id,source_event_id,source_component_id,currency,observed_merchandise_amount,observed_shipping_amount,observed_tax_amount,evidence,idempotency_key,request_fingerprint,created_by)
  values(v_id,p_org,p_source_kind,nullif(btrim(p_source_connection_id),''),btrim(p_source_event_id),btrim(p_source_component_id),p_currency,p_merchandise_amount,p_shipping_amount,p_tax_amount,p_evidence,p_idempotency_key,v_fp,auth.uid());
  v_result:=jsonb_build_object('ok',true,'replay',false,'case_id',v_id,'state','unresolved','contribution_created',false);
  insert into public.e10_customer_commercial_receipts values(p_org,p_idempotency_key,'open_transaction_reconciliation',v_id,v_fp,v_result,auth.uid(),now());return v_result;
exception when unique_violation then
  if exists(select 1 from public.e10_customer_transaction_reconciliation_cases c where c.organization_id=p_org and c.source_kind=p_source_kind and coalesce(c.source_connection_id,'')=coalesce(p_source_connection_id,'') and c.source_event_id=p_source_event_id and c.source_component_id=p_source_component_id) then raise exception using errcode='23505',message='reconciliation_source_component_already_opened';end if;raise;
end $$;

create function public.e10_org_decide_customer_transaction_reconciliation(
  p_org uuid,p_case uuid,p_expected_revision integer,p_action text,p_match_basis text,p_transaction_id uuid,p_transaction_line_id uuid,
  p_reason text,p_evidence jsonb,p_idempotency_key text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_fp text;v_old record;v_case record;v_line record;v_current integer;v_id uuid:=gen_random_uuid();v_result jsonb;
begin
  if not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.reconcile_customer_transactions') then raise exception using errcode='42501',message='decide_customer_reconciliation_denied';end if;
  if p_expected_revision<0 or p_action not in ('ambiguous','link','reject') or p_reason is null or btrim(p_reason)='' or p_evidence is null or jsonb_typeof(p_evidence)<>'object' or octet_length(p_evidence::text)>65536 or p_idempotency_key is null or btrim(p_idempotency_key)='' then raise exception using errcode='22023',message='customer_reconciliation_decision_invalid';end if;
  if (p_action='link' and (p_match_basis not in ('durable_external_id','reviewed_match') or p_transaction_id is null or p_transaction_line_id is null)) or (p_action<>'link' and (p_match_basis is not null or p_transaction_id is not null or p_transaction_line_id is not null)) then raise exception using errcode='22023',message='customer_reconciliation_link_semantics_invalid';end if;
  v_fp:=md5(jsonb_build_object('v','customer-reconciliation-decision-v1','case',p_case,'expected_revision',p_expected_revision,'action',p_action,'match_basis',p_match_basis,'transaction',p_transaction_id,'line',p_transaction_line_id,'reason',p_reason,'evidence',p_evidence)::text);
  perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|customer-commercial|'||p_idempotency_key,0));
  select request_fingerprint,result into v_old from public.e10_customer_commercial_receipts where organization_id=p_org and idempotency_key=p_idempotency_key;
  if found then if v_old.request_fingerprint<>v_fp then raise exception using errcode='22023',message='idempotency_key_mismatch';end if;return v_old.result||'{"replay":true}'::jsonb;end if;
  perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|customer-reconciliation|'||p_case::text,0));
  select * into v_case from public.e10_customer_transaction_reconciliation_cases where organization_id=p_org and id=p_case;
  if not found then raise exception using errcode='42501',message='customer_reconciliation_case_denied';end if;
  select coalesce(max(revision),0) into v_current from public.e10_customer_transaction_reconciliation_decisions where organization_id=p_org and case_id=p_case;
  if v_current<>p_expected_revision then raise exception using errcode='40001',message='customer_reconciliation_stale_revision';end if;
  if exists(select 1 from public.e10_customer_transaction_evidence_links where organization_id=p_org and case_id=p_case) then raise exception using errcode='40001',message='customer_reconciliation_already_linked';end if;
  if p_action='link' then
    perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|customer-adjustment|'||p_transaction_line_id::text,0));
    select l.id,t.currency into v_line from public.e10_customer_transaction_lines l join public.e10_customer_transactions t on t.organization_id=l.organization_id and t.id=l.transaction_id where l.organization_id=p_org and l.id=p_transaction_line_id and l.transaction_id=p_transaction_id;
    if not found then raise exception using errcode='42501',message='customer_reconciliation_line_denied';end if;
    if v_line.currency<>v_case.currency then raise exception using errcode='22023',message='customer_reconciliation_currency_mismatch';end if;
  end if;
  insert into public.e10_customer_transaction_reconciliation_decisions(id,organization_id,case_id,revision,action,match_basis,transaction_id,transaction_line_id,reason,evidence,idempotency_key,request_fingerprint,decided_by)
  values(v_id,p_org,p_case,p_expected_revision+1,p_action,p_match_basis,p_transaction_id,p_transaction_line_id,btrim(p_reason),p_evidence,p_idempotency_key,v_fp,auth.uid());
  if p_action='link' then insert into public.e10_customer_transaction_evidence_links(organization_id,case_id,decision_id,transaction_id,transaction_line_id,linked_by) values(p_org,p_case,v_id,p_transaction_id,p_transaction_line_id,auth.uid());end if;
  v_result:=jsonb_build_object('ok',true,'replay',false,'case_id',p_case,'decision_id',v_id,'revision',p_expected_revision+1,'state',case p_action when 'link' then 'linked' when 'reject' then 'rejected' else 'ambiguous' end,'contribution_created',false);
  insert into public.e10_customer_commercial_receipts values(p_org,p_idempotency_key,'decide_transaction_reconciliation',v_id,v_fp,v_result,auth.uid(),now());return v_result;
end $$;

create function public.e10_org_list_customer_transaction_reconciliation(p_org uuid,p_state text default null,p_limit integer default 50,p_before_created_at timestamptz default null,p_before_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare v_rows jsonb;
begin
  if not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.reconcile_customer_transactions') then raise exception using errcode='42501',message='list_customer_reconciliation_denied';end if;
  if p_state is not null and p_state not in ('unresolved','ambiguous','linked','rejected') then raise exception using errcode='22023',message='customer_reconciliation_state_invalid';end if;
  if p_limit<1 or p_limit>100 or ((p_before_created_at is null)<>(p_before_id is null)) then raise exception using errcode='22023',message='customer_reconciliation_page_invalid';end if;
  select coalesce(jsonb_agg(to_jsonb(q) order by q.created_at desc,q.id desc),'[]'::jsonb) into v_rows from (
    select c.id,c.source_kind,c.source_connection_id,c.source_event_id,c.source_component_id,c.currency,c.observed_merchandise_amount,c.observed_shipping_amount,c.observed_tax_amount,c.created_at,
      coalesce(case d.action when 'link' then 'linked' when 'reject' then 'rejected' when 'ambiguous' then 'ambiguous' end,'unresolved') state,d.revision,d.match_basis,d.transaction_id,d.transaction_line_id
    from public.e10_customer_transaction_reconciliation_cases c left join lateral(select * from public.e10_customer_transaction_reconciliation_decisions x where x.organization_id=c.organization_id and x.case_id=c.id order by x.revision desc limit 1)d on true
    where c.organization_id=p_org and (p_state is null or coalesce(case d.action when 'link' then 'linked' when 'reject' then 'rejected' when 'ambiguous' then 'ambiguous' end,'unresolved')=p_state)
      and (p_before_created_at is null or (c.created_at,c.id)<(p_before_created_at,p_before_id)) order by c.created_at desc,c.id desc limit p_limit
  )q;
  return jsonb_build_object('items',v_rows,'limit',p_limit);
end $$;

revoke all on function public.e10_org_open_customer_transaction_reconciliation(uuid,text,text,text,text,text,numeric,numeric,numeric,jsonb,text) from public,anon;
revoke all on function public.e10_org_decide_customer_transaction_reconciliation(uuid,uuid,integer,text,text,uuid,uuid,text,jsonb,text) from public,anon;
revoke all on function public.e10_org_list_customer_transaction_reconciliation(uuid,text,integer,timestamptz,uuid) from public,anon;
grant execute on function public.e10_org_open_customer_transaction_reconciliation(uuid,text,text,text,text,text,numeric,numeric,numeric,jsonb,text) to authenticated,service_role;
grant execute on function public.e10_org_decide_customer_transaction_reconciliation(uuid,uuid,integer,text,text,uuid,uuid,text,jsonb,text) to authenticated,service_role;
grant execute on function public.e10_org_list_customer_transaction_reconciliation(uuid,text,integer,timestamptz,uuid) to authenticated,service_role;
