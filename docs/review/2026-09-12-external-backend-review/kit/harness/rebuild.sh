#!/bin/bash
# Rebuild the local review database from scratch: shim + all migrations (autocommit, like the Supabase CLI) + seed.
S=$REVIEW_SCRATCH
cd $REPO
ADMIN="postgresql://postgres:postgres@127.0.0.1:54322/template1"
DB="postgresql://postgres:postgres@127.0.0.1:54322/postgres"
UPTO="${1:-}"   # optional: stop after this migration version (for the predecessor upgrade test)
psql "$ADMIN" -q -c "select pg_terminate_backend(pid) from pg_stat_activity where datname='postgres' and pid<>pg_backend_pid()" >/dev/null
psql "$ADMIN" -q -c "drop database if exists postgres" && psql "$ADMIN" -q -c "create database postgres"
for r in supabase_admin anon authenticated service_role authenticator supabase_auth_admin supabase_storage_admin dashboard_user; do psql "$ADMIN" -q -c "drop owned by $r cascade; drop role if exists $r" 2>/dev/null; done
psql "$DB" -v ON_ERROR_STOP=1 -q -f $S/supabase_shim.sql 2>&1 | grep -v "wal_level\|Set wal_level" 
: > $S/migrate.log
for f in $(ls supabase/migrations/*.sql | sort); do
  v=$(basename $f | cut -d_ -f1); n=$(basename $f .sql | cut -d_ -f2-)
  if [ -n "$UPTO" ] && [ "$v" \> "$UPTO" ]; then continue; fi
  src=$f; [ "$v" = "00000000000000" ] && src=$S/baseline_pg16.sql
  if ! psql "$DB" -v ON_ERROR_STOP=1 -q -f "$src" >> $S/migrate.log 2>&1; then echo "FAILED: $f"; tail -8 $S/migrate.log; exit 1; fi
  psql "$DB" -q -c "insert into supabase_migrations.schema_migrations(version,name) values ('$v','$n')"
done
psql "$DB" -v ON_ERROR_STOP=1 -q -f supabase/seed.sql >> $S/migrate.log 2>&1 || { echo SEED-FAILED; exit 1; }
echo "REBUILT: $(psql "$DB" -tAc "select count(*) from supabase_migrations.schema_migrations") migrations applied"
