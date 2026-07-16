-- Foundation Gate A4a, item 3 — scope the cards-bucket listing (advisor 0025 public_bucket_allows_listing).
-- The 'cards' bucket is public=true, so object image URLs resolve WITHOUT any storage.objects SELECT policy
-- (public buckets bypass RLS for object GET-by-URL) — card images keep working untouched. The broad
-- "cards public read" SELECT policy only grants the LIST/search API, and it currently applies to anon,
-- letting anyone enumerate every object. Re-scope that SELECT policy TO authenticated (members can list;
-- anon still fetches images by URL but cannot enumerate the bucket). Touches zero data / zero objects.

begin;

drop policy if exists "cards public read" on storage.objects;
create policy "cards public read" on storage.objects
  for select to authenticated using (bucket_id = 'cards');

commit;

-- ============================================================================
-- DOWN (restore the prior public/anon-listable form):
-- begin;
-- drop policy if exists "cards public read" on storage.objects;
-- create policy "cards public read" on storage.objects for select using (bucket_id = 'cards');
-- commit;
