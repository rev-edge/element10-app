#!/usr/bin/env bash
# Element 10 — A6b Step 1 INVALID concurrent-index recovery proof.
# Fabricates a REAL invalid index (a failed CREATE UNIQUE INDEX CONCURRENTLY leaves indisvalid=false), runs the actual
# recovery script supabase/recovery/a6b_s1_reindex_recovery.sql, and asserts:
#   (A) the invalid ALLOWLISTED index (e10_obs_config_org_uq) is dropped,
#   (B) an invalid NON-allowlisted index survives (refuses unknown),
#   (C) the rerun-migration equivalent rebuilds the index to indisvalid=true.
# e10_obs_config is chosen because no composite FK references its (org,key) index, so it is safe to drop/rebuild.
set -euo pipefail
DB="${E10_LOCAL_DB_URL:-postgresql://postgres:postgres@127.0.0.1:54322/postgres}"
ORG0='e1000000-0000-4000-8000-0000000000a6'
Q() { psql "$DB" -v ON_ERROR_STOP=1 -tA "$@"; }
FAIL=0

echo "[a6b reindex recovery proof]"

# --- Part A: fabricate an INVALID index carrying the real allowlisted NAME e10_obs_config_org_uq ---
# Every composite index includes the table's own unique key, so no genuine (org,key) duplicate is possible; instead we
# make a real failed CONCURRENTLY build under the allowlisted name over a duplicable column (num_value) — recovery
# matches on index NAME + indisvalid, not columns. Distinct PK keys, same num_value => the unique build fails.
Q -c "drop index concurrently if exists public.e10_obs_config_org_uq;" >/dev/null
Q -c "delete from public.e10_obs_config where key in ('__reidx_a','__reidx_b');" >/dev/null
Q -c "insert into public.e10_obs_config(key, num_value, updated_at, organization_id) values ('__reidx_a', 42, now(), '$ORG0'), ('__reidx_b', 42, now(), '$ORG0');" >/dev/null
# concurrent unique build MUST fail on the duplicate num_value=42 and leave an invalid index named e10_obs_config_org_uq
if Q -c "create unique index concurrently e10_obs_config_org_uq on public.e10_obs_config (num_value);" >/dev/null 2>&1; then
  echo "  UNEXPECTED: concurrent build succeeded (no duplicate present)"; FAIL=1
fi
INVALID=$(Q -c "select indisvalid from pg_index where indexrelid='e10_obs_config_org_uq'::regclass;")
echo "  fabricated e10_obs_config_org_uq: indisvalid=$INVALID (expect f)"
[ "$INVALID" = "f" ] || { echo "  FAIL(A): did not fabricate an invalid allowlisted index"; FAIL=1; }

# --- Part B: an invalid NON-allowlisted index that recovery must NOT touch ---
Q -c "drop table if exists _reidx_unknown;" >/dev/null
Q -c "create table _reidx_unknown(organization_id uuid, id uuid);" >/dev/null
Q -c "insert into _reidx_unknown values ('$ORG0','b1000000-0000-4000-8000-000000000001'),('$ORG0','b1000000-0000-4000-8000-000000000001');" >/dev/null
Q -c "create unique index concurrently _reidx_unknown_uq on _reidx_unknown (organization_id, id);" >/dev/null 2>&1 || true
UNK=$(Q -c "select indisvalid from pg_index where indexrelid='_reidx_unknown_uq'::regclass;")
echo "  fabricated non-allowlisted _reidx_unknown_uq: indisvalid=$UNK (expect f)"

# --- run the ACTUAL recovery script (guarded path uses the same file against the staging pooler) ---
echo "  running supabase/recovery/a6b_s1_reindex_recovery.sql ..."
psql "$DB" -v ON_ERROR_STOP=1 -f supabase/recovery/a6b_s1_reindex_recovery.sql

DROPPED=$(Q -c "select count(*) from pg_class where relname='e10_obs_config_org_uq' and relkind='i';")
echo "  after recovery: e10_obs_config_org_uq present=$DROPPED (expect 0 — invalid allowlisted index dropped)"
[ "$DROPPED" = "0" ] || { echo "  FAIL(A): recovery did not drop the invalid allowlisted index"; FAIL=1; }

UNK_EXISTS=$(Q -c "select count(*) from pg_class where relname='_reidx_unknown_uq' and relkind='i';")
echo "  after recovery: _reidx_unknown_uq present=$UNK_EXISTS (expect 1 — non-allowlisted, refused)"
[ "$UNK_EXISTS" = "1" ] || { echo "  FAIL(B): recovery dropped a non-allowlisted index (refuse-unknown violated)"; FAIL=1; }

# --- Part C: rerun-migration equivalent — remove the fixture rows + rebuild the REAL (org,key) index -> valid ---
Q -c "delete from public.e10_obs_config where key in ('__reidx_a','__reidx_b');" >/dev/null
Q -c "create unique index concurrently if not exists e10_obs_config_org_uq on public.e10_obs_config (organization_id, key);" >/dev/null
REBUILT=$(Q -c "select indisvalid from pg_index where indexrelid='e10_obs_config_org_uq'::regclass;")
echo "  rebuilt e10_obs_config_org_uq: indisvalid=$REBUILT (expect t)"
[ "$REBUILT" = "t" ] || { echo "  FAIL(C): rebuild did not produce a valid index"; FAIL=1; }

# cleanup fixture
Q -c "drop table if exists _reidx_unknown;" >/dev/null

if [ "$FAIL" = "0" ]; then
  echo "[a6b reindex recovery proof] PASS (invalid allowlisted dropped, unknown refused, rebuild valid)"
else
  echo "[a6b reindex recovery proof] FAIL"; exit 1
fi
