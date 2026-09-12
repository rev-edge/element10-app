# Reproduction kit

All scripts were run against the `foundation-a6` checkout at `f93aaa7150cd11b7c20d1bef4b61e556a9a46907`. Nothing here touches staging or production; use a throwaway local PostgreSQL only.

## Harness (`harness/`)
- `supabase_shim.sql`: creates the Supabase roles, `auth`/`storage`/`vault`/`extensions` schemas, `auth.uid()`-style functions, the `supabase_realtime` publication and the migration ledger on a plain PostgreSQL 16+ cluster. It also sets the database search path to include `extensions`, which one migration relies on.
- `rebuild.sh`: drops and recreates the `postgres` database on `127.0.0.1:54322`, applies the shim, replays every `supabase/migrations/*.sql` in name order in autocommit mode (recording the ledger), then loads `supabase/seed.sql`. Set `REPO` to the checkout and `REVIEW_SCRATCH` to a writable directory. Pass a migration version as the first argument to stop after it (used for the predecessor-upgrade check). On PostgreSQL 16 the two `MAINTAIN` tokens in the baseline must be removed from a copy first (`sed 's/TRUNCATE,MAINTAIN,UPDATE/TRUNCATE,UPDATE/'`), and a stub `supabase_vault` extension control file is needed; both are described in the report.
- `provision_sql.sql`: creates the three CI users directly in SQL, replacing `tests/provision_local_users.js` when the Supabase auth service is unavailable.
- `ci_steps.txt` and `run_ci.sh`: the database-backed steps of `.github/workflows/ci.yml` in CI order, and a runner that logs PASS/FAIL per step. `ci_results_run2.txt` is the reviewer's final run.

## Counterexamples (`counterexamples/`)
Each SQL script is wrapped in `begin ... rollback` and prints labelled results; run with `psql <url> -f <file>` from inside its folder (they `\i` their fixture). The two-connection races (`*.sh`, `*.js`) create a committed fixture, run the race, delete their rows and print a residue count; run them on a database you can rebuild. Node scripts need the `pg` module from `tests/node_modules`.

| Folder | Covers | Findings |
| --- | --- | --- |
| `authz_x2_x4` | tenant isolation, capabilities, location authority, post-lock races for X2–X4 writers | IMPL-2, IMPL-7, IMPL-9, IMPL-10, IMPL-14 |
| `inventory_x4` | conservation, reversal, disposition, cost history | IMPL-1, IMPL-13, IMPL-14, SCOPE-4/5/6 |
| `intake_x5` | deduplication, provenance, lineage, envelope validation | IMPL-5, IMPL-11, IMPL-14 |
| `customer_x6_x7b` | provisional vs posted, posting race, currencies, grid/summary | IMPL-3, IMPL-4, IMPL-6, IMPL-14 |
| `reporting_x7_x8` | aggregation before pagination, cursors, contexts, drafts, outbox, facets, suspended org | IMPL-10, IMPL-14 |
| `identity_x1_f4` | copy/variant, immutability, mappings, dual membership, F4 | IMPL-8, IMPL-12, IMPL-14 |
