-- R2 final reconciliation corrective.
-- A reviewed new_transaction decision is the explicit operator proof that a
-- slot-bearing import represents a distinct resale rather than duplicate
-- evidence for an existing native sale.

create function e10.customer_source_is_reviewed_new_transaction(
  p_org uuid,
  p_source_kind text,
  p_source_connection_id text,
  p_source_line_id text
) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((
    select d.action = 'new_transaction'
    from public.e10_customer_transaction_source_claims sc
    join public.e10_customer_transaction_reconciliation_decisions d
      on (d.organization_id, d.case_id) =
         (sc.organization_id, sc.reconciliation_case_id)
    where sc.organization_id = p_org
      and sc.source_kind = p_source_kind
      and coalesce(sc.source_connection_id, '') =
          coalesce(nullif(btrim(p_source_connection_id), ''), '')
      and sc.source_line_id = p_source_line_id
    order by d.revision desc
    limit 1
  ), false)
$$;

revoke all on function e10.customer_source_is_reviewed_new_transaction(uuid,text,text,text)
  from public, anon, authenticated;
grant execute on function e10.customer_source_is_reviewed_new_transaction(uuid,text,text,text)
  to service_role;

create or replace function e10.enforce_customer_draft_line_r2() returns trigger
language plpgsql security definer set search_path=public as $$
declare a record;header_currency text;derived_session uuid;derived_slot uuid;
begin
 if new.quantity is null or new.quantity<=0 or new.quantity::text in('NaN','Infinity','-Infinity')
   or new.merchandise_gross is null or new.merchandise_gross<0 or new.merchandise_gross::text in('NaN','Infinity','-Infinity')
   or(new.merchandise_discount is not null and(new.merchandise_discount<0 or new.merchandise_discount>new.merchandise_gross or new.merchandise_discount::text in('NaN','Infinity','-Infinity')))
   or(new.shipping_amount is not null and(new.shipping_amount<0 or new.shipping_amount::text in('NaN','Infinity','-Infinity')))
   or(new.tax_amount is not null and(new.tax_amount<0 or new.tax_amount::text in('NaN','Infinity','-Infinity')))
 then raise exception using errcode='22023',message='draft_line_amount_invalid';end if;
 if new.activity_observation_id is not null then
  select o.* into a from public.e10_customer_activity_observations o where(o.organization_id,o.id)=(new.organization_id,new.activity_observation_id);
  select currency into header_currency from public.e10_customer_transaction_draft_revisions where(organization_id,draft_id,revision)=(new.organization_id,new.draft_id,new.revision);
  if a.id is null then raise exception using errcode='42501',message='draft_activity_denied';end if;
  if a.currency<>header_currency then raise exception using errcode='22023',message='draft_activity_currency_mismatch';end if;
  if new.break_session_id is not null and new.break_session_id is distinct from a.break_session_id or new.break_slot_id is not null and new.break_slot_id is distinct from a.break_slot_id then raise exception using errcode='22023',message='draft_activity_scope_mismatch';end if;
  derived_session:=a.break_session_id;derived_slot:=a.break_slot_id;
  if exists(select 1 from public.e10_customer_transaction_draft_lines l where(l.organization_id,l.draft_id,l.revision,l.activity_observation_id)=(new.organization_id,new.draft_id,new.revision,new.activity_observation_id))then raise exception using errcode='22023',message='draft_activity_duplicate';end if;
  if a.source_kind='native'
    and exists(select 1 from public.e10_native_break_sales s where(s.organization_id,s.activity_observation_id)=(a.organization_id,a.id))
    and not exists(select 1 from public.e10_current_native_break_sales s where(s.organization_id,s.activity_observation_id)=(a.organization_id,a.id))
  then raise exception using errcode='42501',message='released_native_sale_not_postable';end if;
 else derived_session:=new.break_session_id;derived_slot:=new.break_slot_id;end if;
 if new.capture_source='import' and derived_slot is not null
   and exists(select 1 from public.e10_native_break_sales s where(s.organization_id,s.session_id,s.slot_id)=(new.organization_id,derived_session,derived_slot))
   and not e10.customer_source_is_reviewed_new_transaction(new.organization_id,new.capture_source,new.source_connection_id,new.source_line_id)
 then raise exception using errcode='22023',message='slot_import_requires_reconciliation';end if;
 if new.capture_source='native' and derived_slot is not null
   and exists(select 1 from public.e10_customer_transaction_lines l where(l.organization_id,l.break_session_id,l.break_slot_id)=(new.organization_id,derived_session,derived_slot) and l.capture_source='import')
   and not e10.customer_source_is_reviewed_new_transaction(new.organization_id,new.capture_source,new.source_connection_id,new.source_line_id)
 then raise exception using errcode='22023',message='native_sale_requires_reconciliation';end if;
 new.break_session_id:=derived_session;new.break_slot_id:=derived_slot;return new;
end $$;

create or replace function public.e10_org_post_customer_transaction_draft(p_org uuid,p_draft uuid,p_expected_revision integer,p_idempotency_key text)returns jsonb language plpgsql security definer set search_path=public as $$declare a uuid;k text;old_result jsonb;begin
 perform e10.assert_customer_writer(p_org,'act.post_customer_transactions','post_customer_transaction_denied');
 perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|customer-commercial|'||p_idempotency_key,0));
 select result into old_result from public.e10_customer_commercial_receipts where organization_id=p_org and idempotency_key=p_idempotency_key;
 if found then perform e10.assert_customer_writer(p_org,'act.post_customer_transactions','post_customer_transaction_denied');return public._e10_org_post_customer_transaction_draft_r2(p_org,p_draft,p_expected_revision,p_idempotency_key);end if;
 perform 1 from public.e10_customer_transaction_drafts where organization_id=p_org and id=p_draft for update;
 for a in select distinct activity_observation_id from public.e10_customer_transaction_draft_lines where organization_id=p_org and draft_id=p_draft and revision=p_expected_revision and activity_observation_id is not null order by 1 loop perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|activity-attribution|'||a::text,0));end loop;
 for k in select lock_key from(select distinct 'activity|'||activity_observation_id::text lock_key from public.e10_customer_transaction_draft_lines where organization_id=p_org and draft_id=p_draft and revision=p_expected_revision and activity_observation_id is not null union select distinct 'source|'||capture_source||'|'||coalesce(source_connection_id,'')||'|'||source_line_id from public.e10_customer_transaction_draft_lines where organization_id=p_org and draft_id=p_draft and revision=p_expected_revision)s order by 1 loop perform pg_advisory_xact_lock(hashtextextended(p_org::text||'|posted|'||k,0));end loop;
 perform 1 from public.e10_customer_transaction_source_claims c where(c.organization_id,c.source_kind,coalesce(c.source_connection_id,''),c.source_line_id) in(select l.organization_id,l.capture_source,coalesce(l.source_connection_id,''),l.source_line_id from public.e10_customer_transaction_draft_lines l where l.organization_id=p_org and l.draft_id=p_draft and l.revision=p_expected_revision) order by c.source_kind,coalesce(c.source_connection_id,''),c.source_line_id for update;
 perform 1 from public.e10_break_slots sl where(sl.organization_id,sl.id) in(select l.organization_id,coalesce(o.break_slot_id,l.break_slot_id) from public.e10_customer_transaction_draft_lines l left join public.e10_customer_activity_observations o on(o.organization_id,o.id)=(l.organization_id,l.activity_observation_id) where l.organization_id=p_org and l.draft_id=p_draft and l.revision=p_expected_revision and coalesce(o.break_slot_id,l.break_slot_id) is not null) order by sl.id for update;
 if exists(select 1 from public.e10_customer_transaction_draft_lines l where l.organization_id=p_org and l.draft_id=p_draft and l.revision=p_expected_revision and(l.quantity is null or l.quantity<=0 or l.quantity::text in('NaN','Infinity','-Infinity')or l.merchandise_gross is null or l.merchandise_gross<0 or l.merchandise_gross::text in('NaN','Infinity','-Infinity')or l.merchandise_discount::text in('NaN','Infinity','-Infinity')or l.shipping_amount::text in('NaN','Infinity','-Infinity')or l.tax_amount::text in('NaN','Infinity','-Infinity')))then raise exception using errcode='22023',message='draft_line_amount_invalid';end if;
 if exists(select 1 from public.e10_customer_transaction_draft_lines l join public.e10_customer_transaction_draft_revisions r on(r.organization_id,r.draft_id,r.revision)=(l.organization_id,l.draft_id,l.revision) join public.e10_customer_activity_observations o on(o.organization_id,o.id)=(l.organization_id,l.activity_observation_id) where l.organization_id=p_org and l.draft_id=p_draft and l.revision=p_expected_revision and o.currency<>r.currency)then raise exception using errcode='22023',message='draft_activity_currency_mismatch';end if;
 if exists(select 1 from public.e10_customer_transaction_draft_lines l where l.organization_id=p_org and l.draft_id=p_draft and l.revision=p_expected_revision and l.activity_observation_id is not null group by l.activity_observation_id having count(*)>1)then raise exception using errcode='22023',message='draft_activity_duplicate';end if;
 if exists(select 1 from public.e10_customer_transaction_draft_lines l join public.e10_customer_activity_observations o on(o.organization_id,o.id)=(l.organization_id,l.activity_observation_id) where l.organization_id=p_org and l.draft_id=p_draft and l.revision=p_expected_revision and o.source_kind='native' and exists(select 1 from public.e10_native_break_sales s where(s.organization_id,s.activity_observation_id)=(o.organization_id,o.id)) and not exists(select 1 from public.e10_current_native_break_sales s where(s.organization_id,s.activity_observation_id)=(o.organization_id,o.id)))then raise exception using errcode='42501',message='released_native_sale_not_postable';end if;
 if exists(select 1 from public.e10_customer_transaction_draft_lines l left join public.e10_customer_activity_observations o on(o.organization_id,o.id)=(l.organization_id,l.activity_observation_id) where l.organization_id=p_org and l.draft_id=p_draft and l.revision=p_expected_revision and l.capture_source='import' and coalesce(o.break_slot_id,l.break_slot_id) is not null and exists(select 1 from public.e10_native_break_sales s where(s.organization_id,s.session_id,s.slot_id)=(l.organization_id,coalesce(o.break_session_id,l.break_session_id),coalesce(o.break_slot_id,l.break_slot_id))) and not e10.customer_source_is_reviewed_new_transaction(l.organization_id,l.capture_source,l.source_connection_id,l.source_line_id))then raise exception using errcode='22023',message='slot_import_requires_reconciliation';end if;
 if exists(select 1 from public.e10_customer_transaction_draft_lines l left join public.e10_customer_activity_observations o on(o.organization_id,o.id)=(l.organization_id,l.activity_observation_id) where l.organization_id=p_org and l.draft_id=p_draft and l.revision=p_expected_revision and l.capture_source='native' and exists(select 1 from public.e10_customer_transaction_lines posted where(posted.organization_id,posted.break_session_id,posted.break_slot_id)=(l.organization_id,coalesce(o.break_session_id,l.break_session_id),coalesce(o.break_slot_id,l.break_slot_id))and posted.capture_source='import') and not e10.customer_source_is_reviewed_new_transaction(l.organization_id,l.capture_source,l.source_connection_id,l.source_line_id))then raise exception using errcode='22023',message='native_sale_requires_reconciliation';end if;
 perform e10.assert_customer_writer(p_org,'act.post_customer_transactions','post_customer_transaction_denied');return public._e10_org_post_customer_transaction_draft_r2(p_org,p_draft,p_expected_revision,p_idempotency_key);end$$;
