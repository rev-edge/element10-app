# Element 10 — Operations (Foundation Gate A3)

## CI/CD
`.github/workflows/ci.yml` — on every push to `main` and every PR:
- **test job:** `npm install` (tests/), `supabase start` (ephemeral local stack — **proves A1 reproducibility on a clean stack continuously**), provision local users, then the pure-helper suites, local integration + RLS-adversarial suites (incl. `rls_test` — the roles/permissions engine, wired in A4 via `tests/provision_rls_users.js`, so the admin/member/viewer isolation surface is exercised on every push), browser suites, and a final `supabase db reset` (re-apply migrations cleanly). No production access.
- **deploy job:** runs ONLY on `main` and ONLY after `test` passes. Publishes **web assets only** (`index.html`, `open/overlay/companion.html`, `.nojekyll`) to GitHub Pages — never `tests/`, `supabase/`, `docs/`, or `.github/`. (The prior `static.yml` published the entire repo; removed.)

**Branch protection:** `main` requires the `test` check to pass before merge. Workflow: branch → PR → CI green → merge → auto-deploy.

## Supply-chain
The two external scripts are pinned to exact versions with Subresource Integrity + `crossorigin`:
`@supabase/supabase-js@2.110.5` and `xlsx@0.18.5` (index/overlay/companion.html). Bump the version AND recompute the `sha384-…` hash together (`curl -sL <url> | openssl dgst -sha384 -binary | openssl base64 -A`).

## Backups + restore
- **Daily backups:** on by default (Supabase Pro, 7-day retention) for production `element10`.
- **PITR (point-in-time recovery):** a paid add-on — NOT enabled (money-gate; flagged for decision).
- **Restore drill (executed 2026-07-15):** production inventory (35 items) was read and restored into the local stack, verified ($29,486 capital reproduced), and torn down — proving the prod→local recovery path. Full schema recovery is proven continuously by CI's `supabase db reset` + the A1 empty-diff.

## Observability / alerts
- **GitHub Actions:** a failed CI/deploy run notifies via GitHub's default Actions notifications (the repo owner's email/GitHub notifications). Watchable at the repo's Actions tab.
- **Supabase advisors:** security + performance advisors are checked via the Supabase dashboard / MCP `get_advisors` (the P0 recon-view issue was an advisor 0010 finding). Run before/after schema changes. The A4 sweep drove prod to **zero errors, zero undispositioned warnings** — every residual finding is justified in `docs/SECURITY.md` (the register). Re-check that register stays true after any schema change.

## Auth hardening (A4)
- **⚠ Leaked-password protection — MANUAL, pending.** Not settable via the Management API/CLI (it is a GoTrue
  dashboard toggle), so A4 could not automate it. **Trent, enable it here (one-time):**
  Supabase Dashboard → project `element10` → **Authentication** → **Providers** → **Email** →
  turn on **"Check against HaveIBeenPwned"** (a.k.a. leaked-password protection) → Save.
  This clears advisor `auth_leaked_password_protection`. (Do the same on `element10-staging` if desired.)
  - [ ] prod enabled   - [ ] staging enabled
- **Auth DB connection strategy:** left at absolute (10 connections). Fine at the current small instance size;
  switch to percentage-based allocation only when the instance is resized (advisor `auth_db_connections_absolute`,
  INFO — dispositioned in `docs/SECURITY.md`). Pooler config unchanged.

## The M4-incident guardrails (see docs/incidents/2026-07-15-m4-blob-clobber.md)
- Tests never default to production (`tests/env.js`; prod requires `E10_ALLOW_PROD=1`, read-only gate only).
- A `file://`/localhost client defaults to the LOCAL stack; only a hosted deployment (or an explicit override) uses prod.
- The client refuses mutations on a schema-version mismatch (`e10_schema_version()` handshake).
