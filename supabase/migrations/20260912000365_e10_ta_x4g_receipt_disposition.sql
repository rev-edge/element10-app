-- TA-X4g immutable reviewed quarantine disposition and correction.
-- Only accept and damage are modeled. No vendor credit, RTV, write-off,
-- salvage value, landed cost, payment, or accounting consequence is asserted.

alter table public.e10_stock_receipts add column disposition_revision bigint not null default 0
  check(disposition_revision>=0);

create table public.e10_receipt_disposition_decisions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.e10_organizations(id),
  stock_receipt_id uuid not null,
  stock_receipt_line_id uuid not null,
  inventory_lot_id uuid not null,
  root_decision_id uuid not null,
  predecessor_decision_id uuid,
  revision integer not null check(revision>0),
  action text not null check(action in('accept','damage')),
  quantity numeric not null check(quantity>0),
  reason text not null check(btrim(reason)<>''),
  inventory_movement_id uuid,
  decided_by uuid not null references auth.users(id),
  decided_at timestamptz not null default now(),
  unique(organization_id,id),
  unique(organization_id,root_decision_id,revision),
  unique(organization_id,predecessor_decision_id),
  foreign key(organization_id,stock_receipt_id)
    references public.e10_stock_receipts(organization_id,id),
  foreign key(organization_id,stock_receipt_line_id)
    references public.e10_stock_receipt_lines(organization_id,id),
  foreign key(organization_id,inventory_lot_id)
    references public.e10_inventory_lots(organization_id,id),
  foreign key(organization_id,root_decision_id)
    references public.e10_receipt_disposition_decisions(organization_id,id)
    deferrable initially deferred,
  foreign key(organization_id,predecessor_decision_id)
    references public.e10_receipt_disposition_decisions(organization_id,id),
  foreign key(organization_id,inventory_movement_id)
    references public.e10_inventory_movements(organization_id,id),
  check((revision=1 and predecessor_decision_id is null and root_decision_id=id)
    or (revision>1 and predecessor_decision_id is not null))
);
create index e10_receipt_disposition_line_idx on public.e10_receipt_disposition_decisions
  (organization_id,stock_receipt_line_id,root_decision_id,revision desc);
alter table public.e10_receipt_disposition_decisions enable row level security;
revoke all on table public.e10_receipt_disposition_decisions from public,anon,authenticated;
grant all on table public.e10_receipt_disposition_decisions to service_role;
create trigger e10_receipt_disposition_decisions_append_only_trg
  before update or delete on public.e10_receipt_disposition_decisions
  for each row execute function e10.reject_append_only_change();

create table public.e10_receipt_disposition_commands (
  organization_id uuid not null references public.e10_organizations(id),
  idempotency_key text not null check(btrim(idempotency_key)<>''),
  request_fingerprint text not null,
  stock_receipt_line_id uuid not null,
  result jsonb not null,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  primary key(organization_id,idempotency_key),
  foreign key(organization_id,stock_receipt_line_id)
    references public.e10_stock_receipt_lines(organization_id,id)
);
alter table public.e10_receipt_disposition_commands enable row level security;
revoke all on table public.e10_receipt_disposition_commands from public,anon,authenticated;
grant all on table public.e10_receipt_disposition_commands to service_role;
create trigger e10_receipt_disposition_commands_append_only_trg
  before update or delete on public.e10_receipt_disposition_commands
  for each row execute function e10.reject_append_only_change();

create or replace function e10.receipt_line_effective_quantities(p_org uuid,p_receipt_line uuid)
returns table(
  physical_received numeric,effective_accepted numeric,effective_damaged numeric,
  unresolved_quarantined numeric,reversed_quantity numeric,remaining_quantity numeric
) language sql stable security definer set search_path=public as $$
 with terminal as(
  select d.action,d.quantity
  from public.e10_receipt_disposition_decisions d
  where d.organization_id=p_org and d.stock_receipt_line_id=p_receipt_line
    and not exists(select 1 from public.e10_receipt_disposition_decisions s
      where s.organization_id=d.organization_id and s.predecessor_decision_id=d.id)
 ), disposition as(
  select coalesce(sum(quantity)filter(where action='accept'),0) accepted,
    coalesce(sum(quantity)filter(where action='damage'),0) damaged,
    coalesce(sum(quantity),0) decided from terminal
 )
 select l.received_quantity,
   case when r.status not in('posted','corrected') or exists(select 1 from public.e10_stock_receipt_reversals rv
     where rv.organization_id=l.organization_id and rv.stock_receipt_line_id=l.id) then 0 else l.accepted_quantity+d.accepted end,
   case when r.status not in('posted','corrected') or exists(select 1 from public.e10_stock_receipt_reversals rv
     where rv.organization_id=l.organization_id and rv.stock_receipt_line_id=l.id) then 0 else l.damaged_quantity+d.damaged end,
   case when r.status not in('posted','corrected') or exists(select 1 from public.e10_stock_receipt_reversals rv
     where rv.organization_id=l.organization_id and rv.stock_receipt_line_id=l.id) then 0 else l.quarantined_quantity-d.decided end,
   case when r.status='reversed' or exists(select 1 from public.e10_stock_receipt_reversals rv
     where rv.organization_id=l.organization_id and rv.stock_receipt_line_id=l.id) then l.received_quantity else 0 end,
   case when r.status not in('posted','corrected') or exists(select 1 from public.e10_stock_receipt_reversals rv
     where rv.organization_id=l.organization_id and rv.stock_receipt_line_id=l.id) then 0
        else l.received_quantity-l.accepted_quantity-l.damaged_quantity-l.quarantined_quantity end
 from public.e10_stock_receipt_lines l
 join public.e10_stock_receipts r on(r.organization_id,r.id)=(l.organization_id,l.stock_receipt_id)
 cross join disposition d
 where l.organization_id=p_org and l.id=p_receipt_line
$$;
revoke all on function e10.receipt_line_effective_quantities(uuid,uuid) from public,anon,authenticated;
grant execute on function e10.receipt_line_effective_quantities(uuid,uuid) to service_role;

-- Receipt-backed lots are the materialized projection used by the existing lot
-- writers. Fail closed if that projection ever disagrees with the shared
-- effective-quantity interpretation. Legacy lots without a receipt line are
-- deliberately outside this assertion.
create function e10.assert_receipt_lot_projection(p_org uuid,p_lot_id uuid) returns void
language plpgsql stable security definer set search_path=public as $$
declare line_id uuid;lot record;q record;
begin
  select l.stock_receipt_line_id,l.accepted_quantity,l.quarantined_quantity,r.status receipt_status
    into lot from public.e10_inventory_lots l
    join public.e10_stock_receipt_lines rl on(rl.organization_id,rl.id)=(l.organization_id,l.stock_receipt_line_id)
    join public.e10_stock_receipts r on(r.organization_id,r.id)=(rl.organization_id,rl.stock_receipt_id)
    where l.organization_id=p_org and l.id=p_lot_id;
  line_id:=lot.stock_receipt_line_id;
  if not found or line_id is null or lot.receipt_status not in('posted','corrected') then return;end if;
  select * into q from e10.receipt_line_effective_quantities(p_org,line_id);
  if not found or lot.accepted_quantity is distinct from q.effective_accepted
    or lot.quarantined_quantity is distinct from q.unresolved_quarantined then
    raise exception using errcode='55000',message='receipt_lot_projection_diverged';
  end if;
end $$;
revoke all on function e10.assert_receipt_lot_projection(uuid,uuid) from public,anon,authenticated;
grant execute on function e10.assert_receipt_lot_projection(uuid,uuid) to service_role;

-- Preserve X4b byte-compatible API behavior while making its receipt-backed
-- availability decision consume the shared X4g interpretation under the same
-- per-lot advisory lock. The original implementation remains service-only.
alter function public.e10_org_lot_reserve(uuid,uuid,numeric,uuid,text)
  rename to _e10_org_lot_reserve_x4b;
revoke all on function public._e10_org_lot_reserve_x4b(uuid,uuid,numeric,uuid,text)
  from public,anon,authenticated;
grant execute on function public._e10_org_lot_reserve_x4b(uuid,uuid,numeric,uuid,text) to service_role;
create function public.e10_org_lot_reserve(
  p_org uuid,p_lot_id uuid,p_quantity numeric,p_break_session_id uuid,p_idempotency_key text
) returns jsonb language plpgsql security definer set search_path=public as $$
begin
  if auth.uid() is null or not exists(select 1 from public.e10_organizations where id=p_org and status='active')
    or not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.reserve_inventory') then
    raise exception using errcode='42501',message='reserve_inventory_denied';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|lot|'||p_lot_id::text,0));
  if auth.uid() is null or not exists(select 1 from public.e10_organizations where id=p_org and status='active')
    or not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.reserve_inventory') then
    raise exception using errcode='42501',message='reserve_inventory_denied';
  end if;
  perform e10.assert_receipt_lot_projection(p_org,p_lot_id);
  return public._e10_org_lot_reserve_x4b(p_org,p_lot_id,p_quantity,p_break_session_id,p_idempotency_key);
end $$;
revoke all on function public.e10_org_lot_reserve(uuid,uuid,numeric,uuid,text) from public,anon;
grant execute on function public.e10_org_lot_reserve(uuid,uuid,numeric,uuid,text) to authenticated,service_role;

create or replace function e10.normalize_commercial_event_envelope() returns trigger
language plpgsql security definer set search_path=public as $$
begin
  if new.source_kind='native' then
    if new.inventory_movement_id is null and new.customer_activity_observation_id is null and not(
      current_setting('e10.receipt_evidence',true)='on' and new.event_type='receipt'
      and new.source_connection_id='receipt-ledger' and nullif(btrim(new.source_event_id),'') is not null
      and new.subject_type='inventory_item') and not(
      current_setting('e10.receipt_reversal_evidence',true)='on' and new.event_type='correction'
      and new.source_connection_id='receipt-ledger' and nullif(btrim(new.source_event_id),'') is not null
      and new.subject_type='inventory_item') and not(
      current_setting('e10.receipt_disposition_evidence',true)='on' and new.event_type='correction'
      and new.source_connection_id='receipt-ledger' and nullif(btrim(new.source_event_id),'') is not null
      and new.subject_type='inventory_item') then
      raise exception using errcode='42501',message='native_evidence_requires_inventory_movement';
    end if;
    new.evidence_quality:='native_system';
    new.source_connection_id:=coalesce(nullif(btrim(new.source_connection_id),''),
      case when new.inventory_movement_id is not null then 'inventory-ledger'
        when new.customer_activity_observation_id is not null then 'live-break-slot' else 'receipt-ledger' end);
    new.source_event_id:=coalesce(nullif(btrim(new.source_event_id),''),new.inventory_movement_id::text,
      new.customer_activity_observation_id::text);
    new.correlation_id:=coalesce(nullif(btrim(new.correlation_id),''),nullif(btrim(new.source_reference),''),
      new.inventory_movement_id::text,new.customer_activity_observation_id::text);
  elsif new.source_kind='system' then
    raise exception using errcode='42501',message='system_evidence_requires_trusted_writer';
  elsif new.source_kind='import' and new.evidence_quality='operator_asserted' then
    new.evidence_quality:='imported_unreviewed';
  end if;
  if new.source_kind<>'native' and not e10.valid_commercial_event_payload(new.event_type,new.payload) then
    raise exception using errcode='22023',message='event_payload_invalid_for_schema';
  end if;
  return new;
end $$;
revoke all on function e10.normalize_commercial_event_envelope() from public,anon,authenticated;
grant execute on function e10.normalize_commercial_event_envelope() to service_role;

create function public.e10_org_review_receipt_disposition(
  p_org uuid,p_receipt_line_id uuid,p_action text,p_quantity numeric,
  p_predecessor_decision_id uuid,p_expected_revision integer,p_reason text,p_idempotency_key text
) returns jsonb
language plpgsql security definer set search_path=public as $$
#variable_conflict use_variable
declare
  actor uuid:=auth.uid();fp text;existing record;line record;prior record;current_head record;
  decision_id uuid:=gen_random_uuid();root_id uuid;new_revision integer;old_accept numeric:=0;new_accept numeric:=0;
  delta numeric;available_quarantine numeric;lot_committed numeric;legacy_reserved numeric;movement_id uuid;event_id uuid;
  corrects_event uuid;result jsonb;
begin
  if actor is null or not exists(select 1 from public.e10_organizations where id=p_org and status='active')
    or not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.resolve_recovery') then
    raise exception using errcode='42501',message='receipt_disposition_denied';
  end if;
  if p_receipt_line_id is null or p_action not in('accept','damage') or p_quantity is null or p_quantity<=0
    or p_quantity::text in('NaN','Infinity','-Infinity') or p_expected_revision is null or p_expected_revision<0
    or (p_predecessor_decision_id is null)<>(p_expected_revision=0)
    or p_reason is null or btrim(p_reason)='' or length(p_reason)>2000
    or p_idempotency_key is null or btrim(p_idempotency_key)='' or length(p_idempotency_key)>160 then
    raise exception using errcode='22023',message='receipt_disposition_payload_invalid';
  end if;
  fp:=md5(jsonb_build_object('v','receipt-disposition-v1','org',p_org,'line',p_receipt_line_id,
    'action',p_action,'quantity',p_quantity,'predecessor',p_predecessor_decision_id,
    'expected_revision',p_expected_revision,'reason',p_reason)::text);
  perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|receipt-disposition-command|'||p_idempotency_key,0));
  select c.request_fingerprint,c.result into existing from public.e10_receipt_disposition_commands c
    where c.organization_id=p_org and c.idempotency_key=p_idempotency_key;
  if found then
    if existing.request_fingerprint<>fp then raise exception using errcode='22023',message='idempotency_key_mismatch';end if;
    if auth.uid() is distinct from actor or not exists(select 1 from public.e10_organizations where id=p_org and status='active')
      or not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.resolve_recovery') then
      raise exception using errcode='42501',message='receipt_disposition_denied';end if;
    return existing.result||jsonb_build_object('replay',true);
  end if;

  select rl.stock_receipt_id,rl.inventory_lot_id,rl.quarantined_quantity,l.inventory_item_id,
    l.accepted_quantity lot_accepted,l.quarantined_quantity lot_quarantined,r.status receipt_status,
    r.destination_location_id
  into line from public.e10_stock_receipt_lines rl
  join public.e10_stock_receipts r on(r.organization_id,r.id)=(rl.organization_id,rl.stock_receipt_id)
  join public.e10_inventory_lots l on(l.organization_id,l.id)=(rl.organization_id,rl.inventory_lot_id)
    and l.stock_receipt_line_id=rl.id and l.inventory_item_id is not null
  where rl.organization_id=p_org and rl.id=p_receipt_line_id;
  if not found then raise exception using errcode='42501',message='receipt_line_access_denied';end if;
  perform 1 from public.e10_stock_receipts r where r.organization_id=p_org and r.id=line.stock_receipt_id for update;
  perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|lot|'||line.inventory_lot_id::text,0));
  perform 1 from public.e10_lot_reservations lr where lr.organization_id=p_org and lr.lot_id=line.inventory_lot_id order by lr.id for update;
  perform 1 from public.e10_inventory_lots l where l.organization_id=p_org and l.id=line.inventory_lot_id for update;
  perform 1 from public.e10_inventory_items i where i.organization_id=p_org and i.id=line.inventory_item_id for update;
  perform 1 from public.e10_inventory_reservations ir where ir.organization_id=p_org and ir.item_id=line.inventory_item_id order by ir.id for update;

  if auth.uid() is distinct from actor or not exists(select 1 from public.e10_organizations where id=p_org and status='active')
    or not e10.is_org_member(p_org) or not e10.has_org_cap(p_org,'act.resolve_recovery')
    or not e10.can_receive_at(p_org,line.destination_location_id) then
    raise exception using errcode='42501',message='receipt_disposition_denied';end if;
  select rl.stock_receipt_id,rl.inventory_lot_id,rl.quarantined_quantity,l.inventory_item_id,
    l.accepted_quantity lot_accepted,l.quarantined_quantity lot_quarantined,r.status receipt_status,
    r.destination_location_id
  into line from public.e10_stock_receipt_lines rl
  join public.e10_stock_receipts r on(r.organization_id,r.id)=(rl.organization_id,rl.stock_receipt_id)
  join public.e10_inventory_lots l on(l.organization_id,l.id)=(rl.organization_id,rl.inventory_lot_id)
    and l.stock_receipt_line_id=rl.id and l.inventory_item_id is not null
  where rl.organization_id=p_org and rl.id=p_receipt_line_id;
  if not found or line.receipt_status not in('posted','corrected')
    or exists(select 1 from public.e10_stock_receipt_reversals rv
      where rv.organization_id=p_org and rv.stock_receipt_line_id=p_receipt_line_id) then
    raise exception using errcode='55000',message='receipt_disposition_closed';end if;
  perform e10.assert_receipt_lot_projection(p_org,line.inventory_lot_id);

  if p_predecessor_decision_id is null then
    root_id:=decision_id;new_revision:=1;available_quarantine:=line.lot_quarantined;
  else
    select d.* into prior from public.e10_receipt_disposition_decisions d
      where d.organization_id=p_org and d.id=p_predecessor_decision_id
        and d.stock_receipt_line_id=p_receipt_line_id for update;
    if not found then raise exception using errcode='42501',message='receipt_disposition_predecessor_denied';end if;
    select d.id,d.revision into current_head from public.e10_receipt_disposition_decisions d
      where d.organization_id=p_org and d.root_decision_id=prior.root_decision_id
        and not exists(select 1 from public.e10_receipt_disposition_decisions s
          where s.organization_id=d.organization_id and s.predecessor_decision_id=d.id)
      for update;
    if current_head.id is distinct from p_predecessor_decision_id or current_head.revision<>p_expected_revision then
      raise exception using errcode='40001',message='receipt_disposition_revision_conflict';end if;
    root_id:=prior.root_decision_id;new_revision:=prior.revision+1;
    old_accept:=case when prior.action='accept' then prior.quantity else 0 end;
    available_quarantine:=line.lot_quarantined+prior.quantity;
    select ce.id into corrects_event from public.e10_commercial_events ce
      where ce.organization_id=p_org and ce.source_connection_id='receipt-ledger'
        and ce.source_event_id=prior.id::text and ce.event_type='correction';
  end if;
  if p_quantity>available_quarantine then
    raise exception using errcode='23514',message='receipt_disposition_exceeds_quarantine';end if;
  new_accept:=case when p_action='accept' then p_quantity else 0 end;delta:=new_accept-old_accept;
  select coalesce(sum(case when lr.status='active' then lr.quantity else 0 end),0)+coalesce(sum(lr.consumed_quantity),0)
    into lot_committed from public.e10_lot_reservations lr where lr.organization_id=p_org and lr.lot_id=line.inventory_lot_id;
  if line.lot_accepted+delta<lot_committed then
    raise exception using errcode='55000',message='receipt_disposition_quantity_committed';end if;
  select coalesce(sum(ir.qty),0) into legacy_reserved from public.e10_inventory_reservations ir
    where ir.organization_id=p_org and ir.item_id=line.inventory_item_id and ir.status='active';
  if delta<0 and (select i.qty from public.e10_inventory_items i where i.organization_id=p_org and i.id=line.inventory_item_id)+delta<legacy_reserved then
    raise exception using errcode='55000',message='receipt_disposition_quantity_reserved';end if;

  update public.e10_inventory_items set qty=qty+delta,updated_by=actor,updated_at=now()
    where organization_id=p_org and id=line.inventory_item_id and qty+delta>=0;
  if not found then raise exception using errcode='55000',message='receipt_disposition_quantity_unavailable';end if;
  update public.e10_inventory_lots set accepted_quantity=accepted_quantity+delta,
    quarantined_quantity=available_quarantine-p_quantity,
    status=case when accepted_quantity+delta>0 then'available'
      when available_quarantine-p_quantity>0 then'quarantined'else'exhausted'end,updated_at=now()
    where organization_id=p_org and id=line.inventory_lot_id;
  if delta<>0 then
    perform set_config('e10.emit','on',true);
    insert into public.e10_inventory_movements(workspace_id,item_id,movement_type,on_hand_delta,reserved_delta,
      source_entity_type,source_entity_id,source_action,actor_uid,reason_code,note,idempotency_key,meta,organization_id)
    values('shared',line.inventory_item_id,'correction',delta,0,'receipt_disposition_decision',decision_id::text,
      case when p_predecessor_decision_id is null then p_action else'correct'end,actor,'correction',p_reason,
      p_org::text||':receipt-disposition:'||p_idempotency_key,
      jsonb_build_object('receipt_id',line.stock_receipt_id,'receipt_line_id',p_receipt_line_id,
        'lot_id',line.inventory_lot_id,'decision_id',decision_id,'predecessor_decision_id',p_predecessor_decision_id,
        'command',p_idempotency_key),p_org) returning id into movement_id;
  end if;
  insert into public.e10_receipt_disposition_decisions(id,organization_id,stock_receipt_id,stock_receipt_line_id,
    inventory_lot_id,root_decision_id,predecessor_decision_id,revision,action,quantity,reason,
    inventory_movement_id,decided_by)
  values(decision_id,p_org,line.stock_receipt_id,p_receipt_line_id,line.inventory_lot_id,root_id,
    p_predecessor_decision_id,new_revision,p_action,p_quantity,p_reason,movement_id,actor);
  update public.e10_stock_receipts set disposition_revision=disposition_revision+1,updated_at=now()
    where organization_id=p_org and id=line.stock_receipt_id;

  if corrects_event is null then
    select ce.id into corrects_event from public.e10_commercial_events ce
      where ce.organization_id=p_org and ce.event_type='receipt'
        and ce.payload->>'receipt_line_id'=p_receipt_line_id::text order by ce.created_at,ce.id limit 1;
  end if;
  if corrects_event is null then raise exception using errcode='55000',message='receipt_evidence_missing';end if;
  event_id:=gen_random_uuid();perform set_config('e10.receipt_disposition_evidence','on',true);
  insert into public.e10_commercial_events(id,organization_id,event_type,event_schema_version,subject_type,subject_id,
    occurred_at,occurred_at_precision,idempotency_key,source_kind,source_connection_id,source_reference,source_event_id,
    correlation_id,evidence_quality,payload,corrects_event_id,created_by,request_fingerprint,inventory_movement_id)
  values(event_id,p_org,'correction',1,'inventory_item',line.inventory_item_id,now(),'exact',
    p_org::text||':receipt-disposition-event:'||p_idempotency_key,'native','receipt-ledger',
    'receipt_disposition_decision:'||decision_id,decision_id::text,line.stock_receipt_id::text,'native_system',
    jsonb_build_object('movement_id',movement_id,'movement_type','correction','on_hand_delta',delta,'reserved_delta',0,
      'source_action',case when p_predecessor_decision_id is null then p_action else'correct'end,
      'reason_code','correction','receipt_id',line.stock_receipt_id,'receipt_line_id',p_receipt_line_id,
      'lot_id',line.inventory_lot_id,'decision_id',decision_id,'root_decision_id',root_id,
      'predecessor_decision_id',p_predecessor_decision_id,'revision',new_revision,'action',p_action,
      'quantity',p_quantity,'command',p_idempotency_key),corrects_event,actor,
    md5(decision_id::text||'|receipt-disposition|'||line.inventory_item_id),movement_id);
  result:=jsonb_build_object('ok',true,'replay',false,'receipt_id',line.stock_receipt_id,
    'receipt_line_id',p_receipt_line_id,'lot_id',line.inventory_lot_id,'decision_id',decision_id,
    'root_decision_id',root_id,'predecessor_decision_id',p_predecessor_decision_id,'revision',new_revision,
    'action',p_action,'quantity',p_quantity,'inventory_movement_id',movement_id,'commercial_event_id',event_id,
    'effective_accepted',line.lot_accepted+delta,'unresolved_quarantined',available_quarantine-p_quantity);
  insert into public.e10_receipt_disposition_commands(organization_id,idempotency_key,request_fingerprint,
    stock_receipt_line_id,result,created_by) values(p_org,p_idempotency_key,fp,p_receipt_line_id,result,actor);
  return result;
end $$;

revoke all on function public.e10_org_review_receipt_disposition(uuid,uuid,text,numeric,uuid,integer,text,text)
  from public,anon;
grant execute on function public.e10_org_review_receipt_disposition(uuid,uuid,text,numeric,uuid,integer,text,text)
  to authenticated,service_role;
comment on function public.e10_org_review_receipt_disposition(uuid,uuid,text,numeric,uuid,integer,text,text) is
  'Reviewed immutable quarantine accept/damage decision with revisioned correction. No vendor credit, RTV, write-off, salvage, landed-cost, payment, or accounting consequence.';

-- X4f already takes the receipt row before physical effects. Snapshot the X4g
-- generation before entering that lock hierarchy and reject if a disposition
-- committed while reversal waited. The raised serialization error rolls back
-- every internal reversal effect and command row.
alter function public.e10_org_reverse_receipt_batch(uuid,uuid,text,text)
  rename to _e10_org_reverse_receipt_batch_x4f;
revoke all on function public._e10_org_reverse_receipt_batch_x4f(uuid,uuid,text,text)
  from public,anon,authenticated;
grant execute on function public._e10_org_reverse_receipt_batch_x4f(uuid,uuid,text,text) to service_role;

create function public.e10_org_reverse_receipt_batch(
  p_org uuid,p_receipt_id uuid,p_reason text,p_idempotency_key text
) returns jsonb
language plpgsql security definer set search_path=public as $$
declare before_revision bigint;after_revision bigint;result jsonb;rv record;original_event uuid;
begin
  select r.disposition_revision into before_revision from public.e10_stock_receipts r
    where r.organization_id=p_org and r.id=p_receipt_id;
  result:=public._e10_org_reverse_receipt_batch_x4f(p_org,p_receipt_id,p_reason,p_idempotency_key);
  -- X4f's movement trigger cannot find an original receipt movement when a
  -- line was received wholly into quarantine. If a later disposition created
  -- accepted stock, complete the missing reversal event here and correct the
  -- terminal disposition event that authorized that stock.
  for rv in
    select r.id reversal_id,r.stock_receipt_line_id line_id,r.inventory_lot_id lot_id,
      r.inventory_movement_id movement_id,l.inventory_item_id,m.on_hand_delta,m.actor_uid
    from public.e10_stock_receipt_reversals r
    join public.e10_inventory_lots l on(l.organization_id,l.id)=(r.organization_id,r.inventory_lot_id)
    left join public.e10_inventory_movements m on(m.organization_id,m.id)=(r.organization_id,r.inventory_movement_id)
    where r.organization_id=p_org and r.stock_receipt_id=p_receipt_id
      and not exists(select 1 from public.e10_commercial_events ce
        where ce.organization_id=r.organization_id and ce.payload->>'reversal_id'=r.id::text)
  loop
    select ce.id into original_event
    from public.e10_receipt_disposition_decisions d
    join public.e10_commercial_events ce on ce.organization_id=d.organization_id
      and ce.source_connection_id='receipt-ledger' and ce.source_event_id=d.id::text
    where d.organization_id=p_org and d.stock_receipt_line_id=rv.line_id
      and d.action='accept'
      and not exists(select 1 from public.e10_receipt_disposition_decisions s
        where s.organization_id=d.organization_id and s.predecessor_decision_id=d.id)
    order by d.decided_at desc,d.id desc limit 1;
    if original_event is null then
      select ce.id into original_event from public.e10_commercial_events ce
      where ce.organization_id=p_org and ce.event_type='receipt'
        and ce.payload->>'receipt_line_id'=rv.line_id::text order by ce.created_at,ce.id limit 1;
    end if;
    if original_event is null then raise exception using errcode='55000',message='receipt_evidence_missing';end if;
    perform set_config('e10.receipt_reversal_evidence','on',true);
    insert into public.e10_commercial_events(organization_id,event_type,event_schema_version,subject_type,subject_id,
      occurred_at,occurred_at_precision,idempotency_key,source_kind,source_connection_id,source_reference,source_event_id,
      correlation_id,evidence_quality,payload,corrects_event_id,created_by,request_fingerprint,inventory_movement_id)
    values(p_org,'correction',1,'inventory_item',rv.inventory_item_id,now(),'exact',
      p_org::text||':receipt-reversal-event:'||p_idempotency_key||':'||rv.line_id,'native','receipt-ledger',
      'stock_receipt_line:'||rv.line_id,rv.reversal_id::text,p_receipt_id::text,'native_system',
      jsonb_build_object('movement_id',rv.movement_id,'movement_type','correction','on_hand_delta',coalesce(rv.on_hand_delta,0),
        'reserved_delta',0,'source_action','reverse','reason_code','correction','receipt_id',p_receipt_id,
        'receipt_line_id',rv.line_id,'lot_id',rv.lot_id,'reversal_id',rv.reversal_id,'command',p_idempotency_key),
      original_event,coalesce(rv.actor_uid,auth.uid()),md5(rv.reversal_id::text||'|correction|'||rv.inventory_item_id),rv.movement_id)
    on conflict(organization_id,inventory_movement_id) where inventory_movement_id is not null do nothing;
  end loop;
  if not coalesce((result->>'replay')::boolean,false) then
    select r.disposition_revision into after_revision from public.e10_stock_receipts r
      where r.organization_id=p_org and r.id=p_receipt_id;
    if after_revision is distinct from before_revision then
      raise exception using errcode='40001',message='receipt_disposition_changed';
    end if;
  end if;
  return result;
end $$;
revoke all on function public.e10_org_reverse_receipt_batch(uuid,uuid,text,text) from public,anon;
grant execute on function public.e10_org_reverse_receipt_batch(uuid,uuid,text,text) to authenticated,service_role;
