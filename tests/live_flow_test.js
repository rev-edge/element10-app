// Element 10 — P1B full operator flow (local file:// P1B client → live Supabase). Drives the FORBIDDEN-LIST
// actions (showStartLive, liveStart, the live-board product PICKER select → prodAdd, consume, reverse) through
// REAL DOM controls — never page.evaluate of those functions — proving the surface-specific picker works in
// the live board where the collision used to fail (Trent's step 4). Fixtures (item add, reserve, show detail
// render) use non-forbidden helpers. DB assertions verify the reserved drawdown + restoration and exactly one
// consumption/reversal movement. Service-role teardown from finally.
//   Run: (source .env.local) node tests/live_flow_test.js
const puppeteer = require('puppeteer');
const { createClient } = require('@supabase/supabase-js');
const { serviceCleanup } = require('./cleanup');
const URL = process.env.E10_URL || 'https://ddhkkumiyidorzmajwde.supabase.co';
const ANON = process.env.E10_ANON || 'sb_publishable_wRoaFNiqpZJaEJkQvLpnUw_7bpcXllv';
const MEMBER = process.env.E10_MEMBER_EMAIL, MEMBER_PW = process.env.E10_MEMBER_PW;
if (!MEMBER || !MEMBER_PW) { console.error('Set E10_MEMBER_EMAIL / E10_MEMBER_PW.'); process.exit(2); }

let pass = 0, fail = 0;
const T = (n, ok, d) => ok ? (pass++, console.log('  PASS ' + n)) : (fail++, console.log('  FAIL ' + n + (d !== undefined ? '  → ' + JSON.stringify(d) : '')));
const sleep = ms => new Promise(r => setTimeout(r, ms));

(async () => {
  const sb = createClient(URL, ANON, { auth: { persistSession: false, autoRefreshToken: false } });
  const { error: se } = await sb.auth.signInWithPassword({ email: MEMBER, password: MEMBER_PW });
  if (se) { console.error('sign-in failed:', se.message); process.exit(2); }
  const meUid = (await sb.auth.getUser()).data.user.id;
  const uws = 'user:' + meUid;
  const PFX = 'zzlf' + Date.now().toString(36), ID = PFX + 'it';
  const t0 = new Date(Date.now() - 3000).toISOString();
  const manifest = { itemIds: [ID], sessionIds: [], showIds: [], workspaceId: uws };
  console.log('\nElement 10 — P1B live operator flow (' + PFX + ')\n');

  const onhand = async () => { const { data } = await sb.from('e10_inventory_items').select('qty').eq('id', ID).maybeSingle(); return data ? +data.qty : null; };
  const reserved = async (showId) => ((await sb.from('e10_inventory_reservations').select('qty').eq('item_id', ID).eq('show_ref', showId).eq('status', 'active')).data || []).reduce((s, r) => s + (+r.qty || 0), 0);
  const moves = async (type) => (await sb.from('e10_inventory_movements').select('id,reverses_movement_id').eq('item_id', ID).eq('movement_type', type)).data || [];

  const browser = await puppeteer.launch({ headless: true, args: ['--no-sandbox', '--disable-setuid-sandbox'] });
  let SHOWID = null, sessId = null;
  try {
    const page = await browser.newPage();
    page.on('dialog', d => d.accept());   // prodRemove confirm()
    await page.goto('file://' + require('path').resolve(__dirname, '..', 'index.html'), { waitUntil: 'networkidle2', timeout: 30000 });
    await page.type('#auEmail', MEMBER);
    await page.type('#auPass', MEMBER_PW);
    await page.evaluate(() => { const b = [...document.querySelectorAll('button')].find(x => /sign in/i.test(x.textContent)); if (b) b.click(); });
    await page.waitForFunction(() => !document.querySelector('#auEmail') && typeof window.invRpc === 'function' && typeof window.saveShow === 'function', { timeout: 25000 });
    await sleep(3500);

    // ── FIXTURE (non-forbidden): item via invRpc add, show via newShow/saveShow, reserve via invRpc reserve ──
    const SHOWNAME = 'ZZ ' + PFX + ' show';
    SHOWID = await page.evaluate(async (id, nm) => {
      await window.invRpc('e10_inv_add_item', { p_item: { id, name: 'ZZ live item', qty: 5, cost: 3, cat: 'Box', boxesPerCase: 1, reservations: [], addedAt: Date.now() }, p_idempotency_key: id + ':add' });
      window.newShow(); const n = document.querySelector('#mname'); if (n) n.value = nm; window.saveShow();
      return null;
    }, ID, SHOWNAME);
    for (let i = 0; i < 15 && !SHOWID; i++) { await sleep(1000); const { data: w } = await sb.from('e10_workspace').select('data').eq('id', uws).maybeSingle(); const sh = (w && w.data && w.data.shows) || {}; for (const k of Object.keys(sh)) { const hit = (sh[k] || []).find(s => s && s.name === SHOWNAME); if (hit) SHOWID = hit.id; } }
    T('fixture: show created', !!SHOWID, SHOWID);
    if (!SHOWID) throw new Error('no show');
    manifest.showIds = [SHOWID];
    await page.evaluate(async (id, showId) => { await window.invRpc('e10_inv_reserve', { p_id: id, p_show_ref: showId, p_show_label: 'ZZ Show', p_qty: 2, p_idempotency_key: id + ':res' }); }, ID, SHOWID);
    T('fixture: reserved 2 to the show', (await reserved(SHOWID)) === 2, await reserved(SHOWID));
    T('fixture: on-hand 5', (await onhand()) === 5, await onhand());

    // ── UI: open the show detail, CLICK "Start Live Break" (showStartLive) ──
    await page.evaluate(id => window.showDetail(id), SHOWID);   // render only (not a forbidden action)
    await sleep(800);
    const started = await page.evaluate(() => { const b = [...document.querySelectorAll('button')].find(x => /start live break/i.test(x.textContent)); if (b) { b.click(); return true; } return false; });
    T('UI: clicked Start Live Break', started === true);
    await sleep(1500);
    // ── UI: on the live pre-flight, CLICK liveStart ──
    const wentLive = await page.evaluate(() => { const b = [...document.querySelectorAll('button')].find(x => x.getAttribute('onclick') === 'liveStart()'); if (b) { b.click(); return true; } return false; });
    T('UI: clicked go-live (liveStart)', wentLive === true);
    await sleep(2500);
    const { data: sess } = await sb.from('e10_break_sessions').select('id,source_show_ref').eq('streamer_uid', meUid).gt('created_at', t0).order('created_at', { ascending: false }).limit(1);
    sessId = sess && sess[0] && sess[0].id; if (sessId) manifest.sessionIds = [sessId];
    T('session created carries source_show_ref = show', sess && sess[0] && sess[0].source_show_ref === SHOWID, sess && sess[0]);

    // ── UI: TYPE into the live-board picker, wait for results, SELECT (→ prodAdd → consume) ──
    await page.waitForSelector('#epi_prodPick_live', { timeout: 8000 });
    const dupInputs = await page.evaluate(() => document.querySelectorAll('#epi_prodPick_live').length);
    T('exactly one live-board picker input (no collision)', dupInputs === 1, dupInputs);
    await page.type('#epi_prodPick_live', 'ZZ live item');
    await page.waitForFunction(() => { const r = document.querySelector('#epr_prodPick_live'); return r && r.children.length > 0; }, { timeout: 8000 });
    await page.evaluate(() => { const r = document.querySelector('#epr_prodPick_live'); const hit = [...r.querySelectorAll('*')].find(e => /ZZ live item/.test(e.textContent) && e.getAttribute('onclick')); (hit || r.firstElementChild).click(); });
    await sleep(2500);
    T('consume: on-hand 5 → 4', (await onhand()) === 4, await onhand());
    T('consume: reservation 2 → 1 (drew the show reservation)', (await reserved(SHOWID)) === 1, await reserved(SHOWID));
    const cons = await moves('break_consumption');
    T('consume: exactly one consumption movement', cons.length === 1, cons.length);

    // ── UI: REMOVE the product (✕ → prodRemove → breakConsume reversal) ──
    const removed = await page.evaluate(() => { const b = [...document.querySelectorAll('button')].find(x => (x.getAttribute('onclick') || '').startsWith('prodRemove(')); if (b) { b.click(); return true; } return false; });
    T('UI: clicked remove product (reverse)', removed === true);
    await sleep(2500);
    T('reverse: on-hand 4 → 5 (restored)', (await onhand()) === 5, await onhand());
    T('reverse: reservation 1 → 2 (reconstructed)', (await reserved(SHOWID)) === 2, await reserved(SHOWID));
    const rev = await moves('break_reversal');
    T('reverse: exactly one reversal movement', rev.length === 1, rev.length);
    T('reverse: references the original consumption', rev.length === 1 && cons.length === 1 && rev[0].reverses_movement_id === cons[0].id, { rev: rev[0], cons: cons[0] });
  } finally {
    await browser.close();
    if (!manifest.sessionIds.length) { const { data } = await sb.from('e10_break_sessions').select('id').eq('streamer_uid', meUid).gt('created_at', t0); manifest.sessionIds = (data || []).map(x => x.id); }
    let res, cerr;
    try { res = await serviceCleanup(manifest); } catch (e) { cerr = e; }
    T('teardown: service cleanup ran', !cerr, cerr && cerr.message);
    if (res) T('teardown: 0 residue', res.clean, res.residue);
  }

  console.log('\n  ' + pass + ' pass · ' + fail + ' fail\n');
  process.exit(fail ? 1 : 0);
})().catch(e => { console.error(e); process.exit(3); });
