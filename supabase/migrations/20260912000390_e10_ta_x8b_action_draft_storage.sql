-- TA-X8b.1 inert, revisioned action proposals. No ordinary writer is called here.

create table public.e10_action_drafts(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null references public.e10_organizations(id) on delete cascade,
 created_by uuid not null references auth.users(id),
 operation text not null check(operation in('purchase_order.create','customer_transaction.create_draft')),
 current_revision integer not null default 1 check(current_revision>0),
 status text not null default 'draft' check(status in('draft','approved','committed','cancelled')),
 approved_revision integer,
 ordinary_result jsonb,
 committed_at timestamptz,
 cancelled_at timestamptz,
 created_at timestamptz not null default statement_timestamp(),
 updated_at timestamptz not null default statement_timestamp(),
 unique(organization_id,id),
 check(approved_revision is null or approved_revision between 1 and current_revision),
 check((status='approved')=(approved_revision is not null)),
 check((status='committed')=(ordinary_result is not null and committed_at is not null)),
 check((status='cancelled')=(cancelled_at is not null))
);
create index e10_action_drafts_creator_idx on public.e10_action_drafts(organization_id,created_by,updated_at desc,id);

create table public.e10_action_draft_revisions(
 organization_id uuid not null,
 draft_id uuid not null,
 revision integer not null check(revision>0),
 operation text not null check(operation in('purchase_order.create','customer_transaction.create_draft')),
 proposed_values jsonb not null check(jsonb_typeof(proposed_values)='object' and octet_length(proposed_values::text)<=262144),
 missing_fields text[] not null,
 field_provenance jsonb not null check(jsonb_typeof(field_provenance)='object' and octet_length(field_provenance::text)<=262144),
 source_references jsonb not null check(jsonb_typeof(source_references)='array' and jsonb_array_length(source_references)<=100 and octet_length(source_references::text)<=65536),
 reference_fingerprint text not null check(reference_fingerprint~'^[0-9a-f]{64}$'),
 request_fingerprint text not null check(request_fingerprint~'^[0-9a-f]{64}$'),
 authored_by uuid not null references auth.users(id),
 created_at timestamptz not null default statement_timestamp(),
 primary key(organization_id,draft_id,revision),
 foreign key(organization_id,draft_id) references public.e10_action_drafts(organization_id,id) on delete cascade
);

create table public.e10_action_draft_decisions(
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null,
 draft_id uuid not null,
 revision integer not null,
 decision_action text not null check(decision_action in('approve','cancel')),
 reason text,
 decided_by uuid not null references auth.users(id),
 created_at timestamptz not null default statement_timestamp(),
 foreign key(organization_id,draft_id,revision) references public.e10_action_draft_revisions(organization_id,draft_id,revision)
);
create index e10_action_draft_decisions_draft_idx on public.e10_action_draft_decisions(organization_id,draft_id,created_at,id);

create table public.e10_action_draft_commands(
 organization_id uuid not null references public.e10_organizations(id) on delete cascade,
 actor_id uuid not null references auth.users(id),
 idempotency_key text not null check(length(btrim(idempotency_key))between 1 and 200),
 command_type text not null check(command_type in('create','amend','approve','cancel','commit')),
 draft_id uuid not null,
 request_fingerprint text not null check(request_fingerprint~'^[0-9a-f]{64}$'),
 downstream_idempotency_key text,
 result jsonb not null check(jsonb_typeof(result)='object' and octet_length(result::text)<=65536),
 created_at timestamptz not null default statement_timestamp(),
 primary key(organization_id,actor_id,idempotency_key),
 foreign key(organization_id,draft_id) references public.e10_action_drafts(organization_id,id) on delete cascade
);
create index e10_action_draft_commands_draft_idx on public.e10_action_draft_commands(organization_id,draft_id,created_at);

alter table public.e10_action_drafts enable row level security;
alter table public.e10_action_draft_revisions enable row level security;
alter table public.e10_action_draft_decisions enable row level security;
alter table public.e10_action_draft_commands enable row level security;
revoke all on public.e10_action_drafts,public.e10_action_draft_revisions,public.e10_action_draft_decisions,public.e10_action_draft_commands from public,anon,authenticated,service_role;
grant select,insert,update on public.e10_action_drafts to service_role;
grant select,insert on public.e10_action_draft_revisions,public.e10_action_draft_decisions,public.e10_action_draft_commands to service_role;

create function e10.reject_action_draft_history_change()returns trigger
language plpgsql security definer set search_path=public as $$
begin raise exception using errcode='55000',message='action_draft_history_immutable';end $$;
create trigger e10_action_draft_revisions_immutable before update or delete on public.e10_action_draft_revisions for each row execute function e10.reject_action_draft_history_change();
create trigger e10_action_draft_decisions_immutable before update or delete on public.e10_action_draft_decisions for each row execute function e10.reject_action_draft_history_change();
create trigger e10_action_draft_commands_immutable before update or delete on public.e10_action_draft_commands for each row execute function e10.reject_action_draft_history_change();
revoke all on function e10.reject_action_draft_history_change() from public,anon,authenticated;
grant execute on function e10.reject_action_draft_history_change() to service_role;

comment on table public.e10_action_drafts is 'TA-X8b inert reviewable proposals. A row is not an ordinary business object and has no authority by itself.';
comment on table public.e10_action_draft_revisions is 'Immutable typed proposal values, server-derived missing fields, untrusted provenance and reference fingerprint.';
