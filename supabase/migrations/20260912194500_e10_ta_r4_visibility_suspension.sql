-- TA-R4: audience/document visibility, shared-catalog membership semantics,
-- suspended-organization capability denial, and financial metadata filtering.

create or replace function e10.has_org_cap(org uuid,cap text) returns boolean
language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.e10_organizations o where o.id=org and o.status='active')
    and (e10.is_platform_admin() or exists(
      select 1 from public.e10_organization_memberships m
      join public.e10_organization_role_permissions p
        on p.organization_id=m.organization_id and p.role_id=m.role_id
      where m.organization_id=org and m.user_id=auth.uid() and m.status='active'
        and p.capability=cap and p.allowed=true));
$$;

create function e10.has_any_active_org_membership() returns boolean
language sql stable security definer set search_path=public as $$
  select e10.is_platform_admin() or exists(
    select 1 from public.e10_organization_memberships m
    join public.e10_organizations o on o.id=m.organization_id and o.status='active'
    where m.user_id=auth.uid() and m.status='active');
$$;
revoke all on function e10.has_any_active_org_membership() from public,anon;
grant execute on function e10.has_any_active_org_membership() to authenticated,service_role;

drop policy e10_catalog_releases_sel on public.e10_catalog_releases;
drop policy e10_catalog_variants_sel on public.e10_catalog_variants;
drop policy e10_catalog_variant_subjects_sel on public.e10_catalog_variant_subjects;
drop policy e10_catalog_identity_mappings_sel on public.e10_catalog_identity_mappings;
create policy e10_catalog_releases_sel on public.e10_catalog_releases for select to authenticated using(e10.has_any_active_org_membership());
create policy e10_catalog_variants_sel on public.e10_catalog_variants for select to authenticated using(e10.has_any_active_org_membership());
create policy e10_catalog_variant_subjects_sel on public.e10_catalog_variant_subjects for select to authenticated using(e10.has_any_active_org_membership());
create policy e10_catalog_identity_mappings_sel on public.e10_catalog_identity_mappings for select to authenticated using(e10.has_any_active_org_membership());

create function e10.can_access_commercial_comments(p_org uuid,p_kind text) returns boolean
language sql stable security definer set search_path=public as $$
  select case p_kind
    when 'purchase_order' then e10.has_org_cap(p_org,'act.purchasing_prepare')
    when 'stock_receipt' then e10.has_org_cap(p_org,'act.create_receiving')
    when 'supplier_invoice' then e10.has_org_cap(p_org,'act.purchasing_prepare') and e10.has_org_cap(p_org,'financial.actual_cost.read')
    when 'supplier_credit' then e10.has_org_cap(p_org,'act.purchasing_prepare') and e10.has_org_cap(p_org,'financial.actual_cost.read')
    else false end;
$$;
revoke all on function e10.can_access_commercial_comments(uuid,text) from public,anon,authenticated;
grant execute on function e10.can_access_commercial_comments(uuid,text) to service_role;

alter function public.e10_org_add_commercial_comment(uuid,text,uuid,text,text,uuid,text) rename to _e10_org_add_commercial_comment_r4;
alter function public.e10_org_list_commercial_comments(uuid,text,uuid,integer,timestamptz,uuid) rename to _e10_org_list_commercial_comments_r4;
revoke all on function public._e10_org_add_commercial_comment_r4(uuid,text,uuid,text,text,uuid,text),public._e10_org_list_commercial_comments_r4(uuid,text,uuid,integer,timestamptz,uuid) from public,anon,authenticated;
grant execute on function public._e10_org_add_commercial_comment_r4(uuid,text,uuid,text,text,uuid,text),public._e10_org_list_commercial_comments_r4(uuid,text,uuid,integer,timestamptz,uuid) to service_role;

create function public.e10_org_add_commercial_comment(p_org uuid,p_document_kind text,p_document_id uuid,p_audience text,p_body text,p_supersedes_comment_id uuid,p_idempotency_key text)
returns jsonb language plpgsql security definer set search_path=public as $$
begin
  if p_document_kind in ('purchase_order','supplier_invoice','stock_receipt','supplier_credit') and not e10.can_access_commercial_comments(p_org,p_document_kind) then raise exception using errcode='42501',message='commercial_comment_write_denied';end if;
  return public._e10_org_add_commercial_comment_r4(p_org,p_document_kind,p_document_id,p_audience,p_body,p_supersedes_comment_id,p_idempotency_key);
end $$;
create function public.e10_org_list_commercial_comments(p_org uuid,p_document_kind text,p_document_id uuid,p_limit integer default 50,p_before_created_at timestamptz default null,p_before_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path=public as $$
begin
  if p_document_kind in ('purchase_order','supplier_invoice','stock_receipt','supplier_credit') and not e10.can_access_commercial_comments(p_org,p_document_kind) then raise exception using errcode='42501',message='commercial_comment_read_denied';end if;
  return public._e10_org_list_commercial_comments_r4(p_org,p_document_kind,p_document_id,p_limit,p_before_created_at,p_before_id);
end $$;

alter function public.e10_org_purchase_destinations(uuid,text,uuid,integer) rename to _e10_org_purchase_destinations_r4;
revoke all on function public._e10_org_purchase_destinations_r4(uuid,text,uuid,integer) from public,anon,authenticated;
grant execute on function public._e10_org_purchase_destinations_r4(uuid,text,uuid,integer) to service_role;
create function public.e10_org_purchase_destinations(p_org uuid,p_after_name text default null,p_after_id uuid default null,p_limit integer default 50)
returns table(id uuid,code text,name text,eligible_count bigint,sole_eligible boolean)
language plpgsql stable security definer set search_path=public as $$
begin
  if not exists(select 1 from public.e10_organizations o where o.id=p_org and o.status='active') then raise exception using errcode='42501',message='organization_access_denied';end if;
  return query select * from public._e10_org_purchase_destinations_r4(p_org,p_after_name,p_after_id,p_limit);
end $$;

alter function public.e10_org_supplier_workspace(uuid,uuid,integer,text) rename to _e10_org_supplier_workspace_r4;
revoke all on function public._e10_org_supplier_workspace_r4(uuid,uuid,integer,text) from public,anon,authenticated;
grant execute on function public._e10_org_supplier_workspace_r4(uuid,uuid,integer,text) to service_role;
create function public.e10_org_supplier_workspace(p_org uuid,p_supplier_id uuid,p_limit integer default 50,p_cursor text default null)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare v jsonb;can_fin boolean;
begin
  v:=public._e10_org_supplier_workspace_r4(p_org,p_supplier_id,p_limit,p_cursor);
  can_fin:=e10.has_org_cap(p_org,'financial.actual_cost.read');
  if not can_fin then
    select jsonb_set(v,'{items}',coalesce(jsonb_agg(case when i->>'kind'='stock_receipt' then i-'line_ids' else i end),'[]'::jsonb))
      into v from jsonb_array_elements(coalesce(v->'items','[]'::jsonb))i;
  end if;
  return v;
end $$;

revoke all on function public.e10_org_add_commercial_comment(uuid,text,uuid,text,text,uuid,text),public.e10_org_list_commercial_comments(uuid,text,uuid,integer,timestamptz,uuid),public.e10_org_supplier_workspace(uuid,uuid,integer,text),public.e10_org_purchase_destinations(uuid,text,uuid,integer) from public,anon;
grant execute on function public.e10_org_add_commercial_comment(uuid,text,uuid,text,text,uuid,text),public.e10_org_list_commercial_comments(uuid,text,uuid,integer,timestamptz,uuid),public.e10_org_supplier_workspace(uuid,uuid,integer,text),public.e10_org_purchase_destinations(uuid,text,uuid,integer) to authenticated,service_role;
