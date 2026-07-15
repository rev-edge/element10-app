// tests/provision_local_users.js — (re)provision e10adm / e10mem / e10gate in the LOCAL Supabase stack
// (idempotent) via the admin API, using the local service key from env.js. Passwords come from .env.local
// (E10_*_PW) and are NEVER printed. LOCAL-only: refuses if E10_ALLOW_PROD=1. This is what lets the mutation
// and browser suites sign in against local. Run: (source .env.local) node tests/provision_local_users.js
const { createClient } = require('@supabase/supabase-js');
const { requireLocal } = require('./env');
const t = requireLocal('provision_local_users');
if (!t.serviceKey) { console.error('local service key unavailable (is the stack up? `supabase start`)'); process.exit(2); }
const specs = [
  { email: process.env.E10_ADMIN_EMAIL, pw: process.env.E10_ADMIN_PW, role: 'admin' },
  { email: process.env.E10_MEMBER_EMAIL, pw: process.env.E10_MEMBER_PW, role: 'member' },
  { email: process.env.E10_GATE_EMAIL, pw: process.env.E10_GATE_PW, role: 'member' },
];
for (const s of specs) if (!s.email || !s.pw) { console.error('missing email/pw for a ' + s.role + ' account (.env.local)'); process.exit(2); }

(async () => {
  const svc = createClient(t.url, t.serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
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
      const { error } = await svc.auth.admin.updateUserById(uid, { password: s.pw, email_confirm: true });
      if (error) { console.error('update ' + s.email + ':', error.message); process.exit(3); }
      console.log('updated  ' + s.email + ' (' + s.role + ')');
    } else {
      const { data, error } = await svc.auth.admin.createUser({ email: s.email, password: s.pw, email_confirm: true });
      if (error) { console.error('create ' + s.email + ':', error.message); process.exit(3); }
      uid = data.user.id;
      console.log('created  ' + s.email + ' (' + s.role + ')');
    }
    const { error: me } = await svc.from('e10_members').upsert({ user_id: uid, email: s.email, role: s.role }, { onConflict: 'user_id' });
    if (me) { console.error('member upsert ' + s.email + ':', me.message); process.exit(3); }
  }
  console.log('local provisioning ok');
})().catch(e => { console.error(e); process.exit(3); });
