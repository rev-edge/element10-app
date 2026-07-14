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

## Inventory hardening tests (M3.1) — credentials via environment only

No credentials are committed. Provide them via env vars:

- **`tests/verify_inventory.js`** — the inventory GATE (baseline 35 / 223 / 21 / $29,486, recon
  drift 0). Reads a STANDING gate member:
  `E10_GATE_EMAIL=… E10_GATE_PW=… node tests/verify_inventory.js`
- **`tests/m31_test.js`** — adversarial + blocker-2 authorization + concurrent same-key + mid-batch
  atomicity, through real JWT/PostgREST. Needs an admin + a member:
  `E10_ADMIN_EMAIL=… E10_ADMIN_PW=… E10_MEMBER_EMAIL=… E10_MEMBER_PW=… node tests/m31_test.js`
- `E10_URL` / `E10_ANON` are optional (default to the app's public project URL + publishable key —
  those are public, they ship in `index.html`; only the passwords/emails are secret).

**Standing gate member:** `e10gate@example.com` (role `member`) is provisioned permanently for the
gate; its password is held only in the environment (never committed). `m31_test.js` reuses it as the
member and needs a disposable admin provisioned per run.

**Provisioning gotcha:** a raw `auth.users` insert leaves GoTrue token columns NULL → sign-in returns
HTTP 500 (empty body). Set `confirmation_token / recovery_token / email_change /
email_change_token_new / email_change_token_current / phone_change / phone_change_token /
reauthentication_token = ''` and `is_sso_user / is_anonymous = false` at insert.
