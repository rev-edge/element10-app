#!/usr/bin/env bash
# Element 10 — A6c.4 two-connection workspace CAS race (carried A6c.3 disclosure).
# Proves the optimistic-concurrency CAS serializes two GENUINE concurrent writers: connection A locks the row and commits
# a rev bump; connection B, racing the same `... set rev=rev+1 where rev=N`, blocks on A's row lock, then re-evaluates the
# stale predicate against the committed row (rev=N+1) and matches 0 rows -> the merge signal. Exactly one CAS wins.
# The race is run as the table role to isolate the concurrency mechanism from RLS (RLS is proven in the gate); it operates
# on a dedicated throwaway row and cleans it up.
set -uo pipefail
DB="postgresql://postgres:postgres@127.0.0.1:54322/postgres"
ORG='e1000000-0000-4000-8000-0000000000a6'

cleanup(){ psql "$DB" -q -c "delete from public.e10_workspace where id='a6c4_race';" >/dev/null 2>&1 || true; }
trap cleanup EXIT

psql "$DB" -q -c "insert into public.e10_workspace(id,organization_id,rev,data) values ('a6c4_race','$ORG',5,'{}'::jsonb) on conflict (id) do update set rev=5, organization_id='$ORG';" >/dev/null

# Connection A: lock the row at rev=5 (uncommitted), hold ~2s, then commit the bump to 6.
( psql "$DB" -q >/dev/null 2>&1 <<SQL
begin;
update public.e10_workspace set rev=rev+1 where id='a6c4_race' and rev=5;
select pg_sleep(2);
commit;
SQL
) &
APID=$!

sleep 0.5
# Connection B: the racing CAS at the same rev=5. Blocks on A's row lock; after A commits (rev=6), B's predicate no longer
# matches -> 0 rows. (READ COMMITTED re-check.)
BCOUNT=$(psql "$DB" -tA <<SQL
with u as (update public.e10_workspace set rev=rev+1 where id='a6c4_race' and rev=5 returning 1)
select count(*) from u;
SQL
)
wait "$APID"
FINAL=$(psql "$DB" -tAc "select rev from public.e10_workspace where id='a6c4_race';")

BCOUNT="$(echo "$BCOUNT" | tr -d '[:space:]')"; FINAL="$(echo "$FINAL" | tr -d '[:space:]')"
echo "stale writer B affected rows = $BCOUNT (want 0); final rev = $FINAL (want 6 = exactly one CAS win)"
if [ "$BCOUNT" = "0" ] && [ "$FINAL" = "6" ]; then
  echo "A6c.4 CAS race: PASS (one writer wins rev 5->6; the concurrent stale writer matches 0 rows -> merge)"
  exit 0
else
  echo "A6c.4 CAS race: FAIL"
  exit 1
fi
