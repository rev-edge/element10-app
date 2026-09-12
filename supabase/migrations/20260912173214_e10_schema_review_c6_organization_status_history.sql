-- Schema-review checkpoint 6: reversible organization suspension with history.

alter table public.e10_organizations
  add column updated_at timestamptz not null default clock_timestamp(),
  add column suspended_at timestamptz,
  add column suspension_time_known boolean not null default false;
update public.e10_organizations set updated_at=created_at,
  suspended_at=null,suspension_time_known=false;
alter table public.e10_organizations add constraint e10_organizations_suspension_time_ck check(
  (status='active'and suspended_at is null and not suspension_time_known)
  or(status='suspended'and((suspension_time_known and suspended_at is not null)or(not suspension_time_known and suspended_at is null)))
)not valid;
alter table public.e10_organizations validate constraint e10_organizations_suspension_time_ck;

create table public.e10_organization_status_transitions(
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.e10_organizations(id)on delete restrict,
  revision bigint not null check(revision>0),
  transition_type text not null check(transition_type in('baseline','suspend','resume')),
  from_status text check(from_status is null or from_status in('active','suspended')),
  to_status text not null check(to_status in('active','suspended')),
  effective_at timestamptz,
  effective_time_known boolean not null,
  reason text not null check(length(btrim(reason))between 1 and 2000),
  evidence jsonb not null default'{}'::jsonb check(jsonb_typeof(evidence)='object'and octet_length(evidence::text)<=65536),
  idempotency_key text not null unique check(length(btrim(idempotency_key))between 1 and 500),
  request_fingerprint text not null check(length(request_fingerprint)=64),
  changed_by uuid references auth.users(id)on delete set null,
  recorded_at timestamptz not null default clock_timestamp(),
  unique(organization_id,revision),
  check((effective_time_known and effective_at is not null)or(not effective_time_known and effective_at is null)),
  check((transition_type='baseline'and from_status is null)
    or(transition_type='suspend'and from_status='active'and to_status='suspended')
    or(transition_type='resume'and from_status='suspended'and to_status='active'))
);
create index e10_organization_status_transitions_history_idx on public.e10_organization_status_transitions(organization_id,revision desc,id);
insert into public.e10_organization_status_transitions(
  organization_id,revision,transition_type,from_status,to_status,effective_at,effective_time_known,reason,idempotency_key,request_fingerprint)
select id,1,'baseline',null,status,case when status='active'then created_at end,status='active',
  case when status='active'then'organization creation baseline'else'pre-history suspension; effective time unknown'end,
  'organization-status-baseline:'||id,
  encode(sha256(convert_to('organization-status-baseline|'||id||'|'||status,'UTF8')),'hex')
from public.e10_organizations;

create function e10.stamp_organization_lifecycle()returns trigger language plpgsql security definer set search_path=public as $$
begin
 if tg_op='INSERT'then
  new.updated_at:=coalesce(new.updated_at,clock_timestamp());
  if new.status='suspended'and new.suspended_at is null then new.suspended_at:=clock_timestamp();new.suspension_time_known:=true;end if;
  if new.status='active'then new.suspended_at:=null;new.suspension_time_known:=false;end if;
 elsif new.status is distinct from old.status then
  if new.updated_at is not distinct from old.updated_at then new.updated_at:=clock_timestamp();end if;
  if new.status='suspended'then new.suspended_at:=coalesce(new.suspended_at,clock_timestamp());new.suspension_time_known:=true;
  else new.suspended_at:=null;new.suspension_time_known:=false;end if;
 elsif row(new.slug,new.name,new.settings,new.created_by)is distinct from row(old.slug,old.name,old.settings,old.created_by)then
  new.updated_at:=clock_timestamp();
 end if;
 return new;
end$$;
revoke all on function e10.stamp_organization_lifecycle()from public,anon,authenticated;grant execute on function e10.stamp_organization_lifecycle()to service_role;
create trigger e10_organization_lifecycle_trg before insert or update on public.e10_organizations for each row execute function e10.stamp_organization_lifecycle();

create function e10.record_organization_status_baseline()returns trigger language plpgsql security definer set search_path=public as $$
begin
 insert into public.e10_organization_status_transitions(
  organization_id,revision,transition_type,from_status,to_status,effective_at,effective_time_known,reason,idempotency_key,request_fingerprint,changed_by)
 values(new.id,1,'baseline',null,new.status,
  case when new.status='active'then new.created_at else new.suspended_at end,
  new.status='active'or new.suspension_time_known,'organization creation baseline',
  'organization-status-baseline:'||new.id,
  encode(sha256(convert_to('organization-status-baseline|'||new.id||'|'||new.status,'UTF8')),'hex'),new.created_by);
 return new;
end$$;
revoke all on function e10.record_organization_status_baseline()from public,anon,authenticated;grant execute on function e10.record_organization_status_baseline()to service_role;
create trigger e10_organization_status_baseline_trg after insert on public.e10_organizations for each row execute function e10.record_organization_status_baseline();

alter table public.e10_organization_status_transitions enable row level security;
create policy e10_organization_status_transitions_sel on public.e10_organization_status_transitions for select to authenticated using(e10.is_org_member(organization_id));
revoke all on public.e10_organization_status_transitions from public,anon,authenticated;
grant select on public.e10_organization_status_transitions to authenticated;
grant all on public.e10_organization_status_transitions to service_role;
create trigger e10_organization_status_transitions_append_only before update or delete on public.e10_organization_status_transitions for each row execute function e10.reject_append_only_change();

create function public.e10_platform_set_organization_status(
 p_org uuid,p_expected_updated_at timestamptz,p_status text,p_reason text,p_evidence jsonb,p_idempotency_key text
)returns jsonb language plpgsql security definer set search_path=public as $$
declare actor uuid:=auth.uid();o record;prior record;replay record;rid uuid:=gen_random_uuid();fp text;now_at timestamptz:=clock_timestamp();kind text;
begin
 if actor is null or not e10.is_platform_admin()then raise exception using errcode='42501',message='organization_status_change_denied';end if;
 if p_org is null or p_expected_updated_at is null or p_status not in('active','suspended')or p_reason is null or length(btrim(p_reason))not between 1 and 2000 or p_evidence is null or jsonb_typeof(p_evidence)<>'object'or octet_length(p_evidence::text)>65536 or p_idempotency_key is null or length(btrim(p_idempotency_key))not between 1 and 500 then raise exception using errcode='22023',message='organization_status_change_invalid';end if;
 fp:=encode(sha256(convert_to(jsonb_build_object('org',p_org,'expected',p_expected_updated_at,'status',p_status,'reason',btrim(p_reason),'evidence',p_evidence)::text,'UTF8')),'hex');
 perform pg_advisory_xact_lock(hashtextextended('organization-status-idempotency|'||p_idempotency_key,0));
 select*into replay from public.e10_organization_status_transitions where idempotency_key=p_idempotency_key;
 if found then if replay.request_fingerprint<>fp then raise exception using errcode='22023',message='idempotency_key_mismatch';end if;return jsonb_build_object('ok',true,'replay',true,'transition_id',replay.id,'revision',replay.revision,'status',replay.to_status);end if;
 select*into o from public.e10_organizations where id=p_org for update;if not found then raise exception using errcode='22023',message='organization_not_found';end if;
 if auth.uid()is distinct from actor or not e10.is_platform_admin()then raise exception using errcode='42501',message='organization_status_change_denied';end if;
 if o.updated_at<>p_expected_updated_at then raise exception using errcode='40001',message='organization_status_revision_conflict';end if;
 if o.status=p_status then raise exception using errcode='22023',message='organization_status_noop';end if;
 select*into prior from public.e10_organization_status_transitions where organization_id=p_org order by revision desc limit 1 for update;
 kind:=case when p_status='suspended'then'suspend'else'resume'end;
 update public.e10_organizations set status=p_status,suspended_at=case when p_status='suspended'then now_at end,
  suspension_time_known=p_status='suspended',updated_at=now_at where id=p_org;
 insert into public.e10_organization_status_transitions(id,organization_id,revision,transition_type,from_status,to_status,effective_at,effective_time_known,reason,evidence,idempotency_key,request_fingerprint,changed_by)
 values(rid,p_org,prior.revision+1,kind,o.status,p_status,now_at,true,btrim(p_reason),p_evidence,p_idempotency_key,fp,actor);
 return jsonb_build_object('ok',true,'replay',false,'transition_id',rid,'revision',prior.revision+1,'status',p_status,'effective_at',now_at);
end$$;
revoke all on function public.e10_platform_set_organization_status(uuid,timestamptz,text,text,jsonb,text)from public,anon;
grant execute on function public.e10_platform_set_organization_status(uuid,timestamptz,text,text,jsonb,text)to authenticated,service_role;

comment on column public.e10_organizations.suspension_time_known is'False distinguishes a pre-history suspended row with unknown effective time from a reviewed suspension timestamp.';
comment on table public.e10_organization_status_transitions is'Append-only status history. Suspension is reversible. Billing delinquency is deliberately a separate future state machine.';
