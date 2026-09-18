-- TA-X7d.2c one lock order and post-wait authorization check for market reads.
create function e10.lock_market_read_snapshot(p_org uuid)
returns table(actor_id uuid,organization_revision bigint,catalog_revision bigint)
language plpgsql volatile security definer set search_path=public as $$
declare v_actor uuid:=auth.uid();v_org_revision bigint;v_catalog_revision bigint;
begin
 if p_org is null or v_actor is null or not exists(select 1 from public.e10_organizations where id=p_org and status='active')or not e10.is_org_member(p_org)or not e10.has_org_cap(p_org,'act.view_market_analytics')then raise exception using errcode='42501',message='market_read_denied';end if;
 select revision into v_catalog_revision from public.e10_market_catalog_revision where singleton for share;
 select revision into v_org_revision from public.e10_market_org_revisions where organization_id=p_org for share;
 if v_catalog_revision is null or v_org_revision is null then raise exception using errcode='55000',message='market_revision_missing';end if;
 if auth.uid()is distinct from v_actor or not exists(select 1 from public.e10_organizations where id=p_org and status='active')or not e10.is_org_member(p_org)or not e10.has_org_cap(p_org,'act.view_market_analytics')then raise exception using errcode='42501',message='market_read_denied';end if;
 return query select v_actor,v_org_revision,v_catalog_revision;
end $$;
revoke all on function e10.lock_market_read_snapshot(uuid)from public,anon,authenticated;
grant execute on function e10.lock_market_read_snapshot(uuid)to service_role;
comment on function e10.lock_market_read_snapshot(uuid)is'Captures the global catalog then organization market revision under share locks and rechecks active-org membership plus act.view_market_analytics after waits.';
