// Element 10 — A6a.3 genuine two-connection concurrent verify-vs-reject proof.
//
// The race the reviewer wants proven: e10_verify_handle_claim takes a per-handle advisory lock; e10_reject_handle_claim
// does NOT. So a reject can commit (pending->rejected) while a verify is blocked waiting on the lock. This test controls
// the interleaving with two real Postgres connections:
//   A) holds the handle's advisory lock (simulating a verify mid-flight, before its post-lock reread)
//   B) calls verify() -> BLOCKS on A's lock
//   A) commits a reject() (no lock needed), releasing the advisory lock
//   B) unblocks -> its verify MUST fail; a rejected claim can never become verified.
// Determinism: we poll pg_locks until B is confirmed waiting on the advisory lock BEFORE A commits the reject, so the
// blocked-then-reject interleaving is actually exercised (not just the trivially-serial case).
//
// Requires the CI-provisioned local members + a running local stack. Run as: node tests/a6a3_verify_concurrent_test.js

const { Client } = require('pg');

const CONN = process.env.E10_LOCAL_DB_URL || 'postgresql://postgres:postgres@127.0.0.1:54322/postgres';
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const jwt = (uid) => JSON.stringify({ sub: uid, role: 'authenticated' });

async function main() {
  const setup = new Client({ connectionString: CONN });
  await setup.connect();

  const admin = (await setup.query('select user_id from public.e10_members order by created_at limit 1')).rows[0]?.user_id;
  if (!admin) throw new Error('no provisioned members — run provision_local_users.js first');

  // Seed a platform-admin identity (verify/reject are platform-admin gated) and a fresh pending claim.
  await setup.query('insert into public.e10_platform_admins(user_id) values ($1) on conflict do nothing', [admin]);
  await setup.query("delete from public.e10_viewer_handle_claims where handle_norm = 'a6a3race'");
  const claim = (await setup.query(
    `insert into public.e10_viewer_handle_claims(user_id, whatnot_handle, status, expires_at)
     values ($1, '@A6a3Race', 'pending', now() + interval '7 days') returning id, handle_norm`,
    [admin],
  )).rows[0];
  if (claim.handle_norm !== 'a6a3race') throw new Error('unexpected handle_norm: ' + claim.handle_norm);

  // A) hold the advisory lock for the handle
  const A = new Client({ connectionString: CONN });
  await A.connect();
  await A.query('begin');
  await A.query('select set_config($1,$2,true)', ['request.jwt.claims', jwt(admin)]);
  await A.query('select pg_advisory_xact_lock(hashtext($1))', [claim.handle_norm]);

  // B) fire verify() — it will block on A's lock
  const B = new Client({ connectionString: CONN });
  await B.connect();
  await B.query('begin');
  await B.query('select set_config($1,$2,true)', ['request.jwt.claims', jwt(admin)]);
  let bDone = false, bError = null;
  const bVerify = B.query('select public.e10_verify_handle_claim($1)', [claim.id])
    .then(() => { bDone = true; })
    .catch((e) => { bError = e; });

  // Deterministically wait until B is blocked on our advisory lock (bounded poll; no fixed sleep race).
  let blocked = false;
  for (let i = 0; i < 500; i++) {
    const n = (await setup.query("select count(*)::int n from pg_locks where locktype='advisory' and not granted")).rows[0].n;
    if (n >= 1) { blocked = true; break; }
    await sleep(10);
  }
  if (!blocked) throw new Error('B never blocked on the advisory lock — interleaving not achieved');
  if (bDone || bError) throw new Error('B resolved before the reject committed — not a real race');

  // A) reject (no lock) + commit -> releases the advisory lock, unblocking B
  await A.query('select public.e10_reject_handle_claim($1)', [claim.id]);
  await A.query('commit');

  // B) unblocks; verify MUST have failed
  await bVerify;
  await B.query('rollback').catch(() => {});

  const finalStatus = (await setup.query('select status from public.e10_viewer_handle_claims where id=$1', [claim.id])).rows[0].status;

  const failures = [];
  if (bDone) failures.push('verify SUCCEEDED against a concurrently-rejected claim');
  if (!bError || !/claim_not_pending_or_expired/.test(bError.message || '')) {
    failures.push('verify did not raise claim_not_pending_or_expired (got: ' + (bError && bError.message) + ')');
  }
  if (finalStatus !== 'rejected') failures.push('final claim status is ' + finalStatus + ', expected rejected');

  await setup.query('delete from public.e10_viewer_handle_claims where id=$1', [claim.id]);
  await A.end(); await B.end(); await setup.end();

  if (failures.length) {
    console.error('A6a.3 concurrent verify-vs-reject: FAIL\n  - ' + failures.join('\n  - '));
    process.exit(1);
  }
  console.log('A6a.3 concurrent verify-vs-reject: PASS (B blocked on lock; reject committed; verify raised claim_not_pending_or_expired; claim stayed rejected)');
}

main().catch((e) => { console.error('A6a.3 concurrent test ERROR:', e.message); process.exit(1); });
