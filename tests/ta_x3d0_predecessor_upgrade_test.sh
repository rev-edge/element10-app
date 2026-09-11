#!/usr/bin/env bash
set -euo pipefail

restore_head() {
  supabase db reset >/dev/null 2>&1
}
trap restore_head EXIT

supabase db reset --version 20260911190001 >/dev/null 2>&1
psql 'postgresql://postgres:postgres@127.0.0.1:54322/postgres' -v ON_ERROR_STOP=1 \
  -f tests/ta_x3d0_predecessor_setup.sql
supabase migration up --local >/dev/null 2>&1
psql 'postgresql://postgres:postgres@127.0.0.1:54322/postgres' -v ON_ERROR_STOP=1 \
  -f tests/ta_x3d0_predecessor_assert.sql

restore_head
trap - EXIT
