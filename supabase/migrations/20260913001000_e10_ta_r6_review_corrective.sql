-- Independent-review corrective for R6 tenant identity, X4 authorization and
-- legacy idempotency compatibility.

create or replace function e10.sanitize_scoped_line_ids(p_org uuid,p_lines jsonb,p_relation regclass)
returns jsonb language plpgsql security definer set search_path=public as $$
declare element jsonb;candidate uuid;scoped_id uuid;in_scope boolean;result jsonb:='[]'::jsonb;
begin
 if p_lines is null or jsonb_typeof(p_lines)<>'array'then return p_lines;end if;
 for element in select value from jsonb_array_elements(p_lines)loop
  if jsonb_typeof(element)='object'and element?'id'then
   begin candidate:=(element->>'id')::uuid;exception when invalid_text_representation then candidate:=null;end;
   if candidate is not null then
    execute format('select exists(select 1 from %s where id=$1 and organization_id=$2)',p_relation)into in_scope using candidate,p_org;
    if not in_scope then
     scoped_id:=md5(p_org::text||'|'||p_relation::text||'|'||candidate::text)::uuid;
     element:=jsonb_set(element,'{id}',to_jsonb(scoped_id::text));
    end if;
   end if;
  end if;
  result:=result||jsonb_build_array(element);
 end loop;
 return result;
end $$;

do $$
declare lifecycle text;item_evidence text;valuation text;
begin
 select regexp_replace(pg_get_functiondef('public.e10_org_inventory_lifecycle(uuid,timestamptz,uuid,integer,text)'::regprocedure),'\s','','g')into lifecycle;
 select regexp_replace(pg_get_functiondef('public.e10_org_unique_item_evidence(uuid,uuid,timestamptz,integer,text)'::regprocedure),'\s','','g')into item_evidence;
 select regexp_replace(pg_get_functiondef('public.e10_org_inventory_valuation_coverage(uuid,text,text,text,timestamptz,timestamptz,integer,integer,text)'::regprocedure),'\s','','g')into valuation;
 if position('''limit'',p_limit' in lifecycle)=0 or position('max(full_count)fromkeyed' in lifecycle)=0
   or position('''limit'',p_limit' in item_evidence)=0 or position('max(full_count)fromranked' in item_evidence)=0
   or position('''limit'',p_limit' in valuation)=0 then raise exception'R6 X7e final function contract missing';end if;
end $$;

create or replace function public.e10_org_lot_reserve(p_org uuid,p_lot_id uuid,p_quantity numeric,p_break_session_id uuid,p_idempotency_key text)returns jsonb
language plpgsql security definer set search_path=public as $$
begin
 if exists(select 1 from public.e10_lot_reservations where organization_id=p_org and idempotency_key=p_idempotency_key)then
  begin return public._e10_org_lot_reserve_r6(p_org,p_lot_id,p_quantity,p_break_session_id,p_idempotency_key);
  exception when sqlstate'22023'then return public._e10_org_lot_reserve_r6(p_org,p_lot_id,trim_scale(p_quantity),p_break_session_id,p_idempotency_key);end;
 end if;
 return public._e10_org_lot_reserve_r6(p_org,p_lot_id,trim_scale(p_quantity),p_break_session_id,p_idempotency_key);
exception when unique_violation then raise exception using errcode='55000',message='lot_reservation_already_active';end $$;

create or replace function public.e10_org_lot_reserve_for_demand(p_org uuid,p_lot_id uuid,p_quantity numeric,p_demand_type text,p_demand_reference text,p_demand_label text,p_idempotency_key text)returns jsonb
language plpgsql security definer set search_path=public as $$
begin
 if exists(select 1 from public.e10_lot_reservations where organization_id=p_org and idempotency_key=p_idempotency_key)then
  begin return public._e10_org_lot_reserve_for_demand_r6(p_org,p_lot_id,p_quantity,p_demand_type,p_demand_reference,p_demand_label,p_idempotency_key);
  exception when sqlstate'22023'then return public._e10_org_lot_reserve_for_demand_r6(p_org,p_lot_id,trim_scale(p_quantity),p_demand_type,p_demand_reference,p_demand_label,p_idempotency_key);end;
 end if;
 return public._e10_org_lot_reserve_for_demand_r6(p_org,p_lot_id,trim_scale(p_quantity),p_demand_type,p_demand_reference,p_demand_label,p_idempotency_key);
exception when unique_violation then raise exception using errcode='55000',message='lot_reservation_already_active';end $$;

create or replace function public.e10_org_receive_batch(p_org uuid,p_supplier_id uuid,p_destination_location_id uuid,p_received_at timestamptz,p_lines jsonb,p_idempotency_key text)returns jsonb
language plpgsql security definer set search_path=public as $$begin
 if auth.uid()is null or not e10.has_org_cap(p_org,'act.create_receiving')then raise exception using errcode='42501',message='create_receiving_denied';end if;
 if p_lines is not null and jsonb_typeof(p_lines)='array'and exists(select 1 from jsonb_array_elements(p_lines)x where nullif(btrim(x->>'lot_code'),'')is not null group by lower(btrim(x->>'lot_code'))having count(*)>1)then raise exception using errcode='22023',message='duplicate_batch_lot_code';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|receipt-any-command|'||btrim(p_idempotency_key),0));
 if not e10.has_org_cap(p_org,'act.create_receiving')then raise exception using errcode='42501',message='create_receiving_denied';end if;
 if exists(select 1 from public.e10_stock_receipts r where r.organization_id=p_org and r.idempotency_key=btrim(p_idempotency_key))and not exists(select 1 from public.e10_receipt_commands c where c.organization_id=p_org and c.idempotency_key=btrim(p_idempotency_key))then raise exception using errcode='22023',message='idempotency_key_mismatch';end if;
 return public._e10_org_receive_batch_r6(p_org,p_supplier_id,p_destination_location_id,p_received_at,p_lines,p_idempotency_key);end $$;

create or replace function public.e10_org_receive_po_line(p_org uuid,p_purchase_order_line_id uuid,p_inventory_item_id text,p_accepted_quantity numeric,p_damaged_quantity numeric,p_quarantined_quantity numeric,p_lot_code text,p_received_at timestamptz,p_expected_allocations jsonb,p_idempotency_key text)returns jsonb
language plpgsql security definer set search_path=public as $$begin
 if auth.uid()is null or not e10.has_org_cap(p_org,'act.create_receiving')then raise exception using errcode='42501',message='create_receiving_denied';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|receipt-any-command|'||btrim(p_idempotency_key),0));
 if not e10.has_org_cap(p_org,'act.create_receiving')then raise exception using errcode='42501',message='create_receiving_denied';end if;
 if exists(select 1 from public.e10_receipt_commands c where c.organization_id=p_org and c.idempotency_key=btrim(p_idempotency_key))then raise exception using errcode='22023',message='idempotency_key_mismatch';end if;
 return public._e10_org_receive_po_line_r6(p_org,p_purchase_order_line_id,p_inventory_item_id,trim_scale(p_accepted_quantity),trim_scale(p_damaged_quantity),trim_scale(p_quarantined_quantity),p_lot_code,p_received_at,p_expected_allocations,p_idempotency_key);end $$;

create or replace function public.e10_org_record_commercial_event(p_org uuid,p_event_type text,p_subject_type text,p_subject_id text,p_occurred_at timestamptz,p_source_kind text,p_source_reference text,p_payload jsonb,p_corrects_event_id uuid,p_outbox_destinations text[],p_idempotency_key text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare prior_timezone text:=current_setting('TimeZone');result jsonb;prior record;prior_destinations text[];requested_destinations text[];
begin
 if auth.uid()is null or not e10.has_org_cap(p_org,'act.record_commercial_events')then raise exception using errcode='42501',message='record_commercial_event_denied';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|commercial-event|'||p_idempotency_key,0));
 if not e10.has_org_cap(p_org,'act.record_commercial_events')then raise exception using errcode='42501',message='record_commercial_event_denied';end if;
 select * into prior from public.e10_commercial_events where organization_id=p_org and idempotency_key=p_idempotency_key;
 if found then
  select coalesce(array_agg(destination_key order by destination_key),'{}')into prior_destinations from public.e10_integration_outbox where organization_id=p_org and commercial_event_id=prior.id;
  select coalesce(array_agg(x order by x),'{}')into requested_destinations from unnest(coalesce(p_outbox_destinations,'{}'))x;
  if row(prior.event_type,prior.subject_type,prior.subject_id,prior.occurred_at,prior.source_kind,prior.source_reference,prior.payload,prior.corrects_event_id,prior_destinations)
    is distinct from row(p_event_type,p_subject_type,p_subject_id,p_occurred_at,p_source_kind,p_source_reference,p_payload,p_corrects_event_id,requested_destinations)then raise exception using errcode='22023',message='idempotency_key_mismatch';end if;
  return jsonb_build_object('ok',true,'replay',true,'event_id',prior.id,'event_type',prior.event_type);
 end if;
 perform set_config('TimeZone','UTC',true);
 begin result:=public._e10_org_record_commercial_event_r6(p_org,p_event_type,p_subject_type,p_subject_id,p_occurred_at,p_source_kind,p_source_reference,p_payload,p_corrects_event_id,p_outbox_destinations,p_idempotency_key);
 exception when others then perform set_config('TimeZone',prior_timezone,true);raise;end;
 perform set_config('TimeZone',prior_timezone,true);return result;
end $$;
