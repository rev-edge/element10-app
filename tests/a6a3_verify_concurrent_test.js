// Element 10 — A6a.3 genuine two-connection concurrent verify-vs-reject proof.
//
// The race: e10_verify_handle_claim takes a per-handle advisory lock; e10_reject_handle_claim does NOT. So a reject can
// commit (pending->rejected) while a verify is blocked waiting on the lock. This test controls the interleaving with two
// real Postgres connections:
//   A) begins a txn and holds the handle's advisory lock (simulating a verify mid-flight, before its post-lock reread)
//   B) calls verify() asynchronously -> BLOCKS on A's lock
//   we prove B is lock-waiting (bounded poll of pg_locks) BEFORE continuing, so the interleaving is real, not serial
//   A) rejects() (no lock needed) and COMMITs, releasing the advisory lock
//   B) unblocks -> its verify MUST fail with claim_not_pending_or_expired; the claim MUST end 'rejected', never 'verified'
// The test fails if verify succeeds, if the claim becomes verified, if the blocking interleaving was not established,
// or if the bounded poll times out. Fixture-free: it removes the claim (and the platform_admins row IF it inserted one).
//
// Local (CI): uses a provisioned e10_members user. Run: node tests/a6a3_verify_concurrent_test.js
// Staging/other: set E10_DB_URL (connection string) and E10_ADMIN_UID (a pre-provisioned auth.users id to act as
// platform admin); the caller owns creating/deleting that auth user so the database is left bare.

const { Client } = require('pg');

const CONN = process.env.E10_DB_URL || process.env.E10_LOCAL_DB_URL || 'postgresql://postgres:postgres@127.0.0.1:54322/postgres';
const ADMIN_UID = process.env.E10_ADMIN_UID || null;
const LABEL = CONN.replace(/:\/\/[^@/]*@/, '://***@'); // never print credentials
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const jwt = (uid) => JSON.stringify({ sub: uid, role: 'authenticated' });

async function main() {
  const setup = new Client({ connectionString: CONN });
  await setup.connect();

  let admin = ADMIN_UID;
  if (!admin) {
    admin = (await setup.query('select user_id from public.e10_members order by created_at limit 1')).rows[0]?.user_id;
    if (!admin) throw new Error('no admin identity: set E10_ADMIN_UID or provision local members first');
  }

  // Seed a platform-admin identity; track whether WE inserted it so teardown is exact (fixture-free).
  const ins = await setup.query('insert into public.e10_platform_admins(user_id) values ($1) on conflict do nothing returning user_id', [admin]);
  const weInsertedAdmin = ins.rowCount === 1;

  await setup.query("delete from public.e10_viewer_handle_claims where handle_norm = 'a6a3race'");
  const claim = (await setup.query(
    `insert into public.e10_viewer_handle_claims(user_id, whatnot_handle, status, expires_at)
     values ($1, '@A6a3Race', 'pending', now() + interval '7 days') returning id, handle_norm`,
    [admin],
  )).rows[0];
  if (claim.handle_norm !== 'a6a3race') throw new Error('unexpected handle_norm: ' + claim.handle_norm);

  const A = new Client({ connectionString: CONN });
  const B = new Client({ connectionString: CONN });
  await A.connect();
  await B.connect();

  try {
    // A) hold the advisory lock for the handle
    await A.query('begin');
    await A.query('select set_config($1,$2,true)', ['request.jwt.claims', jwt(admin)]);
    await A.query('select pg_advisory_xact_lock(hashtext($1))', [claim.handle_norm]);

    // B) fire verify() — it must block on A's lock
    await B.query('begin');
    await B.query('select set_config($1,$2,true)', ['request.jwt.claims', jwt(admin)]);
    let bDone = false, bError = null;
    const bVerify = B.query('select public.e10_verify_handle_claim($1)', [claim.id])
      .then(() => { bDone = true; })
      .catch((e) => { bError = e; });

    // Prove B is lock-waiting BEFORE continuing (bounded — the test cannot hang).
    let waiting = 0;
    for (let i = 0; i < 500; i++) {
      waiting = (await setup.query("select count(*)::int n from pg_locks where locktype='advisory' and not granted")).rows[0].n;
      if (waiting >= 1) break;
      await sleep(10);
    }
    if (waiting < 1) throw new Error('TIMEOUT: B never blocked on the advisory lock — interleaving not established');
    if (bDone || bError) throw new Error('B resolved before the reject committed — not a real race');
    console.log(`  [proof] real lock wait established: ${waiting} ungranted advisory lock; B still pending (not resolved)`);

    // A) reject (no advisory lock) + COMMIT -> releases the lock, unblocking B
    await A.query('select public.e10_reject_handle_claim($1)', [claim.id]);
    await A.query('commit');

    // B) unblocks; verify must have failed
    await bVerify;
    await B.query('rollback').catch(() => {});

    const finalStatus = (await setup.query('select status from public.e10_viewer_handle_claims where id=$1', [claim.id])).rows[0].status;

    const failures = [];
    if (bDone) failures.push('verify SUCCEEDED against a concurrently-rejected claim');
    if (!bError || !/claim_not_pending_or_expired/.test(bError.message || '')) {
      failures.push('verify did not raise claim_not_pending_or_expired (got: ' + (bError && bError.message) + ')');
    }
    if (finalStatus === 'verified') failures.push('claim became verified');
    if (finalStatus !== 'rejected') failures.push('final claim status is ' + finalStatus + ', expected rejected');

    if (failures.length) throw new Error('A6a.3 concurrent verify-vs-reject FAILED:\n  - ' + failures.join('\n  - '));
    console.log(`  [proof] final claim status = ${finalStatus}; verify error = ${bError.message}`);
    console.log(`A6a.3 concurrent verify-vs-reject: PASS (B blocked on lock; reject committed; verify raised claim_not_pending_or_expired; claim stayed rejected) [${LABEL}]`);
  } finally {
    await A.query('rollback').catch(() => {});
    await B.query('rollback').catch(() => {});
    await setup.query('delete from public.e10_viewer_handle_claims where id=$1', [claim.id]).catch(() => {});
    if (weInsertedAdmin) await setup.query('delete from public.e10_platform_admins where user_id=$1', [admin]).catch(() => {});
    await A.end().catch(() => {});
    await B.end().catch(() => {});
    await setup.end().catch(() => {});
  }
}

main().catch((e) => { console.error('A6a.3 concurrent test ERROR: ' + e.message); process.exit(1); });
