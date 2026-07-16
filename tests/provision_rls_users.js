// tests/provision_rls_users.js — (re)provision the THREE rls_test fixtures in the LOCAL Supabase stack
// (idempotent) via the admin API. rls_test.js signs in as these three with a fixed local test password and
// takes their user-ids as argv. Roles model the RLS surface:
//   e10rls_a — ADMIN  (e10_members role=admin)
//   e10rls_b — MEMBER (e10_members role=member)
//   e10rls_c — VIEWER (NO e10_members row → e10_is_org() false → sees zero org rows; the isolation case)
// The password is the same fixed local constant rls_test.js expects (a local-stack test value, not a secret,
// same posture as the CI-local passwords in ci.yml). LOCAL-only: refuses if E10_ALLOW_PROD=1.
// Prints ONLY the three user-ids (space-separated) to STDOUT so CI can do: IDS=$(node ...); logs go to STDERR.
//   Run: (source .env.local) node tests/provision_rls_users.js
const { createClient } = require('@supabase/supabase-js');
const { requireLocal } = require('./env');
const t = requireLocal('provision_rls_users');
if (!t.serviceKey) { console.error('local service key unavailable (is the stack up? `supabase start`)'); process.exit(2); }

const PW = 'Test!23456'; // matches rls_test.js
const specs = [
  { email: 'e10rls_a@example.com', role: 'admin',  member: true  },
  { email: 'e10rls_b@example.com', role: 'member', member: true  },
  { email: 'e10rls_c@example.com', role: 'viewer', member: false }, // deliberately NOT in e10_members
];

(async () => {
  const svc = createClient(t.url, t.serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const ids = [];
  for (const s of specs) {
    let uid = null;
    for (let page = 1; page <= 20 && !uid; page++) {
      const { data, error } = await svc.auth.admin.listUsers({ page, perPage: 200 });
      if (error) { console.error('listUsers:', error.message); process.exit(3); }
      const hit = (data.users || []).find(u => (u.email || '').toLowerCase() === s.email.toLowerCase());
      if (hit) uid = hit.id;
      if (!data.users || data.users.length < 200) break;
    }
    if (uid) {
      const { error } = await svc.auth.admin.updateUserById(uid, { password: PW, email_confirm: true });
      if (error) { console.error('update ' + s.email + ':', error.message); process.exit(3); }
      console.error('updated  ' + s.email + ' (' + s.role + ')');
    } else {
      const { data, error } = await svc.auth.admin.createUser({ email: s.email, password: PW, email_confirm: true });
      if (error) { console.error('create ' + s.email + ':', error.message); process.exit(3); }
      uid = data.user.id;
      console.error('created  ' + s.email + ' (' + s.role + ')');
    }
    if (s.member) {
      const { error: me } = await svc.from('e10_members').upsert({ user_id: uid, email: s.email, role: s.role }, { onConflict: 'user_id' });
      if (me) { console.error('member upsert ' + s.email + ':', me.message); process.exit(3); }
    } else {
      // ensure the viewer has NO membership row (isolation fixture)
      await svc.from('e10_members').delete().eq('user_id', uid);
    }
    ids.push(uid);
  }
  console.error('rls provisioning ok');
  process.stdout.write(ids.join(' ') + '\n'); // STDOUT: the argv for rls_test.js
})().catch(e => { console.error(e); process.exit(3); });
