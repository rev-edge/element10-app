// Element 10 — real-RLS integration test.
// Drives the ACTUAL supabase-js client (incl. .upsert().select() = INSERT ... RETURNING)
// against the LIVE project's real RLS, with real member/viewer accounts.
// Provisioning + teardown of the fixtures is done out-of-band via the Supabase MCP.
const { createClient } = require('@supabase/supabase-js');

const URL = 'https://ddhkkumiyidorzmajwde.supabase.co';
const ANON = 'sb_publishable_wRoaFNiqpZJaEJkQvLpnUw_7bpcXllv';
const PW = 'Test!23456';

// ids passed in from provisioning (argv: A B C)
const A = process.argv[2], B = process.argv[3], C = process.argv[4];
const rowA = 'user:' + A, rowB = 'user:' + B;

let pass = 0, fail = 0;
function ok(name, cond, detail) {
  if (cond) { pass++; console.log('  PASS  ' + name); }
  else { fail++; console.log('  FAIL  ' + name + (detail ? '  — ' + detail : '')); }
}
function client() { return createClient(URL, ANON, { auth: { persistSession: false, autoRefreshToken: false } }); }
async function signIn(email) {
  const c = client();
  const { error } = await c.auth.signInWithPassword({ email, password: PW });
  if (error) throw new Error('sign-in failed for ' + email + ': ' + error.message);
  return c;
}

(async () => {
  const ca = await signIn('e10rls_a@example.com'); // admin
  const cb = await signIn('e10rls_b@example.com'); // member
  const cc = await signIn('e10rls_c@example.com'); // viewer
  console.log('Signed in A(admin), B(member), C(viewer).');

  // ── FUNCTIONALITY + INSERT ... RETURNING (the gotcha) ────────────────
  console.log('\n[functionality / INSERT...RETURNING]');
  {
    const { data, error } = await ca.from('e10_workspace')
      .upsert({ id: rowA, owner: A, data: { t: 'A-personal' }, rev: 1, updated_by: 'rlsA' })
      .select().maybeSingle();
    ok('admin/owner .upsert().select() RETURNS own row (INSERT...RETURNING)', !error && data && data.id === rowA, error && error.message);
  }
  {
    const { data, error } = await cb.from('e10_workspace')
      .upsert({ id: rowB, owner: B, data: { t: 'B-personal' }, rev: 1, updated_by: 'rlsB' })
      .select().maybeSingle();
    ok('member .upsert().select() RETURNS own row (INSERT...RETURNING)', !error && data && data.id === rowB, error && error.message);
  }
  {
    const { data, error } = await cb.from('e10_workspace').select('id,data').eq('id', rowB).maybeSingle();
    ok('member can read back own personal row', !error && data && data.data && data.data.t === 'B-personal', error && error.message);
  }
  {
    const { data, error } = await cb.from('e10_workspace').select('id').eq('id', 'shared').maybeSingle();
    ok('member can read shared row', !error && data && data.id === 'shared', error && error.message);
  }
  {
    const { data, error } = await ca.from('e10_workspace').select('id').eq('id', rowB).maybeSingle();
    ok('admin can read another member personal row', !error && data && data.id === rowB, error && error.message);
  }

  // ── ISOLATION (must NOT read/write across tenants) ───────────────────
  console.log('\n[isolation]');
  {
    const { data, error } = await cb.from('e10_workspace').select('id').eq('id', rowA).maybeSingle();
    ok('member CANNOT read another member personal row', !error && data === null, 'got: ' + JSON.stringify(data) + (error ? ' err:' + error.message : ''));
  }
  {
    // member tries to write a row owned by A -> with_check must reject
    const { data, error } = await cb.from('e10_workspace')
      .upsert({ id: rowA, owner: A, data: { hijack: true }, rev: 999, updated_by: 'rlsB' }).select();
    ok('member CANNOT upsert a row owned by someone else', !!error && (data === null || data.length === 0), 'unexpectedly succeeded');
  }
  {
    const { data, error } = await cc.from('e10_workspace').select('id');
    ok('viewer sees ZERO e10_workspace rows (no shared/universal/personal)', !error && Array.isArray(data) && data.length === 0, 'got ' + (data ? data.length : '?') + ' rows' + (error ? ' err:' + error.message : ''));
  }
  {
    const { data, error } = await cc.from('e10_workspace')
      .upsert({ id: 'shared', data: { hijack: true }, rev: 999, updated_by: 'rlsC' }).select();
    ok('viewer CANNOT write shared', !!error && (data === null || data.length === 0), 'unexpectedly succeeded');
  }

  // ── SESSIONS: viewer cannot read an unlinked session ─────────────────
  console.log('\n[sessions]');
  let sess = null;
  {
    const { data, error } = await ca.from('e10_break_sessions').insert({ streamer_uid: A, name: 'RLS test session' }).select().maybeSingle();
    ok('admin creates a session (INSERT...RETURNING own session)', !error && data && data.id, error && error.message);
    sess = data;
  }
  if (sess) {
    const { data: sl } = await ca.from('e10_break_slots').insert({ session_id: sess.id, label: 'Spot 1', position: 0 }).select().maybeSingle();
    ok('admin creates a slot in own session', !!sl, 'slot insert failed');
    {
      const { data, error } = await cc.from('e10_break_sessions').select('id').eq('id', sess.id).maybeSingle();
      ok('viewer CANNOT read an unlinked session', !error && data === null, 'got: ' + JSON.stringify(data));
    }
    {
      const { data } = await cc.from('e10_break_slots').select('id').eq('session_id', sess.id);
      ok('viewer CANNOT read slots of an unlinked session', Array.isArray(data) && data.length === 0, 'got ' + (data ? data.length : '?'));
    }
    {
      const { data } = await cc.from('e10_break_events').select('id').eq('session_id', sess.id);
      ok('viewer CANNOT read events of an unlinked session', Array.isArray(data) && data.length === 0, 'got ' + (data ? data.length : '?'));
    }
    {
      const { data } = await cb.from('e10_break_sessions').select('id').eq('id', sess.id).maybeSingle();
      ok('member (non-owner) CANNOT read another streamer session', data === null, 'got: ' + JSON.stringify(data));
    }
  }

  // ── ONBOARDING RPC gating ────────────────────────────────────────────
  console.log('\n[onboarding rpc gating]');
  {
    const { error } = await cb.rpc('e10_add_member', { p_email: 'whoever@example.com' });
    ok('non-admin call to e10_add_member is REJECTED', !!error, 'no error raised');
  }
  {
    const { data, error } = await ca.rpc('e10_add_member', { p_email: 'nonexistent_e10rls_zzz@example.com' });
    ok('admin call to e10_add_member passes gate (no_auth_user, no mutation)', !error && data === 'no_auth_user', (error ? error.message : 'got ' + JSON.stringify(data)));
  }
  {
    const { error } = await cc.rpc('e10_set_role', { p_user: A, p_role: 'member' });
    ok('viewer call to e10_set_role is REJECTED', !!error, 'no error raised');
  }

  // cleanup the session we created (teardown of auth users handled via MCP)
  if (sess) { try { await ca.from('e10_break_sessions').delete().eq('id', sess.id); } catch (e) {} }

  console.log('\n──────────────────────────────');
  console.log('RESULT: ' + pass + ' passed, ' + fail + ' failed');
  process.exit(fail ? 1 : 0);
})().catch(e => { console.error('SUITE ERROR:', e.message); process.exit(2); });
