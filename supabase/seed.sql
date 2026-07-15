-- Foundation Gate A1 — minimal LOCAL/STAGING fixtures. Schema ships in migrations; DATA ships here (never
-- in migrations, never captured by the blueprint). Loaded by `supabase db reset` / `supabase start`.
--
-- NOT seeded here (load separately, by design):
--   * the ~57k-card catalog (public.e10_cards) + 176 rosters → the app's documented import (Data tab),
--   * local test users e10adm / e10mem / e10gate → tests/provision_local_users.js (Foundation Gate A2),
--   * production inventory (35 items) → that lives only in prod; local uses these sample rows.

-- shared workspace: non-inventory sections only (post-M4 inventory is relational, below). The app fills
-- pick-list defaults on first load if `lists` is empty.
insert into public.e10_workspace (id, data, rev, owner)
  values ('shared',
    '{"comments":[],"todos":[],"streamers":["Trent"],"lists":{},"attachments":[],"checklists":[],"repacks":[]}'::jsonb,
    1, null)
  on conflict (id) do nothing;

-- a few inventory items (relational — the post-M4 system of record)
insert into public.e10_inventory_items
  (id, name, cat, qty, cost, value, boxes_per_case, per_box_cost, owner, added_at, seed) values
  ('seed_s01','2026 Topps Chrome Baseball Hobby Box','Box', 6, 110, 140, 1, 110, 'trent@example.com', 1780000000000, true),
  ('seed_s02','2025 Panini Prizm Football Mega Box', 'Box', 10, 40,  55,  1, 40,  'trent@example.com', 1780000000000, true),
  ('seed_g01','2023 Pokémon 151 Charizard ex PSA 10','Slab',1, 300, 450, 1, 300, 'trent@example.com', 1780000000000, true)
  on conflict (id) do nothing;
