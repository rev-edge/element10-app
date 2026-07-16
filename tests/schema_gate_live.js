// Element 10 — LIVE production schema gate (runs in CI on `main` ONLY, before deploy; gates the deploy job).
// Proves client/DB CONTRACT compatibility against the REAL production database: the SCHEMA_VERSION the
// to-be-deployed client (index.html) is built for must exactly equal live e10_schema_version(). Fails the
// deploy if they diverge, so a client is never shipped against an incompatible live schema. The client's
// fail-closed _schemaHandshake() remains the runtime backstop; this is the release-time backstop.
//   Signs in as a DEDICATED LEAST-PRIVILEGE gate account (authenticated, NO org membership → may call
//   e10_schema_version() and read nothing else). Credentials from env ONLY; nothing is printed.
//     E10_ALLOW_PROD=1  E10_ANON=<prod anon>  E10_SCHEMA_GATE_EMAIL / E10_SCHEMA_GATE_PW
//   Run: node tests/schema_gate_live.js
const fs = require('fs');
const path = require('path');
const { createClient } = require('@supabase/supabase-js');
const { target } = require('./env');

const t = target();
if (!t.isProd) { console.error('schema_gate_live checks PRODUCTION — run with E10_ALLOW_PROD=1 and E10_ANON set.'); process.exit(2); }
const EMAIL = process.env.E10_SCHEMA_GATE_EMAIL, PW = process.env.E10_SCHEMA_GATE_PW;
if (!EMAIL || !PW) { console.error('Set E10_SCHEMA_GATE_EMAIL and E10_SCHEMA_GATE_PW (the least-privilege prod gate account).'); process.exit(2); }

const src = fs.readFileSync(path.join(__dirname, '..', 'index.html'), 'utf8');
const mv = src.match(/const SCHEMA_VERSION\s*=\s*'([^']+)'/);
if (!mv) { console.error('SCHEMA_VERSION not found in index.html'); process.exit(2); }
const CLIENT_VERSION = mv[1];

(async () => {
  const c = createClient(t.url, t.anon, { auth: { persistSession: false, autoRefreshToken: false } });
  const { error: se } = await c.auth.signInWithPassword({ email: EMAIL, password: PW });
  if (se) { console.error('gate sign-in failed:', se.message); process.exit(2); }
  const { data, error } = await c.rpc('e10_schema_version');
  if (error) { console.error('e10_schema_version() call failed:', error.message); process.exit(1); }
  const live = String(data);
  if (live !== CLIENT_VERSION) {
    console.error('SCHEMA GATE FAIL — client built for "' + CLIENT_VERSION + '" but production reports "' + live + '". Deploy blocked.');
    process.exit(1);
  }
  console.log('SCHEMA GATE PASS — client and production both at "' + CLIENT_VERSION + '".');
  process.exit(0);
})().catch(e => { console.error('schema gate error:', e.message); process.exit(1); });
