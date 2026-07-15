// Element 10 — M4 realtime cutover test. The inventory read source is now relational (e10_inv_list) and
// a second session must see per-row changes via realtime WITHOUT a reload. Session B = a headless browser
// running the M4 client (local file:// unless E10_APP_URL is set); Session A = a supabase-js client issuing
// the authoritative RPCs. Asserts: initial load from e10_inv_list; add/edit(qty)/reserve/delete each patch
// B's in-memory S.inventory via realtime; out-of-order + duplicate events converge (re-fetch-latest, no
// dupes/corruption). Service-role teardown. Credentials from env ONLY:
//   E10_MEMBER_EMAIL/PW (session B page) + E10_ADMIN_EMAIL/PW (session A mutations)
//   + E10_URL/SUPABASE_SERVICE_KEY/E10_CLEANUP_PROJECT_REF (teardown).
//   Run: (source .env.local) node tests/m4_realtime_test.js
const puppeteer = require('puppeteer');
const { createClient } = require('@supabase/supabase-js');
const { serviceCleanup } = require('./cleanup');
const { target } = require('./env');
const { url: URL, anon: ANON } = target(); // LOCAL by default; the browser client (file://) also connects to LOCAL
const APP = process.env.E10_APP_URL || ('file://' + require('path').resolve(__dirname, '..', 'index.html'));
const MEMBER = process.env.E10_MEMBER_EMAIL, MEMBER_PW = process.env.E10_MEMBER_PW;
const ADMIN = process.env.E10_ADMIN_EMAIL, ADMIN_PW = process.env.E10_ADMIN_PW;
if (!MEMBER || !MEMBER_PW || !ADMIN || !ADMIN_PW) { console.error('Set E10_MEMBER_EMAIL/PW and E10_ADMIN_EMAIL/PW.'); process.exit(2); }

let pass = 0, fail = 0;
const T = (n, ok, d) => ok ? (pass++, console.log('  PASS ' + n)) : (fail++, console.log('  FAIL ' + n + (d !== undefined ? '  → ' + JSON.stringify(d) : '')));
const sleep = ms => new Promise(r => setTimeout(r, ms));
const rpc = (c, fn, a) => c.rpc(fn, a).then(r => r.error ? { ok: false, msg: r.error.message } : r.data);

(async () => {
  // Session A — authoritative mutations
  const A = createClient(URL, ANON, { auth: { persistSession: false, autoRefreshToken: false } });
  const { error: ae } = await A.auth.signInWithPassword({ email: ADMIN, password: ADMIN_PW });
  if (ae) { console.error('admin sign-in:', ae.message); process.exit(2); }

  const ID = 'zzm4' + Date.now().toString(36);
  const SHOW = ID + 'sh';
  const manifest = { itemIds: [ID], idempotencyKeys: [ID + ':res'] };
  console.log('\nElement 10 — M4 realtime cutover (' + ID + ')\n');

  // Session B — the M4 client in a browser (reads inventory from rows; realtime patches it)
  const browser = await puppeteer.launch({ headless: true, args: ['--no-sandbox', '--disable-setuid-sandbox'] });
  try {
    const page = await browser.newPage();
    await page.goto(APP, { waitUntil: 'networkidle2', timeout: 30000 });
    await page.type('#auEmail', MEMBER);
    await page.type('#auPass', MEMBER_PW);
    await page.evaluate(() => { const b = [...document.querySelectorAll('button')].find(x => /sign in/i.test(x.textContent)); if (b) b.click(); });
    await page.waitForFunction(() => typeof S !== 'undefined' && Array.isArray(S.inventory) && S.inventory.length > 0, { timeout: 25000 });
    await sleep(2500);

    // read helper: the in-memory item as session B sees it (no reload)
    const bItem = async () => page.evaluate(id => { const i = (S.inventory || []).find(x => x.id === id); return i ? { qty: i.qty, reserved: (i.reservations || []).reduce((s, r) => s + (+r.qty || 0), 0), name: i.name } : null; }, ID);
    const bCount = async () => page.evaluate(() => S.inventory.length);
    const waitB = async (pred, ms = 8000) => { const t0 = Date.now(); while (Date.now() - t0 < ms) { if (pred(await bItem())) return true; await sleep(400); } return false; };

    const initCount = await bCount();
    T('session B loaded inventory from rows (e10_inv_list, >0 items)', initCount >= 1, initCount);
    T('session B does not yet have the test item', (await bItem()) === null);

    // ── ADD (session A) → realtime INSERT on e10_inventory_items → B sees it, no reload ──
    const add = await rpc(A, 'e10_inv_add_item', { p_item: { id: ID, name: 'ZZ m4 realtime', qty: 4, cost: 2, cat: 'Box', boxesPerCase: 1, reservations: [], addedAt: Date.now() }, p_idempotency_key: ID + ':add' });
    T('A: add ok', add && add.ok === true, add);
    T('B: sees the added item via realtime (no reload)', await waitB(i => i && i.qty === 4), await bItem());

    // ── EDIT qty (session A) → realtime UPDATE → B qty patches ──
    await rpc(A, 'e10_inv_edit_item', { p_id: ID, p_patch: { qty: 9 }, p_remove_keys: [], p_idempotency_key: ID + ':edit' });
    T('B: sees the qty edit via realtime (4→9)', await waitB(i => i && i.qty === 9), await bItem());

    // ── RESERVE (session A) → realtime on e10_inventory_reservations → B item.reservations patches ──
    await rpc(A, 'e10_inv_reserve', { p_id: ID, p_show_ref: SHOW, p_show_label: 'ZZ Show', p_qty: 3, p_idempotency_key: ID + ':res' });
    T('B: sees the reservation via reservations realtime (reserved=3)', await waitB(i => i && i.reserved === 3), await bItem());

    // ── out-of-order + duplicate events converge (re-fetch-latest): fire stale/dup manual events ──
    const conv = await page.evaluate(async id => {
      // duplicate + out-of-order-simulating synthetic events for the same id; handler re-fetches latest
      _invRealtimeEvent({ eventType: 'UPDATE', table: 'e10_inventory_items', new: { id } });
      _invRealtimeEvent({ eventType: 'INSERT', table: 'e10_inventory_items', new: { id } });
      _invRealtimeEvent({ eventType: 'UPDATE', table: 'e10_inventory_reservations', new: { item_id: id } });
      await new Promise(r => setTimeout(r, 1500));
      const hits = (S.inventory || []).filter(x => x.id === id);
      return { copies: hits.length, qty: hits[0] && hits[0].qty };
    }, ID);
    T('duplicate/out-of-order events do not duplicate the array entry', conv.copies === 1, conv.copies);
    T('array converges to latest committed state (qty 9)', conv.qty === 9, conv.qty);

    // ── DELETE (session A) → realtime DELETE on e10_inventory_items → B drops it ──
    await rpc(A, 'e10_inv_delete_item', { p_id: ID, p_idempotency_key: ID + ':del' });
    T('B: sees the delete via realtime (item removed)', await waitB(i => i === null), await bItem());
    T('B: item count back to initial', (await bCount()) === initCount, { init: initCount, now: await bCount() });
  } finally {
    await browser.close();
    let res, cerr;
    try { res = await serviceCleanup(manifest); } catch (e) { cerr = e; }
    T('teardown: service cleanup ran', !cerr, cerr && cerr.message);
    if (res) T('teardown: 0 residue', res.clean, res.residue);
  }

  console.log('\n  ' + pass + ' pass · ' + fail + ' fail\n');
  process.exit(fail ? 1 : 0);
})().catch(e => { console.error(e); process.exit(3); });
