-- Foundation Gate A6b Step 1 (EXPAND) — composite (organization_id, <fk>) FKs referencing each parent's
-- standalone UNIQUE INDEX on (organization_id, <key>) [PG allows FK -> valid non-partial unique index]. ADR §12 s3.
-- ADD ... NOT VALID (instant) then VALIDATE CONSTRAINT (online). Org is NULL pre-backfill, so MATCH SIMPLE means
-- these validate trivially now and begin enforcing org-consistency as Step 2 populates organization_id.
-- Existing single-column FKs are KEPT (dropped only at CONTRACT); global UNIQUE(id)/UNIQUE(share_code) preserved.

alter table public.e10_inventory_movements add constraint e10_inventory_movements_org_item_id_fkey foreign key (organization_id, item_id) references public.e10_inventory_items (organization_id, id) not valid;
alter table public.e10_inventory_reservations add constraint e10_inventory_reservations_org_item_id_fkey foreign key (organization_id, item_id) references public.e10_inventory_items (organization_id, id) not valid;
alter table public.e10_mutation_receipts add constraint e10_mutation_receipts_org_item_id_fkey foreign key (organization_id, item_id) references public.e10_inventory_items (organization_id, id) not valid;
alter table public.e10_break_slots add constraint e10_break_slots_org_session_id_fkey foreign key (organization_id, session_id) references public.e10_break_sessions (organization_id, id) not valid;
alter table public.e10_break_events add constraint e10_break_events_org_session_id_fkey foreign key (organization_id, session_id) references public.e10_break_sessions (organization_id, id) not valid;
alter table public.e10_break_events add constraint e10_break_events_org_slot_id_fkey foreign key (organization_id, slot_id) references public.e10_break_slots (organization_id, id) not valid;
alter table public.e10_session_viewers add constraint e10_session_viewers_org_session_id_fkey foreign key (organization_id, session_id) references public.e10_break_sessions (organization_id, id) not valid;
alter table public.e10_break_sessions add constraint e10_break_sessions_org_live_session_id_fkey foreign key (organization_id, live_session_id) references public.e10_live_sessions (organization_id, id) not valid;
alter table public.e10_obs_breaks add constraint e10_obs_breaks_org_product_id_fkey foreign key (organization_id, product_id) references public.e10_obs_products (organization_id, id) not valid;
alter table public.e10_obs_breaks add constraint e10_obs_breaks_org_stream_id_fkey foreign key (organization_id, stream_id) references public.e10_obs_streams (organization_id, id) not valid;
alter table public.e10_obs_captures add constraint e10_obs_captures_org_stream_id_fkey foreign key (organization_id, stream_id) references public.e10_obs_streams (organization_id, id) not valid;
alter table public.e10_obs_product_prices add constraint e10_obs_product_prices_org_product_id_fkey foreign key (organization_id, product_id) references public.e10_obs_products (organization_id, id) not valid;
alter table public.e10_obs_slots add constraint e10_obs_slots_org_break_id_fkey foreign key (organization_id, break_id) references public.e10_obs_breaks (organization_id, id) not valid;
alter table public.e10_obs_streams add constraint e10_obs_streams_org_channel_id_fkey foreign key (organization_id, channel_id) references public.e10_obs_channels (organization_id, id) not valid;
alter table public.e10_obs_upcoming_shows add constraint e10_obs_upcoming_shows_org_channel_id_fkey foreign key (organization_id, channel_id) references public.e10_obs_channels (organization_id, id) not valid;
alter table public.e10_obs_viewer_snapshots add constraint e10_obs_viewer_snapshots_org_stream_id_fkey foreign key (organization_id, stream_id) references public.e10_obs_streams (organization_id, id) not valid;

alter table public.e10_inventory_movements validate constraint e10_inventory_movements_org_item_id_fkey;
alter table public.e10_inventory_reservations validate constraint e10_inventory_reservations_org_item_id_fkey;
alter table public.e10_mutation_receipts validate constraint e10_mutation_receipts_org_item_id_fkey;
alter table public.e10_break_slots validate constraint e10_break_slots_org_session_id_fkey;
alter table public.e10_break_events validate constraint e10_break_events_org_session_id_fkey;
alter table public.e10_break_events validate constraint e10_break_events_org_slot_id_fkey;
alter table public.e10_session_viewers validate constraint e10_session_viewers_org_session_id_fkey;
alter table public.e10_break_sessions validate constraint e10_break_sessions_org_live_session_id_fkey;
alter table public.e10_obs_breaks validate constraint e10_obs_breaks_org_product_id_fkey;
alter table public.e10_obs_breaks validate constraint e10_obs_breaks_org_stream_id_fkey;
alter table public.e10_obs_captures validate constraint e10_obs_captures_org_stream_id_fkey;
alter table public.e10_obs_product_prices validate constraint e10_obs_product_prices_org_product_id_fkey;
alter table public.e10_obs_slots validate constraint e10_obs_slots_org_break_id_fkey;
alter table public.e10_obs_streams validate constraint e10_obs_streams_org_channel_id_fkey;
alter table public.e10_obs_upcoming_shows validate constraint e10_obs_upcoming_shows_org_channel_id_fkey;
alter table public.e10_obs_viewer_snapshots validate constraint e10_obs_viewer_snapshots_org_stream_id_fkey;
