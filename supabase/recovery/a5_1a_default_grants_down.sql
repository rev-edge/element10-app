-- Recovery / down path for migration 20260716110000_e10_lock_default_function_grants.sql (A5.1a).
-- Immutable-migration convention: the applied migration is never edited; its reversal lives here.
--
-- ⚠ Running this REOPENS the default-function-privileges factory: every newly created public function is again
-- born EXECUTE-able by anon (via built-in PUBLIC) and authenticated. Only run to unwind A5.1a deliberately.
-- Run as the migration role (postgres).

begin;

-- restore the database-level built-in PUBLIC EXECUTE default
alter default privileges grant execute on functions to public;

-- restore Supabase's explicit schema-level anon/authenticated default grants
alter default privileges in schema public grant execute on functions to anon, authenticated;

-- restore the two invoker helpers to their pre-A5.1a PUBLIC-executable state
grant execute on function public.e10_slot_cards(uuid, jsonb, integer) to anon;
grant execute on function public.e10_slot_partition(uuid, jsonb)       to anon;

commit;
