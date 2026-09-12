-- TA-R6 14a/14c: draft currency, finite amounts and duplicate activity guard.
create function e10.guard_customer_draft_line_contract() returns trigger
language plpgsql security definer set search_path=public as $$
declare draft_currency text;activity_currency text;
begin
  if new.quantity is null or new.merchandise_gross is null
    or new.quantity::text in('NaN','Infinity','-Infinity') or new.quantity<=0
    or new.merchandise_gross::text in('NaN','Infinity','-Infinity') or new.merchandise_gross<0
    or new.merchandise_discount is not null and(new.merchandise_discount::text in('NaN','Infinity','-Infinity')or new.merchandise_discount<0 or new.merchandise_discount>new.merchandise_gross)
    or new.shipping_amount is not null and(new.shipping_amount::text in('NaN','Infinity','-Infinity')or new.shipping_amount<0)
    or new.tax_amount is not null and(new.tax_amount::text in('NaN','Infinity','-Infinity')or new.tax_amount<0) then
    raise exception using errcode='22023',message='draft_line_amount_invalid';
  end if;
  if new.activity_observation_id is not null then
    select r.currency,o.currency into draft_currency,activity_currency
    from public.e10_customer_transaction_draft_revisions r
    join public.e10_customer_activity_observations o on o.organization_id=new.organization_id and o.id=new.activity_observation_id
    where r.organization_id=new.organization_id and r.draft_id=new.draft_id and r.revision=new.revision;
    if not found then raise exception using errcode='42501',message='draft_activity_denied';end if;
    if activity_currency is distinct from draft_currency then raise exception using errcode='22023',message='draft_activity_currency_mismatch';end if;
    if exists(select 1 from public.e10_customer_transaction_draft_lines l
      where l.organization_id=new.organization_id and l.draft_id=new.draft_id and l.revision=new.revision
        and l.activity_observation_id=new.activity_observation_id) then
      raise exception using errcode='22023',message='draft_activity_duplicate';
    end if;
  end if;
  return new;
end $$;
create trigger e10_customer_draft_line_contract_trg before insert or update
on public.e10_customer_transaction_draft_lines for each row execute function e10.guard_customer_draft_line_contract();
revoke all on function e10.guard_customer_draft_line_contract() from public,anon,authenticated;
grant execute on function e10.guard_customer_draft_line_contract() to service_role;
