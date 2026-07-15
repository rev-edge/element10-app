-- Foundation Gate A1: reproduce production's TIGHTENED table grants. Supabase-local default privileges
-- (ALTER DEFAULT PRIVILEGES … GRANT TO anon, authenticated) re-add broad grants — REFERENCES, TRIGGER,
-- TRUNCATE, MAINTAIN — that production had REVOKED. pg_dump emits the RESULTING grants, not the revokes,
-- so the schema dump alone can't reproduce a tightened grant. This matters: TRUNCATE is NOT governed by
-- RLS, so a stray anon TRUNCATE grant is a real hole. Match production exactly (service_role GRANT ALL is
-- left intact; authenticated keeps SELECT where production grants it).
revoke all on table public.e10_inventory_items from anon, authenticated;
grant select on table public.e10_inventory_items to authenticated;
revoke all on table public.e10_inventory_reservations from anon, authenticated;
grant select on table public.e10_inventory_reservations to authenticated;
revoke all on table public.e10_mutation_receipts from anon, authenticated;
