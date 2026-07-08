# Real-RLS integration test

`rls_test.js` drives the **actual** `@supabase/supabase-js` client (including
`.insert().select()` / `.upsert().select()` — i.e. `INSERT ... RETURNING`) against the
**live** project's real Row Level Security, using **real** member and viewer accounts.
It does NOT stub the client — that is exactly the gap that let a prior RLS regression ship.

It asserts three things:
- **Functionality + INSERT...RETURNING** — the row owner (and admin) can create a
  `user:<uid>` workspace row and read it back. The returned row is checked against the
  SELECT policy, which must be satisfied by a *direct* `owner = auth.uid()` column check
  (not only a self-referential STABLE SECURITY DEFINER function) or the insert fails.
- **Isolation** — a member cannot read another member's personal row or write a row they
  don't own; a viewer sees zero `e10_workspace` rows and cannot read unlinked
  sessions/slots/events.
- **Onboarding RPC gating** — a non-admin call to `e10_add_member` / `e10_set_role` is
  rejected; an admin call passes the gate.

## Running it

1. Provision three disposable auth users in the target project (admin A, member B, viewer C).
   Because Supabase's GoTrue admin API is not exposed here, provision via SQL against
   `auth.users` + `auth.identities` (bcrypt password, `email_confirmed_at = now()`), then
   insert the matching `public.e10_members` (A=admin, B=member) and `public.e10_viewers` (C)
   rows. See the provisioning + teardown SQL used in the build log; emails
   `e10rls_a/b/c@example.com`, password `Test!23456`.
2. `cd tests && npm install @supabase/supabase-js@2`
3. `node rls_test.js <A_uuid> <B_uuid> <C_uuid>`  — exits non-zero if any assertion fails.
4. **Tear down** the fixtures afterward (delete the three `auth.users` rows — this cascades
   `e10_members` — plus `e10_viewers`, `auth.identities`, and any `user:<A>` / `user:<B>`
   workspace rows and test sessions).

The publishable (anon) key and project URL are read from the constants at the top of the
script — the same values the client app ships. No service-role key is used.
