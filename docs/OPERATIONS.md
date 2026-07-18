# Element 10 — Operations (Foundation Gate A3)

## CI/CD
`.github/workflows/ci.yml` — on every push to `main` and every PR:
- **test job:** `npm ci` (tests/, lockfile-exact), `supabase start` (ephemeral local stack — **proves A1 reproducibility on a clean stack continuously**), provision local users, then the pure-helper suites (incl. the `schema_gate_test` comparator), local integration + RLS-adversarial suites (incl. `rls_test` — the roles/permissions engine, wired in A4 via `tests/provision_rls_users.js`), browser suites, a final `supabase db reset` (re-apply migrations cleanly), and the **default-privileges regression probe** (`tests/probe_defpriv.sql` — new functions born locked + zero anon-executable functions). No production access.
- **deploy job:** runs ONLY on `main` and ONLY after `test` passes. Publishes **web assets only** (`index.html`, `open/overlay/companion.html`, `.nojekyll`) to GitHub Pages — never `tests/`, `supabase/`, `docs/`, or `.github/`. (The prior `static.yml` published the entire repo; removed.)

**Branch protection:** `main` requires the `test` check to pass before merge. Workflow: branch → PR → CI green → merge → auto-deploy.

## Release runbook (schema-safe ordering)
Every DB change flows through the pipeline; the client never ships against an incompatible live schema:
1. **Staging migration** — `supabase db push` to `element10-staging`.
2. **Staging verification** — advisors clean + probes/suite against staging.
3. **Approved production migration** — `supabase db push` to prod (the ledger is reconciled since A4, so push applies only pending migrations). If the change alters the client-visible contract, bump `SCHEMA_VERSION` in `index.html` **and** the `e10_schema_version()` migration together.
4. **Production schema verification** — the CI **`schema-gate` job** (on `main`, before deploy) signs in as the least-privilege `production`-environment gate account and asserts the to-be-deployed client's `SCHEMA_VERSION` == live `e10_schema_version()`. `deploy` has `needs: [test, schema-gate]`, so a contract mismatch **blocks the deploy**.
5. **Client deploy** — Pages publishes web assets only.

**Two layers of the same guarantee.** CI's `schema-gate` is the *release-time* backstop (proves CONTRACT compatibility — client vs DB version — **not** migration completeness); it is exercised on every PR in pure-unit form by `tests/schema_gate_test.js` (the "gate bites" proof, since the live job only runs on `main`). The client's fail-closed `_schemaHandshake()` / `_schemaContract()` is the *runtime* backstop (a mismatched client goes read-only). Because the platform runs 24/7 with no maintenance windows, deploys are **zero-downtime** and this gate is what makes an out-of-order client/schema ship impossible.

**Gate account:** `e10schemagate@example.com` — authenticated, **no `e10_members` row** (may call `e10_schema_version()`, reads nothing else). Its password + the prod anon key + `E10_ALLOW_PROD` live as secrets in the protected `production` GitHub environment (never in logs). Rotate via the same admin-API provisioning + `gh secret set --env production`.

## Staging apply-path guard (A6/A6b — the linked-project hazard)
The Supabase CLI is linked to **production** (`supabase/.temp/project-ref` = `ddhkkumiyidorzmajwde`). Which CLI
command hits what:
- **`supabase db push` (bare)** → pushes migrations to the **linked project = production**. **PROHIBITED** while the
  link points at prod (the A6a.3 near-miss).
- **`supabase db reset` (bare)** → resets the **LOCAL** dev stack only (safe; it does not touch any remote).
- **`supabase db reset --linked`** → destructively **resets the linked REMOTE project** (= production, right now).
  **NEVER** run this while linked to prod — it would wipe the live database.

While Foundation Gate A6 is **staging-only** (zero prod changes until A10), every **remote** DB write MUST go through
an **explicit target**, never the linked project:
- **MCP** `apply_migration` / `execute_sql` with explicit `project_id: csmbjfmoxkexcyssntbg`; after `apply_migration`, reconcile the recorded `schema_migrations.version` to the repo filename (it stamps its own wall-clock version), or
- `supabase db push --db-url "postgresql://postgres.csmbjfmoxkexcyssntbg:<SUPABASE_STAGING_DB_PASSWORD>@aws-0-us-east-1.pooler.supabase.com:5432/postgres"` (session pooler, port 5432 — session mode so advisory locks/`SET`s work; the transaction pooler on 6543 does **not**), or
- direct `psql` / `\copy` against that same staging session-pooler URL.

**Rules:** never run a bare `supabase db push` (or `db reset --linked`) while the link points at prod; a bare
`db reset` is fine (LOCAL only). Prove the target before each remote apply with a harmless read
(`select current_database()` + a staging-only marker such as the presence of the `e10` schema / `e10_organizations`);
take staging secrets from `.env.local` (`SUPABASE_STAGING_DB_PASSWORD`) and stop if missing; production contact stays
**read-only** under `E10_ALLOW_PROD` until A10.

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

## Auth hardening
- **Leaked-password protection — ENABLED (prod, 2026-07-16).** Supabase Auth now checks passwords against
  HaveIBeenPwned; advisor `auth_leaked_password_protection` is cleared on prod. It is a GoTrue **dashboard**
  toggle (not settable via Management API/CLI). To re-enable/verify elsewhere: Dashboard → project →
  **Authentication → Attack Protection → "Leaked password protection" (checks against HaveIBeenPwned) → Save.**
  (Enable on `element10-staging` too if desired.)
- **Auth DB connection strategy:** left at absolute (10 connections). Fine at the current small instance size;
  switch to percentage-based allocation only when the instance is resized (advisor `auth_db_connections_absolute`,
  INFO — dispositioned in `docs/SECURITY.md`). Pooler config unchanged.

## CI flakes / infrastructure protocol
- **Edge-runtime `Bus error (core dumped)` during `supabase start`.** Seen intermittently on the CI runner while
  the `supabase_edge_runtime` container boots (unrelated to app code — migrations apply fine). **Protocol:** a
  re-run is a *workaround, not a fix*. On any recurrence, **capture the failed job's container logs** (the run's
  `Start local Supabase` step already prints them) and **open an infrastructure issue** tracking the frequency /
  runner image / CLI version, rather than silently re-running. (We don't use edge functions; disabling the
  edge-runtime container in CI's `config.toml` is the candidate fix if it recurs often.)

## The M4-incident guardrails (see docs/incidents/2026-07-15-m4-blob-clobber.md)
- Tests never default to production (`tests/env.js`; prod requires `E10_ALLOW_PROD=1`, read-only gate only).
- A `file://`/localhost client defaults to the LOCAL stack; only a hosted deployment (or an explicit override) uses prod.
- The client refuses mutations on a schema-version mismatch (`e10_schema_version()` handshake).
