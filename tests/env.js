// tests/env.js — resolves the DB target for tests. LOCAL is the DEFAULT; PRODUCTION is reachable ONLY with
// E10_ALLOW_PROD=1, and then ONLY the read-only gate (verify_inventory.js) may use it. No test carries a
// silent production URL/key. The local anon/service keys below are the STANDARD Supabase-local demo keys
// (public, non-secret, identical for every `supabase start`).
const LOCAL = {
  url: "http://127.0.0.1:54321",
  anon: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0",
  serviceKey: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMjk5Nn0.EGIM96RAZx35lJzdJsyH-qQwv8Hdp7fsn3W0YpN81IU",
};
const PROD_URL = "https://ddhkkumiyidorzmajwde.supabase.co";
const PROD_REF = "ddhkkumiyidorzmajwde";

// { url, anon, serviceKey, isProd } — LOCAL unless E10_ALLOW_PROD=1.
function target() {
  if (process.env.E10_ALLOW_PROD === "1") {
    const anon = process.env.E10_ANON;
    if (!anon) { console.error("E10_ALLOW_PROD=1 requires an explicit E10_ANON (no baked-in prod key)."); process.exit(2); }
    return { url: process.env.E10_URL || PROD_URL, anon, serviceKey: process.env.SUPABASE_SERVICE_KEY, isProd: true };
  }
  // LOCAL always uses the local demo keys — never the (production) SUPABASE_SERVICE_KEY from .env.local.
  return { url: process.env.E10_URL || LOCAL.url, anon: process.env.E10_ANON || LOCAL.anon, serviceKey: LOCAL.serviceKey, isProd: false };
}
// Mutating suites must never touch production.
function requireLocal(name) {
  const t = target();
  if (t.isProd) { console.error((name || "this suite") + " mutates data — refusing to run against PRODUCTION. Unset E10_ALLOW_PROD and run against the local stack (supabase start)."); process.exit(2); }
  return t;
}
module.exports = { target, requireLocal, LOCAL, PROD_URL, PROD_REF };
