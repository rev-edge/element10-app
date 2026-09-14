-- Schema-review checkpoint 4: stable platform identity and operational-to-presentation bridge.

create table public.e10_platforms(
  id uuid primary key default gen_random_uuid(),
  slug text not null unique check(slug ~ '^[a-z][a-z0-9_-]{1,62}$'),
  current_name text not null check(length(btrim(current_name))between 1 and 100),
  status text not null default'active'check(status in('active','retired')),
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp()
);
create table public.e10_platform_name_decisions(
  id uuid primary key default gen_random_uuid(),
  platform_id uuid not null references public.e10_platforms(id)on delete restrict,
  revision bigint not null check(revision>0),
  display_name text not null check(length(btrim(display_name))between 1 and 100),
  supersedes_decision_id uuid references public.e10_platform_name_decisions(id)on delete restrict,
  reason text not null check(length(btrim(reason))between 1 and 2000),
  idempotency_key text not null unique check(length(btrim(idempotency_key))between 1 and 500),
  request_fingerprint text not null check(length(request_fingerprint)=64),
  reviewed_by uuid references auth.users(id)on delete set null,
  reviewed_at timestamptz not null default clock_timestamp(),
  unique(platform_id,revision)
);
create unique index e10_platform_name_successor_uq on public.e10_platform_name_decisions(supersedes_decision_id)where supersedes_decision_id is not null;
create table public.e10_platform_keys(
  id uuid primary key default gen_random_uuid(),
  platform_id uuid not null references public.e10_platforms(id)on delete restrict,
  key_kind text not null check(key_kind in('channel','provider','legacy_family')),
  key_value text not null check(length(btrim(key_value))between 1 and 100),
  key_norm text generated always as(lower(btrim(key_value)))stored,
  created_at timestamptz not null default clock_timestamp(),
  unique(key_kind,key_norm)
);

insert into public.e10_platforms(id,slug,current_name)values('c4000000-0000-4000-8000-000000000001','whatnot','Whatnot');
insert into public.e10_platform_name_decisions(platform_id,revision,display_name,reason,idempotency_key,request_fingerprint)
values('c4000000-0000-4000-8000-000000000001',1,'Whatnot','initial governed platform name','platform-name:whatnot:1',encode(sha256(convert_to('platform-name|whatnot|1|Whatnot','UTF8')),'hex'));
insert into public.e10_platform_keys(platform_id,key_kind,key_value)values
('c4000000-0000-4000-8000-000000000001','channel','whatnot'),
('c4000000-0000-4000-8000-000000000001','provider','whatnot'),
('c4000000-0000-4000-8000-000000000001','legacy_family','whatnot');

alter table public.e10_customer_identity_decisions add column platform_id uuid references public.e10_platforms(id);
alter table public.e10_session_presence_streams add column platform_id uuid references public.e10_platforms(id);
alter table public.e10_obs_channels add column platform_id uuid references public.e10_platforms(id);
alter table public.e10_break_slots add column buyer_platform_id uuid references public.e10_platforms(id);
alter table public.e10_native_break_sales add column buyer_platform_id uuid references public.e10_platforms(id);

alter table public.e10_customer_identity_decisions disable trigger e10_customer_identity_append_only_trg;
update public.e10_customer_identity_decisions d set platform_id=k.platform_id from public.e10_platform_keys k
where d.identity_kind='channel_account'and k.key_kind='channel'and k.key_norm=lower(btrim(d.channel));
alter table public.e10_customer_identity_decisions enable trigger e10_customer_identity_append_only_trg;
alter table public.e10_session_presence_streams disable trigger e10_presence_stream_immutable;
update public.e10_session_presence_streams s set platform_id=k.platform_id from public.e10_platform_keys k
where s.source_class='authorized_platform'and k.key_kind='provider'and k.key_norm=lower(btrim(s.provider_key));
alter table public.e10_session_presence_streams enable trigger e10_presence_stream_immutable;
update public.e10_obs_channels c set platform_id=k.platform_id from public.e10_platform_keys k
where k.key_kind='legacy_family'and k.key_norm=lower(btrim(c.family));
update public.e10_break_slots set buyer_platform_id='c4000000-0000-4000-8000-000000000001'where buyer_handle is not null;
alter table public.e10_native_break_sales disable trigger e10_native_break_sales_append_only_trg;
update public.e10_native_break_sales set buyer_platform_id='c4000000-0000-4000-8000-000000000001'where buyer_handle is not null;
alter table public.e10_native_break_sales enable trigger e10_native_break_sales_append_only_trg;

create function e10.stamp_platform_identity()returns trigger language plpgsql security definer set search_path=public as $$
declare v_kind text;v_key text;
begin
  if tg_table_name='e10_customer_identity_decisions'then
    if new.identity_kind='alias'then new.platform_id:=null;return new;end if;
    v_kind:='channel';v_key:=new.channel;
  elsif tg_table_name='e10_session_presence_streams'then
    if new.source_class='companion'then new.platform_id:=null;return new;end if;
    v_kind:='provider';v_key:=new.provider_key;
  elsif tg_table_name='e10_obs_channels'then v_kind:='legacy_family';v_key:=new.family;
  elsif tg_table_name='e10_break_slots'then
    if new.buyer_handle is null then new.buyer_platform_id:=null;return new;end if;
    if new.buyer_platform_id is null then new.buyer_platform_id:='c4000000-0000-4000-8000-000000000001';end if;return new;
  else
    if new.buyer_handle is null then new.buyer_platform_id:=null;return new;end if;
    if new.buyer_platform_id is null then new.buyer_platform_id:='c4000000-0000-4000-8000-000000000001';end if;return new;
  end if;
  select platform_id into new.platform_id from public.e10_platform_keys where key_kind=v_kind and key_norm=lower(btrim(v_key));
  if new.platform_id is null then raise exception using errcode='23514',message='platform_identity_unknown';end if;
  return new;
end$$;
revoke all on function e10.stamp_platform_identity()from public,anon,authenticated;grant execute on function e10.stamp_platform_identity()to service_role;
create trigger e10_customer_identity_platform_trg before insert on public.e10_customer_identity_decisions for each row execute function e10.stamp_platform_identity();
create trigger e10_presence_stream_platform_trg before insert on public.e10_session_presence_streams for each row execute function e10.stamp_platform_identity();
create trigger e10_obs_channel_platform_trg before insert or update of family on public.e10_obs_channels for each row execute function e10.stamp_platform_identity();
create trigger e10_break_slot_platform_trg before insert or update of buyer_handle,buyer_platform_id on public.e10_break_slots for each row execute function e10.stamp_platform_identity();
create trigger e10_native_sale_platform_trg before insert on public.e10_native_break_sales for each row execute function e10.stamp_platform_identity();
create index e10_customer_identity_platform_account_idx on public.e10_customer_identity_decisions(organization_id,platform_id,lower(btrim(regexp_replace(external_account_id,'^@',''))),decided_at desc,id desc)where identity_kind='channel_account';
create index e10_presence_stream_platform_subject_idx on public.e10_session_presence_streams(organization_id,platform_id,platform_attendee_key,created_at,id)where source_class='authorized_platform';

alter table public.e10_platforms enable row level security;alter table public.e10_platform_name_decisions enable row level security;alter table public.e10_platform_keys enable row level security;
create policy e10_platforms_sel on public.e10_platforms for select to authenticated using(true);
create policy e10_platform_names_sel on public.e10_platform_name_decisions for select to authenticated using(true);
create policy e10_platform_keys_sel on public.e10_platform_keys for select to authenticated using(true);
revoke all on public.e10_platforms,public.e10_platform_name_decisions,public.e10_platform_keys from public,anon,authenticated;
grant select on public.e10_platforms,public.e10_platform_name_decisions,public.e10_platform_keys to authenticated;
grant all on public.e10_platforms,public.e10_platform_name_decisions,public.e10_platform_keys to service_role;
create trigger e10_platform_name_decisions_append_only before update or delete on public.e10_platform_name_decisions for each row execute function e10.reject_append_only_change();
create trigger e10_platform_keys_append_only before update or delete on public.e10_platform_keys for each row execute function e10.reject_append_only_change();

create function public.e10_platform_review_name(p_platform uuid,p_expected_updated_at timestamptz,p_name text,p_reason text,p_idempotency_key text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare actor uuid:=auth.uid();p record;prior record;replay record;rid uuid:=gen_random_uuid();fp text;
begin
 if actor is null or not e10.is_platform_admin()then raise exception using errcode='42501',message='platform_registry_curation_denied';end if;
 if p_platform is null or p_expected_updated_at is null or p_name is null or length(btrim(p_name))not between 1 and 100 or p_reason is null or length(btrim(p_reason))not between 1 and 2000 or p_idempotency_key is null or length(btrim(p_idempotency_key))not between 1 and 500 then raise exception using errcode='22023',message='platform_name_review_invalid';end if;
 fp:=encode(sha256(convert_to(jsonb_build_object('platform',p_platform,'expected',p_expected_updated_at,'name',btrim(p_name),'reason',btrim(p_reason))::text,'UTF8')),'hex');
 perform pg_advisory_xact_lock(hashtextextended('platform-name-idempotency|'||p_idempotency_key,0));
 select*into replay from public.e10_platform_name_decisions where idempotency_key=p_idempotency_key;
 if found then if replay.request_fingerprint<>fp then raise exception using errcode='22023',message='idempotency_key_mismatch';end if;return jsonb_build_object('ok',true,'replay',true,'decision_id',replay.id,'revision',replay.revision);end if;
 select*into p from public.e10_platforms where id=p_platform for update;
 if not found then raise exception using errcode='22023',message='platform_not_found';end if;
 if auth.uid()is distinct from actor or not e10.is_platform_admin()then raise exception using errcode='42501',message='platform_registry_curation_denied';end if;
 if p.updated_at<>p_expected_updated_at then raise exception using errcode='40001',message='platform_revision_conflict';end if;
 select d.*into prior from public.e10_platform_name_decisions d where d.platform_id=p_platform and not exists(select 1 from public.e10_platform_name_decisions n where n.supersedes_decision_id=d.id)for update;
 insert into public.e10_platform_name_decisions(id,platform_id,revision,display_name,supersedes_decision_id,reason,idempotency_key,request_fingerprint,reviewed_by)
 values(rid,p_platform,prior.revision+1,btrim(p_name),prior.id,btrim(p_reason),p_idempotency_key,fp,actor);
 update public.e10_platforms set current_name=btrim(p_name),updated_at=clock_timestamp()where id=p_platform;
 return jsonb_build_object('ok',true,'replay',false,'decision_id',rid,'revision',prior.revision+1);
end$$;
revoke all on function public.e10_platform_review_name(uuid,timestamptz,text,text,text)from public,anon;grant execute on function public.e10_platform_review_name(uuid,timestamptz,text,text,text)to authenticated,service_role;

create function public.e10_org_lookup_live_buyer(p_org uuid,p_session uuid,p_platform_slug text,p_handle text)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare actor uuid:=auth.uid();pid uuid;norm text:=lower(btrim(regexp_replace(coalesce(p_handle,''),'^@','')));rows jsonb;cnt bigint;
begin
 if actor is null or not e10.is_org_member(p_org)or not e10.has_org_cap(p_org,'act.live_run')or not e10.owns_session(p_session)then raise exception using errcode='42501',message='live_buyer_lookup_denied';end if;
 if norm=''then raise exception using errcode='22023',message='live_buyer_lookup_invalid';end if;
 select id into pid from public.e10_platforms where slug=lower(btrim(p_platform_slug))and status='active';if not found then raise exception using errcode='22023',message='live_buyer_platform_invalid';end if;
 with matches as(select distinct e10.customer_effective_id(p_org,i.customer_id)customer_id,c.display_name,i.verified_user_id
  from public.e10_current_effective_customer_identities i join public.e10_customer_identity_decisions d on d.id=i.id
  join public.e10_customers c on c.organization_id=p_org and c.id=e10.customer_effective_id(p_org,i.customer_id)and c.status='active'
  left join public.e10_viewer_handle_claims h on h.id=i.viewer_handle_claim_id
  where i.organization_id=p_org and i.identity_kind='channel_account'and i.identity_action='attach'and d.platform_id=pid
   and lower(btrim(regexp_replace(i.external_account_id,'^@','')))=norm
   and(i.verification_basis='operator_review'or(i.verification_basis='verified_handle'and h.status='verified')))
 select count(*),coalesce(jsonb_agg(jsonb_build_object('customer_id',customer_id,'display_name',display_name,'verified_user_id',verified_user_id)order by customer_id),'[]'::jsonb)into cnt,rows from matches;
 return jsonb_build_object('platform_id',pid,'platform_slug',lower(btrim(p_platform_slug)),'handle_norm',norm,'match_status',case when cnt=0 then'unrecognized'when cnt=1 then'recognized'else'ambiguous'end,'matches',rows);
end$$;
revoke all on function public.e10_org_lookup_live_buyer(uuid,uuid,text,text)from public,anon;grant execute on function public.e10_org_lookup_live_buyer(uuid,uuid,text,text)to authenticated,service_role;

create function e10.enqueue_live_buyer_presentation()returns trigger language plpgsql security definer set search_path=public as $$
declare s record;
begin
 if tg_table_name='e10_native_break_sales'then
  insert into public.e10_integration_outbox(organization_id,commercial_event_id,destination_key,payload)
  values(new.organization_id,new.commercial_event_id,'presentation.live_buyer',jsonb_build_object('event','buyer_assigned','sale_id',new.id,'session_id',new.session_id,'slot_id',new.slot_id,'platform_id',new.buyer_platform_id,'buyer_handle',new.buyer_handle,'customer_id',new.customer_id,'identity_status',new.buyer_identity_status));
 elsif new.transition_type='released'then
  select*into s from public.e10_native_break_sales where organization_id=new.organization_id and id=new.sale_id;
  insert into public.e10_integration_outbox(organization_id,commercial_event_id,destination_key,payload)
  values(new.organization_id,s.commercial_event_id,'presentation.live_buyer_release',jsonb_build_object('event','buyer_released','sale_id',s.id,'session_id',s.session_id,'slot_id',s.slot_id,'platform_id',s.buyer_platform_id,'buyer_handle',s.buyer_handle,'customer_id',s.customer_id));
 end if;return new;
end$$;
revoke all on function e10.enqueue_live_buyer_presentation()from public,anon,authenticated;grant execute on function e10.enqueue_live_buyer_presentation()to service_role;
create trigger e10_native_sale_presentation_trg after insert on public.e10_native_break_sales for each row execute function e10.enqueue_live_buyer_presentation();
create trigger e10_native_sale_release_presentation_trg after insert on public.e10_native_break_sale_transitions for each row execute function e10.enqueue_live_buyer_presentation();

comment on table public.e10_platforms is'Shared governed platform registry. External accounts remain organization-private and may map to distinct customers in different organizations.';
comment on function e10.enqueue_live_buyer_presentation()is'Projects operational buyer assignment/release into a service-only presentation outbox. Observed-capture tables are never authoritative or written by this bridge.';
