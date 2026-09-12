-- TA-R4 correction: preserve document-specific authority through the final
-- delegated writer lock and replay boundary.

create or replace function e10.can_access_commercial_comments(p_org uuid,p_kind text) returns boolean
language sql stable security definer set search_path=public as $$
  select case p_kind
    when 'purchase_order' then e10.has_org_cap(p_org,'act.purchasing_prepare')
    when 'stock_receipt' then e10.has_org_cap(p_org,'act.create_receiving')
      and e10.has_org_cap(p_org,'act.purchasing_prepare')
    when 'supplier_invoice' then e10.has_org_cap(p_org,'act.purchasing_prepare')
      and e10.has_org_cap(p_org,'financial.actual_cost.read')
    when 'supplier_credit' then e10.has_org_cap(p_org,'act.purchasing_prepare')
      and e10.has_org_cap(p_org,'financial.actual_cost.read')
    else false end;
$$;

create or replace function public.e10_org_add_commercial_comment(
  p_org uuid,p_document_kind text,p_document_id uuid,p_audience text,p_body text,
  p_supersedes_comment_id uuid,p_idempotency_key text
) returns jsonb language plpgsql security definer set search_path=public as $$
declare result jsonb;
begin
  if p_document_kind in ('purchase_order','supplier_invoice','stock_receipt','supplier_credit')
    and not e10.can_access_commercial_comments(p_org,p_document_kind) then
    raise exception using errcode='42501',message='commercial_comment_write_denied';
  end if;

  result:=public._e10_org_add_commercial_comment_r4(
    p_org,p_document_kind,p_document_id,p_audience,p_body,
    p_supersedes_comment_id,p_idempotency_key);

  -- The delegate owns all command, document, and supersession locks. Recheck
  -- after it returns so a concurrent suspension or capability revocation rolls
  -- the entire delegated write back, including replay paths.
  if p_document_kind in ('purchase_order','supplier_invoice','stock_receipt','supplier_credit')
    and not e10.can_access_commercial_comments(p_org,p_document_kind) then
    raise exception using errcode='42501',message='commercial_comment_write_denied';
  end if;
  return result;
end $$;

revoke all on function public.e10_org_add_commercial_comment(uuid,text,uuid,text,text,uuid,text) from public,anon;
grant execute on function public.e10_org_add_commercial_comment(uuid,text,uuid,text,text,uuid,text) to authenticated,service_role;
