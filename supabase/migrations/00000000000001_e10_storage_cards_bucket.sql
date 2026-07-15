-- Foundation Gate A1: storage lives in the `storage` schema, which `supabase db dump` (public schema)
-- does not capture — so the 'cards' bucket + its object policies are re-declared here, recovered verbatim
-- from the live ledger (migration card_images_storage_bucket, 20260703162925). Idempotent.

-- public bucket for card / inventory images
insert into storage.buckets (id, name, public)
  values ('cards','cards', true)
  on conflict (id) do update set public = true;

-- policies on storage.objects for the 'cards' bucket
drop policy if exists "cards public read" on storage.objects;
drop policy if exists "cards authed upload" on storage.objects;
drop policy if exists "cards authed update" on storage.objects;
drop policy if exists "cards authed delete" on storage.objects;

create policy "cards public read"   on storage.objects for select using (bucket_id = 'cards');
create policy "cards authed upload"  on storage.objects for insert to authenticated with check (bucket_id = 'cards');
create policy "cards authed update"  on storage.objects for update to authenticated using (bucket_id = 'cards') with check (bucket_id = 'cards');
create policy "cards authed delete"  on storage.objects for delete to authenticated using (bucket_id = 'cards');
