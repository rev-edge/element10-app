-- TA-X5a typed intake/lifecycle foundation. No posting, settlement, or external delivery is enabled.

create table public.e10_intake_batches (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.e10_organizations(id),
  source_kind text not null check(source_kind in ('manual','csv','native','api')),
  source_connection_id text, source_reference text, original_file_reference text,
  payload_fingerprint text not null check(btrim(payload_fingerprint)<>''),
  status text not null default 'staged' check(status in ('staged','validated','committed','rejected')),
  created_by uuid references auth.users(id), created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unique(organization_id,id), unique(organization_id,source_kind,payload_fingerprint),
  check(source_kind<>'csv' or original_file_reference is not null)
);
create index e10_intake_batches_org_status_idx on public.e10_intake_batches(organization_id,status,created_at desc,id);

create table public.e10_intake_rows (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.e10_organizations(id),
  batch_id uuid not null, source_row_number bigint not null check(source_row_number>0), raw_payload jsonb not null,
  observation_kind text check(observation_kind in ('acquisition_cost','asking_price','completed_sale','estimated_value','inventory_receipt','customer_activity')),
  occurred_at timestamptz, currency text check(currency is null or currency ~ '^[A-Z]{3}$'), amount numeric,
  quantity numeric check(quantity is null or quantity>0),
  match_status text not null default 'unresolved' check(match_status in ('unresolved','matched','rejected')),
  product_master_id uuid, configuration_version_id uuid, unique_item_id uuid,
  validation_errors jsonb not null default '[]'::jsonb check(jsonb_typeof(validation_errors)='array'),
  created_at timestamptz not null default now(), unique(organization_id,id), unique(organization_id,batch_id,source_row_number),
  foreign key(organization_id,batch_id) references public.e10_intake_batches(organization_id,id),
  foreign key(organization_id,product_master_id) references public.e10_product_masters(organization_id,id),
  foreign key(organization_id,configuration_version_id) references public.e10_product_configuration_versions(organization_id,id),
  foreign key(organization_id,unique_item_id) references public.e10_unique_items(organization_id,id),
  check(match_status<>'matched' or num_nonnulls(product_master_id,configuration_version_id,unique_item_id)>0)
);
create index e10_intake_rows_batch_match_idx on public.e10_intake_rows(organization_id,batch_id,match_status,source_row_number,id);

create table public.e10_intake_resolver_decisions (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.e10_organizations(id),
  intake_row_id uuid not null,
  decision text not null check(decision in ('match_product','match_configuration','match_unique_item','reject','clear_match')),
  product_master_id uuid, configuration_version_id uuid, unique_item_id uuid,
  reason text not null check(btrim(reason)<>''), corrects_decision_id uuid,
  decided_by uuid references auth.users(id), decided_at timestamptz not null default now(), unique(organization_id,id),
  foreign key(organization_id,intake_row_id) references public.e10_intake_rows(organization_id,id),
  foreign key(organization_id,product_master_id) references public.e10_product_masters(organization_id,id),
  foreign key(organization_id,configuration_version_id) references public.e10_product_configuration_versions(organization_id,id),
  foreign key(organization_id,unique_item_id) references public.e10_unique_items(organization_id,id),
  foreign key(organization_id,corrects_decision_id) references public.e10_intake_resolver_decisions(organization_id,id),
  check(corrects_decision_id is null or corrects_decision_id<>id),
  check((decision='match_product' and product_master_id is not null and configuration_version_id is null and unique_item_id is null)
    or (decision='match_configuration' and product_master_id is null and configuration_version_id is not null and unique_item_id is null)
    or (decision='match_unique_item' and product_master_id is null and configuration_version_id is null and unique_item_id is not null)
    or (decision in ('reject','clear_match') and product_master_id is null and configuration_version_id is null and unique_item_id is null))
);
create index e10_intake_resolver_decisions_row_idx on public.e10_intake_resolver_decisions(organization_id,intake_row_id,decided_at,id);

create table public.e10_commercial_events (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.e10_organizations(id),
  event_type text not null check(event_type in ('acquisition','receipt','available_for_sale','listing_created','listing_published',
    'listing_paused','listing_resumed','listing_ended','listing_relisted','asking_price_changed','hold','release',
    'sale_committed','fulfillment','fee','payout','refund','return','cost_correction','correction')),
  subject_type text not null check(subject_type in ('inventory_item','unique_item','lot','listing','sale','receipt','customer_transaction','other')),
  subject_id text not null check(btrim(subject_id)<>''), occurred_at timestamptz not null,
  idempotency_key text not null check(btrim(idempotency_key)<>''),
  source_kind text not null check(source_kind in ('native','manual','import','system')), source_reference text,
  payload jsonb not null default '{}'::jsonb check(jsonb_typeof(payload)='object'), corrects_event_id uuid,
  created_by uuid references auth.users(id), created_at timestamptz not null default now(),
  unique(organization_id,id), unique(organization_id,idempotency_key),
  foreign key(organization_id,corrects_event_id) references public.e10_commercial_events(organization_id,id),
  check(corrects_event_id is null or corrects_event_id<>id),
  check(event_type not in ('correction','cost_correction') or corrects_event_id is not null)
);
create index e10_commercial_events_subject_time_idx on public.e10_commercial_events(organization_id,subject_type,subject_id,occurred_at,id);

create table public.e10_integration_outbox (
  id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.e10_organizations(id),
  commercial_event_id uuid not null, destination_key text not null check(btrim(destination_key)<>''),
  payload jsonb not null check(jsonb_typeof(payload)='object'),
  status text not null default 'pending' check(status in ('pending','delivered','failed','dead')),
  attempt_count integer not null default 0 check(attempt_count>=0), next_attempt_at timestamptz,
  delivered_at timestamptz, last_error text, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  unique(organization_id,id), unique(organization_id,commercial_event_id,destination_key),
  foreign key(organization_id,commercial_event_id) references public.e10_commercial_events(organization_id,id),
  check((status='delivered')=(delivered_at is not null))
);
create index e10_integration_outbox_pending_idx on public.e10_integration_outbox(status,next_attempt_at,created_at,id)
  where status in ('pending','failed');

do $$ declare t text; begin
  foreach t in array array['e10_intake_batches','e10_intake_rows','e10_intake_resolver_decisions','e10_commercial_events','e10_integration_outbox'] loop
    execute format('alter table public.%I enable row level security',t);
    execute format('revoke all on table public.%I from public,anon,authenticated',t);
    execute format('grant all on table public.%I to service_role',t);
  end loop;
end $$;
create trigger e10_intake_resolver_decisions_append_only_trg before update or delete on public.e10_intake_resolver_decisions
  for each row execute function e10.reject_append_only_change();
create trigger e10_commercial_events_append_only_trg before update or delete on public.e10_commercial_events
  for each row execute function e10.reject_append_only_change();

comment on table public.e10_intake_batches is 'Typed staging envelope only; committed status does not itself post inventory or finance.';
comment on table public.e10_intake_rows is 'Raw source payload remains separate from typed interpretation and reviewed identity resolution.';
comment on table public.e10_commercial_events is 'Immutable lifecycle evidence; no accounting recognition, payment, or settlement implication.';
comment on table public.e10_integration_outbox is 'Dormant transactional seam; no destination or dispatcher is enabled.';
